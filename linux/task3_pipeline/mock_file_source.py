"""A deterministic, bare-JPEG frame source for offline pipeline tests."""

from __future__ import annotations

import os
from pathlib import Path
import stat
from threading import Event
from time import monotonic_ns
from typing import Any, Iterable, Mapping

from .errors import ConfigurationError, SourceError
from .interfaces import FrameSource
from .models import EncodedFrame, FrameEvent, FrameEventKind, FrameMetadata, SourceHealth


_JPEG_SUFFIXES = {".jpg", ".jpeg"}


class MockFileFrameSource(FrameSource):
    """Publish bare JPEG files once, without interpreting their payloads.

    Supply either ``files`` (whose order is preserved) or ``directory``.
    Directory entries are sorted by a case-insensitive filename key.  Both
    modes reject JPEG-named symbolic links and non-regular files; directory
    mode otherwise ignores non-JPEG entries.  Discovery is non-recursive.
    Exhaustion, stop requests, and a closed source produce ``END_OF_STREAM``
    events.
    """

    def __init__(
        self,
        files: Iterable[str | os.PathLike[str]] | str | os.PathLike[str] | None = None,
        *,
        directory: str | os.PathLike[str] | None = None,
    ) -> None:
        if (files is None) == (directory is None):
            raise ConfigurationError(
                "provide exactly one of files or directory",
                stage="mock_file_source",
                code="invalid_input_mode",
            )
        if isinstance(files, (str, os.PathLike)):
            self._configured_files = (Path(files),)
        elif files is not None:
            self._configured_files = tuple(Path(path) for path in files)
        else:
            self._configured_files = None
        if self._configured_files is not None:
            for path in self._configured_files:
                if path.suffix.casefold() not in _JPEG_SUFFIXES:
                    raise ConfigurationError(
                        f"mock file input is not a JPEG path: {path}",
                        stage="mock_file_source",
                        code="non_jpeg_input",
                    )
        self._directory = Path(directory) if directory is not None else None
        self._paths: tuple[Path | str, ...] = ()
        self._directory_fd: int | None = None
        self._next_index = 0
        self._next_ingest_id = 0
        self._closed = False
        self._started = False
        self._exhausted = False
        self._health = SourceHealth.STOPPED

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Discover configured files and reset this source for one pass."""

        if self._closed:
            raise SourceError(
                "cannot start a closed mock file source",
                stage="mock_file_source",
                code="source_closed",
            )
        if self._started and not self._exhausted:
            raise SourceError(
                "mock file source is already running",
                stage="mock_file_source",
                code="source_already_started",
            )
        if config:
            raise ConfigurationError(
                "MockFileFrameSource does not accept runtime configuration",
                stage="mock_file_source",
                code="unsupported_config",
            )

        self._close_directory_fd()
        if self._directory is None:
            self._paths = self._discover_explicit_paths()
        else:
            self._directory_fd, self._paths = self._open_directory_pass(self._directory)
        self._next_index = 0
        self._started = True
        self._exhausted = False
        self._health = SourceHealth.READY

    def next_frame(self, stop_event: Event) -> FrameEvent:
        """Read and publish one configured file, or return ``END_OF_STREAM``."""

        if not self._started or self._closed or self._exhausted:
            return FrameEvent(FrameEventKind.END_OF_STREAM)
        if stop_event.is_set():
            self.stop()
            return FrameEvent(FrameEventKind.END_OF_STREAM, detail="stop requested")
        if self._next_index >= len(self._paths):
            self._finish_pass()
            return FrameEvent(FrameEventKind.END_OF_STREAM)

        path = self._paths[self._next_index]
        try:
            payload = self._read_regular_file(path)
            now = monotonic_ns()
            metadata = FrameMetadata(
                ingest_id=self._next_ingest_id,
                source_name="mock_file",
                payload_length=len(payload),
                received_monotonic_ns=now,
                wire_sequence=None,
                encoding="jpeg",
            )
            encoded_frame = EncodedFrame(
                metadata=metadata, payload=payload, acquired_monotonic_ns=now
            )
        except Exception:
            self._fail_pass()
            raise
        self._next_index += 1
        self._next_ingest_id += 1
        return FrameEvent(
            FrameEventKind.FRAME,
            encoded_frame,
        )

    def stop(self) -> None:
        """Stop this pass; ``start()`` may begin a new pass unless closed."""

        self._started = False
        self._exhausted = True
        self._health = SourceHealth.STOPPED
        self._close_directory_fd()

    def close(self) -> None:
        """Permanently close the source.  Calling this method repeatedly is safe."""

        if self._closed:
            return
        self.stop()
        self._closed = True

    def health(self) -> SourceHealth:
        return self._health

    def _discover_explicit_paths(self) -> tuple[Path, ...]:
        paths: list[Path] = []
        for path in self._configured_files:
            self._require_regular_file(path)
            paths.append(path)
        return tuple(paths)

    def _open_directory_pass(self, directory: Path) -> tuple[int, tuple[str, ...]]:
        descriptor: int | None = None
        try:
            descriptor = os.open(
                directory,
                os.O_RDONLY | os.O_NONBLOCK | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            )
            if not stat.S_ISDIR(os.fstat(descriptor).st_mode):
                raise SourceError(
                    f"mock JPEG input is not a directory: {directory}",
                    stage="mock_file_source",
                    code="not_directory",
                )
            entries = os.listdir(descriptor)
            jpeg_names: list[str] = []
            for name in entries:
                if Path(name).suffix.casefold() not in _JPEG_SUFFIXES:
                    continue
                self._require_regular_file_at(descriptor, name)
                jpeg_names.append(name)
            return descriptor, tuple(sorted(jpeg_names, key=lambda name: (name.casefold(), name)))
        except SourceError:
            if descriptor is not None:
                os.close(descriptor)
            raise
        except OSError as error:
            if descriptor is not None:
                os.close(descriptor)
            raise SourceError(
                f"failed to list mock JPEG directory: {directory}",
                stage="mock_file_source",
                code="directory_discovery_failed",
                cause=error,
            ) from error

    def _require_regular_file(self, path: Path) -> None:
        try:
            file_status = path.stat(follow_symlinks=False)
        except OSError as error:
            raise SourceError(
                f"failed to inspect mock JPEG file: {path}",
                stage="mock_file_source",
                code="file_discovery_failed",
                cause=error,
            ) from error
        if not stat.S_ISREG(file_status.st_mode):
            raise SourceError(
                f"mock JPEG input is not a regular file: {path}",
                stage="mock_file_source",
                code="not_regular_file",
            )

    @staticmethod
    def _require_regular_file_at(directory_fd: int, name: str) -> None:
        try:
            file_status = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except OSError as error:
            raise SourceError(
                f"failed to inspect mock JPEG file: {name}",
                stage="mock_file_source",
                code="file_discovery_failed",
                cause=error,
            ) from error
        if not stat.S_ISREG(file_status.st_mode):
            raise SourceError(
                f"mock JPEG input is not a regular file: {name}",
                stage="mock_file_source",
                code="not_regular_file",
            )

    def _read_regular_file(self, path: Path | str) -> bytes:
        descriptor: int | None = None
        try:
            flags = os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW
            if self._directory_fd is None:
                descriptor = os.open(path, flags)
            else:
                descriptor = os.open(path, flags, dir_fd=self._directory_fd)
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SourceError(
                    f"mock JPEG input is not a regular file: {path}",
                    stage="mock_file_source",
                    code="not_regular_file",
                )
            source_file = os.fdopen(descriptor, "rb")
            descriptor = None
            with source_file:
                return source_file.read()
        except SourceError:
            raise
        except OSError as error:
            raise SourceError(
                f"failed to read mock JPEG file: {path}",
                stage="mock_file_source",
                code="file_read_failed",
                cause=error,
            ) from error
        finally:
            if descriptor is not None:
                os.close(descriptor)

    def _finish_pass(self) -> None:
        self._exhausted = True
        self._health = SourceHealth.STOPPED
        self._close_directory_fd()

    def _fail_pass(self) -> None:
        self._started = False
        self._exhausted = True
        self._health = SourceHealth.FAILED
        self._close_directory_fd()

    def _close_directory_fd(self) -> None:
        if self._directory_fd is not None:
            os.close(self._directory_fd)
            self._directory_fd = None
