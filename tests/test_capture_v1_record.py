from __future__ import annotations

import os
import struct
import unittest
from unittest import mock

from linux.pcie_transport import pcie_protocol_v1 as protocol
from linux.pcie_transport.capture_v1_record import (
    CaptureError,
    UserBar,
    _positive_float,
    _reader_main,
    capture_one,
)


def make_record(payload: bytes = b"\xff\xd8data\xff\xd9") -> bytes:
    values = {
        "frame_sequence": 7,
        "payload_length": len(payload),
        "width": 20,
        "height": 17,
        "pixel_format": 1,
        "compression": 1,
        "quality": 75,
        "timestamp_ns": 1234,
        "status": 0,
        "error_code": 0,
        "slot_id": 0,
        "payload_crc32": 0,
    }
    packed = []
    for name in protocol.FRAME_HEADER_FIELD_NAMES:
        if name in values:
            packed.append(values[name])
        else:
            packed.append(protocol.FRAME_HEADER_EXPECTED_VALUES[name])
    return protocol.FRAME_HEADER_STRUCT.pack(*packed) + payload


class FakeTime:
    def __init__(self) -> None:
        self.now = 0.0

    def clock(self) -> float:
        return self.now

    def sleep(self, duration: float) -> None:
        self.now += duration


class FakeBar:
    def __init__(
        self,
        *,
        dma_runs: bool = True,
        device_magic: int = protocol.DEVICE_MAGIC,
        protocol_version: int = protocol.PROTOCOL_VERSION,
    ) -> None:
        self.dma_runs = dma_runs
        self.device_magic = device_magic
        self.protocol_version = protocol_version
        self.worker_started = False
        self.armed = False
        self.events: list[object] = []

    def read32(self, offset: int) -> int:
        self.events.append(("read", offset))
        if offset == protocol.PCIE_REG_DEVICE_MAGIC:
            return self.device_magic
        if offset == protocol.PCIE_REG_PROTOCOL_VERSION:
            return self.protocol_version
        if offset != protocol.PCIE_REG_STATUS:
            raise AssertionError(offset)
        status = protocol.PCIE_STATUS_SESSION_REARM_READY
        if self.worker_started and self.dma_runs:
            status |= protocol.PCIE_STATUS_C2H_RUNNING
        if self.armed:
            status &= ~protocol.PCIE_STATUS_SESSION_REARM_READY
            status |= protocol.PCIE_STATUS_SESSION_ARMED
        return status

    def write32(self, offset: int, value: int) -> None:
        self.events.append(("write", offset, value))
        if offset != protocol.PCIE_REG_CONTROL:
            raise AssertionError(offset)
        if value == protocol.PCIE_CONTROL_APP_ENABLE:
            if not self.worker_started or not self.dma_runs:
                raise AssertionError("enabled before DMA running")
            self.armed = True


class FakeWorker:
    def __init__(self, bar: FakeBar, result: tuple[str, object]) -> None:
        self.bar = bar
        self.result = result
        self.started = False
        self.terminated = False
        self.joined = False
        self.closed = False

    def start(self) -> None:
        self.started = True
        self.bar.worker_started = True
        self.bar.events.append("reader_start")

    def poll(self) -> bool:
        return self.bar.armed and not self.terminated

    def receive(self) -> tuple[str, object]:
        return self.result

    def is_alive(self) -> bool:
        return self.started and not (self.terminated or self.joined)

    def terminate(self) -> None:
        self.terminated = True

    def join(self, _timeout: float) -> None:
        self.joined = True

    def close(self) -> None:
        self.closed = True


class UserBarTests(unittest.TestCase):
    @mock.patch("linux.pcie_transport.capture_v1_record.os.close")
    @mock.patch(
        "linux.pcie_transport.capture_v1_record.os.pwrite", return_value=4, create=True
    )
    @mock.patch("linux.pcie_transport.capture_v1_record.os.pread", create=True)
    @mock.patch("linux.pcie_transport.capture_v1_record.os.open", return_value=17)
    def test_relative_offsets_and_little_endian(
        self, open_mock: mock.Mock, pread: mock.Mock, pwrite: mock.Mock, _close: mock.Mock
    ) -> None:
        pread.return_value = struct.pack("<I", 0x12345678)
        bar = UserBar("/dev/user")
        self.assertEqual(bar.read32(protocol.PCIE_REG_STATUS), 0x12345678)
        bar.write32(protocol.PCIE_REG_CONTROL, 0xAABBCCDD)
        bar.close()
        open_mock.assert_called_once()
        pread.assert_called_once_with(17, 4, 0x1C)
        pwrite.assert_called_once_with(17, b"\xdd\xcc\xbb\xaa", 0x18)

    @mock.patch("linux.pcie_transport.capture_v1_record.os.close")
    @mock.patch("linux.pcie_transport.capture_v1_record.os.read", return_value=b"record")
    @mock.patch("linux.pcie_transport.capture_v1_record.os.open", return_value=23)
    def test_reader_opens_c2h_with_eop_flush_flag(
        self, open_mock: mock.Mock, read_mock: mock.Mock, close_mock: mock.Mock
    ) -> None:
        sender = mock.Mock()
        _reader_main("/dev/c2h", 4096, sender)
        flags = open_mock.call_args.args[1]
        self.assertTrue(flags & os.O_TRUNC)
        read_mock.assert_called_once_with(23, 4096)
        close_mock.assert_called_once_with(23)
        sender.send.assert_called_once_with(("ok", b"record"))
        sender.close.assert_called_once()

    @mock.patch("linux.pcie_transport.capture_v1_record.os.close")
    @mock.patch(
        "linux.pcie_transport.capture_v1_record.os.pread",
        return_value=b"\x00\x01",
        create=True,
    )
    @mock.patch("linux.pcie_transport.capture_v1_record.os.open", return_value=17)
    def test_short_bar_read_is_rejected(
        self, _open: mock.Mock, _pread: mock.Mock, _close: mock.Mock
    ) -> None:
        bar = UserBar("/dev/user")
        with self.assertRaisesRegex(CaptureError, "short BAR read"):
            bar.read32(protocol.PCIE_REG_STATUS)
        bar.close()


