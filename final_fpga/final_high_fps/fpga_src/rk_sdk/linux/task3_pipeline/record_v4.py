"""Strict RCD4 sparse lane records, decoded only after explicit negotiation.

Offsets/enums come from generated pcie_protocol_v1. The caller supplies the
same record's validated CTX2 metadata; no current MMIO state is consulted.
"""
from __future__ import annotations
from dataclasses import dataclass
from . import pcie_protocol_v1 as p
from .record_v2 import RecordMetadata
from .record_v3 import (ScaleStatistics,FusedCandidate,MultiscaleRecord,
                        MorphologyTerminal,SubpixelRecord,_unpack)


class RecordV4Error(ValueError):
    pass


@dataclass(frozen=True)
class LanePoint:
    native_x: int
    quarter_y: int
    strength: int
    width_quarter: int
    marking_class: int

    @property
    def native_y(self):
        return self.quarter_y*4


@dataclass(frozen=True)
class SparseLaneRecord:
    context: int
    status: int
    roi_begin: int
    roi_end: int
    points: tuple[LanePoint,...]

    @property
    def count(self):
        return len(self.points)


@dataclass(frozen=True)
class SparseLaneRecords:
    context: int
    enabled: int
    frame_error: bool
    f22: MultiscaleRecord | None
    f23: SparseLaneRecord | None
    f24: MorphologyTerminal | None
    f25: SubpixelRecord | None


