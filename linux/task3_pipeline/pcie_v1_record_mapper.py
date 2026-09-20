"""Pure mapping from a validated PCIe v1 record to a common encoded frame."""

from __future__ import annotations

from .errors import ValidationError
from .models import EncodedFrame, FrameMetadata
from .pcie_v1_record_parser import PcieV1Record


_MAPPING_STAGE = "transport_record_mapping"


def map_pcie_v1_record_to_encoded_frame(
    record: PcieV1Record,
    *,
    ingest_id: int,
    received_monotonic_ns: int,
    source_name: str,
) -> EncodedFrame:
    """Map one validated record using caller-supplied local ingest context.

    This function allocates neither IDs nor timestamps. A zero wire width or
    height becomes ``None`` because ``FrameMetadata`` only accepts positive
    declared dimensions. ``timestamp_ns`` is preserved verbatim, including
    zero, but has no declared clock domain at this boundary.
    """

    if not isinstance(record, PcieV1Record):
        _raise("invalid_record", "record must be a validated PcieV1Record")
    _validate_non_negative_int("ingest_id", ingest_id)
    _validate_non_negative_int("received_monotonic_ns", received_monotonic_ns)
    if not isinstance(source_name, str) or not source_name:
        _raise("invalid_source_name", "source_name must be a non-empty string")
    if record.error_code != 0:
        _raise(
            "record_error_code_nonzero",
            "a PCIe v1 record with a non-zero error_code cannot map to EncodedFrame",
        )

    metadata = FrameMetadata(
        ingest_id=ingest_id,
        source_name=source_name,
        payload_length=record.payload_length,
        received_monotonic_ns=received_monotonic_ns,
        wire_sequence=record.frame_sequence,
        source_timestamp=record.timestamp_ns,
        timestamp_domain=None,
        encoding=None,
        declared_width=record.width or None,
        declared_height=record.height or None,
        integrity={
            "pcie_v1_payload_crc32_declared": record.payload_crc32,
            "pcie_v1_payload_crc32_verified": False,
        },
        protocol_version=record.protocol_version,
        extensions={
            "pcie_v1_compression": record.compression,
            "pcie_v1_pixel_format": record.pixel_format,
            "pcie_v1_quality": record.quality,
            "pcie_v1_status": record.status,
            "pcie_v1_error_code": record.error_code,
        },
    )
    return EncodedFrame(
        metadata=metadata,
        payload=record.payload,
        acquired_monotonic_ns=received_monotonic_ns,
    )


def _validate_non_negative_int(name: str, value: int) -> None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        _raise(f"invalid_{name}", f"{name} must be a non-boolean non-negative integer")


def _raise(code: str, message: str) -> None:
    raise ValidationError(message=message, stage=_MAPPING_STAGE, code=code)
