"""R1 integration for the existing RK debug shell's sole C2H/CFG owner."""
from collections import deque
from dataclasses import asdict

from linux.rk_debug.catalog import BASE_FLAGS, PROCESSING_ENABLES
from linux.rk_debug.controls import DebugControls
from linux.rk_debug.session import DebugSession
from linux.rk_debug.transport import OwnedRecordReader
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import ConfigError
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration

from .camera_shared import AwaitingApplied, SharedStereoReceiver, validate_profile
from .stereo_control import select_cold_mode
from . import stereo_control_v1 as stereo


FILTERS = dict(gray=p.PCIE_CFG_V2_ENABLES_GRAY, gaussian=p.PCIE_CFG_V2_ENABLES_GAUSSIAN_IMAGE,
               he=p.PCIE_CFG_V2_ENABLES_HISTOGRAM, dehaze=p.PCIE_CFG_V2_ENABLES_DEHAZE,
               lane=p.PCIE_CFG_V2_ENABLES_MULTISCALE | p.PCIE_CFG_V2_ENABLES_LANE)


def mode_document(text, topology, hdr_policy=None):
    words = text.lower().split()
    if not words or words[0] not in ('sdr','hdr') or any(name not in FILTERS for name in words[1:]):
        raise ValueError('mode sdr|hdr [gray] [gaussian] [he] [dehaze] [lane]; no filters selects color')
    if topology == 'dual' and 'lane' in words:
        raise ValueError('lane requires mono topology')
    mask = 0
    for name in words[1:]:
        mask |= FILTERS[name]
    hdr = words[0] == 'hdr'
    if hdr:
        from linux.rk_debug.cli import load_document
        if hdr_policy is None:
            raise ValueError('mode hdr requires --shared-hdr-policy or use configure @complete-config.json')
        # A complete existing schema2 configuration supplies the owner's HDR
        # recipe, including all motion/timer fields. The current command owns
        # the processing mask and retains the current base quality.
        document = load_document(hdr_policy)
        extension = document.get('extension',{})
        required = {key for key in asdict(MonoConfiguration()) if key.startswith('hdr_')}
        if document.get('schema') != 2 or extension.get('product_mode') != 2 or not required <= extension.keys():
            raise ValueError('the owner HDR document must contain all the schema2 HDR policy fields')
        policy = {name:extension[name] for name in required}
    profile = MonoConfiguration(product_mode=p.PCIE_CFG_V2_MODES_MONO_HDR if hdr else p.PCIE_CFG_V2_MODES_MONO_SDR,
                                processing_enables=mask, **(policy if hdr else {}))
    return dict(schema=2, base=dict(mode=p.PCIE_CFG_MODE_COLOR), extension=asdict(profile))


def _parameter(path, minimum, maximum, unit, default, **details):
    row = dict(path=path, access='writable', minimum=minimum, maximum=maximum,
               unit=unit, default=default, **details)
    if minimum == maximum:
        row.update(access='fixed', value=minimum)
    return row


