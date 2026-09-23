"""Contract tests for structured model-preprocessing failures."""

from __future__ import annotations

import unittest

from linux.task3_pipeline import PreprocessError
from linux.task3_pipeline.errors import (
    DecodeError,
    InferenceError,
    PipelineError,
    ValidationError,
)
from linux.task3_pipeline.frame_error_policy import (
    FrameErrorDisposition,
    classify_frame_error,
)


class PreprocessErrorContractTests(unittest.TestCase):
    def test_public_type_is_a_distinct_pipeline_error(self) -> None:
        self.assertTrue(issubclass(PreprocessError, PipelineError))
        for other_type in (ValidationError, DecodeError, InferenceError):
            self.assertFalse(issubclass(PreprocessError, other_type))

    def test_all_stable_codes_use_the_fixed_stage_and_fail_closed(self) -> None:
        codes = (
            "preprocess_invalid_frame_type",
            "preprocess_unsupported_pixel_format",
            "preprocess_invalid_dimensions",
            "preprocess_invalid_row_stride",
            "preprocess_invalid_pixel_buffer",
            "preprocess_pixel_buffer_too_small",
            "preprocess_resource_limit_exceeded",
            "preprocess_color_conversion_failed",
            "preprocess_resize_failed",
            "preprocess_padding_failed",
            "preprocess_invalid_output",
        )
        for code in codes:
            with self.subTest(code=code):
                error = PreprocessError("diagnostic", code=code)
                self.assertEqual(error.stage, "model_preprocess")
                self.assertEqual(error.code, code)
                self.assertEqual(error.message, "diagnostic")
                self.assertEqual(str(error), "diagnostic")
                self.assertFalse(error.recoverable)
                self.assertIsNone(error.cause)
                self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_explicit_cause_and_recoverable_follow_pipeline_error_contract(self) -> None:
        cause = ValueError("source detail")
        error = PreprocessError(
            "conversion failed",
            code="preprocess_color_conversion_failed",
            recoverable=True,
            cause=cause,
        )
        self.assertIs(error.cause, cause)
        self.assertTrue(error.recoverable)
        self.assertEqual(error.args, ("conversion failed",))
        self.assertEqual(classify_frame_error(error), FrameErrorDisposition.PROPAGATE)

    def test_existing_error_construction_is_unchanged(self) -> None:
        for error_type in (ValidationError, DecodeError, InferenceError):
            with self.subTest(error_type=error_type):
                error = error_type("existing", stage="existing_stage", code="existing_code")
                self.assertEqual(error.stage, "existing_stage")
                self.assertEqual(error.code, "existing_code")
                self.assertFalse(error.recoverable)


if __name__ == "__main__":
    unittest.main()
