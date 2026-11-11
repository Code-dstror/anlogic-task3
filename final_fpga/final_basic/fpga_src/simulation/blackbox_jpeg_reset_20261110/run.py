"""Compile the public ordered-frame closure and compare independent A/B short runs."""

from argparse import ArgumentParser
from datetime import datetime, timezone
from hashlib import sha256
from itertools import zip_longest
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


BASELINE = "41cb5991a1b03cbbc7dfec60fe4dc1a9fdb91213"
DESIGN = Path(__file__).resolve().parents[2]
CASES = {
    1: "first_terminal_and_fence",
    2: "third_rising_edge_stretch_and_stopped_low_release",
    3: "sink_reset_with_source_stopped_high_and_borrowed_extension",
    4: "source_reset_with_sink_stopped_low_and_held_e2_result",
    5: "e2_terminal_and_same_cohort_recovery",
}
INCLUDES = (
    "rtl/include/01_include",
    "rtl/include/04_include",
    "ip/camera_packet_fifo_147x512/RTL/include",
)
DESIGN_FILES = (
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
BASELINE_REPLACEMENTS = {"ordered_frame_cdc.v", "ordered_frame_ingress.v"}
MODELS = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
)
PASS_LINE = re.compile(r"^(?:#\s*)?(BLACKBOX_PASS case=\d+ .+)$", re.MULTILINE)
EDGE_LINE = re.compile(r"^(?:#\s*)?(EDGE case=\d+ .+)$", re.MULTILINE)
FAIL_LINE = re.compile(r"\bTB_FAIL case=\d+ .*", re.MULTILINE)


def digest(path):
    with path.open("rb") as stream:
        return sha256(stream.read()).hexdigest()


def hashes(paths):
    return {path.as_posix(): digest(path) for path in dict.fromkeys(paths)}


def run_command(directory, logs, deadline, name, command):
    log = directory / f"{name}.log"
    started = time.monotonic()
    environment = os.environ.copy()
    environment.pop("MODELSIM", None)  # Per-variant library map in this run directory.
    with log.open("w", encoding="utf-8") as stream:
        try:
            if started >= deadline:
                raise subprocess.TimeoutExpired(command, 0)
            process = subprocess.run(
                [str(argument) for argument in command], cwd=directory, env=environment,
                stdout=stream, stderr=subprocess.STDOUT,
                timeout=deadline - started, check=False,
            )
            code, status = process.returncode, "PASS" if process.returncode == 0 else "FAIL"
        except subprocess.TimeoutExpired:
            code, status = None, "WALL_TIMEOUT"
        except OSError as error:
            stream.write(f"{error}\n")
            code, status = None, "TOOL_ERROR"
    record = {
        "argv": [str(argument) for argument in command], "cwd": directory.as_posix(),
        "log": log.as_posix(), "exit_code": code, "status": status,
        "seconds": round(time.monotonic() - started, 3),
    }
    logs.append(record)
    print(f"{directory.name}/{name} {status} ({record['seconds']} s) {log}", flush=True)
    return record


def run_variant(directory, files, common, cases, deadline):
    directory.mkdir()
    tools, models, gsr, include_dirs, bench = common
    logs = []
    records = {"commands": logs, "design_sha256": hashes(files), "cases": {}}
    for name, command in (
        ("copy_ini", [tools["vmap"], "-c"]),
        ("vlib_work", [tools["vlib"], "work"]),
        ("vlib_ph1", [tools["vlib"], "ph1"]),
        ("vmap_work", [tools["vmap"], "work", "work"]),
        ("vmap_ph1", [tools["vmap"], "ph1", "ph1"]),
        ("compile_models", [tools["vlog"], "-work", "ph1", "+define+PH1", *models]),
        ("compile_design", [tools["vlog"], "-work", "work", "+define+PH1",
                            *(f"+incdir+{path.as_posix()}" for path in include_dirs), gsr, *files]),
        ("compile_tb", [tools["vlog"], "-work", "work", "-sv", bench]),
    ):
        if run_command(directory, logs, deadline, name, command)["status"] != "PASS":
            records["status"] = "BLOCKED_COMPILE_OR_TOOL"
            return records
    records["modelsim_ini_sha256"] = digest(directory / "modelsim.ini")

    for case in cases:
        command = [
            tools["vsim"], "-c", "-onfinish", "stop", "-L", "ph1", "work.PH1_PHY_GSR",
            "ph1.glbl", "work.tb_jpeg_reset", f"+CASE={case}",
            "-do", "onerror {quit -code 1 -f}; run -all; quit -f",
        ]
        result = run_command(directory, logs, deadline, f"case{case}", command)
        raw = Path(result["log"]).read_text(encoding="utf-8", errors="replace")
        markers = PASS_LINE.findall(raw)
        errors = FAIL_LINE.findall(raw)
        edges = EDGE_LINE.findall(raw)
        trace = directory / f"case{case}.edges.txt"
        trace.write_text("\n".join(edges) + "\n", encoding="utf-8")
        if result["status"] == "PASS" and len(markers) == 1 and not errors:
            status = "PASS"
        elif errors:
            status = "FAIL_CHECKER_TRIAGE_REQUIRED"
        else:
            status = "BLOCKED_SIMULATOR_OR_NO_TERMINAL"
        records["cases"][str(case)] = {
            "scenario": CASES[case], "status": status, "terminal": markers, "checker_failure": errors,
            "trace": trace.as_posix(), "trace_sha256": digest(trace), "edge_events": len(edges),
            "log": result["log"],
        }
        print(f"  case {case}: {status} {' '.join(markers or errors)}", flush=True)
    records["status"] = "PASS" if all(
        result["status"] == "PASS" for result in records["cases"].values()
    ) else "INCOMPLETE"
    return records


