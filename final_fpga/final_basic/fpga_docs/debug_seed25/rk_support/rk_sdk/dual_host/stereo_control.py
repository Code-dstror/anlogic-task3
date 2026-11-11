"""Cold mode selection through the caller's sole, already-owned BAR interface.

Callbacks take USER BAR-relative byte offsets. Reads must be fresh and ordered;
writes must synchronously complete an aligned full 32-bit AXI-Lite transaction
and raise on non-OKAY responses. The caller serializes this entire operation
against all other BAR owners. This module never opens a device or starts DMA.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
import time
from typing import Callable

if __package__:
    from . import pcie_protocol_v1 as p
    from . import stereo_control_v1 as s
else:
    import pcie_protocol_v1 as p
    import stereo_control_v1 as s


class StereoControlError(RuntimeError):
    """Identity, precondition or acknowledgement failure; no recovery attempted."""


class StereoControlTimeout(TimeoutError):
    """Caller deadline expired; does not imply that an accepted APPLY was undone."""


@dataclass(frozen=True)
class StereoSelection:
    mode: int
    cfg_session: int
    status: int
    frame_divisor: int
    jpeg_quality: int


def _seconds(value: float, name: str) -> float:
    if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be finite positive seconds, excluding bool")
    return float(value)


def select_cold_mode(
    read32: Callable[[int], int],
    write32: Callable[[int, int], None],
    mode: int,
    *,
    timeout_s: float,
    poll_interval_s: float,
    frame_divisor: int | None = None,
    jpeg_quality: int | None = None,
    monotonic: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> StereoSelection:
    """Select MONO=0 or DUAL_JPEG=1 before first C2H open/read; B rejects Rice.

    None uses the product's FPGA default cadence and the existing CFG quality.
    Quality has one authority: before cold selection, an explicit change uses
    original CFG PREPARE/COMMIT (PREPARE_EXT when an extension is active) and
    waits for its real APPLIED tuple. BOOT's all-zero extension is not schema0.

    timeout_s and poll_interval_s are explicit caller policy. The one deadline
    covers CFG BOOT polling and the subsequent two-domain APPLY completion.
    Callback I/O must have its own bounded completion policy; this deadline
    cannot cancel a blocked callback. On any exception, the caller must resolve
    ownership/session state. No reset, retry, DMA start or format SELECT occurs.
    A successful return still requires explicit record v2/v4 negotiation.
    """
    if type(mode) is not int or mode not in (s.STEREO_MODES_MONO, s.STEREO_MODES_DUAL_JPEG):
        raise ValueError("B mode must be integer MONO=0 or DUAL_JPEG=1, excluding bool")
    for value, low, high, name in (
        (frame_divisor, 1, s.STEREO_MAXIMUM_FRAME_DIVISOR, "frame_divisor"),
        (jpeg_quality, p.PCIE_CFG_MINIMUM_QUALITY, p.PCIE_CFG_MAXIMUM_QUALITY, "jpeg_quality"),
    ):
        if value is not None and (type(value) is not int or not low <= value <= high):
            raise ValueError(f"{name} must be an integer in {low}..{high}, excluding bool")
    timeout_s = _seconds(timeout_s, "timeout_s")
    poll_interval_s = _seconds(poll_interval_s, "poll_interval_s")
    if poll_interval_s > timeout_s:
        raise ValueError("poll_interval_s must not exceed timeout_s")
    if not all(callable(callback) for callback in (read32, write32, monotonic, sleep)):
        raise TypeError("read32, write32, monotonic and sleep must be callable")
    deadline = monotonic() + timeout_s
    busy_bit = 1 << s.STEREO_STATUS_BITS_BUSY
    done_bit = 1 << s.STEREO_STATUS_BITS_DONE
    locked_bit = 1 << s.STEREO_STATUS_BITS_LOCKED

    def read(offset: int) -> int:
        value = read32(offset)
        if type(value) is not int or not 0 <= value <= 0xffffffff:
            raise StereoControlError(f"read32(0x{offset:03x}) returned a non-uint32 value")
        return value

    def pause(stage: str) -> None:
        remaining = deadline - monotonic()
        if remaining <= 0:
            raise StereoControlTimeout(f"{stage} timeout; no automatic recovery")
        sleep(min(poll_interval_s, remaining))

    def check_app_idle() -> None:
        control = read(p.PCIE_REG_CONTROL)
        status = read(p.PCIE_REG_STATUS)
        if control & p.PCIE_CONTROL_APP_ENABLE:
            raise StereoControlError("APP_ENABLE is already set")
        if status & (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY | p.PCIE_STATUS_SOURCE_BUSY):
            raise StereoControlError("C2H, transmitter or source is already running")
        if status & p.PCIE_STATUS_FRAME_ERROR:
            raise StereoControlError("application reports a frame/recovery error")
        ready = p.PCIE_STATUS_LINK_UP | p.PCIE_STATUS_USER_RESET_RELEASED
        if status & ready != ready:
            raise StereoControlError("PCIe link or USER reset is not ready")

    def stereo_state(*, idle: bool = False) -> tuple[int, int]:
        status = read(p.PCIE_REG_STEREO_STATUS)
        error = read(p.PCIE_REG_STEREO_ERROR)
        if status & locked_bit:
            raise StereoControlError("stereo mode is permanently LOCKED for this cold lifetime")
        if error != s.STEREO_ERRORS_OK:
            raise StereoControlError(f"stereo ERROR={error}")
        if idle and status & busy_bit:
            raise StereoControlError("another stereo APPLY is BUSY")
        return status, error

    def cfg_snapshot() -> tuple[int, ...]:
        return tuple(read(offset) for offset in (
            p.PCIE_REG_CFG_STATUS, p.PCIE_REG_CFG_ERROR,
            p.PCIE_REG_CFG_SESSION, p.PCIE_REG_CFG_ACTIVE_SESSION,
            p.PCIE_REG_CFG_MODE_EPOCH, p.PCIE_REG_CFG_ACTIVE_MODE,
            p.PCIE_REG_CFG_ACTIVE_QUALITY,
        ))

    def validate_boot(snapshot: tuple[int, ...]) -> bool:
        status, error, session, active_session, epoch, active_mode, quality = snapshot
        if error != p.PCIE_CFG_ERROR_OK or status & p.PCIE_CFG_STATUS_ERROR:
            raise StereoControlError(f"CFG reports an error ({error})")
        if not status & p.PCIE_CFG_STATUS_SESSION_READY:
            return False
        if status & (p.PCIE_CFG_STATUS_BUSY | p.PCIE_CFG_STATUS_READY | p.PCIE_CFG_STATUS_APPLIED):
            raise StereoControlError("CFG is occupied or has left the initial BOOT configuration")
        if not session or session != active_session:
            raise StereoControlError("CFG BOOT session identity is inconsistent")
        if epoch != 0 or active_mode != p.PCIE_CFG_MODE_COLOR or quality != p.PCIE_CFG_DEFAULT_QUALITY:
            raise StereoControlError("CFG must be the initial epoch-0 COLOR/Q75 BOOT configuration")
        return True

    for offset, expected, label in (
        (p.PCIE_REG_DEVICE_MAGIC, p.DEVICE_MAGIC, "device MAGIC"),
        (p.PCIE_REG_PROTOCOL_VERSION, p.PROTOCOL_VERSION, "device protocol"),
        (p.PCIE_REG_STEREO_MAGIC, s.STEREO_MAGIC, "stereo MAGIC"),
        (p.PCIE_REG_STEREO_ABI_VERSION, s.STEREO_ABI_VERSION, "stereo ABI"),
        (p.PCIE_REG_CFG_MAGIC, p.PCIE_CFG_MAGIC, "CFG MAGIC"),
        (p.PCIE_REG_CFG_ABI_VERSION, p.PCIE_CFG_ABI_VERSION, "CFG ABI"),
    ):
        if read(offset) != expected:
            raise StereoControlError(f"{label} mismatch")

    capabilities = read(p.PCIE_REG_STEREO_CAPABILITIES)
    if not capabilities & (1 << mode):
        raise StereoControlError("requested product is not supported by this bitstream")
    default_divisor = (capabilities >> 8) & 0xff
    selected_divisor = default_divisor if frame_divisor is None else frame_divisor
    selected_quality = p.PCIE_CFG_DEFAULT_QUALITY if jpeg_quality is None else jpeg_quality
    if not 1 <= selected_divisor <= (capabilities >> 24):
        raise StereoControlError("cadence is outside the advertised capability")

    while True:
        check_app_idle()
        stereo_state(idle=True)
        boot = cfg_snapshot()
        if validate_boot(boot):
            if cfg_snapshot() != boot:
                raise StereoControlError("CFG changed during BOOT snapshot")
            break
        pause("CFG BOOT")

    if selected_quality != boot[6]:
        # Preserve the complete actual configuration, changing only quality.
        # This occurs while topology is still MONO, before its CFG write lock.
        if read(p.PCIE_REG_STEREO_ACTIVE_MODE) != s.STEREO_MODES_MONO:
            raise StereoControlError("quality change requires the original MONO configuration window")
        active_fields = (
            (p.PCIE_REG_CFG_ACTIVE_MODE, p.PCIE_REG_CFG_REQUEST_MODE),
            (p.PCIE_REG_CFG_ACTIVE_FLAGS, p.PCIE_REG_CFG_REQUEST_FLAGS),
            (p.PCIE_REG_CFG_ACTIVE_MIN_QUALITY, p.PCIE_REG_CFG_REQUEST_MIN_QUALITY),
            (p.PCIE_REG_CFG_ACTIVE_FRAME_BUDGET, p.PCIE_REG_CFG_REQUEST_FRAME_BUDGET),
            (p.PCIE_REG_CFG_ACTIVE_RESTART_MCUS, p.PCIE_REG_CFG_REQUEST_RESTART_MCUS),
        )
        unchanged = [(active, request, read(active)) for active, request in active_fields]
        if unchanged[2][2] > selected_quality:
            raise StereoControlError("quality is below the current minimum; use the original CFG policy")
        extension = [read(p.PCIE_REG_CFG_EXT_ACTIVE_BASE + 4 * word) for word in range(32)]
        # Original BOOT carries no extension at all. PREPARE_EXT would send
        # those zeros to a schema validator and correctly reject schema 0.
        prepare_command = (p.PCIE_CFG_COMMAND_PREPARE_EXT if any(extension)
                           else p.PCIE_CFG_COMMAND_PREPARE)
        previous_sequence = read(p.PCIE_REG_CFG_RESPONSE_SEQUENCE)
        sequence = (previous_sequence + 1) & 0xffffffff or 1
        if cfg_snapshot() != boot:
            raise StereoControlError("CFG changed before quality preparation")
        for offset, value in (
            (p.PCIE_REG_CFG_REQUEST_SEQUENCE, sequence),
            (p.PCIE_REG_CFG_REQUEST_SESSION, boot[2]),
            *((request, value) for _, request, value in unchanged),
            (p.PCIE_REG_CFG_REQUEST_QUALITY, selected_quality),
            (p.PCIE_REG_CFG_HOST_CAPABILITIES, read(p.PCIE_REG_CFG_HOST_CAPABILITIES) | 1),
            *((p.PCIE_REG_CFG_EXT_SHADOW_BASE + 4 * word, value) for word, value in enumerate(extension)),
        ):
            check_app_idle()
            if monotonic() >= deadline:
                raise StereoControlTimeout("CFG quality staging deadline expired")
            write32(offset, value)
        if monotonic() >= deadline:
            raise StereoControlTimeout("CFG quality deadline expired before PREPARE")
        write32(p.PCIE_REG_CFG_COMMAND, prepare_command)

        def wait_cfg(*, applied: bool) -> tuple[int, ...]:
            while True:
                check_app_idle()
                snapshot = cfg_snapshot()
                status, error, session, active_session, epoch, _, quality = snapshot
                if session != boot[2] or active_session != boot[3]:
                    raise StereoControlError("CFG session changed during quality transaction")
                if error or status & p.PCIE_CFG_STATUS_ERROR:
                    raise StereoControlError(f"CFG quality transaction error {error}")
                ready = status & p.PCIE_CFG_STATUS_READY
                committed = status & p.PCIE_CFG_STATUS_APPLIED and not status & p.PCIE_CFG_STATUS_BUSY
                if (committed if applied else ready):
                    if read(p.PCIE_REG_CFG_RESPONSE_SEQUENCE) != sequence:
                        raise StereoControlError("CFG quality response sequence mismatch")
                    if applied and (quality != selected_quality or epoch != ((boot[4] + 1) & 0xffffffff)):
                        raise StereoControlError("CFG quality APPLIED tuple mismatch")
                    return snapshot
                pause("CFG quality APPLIED" if applied else "CFG quality PREPARE")

        wait_cfg(applied=False)
        if monotonic() >= deadline:
            raise StereoControlTimeout("CFG quality deadline expired before COMMIT")
        write32(p.PCIE_REG_CFG_COMMAND, p.PCIE_CFG_COMMAND_COMMIT)
        committed = wait_cfg(applied=True)
        if any(read(active) != value for active, _, value in unchanged):
            raise StereoControlError("CFG quality transaction changed an unrelated active field")
        if [read(p.PCIE_REG_CFG_EXT_ACTIVE_BASE + 4 * word) for word in range(32)] != extension:
            raise StereoControlError("CFG quality transaction changed the processing extension")
        boot = committed

    # A successful ordered write32 must represent the actual AXI response.
    # Consequently a fast completed APPLY need not expose BUSY to the host.
    if monotonic() >= deadline:
        raise StereoControlTimeout("CFG BOOT deadline expired before any mode write")
    write32(p.PCIE_REG_STEREO_REQUEST_MODE, mode)
    if read(p.PCIE_REG_STEREO_REQUEST_MODE) != mode:
        raise StereoControlError("stereo REQUEST_MODE readback mismatch")
    if frame_divisor is not None:
        write32(p.PCIE_REG_STEREO_REQUEST_DIVISOR, frame_divisor)
    if read(p.PCIE_REG_STEREO_REQUEST_DIVISOR) != selected_divisor:
        raise StereoControlError("stereo REQUEST_DIVISOR readback mismatch")
    stereo_state(idle=True)
    check_app_idle()
    if cfg_snapshot() != boot:
        raise StereoControlError("CFG changed before APPLY")
    if monotonic() >= deadline:
        raise StereoControlTimeout("deadline expired before APPLY")
    write32(p.PCIE_REG_STEREO_COMMAND, s.STEREO_COMMANDS_APPLY)

    while True:
        check_app_idle()
        if cfg_snapshot() != boot:
            raise StereoControlError("CFG BOOT identity changed during APPLY")
        status, error = stereo_state()
        if status & done_bit and not status & busy_bit:
            active_mode = read(p.PCIE_REG_STEREO_ACTIVE_MODE)
            active_divisor = read(p.PCIE_REG_STEREO_ACTIVE_DIVISOR)
            active_quality = read(p.PCIE_REG_CFG_ACTIVE_QUALITY)
            if stereo_state() != (status, error):
                raise StereoControlError("stereo completion snapshot changed")
            reported_mode = (status >> s.STEREO_STATUS_BITS_ACTIVE_MODE) & 3
            if active_mode != mode or reported_mode != mode:
                raise StereoControlError("DONE has an inconsistent ACTIVE_MODE acknowledgement")
            if active_divisor != selected_divisor or active_quality != selected_quality:
                raise StereoControlError("DONE has an inconsistent cadence/quality acknowledgement")
            check_app_idle()
            if cfg_snapshot() != boot:
                raise StereoControlError("CFG changed at stereo completion")
            if monotonic() > deadline:
                raise StereoControlTimeout("APPLY completed after the caller deadline")
            return StereoSelection(mode=mode, cfg_session=boot[2], status=status,
                                   frame_divisor=active_divisor, jpeg_quality=active_quality)
        pause("stereo two-domain APPLY")