def parse_sparse(extension: bytes, metadata: RecordMetadata) -> SparseLaneRecords:
    """Decode the complete 2048B extension, including its first128B CTX2."""
    if len(extension)!=p.PCIE_RECORD_V4_EXTENSION_WIDTH//8:
        raise RecordV4Error('RCD4 extension length')
    if metadata.source is None:
        raise RecordV4Error('RCD4 requires same-record SOURCE')
    source=metadata.source
    context=(source.session | (source.epoch<<32) | (source.sequence<<64) |
             (source.camera<<96) | (source.kind<<104) | (source.format<<112) |
             (1<<120) | (1<<144))

    def scalar(name,size=1):
        offset=getattr(p,'PCIE_RECORD_V4_OFFSET_'+name)
        return int.from_bytes(extension[offset:offset+size],'little')

    if (scalar('MAGIC',4)!=p.PCIE_RECORD_V4_SPARSE_MAGIC or
        scalar('SCHEMA')!=p.PCIE_RECORD_V4_SPARSE_SCHEMA or
        scalar('POINT_BYTES')!=p.PCIE_RECORD_V4_POINT_BYTES or
        scalar('ROI_BEGIN',2)!=p.PCIE_RECORD_V4_ROI_BEGIN or
        scalar('ROI_END',2)!=p.PCIE_RECORD_V4_ROI_END):
        raise RecordV4Error('RCD4 magic/schema/geometry')
    enabled=scalar('ENABLED');frame_error=scalar('FRAME_ERROR');status=scalar('LANE_STATUS')
    count=scalar('COUNT',2)
    if (enabled&~15 or scalar('PRESENT')!=enabled or
        (enabled&14 and not enabled&1) or frame_error not in (0,1)):
        raise RecordV4Error('RCD4 enabled/present/dependency/frame_error')
    if count>p.PCIE_RECORD_V4_POINT_COUNT_MAX:
        raise RecordV4Error('RCD4 point count exceeds303')
    statuses=(p.PCIE_RECORD_V4_STATUS_OK,p.PCIE_RECORD_V4_STATUS_NO_CANDIDATES,
              p.PCIE_RECORD_V4_STATUS_LOCAL_ERROR,p.PCIE_RECORD_V4_STATUS_SOURCE_ERROR)
    if status not in statuses:
        raise RecordV4Error('RCD4 lane status')
    if not enabled&2:
        if count or status!=p.PCIE_RECORD_V4_STATUS_OK:
            raise RecordV4Error('disabled RCD4 lane must have zero count/status')
    elif (status==p.PCIE_RECORD_V4_STATUS_OK)!=(count>0):
        raise RecordV4Error('RCD4 successful lane/count disagreement')
    if count and status!=p.PCIE_RECORD_V4_STATUS_OK:
        raise RecordV4Error('RCD4 failed lane publishes points')
    if status==p.PCIE_RECORD_V4_STATUS_SOURCE_ERROR and not frame_error:
        raise RecordV4Error('RCD4 SOURCE failure/status disagreement')

    bodies=[]
    for bit,name,width in [(0,'F22',524),(2,'F24',48),(3,'F25',105)]:
        offset=getattr(p,'PCIE_RECORD_V4_OFFSET_'+name)
        value=int.from_bytes(extension[offset:offset+(width+7)//8],'little')
        if value>>width or (not enabled&(1<<bit) and value):
            raise RecordV4Error('RCD4 disabled body or high padding bits')
        bodies.append(value)
    reserved_start=p.PCIE_RECORD_V4_OFFSET_F25+(105+7)//8
    if any(extension[reserved_start:p.PCIE_RECORD_V4_POINTS_OFFSET]):
        raise RecordV4Error('RCD4 reserved prefix bytes')
    used_end=p.PCIE_RECORD_V4_POINTS_OFFSET+count*p.PCIE_RECORD_V4_POINT_BYTES
    if any(extension[used_end:]):
        raise RecordV4Error('RCD4 unpublished point/tail bytes must be zero')

    points=[];previous=None;row_count=0
    for i in range(count):
        offset=p.PCIE_RECORD_V4_POINTS_OFFSET+i*p.PCIE_RECORD_V4_POINT_BYTES
        word=int.from_bytes(extension[offset:offset+p.PCIE_RECORD_V4_POINT_BYTES],'little')
        def field(name):
            return (word>>getattr(p,'PCIE_RECORD_V4_POINT_OFFSET_'+name))&((1<<getattr(p,'PCIE_RECORD_V4_POINT_WIDTH_'+name))-1)
        point=LanePoint(field('X'),field('Y'),field('STRENGTH'),field('WIDTH'),field('CLASS'))
        if (word>>37 or point.native_x>=1920 or
            not p.PCIE_RECORD_V4_ROI_BEGIN<=point.quarter_y<=p.PCIE_RECORD_V4_ROI_END or
            point.strength>2040 or not 1<=point.width_quarter<=8 or
            point.marking_class not in (p.PCIE_RECORD_V4_CLASS_WHITE,p.PCIE_RECORD_V4_CLASS_YELLOW)):
            raise RecordV4Error('RCD4 invalid point fields/reserved')
        if previous is not None and (point.quarter_y<previous.quarter_y or
            (point.quarter_y==previous.quarter_y and point.native_x-previous.native_x<24)):
            raise RecordV4Error('RCD4 point ordering/separation')
        row_count=row_count+1 if previous is not None and point.quarter_y==previous.quarter_y else 1
        if row_count>3:raise RecordV4Error('RCD4 more than3 points per row')
        points.append(point);previous=point
    f22=f24=f25=None
    if enabled&1:
        fields=_unpack(bodies[0],p.RECORD_V3_FIELDS_F22)
        scales=tuple(ScaleStatistics(**_unpack(fields.pop(f'scale{i}'),p.RECORD_V3_FIELDS_SCALE)) for i in range(3))
        fused=FusedCandidate(**_unpack(fields.pop('fused'),p.RECORD_V3_FIELDS_FUSED))
        f22=MultiscaleRecord(context,**fields,scales=scales,fused=fused,original_record=(context<<524)|bodies[0])
    if enabled&4:
        f24=MorphologyTerminal(context,**_unpack(bodies[1],p.RECORD_V3_FIELDS_F24),original_record=(context<<48)|bodies[1])
    if enabled&8:
        f25=SubpixelRecord(context,**_unpack(bodies[2],p.RECORD_V3_FIELDS_F25),original_record=(context<<105)|bodies[2])
    lane=SparseLaneRecord(context,status,p.PCIE_RECORD_V4_ROI_BEGIN,p.PCIE_RECORD_V4_ROI_END,tuple(points)) if enabled&2 else None
    return SparseLaneRecords(context,enabled,bool(frame_error),f22,lane,f24,f25)


def parse(data: bytes):
    from linux.stream_diag.records import parse_record
    return parse_record(data,expected_version=p.PCIE_RECORD_V4_VERSION)
