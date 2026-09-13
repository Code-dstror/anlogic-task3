"""Tests for shared pipeline models, metrics, and abstract contracts."""

from __future__ import annotations

from abc import ABC
from threading import Barrier, Event, Lock, Thread
import time
import unittest

from linux.task3_pipeline import (
    DecodedFrame,
    Detection,
    DetectionResult,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    FrameSource,
    InferenceBackend,
    OutputSink,
    RuntimeMetrics,
    SourceHealth,
)

from tests._helpers import make_metadata


class GatedSpyLock:
    """A test-only lock that holds its first acquirer until the test permits it."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._state_lock = Lock()
        self._acquire_count = 0
        self.first_writer_entered = Event()
        self.second_writer_attempted = Event()
        self.allow_first_writer_release = Event()

    def acquire(self) -> bool:
        with self._state_lock:
            self._acquire_count += 1
            acquisition_number = self._acquire_count

        if acquisition_number == 1:
            self._lock.acquire()
            self.first_writer_entered.set()
            if not self.allow_first_writer_release.wait(timeout=2):
                self._lock.release()
                raise RuntimeError("test did not release the first writer")
            return True

        if acquisition_number == 2:
            self.second_writer_attempted.set()
        return self._lock.acquire()

    def release(self) -> None:
        self._lock.release()

    def __enter__(self) -> GatedSpyLock:
        self.acquire()
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        self.release()


class FrameModelTests(unittest.TestCase):
    def test_metadata_keeps_local_and_wire_identity_separate(self) -> None:
        metadata = make_metadata()

        self.assertEqual(metadata.ingest_id, 7)
        self.assertEqual(metadata.wire_sequence, 42)
        self.assertEqual(metadata.source_name, "mock_file")

    def test_encoded_frame_checks_payload_length_without_protocol_parsing(self) -> None:
        frame = EncodedFrame(
            metadata=make_metadata(payload_length=3),
            payload=b"abc",
            acquired_monotonic_ns=101,
        )
        self.assertEqual(frame.payload, b"abc")

        with self.assertRaises(ValueError):
            EncodedFrame(
                metadata=make_metadata(payload_length=2),
                payload=b"abc",
                acquired_monotonic_ns=101,
            )

    def test_encoded_frame_copies_mutable_payloads(self) -> None:
        payload = bytearray(b"abc")
        frame = EncodedFrame(make_metadata(), payload, 101)
        payload[0] = ord("z")
        self.assertEqual(frame.payload, b"abc")
        self.assertIsInstance(frame.payload, bytes)

        backing = bytearray(b"def")
        view_frame = EncodedFrame(make_metadata(), memoryview(backing), 101)
        backing[0] = ord("z")
        self.assertEqual(view_frame.payload, b"def")
        self.assertIsInstance(view_frame.payload, bytes)

    def test_encoded_frame_rejects_unexpected_payload_types(self) -> None:
        for payload in ("abc", 3):
            with self.subTest(payload=payload), self.assertRaises(TypeError):
                EncodedFrame(make_metadata(), payload, 101)  # type: ignore[arg-type]

    def test_encoded_frame_validates_normalized_payload_length(self) -> None:
        with self.assertRaises(ValueError):
            EncodedFrame(make_metadata(payload_length=2), bytearray(b"abc"), 101)

    def test_decoded_frame_requires_explicit_layout(self) -> None:
        decoded = DecodedFrame(
            metadata=make_metadata(),
            pixels=b"pixels",
            width=2,
            height=1,
            pixel_format="rgb24",
            row_stride=6,
            decoded_monotonic_ns=102,
        )
        self.assertEqual(decoded.pixel_format, "rgb24")

    def test_decoded_frame_copies_mutable_pixel_buffers(self) -> None:
        pixels = bytearray(b"pixels")
        decoded = DecodedFrame(
            make_metadata(), pixels, 2, 1, "rgb24", 6, 102
        )
        pixels[0] = ord("P")
        self.assertEqual(decoded.pixels, b"pixels")
        self.assertIsInstance(decoded.pixels, bytes)

        backing = bytearray(b"sample")
        viewed = DecodedFrame(
            make_metadata(), memoryview(backing), 2, 1, "rgb24", 6, 102
        )
        backing[0] = ord("S")
        self.assertEqual(viewed.pixels, b"sample")
        self.assertIsInstance(viewed.pixels, bytes)

    def test_decoded_frame_rejects_unexpected_pixel_types(self) -> None:
        for pixels in ("pixels", 6):
            with self.subTest(pixels=pixels), self.assertRaises(TypeError):
                DecodedFrame(
                    make_metadata(), pixels, 2, 1, "rgb24", 6, 102
                )  # type: ignore[arg-type]

    def test_detection_result_retains_both_ids(self) -> None:
        result = DetectionResult(
            ingest_id=7,
            wire_sequence=42,
            inference_started_monotonic_ns=110,
            inference_finished_monotonic_ns=115,
            detections=(Detection(class_id=1, score=0.5, bbox=(0, 0, 1, 1)),),
        )
        self.assertEqual(result.ingest_id, 7)
        self.assertEqual(result.wire_sequence, 42)

    def test_frame_event_requires_frame_only_for_frame_events(self) -> None:
        frame = EncodedFrame(make_metadata(), b"abc", 101)
        self.assertEqual(FrameEvent(FrameEventKind.FRAME, frame).frame, frame)
        with self.assertRaises(ValueError):
            FrameEvent(FrameEventKind.FRAME)
        with self.assertRaises(ValueError):
            FrameEvent(FrameEventKind.END_OF_STREAM, frame)


class MetricsTests(unittest.TestCase):
    def test_metrics_snapshot_tracks_counters_and_watermark(self) -> None:
        metrics = RuntimeMetrics()
        metrics.record_received()
        metrics.record_delivered()
        metrics.record_drop("queue_overload")
        metrics.record_transport_invalid("crc")
        metrics.record_jpeg_invalid("missing_eoi")
        metrics.record_sequence_anomaly("gap")
        metrics.record_source_error()
        metrics.record_source_reconnect()
        metrics.set_queue_depth("encoded", 2)
        metrics.set_queue_depth("encoded", 1)

        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], 1)
        self.assertEqual(snapshot["frames_delivered"], 1)
        self.assertEqual(snapshot["frames_dropped"], 1)
        self.assertEqual(snapshot["drop_reasons"]["queue_overload"], 1)
        self.assertEqual(snapshot["transport_invalid_reasons"]["crc"], 1)
        self.assertEqual(snapshot["jpeg_invalid_reasons"]["missing_eoi"], 1)
        self.assertEqual(snapshot["sequence_gap"], 1)
        self.assertEqual(snapshot["source_errors"], 1)
        self.assertEqual(snapshot["source_reconnects"], 1)
        self.assertEqual(snapshot["queue_depth"]["encoded"], 1)
        self.assertEqual(snapshot["queue_high_watermark"]["encoded"], 2)

    def test_unknown_sequence_anomaly_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            RuntimeMetrics().record_sequence_anomaly("unknown")

    def test_source_counters_are_read_only(self) -> None:
        metrics = RuntimeMetrics()
        with self.assertRaises(AttributeError):
            metrics.source_errors += 1
        with self.assertRaises(AttributeError):
            metrics.source_reconnects += 1

    def test_snapshot_is_isolated_from_mutable_copies(self) -> None:
        metrics = RuntimeMetrics()
        metrics.record_drop("queue_overload")
        snapshot = metrics.snapshot()
        reasons_copy = dict(snapshot["drop_reasons"])
        reasons_copy["queue_overload"] = 99
        reasons_copy["other"] = 1

        current = metrics.snapshot()
        self.assertEqual(current["drop_reasons"]["queue_overload"], 1)
        self.assertNotIn("other", current["drop_reasons"])

    def test_concurrent_metric_updates_are_not_lost(self) -> None:
        metrics = RuntimeMetrics()
        workers = 8
        updates_per_worker = 500
        start_writers = Barrier(workers + 1, timeout=2)
        failures: list[BaseException] = []
        failures_lock = Lock()

        def update_metrics() -> None:
            try:
                start_writers.wait()
                for _ in range(updates_per_worker):
                    metrics.record_received()
                    metrics.record_delivered()
                    metrics.record_drop("queue_overload")
                    metrics.record_transport_invalid("crc")
                    metrics.record_jpeg_invalid("missing_eoi")
                    metrics.record_sequence_anomaly("duplicate")
                    metrics.record_sequence_anomaly("gap")
                    metrics.record_sequence_anomaly("out_of_order")
                    metrics.record_source_error()
                    metrics.record_source_reconnect()
                    metrics.set_queue_depth("encoded", 2)
                    time.sleep(0)
            except BaseException as error:
                with failures_lock:
                    failures.append(error)

        threads = [Thread(target=update_metrics) for _ in range(workers)]
        for thread in threads:
            thread.start()
        try:
            start_writers.wait()
        finally:
            for thread in threads:
                thread.join(timeout=5)
                self.assertFalse(
                    thread.is_alive(), "concurrent metrics writer did not finish"
                )
        self.assertEqual(failures, [])

        expected = workers * updates_per_worker
        snapshot = metrics.snapshot()
        self.assertEqual(snapshot["frames_received"], expected)
        self.assertEqual(snapshot["frames_delivered"], expected)
        self.assertEqual(snapshot["frames_dropped"], expected)
        self.assertEqual(snapshot["transport_records_invalid"], expected)
        self.assertEqual(snapshot["jpeg_payloads_invalid"], expected)
        self.assertEqual(snapshot["sequence_duplicate"], expected)
        self.assertEqual(snapshot["sequence_gap"], expected)
        self.assertEqual(snapshot["sequence_out_of_order"], expected)
        self.assertEqual(snapshot["source_errors"], expected)
        self.assertEqual(snapshot["source_reconnects"], expected)
        self.assertEqual(snapshot["drop_reasons"]["queue_overload"], expected)
        self.assertEqual(snapshot["queue_high_watermark"]["encoded"], 2)

    def test_metrics_writers_contend_for_the_same_lock(self) -> None:
        metrics = RuntimeMetrics()
        gated_lock = GatedSpyLock()
        metrics._lock = gated_lock  # type: ignore[assignment]
        first_done = Event()
        second_done = Event()

        def record_first() -> None:
            metrics.record_received()
            first_done.set()

        def record_second() -> None:
            metrics.record_received()
            second_done.set()

        first = Thread(target=record_first)
        second = Thread(target=record_second)
        first.start()
        try:
            self.assertTrue(
                gated_lock.first_writer_entered.wait(timeout=2),
                "first writer did not acquire the metrics lock",
            )
            second.start()
            self.assertTrue(
                gated_lock.second_writer_attempted.wait(timeout=2),
                "second writer did not attempt the same metrics lock",
            )
            self.assertFalse(first_done.is_set())
            self.assertFalse(second_done.is_set())

            gated_lock.allow_first_writer_release.set()
        finally:
            gated_lock.allow_first_writer_release.set()
            first.join(timeout=2)
            if second.ident is not None:
                second.join(timeout=2)

        self.assertFalse(first.is_alive(), "first writer did not finish")
        self.assertFalse(second.is_alive(), "second writer did not finish")
        self.assertTrue(first_done.is_set())
        self.assertTrue(second_done.is_set())
        self.assertEqual(metrics.snapshot()["frames_received"], 2)


class InterfaceTests(unittest.TestCase):
    def test_contracts_are_abstract(self) -> None:
        self.assertTrue(issubclass(FrameSource, ABC))
        self.assertTrue(issubclass(InferenceBackend, ABC))
        self.assertTrue(issubclass(OutputSink, ABC))
        with self.assertRaises(TypeError):
            FrameSource()  # type: ignore[abstract]

    def test_minimal_source_implementation_matches_contract(self) -> None:
        class EndSource(FrameSource):
            def start(self, config=None) -> None:
                self.started = True

            def next_frame(self, stop_event: Event) -> FrameEvent:
                return FrameEvent(FrameEventKind.END_OF_STREAM)

            def stop(self) -> None:
                self.started = False

            def health(self) -> SourceHealth:
                return SourceHealth.READY

        source = EndSource()
        source.start()
        self.assertEqual(source.next_frame(Event()).kind, FrameEventKind.END_OF_STREAM)
        self.assertEqual(source.health(), SourceHealth.READY)
