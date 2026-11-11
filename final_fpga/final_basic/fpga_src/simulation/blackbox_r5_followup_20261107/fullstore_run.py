"""Exercise the full-store public interfaces with the pinned PH1 simulation models."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import time


MODELSIM = Path("D:/App/modelsim/win64")
TD_ROOT = Path("D:/App/TD_Release_2026.2.210.850")
CASES = {
    "normal": ("normal", 1),
    "stagger_local": ("stagger", 1),
    "stagger_global_control": ("stagger", 0),
    "config_reject": ("config_reject", 1),
}


def hashes(paths):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def execute(output, name, executable, args, marker=None):
    command = [str(MODELSIM / f"{executable}.exe"), *map(str, args)]
    print(subprocess.list2cmdline(command), flush=True)
    start = time.monotonic()
    try:
        result = subprocess.run(command, cwd=output, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=50, check=False)
        log, code = result.stdout, result.returncode
        passed = code == 0 and (marker is None or marker.encode() in log)
        status = "PASS" if passed else "FAIL"
    except subprocess.TimeoutExpired as error:
        log, code, status = error.stdout or b"", None, "TIMEOUT"
    log_file = output / f"{name}.log"
    log_file.write_bytes(log)
    duration = round(time.monotonic() - start, 3)
    print(f"{status} {name} {duration:.3f}s {log_file}", flush=True)
    return dict(name=name, status=status, log=str(log_file), command=command,
                returncode=code, wall_seconds=duration)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=CASES, action="append")
    options = parser.parse_args()

    test_dir = Path(__file__).resolve().parent
    stage_dir = test_dir.parents[2]
    manifest = test_dir / "STORE_SOURCE_LIST.json"
    testbench = test_dir / "fullstore_tb.sv"
    spec = json.loads(manifest.read_text(encoding="utf-8"))
    if Path(spec["td_root"]) != TD_ROOT:
        raise ValueError("The public source list must name the pinned TD model root")
    sources = [stage_dir / path for path in spec["sources"]]
    models = [TD_ROOT / path for path in spec["td_models"]]
    includes = [f"+incdir+{stage_dir / directory}" for directory in spec["include"]]
    defines = [f"+define+{define}" for define in spec["defines"]]

    output = stage_dir / "tmp" / "blackbox_fullstore_r5_20261107" / datetime.now().strftime("%H%M%S_%f")
    output.mkdir(parents=True)
    before = hashes(sources + models)
    results = []
    compile_steps = (
        ("vlib_work", "vlib", ["work"]),
        ("vlib_ph1", "vlib", ["ph1"]),
        ("vlog_models", "vlog", ["-work", "ph1", *models]),
        ("vlog_fullstore", "vlog", ["-sv", "-work", "work", *defines, *includes, *sources, testbench]),
    )
    for name, executable, args in compile_steps:
        results.append(execute(output, name, executable, args))
        if results[-1]["status"] != "PASS":
            break
    else:
        for name in options.case or CASES:
            case, local = CASES[name]
            args = ["-c", "-onfinish", "stop", "-L", "ph1", f"-gLOCAL_RETIRE={local}",
                    "ph1.PH1_PHY_GSR", "ph1.glbl", "work.fullstore_tb", f"+CASE={case}",
                    "-do", "onerror {quit -f -code 1}; run -all; quit -f -code 0"]
            results.append(execute(output, name, "vsim", args, f"FULLSTORE_PASS case={case} local={local} "))

    after = hashes(sources + models)
    summary = output / "summary.json"
    summary.write_text(json.dumps(dict(td_root=str(TD_ROOT), before=before, after=after,
                                       harness=hashes([manifest, testbench, Path(__file__).resolve()]),
                                       results=results), indent=2) + "\n", encoding="utf-8")
    print(f"SUMMARY {summary}", flush=True)
    if before != after:
        print("An opaque production or TD model input changed during the run.", flush=True)
    return int(before != after or any(result["status"] != "PASS" for result in results))


if __name__ == "__main__":
    raise SystemExit(main())
