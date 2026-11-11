"""CFG1 atomic configuration client. No DMA, reset, retry or recovery actions."""
from __future__ import annotations

from dataclasses import dataclass
import math
import time

from . import pcie_protocol_v1 as p
from .raw_frame_store import BarAccess
from .advanced_config import AdvancedConfiguration, AdvancedCapabilities
from .mono_config_v2 import MonoConfiguration, MonoCapabilities


class ConfigError(RuntimeError):
    def __init__(self, message: str, code: int = p.PCIE_CFG_ERROR_INVALID):
        super().__init__(message)
        self.code = code


def _uint(value: object, name: str, maximum: int = 0xFFFFFFFF) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= maximum:
        raise ConfigError(f"{name} must be an unsigned integer <= {maximum}")
    return value


@dataclass(frozen=True)
class Configuration:
    mode: int = p.PCIE_CFG_MODE_COLOR
    quality: int = p.PCIE_CFG_DEFAULT_QUALITY
    flags: int = 0
    min_quality: int = p.PCIE_CFG_MINIMUM_QUALITY
    frame_budget: int = 0
    restart_mcus: int = 0

    @property
    def adaptive_enabled(self) -> bool:
        return bool(self.flags & p.PCIE_CFG_FLAG_ADAPTIVE_QUALITY and self.frame_budget)

    def validate(self) -> None:
        for name, value in vars(self).items():
            _uint(value, name)
        if self.mode not in (p.PCIE_CFG_MODE_COLOR, p.PCIE_CFG_MODE_GRAY,
                             p.PCIE_CFG_MODE_GAUSSIAN, p.PCIE_CFG_MODE_HISTOGRAM):
            raise ConfigError("unsupported configuration mode", p.PCIE_CFG_ERROR_UNSUPPORTED)
        if not p.PCIE_CFG_MINIMUM_QUALITY <= self.quality <= p.PCIE_CFG_MAXIMUM_QUALITY:
            raise ConfigError("quality must be 1..100")
        if not p.PCIE_CFG_MINIMUM_QUALITY <= self.min_quality <= self.quality:
            raise ConfigError("min_quality must be 1..quality")
        if self.flags & ~p.PCIE_CFG_FLAG_ADAPTIVE_QUALITY:
            raise ConfigError("unknown configuration flags")
        if self.flags & p.PCIE_CFG_FLAG_ADAPTIVE_QUALITY and not self.frame_budget:
            raise ConfigError("adaptive quality requires a nonzero caller frame budget")
        if self.frame_budget > p.MAX_PAYLOAD or self.restart_mcus > 0xFFFF:
            raise ConfigError("frame budget or restart MCU interval out of range")


@dataclass(frozen=True)
class ConfigCapabilities:
    features: int
    compiled_profile: int
    camera_present: int
    max_width: int
    max_height: int

    def supports(self, configuration: Configuration) -> None:
        configuration.validate()
        needed = p.PCIE_CFG_FEATURE_FRAME_APPLIED
        if configuration.quality != p.PCIE_CFG_DEFAULT_QUALITY:
            needed |= p.PCIE_CFG_FEATURE_DYNAMIC_QUALITY
        if configuration.frame_budget or configuration.flags:
            needed |= p.PCIE_CFG_FEATURE_FRAME_BUDGET
        if configuration.restart_mcus:
            needed |= p.PCIE_CFG_FEATURE_RESTART
        if configuration.mode != p.PCIE_CFG_MODE_COLOR:
            needed |= p.PCIE_CFG_FEATURE_SHARED_Y
        if self.features & needed != needed:
            raise ConfigError("requested configuration feature unavailable", p.PCIE_CFG_ERROR_UNSUPPORTED)


@dataclass(frozen=True)
class PreparedConfiguration:
    session: int
    request_sequence: int
    previous_mode_epoch: int
    configuration: Configuration
    extension: AdvancedConfiguration | MonoConfiguration | None = None


@dataclass(frozen=True)
class AppliedConfiguration:
    session: int
    request_sequence: int
    mode_epoch: int
    camera: int
    first_actual_frame_sequence: int
    configuration: Configuration
    extension: AdvancedConfiguration | MonoConfiguration | None = None


