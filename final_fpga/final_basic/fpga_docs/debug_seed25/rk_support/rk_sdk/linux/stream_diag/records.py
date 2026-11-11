"""Strict selected AJPG record boundaries; no recovery or resynchronization."""
from __future__ import annotations

from dataclasses import dataclass
from typing import BinaryIO, Iterator

from linux.task3_pipeline import pcie_protocol_v1 as protocol
from linux.task3_pipeline.record_selection import header_length
from linux.task3_pipeline.record_v2 import RecordMetadata, RecordV2Error, parse_metadata
from linux.task3_pipeline.record_v3 import SparseRecords, RecordV3Error, parse_sparse
from linux.task3_pipeline.record_v4 import SparseLaneRecords, RecordV4Error, parse_sparse as parse_sparse_v4


class RecordError(ValueError):
    pass


@dataclass(frozen=True)
class Record:
    sequence: int
    width: int
    height: int
    timestamp_ns: int
    jpeg: bytes
    metadata: RecordMetadata | None = None
    s07: SparseRecords | SparseLaneRecords | None = None


def parse_header(data: bytes, *, expected_version: int = protocol.PROTOCOL_VERSION) -> dict[str, object]:
    length_expected = header_length(expected_version)
    if len(data) != length_expected:
        raise RecordError(f"short AJPG header: {len(data)}")
    header = dict(zip(protocol.FRAME_HEADER_FIELD_NAMES,
                      protocol.FRAME_HEADER_STRUCT.unpack(data[:protocol.FRAME_HEADER_SIZE]), strict=True))
    for key, expected in protocol.FRAME_HEADER_EXPECTED_VALUES.items():
        if key == "protocol_version":
            expected = expected_version
        elif key == "header_length":
            expected = length_expected
        if header[key] != expected:
            raise RecordError(f"invalid AJPG {key}")
    length = int(header["payload_length"])
    if not 4 <= length <= protocol.MAX_PAYLOAD:
        raise RecordError(f"invalid AJPG payload_length: {length}")
    if header["compression"] != 1 or header["status"] or header["error_code"]:
        raise RecordError("AJPG is not a successful JPEG record")
    if not header["width"] or not header["height"]:
        raise RecordError("AJPG dimensions must be positive")
    slots = (protocol.SLOT_COUNT if expected_version == protocol.PROTOCOL_VERSION
             else protocol.PCIE_RECORD_V2_SLOT_COUNT)
    if int(header["slot_id"]) >= slots:
        raise RecordError("AJPG slot_id is out of range")
    if expected_version in (protocol.PCIE_RECORD_V2_VERSION, protocol.PCIE_RECORD_V3_VERSION,
                            protocol.PCIE_RECORD_V4_VERSION):
        try:
            header["metadata"] = parse_metadata(data[protocol.FRAME_HEADER_SIZE:protocol.PCIE_RECORD_V2_HEADER_LENGTH], header)
            if expected_version == protocol.PCIE_RECORD_V3_VERSION:
                header["s07"] = parse_sparse(data[protocol.PCIE_RECORD_V2_HEADER_LENGTH:], header["metadata"])
            elif expected_version == protocol.PCIE_RECORD_V4_VERSION:
                header["s07"] = parse_sparse_v4(data[protocol.FRAME_HEADER_SIZE:], header["metadata"])
        except (RecordV2Error, RecordV3Error, RecordV4Error) as exc:
            raise RecordError(str(exc)) from exc
    # CRC strategy is not frozen. Do not invent a CRC algorithm here.
    return header