def _parameter_catalog(capabilities, mono):
    """Describe the online JPEG controls of this physical camera profile."""
    base_features = capabilities.features
    quality_default = p.PCIE_CFG_DEFAULT_QUALITY
    if base_features & p.PCIE_CFG_FEATURE_DYNAMIC_QUALITY:
        quality_minimum, quality_maximum = p.PCIE_CFG_MINIMUM_QUALITY, p.PCIE_CFG_MAXIMUM_QUALITY
    else:
        quality_minimum = quality_maximum = quality_default
    budget_available = bool(base_features & p.PCIE_CFG_FEATURE_FRAME_BUDGET)
    restart_available = bool(base_features & p.PCIE_CFG_FEATURE_RESTART)
    base = [
        _parameter('base.mode', p.PCIE_CFG_MODE_COLOR, p.PCIE_CFG_MODE_COLOR, 'enum',
                   p.PCIE_CFG_MODE_COLOR, symbols={'COLOR': p.PCIE_CFG_MODE_COLOR}),
        _parameter('base.quality', quality_minimum, quality_maximum, 'quality', quality_default),
        _parameter('base.flags', 0, int(budget_available), 'bitmask', 0,
                   symbols=dict(BASE_FLAGS) if budget_available else {},
                   depends_on='ADAPTIVE_QUALITY requires nonzero frame_budget'),
        _parameter('base.min_quality', p.PCIE_CFG_MINIMUM_QUALITY, quality_maximum, 'quality',
                   p.PCIE_CFG_MINIMUM_QUALITY, depends_on='min_quality <= quality; used by adaptive quality'),
        _parameter('base.frame_budget', 0, p.MAX_PAYLOAD if budget_available else 0, 'bytes', 0,
                   note='Feedback target for completed JPEG lengths'),
        _parameter('base.restart_mcus', 0, 0xffff if restart_available else 0, 'MCU', 0,
                   note='0 disables restart markers'),
    ]
    modes = {'MONO_SDR': p.PCIE_CFG_V2_MODES_MONO_SDR, 'MONO_HDR': p.PCIE_CFG_V2_MODES_MONO_HDR}
    modes = {name: value for name, value in modes.items() if mono.modes & (1 << value)}
    supported_enables = mono.enables
    if capabilities.camera_present == 3:
        supported_enables &= ~(p.PCIE_CFG_V2_ENABLES_MULTISCALE | p.PCIE_CFG_V2_ENABLES_LANE)
    if not supported_enables & p.PCIE_CFG_V2_ENABLES_MULTISCALE:
        supported_enables &= ~p.PCIE_CFG_V2_ENABLES_LANE
    enables = {name: bit for name, bit in PROCESSING_ENABLES.items() if supported_enables & bit}
    schema2 = [
        _parameter('extension.schema', p.PCIE_CFG_V2_SCHEMA, p.PCIE_CFG_V2_SCHEMA, 'enum', p.PCIE_CFG_V2_SCHEMA),
        _parameter('extension.product_mode', min(modes.values(), default=0), max(modes.values(), default=0),
                   'enum', p.PCIE_CFG_V2_MODES_MONO_SDR, symbols=modes),
        _parameter('extension.processing_enables', 0, sum(enables.values()), 'bitmask', 0,
                   symbols=enables, depends_on='LANE requires MULTISCALE'),
    ]
    if 'MONO_HDR' in modes:
        hdr_fields = [
            ('hdr_ratio', 4, 4, 'log2'),
            ('hdr_black_long', 50, 50, 'RAW10 code'),
            ('hdr_black_short', 50, 50, 'RAW10 code'),
            ('hdr_motion_base', 0, 0x3fff, 'RAW14 code'),
            ('hdr_motion_shift', 0, 15, 'bit'),
            ('hdr_qualification', p.PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED,
             p.PCIE_CFG_EXT_HDR_QUALIFICATION_REQUIRED, 'bitmask'),
            ('hdr_max_delta_ns', 0, 0xffffffff, 'ns'),
            ('hdr_max_wait_ns', 1, 0xffffffff, 'ns'),
            ('hdr_max_age_ns', 1, 0xffffffff, 'ns'),
        ]
        for name, minimum, maximum, unit in hdr_fields:
            default = minimum if minimum == maximum else None
            schema2.append(_parameter(f'extension.{name}', minimum, maximum, unit, default,
                                      disabled_value=0, depends_on='Physical DOL2 HDR'))
    schema2.append(_parameter('extension.dehaze_lut_generation', 0, int('DEHAZE' in enables), 'enum', 0,
                              disabled_value=0, depends_on='DEHAZE enable',
                              note='0 and 1 select the built-in estimator'))
    return dict(base=base, schemas={'2': schema2}, constraints={
        'dual_d2_quality': quality_default, 'raw_online_cfg': False, 'host_lut_upload': False,
    })


class SharedControls(DebugControls):
    def _validate(self, base, extension):
        if extension is None:
            self.transactions.capabilities.supports(base)  # actual pre-CFG legacy BOOT
        else:
            validate_profile(self.transactions,base,extension)

    def discover(self):
        tx = self.transactions
        base = tx.capabilities
        mono = tx.mono_capabilities()
        return dict(profile='camera_shared_r1', base=asdict(base), schema2=asdict(mono),
                    active=self.read_active().as_dict(), parameters=_parameter_catalog(base, mono))


class SharedRecordReader(OwnedRecordReader):
    """Release each DMA lease first; publish new-epoch copies in order after APPLIED."""
    def __init__(self, receiver, inspector, profiles, **options):
        super().__init__(receiver, self, **options)
        self.products, self.profiles = inspector, profiles
        self.held = deque()
        self.limit = receiver.snapshot().slots
        self.batch = min(self.maximum_batch,self.limit)
        self.last = {}

    def _accept(self, wire, kwargs):
        item = self.profiles.accept(wire)
        m = item.record.metadata
        self.last[item.camera] = dict(session=item.session, epoch=item.epoch, sequence=item.sequence,
            requested=m.schema2_processing_enables, dehaze_applied=m.dehaze_applied,
            hdr_merged=bool(m.record_flags & p.PCIE_RECORD_V2_PRODUCT_HDR_MERGED),
            lane_points=item.record.s07.f23.count if item.record.s07.f23 is not None else None)
        return self.products.feed(wire, **kwargs)

    def feed(self, wire, **kwargs):
        if not self.held:
            try:
                return self._accept(wire, kwargs)
            except AwaitingApplied:
                pass
        if len(self.held) >= self.limit:
            raise ConfigError('unconfirmed record copies exceed the native slot count')
        self.held.append((wire, kwargs))
        return dict(kind='CFG_AWAITING_APPLIED')

    def poll_once(self, timeout_s):
        replay = []
        while self.held:
            wire, kwargs = self.held[0]
            try:
                replay.append(self._accept(wire, kwargs))
            except AwaitingApplied:
                break
            self.held.popleft()
        # A new-epoch SOURCE has reached DMA while the RK control worker is
        # still reading its APPLIED receipt. Keep the copy bound and leave
        # further completed slots with the existing native owner until then.
        self.maximum_batch=min(self.batch,self.limit-len(self.held))
        if not self.maximum_batch:
            return tuple(replay)
        return tuple(replay) + super().poll_once(timeout_s)

    def drained(self):
        return not self.held and super().drained()


