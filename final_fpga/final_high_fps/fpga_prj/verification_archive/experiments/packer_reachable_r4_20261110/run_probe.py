"""Freeze and map the reachable-state packer variants."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import sys


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
NATIVE = PROJECT.parent / "camera_rate_r1/experiments/uhd_resources"
sys.path[:0] = [str(HERE.parent / "reset_data_qual_r2_20261110"), str(NATIVE)]
from prepare_inputs import BASE_COMMIT, frozen_rtl, write_exact
from run import digest, run_native


RUN_ROOT = PROJECT / "tmp/packer_reachable_r4_20261110"
LEAF = "jpeg_byte_packer.v"
TIMING = (
    "uhd_probe_Runs/syn_1/uhd_probe_gate.timing", "reopened.timing", "objects.txt",
    "input_to_data.timing", "input_to_count.timing", "byte_to_data.timing",
    "count_to_data.timing", "count_to_count.timing",
)


def candidate_source(source):
    original = source.decode("utf-8")
    compact_out = (
        "            if (byte_count > 5'd16) begin\n"
        "                next_byte_data  = 128'd0;\n"
        "                next_byte_count = byte_count - 5'd16;\n"
        "            end else begin\n"
        "                next_byte_data  = 128'd0;\n"
        "                next_byte_count = 5'd0;\n"
        "            end\n"
    )
    compact_drain = (
        "                    if (byte_count > 5'd16) begin\n"
        "                        byte_data   <= 128'd0;\n"
        "                        byte_count  <= byte_count - 5'd16;\n"
        "                        drain_error <= 1'b1;\n"
        "                    end else begin\n"
        "                        byte_data   <= 128'd0;\n"
        "                        byte_count  <= 5'd0;\n"
        "                        drain_error <= 1'b0;\n"
        "                    end\n"
    )
    if original.count(compact_out) != 1 or original.count(compact_drain) != 1:
        raise ValueError("Expected exactly two unreachable branches in the frozen packer")
    return original.replace(
        compact_out, "            next_byte_data  = 128'd0;\n"
        "            next_byte_count = 5'd0;\n",
    ).replace(
        compact_drain, "                    byte_data   <= 128'd0;\n"
        "                    byte_count  <= 5'd0;\n"
        "                    drain_error <= 1'b0;\n",
    ).encode("utf-8")


def prepare_inputs():
    baseline = frozen_rtl((LEAF,))[LEAF]
    inputs = RUN_ROOT / "inputs"
    sources = {}
    for variant, data in (("baseline", baseline), ("candidate", candidate_source(baseline))):
        path = inputs / variant / LEAF
        write_exact(path, data)
        sources[variant] = [{"path": path.relative_to(PROJECT).as_posix(), "sha256": sha256(data).hexdigest()}]
    manifest = {
        "schema": 1, "project_root": "refactor/camera_fusion_r1", "baseline_commit": BASE_COMMIT,
        "dut": "jpeg_byte_packer", "compile_mode": "Verilog", "td_simulation_model_dependencies": [],
        "legal_test_max_payload_bytes": [17, 31], "variants": sources,
    }
    write_exact(HERE / "OPAQUE_SOURCES.json", (json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    declaration = baseline.decode("utf-8").split("module jpeg_byte_packer", 1)[1].split("\n);", 1)[0]
    write_exact(HERE / "PORTS.vh", (
        "// Public declaration only. Compile the opaque source instead.\n"
        "module jpeg_byte_packer" + declaration + "\n);\n"
    ).encode("utf-8"))
    return inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--variant", required=True, choices=("baseline", "candidate"))
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("use a fresh ASCII run name")
    inputs = prepare_inputs()
    if args.prepare_only:
        print(inputs)
        return 0
    work = RUN_ROOT / args.name / args.variant
    work.mkdir(parents=True)
    shutil.copyfile(inputs / args.variant / LEAF, work / LEAF)
    shutil.copyfile(HERE / "probe.v", work / "uhd_probe.v")
    for name in ("synth.tcl", "clock.sdc"):
        shutil.copyfile(HERE / name, work / name)
    evidence = {
        "baseline_commit": BASE_COMMIT, "variant": args.variant, "target": "packer_reachable_count",
        "runner_sha256": digest(Path(__file__)), "native_runner_sha256": digest(NATIVE / "run.py"),
        "functional_simulation": "NOT_RUN", "whole_design_synthesis": "NOT_RUN", "physical_sta": "NOT_RUN",
        "place_route": "NOT_RUN", "bitgen": "NOT_RUN", "board": "NOT_RUN",
    }
    return 0 if run_native(work, args.td_root.resolve(), evidence, 80, TIMING) else 1


if __name__ == "__main__":
    sys.exit(main())
