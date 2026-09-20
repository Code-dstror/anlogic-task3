"""Static and OpenCV verification for the FPGA C2H JPEG board-test fixture."""

from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path

import cv2
import numpy as np

from tests._c2h_jpeg_fixture_helpers import (
    canonical_jpeg_fixture_bytes as _fixture_bytes,
    fixture_macro_value as _macro_value,
    fixture_pattern as _fixture_pattern,
)


ROOT = Path(__file__).resolve().parents[1]
PCIE_DIR = ROOT / "fpga_rtl" / "pcie"
SOURCE = PCIE_DIR / "c2h_test_source.v"
REGISTERS = PCIE_DIR / "pcie_app_regs.v"
TOP = PCIE_DIR / "pcie_c2h_test_top.v"
TRANSPORT_TB = ROOT / "fpga_rtl" / "tb" / "tb_c2h_transport.v"


def _transport_oracle_bytes() -> bytes:
    fixture_length = _macro_value("C2H_TEST_JPEG_FIXTURE_LENGTH")
    expected_beat_count = (fixture_length + 15) // 16
    entries = re.findall(
        r"^\s*6'd(\d+): expected_jpeg_fixture_beat = 128'h([0-9a-fA-F]{32});$",
        TRANSPORT_TB.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    beats: dict[int, bytes] = {}
    for index_text, hex_beat in entries:
        index = int(index_text)
        if index in beats:
            raise AssertionError(f"duplicate JPEG transport oracle beat {index}")
        # A Verilog numeric literal's least-significant byte maps to AXI lane 0.
        beats[index] = int(hex_beat, 16).to_bytes(16, byteorder="little")
    if sorted(beats) != list(range(expected_beat_count)):
        raise AssertionError("JPEG transport oracle beats are not contiguous")
    return b"".join(beats[index] for index in range(expected_beat_count))


def _stream_tuple(mode: int, programmed_length: int, byte_offset: int) -> tuple[bytes, int, bool]:
    """Reference the source's combinational beat semantics at one offset."""
    fixture = _fixture_bytes()
    fixture_pattern = _fixture_pattern()
    length = len(fixture) if mode == fixture_pattern else programmed_length
    remaining = length - byte_offset
    valid_lanes = min(16, remaining)
    if mode == 0:
        data = bytes((byte_offset + lane) & 0xFF for lane in range(16))
    elif mode == 1:
        data = bytes([0xA5] * 16)
    elif mode == 2:
        data = bytes(
            ((byte_offset + lane) & 0xFF)
            ^ (((byte_offset + lane) >> 8) & 0xFF)
            ^ 0x5A
            for lane in range(16)
        )
    elif mode == fixture_pattern:
        data = fixture[byte_offset : byte_offset + 16].ljust(16, b"\0")
    else:
        data = bytes(16)
    return data, (1 << valid_lanes) - 1, remaining <= 16


class C2hJpegFixtureTests(unittest.TestCase):
    def test_fixture_is_contiguous_fixed_length_and_has_jpeg_markers(self) -> None:
        fixture = _fixture_bytes()

        self.assertEqual(len(fixture), _macro_value("C2H_TEST_JPEG_FIXTURE_LENGTH"))
        self.assertEqual(
            hashlib.sha256(fixture).hexdigest(),
            "84a5e930a7ffa4292e1ac70de77a18e58ac25fffd214a4916dd569e8eaafe857",
        )
        self.assertEqual(fixture[:2], b"\xff\xd8")
        self.assertEqual(fixture[-2:], b"\xff\xd9")

    def test_fixture_decodes_with_opencv_and_matches_fixture_metadata(self) -> None:
        fixture = _fixture_bytes()
        decoded = cv2.imdecode(np.frombuffer(fixture, dtype=np.uint8), cv2.IMREAD_UNCHANGED)

        self.assertIsNotNone(decoded)
        assert decoded is not None
        self.assertEqual(
            (decoded.shape[1], decoded.shape[0]),
            (
                _macro_value("C2H_TEST_JPEG_FIXTURE_WIDTH"),
                _macro_value("C2H_TEST_JPEG_FIXTURE_HEIGHT"),
            ),
        )

    def test_fixture_stream_has_exact_length_final_keep_and_stable_stalls(self) -> None:
        fixture = _fixture_bytes()
        fixture_pattern = _fixture_pattern()
        assembled = bytearray()
        byte_offset = 0
        ready_sequence = [False, False, True, False, True, True] * 32
        for ready in ready_sequence:
            before = _stream_tuple(fixture_pattern, 7, byte_offset)
            if not ready:
                self.assertEqual(_stream_tuple(fixture_pattern, 9999, byte_offset), before)
                continue
            data, keep, last = before
            assembled.extend(data[lane] for lane in range(16) if keep & (1 << lane))
            if last:
                break
            byte_offset += 16
        else:
            self.fail("fixture stream did not reach TLAST")

        self.assertEqual(bytes(assembled), fixture)
        self.assertEqual(len(assembled), len(fixture))
        self.assertEqual(_stream_tuple(fixture_pattern, 1, 320)[1], 0x07FF)
        self.assertTrue(_stream_tuple(fixture_pattern, 1, 320)[2])

    def test_transport_oracle_matches_canonical_fixture_in_axi_lane_order(self) -> None:
        fixture = _fixture_bytes()
        oracle = _transport_oracle_bytes()

        self.assertEqual(oracle[: len(fixture)], fixture)
        self.assertEqual(oracle[len(fixture) :], bytes(5))

    def test_legacy_pattern_semantics_are_unchanged(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")

        self.assertIn("PATTERN_INCREMENTING = 2'd0", source)
        self.assertIn("PATTERN_FIXED_A5 = 2'd1", source)
        self.assertIn("PATTERN_XOR = 2'd2", source)
        self.assertIn("byte_position[7:0] ^ byte_position[15:8] ^ 8'h5a", source)
        self.assertEqual(_stream_tuple(0, 300, 0)[0], bytes(range(16)))
        self.assertEqual(_stream_tuple(0, 300, 256)[0], bytes(range(16)))
        self.assertEqual(_stream_tuple(1, 300, 32)[0], bytes([0xA5] * 16))
        expected_xor = bytes(
            ((0x120 + lane) & 0xFF) ^ (((0x120 + lane) >> 8) & 0xFF) ^ 0x5A
            for lane in range(16)
        )
        self.assertEqual(_stream_tuple(2, 400, 0x120)[0], expected_xor)
        self.assertEqual(_stream_tuple(0, 17, 16)[1:], (0x0001, True))
        self.assertEqual(_stream_tuple(1, 16, 0)[1:], (0xFFFF, True))

    def test_rtl_maps_mode_three_and_register_defaults_to_shared_constant(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        registers = REGISTERS.read_text(encoding="utf-8")

        self.assertIn("PATTERN_JPEG_FIXTURE = `C2H_TEST_PATTERN_JPEG_FIXTURE", source)
        self.assertIn("payload_length <= `C2H_TEST_JPEG_FIXTURE_LENGTH", source)
        self.assertIn("assign o_meta_payload_length = payload_length", source)
        self.assertIn("C2H_TEST_JPEG_FIXTURE_WIDTH : 16'd1920", source)
        self.assertIn("C2H_TEST_JPEG_FIXTURE_HEIGHT : 16'd1080", source)
        self.assertIn("assign o_meta_compression = 8'd1", source)
        self.assertIn("test_length_o <= `C2H_TEST_JPEG_FIXTURE_LENGTH", registers)
        self.assertIn("test_pattern_o <= `C2H_TEST_PATTERN_JPEG_FIXTURE", registers)

    def test_top_level_jpeg_trigger_bypasses_only_the_programmed_length_gate(self) -> None:
        top = TOP.read_text(encoding="utf-8")

        self.assertIn('`include "c2h_test_fixture.vh"', top)
        self.assertIn(
            "(test_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE) ||", top
        )
        self.assertIn("(test_length != 32'd0)", top)
        self.assertIn("(test_length <= `PCIE_MAX_PAYLOAD)", top)

    def test_rtl_transport_testbench_checks_actual_jpeg_lanes_and_stalls(self) -> None:
        testbench = TRANSPORT_TB.read_text(encoding="utf-8")

        self.assertIn("task run_jpeg_fixture_case", testbench)
        self.assertIn("payload_length = 32'd17", testbench)
        self.assertIn("function [127:0] expected_jpeg_fixture_beat", testbench)
        self.assertIn("case (fixture_beat_index)", testbench)
        self.assertIn("axis_tdata !== expected_jpeg_fixture_beat(beat_index - 4)", testbench)
        self.assertIn("JPEG fixture metadata payload length mismatch", testbench)
        self.assertIn("JPEG fixture final TKEEP mismatch", testbench)
        self.assertIn("JPEG fixture final unused lanes mismatch", testbench)
        self.assertIn("source TDATA changed during backpressure", testbench)


if __name__ == "__main__":
    unittest.main()
