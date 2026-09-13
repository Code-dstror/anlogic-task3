"""Tests for the file-backed mock frame source."""

from __future__ import annotations

import os
from pathlib import Path
from threading import Event, Thread
from tempfile import TemporaryDirectory
import unittest

from linux.task3_pipeline import (
    ConfigurationError,
    FrameEventKind,
    MockFileFrameSource,
    SourceError,
    SourceHealth,
)


class MockFileFrameSourceTests(unittest.TestCase):
    @staticmethod
    def _write_fixture(directory: Path, name: str, payload: bytes) -> Path:
        path = directory / name
        path.write_bytes(payload)
        return path

    def _assert_fd_closed(self, descriptor: int) -> None:
        with self.assertRaises(OSError):
            os.fstat(descriptor)

    def test_constructor_requires_exactly_one_input_mode(self) -> None:
        with self.assertRaises(ConfigurationError):
            MockFileFrameSource()
        with TemporaryDirectory() as temporary_directory, self.assertRaises(
            ConfigurationError
        ):
            MockFileFrameSource([], directory=temporary_directory)

    def test_empty_explicit_file_list_is_immediately_exhausted(self) -> None:
        source = MockFileFrameSource([])
        source.start()

        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        self.assertEqual(source.health(), SourceHealth.STOPPED)

    def test_constructor_copies_explicit_file_list(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            first = self._write_fixture(directory, "first.jpg", b"first")
            second = self._write_fixture(directory, "second.jpg", b"second")
            configured_files = [first]
            source = MockFileFrameSource(configured_files)
            configured_files.append(second)
            source.start()

            event = source.next_frame(Event())
            self.assertEqual(event.frame.payload if event.frame else None, b"first")
            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

    def test_single_file_publishes_bare_encoded_frame(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            fixture = self._write_fixture(
                Path(temporary_directory), "one.jpg", b"\xff\xd8mock\xff\xd9"
            )
            source = MockFileFrameSource([fixture])
            source.start()

            event = source.next_frame(Event())

            self.assertEqual(event.kind, FrameEventKind.FRAME)
            self.assertIsNotNone(event.frame)
            frame = event.frame
            assert frame is not None
            self.assertEqual(frame.payload, b"\xff\xd8mock\xff\xd9")
            self.assertIsInstance(frame.payload, bytes)
            self.assertEqual(frame.metadata.payload_length, len(frame.payload))
            self.assertEqual(frame.metadata.ingest_id, 0)
            self.assertEqual(frame.metadata.source_name, "mock_file")
            self.assertIsNone(frame.metadata.wire_sequence)
            self.assertIsNone(frame.metadata.source_timestamp)
            self.assertIsNone(frame.metadata.protocol_version)
            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

    def test_directory_order_is_deterministic_and_case_insensitive(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            self._write_fixture(directory, "z.JPG", b"z")
            self._write_fixture(directory, "A.jPeG", b"a")
            self._write_fixture(directory, "middle.jpg", b"m")

            source = MockFileFrameSource(directory=directory)
            source.start()
            payloads = [source.next_frame(Event()).frame.payload for _ in range(3)]

            self.assertEqual(payloads, [b"a", b"m", b"z"])
            self.assertEqual(
                [source.next_frame(Event()).kind], [FrameEventKind.END_OF_STREAM]
            )

    def test_explicit_file_list_retains_its_order_and_increments_ids(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            second = self._write_fixture(directory, "second.jpeg", b"second")
            first = self._write_fixture(directory, "first.jpg", b"first")
            source = MockFileFrameSource([second, first])
            source.start()

            frames = [source.next_frame(Event()).frame for _ in range(2)]

            self.assertEqual([frame.payload for frame in frames if frame], [b"second", b"first"])
            self.assertEqual(
                [frame.metadata.ingest_id for frame in frames if frame], [0, 1]
            )

    def test_directory_ignores_non_jpeg_entries(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            self._write_fixture(directory, "accepted.jpg", b"accepted")
            self._write_fixture(directory, "ignored.png", b"png")
            (directory / "nested.not_jpeg").mkdir()

            source = MockFileFrameSource(directory=directory)
            source.start()
            event = source.next_frame(Event())

            self.assertEqual(event.kind, FrameEventKind.FRAME)
            self.assertEqual(event.frame.payload if event.frame else None, b"accepted")
            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

    def test_empty_directory_is_immediately_exhausted(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            source = MockFileFrameSource(directory=temporary_directory)
            source.start()

            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
            self.assertEqual(source.health(), SourceHealth.STOPPED)

    def test_missing_file_raises_source_error_with_cause(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            missing = Path(temporary_directory) / "missing.jpg"
            source = MockFileFrameSource([missing])

            with self.assertRaises(SourceError) as raised:
                source.start()

            self.assertEqual(raised.exception.code, "file_discovery_failed")
            self.assertIsInstance(raised.exception.cause, FileNotFoundError)
            self.assertIsInstance(raised.exception.__cause__, FileNotFoundError)

    def test_running_start_is_rejected_without_resetting_position_or_id(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            first = self._write_fixture(directory, "first.jpg", b"first")
            second = self._write_fixture(directory, "second.jpg", b"second")
            source = MockFileFrameSource([first, second])
            source.start()
            first_event = source.next_frame(Event())

            with self.assertRaises(SourceError) as raised:
                source.start()

            self.assertEqual(raised.exception.code, "source_already_started")
            self.assertEqual(first_event.frame.metadata.ingest_id if first_event.frame else None, 0)
            second_event = source.next_frame(Event())
            self.assertEqual(second_event.frame.payload if second_event.frame else None, b"second")
            self.assertEqual(
                second_event.frame.metadata.ingest_id if second_event.frame else None, 1
            )

    def test_exhausted_pass_restarts_without_resetting_ingest_id(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            fixture = self._write_fixture(Path(temporary_directory), "one.jpg", b"one")
            source = MockFileFrameSource([fixture])
            source.start()
            first = source.next_frame(Event()).frame
            source.next_frame(Event())

            source.start()
            second = source.next_frame(Event()).frame

            self.assertEqual(first.metadata.ingest_id if first else None, 0)
            self.assertEqual(second.metadata.ingest_id if second else None, 1)

    def test_stopped_pass_restarts_without_resetting_ingest_id(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            fixture = self._write_fixture(Path(temporary_directory), "one.jpg", b"one")
            source = MockFileFrameSource([fixture])
            source.start()
            first = source.next_frame(Event()).frame
            source.stop()

            source.start()
            second = source.next_frame(Event()).frame

            self.assertEqual(first.metadata.ingest_id if first else None, 0)
            self.assertEqual(second.metadata.ingest_id if second else None, 1)

    def test_jpeg_symbolic_links_are_rejected_in_both_modes(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            target = self._write_fixture(directory, "target.jpg", b"target")
            link = directory / "linked.jpeg"
            link.symlink_to(target)

            for source in (
                MockFileFrameSource([link]),
                MockFileFrameSource(directory=directory),
            ):
                with self.subTest(source=source), self.assertRaises(SourceError) as raised:
                    source.start()
                self.assertEqual(raised.exception.code, "not_regular_file")

    def test_jpeg_named_directory_is_rejected_in_both_modes(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            jpeg_directory = directory / "not_a_file.jpg"
            jpeg_directory.mkdir()

            for source in (
                MockFileFrameSource([jpeg_directory]),
                MockFileFrameSource(directory=directory),
            ):
                with self.subTest(source=source), self.assertRaises(SourceError) as raised:
                    source.start()
                self.assertEqual(raised.exception.code, "not_regular_file")

    def test_explicit_non_jpeg_file_is_rejected(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            non_jpeg = self._write_fixture(Path(temporary_directory), "input.png", b"png")
            with self.assertRaises(ConfigurationError) as raised:
                MockFileFrameSource([non_jpeg])
            self.assertEqual(raised.exception.code, "non_jpeg_input")

    def test_fifo_replacement_does_not_block_and_releases_directory_fd(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            candidate = self._write_fixture(directory, "candidate.jpg", b"original")
            source = MockFileFrameSource(directory=directory)
            source.start()
            directory_fd = source._directory_fd
            assert directory_fd is not None
            candidate.unlink()
            os.mkfifo(candidate)
            completed = Event()
            outcomes: list[BaseException] = []

            def read_frame() -> None:
                try:
                    source.next_frame(Event())
                except BaseException as error:
                    outcomes.append(error)
                finally:
                    completed.set()

            reader = Thread(target=read_frame, daemon=True)
            reader.start()
            completed_without_fifo_writer = completed.wait(timeout=1)
            if not completed_without_fifo_writer:
                # Release an incorrectly blocking O_RDONLY implementation so
                # the test can fail without leaving a blocked worker behind.
                for _ in range(20):
                    try:
                        writer_fd = os.open(candidate, os.O_WRONLY | os.O_NONBLOCK)
                    except OSError:
                        if completed.wait(timeout=0.01):
                            break
                    else:
                        os.close(writer_fd)
                        break
                completed.wait(timeout=1)
            reader.join(timeout=1)

            self.assertTrue(
                completed_without_fifo_writer,
                "next_frame blocked while opening a FIFO replacement",
            )
            self.assertFalse(reader.is_alive(), "FIFO reader thread did not finish")
            self.assertEqual(len(outcomes), 1)
            self.assertIsInstance(outcomes[0], SourceError)
            self.assertEqual(getattr(outcomes[0], "code", None), "not_regular_file")
            self.assertIsNone(source._directory_fd)
            self._assert_fd_closed(directory_fd)

    def test_directory_pass_remains_bound_after_path_replacement(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            configured = root / "configured"
            replacement = root / "replacement"
            configured.mkdir()
            replacement.mkdir()
            self._write_fixture(configured, "frame.jpg", b"original-directory")
            self._write_fixture(replacement, "frame.jpg", b"replacement-directory")
            source = MockFileFrameSource(directory=configured)
            source.start()

            moved = root / "configured-original"
            configured.rename(moved)
            configured.symlink_to(replacement, target_is_directory=True)
            event = source.next_frame(Event())

            self.assertEqual(event.kind, FrameEventKind.FRAME)
            self.assertEqual(
                event.frame.payload if event.frame else None, b"original-directory"
            )

    def test_directory_fd_is_closed_on_stop_exhaustion_close_and_repass(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            self._write_fixture(directory, "frame.jpg", b"frame")
            source = MockFileFrameSource(directory=directory)

            source.start()
            stopped_fd = source._directory_fd
            assert stopped_fd is not None
            source.stop()
            self.assertIsNone(source._directory_fd)
            self._assert_fd_closed(stopped_fd)

            source.start()
            exhausted_fd = source._directory_fd
            assert exhausted_fd is not None
            source.next_frame(Event())
            source.next_frame(Event())
            self.assertIsNone(source._directory_fd)
            self._assert_fd_closed(exhausted_fd)

            source.start()
            closed_fd = source._directory_fd
            assert closed_fd is not None
            source.close()
            self.assertIsNone(source._directory_fd)
            self._assert_fd_closed(closed_fd)

    def test_stop_close_and_close_idempotence(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            fixture = self._write_fixture(Path(temporary_directory), "one.jpg", b"one")
            source = MockFileFrameSource([fixture])
            source.start()
            stop_event = Event()
            stop_event.set()
            self.assertEqual(source.next_frame(stop_event).kind, FrameEventKind.END_OF_STREAM)
            self.assertEqual(source.health(), SourceHealth.STOPPED)

            source.start()
            source.stop()
            self.assertEqual(source.health(), SourceHealth.STOPPED)
            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

            source.start()
            source.close()
            source.close()
            self.assertEqual(source.health(), SourceHealth.STOPPED)
            self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
            with self.assertRaises(SourceError):
                source.start()

    def test_reading_does_not_modify_input_file(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            fixture = self._write_fixture(Path(temporary_directory), "one.jpg", b"unchanged")
            original_contents = fixture.read_bytes()
            original_stat = fixture.stat()
            source = MockFileFrameSource([fixture])
            source.start()
            source.next_frame(Event())

            self.assertEqual(fixture.read_bytes(), original_contents)
            current_stat = fixture.stat()
            self.assertEqual(current_stat.st_size, original_stat.st_size)
            self.assertEqual(current_stat.st_mtime_ns, original_stat.st_mtime_ns)
