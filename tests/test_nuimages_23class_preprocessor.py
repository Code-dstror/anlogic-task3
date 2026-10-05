"""Regression checks for the named 23-class input and optional A/B fixtures."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import unittest

import cv2
import numpy as np

from linux.task3_pipeline import (
    DecodedFrame,
    FrameMetadata,
    ModelInputSpec,
    PreprocessProfile,
    ResizeRoundingStrategy,
)
from linux.task3_pipeline.letterbox_preprocessor import LetterboxPreprocessor


_AB_DIRECTORY = "nuimages_cam_front_23class_preprocess_ab_val_20261004_02"
_ONNX_DIRECTORY = "nuimages_cam_front_23class_onnx_20261004_01"


def _frame(bgr: np.ndarray, name: str) -> DecodedFrame:
    height, width = bgr.shape[:2]
    pixels = np.ascontiguousarray(bgr).tobytes()
    return DecodedFrame(
        metadata=FrameMetadata(
            ingest_id=1,
            source_name=name,
            payload_length=len(pixels),
            received_monotonic_ns=1,
        ),
        pixels=pixels,
        width=width,
        height=height,
        pixel_format="bgr24",
        row_stride=width * 3,
        decoded_monotonic_ns=1,
    )


class Nuimages23ClassPreprocessorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.spec = ModelInputSpec(width=640, height=640)

    def test_named_profile_truncates_without_changing_default_half_up(self) -> None:
        frame = _frame(np.zeros((731, 1273, 3), dtype=np.uint8), "synthetic")
        legacy = LetterboxPreprocessor(self.spec).preprocess(frame)
        named_preprocessor = LetterboxPreprocessor(
            self.spec, profile=PreprocessProfile.NUIMAGES_CAM_FRONT_23CLASS_V1
        )
        named = named_preprocessor.preprocess(frame)

        self.assertIsNone(legacy.transform.profile)
        self.assertIs(legacy.transform.rounding_strategy, ResizeRoundingStrategy.HALF_UP)
        self.assertEqual((legacy.transform.scaled_width, legacy.transform.scaled_height), (640, 368))
        self.assertEqual((legacy.transform.pad_top, legacy.transform.pad_bottom), (136, 136))
        self.assertIs(named_preprocessor.profile, PreprocessProfile.NUIMAGES_CAM_FRONT_23CLASS_V1)
        self.assertIs(named.transform.profile, PreprocessProfile.NUIMAGES_CAM_FRONT_23CLASS_V1)
        self.assertIs(named.transform.rounding_strategy, ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO)
        self.assertEqual((named.transform.scaled_width, named.transform.scaled_height), (640, 367))
        self.assertEqual((named.transform.pad_top, named.transform.pad_bottom), (136, 137))
        self.assertEqual(named.data.shape, (1, 640, 640, 3))
        self.assertEqual(named.data.dtype, np.dtype("uint8"))
        self.assertIs(named.metadata, frame.metadata)

    def test_named_profile_requires_zero_padding_and_does_not_reuse_80_class_name(self) -> None:
        with self.assertRaisesRegex(ValueError, "padding_value=0"):
            LetterboxPreprocessor(
                ModelInputSpec(width=640, height=640, padding_value=114),
                profile=PreprocessProfile.NUIMAGES_CAM_FRONT_23CLASS_V1,
            )
        with self.assertRaisesRegex(ValueError, "profile must be"):
            LetterboxPreprocessor(
                self.spec, profile=PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1
            )

    def test_fixed_ab_reference_images_match_tensor_hashes(self) -> None:
        """Compare with fixed handoff hashes; never regenerate expected values."""
        root_setting = os.environ.get("ANLOGIC_23CLASS_HANDOFF_ROOT")
        if root_setting is None:
            self.skipTest("set ANLOGIC_23CLASS_HANDOFF_ROOT for external A/B fixtures")
        root = Path(root_setting)
        ab_root = root / _AB_DIRECTORY
        onnx_root = root / _ONNX_DIRECTORY
        reference_root = onnx_root / "reference_images"
        preflight = json.loads((ab_root / "preflight.json").read_text(encoding="utf-8"))
        selected = json.loads((onnx_root / "selected_images.json").read_text(encoding="utf-8"))
        cases = {item["case"]: item for item in preflight["cases"]}
        fixtures = [
            (item["scene"], reference_root / PureWindowsPath(item["image"]).name, item["sha256"])
            for item in selected
        ]
        crop = cases["noninteger_ratio_1273x731"]
        fixtures.append((crop["case"], ab_root / "noninteger_ratio_crop_1273x731.png", crop["sha256"]))
        self.assertEqual(len(fixtures), 4)
        preprocessor = LetterboxPreprocessor(
            self.spec, profile=PreprocessProfile.NUIMAGES_CAM_FRONT_23CLASS_V1
        )
        for scene, path, source_sha in fixtures:
            with self.subTest(scene=scene):
                raw = path.read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), source_sha)
                bgr = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
                self.assertIsNotNone(bgr)
                result = preprocessor.preprocess(_frame(bgr, scene))
                # ModelInput normalizes either accepted input to exact ImmutableTensor.
                canvas = result.data.to_numpy()[0]
                expected = cases[scene]["B"]["transform"]
                self.assertEqual(hashlib.sha256(canvas.tobytes()).hexdigest(), expected["rgb_canvas_sha256"])
                model_input = (
                    np.ascontiguousarray(canvas.transpose(2, 0, 1)[None], dtype=np.float32)
                    / np.float32(255.0)
                )
                self.assertEqual(
                    hashlib.sha256(model_input.tobytes()).hexdigest(),
                    expected["nchw_float32_sha256"],
                )
                self.assertEqual(
                    (result.transform.scaled_width, result.transform.scaled_height),
                    (expected["new_width"], expected["new_height"]),
                )
                self.assertEqual(
                    (
                        result.transform.pad_left,
                        result.transform.pad_top,
                        result.transform.pad_right,
                        result.transform.pad_bottom,
                    ),
                    (expected["left"], expected["top"], expected["right"], expected["bottom"]),
                )


if __name__ == "__main__":
    unittest.main()
