"""A deterministic frame-source wrapper for one payload-tail corruption."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import replace
from threading import Event
from typing import Any, Mapping

from .errors import ConfigurationError
from .interfaces import FrameSource
from .models import EncodedFrame, FrameEvent, FrameEventKind, SourceHealth


def _copy_metadata_value(value: Any) -> Any:
    """Recursively copy metadata values without deepcopying mapping proxies."""

    if isinstance(value, Mapping):
        return {
            _copy_metadata_value(key): _copy_metadata_value(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [_copy_metadata_value(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_copy_metadata_value(item) for item in value)
    if isinstance(value, set):
        return {_copy_metadata_value(item) for item in value}
    return deepcopy(value)


class MockCorruptFrameSource(FrameSource):
    """Inject one deterministic payload-tail truncation into a frame stream.

    ``target_frame_index`` is zero-based over only successfully produced
    ``FRAME`` events.  The wrapped source owns input and lifecycle behavior;
    EOF, non-frame events, and exceptions pass through unchanged.  The target
    frame is replaced by an independent ``EncodedFrame`` whose payload has
    ``tail_bytes_to_drop`` bytes removed.  Its metadata is otherwise retained,
    except for ``payload_length``, which must match the replacement payload.
    """

    def __init__(
        self,
        source: FrameSource,
        *,
        target_frame_index: int,
        tail_bytes_to_drop: int,
    ) -> None:
        if (
            isinstance(target_frame_index, bool)
            or not isinstance(target_frame_index, int)
            or target_frame_index < 0
        ):
            raise ConfigurationError(
                "target_frame_index must be a non-boolean non-negative integer",
                stage="mock_corrupt_frame_source",
                code="invalid_target_frame_index",
            )
        if (
            isinstance(tail_bytes_to_drop, bool)
            or not isinstance(tail_bytes_to_drop, int)
            or tail_bytes_to_drop <= 0
        ):
            raise ConfigurationError(
                "tail_bytes_to_drop must be a non-boolean positive integer",
                stage="mock_corrupt_frame_source",
                code="invalid_tail_bytes_to_drop",
            )
        self._source = source
        self._target_frame_index = target_frame_index
        self._tail_bytes_to_drop = tail_bytes_to_drop
        self._successful_frame_count = 0
        self._injected = False

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        """Delegate startup and source-local configuration to the wrapped source."""

        result = self._source.start(config)
        self._successful_frame_count = 0
        self._injected = False
        return result

    def next_frame(self, stop_event: Event) -> FrameEvent:
        """Return the wrapped event, replacing only the configured frame once."""

        event = self._source.next_frame(stop_event)
        if event.kind is not FrameEventKind.FRAME:
            return event

        frame = event.frame
        assert frame is not None
        frame_index = self._successful_frame_count
        self._successful_frame_count += 1
        if self._injected or frame_index != self._target_frame_index:
            return event

        self._injected = True
        payload = frame.payload[: -self._tail_bytes_to_drop]
        corrupted_metadata = replace(
            frame.metadata,
            payload_length=len(payload),
            integrity=_copy_metadata_value(frame.metadata.integrity),
            extensions=_copy_metadata_value(frame.metadata.extensions),
        )
        corrupted_frame = EncodedFrame(
            metadata=corrupted_metadata,
            payload=payload,
            acquired_monotonic_ns=frame.acquired_monotonic_ns,
            payload_capacity=frame.payload_capacity,
        )
        return FrameEvent(FrameEventKind.FRAME, corrupted_frame, detail=event.detail)

    def stop(self) -> None:
        """Delegate stopping to the wrapped source."""

        self._source.stop()

    def health(self) -> SourceHealth:
        """Return the wrapped source health unchanged."""

        return self._source.health()