_SHADOW_REGISTERS = (p.PCIE_REG_CFG_REQUEST_MODE, p.PCIE_REG_CFG_REQUEST_QUALITY,
                     p.PCIE_REG_CFG_REQUEST_FLAGS, p.PCIE_REG_CFG_REQUEST_MIN_QUALITY,
                     p.PCIE_REG_CFG_REQUEST_FRAME_BUDGET, p.PCIE_REG_CFG_REQUEST_RESTART_MCUS)
_ACTIVE_REGISTERS = (p.PCIE_REG_CFG_ACTIVE_MODE, p.PCIE_REG_CFG_ACTIVE_QUALITY,
                     p.PCIE_REG_CFG_ACTIVE_FLAGS, p.PCIE_REG_CFG_ACTIVE_MIN_QUALITY,
                     p.PCIE_REG_CFG_ACTIVE_FRAME_BUDGET, p.PCIE_REG_CFG_ACTIVE_RESTART_MCUS)


class ConfigTransactions:
    """One explicitly owned CFG command stream, duck-compatible with UserBar.

    Construction is read-only. PREPARE negotiates host capabilities and writes
    shadow settings. Timeout or session change terminates this client; caller
    owns any subsequent maintenance decision. Never infer DMA quiescence here.
    """
    def __init__(self, bar: BarAccess, *, timeout_s: float, poll_interval_s: float = 0.001,
                 host_capabilities: int = p.PCIE_CFG_FEATURE_FRAME_APPLIED,
                 clock=time.monotonic, sleep=time.sleep):
        if not math.isfinite(timeout_s) or timeout_s <= 0 or not math.isfinite(poll_interval_s) or poll_interval_s <= 0:
            raise ValueError("caller must supply a finite positive timeout and polling interval")
        self.bar, self.timeout_s, self.poll_interval_s = bar, timeout_s, poll_interval_s
        self.clock, self.sleep = clock, sleep
        self._terminal = False
        self._prepared: PreparedConfiguration | None = None
        self._extension_capabilities: AdvancedCapabilities | None = None
        self._mono_capabilities: MonoCapabilities | None = None
        if bar.read32(p.PCIE_REG_DEVICE_MAGIC) != p.DEVICE_MAGIC or bar.read32(p.PCIE_REG_PROTOCOL_VERSION) != p.PROTOCOL_VERSION:
            raise ConfigError("AJPG device identity mismatch")
        if not bar.read32(p.PCIE_REG_CAPABILITIES) & p.PCIE_CAPABILITY_CONFIG_TRANSACTION:
            raise ConfigError("CFG capability unavailable", p.PCIE_CFG_ERROR_UNSUPPORTED)
        if bar.read32(p.PCIE_REG_CFG_MAGIC) != p.PCIE_CFG_MAGIC or bar.read32(p.PCIE_REG_CFG_ABI_VERSION) != p.PCIE_CFG_ABI_VERSION:
            raise ConfigError("independent CFG ABI identity mismatch")
        self.capabilities = ConfigCapabilities(*(bar.read32(register) for register in (
            p.PCIE_REG_CFG_FEATURES, p.PCIE_REG_CFG_COMPILED_PROFILE, p.PCIE_REG_CFG_CAMERA_PRESENT,
            p.PCIE_REG_CFG_MAX_WIDTH, p.PCIE_REG_CFG_MAX_HEIGHT)))
        if not self.capabilities.features & p.PCIE_CFG_FEATURE_FRAME_APPLIED:
            raise ConfigError("actual-frame APPLIED capability required", p.PCIE_CFG_ERROR_UNSUPPORTED)
        if self.capabilities.compiled_profile not in (p.PCIE_CFG_PROFILE_MONO1920,
                p.PCIE_CFG_PROFILE_DUAL1920, p.PCIE_CFG_PROFILE_MONO3840):
            raise ConfigError("unknown compiled configuration profile", p.PCIE_CFG_ERROR_UNSUPPORTED)
        if not 0 < self.capabilities.camera_present <= 3 or not self.capabilities.max_width or not self.capabilities.max_height:
            raise ConfigError("invalid configuration geometry/presence capability")
        self.host_capabilities = _uint(host_capabilities, "host_capabilities")
        if not self.host_capabilities & p.PCIE_CFG_FEATURE_FRAME_APPLIED or self.host_capabilities & ~self.capabilities.features:
            raise ConfigError("host capability selection unsupported", p.PCIE_CFG_ERROR_UNSUPPORTED)
        initial_session = bar.read32(p.PCIE_REG_CFG_SESSION)
        initial_status = bar.read32(p.PCIE_REG_CFG_STATUS)
        self.session: int | None = initial_session if (
            initial_session and initial_status & p.PCIE_CFG_STATUS_SESSION_READY) else None
        self.sequence = bar.read32(p.PCIE_REG_CFG_RESPONSE_SEQUENCE)
        self._check_session()

    def _check_session(self) -> None:
        if self._terminal:
            raise ConfigError("CFG client terminal; no automatic recovery", p.PCIE_CFG_ERROR_STALE)
        if self.session is not None and self._read(p.PCIE_REG_CFG_SESSION) != self.session:
            self._terminal = True
            raise ConfigError("CFG application session changed", p.PCIE_CFG_ERROR_SESSION)

    def _read(self, offset: int) -> int:
        try:
            return self.bar.read32(offset)
        except Exception:
            self._terminal = True
            raise

    def wait_session_ready(self) -> int:
        """Wait for real source BOOT ACK before binding a new client's lifetime."""
        deadline = self.clock() + self.timeout_s
        while True:
            self._check_session()
            session = self._read(p.PCIE_REG_CFG_SESSION)
            status = self._read(p.PCIE_REG_CFG_STATUS)
            active_session = self._read(p.PCIE_REG_CFG_ACTIVE_SESSION)
            if session and status & p.PCIE_CFG_STATUS_SESSION_READY:
                if active_session != session:
                    self._terminal = True
                    raise ConfigError("CFG response session identity mismatch", p.PCIE_CFG_ERROR_SESSION)
                if self._read(p.PCIE_REG_CFG_SESSION) == session:
                    if self.session is None:
                        self.session = session
                        self.sequence = self._read(p.PCIE_REG_CFG_RESPONSE_SEQUENCE)
                    return session
            remaining = deadline - self.clock()
            if remaining <= 0:
                self._terminal = True
                raise TimeoutError("CFG session BOOT ACK timeout; no recovery")
            self.sleep(min(self.poll_interval_s, remaining))

    def _write(self, offset: int, value: int) -> None:
        try:
            self.bar.write32(offset, value)
        except Exception:
            self._terminal = True
            raise

    def _wait(self, sequence: int, completion_bit: int) -> None:
        deadline = self.clock() + self.timeout_s
        while True:
            self._check_session()
            status = self._read(p.PCIE_REG_CFG_STATUS)
            response_sequence = self._read(p.PCIE_REG_CFG_RESPONSE_SEQUENCE)
            if response_sequence == sequence:
                if status & p.PCIE_CFG_STATUS_ERROR:
                    code = self._read(p.PCIE_REG_CFG_ERROR)
                    self._terminal = True
                    raise ConfigError(f"CFG command failed: error {code}", code)
                if completion_bit == p.PCIE_CFG_STATUS_READY:
                    completed = bool(status & p.PCIE_CFG_STATUS_READY and status & p.PCIE_CFG_STATUS_BUSY)
                elif completion_bit:
                    completed = bool(status & completion_bit and not status & p.PCIE_CFG_STATUS_BUSY)
                else:
                    completed = not status & (p.PCIE_CFG_STATUS_BUSY | p.PCIE_CFG_STATUS_READY | p.PCIE_CFG_STATUS_APPLIED)
                completed = completed and bool(status & p.PCIE_CFG_STATUS_SESSION_READY)
                if completed:
                    code = self._read(p.PCIE_REG_CFG_ERROR)
                    if code != p.PCIE_CFG_ERROR_OK:
                        self._terminal = True
                        raise ConfigError(f"CFG completion failed: error {code}", code)
                    self._check_session()
                    if self._read(p.PCIE_REG_CFG_ACTIVE_SESSION) != self.session:
                        self._terminal = True
                        raise ConfigError("CFG response session identity mismatch", p.PCIE_CFG_ERROR_SESSION)
                    return
            remaining = deadline - self.clock()
            if remaining <= 0:
                self._terminal = True
                raise TimeoutError("CFG transaction timeout; pending hardware state retained")
            self.sleep(min(self.poll_interval_s, remaining))

    def extension_capabilities(self) -> AdvancedCapabilities:
        """Explicit opt-in probe; old clients never touch the new address window."""
        self._check_session()
        if self._extension_capabilities is None:
            if (self._read(p.PCIE_REG_CFG_EXT_MAGIC) != p.PCIE_CFG_EXT_MAGIC
                    or self._read(p.PCIE_REG_CFG_EXT_ABI_VERSION) != p.PCIE_CFG_EXT_ABI_VERSION
                    or self._read(p.PCIE_REG_CFG_EXT_WIDTH) != p.PCIE_CFG_EXT_WIDTH_BITS):
                raise ConfigError('CFG_EXT schema1 owner unavailable', p.PCIE_CFG_ERROR_UNSUPPORTED)
            capabilities = AdvancedCapabilities(
                self._read(p.PCIE_REG_CFG_EXT_SUPPORTED), self._read(p.PCIE_REG_CFG_EXT_STRIPS),
                self._read(p.PCIE_REG_CFG_EXT_COMBINATIONS))
            sparse_without_strips = (capabilities.strips == 0
                and not capabilities.supported & (p.PCIE_CFG_EXT_FEATURE_F22 | p.PCIE_CFG_EXT_FEATURE_F23)
                and self._read(p.PCIE_REG_RECORD_MAGIC) == p.PCIE_RECORD_V2_MAGIC
                and self._read(p.PCIE_REG_RECORD_ABI_VERSION) == p.PCIE_RECORD_V2_ABI_VERSION
                and self._read(p.PCIE_REG_RECORD_SUPPORTED_VERSIONS) & (1 << p.PCIE_RECORD_V4_VERSION)
                and self._read(p.PCIE_REG_RECORD_FEATURES) &
                    (p.PCIE_RECORD_V4_FEATURE_VERSION4 | p.PCIE_RECORD_V4_FEATURE_LANE_POINTS) ==
                    (p.PCIE_RECORD_V4_FEATURE_VERSION4 | p.PCIE_RECORD_V4_FEATURE_LANE_POINTS))
            if not 0 <= capabilities.supported <= 255 or not (1 <= capabilities.strips <= 8 or sparse_without_strips) or (
                    capabilities.combinations & ~p.PCIE_CFG_EXT_COMBINATION_HDR_THEN_NR):
                raise ConfigError('invalid CFG_EXT production capability descriptor')
            self._check_session()
            self._extension_capabilities = capabilities
        return self._extension_capabilities

    def mono_capabilities(self) -> MonoCapabilities:
        """Read the three opt-in schema2 descriptors from the actual CFG owner."""
        self._check_session()
        if self._mono_capabilities is None:
            self.extension_capabilities()  # same mailbox ABI, geometry and session
            if not self._read(p.PCIE_REG_CFG_EXT_SCHEMAS) & (1 << p.PCIE_CFG_V2_SCHEMA):
                raise ConfigError('CFG_EXT schema2 owner unavailable', p.PCIE_CFG_ERROR_UNSUPPORTED)
            caps = MonoCapabilities(self._read(p.PCIE_REG_CFG_EXT_V2_MODES),
                                    self._read(p.PCIE_REG_CFG_EXT_V2_ENABLES))
            caps.validate()
            self._check_session()
            self._mono_capabilities = caps
        return self._mono_capabilities

    def validate_extension(self, extension: AdvancedConfiguration | MonoConfiguration) -> None:
        if isinstance(extension, MonoConfiguration):
            extension.validate(self.mono_capabilities(), width=self.capabilities.max_width,
                               height=self.capabilities.max_height, camera_present=self.capabilities.camera_present)
            return
        if not isinstance(extension, AdvancedConfiguration):
            raise TypeError('requires immutable AdvancedConfiguration')
        extension.validate(self.extension_capabilities(), width=self.capabilities.max_width,
                           height=self.capabilities.max_height, camera_present=self.capabilities.camera_present)

    def prepare(self, configuration: Configuration, *, extension: AdvancedConfiguration | MonoConfiguration | None = None) -> PreparedConfiguration:
        self._check_session()
        self.capabilities.supports(configuration)
        if extension is not None:
            if isinstance(extension, MonoConfiguration) and configuration.mode != p.PCIE_CFG_V2_REQUIRED_BASE_MODE:
                raise ConfigError('schema2 requires base COLOR mode; use independent processing enables')
            self.validate_extension(extension)
        self.wait_session_ready()
        status = self._read(p.PCIE_REG_CFG_STATUS)
        if not status & p.PCIE_CFG_STATUS_SESSION_READY:
            raise ConfigError("CFG session not ready", p.PCIE_CFG_ERROR_SESSION)
        if self._prepared is not None or status & (p.PCIE_CFG_STATUS_BUSY | p.PCIE_CFG_STATUS_READY):
            raise ConfigError("CFG transaction already owned or busy", p.PCIE_CFG_ERROR_BUSY)
        previous_epoch = self._read(p.PCIE_REG_CFG_MODE_EPOCH)
        self.sequence = (self.sequence + 1) & 0xFFFFFFFF or 1
        self._write(p.PCIE_REG_CFG_HOST_CAPABILITIES, self.host_capabilities)
        for register, value in zip(_SHADOW_REGISTERS, vars(configuration).values()):
            self._write(register, value)
        if extension is not None:
            for i, word in enumerate(extension.words()):
                self._write(p.PCIE_REG_CFG_EXT_SHADOW_BASE + 4*i, word)
        self._write(p.PCIE_REG_CFG_REQUEST_SESSION, self.session)
        self._write(p.PCIE_REG_CFG_REQUEST_SEQUENCE, self.sequence)
        self._check_session()
        self._write(p.PCIE_REG_CFG_COMMAND, p.PCIE_CFG_COMMAND_PREPARE if extension is None else p.PCIE_CFG_COMMAND_PREPARE_EXT)
        self._wait(self.sequence, p.PCIE_CFG_STATUS_READY)
        self._prepared = PreparedConfiguration(self.session, self.sequence, previous_epoch, configuration, extension)
        return self._prepared

    def _handle(self, prepared: PreparedConfiguration) -> None:
        self._check_session()
        if self._prepared is None or prepared != self._prepared or prepared.session != self.session:
            raise ConfigError("configuration is not this client's prepared transaction", p.PCIE_CFG_ERROR_STALE)

    def commit(self, prepared: PreparedConfiguration) -> AppliedConfiguration:
        self._handle(prepared)
        self._write(p.PCIE_REG_CFG_COMMAND, p.PCIE_CFG_COMMAND_COMMIT)
        self._wait(prepared.request_sequence, p.PCIE_CFG_STATUS_APPLIED)
        active = Configuration(*(self._read(register) for register in _ACTIVE_REGISTERS))
        extension = None
        if self._extension_capabilities is not None:
            words = tuple(self._read(p.PCIE_REG_CFG_EXT_ACTIVE_BASE + 4*i) for i in range(32))
            expected = (0,) * 32 if prepared.extension is None else prepared.extension.words()
            if words != expected:
                self._terminal = True
                raise ConfigError('APPLIED extension differs from the complete prepared snapshot', p.PCIE_CFG_ERROR_STALE)
            if prepared.extension is not None:
                parser = MonoConfiguration if isinstance(prepared.extension, MonoConfiguration) else AdvancedConfiguration
                extension = parser.from_words(words)
        applied = AppliedConfiguration(self._read(p.PCIE_REG_CFG_ACTIVE_SESSION), prepared.request_sequence,
            self._read(p.PCIE_REG_CFG_MODE_EPOCH), self._read(p.PCIE_REG_CFG_APPLIED_CAMERA),
            self._read(p.PCIE_REG_CFG_APPLIED_FIRST_SEQUENCE), active, extension)
        self._check_session()
        if active != prepared.configuration or applied.session != prepared.session or (
                applied.mode_epoch == prepared.previous_mode_epoch or not 0 <= applied.camera < 2 or
                not self.capabilities.camera_present & (1 << applied.camera)):
            self._terminal = True
            raise ConfigError("APPLIED identity/configuration does not match the actual transaction", p.PCIE_CFG_ERROR_STALE)
        self._prepared = None
        return applied

    def cancel(self, prepared: PreparedConfiguration) -> None:
        self._handle(prepared)
        status = self._read(p.PCIE_REG_CFG_STATUS)
        if not status & p.PCIE_CFG_STATUS_READY:
            raise ConfigError("only a prepared configuration can be cancelled", p.PCIE_CFG_ERROR_BUSY)
        self._write(p.PCIE_REG_CFG_COMMAND, p.PCIE_CFG_COMMAND_CANCEL)
        self._wait(prepared.request_sequence, 0)
        self._prepared = None
