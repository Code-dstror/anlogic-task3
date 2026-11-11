"""Check exact config response/ACK timing against fixed f3fc9adb, strict and trusted."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
BASE = "f3fc9adb5462ea91b50886be6dfa23449eec4d74"
BASE_ENGINE = "refactor/hdr_jpeg/src_fpga/rtl/mono_config_engine_v2.v"
BASE_BENCH = "refactor/hdr_jpeg/src_fpga/simulation/control/tb_mono_config_ack_pipeline.sv"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/config_control" / args.name
    run.mkdir(parents=True, exist_ok=False)
    manifest = PROJECT / "SOURCE_MANIFEST.json"
    includes = [PROJECT / item for item in json.loads(manifest.read_text())["include_dirs"]]
    sources = [PROJECT / "src_fpga/rtl" / name for name in
               ("mono_config_legacy_scan_v1.v", "mono_config_scan_v2.v", "mono_config_engine_v2.v")]
    bench = HERE / "tb_timing_config_control.sv"
    baselines = []

    def frozen(path):
        body = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=REPO)
        baselines.append({"commit": BASE, "path": path, "sha256": hashlib.sha256(body).hexdigest()})
        return body.decode().replace("\r\n", "\n")

    reference_text, count = re.subn(r"\bmodule\s+mono_config_engine_v2\b",
                                    "module timing_config_engine_reference", frozen(BASE_ENGINE))
    if count != 1:
        raise RuntimeError("baseline engine identity did not match")
    reference = run / "timing_config_engine_reference.v"
    reference.write_text(reference_text, newline="\n")
    base_text = frozen(BASE_BENCH)
    replacements = {
        "module tb_mono_config_ack_pipeline;":
            "module timing_config_base #(parameter integer TRUSTED_COMMANDS=0)(output reg done=0);",
        "mono_config_engine_v2 #(.V2_SUPPORTED_MODES":
            "mono_config_engine_v2 #(.TRUSTED_COMMANDS(TRUSTED_COMMANDS),.V2_SUPPORTED_MODES",
        "$finish;": "done=1;",
    }
    for old, new in replacements.items():
        if base_text.count(old) != 1:
            raise RuntimeError("fixed ACK fixture transformation did not match: " + old)
        base_text = base_text.replace(old, new)
    base_bench = run / "timing_config_base.sv"
    base_bench.write_text(base_text, newline="\n")
    headers = [path for directory in includes for path in directory.glob("*.vh")]
    inputs = sources + [bench, manifest, Path(__file__)] + headers
    identity = [{"path": str(path), "sha256": sha(path)} for path in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity, "baseline": baselines,
              "modelsim_bin": str(args.modelsim_bin), "synthesis": "NOT_RUN",
              "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        completed = subprocess.run([str(args.modelsim_bin / exe)] + list(map(str, words)), cwd=run,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        include_args = ["+incdir+" + str(path) for path in includes]
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + include_args + sources + [reference])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log"] + include_args + [base_bench, bench])
        execute("vsim.exe", ["-c", "work.tb_timing_config_control", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        body = (run / "run.log").read_text()
        if "RESULT: PASS timing_config_control_all" not in body:
            raise RuntimeError(body[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError("unclassified diagnostic in " + name)
        for row in identity:
            if Path(row["path"]) != manifest and sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during simulation: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS" in line]
        print("\n".join(result["metrics"]))
    except Exception as error:
        result["status"] = "FAIL"
        result["error"] = str(error)
        raise
    finally:
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Results:", run / "RESULTS.json")


if __name__ == "__main__":
    main()
