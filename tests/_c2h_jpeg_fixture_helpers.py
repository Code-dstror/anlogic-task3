"""Private readers for the canonical FPGA C2H JPEG fixture.

This module is deliberately not a ``test_*.py`` module: fixture consumers
share these readers without creating another unittest test target.
"""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_CONSTANTS = ROOT / "fpga_rtl" / "include" / "c2h_test_fixture.vh"


def fixture_macro_value(name: str) -> int:
    """Read one numeric fixture macro from the FPGA source of truth."""

    match = re.search(
        rf"^`define {name} (?:32|16)'d(\d+)$",
        FIXTURE_CONSTANTS.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"missing numeric macro {name}")
    return int(match.group(1))


def canonical_jpeg_fixture_bytes() -> bytes:
    """Read the canonical JPEG bytes embedded in the FPGA fixture header."""

    fixture_constants = FIXTURE_CONSTANTS.read_text(encoding="utf-8")
    match = re.search(
        r"^`define\s+C2H_TEST_JPEG_FIXTURE_DATA\s+(\d+)'h([^\r\n]*)$",
        fixture_constants,
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError("embedded JPEG fixture literal is missing")
    return _parse_verilog_hex_literal(match.group(1), match.group(2))


def _parse_verilog_hex_literal(declared_width: str, hex_content: str) -> bytes:
    """Validate and decode one decimal-width Verilog hexadecimal literal."""

    if re.fullmatch(r"\d+", declared_width) is None:
        raise AssertionError("JPEG fixture literal width must be decimal")
    width = int(declared_width)
    if width <= 0:
        raise AssertionError("JPEG fixture literal width must be positive")
    if width % 8 != 0:
        raise AssertionError("JPEG fixture literal width must be divisible by eight")

    hex_digits = "".join(hex_content.split())
    if re.fullmatch(r"[0-9a-fA-F]+", hex_digits) is None:
        raise AssertionError("JPEG fixture literal contains invalid hexadecimal content")
    expected_hex_digits = width // 4
    if len(hex_digits) != expected_hex_digits:
        raise AssertionError(
            "JPEG fixture literal width does not match its hexadecimal digit count"
        )
    return bytes.fromhex(hex_digits)


def fixture_pattern() -> int:
    """Read and validate the dedicated two-bit JPEG fixture pattern selector."""

    definitions = re.findall(
        r"^`define\s+C2H_TEST_PATTERN_JPEG_FIXTURE\s+(.+?)\s*$",
        FIXTURE_CONSTANTS.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if not definitions:
        raise AssertionError("missing C2H_TEST_PATTERN_JPEG_FIXTURE macro")
    if len(definitions) != 1:
        raise AssertionError("duplicate C2H_TEST_PATTERN_JPEG_FIXTURE macros")
    match = re.fullmatch(r"2'd(\d+)", definitions[0])
    if match is None:
        raise AssertionError("C2H_TEST_PATTERN_JPEG_FIXTURE must be a 2-bit decimal macro")
    pattern = int(match.group(1))
    if pattern > 0b11:
        raise AssertionError("C2H_TEST_PATTERN_JPEG_FIXTURE exceeds the 2-bit range")
    return pattern
