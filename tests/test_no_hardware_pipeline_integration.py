"""End-to-end tests for the hardware-independent frame lifecycle pipeline."""

from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event
import unittest

import cv2
import numpy as np

from linux.task3_pipeline.errors import ConfigurationError, ValidationError
from linux.task3_pipeline.frame_lifecycle_runner import (
    FrameLifecycleRunner,
    FrameStepOutcomeKind,
)
from linux.task3_pipeline.jpeg_payload_validator import JpegPayloadValidator
from linux.task3_pipeline.mock_corrupt_frame_source import MockCorruptFrameSource
from linux.task3_pipeline.mock_file_source import MockFileFrameSource
from linux.task3_pipeline.models import (
    DecodedFrame,
    EncodedFrame,
    FrameEventKind,
    RuntimeMetrics,
)
from linux.task3_pipeline.opencv_jpeg_decoder import OpenCvJpegDecoder
from linux.task3_pipeline.sequence_tracker import SequenceTracker


class RecordingOpenCvJpegDecoder:
    """Record decode inputs while delegating unchanged to real OpenCV decoding."""

    def __init__(self) -> None:
        self.received_frames: list[EncodedFrame] = []
        self._decoder = OpenCvJpegDecoder()

    def decode(self, frame: EncodedFrame) -> DecodedFrame:
        self.received_frames.append(frame)
        return self._decoder.decode(frame)


