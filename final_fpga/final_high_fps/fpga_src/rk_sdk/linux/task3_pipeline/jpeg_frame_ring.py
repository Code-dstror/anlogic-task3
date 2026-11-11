"""JPG1 descriptor/pin control only; no DMA or recovery policy."""
from __future__ import annotations

from dataclasses import dataclass, fields
import math
import time

from . import pcie_protocol_v1 as p
from .raw_frame_store import BarAccess


class JpegRingError(RuntimeError):
    def __init__(self, message: str, code: int = p.PCIE_JPEG_ERROR_INVALID):
        super().__init__(message)
        self.code = code


def _uint(value: object, name: str, maximum: int = 0xffffffff) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= maximum:
        raise JpegRingError(f"{name} must be unsigned and <= {maximum}")
    return value


@dataclass(frozen=True)
class JpegDescriptor:
    camera: int
    slot: int
    generation: int
    session: int
    frame_sequence: int
    mode_epoch: int
    width: int
    height: int
    length: int
    state: int
    quality: int

    def validate(self, *, committed: bool = False, pinned: bool = False) -> None:
        for field in fields(self):
            _uint(getattr(self, field.name), field.name)
        if self.camera >= p.PCIE_JPEG_CAMERA_COUNT or self.slot >= p.PCIE_JPEG_SLOT_COUNT:
            raise JpegRingError("descriptor camera/slot outside ring")
        if self.slot // p.PCIE_JPEG_SLOTS_PER_CAMERA != self.camera:
            raise JpegRingError("descriptor slot belongs to another camera")
        state = self.state & p.PCIE_JPEG_STATE_MASK
        if self.state & ~(p.PCIE_JPEG_STATE_MASK | p.PCIE_JPEG_STATE_PINNED) or state > p.PCIE_JPEG_STATE_SENDING:
            raise JpegRingError("invalid descriptor state")
        if committed and state != p.PCIE_JPEG_STATE_COMMITTED:
            raise JpegRingError("descriptor is not committed", p.PCIE_JPEG_ERROR_BUSY if state == p.PCIE_JPEG_STATE_SENDING else p.PCIE_JPEG_ERROR_EMPTY)
        if pinned and not self.state & p.PCIE_JPEG_STATE_PINNED:
            raise JpegRingError("descriptor is not pinned")
        if committed or state in (p.PCIE_JPEG_STATE_COMMITTED, p.PCIE_JPEG_STATE_SENDING):
            if not self.session or not self.generation or not 1 <= self.length <= p.PCIE_JPEG_MAX_FRAME:
                raise JpegRingError("invalid committed identity/length")
            if not 1 <= self.width <= 65535 or not 1 <= self.height <= 65535 or not 1 <= self.quality <= 100:
                raise JpegRingError("invalid committed dimensions/quality")


@dataclass(frozen=True)
class JpegHandle:
    descriptor: JpegDescriptor


_DESC_REGISTERS = (
    p.PCIE_REG_JPEG_DESC_CAMERA, p.PCIE_REG_JPEG_DESC_SLOT,
    p.PCIE_REG_JPEG_DESC_GENERATION, p.PCIE_REG_JPEG_DESC_SESSION,
    p.PCIE_REG_JPEG_DESC_FRAME_SEQUENCE, p.PCIE_REG_JPEG_DESC_MODE_EPOCH,
    p.PCIE_REG_JPEG_DESC_WIDTH, p.PCIE_REG_JPEG_DESC_HEIGHT,
    p.PCIE_REG_JPEG_DESC_LENGTH, p.PCIE_REG_JPEG_DESC_STATE,
    p.PCIE_REG_JPEG_DESC_QUALITY,
)


