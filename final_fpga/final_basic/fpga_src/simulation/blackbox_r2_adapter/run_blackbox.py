"""Run these independent benches with frozen opaque inputs and bounded wall time."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from time import monotonic


HERE = Path(__file__).resolve().parent
R2 = HERE.parents[2]
DEFAULT_MODELSIM = Path("D:/App/modelsim/win64")
DEFAULT_TD_ROOT = Path("D:/App/TD_Release_2026.2.210.850")
ADAPTER = "camera_rgb_native_fixed1080_borrow4.v"
SUITES = {
    "adapter": (
        (ADAPTER,),
        "adapter",
        ("first_raster", "cancel_first", "cancel_middle", "reset_context", "reset_output",
         "reset_status", "stopped_clock", "malformed", "source_identity", "source_fault"),
    ),
    "source_borrow": (
        ("reset_release_sync.v", "hdr_pair_product_abort_drain4.v", ADAPTER, "private_raw_isp_borrow4.v"),
        "source_borrow",
        ("first_raster", "source_failure", "cancel_priority", "cancel_raw_offer", "source_without_drain"),
    ),
}


def sha256(path: Path) -> str:
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def run(argv: list[str], cwd: Path, log: Path, timeout: float) -> dict:
    start = monotonic()
    result = {"argv": argv, "cwd": str(cwd), "log": str(log.relative_to(cwd)), "timeout_s": timeout}
    windows = os.name == "nt"
    creationflags = subprocess.CREATE_NO_WINDOW if windows else 0
    with log.open("wb") as output:
        try:
            process = subprocess.Popen(argv, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=creationflags)
        except OSError as exc:
            output.write((str(exc) + "\n").encode("utf-8"))
            result.update(exit_code=None, outcome="TOOL_BLOCKED")
        else:
            try:
                result.update(exit_code=process.wait(timeout=timeout), outcome="EXIT")
            except subprocess.TimeoutExpired:
                # vsim.exe may spawn a vsimk.exe child. Kill only this invocation's tree.
                if windows and process.poll() is None:
                    try:
                        subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                                       stdout=output, stderr=subprocess.STDOUT,
                                       timeout=3, creationflags=creationflags, check=False)
                    except (OSError, subprocess.TimeoutExpired):
                        pass
                if process.poll() is None:
                    process.kill()
                result.update(exit_code=process.wait(timeout=1), outcome="WALL_TIMEOUT")
    result["elapsed_s"] = round(monotonic() - start, 3)
    result["log_sha256"] = sha256(log)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=SUITES, default="adapter")
    parser.add_argument("--modelsim-bin", type=Path, default=DEFAULT_MODELSIM)
    parser.add_argument("--td-root", type=Path, default=DEFAULT_TD_ROOT,
                        help="Record the local TD identity; these suites compile no TD models.")
    parser.add_argument("--rtl-dir", type=Path, default=R2 / "src_fpga" / "rtl",
                        help="Opaque alternative (for example, a fixed parent snapshot).")
    parser.add_argument("--case", action="append", help="Select a case; repeat for more than one.")
    args = parser.parse_args()
    rtl_files, basename, available_cases = SUITES[args.suite]
    cases = args.case or available_cases
    if set(cases) - set(available_cases) or len(set(cases)) != len(cases):
        parser.error(f"use distinct cases from: {', '.join(available_cases)}")

    out = R2 / "tmp" / "blackbox_r2_adapter" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + "_" + args.suite)
    inputs = out / "inputs"
    inputs.mkdir(parents=True)
    rtl_dir = args.rtl_dir.resolve(strict=True)
    modelsim_bin = args.modelsim_bin.resolve(strict=True)
    tb = HERE / f"{basename}_tb.sv"
    public = R2 / "verification_reference"
    result: dict = {
        "suite": args.suite,
        "runner_argv": [sys.executable, *sys.argv],
        "rtl_dir": str(rtl_dir),
        "td_root": str(args.td_root),
        "td_models": [],
        "python": sys.version,
        "profiles": {"MAX_WIDTH": 1920, "MAX_HEIGHT": 1080},
        "inputs": [],
        "tools": [],
        "setup": [],
        "cases": [],
    }
    if args.suite == "source_borrow":
        result["profiles"].update(RAW_SAMPLE_BITS=14, EXTERNAL_ISP_ENABLE=1, ORIGINAL_SYNC_CLEAR_ENABLE=1)

    def save_result() -> None:
        (out / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

    for original in (HERE / "run_blackbox.py", public / f"{basename}_public.md", public / f"{basename}_ports.txt",
                     *(rtl_dir / filename for filename in rtl_files), tb):
        copy = inputs / original.name
        shutil.copyfile(original, copy)
        result["inputs"].append({"original": str(original), "snapshot": str(copy.relative_to(out)),
                                 "size": copy.stat().st_size, "sha256": sha256(copy)})
    executables = {name: str(modelsim_bin / (name + ".exe")) for name in ("vlib", "vmap", "vlog", "vsim")}
    for file in (*map(Path, executables.values()), modelsim_bin / "vsimk.exe"):
        if file.is_file():
            result["tools"].append({"path": str(file), "sha256": sha256(file)})
    save_result()
    print(f"Evidence: {out}", flush=True)

    def setup(name: str, argv: list[str]) -> bool:
        record = run(argv, out, out / f"{name}.log", 15.0)
        result["setup"].append(record)
        save_result()
        # Keep diagnostics opaque to the test author; do not print compiler source excerpts.
        if record["exit_code"] != 0:
            print(f"BLOCKED setup {name}: {record['outcome']} rc={record['exit_code']} ({record['log']})", flush=True)
            return False
        return True

    if not (setup("version", [executables["vsim"], "-version"])
            and setup("copy_ini", [executables["vmap"], "-c"])
            and setup("vlib", [executables["vlib"], "work"])
            and setup("vmap", [executables["vmap"], "-modelsimini", "modelsim.ini", "work", "work"])
            and setup("vlog", [executables["vlog"], "-modelsimini", "modelsim.ini", "-sv", "-work", "work",
                               *(str(Path("inputs") / name) for name in rtl_files), str(Path("inputs") / tb.name)])):
        result["outcome"] = "SETUP_BLOCKED"
        save_result()
        return 2
    result["modelsim_version"] = (out / "version.log").read_text(encoding="utf-8", errors="replace").strip()
    result["modelsim_ini_sha256"] = sha256(out / "modelsim.ini")
    save_result()
    for case in cases:
        log = out / f"{case}.log"
        argv = [executables["vsim"], "-c", "-modelsimini", "modelsim.ini", "-onfinish", "stop",
                "-l", f"{case}.transcript", "-wlf", f"{case}.wlf", f"work.{basename}_tb", f"+CASE={case}",
                "-do", "run -all; quit -f"]
        # Reserve four seconds of the 45 s limit for terminating a timed-out process tree.
        record = run(argv, out, log, 40.0)
        record["case"] = case
        content = log.read_text(encoding="utf-8", errors="replace")
        expected = rf"^\s*#?\s*PASS {re.escape(args.suite)} {re.escape(case)}\s*$"
        marker = re.search(expected, content, re.MULTILINE) is not None
        error = re.search(r"^\s*#?\s*\*\* (?:Fatal|Error):", content, re.MULTILINE) is not None
        if record["outcome"] == "WALL_TIMEOUT":
            record["status"] = "FAIL_WALL_TIMEOUT"
        elif record["outcome"] == "TOOL_BLOCKED":
            record["status"] = "TOOL_BLOCKED"
        else:
            record["status"] = "PASS" if record["exit_code"] == 0 and marker and not error else "FAIL"
        record["pass_marker"] = marker
        result["cases"].append(record)
        save_result()
        print(f"{record['status']} {args.suite}/{case}: {record['elapsed_s']}s ({log.name})", flush=True)
        if record["status"] == "FAIL_WALL_TIMEOUT" and case == "first_raster":
            break

    result["outcome"] = "PASS" if len(result["cases"]) == len(cases) and all(
        record["status"] == "PASS" for record in result["cases"]
    ) else "FAIL"
    save_result()
    return 0 if result["outcome"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
