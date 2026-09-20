"""Tests for deterministic payload-tail corruption at the FrameSource boundary."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
from threading import Event
from tempfile import TemporaryDirectory
from types import MappingProxyType
from typing import Any, Mapping
import unittest

from linux.task3_pipeline.errors import ConfigurationError, SourceError, ValidationError
from linux.task3_pipeline.interfaces import FrameSource
from linux.task3_pipeline.jpeg_payload_validator import JpegPayloadValidator
from linux.task3_pipeline.mock_corrupt_frame_source import MockCorruptFrameSource
from linux.task3_pipeline.mock_file_source import MockFileFrameSource
from linux.task3_pipeline.models import (
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    SourceHealth,
)

from tests._helpers import make_metadata


class ScriptedFrameSource(FrameSource):
    """Minimal source double that returns scripted events or raises scripted errors."""

    def __init__(self, outcomes: list[FrameEvent | BaseException]) -> None:
        self._outcomes = outcomes
        self.started_with: Mapping[str, Any] | None = None
        self.stopped = False

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        self.started_with = config

    def next_frame(self, stop_event: Event) -> FrameEvent:
        outcome = self._outcomes.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome

    def stop(self) -> None:
        self.stopped = True

    def health(self) -> SourceHealth:
        return SourceHealth.STOPPED if self.stopped else SourceHealth.READY


def make_frame(payload: bytes, **metadata_overrides: object) -> EncodedFrame:
    """Build a frame whose metadata can demonstrate preservation on copying."""

    metadata_values: dict[str, object] = {
        "payload_length": len(payload),
        "frame_id": "frame-7",
        "source_timestamp": 1234,
        "timestamp_domain": "source_ticks",
        "transport": "mock",
        "encoding": "jpeg",
        "declared_width": 2,
        "declared_height": 1,
        "integrity": {"crc": "unverified"},
        "protocol_version": 1,
        "extensions": {"test": "preserve"},
    }
    metadata_values.update(metadata_overrides)
    return EncodedFrame(
        metadata=make_metadata(**metadata_values),
        payload=payload,
        acquired_monotonic_ns=101,
        payload_capacity=len(payload) + 8,
    )


class MockCorruptFrameSourceTests(unittest.TestCase):
    @staticmethod
    def _events(*frames: EncodedFrame) -> list[FrameEvent | BaseException]:
        return [*(FrameEvent(FrameEventKind.FRAME, frame) for frame in frames), FrameEvent(FrameEventKind.END_OF_STREAM)]

    def test_non_target_frame_passes_through_unchanged(self) -> None:
        first = make_frame(b"first")
        target = make_frame(b"second", ingest_id=8)
        source = ScriptedFrameSource(self._events(first, target))
        wrapper = MockCorruptFrameSource(source, target_frame_index=1, tail_bytes_to_drop=2)

        event = wrapper.next_frame(Event())

        self.assertIs(event.frame, first)
        self.assertEqual(event.frame.payload if event.frame else None, b"first")

    def test_target_frame_truncates_only_requested_tail_and_preserves_metadata(self) -> None:
        original = make_frame(b"abcdef")
        wrapper = MockCorruptFrameSource(
            ScriptedFrameSource(self._events(original)),
            target_frame_index=0,
            tail_bytes_to_drop=2,
        )

        event = wrapper.next_frame(Event())

        assert event.frame is not None
        corrupted = event.frame
        self.assertEqual(corrupted.payload, b"abcd")
        self.assertIsNot(corrupted, original)
        self.assertIsNot(corrupted.metadata, original.metadata)
        self.assertEqual(
            corrupted.metadata,
            replace(original.metadata, payload_length=len(corrupted.payload)),
        )
        self.assertEqual(corrupted.acquired_monotonic_ns, original.acquired_monotonic_ns)
        self.assertEqual(corrupted.payload_capacity, original.payload_capacity)

    def test_original_frame_data_is_not_modified(self) -> None:
        original = make_frame(b"abcdef")
        original_payload = original.payload
        original_metadata = original.metadata
        wrapper = MockCorruptFrameSource(
            ScriptedFrameSource(self._events(original)),
            target_frame_index=0,
            tail_bytes_to_drop=3,
        )

        wrapper.next_frame(Event())

        self.assertEqual(original.payload, original_payload)
        self.assertEqual(original.metadata, original_metadata)
        self.assertEqual(original.metadata.payload_length, len(original_payload))

    def test_target_metadata_deep_copies_nested_integrity_and_extensions(self) -> None:
        original = make_frame(
            b"abcdef",
            integrity={"nested": MappingProxyType({"values": ["integrity"]})},
            extensions={"nested": MappingProxyType({"values": ["extension"]})},
        )
        wrapper = MockCorruptFrameSource(
            ScriptedFrameSource(self._events(original)),
            target_frame_index=0,
            tail_bytes_to_drop=2,
        )

        event = wrapper.next_frame(Event())

        assert event.frame is not None
        corrupted = event.frame
        self.assertEqual(
            corrupted.metadata,
            replace(original.metadata, payload_length=len(corrupted.payload)),
        )
        self.assertEqual(corrupted.metadata.payload_length, 4)
        corrupted.metadata.integrity["nested"]["values"].append("changed")
        corrupted.metadata.extensions["nested"]["values"].append("changed")
        self.assertEqual(original.metadata.integrity["nested"]["values"], ["integrity"])
        self.assertEqual(original.metadata.extensions["nested"]["values"], ["extension"])

    def test_fault_is_injected_once_then_later_frames_pass_through(self) -> None:
        frames = [make_frame(b"first"), make_frame(b"second"), make_frame(b"third")]
        wrapper = MockCorruptFrameSource(
            ScriptedFrameSource(self._events(*frames)),
            target_frame_index=1,
            tail_bytes_to_drop=2,
        )

        first = wrapper.next_frame(Event())
        corrupted = wrapper.next_frame(Event())
        third = wrapper.next_frame(Event())

        self.assertIs(first.frame, frames[0])
        self.assertEqual(corrupted.frame.payload if corrupted.frame else None, b"seco")
        self.assertIs(third.frame, frames[2])
        self.assertEqual(third.frame.payload if third.frame else None, b"third")

    def test_successful_restart_resets_frame_count_and_reinjects_once(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "frame.jpg"
            path.write_bytes(b"abcdef")
            wrapped = MockFileFrameSource([path])
            wrapper = MockCorruptFrameSource(
                wrapped, target_frame_index=0, tail_bytes_to_drop=2
            )

            wrapper.start()
            first_pass = wrapper.next_frame(Event())
            self.assertEqual(first_pass.frame.payload if first_pass.frame else None, b"abcd")
            self.assertEqual(wrapper.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

            wrapper.start()
            second_pass = wrapper.next_frame(Event())
            self.assertEqual(second_pass.frame.payload if second_pass.frame else None, b"abcd")
            self.assertEqual(wrapper.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)

    def test_failed_delegated_start_does_not_reset_pending_target_index(self) -> None:
        class FailingRestartSource(ScriptedFrameSource):
            fail_next_start = False

            def start(self, config: Mapping[str, Any] | None = None) -> None:
                if self.fail_next_start:
                    raise SourceError(
                        "scripted start failure",
                        stage="scripted",
                        code="scripted_start_failure",
                    )
                super().start(config)

        source = FailingRestartSource(self._events(make_frame(b"first"), make_frame(b"second")))
        wrapper = MockCorruptFrameSource(
            source, target_frame_index=1, tail_bytes_to_drop=2
        )
        wrapper.start()
        self.assertEqual(wrapper.next_frame(Event()).frame.payload, b"first")

        source.fail_next_start = True
        with self.assertRaises(SourceError):
            wrapper.start()
        event = wrapper.next_frame(Event())

        self.assertEqual(event.frame.payload if event.frame else None, b"seco")

    def test_dropping_at_least_the_payload_length_produces_empty_payload(self) -> None:
        for tail_bytes_to_drop in (4, 10):
            with self.subTest(tail_bytes_to_drop=tail_bytes_to_drop):
                wrapper = MockCorruptFrameSource(
                    ScriptedFrameSource(self._events(make_frame(b"data"))),
                    target_frame_index=0,
                    tail_bytes_to_drop=tail_bytes_to_drop,
                )

                event = wrapper.next_frame(Event())

                self.assertEqual(event.frame.payload if event.frame else None, b"")
                self.assertEqual(event.frame.metadata.payload_length if event.frame else None, 0)

    def test_eof_and_errors_pass_through_without_consuming_successful_frame_index(self) -> None:
        error = SourceError("scripted failure", stage="scripted", code="scripted_failure")
        frame = make_frame(b"abcdef")
        source = ScriptedFrameSource(
            [FrameEvent(FrameEventKind.NO_DATA), error, FrameEvent(FrameEventKind.END_OF_STREAM), FrameEvent(FrameEventKind.FRAME, frame)]
        )
        wrapper = MockCorruptFrameSource(source, target_frame_index=0, tail_bytes_to_drop=2)

        self.assertEqual(wrapper.next_frame(Event()).kind, FrameEventKind.NO_DATA)
        with self.assertRaises(SourceError) as raised:
            wrapper.next_frame(Event())
        self.assertIs(raised.exception, error)
        self.assertEqual(wrapper.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        event = wrapper.next_frame(Event())

        self.assertEqual(event.frame.payload if event.frame else None, b"abcd")

    def test_truncated_eoi_is_rejected_by_existing_payload_validator(self) -> None:
        original = make_frame(b"\xff\xd8valid\xff\xd9")
        wrapper = MockCorruptFrameSource(
            ScriptedFrameSource(self._events(original)),
            target_frame_index=0,
            tail_bytes_to_drop=2,
        )

        event = wrapper.next_frame(Event())

        assert event.frame is not None
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(64).validate(event.frame)
        self.assertEqual(raised.exception.code, "jpeg_payload_invalid_eoi")

    def test_invalid_configuration_uses_existing_configuration_errors(self) -> None:
        source = ScriptedFrameSource([])
        for target_frame_index in (-1, True, 0.0, "0"):
            with self.subTest(target_frame_index=target_frame_index), self.assertRaises(
                ConfigurationError
            ) as raised:
                MockCorruptFrameSource(
                    source,
                    target_frame_index=target_frame_index,  # type: ignore[arg-type]
                    tail_bytes_to_drop=1,
                )
            self.assertEqual(raised.exception.code, "invalid_target_frame_index")
        for tail_bytes_to_drop in (0, -1, True, 1.0, "1"):
            with self.subTest(tail_bytes_to_drop=tail_bytes_to_drop), self.assertRaises(
                ConfigurationError
            ) as raised:
                MockCorruptFrameSource(
                    source,
                    target_frame_index=0,
                    tail_bytes_to_drop=tail_bytes_to_drop,  # type: ignore[arg-type]
                )
            self.assertEqual(raised.exception.code, "invalid_tail_bytes_to_drop")
