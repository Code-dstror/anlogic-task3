from __future__ import annotations

from collections.abc import Mapping
from enum import Enum
import gc
from fractions import Fraction
import sys
from sys import maxsize
import unittest

import numpy as np

from linux.task3_pipeline import (
    DetectionResult,
    ImmutableTensor,
    InferenceBackend,
    ModelInput,
    ModelInputSpec,
    PREPROCESS_MAX_IMAGE_DIMENSION,
    PreprocessProfile,
    PreprocessTransform,
    ResizeRoundingStrategy,
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

    def test_preprocess_image_dimension_contract_is_bounded_and_exported(self) -> None:
        self.assertEqual(PREPROCESS_MAX_IMAGE_DIMENSION, 0xFFFF)
        for field_name in ("width", "height"):
            for value in (1, PREPROCESS_MAX_IMAGE_DIMENSION):
                with self.subTest(field=field_name, accepted=value):
                    spec = ModelInputSpec(**{field_name: value, "width" if field_name == "height" else "height": 1})
                    self.assertEqual(getattr(spec, field_name), value)
            for value in (0, PREPROCESS_MAX_IMAGE_DIMENSION + 1, 2**53 - 1, 10**10000):
                with self.subTest(field=field_name, rejected=value), self.assertRaisesRegex(
                    ValueError, f"{field_name} must be between 1 and"
                ):
                    ModelInputSpec(**{field_name: value, "width" if field_name == "height" else "height": 1})
            for value in (True, np.bool_(True), 1.0):
                with self.subTest(field=field_name, invalid_type=value), self.assertRaisesRegex(
                    TypeError, f"{field_name} must be an integer"
                ):
                    ModelInputSpec(**{field_name: value, "width" if field_name == "height" else "height": 1})

    def test_transform_uses_the_same_bounded_image_dimension_contract(self) -> None:
        field_names = ("source_width", "source_height", "model_width", "model_height")
        valid = {
            "source_width": 1,
            "source_height": 1,
            "model_width": 1,
            "model_height": 1,
            "scale": 1.0,
            "pad_left": 0,
            "pad_top": 0,
            "pad_right": 0,
            "pad_bottom": 0,
        }
        for field_name in field_names:
            for value in (0, PREPROCESS_MAX_IMAGE_DIMENSION + 1, 2**53 - 1, 10**10000):
                with self.subTest(field=field_name, rejected=value), self.assertRaisesRegex(
                    ValueError, f"{field_name} must be between 1 and"
                ):
                    PreprocessTransform(**(valid | {field_name: value}))

        for size in (1, PREPROCESS_MAX_IMAGE_DIMENSION):
            with self.subTest(accepted=size):
                transform = PreprocessTransform(size, size, size, size, 1.0, 0, 0, 0, 0)
                self.assertEqual((transform.scaled_width, transform.scaled_height), (size, size))
        for width, height in ((1920, 1080), (3840, 2160)):
            with self.subTest(width=width, height=height):
                transform = PreprocessTransform(width, height, width, height, 1.0, 0, 0, 0, 0)
                self.assertEqual((transform.scaled_width, transform.scaled_height), (width, height))

    def test_spec_requires_a_non_empty_string_color_format(self) -> None:
        self.assertEqual(ModelInputSpec(1, 1, color_format="RGB").color_format, "RGB")
        for value in ("", "   ", 3, None, True):
            with self.subTest(value=value), self.assertRaisesRegex(
                ValueError, "color_format must be a non-empty string"
            ):
                ModelInputSpec(1, 1, color_format=value)  # type: ignore[arg-type]

    def test_spec_normalizes_string_subclasses_before_validation_and_storage(self) -> None:
        class FakeLayout(str):
            def __hash__(self) -> int:
                return hash("NHWC")

            def __eq__(self, other: object) -> bool:
                return other == "NHWC"

        class FakeColorFormat(str):
            def strip(self) -> str:
                return "RGB"

        class ExplosiveString(str):
            def strip(self) -> str:
                raise AssertionError("validation must use the normalized base string")

        with self.assertRaisesRegex(ValueError, "layout must be NHWC or NCHW"):
            ModelInputSpec(1, 1, layout=FakeLayout("not-a-layout"))
        with self.assertRaisesRegex(ValueError, "color_format must be a non-empty string"):
            ModelInputSpec(1, 1, color_format=FakeColorFormat("   "))

        spec = ModelInputSpec(
            1, 1, color_format=ExplosiveString("RGB"), layout=ExplosiveString("NHWC")
        )
        self.assertIs(type(spec.color_format), str)
        self.assertIs(type(spec.layout), str)
        self.assertEqual(spec.color_format, "RGB")
        self.assertEqual(spec.layout, "NHWC")

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

    def test_transform_normalizes_only_exact_binary64_scales(self) -> None:
        class ChangedFloat(float):
            def __float__(self) -> float:
                return 0.5

        accepted = PreprocessTransform(2, 2, 1, 1, np.float32(0.5), 0, 0, 0, 0)
        self.assertIs(type(accepted.scale), float)
        self.assertEqual(accepted.scale, 0.5)

        changed_one = PreprocessTransform(1, 1, 1, 1, ChangedFloat(1.0), 0, 0, 0, 0)
        self.assertIs(type(changed_one.scale), float)
        self.assertEqual(changed_one.scale, 1.0)
        changed_tenth = PreprocessTransform(10, 10, 1, 1, ChangedFloat(0.1), 0, 0, 0, 0)
        self.assertEqual(changed_tenth.scale, 0.1)
        self.assertEqual(
            changed_tenth.scale.as_integer_ratio(), float(0.1).as_integer_ratio()
        )

        longdouble_candidate = np.longdouble("1.00000000000000000001")
        if np.isfinite(longdouble_candidate) and longdouble_candidate != np.longdouble(
            np.float64(longdouble_candidate)
        ):
            with self.assertRaisesRegex(ValueError, "exactly representable"):
                PreprocessTransform(1, 1, 1, 1, longdouble_candidate, 0, 0, 0, 0)
        else:
            transform = PreprocessTransform(1, 1, 1, 1, longdouble_candidate, 0, 0, 0, 0)
            self.assertIs(type(transform.scale), float)

        for scale in (10**10000, np.uint64(np.iinfo(np.uint64).max)):
            with self.subTest(scale_type=type(scale)), self.assertRaisesRegex(
                ValueError, "exactly representable"
            ):
                PreprocessTransform(1, 1, 1, 1, scale, 0, 0, 0, 0)
        with self.assertRaisesRegex(TypeError, "Python or NumPy real scalar"):
            PreprocessTransform(1, 1, 1, 1, Fraction(1, 2), 0, 0, 0, 0)

    def test_transform_rejects_zero_source_dimensions_directly(self) -> None:
        for source_width, source_height, field_name in ((0, 0, "source_width"), (0, 1, "source_width"), (1, 0, "source_height")):
            with self.subTest(source_width=source_width, source_height=source_height), self.assertRaisesRegex(
                ValueError, f"{field_name} must be between 1 and"
            ):
                PreprocessTransform(source_width, source_height, 1, 1, 1.0, 0, 0, 0, 0)

    def test_transform_uses_nearest_half_up_scaled_dimension_rounding(self) -> None:
        transform = PreprocessTransform(3, 2, 2, 1, 0.5, 0, 0, 0, 0)

        self.assertEqual(transform.scaled_width, 2)
        self.assertEqual(transform.scaled_height, 1)

    def test_transform_rounding_strategy_and_profile_normalize_to_exact_enums(self) -> None:
        legacy = PreprocessTransform(3, 2, 2, 1, 0.5, 0, 0, 0, 0)
        self.assertIs(legacy.rounding_strategy, ResizeRoundingStrategy.HALF_UP)
        self.assertIsNone(legacy.profile)

        truncated = PreprocessTransform(
            3,
            2,
            1,
            1,
            0.5,
            0,
            0,
            0,
            0,
            "truncate_toward_zero",
            "rk3576_yolov5s_relu_pcie_v1",
        )
        self.assertEqual((truncated.scaled_width, truncated.scaled_height), (1, 1))
        self.assertIs(type(truncated.rounding_strategy), ResizeRoundingStrategy)
        self.assertIs(type(truncated.profile), PreprocessProfile)
        self.assertIs(
            truncated.rounding_strategy, ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO
        )
        self.assertIs(
            truncated.profile, PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1
        )

    def test_transform_rejects_non_exact_rounding_and_profile_representations(self) -> None:
        class StringSubclass(str):
            pass

        class OtherEnum(Enum):
            VALUE = "half_up"

        valid = dict(
            source_width=1,
            source_height=1,
            model_width=1,
            model_height=1,
            scale=1.0,
            pad_left=0,
            pad_top=0,
            pad_right=0,
            pad_bottom=0,
        )
        for name, value in (
            ("rounding_strategy", True),
            ("rounding_strategy", "unknown"),
            ("rounding_strategy", StringSubclass("half_up")),
            ("rounding_strategy", OtherEnum.VALUE),
            ("profile", True),
            ("profile", "unknown"),
            ("profile", StringSubclass("rk3576_yolov5s_relu_pcie_v1")),
            ("profile", OtherEnum.VALUE),
        ):
            with self.subTest(name=name, value=value), self.assertRaises((TypeError, ValueError)):
                PreprocessTransform(**(valid | {name: value}))

    def test_transform_profile_requires_truncate_toward_zero(self) -> None:
        valid = dict(
            source_width=1,
            source_height=1,
            model_width=1,
            model_height=1,
            scale=1.0,
            pad_left=0,
            pad_top=0,
            pad_right=0,
            pad_bottom=0,
            profile=PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1,
        )
        with self.assertRaisesRegex(ValueError, "requires truncate_toward_zero"):
            PreprocessTransform(**valid)
        with self.assertRaisesRegex(ValueError, "requires truncate_toward_zero"):
            PreprocessTransform(
                **(valid | {"rounding_strategy": ResizeRoundingStrategy.HALF_UP})
            )
        accepted = PreprocessTransform(
            **(valid | {"rounding_strategy": ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO})
        )
        self.assertIs(
            accepted.rounding_strategy, ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO
        )

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

    def test_transform_normalizes_unroundable_scaled_dimensions_to_value_error(self) -> None:
        cases = (
            (2, 1, sys.float_info.max, "width"),
            (1, 2, sys.float_info.max, "height"),
        )
        for source_width, source_height, scale, axis in cases:
            with self.subTest(axis=axis, scale=scale), self.assertRaisesRegex(
                ValueError, f"scaled {axis} must be finite and roundable"
            ):
                PreprocessTransform(
                    source_width, source_height, 1, 1, scale, 0, 0, 0, 0
                )

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
        class MisleadingObjectArray(np.ndarray):
            @property
            def dtype(self) -> np.dtype:
                return np.dtype(np.uint8)

        object_structured = np.zeros(1, dtype=np.dtype([("number", "u1"), ("value", object)]))
        nested_object_structured = np.zeros(
            1, dtype=np.dtype([("nested", [("value", object)])])
        )
        for array in (
            np.array([object()], dtype=object),
            object_structured,
            nested_object_structured,
            np.array([object()], dtype=object).view(MisleadingObjectArray),
        ):
            with self.subTest(dtype=array.dtype), self.assertRaisesRegex(
                TypeError, "object-containing dtypes"
            ):
                ImmutableTensor.from_array(array)

    def test_immutable_tensor_constructor_enforces_object_dtype_invariant(self) -> None:
        with self.assertRaisesRegex(TypeError, "object-containing dtypes"):
            ImmutableTensor(b"\x00" * np.dtype(object).itemsize, (1,), np.dtype(object), (8,))

    def test_immutable_tensor_rejects_top_level_subarray_dtypes(self) -> None:
        subarray_dtypes = (
            np.dtype((np.uint8, (2,))),
            np.dtype((np.int16, (2, 3))),
        )
        for dtype in subarray_dtypes:
            with self.subTest(dtype=dtype), self.assertRaisesRegex(
                TypeError, "top-level subarray dtypes are not supported"
            ):
                ImmutableTensor(b"\x00" * dtype.itemsize, (1,), dtype, (dtype.itemsize,))

        # NumPy normalizes an ndarray made with a subarray dtype into its
        # scalar base dtype plus expanded shape. That normalized layout remains
        # safe and accurately reflected by ImmutableTensor's public metadata.
        source = np.empty((1,), dtype=np.dtype((np.uint8, (2,))))
        source[0] = (1, 2)
        self.assertEqual(source.dtype, np.dtype(np.uint8))
        self.assertEqual(source.shape, (1, 2))
        tensor = ImmutableTensor.from_array(source)
        self.assertEqual(tensor.dtype, source.dtype)
        self.assertEqual(tensor.shape, source.shape)
        self.assertEqual(tensor.ndim, source.ndim)
        self.assertEqual(tensor.size, source.size)
        np.testing.assert_array_equal(tensor.to_numpy(), source)

    def test_immutable_tensor_uint8_round_trip_remains_supported(self) -> None:
        source = np.array([[1, 2], [3, 4]], dtype=np.uint8)
        tensor = ImmutableTensor.from_array(source)
        self.assertIs(type(tensor), ImmutableTensor)
        np.testing.assert_array_equal(tensor.to_numpy(), source)

    def test_immutable_tensor_from_array_always_returns_the_exact_base_type(self) -> None:
        class EvilTensor(ImmutableTensor):
            def to_numpy(self, *, copy: bool = False) -> np.ndarray:
                raise AssertionError("from_array must not return an ImmutableTensor subclass")

        source = np.array([1, 2], dtype=np.uint8)
        tensor = EvilTensor.from_array(source)
        self.assertIs(type(tensor), ImmutableTensor)
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

    def test_input_rejects_its_own_subclasses_before_reading_any_member(self) -> None:
        with self.assertRaisesRegex(TypeError, "ModelInput subclasses are not supported"):
            class ExplosiveModelInput(ModelInput):
                def __getattribute__(self, name: str) -> object:
                    if name in {"data", "metadata", "spec", "transform"}:
                        raise AssertionError(f"ModelInput must not read subclass.{name}")
                    return super().__getattribute__(name)

    def test_input_rejects_contract_subclasses_before_reading_them(self) -> None:
        class ExplosiveMetadata(FrameMetadata):
            _reject_member_reads = False

            def __getattribute__(self, name: str) -> object:
                if type(self)._reject_member_reads and name in {"ingest_id", "source_name"}:
                    raise AssertionError(f"ModelInput must not read subclass.metadata.{name}")
                return super().__getattribute__(name)

        class ExplosiveTransform(PreprocessTransform):
            _reject_member_reads = False

            def __getattribute__(self, name: str) -> object:
                if type(self)._reject_member_reads and name in {
                    "source_width", "source_height", "model_width", "model_height", "scale",
                    "pad_left", "pad_top", "pad_right", "pad_bottom",
                }:
                    raise AssertionError(f"ModelInput must not read subclass.transform.{name}")
                return super().__getattribute__(name)

        spec = ModelInputSpec(width=1, height=1)
        tensor = ImmutableTensor(b"\x01\x02\x03", spec.shape, spec.dtype, (3, 3, 3, 1))
        exact_metadata = FrameMetadata(0, "test", 0, 0)
        exact_transform = PreprocessTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        self.assertIs(ModelInput(exact_metadata, tensor, spec, exact_transform).transform, exact_transform)

        metadata = ExplosiveMetadata(0, "test", 0, 0)
        transform = ExplosiveTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        ExplosiveMetadata._reject_member_reads = True
        ExplosiveTransform._reject_member_reads = True
        try:
            with self.assertRaisesRegex(TypeError, "metadata must be an exact FrameMetadata"):
                ModelInput(metadata, tensor, spec, exact_transform)
            with self.assertRaisesRegex(TypeError, "transform must be an exact PreprocessTransform"):
                ModelInput(exact_metadata, tensor, spec, transform)
        finally:
            ExplosiveMetadata._reject_member_reads = False
            ExplosiveTransform._reject_member_reads = False

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
        for dtype in (
            np.dtype("bool"),
            np.dtype("complex64"),
            np.dtype("O"),
            np.dtype("U8"),
            np.dtype((np.uint8, (2,))),
        ):
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

    def test_floating_padding_must_be_exactly_representable_by_target_dtype(self) -> None:
        # Decimal mathematical 0.1 is a float64 value here, not an already
        # quantized float16/float32 scalar, so neither target can retain it exactly.
        for dtype in (np.float16, np.float32):
            with self.subTest(source="python float 0.1", dtype=dtype), self.assertRaisesRegex(
                ValueError, "exactly representable"
            ):
                ModelInputSpec(1, 1, dtype=dtype, padding_value=0.1)
            with self.subTest(source="np.float64(0.1)", dtype=dtype), self.assertRaisesRegex(
                ValueError, "exactly representable"
            ):
                ModelInputSpec(1, 1, dtype=dtype, padding_value=np.float64(0.1))

        # These values have already been quantized to the target binary format.
        self.assertEqual(
            ModelInputSpec(1, 1, dtype=np.float32, padding_value=np.float32(0.1)).padding_value,
            np.float32(0.1),
        )
        self.assertEqual(
            ModelInputSpec(1, 1, dtype=np.float16, padding_value=np.float16(0.1)).padding_value,
            np.float16(0.1),
        )

        for dtype in (np.float16, np.float32):
            limits = np.finfo(dtype)
            accepted = (
                0,
                1,
                1.5,
                limits.min,
                limits.max,
                np.nextafter(limits.min, dtype(0)),
                np.nextafter(limits.max, dtype(0)),
            )
            for value in accepted:
                with self.subTest(dtype=dtype, accepted=value):
                    ModelInputSpec(1, 1, dtype=dtype, padding_value=value)

        for value in (65505, -65505, float("nan"), float("inf"), float("-inf")):
            with self.subTest(float16_rejected=value), self.assertRaises(ValueError):
                ModelInputSpec(1, 1, dtype=np.float16, padding_value=value)

        for value in (0, 1, -2, np.int64(17), np.int64(-17)):
            with self.subTest(exact_integer=value):
                ModelInputSpec(1, 1, dtype=np.float64, padding_value=value)
        with self.assertRaisesRegex(ValueError, "exactly representable"):
            ModelInputSpec(1, 1, dtype=np.float64, padding_value=(1 << 53) + 1)

    def test_floating_padding_uses_binary_values_and_rejects_unsupported_reals(self) -> None:
        class FloatWithoutRatio(float):
            # A float subclass cannot alter its stored binary64 value, but it
            # can hide the instance method used by a naïve fallback.
            as_integer_ratio = None

        value = FloatWithoutRatio(0.1)
        accepted = ModelInputSpec(1, 1, dtype=np.float64, padding_value=value)
        self.assertEqual(accepted.padding_value, 0.1)
        for dtype in (np.float16, np.float32):
            with self.subTest(dtype=dtype), self.assertRaisesRegex(
                ValueError, "exactly representable"
            ):
                ModelInputSpec(1, 1, dtype=dtype, padding_value=value)

        # Third-party Real instances have no declared binary-scalar contract;
        # reject them rather than approximating them through formatted text.
        with self.assertRaisesRegex(TypeError, "Python or NumPy real scalar"):
            ModelInputSpec(1, 1, dtype=np.float64, padding_value=Fraction(1, 2))

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

    def test_model_input_retains_the_exact_validated_profile_transform(self) -> None:
        spec = ModelInputSpec(width=1, height=1)
        transform = PreprocessTransform(
            1,
            1,
            1,
            1,
            1.0,
            0,
            0,
            0,
            0,
            ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO,
            PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1,
        )
        model_input = ModelInput(
            self._metadata(), np.zeros(spec.shape, dtype=spec.dtype), spec, transform
        )
        self.assertIs(model_input.transform, transform)
        self.assertIs(type(model_input.transform.rounding_strategy), ResizeRoundingStrategy)
        self.assertIs(type(model_input.transform.profile), PreprocessProfile)

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
        self.assertIs(type(converted.preprocess_transform), PreprocessTransform)
        self.assertEqual(converted.preprocess_transform, transform)
        valid_mapping["model_width"] = 1
        self.assertEqual(converted.preprocess_transform.model_width, 640)

    def test_detection_result_normalizes_rounding_profile_mapping_and_preserves_legacy(self) -> None:
        legacy_mapping = {
            "source_width": 3,
            "source_height": 2,
            "model_width": 2,
            "model_height": 1,
            "scale": 0.5,
            "pad_left": 0,
            "pad_top": 0,
            "pad_right": 0,
            "pad_bottom": 0,
        }
        legacy = DetectionResult(0, 1, 2, preprocess_transform=legacy_mapping)
        self.assertIs(legacy.preprocess_transform.rounding_strategy, ResizeRoundingStrategy.HALF_UP)
        self.assertIsNone(legacy.preprocess_transform.profile)

        v2_mapping = legacy_mapping | {
            "model_width": 1,
            "rounding_strategy": "truncate_toward_zero",
            "profile": "rk3576_yolov5s_relu_pcie_v1",
        }
        converted = DetectionResult(0, 1, 2, preprocess_transform=v2_mapping)
        self.assertIs(type(converted.preprocess_transform), PreprocessTransform)
        self.assertIs(
            converted.preprocess_transform.rounding_strategy,
            ResizeRoundingStrategy.TRUNCATE_TOWARD_ZERO,
        )
        self.assertIs(
            converted.preprocess_transform.profile,
            PreprocessProfile.RK3576_YOLOV5S_RELU_PCIE_V1,
        )

    def test_detection_result_requires_strategy_when_mapping_has_profile_before_value_reads(self) -> None:
        fields = (
            "source_width",
            "source_height",
            "model_width",
            "model_height",
            "scale",
            "pad_left",
            "pad_top",
            "pad_right",
            "pad_bottom",
            "profile",
        )

        class ProfileWithoutStrategyMapping(Mapping[str, object]):
            getitem_calls = 0

            def __iter__(self):
                return iter(fields)

            def __len__(self) -> int:
                return len(fields)

            def __getitem__(self, key: str) -> object:
                type(self).getitem_calls += 1
                raise AssertionError("schema validation must precede mapping value reads")

        mapping = ProfileWithoutStrategyMapping()
        with self.assertRaisesRegex(ValueError, "profile requires rounding_strategy"):
            DetectionResult(0, 1, 2, preprocess_transform=mapping)
        self.assertEqual(mapping.getitem_calls, 0)

    def test_detection_result_rejects_untrusted_rounding_profile_mapping_values(self) -> None:
        class StringSubclass(str):
            pass

        base_mapping = {
            "source_width": 3,
            "source_height": 2,
            "model_width": 1,
            "model_height": 1,
            "scale": 0.5,
            "pad_left": 0,
            "pad_top": 0,
            "pad_right": 0,
            "pad_bottom": 0,
            "rounding_strategy": "truncate_toward_zero",
            "profile": "rk3576_yolov5s_relu_pcie_v1",
        }
        for name, value in (
            ("rounding_strategy", True),
            ("rounding_strategy", "unknown"),
            ("rounding_strategy", StringSubclass("truncate_toward_zero")),
            ("profile", True),
            ("profile", "unknown"),
            ("profile", StringSubclass("rk3576_yolov5s_relu_pcie_v1")),
        ):
            with self.subTest(name=name, value=value), self.assertRaises((TypeError, ValueError)):
                DetectionResult(0, 1, 2, preprocess_transform=base_mapping | {name: value})

    def test_detection_result_rejects_transform_subclasses_before_reading_them(self) -> None:
        class ExplosiveTransform(PreprocessTransform):
            _reject_member_reads = False

            def __getattribute__(self, name: str) -> object:
                if type(self)._reject_member_reads and name in {
                    "source_width", "source_height", "model_width", "model_height", "scale",
                    "pad_left", "pad_top", "pad_right", "pad_bottom",
                }:
                    raise AssertionError(f"DetectionResult must not read subclass.transform.{name}")
                return super().__getattribute__(name)

        transform = ExplosiveTransform(1, 1, 1, 1, 1.0, 0, 0, 0, 0)
        ExplosiveTransform._reject_member_reads = True
        try:
            with self.assertRaisesRegex(TypeError, "PreprocessTransform subclasses are not supported"):
                DetectionResult(0, 1, 2, preprocess_transform=transform)
        finally:
            ExplosiveTransform._reject_member_reads = False

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
        with self.assertRaisesRegex(ValueError, "unknown fields"):
            DetectionResult(0, 1, 2, preprocess_transform={"extra": 1, 7: 1})

        class DeceptiveKey(str):
            def __hash__(self) -> int:
                return hash("source_width")

            def __eq__(self, other: object) -> bool:
                return other == "source_width"

        with self.assertRaisesRegex(ValueError, "unknown fields"):
            DetectionResult(0, 1, 2, preprocess_transform={DeceptiveKey("extra"): 1})

        class RawKeyMapping(Mapping[str, object]):
            def __init__(self, *extra_keys: object) -> None:
                self._keys = tuple(valid_mapping) + extra_keys
                self.getitem_calls = 0

            def __iter__(self):
                return iter(self._keys)

            def __len__(self) -> int:
                return len(self._keys)

            def __getitem__(self, key: str) -> object:
                self.getitem_calls += 1
                return valid_mapping[str.__str__(key)]

        legal_custom_mapping = RawKeyMapping()
        converted = DetectionResult(0, 1, 2, preprocess_transform=legal_custom_mapping)
        self.assertIs(type(converted.preprocess_transform), PreprocessTransform)
        self.assertEqual(legal_custom_mapping.getitem_calls, len(valid_mapping))

        # The raw key's stored text is "junk", but its hostile equality and
        # hash collide with source_width. Validation must reject it before a
        # dict snapshot could silently erase it.
        deceptive_mapping = RawKeyMapping(DeceptiveKey("junk"))
        with self.assertRaisesRegex(ValueError, "unknown field"):
            DetectionResult(0, 1, 2, preprocess_transform=deceptive_mapping)
        self.assertEqual(deceptive_mapping.getitem_calls, 0)

        class DuplicateKey(str):
            pass

        duplicate_mapping = RawKeyMapping(DuplicateKey("source_width"))
        with self.assertRaisesRegex(ValueError, "duplicate fields"):
            DetectionResult(0, 1, 2, preprocess_transform=duplicate_mapping)
        self.assertEqual(duplicate_mapping.getitem_calls, 0)
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