class CaptureTests(unittest.TestCase):
    def test_identity_mismatch_has_no_write_or_worker_side_effect(self) -> None:
        for bar in (
            FakeBar(device_magic=0),
            FakeBar(protocol_version=protocol.PROTOCOL_VERSION + 1),
        ):
            with self.subTest(events=bar.events):
                worker_created = False

                def create_worker(_path: str, _capacity: int) -> FakeWorker:
                    nonlocal worker_created
                    worker_created = True
                    return FakeWorker(bar, ("ok", make_record()))

                with self.assertRaises(CaptureError):
                    capture_one(
                        bar,
                        "/dev/c2h",
                        4096,
                        0.1,
                        worker_factory=create_worker,
                    )
                self.assertFalse(worker_created)
                self.assertFalse(any(event[0] == "write" for event in bar.events))

    def test_non_finite_deadlines_are_rejected(self) -> None:
        for text in ("nan", "inf", "-inf"):
            with self.subTest(text=text), self.assertRaises(Exception):
                _positive_float(text)
        with self.assertRaisesRegex(ValueError, "finite"):
            capture_one(FakeBar(), "/dev/c2h", 4096, float("nan"))
        with self.assertRaisesRegex(ValueError, "finite"):
            capture_one(
                FakeBar(),
                "/dev/c2h",
                4096,
                0.1,
                poll_interval_s=float("nan"),
            )

    def test_ready_reader_running_arm_record_order(self) -> None:
        bar = FakeBar()
        worker = FakeWorker(bar, ("ok", make_record()))
        data, header = capture_one(
            bar,
            "/dev/c2h",
            4096,
            0.1,
            worker_factory=lambda _path, _capacity: worker,
        )
        self.assertEqual(data, make_record())
        self.assertEqual(header["frame_sequence"], 7)
        reader_index = bar.events.index("reader_start")
        enable_index = bar.events.index(
            ("write", protocol.PCIE_REG_CONTROL, protocol.PCIE_CONTROL_APP_ENABLE)
        )
        self.assertLess(reader_index, enable_index)
        self.assertIn(
            ("write", protocol.PCIE_REG_CONTROL, 0), bar.events[enable_index + 1 :]
        )
        self.assertTrue(worker.closed)

    def test_short_dma_record_is_discarded_and_disabled(self) -> None:
        bar = FakeBar()
        worker = FakeWorker(bar, ("ok", make_record()[:-1]))
        with self.assertRaisesRegex(CaptureError, "record length mismatch"):
            capture_one(
                bar,
                "/dev/c2h",
                4096,
                0.1,
                worker_factory=lambda _path, _capacity: worker,
            )
        self.assertEqual(bar.events[-1], ("write", protocol.PCIE_REG_CONTROL, 0))
        self.assertTrue(worker.closed)

    def test_reader_error_is_reported_and_disabled(self) -> None:
        bar = FakeBar()
        worker = FakeWorker(bar, ("error", "read failed"))
        with self.assertRaisesRegex(CaptureError, "read failed"):
            capture_one(
                bar,
                "/dev/c2h",
                4096,
                0.1,
                worker_factory=lambda _path, _capacity: worker,
            )
        self.assertEqual(bar.events[-1], ("write", protocol.PCIE_REG_CONTROL, 0))

    def test_dma_start_timeout_terminates_worker_and_disables(self) -> None:
        fake_time = FakeTime()
        bar = FakeBar(dma_runs=False)
        worker = FakeWorker(bar, ("ok", make_record()))
        with self.assertRaisesRegex(TimeoutError, "C2H_RUNNING"):
            capture_one(
                bar,
                "/dev/c2h",
                4096,
                0.02,
                poll_interval_s=0.01,
                worker_factory=lambda _path, _capacity: worker,
                clock=fake_time.clock,
                sleep=fake_time.sleep,
            )
        self.assertTrue(worker.terminated)
        self.assertTrue(worker.joined)
        self.assertTrue(worker.closed)
        self.assertEqual(bar.events[-1], ("write", protocol.PCIE_REG_CONTROL, 0))


if __name__ == "__main__":
    unittest.main()
