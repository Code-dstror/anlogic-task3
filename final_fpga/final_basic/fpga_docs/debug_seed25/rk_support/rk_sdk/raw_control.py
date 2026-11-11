"""Select ARAW on the caller's serialized cold C2H owner."""

from dataclasses import dataclass
import math
import time

from dual_host import pcie_protocol_v1 as p
from dual_host import stereo_control_v1 as stereo
from dual_host.stereo_control import (
    StereoControlError, StereoControlTimeout, StereoSelection, select_cold_mode,
)
from raw_video_constants import (
    PCIE_RAW_VIDEO_ACTIVE_PRODUCT, PCIE_RAW_VIDEO_HEADER_BYTES,
    PCIE_RAW_VIDEO_PRODUCT_JPEG, PCIE_RAW_VIDEO_PRODUCT_RAW, PCIE_RAW_VIDEO_REQUEST_PRODUCT,
)


# Production ARAW uses the same 1920 × 1080 RAW10 raster as the two capture paths.
RAW1080_RECORD_BYTES = PCIE_RAW_VIDEO_HEADER_BYTES + (p.PCIE_CFG_V2_WIDTH // 4) * 5 * p.PCIE_CFG_V2_HEIGHT


@dataclass(frozen=True, slots=True)
class RawSelection:
    topology: StereoSelection
    cameras: int
    mode_epoch: int

    @property
    def session(self) -> int:
        return self.topology.cfg_session


def select_cold_raw(bar, *, cameras: int, max_record_bytes: int, timeout_s: float,
                    poll_interval_s: float, monotonic=time.monotonic, sleep=time.sleep) -> RawSelection:
    """Apply RAW and mono/dual topology before ARM, using the active plain SDR BOOT."""
    if type(cameras) is not int or cameras not in (1, 2):
        raise ValueError("cameras must be 1 or 2")
    if type(max_record_bytes) is not int or max_record_bytes < RAW1080_RECORD_BYTES:
        raise ValueError(f"C2H capacity must hold a {RAW1080_RECORD_BYTES}-byte ARAW record")
    if type(timeout_s) not in (int, float) or not math.isfinite(timeout_s) or timeout_s <= 0:
        raise ValueError("timeout_s must be positive and finite")
    deadline = monotonic() + timeout_s
    mode = stereo.STEREO_MODES_MONO if cameras == 1 else stereo.STEREO_MODES_DUAL_JPEG

    def check_deadline():
        if monotonic() >= deadline:
            raise StereoControlTimeout("cold RAW selection deadline expired")

    def read(offset):
        value = bar.read32(offset)
        if type(value) is not int or not 0 <= value <= 0xffffffff:
            raise StereoControlError(f"read32(0x{offset:03x}) returned a non-uint32 value")
        if offset == p.PCIE_REG_STATUS and (
                value & p.PCIE_STATUS_SESSION_ARMED or not value & p.PCIE_STATUS_SESSION_REARM_READY):
            raise StereoControlError("RAW selection requires the pre-ARM rearm-ready boundary")
        return value

    def write(offset, value):
        check_deadline()
        if offset == p.PCIE_REG_STEREO_REQUEST_MODE:
            # Probe both product registers and validate plain SDR after CFG BOOT,
            # before making any topology write.
            if (read(PCIE_RAW_VIDEO_REQUEST_PRODUCT) != PCIE_RAW_VIDEO_PRODUCT_JPEG
                    or read(PCIE_RAW_VIDEO_ACTIVE_PRODUCT) != PCIE_RAW_VIDEO_PRODUCT_JPEG):
                raise StereoControlError("RAW requires an unstaged JPEG product at cold BOOT")
            if read(p.PCIE_REG_CFG_ACTIVE_FLAGS) or read(p.PCIE_REG_CFG_EXT_ACTIVE_BASE):
                raise StereoControlError("RAW requires the plain SDR BOOT configuration")
            if cameras == 1:
                # The N2 driver allows DUAL1 only. A fresh MONO BOOT already
                # has the requested and active topology at zero.
                if (read(p.PCIE_REG_STEREO_REQUEST_MODE) != mode
                        or read(p.PCIE_REG_STEREO_ACTIVE_MODE) != mode):
                    raise StereoControlError("MONO RAW requires a fresh MONO topology")
                return
        if offset == p.PCIE_REG_STEREO_COMMAND:
            bar.write32(PCIE_RAW_VIDEO_REQUEST_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_RAW)
            if read(PCIE_RAW_VIDEO_REQUEST_PRODUCT) != PCIE_RAW_VIDEO_PRODUCT_RAW:
                raise StereoControlError("RAW REQUEST_PRODUCT readback mismatch")
            check_deadline()
        bar.write32(offset, value)

    topology = select_cold_mode(read, write, mode, timeout_s=timeout_s,
                                poll_interval_s=poll_interval_s, frame_divisor=2 if cameras == 2 else None,
                                monotonic=monotonic, sleep=sleep)
    if read(PCIE_RAW_VIDEO_ACTIVE_PRODUCT) != PCIE_RAW_VIDEO_PRODUCT_RAW:
        raise StereoControlError("APPLY did not acknowledge RAW ACTIVE_PRODUCT")
    busy = p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY | p.PCIE_STATUS_SOURCE_BUSY
    if (read(p.PCIE_REG_STEREO_STATUS) != topology.status
            or read(p.PCIE_REG_CONTROL) & p.PCIE_CONTROL_APP_ENABLE
            or read(p.PCIE_REG_STATUS) & busy
            or read(p.PCIE_REG_CFG_SESSION) != topology.cfg_session
            or read(p.PCIE_REG_CFG_ACTIVE_SESSION) != topology.cfg_session
            or read(p.PCIE_REG_CFG_MODE_EPOCH) != 0):
        raise StereoControlError("cold RAW ownership or CFG BOOT identity changed at APPLY")
    check_deadline()
    return RawSelection(topology, cameras, 0)
