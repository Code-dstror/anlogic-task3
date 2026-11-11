"""Run the public-port reader cases against three opaque production inputs."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import time


CASES = (
    "normal",
    "lost_start",
    "unseen_active",
    "before_ar",
    "held_ar",
    "accepted_ar",
    "between_bursts",
    "decoder_tail",
    "stop_final_r",
    "stop_fence_stall",
    "wrong_rid",
    "early_rlast",
    "rresp",
)
MODELSIM = Path("D:/App/modelsim/win64")
LIMIT_SECONDS = 50


def digests(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def run(output_dir, name, command, pass_marker=None):
    log_path = output_dir / f"{name}.log"
    print(subprocess.list2cmdline(command), flush=True)
    start = time.monotonic()
    try:
        result = subprocess.run(
            command, cwd=output_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=LIMIT_SECONDS, check=False,
        )
        log = result.stdout
        code = result.returncode
        status = "PASS" if code == 0 else "FAIL"
        if pass_marker and pass_marker.encode() not in log:
            status = "FAIL"
    except subprocess.TimeoutExpired as error:
        log = error.stdout or b""
        code = None
        status = "TIMEOUT"
    wall = round(time.monotonic() - start, 3)
    log_path.write_bytes(log)
    print(f"{status} {name} {wall:.3f}s {log_path}", flush=True)
    return dict(name=name, command=command, status=status, returncode=code,
                wall_seconds=wall, log=str(log_path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, action="append")
    args = parser.parse_args()

    stage_dir = Path(__file__).resolve().parents[3]
    rtl_dir = stage_dir / "src_fpga" / "rtl"
    sources = [rtl_dir / f"{name}.v" for name in (
        "shared_raw10_decoder_masked", "shared_raw10_decode_service", "stereo_raw_reader",
    )]
    testbench = Path(__file__).resolve().with_name("reader_tb.sv")
    output_dir = stage_dir / "tmp" / "blackbox_reader_r5_20261107" / datetime.now().strftime("%H%M%S_%f")
    output_dir.mkdir(parents=True)

    before = digests(sources)
    results = []
    results.append(run(output_dir, "vlib", [str(MODELSIM / "vlib.exe"), "work"]))
    if results[-1]["status"] == "PASS":
        results.append(run(output_dir, "vlog", [str(MODELSIM / "vlog.exe"), "-sv", "-work", "work",
                                               *map(str, sources), str(testbench)]))
    if results[-1]["status"] == "PASS":
        for case in args.case or CASES:
            results.append(run(
                output_dir, case,
                [str(MODELSIM / "vsim.exe"), "-c", "-onfinish", "stop", "work.reader_tb", f"+CASE={case}",
                 "-do", "onerror {quit -f -code 1}; run -all; quit -f -code 0"],
                pass_marker=f"READER_CASE_PASS case={case} ",
            ))

    after = digests(sources)
    summary = output_dir / "summary.json"
    summary.write_text(json.dumps(dict(before=before, after=after, testbench_sha256=digests([testbench]),
                                       results=results), indent=2) + "\n", encoding="utf-8")
    print(f"SUMMARY {summary}", flush=True)
    if before != after:
        print("Production input hashes changed during the run.", flush=True)
    return int(before != after or any(result["status"] != "PASS" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
