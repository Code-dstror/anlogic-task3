"""Official MAC miter for a zero-state clear/advance timing simplification.

--candidate proposal changes only a simulation copy; it never edits production.
Use --candidate current after an approved production edit to bind the same check.
"""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "d86edbed408230828e6cd8a887bceec80c242307"
BASE_PATH = "refactor/hdr_jpeg_timing/src_fpga/rtl/preprocess_gray_pending4.v"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--candidate", choices=("proposal", "current"), required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/r3_gray_clear" / args.name
    run.mkdir(parents=True, exist_ok=False)
    source = PROJECT / "src_fpga/rtl/preprocess_gray_pending4.v"
    parent_pipeline = PROJECT / "src_fpga/rtl/preprocess_live_f21_pipeline4.v"
    baseline = subprocess.check_output(["git", "show", f"{BASE}:{BASE_PATH}"], cwd=REPO)
    reference = baseline.decode().replace("\r\n", "\n")
    reference = re.sub(r"\bmodule\s+preprocess_gray_pending4\b", "module r3_gray_reference", reference, count=1)
    candidate = source.read_text()
    old = "wire advance = !valid_pipe[2] || m_ready;"
    new = "wire advance = clear || !valid_pipe[2] || m_ready;"
    if args.candidate == "proposal":
        if candidate.count(old) != 1:
            raise RuntimeError("proposal requires the unmodified production advance expression")
        candidate = candidate.replace(old, new)
    elif candidate.count(new) != 1:
        raise RuntimeError("current candidate is not the reviewed zero-state change")
    candidate = re.sub(r"\bmodule\s+preprocess_gray_pending4\b", "module r3_gray_candidate", candidate, count=1)
    reference_path, candidate_path = run / "r3_gray_reference.v", run / "r3_gray_candidate.v"
    reference_path.write_text(reference, newline="\n")
    candidate_path.write_text(candidate, newline="\n")
    fixture = json.loads((PROJECT / "src_fpga/simulation/MAIN_FIXTURE.json").read_text())
    models = [args.td_root / p for p in fixture["models"]]
    macros = [PROJECT / row["path"] for row in fixture["groups"]["mac_compile.args"]]
    gsr = args.td_root / "sim_release/ph1/ph1_phy_gsr.v"
    bench = HERE / "r3_gray_clear_tb.sv"
    inputs = models + macros + [gsr, source, parent_pipeline, bench, Path(__file__)]
    identity = [{"path": str(p), "sha256": sha(p)} for p in inputs]
    result = {"status": "IN_PROGRESS", "candidate_kind": args.candidate, "inputs": identity,
              "baseline": {"commit": BASE, "path": BASE_PATH, "sha256": hashlib.sha256(baseline).hexdigest()},
              "simulation_candidate_sha256": sha(candidate_path), "td_root": str(args.td_root),
              "production_write": "NOT_PERFORMED_BY_RUNNER", "synthesis": "NOT_RUN",
              "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        for lib in ("work", "ph1"):
            execute("vlib.exe", [lib]); execute("vmap.exe", [lib, lib])
        execute("vlog.exe", ["-quiet", "-work", "ph1", "-l", "models.log"] + models)
        execute("vlog.exe", ["-quiet", "+define+PH1", "-l", "rtl.log", gsr] + macros + [reference_path, candidate_path])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log", bench])
        execute("vsim.exe", ["-c", "-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl", "work.r3_gray_clear_tb",
                             "-l", "run.log", "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS r3_gray_clear_all" not in body or re.search(r"\*\*\s+(Error|Fatal):", body):
            raise RuntimeError(body[-10000:])
        warnings = []
        for name in ("models.log", "rtl.log", "bench.log", "run.log"):
            for line in (run / name).read_text().splitlines():
                if "** Warning:" not in line:
                    continue
                accepted = "fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v(466)" in line and (
                    re.search(r"\(vopt-2685\).*Too few port connections for 'u_siou'.  Expected 51, found 39", line) or
                    re.search(r"\(vopt-2718\).*Missing connection for port '(cco|cpo|cyo|cxabo|cxbo|cxao|cci|cpi|cyi|cxabi|cxbi|cxai)'", line))
                if not accepted:
                    raise RuntimeError("unclassified diagnostic: " + line)
                warnings.append(line)
        for row in identity:
            if sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during miter: " + row["path"])
        result["status"] = "PASS"
        result["accepted_vendor_warnings"] = sorted(set(warnings))
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL"; result["error"] = str(error); raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
