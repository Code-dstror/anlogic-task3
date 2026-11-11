"""Generate the additive cold SDR rate constants for Verilog and Python."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def outputs():
    spec = json.loads((ROOT / "docs/rate_control_v1.json").read_text(encoding="utf-8"))
    registers = spec["registers"]
    codes = spec["codes"]
    if list(registers.values()) != [0xFB0, 0xFB4, 0xFB8]:
        raise ValueError("rate v1 occupies the three words immediately after the RAW extension")
    if list(codes.values()) != list(range(4)) or spec["legacy_30_sensor_profile"] != 4:
        raise ValueError("rate v1 codes must fit the selector and leave bit 2 for legacy 30 fps")
    capability = (spec["abi_version"] << 8) | sum(1 << code for code in codes.values())
    values = {f"PCIE_RATE_REG_{name}": (12, value) for name, value in registers.items()}
    values["PCIE_RATE_CAPABILITIES"] = (32, capability)
    values.update({f"PCIE_RATE_CODE_{name}": (2, code) for name, code in codes.items()})
    values["RATE_SENSOR_PROFILE_LEGACY_30"] = (3, spec["legacy_30_sensor_profile"])

    origin = "Generated from docs/rate_control_v1.json."
    verilog = f"// {origin}\n`ifndef RATE_CONTROL_V1_VH\n`define RATE_CONTROL_V1_VH\n"
    verilog += "".join(f"`define {name} {width}'h{value:x}\n"
                       for name, (width, value) in values.items())
    verilog += "`endif\n"
    python = f"# {origin}\n"
    python += "".join(f"{name} = 0x{value:x}\n" for name, (_, value) in values.items())
    return {
        ROOT / "src_fpga/rtl/include/00_rtl/rate_control_v1.vh": verilog,
        ROOT / "rk_sdk/rate_control_constants.py": python,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for path, body in outputs().items():
        if args.check:
            if path.read_text(encoding="utf-8") != body:
                raise ValueError(f"stale generated file {path}")
        else:
            path.write_text(body, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
