"""Exercise the production stereo reader with the shared RAW10 decoder."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RTL = PROJECT / "src_fpga/rtl"
SOURCES = tuple(RTL / name for name in (
    "stereo_raw_reader.v", "shared_raw10_decode_service.v", "shared_raw10_decoder_masked.v",
)) + (HERE / "tb_shared_decode_start.sv",)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    ap.add_argument("--name", required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        ap.error("name must be a lowercase run identifier")
    ms = args.modelsim_bin.resolve()
    for tool in ("vsim", "vlib", "vlog"):
        if not (ms / f"{tool}.exe").is_file():
            ap.error(f"missing ModelSim {tool} under {ms}")
    run = PROJECT / "tmp/shared_decode_start" / args.name
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    start = time.monotonic()
    result = dict(status="IN_PROGRESS", scope="SHARED_RAW10_STEREO_LIFECYCLE_8X2",
                  runner_argv=[sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
                  inputs=[], commands=[], synthesis="NOT_RUN", place_route="NOT_RUN",
                  timing="NOT_RUN", board="NOT_RUN")

    def command(label, tool, options, timeout=20):
        argv = [str(ms / f"{tool}.exe"), *map(str, options)]
        log = run / f"{label}.log"
        entry = dict(argv=argv, log=log.name, timeout_seconds=timeout)
        result["commands"].append(entry)
        with log.open("wb") as output:
            process = subprocess.run(argv, cwd=run, stdout=output, stderr=subprocess.STDOUT, timeout=timeout)
        entry["returncode"] = process.returncode
        body = log.read_text(encoding="utf-8", errors="replace")
        if process.returncode or re.search(r"\*\* (Error|Fatal|Warning)\b", body):
            raise RuntimeError(f"{label} failed\n{body[-6000:]}")
        return body

    try:
        for path in (*SOURCES, Path(__file__).resolve()):
            data = path.read_bytes()
            copied = snapshot / path.name
            copied.write_bytes(data)
            result["inputs"].append(dict(path=path.relative_to(PROJECT).as_posix(),
                                         snapshot=copied.relative_to(run).as_posix(),
                                         sha256=hashlib.sha256(data).hexdigest()))
        result["modelsim_version"] = command("version", "vsim", ["-version"]).strip()
        command("library", "vlib", ["work"])
        command("compile", "vlog", ["-work", "work", "-sv", *[snapshot / p.name for p in SOURCES]])
        sim = command("simulation", "vsim", ["-c", "work.tb_shared_decode_start", "-do",
                                              "run -all; quit -f"], timeout=45)
        if "RESULT: PASS shared_decode_start" not in sim:
            raise RuntimeError(f"missing self-check result\n{sim[-6000:]}")
        result["cases"] = [line.strip("# ") for line in sim.splitlines() if "CASE:" in line]
        for item in result["inputs"]:
            digest = hashlib.sha256((PROJECT / item["path"]).read_bytes()).hexdigest()
            if digest != item["sha256"]:
                raise RuntimeError(f"input changed during simulation: {item['path']}")
        result.update(status="PASS", input_hash_recheck="PASS")
        print("\n".join(result["cases"]))
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
        (run / "qualification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"{result['status']} {run.as_posix()} ({result['elapsed_seconds']} s)")


if __name__ == "__main__":
    main()
