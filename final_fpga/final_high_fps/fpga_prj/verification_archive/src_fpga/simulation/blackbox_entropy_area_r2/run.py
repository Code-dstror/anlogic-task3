"""Run the new public-port benches against one already compiled opaque work library."""

import argparse
import json
import re
import subprocess
import time
from pathlib import Path

from oracle import HERE, ROOT, generate, score, sha256, write_json


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--target", choices=("entropy", "encoder", "both"), default="both")
    parser.add_argument("--split-encoder", action="store_true",
                        help="run low/high success and negative/recovery in separate simulator processes")
    args = parser.parse_args()
    run = args.run_dir.resolve(strict=True)
    if not (run / "work").is_dir() or not (run / "rom_init").is_dir():
        parser.error("use an already compiled work library with sealed rom_init")
    modelsim = args.modelsim_bin.resolve(strict=True)
    td_root = args.td_root.resolve(strict=True)
    targets = ("entropy", "encoder") if args.target == "both" else (args.target,)
    deadline = time.monotonic() + 177
    record = {
        "modelsim_bin": modelsim.as_posix(), "td_root": td_root.as_posix(), "commands": [],
        "encoder_split": args.split_encoder,
        "sources_sha256": {
            path.name: sha256(path.read_bytes())
            for path in (HERE / "run.py", HERE / "oracle.py", ROOT / "tools/jpeg_ref/jpeg_ref.py",
                         *(HERE / f"tb_{target}.sv" for target in targets))
        },
        "target_results": {},
    }
    for item in ("compile_inputs.json", "compile.json", "modelsim.ini"):
        if (run / item).is_file():
            record["sources_sha256"][item] = sha256((run / item).read_bytes())
    evidence = run / "blackbox_run.json"
    with evidence.open("x", encoding="utf-8") as output:
        json.dump(record, output, indent=2)

    def call(argv, log_name, limit=56):
        argv = [str(arg) for arg in argv]
        log = run / log_name
        entry = {"argv": argv, "cwd": str(run), "log": log.name}
        record["commands"].append(entry)
        started = time.monotonic()
        timeout = min(limit, deadline - started)
        if timeout <= 0:
            raise RuntimeError("suite wall-clock budget expired")
        with log.open("xb") as capture:
            proc = subprocess.Popen(argv, cwd=run, stdout=capture, stderr=subprocess.STDOUT,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                entry["exit_code"] = proc.wait(timeout)
            except subprocess.TimeoutExpired:
                entry["timed_out"] = True
                subprocess.run(["taskkill.exe", "/pid", str(proc.pid), "/t", "/f"],
                               stdout=capture, stderr=subprocess.STDOUT,
                               creationflags=subprocess.CREATE_NO_WINDOW, timeout=2, check=False)
                raise RuntimeError(f"tool wall-clock timeout: {log}") from None
            finally:
                entry["elapsed_s"] = round(time.monotonic() - started, 3)
        if entry["exit_code"] != 0:
            raise RuntimeError(f"tool exit {entry['exit_code']}: {log}")
        return log

    failures = []
    try:
        generate(run)
        record["fixture_manifest_sha256"] = sha256((run / "fixtures.json").read_bytes())
        record["modelsim_version"] = call([modelsim / "vsim.exe", "-version"], "modelsim_version.log", 8).read_text(
            encoding="utf-8", errors="replace").strip()
        for target in targets:
            try:
                call([modelsim / "vlog.exe", "-sv", "-work", "work", "-L", "ph1",
                      HERE / f"tb_{target}.sv"], f"{target}_vlog.log")
                split = target == "encoder" and args.split_encoder
                ranges = (("_success", 0, 2), ("_recover", 2, 4)) if split else (("", 0, 0),)
                for suffix, first_frame, end_frame in ranges:
                    log_prefix = target + suffix
                    fixture_args = []
                    if split:
                        fixture_args = [f"+first_frame={first_frame}", f"+end_frame={end_frame}",
                                        f"+trace_path={log_prefix}.trace"]
                    log = call([modelsim / "vsim.exe", "-c", "-t", "1ps", "-L", "ph1", "-onfinish", "stop",
                                "-l", f"{log_prefix}.transcript", f"work.tb_{target}",
                                "work.PH1_PHY_GSR", "ph1.glbl", *fixture_args, "-do",
                                "onerror {quit -f -code 1}; run -all; quit -f -code 0"],
                               f"{log_prefix}_vsim.log")
                    transcript = log.read_text(encoding="utf-8", errors="replace")
                    expected_count = end_frame - first_frame if split else (11 if target == "entropy" else 4)
                    marker = re.search(rf"(?m)^\s*(?:#\s*)?PASS {target}_area_r2 frames={expected_count} cycles=\d+\s*$",
                                       transcript)
                    if not marker or re.search(r"(?m)^#?\s*\*\* (?:Error|Fatal):", transcript):
                        raise RuntimeError(f"missing terminal PASS or simulator error: {log}")
                if split:
                    (run / "encoder.trace").write_bytes(
                        b"".join((run / f"encoder{suffix}.trace").read_bytes() for suffix, _, _ in ranges))
                score(run, target)
                record["target_results"][target] = "PASS"
            except Exception as exc:
                record["target_results"][target] = f"FAIL: {exc}"
                failures.append(f"{target}: {exc}")
    finally:
        write_json(evidence, record)
    for failure in failures:
        print(failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
