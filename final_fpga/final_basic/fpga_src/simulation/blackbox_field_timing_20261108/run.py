"""Bounded ModelSim and UART decoder runs against the public field contracts."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from time import monotonic


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RTL = PROJECT / "src_fpga" / "rtl"
SOURCES = {
    "dcp": ["dehaze_dcp_restore4.v"],
    "uart": ["camera_field_diagnostics.v", "uart_status_observer.v", "uart_observer_snapshot.v", "cfg_diag_snapshot.v"],
}
BENCH = {"dcp": HERE / "tb_dcp_clear.sv", "uart": HERE / "tb_field_uart.sv"}
SCRIPT = HERE / "check_decoder.py"
DECODER = PROJECT / "tools" / "uart_observer.py"
CASES = {"dcp": ("clear", "history_reset"), "uart": ("wire",), "python": ("fragmented_wire",)}
MARKER = {"dcp": "PASS_FIELD_DCP ", "uart": "PASS_FIELD_UART ", "python": "PASS_FIELD_DECODER "}
WALL_SECONDS = 45


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(paths):
    return {str(path): digest(path) for path in sorted(set(paths))}


def read_log(path):
    return path.read_bytes().decode("utf-8", errors="replace")


def parse_hdl(log, bench):
    lines = [re.sub(r"^#\s*", "", line).strip() for line in read_log(log).splitlines()]
    markers = [line for line in lines if line.startswith(tuple(MARKER.values()))]
    fatals = [line.removeprefix("** Fatal:").strip() for i, line in enumerate(lines)
              if line.startswith("** Fatal:") and bench.name in " ".join(lines[i + 1:i + 4])]
    locations = sorted({f"{name}:{line}" for raw in lines if re.search(r"\*\*\s*(Error|Fatal):", raw)
                        for name, line in re.findall(r"([^/\\\s(]+\.s?v)\((\d+)\)", raw, re.I)})
    return markers, fatals, locations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True, help="explicit model root; these cases do not use vendor models")
    parser.add_argument("--only", choices=CASES, action="append")
    parser.add_argument("--run-label", default="field_timing")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.run_label):
        parser.error("invalid run label")
    suites = args.only or list(CASES)
    sim = args.modelsim_bin.resolve(strict=True)
    td = args.td_root.resolve(strict=True)
    exe = {name: sim / f"{name}.exe" for name in ("vlib", "vmap", "vlog", "vsim")}
    out = PROJECT / "tmp" / "blackbox_field_timing_20261108" / (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ_") + args.run_label
    )
    out.mkdir(parents=True)
    print(f"RUN_DIR {out.as_posix()}", flush=True)
    input_files = [Path(__file__).resolve()]
    for suite in suites:
        if suite == "python":
            input_files.extend((SCRIPT, DECODER))
        else:
            input_files += [BENCH[suite]] + [RTL / name for name in SOURCES[suite]]
    report = {"inputs_before": snapshot(input_files), "tools": snapshot(exe.values()),
              "python": sys.version, "python_executable": sys.executable, "td_root": str(td),
              "vendor_models": [], "wall_limit_seconds_per_case": WALL_SECONDS,
              "sim_limit_ns": 1_000_000, "commands": [], "cases": []}
    report["input_sha256"] = hashlib.sha256(json.dumps(report["inputs_before"], sort_keys=True).encode()).hexdigest()

    def run(name, args_):
        argv = [str(arg) for arg in args_]
        log = out / f"{name}.log"
        start = monotonic()
        with log.open("wb") as fp:
            try:
                code = subprocess.run(argv, cwd=out, stdout=fp, stderr=subprocess.STDOUT,
                                      check=False, timeout=WALL_SECONDS).returncode
            except subprocess.TimeoutExpired:
                code = "WALL_TIMEOUT"
            except OSError as exc:
                fp.write(f"{exc}\n".encode())
                code = "SPAWN_ERROR"
        report["commands"].append({"name": name, "argv": argv, "cwd": str(out), "exit": code,
                                   "wall_seconds": round(monotonic()-start, 4), "log_sha256": digest(log)})
        return code, log

    status = True
    modelsim_ready = True
    if any(suite != "python" for suite in suites):
        for name, argv in (("version", [exe["vsim"], "-version"]), ("vmap_ini", [exe["vmap"], "-c"]),
                           ("vlib", [exe["vlib"], "work"]), ("vmap", [exe["vmap"], "work", "work"])):
            code, log = run(name, argv)
            if code:
                print(f"BLOCKED_SETUP stage={name} exit={code}", flush=True)
                status = modelsim_ready = False
                break
            if name == "version":
                report["modelsim_version"] = read_log(log).strip()

    for suite in suites:
        if suite == "python":
            code, log = run("decoder_fragmented_wire", [sys.executable, "-B", SCRIPT])
            lines = read_log(log).splitlines()
            markers = [line for line in lines if line.startswith(MARKER[suite])]
            failures = [line for line in lines if line.startswith(("AssertionError", "KeyError", "TypeError", "ImportError", "ModuleNotFoundError"))]
            ok = code == 0 and len(markers) == 1
            print(markers[0] if ok else f"FAIL case=decoder_fragmented_wire exit={code} fatal={failures}", flush=True)
            status &= ok
            report["cases"].append({"name": "decoder_fragmented_wire", "pass": ok, "fatal": failures})
            continue
        if not modelsim_ready:
            continue
        code, log = run(f"{suite}_vlog", [exe["vlog"], "-sv", "-work", "work",
                                         *[RTL / name for name in SOURCES[suite]], BENCH[suite]])
        if code:
            print(f"BLOCKED_SETUP suite={suite} exit={code} locations={parse_hdl(log, BENCH[suite])[2]}", flush=True)
            status = False
            continue
        for case in CASES[suite]:
            code, log = run(f"{suite}_{case}", [exe["vsim"], "-c", "-t", "1ps", "-onfinish", "exit", "-quiet",
                                                f"work.{BENCH[suite].stem}", f"+CASE={case}", "-do",
                                                "onerror {quit -code 2}; run -all; quit -code 0"])
            markers, failures, locations = parse_hdl(log, BENCH[suite])
            ok = code == 0 and len(markers) == 1 and markers[0].startswith(MARKER[suite]) and not failures
            status &= ok
            report["cases"].append({"name": f"{suite}_{case}", "pass": ok, "fatal": failures, "locations": locations})
            print(markers[0] if ok else f"FAIL case={suite}_{case} exit={code} fatal={failures} locations={locations}", flush=True)

    report["inputs_after"] = snapshot(input_files)
    report["inputs_stable"] = report["inputs_before"] == report["inputs_after"]
    report["status"] = "PASS" if status and report["inputs_stable"] else "FAIL"
    (out / "evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"RESULT {report['status']} inputs_stable={report['inputs_stable']} input_sha256={report['input_sha256']}", flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
