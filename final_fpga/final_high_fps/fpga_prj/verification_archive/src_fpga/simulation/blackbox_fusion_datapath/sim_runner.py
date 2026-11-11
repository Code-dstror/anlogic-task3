import hashlib
import json
import subprocess
import time
from pathlib import Path


BENCH_DIR = Path(__file__).resolve().parent
PROJECT = BENCH_DIR.parents[2]
WALL_SECONDS = 60


def fingerprint(files):
    return {str(path.resolve()): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


class SimFailure(Exception):
    def __init__(self, status, reason):
        super().__init__(reason)
        self.status = status


class Simulator:
    def __init__(self, run_dir, modelsim_bin, overall_seconds):
        self.run_dir = run_dir.resolve()
        if self.run_dir.parent != PROJECT / "tmp" or not self.run_dir.name.startswith(
            "blackbox_fusion_datapath_"
        ):
            raise ValueError("run directory must be a new project tmp/blackbox_fusion_datapath_* directory")
        self.run_dir.mkdir()
        self.modelsim_bin = modelsim_bin.resolve()
        self.deadline = time.monotonic() + overall_seconds
        self.commands = []

    def invoke(self, cwd, logfile, tool, *arguments, simulation=False):
        command = [str(self.modelsim_bin / f"{tool}.exe"), *map(str, arguments)]
        log = cwd / logfile
        timeout = min(WALL_SECONDS, self.deadline - time.monotonic())
        self.commands.append({"argv": command, "cwd": str(cwd), "log": str(log), "timeout": timeout})
        write_json(self.run_dir / "commands.json", self.commands)
        if timeout <= 0:
            raise SimFailure("BLOCKED", "overall wall watchdog expired")
        started = time.monotonic()
        try:
            with log.open("wb") as stream:
                result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                        timeout=timeout, check=False)
        except subprocess.TimeoutExpired as failure:
            raise SimFailure("BLOCKED", f"wall watchdog expired in {log}") from failure
        except OSError as failure:
            raise SimFailure("BLOCKED", f"could not launch {tool}, see {log}") from failure
        self.commands[-1].update(return_code=result.returncode, elapsed=time.monotonic() - started)
        write_json(self.run_dir / "commands.json", self.commands)
        if result.returncode != 0 and not simulation:
            raise SimFailure("BLOCKED", f"{tool} exit {result.returncode}, see {log}")
        return result.returncode

    def library(self, cwd):
        cwd.mkdir()
        self.invoke(cwd, "vmap_copy.log", "vmap", "-c")
        self.invoke(cwd, "vlib.log", "vlib", "work")
        self.invoke(cwd, "vmap_work.log", "vmap", "work", "work")

    def simulate(self, cwd, name, top, pass_marker, fail_marker, *options):
        log = f"{name}.log"
        rc = self.invoke(cwd, log, "vsim", "-c", "-onfinish", "stop", *options, f"work.{top}",
                         "-do", "onerror {quit -code 2 -f}; run -all; quit -f", simulation=True)
        lines = (cwd / log).read_text(encoding="utf-8", errors="replace").splitlines()
        failures = [line for line in lines if fail_marker in line]
        if failures:
            raise SimFailure("FAIL", failures[0].removeprefix("# ").strip())
        if rc != 0 or not any(pass_marker in line for line in lines):
            raise SimFailure("BLOCKED", f"missing terminal PASS or simulator startup failed, see {cwd / log}")
        return [line.removeprefix("# ").strip() for line in lines if "_PASS " in line]
