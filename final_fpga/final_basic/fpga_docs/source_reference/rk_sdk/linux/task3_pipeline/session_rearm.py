"""主机侧 FPGA 会话重新使能握手的顺序辅助函数

本模块只安排应用 BAR 的访问顺序
调用方负责在 wait_for_session_rearm_ready 前停止旧 DMA 并丢弃残留数据，在该调用与 arm_session 之间准备并启动 DMA
本模块不是 PCIe 或 SGDMA 驱动"""

from __future__ import annotations

import time
from collections.abc import Callable

from .pcie_protocol_v1 import (
    PCIE_CONTROL_APP_ENABLE,
    PCIE_CONTROL_SOFT_RESET,
    PCIE_REG_CONTROL,
    PCIE_REG_STATUS,
    PCIE_STATUS_SESSION_ARMED,
    PCIE_STATUS_SESSION_REARM_READY,
)

# 传给回调的偏移相对于 USER_BAR_BASE
# 调用方负责 BAR 映射、基址相加以及有序 MMIO 访问
Read32 = Callable[[int], int]
Write32 = Callable[[int, int], None]
Clock = Callable[[], float]
Sleeper = Callable[[float], None]


class SessionRearmTimeout(TimeoutError):
    """FPGA 未进入请求的可观察会话状态"""


def _wait_for_status(
    read32: Read32,
    mask: int,
    timeout_s: float,
    poll_interval_s: float,
    clock: Clock,
    sleep: Sleeper,
) -> int:
    if timeout_s < 0:
        raise ValueError("timeout_s must be non-negative")
    if poll_interval_s <= 0:
        raise ValueError("poll_interval_s must be positive")

    deadline = clock() + timeout_s
    while True:
        status = read32(PCIE_REG_STATUS)
        if status & mask:
            return status
        remaining = deadline - clock()
        if remaining <= 0:
            raise SessionRearmTimeout(
                f"status bit 0x{mask:08x} did not assert within {timeout_s}s"
            )
        sleep(min(poll_interval_s, remaining))


def wait_for_session_rearm_ready(
    read32: Read32,
    write32: Write32,
    timeout_s: float,
    *,
    poll_interval_s: float = 0.001,
    clock: Clock = time.monotonic,
    sleep: Sleeper = time.sleep,
) -> int:
    """进入新的禁止状态代次，并等待会话屏障就绪

    调用前必须已停止旧 DMA 并丢弃不完整记录
    已使能会话需要 SOFT_RESET，因为单独拉低 APP_ENABLE 不会退出控制器 RUN 状态
    启动阶段或已有故障时只需拉低使能；失败时 APP_ENABLE 仍保持为低"""

    status = read32(PCIE_REG_STATUS)
    if status & PCIE_STATUS_SESSION_ARMED:
        write32(PCIE_REG_CONTROL, PCIE_CONTROL_SOFT_RESET)
    else:
        write32(PCIE_REG_CONTROL, 0)
    try:
        return _wait_for_status(
            read32,
            PCIE_STATUS_SESSION_REARM_READY,
            timeout_s,
            poll_interval_s,
            clock,
            sleep,
        )
    except Exception:
        write32(PCIE_REG_CONTROL, 0)
        raise


def arm_session(
    read32: Read32,
    write32: Write32,
    timeout_s: float,
    *,
    poll_interval_s: float = 0.001,
    clock: Clock = time.monotonic,
    sleep: Sleeper = time.sleep,
) -> int:
    """DMA 准备并启动后拉高 APP_ENABLE，等待 SESSION_ARMED

    在使能前立即再次检查 READY，任何异常或超时都会拉低 APP_ENABLE，使后续重试必须重新握手"""

    try:
        status = read32(PCIE_REG_STATUS)
        if not status & PCIE_STATUS_SESSION_REARM_READY:
            raise RuntimeError("SESSION_REARM_READY is not asserted")
        write32(PCIE_REG_CONTROL, PCIE_CONTROL_APP_ENABLE)
        return _wait_for_status(
            read32,
            PCIE_STATUS_SESSION_ARMED,
            timeout_s,
            poll_interval_s,
            clock,
            sleep,
        )
    except Exception:
        write32(PCIE_REG_CONTROL, 0)
        raise
