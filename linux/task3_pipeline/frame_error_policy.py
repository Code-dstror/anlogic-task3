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

_TRANSPORT_RECORD_CONTINUE_ERRORS = frozenset(
    {
        ("transport_record_validation", "record_header_truncated"),
        ("transport_record_validation", "record_too_large"),
        ("transport_record_validation", "record_invalid_frame_magic"),
        ("transport_record_validation", "record_invalid_protocol_version"),
        ("transport_record_validation", "record_invalid_header_length"),
        ("transport_record_validation", "record_invalid_flags"),
        ("transport_record_validation", "record_invalid_reserved0"),
        ("transport_record_validation", "record_invalid_reserved1"),
        ("transport_record_validation", "record_payload_length_zero"),
        ("transport_record_validation", "record_payload_length_exceeds_max"),
        ("transport_record_validation", "record_payload_truncated"),
        ("transport_record_validation", "record_trailing_bytes"),
        ("transport_record_mapping", "record_error_code_nonzero"),
    }
)


def is_transport_record_invalid_error(error: PipelineError) -> bool:
    """Return whether one assembled record has an allowlisted wire failure.

    Callers may use this only after they have already supplied exactly one
    record candidate boundary.  This deliberately excludes buffer access and
    mapper call-contract failures, which remain fail-closed programming or
    resource errors.
    """

    return (
        type(error) is ValidationError
        and (error.stage, error.code) in _TRANSPORT_RECORD_CONTINUE_ERRORS
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
    if is_transport_record_invalid_error(error):
        return FrameErrorDisposition.CONTINUE_NEXT_FRAME
    if (
        type(error) is DecodeError
        and error.stage == "jpeg_decode"
        and error.code == "jpeg_decode_failed"
    ):
        return FrameErrorDisposition.CONTINUE_NEXT_FRAME
    return FrameErrorDisposition.PROPAGATE
