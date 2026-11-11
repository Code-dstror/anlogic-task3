"""Select an explicit dual-camera SDR rate on the existing cold C2H owner."""

import math
import time
from types import SimpleNamespace

from dual_host import pcie_protocol_v1 as p
from dual_host import stereo_control_v1 as stereo
from dual_host.stereo_control import StereoControlError, StereoControlTimeout, StereoSelection, select_cold_mode
from raw_control import RawSelection, select_cold_raw
from raw_video_constants import (
    PCIE_RAW_VIDEO_ACTIVE_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_JPEG, PCIE_RAW_VIDEO_REQUEST_PRODUCT,
)
from rate_control_constants import (
    PCIE_RATE_CAPABILITIES, PCIE_RATE_CODE_FPS40, PCIE_RATE_CODE_FPS45,
    PCIE_RATE_CODE_FPS48, PCIE_RATE_REG_ACTIVE, PCIE_RATE_REG_CAPABILITIES, PCIE_RATE_REG_REQUEST,
)


def select_cold_dual_rate(bar, *, fps: int, timeout_s: float, poll_interval_s: float,
                         raw_max_record_bytes: int | None = None, monotonic=time.monotonic,
                         sleep=time.sleep) -> StereoSelection | RawSelection:
    """Apply DUAL and SDR rate on a serialized pre-ARM owner.

    Supplying the actual record capacity also selects RAW. The result confirms
    cold APPLY; sensor configuration, ARM and START follow their normal path.
    """
    rates = {40: PCIE_RATE_CODE_FPS40, 45: PCIE_RATE_CODE_FPS45, 48: PCIE_RATE_CODE_FPS48}
    if type(fps) is not int or fps not in rates:
        raise ValueError("fps must be 40, 45 or 48")
    if type(timeout_s) not in (int, float) or not math.isfinite(timeout_s) or timeout_s <= 0:
        raise ValueError("timeout_s must be positive and finite")
    code = rates[fps]
    deadline = monotonic() + timeout_s

    def check_deadline():
        if monotonic() >= deadline:
            raise StereoControlTimeout("cold SDR rate selection deadline expired")

    def read(offset):
        value = bar.read32(offset)
        if type(value) is not int or not 0 <= value <= 0xffffffff:
            raise StereoControlError(f"read32(0x{offset:03x}) returned a non-uint32 value")
        if offset == p.PCIE_REG_STATUS and (
                value & p.PCIE_STATUS_SESSION_ARMED or not value & p.PCIE_STATUS_SESSION_REARM_READY):
            raise StereoControlError("SDR rate selection requires the pre-ARM rearm-ready boundary")
        return value

    def write(offset, value):
        if offset == p.PCIE_REG_STEREO_REQUEST_MODE:
            if read(PCIE_RATE_REG_CAPABILITIES) != PCIE_RATE_CAPABILITIES:
                raise StereoControlError("cold SDR rate capability mismatch")
            if raw_max_record_bytes is None and any(
                    read(product_offset) != PCIE_RAW_VIDEO_PRODUCT_JPEG for product_offset in
                    (PCIE_RAW_VIDEO_REQUEST_PRODUCT, PCIE_RAW_VIDEO_ACTIVE_PRODUCT)):
                raise StereoControlError("JPEG rate selection requires cold JPEG product")
        if offset == p.PCIE_REG_STEREO_COMMAND:
            check_deadline()
            bar.write32(PCIE_RATE_REG_REQUEST, code)
            if read(PCIE_RATE_REG_REQUEST) != code:
                raise StereoControlError("SDR rate REQUEST readback mismatch")
        check_deadline()
        bar.write32(offset, value)

    if raw_max_record_bytes is None:
        selection = select_cold_mode(read, write, stereo.STEREO_MODES_DUAL_JPEG,
                                     timeout_s=timeout_s, poll_interval_s=poll_interval_s,
                                     frame_divisor=2, monotonic=monotonic, sleep=sleep)
    else:
        rate_bar = SimpleNamespace(read32=read, write32=write)
        selection = select_cold_raw(rate_bar, cameras=2, max_record_bytes=raw_max_record_bytes,
                                    timeout_s=timeout_s, poll_interval_s=poll_interval_s,
                                    monotonic=monotonic, sleep=sleep)
    if read(PCIE_RATE_REG_ACTIVE) != code:
        raise StereoControlError("APPLY did not acknowledge the active SDR rate")
    if raw_max_record_bytes is None and read(PCIE_RAW_VIDEO_ACTIVE_PRODUCT) != PCIE_RAW_VIDEO_PRODUCT_JPEG:
        raise StereoControlError("APPLY did not acknowledge the active JPEG product")
    check_deadline()
    return selection
