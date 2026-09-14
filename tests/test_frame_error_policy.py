"""Tests for fail-closed disposition of one-frame processing errors."""

from __future__ import annotations

import unittest

from linux.task3_pipeline.errors import (
    ConfigurationError,
    DecodeError,
    PipelineError,
    SourceError,
    ValidationError,
)
from linux.task3_pipeline.frame_error_policy import (
    FrameErrorDisposition,
    classify_frame_error,
)
from linux.task3_pipeline.jpeg_payload_validator import JpegPayloadValidator
from linux.task3_pipeline.models import EncodedFrame
from linux.task3_pipeline.opencv_jpeg_decoder import OpenCvJpegDecoder
from linux.task3_pipeline.sequence_tracker import SequenceTracker

from tests._helpers import make_metadata


def make_frame(payload: bytes) -> EncodedFrame:
    """Build an encoded frame with metadata matching its payload length."""

    return EncodedFrame(make_metadata(payload_length=len(payload)), payload, 101)


class _DerivedDecodeError(DecodeError):
    """An unreviewed decoder-error subtype used to verify exact type matching."""


class _DerivedValidationError(ValidationError):
    """An unreviewed validation-error subtype used to verify exact type matching."""


class FrameErrorPolicyTests(unittest.TestCase):
    def test_all_known_jpeg_payload_errors_continue(self) -> None:
        for code in (
            "jpeg_payload_empty",
            "jpeg_payload_too_short",
            "jpeg_payload_too_long",
            "jpeg_payload_invalid_soi",
            "jpeg_payload_invalid_eoi",
        ):
            with self.subTest(code=code):
                error = ValidationError(
                    "invalid payload", stage="jpeg_payload_validation", code=code
                )
                self.assertEqual(
                    classify_frame_error(error),
                    FrameErrorDisposition.CONTINUE_NEXT_FRAME,
                )

    def test_known_decode_failure_continues(self) -> None:
        error = DecodeError("undecodable", stage="jpeg_decode", code="jpeg_decode_failed")

        self.assertEqual(
            classify_frame_error(error), FrameErrorDisposition.CONTINUE_NEXT_FRAME
        )

    def test_sequence_validation_error_propagates(self) -> None:
        error = ValidationError(
            "invalid sequence", stage="sequence_tracking", code="invalid_wire_sequence"
        )

        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_decoder_runtime_and_contract_errors_propagate(self) -> None:
        for code in ("jpeg_decode_cv2_error", "jpeg_decode_invalid_image"):
            with self.subTest(code=code):
                error = DecodeError("decoder error", stage="jpeg_decode", code=code)
                self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_source_configuration_and_base_errors_propagate(self) -> None:
        errors = (
            SourceError("source", stage="source", code="source_error"),
            ConfigurationError("configuration", stage="configuration", code="bad_config"),
            PipelineError("pipeline", stage="pipeline", code="unknown"),
        )

        for error in errors:
            with self.subTest(error_type=type(error).__name__):
                self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_unknown_code_propagates(self) -> None:
        error = ValidationError(
            "future payload error",
            stage="jpeg_payload_validation",
            code="jpeg_payload_future_error",
        )

        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_allowlisted_code_in_wrong_stage_propagates(self) -> None:
        error = ValidationError(
            "wrong stage", stage="sequence_tracking", code="jpeg_payload_invalid_eoi"
        )

        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_allowlisted_stage_and_code_with_wrong_error_class_propagates(self) -> None:
        error = DecodeError(
            "wrong class", stage="jpeg_payload_validation", code="jpeg_payload_invalid_eoi"
        )

        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_decoder_and_payload_allowlists_reject_wrong_exact_error_types(self) -> None:
        errors = (
            ValidationError(
                "wrong decoder class", stage="jpeg_decode", code="jpeg_decode_failed"
            ),
            _DerivedDecodeError(
                "derived decoder error", stage="jpeg_decode", code="jpeg_decode_failed"
            ),
            _DerivedValidationError(
                "derived validation error",
                stage="jpeg_payload_validation",
                code="jpeg_payload_invalid_eoi",
            ),
        )

        for error in errors:
            with self.subTest(error_type=type(error).__name__):
                self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_allowlisted_error_continues_despite_false_recoverable(self) -> None:
        error = ValidationError(
            "invalid payload",
            stage="jpeg_payload_validation",
            code="jpeg_payload_invalid_eoi",
            recoverable=False,
        )

        self.assertEqual(
            classify_frame_error(error), FrameErrorDisposition.CONTINUE_NEXT_FRAME
        )

    def test_non_allowlisted_error_propagates_despite_true_recoverable(self) -> None:
        error = DecodeError(
            "runtime error",
            stage="jpeg_decode",
            code="jpeg_decode_cv2_error",
            recoverable=True,
        )

        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_classification_does_not_modify_public_error_fields(self) -> None:
        cause = RuntimeError("cause")
        error = ValidationError(
            "invalid payload",
            stage="jpeg_payload_validation",
            code="jpeg_payload_invalid_eoi",
            recoverable=False,
            cause=cause,
        )
        before = (error.message, error.stage, error.code, error.recoverable, error.cause)

        classify_frame_error(error)

        self.assertEqual(
            (error.message, error.stage, error.code, error.recoverable, error.cause), before
        )

    def test_real_jpeg_validator_error_continues(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            JpegPayloadValidator(4).validate(make_frame(b""))

        self.assertEqual(
            classify_frame_error(raised.exception),
            FrameErrorDisposition.CONTINUE_NEXT_FRAME,
        )

    def test_real_sequence_tracker_error_propagates(self) -> None:
        with self.assertRaises(ValidationError) as raised:
            SequenceTracker().observe(True)

        self.assertEqual(classify_frame_error(raised.exception), FrameErrorDisposition.PROPAGATE)

    def test_real_undecodable_jpeg_error_continues(self) -> None:
        with self.assertRaises(DecodeError) as raised:
            OpenCvJpegDecoder().decode(make_frame(b"\xff\xd8not an image\xff\xd9"))

        self.assertEqual(raised.exception.code, "jpeg_decode_failed")
        self.assertEqual(
            classify_frame_error(raised.exception),
            FrameErrorDisposition.CONTINUE_NEXT_FRAME,
        )
