"""Regression coverage for private canonical C2H JPEG fixture readers."""

from __future__ import annotations

import unittest

from tests._c2h_jpeg_fixture_helpers import _parse_verilog_hex_literal


class C2hJpegFixtureHelperTests(unittest.TestCase):
    def test_literal_parser_accepts_other_width_and_rejects_mismatched_digits(self) -> None:
        self.assertEqual(_parse_verilog_hex_literal("16", "ab cd"), b"\xab\xcd")

        with self.assertRaisesRegex(AssertionError, "does not match"):
            _parse_verilog_hex_literal("16", "abc")


if __name__ == "__main__":
    unittest.main()
