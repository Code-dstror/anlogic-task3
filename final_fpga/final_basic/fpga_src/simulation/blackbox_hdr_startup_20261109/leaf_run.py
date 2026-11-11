"""Compile and exercise the public HDR gate boundary, with a fresh run directory."""

import argparse
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import re
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
R2 = HERE.parents[2]
RTL = R2 / "src_fpga" / "rtl"
BASELINE = R2 / "tmp/seed12fix_20261109/baseline/real_hdr_pair_cycle_gate.v"
RUNS = R2 / "tmp/blackbox_hdr_startup_20261109"
MARKERS = re.compile(r"^(?:#\s*)?(LEAF_GATE_(?:CASE|STATS|FAIL|PASS)(?: .*)?)$")
WALL_SECONDS = 45


def digests(files):
    return {str(path): sha256(path.read_bytes()).hexdigest() for path in files}


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("variant", choices=("baseline", "candidate"))
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    start = time.monotonic()
    msim = args.modelsim_bin.resolve(strict=True)
    bench = HERE / "leaf_tb.sv"
    source = BASELINE if args.variant == "baseline" else RTL / "real_hdr_pair_cycle_gate.v"
    incs = [RTL / "include" / name for name in ("04_include", "00_rtl")]
    contract = R2 / "docs/seed12fix_20261109"
    inputs = [source, bench, Path(__file__).resolve(), incs[0] / "pcie_protocol_v1.vh",
              contract / "GATE_PUBLIC.md", contract / "GATE_PORTS.txt"]
    run = RUNS / datetime.now(timezone.utc).strftime(f"leaf_{args.variant}_%Y%m%dT%H%M%S_%fZ")
    run.mkdir(parents=True)
    print(run, flush=True)
    status = {"verdict": "TOOL_BLOCKED"}
    try:
        before = digests(inputs)
        stages = [
            ("version", [str(msim / "vsim.exe"), "-version"]),
            ("vlib", [str(msim / "vlib.exe"), "work"]),
            ("vlog", [str(msim / "vlog.exe"), "-sv", "-work", "work",
                      *(f"+incdir+{path}" for path in incs), str(source), str(bench)]),
            ("sim", [str(msim / "vsim.exe"), "-c", "-onfinish", "stop", "work.leaf_tb",
                     "-do", "onerror {quit -code 2}; run -all; quit -code 0"]),
        ]
        save_json(run / "inputs.json", {
            "variant": args.variant,
            "python": sys.version,
            "runner_command": sys.orig_argv,
            "hdl_parameters": {"TIMEOUT_CYCLES": 512, "EXTERNAL_PHASE_ENABLE": 0},
            "watchdogs": {"wall_seconds": WALL_SECONDS, "simulation_ns": 200000},
            "sha256": before,
            "cwd": str(run),
            "commands": dict(stages),
        })
        stage_codes = {}
        status["exit_codes"] = stage_codes
        for stage, cmd in stages:
            status["stage"] = stage
            remaining = WALL_SECONDS - (time.monotonic() - start)
            if remaining <= 0:
                raise TimeoutError("wall watchdog")
            with (run / f"{stage}.log").open("wb") as log:
                stage_codes[stage] = subprocess.run(cmd, cwd=run, stdout=log, stderr=subprocess.STDOUT,
                                                    timeout=remaining, check=False).returncode
            if stage != "sim" and stage_codes[stage] != 0:
                print(f"TOOL_BLOCKED: {stage}; log for maintainer in {run}")
                return 2

        if digests(inputs) != before:
            status["verdict"] = "INPUT_CHANGED"
            print("INPUT_CHANGED: discard this run's result")
            return 2
        public_lines = []
        for line in (run / "sim.log").read_text(encoding="utf-8", errors="replace").splitlines():
            match = MARKERS.fullmatch(line.strip())
            if match:
                public_lines.append(match[1])
        print(*public_lines, sep="\n")
        failed = next((line for line in public_lines if line.startswith("LEAF_GATE_FAIL")), None)
        if failed:
            status.update(verdict="HDL_FAIL", marker=failed)
            return 1
        if public_lines.count("LEAF_GATE_PASS") == 1 and stage_codes["sim"] == 0:
            status.update(verdict="PASS", marker="LEAF_GATE_PASS")
            return 0
        print("TOOL_BLOCKED: no definitive HDL marker; simulation log for maintainer")
        return 2
    except (OSError, subprocess.SubprocessError) as exc:
        status["error"] = str(exc)
        print(f"TOOL_BLOCKED: {exc}")
        return 2
    finally:
        status["wall_seconds"] = round(time.monotonic() - start, 3)
        save_json(run / "result.json", status)


if __name__ == "__main__":
    sys.exit(main())
