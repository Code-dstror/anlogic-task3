"""In-memory validation and parsing of complete PCIe v1 records.

This module accepts only a caller-assembled ``[header][payload]`` record.  It
does not read a device, manage DMA slots, or map records to ``EncodedFrame``.
"""

from __future__ import annotations

from dataclasses import dataclass
import struct

from .errors import ValidationError
from .pcie_protocol_v1 import (
    FRAME_HEADER_EXPECTED_VALUES,
    FRAME_HEADER_FIELD_NAMES,
    FRAME_HEADER_STRUCT,
    HEADER_LENGTH,
    MAX_PAYLOAD,
)


_VALIDATION_STAGE = "transport_record_validation"
_BUFFER_ACCESS_ERROR_CODE = "transport_record_buffer_access"
_EXPECTED_FIELD_NAMES = (
    "frame_magic",
    "protocol_version",
    "header_length",
    "flags",
)
_RESERVED_FIELD_NAMES = ("reserved0", "reserved1")
_BYTE_WIRE_FIELD_NAMES = frozenset(
    name
    for name, expected in FRAME_HEADER_EXPECTED_VALUES.items()
    if isinstance(expected, bytes)
)


@dataclass(frozen=True, slots=True)
class PcieV1Record:
    """One immutable, fully validated PCIe v1 wire record.

    Fields retain their decoded wire values. In particular, compression, pixel
    format, quality, status, error code, payload CRC, and timestamp are opaque
    at this boundary. ``slot_id`` intentionally remains transport record data
    rather than becoming public frame metadata.
    """

    frame_magic: int
    protocol_version: int
    header_length: int
    frame_sequence: int
    payload_length: int
    width: int
    height: int
    pixel_format: int
    compression: int
    quality: int
    flags: int
    timestamp_ns: int
    status: int
    error_code: int
    slot_id: int
    reserved0: int
    payload_crc32: int
    reserved1: bytes
    payload: bytes

    def __post_init__(self) -> None:
        """Keep directly constructed records as valid and immutable as parsed ones."""

        if not isinstance(self.payload, bytes):
            raise TypeError("payload must be bytes")
        for name in FRAME_HEADER_FIELD_NAMES:
            value = getattr(self, name)
            if name in _BYTE_WIRE_FIELD_NAMES:
                if not isinstance(value, bytes):
                    raise TypeError(f"{name} must be bytes")
            elif isinstance(value, bool) or not isinstance(value, int):
                raise TypeError(f"{name} must be an integer")
        if self.payload_length != len(self.payload):
            raise ValueError("payload_length must match payload length")
        if not 1 <= self.payload_length <= MAX_PAYLOAD:
            raise ValueError("payload_length must be within the v1 payload range")

        values = tuple(getattr(self, name) for name in FRAME_HEADER_FIELD_NAMES)
        try:
            FRAME_HEADER_STRUCT.pack(*values)
        except (struct.error, TypeError) as error:
            raise ValueError("wire fields must fit the generated v1 header layout") from error

        for name, expected in FRAME_HEADER_EXPECTED_VALUES.items():
            if getattr(self, name) != expected:
                raise ValueError(f"{name} must match the generated v1 expected value")


class PcieV1RecordParser:
    """Validate and parse one complete v1 ``[64-byte header][payload]`` record."""

    def parse(self, record: bytes | bytearray | memoryview) -> PcieV1Record:
        """Return an immutable record snapshot, or raise ``ValidationError``.

        The source is deliberately not interpreted as a device read or a DMA
        completion. The caller must already have assembled exactly one record.
        """

        if not isinstance(record, (bytes, bytearray, memoryview)):
            self._raise("record_not_bytes_like", "record must be bytes, bytearray, or memoryview")

        stable_record = self._snapshot(record)
        record_length = len(stable_record)
        self._validate_buffer_length(record_length)

        field_values = dict(
            zip(FRAME_HEADER_FIELD_NAMES, FRAME_HEADER_STRUCT.unpack_from(stable_record))
        )

        for name in _EXPECTED_FIELD_NAMES:
            if field_values[name] != FRAME_HEADER_EXPECTED_VALUES[name]:
                self._raise(f"record_invalid_{name}", f"{name} does not match v1")
        for name in _RESERVED_FIELD_NAMES:
            if field_values[name] != FRAME_HEADER_EXPECTED_VALUES[name]:
                self._raise(f"record_invalid_{name}", f"{name} does not match v1")

        payload_length = field_values["payload_length"]
        if payload_length == 0:
            self._raise("record_payload_length_zero", "payload_length must be non-zero")
        if payload_length > MAX_PAYLOAD:
            self._raise(
                "record_payload_length_exceeds_max",
                f"payload_length {payload_length} exceeds {MAX_PAYLOAD}",
            )

        expected_record_length = HEADER_LENGTH + payload_length
        if record_length < expected_record_length:
            self._raise(
                "record_payload_truncated",
                f"record contains {record_length} bytes, expected {expected_record_length}",
            )
        if record_length > expected_record_length:
            self._raise(
                "record_trailing_bytes",
                f"record contains {record_length} bytes, expected {expected_record_length}",
            )

        return PcieV1Record(**field_values, payload=stable_record[HEADER_LENGTH:])

    def _snapshot(self, record: bytes | bytearray | memoryview) -> bytes:
        """Copy through one bounded export without rereading the caller buffer."""

        view: memoryview | None = None
        try:
            view = self._create_view(record)
            self._validate_buffer_length(view.nbytes)
            return view.tobytes()
        except (BufferError, TypeError, ValueError) as error:
            raise ValidationError(
                message="record buffer cannot be accessed or copied",
                stage=_VALIDATION_STAGE,
                code=_BUFFER_ACCESS_ERROR_CODE,
                cause=error,
            ) from error
        finally:
            if view is not None:
                view.release()

    @staticmethod
    def _create_view(record: bytes | bytearray | memoryview) -> memoryview:
        """Create the one parser-owned export used to make a snapshot."""

        return memoryview(record)

    @staticmethod
    def _validate_buffer_length(record_length: int) -> None:
        if record_length < HEADER_LENGTH:
            PcieV1RecordParser._raise(
                "record_header_truncated",
                f"record contains {record_length} bytes, shorter than its complete header",
            )
        maximum_record_length = HEADER_LENGTH + MAX_PAYLOAD
        if record_length > maximum_record_length:
            PcieV1RecordParser._raise(
                "record_too_large",
                f"record contains {record_length} bytes, exceeding {maximum_record_length}",
            )

    @staticmethod
    def _raise(code: str, message: str) -> None:
        raise ValidationError(message=message, stage=_VALIDATION_STAGE, code=code)
