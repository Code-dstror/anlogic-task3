"""Offline control-owner boundary and strict complete-record routing tests."""
from dataclasses import replace
from unittest import TestCase, main
from unittest.mock import Mock

from dual_host.camera_shared import AwaitingApplied, SharedStereoReceiver
from dual_host.stereo_control import StereoSelection
from linux.stream_diag.records import RecordError
from linux.task3_pipeline import pcie_protocol_v1 as p
from linux.task3_pipeline.config_transaction import (
    AppliedConfiguration, ConfigCapabilities, ConfigError, Configuration, PreparedConfiguration)
from linux.task3_pipeline.mono_config_v2 import MonoCapabilities, MonoConfiguration
from linux.task3_pipeline.record_selection import RecordSelection


def wire(eye, epoch, seq, *, mask=0, hdr=False, qualified=True, wrong_pair=False, haze_applied=False):
    # Structurally valid baseline-JPEG envelope for packet parsing, no decoder claim.
    jpeg = bytes.fromhex("ffd8 ffc0 000b 08 0438 0780 01 01 11 00 ffda 0008 01 01 00 00 3f 00 11 ffd9")
    header = dict(zip(p.FRAME_HEADER_FIELD_NAMES, p.FRAME_HEADER_STRUCT.unpack(bytes(p.FRAME_HEADER_SIZE))))
    header.update(p.FRAME_HEADER_EXPECTED_VALUES)
    header.update(protocol_version=4, header_length=2112, frame_sequence=seq, payload_length=len(jpeg),
                  width=1920, height=1080, compression=1, quality=75, slot_id=3*eye)
    v2 = p.RECORD_V2_EXTENSION_STRUCT
    meta = dict(zip(p.RECORD_V2_EXTENSION_FIELD_NAMES, v2.unpack(bytes(v2.size))))
    meta.update(p.RECORD_V2_EXTENSION_EXPECTED_VALUES)
    flags = p.PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY
    if hdr:
        flags |= p.PCIE_RECORD_V2_FLAG_HDR_PRODUCT | p.PCIE_RECORD_V2_FLAG_PAIR | p.PCIE_RECORD_V2_FLAG_JOB
        if qualified:
            flags |= p.PCIE_RECORD_V2_FLAG_QUALIFIED
    meta.update(source_camera=eye, source_session=7, source_epoch=epoch, source_sequence=seq,
                validity_flags=flags, jpeg_session=20+eye, jpeg_generation=seq,
                source_kind=p.PCIE_RECORD_V2_SOURCE_PHYSICAL, source_format=p.PCIE_RECORD_V2_FORMAT_RAW10,
                exposure_role=p.PCIE_RECORD_V2_ROLE_LONG if hdr else p.PCIE_RECORD_V2_ROLE_SINGLE,
                record_flags=((p.PCIE_RECORD_V2_PRODUCT_HDR_MERGED if hdr else 0) |
                              (p.PCIE_RECORD_V2_PRODUCT_DEHAZE_FILTERED if haze_applied else 0)),
                pair_id=seq if hdr else 0, job_id=seq+int(wrong_pair) if hdr else 0,
                processing_mode=p.PCIE_RECORD_V2_MODE_SCHEMA2_TAG | mask)
    if epoch==0:
        meta["processing_mode"]=0  # Actual legacy COLOR BOOT before a schema2 commit.
    ext = bytearray(p.PCIE_RECORD_V4_HEADER_LENGTH-p.FRAME_HEADER_SIZE)
    ext[:v2.size] = v2.pack(*(meta[n] for n in p.RECORD_V2_EXTENSION_FIELD_NAMES))
    for field, value, size in (("MAGIC", p.PCIE_RECORD_V4_SPARSE_MAGIC, 4),
                               ("SCHEMA", p.PCIE_RECORD_V4_SPARSE_SCHEMA, 1),
                               ("POINT_BYTES", p.PCIE_RECORD_V4_POINT_BYTES, 1),
                               ("ROI_BEGIN", p.PCIE_RECORD_V4_ROI_BEGIN, 2),
                               ("ROI_END", p.PCIE_RECORD_V4_ROI_END, 2)):
        start = getattr(p, "PCIE_RECORD_V4_OFFSET_"+field)
        ext[start:start+size] = value.to_bytes(size, "little")
    if mask&48:
        ext[p.PCIE_RECORD_V4_OFFSET_ENABLED]=ext[p.PCIE_RECORD_V4_OFFSET_PRESENT]=mask>>4
        offset=p.PCIE_RECORD_V4_OFFSET_F22
        ext[offset:offset+66]=(1<<523).to_bytes(66,'little')  # F22 successful terminal.
        if mask&32:
            ext[p.PCIE_RECORD_V4_OFFSET_LANE_STATUS]=p.PCIE_RECORD_V4_STATUS_NO_CANDIDATES
    return p.FRAME_HEADER_STRUCT.pack(*(header[n] for n in p.FRAME_HEADER_FIELD_NAMES)) + ext + jpeg


