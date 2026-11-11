"""Strict dual-camera AJPG demultiplexing after the sole transport owner.

This module never opens a device, starts DMA, changes FPGA configuration or
infers exposure synchronization. The CLI reads saved complete record streams.
Live integration may pass one complete owned copy from the existing Receiver.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))
from linux.stream_diag.records import Record, RecordError, iter_records, parse_record
from linux.task3_pipeline import pcie_protocol_v1 as p


def forward32(new: int, old: int) -> bool:
    return 0 < ((new - old) & 0xffffffff) < 0x80000000


@dataclass(frozen=True)
class CameraRecord:
    camera: int
    session: int
    epoch: int
    sequence: int
    record: Record
    wire: bytes


@dataclass(frozen=True)
class DecodedCameraFrame:
    source: CameraRecord
    frame: object


class DualVideoConsumer:
    """Synchronous adapter for one existing owner and one persistent MPP context.

    No internal queue or device handle is created. The caller controls bounded
    scheduling and supplies its existing decoder. Copying NV12 is explicit;
    consumers receive the exact SOURCE belonging to the decoded record.
    """
    def __init__(self, decoder, *, record_version: int, source_session: int | None = None,
                 copy_nv12: bool = False, on_frame=None):
        self.demux = DualRecordDemux(record_version=record_version, source_session=source_session)
        self.decoder, self.copy_nv12, self.on_frame = decoder, copy_nv12, on_frame
        self.decoded = [0, 0]
        self.faulted = False

    def consume(self, wire: bytes) -> DecodedCameraFrame:
        if self.faulted:
            raise RuntimeError("dual video consumer faulted; owner must resolve the session")
        try:
            item = self.demux.accept(wire)
            frame = self.decoder.decode_record(item.wire, expected_version=self.demux.version,
                                                copy_nv12=self.copy_nv12)
            if (frame.sequence, frame.width, frame.height) != (
                    item.sequence, item.record.width, item.record.height):
                raise RecordError("MPP result differs from this exact source record")
            if self.copy_nv12 and (type(frame.nv12) is not bytes
                    or frame.hor_stride < frame.width or frame.ver_stride < frame.height
                    or frame.hor_stride % 2 or frame.ver_stride % 2
                    or len(frame.nv12) != frame.hor_stride*frame.ver_stride*3//2):
                raise RecordError("consumer requires one complete independently owned NV12 copy")
            result = DecodedCameraFrame(item, frame)
            if self.on_frame is not None:
                self.on_frame(result)
            self.decoded[item.camera] += 1
            return result
        except Exception:
            self.faulted = True
            raise


class DualRecordDemux:
    """Bounded per-camera ordering; wire metadata is the only camera authority.

    A receiver lifetime has one explicitly selected record version and one
    source session. A changed session requires a new demux after the owner's
    real session boundary. Camera sequences and epochs are independent.
    """
    def __init__(self, *, record_version: int, source_session: int | None = None):
        if type(record_version) is not int or record_version not in (2, 4):
            raise ValueError("dual records require explicitly selected v2 or v4")
        if source_session is not None and (type(source_session) is not int or not 0 < source_session <= 0xffffffff):
            raise ValueError("source_session must be a nonzero u32")
        self.version, self.session = record_version, source_session
        self._jpeg_session: int | None = None
        self._latest: dict[int, tuple[int, int]] = {}
        self._generations: dict[tuple[int, int], int] = {}
        self.frames = [0, 0]
        self.jpeg_bytes = [0, 0]

    def accept(self, wire: bytes) -> CameraRecord:
        # Own a stable copy before parsing; callers may recycle a DMA lease.
        owned = bytes(wire)
        record = parse_record(owned, expected_version=self.version)
        return self._accept_verified(owned, record)

    def _accept_verified(self, owned: bytes, record: Record) -> CameraRecord:
        # Internal continuation after parsing this exact owned record.
        metadata = record.metadata
        if metadata is None or metadata.source is None:
            raise RecordError("dual record has no complete SOURCE identity")
        source = metadata.source
        if self.session is not None and source.session != self.session:
            raise RecordError("source session changed inside selected receiver lifetime")
        if self._jpeg_session is not None and metadata.jpeg_session != self._jpeg_session:
            raise RecordError("JPEG session changed inside selected receiver lifetime")
        previous = self._latest.get(source.camera)
        if previous is not None:
            epoch, sequence = previous
            if source.epoch == epoch:
                if not forward32(source.sequence, sequence):
                    raise RecordError("duplicate/backward sequence for this camera")
            elif not forward32(source.epoch, epoch):
                raise RecordError("backward/ambiguous epoch for this camera")
        slot_key = metadata.jpeg_session, metadata.jpeg_slot
        generation = self._generations.get(slot_key)
        if generation is not None and not forward32(metadata.jpeg_generation, generation):
            raise RecordError("JPEG slot generation was reused or moved backwards")
        # Invalid input cannot update any ordering state.
        self.session = source.session
        self._jpeg_session = metadata.jpeg_session
        self._latest[source.camera] = source.epoch, source.sequence
        self._generations[slot_key] = metadata.jpeg_generation
        self.frames[source.camera] += 1
        self.jpeg_bytes[source.camera] += len(record.jpeg)
        return CameraRecord(source.camera, source.session, source.epoch,
                            source.sequence, record, owned)

    def describe(self) -> dict:
        return {"record_version": self.version, "source_session": self.session,
                "cameras": [{"camera": c, "records": self.frames[c], "jpeg_bytes": self.jpeg_bytes[c]}
                            for c in (0, 1)],
                "physical_sync": "NOT_QUALIFIED", "board": "NOT_RUN",
                "scope": "COMPLETE_OWNED_RECORD_PARSE_AND_DEMUX"}


def copy_completed_lease(lease, demux: DualRecordDemux) -> CameraRecord:
    """Copy/parse a successful native lease; its existing owner still releases it.

    No release is performed here, so the owner can finish any other consumer
    before its one release. Error/cancelled results are never decoded as JPEG.
    """
    from linux.dma_c2h_candidate.c2h_abi import RESULT_COMPLETE
    if lease.result != RESULT_COMPLETE:
        raise RecordError("transport result is not COMPLETE")
    with lease.view() as view:
        wire = bytes(view)
    return demux.accept(wire)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, action="append", required=True,
                    help="saved concatenated complete records; repeat in arrival order")
    ap.add_argument("--output", type=Path, required=True, help="new output directory")
    ap.add_argument("--record-version", type=int, choices=(2, 4), required=True)
    ap.add_argument("--source-session", type=int)
    args = ap.parse_args()
    demux = DualRecordDemux(record_version=args.record_version, source_session=args.source_session)
    args.output.mkdir(parents=True, exist_ok=False)
    index = []
    for path in args.input:
        with path.open("rb") as stream:
            for wire in iter_records(stream, expected_version=args.record_version):
                item = demux.accept(wire)
                name = f"camera{item.camera}_s{item.session}_e{item.epoch}_f{item.sequence}"
                (args.output / (name + ".jpg")).write_bytes(item.record.jpeg)
                (args.output / (name + ".record.bin")).write_bytes(item.wire)
                m = item.record.metadata
                index.append({"file": name, "source": {"camera": item.camera,
                    "session": item.session, "epoch": item.epoch, "sequence": item.sequence},
                    "jpeg_slot": m.jpeg_slot, "jpeg_generation": m.jpeg_generation,
                    "jpeg_session": m.jpeg_session, "timestamp_ns": item.record.timestamp_ns,
                    "time_quality": m.time_quality,
                    "wire_sha256": hashlib.sha256(item.wire).hexdigest()})
    summary = {**demux.describe(), "status": "PASS_SAVED_RECORDS", "records": index}
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "records"}))


if __name__ == "__main__":
    main()
