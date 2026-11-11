"""Compile an opaque public projection and run bounded product-chain cases."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from verify_record import (
    GAINS,
    MAX_RGB_ERROR,
    SCENES,
    expected_raw_bytes,
    expected_rgb,
    read_gamma,
    validate_record,
)


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
PUBLIC = PROJECT / "verification_reference" / "fusion_product_public"
RUN_PREFIX = "blackbox_fusion_product_"
WALL_LIMIT = 180
SIM_LIMIT = 60
SLVERR_CASES = {"normal", "deadline", "stress"}
DEFINED_CASES = ("normal", "stopped", "deadline", "timeout")


class GateFailure(Exception):
    pass


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(paths):
    return {path.as_posix(): sha(path) for path in sorted(set(paths))}


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


class Gate:
    def __init__(self, out, modelsim):
        self.out = out
        self.modelsim = modelsim
        self.start = time.monotonic()
        self.env = os.environ.copy()
        self.env.pop("MODELSIM", None)
        self.commands = []

    def command(self, name, args, *, directory=None, timeout=WALL_LIMIT):
        directory = directory or self.out
        argv = [str(value) for value in args]
        log_path = directory / f"{name}.log"
        limit = min(timeout, WALL_LIMIT - (time.monotonic() - self.start))
        if limit <= 0:
            raise GateFailure("180-second compile and run deadline")
        entry = {"argv": argv, "cwd": str(directory), "timeout_seconds": limit,
                 "log": str(log_path)}
        self.commands.append(entry)
        write_json(self.out / "commands.json", self.commands)
        began = time.monotonic()
        print(f"RUN {name} log={log_path}", flush=True)
        with log_path.open("wb") as log:
            try:
                process = subprocess.Popen(
                    argv, cwd=directory, env=self.env, stdout=log, stderr=subprocess.STDOUT,
                    creationflags=subprocess.CREATE_NO_WINDOW,
                )
            except OSError as error:
                raise GateFailure(f"{name}: tool launch failed ({error})") from error
            try:
                returncode = process.wait(timeout=limit)
            except subprocess.TimeoutExpired as error:
                subprocess.run(
                    ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                    stdout=log, stderr=subprocess.STDOUT, timeout=5,
                    creationflags=subprocess.CREATE_NO_WINDOW, check=False,
                )
                process.wait(timeout=3)
                raise GateFailure(f"{name}: wall-clock timeout; inspect {log_path}") from error
            finally:
                entry["elapsed_seconds"] = time.monotonic() - began
                entry["returncode"] = process.poll()
                write_json(self.out / "commands.json", self.commands)
        if returncode:
            raise GateFailure(f"{name}: process exited {returncode}; inspect {log_path}")
        return log_path

    def msim(self, name, tool, *args, **kwargs):
        return self.command(name, [self.modelsim / f"{tool}.exe", *args], **kwargs)

    def compile(self, manifest, model_paths, sources, include_dirs):
        ini = self.out / "modelsim.ini"
        self.msim("tool_version", "vsim", "-version")
        self.msim("copy_ini", "vmap", "-c")
        self.env["MODELSIM"] = ini.as_posix()
        for library in ("work", "ph1"):
            path = self.out / library
            self.msim(f"create_{library}", "vlib", path)
            self.msim(f"map_{library}", "vmap", library, path.as_posix())
        gsr = [model for model in model_paths if model.name == "ph1_phy_gsr.v"]
        if len(gsr) != 1:
            raise GateFailure("compile manifest must contain exactly one PH1 GSR model")
        self.msim("compile_td_ph1", "vlog", "-work", "ph1",
                  *(model for model in model_paths if model not in gsr))
        self.msim("compile_gsr", "vlog", "-work", "work", *gsr)

        options = [f"+incdir+{path.as_posix()}" for path in include_dirs]
        options += [f"+define+{define}" for define in manifest["defines"]]
        mac = [source for source in sources if "fdct_mac19s14s_z33s_p34_m1p1" in source.name]
        if len(mac) != 2:
            raise GateFailure("compile manifest must contain exactly two fixed FDCT MAC inputs")
        self.msim("compile_fdct_mac", "vlog", "-work", "work", "-mfcu", *options, *mac)
        self.msim("compile_opaque_projection", "vlog", "-work", "work", *options,
                  *(source for source in sources if source not in mac))
        self.msim("compile_blackbox_bench", "vlog", "-work", "work", "-sv",
                  f"+incdir+{HERE.as_posix()}", HERE / "tb_fusion_product.sv")

    def prepare_and_simulate(self, case, sibling_tops, report):
        directory = self.out / case
        directory.mkdir()
        shutil.copyfile(self.out / "modelsim.ini", directory / "modelsim.ini")
        script_path = (PUBLIC / "prepare_rom.ps1").as_posix().replace("'", "''")
        self.command("prepare_rom", [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            "$ErrorActionPreference = 'Stop'; Import-Module Microsoft.PowerShell.Utility; "
            f"& '{script_path}' -SimDirectory (Get-Location).Path",
        ], directory=directory)
        rom = list((directory / "rom_init").rglob("*"))
        rom = [path for path in rom if path.is_file()]
        if len([path for path in rom if path.suffix == ".dath"]) != 13:
            raise GateFailure(f"{case}: expected thirteen ROM initialization DATH files")
        original_roms = json.loads(
            (directory / "rom_init/inputs.json").read_text(encoding="utf-8-sig"),
        )
        if len(original_roms) != 13:
            raise GateFailure(f"{case}: expected thirteen original ROM identities")
        for entry in original_roms:
            original = Path(entry["source"])
            relocated = Path(entry["destination"])
            if sha(original) != entry["source_sha256"].lower() or sha(relocated) != entry["sha256"].lower():
                raise GateFailure(f"{case}: ROM initialization hash mismatch for {relocated.name}")
            rom.append(original)
        before = fingerprint(rom)
        write_json(directory / "rom_before.json", before)
        try:
            log_path = self.msim(
                "simulate", "vsim", "-c", "-L", "ph1", "work.tb_fusion_product",
                *sibling_tops, f"+CASE={case}",
                "-onfinish", "stop", "-do", "run -all; quit -f",
                directory=directory, timeout=SIM_LIMIT,
            )
        finally:
            after = fingerprint(rom)
            write_json(directory / "rom_after.json", after)
            report["rom_unchanged"] = before == after
        if before != after:
            raise GateFailure(f"{case}: ROM bytes changed during simulation")
        log = log_path.read_text(encoding="utf-8", errors="replace")
        if re.search(r"\bBB_FAIL\b|\*\*\s+(?:Fatal|Error):", log):
            raise GateFailure(f"{case}: simulation diagnostic; inspect {log_path}")
        if not re.search(rf"BB_SIM_PASS\s+case={case}\s+geometry=[12]\s+pixel_cycles=\d+", log):
            raise GateFailure(f"{case}: no completed simulation marker; inspect {log_path}")
        if case in SLVERR_CASES and not re.search(r"BB_FAILURE_TERMINAL_PASS\s+seq=12\b", log):
            raise GateFailure(f"{case}: post-START SLVERR terminal marker missing")
        if case == "deadline" and len(re.findall(r"BB_DEADLINE_PASS\s+seq=(?:11|13)\b", log)) != 2:
            raise GateFailure("deadline: exact-deadline retirement markers missing")
        if case == "timeout" and (
            not re.search(r"BB_B_SERVICE\s+seq=11\b[^\r\n]+\bdelta=4097\b", log)
            or not re.search(r"BB_HARD_TIMEOUT_DRAINED\s+seq=11\b", log)
            or not re.search(r"BB_LINK_PERST_BOUNDARY\s+fault=1\b", log)
        ):
            raise GateFailure("timeout: committed late B drain or retained link fault marker missing")
        applied = re.findall(r"BB_CFG_APPLIED\s+session=([\da-fA-F]{8})\s+epoch=(\d+)", log)
        if len(applied) != 1:
            raise GateFailure(f"{case}: missing exact APPLIED identity")
        report["hdl"] = "PASS"
        (session, epoch), = applied
        return directory, log, int(session, 16), int(epoch)

    def verify_case(self, case, manifest, gamma, report):
        simulation = case
        if case == "timeout":
            fault_report = report["fault_and_drain"] = {"hdl": "RUNNING"}
            try:
                fault_dir, _, _, _ = self.prepare_and_simulate(case, manifest["sibling_tops"], fault_report)
                if any(fault_dir.glob("*.ajpg")):
                    raise GateFailure("timeout: unexpected successful AJPG in the faulted process")
            except (GateFailure, OSError, ValueError) as error:
                fault_report.update(hdl="FAIL", reason=str(error))
                raise
            # Start a new ModelSim process and work directory with a fresh GSR/DUT/DDR/host.
            simulation = "cold_recovery"
            report["recovery_scope"] = "fresh simulator process modeling full configuration/power-on"
        directory, log, session, epoch = self.prepare_and_simulate(
            simulation, manifest["sibling_tops"], report,
        )
        report["numerical"] = "RUNNING"
        from PIL import __version__ as pillow_version

        report["pillow_version"] = pillow_version
        metrics = {}
        for basename, (sequence, rgb) in SCENES[case].items():
            if not re.search(rf"BB_PRODUCT_PASS\s+file={basename}\s+seq={sequence}\b", log):
                raise GateFailure(f"{case}: missing real {basename} product retirement")
            metrics[basename] = validate_record(
                directory / f"{basename}.ajpg", sequence, session, epoch, rgb, gamma,
            )
            write_json(directory / "records.json", metrics)
        if any(max(value["max_abs_error_rgb8"]) > MAX_RGB_ERROR for value in metrics.values()):
            raise GateFailure(f"{case}: decoded pixel error exceeds {MAX_RGB_ERROR}; inspect records.json")
        report["numerical"] = "PASS"


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--run-name", required=True)
    parser.add_argument("--fixture", type=Path,
                        default=PROJECT / "tmp/fusion_product_projection/real_isp_a3")
    parser.add_argument("--case", choices=(*DEFINED_CASES, "stress", "both", "all"), default="both",
                        help="both runs normal/stopped; all adds deadline/timeout; stress reproduces the old failure")
    args = parser.parse_args()
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,60}", args.run_name) is None:
        parser.error("--run-name must be a simple unique directory suffix")
    return args


def main():
    args = parse_args()
    out = PROJECT / "tmp" / f"{RUN_PREFIX}{args.run_name}"
    out.mkdir(parents=True)
    gate = Gate(out, args.modelsim_bin.resolve())
    summary = {"status": "FAIL", "compile": "NOT_RUN", "cases": {},
               "python": sys.version, "python_exe": sys.executable,
               "td_root": str(args.td_root.resolve()), "td_model_release": "2026.2.210.850",
               "wall_seconds": WALL_LIMIT, "case_wall_seconds": SIM_LIMIT,
               "case_pixel_cycles": 200000}
    before = None
    try:
        manifest_path = args.fixture.resolve() / "compile.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        sources = [PROJECT / path for path in manifest["sources"]]
        model_paths = [args.td_root.resolve() / path for path in manifest["td_models"]]
        include_dirs = [PROJECT / path for path in manifest["include"]]
        includes = [path for folder in include_dirs for path in folder.rglob("*") if path.is_file()]
        gamma_path = PROJECT / "src_fpga/rtl/isp/color/gamma22_10to8.mif"
        paths = [
            manifest_path, manifest_path.with_name("uhd_integration_fixture_ports.vh"),
            PUBLIC / "CONTRACT.md", PUBLIC / "AXI_DEADLINE.md",
            PUBLIC.parent / "uhd_integration_public/CONTRACT.md",
            PUBLIC / "prepare_rom.ps1", PROJECT / "docs/pcie_protocol_v1.json",
            PROJECT / "docs/quality_control_v1.json", PROJECT / "docs/GEOMETRY_CONTROL_PUBLIC.md",
            PROJECT / "docs/UHD_CFG_PUBLIC.md", gamma_path,
            PROJECT.parent / "camera_hdr_quality_r1/docs/blackbox/ISP.md",
            PROJECT.parent / "camera_hdr_quality_r1/analysis/tone/PUBLIC_CONTRACT.md",
            PROJECT.parents[1] / "src_fpga/rtl/ddr/ddr_axi_two_client_arbiter_spec.md",
            *HERE.glob("*.py"), *HERE.glob("*.sv"), *HERE.glob("*.svh"),
            *sources, *model_paths, *includes,
        ]
        before = fingerprint(paths)
        write_json(out / "inputs_before.json", before)
        gamma = read_gamma(gamma_path)
        cases = {"both": DEFINED_CASES[:2], "all": DEFINED_CASES}.get(args.case, (args.case,))
        inputs = {
            case: {
                name: {
                    "sequence": sequence,
                    "raw_rgb10": rgb,
                    "expected_rgb8": expected_rgb(rgb, gamma),
                    "raw_input_sha256": hashlib.sha256(expected_raw_bytes(rgb)).hexdigest(),
                }
                for name, (sequence, rgb) in SCENES[case].items()
            }
            for case in cases
        }
        negative_rgb = (321, 280, 580)
        for case in (item for item in cases if item in SLVERR_CASES):
            inputs[case]["slverr"] = {
                "sequence": 12, "raw_rgb10": negative_rgb,
                "raw_input_sha256": hashlib.sha256(expected_raw_bytes(negative_rgb)).hexdigest(),
            }
        if "timeout" in cases:
            timeout_seq, timeout_rgb = SCENES["normal"]["first"]
            inputs["timeout"]["timed_out"] = {
                "sequence": timeout_seq, "raw_rgb10": timeout_rgb,
                "raw_input_sha256": hashlib.sha256(expected_raw_bytes(timeout_rgb)).hexdigest(),
            }
        write_json(out / "scenes.json", {"manual_wb_q8": GAINS, "cases": inputs})
        summary["compile"] = "RUNNING"
        gate.compile(manifest, model_paths, sources, include_dirs)
        summary["compile"] = "PASS"
        case_failed = False
        for case in cases:
            report = summary["cases"][case] = {"hdl": "RUNNING", "numerical": "NOT_RUN"}
            try:
                gate.verify_case(case, manifest, gamma, report)
            except (GateFailure, OSError, ValueError, ImportError) as error:
                case_failed = True
                report["reason"] = str(error)
                for stage in ("hdl", "numerical"):
                    if report[stage] == "RUNNING":
                        report[stage] = "FAIL"
        if not case_failed:
            summary["status"] = "PASS"
    except (GateFailure, OSError, ValueError, ImportError) as error:
        summary["reason"] = str(error)
        if summary["compile"] == "RUNNING":
            summary["compile"] = "FAIL"
    finally:
        if before is not None:
            after = fingerprint(paths)
            write_json(out / "inputs_after.json", after)
            summary["inputs_unchanged"] = before == after
            if before != after:
                summary["status"] = "FAIL"
                summary["reason"] = "source, tool model or test inputs changed during the gate"
        summary["elapsed_seconds"] = time.monotonic() - gate.start
        if summary["elapsed_seconds"] > WALL_LIMIT:
            summary["status"] = "FAIL"
            summary["reason"] = "180-second compile and run deadline exceeded"
        write_json(out / "summary.json", summary)
    print(f"{summary['status']} {out / 'summary.json'}")
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
