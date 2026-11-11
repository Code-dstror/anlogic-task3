"""Check the extension payload timing cut against the frozen f3fc9adb RTL."""
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
BASE_PATH = "refactor/hdr_jpeg/src_fpga/rtl/frame_record_extension_builder.v"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("unsafe run name")
    run = PROJECT / "tmp/extension_builder" / args.name
    run.mkdir(parents=True, exist_ok=False)
    source = PROJECT / "src_fpga/rtl/frame_record_extension_builder.v"
    bench = HERE / "tb_timing_extension_builder.sv"
    manifest = PROJECT / "SOURCE_MANIFEST.json"
    includes = [PROJECT / item for item in json.loads(manifest.read_text())["include_dirs"]]
    headers = [directory / "pcie_protocol_v1.vh" for directory in includes
               if (directory / "pcie_protocol_v1.vh").is_file()]
    if len(headers) != 1:
        raise RuntimeError("expected exactly one registered protocol header")
    baseline = subprocess.check_output(["git", "show", f"{BASE}:{BASE_PATH}"], cwd=REPO)
    renamed, count = re.subn(r"\bmodule\s+frame_record_extension_builder\b",
                            "module timing_extension_reference", baseline.decode().replace("\r\n", "\n"))
    if count != 1:
        raise RuntimeError("baseline module identity did not match")
    reference = run / "timing_extension_reference.v"
    reference.write_text(renamed, newline="\n")
    inputs = [source, bench, manifest, Path(__file__)] + headers
    identity = [{"path": str(path), "sha256": sha(path)} for path in inputs]
    result = {"status": "IN_PROGRESS", "inputs": identity,
              "baseline": {"commit": BASE, "path": BASE_PATH,
                           "sha256": hashlib.sha256(baseline).hexdigest()},
              "modelsim_bin": str(args.modelsim_bin), "synthesis": "NOT_RUN",
              "physical": "NOT_RUN", "timing": "NOT_RUN", "board": "NOT_RUN"}

    def execute(exe, words):
        command = [str(args.modelsim_bin / exe)] + list(map(str, words))
        completed = subprocess.run(command, cwd=run, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True)
        if completed.returncode:
            raise RuntimeError(completed.stdout[-10000:])

    try:
        execute("vmap.exe", ["-c"])
        execute("vlib.exe", ["work"])
        execute("vmap.exe", ["work", "work"])
        include_args = ["+incdir+" + str(path) for path in includes]
        execute("vlog.exe", ["-quiet", "-l", "rtl.log"] + include_args + [source, reference])
        execute("vlog.exe", ["-quiet", "-sv", "-l", "bench.log"] + include_args + [bench])
        execute("vsim.exe", ["-c", "work.tb_timing_extension_builder", "-l", "run.log",
                             "-do", "onerror {quit -code 1}; run -all; quit -f"])
        text = (run / "run.log").read_text()
        if "RESULT: PASS timing_extension_builder_all" not in text:
            raise RuntimeError(text[-10000:])
        for name in ("rtl.log", "bench.log", "run.log"):
            if re.search(r"\*\*\s+(Warning|Error|Fatal):", (run / name).read_text()):
                raise RuntimeError(f"unclassified diagnostic in {name}")
        # The shared project manifest can be refreshed independently while this
        # isolated check runs. Executed RTL, test and header bytes must stay fixed.
        for row in identity:
            if Path(row["path"]) != manifest and sha(Path(row["path"])) != row["sha256"]:
                raise RuntimeError("input changed during simulation: " + row["path"])
        result["status"] = "PASS"
        result["metrics"] = [line.strip("# ") for line in text.splitlines()
                             if "RESULT: PASS" in line]
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
