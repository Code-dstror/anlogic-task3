"""Run the independent CFG/CAM1 tests with a fresh library and bounded runtime."""

import argparse
import hashlib
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
RTL = PROJECT / "src_fpga" / "rtl"
IP = PROJECT / "src_fpga" / "ip"
SEED = REPO / "tmp" / "fieldfix_20261108" / "config_seed92"
CASES = ("cfg-positive", "cfg-fault", "cfg-same-edge",
         "cam-training", "cam-nack", "cam-lock")
CFG_RTL = (
    "td_sdp_ram40.v", "reset_release_sync.v", "control_fifo_40x512.v",
    "control_message_fifo_ip.v", "mono_config_byte_store_v2.v",
    "mono_config_legacy_scan_v1.v", "mono_config_scan_v2.v", "mono_config_bar_v2.v",
    "mono_config_engine_v2.v", "mono_config_service_v2.v",
)
CAM_RTL = (
    "reset_release_sync.v", "camera_i2c_write.v", "imx415_mode_table.v",
    "imx415_hdr2_recipe_rom.v", "imx415_sensor_recipe.v", "imx415_sensor_config.v",
    "csi_rx_word_align_observed.v", "csi_clock_watchdog.v", "csi2_async_event_fifo.v",
    "physical_csi_word_core.v", "physical_csi_rx_stream.v", "physical_camera_crop.v",
    "raw_capture_fifo_eram_safe.v", "hdr_csi_boundary_adapter.v",
    "real_hdr_sensor_clock_mux.v", "real_hdr_event_cdc.v", "real_hdr_csi_word_core.v",
    "real_hdr_csi_dual_word_rx.v", "real_hdr_member_crop10.v",
    "real_hdr_csi_capture_stream.v", "real_hdr_physical_csi_rx.v",
    "sdr_camera_raw_frontend.v",
)
INCLUDES = ("00_rtl", "01_include", "02_jpeg", "03_mono_config_v2_20261015", "04_include")
TD_MODELS = (
    "common/al_phy_glbl.v", "ph1/ph1_logic_eram.v", "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v", "ph1/ph1_phy_eram.v", "ph1/ph1_phy_fifoctrl.v",
)


def fifo_files(name):
    return [IP / name / "RTL" / f"{name}_soft_fifo_core.v",
            IP / name / "RTL" / f"{name}_soft_fifo.v", IP / name / f"{name}.v"]


def input_lists(td_root, suite, variant):
    sim_release = td_root / "sim_release"
    includes = [RTL / "include" / name for name in INCLUDES]
    models = [sim_release / path for path in TD_MODELS]
    defines = ["+define+PH1", "+define+C15_F23_FULLHEIGHT_PROFILE=1"]
    if suite == "cfg":
        rtl_files = [
            (SEED if variant == "seed92" and path in CFG_RTL[-2:] else RTL) / path
            for path in CFG_RTL
        ]
        if variant == "seed92":
            defines.append("+define+SEED92_CFG")
        rtl_files += [IP / "ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v"]
        rtl_files += fifo_files("camera_control_fifo_40x512")
    else:
        if variant == "seed92":
            includes.insert(0, SEED)
        models += [sim_release / "ph1/ph1_phy_gclk_v2.v"]
        rtl_files = [RTL / path for path in CAM_RTL]
        rtl_files += [
            HERE.parent / "camera1/word_phy_boundary.sv",
            IP / "vendor/anlogic_camera/sensor/ui_imx415_reg.v",
            IP / "vendor/anlogic_camera/phy/csi_rx_word_gear_box.v",
        ]
        rtl_files += fifo_files("camera_event_fifo_47x512")
        rtl_files += fifo_files("camera_packet_fifo_147x512")
    top = f"tb_{suite}_field"
    design = [sim_release / "ph1/ph1_phy_gsr.v", *rtl_files, HERE / f"{top}.sv"]
    return top, defines, includes, models, design


def hash_paths(paths):
    hashes = {}
    for path in dict.fromkeys(paths):
        with path.open("rb") as data:
            hashes[path.as_posix()] = hashlib.file_digest(data, "sha256").hexdigest()
    return hashes


