"""Generated from doc/pcie_protocol_v1.json. Do not edit by hand."""

from __future__ import annotations

import struct

FRAME_HEADER_BYTE_ORDER = "little"
FRAME_HEADER_SIZE = 64
FRAME_MAGIC = 0x47504A41
PROTOCOL_VERSION = 1
HEADER_LENGTH = 64
MAX_PAYLOAD = 16777216

FRAME_HEADER_FORMAT = "<IHHIIHHBBBBQIIHHI16s"
FRAME_HEADER_STRUCT = struct.Struct(FRAME_HEADER_FORMAT)

FRAME_HEADER_FIELD_NAMES = (
    "frame_magic",
    "protocol_version",
    "header_length",
    "frame_sequence",
    "payload_length",
    "width",
    "height",
    "pixel_format",
    "compression",
    "quality",
    "flags",
    "timestamp_ns",
    "status",
    "error_code",
    "slot_id",
    "reserved0",
    "payload_crc32",
    "reserved1",
)
FRAME_HEADER_FIELD_OFFSETS = {
    "frame_magic": 0,
    "protocol_version": 4,
    "header_length": 6,
    "frame_sequence": 8,
    "payload_length": 12,
    "width": 16,
    "height": 18,
    "pixel_format": 20,
    "compression": 21,
    "quality": 22,
    "flags": 23,
    "timestamp_ns": 24,
    "status": 32,
    "error_code": 36,
    "slot_id": 40,
    "reserved0": 42,
    "payload_crc32": 44,
    "reserved1": 48,
}
FRAME_HEADER_FIELD_SIZES = {
    "frame_magic": 4,
    "protocol_version": 2,
    "header_length": 2,
    "frame_sequence": 4,
    "payload_length": 4,
    "width": 2,
    "height": 2,
    "pixel_format": 1,
    "compression": 1,
    "quality": 1,
    "flags": 1,
    "timestamp_ns": 8,
    "status": 4,
    "error_code": 4,
    "slot_id": 2,
    "reserved0": 2,
    "payload_crc32": 4,
    "reserved1": 16,
}
FRAME_HEADER_FIELD_TYPES = {
    "frame_magic": "u32",
    "protocol_version": "u16",
    "header_length": "u16",
    "frame_sequence": "u32",
    "payload_length": "u32",
    "width": "u16",
    "height": "u16",
    "pixel_format": "u8",
    "compression": "u8",
    "quality": "u8",
    "flags": "u8",
    "timestamp_ns": "u64",
    "status": "u32",
    "error_code": "u32",
    "slot_id": "u16",
    "reserved0": "u16",
    "payload_crc32": "u32",
    "reserved1": "bytes",
}

FRAME_MAGIC_OFFSET = 0
FRAME_MAGIC_SIZE = 4
PROTOCOL_VERSION_OFFSET = 4
PROTOCOL_VERSION_SIZE = 2
HEADER_LENGTH_OFFSET = 6
HEADER_LENGTH_SIZE = 2
FRAME_SEQUENCE_OFFSET = 8
FRAME_SEQUENCE_SIZE = 4
PAYLOAD_LENGTH_OFFSET = 12
PAYLOAD_LENGTH_SIZE = 4
WIDTH_OFFSET = 16
WIDTH_SIZE = 2
HEIGHT_OFFSET = 18
HEIGHT_SIZE = 2
PIXEL_FORMAT_OFFSET = 20
PIXEL_FORMAT_SIZE = 1
COMPRESSION_OFFSET = 21
COMPRESSION_SIZE = 1
QUALITY_OFFSET = 22
QUALITY_SIZE = 1
FLAGS_OFFSET = 23
FLAGS_SIZE = 1
TIMESTAMP_NS_OFFSET = 24
TIMESTAMP_NS_SIZE = 8
STATUS_OFFSET = 32
STATUS_SIZE = 4
ERROR_CODE_OFFSET = 36
ERROR_CODE_SIZE = 4
SLOT_ID_OFFSET = 40
SLOT_ID_SIZE = 2
RESERVED0_OFFSET = 42
RESERVED0_SIZE = 2
PAYLOAD_CRC32_OFFSET = 44
PAYLOAD_CRC32_SIZE = 4
RESERVED1_OFFSET = 48
RESERVED1_SIZE = 16

FRAME_HEADER_EXPECTED_VALUES = {
    "frame_magic": 1196444225,
    "protocol_version": 1,
    "header_length": 64,
    "flags": 1,
    "reserved0": 0,
    "reserved1": b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',
}
FRAME_HEADER_FRAME_MAGIC_EXPECTED = 1196444225
FRAME_HEADER_PROTOCOL_VERSION_EXPECTED = 1
FRAME_HEADER_HEADER_LENGTH_EXPECTED = 64
FRAME_HEADER_FLAGS_EXPECTED = 1
FRAME_HEADER_RESERVED0_EXPECTED = 0
FRAME_HEADER_RESERVED1_EXPECTED = b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
FLAGS_EXPECTED = FRAME_HEADER_FLAGS_EXPECTED
