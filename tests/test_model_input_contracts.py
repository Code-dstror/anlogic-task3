from __future__ import annotations

import gc
from sys import maxsize
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

    def test_spec_requires_a_non_empty_string_color_format(self) -> None:
        self.assertEqual(ModelInputSpec(1, 1, color_format="RGB").color_format, "RGB")
        for value in ("", "   ", 3, None, True):
            with self.subTest(value=value), self.assertRaisesRegex(
                ValueError, "color_format must be a non-empty string"
            ):
                ModelInputSpec(1, 1, color_format=value)  # type: ignore[arg-type]

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

    def test_transform_rejects_zero_source_dimensions_directly(self) -> None:
        for source_width, source_height, field_name in ((0, 0, "source_width"), (0, 1, "source_width"), (1, 0, "source_height")):
            with self.subTest(source_width=source_width, source_height=source_height), self.assertRaisesRegex(
                ValueError, f"{field_name} must be positive"
            ):
                PreprocessTransform(source_width, source_height, 1, 1, 1.0, 0, 0, 0, 0)

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

    def test_immutable_tensor_rejects_object_containing_array_dtypes(self) -> None:
        object_structured = np.zeros(1, dtype=np.dtype([("number", "u1"), ("value", object)]))
        nested_object_structured = np.zeros(
            1, dtype=np.dtype([("nested", [("value", object)])])
        )
        for array in (
            np.array([object()], dtype=object),
            object_structured,
            nested_object_structured,
        ):
            with self.subTest(dtype=array.dtype), self.assertRaisesRegex(
                TypeError, "object-containing dtypes"
            ):
                ImmutableTensor.from_array(array)

    def test_immutable_tensor_constructor_enforces_object_dtype_invariant(self) -> None:
        with self.assertRaisesRegex(TypeError, "object-containing dtypes"):
            ImmutableTensor(b"\x00" * np.dtype(object).itemsize, (1,), np.dtype(object), (8,))

    def test_immutable_tensor_uint8_round_trip_remains_supported(self) -> None:
        source = np.array([[1, 2], [3, 4]], dtype=np.uint8)
        tensor = ImmutableTensor.from_array(source)
        np.testing.assert_array_equal(tensor.to_numpy(), source)

    def test_immutable_tensor_requires_an_exact_dense_c_layout(self) -> None:
        with self.assertRaisesRegex(ValueError, "dense C-contiguous"):
            ImmutableTensor(b"\x01\x02", (2,), np.uint8, (0,))
        with self.assertRaisesRegex(ValueError, "dense C-contiguous"):
            ImmutableTensor(b"\x01\x02\x03\x04", (2, 2), np.uint8, (3, 1))
        with self.assertRaisesRegex(ValueError, "dense C-contiguous"):
            ImmutableTensor(b"\x01\x02", (2,), np.uint8, (-1,))
        with self.assertRaisesRegex(ValueError, "backing length"):
            ImmutableTensor(b"\x01", (2,), np.uint8, (1,))
        with self.assertRaisesRegex(ValueError, "backing length"):
            ImmutableTensor(b"\x01\x02\x03", (2,), np.uint8, (1,))

        tensor = ImmutableTensor(b"\x01\x02\x03\x04", (2, 2), np.uint8, (2, 1))
        self.assertEqual(tensor.strides, (2, 1))
        self.assertTrue(tensor.flags.c_contiguous)
        self.assertTrue(tensor.to_numpy().flags.c_contiguous)

    def test_immutable_tensor_rejects_invalid_shape_dimensions(self) -> None:
        for shape in ((0,), (-1,), (True,), (1.0,), ("1",)):
            with self.subTest(shape=shape), self.assertRaises((TypeError, ValueError)):
                ImmutableTensor(b"\x01", shape, np.uint8, (1,))  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "tensor shape is too large"):
            ImmutableTensor(b"", (maxsize, 2), np.uint8, (2, 1))

    def test_immutable_tensor_freezes_mutable_backing_buffers(self) -> None:
        backing = bytearray([1, 2, 3, 4])
        tensor = ImmutableTensor(backing, (4,), np.uint8, (1,))
        backing[0] = 99
        self.assertEqual(tensor[0], 1)
        view_backing = bytearray([5, 6, 7, 8])
        viewed = ImmutableTensor(memoryview(view_backing), (4,), np.uint8, (1,))
        view_backing[0] = 99
        self.assertEqual(viewed[0], 5)
        readonly = tensor.to_numpy()
        self.assertFalse(readonly.flags.writeable)
        with self.assertRaises(ValueError):
            readonly.setflags(write=True)
        copied = tensor.to_numpy(copy=True)
        copied[0] = 42
        self.assertEqual(tensor[0], 1)

    def test_immutable_tensor_normalizes_bytes_subclasses_before_sizing(self) -> None:
        class LyingBytes(bytes):
            def __len__(self) -> int:
                return 3

        backing = LyingBytes(b"\x01")
        with self.assertRaisesRegex(ValueError, "backing length"):
            ImmutableTensor(backing, (3,), np.uint8, (1,))

        tensor = ImmutableTensor(backing, (1,), np.uint8, (1,))
        self.assertIs(type(tensor._backing), bytes)
        self.assertIsNot(tensor._backing, backing)
        np.testing.assert_array_equal(tensor.to_numpy(), np.array([1], dtype=np.uint8))

    def test_immutable_tensor_fixed_width_structured_dtype_remains_supported(self) -> None:
        source = np.array([(1, 2), (3, 4)], dtype=np.dtype([("first", "u1"), ("second", "u2")]))
        tensor = ImmutableTensor.from_array(source)
        np.testing.assert_array_equal(tensor.to_numpy(), source)

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

    def test_input_accepts_and_retains_a_valid_immutable_tensor(self) -> None:
        spec = ModelInputSpec(width=1, height=1)
        tensor = ImmutableTensor(b"\x01\x02\x03", spec.shape, spec.dtype, (3, 3, 3, 1))
        result = ModelInput(
            self._metadata(), tensor, spec, PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        )
        self.assertIs(result.data, tensor)
        del tensor
        gc.collect()
        np.testing.assert_array_equal(result.data.to_numpy(), np.array([[[[1, 2, 3]]]], dtype=np.uint8))

    def test_input_requires_an_exact_model_input_spec_before_reading_it(self) -> None:
        exact_spec = ModelInputSpec(width=1, height=1)
        exact_transform = PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        exact_tensor = ImmutableTensor(b"\x01\x02\x03", (1, 1, 1, 3), np.uint8, (3, 3, 3, 1))
        self.assertIs(
            ModelInput(self._metadata(), exact_tensor, exact_spec, exact_transform).spec,
            exact_spec,
        )

        class MisleadingShapeSpec(ModelInputSpec):
            @property
            def shape(self) -> tuple[int, int, int, int]:
                return (1, 1, 1, 3)

        class ExplosiveSpec(ModelInputSpec):
            _reject_member_reads = False

            def __getattribute__(self, name: str) -> object:
                if type(self)._reject_member_reads and name in {
                    "shape", "width", "height", "channels", "batch_size", "layout", "dtype"
                }:
                    raise AssertionError(f"ModelInput must not read subclass.spec.{name}")
                return super().__getattribute__(name)

        transform = PreprocessTransform(1, 1, 2, 2, 1.0, 0, 0, 1, 1)
        undersized = ImmutableTensor(b"\x01\x02\x03", (1, 1, 1, 3), np.uint8, (3, 3, 3, 1))
        with self.assertRaisesRegex(TypeError, "spec must be an exact ModelInputSpec"):
            ModelInput(self._metadata(), undersized, MisleadingShapeSpec(2, 2), transform)

        explosive_spec = ExplosiveSpec(2, 2)
        ExplosiveSpec._reject_member_reads = True
        try:
            with self.assertRaisesRegex(TypeError, "spec must be an exact ModelInputSpec"):
                ModelInput(self._metadata(), undersized, explosive_spec, transform)
        finally:
            ExplosiveSpec._reject_member_reads = False

    def test_input_rejects_immutable_tensor_subclasses_before_reading_them(self) -> None:
        spec = ModelInputSpec(width=1, height=1)
        transform = PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)

        class PlainSubclass(ImmutableTensor):
            pass

        class WritableToNumpySubclass(ImmutableTensor):
            def to_numpy(self, *, copy: bool = False) -> np.ndarray:
                return np.zeros((1, 1, 1, 3), dtype=np.uint8)

        class ExplosivePropertySubclass(ImmutableTensor):
            @property
            def shape(self) -> tuple[int, ...]:
                raise AssertionError("ModelInput must not read subclass.shape")

            @property
            def dtype(self) -> np.dtype:
                raise AssertionError("ModelInput must not read subclass.dtype")

            @property
            def strides(self) -> tuple[int, ...]:
                raise AssertionError("ModelInput must not read subclass.strides")

            @property
            def flags(self) -> object:
                raise AssertionError("ModelInput must not read subclass.flags")

            def to_numpy(self, *, copy: bool = False) -> np.ndarray:
                raise AssertionError("ModelInput must not call subclass.to_numpy")

        for subclass in (PlainSubclass, WritableToNumpySubclass, ExplosivePropertySubclass):
            with self.subTest(subclass=subclass.__name__), self.assertRaisesRegex(
                TypeError, "ImmutableTensor subclasses are not supported"
            ):
                ModelInput(
                    self._metadata(),
                    subclass(b"\x01\x02\x03", spec.shape, spec.dtype, (3, 3, 3, 1)),
                    spec,
                    transform,
                )

    def test_input_snapshots_ndarray_subclasses_to_an_exact_immutable_tensor(self) -> None:
        class ArraySubclass(np.ndarray):
            pass

        spec = ModelInputSpec(width=1, height=1)
        transform = PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        source = np.array([[[[1, 2, 3]]]], dtype=np.uint8).view(ArraySubclass)
        result = ModelInput(self._metadata(), source, spec, transform)
        source[:] = 99

        self.assertIs(type(result.data), ImmutableTensor)
        np.testing.assert_array_equal(result.data.to_numpy(), np.array([[[[1, 2, 3]]]], dtype=np.uint8))

    def test_input_validates_immutable_tensor_against_its_spec(self) -> None:
        spec = ModelInputSpec(width=1, height=1)
        transform = PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        with self.assertRaisesRegex(ValueError, "data shape"):
            ModelInput(
                self._metadata(),
                ImmutableTensor(b"\x00" * 6, (1, 1, 2, 3), np.uint8, (6, 6, 3, 1)),
                spec,
                transform,
            )
        with self.assertRaisesRegex(ValueError, "data dtype"):
            ModelInput(
                self._metadata(),
                ImmutableTensor(b"\x00" * 12, spec.shape, np.float32, (12, 12, 12, 4)),
                spec,
                transform,
            )
        with self.assertRaisesRegex(ValueError, "data shape"):
            ModelInput(
                self._metadata(),
                ImmutableTensor(b"\x00" * 6, (2, 1, 1, 3), np.uint8, (3, 3, 3, 1)),
                spec,
                transform,
            )
        with self.assertRaisesRegex(TypeError, "NumPy array or an exact ImmutableTensor"):
            ModelInput(self._metadata(), b"\x00" * 3, spec, transform)  # type: ignore[arg-type]
        with self.assertRaisesRegex(ValueError, "dense C-contiguous"):
            ImmutableTensor(b"\x00" * 3, spec.shape, spec.dtype, (0, 0, 0, 1))

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
        if np.isfinite(large_value):
            longdouble_spec = ModelInputSpec(
                width=640, height=640, dtype=np.longdouble, padding_value=large_value
            )
            self.assertEqual(longdouble_spec.padding_value, large_value)
            if large_value > np.finfo(np.float64).max:
                with self.assertRaises(ValueError):
                    ModelInputSpec(width=640, height=640, dtype=np.float64, padding_value=large_value)
        else:
            with self.assertRaises(ValueError):
                ModelInputSpec(width=640, height=640, dtype=np.longdouble, padding_value=large_value)

    def test_float16_padding_range_is_checked_before_conversion(self) -> None:
        self.assertEqual(ModelInputSpec(1, 1, dtype=np.float16, padding_value=65504).padding_value, 65504)
        for value in (65505, -65505, float("nan"), float("inf"), float("-inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                ModelInputSpec(1, 1, dtype=np.float16, padding_value=value)

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
