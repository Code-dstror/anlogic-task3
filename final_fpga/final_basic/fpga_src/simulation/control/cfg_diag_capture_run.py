"""Exercise passive USER/PIX capture helpers independently of business FSMs."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--name", required=True)
    ap.add_argument("--modelsim-bin", type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        ap.error("unsafe run name")
    run = ROOT / "tmp/cfg_diag" / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / "src_fpga/rtl" / name for name in ("cfg_diag_user.v", "cfg_diag_pixel.v")]
    bench = HERE / "cfg_diag_capture_tb.sv"
    inputs = sources + [bench, Path(__file__)]
    identity = [{"path": str(p), "sha256": sha(p)} for p in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity, "modelsim_bin": str(args.modelsim_bin),
              "scope": "Passive capture helpers only; actual BAR/engine event and ACK identity mapping is separate",
              "synthesis": "NOT_RUN", "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        proc = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if proc.returncode:
            raise RuntimeError(proc.stdout[-12000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + sources)
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        execute("vsim.exe", ["-c", "work.cfg_diag_capture_tb", "-l", "run.log", "-do",
                              "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS cfg_diag_capture" not in body:
            raise RuntimeError(body[-12000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during run: " + row["path"])
        result.update(status="PASS", metrics=[s.strip("# ") for s in body.splitlines() if "RESULT: PASS" in s])
        print("\n".join(result["metrics"]))
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print(run / "RESULTS.json")


if __name__ == "__main__":
    main()
