"""Tests for the explicit one-step frame lifecycle runner."""

from __future__ import annotations

from threading import Event
from typing import Any, Mapping
import unittest

from linux.task3_pipeline.errors import ConfigurationError, DecodeError, SourceError, ValidationError
import linux.task3_pipeline.frame_lifecycle_runner as runner_module
from linux.task3_pipeline.frame_lifecycle_runner import (
    FrameLifecycleRunner,
    FrameStepOutcome,
    FrameStepOutcomeKind,
)
from linux.task3_pipeline.interfaces import FrameSource
from linux.task3_pipeline.jpeg_payload_validator import JpegPayloadValidator
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

from tests._helpers import make_metadata


def make_frame(
    payload: bytes = b"\xff\xd8ok\xff\xd9", wire_sequence: int | None = None
) -> EncodedFrame:
    return EncodedFrame(
        metadata=make_metadata(payload_length=len(payload), wire_sequence=wire_sequence),
        payload=payload,
        acquired_monotonic_ns=101,
    )


class ScriptedSource(FrameSource):
    def __init__(self, outcomes: list[FrameEvent | BaseException]) -> None:
        self.outcomes = outcomes
        self.start_calls: list[Mapping[str, Any] | None] = []
        self.stop_calls = 0
        self.next_calls = 0
        self.received_stop_event: Event | None = None
        self.start_error: BaseException | None = None
        self.stop_error: BaseException | None = None
        self.health_value = SourceHealth.DEGRADED

    def start(self, config: Mapping[str, Any] | None = None) -> None:
        self.start_calls.append(config)
        if self.start_error is not None:
            raise self.start_error

    def next_frame(self, stop_event: Event) -> FrameEvent:
        self.next_calls += 1
        self.received_stop_event = stop_event
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, BaseException):
            raise outcome
        return outcome

    def stop(self) -> None:
        self.stop_calls += 1
        if self.stop_error is not None:
            raise self.stop_error

    def health(self) -> SourceHealth:
        return self.health_value


class RecordingTracker(SequenceTracker):
    def __init__(self, error: ValidationError | None = None) -> None:
        super().__init__()
        self.reset_calls = 0
        self.error = error
        self.observed_sequences: list[int] = []

    def observe(self, wire_sequence: int):  # type: ignore[override]
        self.observed_sequences.append(wire_sequence)
        if self.error is not None:
            raise self.error
        return super().observe(wire_sequence)

    def reset(self) -> None:
        self.reset_calls += 1
        super().reset()


class Validator(JpegPayloadValidator):
    def __init__(self, error: ValidationError | None = None) -> None:
        super().__init__(1024)
        self.error = error
        self.validate_calls = 0

    def validate(self, frame: EncodedFrame) -> EncodedFrame:
        self.validate_calls += 1
        if self.error is not None:
            error = self.error
            self.error = None
            raise error
        return frame


class Decoder(OpenCvJpegDecoder):
    def __init__(self, error: DecodeError | None = None) -> None:
        self.error = error
        self.returned: DecodedFrame | None = None
        self.decode_calls = 0

    def decode(self, frame: EncodedFrame) -> DecodedFrame:
        self.decode_calls += 1
        if self.error is not None:
            error = self.error
            self.error = None
            raise error
        self.returned = DecodedFrame(
            metadata=frame.metadata,
            pixels=b"\x00\x00\x00",
            width=1,
            height=1,
            pixel_format="bgr24",
            row_stride=3,
            decoded_monotonic_ns=200,
        )
        return self.returned


class RecordingMetrics(RuntimeMetrics):
    def __init__(self) -> None:
        super().__init__()
        self.source_error_calls = 0

    def record_source_error(self) -> None:
        self.source_error_calls += 1
        super().record_source_error()


