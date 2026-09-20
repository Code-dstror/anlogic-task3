"""Tests for mapping validated PCIe v1 records to common encoded frames."""

from __future__ import annotations

import unittest

from linux.task3_pipeline import (
    PcieV1RecordParser,
    ValidationError,
    map_pcie_v1_record_to_encoded_frame,
)
from linux.task3_pipeline import pcie_protocol_v1 as protocol


class PcieV1RecordMapperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.parser = PcieV1RecordParser()

    @staticmethod
    def make_record(payload: bytes = b"payload", **overrides: object) -> bytes:
        fields: dict[str, object] = dict.fromkeys(protocol.FRAME_HEADER_FIELD_NAMES, 0)
        fields.update(protocol.FRAME_HEADER_EXPECTED_VALUES)
        fields.update(
            {
                "frame_sequence": 91,
                "payload_length": len(payload),
                "width": 640,
                "height": 480,
                "pixel_format": 0x12,
                "compression": 0x34,
                "quality": 0x56,
                "timestamp_ns": 0x0102030405060708,
                "status": 0x11223344,
                "error_code": 0,
                "slot_id": 0x99AA,
                "payload_crc32": 0xBBCCDDEE,
            }
        )
        fields.update(overrides)
        return protocol.FRAME_HEADER_STRUCT.pack(
            *(fields[name] for name in protocol.FRAME_HEADER_FIELD_NAMES)
        ) + payload

    def parse_record(self, payload: bytes = b"payload", **overrides: object):
        return self.parser.parse(self.make_record(payload, **overrides))

    def assert_mapping_error(self, expected_code: str, **arguments: object) -> ValidationError:
        record = arguments.pop("record", self.parse_record())
        with self.assertRaises(ValidationError) as captured:
            map_pcie_v1_record_to_encoded_frame(
                record,  # type: ignore[arg-type]
                ingest_id=arguments.pop("ingest_id", 7),  # type: ignore[arg-type]
                received_monotonic_ns=arguments.pop("received_monotonic_ns", 11),  # type: ignore[arg-type]
                source_name=arguments.pop("source_name", "pcie-test"),  # type: ignore[arg-type]
            )
        self.assertEqual(arguments, {})
        error = captured.exception
        self.assertEqual(error.stage, "transport_record_mapping")
        self.assertEqual(error.code, expected_code)
        return error

    def test_maps_wire_and_local_fields_without_conflating_ids(self) -> None:
        record = self.parse_record(b"opaque-payload")
        frame = map_pcie_v1_record_to_encoded_frame(
            record,
            ingest_id=7,
            received_monotonic_ns=123456,
            source_name="pcie-test",
        )
        metadata = frame.metadata

        self.assertEqual(metadata.ingest_id, 7)
        self.assertEqual(metadata.wire_sequence, 91)
        self.assertNotEqual(metadata.ingest_id, metadata.wire_sequence)
        self.assertEqual(metadata.source_name, "pcie-test")
        self.assertEqual(metadata.received_monotonic_ns, 123456)
        self.assertEqual(frame.acquired_monotonic_ns, 123456)
        self.assertEqual(metadata.source_timestamp, 0x0102030405060708)
        self.assertIsNone(metadata.timestamp_domain)
        self.assertEqual(metadata.payload_length, len(b"opaque-payload"))
        self.assertEqual(metadata.protocol_version, record.protocol_version)
        self.assertEqual(metadata.declared_width, 640)
        self.assertEqual(metadata.declared_height, 480)
        self.assertEqual(frame.payload, record.payload)

    def test_zero_wire_dimensions_become_absent_declared_dimensions(self) -> None:
        cases = (
            (0, 480, None, 480),
            (640, 0, 640, None),
            (0, 0, None, None),
        )
        for width, height, expected_width, expected_height in cases:
            with self.subTest(width=width, height=height):
                record = self.parse_record(width=width, height=height)
                frame = map_pcie_v1_record_to_encoded_frame(
                    record,
                    ingest_id=0,
                    received_monotonic_ns=0,
                    source_name="pcie-test",
                )

                self.assertEqual(frame.metadata.declared_width, expected_width)
                self.assertEqual(frame.metadata.declared_height, expected_height)

    def test_opaque_wire_values_and_unverified_crc_are_preserved(self) -> None:
        record = self.parse_record(
            compression=1,
            pixel_format=0xAB,
            quality=0xCD,
            status=0xDEADBEEF,
            payload_crc32=0xCAFEBABE,
            timestamp_ns=0,
        )
        frame = map_pcie_v1_record_to_encoded_frame(
            record,
            ingest_id=1,
            received_monotonic_ns=2,
            source_name="pcie-test",
        )

        self.assertIsNone(frame.metadata.encoding)
        self.assertEqual(frame.metadata.source_timestamp, 0)
        self.assertIsNone(frame.metadata.timestamp_domain)
        self.assertEqual(
            frame.metadata.integrity,
            {
                "pcie_v1_payload_crc32_declared": 0xCAFEBABE,
                "pcie_v1_payload_crc32_verified": False,
            },
        )
        self.assertEqual(
            frame.metadata.extensions,
            {
                "pcie_v1_compression": 1,
                "pcie_v1_pixel_format": 0xAB,
                "pcie_v1_quality": 0xCD,
                "pcie_v1_status": 0xDEADBEEF,
                "pcie_v1_error_code": 0,
            },
        )

    def test_slot_id_does_not_leak_to_common_metadata(self) -> None:
        record = self.parse_record(slot_id=0x1234)
        frame = map_pcie_v1_record_to_encoded_frame(
            record,
            ingest_id=1,
            received_monotonic_ns=2,
            source_name="pcie-test",
        )

        self.assertEqual(record.slot_id, 0x1234)
        self.assertFalse(hasattr(frame.metadata, "slot_id"))
        self.assertFalse(any("slot" in key for key in frame.metadata.integrity))
        self.assertFalse(any("slot" in key for key in frame.metadata.extensions))

    def test_nonzero_error_code_is_rejected_without_changing_record(self) -> None:
        record = self.parse_record(error_code=5)
        original_payload = record.payload
        original_slot_id = record.slot_id

        error = self.assert_mapping_error("record_error_code_nonzero", record=record)

        self.assertIn("error_code", error.message)
        self.assertEqual(record.payload, original_payload)
        self.assertEqual(record.slot_id, original_slot_id)

    def test_invalid_caller_arguments_have_stable_codes(self) -> None:
        cases = (
            ("invalid_ingest_id", {"ingest_id": True}),
            ("invalid_ingest_id", {"ingest_id": -1}),
            ("invalid_ingest_id", {"ingest_id": "7"}),
            ("invalid_received_monotonic_ns", {"received_monotonic_ns": True}),
            ("invalid_received_monotonic_ns", {"received_monotonic_ns": -1}),
            ("invalid_received_monotonic_ns", {"received_monotonic_ns": "11"}),
            ("invalid_source_name", {"source_name": ""}),
            ("invalid_source_name", {"source_name": None}),
            ("invalid_source_name", {"source_name": False}),
        )
        for expected_code, arguments in cases:
            with self.subTest(arguments=arguments):
                self.assert_mapping_error(expected_code, **arguments)

    def test_non_record_input_has_a_stable_error(self) -> None:
        self.assert_mapping_error("invalid_record", record=object())
