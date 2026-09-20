"""Pure-memory compatibility coverage for the canonical FPGA JPEG fixture.

This proves only that the canonical fixture is compatible with the Linux
in-memory PCIe v1 parsing, mapping, JPEG validation, and OpenCV decoding
chain. It does not prove that an RTL testbench ran, or that SGDMA/DMA,
completion/read boundaries, slot lifetimes, board hardware, or RK3576 have
been validated.
"""

from __future__ import annotations

import unittest

from linux.task3_pipeline import (
    JpegPayloadValidator,
    OpenCvJpegDecoder,
    PcieV1RecordParser,
    map_pcie_v1_record_to_encoded_frame,
)
from linux.task3_pipeline.pcie_protocol_v1 import (
    FRAME_HEADER_EXPECTED_VALUES,
    FRAME_HEADER_FIELD_NAMES,
    FRAME_HEADER_STRUCT,
)
from tests._c2h_jpeg_fixture_helpers import (
    canonical_jpeg_fixture_bytes,
    fixture_macro_value,
)


class PcieV1FixturePipelineIntegrationTests(unittest.TestCase):
    """Exercise one complete PCIe v1 record built from the FPGA fixture."""

    _FRAME_SEQUENCE = 0x10203040
    _INGEST_ID = 7
    _RECEIVED_MONOTONIC_NS = 123456789

    @staticmethod
    def _mode_three_record(
        payload: bytes, payload_length: int, width: int, height: int
    ) -> bytes:
        """Build the current c2h_test_source mode-3 metadata using generated layout."""

        fields: dict[str, object] = dict.fromkeys(FRAME_HEADER_FIELD_NAMES, 0)
        fields.update(FRAME_HEADER_EXPECTED_VALUES)
        fields.update(
            {
                "frame_sequence": PcieV1FixturePipelineIntegrationTests._FRAME_SEQUENCE,
                "payload_length": payload_length,
                "width": width,
                "height": height,
                "pixel_format": 1,
                "compression": 1,
                "quality": 75,
                "timestamp_ns": 0,
                "status": 0,
                "error_code": 0,
                "slot_id": 0,
                "payload_crc32": 0,
            }
        )
        return FRAME_HEADER_STRUCT.pack(
            *(fields[name] for name in FRAME_HEADER_FIELD_NAMES)
        ) + payload

    def test_canonical_fixture_flows_through_pcie_v1_and_jpeg_pipeline(self) -> None:
        payload = canonical_jpeg_fixture_bytes()
        fixture_length = fixture_macro_value("C2H_TEST_JPEG_FIXTURE_LENGTH")
        fixture_width = fixture_macro_value("C2H_TEST_JPEG_FIXTURE_WIDTH")
        fixture_height = fixture_macro_value("C2H_TEST_JPEG_FIXTURE_HEIGHT")
        self.assertEqual(len(payload), fixture_length)

        parsed = PcieV1RecordParser().parse(
            self._mode_three_record(
                payload, fixture_length, fixture_width, fixture_height
            )
        )

        self.assertEqual(parsed.payload, payload)
        self.assertEqual(parsed.payload_length, fixture_length)
        self.assertEqual(
            parsed.protocol_version, FRAME_HEADER_EXPECTED_VALUES["protocol_version"]
        )
        self.assertEqual((parsed.width, parsed.height), (fixture_width, fixture_height))

        frame = map_pcie_v1_record_to_encoded_frame(
            parsed,
            ingest_id=self._INGEST_ID,
            received_monotonic_ns=self._RECEIVED_MONOTONIC_NS,
            source_name="pcie-c2h-fixture",
        )
        metadata = frame.metadata

        self.assertEqual(frame.payload, payload)
        self.assertEqual(metadata.ingest_id, self._INGEST_ID)
        self.assertEqual(metadata.wire_sequence, self._FRAME_SEQUENCE)
        self.assertNotEqual(metadata.ingest_id, metadata.wire_sequence)
        self.assertEqual(metadata.payload_length, fixture_length)
        self.assertEqual(metadata.protocol_version, parsed.protocol_version)
        self.assertEqual(
            (metadata.declared_width, metadata.declared_height),
            (fixture_width, fixture_height),
        )
        self.assertIsNone(metadata.encoding)
        self.assertEqual(
            metadata.extensions,
            {
                "pcie_v1_compression": parsed.compression,
                "pcie_v1_pixel_format": parsed.pixel_format,
                "pcie_v1_quality": parsed.quality,
                "pcie_v1_status": parsed.status,
                "pcie_v1_error_code": 0,
            },
        )
        self.assertEqual(
            metadata.integrity,
            {
                "pcie_v1_payload_crc32_declared": 0,
                "pcie_v1_payload_crc32_verified": False,
            },
        )
        self.assertEqual(metadata.source_timestamp, 0)
        self.assertIsNone(metadata.timestamp_domain)
        self.assertFalse(hasattr(metadata, "slot_id"))
        self.assertFalse(any("slot_id" in key for key in metadata.integrity))
        self.assertFalse(any("slot_id" in key for key in metadata.extensions))
        self.assertIsNone(metadata.frame_id)

        validated = JpegPayloadValidator(fixture_length).validate(frame)
        self.assertIs(validated, frame)
        decoded = OpenCvJpegDecoder().decode(validated)

        self.assertEqual((decoded.width, decoded.height), (fixture_width, fixture_height))
        self.assertEqual(decoded.pixel_format, "bgr24")
        self.assertEqual(decoded.row_stride, fixture_width * 3)
        self.assertEqual(len(decoded.pixels), fixture_width * fixture_height * 3)
        self.assertIs(decoded.metadata, metadata)


if __name__ == "__main__":
    unittest.main()
