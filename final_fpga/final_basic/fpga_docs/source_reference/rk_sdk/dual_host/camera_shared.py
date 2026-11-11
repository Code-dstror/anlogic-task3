"""Dual frontend policy over the unchanged STEREO, CFG1/schema2 and AJPG v4 ABIs."""
from threading import Lock

from linux.stream_diag.records import RecordError, parse_record
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import Configuration, ConfigTransactions, ConfigError
from linux.task3_pipeline.mono_config_v2 import MonoConfiguration
from linux.task3_pipeline.record_selection import select_record

from .dual_records import DualRecordDemux
from .stereo_control import select_cold_mode
from . import stereo_control_v1 as stereo


class AwaitingApplied(RecordError):
    """Retain the owned copy in arrival order until the CFG COMMIT resolves."""


def validate_profile(owner, base, profile):
    owner.capabilities.supports(base)
    if not isinstance(profile,MonoConfiguration) or profile.product_mode not in (
            p.PCIE_CFG_V2_MODES_MONO_SDR,p.PCIE_CFG_V2_MODES_MONO_HDR) or base.mode != p.PCIE_CFG_V2_REQUIRED_BASE_MODE:
        raise ConfigError("R1 requires schema2 SDR or physical HDR with base COLOR")
    owner.validate_extension(profile)
    if profile.product_mode == p.PCIE_CFG_V2_MODES_MONO_HDR and (
            (profile.hdr_ratio,profile.hdr_black_long,profile.hdr_black_short) != (4,50,50)
            or profile.hdr_max_delta_ns >> 32 or not profile.hdr_max_wait_ns or not profile.hdr_max_age_ns):
        raise ConfigError("physical HDR requires DOL2 ratio/black levels, u32 delta and nonzero wait/age")


