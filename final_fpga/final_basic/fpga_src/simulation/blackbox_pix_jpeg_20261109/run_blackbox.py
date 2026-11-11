"""Compile opaque DUTs and run bounded public-interface ModelSim cases."""

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import subprocess
from time import monotonic
from uuid import uuid4


HERE = Path(__file__).resolve().parent
ROOT = next(parent for parent in HERE.parents if (parent / "refactor/camera_raw_r2/AGENTS.md").is_file())
STAGE = ROOT / "refactor/camera_raw_r2"
DESIGN = STAGE / "src_fpga"
PIX_EXPERIMENT = STAGE / "experiments/timing_pix_20261109"
PUBLIC_JPEG = STAGE / "verification_reference/egress_public.md"

PIX_CASES = (
    "first_overlap", "stop_wrap", "peer_faults", "cohort", "stopped_reset", "deadline",
    "terminal_priority", "old_short_fault", "dual_cancel",
)
JPEG_CASES = (
    "two_frames", "reset_context", "reset_start", "reset_data", "reset_ext_head",
    "reset_ext_mid", "reset_ext_final", "reset_fence", "negative", "wrong_identity", "wrong_length",
    "wrong_cohort", "malformed_prefix_flit1", "malformed_stream_flit7",
)

JPEG_SOURCES = (
    "rtl/ordered_frame_egress.v",
    "rtl/ddr_extension_staging_ram.v",
    "rtl/lane_sparse_extension_checker.v",
    "rtl/td_sdp_ram40.v",
    "ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
    "rtl/reset_release_sync.v",
    "rtl/reset_release_sync_data.v",
    "rtl/ordered_frame_cdc.v",
    "rtl/ordered_frame_ingress.v",
    "rtl/ordered_frame_fifo_fence.v",
    "rtl/axis_frame_fifo_ip.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    "ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v",
)
JPEG_INCLUDES = (
    "rtl/include/01_include",
    "rtl/include/04_include",
    "ip/camera_packet_fifo_147x512/RTL/include",
)
JPEG_MODELS = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def emit_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_command(exe, args, out_dir, stem):
    argv = [str(exe), *(str(arg) for arg in args)]
    log = out_dir / f"{stem}.txt"
    command = {"argv": argv, "cwd": str(out_dir), "timeout_sec": 60, "stdout_stderr": log.name}
    emit_json(out_dir / f"{stem}.command.json", command)
    started = monotonic()
    with log.open("wb") as stream:
        try:
            completed = subprocess.run(argv, cwd=out_dir, stdout=stream, stderr=subprocess.STDOUT,
                                       timeout=60, check=False)
            command["exit_code"] = completed.returncode
        except subprocess.TimeoutExpired:
            command["exit_code"] = None
            command["status"] = "TIMEOUT"
        except OSError as error:
            stream.write(str(error).encode("utf-8"))
            command["exit_code"] = None
            command["status"] = "SPAWN_ERROR"
    command["elapsed_sec"] = round(monotonic() - started, 3)
    emit_json(out_dir / f"{stem}.command.json", command)
    return command


