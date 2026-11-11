"""RAW1 BAR ABI and independent RAW10 reference; no DMA or reset actions."""
from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import struct
import time
from typing import Protocol

from . import pcie_protocol_v1 as p

PACKING = "RAW10_PACKED_LE5_RASTER"


class RawFrameError(ValueError):
    """Invalid metadata, stale handle, or a failed RAW BAR command."""

    def __init__(self, message: str, code: int = p.PCIE_RAW_ERROR_INVALID):
        super().__init__(message)
        self.code = code


def _uint(value: object, name: str, maximum: int = 0xFFFFFFFF) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= maximum:
        raise RawFrameError(f"{name} must be an unsigned integer <= {maximum}")
    return value


def pack_raw10(samples: Iterable[int]) -> bytes:
    """Pack raster samples as consecutive little-endian 10-bit values.

    Four samples form five bytes; a partial group has ceil(count*10/8) bytes.
    Rows do not restart the bit stream. Unused high tail bits are zero.
    """
    output = bytearray()
    accumulator = bits = 0
    for sample in samples:
        accumulator |= _uint(sample, "sample", 1023) << bits
        bits += 10
        while bits >= 8:
            output.append(accumulator & 255)
            accumulator >>= 8
            bits -= 8
    if bits:
        output.append(accumulator)
    return bytes(output)


def unpack_raw10(data: bytes, sample_count: int) -> list[int]:
    count = _uint(sample_count, "sample_count")
    if len(data) != (count * 10 + 7) // 8:
        raise RawFrameError("RAW packed byte length disagrees with sample_count")
    output = []
    accumulator = bits = 0
    cursor = 0
    for _ in range(count):
        while bits < 10:
            accumulator |= data[cursor] << bits
            cursor += 1
            bits += 8
        output.append(accumulator & 1023)
        accumulator >>= 10
        bits -= 10
    if accumulator:
        raise RawFrameError("nonzero unused RAW tail bits")
    return output


@dataclass(frozen=True)
class FrameDescriptor:
    camera: int
    slot: int
    generation: int
    frame_sequence: int
    mode_epoch: int
    width: int
    height: int
    sample_count: int
    packed_bytes: int
    state: int
    session: int
    format: int

    def validate(self, *, pinned: bool = False) -> None:
        for name, value in vars(self).items():
            _uint(value, name)
        if self.camera >= p.PCIE_RAW_CAMERA_COUNT or self.slot >= p.PCIE_RAW_SLOTS_PER_CAMERA:
            raise RawFrameError("RAW camera/slot out of range")
        if not self.generation or not self.width or not self.height:
            raise RawFrameError("RAW generation and dimensions must be positive")
        if self.sample_count != self.width * self.height:
            raise RawFrameError("RAW sample_count disagrees with dimensions")
        if self.packed_bytes != (self.sample_count * 10 + 7) // 8 or not 0 < self.packed_bytes <= p.PCIE_RAW_MAX_FRAME:
            raise RawFrameError("RAW packed_bytes disagrees with dimensions or capacity")
        if self.state & p.PCIE_RAW_STATE_MASK != p.PCIE_RAW_STATE_COMMITTED:
            raise RawFrameError("RAW descriptor is not committed")
        if self.state & ~(p.PCIE_RAW_STATE_MASK | p.PCIE_RAW_STATE_PINNED):
            raise RawFrameError("unknown RAW descriptor state bits")
        if self.format != p.PCIE_RAW_FORMAT_RAW10:
            raise RawFrameError("current RAW BAR/file format must be canonical RAW10")
        if pinned and not self.state & p.PCIE_RAW_STATE_PINNED:
            raise RawFrameError("RAW descriptor is not pinned")


@dataclass(frozen=True)
class FrameHandle:
    session: int
    descriptor: FrameDescriptor

    def validate(self) -> None:
        _uint(self.session, "session")
        self.descriptor.validate(pinned=True)


class BarAccess(Protocol):
    def read32(self, offset: int) -> int: ...
    def write32(self, offset: int, value: int) -> None: ...


