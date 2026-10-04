"""验证基于回调的主机会话重新使能顺序"""

from __future__ import annotations

import unittest

from linux.pcie_transport.pcie_protocol_v1 import (
    PCIE_CONTROL_APP_ENABLE,
    PCIE_CONTROL_SOFT_RESET,
    PCIE_REG_CONTROL,
    PCIE_REG_STATUS,
    PCIE_STATUS_SESSION_ARMED,
    PCIE_STATUS_SESSION_REARM_READY,
)
from linux.pcie_transport.session_rearm import (
    SessionRearmTimeout,
    arm_session,
    wait_for_session_rearm_ready,
)


class FakeTime:
    def __init__(self) -> None:
        self.now = 0.0

    def clock(self) -> float:
        return self.now

    def sleep(self, duration: float) -> None:
        self.now += duration


class FakeBar:
    def __init__(self) -> None:
        self.status = 0
        self.reads = 0
        self.writes: list[tuple[int, int]] = []
        self.ready_after_reads: int | None = None
        self.arm_after_reads: int | None = None
        self.dma_prepared = False

    def read32(self, offset: int) -> int:
        if offset != PCIE_REG_STATUS:
            raise AssertionError(f"unexpected read offset {offset:#x}")
        self.reads += 1
        if self.ready_after_reads is not None and self.reads >= self.ready_after_reads:
            self.status |= PCIE_STATUS_SESSION_REARM_READY
        if self.arm_after_reads is not None and self.reads >= self.arm_after_reads:
            self.status &= ~PCIE_STATUS_SESSION_REARM_READY
            self.status |= PCIE_STATUS_SESSION_ARMED
        return self.status

    def write32(self, offset: int, value: int) -> None:
        if offset != PCIE_REG_CONTROL:
            raise AssertionError(f"unexpected write offset {offset:#x}")
        self.writes.append((offset, value))
        if value == 0:
            # 对应 frame_session_controller 的 RUN 状态：禁止准入本身不会开启新的会话代次
            pass
        elif value == PCIE_CONTROL_SOFT_RESET:
            self.status &= ~(
                PCIE_STATUS_SESSION_ARMED | PCIE_STATUS_SESSION_REARM_READY
            )
        elif value == PCIE_CONTROL_APP_ENABLE:
            if not self.dma_prepared:
                raise AssertionError("APP_ENABLE written before external DMA prepare/start")
        else:
            raise AssertionError(f"unexpected control value {value:#x}")


class SessionRearmTests(unittest.TestCase):
    def test_low_ready_external_dma_high_armed_order(self) -> None:
        fake_time = FakeTime()
        bar = FakeBar()
        bar.ready_after_reads = 3

        ready_status = wait_for_session_rearm_ready(
            bar.read32,
            bar.write32,
            0.1,
            poll_interval_s=0.01,
            clock=fake_time.clock,
            sleep=fake_time.sleep,
        )
        self.assertTrue(ready_status & PCIE_STATUS_SESSION_REARM_READY)
        self.assertEqual(bar.writes, [(PCIE_REG_CONTROL, 0)])

        # 该操作由主机负责，辅助函数刻意在 READY 与使能之间留出准备 DMA 缓冲区和启动通道的窗口
        bar.dma_prepared = True
        bar.arm_after_reads = bar.reads + 3
        armed_status = arm_session(
            bar.read32,
            bar.write32,
            0.1,
            poll_interval_s=0.01,
            clock=fake_time.clock,
            sleep=fake_time.sleep,
        )
        self.assertTrue(armed_status & PCIE_STATUS_SESSION_ARMED)
        self.assertEqual(bar.writes[-1], (PCIE_REG_CONTROL, PCIE_CONTROL_APP_ENABLE))

    def test_normal_armed_restart_uses_soft_reset_before_ready(self) -> None:
        fake_time = FakeTime()
        bar = FakeBar()
        bar.status = PCIE_STATUS_SESSION_ARMED
        bar.ready_after_reads = 4

        status = wait_for_session_rearm_ready(
            bar.read32,
            bar.write32,
            0.1,
            poll_interval_s=0.01,
            clock=fake_time.clock,
            sleep=fake_time.sleep,
        )
        self.assertTrue(status & PCIE_STATUS_SESSION_REARM_READY)
        self.assertFalse(status & PCIE_STATUS_SESSION_ARMED)
        self.assertEqual(
            bar.writes,
            [(PCIE_REG_CONTROL, PCIE_CONTROL_SOFT_RESET)],
        )

    def test_initial_ready_does_not_issue_unnecessary_soft_reset(self) -> None:
        bar = FakeBar()
        bar.status = PCIE_STATUS_SESSION_REARM_READY
        status = wait_for_session_rearm_ready(bar.read32, bar.write32, 0.1)
        self.assertTrue(status & PCIE_STATUS_SESSION_REARM_READY)
        self.assertEqual(bar.writes, [(PCIE_REG_CONTROL, 0)])

    def test_ready_timeout_leaves_enable_low(self) -> None:
        fake_time = FakeTime()
        bar = FakeBar()
        with self.assertRaises(SessionRearmTimeout):
            wait_for_session_rearm_ready(
                bar.read32,
                bar.write32,
                0.02,
                poll_interval_s=0.01,
                clock=fake_time.clock,
                sleep=fake_time.sleep,
            )
        self.assertEqual(bar.writes[-1], (PCIE_REG_CONTROL, 0))

    def test_fault_before_armed_timeout_returns_enable_low(self) -> None:
        fake_time = FakeTime()
        bar = FakeBar()
        bar.status = PCIE_STATUS_SESSION_REARM_READY
        bar.dma_prepared = True
        with self.assertRaises(SessionRearmTimeout):
            arm_session(
                bar.read32,
                bar.write32,
                0.02,
                poll_interval_s=0.01,
                clock=fake_time.clock,
                sleep=fake_time.sleep,
            )
        self.assertEqual(
            bar.writes,
            [
                (PCIE_REG_CONTROL, PCIE_CONTROL_APP_ENABLE),
                (PCIE_REG_CONTROL, 0),
            ],
        )

    def test_arm_rejects_missing_ready_without_enable_pulse(self) -> None:
        bar = FakeBar()
        with self.assertRaisesRegex(RuntimeError, "SESSION_REARM_READY"):
            arm_session(bar.read32, bar.write32, 0.1)
        self.assertEqual(bar.writes, [(PCIE_REG_CONTROL, 0)])


if __name__ == "__main__":
    unittest.main()