def compile_suite(opts, out_dir):
    simulator = opts.modelsim_bin.resolve()
    models_root = opts.td_root.resolve() / "sim_release"
    bench = HERE / ("tb_pix_gate.sv" if opts.suite == "pix" else "tb_jpeg_cdc.sv")
    ph1_models = []
    sibling_tops = []
    defines = []
    if opts.suite == "pix":
        manifest = PIX_EXPERIMENT / "OPAQUE_SOURCES.json"
        spec = json.loads(manifest.read_text(encoding="utf-8"))
        production = [ROOT / source for source in spec["sources"]]
        includes = [ROOT / directory for directory in spec["include_dirs"]]
        fingerprints = [manifest, PIX_EXPERIMENT / "IO_CONTRACT.md",
                        *(ROOT / header for header in spec["include_sha_inputs"])]
    else:
        production = [DESIGN / source for source in JPEG_SOURCES]
        includes = [DESIGN / directory for directory in JPEG_INCLUDES]
        ph1_models = [models_root / model for model in JPEG_MODELS]
        production.insert(0, models_root / "ph1/ph1_phy_gsr.v")
        sibling_tops = ["work.PH1_PHY_GSR", "ph1.glbl"]
        defines = ["+define+PH1"]
        fingerprints = [PUBLIC_JPEG, STAGE / "docs/timing_20261109/JPEG_RESET_PUBLIC.md",
                        ROOT / "docs/pcie_protocol_v1.json", STAGE / "docs/pcie_protocol_v1.json"]
        for include in includes:
            fingerprints.extend(sorted(include.glob("*.vh")))
    inputs = [Path(__file__).resolve(), bench, *production, *ph1_models, *fingerprints]
    emit_json(out_dir / "inputs.json", {"suite": opts.suite, "modelsim_bin": str(simulator),
              "td_root": str(opts.td_root.resolve()), "sha256": {str(path): digest(path) for path in inputs}})

    build = [
        ("vsim", ["-version"], "tool_version"),
        ("vmap", ["-c"], "ini"),
        ("vlib", ["work"], "work_library"),
    ]
    include_args = [f"+incdir+{directory.as_posix()}" for directory in includes]
    if ph1_models:
        build.extend([
            ("vlib", ["ph1"], "ph1_library"),
            ("vmap", ["ph1", "ph1"], "ph1_map"),
            ("vlog", ["-work", "ph1", *defines, *ph1_models], "compile_models"),
        ])
    build.extend([
        ("vlog", ["-work", "work", *defines, *include_args, *production], "compile_design"),
        ("vlog", ["-sv", "-work", "work", bench], "compile_tb"),
    ])
    for program, args, label in build:
        command = run_command(simulator / f"{program}.exe", args, out_dir, label)
        if command["exit_code"] != 0:
            print(f"BUILD_FAIL phase={label} evidence={out_dir / command['stdout_stderr']}")
            return None
    after_hashes = {str(path): digest(path) for path in inputs}
    if json.loads((out_dir / "inputs.json").read_text(encoding="utf-8"))["sha256"] != after_hashes:
        emit_json(out_dir / "inputs_after_changed.json", after_hashes)
        print(f"BUILD_FAIL input changed during build evidence={out_dir}")
        return None
    return bench.stem, sibling_tops


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=["pix", "jpeg"])
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--case", action="append")
    opts = parser.parse_args()
    allowed = PIX_CASES if opts.suite == "pix" else JPEG_CASES
    cases = opts.case or allowed
    if unexpected := (set(cases) - set(allowed)):
        parser.error(f"unknown case(s) {sorted(unexpected)}")
    if len(cases) != len(set(cases)):
        parser.error("duplicate case")
    key = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_dir = ROOT / "work/exp/blackbox_pix_jpeg_20261109" / f"{key}_{opts.suite}_{uuid4().hex[:6]}"
    out_dir.mkdir(parents=True)
    print(f"EVIDENCE {out_dir}", flush=True)
    compiled = compile_suite(opts, out_dir)
    if compiled is None:
        return 2
    top, sibling_tops = compiled
    report = []
    for case in cases:
        library = ["-L", "ph1"] if sibling_tops else []
        args = ["-c", "-onfinish", "exit", "-wlf", f"{case}.wlf", *library,
                *sibling_tops, f"work.{top}", f"+CASE={case}", "-do", "run -all; quit -code 3"]
        command = run_command(opts.modelsim_bin.resolve() / "vsim.exe", args, out_dir, case)
        log = (out_dir / command["stdout_stderr"]).read_text(encoding="utf-8", errors="replace")
        markers = [line.lstrip("# ") for line in log.splitlines()
                   if line.lstrip("# ").startswith(f"BLACKBOX_PASS case={case} ")]
        passed = command["exit_code"] == 0 and len(markers) == 1
        entry = {"case": case, "status": "PASS" if passed else "FAIL", **command}
        entry["status"] = "PASS" if passed else command.get("status", "FAIL")
        if markers:
            entry["markers"] = markers
        report.append(entry)
        print(f"{entry['status']} {case} {command['elapsed_sec']:.3f}s", flush=True)
    emit_json(out_dir / "results.json", report)
    return 0 if all(entry["status"] == "PASS" for entry in report) else 1


if __name__ == "__main__":
    raise SystemExit(main())