class FrameLifecycleRunnerTests(unittest.TestCase):
    def _assert_snapshot(
        self,
        metrics: RuntimeMetrics,
        *,
        frames_received: int = 0,
        frames_delivered: int = 0,
        frames_dropped: int = 0,
        transport_records_invalid: int = 0,
        jpeg_payloads_invalid: int = 0,
        sequence_duplicate: int = 0,
        sequence_gap: int = 0,
        sequence_out_of_order: int = 0,
        source_reconnects: int = 0,
        source_errors: int = 0,
        drop_reasons: dict[str, int] | None = None,
        transport_invalid_reasons: dict[str, int] | None = None,
        jpeg_invalid_reasons: dict[str, int] | None = None,
        queue_depth: dict[str, int] | None = None,
        queue_high_watermark: dict[str, int] | None = None,
    ) -> None:
        """Assert every field of RuntimeMetrics.snapshot() exactly."""

        self.assertEqual(
            metrics.snapshot(),
            {
                "frames_received": frames_received,
                "frames_delivered": frames_delivered,
                "frames_dropped": frames_dropped,
                "transport_records_invalid": transport_records_invalid,
                "jpeg_payloads_invalid": jpeg_payloads_invalid,
                "sequence_duplicate": sequence_duplicate,
                "sequence_gap": sequence_gap,
                "sequence_out_of_order": sequence_out_of_order,
                "source_reconnects": source_reconnects,
                "source_errors": source_errors,
                "drop_reasons": {} if drop_reasons is None else drop_reasons,
                "transport_invalid_reasons": (
                    {} if transport_invalid_reasons is None else transport_invalid_reasons
                ),
                "jpeg_invalid_reasons": (
                    {} if jpeg_invalid_reasons is None else jpeg_invalid_reasons
                ),
                "queue_depth": {} if queue_depth is None else queue_depth,
                "queue_high_watermark": (
                    {} if queue_high_watermark is None else queue_high_watermark
                ),
            },
        )

    def _runner(
        self,
        outcomes: list[FrameEvent | BaseException],
        *,
        validator_error: ValidationError | None = None,
        decoder_error: DecodeError | None = None,
        tracker_error: ValidationError | None = None,
    ) -> tuple[FrameLifecycleRunner, ScriptedSource, RecordingTracker, RecordingMetrics, Decoder]:
        source = ScriptedSource(outcomes)
        tracker = RecordingTracker(tracker_error)
        metrics = RecordingMetrics()
        decoder = Decoder(decoder_error)
        return (
            FrameLifecycleRunner(source, Validator(validator_error), decoder, tracker, metrics),
            source,
            tracker,
            metrics,
            decoder,
        )

    def _start(self, runner: FrameLifecycleRunner) -> None:
        runner.start()

    def test_outcome_accepts_each_legal_single_value_combination(self) -> None:
        decoded = Decoder().decode(make_frame())
        event = FrameEvent(FrameEventKind.NO_DATA)
        error = ValidationError("bad", stage="jpeg_payload_validation", code="jpeg_payload_empty")

        self.assertIs(FrameStepOutcome(FrameStepOutcomeKind.DELIVERED, decoded_frame=decoded).decoded_frame, decoded)
        self.assertIs(FrameStepOutcome(FrameStepOutcomeKind.EVENT, event=event).event, event)
        self.assertIs(FrameStepOutcome(FrameStepOutcomeKind.DROPPED_FRAME, error=error).error, error)

    def test_outcome_rejects_every_invalid_kind_field_combination(self) -> None:
        decoded = Decoder().decode(make_frame())
        event = FrameEvent(FrameEventKind.NO_DATA)
        error = ValidationError("bad", stage="jpeg_payload_validation", code="jpeg_payload_empty")
        for kind in FrameStepOutcomeKind:
            for has_decoded in (False, True):
                for has_event in (False, True):
                    for has_error in (False, True):
                        legal = ((kind is FrameStepOutcomeKind.DELIVERED and has_decoded and not has_event and not has_error) or
                                 (kind is FrameStepOutcomeKind.EVENT and has_event and not has_decoded and not has_error) or
                                 (kind is FrameStepOutcomeKind.DROPPED_FRAME and has_error and not has_decoded and not has_event))
                        if legal:
                            continue
                        with self.subTest(kind=kind, fields=(has_decoded, has_event, has_error)):
                            with self.assertRaises(ValueError):
                                FrameStepOutcome(kind, decoded if has_decoded else None, event if has_event else None, error if has_error else None)
        with self.assertRaises(ValueError):
            FrameStepOutcome("event")  # type: ignore[arg-type]

    def test_construction_does_not_start_or_reset(self) -> None:
        runner, source, tracker, _metrics, _decoder = self._runner([])
        self.assertIsNotNone(runner)
        self.assertEqual(source.start_calls, [])
        self.assertEqual(tracker.reset_calls, 0)

    def test_start_delegates_same_source_and_enables_step(self) -> None:
        event = FrameEvent(FrameEventKind.NO_DATA)
        runner, source, _tracker, _metrics, _decoder = self._runner([event])
        config = {"local": "value"}
        runner.start(config)
        outcome = runner.step(Event())
        self.assertEqual(source.start_calls, [config])
        self.assertIs(outcome.event, event)

    def test_repeated_start_while_running_is_rejected_without_delegation(self) -> None:
        runner, source, _tracker, _metrics, _decoder = self._runner([])
        self._start(runner)
        with self.assertRaises(ConfigurationError) as raised:
            runner.start()
        self.assertEqual(raised.exception.stage, "frame_lifecycle_runner")
        self.assertEqual(raised.exception.code, "runner_already_running")
        self.assertEqual(len(source.start_calls), 1)

    def test_failed_start_preserves_exception_and_prior_state_without_reset(self) -> None:
        runner, source, tracker, _metrics, _decoder = self._runner([FrameEvent(FrameEventKind.NO_DATA)])
        failure = RuntimeError("start failed")
        source.start_error = failure
        with self.assertRaises(RuntimeError) as raised:
            runner.start()
        self.assertIs(raised.exception, failure)
        self.assertEqual(tracker.reset_calls, 0)
        with self.assertRaises(ConfigurationError) as not_running:
            runner.step(Event())
        self.assertEqual(not_running.exception.code, "runner_not_running")

    def test_step_in_idle_or_terminated_does_not_consume_source(self) -> None:
        runner, source, _tracker, _metrics, _decoder = self._runner([FrameEvent(FrameEventKind.END_OF_STREAM)])
        for label in ("idle", "terminated"):
            if label == "terminated":
                self._start(runner)
                runner.step(Event())
            with self.subTest(label=label), self.assertRaises(ConfigurationError) as raised:
                runner.step(Event())
            self.assertEqual(raised.exception.code, "runner_not_running")
        self.assertEqual(source.next_calls, 1)

    def test_stop_delegates_in_any_state_and_success_returns_to_idle(self) -> None:
        runner, source, tracker, _metrics, _decoder = self._runner([])
        runner.stop()
        self._start(runner)
        runner.stop()
        runner.stop()
        self.assertEqual(source.stop_calls, 3)
        self.assertEqual(tracker.reset_calls, 0)
        with self.assertRaises(ConfigurationError):
            runner.step(Event())

        terminal_runner, terminal_source, _tracker, _metrics, _decoder = self._runner(
            [FrameEvent(FrameEventKind.END_OF_STREAM)]
        )
        self._start(terminal_runner)
        terminal_runner.step(Event())
        terminal_runner.stop()
        self.assertEqual(terminal_source.stop_calls, 1)

    def test_stop_failure_preserves_exception_and_running_state(self) -> None:
        event = FrameEvent(FrameEventKind.NO_DATA)
        runner, source, _tracker, _metrics, _decoder = self._runner([event])
        self._start(runner)
        failure = RuntimeError("stop failed")
        source.stop_error = failure
        with self.assertRaises(RuntimeError) as raised:
            runner.stop()
        self.assertIs(raised.exception, failure)
        self.assertIs(runner.step(Event()).event, event)

    def test_health_is_delegated_without_rewriting(self) -> None:
        runner, source, _tracker, _metrics, _decoder = self._runner([])
        source.health_value = SourceHealth.FAILED
        self.assertIs(runner.health(), source.health_value)

    def test_stop_event_identity_reaches_source(self) -> None:
        runner, source, _tracker, _metrics, _decoder = self._runner([FrameEvent(FrameEventKind.NO_DATA)])
        self._start(runner)
        stop_event = Event()
        runner.step(stop_event)
        self.assertIs(source.received_stop_event, stop_event)

    def test_valid_frame_is_delivered_without_runner_metric_duplication(self) -> None:
        runner, _source, _tracker, metrics, decoder = self._runner([FrameEvent(FrameEventKind.FRAME, make_frame())])
        self._start(runner)
        outcome = runner.step(Event())
        self.assertEqual(outcome.kind, FrameStepOutcomeKind.DELIVERED)
        self.assertIs(outcome.decoded_frame, decoder.returned)
        self._assert_snapshot(metrics, frames_received=1, frames_delivered=1)
        self.assertEqual(metrics.source_error_calls, 0)

    def test_no_data_keeps_running_and_next_step_consumes_next_event(self) -> None:
        no_data = FrameEvent(FrameEventKind.NO_DATA)
        eos = FrameEvent(FrameEventKind.END_OF_STREAM)
        runner, source, _tracker, metrics, _decoder = self._runner([no_data, eos])
        self._start(runner)
        self.assertIs(runner.step(Event()).event, no_data)
        self.assertEqual(source.next_calls, 1)
        self._assert_snapshot(metrics)
        self.assertEqual(metrics.snapshot(), RuntimeMetrics().snapshot())
        self.assertIs(runner.step(Event()).event, eos)
        self._assert_snapshot(metrics)
        self.assertEqual(metrics.snapshot(), RuntimeMetrics().snapshot())

    def test_disconnect_and_fatal_events_record_one_source_error_and_terminate(self) -> None:
        for kind in (FrameEventKind.RECOVERABLE_DISCONNECT, FrameEventKind.FATAL_ERROR):
            with self.subTest(kind=kind):
                event = FrameEvent(kind, detail="same")
                runner, source, _tracker, metrics, _decoder = self._runner([event, FrameEvent(FrameEventKind.NO_DATA)])
                self._start(runner)
                self.assertIs(runner.step(Event()).event, event)
                self.assertEqual(metrics.source_error_calls, 1)
                self._assert_snapshot(metrics, source_errors=1)
                with self.assertRaises(ConfigurationError):
                    runner.step(Event())
                self.assertEqual(source.next_calls, 1)

    def test_end_of_stream_terminates_without_metrics(self) -> None:
        event = FrameEvent(FrameEventKind.END_OF_STREAM)
        runner, _source, _tracker, metrics, _decoder = self._runner([event])
        self._start(runner)
        self.assertIs(runner.step(Event()).event, event)
        self._assert_snapshot(metrics)
        with self.assertRaises(ConfigurationError):
            runner.step(Event())

    def test_allowlisted_validation_and_decode_errors_drop_once_and_continue(self) -> None:
        cases: tuple[tuple[PipelineError, str], ...] = (
            (ValidationError("bad", stage="jpeg_payload_validation", code="jpeg_payload_empty"), "validator"),
            (DecodeError("bad", stage="jpeg_decode", code="jpeg_decode_failed"), "decoder"),
        )
        for error, location in cases:
            with self.subTest(error=error):
                kwargs = {"validator_error": error} if location == "validator" else {"decoder_error": error}
                runner, source, _tracker, metrics, decoder = self._runner(
                    [
                        FrameEvent(FrameEventKind.FRAME, make_frame()),
                        FrameEvent(FrameEventKind.FRAME, make_frame()),
                    ],
                    **kwargs,
                )
                self._start(runner)
                outcome = runner.step(Event())
                self.assertEqual(outcome.kind, FrameStepOutcomeKind.DROPPED_FRAME)
                self.assertIs(outcome.error, error)
                self.assertEqual(metrics.source_error_calls, 0)
                if location == "validator":
                    self._assert_snapshot(
                        metrics,
                        frames_received=1,
                        frames_dropped=1,
                        jpeg_payloads_invalid=1,
                        drop_reasons={"jpeg_validation:jpeg_payload_empty": 1},
                        jpeg_invalid_reasons={"jpeg_payload_empty": 1},
                    )
                else:
                    self._assert_snapshot(
                        metrics,
                        frames_received=1,
                        frames_dropped=1,
                        drop_reasons={"jpeg_decode:jpeg_decode_failed": 1},
                    )
                second = runner.step(Event())
                self.assertEqual(second.kind, FrameStepOutcomeKind.DELIVERED)
                self.assertIs(second.decoded_frame, decoder.returned)
                if location == "validator":
                    self._assert_snapshot(
                        metrics,
                        frames_received=2,
                        frames_delivered=1,
                        frames_dropped=1,
                        jpeg_payloads_invalid=1,
                        drop_reasons={"jpeg_validation:jpeg_payload_empty": 1},
                        jpeg_invalid_reasons={"jpeg_payload_empty": 1},
                    )
                else:
                    self._assert_snapshot(
                        metrics,
                        frames_received=2,
                        frames_delivered=1,
                        frames_dropped=1,
                        drop_reasons={"jpeg_decode:jpeg_decode_failed": 1},
                    )
                self.assertEqual(source.next_calls, 2)

    def test_non_allowlisted_sequence_error_propagates_from_tracker_and_terminates(self) -> None:
        error = ValidationError(
            "invalid sequence", stage="sequence_tracking", code="invalid_wire_sequence"
        )
        frame = make_frame(wire_sequence=19)
        source = ScriptedSource([FrameEvent(FrameEventKind.FRAME, frame)])
        tracker = RecordingTracker(error)
        validator = Validator()
        decoder = Decoder()
        metrics = RecordingMetrics()
        runner = FrameLifecycleRunner(source, validator, decoder, tracker, metrics)
        self._start(runner)

        with self.assertRaises(ValidationError) as raised:
            runner.step(Event())

        self.assertIs(raised.exception, error)
        self.assertEqual(tracker.observed_sequences, [19])
        self.assertEqual(validator.validate_calls, 0)
        self.assertEqual(decoder.decode_calls, 0)
        self._assert_snapshot(
            metrics,
            frames_received=1,
            frames_dropped=1,
            drop_reasons={"sequence_validation:invalid_wire_sequence": 1},
        )
        with self.assertRaises(ConfigurationError) as not_running:
            runner.step(Event())
        self.assertEqual(not_running.exception.code, "runner_not_running")
        self.assertEqual(source.next_calls, 1)

    def test_non_allowlisted_decode_error_propagates_and_terminates(self) -> None:
        error = DecodeError("bad", stage="jpeg_decode", code="jpeg_decode_cv2_error")
        runner, source, _tracker, metrics, _decoder = self._runner(
            [FrameEvent(FrameEventKind.FRAME, make_frame())], decoder_error=error
        )
        self._start(runner)
        with self.assertRaises(DecodeError) as raised:
            runner.step(Event())
        self.assertIs(raised.exception, error)
        self._assert_snapshot(
            metrics,
            frames_received=1,
            frames_dropped=1,
            drop_reasons={"jpeg_decode:jpeg_decode_cv2_error": 1},
        )
        with self.assertRaises(ConfigurationError):
            runner.step(Event())
        self.assertEqual(source.next_calls, 1)

    def test_source_error_is_not_double_counted_and_terminates(self) -> None:
        error = SourceError("source", stage="source", code="failed")
        runner, source, _tracker, metrics, _decoder = self._runner([error])
        self._start(runner)
        with self.assertRaises(SourceError) as raised:
            runner.step(Event())
        self.assertIs(raised.exception, error)
        self.assertEqual(metrics.source_error_calls, 1)
        self._assert_snapshot(metrics, source_errors=1)
        with self.assertRaises(ConfigurationError):
            runner.step(Event())
        self.assertEqual(source.next_calls, 1)

    def test_unexpected_exception_terminates_without_metrics(self) -> None:
        error = RuntimeError("unexpected")
        runner, _source, _tracker, metrics, _decoder = self._runner([error])
        self._start(runner)
        with self.assertRaises(RuntimeError) as raised:
            runner.step(Event())
        self.assertIs(raised.exception, error)
        self.assertEqual(metrics.snapshot()["source_errors"], 0)
        with self.assertRaises(ConfigurationError):
            runner.step(Event())

    def test_classifier_failure_terminates_and_preserves_exception(self) -> None:
        error = ValidationError("bad", stage="jpeg_payload_validation", code="jpeg_payload_empty")
        runner, source, _tracker, metrics, _decoder = self._runner(
            [FrameEvent(FrameEventKind.FRAME, make_frame())], validator_error=error
        )
        classifier_failure = RuntimeError("classifier failure")
        classified_errors: list[ValidationError] = []

        def failing_classifier(actual: ValidationError) -> None:
            classified_errors.append(actual)
            raise classifier_failure

        original = runner_module.classify_frame_error
        runner_module.classify_frame_error = failing_classifier
        try:
            self._start(runner)
            with self.assertRaises(RuntimeError) as raised:
                runner.step(Event())
        finally:
            runner_module.classify_frame_error = original
        self.assertEqual(classified_errors, [error])
        self.assertIs(raised.exception, classifier_failure)
        self._assert_snapshot(
            metrics,
            frames_received=1,
            frames_dropped=1,
            jpeg_payloads_invalid=1,
            drop_reasons={"jpeg_validation:jpeg_payload_empty": 1},
            jpeg_invalid_reasons={"jpeg_payload_empty": 1},
        )
        with self.assertRaises(ConfigurationError):
            runner.step(Event())
        self.assertEqual(source.next_calls, 1)

    def test_terminal_event_stop_and_restart_never_reset_tracker_or_record_reconnect(self) -> None:
        runner, _source, tracker, metrics, _decoder = self._runner([FrameEvent(FrameEventKind.END_OF_STREAM), FrameEvent(FrameEventKind.NO_DATA)])
        self._start(runner)
        runner.step(Event())
        runner.stop()
        runner.start()
        self.assertIs(runner.step(Event()).event.kind, FrameEventKind.NO_DATA)
        self.assertEqual(tracker.reset_calls, 0)
        self.assertEqual(metrics.snapshot()["source_reconnects"], 0)
