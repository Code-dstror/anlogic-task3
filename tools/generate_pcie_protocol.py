"""Generate Verilog and C protocol headers from the reviewed JSON contract."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "doc" / "pcie_protocol_v1.json"
VERILOG_OUT = ROOT / "fpga_rtl" / "include" / "pcie_protocol_v1.vh"
C_OUT = ROOT / "doc" / "pcie_protocol_v1.h"


def number(value: int | str) -> int:
    return int(value, 0) if isinstance(value, str) else value


def generate_verilog(data: dict) -> str:
    lines = [
        "`ifndef PCIE_PROTOCOL_V1_VH",
        "`define PCIE_PROTOCOL_V1_VH",
        "",
        "// Generated from doc/pcie_protocol_v1.json. Do not edit by hand.",
        f"`define PCIE_DEVICE_MAGIC       32'h{number(data['device_magic']):08X}",
        f"`define PCIE_FRAME_MAGIC        32'h{number(data['frame_magic']):08X}",
        f"`define PCIE_PROTOCOL_VERSION   16'h{number(data['protocol_version']):04X}",
        f"`define PCIE_HEADER_LENGTH      32'd{number(data['header_length'])}",
        f"`define PCIE_MAX_PAYLOAD        32'd{number(data['max_payload'])}",
        f"`define PCIE_SLOT_COUNT         32'd{number(data['slot_count'])}",
        f"`define PCIE_USER_BAR_BASE      32'h{number(data['user_bar_base']):08X}",
        "",
    ]
    for name, offset in data["registers"].items():
        lines.append(f"`define PCIE_REG_{name:<20} 12'h{number(offset):03X}")
    lines.append("")
    for name, bit in data["control_bits"].items():
        lines.append(f"`define PCIE_CONTROL_{name:<16} {number(bit)}")
    lines.append("")
    for name, bit in data["status_bits"].items():
        lines.append(f"`define PCIE_STATUS_{name:<17} {number(bit)}")
    lines.append("")
    for name, code in data["error_codes"].items():
        lines.append(f"`define PCIE_ERROR_{name:<18} 32'd{number(code)}")
    lines.extend(["", "`endif", ""])
    return "\n".join(lines)


def generate_c(data: dict) -> str:
    lines = [
        "#ifndef PCIE_PROTOCOL_V1_H",
        "#define PCIE_PROTOCOL_V1_H",
        "",
        "/* Generated from doc/pcie_protocol_v1.json. Do not edit by hand. */",
        f"#define PCIE_DEVICE_MAGIC       0x{number(data['device_magic']):08X}u",
        f"#define PCIE_FRAME_MAGIC        0x{number(data['frame_magic']):08X}u",
        f"#define PCIE_PROTOCOL_VERSION   {number(data['protocol_version'])}u",
        f"#define PCIE_HEADER_LENGTH      {number(data['header_length'])}u",
        f"#define PCIE_MAX_PAYLOAD        {number(data['max_payload'])}u",
        f"#define PCIE_SLOT_COUNT         {number(data['slot_count'])}u",
        f"#define PCIE_USER_BAR_BASE      0x{number(data['user_bar_base']):08X}u",
        "",
    ]
    for name, offset in data["registers"].items():
        lines.append(f"#define PCIE_REG_{name:<20} 0x{number(offset):03X}u")
    lines.append("")
    for name, bit in data["control_bits"].items():
        lines.append(f"#define PCIE_CONTROL_{name:<16} (1u << {number(bit)})")
    lines.append("")
    for name, bit in data["status_bits"].items():
        lines.append(f"#define PCIE_STATUS_{name:<17} (1u << {number(bit)})")
    lines.append("")
    for name, code in data["error_codes"].items():
        lines.append(f"#define PCIE_ERROR_{name:<18} {number(code)}u")
    lines.extend(["", "#endif", ""])
    return "\n".join(lines)


def main() -> None:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    VERILOG_OUT.write_text(generate_verilog(data), encoding="utf-8", newline="\n")
    C_OUT.write_text(generate_c(data), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
