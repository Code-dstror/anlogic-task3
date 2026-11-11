"""Run the public RAW replay gate against sealed opaque sources."""

import argparse
import hashlib
import json
import re
import subprocess
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
CONTRACT = PROJECT / "experiments" / "reset_data_qual_r2_20261110"
BENCH = HERE / "tb_raw_source.sv"
PROCESS_TIMEOUT = 55
SUITE_TIMEOUT = 158
OUTPUT_LINE = re.compile(r"^\s*(?:#\s*)?(TRACE .+|RAW_SOURCE_GATE_PASS .+)$")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def checked_sources(manifest):
    variants = {}
    for variant in ("baseline", "candidate"):
        variants[variant] = []
        for entry in manifest["variants"][variant]:
            source = (PROJECT / entry["path"]).resolve()
            if not source.is_relative_to(PROJECT):
                raise ValueError(f"Opaque input escapes project: {source}")
            if sha256(source) != entry["sha256"]:
                raise ValueError(f"Opaque input hash mismatch: {source}")
            variants[variant].append(str(source))
    return variants


class Gate:
    def __init__(self, run_dir, modelsim, manifest):
        self.run_dir = run_dir
        self.modelsim = modelsim
        self.deadline = time.monotonic() + SUITE_TIMEOUT
        self.evidence = {
            "run_dir": str(run_dir),
            "process_timeout_seconds": PROCESS_TIMEOUT,
            "suite_timeout_seconds": SUITE_TIMEOUT,
            "inputs": {
                str(path): sha256(path)
                for path in (
                    Path(__file__).resolve(), BENCH, CONTRACT / "PUBLIC_CONTRACT.md",
                    CONTRACT / "PORTS.vh", CONTRACT / "OPAQUE_SOURCES.json",
                )
            },
            "opaque_sources": manifest,
            "commands": [],
            "results": {},
        }

    def record(self):
        write_json(self.run_dir / "evidence.json", self.evidence)

    def command(self, cwd, log_name, executable, *arguments):
        argv = [str(self.modelsim / f"{executable}.exe"), *arguments]
        log = cwd / log_name
        entry = {"cwd": str(cwd), "argv": argv, "log": str(log)}
        self.evidence["commands"].append(entry)
        self.record()
        start = time.monotonic()
        timeout = min(PROCESS_TIMEOUT, self.deadline - start)
        if timeout <= 0:
            entry["result"] = "SUITE_TIMEOUT"
            self.record()
            raise RuntimeError(f"Suite watchdog expired before {log}")
        try:
            with log.open("wb") as output:
                result = subprocess.run(
                    argv, cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                    timeout=timeout, check=False,
                )
        except subprocess.TimeoutExpired as exc:
            entry["result"] = "PROCESS_TIMEOUT"
            raise RuntimeError(f"Process watchdog expired: {log}") from exc
        except OSError as exc:
            entry["result"] = f"LAUNCH_ERROR {exc}"
            raise RuntimeError(f"Could not launch {argv[0]}: {log}") from exc
        else:
            entry["returncode"] = result.returncode
            if result.returncode:
                raise RuntimeError(f"{executable} exited {result.returncode}: {log}")
        finally:
            entry["elapsed_seconds"] = round(time.monotonic() - start, 3)
            self.record()

    def arm(self, variant, profile_name, profile, sources):
        arm_dir = self.run_dir / f"{profile_name}_{variant}"
        arm_dir.mkdir()
        record = self.evidence["results"].setdefault(profile_name, {})
        try:
            self.command(arm_dir, "vlib.log", "vlib", "work")
            self.command(arm_dir, "vlog_opaque.log", "vlog", "-work", "work", *sources)
            self.command(arm_dir, "vlog_bench.log", "vlog", "-sv", "-work", "work", str(BENCH))
            (arm_dir / "run.do").write_text(
                "onerror {quit -f -code 3}\n"
                "run -all\n"
                "quit -f -code 0\n", encoding="ascii",
            )
            parameters = [f"-g{name}={value}" for name, value in profile.items()]
            self.command(
                arm_dir, "vsim.log", "vsim", "-c", "-lib", "work", "-onfinish", "stop",
                *parameters, "tb_raw_source", "-do", "run.do",
            )
            trace = []
            markers = []
            for line in (arm_dir / "vsim.log").read_text(
                encoding="utf-8", errors="replace"
            ).splitlines():
                match = OUTPUT_LINE.fullmatch(line)
                if match and match[1].startswith("TRACE "):
                    trace.append(match[1])
                if match and match[1].startswith("RAW_SOURCE_GATE_PASS "):
                    markers.append(match[1])
            if len(markers) != 1 or not trace:
                raise RuntimeError(f"Missing unambiguous PASS and trace: {arm_dir / 'vsim.log'}")
            trace_bytes = ("\n".join(trace) + "\n").encode("ascii")
            (arm_dir / "public_trace.txt").write_bytes(trace_bytes)
            record[variant] = {
                "status": "PASS",
                "marker": markers[0],
                "trace_lines": len(trace),
                "trace_sha256": hashlib.sha256(trace_bytes).hexdigest(),
            }
            return trace, markers[0]
        except RuntimeError as exc:
            record[variant] = {"status": "FAIL", "reason": str(exc)}
            print(exc, flush=True)
            return None
        finally:
            self.record()

    def compare(self, profile_name, baseline, candidate):
        results = self.evidence["results"][profile_name]
        if baseline is None or candidate is None:
            results["comparison"] = {"status": "UNAVAILABLE"}
            return False
        if baseline == candidate:
            results["comparison"] = {"status": "PASS"}
            return True
        result = {"status": "FAIL", "trace_lengths": [len(baseline[0]), len(candidate[0])]}
        for index, (left, right) in enumerate(zip(baseline[0], candidate[0]), start=1):
            if left != right:
                result.update({"first_difference": index, "baseline": left, "candidate": right})
                break
        results["comparison"] = result
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--run-name", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"raw_source_r2_blackbox_[A-Za-z0-9_-]+", args.run_name):
        parser.error("--run-name must be a single raw_source_r2_blackbox_* directory name")

    manifest = json.loads((CONTRACT / "OPAQUE_SOURCES.json").read_text(encoding="utf-8"))
    sources = checked_sources(manifest)
    profiles = manifest.get("legal_profiles")
    if profiles is None:
        profiles = {"raw14": manifest["legal_profile"]}
    run_dir = PROJECT / "tmp" / args.run_name
    run_dir.mkdir(parents=True)
    gate = Gate(run_dir, args.modelsim_bin.resolve(), manifest)
    gate.record()
    print(run_dir, flush=True)
    try:
        gate.command(run_dir, "version.log", "vsim", "-version")
        passed = True
        for name, profile in profiles.items():
            baseline = gate.arm("baseline", name, profile, sources["baseline"])
            candidate = gate.arm("candidate", name, profile, sources["candidate"])
            passed = gate.compare(name, baseline, candidate) and passed
        checked_sources(manifest)
        if any(sha256(Path(path)) != digest for path, digest in gate.evidence["inputs"].items()):
            raise RuntimeError("Public contract or fixture changed during verification")
        gate.evidence["status"] = "PASS" if passed else "FAIL"
    except (RuntimeError, ValueError) as exc:
        gate.evidence["status"] = "BLOCKED"
        gate.evidence["reason"] = str(exc)
        print(exc, flush=True)
    gate.record()
    print(f"RAW_SOURCE_R2 {gate.evidence['status']} {run_dir / 'evidence.json'}", flush=True)
    return 0 if gate.evidence["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