_DESCRIPTOR_REGISTERS = (
    p.PCIE_REG_RAW_DESC_CAMERA, p.PCIE_REG_RAW_DESC_SLOT,
    p.PCIE_REG_RAW_DESC_GENERATION, p.PCIE_REG_RAW_DESC_FRAME_SEQUENCE,
    p.PCIE_REG_RAW_DESC_MODE_EPOCH, p.PCIE_REG_RAW_DESC_WIDTH,
    p.PCIE_REG_RAW_DESC_HEIGHT, p.PCIE_REG_RAW_DESC_SAMPLE_COUNT,
    p.PCIE_REG_RAW_DESC_PACKED_BYTES, p.PCIE_REG_RAW_DESC_STATE,
    p.PCIE_REG_RAW_DESC_SESSION, p.PCIE_REG_RAW_DESC_FORMAT,
)


class RawFrameStore:
    """One explicitly owned BAR command stream, compatible with existing UserBar.

    Caller holds exclusive command ownership. Timeouts leave hardware state
    intact; no retry, reset, DMA open/close, driver reload or UART is performed.
    Handles cannot survive a boot, bitstream reload, or application reset.
    """

    def __init__(self, bar: BarAccess, *, timeout_s: float = 1.0,
                 poll_interval_s: float = 0.001, clock=time.monotonic, sleep=time.sleep):
        if timeout_s < 0 or poll_interval_s <= 0:
            raise ValueError("invalid polling interval/timeout")
        self.bar, self.timeout_s, self.poll_interval_s = bar, timeout_s, poll_interval_s
        self.clock, self.sleep = clock, sleep
        self._terminal = False
        if bar.read32(p.PCIE_REG_DEVICE_MAGIC) != p.DEVICE_MAGIC or bar.read32(p.PCIE_REG_PROTOCOL_VERSION) != p.PROTOCOL_VERSION:
            raise RawFrameError("AJPG device identity mismatch")
        if not bar.read32(p.PCIE_REG_CAPABILITIES) & p.PCIE_CAPABILITY_RAW_FRAME_STORE:
            raise RawFrameError("RAW capability unavailable")
        expected = ((p.PCIE_REG_RAW_MAGIC, p.PCIE_RAW_MAGIC),
                    (p.PCIE_REG_RAW_ABI_VERSION, p.PCIE_RAW_ABI_VERSION),
                    (p.PCIE_REG_RAW_CONFIG, p.PCIE_RAW_CONFIG),
                    (p.PCIE_REG_RAW_MAX_BLOCK, p.PCIE_RAW_MAX_BLOCK),
                    (p.PCIE_REG_RAW_MAX_FRAME, p.PCIE_RAW_MAX_FRAME))
        for register, value in expected:
            if bar.read32(register) != value:
                raise RawFrameError(f"RAW ABI identity mismatch at {register:#x}")
        self.session = bar.read32(p.PCIE_REG_RAW_SESSION)
        self.sequence = bar.read32(p.PCIE_REG_RAW_RESPONSE_SEQUENCE)

    def _check_session(self, session: int) -> None:
        if self._terminal:
            raise RawFrameError("RAW client terminal; no automatic recovery", p.PCIE_RAW_ERROR_STALE)
        if self.bar.read32(p.PCIE_REG_RAW_SESSION) != session:
            self._terminal = True
            raise RawFrameError("RAW application session changed", p.PCIE_RAW_ERROR_RESET)

    def _execute(self, command: int, camera: int, slot: int, generation: int = 0,
                 offset: int = 0, length: int = 0, descriptor_session: int = 0) -> int:
        self._check_session(self.session)
        for name, value in (("camera", camera), ("slot", slot), ("generation", generation),
                            ("offset", offset), ("length", length), ("descriptor_session", descriptor_session)):
            _uint(value, name)
        if camera >= p.PCIE_RAW_CAMERA_COUNT or slot >= p.PCIE_RAW_SLOTS_PER_CAMERA:
            raise RawFrameError("RAW request camera/slot out of range")
        if self.bar.read32(p.PCIE_REG_RAW_STATUS) & p.PCIE_RAW_STATUS_BUSY:
            raise RawFrameError("RAW command already busy", p.PCIE_RAW_ERROR_BUSY)
        self.sequence = (self.sequence + 1) & 0xFFFFFFFF
        if self.sequence == 0:
            self.sequence = 1  # Zero is reserved by the hardware command ABI.
        params = ((p.PCIE_REG_RAW_REQUEST_CAMERA, camera), (p.PCIE_REG_RAW_REQUEST_SLOT, slot),
                  (p.PCIE_REG_RAW_REQUEST_GENERATION, generation), (p.PCIE_REG_RAW_REQUEST_OFFSET, offset),
                  (p.PCIE_REG_RAW_REQUEST_LENGTH, length),
                  (p.PCIE_REG_RAW_REQUEST_SESSION, descriptor_session),
                  (p.PCIE_REG_RAW_REQUEST_SEQUENCE, self.sequence))
        for register, value in params:
            self.bar.write32(register, value)
        self.bar.write32(p.PCIE_REG_RAW_COMMAND, command)
        deadline = self.clock() + self.timeout_s
        while True:
            self._check_session(self.session)
            status = self.bar.read32(p.PCIE_REG_RAW_STATUS)
            response_sequence = self.bar.read32(p.PCIE_REG_RAW_RESPONSE_SEQUENCE)
            if response_sequence == self.sequence and status & p.PCIE_RAW_STATUS_DONE and not status & p.PCIE_RAW_STATUS_BUSY:
                code = self.bar.read32(p.PCIE_REG_RAW_ERROR)
                self._check_session(self.session)
                if code != p.PCIE_RAW_ERROR_OK or status & p.PCIE_RAW_STATUS_ERROR:
                    if code in (p.PCIE_RAW_ERROR_STALE, p.PCIE_RAW_ERROR_RESET):
                        self._terminal = True
                    raise RawFrameError(f"RAW command {command} failed: error {code}", code)
                return status
            remaining = deadline - self.clock()
            if remaining <= 0:
                self._terminal = True
                raise TimeoutError("RAW command did not complete; hardware state retained")
            self.sleep(min(self.poll_interval_s, remaining))

    def _descriptor(self, *, pinned: bool = False) -> FrameDescriptor:
        descriptor = FrameDescriptor(*(self.bar.read32(reg) for reg in _DESCRIPTOR_REGISTERS))
        self._check_session(self.session)
        descriptor.validate(pinned=pinned)
        return descriptor

    def query(self, camera: int, slot: int) -> FrameDescriptor:
        self._execute(p.PCIE_RAW_COMMAND_QUERY, camera, slot)
        descriptor = self._descriptor()
        if (descriptor.camera, descriptor.slot) != (camera, slot):
            self._terminal = True
            raise RawFrameError("RAW query response identity mismatch", p.PCIE_RAW_ERROR_STALE)
        return descriptor

    def pin(self, camera: int, slot: int = 0, generation: int = 0) -> FrameHandle:
        """Query one explicit slot, then pin its exact source-session/generation.

        generation=0 accepts that slot's queried generation; there is no RAW
        atomic latest selector. A changed descriptor is terminal, never retried.
        """
        _uint(generation, "generation")
        descriptor = self.query(camera, slot)
        if generation and descriptor.generation != generation:
            self._terminal = True
            raise RawFrameError("RAW queried generation is stale", p.PCIE_RAW_ERROR_STALE)
        return self.pin_descriptor(descriptor)

    def pin_descriptor(self, expected: FrameDescriptor) -> FrameHandle:
        expected.validate()
        self._execute(p.PCIE_RAW_COMMAND_PIN, expected.camera, expected.slot, expected.generation,
                      descriptor_session=expected.session)
        descriptor = self._descriptor(pinned=True)
        self._match_descriptor(expected, descriptor)
        return FrameHandle(self.session, descriptor)

    def _match_descriptor(self, expected: FrameDescriptor, actual: FrameDescriptor) -> None:
        if any(getattr(expected, name) != getattr(actual, name)
               for name in FrameDescriptor.__dataclass_fields__ if name != "state"):
            self._terminal = True
            raise RawFrameError("RAW response descriptor identity mismatch", p.PCIE_RAW_ERROR_STALE)

    def _handle(self, handle: FrameHandle) -> FrameDescriptor:
        handle.validate()
        if handle.session != self.session:
            raise RawFrameError("handle belongs to a different RAW session", p.PCIE_RAW_ERROR_RESET)
        self._check_session(handle.session)
        return handle.descriptor

    def fetch(self, handle: FrameHandle, offset: int, length: int) -> bytes:
        descriptor = self._handle(handle)
        _uint(offset, "offset")
        _uint(length, "length")
        if offset % 16 or not 1 <= length <= p.PCIE_RAW_MAX_BLOCK or offset + length > descriptor.packed_bytes:
            raise RawFrameError("RAW FETCH range/alignment invalid", p.PCIE_RAW_ERROR_RANGE)
        status = self._execute(p.PCIE_RAW_COMMAND_FETCH, descriptor.camera, descriptor.slot,
                               descriptor.generation, offset, length, descriptor.session)
        self._match_descriptor(descriptor, self._descriptor(pinned=True))
        if not status & p.PCIE_RAW_STATUS_CACHE_VALID or self.bar.read32(p.PCIE_REG_RAW_CACHE_VALID_BYTES) != length:
            raise RawFrameError("RAW cache completion length/valid mismatch")
        data = bytearray()
        for cursor in range(0, length, 4):
            data.extend(struct.pack("<I", self.bar.read32(p.PCIE_RAW_CACHE_BASE + cursor)))
        self._check_session(handle.session)
        if any(data[length:]):
            raise RawFrameError("RAW cache tail padding is not zero")
        return bytes(data[:length])

    def read_frame(self, handle: FrameHandle) -> bytes:
        descriptor = self._handle(handle)
        data = bytearray()
        for offset in range(0, descriptor.packed_bytes, p.PCIE_RAW_MAX_BLOCK):
            data.extend(self.fetch(handle, offset, min(p.PCIE_RAW_MAX_BLOCK, descriptor.packed_bytes - offset)))
        unpack_raw10(bytes(data), descriptor.sample_count)
        return bytes(data)

    def release(self, handle: FrameHandle) -> None:
        descriptor = self._handle(handle)
        self._execute(p.PCIE_RAW_COMMAND_RELEASE, descriptor.camera, descriptor.slot, descriptor.generation,
                      descriptor_session=descriptor.session)
        self._match_descriptor(descriptor, self._descriptor())

    def replay(self, handle: FrameHandle) -> None:
        """Wait for full replay acknowledgment; the caller still owns its pin."""
        descriptor = self._handle(handle)
        self._execute(p.PCIE_RAW_COMMAND_REPLAY, descriptor.camera, descriptor.slot, descriptor.generation,
                      descriptor_session=descriptor.session)
        self._match_descriptor(descriptor, self._descriptor(pinned=True))