class NoHardwarePipelineIntegrationTests(unittest.TestCase):
    @staticmethod
    def _write_jpeg(path: Path, image: np.ndarray) -> None:
        success, encoded = cv2.imencode(".jpg", image)
        if not success:
            raise AssertionError("test fixture JPEG encoding failed")
        path.write_bytes(encoded.tobytes())

    def _make_jpeg_directory(self, directory: Path) -> tuple[tuple[int, int], tuple[int, int]]:
        first = np.array(
            [
                [[10, 20, 30], [40, 50, 60], [70, 80, 90]],
                [[100, 110, 120], [130, 140, 150], [160, 170, 180]],
            ],
            dtype=np.uint8,
        )
        second = np.array(
            [
                [[5, 15, 25], [35, 45, 55]],
                [[65, 75, 85], [95, 105, 115]],
                [[125, 135, 145], [155, 165, 175]],
            ],
            dtype=np.uint8,
        )
        self._write_jpeg(directory / "01-first.jpg", first)
        self._write_jpeg(directory / "02-second.jpg", second)
        return (3, 2), (2, 3)

    def _assert_snapshot(
        self,
        metrics: RuntimeMetrics,
        *,
        frames_received: int = 0,
        frames_delivered: int = 0,
        frames_dropped: int = 0,
        jpeg_payloads_invalid: int = 0,
        source_errors: int = 0,
        drop_reasons: dict[str, int] | None = None,
        jpeg_invalid_reasons: dict[str, int] | None = None,
    ) -> None:
        """Assert every current RuntimeMetrics.snapshot() field exactly."""

        self.assertEqual(
            metrics.snapshot(),
            {
                "frames_received": frames_received,
                "frames_delivered": frames_delivered,
                "frames_dropped": frames_dropped,
                "transport_records_invalid": 0,
                "jpeg_payloads_invalid": jpeg_payloads_invalid,
                "sequence_duplicate": 0,
                "sequence_gap": 0,
                "sequence_out_of_order": 0,
                "source_reconnects": 0,
                "source_errors": source_errors,
                "drop_reasons": {} if drop_reasons is None else drop_reasons,
                "transport_invalid_reasons": {},
                "jpeg_invalid_reasons": (
                    {} if jpeg_invalid_reasons is None else jpeg_invalid_reasons
                ),
                "queue_depth": {},
                "queue_high_watermark": {},
            },
        )

    def _assert_decoded(
        self, decoded: DecodedFrame | None, dimensions: tuple[int, int], ingest_id: int
    ) -> None:
        self.assertIsNotNone(decoded)
        assert decoded is not None
        width, height = dimensions
        self.assertEqual(decoded.pixel_format, "bgr24")
        self.assertEqual((decoded.width, decoded.height), (width, height))
        self.assertEqual(decoded.row_stride, width * 3)
        self.assertIsInstance(decoded.pixels, bytes)
        self.assertEqual(len(decoded.pixels), width * height * 3)
        self.assertEqual(decoded.metadata.ingest_id, ingest_id)
        self.assertEqual(decoded.metadata.source_name, "mock_file")
        self.assertIsNone(decoded.metadata.wire_sequence)

    def _assert_not_running(self, runner: FrameLifecycleRunner) -> None:
        with self.assertRaises(ConfigurationError) as raised:
            runner.step(Event())
        self.assertEqual(raised.exception.stage, "frame_lifecycle_runner")
        self.assertEqual(raised.exception.code, "runner_not_running")

    def test_real_components_deliver_two_jpegs_then_end_of_stream(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            dimensions = self._make_jpeg_directory(Path(temporary_directory))
            metrics = RuntimeMetrics()
            runner = FrameLifecycleRunner(
                MockFileFrameSource(directory=temporary_directory),
                JpegPayloadValidator(1024 * 1024),
                OpenCvJpegDecoder(),
                SequenceTracker(),
                metrics,
            )

            runner.start()
            first = runner.step(Event())
            self.assertEqual(first.kind, FrameStepOutcomeKind.DELIVERED)
            self.assertIsNone(first.event)
            self.assertIsNone(first.error)
            self._assert_decoded(first.decoded_frame, dimensions[0], ingest_id=0)

            second = runner.step(Event())
            self.assertEqual(second.kind, FrameStepOutcomeKind.DELIVERED)
            self.assertIsNone(second.event)
            self.assertIsNone(second.error)
            self._assert_decoded(second.decoded_frame, dimensions[1], ingest_id=1)

            end_of_stream = runner.step(Event())
            self.assertEqual(end_of_stream.kind, FrameStepOutcomeKind.EVENT)
            self.assertIsNotNone(end_of_stream.event)
            self.assertEqual(end_of_stream.event.kind, FrameEventKind.END_OF_STREAM)
            self.assertIsNone(end_of_stream.decoded_frame)
            self.assertIsNone(end_of_stream.error)
            self._assert_snapshot(metrics, frames_received=2, frames_delivered=2)
            self._assert_not_running(runner)
            self._assert_snapshot(metrics, frames_received=2, frames_delivered=2)
            runner.stop()
            self._assert_snapshot(metrics, frames_received=2, frames_delivered=2)

    def test_real_tail_corruption_drops_once_then_delivers_next_jpeg(self) -> None:
        with TemporaryDirectory() as temporary_directory:
            dimensions = self._make_jpeg_directory(Path(temporary_directory))
            first_payload = (Path(temporary_directory) / "01-first.jpg").read_bytes()
            self.assertGreater(len(first_payload), 2)
            self.assertEqual(first_payload[-2:], b"\xff\xd9")
            source = MockCorruptFrameSource(
                MockFileFrameSource(directory=temporary_directory),
                target_frame_index=0,
                tail_bytes_to_drop=2,
            )
            metrics = RuntimeMetrics()
            decoder = RecordingOpenCvJpegDecoder()
            runner = FrameLifecycleRunner(
                source,
                JpegPayloadValidator(1024 * 1024),
                decoder,
                SequenceTracker(),
                metrics,
            )

            runner.start()
            dropped = runner.step(Event())
            self.assertEqual(dropped.kind, FrameStepOutcomeKind.DROPPED_FRAME)
            self.assertIsNone(dropped.decoded_frame)
            self.assertIsNone(dropped.event)
            self.assertIsInstance(dropped.error, ValidationError)
            assert dropped.error is not None
            self.assertEqual(dropped.error.stage, "jpeg_payload_validation")
            self.assertEqual(dropped.error.code, "jpeg_payload_invalid_eoi")
            self.assertEqual(decoder.received_frames, [])
            self._assert_snapshot(
                metrics,
                frames_received=1,
                frames_dropped=1,
                jpeg_payloads_invalid=1,
                drop_reasons={"jpeg_validation:jpeg_payload_invalid_eoi": 1},
                jpeg_invalid_reasons={"jpeg_payload_invalid_eoi": 1},
            )

            delivered = runner.step(Event())
            self.assertEqual(delivered.kind, FrameStepOutcomeKind.DELIVERED)
            self.assertIsNone(delivered.event)
            self.assertIsNone(delivered.error)
            self._assert_decoded(delivered.decoded_frame, dimensions[1], ingest_id=1)
            self.assertEqual(len(decoder.received_frames), 1)
            self.assertEqual(decoder.received_frames[0].metadata.ingest_id, 1)
            assert delivered.decoded_frame is not None
            self.assertIs(decoder.received_frames[0].metadata, delivered.decoded_frame.metadata)
            self._assert_snapshot(
                metrics,
                frames_received=2,
                frames_delivered=1,
                frames_dropped=1,
                jpeg_payloads_invalid=1,
                drop_reasons={"jpeg_validation:jpeg_payload_invalid_eoi": 1},
                jpeg_invalid_reasons={"jpeg_payload_invalid_eoi": 1},
            )

            end_of_stream = runner.step(Event())
            self.assertEqual(end_of_stream.kind, FrameStepOutcomeKind.EVENT)
            self.assertIsNotNone(end_of_stream.event)
            self.assertEqual(end_of_stream.event.kind, FrameEventKind.END_OF_STREAM)
            self.assertIsNone(end_of_stream.decoded_frame)
            self.assertIsNone(end_of_stream.error)
            self._assert_snapshot(
                metrics,
                frames_received=2,
                frames_delivered=1,
                frames_dropped=1,
                jpeg_payloads_invalid=1,
                drop_reasons={"jpeg_validation:jpeg_payload_invalid_eoi": 1},
                jpeg_invalid_reasons={"jpeg_payload_invalid_eoi": 1},
            )
            self._assert_not_running(runner)
            self._assert_snapshot(
                metrics,
                frames_received=2,
                frames_delivered=1,
                frames_dropped=1,
                jpeg_payloads_invalid=1,
                drop_reasons={"jpeg_validation:jpeg_payload_invalid_eoi": 1},
                jpeg_invalid_reasons={"jpeg_payload_invalid_eoi": 1},
            )
            runner.stop()
            self._assert_snapshot(
                metrics,
                frames_received=2,
                frames_delivered=1,
                frames_dropped=1,
                jpeg_payloads_invalid=1,
                drop_reasons={"jpeg_validation:jpeg_payload_invalid_eoi": 1},
                jpeg_invalid_reasons={"jpeg_payload_invalid_eoi": 1},
            )
