"""Unit tests for the Stage-A shared Python foundation."""

from __future__ import annotations

from abc import ABC
import os
from pathlib import Path
from threading import Barrier, Event, Lock, Thread
from tempfile import TemporaryDirectory
import time
import unittest

from linux.task3_pipeline import (
    ConfigurationError,
    DecodedFrame,
    Detection,
    DetectionResult,
    EncodedFrame,
    FrameEvent,
    FrameEventKind,
    FrameMetadata,
    FrameSource,
    InferenceBackend,
    JpegPayloadValidator,
    MockFileFrameSource,
    OutputSink,
    RuntimeMetrics,
    SourceError,
    SourceHealth,
    ValidationError,
)


def make_metadata(**overrides: object) -> FrameMetadata:
    values: dict[str, object] = {
        "ingest_id": 7,
        "source_name": "mock_file",
        "payload_length": 3,
        "received_monotonic_ns": 100,
        "wire_sequence": 42,
    }
    values.update(overrides)
    return FrameMetadata(**values)  # type: ignore[arg-type]


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


class JpegPayloadValidatorTests(unittest.TestCase):
    @staticmethod
    def _frame(payload: bytes, **metadata_overrides: object) -> EncodedFrame:
        return EncodedFrame(
            metadata=make_metadata(
                payload_length=len(payload), **metadata_overrides
            ),
            payload=payload,
            acquired_monotonic_ns=101,
        )

    def test_valid_jpeg_style_payload_returns_same_frame(self) -> None:
        frame = self._frame(b"\xff\xd8mock jpeg bytes\xff\xd9")

        self.assertIs(JpegPayloadValidator(1024).validate(frame), frame)

    def test_minimum_marker_only_payload_passes(self) -> None:
        frame = self._frame(b"\xff\xd8\xff\xd9")

        self.assertIs(JpegPayloadValidator(4).validate(frame), frame)

    def test_empty_payload_has_distinct_error_code(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(4).validate(self._frame(b""))

        self.assertEqual(raised.exception.code, "jpeg_payload_empty")

    def test_payload_shorter_than_both_markers_has_distinct_error_code(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(4).validate(self._frame(b"\xff\xd8\xff"))

        self.assertEqual(raised.exception.code, "jpeg_payload_too_short")

    def test_invalid_soi_has_distinct_error_code(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(16).validate(self._frame(b"bad\xff\xd9"))

        self.assertEqual(raised.exception.code, "jpeg_payload_invalid_soi")

    def test_invalid_final_eoi_has_distinct_error_code(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(16).validate(self._frame(b"\xff\xd8bad!"))

        self.assertEqual(raised.exception.code, "jpeg_payload_invalid_eoi")

    def test_payload_over_configured_maximum_has_distinct_error_code(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(4).validate(self._frame(b"\xff\xd8x\xff\xd9"))

        self.assertEqual(raised.exception.code, "jpeg_payload_too_long")

    def test_payload_equal_to_configured_maximum_passes(self) -> None:
        frame = self._frame(b"\xff\xd8xx\xff\xd9")

        self.assertIs(JpegPayloadValidator(len(frame.payload)).validate(frame), frame)

    def test_invalid_maximum_payload_length_configuration_is_rejected(self) -> None:
        for maximum in (-1, 0, 3, True, 4.0, "4"):
            with self.subTest(maximum=maximum), self.assertRaises(
                ConfigurationError
            ) as raised:
                JpegPayloadValidator(maximum)  # type: ignore[arg-type]
            self.assertEqual(raised.exception.code, "invalid_max_payload_length")

    def test_failed_validation_does_not_modify_frame_or_metadata(self) -> None:
        frame = self._frame(b"\xff\xd8missing final marker", wire_sequence=99)
        original_payload = frame.payload
        original_metadata = frame.metadata

        with self.assertRaises(ValidationError):
            JpegPayloadValidator(1024).validate(frame)

        self.assertIs(frame.metadata, original_metadata)
        self.assertEqual(frame.payload, original_payload)
        self.assertEqual(frame.metadata.ingest_id, 7)
        self.assertEqual(frame.metadata.wire_sequence, 99)
        self.assertEqual(frame.metadata.payload_length, len(original_payload))

    def test_wire_sequence_does_not_affect_jpeg_validation(self) -> None:
        validator = JpegPayloadValidator(16)
        for wire_sequence in (None, 42):
            with self.subTest(wire_sequence=wire_sequence):
                frame = self._frame(b"\xff\xd8ok\xff\xd9", wire_sequence=wire_sequence)
                self.assertIs(validator.validate(frame), frame)

    def test_internal_eoi_marker_does_not_replace_required_final_eoi(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(16).validate(self._frame(b"\xff\xd8\xff\xd9tail"))

        self.assertEqual(raised.exception.code, "jpeg_payload_invalid_eoi")


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


if __name__ == "__main__":
    unittest.main()
