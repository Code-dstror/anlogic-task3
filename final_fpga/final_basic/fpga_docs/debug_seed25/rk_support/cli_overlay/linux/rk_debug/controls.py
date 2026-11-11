"""Single-owner r3 debug CFG/LUT adapter, with no transport or reset actions.

The caller runs these synchronous methods on its bounded control worker while
another worker keeps receiving and releasing records. A transition guard must
bind a session-issued one-use permit to the complete proposal and preserve old
record owners after APPLIED. Hardware quiet/whole-ACK remains the CFG protocol's
job; the guard is not evidence of board or physical HDR qualification.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import asdict, dataclass, fields
import hashlib
import json
import math
import re
import threading

from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.advanced_config import AdvancedConfiguration
from linux.task3_pipeline.config_transaction import (
    AppliedConfiguration, ConfigError, ConfigTransactions, Configuration)
from linux.task3_pipeline.dehaze_lut import DehazeLutTransactions, LutSnapshot
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
from .catalog import (ADVANCED_ENABLES, BASE_FLAGS, BASE_MODES, PROCESSING_ENABLES,
                      PRODUCT_MODES, R3_SOURCE, parameter_catalog, validate_r3_preset)


Extension = AdvancedConfiguration | MonoConfiguration | None
_ACTIVE = (p.PCIE_REG_CFG_ACTIVE_MODE, p.PCIE_REG_CFG_ACTIVE_QUALITY,
           p.PCIE_REG_CFG_ACTIVE_FLAGS, p.PCIE_REG_CFG_ACTIVE_MIN_QUALITY,
           p.PCIE_REG_CFG_ACTIVE_FRAME_BUDGET, p.PCIE_REG_CFG_ACTIVE_RESTART_MCUS)
_IDENTITY = (p.PCIE_REG_CFG_SESSION, p.PCIE_REG_CFG_ACTIVE_SESSION,
             p.PCIE_REG_CFG_MODE_EPOCH, p.PCIE_REG_CFG_RESPONSE_SEQUENCE,
             p.PCIE_REG_CFG_APPLIED_CAMERA, p.PCIE_REG_CFG_APPLIED_FIRST_SEQUENCE)


class TransitionRequired(ConfigError):
    """The complete proposal needs an explicit session transition permit."""


def _hash(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'),
                                     allow_nan=False).encode('ascii')).hexdigest()


def _words(extension: Extension) -> tuple[int, ...]:
    return (0,) * 32 if extension is None else extension.words()


@dataclass(frozen=True)
class ActiveConfiguration:
    session: int
    mode_epoch: int
    configuration: Configuration
    extension: Extension
    extension_words: tuple[int, ...]
    request_sequence: int
    camera: int
    first_actual_frame_sequence: int
    status: int
    fingerprint: str

    @property
    def base(self): return self.configuration

    @property
    def schema(self): return 0 if self.extension is None else self.extension.schema

    def as_dict(self): return asdict(self)


@dataclass(frozen=True)
class ControlProposal:
    baseline: ActiveConfiguration
    configuration: Configuration
    extension: Extension
    extension_words: tuple[int, ...]
    requires_transition: bool
    transition_reasons: tuple[str, ...]
    digest: str

    @property
    def base(self): return self.configuration

    def as_dict(self): return asdict(self)


def _integer(value, name, symbols=None, *, mask=False):
    if type(value) is int:
        return value
    if symbols and type(value) is str and value in symbols:
        return symbols[value]
    if mask and type(value) in (list, tuple):
        result = 0
        for entry in value:
            if type(entry) is not str or entry not in symbols or result & symbols[entry]:
                raise ConfigError(name + ' requires distinct known flag names')
            result |= symbols[entry]
        return result
    if type(value) is str and len(value) <= 32 and re.fullmatch(r'(?:0|[1-9][0-9]*|0x[0-9a-fA-F]+)', value):
        return int(value, 16 if value.startswith('0x') else 10)
    raise ConfigError(name + ' requires an integer, canonical decimal/hex string, or documented symbol')


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ConfigError('duplicate JSON field: ' + key)
        result[key] = value
    return result


def _document(document):
    if type(document) is str:
        if len(document.encode('utf-8')) > 65536:
            raise ConfigError('configuration JSON exceeds 65536 bytes')
        try:
            document = json.loads(document, object_pairs_hook=_unique_object,
                parse_constant=lambda value: (_ for _ in ()).throw(ConfigError('non-finite JSON value')))
        except (ValueError, RecursionError) as exc:
            raise ConfigError('invalid configuration JSON') from exc
    if type(document) is not dict or set(document) - {'schema', 'base', 'extension'}:
        raise ConfigError('configuration requires only schema/base/extension fields')
    return document


def _merge(cls, patch, original, *, full=False, schema=None):
    if type(patch) is not dict:
        raise ConfigError('base/extension must be objects')
    names = {f.name for f in fields(cls)}
    if set(patch) - names:
        raise ConfigError('unknown configuration field: ' + str(sorted(set(patch) - names, key=str)))
    if full and names - {'schema'} - set(patch):
        raise ConfigError('schema change requires a complete extension object')
    values = asdict(original)
    for name, value in patch.items():
        symbols, mask = None, False
        if cls is Configuration and name == 'mode': symbols = BASE_MODES
        if cls is Configuration and name == 'flags': symbols, mask = BASE_FLAGS, True
        if cls is MonoConfiguration and name == 'product_mode': symbols = PRODUCT_MODES
        if cls is MonoConfiguration and name == 'processing_enables': symbols, mask = PROCESSING_ENABLES, True
        if cls is AdvancedConfiguration and name == 'enable': symbols, mask = ADVANCED_ENABLES, True
        if type(getattr(original, name)) is tuple:
            if type(value) not in (list, tuple) or len(value) != 8:
                raise ConfigError(name + ' requires exactly eight lanes')
            values[name] = tuple(_integer(item, name) for item in value)
        else:
            values[name] = _integer(value, name, symbols, mask=mask)
    if schema is not None and values['schema'] != schema:
        raise ConfigError('root schema and extension.schema differ')
    return cls(**values)


def _product(extension: Extension) -> str:
    if isinstance(extension, MonoConfiguration):
        return {0: 'SDR', 1: 'SDR_LZ', 2: 'HDR'}.get(extension.product_mode, 'INVALID')
    if isinstance(extension, AdvancedConfiguration):
        if extension.enable & p.PCIE_CFG_EXT_FEATURE_CFS: return 'SDR_LZ'
        if extension.enable & p.PCIE_CFG_EXT_FEATURE_HDR: return 'HDR'
    return 'SDR'


def _dehaze(extension: Extension) -> bool:
    if isinstance(extension, MonoConfiguration):
        return bool(extension.processing_enables & p.PCIE_CFG_V2_ENABLES_DEHAZE)
    return isinstance(extension, AdvancedConfiguration) and bool(extension.enable & p.PCIE_CFG_EXT_FEATURE_DEHAZE)


def _proposal(baseline, configuration, extension):
    before, after = _product(baseline.extension), _product(extension)
    reasons = []
    if before != after: reasons.append('PRODUCT_MODE_CHANGE:' + before + '->' + after)
    if before == 'SDR_LZ' or after == 'SDR_LZ': reasons.append('LZ_EPOCH_OWNER_RETENTION')
    if after == 'HDR': reasons.append('LAB_HDR_EXPLICIT_AUTHORIZATION')
    words = _words(extension)
    body = {'baseline': baseline.fingerprint, 'base': asdict(configuration),
            'extension_words': words, 'transition_reasons': reasons}
    return ControlProposal(baseline, configuration, extension, words, bool(reasons),
                           tuple(reasons), _hash(body))


class DebugControls:
    """One existing ConfigTransactions owner, shared with an explicit LUT client.

    No method drains/stops DMA, clears unknown hardware replies or auto-cancels.
    A failed CFG command retains this object and the original owner as terminal.
    snapshot() is cached software state; read_active()/discover() perform MMIO.
    """
    def __init__(self, transactions: ConfigTransactions, *, lut_timeout_s: float,
                 profile='r3', transition_guard=None):
        if not isinstance(transactions, ConfigTransactions):
            raise TypeError('requires the sole ConfigTransactions owner')
        if profile != 'r3': raise ValueError('only source-audited r3 is supported')
        if (type(lut_timeout_s) not in (int, float) or not math.isfinite(lut_timeout_s)
                or lut_timeout_s <= 0):
            raise ValueError('finite positive caller LUT timeout required')
        if transition_guard is not None and not callable(transition_guard):
            raise TypeError('transition_guard must be callable')
        self.transactions = transactions
        self.lut_timeout_s, self.transition_guard = lut_timeout_s, transition_guard
        self._lock, self._state_lock = threading.Lock(), threading.Lock()
        self._terminal, self._failure, self._operation = False, None, None
        self._lut = None
        self._last_active = self._last_request = self._last_applied = self._last_lut = None
        self._applied_count = self._lut_load_count = 0

    @contextmanager
    def _exclusive(self, operation):
        if not self._lock.acquire(blocking=False):
            raise ConfigError('debug control owner busy', p.PCIE_CFG_ERROR_BUSY)
        try:
            if self._terminal or self.transactions._terminal or (self._lut and self._lut._terminal):
                raise ConfigError('debug control owner terminal; retained without recovery', p.PCIE_CFG_ERROR_STALE)
            with self._state_lock: self._operation = operation
            yield
        finally:
            with self._state_lock: self._operation = None
            self._lock.release()

    def _fault(self, exc):
        with self._state_lock:
            self._terminal, self._failure = True, type(exc).__name__ + ': ' + str(exc)[:240]

    def _read(self, register):
        try:
            value = self.transactions.bar.read32(register)
            if type(value) is not int or not 0 <= value <= 0xffffffff:
                raise ConfigError('BAR returned a non-uint32 register')
            return value
        except Exception as exc:
            self._fault(exc)
            raise

    def _validate(self, base, extension):
        caps = self.transactions.capabilities
        if (caps.compiled_profile, caps.max_width, caps.max_height, caps.camera_present) != (
                p.PCIE_CFG_PROFILE_MONO1920, 1920, 1080, 1):
            raise ConfigError('selected live profile is not r3 mono 1920x1080', p.PCIE_CFG_ERROR_UNSUPPORTED)
        caps.supports(base)
        if extension is not None:
            self.transactions.validate_extension(extension)
        if isinstance(extension, MonoConfiguration) and base.mode != p.PCIE_CFG_MODE_COLOR:
            raise ConfigError('schema2 requires base COLOR; select independent enables')
        if isinstance(extension, AdvancedConfiguration):
            validate_r3_preset(extension)
            if extension.enable & 0x30 and base.mode != p.PCIE_CFG_MODE_GAUSSIAN:
                raise ConfigError('r3 schema1 lane preset requires base GAUSSIAN')

    def _read_active(self):
        self.transactions.extension_capabilities()  # enables full32-word ACK verification too
        def sample():
            status = self._read(p.PCIE_REG_CFG_STATUS)
            identity = tuple(self._read(reg) for reg in _IDENTITY)
            base = Configuration(*(self._read(reg) for reg in _ACTIVE))
            words = tuple(self._read(p.PCIE_REG_CFG_EXT_ACTIVE_BASE + 4*i) for i in range(32))
            error = self._read(p.PCIE_REG_CFG_ERROR)
            return status, identity, base, words, error
        first, second = sample(), sample()
        if first != second:
            raise ConfigError('active configuration changed during snapshot', p.PCIE_CFG_ERROR_STALE)
        status, identity, base, words, error = second
        session, active_session, epoch, sequence, camera, first_sequence = identity
        if status & (p.PCIE_CFG_STATUS_BUSY | p.PCIE_CFG_STATUS_READY):
            raise ConfigError('CFG has an in-flight owner', p.PCIE_CFG_ERROR_BUSY)
        if (error or status & p.PCIE_CFG_STATUS_ERROR or not status & p.PCIE_CFG_STATUS_SESSION_READY
                or not session or active_session != session or session != self.transactions.session):
            raise ConfigError('active CFG session/status is not a clean owned snapshot', p.PCIE_CFG_ERROR_SESSION)
        if not any(words): extension = None
        elif words[0] & 255 == 1: extension = AdvancedConfiguration.from_words(words)
        elif words[0] & 255 == 2: extension = MonoConfiguration.from_words(words)
        else: raise ConfigError('unknown active extension schema')
        self._validate(base, extension)
        if camera not in (0,1) or not self.transactions.capabilities.camera_present & (1<<camera):
            raise ConfigError('active camera is absent from the selected topology')
        fingerprint = _hash({'identity': identity, 'base': asdict(base), 'extension_words': words})
        active = ActiveConfiguration(session, epoch, base, extension, words, sequence,
                                     camera, first_sequence, status, fingerprint)
        with self._state_lock: self._last_active = active
        return active

    def read_active(self) -> ActiveConfiguration:
        with self._exclusive('read_active'): return self._read_active()

    def discover(self) -> dict:
        with self._exclusive('discover'):
            tx = self.transactions
            advanced = tx.extension_capabilities()
            schemas = self._read(p.PCIE_REG_CFG_EXT_SCHEMAS)
            mono = asdict(tx.mono_capabilities()) if schemas & 4 else None
            algo_available = (self._read(p.PCIE_REG_ALGO_MAGIC) == p.PCIE_ALGO_MAGIC and
                              self._read(p.PCIE_REG_ALGO_ABI_VERSION) == p.PCIE_ALGO_ABI_VERSION)
            return {'source_reference': dict(R3_SOURCE),
                    'source_identity_scope': 'OFFLINE_REFERENCE_NOT_LIVE_BIT_ATTESTATION',
                    'live': {'base': asdict(tx.capabilities), 'schema1': asdict(advanced),
                             'schemas': schemas, 'schema2': mono,
                             'lut_features': self._read(p.PCIE_REG_ALGO_FEATURES) if algo_available else 0},
                    'parameters': parameter_catalog(), 'active': self._read_active().as_dict(),
                    'request_format': {'root_keys': ['schema', 'base', 'extension'],
                        'patch': 'same schema only; cross-schema extension must be complete',
                        'integers': 'integer or exact decimal/0x string; no bool/float',
                        'schema0': 'extension must be empty or null; PREPARE clears all extension words'}}

    def propose(self, document: dict | str, *, active: ActiveConfiguration | None = None) -> ControlProposal:
        with self._exclusive('propose'):
            document = _document(document)
            if active is None: active = self._read_active()
            if not isinstance(active, ActiveConfiguration): raise TypeError('invalid active snapshot')
            schema = _integer(document.get('schema', active.schema), 'schema')
            base = _merge(Configuration, document.get('base', {}), active.configuration)
            if schema == 0:
                if document.get('extension') not in (None, {}):
                    raise ConfigError('schema0 requires empty/null extension')
                extension = None
            elif schema in (1, 2):
                cls = AdvancedConfiguration if schema == 1 else MonoConfiguration
                extension = _merge(cls, document.get('extension', {}),
                    active.extension if active.schema == schema else cls(),
                    full=active.schema != schema, schema=schema)
            else: raise ConfigError('schema must be 0, 1 or 2')
            self._validate(base, extension)
            return _proposal(active, base, extension)

    def _lut_idle(self, *, required_generation=None):
        if (self._read(p.PCIE_REG_ALGO_MAGIC) != p.PCIE_ALGO_MAGIC or
                self._read(p.PCIE_REG_ALGO_ABI_VERSION) != p.PCIE_ALGO_ABI_VERSION or
                not self._read(p.PCIE_REG_ALGO_FEATURES) & p.PCIE_ALGO_FEATURE_F21):
            if required_generation is not None: raise ConfigError('F21 LUT owner unavailable')
            return
        status = self._read(p.PCIE_REG_ALGO_STATUS)
        if status & (p.PCIE_ALGO_STATUS_BUSY | p.PCIE_ALGO_STATUS_LOADING | p.PCIE_ALGO_STATUS_ERROR):
            raise ConfigError('LUT owner busy/loading/error; no CFG or new LUT command issued')
        if required_generation is not None and (not status & p.PCIE_ALGO_STATUS_LUT_VALID or
                self._read(p.PCIE_REG_ALGO_ACTIVE_GENERATION) != required_generation):
            raise ConfigError('requested dehaze generation is not the actual valid LUT')

    def apply(self, proposal: ControlProposal, *, transition_permit=None) -> AppliedConfiguration:
        with self._exclusive('apply'):
            if not isinstance(proposal, ControlProposal): raise TypeError('requires ControlProposal')
            current = self._read_active()
            if current.fingerprint != proposal.baseline.fingerprint:
                raise ConfigError('proposal baseline is stale', p.PCIE_CFG_ERROR_STALE)
            self._validate(proposal.configuration, proposal.extension)
            expected = _proposal(current, proposal.configuration, proposal.extension)
            if (proposal.digest, proposal.extension_words, proposal.requires_transition, proposal.transition_reasons) != (
                    expected.digest, expected.extension_words, expected.requires_transition, expected.transition_reasons):
                raise ConfigError('proposal digest/transition fields do not match complete request')
            self._lut_idle(required_generation=(proposal.extension.dehaze_lut_generation
                           if _dehaze(proposal.extension) else None))
            if expected.requires_transition:
                if self.transition_guard is None or transition_permit is None or type(transition_permit) is bool:
                    raise TransitionRequired('session-issued transition permit required: ' + ', '.join(expected.transition_reasons))
                self.transition_guard(expected, transition_permit)
            elif transition_permit is not None:
                raise ConfigError('ordinary CFG request must not consume a transition permit')
            with self._state_lock: self._last_request = expected
            try:
                prepared = self.transactions.prepare(expected.configuration, extension=expected.extension)
                applied = self.transactions.commit(prepared)
            except Exception as exc:
                self._fault(exc)
                raise
            with self._state_lock:
                self._last_applied = applied
                self._applied_count += 1
            return applied

    def _lut_client(self, active):
        if self._lut is None:
            tx = self.transactions
            self._lut = DehazeLutTransactions(tx.bar, session=active.session,
                timeout_s=self.lut_timeout_s, poll_interval_s=tx.poll_interval_s,
                clock=tx.clock, sleep=tx.sleep)
        return self._lut

    def query_lut(self) -> LutSnapshot:
        """An actual sequenced QUERY command; discover itself never issues one."""
        with self._exclusive('query_lut'):
            active = self._read_active()
            self._lut_idle()
            try: result = self._lut_client(active).query()
            except Exception as exc:
                self._fault(exc)
                raise
            with self._state_lock: self._last_lut = result
            return result

    def load_lut(self, generation: int) -> LutSnapshot:
        with self._exclusive('load_lut'):
            generation = _integer(generation, 'generation')
            if not 1 <= generation <= 0xffffffff: raise ConfigError('LUT generation must be 1..uint32_max')
            active = self._read_active()
            last = self._last_applied
            if (_dehaze(active.extension) or last is None or
                    (last.session, last.mode_epoch, last.configuration, last.extension) !=
                    (active.session, active.mode_epoch, active.configuration, active.extension)):
                raise ConfigError('LUT load requires this owner confirmed F21-off APPLIED at the current epoch')
            self._lut_idle()
            try: result = self._lut_client(active).load(generation)
            except ValueError:
                raise  # e.g. generation did not increase; no uncertain mutation
            except Exception as exc:
                self._fault(exc)
                raise
            with self._state_lock:
                self._last_lut = result
                self._lut_load_count += 1
            return result

    def snapshot(self) -> dict:
        with self._state_lock:
            return {'operation': self._operation, 'terminal': self._terminal or self.transactions._terminal,
                    'failure': self._failure, 'applied_count': self._applied_count,
                    'lut_load_count': self._lut_load_count,
                    'requested': self._last_request.as_dict() if self._last_request else None,
                    'last_observed_active': self._last_active.as_dict() if self._last_active else None,
                    'last_applied': asdict(self._last_applied) if self._last_applied else None,
                    'last_lut': asdict(self._last_lut) if self._last_lut else None,
                    'hardware_validation': 'NOT_RUN', 'physical_hdr_exposure': 'UNQUALIFIED'}
