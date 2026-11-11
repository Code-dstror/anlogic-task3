"""Linux-private strict RCD2 metadata. Layout comes only from generated protocol.

This parser is not a firmware capability claim, a CRC implementation, or a
current-MMIO-to-old-frame association. The caller must explicitly select v2.
"""
from __future__ import annotations

from dataclasses import dataclass

from . import pcie_protocol_v1 as p


class RecordV2Error(ValueError):
    pass


@dataclass(frozen=True)
class SourceStamp:
    session: int
    epoch: int
    sequence: int
    camera: int
    kind: int
    format: int
    role: int


@dataclass(frozen=True)
class NeutralContext:
    session: int
    epoch: int
    sequence: int
    camera: int
    source_kind: int
    source_format: int
    identity_flags: int
    view_id: int
    schema: int


@dataclass(frozen=True)
class NeutralStats:
    sampled: int
    delivered: int
    sum_y: int
    dark: int
    bright: int
    min_y: int
    max_y: int
    dark_threshold: int
    bright_threshold: int
    width: int
    height: int


@dataclass(frozen=True)
class RecordMetadata:
    validity_flags: int
    source: SourceStamp | None
    jpeg_session: int
    jpeg_generation: int
    jpeg_slot: int
    actual_exposure: int | None
    actual_gain: int | None
    calibration_id: int | None
    exposure_group: int
    pair_id: int | None
    job_id: int | None
    write_tag: int | None
    neutral_context: NeutralContext | None
    neutral_stats: NeutralStats | None
    processing_member: int
    processing_mode: int
    time_quality: int
    record_flags: int

    @property
    def qualified(self) -> bool:
        return bool(self.validity_flags & p.PCIE_RECORD_V2_FLAG_QUALIFIED)

    @property
    def schema2_processing_enables(self) -> int | None:
        """Requested frame transforms/analysis, not proof of a prior map use."""
        return (self.processing_mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_ENABLE_MASK
                if self.processing_mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_TAG else None)

    @property
    def dehaze_requested(self) -> bool | None:
        enables = self.schema2_processing_enables
        return None if enables is None else bool(enables & p.PCIE_CFG_V2_ENABLES_DEHAZE)

    @property
    def dehaze_applied(self) -> bool:
        """Actual use of qualified dehaze history on this completed frame."""
        return bool(self.record_flags & p.PCIE_RECORD_V2_PRODUCT_DEHAZE_FILTERED)


def _zero(fields, names):
    for name in names:
        value = fields[name]
        if value != (bytes(len(value)) if isinstance(value, bytes) else 0):
            raise RecordV2Error(f"unknown RCD2 {name} must be zero")


