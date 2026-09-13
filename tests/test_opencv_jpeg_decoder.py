"""Tests for OpenCV JPEG decoding."""

from __future__ import annotations

import unittest
from unittest.mock import patch

import cv2
import numpy as np

from linux.task3_pipeline import DecodeError, EncodedFrame, OpenCvJpegDecoder

from tests._helpers import make_metadata


class OpenCvJpegDecoderTests(unittest.TestCase):
    @staticmethod
    def _jpeg_payload(image: np.ndarray) -> bytes:
        success, encoded = cv2.imencode(".jpg", image)
        if not success:
            raise AssertionError("test fixture JPEG encoding failed")
        return encoded.tobytes()

    @staticmethod
    def _frame(payload: bytes, **metadata_overrides: object) -> EncodedFrame:
        return EncodedFrame(
            metadata=make_metadata(
                payload_length=len(payload), **metadata_overrides
            ),
            payload=payload,
            acquired_monotonic_ns=101,
        )

    def test_valid_color_jpeg_decodes_to_bgr24_with_actual_layout(self) -> None:
        image = np.array(
            [
                [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
                [[10, 11, 12], [13, 14, 15], [16, 17, 18]],
            ],
            dtype=np.uint8,
        )
        frame = self._frame(self._jpeg_payload(image), wire_sequence=42)

        decoded = OpenCvJpegDecoder().decode(frame)

        self.assertEqual((decoded.width, decoded.height), (3, 2))
        self.assertEqual(decoded.pixel_format, "bgr24")
        self.assertEqual(decoded.row_stride, 9)
        self.assertEqual(len(decoded.pixels), 18)
        self.assertIsInstance(decoded.pixels, bytes)
        self.assertEqual(decoded.metadata.ingest_id, 7)
        self.assertEqual(decoded.metadata.wire_sequence, 42)
        self.assertGreaterEqual(decoded.decoded_monotonic_ns, 0)

    def test_grayscale_jpeg_decodes_to_three_channel_bgr24(self) -> None:
        grayscale = np.array([[0, 100], [150, 255]], dtype=np.uint8)
        frame = self._frame(self._jpeg_payload(grayscale), wire_sequence=None)

        decoded = OpenCvJpegDecoder().decode(frame)

        self.assertEqual((decoded.width, decoded.height), (2, 2))
        self.assertEqual(decoded.pixel_format, "bgr24")
        self.assertEqual(decoded.row_stride, 6)
        self.assertEqual(len(decoded.pixels), 12)
        self.assertIsNone(decoded.metadata.wire_sequence)

    def test_output_pixels_are_independent_immutable_bytes(self) -> None:
        frame = self._frame(self._jpeg_payload(np.zeros((2, 2, 3), dtype=np.uint8)))
        mutable_decoded = np.full((2, 2, 3), 7, dtype=np.uint8)

        with patch(
            "linux.task3_pipeline.opencv_jpeg_decoder.cv2.imdecode",
            return_value=mutable_decoded,
        ):
            decoded = OpenCvJpegDecoder().decode(frame)
        original_pixels = decoded.pixels
        mutable_decoded[:, :, :] = 99

        self.assertIsInstance(decoded.pixels, bytes)
        self.assertEqual(decoded.pixels, original_pixels)
        self.assertNotEqual(decoded.pixels, mutable_decoded.tobytes())

    def test_boundary_valid_but_undecodable_payload_raises_decode_error(self) -> None:
        frame = self._frame(b"\xff\xd8not an image\xff\xd9")

        with self.assertRaises(DecodeError) as raised:
            OpenCvJpegDecoder().decode(frame)

        self.assertEqual(raised.exception.code, "jpeg_decode_failed")

    def test_imdecode_none_raises_decode_error_without_payload_in_message(self) -> None:
        frame = self._frame(b"payload secret")

        with patch(
            "linux.task3_pipeline.opencv_jpeg_decoder.cv2.imdecode", return_value=None
        ), self.assertRaises(DecodeError) as raised:
            OpenCvJpegDecoder().decode(frame)

        self.assertEqual(raised.exception.code, "jpeg_decode_failed")
        self.assertNotIn("payload secret", raised.exception.message)

    def test_imdecode_cv2_error_raises_stable_decode_error(self) -> None:
        frame = self._frame(b"payload secret")

        with patch(
            "linux.task3_pipeline.opencv_jpeg_decoder.cv2.imdecode",
            side_effect=cv2.error("decoder failure"),
        ), self.assertRaises(DecodeError) as raised:
            OpenCvJpegDecoder().decode(frame)

        self.assertEqual(raised.exception.code, "jpeg_decode_cv2_error")
        self.assertNotIn("payload secret", raised.exception.message)

    def test_unexpected_decoded_images_are_rejected(self) -> None:
        frame = self._frame(self._jpeg_payload(np.zeros((2, 2, 3), dtype=np.uint8)))
        invalid_images = {
            "two_dimensional": np.zeros((2, 2), dtype=np.uint8),
            "four_channels": np.zeros((2, 2, 4), dtype=np.uint8),
            "wrong_dtype": np.zeros((2, 2, 3), dtype=np.float32),
            "empty_shape": np.zeros((0, 2, 3), dtype=np.uint8),
        }

        for description, image in invalid_images.items():
            with self.subTest(description=description), patch(
                "linux.task3_pipeline.opencv_jpeg_decoder.cv2.imdecode", return_value=image
            ), self.assertRaises(DecodeError) as raised:
                OpenCvJpegDecoder().decode(frame)
            self.assertEqual(raised.exception.code, "jpeg_decode_invalid_image")

    def test_input_frame_is_unchanged_after_success_and_failure(self) -> None:
        valid_frame = self._frame(self._jpeg_payload(np.zeros((2, 2, 3), dtype=np.uint8)))
        invalid_frame = self._frame(b"\xff\xd8broken\xff\xd9", wire_sequence=99)
        for frame, should_succeed in ((valid_frame, True), (invalid_frame, False)):
            with self.subTest(should_succeed=should_succeed):
                original_payload = frame.payload
                original_metadata = frame.metadata
                if should_succeed:
                    OpenCvJpegDecoder().decode(frame)
                else:
                    with self.assertRaises(DecodeError):
                        OpenCvJpegDecoder().decode(frame)
                self.assertIs(frame.metadata, original_metadata)
                self.assertEqual(frame.payload, original_payload)
                self.assertEqual(frame.metadata.payload_length, len(original_payload))
