"""Run the same public-port bench on an opaque baseline or candidate snapshot."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from time import monotonic


CASES = (
    "r4_first", "reassert_r3", "reset_context", "reset_rgb", "reset_notice",
    "reset_result", "negative_cleanup",
)
WALL_SECONDS = 55
MARKER = re.compile(r"^(?:#\s*)?\s*((?:BLACKBOX_(?:PASS|FAIL)|EVENT|COVER|LEDGER|TERMINAL)\b.*)")


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def run_command(args, cwd, log_name, deadline):
    result = {"argv": [str(arg) for arg in args], "cwd": str(cwd), "log": log_name}
    with (cwd / log_name).open("wb") as log:
        if monotonic() >= deadline:
            result["wall_timeout"] = True
            return result
        try:
            proc = subprocess.Popen(
                result["argv"], cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW,
            )
        except OSError as error:
            result["launch_error"] = str(error)
            return result
        try:
            result["exit_code"] = proc.wait(timeout=max(0, deadline - monotonic()))
        except subprocess.TimeoutExpired:
            result["wall_timeout"] = True
            # Target the subprocess tree created for this invocation only.
            subprocess.run(
                ["taskkill.exe", "/PID", str(proc.pid), "/T", "/F"], cwd=cwd,
                stdout=log, stderr=subprocess.STDOUT, timeout=3,
                creationflags=subprocess.CREATE_NO_WINDOW, check=False,
            )
    return result


def copy_opaque(path, origin, dest):
    target = dest / path.name
    shutil.copyfile(path, target)
    return {"origin": str(origin), "snapshot": str(target), "sha256": sha256(target)}


def observe_case(name, cwd, modelsim, deadline):
    invocation = run_command(
        [modelsim / "vsim.exe", "-c", "-quiet", "-onfinish", "stop", "-wlf", f"{name}.wlf",
         "-l", f"{name}.transcript", "work.source_reset_tb", f"+case={name}",
         "-do", "onerror {quit -code 2 -f}; run -all; quit -code 0 -f"],
        cwd, f"{name}.log", deadline,
    )
    markers = []
    for line in (cwd / invocation["log"]).read_text(encoding="utf-8", errors="replace").splitlines():
        match = MARKER.match(line)
        if match:
            markers.append(match[1])
    if invocation.get("wall_timeout"):
        state = "BLOCKED_WALL_TIMEOUT"
    elif any(line.startswith("BLACKBOX_FAIL ") for line in markers):
        state = "FAIL_ASSERTION"
    elif invocation.get("exit_code") == 0 and f"BLACKBOX_PASS case={name}" in markers:
        state = "PASS"
    else:
        state = "BLOCKED_TOOL_OR_ELABORATION"
    print(f"{name}: {state}", flush=True)
    return {"name": name, "state": state, "invocation": invocation, "markers": markers}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--variant", required=True, choices=("baseline", "candidate"))
    parser.add_argument("--baseline-source", type=Path)
    parser.add_argument("--case", action="append", choices=CASES)
    args = parser.parse_args()
    if (args.variant == "baseline") != (args.baseline_source is not None):
        parser.error("--baseline-source is required only for the baseline variant")
    start = monotonic()
    deadline = start + WALL_SECONDS
    repo = args.repo.resolve(strict=True)
    modelsim = args.modelsim_bin.resolve(strict=True)
    td_root = args.td_root.resolve(strict=True)
    stage = repo / "refactor/camera_raw_r2"
    public = stage / "docs/parameter_timing_20261110"
    manifest_path = stage / "experiments/timing_source_20261110/OPAQUE_SOURCES.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    tag = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    run_dir = repo / f"tmp/timing_source_20261110/blackbox/{args.variant}_{tag}"
    snapshot = run_dir / "inputs"
    snapshot.mkdir(parents=True)
    print(run_dir, flush=True)
    runner = Path(__file__).resolve()
    testbench = runner.with_name("source_reset_tb.sv")
    support = [runner, testbench, manifest_path, public / "SOURCE_RESET_PUBLIC.md",
               public / "SOURCE_PORTS.txt", public / "CLEANUP_PORTS.txt"]
    inputs = [copy_opaque(path, path, snapshot) for path in support]
    sources = []
    for name in manifest["sources"]:
        path = repo / name
        if args.variant == "baseline" and path.name == "private_rgb_source_borrow4.v":
            path = args.baseline_source.resolve(strict=True)
            if path.name != "private_rgb_source_borrow4.v":
                parser.error("baseline snapshot must retain its public module filename")
        sources.append(copy_opaque(path, path, snapshot))
    suite = args.case or CASES
    commands = []
    cases = []
    for log, command in (
        ("version.log", [modelsim / "vsim.exe", "-version"]),
        ("vlib.log", [modelsim / "vlib.exe", "work"]),
        ("production_compile.log", [modelsim / "vlog.exe", "-work", "work",
                                    *(f"+incdir+{repo / path}" for path in manifest["include_dirs"]),
                                    *(f"+define+{value}" for value in manifest["defines"]),
                                    *(entry["snapshot"] for entry in sources)]),
        ("testbench_compile.log", [modelsim / "vlog.exe", "-sv", "-work", "work", snapshot / testbench.name]),
    ):
        result = run_command(command, run_dir, log, deadline)
        commands.append(result)
        if result.get("exit_code") != 0:
            print(f"Blocked at {run_dir / log}", flush=True)
            break
    else:
        cases = [observe_case(case, run_dir, modelsim, deadline) for case in suite]
    if not cases or any(case["state"].startswith("BLOCKED") for case in cases):
        state = "BLOCKED"
    elif any(case["state"] != "PASS" for case in cases):
        state = "FAIL"
    else:
        state = "PASS"
    receipt = {
        "state": state, "variant": args.variant, "baseline_commit": manifest["baseline"],
        "run_dir": str(run_dir), "wall_limit_seconds": WALL_SECONDS,
        "wall_seconds": round(monotonic() - start, 3), "simulation_limit_ns": 20000,
        "modelsim_bin": str(modelsim), "modelsim_version_log": "version.log",
        "td_root": str(td_root), "vendor_models": manifest["vendor_models"],
        "requested_cases": list(suite), "inputs": inputs, "sources": sources,
        "commands": commands, "cases": cases,
    }
    (run_dir / "result.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return 0 if state == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
