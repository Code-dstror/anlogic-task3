"""Interactive debug owner: receive continuously while one worker applies CFG.

This is an explicit r3 debug integration, not a patch to the frozen production
runtime. FPGA PREPARE/COMMIT performs its actual source/RAW/LZ drain handshake.
Normal host STOP alone is never a product-mode transition authorization.
"""
from __future__ import annotations

from collections import OrderedDict, deque
from dataclasses import asdict, dataclass, field
from queue import Empty, Full, Queue
from threading import Event, Lock, RLock, Thread
import time
import uuid

from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import ConfigError
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
from linux.task3_pipeline.product_receiver import JpegProduct, RawProduct
from linux.task3_runtime.session import C2HSession
from .journal import Journal, public_value
from .products import ProductInspector
from .transport import OwnedRecordReader


@dataclass
class CommandResult:
    sequence: int
    operation: str
    done: Event = field(default_factory=Event)
    value: object = None
    error: str | None = None

    def wait(self, timeout_s):
        if not self.done.wait(timeout_s):
            raise TimeoutError('command still in flight; no retry/cancel/reset was inferred')
        if self.error is not None:
            raise RuntimeError(self.error)
        return self.value


@dataclass(frozen=True)
class _TransitionPermit:
    token: str
    proposal_digest: str
    session: int
    old_epoch: int
    new_epoch: int


class _CommitBoundaryBar:
    """Same fd; arm the decoder only after PREPARE succeeds, before COMMIT."""
    def __init__(self, receiver, before_commit):
        self.receiver, self.before_commit = receiver, before_commit
    def read32(self, offset):
        return self.receiver.read32(offset)
    def write32(self, offset, value):
        if offset == p.PCIE_REG_CFG_COMMAND and value == p.PCIE_CFG_COMMAND_COMMIT:
            self.before_commit()
        self.receiver.write32(offset, value)


def _product_mode(extension):
    if isinstance(extension, MonoConfiguration):
        return extension.product_mode
    if extension is not None:
        if extension.enable & p.PCIE_CFG_EXT_FEATURE_HDR:
            return p.PCIE_CFG_V2_MODES_MONO_HDR
        if extension.enable & p.PCIE_CFG_EXT_FEATURE_CFS:
            return p.PCIE_CFG_V2_MODES_MONO_SDR_LZ
    return p.PCIE_CFG_V2_MODES_MONO_SDR