def read_frame_file(raw_path: str | Path, metadata_path: str | Path) -> tuple[FrameHandle, bytes]:
    """Read a completed RAW fixture. Reject packing/stride, identity and length errors."""
    metadata = json.loads(Path(metadata_path).read_text(encoding="utf-8"))
    if not isinstance(metadata, dict) or metadata.get("abi_version") != p.PCIE_RAW_ABI_VERSION or metadata.get("packing") != PACKING:
        raise RawFrameError("unsupported RAW file metadata ABI/packing")
    try:
        descriptor = FrameDescriptor(**{name: metadata["descriptor_session" if name == "session" else name]
                                       for name in FrameDescriptor.__dataclass_fields__})
        descriptor.validate()
        session = _uint(metadata["session"], "session")
    except (KeyError, TypeError) as exc:
        raise RawFrameError("missing/invalid RAW file metadata") from exc
    if metadata.get("row_padding") is not False or metadata.get("row_stride_bits") != descriptor.width * 10:
        raise RawFrameError("RAW file stride/row padding mismatch")
    data = Path(raw_path).read_bytes()
    unpack_raw10(data, descriptor.sample_count)
    expected_sha = metadata.get("sha256")
    if expected_sha is not None and expected_sha != hashlib.sha256(data).hexdigest():
        raise RawFrameError("RAW file SHA256 mismatch")
    return FrameHandle(session, descriptor), data
