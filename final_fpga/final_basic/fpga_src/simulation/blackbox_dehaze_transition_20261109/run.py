"""Run the independent public-port dehaze check in a fresh result directory."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
R2_ROOT = HERE.parents[2]
TOP = "tb_dehaze_transition"
WALL_TIMEOUT_SECONDS = 60
ARTIFACT_ROOT = R2_ROOT / "tmp" / HERE.name


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run_logged(command, log_path, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("wall-clock deadline expired before next stage")
    with log_path.open("wb") as log:
        subprocess.run(
            command, cwd=log_path.parent, stdout=log, stderr=subprocess.STDOUT,
            timeout=remaining, check=True,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--run-name", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", args.run_name):
        parser.error("--run-name must start with an alphanumeric and use only alphanumerics, '_' or '-'")

    run_dir = ARTIFACT_ROOT / args.run_name
    run_dir.mkdir(parents=True, exist_ok=False)
    modelsim_bin = args.modelsim_bin.resolve()
    rtl = R2_ROOT / "src_fpga" / "rtl" / "dehaze_dcp_restore4.v"
    bench = HERE / f"{TOP}.sv"
    contract = R2_ROOT / "docs" / "fieldfix_20261109" / "DEHAZE_PUBLIC_CONTRACT.md"
    inputs = (rtl, bench, Path(__file__).resolve(), contract)
    commands = {
        "version": [str(modelsim_bin / "vsim.exe"), "-version"],
        "vlib": [str(modelsim_bin / "vlib.exe"), "work"],
        "compile": [str(modelsim_bin / "vlog.exe"), "-sv", "-work", "work", str(rtl), str(bench)],
        "simulate": [
            str(modelsim_bin / "vsim.exe"), "-c", "-onfinish", "stop", f"work.{TOP}",
            "-do", "onerror {quit -code 1}; run -all; quit -code 0",
        ],
    }
    start = time.monotonic()
    result = {
        "cwd": str(run_dir),
        "runner_argv": [sys.executable, *sys.argv],
        "commands": commands,
        "profile": {"WIDTH": 256, "HEIGHT": 128, "EXTERNAL_DARK_ENABLE": 0},
        "wall_timeout_seconds": WALL_TIMEOUT_SECONDS,
        "simulation_watchdog_ns": 2_000_000,
        "status": "FAIL",
    }
    stage = "hash before run"
    try:
        result["input_sha256_before"] = {str(path): sha256(path) for path in inputs}
        for stage, command in commands.items():
            run_logged(command, run_dir / f"{stage}.log", start + WALL_TIMEOUT_SECONDS)
        stage = "terminal marker"
        simulation = (run_dir / "simulate.log").read_text(errors="replace")
        pass_marker = "PASS_DEHAZE_TRANSITION full_frames=9 aborted_frames=2 groups_per_frame=8192"
        if simulation.count(pass_marker) != 1 or "FAIL_DEHAZE_TRANSITION" in simulation:
            raise RuntimeError("simulation failed or is missing its expected completion marker")
        result["terminal_marker"] = pass_marker
        result["status"] = "PASS"
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        result["failed_stage"] = stage
        if isinstance(error, subprocess.CalledProcessError):
            result["tool_exit_code"] = error.returncode
        else:
            result["error"] = str(error)
    finally:
        result["input_sha256_after"] = {str(path): sha256(path) for path in inputs if path.is_file()}
        if result.get("input_sha256_before") != result["input_sha256_after"]:
            result["status"] = "FAIL"
            result["input_identity_error"] = "inputs were unavailable or changed during the run"
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        (run_dir / "run.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    print(f'{result["status"]} {run_dir}')
    if result["status"] == "PASS":
        print(result["terminal_marker"])
    else:
        print(f'Failed stage {result.get("failed_stage", "input identity")}. See run.json and stage logs.')
    return int(result["status"] != "PASS")


if __name__ == "__main__":
    sys.exit(main())
