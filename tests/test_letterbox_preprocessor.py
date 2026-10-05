"""Offline regression tests for the verified YOLOv5 letterbox profile."""

from __future__ import annotations

import gc
import unittest

import numpy as np

from linux.task3_pipeline import (
    DecodedFrame,
    ImmutableTensor,
    ModelInputSpec,
    PREPROCESS_MAX_IMAGE_DIMENSION,
    PreprocessTransform,
)
from linux.task3_pipeline.letterbox_preprocessor import LetterboxPreprocessor

from tests._helpers import make_metadata


_YOLOV5_WIDTH = 640
_YOLOV5_HEIGHT = 640


class LetterboxPreprocessorTests(unittest.TestCase):
    @staticmethod
    def _frame(
        pixels: bytes | bytearray,
        width: int,
        height: int,
        *,
        row_stride: int | None = None,
        pixel_format: str = "bgr24",
        source_name: str = "camera-0",
    ) -> DecodedFrame:
        return DecodedFrame(
            metadata=make_metadata(source_name=source_name, payload_length=len(pixels)),
            pixels=pixels,
            width=width,
            height=height,
            pixel_format=pixel_format,
            row_stride=width * 3 if row_stride is None else row_stride,
            decoded_monotonic_ns=101,
        )

    @staticmethod
    def _preprocessor(**kwargs: object) -> LetterboxPreprocessor:
        return LetterboxPreprocessor(
            ModelInputSpec(width=_YOLOV5_WIDTH, height=_YOLOV5_HEIGHT, **kwargs)
        )

    def test_equal_size_input_preserves_geometry_and_converts_bgr_to_rgb(self) -> None:
        pixels = bytearray(_YOLOV5_WIDTH * _YOLOV5_HEIGHT * 3)
        pixels[:3] = bytes((1, 2, 3))
        frame = self._frame(pixels, _YOLOV5_WIDTH, _YOLOV5_HEIGHT)
        original_pixels = frame.pixels
        preprocessor = self._preprocessor()

        result = preprocessor.preprocess(frame)

        self.assertIs(result.metadata, frame.metadata)
        self.assertIs(result.spec, preprocessor.spec)
        self.assertEqual(frame.pixels, original_pixels)
        self.assertEqual(result.data.shape, (1, _YOLOV5_HEIGHT, _YOLOV5_WIDTH, 3))
        self.assertEqual(result.data.dtype, np.dtype("uint8"))
        self.assertTrue(result.data.flags.c_contiguous)
        self.assertTrue(result.data.to_numpy().flags.c_contiguous)
        np.testing.assert_array_equal(result.data.to_numpy()[0, 0, 0], np.array([3, 2, 1]))
        self.assertEqual(result.transform.scale, 1.0)
        self.assertEqual(
            (
                result.transform.pad_left,
                result.transform.pad_top,
                result.transform.pad_right,
                result.transform.pad_bottom,
            ),
            (0, 0, 0, 0),
        )

    def test_one_by_one_source_is_upscaled_with_bgr_to_rgb_conversion(self) -> None:
        result = self._preprocessor().preprocess(self._frame(bytes((7, 8, 9)), 1, 1))

        self.assertEqual(result.data.shape, (1, _YOLOV5_HEIGHT, _YOLOV5_WIDTH, 3))
        np.testing.assert_array_equal(
            result.data.to_numpy()[0, 0, 0], np.array([9, 8, 7], dtype=np.uint8)
        )
        self.assertEqual((result.transform.scaled_width, result.transform.scaled_height), (640, 640))

    def test_horizontal_and_vertical_letterbox_geometry(self) -> None:
        horizontal = self._preprocessor().preprocess(self._frame(bytes(4 * 2 * 3), 4, 2))
        vertical = self._preprocessor().preprocess(self._frame(bytes(2 * 4 * 3), 2, 4))

        self.assertEqual(horizontal.transform.scale, 160.0)
        self.assertEqual(
            (horizontal.transform.scaled_width, horizontal.transform.scaled_height), (640, 320)
        )
        self.assertEqual(
            (
                horizontal.transform.pad_left,
                horizontal.transform.pad_top,
                horizontal.transform.pad_right,
                horizontal.transform.pad_bottom,
            ),
            (0, 160, 0, 160),
        )
        self.assertEqual(vertical.transform.scale, 160.0)
        self.assertEqual(
            (vertical.transform.scaled_width, vertical.transform.scaled_height), (320, 640)
        )
        self.assertEqual(
            (
                vertical.transform.pad_left,
                vertical.transform.pad_top,
                vertical.transform.pad_right,
                vertical.transform.pad_bottom,
            ),
            (160, 0, 160, 0),
        )

    def test_odd_padding_places_remainder_on_right_and_bottom(self) -> None:
        horizontal = self._preprocessor().preprocess(self._frame(bytes(2 * 3 * 3), 2, 3))
        vertical = self._preprocessor().preprocess(self._frame(bytes(3 * 2 * 3), 3, 2))

        self.assertEqual((horizontal.transform.pad_left, horizontal.transform.pad_right), (106, 107))
        self.assertEqual((vertical.transform.pad_top, vertical.transform.pad_bottom), (106, 107))

    def test_half_up_resize_rule_is_reflected_in_the_transform_and_tensor(self) -> None:
        # 3 * 2.5 is exactly 7.5, which must round upward to eight.
        result = self._preprocessor().preprocess(self._frame(bytes(256 * 3 * 3), 256, 3))

        self.assertEqual(result.transform.scale, 2.5)
        self.assertEqual((result.transform.scaled_width, result.transform.scaled_height), (640, 8))
        self.assertEqual((result.transform.pad_top, result.transform.pad_bottom), (316, 316))
        self.assertEqual(result.data.shape, (1, 640, 640, 3))

    def test_large_source_geometry_uses_the_shared_contract_without_large_buffers(self) -> None:
        for width, height in ((1920, 1080), (3840, 2160)):
            with self.subTest(width=width, height=height):
                transform = PreprocessTransform(
                    width,
                    height,
                    _YOLOV5_WIDTH,
                    _YOLOV5_HEIGHT,
                    640 / width,
                    0,
                    140,
                    0,
                    140,
                )
                self.assertEqual(transform.scaled_width, 640)
                self.assertLessEqual(transform.scaled_height, 640)

    def test_default_and_custom_padding_values_fill_only_the_padding(self) -> None:
        frame = self._frame(bytes((1, 2, 3)), 1, 1)
        default = self._preprocessor().preprocess(frame).data.to_numpy()
        custom = self._preprocessor(padding_value=17).preprocess(frame).data.to_numpy()

        self.assertTrue(np.all(default[0] == np.array([3, 2, 1], dtype=np.uint8)))
        self.assertTrue(np.all(custom[0] == np.array([3, 2, 1], dtype=np.uint8)))
        padded = self._preprocessor().preprocess(self._frame(bytes(2 * 1 * 3), 2, 1)).data.to_numpy()
        self.assertTrue(np.all(padded[0, 0] == 0))

    def test_row_padding_and_trailing_bytes_do_not_enter_pixels(self) -> None:
        padded = bytes((1, 2, 3, 1, 2, 3, 99, 98, 1, 2, 3, 1, 2, 3, 97, 96))
        frame = self._frame(padded + b"trailing", 2, 2, row_stride=8)

        result = self._preprocessor().preprocess(frame)

        self.assertTrue(
            np.all(result.data.to_numpy()[0] == np.array([3, 2, 1], dtype=np.uint8))
        )

    def test_invalid_stride_and_short_full_stride_buffer_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "row_stride"):
            self._preprocessor().preprocess(self._frame(bytes(6), 2, 1, row_stride=5))
        with self.assertRaisesRegex(ValueError, "shorter than height \* row_stride"):
            self._preprocessor().preprocess(self._frame(bytes(15), 2, 2, row_stride=8))

    def test_non_bgr24_and_unsupported_specs_are_rejected_at_preprocessor_boundary(self) -> None:
        frame = self._frame(bytes(3), 1, 1, pixel_format="rgb24")
        with self.assertRaisesRegex(ValueError, "pixel_format='bgr24'"):
            self._preprocessor().preprocess(frame)
        for spec_kwargs in (
            {"color_format": "BGR"},
            {"layout": "NCHW"},
            {"dtype": np.dtype("float32")},
            {"channels": 1},
        ):
            with self.subTest(spec_kwargs=spec_kwargs), self.assertRaisesRegex(
                ValueError, "initial verified YOLOv5 profile requires 640x640"
            ):
                self._preprocessor(**spec_kwargs)

    def test_non_640_target_specs_are_rejected(self) -> None:
        for width, height in ((1, 1), (7, 5), (640, 320), (320, 640)):
            with self.subTest(width=width, height=height), self.assertRaisesRegex(
                ValueError, "initial verified YOLOv5 profile requires 640x640"
            ):
                LetterboxPreprocessor(ModelInputSpec(width=width, height=height))

    def test_output_is_an_exact_immutable_tensor_independent_of_the_source(self) -> None:
        pixels = bytearray((1, 2, 3))
        frame = self._frame(pixels, 1, 1)
        result = self._preprocessor().preprocess(frame)
        pixels[:] = b"\x09\x09\x09"
        del frame
        gc.collect()

        self.assertIs(type(result.data), ImmutableTensor)
        view = result.data.to_numpy()
        np.testing.assert_array_equal(view[0, 0, 0], np.array([3, 2, 1], dtype=np.uint8))
        self.assertFalse(view.flags.writeable)
        with self.assertRaises(ValueError):
            view[0, 0, 0, 0] = 99
        with self.assertRaises(ValueError):
            view.setflags(write=True)
        with self.assertRaises(AttributeError):
            result.data.shape = (1,)  # type: ignore[misc]

    def test_metadata_does_not_cross_between_sources_and_transform_matches_output(self) -> None:
        first = self._frame(bytes((1, 2, 3)), 1, 1, source_name="left")
        second = self._frame(bytes((4, 5, 6)), 1, 1, source_name="right")
        preprocessor = self._preprocessor()

        first_input = preprocessor.preprocess(first)
        second_input = preprocessor.preprocess(second)

        self.assertIs(first_input.metadata, first.metadata)
        self.assertIs(second_input.metadata, second.metadata)
        self.assertEqual(first_input.metadata.source_name, "left")
        self.assertEqual(second_input.metadata.source_name, "right")
        transform = first_input.transform
        self.assertEqual((transform.scaled_width, transform.scaled_height), (640, 640))
        self.assertEqual(
            (transform.pad_left, transform.pad_top, transform.pad_right, transform.pad_bottom),
            (0, 0, 0, 0),
        )
        self.assertEqual(first_input.data.to_numpy().shape, first_input.spec.shape)

    def test_frame_dimensions_remain_bounded_by_the_preprocessing_contract(self) -> None:
        oversized = self._frame(bytes(3), PREPROCESS_MAX_IMAGE_DIMENSION + 1, 1)
        with self.assertRaisesRegex(ValueError, "frame width must be between"):
            self._preprocessor().preprocess(oversized)


if __name__ == "__main__":
    unittest.main()
