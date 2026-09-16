"""Generate protocol constants from the reviewed JSON contract."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "doc" / "pcie_protocol_v1.json"
VERILOG_OUT = ROOT / "fpga_rtl" / "include" / "pcie_protocol_v1.vh"
C_OUT = ROOT / "doc" / "pcie_protocol_v1.h"
PYTHON_OUT = ROOT / "linux" / "task3_pipeline" / "pcie_protocol_v1.py"

_HEADER_SIZE = 64
_TYPE_SIZES = {"u8": 1, "u16": 2, "u32": 4, "u64": 8}
_STRUCT_CODES = {"u8": "B", "u16": "H", "u32": "I", "u64": "Q"}
_ASCII_IDENTIFIER_START = frozenset("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")
_ASCII_IDENTIFIER_CONTINUE = _ASCII_IDENTIFIER_START | frozenset("0123456789")


def number(value: int | str, context: str = "value") -> int:
    if isinstance(value, bool):
        raise ValueError(f"{context} must be an integer, not a boolean")
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError as error:
            raise ValueError(f"{context} must be an integer literal, got {value!r}") from error
    raise ValueError(f"{context} must be an integer, got {type(value).__name__}")


def _mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{context} must be an object")
    return value


def _unsigned_number(value: Any, context: str, bits: int) -> int:
    result = number(value, context)
    maximum = (1 << bits) - 1
    if not 0 <= result <= maximum:
        raise ValueError(f"{context} must fit an unsigned {bits}-bit value, got {result}")
    return result


def _constant_name(name: str) -> str:
    return name.upper()


def _is_ascii_identifier(name: Any) -> bool:
    return (
        isinstance(name, str)
        and bool(name)
        and name[0] in _ASCII_IDENTIFIER_START
        and all(character in _ASCII_IDENTIFIER_CONTINUE for character in name[1:])
    )


def _macro_name(name: Any, context: str) -> str:
    if not isinstance(name, str) or not name:
        raise ValueError(f"{context} must be a non-empty ASCII identifier safe for C/Verilog macros")
    normalized = _constant_name(name)
    if not _is_ascii_identifier(name) or not _is_ascii_identifier(normalized):
        raise ValueError(f"{context} must be an ASCII identifier safe for C/Verilog macros")
    return normalized


def _validate_named_unsigned_mapping(
    root: dict[str, Any],
    name: str,
    bits: int,
    *,
    alignment: int | None = None,
) -> None:
    values = _mapping(root.get(name), name)
    normalized_names: dict[str, str] = {}
    for key, value in values.items():
        context = f"{name}[{key!r}]"
        normalized = _macro_name(key, f"{name} key {key!r}")
        previous_key = normalized_names.get(normalized)
        if previous_key is not None:
            raise ValueError(
                f"{name} macro name collision: {key!r} and {previous_key!r} both "
                f"normalize to {normalized!r}"
            )
        normalized_names[normalized] = key
        numeric_value = _unsigned_number(value, context, bits)
        if alignment is not None and numeric_value % alignment:
            raise ValueError(
                f"{context} must be {alignment}-byte aligned, got {numeric_value}"
            )


def _field_bytes_expected(value: Any, size: int, context: str) -> bytes:
    if not isinstance(value, str):
        raise ValueError(f"{context} for a bytes field must be a hexadecimal string")
    try:
        result = bytes.fromhex(value)
    except ValueError as error:
        raise ValueError(f"{context} must be valid hexadecimal") from error
    if len(result) != size:
        raise ValueError(f"{context} has {len(result)} bytes, but field size is {size}")
    return result


def validate_frame_header(data: Any) -> list[dict[str, Any]]:
    """Validate and return header fields sorted by byte offset.

    This is intentionally strict: a header is a complete 64-byte wire layout,
    not a partial collection of fields for a future parser to interpret.
    """
    root = _mapping(data, "protocol root")
    header = _mapping(root.get("frame_header"), "frame_header")
    byte_order = header.get("byte_order")
    if byte_order != "little":
        raise ValueError(f"frame_header.byte_order must be 'little', got {byte_order!r}")

    declared_size = number(header.get("size"), "frame_header.size")
    protocol_size = number(root.get("header_length"), "header_length")
    if declared_size != protocol_size:
        raise ValueError("frame_header.size must match header_length")
    if declared_size != _HEADER_SIZE:
        raise ValueError(
            f"frame_header.size must be exactly {_HEADER_SIZE}, got {declared_size}"
        )
    if protocol_size != _HEADER_SIZE:
        raise ValueError(f"header_length must be exactly {_HEADER_SIZE}, got {protocol_size}")

    raw_fields = header.get("fields")
    if not isinstance(raw_fields, list) or not raw_fields:
        raise ValueError("frame_header.fields must be a non-empty array")

    occupied: list[str | None] = [None] * _HEADER_SIZE
    names: set[str] = set()
    constant_names: dict[str, str] = {}
    fields: list[dict[str, Any]] = []
    for index, raw_field in enumerate(raw_fields):
        context = f"frame_header.fields[{index}]"
        field = _mapping(raw_field, context)
        name = field.get("name")
        if not isinstance(name, str) or not name:
            raise ValueError(f"{context}.name must be a non-empty ASCII identifier")
        constant_name = _constant_name(name)
        if not _is_ascii_identifier(name) or not _is_ascii_identifier(constant_name):
            raise ValueError(
                f"{context}.name must generate a valid ASCII Python constant identifier"
            )
        if name in names:
            raise ValueError(f"duplicate frame header field name {name!r}")
        names.add(name)
        previous_name = constant_names.get(constant_name)
        if previous_name is not None:
            raise ValueError(
                f"{context}.name causes Python constant name collision: {name!r} and "
                f"{previous_name!r} both normalize to {constant_name!r}"
            )
        constant_names[constant_name] = name

        field_type = field.get("type")
        if not isinstance(field_type, str):
            raise ValueError(f"{context}.type must be a string, got {type(field_type).__name__}")
        if field_type not in {*_TYPE_SIZES, "bytes"}:
            raise ValueError(f"{context}.type has unsupported value {field_type!r}")
        offset = number(field.get("offset"), f"{context}.offset")
        size = number(field.get("size"), f"{context}.size")
        if offset < 0:
            raise ValueError(f"{context}.offset must be non-negative")
        if size <= 0:
            raise ValueError(f"{context}.size must be positive")
        if field_type in _TYPE_SIZES and size != _TYPE_SIZES[field_type]:
            raise ValueError(
                f"{context}.size must be {_TYPE_SIZES[field_type]} for type {field_type}, got {size}"
            )
        end = offset + size
        if end > _HEADER_SIZE:
            raise ValueError(
                f"{context} spans bytes {offset}..{end - 1}, outside 0..{_HEADER_SIZE - 1}"
            )
        for byte in range(offset, end):
            if occupied[byte] is not None:
                raise ValueError(
                    f"{context} overlaps byte {byte} already declared by {occupied[byte]!r}"
                )
            occupied[byte] = name

        if "expected" in field:
            expected_context = f"{context}.expected"
            if field_type == "bytes":
                _field_bytes_expected(field["expected"], size, expected_context)
            else:
                expected = number(field["expected"], expected_context)
                maximum = (1 << (size * 8)) - 1
                if not 0 <= expected <= maximum:
                    raise ValueError(
                        f"{expected_context}={expected} does not fit in {field_type}"
                    )
        fields.append(field)

    holes = [str(byte) for byte, field_name in enumerate(occupied) if field_name is None]
    if holes:
        raise ValueError(
            "frame_header.fields leaves undeclared byte(s): " + ", ".join(holes)
        )

    fields.sort(key=lambda field: number(field["offset"], "field.offset"))
    return fields


def validate_protocol(data: Any) -> list[dict[str, Any]]:
    """Validate cross-references and return the sorted frame-header layout."""
    root = _mapping(data, "protocol root")

    scalar_values: dict[str, int] = {}
    for name, bits in (
        ("device_magic", 32),
        ("frame_magic", 32),
        ("protocol_version", 16),
        ("header_length", 32),
        ("max_payload", 32),
        ("slot_count", 32),
        ("user_bar_base", 32),
    ):
        scalar_values[name] = _unsigned_number(root.get(name), name, bits)
    for name in (
        "device_magic",
        "frame_magic",
        "protocol_version",
        "max_payload",
        "slot_count",
    ):
        if scalar_values[name] == 0:
            raise ValueError(f"{name} must be positive")
    if scalar_values["user_bar_base"] == 0:
        raise ValueError("user_bar_base must be non-zero")
    if scalar_values["user_bar_base"] % 4096:
        raise ValueError(
            f"user_bar_base must be 4096-byte aligned, got {scalar_values['user_bar_base']}"
        )

    _validate_named_unsigned_mapping(root, "registers", 12, alignment=4)
    _validate_named_unsigned_mapping(root, "control_bits", 5)
    _validate_named_unsigned_mapping(root, "status_bits", 5)
    _validate_named_unsigned_mapping(root, "error_codes", 32)

    fields = validate_frame_header(root)
    by_name = {field["name"]: field for field in fields}
    for name, top_level in (
        ("frame_magic", "frame_magic"),
        ("protocol_version", "protocol_version"),
        ("header_length", "header_length"),
    ):
        field = by_name.get(name)
        if field is None or "expected" not in field:
            raise ValueError(f"frame_header field {name!r} must declare an expected value")
        if number(field["expected"], f"frame_header.{name}.expected") != number(
            root.get(top_level), top_level
        ):
            raise ValueError(f"frame_header.{name}.expected must match {top_level}")
    flags = by_name.get("flags")
    if flags is None or "expected" not in flags:
        raise ValueError("frame_header field 'flags' must declare an expected value")
    return fields


def generate_verilog(data: Any) -> str:
    """Generate the Verilog header after validating the complete protocol."""
    validate_protocol(data)
    root = _mapping(data, "protocol root")
    lines = [
        "`ifndef PCIE_PROTOCOL_V1_VH",
        "`define PCIE_PROTOCOL_V1_VH",
        "",
        "// Generated from doc/pcie_protocol_v1.json. Do not edit by hand.",
        f"`define PCIE_DEVICE_MAGIC       32'h{number(root['device_magic']):08X}",
        f"`define PCIE_FRAME_MAGIC        32'h{number(root['frame_magic']):08X}",
        f"`define PCIE_PROTOCOL_VERSION   16'h{number(root['protocol_version']):04X}",
        f"`define PCIE_HEADER_LENGTH      32'd{number(root['header_length'])}",
        f"`define PCIE_MAX_PAYLOAD        32'd{number(root['max_payload'])}",
        f"`define PCIE_SLOT_COUNT         32'd{number(root['slot_count'])}",
        f"`define PCIE_USER_BAR_BASE      32'h{number(root['user_bar_base']):08X}",
        "",
    ]
    for name, offset in root["registers"].items():
        lines.append(f"`define PCIE_REG_{name:<20} 12'h{number(offset):03X}")
    lines.append("")
    for name, bit in root["control_bits"].items():
        lines.append(f"`define PCIE_CONTROL_{name:<16} {number(bit)}")
    lines.append("")
    for name, bit in root["status_bits"].items():
        lines.append(f"`define PCIE_STATUS_{name:<17} {number(bit)}")
    lines.append("")
    for name, code in root["error_codes"].items():
        lines.append(f"`define PCIE_ERROR_{name:<18} 32'd{number(code)}")
    lines.extend(["", "`endif", ""])
    return "\n".join(lines)


def generate_c(data: Any) -> str:
    """Generate the C header after validating the complete protocol."""
    validate_protocol(data)
    root = _mapping(data, "protocol root")
    lines = [
        "#ifndef PCIE_PROTOCOL_V1_H",
        "#define PCIE_PROTOCOL_V1_H",
        "",
        "/* Generated from doc/pcie_protocol_v1.json. Do not edit by hand. */",
        f"#define PCIE_DEVICE_MAGIC       0x{number(root['device_magic']):08X}u",
        f"#define PCIE_FRAME_MAGIC        0x{number(root['frame_magic']):08X}u",
        f"#define PCIE_PROTOCOL_VERSION   {number(root['protocol_version'])}u",
        f"#define PCIE_HEADER_LENGTH      {number(root['header_length'])}u",
        f"#define PCIE_MAX_PAYLOAD        {number(root['max_payload'])}u",
        f"#define PCIE_SLOT_COUNT         {number(root['slot_count'])}u",
        f"#define PCIE_USER_BAR_BASE      0x{number(root['user_bar_base']):08X}u",
        "",
    ]
    for name, offset in root["registers"].items():
        lines.append(f"#define PCIE_REG_{name:<20} 0x{number(offset):03X}u")
    lines.append("")
    for name, bit in root["control_bits"].items():
        lines.append(f"#define PCIE_CONTROL_{name:<16} (1u << {number(bit)})")
    lines.append("")
    for name, bit in root["status_bits"].items():
        lines.append(f"#define PCIE_STATUS_{name:<17} (1u << {number(bit)})")
    lines.append("")
    for name, code in root["error_codes"].items():
        lines.append(f"#define PCIE_ERROR_{name:<18} {number(code)}u")
    lines.extend(["", "#endif", ""])
    return "\n".join(lines)


def _python_expected(value: Any, field_type: str, size: int) -> str:
    if field_type == "bytes":
        return repr(_field_bytes_expected(value, size, "expected"))
    return str(number(value, "expected"))


def generate_python(data: Any, fields: list[dict[str, Any]] | None = None) -> str:
    """Generate importable protocol constants without runtime JSON access."""
    validated_fields = validate_protocol(data)
    if fields is not None and fields != validated_fields:
        raise ValueError("fields must match the validated frame_header layout")
    fields = validated_fields
    root = _mapping(data, "protocol root")
    format_codes = [
        _STRUCT_CODES[field["type"]]
        if field["type"] != "bytes"
        else f"{number(field['size'], 'field.size')}s"
        for field in fields
    ]
    expected_fields = [field for field in fields if "expected" in field]
    lines = [
        '"""Generated from doc/pcie_protocol_v1.json. Do not edit by hand."""',
        "",
        "from __future__ import annotations",
        "",
        "import struct",
        "",
        'FRAME_HEADER_BYTE_ORDER = "little"',
        f"FRAME_HEADER_SIZE = {number(root['header_length'])}",
        f"FRAME_MAGIC = 0x{number(root['frame_magic']):08X}",
        f"PROTOCOL_VERSION = {number(root['protocol_version'])}",
        f"HEADER_LENGTH = {number(root['header_length'])}",
        f"MAX_PAYLOAD = {number(root['max_payload'])}",
        "",
        f"FRAME_HEADER_FORMAT = \"<{''.join(format_codes)}\"",
        "FRAME_HEADER_STRUCT = struct.Struct(FRAME_HEADER_FORMAT)",
        "",
        "FRAME_HEADER_FIELD_NAMES = (",
    ]
    lines.extend(f'    "{field["name"]}",' for field in fields)
    lines.extend([")", "FRAME_HEADER_FIELD_OFFSETS = {"])
    lines.extend(
        f'    "{field["name"]}": {number(field["offset"], "field.offset")},'
        for field in fields
    )
    lines.extend(["}", "FRAME_HEADER_FIELD_SIZES = {"])
    lines.extend(
        f'    "{field["name"]}": {number(field["size"], "field.size")},'
        for field in fields
    )
    lines.extend(["}", "FRAME_HEADER_FIELD_TYPES = {"])
    lines.extend(f'    "{field["name"]}": "{field["type"]}",' for field in fields)
    lines.extend(["}", ""])
    for field in fields:
        constant = _constant_name(field["name"])
        lines.extend(
            [
                f"{constant}_OFFSET = {number(field['offset'], 'field.offset')}",
                f"{constant}_SIZE = {number(field['size'], 'field.size')}",
            ]
        )
    lines.append("")
    lines.append("FRAME_HEADER_EXPECTED_VALUES = {")
    lines.extend(
        f'    "{field["name"]}": {_python_expected(field["expected"], field["type"], number(field["size"], "field.size"))},'
        for field in expected_fields
    )
    lines.append("}")
    for field in expected_fields:
        constant = _constant_name(field["name"])
        lines.append(
            f"FRAME_HEADER_{constant}_EXPECTED = "
            f"{_python_expected(field['expected'], field['type'], number(field['size'], 'field.size'))}"
        )
    lines.extend(
        [
            "FLAGS_EXPECTED = FRAME_HEADER_FLAGS_EXPECTED",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> None:
    try:
        data = json.loads(SOURCE.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"{SOURCE} contains invalid JSON: {error.msg}") from error
    fields = validate_protocol(data)
    verilog = generate_verilog(data)
    c_header = generate_c(data)
    python_module = generate_python(data, fields)
    VERILOG_OUT.write_text(verilog, encoding="utf-8", newline="\n")
    C_OUT.write_text(c_header, encoding="utf-8", newline="\n")
    PYTHON_OUT.write_text(python_module, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