class JpegFrameRing:
    """One caller-owned MMIO command stream with a caller-supplied timeout.

    A QUERY/PIN race, session loss, timeout or uncertain MMIO failure makes the
    client terminal. It never retries, resets, opens DMA or releases implicitly.
    Constructor performs only reads and requires the CFG/JPEG BOOT ACK ready.
    """

    def __init__(self, bar: BarAccess, *, timeout_s: float,
                 poll_interval_s: float = 0.001, clock=time.monotonic, sleep=time.sleep):
        if not math.isfinite(timeout_s) or timeout_s <= 0 or not math.isfinite(poll_interval_s) or poll_interval_s <= 0:
            raise ValueError("finite positive caller timeout/poll interval required")
        self.bar, self.timeout_s, self.poll_interval_s = bar, timeout_s, poll_interval_s
        self.clock, self.sleep = clock, sleep
        self._terminal = False
        expected = ((p.PCIE_REG_DEVICE_MAGIC, p.DEVICE_MAGIC),
                    (p.PCIE_REG_PROTOCOL_VERSION, p.PROTOCOL_VERSION),
                    (p.PCIE_REG_JPEG_MAGIC, p.PCIE_JPEG_MAGIC),
                    (p.PCIE_REG_JPEG_ABI_VERSION, p.PCIE_JPEG_ABI_VERSION),
                    (p.PCIE_REG_JPEG_CONFIG, p.PCIE_JPEG_CONFIG),
                    (p.PCIE_REG_JPEG_MAX_FRAME, p.PCIE_JPEG_MAX_FRAME),
                    (p.PCIE_REG_CFG_MAGIC, p.PCIE_CFG_MAGIC),
                    (p.PCIE_REG_CFG_ABI_VERSION, p.PCIE_CFG_ABI_VERSION))
        for register, value in expected:
            if self._read(register) != value:
                raise JpegRingError(f"JPEG/CFG ABI identity mismatch at {register:#x}")
        capabilities = self._read(p.PCIE_REG_CAPABILITIES)
        required = p.PCIE_CAPABILITY_JPEG_FRAME_RING | p.PCIE_CAPABILITY_CONFIG_TRANSACTION
        if capabilities & required != required:
            raise JpegRingError("JPEG ring/configuration capability unavailable")
        self.session = self._read(p.PCIE_REG_CFG_SESSION)
        self.sequence = self._read(p.PCIE_REG_JPEG_RESPONSE_SEQUENCE)
        self._check_session()

    def _read(self, register: int) -> int:
        try:
            return _uint(self.bar.read32(register), "MMIO read")
        except Exception:
            self._terminal = True
            raise

    def _write(self, register: int, value: int) -> None:
        try:
            self.bar.write32(register, value)
        except Exception:
            self._terminal = True
            raise

    def _fail(self, message: str, code: int = p.PCIE_JPEG_ERROR_STALE) -> None:
        self._terminal = True
        raise JpegRingError(message, code)

    def _check_session(self) -> None:
        if self._terminal:
            raise JpegRingError("JPEG client terminal; no automatic recovery", p.PCIE_JPEG_ERROR_STALE)
        if (not self.session or self._read(p.PCIE_REG_CFG_SESSION) != self.session or
            self._read(p.PCIE_REG_CFG_ACTIVE_SESSION) != self.session or
            self._read(p.PCIE_REG_JPEG_SESSION) != self.session or
            not self._read(p.PCIE_REG_CFG_STATUS) & p.PCIE_CFG_STATUS_SESSION_READY or
            not self._read(p.PCIE_REG_JPEG_STATUS) & p.PCIE_JPEG_STATUS_SESSION_READY):
            self._fail("JPEG/CFG session lost or not initialized", p.PCIE_JPEG_ERROR_RESET)

    def _selection(self, camera: int, slot: int, *, latest: bool) -> None:
        _uint(camera, "camera", p.PCIE_JPEG_CAMERA_COUNT - 1)
        _uint(slot, "slot", 0xffff)
        if not self._read(p.PCIE_REG_CFG_CAMERA_PRESENT) & (1 << camera):
            raise JpegRingError("physical camera unavailable", p.PCIE_JPEG_ERROR_RANGE)
        if latest and slot == p.PCIE_JPEG_LATEST_SLOT:
            return
        if slot >= p.PCIE_JPEG_SLOT_COUNT or slot // p.PCIE_JPEG_SLOTS_PER_CAMERA != camera:
            raise JpegRingError("explicit slot does not belong to camera", p.PCIE_JPEG_ERROR_RANGE)

    def _execute(self, command: int, camera: int, slot: int, generation: int = 0) -> None:
        self._check_session()
        self._selection(camera, slot, latest=command == p.PCIE_JPEG_COMMAND_QUERY)
        _uint(generation, "generation")
        if command != p.PCIE_JPEG_COMMAND_QUERY and not generation:
            raise JpegRingError("exact nonzero generation required")
        if self._read(p.PCIE_REG_JPEG_STATUS) & p.PCIE_JPEG_STATUS_BUSY:
            raise JpegRingError("JPEG command already busy", p.PCIE_JPEG_ERROR_BUSY)
        self.sequence = (self.sequence + 1) & 0xffffffff or 1
        params = ((p.PCIE_REG_JPEG_REQUEST_CAMERA, camera), (p.PCIE_REG_JPEG_REQUEST_SLOT, slot),
                  (p.PCIE_REG_JPEG_REQUEST_GENERATION, generation),
                  (p.PCIE_REG_JPEG_REQUEST_SESSION, self.session),
                  (p.PCIE_REG_JPEG_REQUEST_SEQUENCE, self.sequence))
        for register, value in params:
            self._write(register, value)
        self._check_session()
        self._write(p.PCIE_REG_JPEG_COMMAND, command)
        deadline = self.clock() + self.timeout_s
        while True:
            self._check_session()
            status = self._read(p.PCIE_REG_JPEG_STATUS)
            response = self._read(p.PCIE_REG_JPEG_RESPONSE_SEQUENCE)
            if response == self.sequence and status & p.PCIE_JPEG_STATUS_DONE and not status & p.PCIE_JPEG_STATUS_BUSY:
                code = self._read(p.PCIE_REG_JPEG_ERROR)
                self._check_session()
                if code or status & p.PCIE_JPEG_STATUS_ERROR:
                    if code in (p.PCIE_JPEG_ERROR_STALE, p.PCIE_JPEG_ERROR_RESET):
                        self._terminal = True
                    raise JpegRingError(f"JPEG command {command} failed: error {code}", code)
                return
            remaining = deadline - self.clock()
            if remaining <= 0:
                self._terminal = True
                raise TimeoutError("JPEG command timeout; hardware ownership retained")
            self.sleep(min(self.poll_interval_s, remaining))

    def _descriptor(self) -> JpegDescriptor:
        descriptor = JpegDescriptor(*(self._read(register) for register in _DESC_REGISTERS))
        self._check_session()
        status = self._read(p.PCIE_REG_JPEG_STATUS)
        if (self._read(p.PCIE_REG_JPEG_RESPONSE_SEQUENCE) != self.sequence or
            not status & p.PCIE_JPEG_STATUS_DONE or status & (p.PCIE_JPEG_STATUS_BUSY | p.PCIE_JPEG_STATUS_ERROR)):
            self._fail("JPEG descriptor response changed during read")
        try:
            descriptor.validate()
        except JpegRingError:
            self._terminal = True
            raise
        return descriptor

    def query(self, camera: int, slot: int = p.PCIE_JPEG_LATEST_SLOT) -> JpegDescriptor:
        self._execute(p.PCIE_JPEG_COMMAND_QUERY, camera, slot)
        descriptor = self._descriptor()
        if descriptor.camera != camera or (slot != p.PCIE_JPEG_LATEST_SLOT and descriptor.slot != slot):
            self._fail("JPEG QUERY response camera/slot mismatch")
        if (descriptor.state & p.PCIE_JPEG_STATE_MASK) in (p.PCIE_JPEG_STATE_COMMITTED, p.PCIE_JPEG_STATE_SENDING) and descriptor.session != self.session:
            self._fail("JPEG descriptor belongs to an old session")
        return descriptor

    def _match(self, expected: JpegDescriptor, actual: JpegDescriptor) -> None:
        if any(getattr(expected, field.name) != getattr(actual, field.name)
               for field in fields(expected) if field.name != "state"):
            self._fail("JPEG descriptor identity or metadata changed")

    def pin(self, camera: int, slot: int = p.PCIE_JPEG_LATEST_SLOT) -> JpegHandle:
        """QUERY latest/explicit then exact PIN; races terminate without retry."""
        return self.pin_descriptor(self.query(camera, slot))

    def pin_descriptor(self, expected: JpegDescriptor) -> JpegHandle:
        expected.validate(committed=True)
        self._check_session()
        if expected.session != self.session:
            self._fail("JPEG pin descriptor belongs to another session")
        self._execute(p.PCIE_JPEG_COMMAND_PIN, expected.camera, expected.slot, expected.generation)
        actual = self._descriptor()
        self._match(expected, actual)
        try:
            actual.validate(committed=True, pinned=True)
        except JpegRingError:
            self._terminal = True
            raise
        return JpegHandle(actual)

    def release(self, handle: JpegHandle) -> None:
        expected = handle.descriptor
        expected.validate(committed=True, pinned=True)
        self._check_session()
        if expected.session != self.session:
            self._fail("JPEG handle belongs to another session")
        self._execute(p.PCIE_JPEG_COMMAND_RELEASE, expected.camera, expected.slot, expected.generation)
        actual = self._descriptor()
        self._match(expected, actual)
        if actual.state & p.PCIE_JPEG_STATE_PINNED:
            self._fail("JPEG RELEASE response still pinned")
