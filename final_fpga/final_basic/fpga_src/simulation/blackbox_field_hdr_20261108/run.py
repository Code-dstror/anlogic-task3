"""Compile opaque HDR inputs and run bounded, independent public-port tests."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


REPO = Path(__file__).resolve().parents[5]
DESIGN = Path("refactor/camera_raw_r1/src_fpga")
FROZEN_COMMIT = "81404aec1727e16f3df7424a74c5f960ad3d6683"
INCLUDE = DESIGN / "rtl/include/04_include"
RTL = [
    DESIGN / "ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
    DESIGN / "rtl/td_sdp_ram40.v",
    DESIGN / "rtl/hdr_pair_directory.v",
    DESIGN / "rtl/hdr_eye_shared.v",
]
HEADERS = [INCLUDE / name for name in (
    "analysis_config_transport.vh", "camera_physical_capture.vh", "pcie_protocol_v1.vh"
)]
GATE_INCLUDE = DESIGN / "rtl/include/00_rtl"
GATE_RTL = DESIGN / "rtl/real_hdr_pair_cycle_gate.v"
GATE_HEADERS = [GATE_INCLUDE / name for name in (
    "mono_config_transport_v2.vh", "raw_video_v1.vh", "stereo_control_v1.vh"
)] + [INCLUDE / "pcie_protocol_v1.vh"]
LIBRARY_MODELS = [
    "sim_release/common/al_phy_glbl.v",
    "sim_release/ph1/ph1_logic_dram.v",
    "sim_release/ph1/ph1_logic_eram.v",
    "sim_release/ph1/ph1_phy_eram.v",
]
GSR_MODEL = "sim_release/ph1/ph1_phy_gsr.v"
WALL_TIMEOUT_SECONDS = 48
TERMINAL = re.compile(r"^#\s*HDR_BLACKBOX (PASS|FAIL) case=(\w+)(?:\s|$)", re.MULTILINE)


def sha256(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def snapshot(profile, run_dir, sources, testbench):
    inputs = {}
    for relative in sources:
        copy = run_dir / "inputs" / relative
        copy.parent.mkdir(parents=True, exist_ok=True)
        if profile == "baseline":
            with copy.open("wb") as handle:
                subprocess.run(
                    ["git", "show", f"{FROZEN_COMMIT}:{relative.as_posix()}"],
                    cwd=REPO, stdout=handle, check=True, timeout=10,
                )
            origin = f"{FROZEN_COMMIT}:{relative.as_posix()}"
        else:
            source = REPO / relative
            before = sha256(source)
            shutil.copyfile(source, copy)
            if before != sha256(copy) or before != sha256(source):
                raise RuntimeError(f"Changed during snapshot: {relative}")
            origin = str(source)
        inputs[copy] = origin
    testbench_copy = run_dir / "inputs" / testbench.name
    shutil.copyfile(testbench, testbench_copy)
    inputs[testbench_copy] = str(testbench)
    return inputs, testbench_copy


def run(argv, log_name, run_dir, commands):
    command = {
        "argv": [str(arg) for arg in argv],
        "cwd": str(run_dir),
        "log": log_name,
        "timeout_seconds": WALL_TIMEOUT_SECONDS,
    }
    commands.append(command)
    started = time.monotonic()
    with (run_dir / log_name).open("wb") as log:
        with subprocess.Popen(command["argv"], cwd=run_dir, stdout=log,
                              stderr=subprocess.STDOUT) as process:
            try:
                command["returncode"] = process.wait(timeout=WALL_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                command["timed_out"] = True
                subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                               stdout=log, stderr=subprocess.STDOUT, timeout=5, check=False)
                if process.poll() is None:
                    process.kill()
    command["elapsed_seconds"] = round(time.monotonic() - started, 3)
    return command


def compile_inputs(bin_dir, td_root, run_dir, tb, commands, target):
    src = run_dir / "inputs"
    compile_steps = [
        ([bin_dir / "vsim.exe", "-version"], "00_version.log"),
        ([bin_dir / "vlib.exe", "work"], "01_vlib_work.log"),
    ]
    if target == "owner":
        compile_steps.extend([
            ([bin_dir / "vlib.exe", "ph1"], "02_vlib_ph1.log"),
            ([bin_dir / "vlog.exe", "-work", "ph1", *(td_root / f for f in LIBRARY_MODELS)],
             "03_vlog_ph1.log"),
            ([bin_dir / "vlog.exe", "-sv", "+define+PH1", f"+incdir+{src / INCLUDE}",
              td_root / GSR_MODEL, *(src / f for f in RTL), tb], "04_vlog_work.log"),
        ])
    else:
        compile_steps.append(
            ([bin_dir / "vlog.exe", "-sv", f"+incdir+{src / GATE_INCLUDE}",
              f"+incdir+{src / INCLUDE}", src / GATE_RTL, tb],
             "04_vlog_work.log")
        )
    for argv, log_name in compile_steps:
        command = run(argv, log_name, run_dir, commands)
        if command.get("returncode") != 0:
            raise RuntimeError(f"Compile/tool error: {log_name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("baseline", "candidate"), required=True)
    parser.add_argument("--target", choices=("owner", "cycle_gate"), default="owner")
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("cases", nargs="+")
    args = parser.parse_args()
    if any(not re.fullmatch(r"[a-z0-9_]+", case) for case in args.cases):
        parser.error("Case names use only lower-case letters, digits and underscores.")
    if len(set(args.cases)) != len(args.cases):
        parser.error("Case names must be unique within a run directory.")

    run_dir = args.run_dir.resolve()
    run_dir.mkdir(parents=True)
    td_root = args.td_root.resolve()
    bin_dir = args.modelsim_bin.resolve()
    if args.target == "owner":
        sources = RTL + HEADERS
        bench_module = "tb_field_hdr"
        parameters = {"WIDTH": 16, "HEIGHT": 4, "cfg_ratio": 4, "cfg_hdr": 1,
                      "cfg_delta": 50_000_000, "cfg_wait": 100_000_000,
                      "cfg_age": 1_000_000_000}
        simulation_targets = ["-L", "ph1", "work.PH1_PHY_GSR", f"work.{bench_module}"]
    else:
        sources = [GATE_RTL, *GATE_HEADERS]
        bench_module = "tb_field_hdr_gate"
        parameters = {"TIMEOUT_CYCLES": 64, "EXTERNAL_PHASE_ENABLE": 1}
        simulation_targets = [f"work.{bench_module}"]
    testbench = Path(__file__).with_name(f"{bench_module}.sv")
    manifest = {
        "runner_argv": sys.orig_argv,
        "runner_sha256": sha256(Path(__file__)),
        "profile": args.profile,
        "target": args.target,
        "td_root": str(td_root),
        "modelsim_bin": str(bin_dir),
        "parameters": parameters,
        "commands": [],
        "cases": {},
        "inputs": {},
    }
    status = 0
    try:
        inputs, tb = snapshot(args.profile, run_dir, sources, testbench)
        if args.target == "owner":
            inputs.update({td_root / f: str(td_root / f) for f in LIBRARY_MODELS + [GSR_MODEL]})
        for path, origin in inputs.items():
            manifest["inputs"][str(path)] = {"origin": origin, "before_sha256": sha256(path)}
        compile_inputs(bin_dir, td_root, run_dir, tb, manifest["commands"], args.target)
        for case in args.cases:
            log_name = f"case_{case}.log"
            argv = [bin_dir / "vsim.exe", "-c", "-t", "1ps", *simulation_targets, f"+CASE={case}",
                    "-do", "onerror {quit -f -code 2}; run -all; quit -f"]
            command = run(argv, log_name, run_dir, manifest["commands"])
            log = (run_dir / log_name).read_text(encoding="utf-8", errors="replace")
            markers = TERMINAL.findall(log)
            if command.get("timed_out"):
                result = "TOOL_TIMEOUT"
            elif markers == [("PASS", case)] and command.get("returncode") == 0:
                result = "PASS"
            elif markers == [("FAIL", case)]:
                result = "FAIL"
            else:
                result = "TOOL_ERROR"
            manifest["cases"][case] = {"result": result, "log": log_name}
            print(f"{args.profile} {case} {result} {command['elapsed_seconds']:.3f}s")
            if result != "PASS":
                status = 1
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        manifest["error"] = str(error)
        print(str(error), file=sys.stderr)
        status = 2
    finally:
        for path, info in manifest["inputs"].items():
            info["after_sha256"] = sha256(Path(path)) if Path(path).is_file() else None
            if info["before_sha256"] != info["after_sha256"]:
                status = 2
        (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n",
                                               encoding="utf-8")
    return status


if __name__ == "__main__":
    sys.exit(main())