def run_case(args, case):
    suite = case.split("-", 1)[0]
    top, defines, includes, models, design = input_lists(args.td_root, suite, args.variant)
    run_dir = args.run_root / f"{args.variant}-{case}"
    run_dir.mkdir()
    started = time.monotonic()
    deadline = started + args.wall_seconds
    manifest_path = run_dir / "manifest.json"
    manifest = {
        "case": case, "variant": args.variant, "suite": suite,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "td_root": args.td_root.as_posix(), "modelsim_bin": args.modelsim_bin.as_posix(),
        "wall_watchdog_s": args.wall_seconds, "cwd": run_dir.as_posix(),
        "include_search_order": [path.as_posix() for path in includes], "commands": [],
    }

    def write_manifest():
        manifest["elapsed_s"] = round(time.monotonic() - started, 3)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    def run_stage(stage, tool, *argv):
        command = [str(args.modelsim_bin / f"{tool}.exe"), *map(str, argv)]
        stage_result = {"stage": stage, "argv": command, "log": f"{stage}.log"}
        manifest["commands"].append(stage_result)
        write_manifest()
        try:
            with (run_dir / stage_result["log"]).open("wb") as output:
                result = subprocess.run(
                    command, cwd=run_dir, stdout=output, stderr=subprocess.STDOUT,
                    timeout=max(0.1, deadline - time.monotonic()),
                )
        except subprocess.TimeoutExpired:
            stage_result["status"] = "WALL_TIMEOUT"
            return False
        except OSError as error:
            stage_result.update(status="TOOL_ERROR", detail=str(error))
            return False
        stage_result.update(exit_code=result.returncode,
                            status="PASS" if result.returncode == 0 else "FAIL")
        return result.returncode == 0

    try:
        for path in includes:
            if not path.is_dir():
                raise FileNotFoundError(f"include directory: {path}")
        include_inputs = [
            candidate for path in includes for candidate in sorted(path.rglob("*"))
            if candidate.is_file() and candidate.suffix.lower() in (".v", ".sv", ".vh", ".svh", ".mem")
        ]
        input_paths = [Path(__file__), REPO / "docs/pcie_protocol_v1.json",
                       REPO / "docs/s01_config_transaction.md", *models, *design, *include_inputs]
        manifest["input_sha256"] = hash_paths(input_paths)
    except OSError as error:
        manifest.update(status="BLOCKED_INPUT", detail=str(error))
        write_manifest()
        print(f"{args.variant} {case}: BLOCKED_INPUT {error}", flush=True)
        return False
    write_manifest()

    stages = [
        ("version", "vsim", "-version"),
        ("modelsimini", "vmap", "-c"),
        ("worklib", "vlib", "work"),
        ("ph1lib", "vlib", "ph1"),
        ("ph1map", "vmap", "ph1", "ph1"),
        ("compile_ph1", "vlog", "-work", "ph1", *models),
        ("compile_dut_tb", "vlog", "-sv", "-work", "work", "-L", "ph1", *defines,
         *(f"+incdir+{path.as_posix()}" for path in includes), *design),
        ("simulate", "vsim", "-c", "-L", "ph1", "-onfinish", "exit",
         "work.PH1_PHY_GSR", "ph1.glbl", f"work.{top}", f"+CASE={case}",
         "-do", "onerror {quit -code 2 -f}; run -all; quit -code 3 -f"),
    ]
    for stage, tool, *argv in stages:
        if not run_stage(stage, tool, *argv):
            manifest["status"] = (
                "SIM_NONZERO" if stage == "simulate" else "BLOCKED_" + stage.upper()
            )
            break
    else:
        manifest["status"] = "NO_PASS_MARKER"

    if (run_dir / "simulate.log").exists():
        # Only display markers authored in these benches, never RTL/model diagnostics.
        sim = (run_dir / "simulate.log").read_text(encoding="utf-8", errors="replace")
        markers = re.findall(r"(?m)^\s*#?\s*(BB_(?:CHECK|PASS|FAIL) [^\r\n]+)", sim)
        manifest["markers"] = markers
        for marker in markers:
            print(f"{args.variant} {marker}", flush=True)
        if any(marker.startswith("BB_FAIL ") for marker in markers):
            manifest["status"] = "FAIL"
        elif manifest["status"] == "NO_PASS_MARKER" and f"BB_PASS {suite} {case}" in markers:
            manifest["status"] = "PASS"

    if hash_paths(input_paths) != manifest["input_sha256"]:
        manifest["status"] = "STALE_INPUT_CHANGED_DURING_RUN"
    write_manifest()
    print(f"{args.variant} {case}: {manifest['status']} ({manifest['elapsed_s']}s) {run_dir}",
          flush=True)
    return manifest["status"] == "PASS"


def main():
    global SEED
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--run-root", type=Path, required=True, help="new output directory")
    parser.add_argument("--variant", choices=("current", "seed92"), default="current")
    parser.add_argument("--case", choices=CASES, action="append", required=True)
    parser.add_argument("--wall-seconds", type=int, default=55, choices=range(1, 60),
                        metavar="1..59")
    args = parser.parse_args()
    for name in ("td_root", "modelsim_bin", "run_root"):
        setattr(args, name, getattr(args, name).resolve())
    args.run_root.mkdir(parents=True)
    if args.variant == "seed92":
        # Fixed Git bytes are opaque compiler inputs, not an ignored tmp dependency.
        SEED = args.run_root / "seed92_inputs"
        SEED.mkdir()
        for name in ("mono_config_engine_v2.v", "mono_config_service_v2.v",
                     "include/04_include/camera_physical_capture.vh"):
            body = subprocess.check_output([
                "git", "show", "81404aec1727e16f3df7424a74c5f960ad3d6683:"
                "refactor/camera_raw_r1/src_fpga/rtl/" + name], cwd=REPO)
            (SEED / Path(name).name).write_bytes(body)
    statuses = [run_case(args, case) for case in dict.fromkeys(args.case)]
    return 0 if all(statuses) else 1


if __name__ == "__main__":
    raise SystemExit(main())
