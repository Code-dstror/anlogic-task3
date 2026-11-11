"""Run only the public-pin IMX415 configuration tests in a private ModelSim library."""

import argparse
import hashlib
import json
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RTL = PROJECT / "src_fpga" / "rtl"
DUT_SOURCES = [RTL / f"{name}.v" for name in (
    "imx415_sensor_config", "imx415_sensor_recipe", "imx415_mode_table",
    "imx415_hdr2_recipe_rom", "camera_i2c_write",
)] + [PROJECT / "src_fpga" / "ip" / "vendor" / "anlogic_camera" / "sensor" / "ui_imx415_reg.v"]
BENCH = HERE / "tb_camera_config.sv"
WALL_TIMEOUT_SECONDS = 60


def cases():
    for scenario in (
        "dual_same", "dual_stagger", "dual_nack", "dual_lock", "sdr_roundtrip",
        "wake_abort", "wake_reset", "bit_reset", "bit_lock", "hdr_recipe", "hdr_abort",
        "hdr_fault", "production_defaults",
    ):
        yield scenario, scenario, []
    for ordinal in (1, 102, 203):
        for byte in range(4):
            yield f"nack_{ordinal:03d}_byte{byte}", "nack", [
                f"+NACK_TRANSFER={ordinal}", f"+NACK_BYTE={byte}",
            ]


def inputs():
    return {
        path.relative_to(PROJECT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [*DUT_SOURCES, BENCH, Path(__file__).resolve()]
    }


def execute(args, output_dir, log_name):
    started = time.monotonic()
    try:
        result = subprocess.run(
            [str(arg) for arg in args], cwd=output_dir, check=False,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=WALL_TIMEOUT_SECONDS,
        )
        output, exit_code, timed_out = result.stdout, result.returncode, False
    except subprocess.TimeoutExpired as exc:
        output, exit_code, timed_out = exc.stdout or b"", None, True
    except OSError as exc:
        output, exit_code, timed_out = str(exc).encode("utf-8"), None, False

    (output_dir / log_name).write_bytes(output)
    return {
        "command": subprocess.list2cmdline([str(arg) for arg in args]),
        "log": log_name,
        "wall_seconds": round(time.monotonic() - started, 3),
        "exit_code": exit_code,
        "timed_out": timed_out,
    }, output.decode("utf-8", errors="replace")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--case", choices=[name for name, _, _ in cases()], action="append")
    args = parser.parse_args()

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    output_dir = PROJECT / "tmp" / "blackbox_camera_20261107" / stamp
    output_dir.mkdir(parents=True)
    print(f"Evidence {output_dir}", flush=True)
    modelsim = args.modelsim_bin.resolve()
    manifest = {
        "started_utc": stamp,
        "working_directory": str(output_dir),
        "per_command_wall_timeout_seconds": WALL_TIMEOUT_SECONDS,
        "inputs_sha256": inputs(),
        "commands": [],
        "cases": [],
    }

    def save_manifest():
        (output_dir / "results.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for name, command in (
        ("version", [modelsim / "vsim.exe", "-version"]),
        ("vlib", [modelsim / "vlib.exe", "work"]),
        ("compile_dut", [modelsim / "vlog.exe", "-work", "work", *DUT_SOURCES]),
        ("compile_tb", [modelsim / "vlog.exe", "-sv", "-work", "work", BENCH]),
    ):
        record, _ = execute(command, output_dir, f"{name}.log")
        manifest["commands"].append(record)
        save_manifest()
        print(f"{name} exit={record['exit_code']} wall={record['wall_seconds']:.3f}s", flush=True)
        if record["exit_code"] != 0:
            return 1

    for name, scenario, plusargs in cases():
        if args.case and name not in args.case:
            continue
        command = [
            modelsim / "vsim.exe", "-c", "-quiet", "-onfinish", "stop",
            "-wlf", f"{name}.wlf", "-l", f"{name}.transcript.log",
            "-do", "onerror {quit -f -code 2}; run -all; quit -f -code 0",
            f"-gDEFAULT_TIMING={int(scenario == 'production_defaults')}",
            "work.tb_camera_config", f"+CASE={scenario}", f"+TRACE={name}.csv", *plusargs,
        ]
        record, stdout = execute(command, output_dir, f"{name}.log")
        if record["timed_out"]:
            status = "TIMEOUT"
        elif record["exit_code"] == 0 and f"CASE_RESULT PASS {scenario}" in stdout and "ASSERT_FAIL" not in stdout:
            status = "PASS"
        elif "CASE_RESULT FAIL" in stdout or "ASSERT_FAIL" in stdout:
            status = "FAIL"
        else:
            status = "TOOL_ERROR"
        record.update(name=name, status=status, trace=f"{name}.csv")
        manifest["cases"].append(record)
        save_manifest()
        print(f"{status:10} {name:24} {record['wall_seconds']:7.3f}s", flush=True)

    manifest["inputs_unchanged_during_run"] = manifest["inputs_sha256"] == inputs()
    save_manifest()
    return int(not manifest["inputs_unchanged_during_run"] or any(
        record["status"] != "PASS" for record in manifest["cases"]
    ))


if __name__ == "__main__":
    raise SystemExit(main())
