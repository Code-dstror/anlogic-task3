"""Explicit pre-DMA RCD2 selection on the receiver's existing BAR handle.

The positive device ACK is the authoritative old writer/reader/FIFO/retire idle
barrier. APP_ENABLE=0 and a host timer alone cannot prove it. No retries, reset,
DMA open, CFG transaction owner, or fallback probe is created here.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
import time

from . import pcie_protocol_v1 as p


class RecordSelectionError(RuntimeError):
    pass


@dataclass(frozen=True)
class RecordSelection:
    version: int
    header_length: int
    session: int = 0
    request_sequence: int = 0
    selection_epoch: int = 0


def header_length(version: int) -> int:
    if type(version) is not int:
        raise ValueError("record version must be an integer")
    if version == p.PROTOCOL_VERSION:
        return p.FRAME_HEADER_SIZE
    if version == p.PCIE_RECORD_V2_VERSION:
        return p.PCIE_RECORD_V2_HEADER_LENGTH
    if version == p.PCIE_RECORD_V3_VERSION:
        return p.PCIE_RECORD_V3_HEADER_LENGTH
    if version == p.PCIE_RECORD_V4_VERSION:
        return p.PCIE_RECORD_V4_HEADER_LENGTH
    raise ValueError("unsupported record version")


def select_record(bar, version: int, *, timeout_s: float, poll_interval_s=0.001,
                  clock=time.monotonic, sleep=time.sleep) -> RecordSelection:
    """Select before the first C2H read; returned version is immutable per fd.

    Legacy default v1 does not write new registers. An advertised extension
    already selected to another version is rejected rather than guessed.
    v2 requires a nonzero, BOOT-acknowledged CFG source session.
    """
    length = header_length(version)
    if (not math.isfinite(timeout_s) or timeout_s <= 0
            or not math.isfinite(poll_interval_s) or poll_interval_s <= 0):
        raise ValueError("caller-supplied selection timeout/poll must be positive finite")
    caps = bar.read32(p.PCIE_REG_CAPABILITIES)
    if not caps & p.PCIE_CAPABILITY_RECORD_V2:
        if version == p.PROTOCOL_VERSION:
            return RecordSelection(version, length)
        raise RecordSelectionError("record v2 capability is UNSUPPORTED; no register writes")
    if (bar.read32(p.PCIE_REG_RECORD_MAGIC) != p.PCIE_RECORD_V2_MAGIC
            or bar.read32(p.PCIE_REG_RECORD_ABI_VERSION) != p.PCIE_RECORD_V2_ABI_VERSION):
        raise RecordSelectionError("invalid record selection ABI")
    if version == p.PROTOCOL_VERSION:
        if (bar.read32(p.PCIE_REG_RECORD_SELECTED_VERSION) != version
                or bar.read32(p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH) != length):
            raise RecordSelectionError("device is not selected to default v1; no implicit reselection")
        return RecordSelection(version, length)
    required = p.PCIE_RECORD_V2_FEATURE_VERSION2 | p.PCIE_RECORD_V2_FEATURE_SOURCE_STAMP
    if version == p.PCIE_RECORD_V3_VERSION:
        required |= p.PCIE_RECORD_V3_FEATURE_VERSION3 | p.PCIE_RECORD_V3_FEATURE_SPARSE
    if version == p.PCIE_RECORD_V4_VERSION:
        required |= p.PCIE_RECORD_V4_FEATURE_VERSION4 | p.PCIE_RECORD_V4_FEATURE_LANE_POINTS
    if (bar.read32(p.PCIE_REG_RECORD_FEATURES) & required != required
            or not bar.read32(p.PCIE_REG_RECORD_SUPPORTED_VERSIONS) & (1 << version)):
        raise RecordSelectionError("record v2/source stamp is UNSUPPORTED")
    if (not caps & p.PCIE_CAPABILITY_CONFIG_TRANSACTION
            or bar.read32(p.PCIE_REG_CFG_MAGIC) != p.PCIE_CFG_MAGIC
            or bar.read32(p.PCIE_REG_CFG_ABI_VERSION) != p.PCIE_CFG_ABI_VERSION):
        raise RecordSelectionError("record v2 requires CFG source-session ABI")
    session = bar.read32(p.PCIE_REG_CFG_SESSION)
    if (not session or not bar.read32(p.PCIE_REG_CFG_STATUS) & p.PCIE_CFG_STATUS_SESSION_READY
            or bar.read32(p.PCIE_REG_CFG_ACTIVE_SESSION) != session):
        raise RecordSelectionError("CFG source BOOT/session ACK absent; DMA not opened")

    def check_boundary():
        status = bar.read32(p.PCIE_REG_STATUS)
        busy = (p.PCIE_STATUS_C2H_RUNNING | p.PCIE_STATUS_TX_BUSY
                | p.PCIE_STATUS_SOURCE_BUSY | p.PCIE_STATUS_SESSION_ARMED)
        if (bar.read32(p.PCIE_REG_CONTROL) & p.PCIE_CONTROL_APP_ENABLE
                or status & busy or not status & p.PCIE_STATUS_SESSION_REARM_READY):
            raise RecordSelectionError("record selection requires source-off clean pre-DMA boundary")
        if (bar.read32(p.PCIE_REG_CFG_SESSION) != session
                or bar.read32(p.PCIE_REG_CFG_ACTIVE_SESSION) != session
                or not bar.read32(p.PCIE_REG_CFG_STATUS) & p.PCIE_CFG_STATUS_SESSION_READY):
            raise RecordSelectionError("CFG source session changed during selection; no retry")

    check_boundary()
    if bar.read32(p.PCIE_REG_RECORD_STATUS) & p.PCIE_RECORD_V2_STATUS_BUSY:
        raise RecordSelectionError("preexisting record selection is busy")
    sequence = (bar.read32(p.PCIE_REG_RECORD_RESPONSE_SEQUENCE) + 1) & 0xFFFFFFFF
    sequence = sequence or 1
    bar.write32(p.PCIE_REG_RECORD_REQUEST_VERSION, version)
    bar.write32(p.PCIE_REG_RECORD_REQUEST_SEQUENCE, sequence)
    bar.write32(p.PCIE_REG_RECORD_REQUEST_SESSION, session)
    bar.write32(p.PCIE_REG_RECORD_COMMAND, p.PCIE_RECORD_V2_COMMAND_SELECT)
    deadline = clock() + timeout_s
    while True:
        check_boundary()
        status = bar.read32(p.PCIE_REG_RECORD_STATUS)
        if status & p.PCIE_RECORD_V2_STATUS_DONE and not status & p.PCIE_RECORD_V2_STATUS_BUSY:
            if (bar.read32(p.PCIE_REG_RECORD_RESPONSE_SEQUENCE) != sequence
                    or bar.read32(p.PCIE_REG_RECORD_RESPONSE_SESSION) != session):
                raise RecordSelectionError("record selection ACK identity mismatch")
            error = bar.read32(p.PCIE_REG_RECORD_ERROR)
            if status & p.PCIE_RECORD_V2_STATUS_ERROR or error != p.PCIE_RECORD_V2_ERROR_OK:
                raise RecordSelectionError(f"record selection negative ACK error={error}")
            if (bar.read32(p.PCIE_REG_RECORD_SELECTED_VERSION) != version
                    or bar.read32(p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH) != length):
                raise RecordSelectionError("record selection ACK version/header mismatch")
            epoch = bar.read32(p.PCIE_REG_RECORD_SELECTION_EPOCH)
            check_boundary()
            return RecordSelection(version, length, session, sequence, epoch)
        remaining = deadline - clock()
        if remaining <= 0:
            raise TimeoutError("record selection ACK timeout; no DMA open/retry/reopen")
        sleep(min(poll_interval_s, remaining))
