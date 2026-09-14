"""Fail-closed classification for one-frame processing errors."""

from __future__ import annotations

from enum import Enum

from .errors import DecodeError, PipelineError, ValidationError


class FrameErrorDisposition(str, Enum):
    """The action a future lifecycle runner may take for one frame error."""

    CONTINUE_NEXT_FRAME = "continue_next_frame"
    PROPAGATE = "propagate"


_JPEG_PAYLOAD_CONTINUE_CODES = frozenset(
    {
        "jpeg_payload_empty",
        "jpeg_payload_too_short",
        "jpeg_payload_too_long",
        "jpeg_payload_invalid_soi",
        "jpeg_payload_invalid_eoi",
    }
)


def classify_frame_error(error: PipelineError) -> FrameErrorDisposition:
    """Classify a known local frame error without changing it or its metrics.

    Classification is deliberately independent of ``error.recoverable``.  New
    exception classes, stages, and codes fail closed by propagating.
    """

    if (
        type(error) is ValidationError
        and error.stage == "jpeg_payload_validation"
        and error.code in _JPEG_PAYLOAD_CONTINUE_CODES
    ):
        return FrameErrorDisposition.CONTINUE_NEXT_FRAME
    if (
        type(error) is DecodeError
        and error.stage == "jpeg_decode"
        and error.code == "jpeg_decode_failed"
    ):
        return FrameErrorDisposition.CONTINUE_NEXT_FRAME
    return FrameErrorDisposition.PROPAGATE
