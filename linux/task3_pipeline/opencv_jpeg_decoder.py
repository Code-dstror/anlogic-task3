"""OpenCV-backed JPEG decoding into the pipeline's BGR24 frame layout."""

from __future__ import annotations

import time

import cv2
import numpy as np

from .errors import DecodeError
from .models import DecodedFrame, EncodedFrame


class OpenCvJpegDecoder:
    """Decode an already payload-validated JPEG ``EncodedFrame`` with OpenCV.

    Payload boundary validation is intentionally outside this adapter. The
    decoder always requests OpenCV's three-channel BGR result and publishes a
    C-contiguous BGR24 byte buffer.
    """

    _PIXEL_FORMAT = "bgr24"

    def decode(self, frame: EncodedFrame) -> DecodedFrame:
        """Decode ``frame`` into a BGR24 :class:`DecodedFrame`.

        Raises:
            DecodeError: If OpenCV cannot decode the payload or produces an
                unexpected image representation.
        """

        encoded = np.frombuffer(frame.payload, dtype=np.uint8)
        started_monotonic_ns = time.monotonic_ns()
        try:
            image = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
        except cv2.error as error:
            self._raise(
                "jpeg_decode_cv2_error",
                "OpenCV failed while decoding JPEG " + self._frame_context(frame),
                cause=error,
            )
        decoded_monotonic_ns = time.monotonic_ns()

        if image is None:
            self._raise(
                "jpeg_decode_failed",
                "OpenCV could not decode JPEG " + self._frame_context(frame),
            )
        if not isinstance(image, np.ndarray):
            self._raise_invalid_image(frame)
        if (
            image.ndim != 3
            or image.shape[0] <= 0
            or image.shape[1] <= 0
            or image.shape[2] != 3
            or image.dtype != np.uint8
        ):
            self._raise_invalid_image(frame)

        normalized = np.ascontiguousarray(image)
        height, width, _channels = normalized.shape
        pixels = normalized.tobytes()
        row_stride = len(pixels) // height

        # ``DecodedFrame`` currently carries the monotonic completion instant,
        # not a duration field. Capture both ends around imdecode so a future
        # metrics layer can measure decoder work without switching clock domains.
        _decode_elapsed_ns = max(0, decoded_monotonic_ns - started_monotonic_ns)
        del _decode_elapsed_ns

        return DecodedFrame(
            metadata=frame.metadata,
            pixels=pixels,
            width=width,
            height=height,
            pixel_format=self._PIXEL_FORMAT,
            row_stride=row_stride,
            decoded_monotonic_ns=decoded_monotonic_ns,
        )

    @staticmethod
    def _frame_context(frame: EncodedFrame) -> str:
        return (
            f"(ingest_id={frame.metadata.ingest_id}, "
            f"payload_length={len(frame.payload)})"
        )

    def _raise_invalid_image(self, frame: EncodedFrame) -> None:
        self._raise(
            "jpeg_decode_invalid_image",
            "OpenCV returned an unexpected decoded image " + self._frame_context(frame),
        )

    @staticmethod
    def _raise(code: str, message: str, cause: BaseException | None = None) -> None:
        raise DecodeError(
            message=message,
            stage="jpeg_decode",
            code=code,
            cause=cause,
        ) from cause
