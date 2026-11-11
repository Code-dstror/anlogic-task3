"""Run short, port-only ModelSim fixtures and retain source-bound evidence."""

import argparse
import hashlib
import json
import subprocess
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RTL = PROJECT / "src_fpga" / "rtl"
TIMEOUT_SECONDS = 60


def suite_inputs(name, td_root):
    if name == "stereo_cold_control":
        cases = [("registers", 1), ("commit", 1), ("commit", 2), ("app_lock", 1),
                 ("dma_lock", 2), ("reset_wait", 2)]
        return [RTL / "reset_release_sync.v", RTL / "stereo_cold_control.v"], ["04_include", "00_rtl"], [], cases
    if name == "real_hdr_pair_cycle_gate":
        cases = [("basic", 1), ("overlap", 1), ("drain_serial", 1), ("cancel", 1),
                 ("timeout_reset", 2)]
        return [RTL / "real_hdr_pair_cycle_gate.v"], ["04_include"], [], cases
    if name == "reset_pix":
        files = ("reset_release_sync_data", "frame_record_extension_builder", "frame_record_v3_join")
        return [RTL / f"{file}.v" for file in files], ["01_include", "04_include"], [], [("pix", 1), ("pix", 2)]

    if td_root is None:
        raise ValueError("--td-root is required for reset_dfi")
    td_sim = td_root / "sim_release"
    files = ("reset_release_sync_data", "jpeg_record_metadata_gate", "jpeg_record_metadata_store",
             "jpeg_metadata_read_arbiter", "lane_sparse_extension_checker", "td_sdp_ram40")
    sources = [RTL / f"{file}.v" for file in files]
    sources += [PROJECT / "src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
                td_sim / "common/al_phy_glbl.v"]
    td_models = ("ph1_logic_eram", "ph1_phy_eram", "ph1_phy_gsr", "ph1_logic_dram")
    sources += [td_sim / "ph1" / f"{file}.v" for file in td_models]
    return sources, ["01_include", "04_include"], ["work.PH1_PHY_GSR", "work.glbl"], [("dfi", 1), ("dfi", 2)]


def identities(files):
    result = {}
    for path in files:
        with path.open("rb") as source:
            result[str(path)] = hashlib.file_digest(source, "sha256").hexdigest()
    return result


def run_command(command, directory, name, deadline):
    log = directory / f"{name}.log"
    started = time.monotonic()
    record = {"argv": command, "log": log.name, "exit_code": None, "timed_out": False}
    budget = deadline - started - 3
    if budget <= 0:
        record["timed_out"] = True
        log.write_text("Suite wall-clock budget exhausted before launch.\n", encoding="utf-8")
        return record
    with log.open("wb") as output:
        with subprocess.Popen(command, cwd=directory, stdin=subprocess.DEVNULL,
                              stdout=output, stderr=subprocess.STDOUT) as process:
            try:
                record["exit_code"] = process.wait(timeout=budget)
            except subprocess.TimeoutExpired:
                record["timed_out"] = True
                try:
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                   timeout=2, check=False)
                except subprocess.TimeoutExpired:
                    pass
                if process.poll() is None:
                    process.kill()
                record["exit_code"] = process.wait()
    record["wall_seconds"] = round(time.monotonic() - started, 3)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", choices=("stereo_cold_control", "real_hdr_pair_cycle_gate",
                                          "reset_pix", "reset_dfi"))
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path)
    args = parser.parse_args()
    started = time.monotonic()
    deadline = started + TIMEOUT_SECONDS
    td_root = args.td_root.resolve() if args.td_root else None
    sources, include_ids, extra_tops, cases = suite_inputs(args.suite, td_root)
    includes = [RTL / "include" / item for item in include_ids]
    bench = HERE / f"tb_{args.suite}.sv"
    inputs = sources + [bench, Path(__file__).resolve()]
    for directory in includes:
        inputs += sorted(path for path in directory.iterdir() if path.is_file())
    command_root = args.modelsim_bin.resolve()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = PROJECT / "tmp" / "blackbox_timing_20261107" / args.suite / f"{stamp}-{uuid.uuid4().hex[:6]}"
    output.mkdir(parents=True)
    print(f"Evidence directory {output}", flush=True)
    manifest = {"suite": args.suite, "cwd": str(output), "timeout_seconds": TIMEOUT_SECONDS,
                "td_root": str(td_root) if td_root else None, "sha256_before": identities(inputs),
                "commands": [], "cases": []}

    def invoke(tool, arguments, name):
        record = run_command([str(command_root / f"{tool}.exe"), *arguments], output, name, deadline)
        manifest["commands"].append(record)
        return record

    def succeeded(record):
        return record["exit_code"] == 0 and not record["timed_out"]

    vlib = invoke("vlib", ["work"], "vlib")
    if succeeded(vlib):
        vlog = invoke("vlog", ["-sv", "-work", "work", *[f"+incdir+{path}" for path in includes],
                               *[str(path) for path in sources], str(bench)], "vlog")
        if succeeded(vlog):
            for case, profile in cases:
                name = f"{case}-p{profile}"
                reset_parameter = {"reset_pix": "SEPARATE", "reset_dfi": "EARLY"}.get(args.suite)
                overrides = [f"-g{reset_parameter}={int(profile == 1)}"] if reset_parameter else []
                record = invoke("vsim", ["-c", "-onfinish", "stop", *overrides,
                                         f"work.tb_{args.suite}", *extra_tops,
                                         f"+case={case}", f"+profile={profile}", "-do",
                                         "onerror {quit -code 2 -f}; run -all; quit -code 0 -f"], name)
                log = (output / record["log"]).read_text(encoding="utf-8", errors="replace")
                marker = f"BLACKBOX_PASS {args.suite} case={case} profile={profile}"
                failures = [line.split("BLACKBOX_FAIL ", 1)[1] for line in log.splitlines()
                            if line.startswith("# BLACKBOX_FAIL ")]
                passed = (succeeded(record) and marker in log and not failures and
                          "** Error:" not in log and "** Fatal:" not in log)
                status = "PASS" if passed else "FAIL" if failures else "BLOCKED"
                result = {"case": case, "profile": profile, "status": status, "failures": failures}
                manifest["cases"].append(result)
                print(f"{status} {name} {record['log']}", flush=True)
                for failure in failures:
                    print(failure, flush=True)
        else:
            print("BLOCKED compile, see vlog.log", flush=True)
    else:
        print("BLOCKED creating simulation library, see vlib.log", flush=True)

    manifest["sha256_after"] = identities(inputs)
    manifest["input_identity_match"] = manifest["sha256_before"] == manifest["sha256_after"]
    manifest["wall_seconds"] = round(time.monotonic() - started, 3)
    case_statuses = {result["status"] for result in manifest["cases"]}
    if "FAIL" in case_statuses:
        manifest["status"] = "FAIL"
    else:
        manifest["status"] = "PASS" if case_statuses == {"PASS"} else "BLOCKED"
    if not manifest["input_identity_match"]:
        manifest["status"] = "STALE"
    (output / "run.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{manifest['status']} {args.suite} elapsed={manifest['wall_seconds']:.3f}s", flush=True)
    return int(manifest["status"] != "PASS")


if __name__ == "__main__":
    raise SystemExit(main())
