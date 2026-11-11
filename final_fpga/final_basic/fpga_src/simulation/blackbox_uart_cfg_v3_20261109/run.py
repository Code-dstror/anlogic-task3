"""Run the public-page UART simulation and offline decoder checks."""

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
ARTIFACT_ROOT = R2_ROOT / "tmp" / HERE.name
TOP = "tb_uart_cfg_v3"
WALL_TIMEOUT_SECONDS = 60


def input_hashes(paths):
    result = {}
    for path in paths:
        with path.open("rb") as source:
            result[str(path)] = hashlib.file_digest(source, "sha256").hexdigest()
    return result


def run_logged(command, log_path, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError("wall-clock deadline expired")
    with log_path.open("wb") as log:
        subprocess.run(
            command, cwd=log_path.parent, stdout=log, stderr=subprocess.STDOUT,
            check=True, timeout=remaining,
        )


def check_gate(commands, run_dir, deadline, marker, fail_marker):
    for stage, command in commands.items():
        log_path = run_dir / f"{stage}.log"
        try:
            run_logged(command, log_path, deadline)
        except (OSError, subprocess.SubprocessError) as error:
            return {"status": "FAIL", "stage": stage, "error": str(error)}
    last_log = log_path.read_text(errors="replace")
    completed = re.findall(marker, last_log, re.MULTILINE)
    if len(completed) != 1 or fail_marker in last_log:
        return {"status": "FAIL", "stage": stage, "error": "expected one successful completion marker"}
    return {"status": "PASS", "terminal_marker": completed[0]}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--modelsim-bin", required=True, type=Path)
    cli.add_argument("--run-name", required=True)
    args = cli.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", args.run_name):
        cli.error("--run-name must start with an alphanumeric and use only alphanumerics, '_' or '-'")

    run_dir = ARTIFACT_ROOT / args.run_name
    run_dir.mkdir(parents=True, exist_ok=False)
    rtl_dir = R2_ROOT / "src_fpga" / "rtl"
    rtl = [rtl_dir / name for name in (
        "camera_field_diagnostics.v", "uart_status_observer.v",
        "uart_observer_snapshot.v", "cfg_diag_snapshot.v",
    )]
    bench = HERE / f"{TOP}.sv"
    parser = R2_ROOT / "tools" / "uart_observer.py"
    parser_check = HERE / "check_decoder.py"
    public_docs = R2_ROOT / "docs" / "fieldfix_20261109"
    inputs = [
        *rtl, bench, parser, parser_check, Path(__file__).resolve(),
        public_docs / "UART_FIELD_V3.md", public_docs / "UART_PORTS.txt", public_docs / "FIELD_PORTS.txt",
        R2_ROOT / "docs" / "fieldfix_20261108" / "UART_FIELD_V2.md",
    ]
    bin_dir = args.modelsim_bin.resolve()
    simulation = {
        "version": [str(bin_dir / "vsim.exe"), "-version"],
        "vlib": [str(bin_dir / "vlib.exe"), "work"],
        "compile": [str(bin_dir / "vlog.exe"), "-sv", "-work", "work", *(str(path) for path in rtl), str(bench)],
        "simulate": [
            str(bin_dir / "vsim.exe"), "-c", "-onfinish", "stop", f"work.{TOP}",
            "-do", "onerror {quit -code 1}; run -all; quit -code 0",
        ],
    }
    decode = {"decode": [sys.executable, "-I", "-B", str(parser_check), str(parser)]}

    start = time.monotonic()
    deadline = start + WALL_TIMEOUT_SECONDS
    result = {
        "cwd": str(run_dir),
        "runner_argv": sys.orig_argv,
        "commands": {"simulation": simulation, "decoder": decode},
        "profile": {
            "clock_period_ns": {"sys": 10, "dfi": 14, "pix": 22, "user": 18},
            "UART_DIV": 4, "REPORT_INTERVAL_CYCLES": 64, "SNAPSHOT_TIMEOUT_CYCLES": 128,
            "CFG_DIAG_ENABLE": 1, "CFG_FRAME_VERSION": 3, "JOB_PAGE_ENABLE": 1,
            "JOB_SYS_CONFIG_ENABLE": 1, "RX_DIAG_ENABLE": 0, "RX_TRACE_ENABLE": 0,
        },
        "wall_timeout_seconds": WALL_TIMEOUT_SECONDS,
        "simulation_watchdog_ns": 2_000_000,
        "input_sha256_before": input_hashes(inputs),
    }
    result["simulation"] = check_gate(
        simulation, run_dir, deadline, r"^# (PASS_UART_CFG_V3 phases=8 packet_pairs=\d+)$",
        "FAIL_UART_CFG_V3",
    )
    result["decoder"] = check_gate(
        decode, run_dir, deadline, r"^(PASS_UART_PARSER versions=1,2,3 crc_errors=1 invalid_headers=1)$",
        "FAIL_UART_PARSER",
    )
    result["input_sha256_after"] = input_hashes(inputs)
    result["inputs_stable"] = result["input_sha256_before"] == result["input_sha256_after"]
    passed = result["inputs_stable"] and all(
        result[gate]["status"] == "PASS" for gate in ("simulation", "decoder")
    )
    result["status"] = "PASS" if passed else "FAIL"
    result["elapsed_seconds"] = round(time.monotonic() - start, 3)
    (run_dir / "run.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    print(f'{result["status"]} {run_dir}')
    for gate in ("simulation", "decoder"):
        gate_result = result[gate]
        if gate_result["status"] == "PASS":
            print(gate_result["terminal_marker"])
        else:
            print(f'{gate} failed at {gate_result["stage"]}. See run.json and stage log.')
    return int(not passed)


if __name__ == "__main__":
    sys.exit(main())
