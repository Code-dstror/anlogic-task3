"""Compile opaque production inputs and run one bounded public-port test."""

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time


BENCH = Path(__file__).resolve().parent
FPGA = BENCH.parents[1]
PROJECT = FPGA.parent
MODEL_FILES = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
)
CONFIG_FILES = (
    "rtl/frame_job_config_cdc.v",
    "rtl/frame_config_extension_validate.v",
    "rtl/reset_release_sync.v",
    "rtl/control_message_fifo_ip.v",
    "rtl/control_fifo_40x512.v",
    "ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v",
    "ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v",
    "ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v",
)
CONFIG_INCLUDES = (
    "rtl/include/00_rtl",
    "rtl/include/03_mono_config_v2_20261015",
    "rtl/include/04_include",
    "ip/camera_control_fifo_40x512/RTL/include",
)
PRODUCT_FILES = (
    "rtl/reset_release_sync_data.v",
    "rtl/raw_video_record_formatter.v",
    "rtl/product_record_cdc.v",
    "rtl/reset_release_sync.v",
    "rtl/axis_frame_fifo_ip.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    "ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v",
)
PRODUCT_INCLUDES = (
    "rtl/include/00_rtl",
    "rtl/include/01_include",
    "ip/camera_packet_fifo_147x512/RTL/include",
)
SOURCES = {
    "config": (CONFIG_FILES, CONFIG_INCLUDES, True),
    "arbiter": (("rtl/reset_release_sync_data.v", "rtl/dol2_axi_write_arbiter.v"), (), False),
    "formatter": (("rtl/reset_release_sync_data.v", "rtl/raw_video_record_formatter.v"),
                  ("rtl/include/00_rtl", "rtl/include/01_include"), False),
    "product": (PRODUCT_FILES, PRODUCT_INCLUDES, True),
}


def path_text(path):
    return path.as_posix()


def sha256(paths):
    return {path_text(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(set(paths))}


def write_araw_oracle(wire_format, header):
    schema = json.loads(wire_format.read_text(encoding="utf-8"))
    if schema["byte_order"] != "little":
        raise RuntimeError("ARAW byte order changed")
    constants = [f"localparam logic [31:0] ARAW_MAGIC = 32'd{schema['magic']};",
                 f"localparam int ARAW_VERSION = {schema['version']};",
                 f"localparam int ARAW_HEADER_BYTES = {schema['header_bytes']};",
                 f"localparam int ARAW_FORMAT_RAW10 = {schema['format_raw10']};",
                 f"localparam int ARAW_TIMESTAMP_FLAG = {schema['flag_timestamp_valid']};"]
    for field in schema["fields"]:
        name = field["name"].upper()
        constants.extend([f"localparam int ARAW_{name}_LO = {8 * field['offset']};",
                          f"localparam int ARAW_{name}_BITS = {8 * field['bytes']};"])
    header.write_text("\n".join(constants) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=SOURCES, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    start = time.monotonic()
    deadline = start + 55
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out = PROJECT / "tmp" / "blackbox_dfi_timing_20261109" / f"{args.case}-{now}"
    out.mkdir(parents=True)
    print(path_text(out), flush=True)
    report = {"case": args.case, "status": "BLOCKED", "commands": [], "deadline_s": 55,
              "invocation": [sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]]}

    def run(tool, *options):
        command = [path_text(args.modelsim_bin.resolve() / f"{tool}.exe"), *options]
        logfile = out / f"{len(report['commands']):02d}-{tool}.log"
        record = {"argv": command, "cwd": path_text(out), "log": logfile.name}
        report["commands"].append(record)
        with logfile.open("wb") as log:
            result = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=max(0.001, deadline - time.monotonic()))
        record["exit_code"] = result.returncode
        return result.returncode, logfile

    def require(tool, *options):
        code, logfile = run(tool, *options)
        if code:
            raise RuntimeError(f"{tool} exit {code} in {logfile.name}")
        return logfile

    try:
        sources, includes, vendor_fifo = SOURCES[args.case]
        top = f"tb_dfi_{args.case}"
        tb = BENCH / f"{top}.sv"
        model_root = args.td_root.resolve() / "sim_release"
        models = [model_root / name for name in MODEL_FILES] if vendor_fifo else []
        gsr = [model_root / "ph1/ph1_phy_gsr.v"] if vendor_fifo else []
        includes = [FPGA / name for name in includes]
        sources = [FPGA / name for name in sources]
        headers = [path for directory in includes for path in directory.glob("*")
                   if path.is_file() and path.suffix.lower() in {".h", ".vh", ".svh"}]
        contracts = [PROJECT / "docs/timing_20261109/DFI_CONFIG_PUBLIC.md"]
        fixture = [tb]
        if args.case != "config":
            contracts = [BENCH / "DFI_RESET_PUBLIC.md", BENCH / "ports.txt"]
        if args.case in {"formatter", "product"}:
            wire_format = PROJECT / "docs/raw_video_v1.json"
            oracle = out / "araw_oracle_fields.svh"
            write_araw_oracle(wire_format, oracle)
            fixture.insert(0, BENCH / "dfi_araw_fixture.sv")
            headers.append(oracle)
            includes.append(out)
            contracts.append(wire_format)
        inputs = [Path(__file__).resolve(), *fixture, *sources, *headers, *models, *gsr, *contracts]
        report["sha256"] = sha256(inputs)
        report["python"] = {"executable": sys.executable, "version": sys.version}
        report["td_root"] = path_text(args.td_root.resolve())
        version = require("vsim", "-version")
        report["modelsim"] = version.read_text(errors="replace").strip()
        require("vmap", "-c")
        require("vlib", "work")
        libraries = []
        tops = [f"work.{top}"]
        defines = []
        if vendor_fifo:
            require("vlib", "ph1")
            require("vmap", "ph1", "ph1")
            require("vlog", "-sv", "-work", "ph1", *map(path_text, models))
            libraries = ["-L", "ph1"]
            tops.append("ph1.glbl")
            if args.case == "product":
                tops.append("work.PH1_PHY_GSR")
            defines = ["+define+PH1"]
        require("vlog", "-sv", *defines, *libraries,
                *(f"+incdir+{path_text(directory)}" for directory in includes),
                *map(path_text, [*gsr, *sources, *fixture]))
        code, sim = run("vsim", "-c", *libraries, "-t", "1ps", *tops,
                        "-do", "onerror {quit -code 2 -f}; run -all; quit -code 0 -f")
        markers = [line.strip().removeprefix("# ") for line in
                   sim.read_text(errors="replace").splitlines()]
        report["terminal"] = [line for line in markers if line.startswith(("PASS ", "FAIL "))]
        expected_pass = f"PASS dfi_{args.case}"
        if any(line.startswith("FAIL ") for line in report["terminal"]):
            report["status"] = "FAIL"
        elif not code and any(line.startswith(expected_pass + " ") for line in report["terminal"]):
            report["status"] = "PASS"
        else:
            report["error"] = f"No clean {expected_pass} terminal. Simulation exit {code}."
        if sha256(inputs) != report["sha256"]:
            report["status"] = "STALE"
            report["error"] = "An input changed during this run."
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        report["error"] = str(error)
    finally:
        report["elapsed_s"] = round(time.monotonic() - start, 3)
        (out / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(report["status"], *report.get("terminal", []), report.get("error", ""), flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
