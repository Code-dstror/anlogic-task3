"""Tests for pure-memory PCIe v1 record parsing."""

from __future__ import annotations

from dataclasses import FrozenInstanceError, replace
import unittest
from unittest.mock import patch

from linux.task3_pipeline import PcieV1RecordParser, ValidationError
from linux.task3_pipeline import pcie_protocol_v1 as protocol


class PcieV1RecordParserTests(unittest.TestCase):
    def setUp(self) -> None:
        self.parser = PcieV1RecordParser()

    @staticmethod
    def make_record(payload: bytes = b"payload", **overrides: object) -> bytes:
        fields: dict[str, object] = dict.fromkeys(protocol.FRAME_HEADER_FIELD_NAMES, 0)
        fields.update(protocol.FRAME_HEADER_EXPECTED_VALUES)
        fields.update(
            {
                "frame_sequence": 0x10203040,
                "payload_length": len(payload),
                "width": 640,
                "height": 480,
                "pixel_format": 0x12,
                "compression": 0x34,
                "quality": 0x56,
                "timestamp_ns": 0x0102030405060708,
                "status": 0x11223344,
                "error_code": 0x55667788,
                "slot_id": 0x99AA,
                "payload_crc32": 0xBBCCDDEE,
            }
        )
        fields.update(overrides)
        header = protocol.FRAME_HEADER_STRUCT.pack(
            *(fields[name] for name in protocol.FRAME_HEADER_FIELD_NAMES)
        )
        return header + payload

    def assert_validation_error(
        self, record: object, expected_code: str
    ) -> ValidationError:
        with self.assertRaises(ValidationError) as captured:
            self.parser.parse(record)  # type: ignore[arg-type]
        error = captured.exception
        self.assertEqual(error.stage, "transport_record_validation")
        self.assertEqual(error.code, expected_code)
        return error

    def test_parses_every_wire_field_and_payload(self) -> None:
        payload = b"\x00\xffopaque-payload"
        parsed = self.parser.parse(self.make_record(payload))

        self.assertEqual(parsed.frame_magic, protocol.FRAME_HEADER_EXPECTED_VALUES["frame_magic"])
        self.assertEqual(
            parsed.protocol_version,
            protocol.FRAME_HEADER_EXPECTED_VALUES["protocol_version"],
        )
        self.assertEqual(parsed.header_length, protocol.HEADER_LENGTH)
        self.assertEqual(parsed.frame_sequence, 0x10203040)
        self.assertEqual(parsed.payload_length, len(payload))
        self.assertEqual(parsed.width, 640)
        self.assertEqual(parsed.height, 480)
        self.assertEqual(parsed.pixel_format, 0x12)
        self.assertEqual(parsed.compression, 0x34)
        self.assertEqual(parsed.quality, 0x56)
        self.assertEqual(parsed.flags, protocol.FRAME_HEADER_EXPECTED_VALUES["flags"])
        self.assertEqual(parsed.timestamp_ns, 0x0102030405060708)
        self.assertEqual(parsed.status, 0x11223344)
        self.assertEqual(parsed.error_code, 0x55667788)
        self.assertEqual(parsed.slot_id, 0x99AA)
        self.assertEqual(parsed.reserved0, protocol.FRAME_HEADER_EXPECTED_VALUES["reserved0"])
        self.assertEqual(parsed.payload_crc32, 0xBBCCDDEE)
        self.assertEqual(parsed.reserved1, protocol.FRAME_HEADER_EXPECTED_VALUES["reserved1"])
        self.assertEqual(parsed.payload, payload)
        self.assertIsInstance(parsed.payload, bytes)

    def test_accepts_bytes_bytearray_and_memoryview(self) -> None:
        record = self.make_record()
        for source in (record, bytearray(record), memoryview(record)):
            with self.subTest(source_type=type(source).__name__):
                self.assertEqual(self.parser.parse(source).payload, b"payload")

    def test_mutating_bytearray_or_memoryview_source_after_parse_cannot_change_record(self) -> None:
        for use_memoryview in (False, True):
            with self.subTest(use_memoryview=use_memoryview):
                source = bytearray(self.make_record(b"immutable"))
                parsed = self.parser.parse(memoryview(source) if use_memoryview else source)
                source[:] = b"\x00" * len(source)

                self.assertEqual(parsed.payload, b"immutable")
                self.assertEqual(parsed.frame_sequence, 0x10203040)
                with self.assertRaises(FrozenInstanceError):
                    parsed.payload = b"changed"  # type: ignore[misc]

    def test_released_memoryview_has_stable_buffer_access_error(self) -> None:
        source = memoryview(self.make_record())
        source.release()

        error = self.assert_validation_error(source, "transport_record_buffer_access")
        self.assertIsInstance(error.cause, ValueError)
        with self.assertRaises(ValueError):
            _ = source.nbytes

    def test_snapshot_holds_view_during_copy_and_uses_only_snapshot_afterward(self) -> None:
        source = bytearray(self.make_record(b"snapshot"))
        views: list[object] = []

        class ResizeCheckingView:
            def __init__(self, buffer: bytearray) -> None:
                self._buffer = buffer
                self._view = memoryview(buffer)
                self.copy_called = False
                self.resize_blocked = False
                self.released = False

            @property
            def nbytes(self) -> int:
                return self._view.nbytes

            def tobytes(self) -> bytes:
                self.copy_called = True
                try:
                    self._buffer.extend(b"unexpected-trailing-bytes")
                except BufferError:
                    self.resize_blocked = True
                else:
                    self._buffer[:] = self._buffer[: -len(b"unexpected-trailing-bytes")]
                    raise AssertionError("bytearray resize was not blocked during snapshot")
                snapshot = self._view.tobytes()
                self._buffer[:] = b"\x00" * len(self._buffer)
                return snapshot

            def release(self) -> None:
                self.released = True
                self._view.release()

        def create_view(record: bytes | bytearray | memoryview) -> ResizeCheckingView:
            self.assertIs(record, source)
            view = ResizeCheckingView(source)
            views.append(view)
            return view

        with patch.object(PcieV1RecordParser, "_create_view", side_effect=create_view):
            parsed = self.parser.parse(source)

        self.assertEqual(len(views), 1)
        view = views[0]
        self.assertIsInstance(view, ResizeCheckingView)
        self.assertTrue(view.copy_called)
        self.assertTrue(view.resize_blocked)
        self.assertTrue(view.released)
        self.assertEqual(parsed.payload, b"snapshot")
        self.assertEqual(source, bytes(len(source)))

    def test_record_rejects_mutable_payload_or_invalid_wire_integer(self) -> None:
        parsed = self.parser.parse(self.make_record())
        with self.assertRaises(TypeError):
            replace(parsed, payload=bytearray(parsed.payload))
        with self.assertRaises(TypeError):
            replace(parsed, width=True)

    def test_non_bytes_like_input_has_stable_error(self) -> None:
        for source in (None, "record", 1, object()):
            with self.subTest(source=source):
                self.assert_validation_error(source, "record_not_bytes_like")

    def test_short_header_has_stable_error_and_does_not_modify_input(self) -> None:
        source = bytearray(protocol.HEADER_LENGTH - 1)
        original = bytes(source)

        self.assert_validation_error(source, "record_header_truncated")
        self.assertEqual(source, original)

    def test_identity_field_failures_have_distinct_stable_codes(self) -> None:
        invalid_values = {
            "frame_magic": 0,
            "protocol_version": 2,
            "header_length": protocol.HEADER_LENGTH - 1,
            "flags": 0,
        }
        for name, value in invalid_values.items():
            with self.subTest(name=name):
                source = bytearray(self.make_record(**{name: value}))
                original = bytes(source)
                self.assert_validation_error(source, f"record_invalid_{name}")
                self.assertEqual(source, original)

    def test_reserved_field_failures_have_distinct_stable_codes(self) -> None:
        invalid_values = {
            "reserved0": 1,
            "reserved1": b"\x01"
            + bytes(len(protocol.FRAME_HEADER_EXPECTED_VALUES["reserved1"]) - 1),
        }
        for name, value in invalid_values.items():
            with self.subTest(name=name):
                source = bytearray(self.make_record(**{name: value}))
                original = bytes(source)
                self.assert_validation_error(source, f"record_invalid_{name}")
                self.assertEqual(source, original)

    def test_payload_length_zero_and_above_max_are_rejected_before_length_match(self) -> None:
        self.assert_validation_error(
            self.make_record(b"", payload_length=0), "record_payload_length_zero"
        )
        self.assert_validation_error(
            self.make_record(b"", payload_length=protocol.MAX_PAYLOAD + 1),
            "record_payload_length_exceeds_max",
        )

    def test_payload_length_mismatch_and_trailing_bytes_are_rejected(self) -> None:
        self.assert_validation_error(
            self.make_record(b"ab", payload_length=3), "record_payload_truncated"
        )
        self.assert_validation_error(
            self.make_record(b"abc", payload_length=2), "record_trailing_bytes"
        )
        self.assert_validation_error(
            self.make_record(b"xy", payload_length=2) + b"trailer",
            "record_trailing_bytes",
        )

    def test_total_input_limit_is_checked_before_copying(self) -> None:
        oversized = b"\x00" * (protocol.HEADER_LENGTH + protocol.MAX_PAYLOAD + 1)
        self.assert_validation_error(oversized, "record_too_large")

    def test_opaque_wire_values_are_preserved_without_interpretation(self) -> None:
        parsed = self.parser.parse(
            self.make_record(
                b"not-a-jpeg",
                timestamp_ns=0xFEDCBA9876543210,
                status=0xDEADBEEF,
                error_code=0xA1B2C3D4,
                slot_id=0xE5F6,
                payload_crc32=0xCAFEBABE,
            )
        )

        self.assertEqual(parsed.timestamp_ns, 0xFEDCBA9876543210)
        self.assertEqual(parsed.status, 0xDEADBEEF)
        self.assertEqual(parsed.error_code, 0xA1B2C3D4)
        self.assertEqual(parsed.slot_id, 0xE5F6)
        self.assertEqual(parsed.payload_crc32, 0xCAFEBABE)
        self.assertEqual(parsed.payload, b"not-a-jpeg")

    def test_no_partial_record_is_published_on_failure(self) -> None:
        source = bytearray(self.make_record(b"x", payload_length=2))
        original = bytes(source)

        self.assert_validation_error(source, "record_payload_truncated")
        self.assertEqual(source, original)
