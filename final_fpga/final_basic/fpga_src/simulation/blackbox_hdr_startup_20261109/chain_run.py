"""Run the independent dual-eye HDR startup regression with ModelSim and TD models."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


BENCH = Path(__file__).resolve().with_name("chain_startup_tb.sv")
SRC = BENCH.parents[2]
RUNS = SRC.parent / "tmp" / "seed12fix_20261109"
BOARD_GATE_SHA = "9a8aaad1b7e59827c9afb0ddfd539bcbc3f78ca39002a1a0e2861f4c789fb2ae"
BOARD_COMMIT = "4a08ae35391e7b7ea6767260d7d1b4b182ef4bb9"
SOURCE_LIST = (
    "simulation/blackbox_hdr_startup_20261109/seed12_hdr_startup_carrier.v",
    "rtl/reset_release_sync.v",
    "rtl/imx415_sensor_config.v",
    "rtl/imx415_sensor_recipe.v",
    "rtl/imx415_mode_table.v",
    "rtl/imx415_hdr2_recipe_rom.v",
    "rtl/camera_i2c_write.v",
    "ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v",
    "rtl/real_hdr_event_cdc.v",
    "rtl/hdr_csi_boundary_adapter.v",
    "rtl/real_hdr_csi_word_core.v",
    "rtl/real_hdr_csi_dual_word_rx.v",
    "rtl/real_hdr_member_crop10.v",
    "rtl/raw_capture_fifo_eram_safe.v",
    "rtl/real_hdr_csi_capture_stream.v",
    "ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v",
)
MODEL_LIST = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
    "ph1/ph1_phy_gsr.v",
)
INCLUDE_DIRS = (
    SRC / "rtl/include/04_include",
    SRC / "ip/camera_packet_fifo_147x512/RTL/include",
)
PUBLIC_LINE = re.compile(
    r"^\s*(?:#\s*)?(?:\*\* Fatal:\s*)?"
    r"(CHAIN_(?:CFG_START|CONFIG|PREFIX|WARMUP|RAW|SOURCE|DRAIN|PASS|FAIL|FIXTURE_FAIL|WARMUP_LIVENESS_FAIL)\b.*)$"
)


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=("baseline", "candidate"), required=True)
    parser.add_argument("--run-id", required=True, help="new directory name beginning with chain-")
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"chain-[A-Za-z0-9][A-Za-z0-9_-]*", args.run_id):
        parser.error("expected a chain- run ID containing only letters, numbers, '-' and '_'")

    out = RUNS / args.run_id
    out.mkdir(parents=True, exist_ok=False)
    tool_bin = args.modelsim_bin.resolve()
    td_root = args.td_root.resolve()
    gate = SRC / "rtl/real_hdr_pair_cycle_gate.v"
    if args.variant == "baseline":
        gate = RUNS / "baseline/real_hdr_pair_cycle_gate.v"
    models = [td_root / "sim_release" / rel for rel in MODEL_LIST]
    work_sources = [SRC / rel for rel in SOURCE_LIST] + [gate, BENCH, models[-1]]

    started = time.monotonic()
    deadline = started + 85
    env = os.environ.copy()
    env.pop("MODELSIM", None)
    result = {
        "variant": args.variant,
        "board_commit": BOARD_COMMIT,
        "gate": str(gate),
        "modelsim_bin": str(tool_bin),
        "td_root": str(td_root),
        "workdir": str(out),
        "wall_clock_limit_s": 85,
        "simulator_limit_ms": 8,
        "commands": [],
        "public_events": [],
    }

    def run(tool, label, *arguments):
        argv = [str(tool_bin / f"{tool}.exe"), *map(str, arguments)]
        log = out / f"{label}.log"
        step = {"argv": argv, "log": log.name}
        result["commands"].append(step)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(f"wall-clock watchdog before {label}")
        with log.open("wb") as handle:
            proc = subprocess.run(
                argv,
                cwd=out,
                env=env,
                stdout=handle,
                stderr=subprocess.STDOUT,
                timeout=remaining,
                creationflags=subprocess.CREATE_NO_WINDOW,
                check=False,
            )
        step["exit_code"] = proc.returncode
        return proc.returncode

    def require(tool, label, *arguments):
        if run(tool, label, *arguments):
            raise RuntimeError(f"{label} failed. See {label}.log in {out}")

    try:
        includes = []
        for directory in INCLUDE_DIRS:
            if not directory.is_dir():
                raise FileNotFoundError(directory)
            includes.extend(sorted(path for path in directory.rglob("*") if path.is_file()))
        inputs = list(dict.fromkeys(work_sources + models + includes + [Path(__file__).resolve()]))
        result["input_sha256"] = {str(path): sha256(path) for path in inputs}
        if args.variant == "baseline" and result["input_sha256"][str(gate)] != BOARD_GATE_SHA:
            raise RuntimeError("baseline gate SHA-256 differs from the board-source contract")

        require("vsim", "version", "-version")
        result["modelsim_version"] = (out / "version.log").read_text(errors="replace").strip()
        require("vmap", "config", "-c")
        env["MODELSIM"] = str(out / "modelsim.ini")
        for library in ("ph1", "work"):
            require("vlib", f"vlib-{library}", library)
            require("vmap", f"vmap-{library}", library, library)
        require("vlog", "compile-models", "-work", "ph1", *models)
        require(
            "vlog", "compile-chain", "-sv", "-work", "work",
            *(f"+incdir+{directory}" for directory in INCLUDE_DIRS), *work_sources
        )
        exit_code = run(
            "vsim", "simulate", "-c", "-t", "1ps", "-onfinish", "stop",
            "-L", "ph1", "work.chain_startup_tb", "ph1.glbl",
            "-do", "onerror {quit -code 2 -f}; run 8 ms; quit -code 0 -f"
        )
        for line in (out / "simulate.log").read_text(errors="replace").splitlines():
            match = PUBLIC_LINE.match(line)
            if match:
                result["public_events"].append(match[1])

        markers = [line.split(maxsplit=1)[0] for line in result["public_events"]]
        if "CHAIN_WARMUP_LIVENESS_FAIL" in markers:
            result["outcome"] = "WARMUP_LIVENESS_FAIL"
        elif "CHAIN_FIXTURE_FAIL" in markers:
            result["outcome"] = "FIXTURE_FAIL"
        elif "CHAIN_FAIL" in markers:
            result["outcome"] = "SIMULATION_FAIL"
        elif exit_code == 0 and markers.count("CHAIN_PASS") == 1:
            result["outcome"] = "PASS"
        else:
            raise RuntimeError(f"simulation exited {exit_code} without a public terminal marker")

        if any(sha256(path) != result["input_sha256"][str(path)] for path in inputs):
            result["outcome"] = "INPUT_CHANGED"
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        result["outcome"] = "TOOL_OR_DEPENDENCY_FAILURE"
        result["detail"] = str(error)

    result["wall_elapsed_s"] = round(time.monotonic() - started, 3)
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for line in result["public_events"]:
        print(line)
    if "detail" in result:
        print(result["detail"], file=sys.stderr)
    print(f"{result['outcome']} {out / 'result.json'}")
    return 0 if result["outcome"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