class SharedStereoReceiver:
    """One cold owner/session, two independent SOURCE and JPEG generation checks."""

    def __init__(self, topology, selection, *, max_record_bytes, cameras=2):
        if cameras==1:
            valid_topology = (topology.capabilities.compiled_profile == p.PCIE_CFG_PROFILE_MONO1920
                              and topology.capabilities.camera_present == 1 and topology.session == selection.session)
        elif cameras==2:
            valid_topology = (topology.mode == stereo.STEREO_MODES_DUAL_JPEG and topology.frame_divisor == 2
                              and topology.jpeg_quality == 75 and selection.session == topology.cfg_session)
        else:
            valid_topology = False
        if (not valid_topology or (selection.version, selection.header_length) !=
                (p.PCIE_RECORD_V4_VERSION, p.PCIE_RECORD_V4_HEADER_LENGTH)):
            raise ConfigError("camera topology and v4 selection receipts must match the same session")
        if type(max_record_bytes) is not int or max_record_bytes < selection.header_length + 4:
            raise ValueError("pass the real DMA record buffer capacity")
        self.session = selection.session
        self.cameras = cameras
        self.max_record_bytes = max_record_bytes
        self.demux = tuple(DualRecordDemux(record_version=selection.version,
                                          source_session=self.session) for _ in range(cameras))
        self._profiles = {0: MonoConfiguration()}
        self._current_epoch = 0
        self._seen = set()
        self._pending = None
        self._faulted = False
        self._lock = Lock()

    @classmethod
    def select_cold(cls, bar, *, timeout_s, poll_interval_s, max_record_bytes):
        """Run before C2H open/ARM, under the existing owner's BAR serialization."""
        topology = select_cold_mode(bar.read32, bar.write32, stereo.STEREO_MODES_DUAL_JPEG,
                                    timeout_s=timeout_s, poll_interval_s=poll_interval_s,
                                    frame_divisor=2, jpeg_quality=75)
        selected = select_record(bar, p.PCIE_RECORD_V4_VERSION, timeout_s=timeout_s,
                                 poll_interval_s=poll_interval_s)
        return cls(topology, selected, max_record_bytes=max_record_bytes)

    def apply(self, owner: ConfigTransactions, base: Configuration, profile: MonoConfiguration):
        """Apply one complete configuration after selecting DUAL, v4 and starting video."""
        caps = owner.capabilities
        if (owner.session != self.session or caps.compiled_profile != (p.PCIE_CFG_PROFILE_DUAL1920
                if self.cameras==2 else p.PCIE_CFG_PROFILE_MONO1920)
                or caps.camera_present != (1<<self.cameras)-1 or not isinstance(profile, MonoConfiguration)):
            raise ConfigError("use the current topology CFG owner and a schema2 profile")
        validate_profile(owner,base,profile)
        with self._lock:
            if self._faulted or self._pending is not None or len(self._profiles) > 1:
                raise ConfigError("session faulted, another CFG pending, or prior mode still draining")
            if self._current_epoch == 0xffffffff:
                raise ConfigError("CFG epoch exhausted; begin a fresh session")
            expected = self._current_epoch + 1
            self._pending = expected
        try:
            prepared = owner.prepare(base, extension=profile)
            if prepared.previous_mode_epoch != self._current_epoch:
                owner.cancel(prepared)
                raise ConfigError("CFG epoch changed outside this receiver owner")
            applied = owner.commit(prepared)
            if ((applied.session, applied.mode_epoch, applied.configuration, applied.extension)
                    != (self.session, expected, base, profile)):
                raise ConfigError("APPLIED differs from expected session, epoch or snapshot")
            with self._lock:
                self._profiles[expected] = profile
                self._current_epoch = expected
                self._seen.clear()
                self._pending = None
            return applied
        except Exception:
            # A timed-out commit may have changed hardware. Never infer rollback.
            with self._lock:
                self._faulted = True
                self._pending = None
            raise

    def accept(self, wire: bytes):
        """Validate one owned complete record before advancing that eye's decoder queue."""
        if len(wire) > self.max_record_bytes:
            raise RecordError("AJPG record exceeds the negotiated DMA buffer")
        owned = bytes(wire)
        record = parse_record(owned, expected_version=p.PCIE_RECORD_V4_VERSION)
        m = record.metadata
        source = None if m is None else m.source
        if (source is None or source.session != self.session or source.camera not in range(self.cameras)
                or (source.kind, source.format) != (p.PCIE_RECORD_V2_SOURCE_PHYSICAL,
                                                     p.PCIE_RECORD_V2_FORMAT_RAW10)
                or (record.width, record.height) != (1920, 1080) or m.processing_member
                or record.s07 is None or record.s07.frame_error):
            raise RecordError("invalid physical dual v4 source, geometry or analysis")
        with self._lock:
            if self._faulted:
                raise ConfigError("resolve the faulted configuration session")
            if source.epoch == self._pending:
                raise AwaitingApplied("hold the copied record pending actual APPLIED")
            profile = self._profiles.get(source.epoch)
            if profile is None:
                raise RecordError("unconfirmed source epoch")
            hdr = profile.product_mode == p.PCIE_CFG_V2_MODES_MONO_HDR
            # Revoked or not-yet-established history yields an identity frame.
            # The requesting epoch is shared; actual restoration is a per-eye/per-frame fact.
            mask = m.schema2_processing_enables
            if (source.epoch == 0 and m.processing_mode == 0):
                mask = 0  # Legacy COLOR BOOT has no schema2 tag until the first real CFG.
            if (mask != profile.processing_enables or record.s07.enabled != profile.processing_enables >> 4
                    or (m.dehaze_applied and not m.dehaze_requested)
                    or (m.record_flags & ~p.PCIE_RECORD_V2_PRODUCT_DEHAZE_FILTERED)
                    != (p.PCIE_RECORD_V2_PRODUCT_HDR_MERGED if hdr else 0)
                    or bool(m.validity_flags & p.PCIE_RECORD_V2_FLAG_HDR_PRODUCT) != hdr
                    or source.role != (p.PCIE_RECORD_V2_ROLE_LONG if hdr else p.PCIE_RECORD_V2_ROLE_SINGLE)
                    or (hdr and (not m.qualified or not m.pair_id or m.job_id != m.pair_id))):
                raise RecordError("record product or processing differs from its confirmed epoch")
            item = self.demux[source.camera]._accept_verified(owned, record)
            if source.epoch == self._current_epoch:
                self._seen.add(source.camera)
                if len(self._seen) == self.cameras and len(self._profiles) > 1:
                    self._profiles = {self._current_epoch: profile}
            return item

    def status(self):
        with self._lock:
            return dict(session=self.session, active_epoch=self._current_epoch, pending_epoch=self._pending,
                        seen_cameras=sorted(self._seen), faulted=self._faulted)
