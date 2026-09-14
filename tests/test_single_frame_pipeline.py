"""Tests for one-event orchestration of the hardware-agnostic JPEG pipeline."""

from __future__ import annotations

from threading import Event
from typing import Any, Mapping
import unittest

from linux.task3_pipeline.errors import DecodeError, SourceError, ValidationError
from linux.task3_pipeline.interfaces import FrameSource
from linux.task3_pipeline.jpeg_payload_validator import JpegPayloadValidator
from linux.task3_pipeline.mock_corrupt_frame_source import MockCorruptFrameSource
from linux.task3_pipeline.models import (
    DecodedFrame,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    RuntimeMetrics,
    SourceHealth,
)
from linux.task3_pipeline.opencv_jpeg_decoder import OpenCvJpegDecoder
from linux.task3_pipeline.sequence_tracker import SequenceTracker
from linux.task3_pipeline.single_frame_pipeline import SingleFramePipeline

from tests._helpers import make_metadata


class ScriptedFrameSource(FrameSource):
    """A minimal source double that returns scripted events or raises errors."""

    def __init__(self, outcomes: list[FrameEvent | SourceError], calls: list[str] | None = None) -> None:
        self._outcomes = outcomes
        self._calls = calls
        self.received_stop_event: Event | None = None

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        pass

    def next_frame(self, stop_event: Event) -> FrameEvent:
        self.received_stop_event = stop_event
        if self._calls is not None:
            self._calls.append("source")
        outcome = self._outcomes.pop(0)
        if isinstance(outcome, SourceError):
            raise outcome
        return outcome

    def stop(self) -> None:
        pass

    def health(self) -> SourceHealth:
        return SourceHealth.READY


class RecordingSequenceTracker(SequenceTracker):
    """Sequence tracker that records observations while retaining its semantics."""

    def __init__(self, calls: list[str], error: ValidationError | None = None) -> None:
        super().__init__()
        self.calls = calls
        self.error = error

    def observe(self, wire_sequence: int):  # type: ignore[override]
        self.calls.append("sequence")
        if self.error is not None:
            raise self.error
        return super().observe(wire_sequence)


class RecordingValidator(JpegPayloadValidator):
    """JPEG validator that records calls while retaining production validation."""

    def __init__(
        self,
        calls: list[str],
        maximum: int = 1024,
        returned_frame: EncodedFrame | None = None,
        error: ValidationError | None = None,
    ) -> None:
        super().__init__(maximum)
        self.calls = calls
        self.returned_frame = returned_frame
        self.error = error
        self.received_frame: EncodedFrame | None = None

    def validate(self, frame: EncodedFrame) -> EncodedFrame:
        self.calls.append("validator")
        self.received_frame = frame
        if self.error is not None:
            raise self.error
        if self.returned_frame is not None:
            return self.returned_frame
        return super().validate(frame)


class RecordingDecoder(OpenCvJpegDecoder):
    """Decoder double conforming to the existing decoder implementation API."""

    def __init__(self, calls: list[str], error: DecodeError | None = None) -> None:
        self.calls = calls
        self.error = error
        self.received_frame: EncodedFrame | None = None
        self.returned_frame: DecodedFrame | None = None

    def decode(self, frame: EncodedFrame) -> DecodedFrame:
        self.calls.append("decoder")
        self.received_frame = frame
        if self.error is not None:
            raise self.error
        self.returned_frame = DecodedFrame(
            metadata=frame.metadata,
            pixels=b"\x00\x00\x00",
            width=1,
            height=1,
            pixel_format="bgr24",
            row_stride=3,
            decoded_monotonic_ns=200,
        )
        return self.returned_frame


class RecordingMetrics(RuntimeMetrics):
    """Metrics double that records stage order while preserving counter behavior."""

    def __init__(self, calls: list[str]) -> None:
        super().__init__()
        self.calls = calls

    def record_received(self) -> None:
        self.calls.append("received")
        super().record_received()

    def record_delivered(self) -> None:
        self.calls.append("delivered")
        super().record_delivered()


def make_frame(payload: bytes, wire_sequence: int | None = None) -> EncodedFrame:
    return EncodedFrame(
        metadata=make_metadata(payload_length=len(payload), wire_sequence=wire_sequence),
        payload=payload,
        acquired_monotonic_ns=101,
    )


