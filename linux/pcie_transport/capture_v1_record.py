#!/usr/bin/env python3
"""通过安路字符设备采集一条 FPGA v1 JPEG 记录"""

from __future__ import annotations

import argparse
import math
import multiprocessing
import os
import struct
import time
from collections.abc import Callable
from pathlib import Path
from typing import Protocol

from . import pcie_protocol_v1 as protocol
from .session_rearm import arm_session, wait_for_session_rearm_ready


DEFAULT_CAPACITY = protocol.FRAME_HEADER_SIZE + protocol.MAX_PAYLOAD


class CaptureError(RuntimeError):
    """设备行为或收到的记录不满足 v1 协议合同"""


class UserBar:
    """通过 ANLOGIC-PCI<n>_user 执行 32 位应用 BAR 访问

    偏移相对于 USER_BAR_BASE，驱动会在文件读写操作中加上 0x80000 用户窗口基址"""

    def __init__(self, path: str) -> None:
        self._fd = os.open(path, os.O_RDWR | getattr(os, "O_CLOEXEC", 0))

    def close(self) -> None:
        if self._fd >= 0:
            os.close(self._fd)
            self._fd = -1

    def __enter__(self) -> UserBar:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()

    def read32(self, offset: int) -> int:
        raw = os.pread(self._fd, 4, offset)
        if len(raw) != 4:
            raise CaptureError(f"short BAR read at {offset:#x}: {len(raw)} bytes")
        return struct.unpack("<I", raw)[0]

    def write32(self, offset: int, value: int) -> None:
        raw = struct.pack("<I", value & 0xFFFF_FFFF)
        written = os.pwrite(self._fd, raw, offset)
        if written != 4:
            raise CaptureError(f"short BAR write at {offset:#x}: {written} bytes")


class ReaderWorker(Protocol):
    def start(self) -> None: ...
    def poll(self) -> bool: ...
    def receive(self) -> tuple[str, object]: ...
    def is_alive(self) -> bool: ...
    def terminate(self) -> None: ...
    def join(self, timeout: float) -> None: ...
    def close(self) -> None: ...


def _reader_main(device: str, capacity: int, sender: object) -> None:
    try:
        fd = os.open(
            device, os.O_RDONLY | os.O_TRUNC | getattr(os, "O_CLOEXEC", 0)
        )
        try:
            data = os.read(fd, capacity)
        finally:
            os.close(fd)
        sender.send(("ok", data))
    except BaseException as exc:
        sender.send(("error", f"{type(exc).__name__}: {exc}"))
    finally:
        sender.close()


class ProcessReader:
    """将一次阻塞 C2H 读取隔离到独立进程，以便在有限时间内清理"""

    def __init__(self, device: str, capacity: int) -> None:
        receiver, sender = multiprocessing.Pipe(duplex=False)
        self._receiver = receiver
        self._sender = sender
        self._process = multiprocessing.Process(
            target=_reader_main,
            args=(device, capacity, sender),
            name="anlogic-v1-c2h-read",
        )
        self._started = False

    def start(self) -> None:
        self._process.start()
        self._started = True
        self._sender.close()

    def poll(self) -> bool:
        return self._receiver.poll()

    def receive(self) -> tuple[str, object]:
        return self._receiver.recv()

    def is_alive(self) -> bool:
        return self._started and self._process.is_alive()

    def terminate(self) -> None:
        if self._started:
            self._process.terminate()

    def join(self, timeout: float) -> None:
        if self._started:
            self._process.join(timeout)

    def close(self) -> None:
        self._receiver.close()
        self._sender.close()
        self._process.close()


def validate_device(read32: Callable[[int], int]) -> None:
    magic = read32(protocol.PCIE_REG_DEVICE_MAGIC)
    version = read32(protocol.PCIE_REG_PROTOCOL_VERSION)
    if magic != protocol.DEVICE_MAGIC:
        raise CaptureError(
            f"device magic mismatch: got {magic:#010x}, expected {protocol.DEVICE_MAGIC:#010x}"
        )
    if version != protocol.PROTOCOL_VERSION:
        raise CaptureError(
            f"protocol version mismatch: got {version}, expected {protocol.PROTOCOL_VERSION}"
        )


def parse_record(data: bytes) -> tuple[dict[str, object], bytes]:
    if len(data) < protocol.FRAME_HEADER_SIZE:
        raise CaptureError(f"short record: {len(data)} bytes")
    values = protocol.FRAME_HEADER_STRUCT.unpack(data[: protocol.FRAME_HEADER_SIZE])
    header = dict(zip(protocol.FRAME_HEADER_FIELD_NAMES, values, strict=True))
    for name, expected in protocol.FRAME_HEADER_EXPECTED_VALUES.items():
        if header[name] != expected:
            raise CaptureError(
                f"header {name} mismatch: got {header[name]!r}, expected {expected!r}"
            )
    payload_length = int(header["payload_length"])
    expected_length = protocol.FRAME_HEADER_SIZE + payload_length
    if not 1 <= payload_length <= protocol.MAX_PAYLOAD:
        raise CaptureError(f"invalid payload_length: {payload_length}")
    if len(data) != expected_length:
        raise CaptureError(
            f"record length mismatch: got {len(data)}, expected {expected_length}"
        )
    if header["compression"] != 1:
        raise CaptureError(f"unsupported compression: {header['compression']}")
    if header["status"] != 0 or header["error_code"] != protocol.PCIE_ERROR_NONE:
        raise CaptureError(
            f"record reports failure: status={header['status']} error={header['error_code']}"
        )
    payload = data[protocol.FRAME_HEADER_SIZE :]
    if not payload.startswith(b"\xff\xd8") or not payload.endswith(b"\xff\xd9"):
        raise CaptureError("payload lacks JPEG SOI/EOI markers")
    return header, payload


