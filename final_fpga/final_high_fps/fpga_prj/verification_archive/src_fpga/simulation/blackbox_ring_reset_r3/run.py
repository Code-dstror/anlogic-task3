"""Compile sealed opaque arms and compare the independently scored DFI traces."""

import argparse
import hashlib
import itertools
import json
import re
import subprocess
import sys
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
PUBLIC = PROJECT / "experiments" / "ring_data_qual_r3_20261110"
BENCH = HERE / "tb_jpeg_ring_reset.sv"
PASS_MARKER = re.compile(r"^(?:#\s*)?RING_BLACKBOX_PASS\b", re.MULTILINE)
ARMS = ("baseline", "candidate")
COMMAND_SECONDS = 50
SUITE_SECONDS = 165


class RunError(RuntimeError):
    pass


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def bind_sources(root, entries):
    paths = []
    for entry in entries:
        path = (root / entry["path"]).resolve()
        if not path.is_relative_to(root) or digest(path) != entry["sha256"]:
            raise RunError(f"Opaque input path or SHA-256 mismatch: {path}")
        paths.append(str(path))
    return paths


def run_command(bin_dir, directory, log, name, args, evidence, deadline):
    argv = [str(bin_dir / f"{name}.exe"), *args]
    log_path = directory / f"{log}.log"
    limit = min(COMMAND_SECONDS, deadline - time.monotonic())
    if limit <= 0:
        raise RunError("Suite wall-clock watchdog expired")
    record = {
        "argv": argv,
        "cwd": str(directory),
        "log": str(log_path),
        "timeout_seconds": round(limit, 3),
    }
    evidence["commands"].append(record)
    started = time.monotonic()
    with log_path.open("wb") as stdout:
        process = subprocess.Popen(
            argv,
            cwd=directory,
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        try:
            record["returncode"] = process.wait(timeout=limit)
        except subprocess.TimeoutExpired as exc:
            record["timeout"] = True
            if process.poll() is None:
                try:
                    subprocess.run(
                        ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                        stdout=stdout,
                        stderr=subprocess.STDOUT,
                        timeout=3,
                        creationflags=subprocess.CREATE_NO_WINDOW,
                        check=False,
                    )
                finally:
                    if process.poll() is None:
                        process.kill()
                    process.wait(timeout=1)
            raise RunError(f"Wall-clock watchdog: {log_path}") from exc
        finally:
            record["elapsed_seconds"] = round(time.monotonic() - started, 3)
    if record["returncode"] != 0:
        raise RunError(f"{name} exited {record['returncode']}: {log_path}")
    return log_path


def run_arm(out, arm, bin_dir, model, common, sources, globals_, evidence, deadline):
    directory = out / arm
    directory.mkdir()

    def command(log, executable, *args):
        return run_command(bin_dir, directory, log, executable, list(args), evidence, deadline)

    command("01-vlib-work", "vlib", "work")
    command("02-vlib-ph1", "vlib", "ph1")
    command("03-vmap-local", "vmap", "-c")
    command("04-vmap-ph1", "vmap", "ph1", "ph1")
    command("05-vlog-model", "vlog", "-work", "ph1", *model)
    command("06-vlog-arm", "vlog", "-work", "work", "-L", "ph1", *common, *sources)
    command(
        "07-vlog-bench", "vlog", "-work", "work", "-sv", "-L", "ph1",
        f"+incdir+{HERE}", str(BENCH),
    )
    sim_log = command(
        "08-vsim",
        "vsim",
        "-c",
        "-onfinish",
        "exit",
        "-L",
        "ph1",
        "-t",
        "1ps",
        "work.tb_jpeg_ring_reset",
        *globals_,
        "-do",
        "onerror {quit -f -code 2}; onbreak {quit -f -code 3}; run -all; quit -f -code 0",
    )
    public_log = sim_log.read_text(encoding="utf-8", errors="replace")
    trace = directory / "events.trace"
    markers = PASS_MARKER.findall(public_log)
    if len(markers) != 1 or not trace.is_file() or trace.stat().st_size == 0:
        raise RunError(f"Missing unique independent scoreboard PASS or trace: {sim_log}")
    return {"status": "PASS", "log": str(sim_log), "trace_sha256": digest(trace)}


def compare_traces(out):
    with (out / "baseline" / "events.trace").open(encoding="ascii") as baseline:
        with (out / "candidate" / "events.trace").open(encoding="ascii") as candidate:
            for number, (before, after) in enumerate(
                itertools.zip_longest(baseline, candidate), start=1
            ):
                if before != after:
                    return {
                        "status": "MISMATCH",
                        "line": number,
                        "baseline": before.rstrip() if before is not None else None,
                        "candidate": after.rstrip() if after is not None else None,
                    }
    return {"status": "MATCH"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    bin_dir = args.modelsim_bin.resolve()
    td_root = args.td_root.resolve()
    out = args.out.resolve()
    if out.parent != (PROJECT / "tmp").resolve() or not out.name.startswith(
        "ring_reset_r3_blackbox_"
    ):
        parser.error("--out must be a fresh project tmp/ring_reset_r3_blackbox_* directory")
    out.mkdir(parents=False, exist_ok=False)
    deadline = time.monotonic() + SUITE_SECONDS
    manifest_path = PUBLIC / "OPAQUE_SOURCES.json"
    sealed_inputs = [manifest_path, PUBLIC / "PUBLIC_CONTRACT.md", PUBLIC / "PORTS.vh"]
    test_inputs = [Path(__file__).resolve(), BENCH, HERE / "ring_test_bfm.svh"]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    evidence = {
        "python": sys.version,
        "invocation": [sys.executable, *sys.argv],
        "modelsim_bin": str(bin_dir),
        "td_root": str(td_root),
        "sealed_manifest": manifest,
        "input_hashes": {str(path): digest(path) for path in sealed_inputs + test_inputs},
        "commands": [],
        "arms": {},
    }
    sources_verified = False
    try:
        model = bind_sources(td_root, manifest["model_sources"])
        common = bind_sources(td_root, manifest["td_work_sources"])
        arms = {arm: bind_sources(PROJECT, manifest["variants"][arm]) for arm in ARMS}
        sources_verified = True
        version = run_command(
            bin_dir, out, "modelsim-version", "vsim", ["-version"], evidence, deadline
        )
        evidence["modelsim_version"] = version.read_text(encoding="utf-8", errors="replace").strip()
        for arm in ARMS:
            try:
                result = run_arm(
                    out, arm, bin_dir, model, common, arms[arm], manifest["globals"],
                    evidence, deadline,
                )
            except (RunError, OSError) as exc:
                result = {"status": "FAIL", "error": str(exc)}
            evidence["arms"][arm] = result
            print(f"{arm}: {result['status']} {result.get('error', '')}".rstrip(), flush=True)
        if all(evidence["arms"][arm]["status"] == "PASS" for arm in ARMS):
            evidence["comparison"] = compare_traces(out)
            print(f"accepted events and sampled levels: {evidence['comparison']['status']}")
    except (RunError, OSError) as exc:
        evidence["run_error"] = str(exc)
        print(f"ring suite: {exc}", file=sys.stderr)
    finally:
        if sources_verified:
            try:
                bind_sources(td_root, manifest["model_sources"])
                bind_sources(td_root, manifest["td_work_sources"])
                for arm in ARMS:
                    bind_sources(PROJECT, manifest["variants"][arm])
                if any(digest(Path(path)) != sha for path, sha in evidence["input_hashes"].items()):
                    raise RunError("A bench or public handoff input changed during the suite")
                evidence["inputs_reverified"] = True
            except (RunError, OSError) as exc:
                evidence["inputs_reverified"] = False
                evidence["reverification_error"] = str(exc)
        receipt = out / "run.json"
        receipt.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print(receipt)
    matched = evidence.get("comparison", {}).get("status") == "MATCH"
    return 0 if matched and evidence.get("inputs_reverified") else 1


if __name__ == "__main__":
    sys.exit(main())
