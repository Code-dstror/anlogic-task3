"""Run independent public-port and SDK gates in a fresh, source-sealed directory."""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]
RTL = PROJECT / "src_fpga/rtl"
REFERENCE = PROJECT / "verification_reference"
UART_TEST = HERE.parent / "blackbox_fusion_uart"
LEGACY_SDK = PROJECT.parent / "camera_rate_r3/rk_sdk"
NEW_SDK = PROJECT / "rk_sdk"
INCLUDES = ("00_rtl", "01_include", "03_mono_config_v2_20261015", "04_include")
COLD_RTL = [RTL / f"{name}.v" for name in (
    "reset_release_sync", "stereo_cold_control", "mono_pcie_app_regs_v2",
)]
UART_RTL = [RTL / f"{name}.v" for name in (
    "uart_status_observer", "camera_field_diagnostics", "uart_observer_snapshot", "cfg_diag_snapshot",
)]


def sha256_files(files):
    return {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(set(files))}


def source_files(td_root, groups):
    inputs = {Path(__file__).resolve(), PROJECT / "docs/pcie_protocol_v1.json"}
    if "cfg" in groups:
        manifest_path = REFERENCE / "QUALITY_CONFIG_INPUTS.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        roots = {"td_root": td_root, "project": PROJECT}
        inputs.update(roots[entry["root"]] / entry["path"]
                      for entry in manifest["sources"] + manifest["include_headers"])
        inputs.update({manifest_path, REFERENCE / "compile_quality_config.ps1",
                       HERE / "tb_fusion_config.sv", PROJECT / "docs/quality_control_v1.json"})
    if "cold" in groups or "uart" in groups:
        for include in INCLUDES:
            inputs.update((RTL / "include" / include).rglob("*.vh"))
    if "cold" in groups:
        inputs.update(COLD_RTL + [HERE / "tb_fusion_cold.sv"])
    if "uart" in groups:
        inputs.update(UART_RTL + [UART_TEST / "tb_fusion_uart.sv", UART_TEST / "check_uart.py",
                                  PROJECT / "tools/uart_observer.py", PROJECT / "docs/UART_FIELD_V4.md",
                                  REFERENCE / "UART_FIELD_V4_PORTS.vh"])
    if "sdk" in groups:
        inputs.update({HERE / "check_sdk.py", PROJECT / "docs/quality_control_v1.json",
                       REPO / "docs/pcie_protocol_v1.json"})
        packages = (NEW_SDK / "linux", NEW_SDK / "dual_host", LEGACY_SDK / "linux",
                    LEGACY_SDK / "dual_host", REPO / "linux")
        for package in packages:
            inputs.update(path for path in package.rglob("*.py")
                          if not {"test", "tests"}.intersection(path.relative_to(package).parts)
                          and not path.name.startswith("test_"))
    return inputs


class Run:
    def __init__(self, directory):
        self.directory = directory
        self.deadline = time.monotonic() + 175
        self.commands = []
        self.outcomes = {}

    def command(self, name, arguments, cwd, env=None, marker=None):
        command = list(map(str, arguments))
        log = self.directory / f"{name}.log"
        entry = {"name": name, "argv": command, "cwd": str(cwd), "log": log.name}
        self.commands.append(entry)
        if env is not None:
            entry["PYTHONPATH"] = env["PYTHONPATH"]
        timeout = min(55, self.deadline - time.monotonic())
        if timeout <= 0:
            self.outcomes[name] = "TIMEOUT"
            return False
        started = time.monotonic()
        with log.open("wb") as stream:
            child = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream,
                                     stderr=subprocess.STDOUT,
                                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            try:
                code = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
                                   creationflags=subprocess.CREATE_NO_WINDOW, check=False)
                if child.poll() is None:
                    child.kill()
                child.wait(timeout=1)
                entry["seconds"] = round(time.monotonic() - started, 3)
                self.outcomes[name] = "TIMEOUT"
                print(f"{name} TIMEOUT {log}", flush=True)
                return False
        entry["returncode"] = code
        entry["seconds"] = round(time.monotonic() - started, 3)
        if marker:
            output = log.read_text(encoding="utf-8", errors="replace")
            match = re.search(rf"(?m)^\s*(?:#\s*)?({re.escape(marker)}[^\r\n]*)", output)
            if match:
                entry["marker"] = match[1].strip()
        success = code == 0 and (not marker or "marker" in entry)
        self.outcomes[name] = "PASS" if success else "FAIL"
        print(f"{name} {self.outcomes[name]} {entry.get('marker', log)}", flush=True)
        return success


def cfg_cases(run, model_bin, td_root, shell):
    model_dir = run.directory / "cfg_model"
    model_dir.mkdir()
    compiled = run.command("cfg_design_compile", [
        shell, "-NoProfile", "-File", REFERENCE / "compile_quality_config.ps1",
        "-ModelSimBin", model_bin, "-TdRoot", td_root, "-WorkDir", model_dir,
    ], model_dir)
    if not compiled:
        return
    if not run.command("cfg_tb_compile", [model_bin / "vlog.exe", "-work", "work", "-sv",
                                          HERE / "tb_fusion_config.sv"], model_dir):
        return
    for name, scenario, quality in (
        ("cfg_hd_dual", "hd-dual", 1), ("cfg_hd_mono", "hd-mono", 1),
        ("cfg_uhd", "uhd", 1), ("cfg_featureless", "hd-mono", 0),
    ):
        run.command(name, [model_bin / "vsim.exe", "-c", "-onfinish", "stop",
                           "-l", run.directory / f"{name}.transcript", f"-gQUALITY_ENABLE={quality}",
                           "work.tb_fusion_config", "work.glbl", "work.PH1_PHY_GSR", f"+CASE={scenario}",
                           "-do", "run -all; quit -f"], model_dir, marker="FUSION_CFG_PASS")


