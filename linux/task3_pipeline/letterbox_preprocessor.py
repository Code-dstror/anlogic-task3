"""Pure-memory BGR24 to RGB/NHWC letterbox preprocessing.

This module deliberately stops at constructing a :class:`ModelInput`: it does
not load a model, access an RKNN runtime, or interact with a device.  The
first profile supports the explicit YOLOv5-style RGB, NHWC, uint8, three
channel, batch-one specification.  Target dimensions remain caller supplied
rather than being fixed to 640 by this implementation.
"""

from __future__ import annotations

from math import floor
from numbers import Integral

import cv2
import numpy as np

from .models import (
    PREPROCESS_MAX_IMAGE_DIMENSION,
    DecodedFrame,
    FrameMetadata,
    ImmutableTensor,
    ModelInput,
    ModelInputSpec,
    PreprocessTransform,
)


_BGR24_PIXEL_FORMAT = "bgr24"


def _require_frame_dimension(value: object, name: str) -> int:
    """Normalize a decoded-frame dimension for this bounded preprocessor."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError(f"frame {name} must be an integer")
    normalized = int(value)
    if not 1 <= normalized <= PREPROCESS_MAX_IMAGE_DIMENSION:
        raise ValueError(
            f"frame {name} must be between 1 and {PREPROCESS_MAX_IMAGE_DIMENSION}"
        )
    return normalized


def _require_row_stride(value: object, packed_row_bytes: int) -> int:
    """Normalize a BGR24 row stride without accepting padded-pixel overlap."""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise TypeError("frame row_stride must be an integer")
    normalized = int(value)
    if normalized < packed_row_bytes:
        raise ValueError("frame row_stride must cover width * 3 BGR24 bytes")
    return normalized


def _round_half_up(dimension: int, scale: float) -> int:
    """Apply the shared ``floor(dimension * scale + 0.5)`` geometry rule.

    Frame and model dimensions are bounded by ``PREPROCESS_MAX_IMAGE_DIMENSION``;
    the resulting product is therefore safe for this binary64 calculation.
    ``PreprocessTransform`` validates the same rule independently when the
    output association is constructed.
    """
    return floor(dimension * scale + 0.5)


class LetterboxPreprocessor:
    """Build immutable RGB/NHWC/uint8 batch-one inputs from BGR24 frames.

    ``cv2.INTER_LINEAR`` is used for every non-identity resize, including
    upscaling.  The frame buffer must provide at least ``height * row_stride``
    bytes; any trailing bytes are ignored.  Each row contributes exactly
    ``width * 3`` BGR24 bytes, so row padding never enters the image.
    """

    def __init__(self, spec: ModelInputSpec) -> None:
        if type(spec) is not ModelInputSpec:
            raise TypeError("spec must be an exact ModelInputSpec")
        if (
            spec.color_format != "RGB"
            or spec.layout != "NHWC"
            or spec.dtype != np.dtype("uint8")
            or spec.channels != 3
            or spec.batch_size != 1
        ):
            raise ValueError(
                "LetterboxPreprocessor supports only RGB, NHWC, uint8, "
                "three-channel, batch_size=1 specs"
            )
        self._spec = spec

    @property
    def spec(self) -> ModelInputSpec:
        """The exact immutable specification used for every output."""
        return self._spec

    def preprocess(self, frame: DecodedFrame) -> ModelInput:
        """Copy one BGR24 frame into an immutable letterboxed ``ModelInput``."""
        if not isinstance(frame, DecodedFrame):
            raise TypeError("frame must be a DecodedFrame")

        # Snapshot the transport-owned values once.  We do not retain the
        # frame or its buffer; only its exact metadata is carried forward.
        metadata = frame.metadata
        if type(metadata) is not FrameMetadata:
            raise TypeError("frame metadata must be an exact FrameMetadata")
        width = _require_frame_dimension(frame.width, "width")
        height = _require_frame_dimension(frame.height, "height")
        pixel_format = frame.pixel_format
        if type(pixel_format) is not str or pixel_format != _BGR24_PIXEL_FORMAT:
            raise ValueError("LetterboxPreprocessor requires pixel_format='bgr24'")
        packed_row_bytes = width * 3
        row_stride = _require_row_stride(frame.row_stride, packed_row_bytes)

        try:
            raw_buffer = memoryview(frame.pixels)
        except TypeError as error:
            raise TypeError("frame pixels must expose a byte buffer") from error
        if not raw_buffer.c_contiguous:
            raise ValueError("frame pixels must be C-contiguous")
        required_nbytes = height * row_stride
        if raw_buffer.nbytes < required_nbytes:
            raise ValueError("frame pixels are shorter than height * row_stride")
        try:
            byte_buffer = raw_buffer.cast("B")
        except TypeError as error:
            raise ValueError("frame pixels must expose byte-addressable storage") from error

        # ``np.ndarray`` only views the valid BGR bytes; it never includes row
        # padding.  The following channel reversal is an owned C-contiguous
        # copy, making the result independent of the frame buffer lifetime.
        bgr = np.ndarray(
            shape=(height, width, 3),
            dtype=np.uint8,
            buffer=byte_buffer,
            strides=(row_stride, 3, 1),
        )
        rgb = np.ascontiguousarray(bgr[:, :, ::-1])

        scale = min(self._spec.width / width, self._spec.height / height)
        scaled_width = _round_half_up(width, scale)
        scaled_height = _round_half_up(height, scale)
        if not 1 <= scaled_width <= self._spec.width:
            raise ValueError("scaled width does not fit the model input")
        if not 1 <= scaled_height <= self._spec.height:
            raise ValueError("scaled height does not fit the model input")

        if (scaled_width, scaled_height) == (width, height):
            resized = rgb
        else:
            try:
                resized = cv2.resize(
                    rgb,
                    (scaled_width, scaled_height),
                    interpolation=cv2.INTER_LINEAR,
                )
            except cv2.error as error:
                raise ValueError("OpenCV failed to resize the decoded frame") from error
            resized = np.ascontiguousarray(resized)

        horizontal_padding = self._spec.width - scaled_width
        vertical_padding = self._spec.height - scaled_height
        pad_left = horizontal_padding // 2
        pad_right = horizontal_padding - pad_left
        pad_top = vertical_padding // 2
        pad_bottom = vertical_padding - pad_top
        transform = PreprocessTransform(
            source_width=width,
            source_height=height,
            model_width=self._spec.width,
            model_height=self._spec.height,
            scale=scale,
            pad_left=pad_left,
            pad_top=pad_top,
            pad_right=pad_right,
            pad_bottom=pad_bottom,
        )

        output = np.full(self._spec.shape, self._spec.padding_value, dtype=np.uint8)
        output[
            0,
            pad_top : pad_top + scaled_height,
            pad_left : pad_left + scaled_width,
            :,
        ] = resized
        output = np.ascontiguousarray(output)
        tensor = ImmutableTensor.from_array(output)
        return ModelInput(metadata=metadata, data=tensor, spec=self._spec, transform=transform)
