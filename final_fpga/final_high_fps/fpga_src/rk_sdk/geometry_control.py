"""Select a MONO UHD cadence before ARM on an already opened C2H Receiver."""

import math
import time

from dual_host import stereo_control_v1 as stereo
from dual_host.camera_shared import SharedStereoReceiver, validate_jpeg_budget
from dual_host.pcie_protocol_v1 import (
    PCIE_REG_STEREO_ACTIVE_MODE, PCIE_REG_STEREO_REQUEST_MODE, PCIE_REG_STEREO_STATUS,
)
from dual_host.stereo_control import StereoControlError, StereoControlTimeout, select_cold_mode
from geometry_control_constants import (
    PCIE_GEOMETRY_ABI_VERSION, PCIE_GEOMETRY_CODE_HD, PCIE_GEOMETRY_CODE_MONO_UHD15,
    PCIE_GEOMETRY_CODE_MONO_UHD20, PCIE_GEOMETRY_REG_ACTIVE, PCIE_GEOMETRY_REG_CAPABILITIES,
    PCIE_GEOMETRY_REG_REQUEST,
)
from linux.dma_c2h_candidate.c2h_abi import MAX_RECORD_BYTES
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import ConfigTransactions
from linux.task3_pipeline.mono_config_v2 import HD_GEOMETRY, UHD_GEOMETRY
from linux.task3_pipeline.record_selection import select_record
from rate_control_constants import PCIE_RATE_CODE_LEGACY, PCIE_RATE_REG_ACTIVE, PCIE_RATE_REG_REQUEST
from raw_video import RawVideoReceiver, raw10_record_bytes
from raw_video_constants import (
    PCIE_RAW_VIDEO_ACTIVE_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_JPEG,
    PCIE_RAW_VIDEO_PRODUCT_RAW, PCIE_RAW_VIDEO_REQUEST_PRODUCT,
)


_UHD_BY_FPS = {15: PCIE_GEOMETRY_CODE_MONO_UHD15, 20: PCIE_GEOMETRY_CODE_MONO_UHD20}


def _apply_cold_uhd(owner, product, fps, *, timeout_s, poll_interval_s, monotonic, sleep):
    if type(fps) is not int or fps not in _UHD_BY_FPS:
        raise ValueError("UHD fps must be 15 or 20")
    geometry = _UHD_BY_FPS[fps]
    if type(timeout_s) not in (int, float) or not math.isfinite(timeout_s) or timeout_s <= 0:
        raise ValueError("timeout_s must be positive and finite")
    deadline = monotonic() + timeout_s
    if not owner.snapshot().transport_drained or owner.leased_count:
        raise StereoControlError("UHD selection requires the stopped C2H owner with no leases")

    def check_deadline():
        if monotonic() >= deadline:
            raise StereoControlTimeout("cold UHD selection deadline expired")

    def read(offset):
        check_deadline()
        value = owner.read32(offset)
        if type(value) is not int or not 0 <= value <= 0xffffffff:
            raise StereoControlError(f"read32(0x{offset:03x}) returned a non-uint32 value")
        if offset == p.PCIE_REG_STATUS and (
                value & p.PCIE_STATUS_SESSION_ARMED or not value & p.PCIE_STATUS_SESSION_REARM_READY):
            raise StereoControlError("UHD selection requires the pre-ARM rearm-ready boundary")
        return value

    def write(offset, value):
        check_deadline()
        if offset == PCIE_REG_STEREO_REQUEST_MODE:
            capabilities = read(PCIE_GEOMETRY_REG_CAPABILITIES)
            required = (1 << PCIE_GEOMETRY_CODE_HD) | (1 << geometry)
            if (capabilities >> 8 != PCIE_GEOMETRY_ABI_VERSION
                    or (capabilities & required) != required):
                raise StereoControlError(f"cold UHD{fps} geometry capability mismatch")
            if read(PCIE_REG_STEREO_STATUS) & (1 << stereo.STEREO_STATUS_BITS_DONE) or any(
                    read(register) != expected for register, expected in (
                        (PCIE_REG_STEREO_REQUEST_MODE, stereo.STEREO_MODES_MONO),
                        (PCIE_REG_STEREO_ACTIVE_MODE, stereo.STEREO_MODES_MONO),
                        (PCIE_RATE_REG_REQUEST, PCIE_RATE_CODE_LEGACY),
                        (PCIE_RATE_REG_ACTIVE, PCIE_RATE_CODE_LEGACY),
                        (PCIE_GEOMETRY_REG_REQUEST, PCIE_GEOMETRY_CODE_HD),
                        (PCIE_GEOMETRY_REG_ACTIVE, PCIE_GEOMETRY_CODE_HD),
                        (PCIE_RAW_VIDEO_REQUEST_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_JPEG),
                        (PCIE_RAW_VIDEO_ACTIVE_PRODUCT, PCIE_RAW_VIDEO_PRODUCT_JPEG),
                        (p.PCIE_REG_CFG_COMPILED_PROFILE, p.PCIE_CFG_PROFILE_MONO1920),
                        (p.PCIE_REG_CFG_CAMERA_PRESENT, 1),
                        (p.PCIE_REG_CFG_MAX_WIDTH, HD_GEOMETRY[0]),
                        (p.PCIE_REG_CFG_MAX_HEIGHT, HD_GEOMETRY[1]),
                        (p.PCIE_REG_CFG_ACTIVE_FLAGS, 0),
                        (p.PCIE_REG_CFG_EXT_ACTIVE_BASE, 0),
                    )):
                raise StereoControlError("UHD requires a fresh MONO HD COLOR BOOT with legacy rate and JPEG product")
            # The published N2 value guard permits DUAL=1 only. Retain cold MONO=0.
            return
        for register, setting, label in (
            (PCIE_RAW_VIDEO_REQUEST_PRODUCT, product, "REQUEST_PRODUCT"),
            (PCIE_GEOMETRY_REG_REQUEST, geometry, "REQUEST_GEOMETRY"),
        ):
            owner.write32(register, setting)
            if read(register) != setting:
                raise StereoControlError(f"UHD {label} readback mismatch")
            check_deadline()
        owner.write32(offset, value)

    topology = select_cold_mode(read, write, stereo.STEREO_MODES_MONO, timeout_s=timeout_s,
                                poll_interval_s=poll_interval_s, monotonic=monotonic, sleep=sleep)
    if (read(PCIE_GEOMETRY_REG_ACTIVE), read(PCIE_RAW_VIDEO_ACTIVE_PRODUCT), read(PCIE_RATE_REG_ACTIVE)) != (
            geometry, product, PCIE_RATE_CODE_LEGACY):
        raise StereoControlError("APPLY did not acknowledge the active UHD geometry, product and legacy rate")
    cfg = ConfigTransactions(owner, timeout_s=timeout_s, poll_interval_s=poll_interval_s,
                             clock=monotonic, sleep=sleep)
    if (cfg.capabilities.compiled_profile != p.PCIE_CFG_PROFILE_MONO3840
            or cfg.session != topology.cfg_session
            or read(p.PCIE_REG_CFG_ACTIVE_SESSION) != topology.cfg_session
            or read(p.PCIE_REG_CFG_MODE_EPOCH) != 0
            or read(p.PCIE_REG_CONTROL) & p.PCIE_CONTROL_APP_ENABLE
            or read(p.PCIE_REG_STATUS) & (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY | p.PCIE_STATUS_SOURCE_BUSY)
            or read(PCIE_REG_STEREO_STATUS) != topology.status):
        raise StereoControlError("UHD CFG BOOT or cold ownership changed during APPLY")
    check_deadline()
    return cfg


