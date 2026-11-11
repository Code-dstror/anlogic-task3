"""Explicit RCD3 sparse decoding; complete F24 mask transport remains pending."""
from __future__ import annotations

from dataclasses import dataclass

from . import pcie_protocol_v1 as p
from .record_v2 import RecordMetadata


class RecordV3Error(ValueError):
    pass


def _unpack(value: int, fields):
    """Decode the original modules' high-to-low packed field order."""
    result = {}
    for name, width, signed in reversed(fields):
        field = value & ((1 << width) - 1)
        value >>= width
        if signed and field & (1 << (width - 1)):
            field -= 1 << width
        result[name] = field
    if value:
        raise RecordV3Error("typed record exceeds its declared width")
    return result


def _fields(*fields):
    return tuple((name, width, False) for name, width in fields)


@dataclass(frozen=True)
class ScaleStatistics:
    width: int
    height: int
    pixels_seen: int
    strong_count: int
    gradient_sum: int
    peak_gradient: int
    peak_x: int
    peak_y: int
    candidate_valid: int


@dataclass(frozen=True)
class FusedCandidate:
    scale: int
    peak_gradient: int
    native_x: int
    native_y: int
    valid: int


@dataclass(frozen=True)
class MultiscaleRecord:
    context: int
    ok: int
    error: int
    width: int
    height: int
    threshold: int
    scales: tuple[ScaleStatistics, ...]
    fused: FusedCandidate
    original_record: int


@dataclass(frozen=True)
class LaneSide:
    count: int
    sum_native_x: int
    strength_sum: int
    peak: int
    peak_native_x: int
    peak_native_y: int
    valid: int


@dataclass(frozen=True)
class LaneStrip:
    native_y_begin: int
    native_y_end_exclusive: int
    left: LaneSide
    right: LaneSide


@dataclass(frozen=True)
class LaneRecord:
    context: int
    ok: int
    error: int
    frame_valid: int
    width: int
    height: int
    quarter_width: int
    quarter_height: int
    threshold: int
    gx_min: int
    ratio_shift: int
    direction_sign: int
    min_count: int
    min_paired_strips: int
    pixels_seen: int
    strips: tuple[LaneStrip, ...]
    original_record: int


@dataclass(frozen=True)
class MorphologyTerminal:
    context: int
    ok: int
    error: int
    threshold: int
    mode: int
    output_pixels: int
    overflow: int
    original_record: int


@dataclass(frozen=True)
class SubpixelRecord:
    context: int
    tag: int
    ok: int
    error: int
    x_q8: int
    delta_q8: int
    native_y: int
    spacing: int
    curvature: int
    original_record: int


@dataclass(frozen=True)
class SparseRecords:
    context: int
    enabled: int
    frame_error: bool
    f22: MultiscaleRecord | None
    f23: LaneRecord | None
    f24: MorphologyTerminal | None
    f25: SubpixelRecord | None


def parse_sparse(data: bytes, metadata: RecordMetadata) -> SparseRecords:
    """Reconstruct every original bit using this record's complete SOURCE."""
    if len(data) != p.PCIE_RECORD_V3_SPARSE_BYTES:
        raise RecordV3Error("short RCD3 sparse section")
    source = metadata.source
    if source is None:
        raise RecordV3Error("RCD3 sparse section requires real same-record SOURCE")
    context = (source.session | (source.epoch << 32) | (source.sequence << 64)
               | (source.camera << 96) | (source.kind << 104) | (source.format << 112)
               | (1 << 120) | (1 << 144))
    packed = int.from_bytes(data, "little")

    def field(name):
        offset = getattr(p, "PCIE_RECORD_V3_SPARSE_OFFSET_" + name)
        width = getattr(p, "PCIE_RECORD_V3_SPARSE_WIDTH_" + name)
        return (packed >> offset) & ((1 << width) - 1)

    if (field("MAGIC") != p.PCIE_RECORD_V3_SPARSE_MAGIC
            or field("SCHEMA") != p.PCIE_RECORD_V3_SPARSE_SCHEMA
            or field("STRIPS") != p.PCIE_RECORD_V3_STRIPS
            or packed & ~p.PCIE_RECORD_V3_SPARSE_ALLOWED_MASK):
        raise RecordV3Error("invalid RCD3 sparse schema/strips/reserved bits")
    enabled = field("ENABLED")
    if field("PRESENT") != enabled or (enabled & 14 and not enabled & 1):
        raise RecordV3Error("RCD3 enabled report missing or invalid dependency")
    bodies = tuple(field(name) for name in ("F22", "F23", "F24", "F25"))
    if any(body and not enabled & (1 << i) for i, body in enumerate(bodies)):
        raise RecordV3Error("disabled RCD3 report must be zero")

    f22 = None
    if enabled & 1:
        fields = _unpack(bodies[0], p.RECORD_V3_FIELDS_F22)
        scales = tuple(ScaleStatistics(**_unpack(fields.pop(f"scale{i}"), p.RECORD_V3_FIELDS_SCALE))
                       for i in range(3))
        fused = FusedCandidate(**_unpack(fields.pop("fused"), p.RECORD_V3_FIELDS_FUSED))
        f22 = MultiscaleRecord(context, **fields, scales=scales, fused=fused,
                              original_record=(context << 524) | bodies[0])
    f23 = None
    if enabled & 2:
        fields = _unpack(bodies[1] >> 1064, p.RECORD_V3_FIELDS_F23_HEADER)
        strips = []
        for i in range(4):
            strip = _unpack((bodies[1] >> (266*i)) & ((1 << 266)-1), p.RECORD_V3_FIELDS_STRIP)
            sides = {}
            for side in ("left", "right"):
                sides[side] = LaneSide(**_unpack(strip.pop(side), p.RECORD_V3_FIELDS_SIDE))
            strips.append(LaneStrip(**strip, **sides))
        f23 = LaneRecord(context, **fields, strips=tuple(strips),
                         original_record=(context << 1196) | bodies[1])
    f24 = None
    if enabled & 4:
        fields = _unpack(bodies[2], p.RECORD_V3_FIELDS_F24)
        f24 = MorphologyTerminal(context, **fields, original_record=(context << 48) | bodies[2])
    f25 = None
    if enabled & 8:
        fields = _unpack(bodies[3], p.RECORD_V3_FIELDS_F25)
        f25 = SubpixelRecord(context, **fields, original_record=(context << 105) | bodies[3])
    return SparseRecords(context, enabled, bool(field("FRAME_ERROR")), f22, f23, f24, f25)