def cold_case(run, model_bin):
    model_dir = run.directory / "cold_model"
    model_dir.mkdir()
    if not run.command("cold_vlib", [model_bin / "vlib.exe", "work"], model_dir):
        return
    include_args = [f"+incdir+{RTL / 'include' / name}" for name in INCLUDES]
    if not run.command("cold_compile", [model_bin / "vlog.exe", "-work", "work", "-sv", *include_args,
                                        *COLD_RTL, HERE / "tb_fusion_cold.sv"], model_dir):
        return
    run.command("cold", [model_bin / "vsim.exe", "-c", "-onfinish", "stop",
                         "-l", run.directory / "cold.transcript", "work.tb_fusion_cold",
                         "-do", "run -all; quit -f"], model_dir, marker="FUSION_COLD_PASS")


def sdk_cases(run):
    for edition, path in (("new", NEW_SDK), ("old", LEGACY_SDK)):
        env = dict(os.environ, PYTHONPATH=os.pathsep.join(map(str, (path, REPO))))
        run.command(f"sdk_{edition}", [sys.executable, "-B", "-u", HERE / "check_sdk.py",
                                       "--sdk", edition, "--sdk-root", path],
                    run.directory, env, marker="FUSION_SDK_PASS")


def uart_case(run, model_bin):
    model_dir = run.directory / "uart_model"
    model_dir.mkdir()
    if not run.command("uart_vlib", [model_bin / "vlib.exe", "work"], model_dir):
        return
    include_args = [f"+incdir+{RTL / 'include' / name}" for name in INCLUDES]
    if not run.command("uart_compile", [model_bin / "vlog.exe", "-work", "work", "-sv", *include_args,
                                        *UART_RTL, UART_TEST / "tb_fusion_uart.sv"], model_dir):
        return
    capture = model_dir / "uart_capture.bin"
    if not run.command("uart_serial", [model_bin / "vsim.exe", "-c", "-onfinish", "stop",
                                       "-l", run.directory / "uart_serial.transcript", "work.tb_fusion_uart",
                                       "+CAPTURE=uart_capture.bin", "-do", "run -all; quit -f"], model_dir,
                       marker="FUSION_UART_SERIAL_PASS"):
        return
    run.command("uart", [sys.executable, "-B", "-u", UART_TEST / "check_uart.py", capture],
                run.directory, marker="FUSION_UART_PASS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--only", choices=("all", "cfg", "cold", "sdk", "uart"), default="all")
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    tmp = (PROJECT / "tmp").resolve()
    if run_dir == tmp or not run_dir.is_relative_to(tmp):
        parser.error(f"--run-dir must be a new subdirectory of {tmp}")
    run_dir.mkdir(parents=True, exist_ok=False)
    run = Run(run_dir)
    td_root = args.td_root.resolve()
    model_bin = args.modelsim_bin.resolve()
    groups = ("cfg", "cold", "sdk") if args.only == "all" else (args.only,)
    inputs = source_files(td_root, groups)
    summary = {"python": sys.version, "python_executable": sys.executable, "td_root": str(td_root),
               "modelsim_bin": str(model_bin), "inputs_before": {}, "inputs_after": {}}
    try:
        summary["inputs_before"] = sha256_files(inputs)
        if {"cfg", "cold", "uart"}.intersection(groups):
            run.command("modelsim_version", [model_bin / "vsim.exe", "-version"], run_dir)
        if "cfg" in groups:
            shell = shutil.which("pwsh.exe") or shutil.which("powershell.exe")
            if shell is None:
                raise RuntimeError("Missing PowerShell for the opaque CFG compiler")
            cfg_cases(run, model_bin, td_root, shell)
        if "cold" in groups:
            cold_case(run, model_bin)
        if "sdk" in groups:
            sdk_cases(run)
        if "uart" in groups:
            uart_case(run, model_bin)
            capture = run.directory / "uart_model/uart_capture.bin"
            if capture.is_file():
                summary["outputs"] = sha256_files([capture])
        summary["inputs_after"] = sha256_files(inputs)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        summary["runner_error"] = str(error)
        print(f"runner error {error}", file=sys.stderr)
    finally:
        summary.update(commands=run.commands, outcomes=run.outcomes,
                       stable=summary["inputs_before"] == summary["inputs_after"] != {})
        (run_dir / "evidence.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    expected_terminals = {"cfg": {"cfg_hd_dual", "cfg_hd_mono", "cfg_uhd", "cfg_featureless"},
                          "cold": {"cold"}, "sdk": {"sdk_new", "sdk_old"}, "uart": {"uart_serial", "uart"}}
    required = set().union(*(expected_terminals[group] for group in groups))
    return int(not (summary["stable"] and required.issubset(run.outcomes)
                    and all(outcome == "PASS" for outcome in run.outcomes.values())))


if __name__ == "__main__":
    raise SystemExit(main())
