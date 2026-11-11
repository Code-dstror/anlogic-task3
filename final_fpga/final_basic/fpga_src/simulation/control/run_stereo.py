"""Focused mailbox simulation; no vendor primitives, synthesis or board I/O."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch("[a-z][a-z0-9_]{0,48}", args.name):
        ap.error("invalid run identifier")
    run = PROJECT / "tmp/control" / args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl = PROJECT / "src_fpga/rtl"
    include_dirs = [rtl / "include/00_rtl", rtl / "include/04_include"]
    sources = [rtl / "reset_release_sync.v", rtl / "stereo_cold_control.v", HERE / "tb_stereo_cold_control.sv"]
    inputs = sources + [include_dirs[0]/"stereo_control_v1.vh", include_dirs[1]/"pcie_protocol_v1.vh", Path(__file__)]
    hashes = [{"path": str(p.resolve()), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in inputs]
    start = time.monotonic()
    result = {"status": "IN_PROGRESS", "inputs": hashes, "td_models": "NOT_REQUIRED_PURE_RTL",
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "board": "NOT_RUN"}
    try:
        commands = [[args.modelsim_bin / "vlib.exe", "work"],
                    [args.modelsim_bin / "vlog.exe", "-sv", "-work", "work", "-l", "compile.log",
                     *("+incdir+" + p.as_posix() for p in include_dirs), *sources],
                    [args.modelsim_bin / "vsim.exe", "-c", "work.tb_stereo_cold_control", "-l", "run.log",
                     "-do", "run -all; quit -f"]]
        for command in commands:
            done = subprocess.run([str(w) for w in command], cwd=run, capture_output=True, text=True, errors="replace")
            with (run / "console.log").open("a") as stream:
                stream.write(done.stdout + done.stderr)
            if done.returncode:
                raise RuntimeError(done.stdout + done.stderr)
        logs = (run / "compile.log").read_text() + (run / "run.log").read_text()
        if re.search(r"\*\* (Warning|Error|Fatal):", logs):
            raise RuntimeError("compiler/runtime diagnostic; inspect retained logs")
        marker = re.search(r"RESULT: PASS STEREO COLD CONTROL checks=(\d+)", logs)
        if marker is None:
            raise RuntimeError("actual self-check PASS missing")
        if any(hashlib.sha256(Path(row["path"]).read_bytes()).hexdigest() != row["sha256"] for row in hashes):
            raise RuntimeError("source changed during simulation")
        result.update(status="PASS", checks=int(marker[1]))
    except Exception as exc:
        result.update(status="FAIL", error=str(exc))
        raise
    finally:
        result["elapsed_seconds"] = round(time.monotonic()-start, 3)
        (run / "qualification.json").write_text(json.dumps(result, indent=2)+"\n")
        print(json.dumps({"run": str(run), "status": result["status"]}))


if __name__ == "__main__":
    main()