def jpeg_dimensions(jpeg: bytes) -> tuple[int, int]:
    """Walk marker/segment lengths and entropy escapes through exact EOI.

    Hardware decoding remains the authority for entropy and pixel validity.
    Require baseline SOF0 and an SOS; reject concatenation/trailing padding.
    """
    if not jpeg.startswith(b"\xff\xd8"):
        raise RecordError("JPEG SOI missing")
    pos, dimensions, scan = 2, None, False
    while pos < len(jpeg):
        if jpeg[pos] != 0xFF:
            raise RecordError("invalid JPEG marker boundary")
        while pos < len(jpeg) and jpeg[pos] == 0xFF:
            pos += 1
        if pos == len(jpeg):
            raise RecordError("truncated JPEG marker")
        marker = jpeg[pos]
        pos += 1
        if marker == 0xD9:
            if pos != len(jpeg) or dimensions is None or not scan:
                raise RecordError("JPEG premature EOI or trailing bytes")
            return dimensions
        if marker in (0, 0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            raise RecordError("unexpected standalone JPEG marker")
        if pos + 2 > len(jpeg):
            raise RecordError("truncated JPEG segment length")
        size = int.from_bytes(jpeg[pos:pos + 2], "big")
        if size < 2 or pos + size > len(jpeg):
            raise RecordError("truncated JPEG segment")
        segment = jpeg[pos + 2:pos + size]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                      0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            if marker != 0xC0 or dimensions is not None:
                raise RecordError("only one baseline JPEG SOF0 is supported")
            if len(segment) < 6 or segment[0] != 8:
                raise RecordError("invalid baseline JPEG SOF0")
            components = segment[5]
            if components not in (1, 3) or len(segment) != 6 + components * 3:
                raise RecordError("invalid JPEG component table")
            height = int.from_bytes(segment[1:3], "big")
            width = int.from_bytes(segment[3:5], "big")
            if not width or not height:
                raise RecordError("invalid JPEG dimensions")
            dimensions = (width, height)
        pos += size
        if marker == 0xDA:
            if dimensions is None or not segment:
                raise RecordError("JPEG SOS before SOF0")
            if len(segment) != 1 + 2 * segment[0] + 3:
                raise RecordError("invalid JPEG SOS component table")
            scan = True
            # Skip escaped FF and restart markers; stop at the next marker.
            while pos < len(jpeg):
                # C-level search avoids a Python loop over every JPEG byte.
                pos = jpeg.find(b"\xff", pos)
                if pos < 0:
                    raise RecordError("JPEG EOI missing")
                start = pos
                while pos < len(jpeg) and jpeg[pos] == 0xFF:
                    pos += 1
                if pos == len(jpeg):
                    raise RecordError("truncated JPEG entropy marker")
                if jpeg[pos] == 0 or 0xD0 <= jpeg[pos] <= 0xD7:
                    pos += 1
                else:
                    pos = start
                    break
    raise RecordError("JPEG EOI missing")


def parse_record(data: bytes, *, expected_version: int = protocol.PROTOCOL_VERSION) -> Record:
    """Default v1 rejects unsolicited v2; explicit v2 is not negotiation proof."""
    size = header_length(expected_version)
    header = parse_header(data[:size], expected_version=expected_version)
    if len(data) != size + int(header["payload_length"]):
        raise RecordError(f"AJPG length mismatch: got {len(data)} expected "
                          f"{size + int(header['payload_length'])}")
    jpeg = data[size:]
    width, height = jpeg_dimensions(jpeg)
    if (width, height) != (header["width"], header["height"]):
        raise RecordError("JPEG dimensions disagree with AJPG header")
    return Record(int(header["frame_sequence"]), width, height,
                  int(header["timestamp_ns"]), jpeg, header.get("metadata"), header.get("s07"))


def _read_exact(stream: BinaryIO, size: int) -> bytes:
    parts, remaining = [], size
    while remaining:
        part = stream.read(remaining)
        if not part:
            raise RecordError(f"truncated record stream: missing {remaining} bytes")
        parts.append(part)
        remaining -= len(part)
    return b"".join(parts)


def iter_records(stream: BinaryIO, *, expected_version: int = protocol.PROTOCOL_VERSION) -> Iterator[bytes]:
    """Concatenated records have no padding. EOF only allowed between records."""
    size = header_length(expected_version)
    while True:
        first = stream.read(1)
        if not first:
            return
        header_bytes = first + _read_exact(stream, size - 1)
        header = parse_header(header_bytes, expected_version=expected_version)
        data = header_bytes + _read_exact(stream, int(header["payload_length"]))
        parse_record(data, expected_version=expected_version)
        yield data
