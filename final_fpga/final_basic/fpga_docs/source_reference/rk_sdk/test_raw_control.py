"""Cold RAW selection and N2 policy regression with synthetic ioctl only."""

import errno
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from dual_host import pcie_protocol_v1 as p
from dual_host import stereo_control_v1 as stereo
from dual_host.stereo_control import StereoControlError
from linux.dma_c2h_candidate import receiver
from linux.stream_diag.records import RecordError, parse_record
from raw_control import RAW1080_RECORD_BYTES, select_cold_raw
from raw_driver import prepare
from raw_video import parse_raw_video
import raw_video_constants as raw


REQUEST = raw.PCIE_RAW_VIDEO_REQUEST_PRODUCT
ACTIVE = raw.PCIE_RAW_VIDEO_ACTIVE_PRODUCT


class ColdIo:
    """Exercise the published Receiver's real preflight and ioctl packing."""

    def __init__(self):
        self.regs = {
            p.PCIE_REG_DEVICE_MAGIC: p.DEVICE_MAGIC,
            p.PCIE_REG_PROTOCOL_VERSION: p.PROTOCOL_VERSION,
            p.PCIE_REG_STEREO_MAGIC: stereo.STEREO_MAGIC,
            p.PCIE_REG_STEREO_ABI_VERSION: stereo.STEREO_ABI_VERSION,
            p.PCIE_REG_STEREO_CAPABILITIES: 0xff000203,
            p.PCIE_REG_STEREO_REQUEST_DIVISOR: 2,
            p.PCIE_REG_STEREO_ACTIVE_DIVISOR: 2,
            p.PCIE_REG_CFG_MAGIC: p.PCIE_CFG_MAGIC,
            p.PCIE_REG_CFG_ABI_VERSION: p.PCIE_CFG_ABI_VERSION,
            p.PCIE_REG_CFG_SESSION: 17,
            p.PCIE_REG_CFG_ACTIVE_SESSION: 17,
            p.PCIE_REG_CFG_STATUS: p.PCIE_CFG_STATUS_SESSION_READY,
            p.PCIE_REG_CFG_ACTIVE_QUALITY: p.PCIE_CFG_DEFAULT_QUALITY,
            p.PCIE_REG_STATUS: (p.PCIE_STATUS_LINK_UP | p.PCIE_STATUS_USER_RESET_RELEASED
                                | p.PCIE_STATUS_SESSION_REARM_READY),
            p.PCIE_REG_RECORD_SELECTED_VERSION: 1,
            REQUEST: 0, ACTIVE: 0,
        }
        self.writes = []
        self.product_ack = True
        self.request_echo = True
        self.has_raw = True

    def ioctl(self, command, arg):
        if command != receiver.LEGACY:
            raise AssertionError("expected only the existing owner BAR ioctl")
        count, reserved = struct.unpack_from("=II", arg)
        assert count == 1 and reserved == 0
        offset, value, write, reserved = struct.unpack_from("=4I", arg, 8)
        assert reserved == 0
        if offset in (REQUEST, ACTIVE) and not self.has_raw:
            raise OSError(errno.EIO, "BAR product offset unsupported")
        if not write:
            struct.pack_into("=I", arg, 12, self.regs.get(offset, 0))
            return
        required = {p.PCIE_REG_STEREO_REQUEST_MODE: 1, p.PCIE_REG_STEREO_REQUEST_DIVISOR: 2,
                    p.PCIE_REG_STEREO_COMMAND: 1}
        if offset != REQUEST and required.get(offset) != value:
            raise PermissionError("outside the published N2 value guard")
        self.writes.append((offset, value))
        if offset != REQUEST or self.request_echo:
            self.regs[offset] = value
        if offset == p.PCIE_REG_STEREO_COMMAND:
            mode = self.regs.get(p.PCIE_REG_STEREO_REQUEST_MODE, 0)
            self.regs[p.PCIE_REG_STEREO_ACTIVE_MODE] = mode
            self.regs[p.PCIE_REG_STEREO_ACTIVE_DIVISOR] = self.regs[p.PCIE_REG_STEREO_REQUEST_DIVISOR]
            self.regs[p.PCIE_REG_STEREO_STATUS] = (1 << stereo.STEREO_STATUS_BITS_DONE) | (
                mode << stereo.STEREO_STATUS_BITS_ACTIVE_MODE)
            if self.product_ack:
                self.regs[ACTIVE] = self.regs[REQUEST]


class RawControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.n2, cls.raw_sources, python_policy = prepare.derive_sources()
        cls.policy = {}
        exec(compile(python_policy, "c2h_legacy_policy.py", "exec"), cls.policy)

    def setUp(self):
        self.io = ColdIo()
        self.bar = object.__new__(receiver.Receiver)
        self.bar._io = self.io
        self.bar._closed = False
        self.bar._poisoned = False

    def select(self, cameras=2, capacity=4 * 1024 * 1024):
        with patch.multiple(receiver, READABLE=self.policy["READABLE"], WRITABLE=self.policy["WRITABLE"]):
            return select_cold_raw(self.bar, cameras=cameras, max_record_bytes=capacity,
                                   timeout_s=0.1, poll_interval_s=0.001)

    def test_mono_uses_boot_topology_on_n2(self):
        selection = self.select(1)
        self.assertEqual((selection.cameras, selection.session, selection.mode_epoch), (1, 17, 0))
        self.assertEqual(self.io.writes, [(REQUEST, 1), (p.PCIE_REG_STEREO_COMMAND, 1)])

    def test_dual_n2_applies_topology_and_product_before_arm(self):
        selection = self.select(2)
        self.assertEqual((selection.topology.mode, selection.topology.frame_divisor), (1, 2))
        self.assertEqual(self.io.writes, [(p.PCIE_REG_STEREO_REQUEST_MODE, 1),
                         (p.PCIE_REG_STEREO_REQUEST_DIVISOR, 2), (REQUEST, 1),
                         (p.PCIE_REG_STEREO_COMMAND, 1)])
        self.assertEqual(self.io.regs[p.PCIE_REG_RECORD_SELECTED_VERSION], 1)

    def test_reject_hot_armed_or_locked(self):
        for offset, value in (
            (p.PCIE_REG_CONTROL, p.PCIE_CONTROL_APP_ENABLE),
            (p.PCIE_REG_STATUS, p.PCIE_STATUS_C2H_RUNNING),
            (p.PCIE_REG_STATUS, p.PCIE_STATUS_SESSION_ARMED),
            (p.PCIE_REG_STEREO_STATUS, 1 << stereo.STEREO_STATUS_BITS_LOCKED),
        ):
            with self.subTest(offset=offset, value=value), patch.dict(self.io.regs):
                self.io.regs[offset] = self.io.regs.get(offset, 0) | value
                with self.assertRaises(StereoControlError):
                    self.select()
                self.assertEqual(self.io.writes, [])

    def test_reject_unsupported_product_before_writes(self):
        self.io.has_raw = False
        with self.assertRaises(OSError):
            self.select()
        self.assertEqual(self.io.writes, [])

    def test_reject_hdr_and_small_dma_buffer(self):
        with self.assertRaises(ValueError):
            self.select(capacity=RAW1080_RECORD_BYTES - 1)
        self.io.regs[p.PCIE_REG_CFG_EXT_ACTIVE_BASE] = p.PCIE_CFG_V2_SCHEMA | (2 << 8)
        with self.assertRaisesRegex(StereoControlError, "plain SDR"):
            self.select()
        self.assertEqual(self.io.writes, [])

    def test_wrong_request_echo_blocks_apply(self):
        self.io.request_echo = False
        with self.assertRaisesRegex(StereoControlError, "REQUEST_PRODUCT"):
            self.select()
        self.assertNotIn((p.PCIE_REG_STEREO_COMMAND, 1), self.io.writes)

    def test_apply_done_without_raw_active_is_rejected(self):
        self.io.product_ack = False
        with self.assertRaisesRegex(StereoControlError, "ACTIVE_PRODUCT"):
            self.select()

    def test_legacy_ajpg_rejects_valid_raw_magic(self):
        payload_bytes = RAW1080_RECORD_BYTES - raw.PCIE_RAW_VIDEO_HEADER_BYTES
        header = struct.pack("<IHHIHHIII4BQQ16s", raw.PCIE_RAW_VIDEO_MAGIC, raw.PCIE_RAW_VIDEO_VERSION,
                             raw.PCIE_RAW_VIDEO_HEADER_BYTES, payload_bytes, 1920, 1080,
                             1, 17, 0, 0, raw.PCIE_RAW_VIDEO_FORMAT_RAW10, 0, 0, 0, 1, bytes(16))
        record = header + bytes(payload_bytes)
        self.assertEqual(parse_raw_video(record).source_session, 17)
        for version in (1, 4):
            with self.assertRaisesRegex(RecordError, "invalid AJPG frame_magic"):
                parse_record(record, expected_version=version)

    def test_policy_diff_and_published_preflight(self):
        self.assertEqual({name for name, content in self.n2.items() if content != self.raw_sources[name]},
                         {"ph1a_c2h.c", "c2h_legacy_policy.h"})
        original = {}
        exec(compile((prepare.REPO / prepare.PUBLISHED_POLICY).read_bytes(), "n2_policy.py", "exec"), original)
        self.assertEqual(self.policy["READABLE"], original["READABLE"] | {REQUEST, ACTIVE})
        self.assertEqual(self.policy["WRITABLE"], original["WRITABLE"] | {REQUEST})
        with patch.multiple(receiver, READABLE=original["READABLE"], WRITABLE=original["WRITABLE"]):
            with self.assertRaises(PermissionError):
                self.bar.write32(REQUEST, 1)
        with patch.multiple(receiver, READABLE=self.policy["READABLE"], WRITABLE=self.policy["WRITABLE"]):
            with self.assertRaises(ValueError):
                self.bar.write32(REQUEST + 1, 1)
            with self.assertRaises(PermissionError):
                self.bar.write32(ACTIVE, 1)
        self.assertEqual(self.io.writes, [])

    def test_compile_actual_kernel_guard_on_host(self):
        cc = os.environ.get("RK_RAW_TEST_CC")
        if not cc:
            self.skipTest("set RK_RAW_TEST_CC to a host C compiler to execute the kernel preflight unit")
        source = self.raw_sources["ph1a_c2h.c"].decode()
        start = source.index("\t\tfor (i = 0; i < legacy.count; ++i) {\n")
        end = source.index("\t\t/* Same exclusive fd and mutex", start)
        fixture = Path(__file__).resolve().parent / "raw_driver/guard_test.c"
        temp_parent = Path(__file__).resolve().parents[1] / "tmp/rk_raw_control"
        temp_parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temp_parent) as work:
            path = Path(work)
            (path / "c2h_legacy_policy.h").write_bytes(self.raw_sources["c2h_legacy_policy.h"])
            (path / "kernel_preflight.inc").write_text(source[start:end], encoding="ascii")
            exe = path / "guard_test.exe"
            subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(path),
                            str(fixture), "-o", str(exe)], check=True, cwd=path, timeout=30)
            subprocess.run([str(exe)], check=True, cwd=path, timeout=10)


if __name__ == "__main__":
    unittest.main()
