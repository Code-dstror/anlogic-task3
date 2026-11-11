import argparse
import sys
from pathlib import Path

from sim_runner import BENCH_DIR, PROJECT, SimFailure, Simulator, fingerprint, write_json
import json


def main():
    parser = argparse.ArgumentParser(description="Independent RAW10 A/B functional short gate")
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--run-dir", required=True, type=Path)
    args = parser.parse_args()
    td_root = args.td_root.resolve(strict=True)
    root = PROJECT / "experiments" / "raw_ingress_equiv"
    source_list = root / "OPAQUE_SOURCES.json"
    manifest = json.loads(source_list.read_text(encoding="utf-8"))
    arms = {arm: [root / file for file in manifest[arm]["files"]] for arm in ("baseline", "candidate")}
    bench = BENCH_DIR / "tb_raw_ingress.sv"
    files = [bench, Path(__file__), BENCH_DIR / "sim_runner.py", source_list,
             root / "PUBLIC_CONTRACT.md", root / "PORTS.vh", *arms["baseline"], *arms["candidate"]]
    inputs = fingerprint(files)
    for arm, arm_files in arms.items():
        if len(arm_files) != 1 or inputs[str(arm_files[0])] != manifest[arm]["sha256"]:
            raise ValueError(f"{arm} identity differs from its opaque source manifest")

    simulator = Simulator(args.run_dir, args.modelsim_bin, overall_seconds=160)
    run = simulator.run_dir
    write_json(run / "inputs.json", {"files": inputs, "python": sys.version, "td_root": str(td_root),
                                    "td_models_used": False, "overall_seconds": 160})
    results = {}
    try:
        simulator.invoke(run, "version.log", "vsim", "-version")
        for arm, arm_files in arms.items():
            cwd = run / arm
            try:
                simulator.library(cwd)
                simulator.invoke(cwd, "vlog_dut.log", "vlog", "-work", "work", *arm_files)
                simulator.invoke(cwd, "vlog_tb.log", "vlog", "-sv", "-work", "work", bench)
                markers = simulator.simulate(cwd, "simulation", "tb_raw_ingress",
                                             "RAW_INGRESS_PASS profiles=4", "RAW_FAIL")
                results[arm] = {"status": "PASS", "markers": markers}
            except SimFailure as failure:
                results[arm] = {"status": failure.status, "reason": str(failure)}

        if all(result["status"] == "PASS" for result in results.values()):
            differences = []
            for profile in range(4):
                name = f"trace_{profile}.csv"
                before = (run / "baseline" / name).read_text(encoding="utf-8").splitlines()
                after = (run / "candidate" / name).read_text(encoding="utf-8").splitlines()
                if before != after:
                    first = next((i for i, (a, b) in enumerate(zip(before, after), 1) if a != b),
                                 min(len(before), len(after)) + 1)
                    differences.append({"profile": profile, "first_trace_row": first})
            results["equivalence"] = {"status": "FAIL" if differences else "PASS",
                                      "differences": differences}
        else:
            results["equivalence"] = {"status": "NOT_RUN"}
    except SimFailure as failure:
        results["toolchain"] = {"status": failure.status, "reason": str(failure)}

    results["input_identity"] = {"status": "PASS" if inputs == fingerprint(files) else "STALE"}
    write_json(run / "results.json", results)
    print(json.dumps(results, indent=2))
    return 0 if all(result["status"] == "PASS" for result in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
