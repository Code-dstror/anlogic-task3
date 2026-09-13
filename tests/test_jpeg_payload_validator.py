"""Tests for JPEG payload boundary validation."""

from __future__ import annotations

import unittest

from linux.task3_pipeline import (
    ConfigurationError,
    EncodedFrame,
    JpegPayloadValidator,
    ValidationError,
)

from tests._helpers import make_metadata


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