class SharedStereoTests(TestCase):
    def setUp(self):
        self.rx = SharedStereoReceiver(StereoSelection(1, 7, 0, 2, 75), RecordSelection(4, 2112, 7),
                                       max_record_bytes=4194304)
        self.base = Configuration()
        self.owner = Mock(session=7)
        self.owner.capabilities = ConfigCapabilities(p.PCIE_CFG_FEATURE_FRAME_APPLIED, 2, 3, 1920, 1080)
        self.owner.validate_extension.side_effect = lambda ext: ext.validate(
            MonoCapabilities(5, 15), camera_present=3, width=1920, height=1080)

    def apply(self, profile, epoch, callback=None):
        prepared = PreparedConfiguration(7, epoch, epoch-1, self.base, profile)
        self.owner.prepare.return_value = prepared
        def commit(handle):
            self.assertEqual(handle, prepared)
            if callback:
                callback()
            return AppliedConfiguration(7, epoch, epoch, 0, 1, self.base, profile)
        self.owner.commit.side_effect = commit
        self.rx.apply(self.owner, self.base, profile)

    def test_independent_epochs_and_hdr_validation(self):
        self.rx.accept(wire(0, 0, 1))
        self.rx.accept(wire(1, 0, 1))
        hdr = MonoConfiguration(product_mode=2, hdr_ratio=4, hdr_qualification=15,
                                hdr_black_long=50, hdr_black_short=50, processing_enables=13,
                                hdr_max_wait_ns=100_000_000,hdr_max_age_ns=1_000_000_000)
        self.apply(hdr, 1, lambda: self.assertRaises(AwaitingApplied, self.rx.accept,
                                                     wire(0, 1, 2, mask=13, hdr=True)))
        with self.assertRaises(RecordError):
            self.rx.accept(wire(0, 1, 2, mask=5, hdr=True))
        self.rx.accept(wire(0, 1, 2, mask=13, hdr=True))
        self.rx.accept(wire(1, 0, 2))  # old eye1 record after first eye0 HDR
        for bad in (wire(1, 1, 3, mask=13), wire(1, 1, 3, mask=13, hdr=True, qualified=False),
                    wire(1, 1, 3, mask=13, hdr=True, wrong_pair=True)):
            with self.assertRaises(RecordError):
                self.rx.accept(bad)
        self.rx.accept(wire(1, 1, 3, mask=13, hdr=True))
        with self.assertRaises(RecordError):
            self.rx.accept(wire(1, 1, 3, mask=13, hdr=True))
        with self.assertRaises(RecordError):
            self.rx.accept(wire(1, 0, 4))
        self.apply(MonoConfiguration(processing_enables=8), 2)
        self.rx.accept(wire(0, 2, 4, mask=8))
        self.rx.accept(wire(1, 2, 4, mask=8))

    def test_cold_and_cfg_guards(self):
        with self.assertRaises(ConfigError):
            self.rx.apply(self.owner, self.base, MonoConfiguration(processing_enables=48))
        self.owner.prepare.assert_not_called()
        self.owner.capabilities = replace(self.owner.capabilities, camera_present=1)
        with self.assertRaises(ConfigError):
            self.rx.apply(self.owner, self.base, MonoConfiguration())
        with self.assertRaises(RecordError):
            self.rx.accept(wire(1, 77, 1))

    def test_timeout_requires_recovery(self):
        self.owner.prepare.side_effect = TimeoutError
        with self.assertRaises(TimeoutError):
            self.rx.apply(self.owner, self.base, MonoConfiguration(processing_enables=1))
        with self.assertRaises(ConfigError):
            self.rx.accept(wire(0, 0, 1))

    def test_dehaze_per_eye_actual_use_and_capability(self):
        with self.assertRaises(RecordError):
            self.rx.accept(wire(0, 0, 1, haze_applied=True))
        self.apply(MonoConfiguration(processing_enables=2 | 8), 1)
        for eye in (0, 1):
            first = self.rx.accept(wire(eye, 1, 1, mask=10))
            self.assertTrue(first.record.metadata.dehaze_requested)
            self.assertFalse(first.record.metadata.dehaze_applied)
        next0 = self.rx.accept(wire(0, 1, 2, mask=10, haze_applied=True))
        next1 = self.rx.accept(wire(1, 1, 2, mask=10))
        self.assertTrue(next0.record.metadata.dehaze_applied)
        self.assertFalse(next1.record.metadata.dehaze_applied)
        hdr = MonoConfiguration(product_mode=2, processing_enables=2, hdr_ratio=4,
                                hdr_qualification=15, hdr_black_long=50, hdr_black_short=50,
                                hdr_max_wait_ns=100_000_000,hdr_max_age_ns=1_000_000_000,
                                dehaze_lut_generation=1)
        self.apply(hdr, 2)
        self.rx.accept(wire(0, 2, 3, mask=2, hdr=True))
        applied = self.rx.accept(wire(0, 2, 4, mask=2, hdr=True, haze_applied=True))
        self.assertTrue(applied.record.metadata.dehaze_applied)
        for eye_mask in (1, 3):
            for selector in (0, 1):
                profile = MonoConfiguration(processing_enables=2, dehaze_lut_generation=selector)
                profile.validate(MonoCapabilities(5, 15), width=1920, height=1080,
                                 camera_present=eye_mask)
                with self.assertRaises(ConfigError):
                    profile.validate(MonoCapabilities(5, 13), width=1920, height=1080,
                                     camera_present=eye_mask)
            for profile in (MonoConfiguration(processing_enables=2, dehaze_lut_generation=2),
                            MonoConfiguration(dehaze_lut_generation=1)):
                with self.assertRaises(ConfigError):
                    profile.validate(MonoCapabilities(5, 15), width=1920, height=1080,
                                     camera_present=eye_mask)


if __name__ == "__main__":
    main()