class SharedDebugSession(DebugSession):
    def __init__(self, receiver, *, topology, **kwargs):
        super().__init__(receiver, controls_factory=SharedControls, **kwargs)
        self.cameras = {'mono':1,'dual':2}[topology]
        self.profiles = None

    def prepare(self):
        if self.state != 'NEW':
            raise RuntimeError('camera topology is cold-selected once per session')
        try:
            info = self.receiver.snapshot()
            if (self.receiver.owner_identity().bdf != self.expected_bdf or not info.transport_drained
                    or info.submitted or info.completed or self.receiver.leased_count or self.receiver.poll(0)):
                raise ConfigError('camera selection requires the requested fresh stopped C2H owner')
            if (self.receiver.read32(p.PCIE_REG_RECORD_SELECTED_VERSION),
                    self.receiver.read32(p.PCIE_REG_RECORD_SELECTED_HEADER_LENGTH)) != (
                    p.PCIE_RECORD_V2_VERSION,p.PCIE_RECORD_V2_HEADER_LENGTH):
                raise ConfigError('cold R1 must expose the published v2 BOOT selector before topology and v4')
            if self.cameras == 2:
                topology = select_cold_mode(self.receiver.read32,self.receiver.write32,stereo.STEREO_MODES_DUAL_JPEG,
                    frame_divisor=2,jpeg_quality=75,timeout_s=self.config_timeout_s,poll_interval_s=self.poll_seconds)
            else:
                # The released N2 kernel authorizes DUAL=1 and N=2 writes
                # only. MONO already owns the cold boot and needs no writes.
                read = self.receiver.read32
                if (read(p.PCIE_REG_CFG_COMPILED_PROFILE),read(p.PCIE_REG_CFG_CAMERA_PRESENT),
                        read(p.PCIE_REG_CFG_STATUS),read(p.PCIE_REG_CFG_MODE_EPOCH),
                        read(p.PCIE_REG_CFG_ACTIVE_MODE),read(p.PCIE_REG_CFG_ACTIVE_QUALITY)) != (
                        p.PCIE_CFG_PROFILE_MONO1920,1,p.PCIE_CFG_STATUS_SESSION_READY,0,p.PCIE_CFG_MODE_COLOR,75):
                    raise ConfigError('physical MONO requires actual CAM0 COLOR/Q75 BOOT')
            super().prepare()  # The original owner checks BOOT, selects v4 and obtains the current CFG capabilities.
            self.profiles = SharedStereoReceiver(topology if self.cameras==2 else self.cold.transactions,
                                                 self.cold.selection,max_record_bytes=self.receiver.capacity,
                                                 cameras=self.cameras)
            if self._active.mode_epoch or self._active.session != self.profiles.session:
                raise ConfigError('expected the cold session and BOOT epoch')
            caps = self.cold.transactions.capabilities
            if (caps.compiled_profile,caps.camera_present,caps.max_width,caps.max_height) != (
                    p.PCIE_CFG_PROFILE_DUAL1920 if self.cameras==2 else p.PCIE_CFG_PROFILE_MONO1920,
                    (1<<self.cameras)-1,1920,1080):
                raise ConfigError('CFG discovery differs from the selected camera topology')
            self.cold.transactions.bar = self.receiver  # profiles.apply owns pending/confirmed epochs for JPEG.
            self.reader = SharedRecordReader(self.receiver,self.inspector,self.profiles,
                maximum_batch=self.reader.maximum_batch,record_budget=self.max_records)
            return self
        except BaseException as exc:
            self._fault('SHARED_PREPARE',exc)
            raise

    def _apply(self, document):
        proposal = self.controls.propose(document)
        if not isinstance(proposal.extension, MonoConfiguration):
            raise ConfigError('mode switching uses schema2')
        self.journal.record('REQUESTED', proposal)
        try:
            applied = self.profiles.apply(self.cold.transactions,proposal.configuration,proposal.extension)
        except Exception as exc:
            if self.profiles.status()['faulted']:
                self._fault('CFG',exc)
            raise
        try:
            self._active = self.controls.read_active()
            if (self._active.session,self._active.mode_epoch,self._active.configuration,self._active.extension) != (
                    applied.session,applied.mode_epoch,applied.configuration,applied.extension):
                raise ConfigError('active snapshot differs after APPLIED')
        except Exception as exc:
            self._fault('CFG_READBACK',exc)
            raise
        self.journal.record('APPLIED', applied)
        return applied

    def submit(self, operation, value=None):
        if operation in ('load-lut','query-lut'):
            raise ValueError('R1 dehaze uses the built-in FPGA estimator')
        return super().submit(operation,value)

    def snapshot(self):
        result = super().snapshot()
        if isinstance(self.reader,SharedRecordReader):
            with self._inspect_lock:
                result['camera_mode'] = dict(**self.profiles.status(),last_by_camera=dict(self.reader.last))
        return result