def compare_edges(baseline, candidate, cases):
    comparisons = {}
    for case in map(str, cases):
        first = baseline["cases"].get(case)
        second = candidate["cases"].get(case)
        if not first or not second or first["status"] != "PASS" or second["status"] != "PASS":
            comparisons[case] = {"status": "NOT_COMPARABLE"}
            continue
        baseline_edges = Path(first["trace"]).read_text(encoding="utf-8").splitlines()
        candidate_edges = Path(second["trace"]).read_text(encoding="utf-8").splitlines()
        for index, (before, after) in enumerate(zip_longest(baseline_edges, candidate_edges), start=1):
            if before != after:
                comparisons[case] = {
                    "status": "DIFFERENT", "first_event_number": index, "baseline": before, "candidate": after,
                }
                break
        else:
            comparisons[case] = {"status": "IDENTICAL", "events": len(baseline_edges)}
    return comparisons


def reuse_baseline(path, baseline_files, shared_inputs, bench, cases):
    previous = json.loads(path.read_text(encoding="utf-8"))
    baseline = previous["baseline"]
    old_bench = path.parent / bench.name
    expected = hashes([*baseline_files, *shared_inputs])
    expected[old_bench.as_posix()] = digest(bench)
    if (previous["baseline_commit"] != BASELINE or previous["changed_inputs"] or
            baseline["status"] != "PASS" or sum(command["seconds"] for command in baseline["commands"]) > 58 or
            not all(previous["input_sha256"].get(name) == sha for name, sha in expected.items()) or
            not all(str(case) in baseline["cases"] and baseline["cases"][str(case)]["status"] == "PASS"
                    for case in cases)):
        raise ValueError("the previous baseline lacks passing cases with the same source, TB and tools")
    for case in cases:
        prior = baseline["cases"][str(case)]
        if digest(Path(prior["trace"])) != prior["trace_sha256"]:
            raise ValueError(f"previous baseline trace changed for case {case}")
    return baseline


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True, help="opaque frozen pair from 41cb5991")
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="new run directory")
    parser.add_argument("--cases", type=int, nargs="+", choices=CASES, default=list(CASES))
    parser.add_argument("--reuse-baseline", type=Path, help="reuse passing cases from a prior RUN.json")
    arguments = parser.parse_args()
    started = time.monotonic()
    deadline = started + 58
    output = arguments.output.resolve()
    output.mkdir(parents=True)
    frozen_bench = output / "tb_jpeg_reset.sv"
    frozen_runner = output / "run.py"
    shutil.copyfile(Path(__file__).with_name(frozen_bench.name), frozen_bench)
    shutil.copyfile(__file__, frozen_runner)
    model_root = arguments.td_root.resolve() / "sim_release"
    models = [model_root / path for path in MODELS]
    gsr = model_root / "ph1/ph1_phy_gsr.v"
    include_dirs = [DESIGN / path for path in INCLUDES]
    tool_paths = {name: arguments.modelsim_bin.resolve() / f"{name}.exe"
                  for name in ("vlib", "vmap", "vlog", "vsim")}
    shared = [Path(sys.executable), *tool_paths.values(), *models, gsr]
    for directory in include_dirs:
        if not directory.is_dir():
            raise FileNotFoundError(directory)
        shared.extend(sorted(path for path in directory.rglob("*") if path.is_file()))
    candidate_files = [DESIGN / path for path in DESIGN_FILES]
    baseline_files = [arguments.baseline.resolve() / path.name if path.name in BASELINE_REPLACEMENTS else path
                      for path in candidate_files]
    identities = hashes([frozen_bench, frozen_runner, *shared, *baseline_files, *candidate_files])
    common = (tool_paths, models, gsr, include_dirs, frozen_bench)
    result = {
        "baseline_commit": BASELINE, "td_root": arguments.td_root.resolve().as_posix(),
        "started_utc": datetime.now(timezone.utc).isoformat(), "python_version": sys.version,
        "input_sha256": identities, "wall_budget_seconds": 58, "sim_watchdog_ps": 50000000,
        "compile_define": "PH1", "include_dirs": [path.as_posix() for path in include_dirs], "commands": [],
    }
    version = run_command(output, result["commands"], deadline, "vsim_version", [tool_paths["vsim"], "-version"])
    result["modelsim_version"] = Path(version["log"]).read_text(encoding="utf-8", errors="replace").strip()
    if arguments.reuse_baseline:
        previous = arguments.reuse_baseline.resolve()
        result["baseline"] = reuse_baseline(previous, baseline_files, shared, frozen_bench, arguments.cases)
        result["baseline_reused_from"] = {"path": previous.as_posix(), "sha256": digest(previous)}
    else:
        result["baseline"] = run_variant(output / "baseline", baseline_files, common, arguments.cases, deadline)
    result["candidate"] = run_variant(output / "candidate", candidate_files, common, arguments.cases, deadline)
    comparisons = compare_edges(result["baseline"], result["candidate"], arguments.cases)
    result["edge_comparison"] = comparisons
    result["changed_inputs"] = [path for path, before in identities.items() if digest(Path(path)) != before]
    result["elapsed_seconds"] = round(time.monotonic() - started, 3)
    accepted = (result["baseline"]["status"] == result["candidate"]["status"] == "PASS" and
                result["elapsed_seconds"] <= 60 and not result["changed_inputs"] and
                all(entry["status"] == "IDENTICAL" for entry in comparisons.values()))
    result["status"] = "PASS" if accepted else "INCOMPLETE"
    record = output / "RUN.json"
    record.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{result['status']} {result['elapsed_seconds']} s {record}", flush=True)
    return 0 if accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
