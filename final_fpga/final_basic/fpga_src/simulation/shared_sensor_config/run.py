"""Check the shared IMX415 configuration owner against pin-level I2C traces."""

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
REPO = PROJECT.parents[1]
BASELINE = "01cc78afba01b313cbeb3090118763c3f30735f0"
TABLES = (
    ("rtl/imx415_mode_table.v", "imx415_mode_table"),
    ("rtl/imx415_hdr2_recipe_rom.v", "imx415_hdr2_recipe_rom"),
    ("ip/vendor/anlogic_camera/sensor/ui_imx415_reg.v", "ui_imx415reg"),
)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--name", required=True, help="new run directory name")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("name must be a lowercase run identifier")
    ms = args.modelsim_bin.resolve()
    for exe in ("vlib.exe", "vlog.exe", "vsim.exe"):
        if not (ms / exe).is_file():
            parser.error(f"missing ModelSim executable {ms / exe}")

    run = PROJECT / "tmp/shared_sensor_config" / args.name
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    result = dict(status="IN_PROGRESS", scope="PER_EYE_CONFIG_AND_PIN_I2C",
                  baseline=BASELINE, modelsim_bin=ms.as_posix(), python=sys.executable,
                  runner_argv=[sys.executable, str(Path(__file__).resolve()), *sys.argv[1:]],
                  inputs=[], commands=[], cases=[], synthesis="NOT_RUN",
                  place_route="NOT_RUN", timing="NOT_RUN", board="NOT_RUN")
    start = time.monotonic()
    worktree_inputs = {}

    def git(*args):
        return subprocess.check_output(["git", *args], cwd=REPO, timeout=10)

    def copy_input(path):
        content = path.read_bytes()
        copied = snapshot / path.name
        copied.write_bytes(content)
        digest = sha(content)
        worktree_inputs[path] = digest
        result["inputs"].append(dict(source=path.relative_to(REPO).as_posix(),
                                     sha256=digest, snapshot=copied.relative_to(run).as_posix()))
        return copied

    def copy_oracle(rel, module):
        path = "refactor/camera_shared_r1/src_fpga/" + rel
        original = git("show", f"{BASELINE}:{path}")
        content = original
        # Keep the frozen oracle distinct from the candidate's table modules.
        for _, name in TABLES:
            token = name.encode("ascii")
            content = re.sub(rb"\b" + token + rb"\b", b"frozen_" + token, content)
        copied = snapshot / f"frozen_{module}.v"
        copied.write_bytes(content)
        result["inputs"].append(dict(source=f"{BASELINE}:{path}", sha256=sha(original),
                                     snapshot=copied.relative_to(run).as_posix(),
                                     snapshot_sha256=sha(content)))
        return copied

    def command(label, exe, args, timeout=20):
        argv = [str(ms / exe), *map(str, args)]
        log = run / f"{label}.log"
        record = dict(argv=argv, log=log.name, timeout_seconds=timeout)
        result["commands"].append(record)
        with log.open("wb") as output:
            completed = subprocess.run(argv, cwd=run, stdout=output,
                                       stderr=subprocess.STDOUT, timeout=timeout)
        record["returncode"] = completed.returncode
        console = log.read_text(encoding="utf-8", errors="replace")
        if completed.returncode or re.search(r"\*\* (Error|Fatal)\b", console):
            raise RuntimeError(f"{label} failed\n{console[-6000:]}")
        return console

    try:
        result["git_head"] = git("rev-parse", "HEAD").decode("ascii").strip()
        legacy_owner = Path("refactor/camera_shared_r1/src_fpga/rtl/imx415_config.v")
        result["baseline_sdr_policy"] = f"{BASELINE}:{legacy_owner.as_posix()}"
        sources = [copy_input(PROJECT / "src_fpga" / p) for p in (
            "rtl/camera_i2c_write.v", "rtl/imx415_sensor_config.v", "rtl/imx415_sensor_recipe.v",
            *(rel for rel, _ in TABLES))]
        sources += [copy_oracle(rel, module) for rel, module in TABLES]
        sources.append(copy_input(HERE / "tb_sensor_config.sv"))
        copy_input(Path(__file__).resolve())
        result["modelsim_version"] = command("version", "vsim.exe", ["-version"]).strip()
        command("library", "vlib.exe", ["work"])
        command("compile", "vlog.exe", ["-work", "work", "-sv", "-timescale", "1ns/1ps", *sources])
        simulation = command("simulation", "vsim.exe", [
            "-c", "work.tb_sensor_config", "-do", "run -all; quit -f"], timeout=60)
        result["cases"] = [line.strip("# ") for line in simulation.splitlines() if "CASE:" in line]
        if "RESULT: PASS shared_sensor_config" not in simulation:
            raise RuntimeError(f"simulation did not finish\n{simulation[-6000:]}")
        warnings = [line for log in ("compile.log", "simulation.log")
                    for line in (run / log).read_text(encoding="utf-8", errors="replace").splitlines()
                    if re.search(r"\*\* Warning\b", line)]
        if warnings:
            raise RuntimeError("unexpected ModelSim warnings\n" + "\n".join(warnings))
        for path, digest in worktree_inputs.items():
            if sha(path.read_bytes()) != digest:
                raise RuntimeError(f"input changed during run: {path}")
        result.update(status="PASS", input_hash_recheck="PASS", warning_count=0)
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
