"""Offline regression tests for the BGR24 letterbox preprocessor."""

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
    def _preprocessor(width: int, height: int, **kwargs: object) -> LetterboxPreprocessor:
        return LetterboxPreprocessor(ModelInputSpec(width=width, height=height, **kwargs))

    def test_equal_size_converts_bgr_to_rgb_and_preserves_metadata(self) -> None:
        frame = self._frame(bytes((1, 2, 3, 4, 5, 6)), 2, 1)
        original_pixels = frame.pixels
        preprocessor = self._preprocessor(2, 1)

        result = preprocessor.preprocess(frame)

        self.assertIs(result.metadata, frame.metadata)
        self.assertIs(result.spec, preprocessor.spec)
        self.assertEqual(frame.pixels, original_pixels)
        self.assertEqual(result.data.shape, (1, 1, 2, 3))
        self.assertEqual(result.data.dtype, np.dtype("uint8"))
        self.assertTrue(result.data.flags.c_contiguous)
        self.assertTrue(result.data.to_numpy().flags.c_contiguous)
        np.testing.assert_array_equal(
            result.data.to_numpy(), np.array([[[[3, 2, 1], [6, 5, 4]]]], dtype=np.uint8)
        )
        self.assertEqual((result.transform.pad_left, result.transform.pad_top), (0, 0))
        self.assertEqual((result.transform.pad_right, result.transform.pad_bottom), (0, 0))

    def test_horizontal_and_vertical_letterbox_geometry(self) -> None:
        horizontal = self._preprocessor(6, 6).preprocess(self._frame(bytes(4 * 2 * 3), 4, 2))
        vertical = self._preprocessor(6, 6).preprocess(self._frame(bytes(2 * 4 * 3), 2, 4))

        self.assertEqual(horizontal.transform.scale, 1.5)
        self.assertEqual((horizontal.transform.scaled_width, horizontal.transform.scaled_height), (6, 3))
        self.assertEqual(
            (horizontal.transform.pad_left, horizontal.transform.pad_top, horizontal.transform.pad_right, horizontal.transform.pad_bottom),
            (0, 1, 0, 2),
        )
        self.assertEqual(vertical.transform.scale, 1.5)
        self.assertEqual((vertical.transform.scaled_width, vertical.transform.scaled_height), (3, 6))
        self.assertEqual(
            (vertical.transform.pad_left, vertical.transform.pad_top, vertical.transform.pad_right, vertical.transform.pad_bottom),
            (1, 0, 2, 0),
        )

    def test_half_up_resize_rule_is_reflected_in_the_transform_and_tensor(self) -> None:
        # 3 * 1.5 is exactly 4.5, which must round upward to five.
        result = self._preprocessor(6, 5).preprocess(self._frame(bytes(4 * 3 * 3), 4, 3))

        self.assertEqual(result.transform.scale, 1.5)
        self.assertEqual((result.transform.scaled_width, result.transform.scaled_height), (6, 5))
        self.assertEqual((result.transform.pad_left, result.transform.pad_top), (0, 0))
        self.assertEqual(result.data.shape, (1, 5, 6, 3))

    def test_odd_padding_places_remainder_on_right_and_bottom(self) -> None:
        horizontal = self._preprocessor(5, 4).preprocess(self._frame(bytes(2 * 4 * 3), 2, 4))
        vertical = self._preprocessor(4, 5).preprocess(self._frame(bytes(4 * 2 * 3), 4, 2))

        self.assertEqual((horizontal.transform.pad_left, horizontal.transform.pad_right), (1, 2))
        self.assertEqual((vertical.transform.pad_top, vertical.transform.pad_bottom), (1, 2))

    def test_one_by_one_and_non_640_spec_are_supported(self) -> None:
        one = self._preprocessor(1, 1).preprocess(self._frame(bytes((7, 8, 9)), 1, 1))
        alternate = self._preprocessor(7, 5).preprocess(self._frame(bytes(2 * 1 * 3), 2, 1))

        np.testing.assert_array_equal(one.data.to_numpy(), np.array([[[[9, 8, 7]]]], dtype=np.uint8))
        self.assertEqual(alternate.data.shape, (1, 5, 7, 3))
        self.assertEqual((alternate.transform.scaled_width, alternate.transform.scaled_height), (7, 4))

    def test_large_source_geometry_uses_the_shared_contract_without_large_buffers(self) -> None:
        for width, height in ((1920, 1080), (3840, 2160)):
            with self.subTest(width=width, height=height):
                transform = PreprocessTransform(
                    width, height, 640, 640, 640 / width, 0, 140, 0, 140
                )
                self.assertEqual(transform.scaled_width, 640)
                self.assertLessEqual(transform.scaled_height, 640)

    def test_default_and_custom_padding_values_fill_only_the_padding(self) -> None:
        frame = self._frame(bytes((1, 2, 3, 4, 5, 6)), 2, 1)
        default = self._preprocessor(4, 4).preprocess(frame).data.to_numpy()
        custom = self._preprocessor(4, 4, padding_value=17).preprocess(frame).data.to_numpy()

        self.assertTrue(np.all(default[0, 0] == 0))
        self.assertTrue(np.all(custom[0, 0] == 17))
        np.testing.assert_array_equal(default[0, 1, 0], np.array([3, 2, 1], dtype=np.uint8))
        np.testing.assert_array_equal(custom[0, 1, 0], np.array([3, 2, 1], dtype=np.uint8))

    def test_row_padding_and_trailing_bytes_do_not_enter_pixels(self) -> None:
        padded = bytes((1, 2, 3, 4, 5, 6, 99, 98, 7, 8, 9, 10, 11, 12, 97, 96))
        frame = self._frame(padded + b"trailing", 2, 2, row_stride=8)

        result = self._preprocessor(2, 2).preprocess(frame)

        np.testing.assert_array_equal(
            result.data.to_numpy()[0],
            np.array(
                [[[3, 2, 1], [6, 5, 4]], [[9, 8, 7], [12, 11, 10]]],
                dtype=np.uint8,
            ),
        )

    def test_invalid_stride_and_short_full_stride_buffer_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "row_stride"):
            self._preprocessor(2, 1).preprocess(self._frame(bytes(6), 2, 1, row_stride=5))
        with self.assertRaisesRegex(ValueError, "shorter than height \* row_stride"):
            self._preprocessor(2, 2).preprocess(self._frame(bytes(15), 2, 2, row_stride=8))

    def test_non_bgr24_and_unsupported_specs_are_rejected_at_preprocessor_boundary(self) -> None:
        frame = self._frame(bytes(3), 1, 1, pixel_format="rgb24")
        with self.assertRaisesRegex(ValueError, "pixel_format='bgr24'"):
            self._preprocessor(1, 1).preprocess(frame)
        for spec_kwargs in (
            {"color_format": "BGR"},
            {"layout": "NCHW"},
            {"dtype": np.dtype("float32")},
            {"channels": 1},
        ):
            with self.subTest(spec_kwargs=spec_kwargs), self.assertRaisesRegex(ValueError, "supports only RGB"):
                self._preprocessor(1, 1, **spec_kwargs)

    def test_output_is_an_exact_immutable_tensor_independent_of_the_source(self) -> None:
        pixels = bytearray((1, 2, 3))
        frame = self._frame(pixels, 1, 1)
        result = self._preprocessor(1, 1).preprocess(frame)
        pixels[:] = b"\x09\x09\x09"
        del frame
        gc.collect()

        self.assertIs(type(result.data), ImmutableTensor)
        view = result.data.to_numpy()
        np.testing.assert_array_equal(view, np.array([[[[3, 2, 1]]]], dtype=np.uint8))
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
        preprocessor = self._preprocessor(3, 2)

        first_input = preprocessor.preprocess(first)
        second_input = preprocessor.preprocess(second)

        self.assertIs(first_input.metadata, first.metadata)
        self.assertIs(second_input.metadata, second.metadata)
        self.assertEqual(first_input.metadata.source_name, "left")
        self.assertEqual(second_input.metadata.source_name, "right")
        transform = first_input.transform
        self.assertEqual((transform.scaled_width, transform.scaled_height), (2, 2))
        self.assertEqual((transform.pad_left, transform.pad_top, transform.pad_right, transform.pad_bottom), (0, 0, 1, 0))
        self.assertEqual(first_input.data.to_numpy().shape, first_input.spec.shape)

    def test_frame_dimensions_remain_bounded_by_the_preprocessing_contract(self) -> None:
        oversized = self._frame(bytes(3), PREPROCESS_MAX_IMAGE_DIMENSION + 1, 1)
        with self.assertRaisesRegex(ValueError, "frame width must be between"):
            self._preprocessor(1, 1).preprocess(oversized)


if __name__ == "__main__":
    unittest.main()