def select_cold_uhd_jpeg(owner, *, payload_budget: int, timeout_s: float, poll_interval_s: float,
                         fps: int = 15, monotonic=time.monotonic, sleep=time.sleep) -> SharedStereoReceiver:
    """Apply UHD JPEG and negotiate AJPG v4 on the caller's serialized C2H owner."""
    capacity = owner.capacity
    validate_jpeg_budget(capacity, payload_budget)
    cfg = _apply_cold_uhd(owner, PCIE_RAW_VIDEO_PRODUCT_JPEG, fps, timeout_s=timeout_s,
                          poll_interval_s=poll_interval_s, monotonic=monotonic, sleep=sleep)
    cfg.mono_capabilities()
    selection = select_record(owner, p.PCIE_RECORD_V4_VERSION, timeout_s=timeout_s,
                              poll_interval_s=poll_interval_s, clock=monotonic, sleep=sleep)
    return SharedStereoReceiver(cfg, selection, max_record_bytes=capacity, cameras=1,
                                payload_budget=payload_budget)


def select_cold_uhd_raw(owner, *, timeout_s: float, poll_interval_s: float,
                        fps: int = 15, monotonic=time.monotonic, sleep=time.sleep) -> RawVideoReceiver:
    """Apply UHD RAW and return a receiver bound to the actual CAM0 BOOT geometry."""
    capacity = owner.capacity
    required = raw10_record_bytes(*UHD_GEOMETRY)
    if type(capacity) is not int or not required <= capacity <= MAX_RECORD_BYTES:
        raise ValueError(f"actual Receiver.capacity must be {required}..{MAX_RECORD_BYTES} bytes for UHD RAW")
    cfg = _apply_cold_uhd(owner, PCIE_RAW_VIDEO_PRODUCT_RAW, fps, timeout_s=timeout_s,
                          poll_interval_s=poll_interval_s, monotonic=monotonic, sleep=sleep)
    return RawVideoReceiver(session=cfg.session, mode_epoch=0, cameras=1,
                            width=cfg.capabilities.max_width, height=cfg.capabilities.max_height)
