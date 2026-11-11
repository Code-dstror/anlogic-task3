"""Decode one complete ARAW record received by the existing C2H owner."""

from dataclasses import dataclass
from struct import Struct

if __package__:
    from . import raw_video_constants as p
    from .linux.task3_pipeline.raw_frame_store import unpack_raw10
else:
    import raw_video_constants as p
    from linux.task3_pipeline.raw_frame_store import unpack_raw10


_HEADER = Struct("<IHHIHHIII4BQQ16s")


class RawVideoError(ValueError):
    """A record failed ARAW wire or SOURCE identity validation."""


def raw10_record_bytes(width: int, height: int) -> int:
    """Return the exact size of an ARAW header and a packed RAW10 raster."""
    if type(width) is not int or type(height) is not int or width <= 0 or width % 4 or height <= 0:
        raise ValueError("ARAW dimensions require complete four-pixel groups per row")
    return p.PCIE_RAW_VIDEO_HEADER_BYTES + (width // 4) * 5 * height


@dataclass(frozen=True, slots=True)
class RawVideoFrame:
    width: int
    height: int
    source_sequence: int
    source_session: int
    mode_epoch: int
    camera: int
    bayer_phase: int
    capture_time_ns: int | None
    job_id: int
    payload: memoryview

    def unpack_samples(self) -> list[int]:
        """Reconstruct raster-ordered 10-bit Bayer samples."""
        return unpack_raw10(self.payload, self.width * self.height)


def parse_raw_video(record: bytes | bytearray | memoryview) -> RawVideoFrame:
    """Validate an exact C2H record and borrow its packed RAW10 bytes.

    The receiver must hold the source buffer until consumers finish using the
    returned payload view. Bayer phase 0/1/2/3 means RGGB/GRBG/GBRG/BGGR.
    """
    try:
        data = memoryview(record).cast("B").toreadonly()
    except (BufferError, TypeError, ValueError) as error:
        raise RawVideoError("ARAW requires a contiguous byte buffer") from error

    if len(data) < _HEADER.size:
        raise RawVideoError("truncated ARAW header")
    (magic, version, header_bytes, payload_bytes, width, height,
     sequence, session, epoch, camera, raw_format, bayer, flags,
     time_ns, job_id, reserved) = _HEADER.unpack_from(data)
    if (magic, version, header_bytes) != (p.PCIE_RAW_VIDEO_MAGIC,
                                         p.PCIE_RAW_VIDEO_VERSION,
                                         p.PCIE_RAW_VIDEO_HEADER_BYTES):
        raise RawVideoError("ARAW magic, version or header size")
    if reserved != bytes(16) or flags & ~p.PCIE_RAW_VIDEO_FLAG_TIMESTAMP_VALID:
        raise RawVideoError("ARAW reserved fields")
    if camera > 1 or bayer > 3 or raw_format != p.PCIE_RAW_VIDEO_FORMAT_RAW10:
        raise RawVideoError("ARAW camera, Bayer phase or RAW10 format")
    if not session or not job_id:
        raise RawVideoError("ARAW source session or job identity")
    if not width or width % 4 or not height:
        raise RawVideoError("ARAW dimensions require complete four-pixel groups per row")
    if (header_bytes + payload_bytes != raw10_record_bytes(width, height) or
            not 0 < payload_bytes <= p.PCIE_RAW_VIDEO_PAYLOAD_MAX_BYTES or
            len(data) != header_bytes + payload_bytes):
        raise RawVideoError("ARAW payload size disagrees with dimensions or delivered length")

    capture_time_ns = time_ns if flags & p.PCIE_RAW_VIDEO_FLAG_TIMESTAMP_VALID else None
    return RawVideoFrame(width, height, sequence, session, epoch, camera, bayer,
                         capture_time_ns, job_id, data[header_bytes:])


class RawVideoReceiver:
    """Check a single C2H owner's applied SOURCE identity and per-eye order."""

    def __init__(self, *, session: int, mode_epoch: int, cameras: int, width: int, height: int):
        if type(cameras) is not int or cameras not in (1, 2):
            raise ValueError("ARAW receiver requires one or two cameras")
        self._source = session, mode_epoch
        self._geometry = width, height
        self._last_sequence = [-1] * cameras

    def accept(self, record: bytes | bytearray | memoryview) -> RawVideoFrame:
        """Validate one complete record while preserving the caller's buffer lease."""
        frame = parse_raw_video(record)
        if ((frame.source_session, frame.mode_epoch) != self._source or
                frame.camera >= len(self._last_sequence) or
                (frame.width, frame.height) != self._geometry):
            raise RawVideoError("ARAW SOURCE does not match the applied configuration")
        previous = self._last_sequence[frame.camera]
        if frame.source_sequence <= previous:
            raise RawVideoError(f"ARAW camera {frame.camera} SOURCE sequence must exceed {previous}")
        self._last_sequence[frame.camera] = frame.source_sequence
        return frame