class DebugSession:
    """Own exactly one already-open Receiver; CLI controls receive no fd.

    A native LZ owner is source-bound, including while current mode is SDR. This
    allows one future configuration epoch to be admitted before COMMIT; actual
    APPLIED must match before it is confirmed. Old READY tails keep their owner
    until an observed new boundary, empty old assembly and drained host queue.
    """
    def __init__(self, receiver, *, jpeg_version=3, config_timeout_s,
                 drain_timeout_s, consumers=None, lz_library=None,
                 allow_lab_hdr=False, expected_bdf=None, max_records=200000,
                 event_limit=128, poll_seconds=.01, controls_factory=None,
                 allow_source_reset=False, reset_api=None):
        import math
        for name, value in (('config timeout', config_timeout_s), ('drain timeout', drain_timeout_s),
                            ('poll interval', poll_seconds)):
            if type(value) not in (int, float) or not math.isfinite(value) or value <= 0:
                raise ValueError('explicit positive finite ' + name + ' required')
        if type(allow_lab_hdr) is not bool:
            raise ValueError('allow_lab_hdr must be explicit boolean')
        if type(allow_source_reset) is not bool:
            raise ValueError('allow_source_reset must be explicit boolean')
        self.receiver, self.jpeg_version = receiver, jpeg_version
        self.config_timeout_s, self.drain_timeout_s = config_timeout_s, drain_timeout_s
        self.consumers, self.lz_library = consumers, lz_library
        self.allow_lab_hdr, self.expected_bdf = allow_lab_hdr, expected_bdf
        self.allow_source_reset, self._reset_api = allow_source_reset, reset_api
        self.max_records, self.poll_seconds = max_records, poll_seconds
        self.controls_factory = controls_factory
        self.journal = Journal(limit=event_limit)
        self.state, self.failure, self.ownership_retained = 'NEW', None, True
        self.cold = self.controls = self.inspector = self.reader = None
        self._receive_thread = self._control_thread = None
        self._state_lock, self._inspect_lock = RLock(), RLock()
        self._command_lock = Lock()
        self._observation_lock = Lock()
        self._observed = OrderedDict()
        self._commands = Queue(maxsize=4)
        self._history = deque(maxlen=32)
        self._command_sequence = 0
        self._command_busy = False
        self._closing, self._pause, self._control_stop = Event(), Event(), Event()
        self._stopped, self._receive_done = Event(), Event()
        self._permit = None
        self._epoch_armed = False
        self._active = None
        self._owner_identity = None
        self._finished_products = None
        self._cleanup_errors = []
        self.stop_reason = None
        self._prior_sources = deque(maxlen=8)

    def _fault(self, phase, error):
        with self._state_lock:
            if self.failure is None:
                self.failure = dict(phase=phase, error=f'{type(error).__name__}: {error}'[:512])
                self.journal.record('FAULT', self.failure)
            self.state = 'FAULTED'
            self.ownership_retained = True
        self._control_stop.set()
        self._closing.set()

    def prepare(self):
        if self.state != 'NEW':
            raise RuntimeError('debug owner preparation is single use')
        try:
            identity = self.receiver.owner_identity()
            if self.expected_bdf is not None and identity.bdf != self.expected_bdf:
                raise ValueError('GET_OWNER BDF differs from the explicit debug target')
            self._owner_identity = identity
            self.cold = C2HSession(self.receiver, jpeg_version=self.jpeg_version,
                                   timeout_s=self.config_timeout_s)
            self.cold.prepare()
            self.cold.transactions.bar = _CommitBoundaryBar(self.receiver, self._before_commit)
            factory = self.controls_factory
            if factory is None:
                from .controls import DebugControls
                factory = DebugControls
            self.controls = factory(self.cold.transactions, lut_timeout_s=self.config_timeout_s,
                                    profile='r3', transition_guard=self._guard_transition)
            self._active = self.controls.read_active()
            initial_mode = _product_mode(self._active.extension)
            if initial_mode == p.PCIE_CFG_V2_MODES_MONO_SDR_LZ and self.lz_library is None:
                raise ValueError('initial active LZ mode needs an explicit native library before START')
            if initial_mode == p.PCIE_CFG_V2_MODES_MONO_HDR and not self.allow_lab_hdr:
                raise ValueError('initial active LAB HDR needs explicit acknowledgment before START')
            self.inspector = ProductInspector(expected_jpeg_version=self.jpeg_version,
                lz_session=self._active.session if self.lz_library is not None else None,
                lz_epoch=self._active.mode_epoch if self.lz_library is not None else None,
                lz_library=self.lz_library, max_records=self.max_records,
                max_record_bytes=self.receiver.capacity)
            self.reader = OwnedRecordReader(self.receiver, self.inspector, maximum_batch=4,
                                            record_budget=self.max_records)
            self.journal.record('DISCOVERY', self.controls.discover())
            self.journal.record('INITIAL_ACTIVE', self._active)
            self.state = 'PREPARED'
            return self
        except BaseException as error:
            self._fault('PREPARE', error)
            raise

    def start(self):
        if self.state == 'NEW':
            self.prepare()
        if self.state != 'PREPARED':
            raise RuntimeError('use resume for a normally stopped debug session')
        try:
            self.cold.start()
            self.state = 'RUNNING'
            self._receive_thread = Thread(target=self._receive, name='rk-debug-rx', daemon=True)
            self._control_thread = Thread(target=self._control, name='rk-debug-cfg', daemon=True)
            self._receive_thread.start()
            self._control_thread.start()
            self.journal.record('START', dict(owner=asdict(self._owner_identity)))
            return self
        except BaseException as error:
            self._fault('START', error)
            raise

    def _guard_transition(self, proposal, permit):
        if (permit is not self._permit or not isinstance(permit, _TransitionPermit)
                or permit.proposal_digest != proposal.digest or self.state != 'RUNNING'
                or self._receive_thread is None or not self._receive_thread.is_alive()
                or self._pause.is_set() or self._closing.is_set()
                or permit.session != proposal.baseline.session
                or permit.old_epoch != proposal.baseline.mode_epoch):
            raise ValueError('transition requires this active receiving owner and exact proposal')
        mode = _product_mode(proposal.extension)
        if mode == p.PCIE_CFG_V2_MODES_MONO_HDR and not self.allow_lab_hdr:
            raise ValueError('r3 HDR is a digital LAB source; explicit --allow-lab-hdr is required')
        if mode == p.PCIE_CFG_V2_MODES_MONO_SDR_LZ and self.lz_library is None:
            raise ValueError('LZ mode requires an explicit existing native reassembly library')

    def _before_commit(self):
        permit = self._permit
        if permit is None or self._epoch_armed or self.state != 'RUNNING':
            raise RuntimeError('COMMIT lacks the exact active debug command')
        with self._inspect_lock:
            if self.lz_library is not None:
                self.inspector.authorize_epoch(permit.new_epoch)
        self._epoch_armed = True

    def submit(self, operation, value=None):
        if operation not in ('configure', 'active', 'discover', 'load-lut', 'query-lut'):
            raise ValueError('unknown bounded debug operation')
        with self._command_lock:
            if (self.state != 'RUNNING' or self._pause.is_set() or self._closing.is_set()
                    or self._control_stop.is_set()):
                raise RuntimeError('commands require a live receiving session; resume before configuring')
            self._command_sequence += 1
            result = CommandResult(self._command_sequence, operation)
            try:
                self._commands.put_nowait((result, value))
            except Full as error:
                raise RuntimeError('debug command queue is full') from error
            self._history.append(result)
            return result

    def _apply(self, document):
        proposal = self.controls.propose(document)
        old = proposal.baseline.mode_epoch
        if old == 0xffffffff:
            raise ValueError('CFG epoch exhausted; no implicit wrap/restart is allowed')
        permit = _TransitionPermit(uuid.uuid4().hex, proposal.digest,
                                   proposal.baseline.session, old, old + 1)
        # Validate before allocating the prospective decoder or doing MMIO.
        self._permit = permit
        self._epoch_armed = False
        self._guard_transition(proposal, permit)
        with self._inspect_lock:
            if self.lz_library is not None:
                if len(self.inspector.snapshot()['epochs']) >= 2:
                    raise ValueError('previous epoch still has pending host tails; wait for receiving to drain it')
        self.journal.record('REQUESTED', proposal)
        try:
            applied = self.controls.apply(proposal,
                transition_permit=permit if proposal.requires_transition else None)
            if applied.mode_epoch != permit.new_epoch or applied.session != permit.session:
                raise RuntimeError('actual r3 APPLIED epoch differs; proposed decoder is not confirmed')
            with self._inspect_lock:
                if self.lz_library is not None:
                    self.inspector.confirm_epoch(applied.mode_epoch)
            self._active = self.controls.read_active()
            self.journal.record('APPLIED', applied)
            return applied
        finally:
            self._permit = None
            self._epoch_armed = False

    def _control(self):
        try:
            while not self._control_stop.is_set():
                try:
                    result, value = self._commands.get(timeout=.05)
                except Empty:
                    continue
                with self._command_lock:
                    self._command_busy = True
                try:
                    if result.operation == 'configure':
                        result.value = self._apply(value)
                    elif result.operation == 'active':
                        result.value = self.controls.read_active()
                        self._active = result.value
                    elif result.operation == 'discover':
                        result.value = self.controls.discover()
                    elif result.operation == 'load-lut':
                        result.value = self.controls.load_lut(value)
                    else:
                        result.value = self.controls.query_lut()
                except (ValueError, TypeError, ConfigError) as error:
                    # Proposal/shape rejection happens before writes. A terminal
                    # CFG/LUT client is checked below and is never retried.
                    result.error = f'{type(error).__name__}: {error}'[:512]
                    if (self.controls.snapshot().get('terminal')
                            or getattr(self.cold.transactions, '_terminal', False)):
                        self._fault('CONTROL', error)
                except BaseException as error:
                    result.error = f'{type(error).__name__}: {error}'[:512]
                    self._fault('CONTROL', error)
                finally:
                    self._permit = None
                    with self._command_lock:
                        self._command_busy = False
                    result.done.set()
                    self._commands.task_done()
                    self.journal.record('COMMAND', dict(sequence=result.sequence,
                        operation=result.operation, error=result.error,
                        value=None if result.error else public_value(result.value)))
        except BaseException as error:
            self._fault('CONTROL_WORKER', error)
        finally:
            while True:
                try:
                    result, _ = self._commands.get_nowait()
                except Empty:
                    break
                result.error = 'not executed: debug owner is stopping'
                result.done.set()
                self._commands.task_done()

    def _retire_epochs_at_host_queue_boundary(self):
        if self.lz_library is None or self.receiver.poll(0):
            return
        snapshot = self.inspector.snapshot()['epochs']
        if len(snapshot) < 2:
            return
        older, newer = sorted(map(int, snapshot))
        before, after = snapshot[str(older)], snapshot[str(newer)]
        if (before['pending'] is None and not before['buffered_bytes']
                and after['confirmed'] and after['boundary_seen']):
            self.inspector.retire_epoch(older)
            self.journal.record('OLD_EPOCH_RETIRED', dict(epoch=older, successor=newer,
                proof='R3_CFG_OWNER_DRAIN_PLUS_ORDERED_COMPLETIONS_AND_EMPTY_HOST_QUEUE'))

    def _observe_product(self, event):
        product = event.product
        if isinstance(product, JpegProduct):
            source = product.record.metadata.source if product.record.metadata is not None else None
            key = (None, None) if source is None else (source.session, source.epoch)
            kind, sequence = 'jpeg_complete', product.record.sequence
        elif isinstance(product, RawProduct):
            source = product.frame.identity
            key = source.source_session, source.mode_epoch
            kind, sequence = 'raw_complete', source.capture_sequence
        else:
            return
        with self._observation_lock:
            if key not in self._observed:
                if len(self._observed) == 64:
                    self._observed.popitem(last=False)
                self._observed[key] = dict(source_session=key[0], source_epoch=key[1],
                    jpeg_complete=0, raw_complete=0, last_jpeg_sequence=None, last_raw_sequence=None,
                    last_processing_mode=None, last_quality=None)
            row = self._observed[key]
            row[kind] += 1
            if kind == 'jpeg_complete':
                row['last_jpeg_sequence'] = sequence
                row['last_quality'] = event.summary.get('base_header', {}).get('quality')
                row['last_processing_mode'] = (None if product.record.metadata is None
                                                else product.record.metadata.processing_mode)
            else:
                row['last_raw_sequence'] = sequence

    def _receive(self):
        drain_started = None
        try:
            while self.state != 'FAULTED':
                if self._pause.is_set() and self.state == 'RUNNING':
                    self.receiver.stop()
                    self.state = 'DRAINING'
                    drain_started = time.monotonic()
                if self.state == 'STOPPED':
                    if self._closing.is_set():
                        break
                    time.sleep(min(self.poll_seconds, .05))
                    continue
                # Never hold the parser/epoch lock during a blocking device
                # wait: the CFG thread needs it before COMMIT and after APPLIED.
                self.receiver.poll(self.poll_seconds)
                with self._inspect_lock:
                    events = self.reader.poll_once(0)
                    self._retire_epochs_at_host_queue_boundary()
                for event in events:
                    if isinstance(event, dict):
                        self.journal.record(event['kind'], event)
                    else:
                        self._observe_product(event)
                        if event.product is not None and self.consumers is not None:
                            self.consumers.consume(event)
                        if event.status not in ('OK', 'PARTIAL', 'COMPLETE'):
                            self.journal.record('PRODUCT', dict(kind=event.kind, status=event.status,
                                                                 summary=event.summary))
                if self.consumers is not None:
                    self.consumers.check()
                if self.reader.limit_reached:
                    self.stop_reason = 'EXPLICIT_RECORD_BUDGET_REACHED'
                    self._control_stop.set()
                    self._closing.set()
                if self.state == 'DRAINING':
                    if self.reader.drained():
                        self.state = 'STOPPED'
                        self._stopped.set()
                        self.journal.record('STOPPED', self.reader.snapshot())
                    elif time.monotonic() - drain_started >= self.drain_timeout_s:
                        raise TimeoutError('host transport stop did not drain; owner is retained')
                if self._closing.is_set() and not self._pause.is_set():
                    with self._command_lock:
                        if not self._command_busy:
                            self._pause.set()
        except BaseException as error:
            self._fault('RECEIVE', error)
        finally:
            if self.state == 'FAULTED':
                try:
                    self.receiver.stop()
                except BaseException as error:
                    self._cleanup_errors.append(f'STOP: {type(error).__name__}: {error}'[:512])
            self._receive_done.set()

    def pause(self, timeout_s=None):
        with self._command_lock:
            if self._command_busy or not self._commands.empty():
                raise RuntimeError('finish the current configuration command before STOP')
            if self.state != 'RUNNING':
                raise RuntimeError('normal pause requires RUNNING')
            self._pause.set()
        if not self._stopped.wait(self.drain_timeout_s + .1 if timeout_s is None else timeout_s):
            raise TimeoutError('pause is not confirmed; no close or restart is permitted')
        return self.snapshot()

    def resume(self):
        if self.state != 'STOPPED' or self._closing.is_set() or self.failure is not None:
            raise RuntimeError('resume requires this same normally stopped owner')
        try:
            self.receiver.start()
        except BaseException as error:
            self._fault('RESUME', error)
            raise
        self._stopped.clear()
        self._pause.clear()
        self.state = 'RUNNING'
        self.journal.record('RESUME', dict(source_session=self._active.session,
                                          mode_epoch=self._active.mode_epoch))

    def source_reset(self):
        """Explicit normal source rearm through the optional guarded driver.

        This never reloads the module or changes BME/native transport ownership.
        Missing/disabled extensions are known pre-write rejections. Once issued,
        any uncertain completion retains the same owner and cannot be retried.
        """
        if not self.allow_source_reset:
            raise ValueError('source reset is disabled; explicit reviewed-contract opt-in is required')
        if self.config_timeout_s > 60:
            raise ValueError('source-reset observation requires a CFG timeout of at most60 seconds')
        from .driver_api import DebugDriverAPI, Unsupported, ResetRejected
        with self._command_lock:
            if (self.state != 'STOPPED' or self._closing.is_set() or self.failure is not None
                    or self._command_busy or not self._commands.empty()):
                raise ValueError('source reset requires normal pause and no configuration command')
            try:
                active = self.controls.read_active()
            except BaseException as error:
                if not isinstance(error, ConfigError) or self.controls.snapshot().get('terminal'):
                    self._fault('SOURCE_RESET_PREFLIGHT', error)
                raise
            if _product_mode(active.extension) != p.PCIE_CFG_V2_MODES_MONO_SDR:
                raise ValueError('transition to SDR and observe its product before pausing for source reset')
            with self._inspect_lock:
                try:
                    drained = self.reader.drained()
                except BaseException as error:
                    self._fault('SOURCE_RESET_PREFLIGHT', error)
                    raise
                if not drained:
                    raise ValueError('host results or leases remain')
                before = self.inspector.snapshot()
                if any(item['pending'] is not None or item['buffered_bytes']
                       for item in before['epochs'].values()):
                    raise ValueError('incomplete application RAW remains; no reset was requested')
            api = self._reset_api if self._reset_api is not None else DebugDriverAPI(self.receiver)
            try:
                issued = api.request_source_reset(active.session)
            except (Unsupported, ResetRejected):
                raise  # Driver/API promises these are known pre-write refusals.
            except BaseException as error:
                self._fault('SOURCE_RESET_REQUEST', error)
                raise
            try:
                self.journal.record('SOURCE_RESET_ISSUED', issued)
                observed = api.wait_new_boot(active.session, timeout_s=self.config_timeout_s)
                cold = C2HSession(self.receiver, jpeg_version=self.jpeg_version,
                                  timeout_s=self.config_timeout_s)
                cold.prepare()  # Fresh source BOOT requires a new exact format SELECT.
                cold.transactions.bar = _CommitBoundaryBar(self.receiver, self._before_commit)
                factory = self.controls_factory
                if factory is None:
                    from .controls import DebugControls
                    factory = DebugControls
                controls = factory(cold.transactions, lut_timeout_s=self.config_timeout_s,
                    profile='r3', transition_guard=self._guard_transition)
                after = controls.read_active()
                if after.session == active.session or after.session != observed.observed_source_session:
                    raise RuntimeError('new CFG source session does not match the observed debug reset')
                inspector = ProductInspector(expected_jpeg_version=self.jpeg_version,
                    lz_session=after.session if self.lz_library is not None else None,
                    lz_epoch=after.mode_epoch if self.lz_library is not None else None,
                    lz_library=self.lz_library, max_records=self.max_records,
                    max_record_bytes=self.receiver.capacity)
                with self._inspect_lock:
                    previous = dict(source_session=active.session, active_epoch=active.mode_epoch,
                                    counters=before['counters'], transport_records=self.reader.records)
                    self.inspector.close()
                    self._prior_sources.append(previous)
                    self.inspector = inspector
                    self.reader = OwnedRecordReader(self.receiver, inspector, maximum_batch=4,
                                                    record_budget=self.max_records)
                    self.cold, self.controls, self._active = cold, controls, after
                self.journal.record('SOURCE_RESET_NEW_BOOT', dict(observed=public_value(observed),
                    active=public_value(after), state='STOPPED', automatic_restart=False))
                return self.snapshot()
            except BaseException as error:
                self._fault('SOURCE_RESET_COMPLETION', error)
                raise

    def close(self):
        """Return a retained-owner report on uncertainty; never force completion."""
        if self.state == 'CLOSED':
            return self.snapshot()
        self._control_stop.set()
        if self._control_thread is not None:
            self._control_thread.join(self.config_timeout_s + .1)
            if self._control_thread.is_alive():
                self._fault('CLOSE', TimeoutError('configuration worker still owns a transaction'))
        self._closing.set()
        self._pause.set()
        if self._receive_thread is not None:
            self._receive_thread.join(self.drain_timeout_s + .2)
            if self._receive_thread.is_alive():
                self._fault('CLOSE', TimeoutError('receiving worker still owns the device'))
        if self.failure is not None:
            return self.snapshot()
        if self.state not in ('STOPPED', 'PREPARED'):
            self._fault('CLOSE', RuntimeError('normal stopped state was not established'))
            return self.snapshot()
        try:
            if self.consumers is not None:
                consumers = self.consumers.close(timeout_s=self.drain_timeout_s)
                if not consumers.get('worker_done'):
                    raise RuntimeError('consumer still owns native data/files')
            with self._inspect_lock:
                self._finished_products = self.inspector.finish()
                self.inspector.close()
            self.receiver.close()
            self.state = 'CLOSED'
            self.ownership_retained = False
            return self.snapshot()
        except BaseException as error:
            self._fault('CLOSE', error)
            return self.snapshot()

    def snapshot(self):
        with self._inspect_lock:
            products = self._finished_products if self._finished_products is not None else (
                None if self.inspector is None else self.inspector.snapshot())
        with self._observation_lock:
            observed = [dict(row) for row in self._observed.values()]
        return dict(format='RK_DEBUG_SESSION_V1', state=self.state, failure=self.failure,
            ownership_retained=self.ownership_retained,
            stop_reason=self.stop_reason,
            transport=None if self.reader is None else dict(records=self.reader.records,
                inspected_records=self.reader.inspected_records, budget_discards=self.reader.budget_discards,
                safe_errors=self.reader.safe_errors, copied_bytes=self.reader.copied_bytes, fault=self.reader.fault),
            owner=None if self._owner_identity is None else asdict(self._owner_identity),
            active=None if self._active is None else public_value(self._active), products=products,
            observed_products=observed,
            prior_source_runs=list(self._prior_sources),
            consumers=None if self.consumers is None else self.consumers.snapshot(),
            controls=None if self.controls is None else self.controls.snapshot(),
            commands=[dict(sequence=item.sequence,
                operation=item.operation, done=item.done.is_set(), error=item.error) for item in self._history],
            cleanup_errors=list(self._cleanup_errors), journal=self.journal.snapshot(),
            policy=dict(profile='R3_SOURCE_AUDIT_NOT_A_FIRMWARE_ATTESTATION', allow_lab_hdr=self.allow_lab_hdr,
                allow_source_reset=self.allow_source_reset,
                product_changes='REAL_CFG_ACK_APPLIED_WHILE_RECEIVING_NO_SOFTRESET',
                sensor_capture_age='UNKNOWN', usb_4g='EXCLUDED'))
