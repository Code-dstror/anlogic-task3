"""Tests for the complete-record, in-memory PCIe v1 mock source."""

from __future__ import annotations

from threading import Event
from typing import Callable
import unittest

from linux.task3_pipeline import (
    ConfigurationError,
    DecodedFrame,
    FrameEventKind,
    JpegPayloadValidator,
    MockProtocolRecordSource,
    RuntimeMetrics,
    SourceError,
    SourceHealth,
    ValidationError,
)
from linux.task3_pipeline.frame_lifecycle_runner import (
    FrameLifecycleRunner,
    FrameStepOutcomeKind,
)
from linux.task3_pipeline.pcie_protocol_v1 import (
    FRAME_HEADER_EXPECTED_VALUES,
    FRAME_HEADER_FIELD_NAMES,
    FRAME_HEADER_STRUCT,
)
from linux.task3_pipeline.sequence_tracker import SequenceTracker
from tests._c2h_jpeg_fixture_helpers import canonical_jpeg_fixture_bytes


def make_record(
    payload: bytes,
    *,
    frame_sequence: int = 0,
    error_code: int = 0,
) -> bytes:
    """Build one complete valid-layout record with caller-selected wire fields."""

    fields: dict[str, object] = dict.fromkeys(FRAME_HEADER_FIELD_NAMES, 0)
    fields.update(FRAME_HEADER_EXPECTED_VALUES)
    fields.update(
        {
            "frame_sequence": frame_sequence,
            "payload_length": len(payload),
            "width": 2,
            "height": 1,
            "pixel_format": 1,
            "compression": 1,
            "quality": 75,
            "timestamp_ns": 1234,
            "status": 0,
            "error_code": error_code,
            "slot_id": 0,
            "payload_crc32": 0,
        }
    )
    return FRAME_HEADER_STRUCT.pack(*(fields[name] for name in FRAME_HEADER_FIELD_NAMES)) + payload


class StubDecoder:
    """Avoid coupling these transport tests to an OpenCV installation."""

    def decode(self, frame):  # type: ignore[no-untyped-def]
        return DecodedFrame(
            metadata=frame.metadata,
            pixels=b"\x00\x00\x00",
            width=1,
            height=1,
            pixel_format="bgr24",
            row_stride=3,
            decoded_monotonic_ns=99,
        )


