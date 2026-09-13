"""Lightweight JPEG payload boundary validation.

This module deliberately checks only payload-level size and boundary markers.
It neither parses PCIe protocol records nor proves that a JPEG can be decoded.
"""

from __future__ import annotations

from .errors import ConfigurationError, ValidationError
from .models import EncodedFrame


class JpegPayloadValidator:
    """Validate JPEG payload boundaries without decoding or copying a frame.

    Args:
        max_payload_length: Inclusive caller-supplied payload limit in bytes.
            It must be an integer (not ``bool``) of at least four bytes, the
            minimum size capable of containing the JPEG SOI and EOI markers.
    """

    _MINIMUM_PAYLOAD_LENGTH = 4
    _SOI = b"\xff\xd8"
    _EOI = b"\xff\xd9"

    def __init__(self, max_payload_length: int) -> None:
        if (
            isinstance(max_payload_length, bool)
            or not isinstance(max_payload_length, int)
            or max_payload_length < self._MINIMUM_PAYLOAD_LENGTH
        ):
            raise ConfigurationError(
                message=(
                    "max_payload_length must be a non-boolean integer of at least "
                    f"{self._MINIMUM_PAYLOAD_LENGTH} bytes"
                ),
                stage="jpeg_payload_validation",
                code="invalid_max_payload_length",
            )
        self._max_payload_length = max_payload_length

    @property
    def max_payload_length(self) -> int:
        """The inclusive payload limit configured for this validator."""

        return self._max_payload_length

    def validate(self, frame: EncodedFrame) -> EncodedFrame:
        """Return ``frame`` unchanged when its JPEG payload boundaries are valid.

        Raises:
            ValidationError: If the payload is empty, too short, too long, or
                lacks the required SOI or final EOI marker.
        """

        payload_length = len(frame.payload)
        error_context = (
            f"ingest_id={frame.metadata.ingest_id}, payload_length={payload_length}"
        )
        if payload_length == 0:
            self._raise("jpeg_payload_empty", f"JPEG payload is empty ({error_context})")
        if payload_length < self._MINIMUM_PAYLOAD_LENGTH:
            self._raise(
                "jpeg_payload_too_short",
                f"JPEG payload cannot contain both SOI and EOI ({error_context})",
            )
        if payload_length > self._max_payload_length:
            self._raise(
                "jpeg_payload_too_long",
                (
                    "JPEG payload exceeds configured maximum "
                    f"{self._max_payload_length} bytes ({error_context})"
                ),
            )
        if not frame.payload.startswith(self._SOI):
            self._raise("jpeg_payload_invalid_soi", f"JPEG payload lacks SOI ({error_context})")
        if not frame.payload.endswith(self._EOI):
            self._raise("jpeg_payload_invalid_eoi", f"JPEG payload lacks final EOI ({error_context})")
        return frame

    @staticmethod
    def _raise(code: str, message: str) -> None:
        raise ValidationError(
            message=message,
            stage="jpeg_payload_validation",
            code=code,
        )