def _worker_result(worker: ReaderWorker) -> bytes:
    kind, value = worker.receive()
    if kind != "ok":
        raise CaptureError(f"C2H reader failed: {value}")
    if not isinstance(value, bytes):
        raise CaptureError("C2H reader returned a non-byte result")
    return value


def _wait_dma_running(
    read32: Callable[[int], int],
    worker: ReaderWorker,
    timeout_s: float,
    poll_interval_s: float,
    clock: Callable[[], float],
    sleep: Callable[[float], None],
) -> int:
    deadline = clock() + timeout_s
    while True:
        if worker.poll():
            _worker_result(worker)
            raise CaptureError("C2H read completed before the session was armed")
        status = read32(protocol.PCIE_REG_STATUS)
        if status & protocol.PCIE_STATUS_C2H_RUNNING:
            return status
        remaining = deadline - clock()
        if remaining <= 0:
            raise TimeoutError("C2H_RUNNING did not assert before timeout")
        sleep(min(poll_interval_s, remaining))


def _wait_record(
    worker: ReaderWorker,
    timeout_s: float,
    poll_interval_s: float,
    clock: Callable[[], float],
    sleep: Callable[[float], None],
) -> bytes:
    deadline = clock() + timeout_s
    while True:
        if worker.poll():
            return _worker_result(worker)
        remaining = deadline - clock()
        if remaining <= 0:
            raise TimeoutError("C2H record did not complete before timeout")
        sleep(min(poll_interval_s, remaining))


def _cleanup_worker(worker: ReaderWorker, timeout_s: float, *, force: bool) -> None:
    if force and worker.is_alive():
        worker.terminate()
    worker.join(timeout_s)
    if worker.is_alive():
        worker.terminate()
        worker.join(timeout_s)
        if worker.is_alive():
            raise CaptureError("C2H reader process did not terminate")
    worker.close()


def capture_one(
    bar: UserBar,
    c2h_device: str,
    capacity: int,
    timeout_s: float,
    *,
    poll_interval_s: float = 0.001,
    worker_factory: Callable[[str, int], ReaderWorker] = ProcessReader,
    record_sink: Callable[[bytes], None] | None = None,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[bytes, dict[str, object]]:
    """采集一条记录，无论成功或失败都将 APP_ENABLE 保持为低"""

    if not protocol.FRAME_HEADER_SIZE <= capacity <= DEFAULT_CAPACITY:
        raise ValueError(f"capacity must be {protocol.FRAME_HEADER_SIZE}..{DEFAULT_CAPACITY}")
    if not math.isfinite(timeout_s) or timeout_s <= 0:
        raise ValueError("timeout_s must be positive and finite")
    if not math.isfinite(poll_interval_s) or poll_interval_s <= 0:
        raise ValueError("poll_interval_s must be positive and finite")

    validate_device(bar.read32)
    worker: ReaderWorker | None = None
    try:
        wait_for_session_rearm_ready(
            bar.read32,
            bar.write32,
            timeout_s,
            poll_interval_s=poll_interval_s,
            clock=clock,
            sleep=sleep,
        )
        worker = worker_factory(c2h_device, capacity)
        worker.start()
        _wait_dma_running(
            bar.read32, worker, timeout_s, poll_interval_s, clock, sleep
        )
        arm_session(
            bar.read32,
            bar.write32,
            timeout_s,
            poll_interval_s=poll_interval_s,
            clock=clock,
            sleep=sleep,
        )
        data = _wait_record(worker, timeout_s, poll_interval_s, clock, sleep)
        bar.write32(protocol.PCIE_REG_CONTROL, 0)
        if record_sink is not None:
            record_sink(data)
        header, _payload = parse_record(data)
        _cleanup_worker(worker, timeout_s, force=False)
        worker = None
        return data, header
    except BaseException:
        try:
            bar.write32(protocol.PCIE_REG_CONTROL, 0)
        finally:
            if worker is not None:
                _cleanup_worker(worker, timeout_s, force=True)
        raise


def _positive_float(text: str) -> float:
    value = float(text)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("must be positive and finite")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-device", default="/dev/ANLOGIC-PCI0_user")
    parser.add_argument("--c2h-device", default="/dev/ANLOGIC-PCI0_c2h_0")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--timeout-seconds",
        type=_positive_float,
        required=True,
        help="Bound for each READY, DMA-start, ARMED, record, and cleanup phase",
    )
    parser.add_argument("--capacity", type=int, default=DEFAULT_CAPACITY)
    parser.add_argument("--poll-interval-seconds", type=_positive_float, default=0.001)
    args = parser.parse_args()

    with UserBar(args.user_device) as bar:
        data, header = capture_one(
            bar,
            args.c2h_device,
            args.capacity,
            args.timeout_seconds,
            poll_interval_s=args.poll_interval_seconds,
        )
    args.output.write_bytes(data)
    print(
        "CAPTURE PASS "
        f"bytes={len(data)} sequence={header['frame_sequence']} "
        f"jpeg_bytes={header['payload_length']} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
