"""Same-fd host-only guarded source-reset extension; no raw CONTROL access.

capabilities is a read. request acknowledges one pulse only; wait_new_boot is
read-only and requires the driver's repeated hardware BOOT/idle observation.
The module opt-in is an operator declaration, never firmware attestation.
"""
from dataclasses import dataclass
import errno
import math
import struct
import time

from linux.dma_c2h_candidate.c2h_abi import USER_ABI
from .driver import debug_abi as a

CAP = struct.Struct(a.C2H_GET_DEBUG_CAP_FORMAT)
REQUEST = struct.Struct(a.C2H_SOURCE_RESET_FORMAT)


class DebugDriverError(RuntimeError): pass
class Unsupported(DebugDriverError): pass
class ResetRejected(DebugDriverError): pass
class ResetUncertain(DebugDriverError): pass


@dataclass(frozen=True)
class DebugCapabilities:
    version: int
    user_abi: int
    capabilities: int
    reset_state: int
    issued_source_session: int
    observed_source_session: int
    reset_requests: int
    reserved: int

    @property
    def features(self): return self.capabilities

    @property
    def source_reset_supported(self):
        return bool(self.capabilities & a.RKDBG_CAP_SOURCE_RESET)


class DebugDriverAPI:
    def __init__(self, receiver):
        if not hasattr(receiver, '_io') or not callable(getattr(receiver._io, 'ioctl', None)):
            raise TypeError('existing same-fd C2H Receiver required')
        self.receiver = receiver
        self._last = None
        self._attempted_session = None
        self._owner = None
        self._request_number = None
        self._acknowledged = False
        self.last_outcome = 'NOT_REQUESTED'

    def capabilities(self):
        if getattr(self.receiver, '_closed', False):
            raise DebugDriverError('Receiver is closed')
        raw = bytearray(CAP.size)
        try:
            self.receiver._io.ioctl(a.C2H_GET_DEBUG_CAP, raw)
        except OSError as error:
            if error.errno in (errno.ENOTTY, errno.EOPNOTSUPP):
                raise Unsupported('debug extension unavailable; no reset requested') from error
            raise
        if len(raw) != CAP.size:
            raise DebugDriverError('invalid GET_DEBUG_CAP size')
        cap = DebugCapabilities(*CAP.unpack(raw))
        if (cap.version != a.RKDBG_ABI_VERSION or cap.user_abi != USER_ABI or cap.reserved or
                cap.capabilities & ~a.RKDBG_CAP_SOURCE_RESET or cap.reset_state not in (0, 1, 2, 3) or
                (cap.reset_requests == 0 and (cap.issued_source_session or cap.reset_state in (1, 2))) or
                (cap.reset_requests and not cap.issued_source_session) or
                (cap.reset_state == a.RKDBG_RESET_NEW_BOOT and
                 (not cap.observed_source_session or cap.observed_source_session == cap.issued_source_session)) or
                (self._last is not None and (cap.reset_requests < self._last.reset_requests or
                 cap.capabilities != self._last.capabilities or
                 (cap.reset_requests == self._last.reset_requests and
                  cap.issued_source_session != self._last.issued_source_session)))):
            raise DebugDriverError('inconsistent debug extension capability/identity')
        self._last = cap
        return cap

    def request_source_reset(self, expected_cfg_session):
        if type(expected_cfg_session) is not int or not 1 <= expected_cfg_session <= 0xffffffff:
            raise ValueError('expected CFG source session must be nonzero uint32')
        cap = self.capabilities()
        if not cap.source_reset_supported:
            raise Unsupported('source reset not opted in by reviewed module configuration')
        if (self._attempted_session == expected_cfg_session or cap.issued_source_session == expected_cfg_session or
                cap.reset_state in (a.RKDBG_RESET_ISSUED, a.RKDBG_RESET_UNCERTAIN) or cap.reset_requests == 0xffffffff):
            raise ResetRejected('duplicate/pending/uncertain reset cannot be retried')
        info = self.receiver.snapshot()
        if not info.transport_drained or self.receiver.leased_count:
            raise ResetRejected('host transport/consumer ownership is not drained')
        self._owner = self.receiver.owner_identity()
        request = bytearray(REQUEST.pack(a.RKDBG_ABI_VERSION, expected_cfg_session, 0, 0))
        self._attempted_session = expected_cfg_session
        self._acknowledged = False
        self._request_number = None
        self.last_outcome = 'REQUEST_OUTCOME_UNKNOWN'
        try:
            result = self.receiver._io.ioctl(a.C2H_SOURCE_RESET, request)
            if result not in (0, None):
                raise ResetUncertain('unexpected source-reset ioctl return')
        except OSError as error:
            if error.errno in (errno.EBUSY, errno.ESTALE, errno.EALREADY, errno.EINVAL):
                self.last_outcome = 'REJECTED_NO_PULSE'
                raise ResetRejected('source reset rejected by locked hardware/owner guard') from error
            # Even ENOTTY here is an inconsistent extension after capability
            # acceptance. Do not disguise an attempted command as no-request.
            raise ResetUncertain('source reset outcome unknown; retain owner and do not retry') from error
        self.last_outcome = 'ISSUED_NOT_COMPLETED'
        try:
            issued = self.capabilities()
            if (issued.reset_requests != cap.reset_requests+1 or issued.issued_source_session != expected_cfg_session or
                    issued.reset_state not in (a.RKDBG_RESET_ISSUED, a.RKDBG_RESET_NEW_BOOT)):
                raise ValueError('reset acknowledgement identity mismatch')
        except Exception as error:
            self.last_outcome = 'REQUEST_OUTCOME_UNKNOWN'
            raise ResetUncertain('reset acknowledgement unavailable; retain owner, no retry') from error
        # Fast hardware may already have a new BOOT by this first read. The
        # caller must still use wait_new_boot for host-owner/idle confirmation.
        self._request_number = issued.reset_requests
        self._acknowledged = True
        return issued

    def wait_new_boot(self, expected_old_session, timeout_s, *, poll_interval_s=.01):
        if type(expected_old_session) is not int or not 1 <= expected_old_session <= 0xffffffff:
            raise ValueError('expected old CFG source session must be nonzero uint32')
        if (not self._acknowledged or self._owner is None or self._request_number is None or
                self._attempted_session != expected_old_session):
            raise ResetRejected('this API has no matching acknowledged source-reset request')
        if (type(timeout_s) not in (int, float) or not math.isfinite(timeout_s) or not 0 < timeout_s <= 60 or
                type(poll_interval_s) not in (int, float) or not math.isfinite(poll_interval_s) or
                not .001 <= poll_interval_s <= .1):
            raise ValueError('invalid reset observation deadline')
        deadline = time.monotonic() + timeout_s
        while True:
            try:
                cap = self.capabilities()
            except Exception as error:
                self.last_outcome = 'OBSERVATION_UNKNOWN'
                raise ResetUncertain('source reset observation unavailable; no retry') from error
            if (not cap.source_reset_supported or cap.reset_requests != self._request_number or
                    cap.issued_source_session != expected_old_session or
                    cap.reset_state in (a.RKDBG_RESET_NONE, a.RKDBG_RESET_UNCERTAIN)):
                self.last_outcome = 'OBSERVATION_UNKNOWN'
                raise ResetUncertain('source reset observation does not match the issued request')
            if cap.reset_state == a.RKDBG_RESET_NEW_BOOT:
                try:
                    owner = self.receiver.owner_identity()
                    info = self.receiver.snapshot()
                    if (owner != self._owner or not info.transport_drained or
                            self.receiver.leased_count or cap.observed_source_session == expected_old_session):
                        raise ValueError('owner/transport changed during source reset')
                except Exception as error:
                    self.last_outcome = 'OBSERVATION_UNKNOWN'
                    raise ResetUncertain('new BOOT did not preserve the host owner') from error
                self.last_outcome = 'NEW_BOOT_OBSERVED'
                return cap
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.last_outcome = 'UNKNOWN_PENDING'
                raise ResetUncertain('source reset still pending at deadline; retain owner, no retry')
            time.sleep(min(remaining, poll_interval_s))
