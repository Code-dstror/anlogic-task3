"""Run the public-ports-only CFG service checks in a fresh ModelSim library."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


CASES = ("mono", "dual", "reject_basic", "reject_hdr", "fault_recovery")
RTL_FILES = (
    "rtl/td_sdp_ram40.v",
    "rtl/reset_release_sync.v",
    "rtl/control_fifo_40x512.v",
    "rtl/control_message_fifo_ip.v",
    "rtl/mono_config_byte_store_v2.v",
    "rtl/mono_config_legacy_scan_v1.v",
    "rtl/mono_config_scan_v2.v",
    "rtl/mono_config_bar_v2.v",
    "rtl/mono_config_engine_v2.v",
    "rtl/mono_config_service_v2.v",
    "ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
    "ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v",
    "ip/camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v",
    "ip/camera_control_fifo_40x512/camera_control_fifo_40x512.v",
)
TD_FILES = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
)
INCLUDE_DIRS = ("00_rtl", "01_include", "02_jpeg", "03_mono_config_v2_20261015", "04_include")
DEFINES = ("+define+PH1", "+define+C15_F23_FULLHEIGHT_PROFILE=1")


class ToolFailure(RuntimeError):
    pass


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def write_constants(source, destination):
    protocol = json.loads(source.read_text(encoding="utf-8"))
    transaction = protocol["config_transaction"]
    v2 = protocol["advanced_config_v2"]
    lines = ["// Generated from docs/pcie_protocol_v1.json."]
    for name, address in protocol["registers"].items():
        if name.startswith("CFG_"):
            lines.append(f"localparam logic [11:0] {name} = 12'h{int(address, 16):03x};")

    values = {
        "CFG_DEFAULT_QUALITY": transaction["default_quality"],
        "CFG_MODE_COLOR": transaction["modes"]["COLOR"],
        "V2_SCHEMA_VALUE": v2["schema"],
        "V2_WORD_COUNT": v2["word_count"],
    }
    values.update({f"CFG_{name}": value for name, value in transaction["profiles"].items()})
    values.update({f"CFG_FEAT_{name}": 1 << value for name, value in transaction["features"].items()})
    values.update({f"CFG_CMD_{name}": value for name, value in transaction["commands"].items()})
    values.update({f"CFG_STS_{name}": 1 << value for name, value in transaction["status_bits"].items()})
    values.update({f"CFG_ERR_{name}": value for name, value in transaction["error_codes"].items()})
    values.update({f"V2_{name}": value for name, value in v2["modes"].items()})
    values.update({f"V2_{name}": value for name, value in v2["enables"].items()})
    for field in v2["fields"]:
        values[f"V2_{field['name']}_LSB"] = field["offset"]
        values[f"V2_{field['name']}_WIDTH"] = field["width"]
    lines.extend(f"localparam int unsigned {name} = {value};" for name, value in values.items())
    destination.write_text("\n".join(lines) + "\n", encoding="ascii")


def run_command(name, command, cwd, log, deadline, env, commands):
    args = [os.fspath(item) for item in command]
    record = {"name": name, "argv": args, "cwd": str(cwd), "log": str(log)}
    commands.append(record)
    start = time.monotonic()
    remaining = deadline - start
    if remaining <= 0:
        raise ToolFailure(f"Wall-clock watchdog before {name}")
    try:
        with log.open("xb") as raw:
            with subprocess.Popen(args, cwd=cwd, stdout=raw, stderr=subprocess.STDOUT, env=env) as process:
                try:
                    record["exit_code"] = process.wait(timeout=remaining)
                except subprocess.TimeoutExpired as exc:
                    subprocess.run(
                        ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                        stdout=raw, stderr=subprocess.STDOUT, timeout=1, check=False,
                    )
                    process.kill()
                    raise ToolFailure(f"Wall-clock watchdog during {name}") from exc
    finally:
        record["wall_seconds"] = round(time.monotonic() - start, 3)
    return record["exit_code"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--run-id", default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ"))
    parser.add_argument("--case", choices=CASES, action="append")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", args.run_id):
        parser.error("--run-id must be a single alphanumeric label, with optional hyphens or underscores")
    cases = args.case or CASES
    if len(set(cases)) != len(cases):
        parser.error("Each --case may appear at most once")

    start = time.monotonic()
    deadline = start + 58
    script = Path(__file__).resolve()
    bench_dir = script.parent
    fpga_root = bench_dir.parent.parent
    candidate = fpga_root.parent
    root = candidate.parent.parent
    run_dir = candidate / "tmp" / "parameters_20261110" / "rtl_bb" / args.run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    print(f"Raw evidence directory: {run_dir}", flush=True)

    bench = bench_dir / "tb_cfg_parameters.sv"
    run_bench = run_dir / bench.name
    protocol = root / "docs" / "pcie_protocol_v1.json"
    contract = candidate / "docs" / "parameter_timing_20261110" / "CFG_PARAMETERS_PUBLIC.md"
    generated = run_dir / "cfg_public_constants.svh"
    model_root = args.td_root.resolve(strict=True) / "sim_release"
    gsr = model_root / "ph1" / "ph1_phy_gsr.v"
    rtl = [fpga_root / file for file in RTL_FILES]
    td_models = [model_root / file for file in TD_FILES]
    includes = [fpga_root / "rtl" / "include" / directory for directory in INCLUDE_DIRS]
    tools = {name: args.modelsim_bin.resolve(strict=True) / f"{name}.exe"
             for name in ("vlib", "vlog", "vmap", "vsim")}
    env = os.environ.copy()
    env.pop("MODELSIM", None)
    manifest = {
        "scope": "Independent public BAR, CDC and configuration service simulation",
        "result": "BLOCKED",
        "runner_argv": [sys.executable, *sys.argv],
        "runner_cwd": str(Path.cwd()),
        "td_root": str(model_root.parent),
        "clock_ns": {"user": 8, "pixel": 10},
        "simulation_watchdog_ns_per_case": 1_000_000,
        "wall_watchdog_seconds_per_run": 60,
        "requested_cases": cases,
        "cases": {},
        "commands": [],
    }

    def invoke(name, command, cwd=run_dir):
        log = cwd / f"{name}.log"
        code = run_command(name, command, cwd, log, deadline, env, manifest["commands"])
        return code, log

    def require(name, command):
        code, log = invoke(name, command)
        if code:
            raise ToolFailure(f"{name} exited {code}; raw diagnostic preserved at {log}")
        return log

    try:
        shutil.copy2(bench, run_bench)
        shutil.copy2(script, run_dir / script.name)
        write_constants(protocol, generated)
        include_files = sorted(file for directory in includes for file in directory.rglob("*")
                               if file.is_file())
        inputs = [script, run_bench, protocol, contract, generated, gsr, *rtl, *td_models, *include_files]
        manifest["sha256"] = {str(path): sha256(path) for path in inputs}
        version = require("modelsim-version", [tools["vsim"], "-version"])
        manifest["modelsim_version"] = version.read_text(encoding="utf-8", errors="replace").strip()
        require("vmap-init", [tools["vmap"], "-c"])
        for library in ("work", "ph1"):
            physical = run_dir / library
            require(f"vlib-{library}", [tools["vlib"], physical])
            require(f"vmap-{library}", [tools["vmap"], library, physical])
        require("compile-td-models", [tools["vlog"], "-work", "ph1", *DEFINES, *td_models])
        require("compile-production", [
            tools["vlog"], "-work", "work", "-L", "ph1", *DEFINES,
            *(f"+incdir+{path.as_posix()}" for path in includes), gsr, *rtl,
        ])
        require("compile-testbench", [
            tools["vlog"], "-sv", "-work", "work", f"+incdir+{run_dir.as_posix()}", run_bench,
        ])
        changed_inputs = [path for path, before in manifest["sha256"].items()
                          if sha256(Path(path)) != before]
        if changed_inputs:
            raise ToolFailure(f"Inputs changed while compiling: {', '.join(changed_inputs)}")
        for case in cases:
            case_dir = run_dir / case
            case_dir.mkdir()
            shutil.copy2(run_dir / "modelsim.ini", case_dir / "modelsim.ini")
            code, raw = invoke("simulation", [
                tools["vsim"], "-c", "-onfinish", "stop", "-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl",
                "work.tb_cfg_parameters", f"+case={case}",
                "-do", "onerror {quit -f -code 2}; run -all; quit -f -code 0",
            ], case_dir)
            transcript = raw.read_text(encoding="utf-8", errors="replace")
            marker = re.search(rf"^\s*#?\s*BLACKBOX_PASS\s+CFG_PARAMETERS\s+{case}\s+time_ns=(\d+)\s*$",
                               transcript, flags=re.MULTILINE)
            test_assertion = re.search(r"^\s*#?\s*\*\* Fatal: (\[[^\]]+\].*|Simulation watchdog.*)$",
                                       transcript, flags=re.MULTILINE)
            passed = code == 0 and marker and int(marker[1]) <= 1_000_000
            result = "PASS" if passed else "FAIL" if test_assertion else "BLOCKED"
            entry = {"result": result, "log": str(raw), "exit_code": code}
            if marker:
                entry["simulation_ns"] = int(marker[1])
            if test_assertion:
                entry["public_assertion"] = test_assertion[1]
            manifest["cases"][case] = entry
            print(f"{case}: {result} {entry.get('public_assertion', '')}".rstrip(), flush=True)
        results = {entry["result"] for entry in manifest["cases"].values()}
        manifest["result"] = "PASS" if results == {"PASS"} else "FAIL" if "FAIL" in results else "BLOCKED"
    except (OSError, subprocess.TimeoutExpired, ToolFailure) as exc:
        manifest["tool_or_dependency_error"] = str(exc)
        print(f"BLOCKED: {exc}", flush=True)
    finally:
        manifest["wall_seconds"] = round(time.monotonic() - start, 3)
        (run_dir / "VALIDATION.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8",
        )
    return 0 if manifest["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
