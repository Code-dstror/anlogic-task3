from __future__ import annotations

import gc
import unittest

import numpy as np

from linux.task3_pipeline import (
    DetectionResult,
    ImmutableTensor,
    InferenceBackend,
    ModelInput,
    ModelInputSpec,
    PreprocessTransform,
)
from linux.task3_pipeline.models import FrameMetadata


class ModelInputContractTests(unittest.TestCase):
    def test_yolov5_baseline_is_explicit_and_size_is_configurable(self) -> None:
        baseline = ModelInputSpec(width=640, height=640)

        self.assertEqual(baseline.batch_size, 1)
        self.assertEqual(baseline.shape, (1, 640, 640, 3))
        self.assertEqual(baseline.layout, "NHWC")
        self.assertEqual(baseline.dtype, np.dtype("uint8"))
        self.assertEqual(baseline.color_format, "RGB")
        self.assertEqual(baseline.padding_value, 0)

        alternate = ModelInputSpec(width=320, height=512, padding_value=114)
        self.assertEqual(alternate.shape, (1, 512, 320, 3))
        self.assertEqual(alternate.padding_value, 114)

    def test_transform_records_source_target_scale_and_each_padding_side(self) -> None:
        transform = PreprocessTransform(
            source_width=1280,
            source_height=720,
            model_width=640,
            model_height=640,
            scale=0.5,
            pad_left=0,
            pad_top=140,
            pad_right=0,
            pad_bottom=140,
        )

        self.assertEqual(transform.source_width, 1280)
        self.assertEqual(transform.source_height, 720)
        self.assertEqual(transform.model_width, 640)
        self.assertEqual(transform.model_height, 640)
        self.assertEqual(transform.ratio, 0.5)
        self.assertEqual(
            (transform.pad_left, transform.pad_right, transform.pad_top, transform.pad_bottom),
            (0, 0, 140, 140),
        )
        self.assertEqual((transform.scaled_width, transform.scaled_height), (640, 360))

    def test_transform_records_vertical_letterbox(self) -> None:
        transform = PreprocessTransform(720, 1280, 640, 640, 0.5, 140, 0, 140, 0)

        self.assertEqual((transform.scaled_width, transform.scaled_height), (360, 640))
        self.assertEqual((transform.pad_left, transform.pad_right), (140, 140))

    def test_transform_rejects_invalid_scale_dimension_and_padding_types(self) -> None:
        valid = dict(
            source_width=1280,
            source_height=720,
            model_width=640,
            model_height=640,
            scale=0.5,
            pad_left=0,
            pad_top=140,
            pad_right=0,
            pad_bottom=140,
        )
        for scale in (float("nan"), float("inf"), float("-inf"), 0, -0.5):
            with self.subTest(scale=scale), self.assertRaises(ValueError):
                PreprocessTransform(**(valid | {"scale": scale}))
        for scale in (True, "0.5"):
            with self.subTest(scale=scale), self.assertRaises(TypeError):
                PreprocessTransform(**(valid | {"scale": scale}))
        for name in ("source_width", "source_height", "model_width", "model_height"):
            for value in (True, np.bool_(True), 640.0, "640"):
                with self.subTest(name=name, value=value), self.assertRaises(TypeError):
                    PreprocessTransform(**(valid | {name: value}))
        for name in ("pad_left", "pad_top", "pad_right", "pad_bottom"):
            for value in (True, np.bool_(True), 1.0, "1"):
                with self.subTest(name=name, value=value), self.assertRaises(TypeError):
                    PreprocessTransform(**(valid | {name: value}))

    def test_transform_uses_nearest_half_up_scaled_dimension_rounding(self) -> None:
        transform = PreprocessTransform(3, 2, 2, 1, 0.5, 0, 0, 0, 0)

        self.assertEqual(transform.scaled_width, 2)
        self.assertEqual(transform.scaled_height, 1)

    def test_transform_rejects_inconsistent_horizontal_or_vertical_geometry(self) -> None:
        with self.assertRaises(ValueError):
            PreprocessTransform(1280, 720, 641, 640, 0.5, 0, 140, 0, 140)
        with self.assertRaises(ValueError):
            PreprocessTransform(1280, 720, 640, 641, 0.5, 0, 140, 0, 140)

    def test_transform_rejects_scaled_dimensions_that_round_to_zero(self) -> None:
        for source_width, source_height in ((1, 1), (1, 10), (10, 1)):
            with self.subTest(source_width=source_width, source_height=source_height):
                with self.assertRaisesRegex(ValueError, "round to at least 1"):
                    PreprocessTransform(
                        source_width, source_height, 1, 1, 0.01, 0, 0, 0, 0
                    )

    def test_transform_accepts_smallest_one_by_one_resize(self) -> None:
        transform = PreprocessTransform(1, 1, 1, 1, 0.5, 0, 0, 0, 0)
        self.assertEqual((transform.scaled_width, transform.scaled_height), (1, 1))

    def test_input_owns_contiguous_read_only_tensor_for_its_lifetime(self) -> None:
        spec = ModelInputSpec(width=640, height=640)
        source = np.zeros((1, 640, 1280, 3), dtype=np.uint8)[:, :, :640, :]
        self.assertFalse(source.flags.c_contiguous)
        result = ModelInput(
            self._metadata(), source, spec, self._transform_for(spec)
        )

        source[:, :, :, :] = 99
        del source
        gc.collect()

        self.assertEqual(result.data[0, 0, 0, 0], 0)
        self.assertIsInstance(result.data, ImmutableTensor)
        self.assertTrue(result.data.flags.c_contiguous)
        self.assertFalse(result.data.flags.writeable)
        with self.assertRaises(TypeError):
            result.data[0, 0, 0, 0] = 1
        with self.assertRaises(AttributeError):
            result.data.flags.writeable = True
        with self.assertRaises(ValueError):
            result.data.setflags(write=True)
        for attribute, value in (
            ("shape", (1, 640 * 640 * 3)),
            ("dtype", np.dtype("float32")),
            ("strides", (1, 1, 1, 1)),
        ):
            with self.subTest(attribute=attribute), self.assertRaises(AttributeError):
                setattr(result.data, attribute, value)

        temporary = result.data.to_numpy()
        temporary.shape = (1, -1)
        self.assertEqual(result.data.shape, spec.shape)
        self.assertEqual(result.data.dtype, spec.dtype)
        self.assertEqual(result.data.strides, (640 * 640 * 3, 640 * 3, 3, 1))
        mutable_copy = result.data.to_numpy(copy=True)
        mutable_copy[0, 0] = 42
        self.assertEqual(result.data[0, 0, 0, 0], 0)

    def test_input_preserves_complete_metadata_object(self) -> None:
        metadata = self._metadata()
        spec = ModelInputSpec(width=640, height=640)
        result = ModelInput(
            metadata,
            np.zeros(spec.shape, dtype=np.uint8),
            spec,
            self._transform_for(spec),
        )

        self.assertIs(result.metadata, metadata)
        self.assertEqual(result.metadata.source_name, "decoded-camera")
        self.assertEqual(result.metadata.received_monotonic_ns, 101)
        self.assertEqual(result.metadata.source_timestamp, 202)
        self.assertEqual(result.metadata.timestamp_domain, "sensor_clock")
        self.assertEqual(result.metadata.wire_sequence, 303)

    def test_input_rejects_wrong_shape_dtype_or_target(self) -> None:
        spec = ModelInputSpec(width=640, height=640)
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros((640, 640, 3), dtype=np.uint8),
                spec,
                self._transform_for(spec),
            )
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros(spec.shape, dtype=np.float32),
                spec,
                self._transform_for(spec),
            )
        with self.assertRaises(ValueError):
            ModelInput(
                self._metadata(),
                np.zeros(spec.shape, dtype=np.uint8),
                spec,
                PreprocessTransform(1280, 720, 320, 640, 0.5, 0, 140, 0, 140),
            )

    def test_spec_rejects_unsupported_batch_and_non_integer_dimensions(self) -> None:
        with self.assertRaisesRegex(ValueError, "batch_size=1"):
            ModelInputSpec(width=640, height=640, batch_size=2)
        for name in ("width", "height", "batch_size", "channels"):
            for value in (True, np.bool_(True), 640.0, "640"):
                with self.subTest(name=name, value=value), self.assertRaises(TypeError):
                    ModelInputSpec(**({"width": 640, "height": 640} | {name: value}))

    def test_spec_validates_image_dtype_and_padding_value_range(self) -> None:
        for dtype in (np.dtype("bool"), np.dtype("complex64"), np.dtype("O"), np.dtype("U8")):
            with self.subTest(dtype=dtype), self.assertRaises(ValueError):
                ModelInputSpec(width=640, height=640, dtype=dtype)
        for value in (300, -1, 1.5, float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises((TypeError, ValueError)):
                ModelInputSpec(width=640, height=640, dtype=np.uint8, padding_value=value)
        for value in (float("nan"), float("inf"), float("-inf"), 1e100):
            with self.subTest(value=value), self.assertRaises(ValueError):
                ModelInputSpec(width=640, height=640, dtype=np.float32, padding_value=value)
        floating = ModelInputSpec(width=640, height=640, dtype=np.float32, padding_value=1.5)
        self.assertEqual(floating.padding_value, 1.5)

    def test_spec_validates_longdouble_padding_without_python_float_narrowing(self) -> None:
        large_value = np.longdouble("1e400")
        longdouble_spec = ModelInputSpec(
            width=640, height=640, dtype=np.longdouble, padding_value=large_value
        )
        self.assertEqual(longdouble_spec.padding_value, large_value)
        with self.assertRaises(ValueError):
            ModelInputSpec(width=640, height=640, dtype=np.float64, padding_value=large_value)

    def test_structured_transform_flows_from_model_input_to_detection_result(self) -> None:
        spec = ModelInputSpec(width=640, height=640)
        model_input = ModelInput(
            self._metadata(), np.zeros(spec.shape, dtype=spec.dtype), spec, self._transform_for(spec)
        )

        class ContractBackend(InferenceBackend):
            def load(self, model_config: object) -> None:
                pass

            def infer(self, input_value: ModelInput) -> DetectionResult:
                return DetectionResult(
                    ingest_id=input_value.metadata.ingest_id,
                    inference_started_monotonic_ns=1,
                    inference_finished_monotonic_ns=2,
                    preprocess_transform=input_value.transform,
                )

            def close(self) -> None:
                pass

        result = ContractBackend().infer(model_input)
        self.assertIs(result.preprocess_transform, model_input.transform)

    def test_detection_result_normalizes_supported_transform_representations(self) -> None:
        transform = self._transform_for(ModelInputSpec(width=640, height=640))
        valid_mapping = {
            "source_width": transform.source_width,
            "source_height": transform.source_height,
            "model_width": transform.model_width,
            "model_height": transform.model_height,
            "scale": transform.scale,
            "pad_left": transform.pad_left,
            "pad_top": transform.pad_top,
            "pad_right": transform.pad_right,
            "pad_bottom": transform.pad_bottom,
        }
        for value, expected in ((None, None), ({}, None), (transform, transform)):
            with self.subTest(value=value):
                self.assertIs(
                    DetectionResult(0, 1, 2, preprocess_transform=value).preprocess_transform,
                    expected,
                )
        converted = DetectionResult(0, 1, 2, preprocess_transform=valid_mapping)
        self.assertIsInstance(converted.preprocess_transform, PreprocessTransform)
        self.assertEqual(converted.preprocess_transform, transform)

    def test_detection_result_rejects_invalid_transform_representations(self) -> None:
        valid_mapping = {
            "source_width": 1280,
            "source_height": 720,
            "model_width": 640,
            "model_height": 640,
            "scale": 0.5,
            "pad_left": 0,
            "pad_top": 140,
            "pad_right": 0,
            "pad_bottom": 140,
        }
        with self.assertRaisesRegex(ValueError, "missing fields"):
            DetectionResult(0, 1, 2, preprocess_transform={"source_width": 1280})
        with self.assertRaisesRegex(ValueError, "unknown fields"):
            DetectionResult(0, 1, 2, preprocess_transform=valid_mapping | {"extra": 1})
        with self.assertRaisesRegex(TypeError, "must be None"):
            DetectionResult(0, 1, 2, preprocess_transform=[valid_mapping])  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "horizontal padding"):
            DetectionResult(
                0, 1, 2, preprocess_transform=valid_mapping | {"model_width": 641}
            )

    @staticmethod
    def _transform_for(spec: ModelInputSpec) -> PreprocessTransform:
        return PreprocessTransform(1280, 720, spec.width, spec.height, 0.5, 0, 140, 0, 140)

    @staticmethod
    def _metadata() -> FrameMetadata:
        return FrameMetadata(
            ingest_id=7,
            source_name="decoded-camera",
            payload_length=3,
            received_monotonic_ns=101,
            frame_id="frame-7",
            wire_sequence=303,
            source_timestamp=202,
            timestamp_domain="sensor_clock",
            transport="mock",
            encoding="jpeg",
            declared_width=1280,
            declared_height=720,
            integrity={"crc": "verified"},
            protocol_version=1,
            extensions={"origin": "contract-test"},
        )
