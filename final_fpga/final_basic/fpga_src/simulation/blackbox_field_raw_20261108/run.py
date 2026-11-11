"""Run each public-interface case in a fresh bounded ModelSim process."""

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
CASES = (
    ("startup", 0, 0),
    ("startup", 1, 2200),
    ("pressure", 0, 0),
    ("pressure", 1, 2200),
    ("negative_source", 0, 0),
    ("stop_begin", 0, 2200),
    ("stop_ar", 0, 0),
    ("stop_data", 1, 2200),
)
WALL_SECONDS = 45
TB = HERE / "tb_field_raw.sv"
PUBLIC_PREFIXES = ("BEGIN_RESPONSE ", "RECORD_START ", "RECORD_RETIRED ", "PASS_FIELD_RAW ")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(paths):
    return {str(path): digest(path) for path in sorted(set(paths))}


def digest_snapshot(snapshot_):
    return hashlib.sha256(json.dumps(snapshot_, sort_keys=True).encode()).hexdigest()


def log_text(path):
    return path.read_bytes().decode("utf-8", errors="replace")


def parse_log(path):
    """Expose bench assertions only; production and model diagnostics stay in logs."""
    lines = log_text(path).splitlines()
    lines = [re.sub(r"^#\s*", "", line).strip() for line in lines]
    events = [line for line in lines if line.startswith(PUBLIC_PREFIXES)]
    fatals = [
        line.removeprefix("** Fatal:").strip()
        for i, line in enumerate(lines)
        if line.startswith("** Fatal:") and "tb_field_raw.sv" in " ".join(lines[i + 1:i + 4])
    ]
    locations = sorted({
        f"{name}:{line}"
        for raw in lines if re.search(r"\*\*\s*(Error|Fatal):", raw)
        for name, line in re.findall(r"([^/\\\s(]+\.s?v)\((\d+)\)", raw, re.I)
    })
    return events, fatals, locations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--case", choices=sorted({case for case, _, _ in CASES}), action="append")
    parser.add_argument("--run-label", default="field_raw")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.run_label):
        parser.error("invalid run label")

    manifest_path = HERE / "sources.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    design = [PROJECT / name for name in manifest["sources"]]
    td_root = args.td_root.resolve(strict=True)
    models = [td_root / name for name in manifest["td_models"]]
    includes = [PROJECT / name for name in manifest["include"]]
    input_files = design + models + [p for directory in includes for p in directory.rglob("*") if p.is_file()]
    input_files += [TB, manifest_path, Path(__file__).resolve()]
    sim = args.modelsim_bin.resolve(strict=True)
    exe = {name: sim / f"{name}.exe" for name in ("vlib", "vmap", "vlog", "vsim")}
    out = PROJECT / "tmp" / "blackbox_field_raw_20261108" / (
        datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ_") + args.run_label
    )
    out.mkdir(parents=True)
    print(f"RUN_DIR {out.as_posix()}", flush=True)
    report = {
        "profile": {"width": 8, "height": 2, "dfi_period_ps": 7500, "sim_limit_ps": 200_000_000,
                    "wall_limit_seconds_per_case": WALL_SECONDS, "raw_export_enable": 1,
                    "external_decoder": 1, "verify_decode_active": 1},
        "python": sys.version,
        "python_executable": sys.executable,
        "td_root": str(td_root),
        "modelsim_bin": str(sim),
        "inputs_before": snapshot(input_files),
        "executables": snapshot(exe.values()),
        "commands": [],
        "cases": [],
    }
    report["input_sha256"] = digest_snapshot(report["inputs_before"])

    def run(name, argv):
        argv = [str(arg) for arg in argv]
        log = out / f"{name}.log"
        start = monotonic()
        with log.open("wb") as fp:
            try:
                result = subprocess.run(argv, cwd=out, stdout=fp, stderr=subprocess.STDOUT,
                                        check=False, timeout=WALL_SECONDS)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = "WALL_TIMEOUT"
            except OSError as exc:
                fp.write(f"{exc}\n".encode())
                code = "SPAWN_ERROR"
        report["commands"].append({"name": name, "argv": argv, "cwd": str(out),
                                   "exit": code, "wall_seconds": round(monotonic() - start, 4),
                                   "log_sha256": digest(log)})
        return code, log

    setup = (
        ("version", [exe["vsim"], "-version"]),
        ("vmap_ini", [exe["vmap"], "-c"]),
        ("vlib", [exe["vlib"], "work"]),
        ("vmap", [exe["vmap"], "work", "work"]),
        ("vlog", [exe["vlog"], "-sv", "-work", "work",
                  *(f"+incdir+{path.as_posix()}" for path in includes),
                  *(f"+define+{name}" for name in manifest["defines"]),
                  *(path.as_posix() for path in models + design + [TB])]),
    )
    overall_ok = True
    for name, argv in setup:
        code, log = run(name, argv)
        if code != 0:
            locations = parse_log(log)[2]
            print(f"BLOCKED_SETUP stage={name} exit={code} locations={locations}", flush=True)
            overall_ok = False
            report["setup_failure"] = {"stage": name, "exit": code, "locations": locations}
            break
        if name == "version":
            report["modelsim_version"] = log_text(log).strip()
    else:
        for case, first, phase in CASES:
            if args.case and case not in args.case:
                continue
            name = f"{case}_eye{first}_phase{phase}"
            code, log = run(name, [exe["vsim"], "-c", "-t", "1ps", "-onfinish", "exit", "-quiet",
                                    "work.tb_field_raw", "work.glbl", "work.PH1_PHY_GSR", f"+CASE={case}",
                                    f"+FIRST={first}", f"+PHASE={phase}", "-do",
                                    "onerror {quit -code 2}; run -all; quit -code 0"])
            events, fatals, locations = parse_log(log)
            markers = [event for event in events if event.startswith("PASS_FIELD_RAW ")]
            ok = code == 0 and len(markers) == 1 and not fatals
            overall_ok &= ok
            report["cases"].append({"name": name, "status": "PASS" if ok else "FAIL", "events": events,
                                    "fatal": fatals, "locations": locations})
            if ok:
                print(markers[0], flush=True)
            else:
                print(f"FAIL case={name} exit={code} fatal={fatals} locations={locations}", flush=True)

    report["inputs_after"] = snapshot(input_files)
    stable = report["inputs_before"] == report["inputs_after"]
    report["inputs_stable"] = stable
    report["status"] = "PASS" if overall_ok and stable else "FAIL"
    (out / "evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"RESULT {report['status']} inputs_stable={stable} input_sha256={report['input_sha256']}", flush=True)
    return 0 if overall_ok and stable else 1


if __name__ == "__main__":
    raise SystemExit(main())