def parse_metadata(extension: bytes, header: dict[str, object]) -> RecordMetadata:
    """Validate one extension against the base header from the same record."""
    if len(extension) != p.RECORD_V2_EXTENSION_STRUCT.size:
        raise RecordV2Error("short RCD2 extension")
    f = dict(zip(p.RECORD_V2_EXTENSION_FIELD_NAMES,
                 p.RECORD_V2_EXTENSION_STRUCT.unpack(extension), strict=True))
    for name, expected in p.RECORD_V2_EXTENSION_EXPECTED_VALUES.items():
        if f[name] != expected:
            raise RecordV2Error(f"invalid RCD2 {name}")
    flags = int(f["validity_flags"])
    known_flags = (p.PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY | p.PCIE_RECORD_V2_FLAG_EXPOSURE
                   | p.PCIE_RECORD_V2_FLAG_GAIN | p.PCIE_RECORD_V2_FLAG_CALIBRATION
                   | p.PCIE_RECORD_V2_FLAG_TIME | p.PCIE_RECORD_V2_FLAG_PAIR
                   | p.PCIE_RECORD_V2_FLAG_JOB | p.PCIE_RECORD_V2_FLAG_WRITE_TAG
                   | p.PCIE_RECORD_V2_FLAG_NEUTRAL_CONTEXT | p.PCIE_RECORD_V2_FLAG_NEUTRAL_STATS
                   | p.PCIE_RECORD_V2_FLAG_QUALIFIED | p.PCIE_RECORD_V2_FLAG_HDR_PRODUCT)
    if flags & ~known_flags:
        raise RecordV2Error("unknown RCD2 validity flags")
    products = int(f["record_flags"])
    mode = int(f['processing_mode'])
    if mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_TAG:
        if (mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_RESERVED_MASK or
                (mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_LANE_MASK and
                 not mode & p.PCIE_RECORD_V2_MODE_SCHEMA2_MULTISCALE_MASK)):
            raise RecordV2Error('invalid tagged schema2 processing_mode')
    elif mode > p.PCIE_RECORD_V2_MODE_LEGACY_MAXIMUM:
        raise RecordV2Error('unknown legacy processing_mode')
    if products & ~(p.PCIE_RECORD_V2_PRODUCT_HDR_MERGED | p.PCIE_RECORD_V2_PRODUCT_NR_FILTERED
                    | p.PCIE_RECORD_V2_PRODUCT_DEHAZE_FILTERED):
        raise RecordV2Error("unknown RCD2 record flags")
    if not f["jpeg_session"] or not f["jpeg_generation"]:
        raise RecordV2Error("RCD2 JPEG session/generation must be nonzero")

    source = None
    source_fields = ("source_session", "source_epoch", "source_sequence", "source_camera",
                     "source_kind", "source_format", "exposure_role")
    if flags & p.PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY:
        if (not f["source_session"] or f["source_camera"] not in (0, 1)
                or f["source_kind"] not in (p.PCIE_RECORD_V2_SOURCE_DIGITAL_REPLAY,
                                            p.PCIE_RECORD_V2_SOURCE_PHYSICAL)
                or f["source_format"] not in (p.PCIE_RECORD_V2_FORMAT_RAW10,
                                              p.PCIE_RECORD_V2_FORMAT_RAW14)
                or f["exposure_role"] not in (p.PCIE_RECORD_V2_ROLE_SINGLE,
                                              p.PCIE_RECORD_V2_ROLE_LONG,
                                              p.PCIE_RECORD_V2_ROLE_SHORT)
                or f["source_sequence"] != header["frame_sequence"]
                or int(header["slot_id"]) // p.PCIE_JPEG_SLOTS_PER_CAMERA != f["source_camera"]):
            raise RecordV2Error("invalid RCD2 source identity/sequence/JPEG camera")
        source = SourceStamp(*(int(f[name]) for name in source_fields))
    else:
        _zero(f, source_fields)
    if flags & p.PCIE_RECORD_V2_FLAG_QUALIFIED and source is None:
        raise RecordV2Error("qualified RCD2 requires source identity")

    optional = {}
    for flag, name in ((p.PCIE_RECORD_V2_FLAG_EXPOSURE, "actual_exposure"),
                       (p.PCIE_RECORD_V2_FLAG_GAIN, "actual_gain"),
                       (p.PCIE_RECORD_V2_FLAG_CALIBRATION, "calibration_id"),
                       (p.PCIE_RECORD_V2_FLAG_PAIR, "pair_id"),
                       (p.PCIE_RECORD_V2_FLAG_JOB, "job_id"),
                       (p.PCIE_RECORD_V2_FLAG_WRITE_TAG, "write_tag")):
        if flags & flag:
            optional[name] = int(f[name])
        else:
            _zero(f, (name,))
            optional[name] = None
    if not flags & p.PCIE_RECORD_V2_FLAG_EXPOSURE:
        _zero(f, ("exposure_group",))
    if flags & p.PCIE_RECORD_V2_FLAG_PAIR and not f["pair_id"]:
        raise RecordV2Error("known RCD2 pair_id must be nonzero")
    time_quality = int(f["time_quality"])
    if flags & p.PCIE_RECORD_V2_FLAG_TIME:
        if time_quality not in (p.PCIE_RECORD_V2_TIME_LOCAL_PIXEL_COUNTER_NS,
                                p.PCIE_RECORD_V2_TIME_COMMON_FPGA_COUNTER_NS):
            raise RecordV2Error("invalid RCD2 time quality")
    elif time_quality != p.PCIE_RECORD_V2_TIME_UNKNOWN or header["timestamp_ns"]:
        raise RecordV2Error("unknown RCD2 time must be zero/UNKNOWN")
    if f["processing_member"] not in (0, 1):
        raise RecordV2Error("invalid RCD2 processing member")

    neutral = None
    if flags & p.PCIE_RECORD_V2_FLAG_NEUTRAL_CONTEXT:
        n = dict(zip(p.RECORD_V2_NEUTRAL_FIELD_NAMES,
                     p.RECORD_V2_NEUTRAL_STRUCT.unpack(f["neutral_context"]), strict=True))
        for name, expected in p.RECORD_V2_NEUTRAL_EXPECTED_VALUES.items():
            if n[name] != expected:
                raise RecordV2Error(f"invalid RCD2 neutral {name}")
        if (source is None or n["identity_flags"] != p.PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY
                or (n["session"], n["epoch"], n["sequence"], n["camera"], n["source_kind"],
                    n["source_format"]) != (source.session, source.epoch, source.sequence,
                    source.camera, source.kind, source.format)):
            raise RecordV2Error("RCD2 neutral context is not this complete source identity")
        neutral = NeutralContext(*(int(n[name]) for name in p.RECORD_V2_NEUTRAL_FIELD_NAMES))
    else:
        _zero(f, ("neutral_context",))

    stats = None
    stat_names = tuple(name for name in p.RECORD_V2_EXTENSION_FIELD_NAMES
                       if name.startswith("neutral_") and name != "neutral_context")
    if flags & p.PCIE_RECORD_V2_FLAG_NEUTRAL_STATS:
        count = int(f["neutral_width"]) * int(f["neutral_height"])
        if (neutral is None or not count or not f["neutral_status_valid"]
                or f["neutral_status_valid"] != 1 or f["neutral_status_ok"] != 1
                or f["neutral_status_error"] or f["neutral_sampled"] != count
                or f["neutral_delivered"] != count
                or not f["neutral_min_y"] <= f["neutral_max_y"]
                or not count*f["neutral_min_y"] <= f["neutral_sum_y"] <= count*f["neutral_max_y"]
                or f["neutral_dark"] > count or f["neutral_bright"] > count):
            raise RecordV2Error("RCD2 neutral statistics are not a complete successful frame")
        stats = NeutralStats(*(int(f["neutral_" + name]) for name in
                               NeutralStats.__dataclass_fields__))
    else:
        _zero(f, stat_names)
    return RecordMetadata(flags, source, int(f["jpeg_session"]), int(f["jpeg_generation"]),
                          int(header["slot_id"]), **optional,
                          exposure_group=int(f["exposure_group"]), neutral_context=neutral,
                          neutral_stats=stats, processing_member=int(f["processing_member"]),
                          processing_mode=int(f["processing_mode"]), time_quality=time_quality,
                          record_flags=products)


def parse(data: bytes):
    """Explicit offline v2 parse, not permission to bypass live negotiation."""
    from linux.stream_diag.records import parse_record
    return parse_record(data, expected_version=p.PCIE_RECORD_V2_VERSION)
