"""Run the public-port capture tests in a fresh, isolated ModelSim library."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter


CASES = ("cadence", "stall", "terminals", "geometry", "isolation", "reset", "saturation")
HERE = Path(__file__).resolve().parent
STAGE = HERE.parents[2]
RTL = STAGE / "src_fpga" / "rtl"
DUT = tuple(RTL / name for name in (
    "stereo_capture_source4.v", "physical_capture_router.v", "physical_identity_source_fence.v"
))
INCLUDES = (RTL / "include" / "00_rtl", RTL / "include" / "04_include")
TB = HERE / "capture_blackbox_tb.sv"
OUTPUT = STAGE / "tmp" / "blackbox_capture_r5_20261107"


def source_hashes():
    headers = sorted(path for folder in INCLUDES for path in folder.rglob("*") if path.is_file())
    return {
        str(path.relative_to(STAGE)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in (*DUT, *headers, TB, Path(__file__).resolve(), HERE / "CAPTURE_IO_CONTRACT.md")
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim", type=Path, required=True, help="directory with ModelSim executables")
    parser.add_argument("--case", choices=CASES, action="append", help="one or more cases, defaults to all")
    args = parser.parse_args()
    tools = args.modelsim.resolve()
    cases = args.case or CASES
    run = OUTPUT / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    run.mkdir(parents=True)
    manifest = {
        "run": str(run),
        "python": {"executable": sys.executable, "version": sys.version, "argv": sys.argv},
        "commands": [],
        "cases": {case: "NOT_RUN" for case in cases},
        "sha256_before": source_hashes(),
    }
    print(f"Evidence {run}", flush=True)

    def invoke(label, exe, *options, timeout=30):
        argv = [str(tools / (exe + ".exe")), *(str(option) for option in options)]
        started = perf_counter()
        logfile = run / f"{label}.log"
        with logfile.open("w", encoding="utf-8") as log:
            try:
                result = subprocess.run(
                    argv, cwd=run, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, check=False
                )
                status = result.returncode
            except subprocess.TimeoutExpired:
                status = "TIMEOUT"
            except OSError as exc:
                print(exc, file=log)
                status = "LAUNCH_ERROR"
        elapsed = round(perf_counter() - started, 3)
        manifest["commands"].append({
            "label": label, "argv": argv, "cwd": str(run), "log": logfile.name,
            "status": status, "elapsed_seconds": elapsed, "timeout_seconds": timeout,
        })
        return status, logfile, elapsed

    try:
        status, log, _ = invoke("vsim_version", "vsim", "-version")
        manifest["modelsim_version"] = log.read_text(encoding="utf-8", errors="replace").strip()
        if status != 0:
            print(f"BLOCKED ModelSim version exit={status}", flush=True)
            return 2
        status, log, _ = invoke("vlog_version", "vlog", "-version")
        manifest["compiler_version"] = log.read_text(encoding="utf-8", errors="replace").strip()
        if status != 0:
            print(f"BLOCKED compiler version exit={status}", flush=True)
            return 2
        for label, exe, options in (
            ("vlib", "vlib", ("work",)),
            ("vmap_copy", "vmap", ("-c",)),
            ("vmap_work", "vmap", ("work", "work")),
            ("vlog", "vlog", ("-sv", "-work", "work", *(f"+incdir+{path}" for path in INCLUDES), *DUT, TB)),
        ):
            status, _, _ = invoke(label, exe, *options)
            if status != 0:
                print(f"BLOCKED {label} exit={status} (see {label}.log)", flush=True)
                return 2

        for case in cases:
            status, log, elapsed = invoke(
                f"case_{case}", "vsim", "-c", "-onfinish", "stop", "work.capture_blackbox_tb",
                f"+case={case}", "-do", "onerror {quit -code 2}; run -all; quit -code 0", timeout=55,
            )
            transcript = log.read_text(encoding="utf-8", errors="replace")
            marker = f"CAPTURE_BLACKBOX_PASS {case} "
            failure = re.search(r"(?im)^#?\s*\*\*\s*(Fatal|Error):.*$", transcript)
            outcome = "PASS" if status == 0 and marker in transcript and not failure else "FAIL"
            manifest["cases"][case] = {"outcome": outcome, "elapsed_seconds": elapsed, "log": log.name}
            if failure:
                manifest["cases"][case]["diagnostic"] = failure.group(0).strip("# \r\n")
            print(f"{outcome} {case} ({elapsed:.3f}s)", flush=True)
    finally:
        manifest["sha256_after"] = source_hashes()
        manifest["sources_unchanged"] = manifest["sha256_before"] == manifest["sha256_after"]
        (run / "capture_evidence.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if not manifest["sources_unchanged"]:
        print("FAIL source or test hashes changed during the run", flush=True)
        return 2
    return 0 if all(item["outcome"] == "PASS" for item in manifest["cases"].values()) else 1


if __name__ == "__main__":
    sys.exit(main())