class SingleFramePipelineTests(unittest.TestCase):
    @staticmethod
    def _pipeline(
        outcomes: list[FrameEvent | SourceError],
        calls: list[str] | None = None,
        decoder_error: DecodeError | None = None,
    ) -> tuple[SingleFramePipeline, RecordingMetrics, RecordingSequenceTracker, RecordingValidator, RecordingDecoder]:
        trace = calls if calls is not None else []
        metrics = RecordingMetrics(trace)
        tracker = RecordingSequenceTracker(trace)
        validator = RecordingValidator(trace)
        decoder = RecordingDecoder(trace, decoder_error)
        return (
            SingleFramePipeline(ScriptedFrameSource(outcomes, trace), validator, decoder, tracker, metrics),
            metrics,
            tracker,
            validator,
            decoder,
        )

    def test_valid_frame_follows_the_stage_order_and_is_delivered(self) -> None:
        calls: list[str] = []
        original = make_frame(b"\xff\xd8valid\xff\xd9", wire_sequence=4)
        validated = make_frame(b"\xff\xd8replacement\xff\xd9", wire_sequence=4)
        source = ScriptedFrameSource([FrameEvent(FrameEventKind.FRAME, original)], calls)
        metrics = RecordingMetrics(calls)
        tracker = RecordingSequenceTracker(calls)
        validator = RecordingValidator(calls, returned_frame=validated)
        decoder = RecordingDecoder(calls)
        pipeline = SingleFramePipeline(source, validator, decoder, tracker, metrics)
        stop_event = Event()

        result = pipeline.process_next(stop_event)

        self.assertIsInstance(result, DecodedFrame)
        self.assertIs(source.received_stop_event, stop_event)
        self.assertIs(validator.received_frame, original)
        self.assertIs(decoder.received_frame, validated)
        self.assertIsNot(decoder.received_frame, original)
        self.assertIs(result, decoder.returned_frame)
        self.assertEqual(calls, ["source", "received", "sequence", "validator", "decoder", "delivered"])
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["frames_delivered"], 1)
        self.assertEqual(snapshot["frames_dropped"], 0)
        self.assertEqual(snapshot["source_errors"], 0)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 0)

    def test_frame_without_wire_sequence_skips_tracker_and_is_delivered(self) -> None:
        calls: list[str] = []
        pipeline, metrics, tracker, _validator, _decoder = self._pipeline(
            [FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8valid\xff\xd9"))], calls
        )

        self.assertIsInstance(pipeline.process_next(Event()), DecodedFrame)
        self.assertNotIn("sequence", calls)
        self.assertEqual(tracker.last_sequence, None)
        self.assertEqual(metrics.snapshot()["frames_delivered"], 1)

    def test_first_and_in_order_sequences_do_not_record_anomalies(self) -> None:
        frames = [
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8a\xff\xd9", 4)),
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8b\xff\xd9", 5)),
        ]
        pipeline, metrics, _tracker, _validator, _decoder = self._pipeline(frames)

        pipeline.process_next(Event())
        pipeline.process_next(Event())

        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_delivered"], 2)
        self.assertEqual(snapshot["sequence_duplicate"], 0)
        self.assertEqual(snapshot["sequence_gap"], 0)
        self.assertEqual(snapshot["sequence_out_of_order"], 0)

    def test_sequence_anomalies_are_recorded_without_dropping_frames(self) -> None:
        frames = [
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8a\xff\xd9", 4)),
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8b\xff\xd9", 4)),
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8c\xff\xd9", 7)),
            FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8d\xff\xd9", 5)),
        ]
        pipeline, metrics, _tracker, _validator, _decoder = self._pipeline(frames)

        for _ in range(4):
            self.assertIsInstance(pipeline.process_next(Event()), DecodedFrame)

        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_delivered"], 4)
        self.assertEqual(snapshot["frames_dropped"], 0)
        self.assertEqual(snapshot["sequence_duplicate"], 1)
        self.assertEqual(snapshot["sequence_gap"], 1)
        self.assertEqual(snapshot["sequence_out_of_order"], 1)

    def test_non_frame_events_pass_through_without_processing_or_metrics(self) -> None:
        for kind in (
            FrameEventKind.NO_DATA,
            FrameEventKind.RECOVERABLE_DISCONNECT,
            FrameEventKind.FATAL_ERROR,
            FrameEventKind.END_OF_STREAM,
        ):
            with self.subTest(kind=kind):
                calls: list[str] = []
                event = FrameEvent(kind, detail="unchanged")
                pipeline, metrics, _tracker, _validator, _decoder = self._pipeline([event], calls)

                self.assertIs(pipeline.process_next(Event()), event)
                self.assertEqual(calls, ["source"])
                snapshot = metrics.snapshot()
                self.assertEqual(snapshot["frames_received"], 0)
                self.assertEqual(snapshot["frames_delivered"], 0)
                self.assertEqual(snapshot["frames_dropped"], 0)
                self.assertEqual(snapshot["jpeg_payloads_invalid"], 0)

    def test_source_error_is_propagated_and_recorded_once(self) -> None:
        error = SourceError("source failed", stage="scripted", code="source_failed")
        pipeline, metrics, _tracker, _validator, _decoder = self._pipeline([error])

        with self.assertRaises(SourceError) as raised:
            pipeline.process_next(Event())

        self.assertIs(raised.exception, error)
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["source_errors"], 1)
        self.assertEqual(snapshot["frames_received"], 0)
        self.assertEqual(snapshot["frames_delivered"], 0)
        self.assertEqual(snapshot["frames_dropped"], 0)

    def test_sequence_validation_error_is_dropped_without_reaching_jpeg_stages(self) -> None:
        calls: list[str] = []
        error = ValidationError(
            "invalid sequence", stage="sequence_tracking", code="invalid_wire_sequence"
        )
        frame = make_frame(b"\xff\xd8valid\xff\xd9", wire_sequence=4)
        metrics = RecordingMetrics(calls)
        tracker = RecordingSequenceTracker(calls, error)
        validator = RecordingValidator(calls)
        decoder = RecordingDecoder(calls)
        pipeline = SingleFramePipeline(
            ScriptedFrameSource([FrameEvent(FrameEventKind.FRAME, frame)], calls),
            validator,
            decoder,
            tracker,
            metrics,
        )

        with self.assertRaises(ValidationError) as raised:
            pipeline.process_next(Event())

        self.assertIs(raised.exception, error)
        self.assertEqual(calls, ["source", "received", "sequence"])
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["sequence_validation:invalid_wire_sequence"], 1)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 0)
        self.assertEqual(snapshot["frames_delivered"], 0)

    def test_validator_error_is_propagated_with_identity_and_recorded_once(self) -> None:
        calls: list[str] = []
        error = ValidationError(
            "invalid JPEG", stage="jpeg_payload_validation", code="jpeg_payload_invalid_eoi"
        )
        metrics = RecordingMetrics(calls)
        validator = RecordingValidator(calls, error=error)
        decoder = RecordingDecoder(calls)
        pipeline = SingleFramePipeline(
            ScriptedFrameSource(
                [FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8valid\xff\xd9"))],
                calls,
            ),
            validator,
            decoder,
            RecordingSequenceTracker(calls),
            metrics,
        )

        with self.assertRaises(ValidationError) as raised:
            pipeline.process_next(Event())

        self.assertIs(raised.exception, error)
        self.assertNotIn("decoder", calls)
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 1)
        self.assertEqual(snapshot["jpeg_invalid_reasons"][error.code], 1)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["jpeg_validation:" + error.code], 1)
        self.assertEqual(snapshot["frames_delivered"], 0)

    def test_corrupted_eoi_is_recorded_as_jpeg_validation_failure(self) -> None:
        calls: list[str] = []
        original = make_frame(b"\xff\xd8valid\xff\xd9")
        source = MockCorruptFrameSource(
            ScriptedFrameSource([FrameEvent(FrameEventKind.FRAME, original)], calls),
            target_frame_index=0,
            tail_bytes_to_drop=2,
        )
        metrics = RecordingMetrics(calls)
        tracker = RecordingSequenceTracker(calls)
        validator = RecordingValidator(calls)
        decoder = RecordingDecoder(calls)
        pipeline = SingleFramePipeline(source, validator, decoder, tracker, metrics)

        with self.assertRaises(ValidationError) as raised:
            pipeline.process_next(Event())

        self.assertEqual(raised.exception.code, "jpeg_payload_invalid_eoi")
        self.assertNotIn("decoder", calls)
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 1)
        self.assertEqual(snapshot["jpeg_invalid_reasons"]["jpeg_payload_invalid_eoi"], 1)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["jpeg_validation:jpeg_payload_invalid_eoi"], 1)
        self.assertEqual(snapshot["frames_delivered"], 0)

    def test_decode_failure_is_dropped_after_successful_validation(self) -> None:
        calls: list[str] = []
        error = DecodeError("decode failed", stage="scripted", code="decode_failed")
        pipeline, metrics, _tracker, _validator, _decoder = self._pipeline(
            [FrameEvent(FrameEventKind.FRAME, make_frame(b"\xff\xd8valid\xff\xd9"))],
            calls,
            decoder_error=error,
        )

        with self.assertRaises(DecodeError) as raised:
            pipeline.process_next(Event())

        self.assertIs(raised.exception, error)
        self.assertEqual(calls, ["source", "received", "validator", "decoder"])
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["jpeg_decode:decode_failed"], 1)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 0)
        self.assertEqual(snapshot["frames_delivered"], 0)

    def test_boundary_valid_but_undecodable_payload_fails_in_real_decoder(self) -> None:
        payload = b"\xff\xd8not an image\xff\xd9"
        metrics = RuntimeMetrics()
        pipeline = SingleFramePipeline(
            ScriptedFrameSource([FrameEvent(FrameEventKind.FRAME, make_frame(payload))]),
            JpegPayloadValidator(1024),
            OpenCvJpegDecoder(),
            SequenceTracker(),
            metrics,
        )

        with self.assertRaises(DecodeError) as raised:
            pipeline.process_next(Event())

        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["frames_delivered"], 0)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], 0)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["jpeg_decode:" + raised.exception.code], 1)
        self.assertFalse(
            any(reason.startswith("jpeg_validation:") for reason in snapshot["drop_reasons"])
        )
