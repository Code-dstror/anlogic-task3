"""Tests for the generated PCIe v1 header layout constants."""

from __future__ import annotations

import copy
import json
import unittest

from linux.task3_pipeline import pcie_protocol_v1 as protocol
from tools.generate_pcie_protocol import (
    C_OUT,
    PYTHON_OUT,
    SOURCE,
    VERILOG_OUT,
    generate_c,
    generate_python,
    generate_verilog,
    validate_frame_header,
    validate_protocol,
)


class PcieProtocolLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = json.loads(SOURCE.read_text(encoding="utf-8"))

    def test_json_layout_exactly_covers_all_64_bytes(self) -> None:
        fields = validate_protocol(self.data)
        covered = [
            byte
            for field in fields
            for byte in range(field["offset"], field["offset"] + field["size"])
        ]

        self.assertEqual(len(covered), 64)
        self.assertEqual(set(covered), set(range(64)))
        self.assertEqual(protocol.FRAME_HEADER_FIELD_OFFSETS["reserved1"], 48)
        self.assertEqual(protocol.FRAME_HEADER_FIELD_SIZES["reserved1"], 16)

    def test_generated_struct_is_exactly_64_bytes(self) -> None:
        self.assertEqual(protocol.FRAME_HEADER_BYTE_ORDER, "little")
        self.assertEqual(protocol.FRAME_HEADER_STRUCT.size, 64)
        self.assertEqual(protocol.FRAME_HEADER_STRUCT.size, protocol.FRAME_HEADER_SIZE)

    def test_pack_unpack_uses_declared_offsets_and_little_endian(self) -> None:
        values = (
            protocol.FRAME_MAGIC,
            protocol.PROTOCOL_VERSION,
            protocol.HEADER_LENGTH,
            0x11223344,
            0x55667788,
            0x99AA,
            0xBBCC,
            0xDD,
            0xEE,
            0xF0,
            protocol.FLAGS_EXPECTED,
            0x0102030405060708,
            0xA1B2C3D4,
            0xE5F60718,
            0x3344,
            protocol.FRAME_HEADER_RESERVED0_EXPECTED,
            0xDEADBEEF,
            protocol.FRAME_HEADER_RESERVED1_EXPECTED,
        )
        packed = protocol.FRAME_HEADER_STRUCT.pack(*values)

        self.assertEqual(packed[protocol.FRAME_MAGIC_OFFSET : protocol.FRAME_MAGIC_OFFSET + 4], b"AJPG")
        self.assertEqual(
            packed[protocol.FRAME_SEQUENCE_OFFSET : protocol.FRAME_SEQUENCE_OFFSET + 4],
            b"\x44\x33\x22\x11",
        )
        self.assertEqual(
            packed[protocol.TIMESTAMP_NS_OFFSET : protocol.TIMESTAMP_NS_OFFSET + 8],
            b"\x08\x07\x06\x05\x04\x03\x02\x01",
        )
        self.assertEqual(packed[protocol.FLAGS_OFFSET], protocol.FLAGS_EXPECTED)
        self.assertEqual(packed[protocol.RESERVED1_OFFSET :], bytes(16))
        self.assertEqual(protocol.FRAME_HEADER_STRUCT.unpack(packed), values)

    def test_all_generated_files_have_not_drifted(self) -> None:
        fields = validate_protocol(self.data)

        generated = (
            (PYTHON_OUT, generate_python(self.data, fields)),
            (C_OUT, generate_c(self.data)),
            (VERILOG_OUT, generate_verilog(self.data)),
        )
        for path, expected in generated:
            with self.subTest(path=path):
                self.assertEqual(path.read_text(encoding="utf-8"), expected)


class PcieProtocolValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.data = json.loads(SOURCE.read_text(encoding="utf-8"))

    def _invalid_layout(self) -> dict:
        return copy.deepcopy(self.data)

    def test_invalid_byte_order_fails(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["byte_order"] = "big"

        with self.assertRaisesRegex(ValueError, "byte_order"):
            validate_protocol(data)

    def test_non_object_protocol_roots_fail_as_schema_errors(self) -> None:
        for root in (None, [], "pcie_protocol_v1", 1, True):
            with self.subTest(root=root):
                with self.assertRaisesRegex(ValueError, "root.*object"):
                    validate_protocol(root)

    def test_frame_header_validator_rejects_non_object_protocol_roots(self) -> None:
        for root in (None, [], "pcie_protocol_v1", 1, True):
            with self.subTest(root=root):
                with self.assertRaisesRegex(ValueError, "root.*object"):
                    validate_frame_header(root)

    def test_each_required_top_level_member_must_exist(self) -> None:
        for name in (
            "device_magic",
            "frame_magic",
            "protocol_version",
            "header_length",
            "max_payload",
            "slot_count",
            "user_bar_base",
            "registers",
            "control_bits",
            "status_bits",
            "error_codes",
            "frame_header",
        ):
            with self.subTest(name=name):
                data = self._invalid_layout()
                del data[name]

                with self.assertRaisesRegex(ValueError, name):
                    validate_protocol(data)

    def test_top_level_mapping_containers_must_be_objects(self) -> None:
        for value in ([], None):
            with self.subTest(value=value):
                data = self._invalid_layout()
                data["registers"] = value

                with self.assertRaisesRegex(ValueError, "registers.*object"):
                    validate_protocol(data)

        data = self._invalid_layout()
        data["control_bits"] = []
        with self.assertRaisesRegex(ValueError, "control_bits.*object"):
            validate_protocol(data)

    def test_top_level_scalars_reject_invalid_values_and_ranges(self) -> None:
        for value in (True, None, "not-a-number", 1 << 32):
            with self.subTest(value=value):
                data = self._invalid_layout()
                data["device_magic"] = value

                with self.assertRaisesRegex(ValueError, "device_magic"):
                    validate_protocol(data)

        for name in ("max_payload", "slot_count"):
            with self.subTest(name=name):
                data = self._invalid_layout()
                data[name] = 0

                with self.assertRaisesRegex(ValueError, f"{name}.*positive"):
                    validate_protocol(data)

    def test_user_bar_base_requires_nonzero_4k_alignment(self) -> None:
        for value, message in ((0, "non-zero"), (0x00080123, "4096-byte aligned")):
            with self.subTest(value=value):
                data = self._invalid_layout()
                data["user_bar_base"] = value

                with self.assertRaisesRegex(ValueError, f"user_bar_base.*{message}"):
                    validate_protocol(data)

        for value in (0x00080000, 0xFFFFF000):
            with self.subTest(value=value):
                data = self._invalid_layout()
                data["user_bar_base"] = value
                validate_protocol(data)

    def test_protocol_identity_constants_must_be_positive(self) -> None:
        header_field_index = {"frame_magic": 0, "protocol_version": 1}
        for name in ("device_magic", "frame_magic", "protocol_version"):
            with self.subTest(name=name):
                data = self._invalid_layout()
                data[name] = 0
                if name in header_field_index:
                    data["frame_header"]["fields"][header_field_index[name]]["expected"] = 0

                with self.assertRaisesRegex(ValueError, f"{name}.*positive"):
                    validate_protocol(data)

    def test_mapping_values_reject_invalid_values_and_ranges(self) -> None:
        cases = (
            ("registers", "DEVICE_MAGIC", True),
            ("registers", "DEVICE_MAGIC", "not-a-number"),
            ("registers", "DEVICE_MAGIC", 1 << 12),
            ("control_bits", "APP_ENABLE", 32),
            ("status_bits", "LINK_UP", 32),
            ("error_codes", "NONE", 1 << 32),
        )
        for mapping, key, value in cases:
            with self.subTest(mapping=mapping, key=key, value=value):
                data = self._invalid_layout()
                data[mapping][key] = value

                with self.assertRaisesRegex(ValueError, mapping):
                    validate_protocol(data)

    def test_mapping_macro_names_must_be_safe_and_non_colliding(self) -> None:
        data = self._invalid_layout()
        data["registers"]["not-a-macro"] = 0x60
        with self.assertRaisesRegex(ValueError, "registers key.*macro"):
            validate_protocol(data)

        data = self._invalid_layout()
        data["registers"]["device_magic"] = 0x60
        with self.assertRaisesRegex(ValueError, "registers.*collision"):
            validate_protocol(data)

    def test_mapping_macro_names_must_be_ascii(self) -> None:
        for mapping in ("registers", "control_bits", "status_bits", "error_codes"):
            with self.subTest(mapping=mapping):
                data = self._invalid_layout()
                data[mapping]["\u212aEY"] = 0

                with self.assertRaisesRegex(ValueError, f"{mapping} key.*ASCII"):
                    validate_protocol(data)

    def test_header_length_must_match_frame_header_size(self) -> None:
        data = self._invalid_layout()
        data["header_length"] = 63

        with self.assertRaisesRegex(ValueError, "frame_header.size.*header_length"):
            validate_protocol(data)

    def test_generator_entries_validate_before_rendering(self) -> None:
        data = self._invalid_layout()
        del data["registers"]

        for generator in (generate_verilog, generate_c, generate_python):
            with self.subTest(generator=generator.__name__):
                with self.assertRaisesRegex(ValueError, "registers"):
                    generator(data)

    def test_overlapping_fields_fail(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["fields"][3]["offset"] = 6

        with self.assertRaisesRegex(ValueError, "overlaps byte 6"):
            validate_protocol(data)

    def test_undeclared_hole_fails(self) -> None:
        data = self._invalid_layout()
        reserved1 = data["frame_header"]["fields"][-1]
        reserved1["size"] = 15
        reserved1["expected"] = "00" * 15

        with self.assertRaisesRegex(ValueError, "leaves undeclared byte"):
            validate_protocol(data)

    def test_type_and_size_mismatch_fails(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["fields"][0]["size"] = 2

        with self.assertRaisesRegex(ValueError, "must be 4 for type u32"):
            validate_protocol(data)

    def test_non_string_field_types_fail_as_schema_errors(self) -> None:
        for field_type in ([], {}, None, 1, True):
            with self.subTest(field_type=field_type):
                data = self._invalid_layout()
                data["frame_header"]["fields"][0]["type"] = field_type

                with self.assertRaisesRegex(ValueError, "type.*string"):
                    validate_protocol(data)

    def test_field_names_with_normalized_constant_collisions_fail(self) -> None:
        for first_name, second_name in (("width", "WIDTH"), ("field", "Field")):
            with self.subTest(first_name=first_name, second_name=second_name):
                data = self._invalid_layout()
                data["frame_header"]["fields"][5]["name"] = first_name
                data["frame_header"]["fields"][6]["name"] = second_name

                with self.assertRaisesRegex(ValueError, "collision"):
                    validate_protocol(data)

    def test_field_name_that_cannot_generate_python_constant_fails(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["fields"][5]["name"] = "not-a-symbol"

        with self.assertRaisesRegex(ValueError, "constant identifier"):
            validate_protocol(data)

    def test_field_name_unicode_normalization_confusion_fails(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["fields"][5]["name"] = "K"
        data["frame_header"]["fields"][6]["name"] = "\u212a"

        with self.assertRaisesRegex(ValueError, "ASCII Python constant identifier"):
            validate_protocol(data)

    def test_fixed_value_that_overflows_field_fails(self) -> None:
        data = self._invalid_layout()
        data["frame_header"]["fields"][10]["expected"] = 256

        with self.assertRaisesRegex(ValueError, "does not fit in u8"):
            validate_protocol(data)


if __name__ == "__main__":
    unittest.main()