class MockProtocolRecordSourceTests(unittest.TestCase):
    def _runner(
        self, source: MockProtocolRecordSource, *, maximum_payload_length: int
    ) -> tuple[FrameLifecycleRunner, RuntimeMetrics]:
        metrics = RuntimeMetrics()
        return (
            FrameLifecycleRunner(
                source,
                JpegPayloadValidator(maximum_payload_length),
                StubDecoder(),  # type: ignore[arg-type]
                SequenceTracker(),
                metrics,
            ),
            metrics,
        )

    def test_one_complete_record_maps_to_the_existing_frame_event(self) -> None:
        payload = b"\xff\xd8mock\xff\xd9"
        source = MockProtocolRecordSource(
            [make_record(payload, frame_sequence=41)], clock=lambda: 456
        )
        source.start()

        event = source.next_frame(Event())

        self.assertEqual(event.kind, FrameEventKind.FRAME)
        assert event.frame is not None
        self.assertEqual(event.frame.payload, payload)
        self.assertEqual(event.frame.metadata.ingest_id, 0)
        self.assertEqual(event.frame.metadata.wire_sequence, 41)
        self.assertEqual(event.frame.metadata.received_monotonic_ns, 456)
        self.assertEqual(event.frame.acquired_monotonic_ns, 456)
        self.assertEqual(event.frame.metadata.source_name, "mock_protocol_record")
        self.assertEqual(event.frame.metadata.source_timestamp, 1234)
        self.assertEqual((event.frame.metadata.declared_width, event.frame.metadata.declared_height), (2, 1))

    def test_wire_sequence_is_independent_from_locally_allocated_ingest_id(self) -> None:
        source = MockProtocolRecordSource(
            [make_record(b"first", frame_sequence=0xF0000001)], clock=lambda: 1
        )
        source.start()

        event = source.next_frame(Event())

        assert event.frame is not None
        self.assertEqual(event.frame.metadata.ingest_id, 0)
        self.assertEqual(event.frame.metadata.wire_sequence, 0xF0000001)

    def test_two_records_are_delivered_in_input_order(self) -> None:
        source = MockProtocolRecordSource(
            [
                make_record(b"first", frame_sequence=7),
                make_record(b"second", frame_sequence=3),
            ],
            clock=iter((10, 20)).__next__,
        )
        source.start()

        first = source.next_frame(Event()).frame
        second = source.next_frame(Event()).frame

        self.assertEqual([frame.payload for frame in (first, second) if frame], [b"first", b"second"])
        self.assertEqual(
            [frame.metadata.ingest_id for frame in (first, second) if frame], [0, 1]
        )
        self.assertEqual(
            [frame.metadata.received_monotonic_ns for frame in (first, second) if frame],
            [10, 20],
        )

    def test_mapper_failure_consumes_its_record_without_allocating_an_ingest_id(self) -> None:
        source = MockProtocolRecordSource(
            [make_record(b"bad", error_code=1), make_record(b"good", frame_sequence=8)],
            clock=iter((10, 20)).__next__,
        )
        source.start()

        with self.assertRaises(ValidationError) as raised:
            source.next_frame(Event())
        delivered = source.next_frame(Event()).frame

        self.assertEqual(raised.exception.stage, "transport_record_mapping")
        self.assertEqual(raised.exception.code, "record_error_code_nonzero")
        assert delivered is not None
        self.assertEqual(delivered.metadata.ingest_id, 0)
        self.assertEqual(delivered.metadata.wire_sequence, 8)

    def test_allowlisted_invalid_record_is_dropped_once_then_jpeg_fixture_delivers(self) -> None:
        jpeg_payload = canonical_jpeg_fixture_bytes()
        source = MockProtocolRecordSource(
            [b"\x00" * 64, make_record(jpeg_payload, frame_sequence=9)],
            clock=lambda: 123,
        )
        runner, metrics = self._runner(source, maximum_payload_length=len(jpeg_payload))
        runner.start()

        dropped = runner.step(Event())
        delivered = runner.step(Event())

        self.assertEqual(dropped.kind, FrameStepOutcomeKind.DROPPED_FRAME)
        assert dropped.error is not None
        self.assertEqual(dropped.error.stage, "transport_record_validation")
        self.assertEqual(dropped.error.code, "record_invalid_frame_magic")
        self.assertEqual(delivered.kind, FrameStepOutcomeKind.DELIVERED)
        self.assertEqual(delivered.decoded_frame.metadata.wire_sequence if delivered.decoded_frame else None, 9)
        self.assertEqual(
            metrics.snapshot(),
            {
                "frames_received": 1,
                "frames_delivered": 1,
                "frames_dropped": 1,
                "transport_records_invalid": 1,
                "jpeg_payloads_invalid": 0,
                "sequence_duplicate": 0,
                "sequence_gap": 0,
                "sequence_out_of_order": 0,
                "source_reconnects": 0,
                "source_errors": 0,
                "drop_reasons": {"transport_validation:record_invalid_frame_magic": 1},
                "transport_invalid_reasons": {"record_invalid_frame_magic": 1},
                "jpeg_invalid_reasons": {},
                "queue_depth": {},
                "queue_high_watermark": {},
            },
        )

    def test_non_allowlisted_buffer_and_mapper_errors_terminate_the_runner(self) -> None:
        valid_record = make_record(b"\xff\xd8ok\xff\xd9")
        released_view = memoryview(bytearray(valid_record))
        released_view.release()
        cases: tuple[tuple[str, object, Callable[[], int]], ...] = (
            ("buffer", released_view, lambda: 1),
            ("mapper", valid_record, lambda: -1),
        )
        for name, record, clock in cases:
            with self.subTest(name=name):
                source = MockProtocolRecordSource([record], clock=clock)  # type: ignore[list-item]
                runner, metrics = self._runner(source, maximum_payload_length=1024)
                runner.start()

                with self.assertRaises(ValidationError) as raised:
                    runner.step(Event())

                if name == "buffer":
                    self.assertEqual(raised.exception.code, "transport_record_buffer_access")
                else:
                    self.assertEqual(raised.exception.code, "invalid_received_monotonic_ns")
                self.assertEqual(metrics.snapshot(), RuntimeMetrics().snapshot())
                with self.assertRaises(ConfigurationError) as not_running:
                    runner.step(Event())
                self.assertEqual(not_running.exception.code, "runner_not_running")

    def test_eof_stop_restart_and_close_match_frame_source_semantics(self) -> None:
        source = MockProtocolRecordSource([make_record(b"one")], clock=lambda: 1)
        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        source.start()
        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.FRAME)
        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        self.assertEqual(source.health(), SourceHealth.STOPPED)

        source.start()
        restarted = source.next_frame(Event()).frame
        assert restarted is not None
        self.assertEqual(restarted.metadata.ingest_id, 1)
        stop_event = Event()
        stop_event.set()
        self.assertEqual(source.next_frame(stop_event).kind, FrameEventKind.END_OF_STREAM)
        source.close()
        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        with self.assertRaises(SourceError) as raised:
            source.start()
        self.assertEqual(raised.exception.code, "source_closed")

    def test_bytes_bytearray_and_memoryview_follow_parser_snapshot_semantics(self) -> None:
        payload = b"\xff\xd8mutable\xff\xd9"
        for factory in (bytes, bytearray, memoryview):
            with self.subTest(factory=factory.__name__):
                raw_record = bytearray(make_record(payload))
                record_input = factory(raw_record)
                source = MockProtocolRecordSource([record_input], clock=lambda: 1)
                source.start()
                if isinstance(record_input, (bytearray, memoryview)):
                    record_input[-3] = ord("X")

                event = source.next_frame(Event())

                assert event.frame is not None
                expected_payload = b"\xff\xd8mutablX\xff\xd9"
                if factory is bytes:
                    expected_payload = payload
                self.assertEqual(event.frame.payload, expected_payload)
                if isinstance(record_input, (bytearray, memoryview)):
                    record_input[-3] = ord("Y")
                    self.assertEqual(event.frame.payload, expected_payload)


if __name__ == "__main__":
    unittest.main()
