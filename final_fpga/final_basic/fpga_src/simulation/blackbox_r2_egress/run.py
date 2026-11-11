"""Source-bound ModelSim runner for the independent r2 egress and HDR gates."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from uuid import uuid4


HERE = Path(__file__).resolve().parent
DESIGN = HERE.parents[1]
STAGE = DESIGN.parent
REPO = STAGE.parents[1]
REFERENCE = STAGE / "verification_reference"
GATES = {
    "tokens": ("tb_r2_egress_tokens", "R2_EGRESS_TOKENS"),
    "cdc": ("tb_r2_egress_cdc", "R2_EGRESS_CDC"),
    "hdr": ("tb_r2_hdr_fence", "R2_HDR_FENCE"),
}

INCLUDES = [
    DESIGN / "rtl/include/01_include",
    DESIGN / "rtl/include/04_include",
    DESIGN / "ip/camera_packet_fifo_147x512/RTL/include",
]
EGRESS_RTL = [
    "rtl/ordered_frame_egress.v",
    "rtl/ddr_extension_staging_ram.v",
    "rtl/lane_sparse_extension_checker.v",
    "rtl/td_sdp_ram40.v",
    "ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
]
CDC_RTL = [
    "rtl/reset_release_sync.v",
    "rtl/reset_release_sync_data.v",
    "rtl/ordered_frame_cdc.v",
    "rtl/ordered_frame_ingress.v",
    "rtl/ordered_frame_fifo_fence.v",
    "rtl/axis_frame_fifo_ip.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v",
    "ip/camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    "ip/camera_packet_fifo_147x512/camera_packet_fifo_147x512.v",
]
HDR_RTL = ["rtl/hdr_raw14_shared_transport4.v", "rtl/reset_release_sync.v"]
MODELS = [
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_logic_fifo.v",
    "ph1/ph1_logic_ramfifo.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_phy_fifoctrl.v",
]


def hashes(paths):
    result = {}
    for path in sorted(set(paths)):
        with path.open("rb") as handle:
            result[path.as_posix()] = hashlib.file_digest(handle, "sha256").hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--suite", choices=["all", *GATES], default="all")
    args = parser.parse_args()
    started = time.monotonic()
    deadline = started + 54
    suites = list(GATES) if args.suite == "all" else [args.suite]
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid4().hex[:8]
    run_dir = STAGE / "tmp/blackbox_r2_egress" / run_id
    run_dir.mkdir(parents=True)
    print(f"Evidence directory: {run_dir}", flush=True)
    msim = args.modelsim_bin.resolve()
    td = args.td_root.resolve()
    model_dir = td / "sim_release"
    models = [model_dir / name for name in MODELS]
    gsr = model_dir / "ph1/ph1_phy_gsr.v"
    eg = bool({"tokens", "cdc"} & set(suites))
    sources = []
    inputs = [Path(__file__).resolve()]
    if eg:
        sources += [DESIGN / name for name in EGRESS_RTL]
        inputs += [gsr, *models, HERE / "egress_vectors.sv", HERE / "egress_sink_checks.svh",
                   REFERENCE / "egress_public.md", REPO / "docs/pcie_protocol_v1.json"]
    if "cdc" in suites:
        sources += [DESIGN / name for name in CDC_RTL]
    if "hdr" in suites:
        sources += [DESIGN / name for name in HDR_RTL]
        inputs += [REFERENCE / "hdr_fence_public.md", REFERENCE / "hdr_fence_ports.txt"]
    inputs += sources + [HERE / f"{GATES[suite][0]}.sv" for suite in suites]
    status = {
        "suite": args.suite,
        "td_root": td.as_posix(),
        "python": sys.version,
        "commands": [],
        "gates": {suite: "NOT_RUN" for suite in suites},
    }
    child_env = os.environ.copy()
    child_env.pop("MODELSIM", None)

    def run(stage, tool, *arguments):
        argv = [str(msim / f"{tool}.exe"), *map(str, arguments)]
        log = run_dir / f"{stage}.log"
        command = {"argv": argv, "cwd": run_dir.as_posix(), "log": log.name}
        status["commands"].append(command)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("54 s tool budget exhausted")
        start = time.monotonic()
        with log.open("xb") as output:
            with subprocess.Popen(argv, cwd=run_dir, env=child_env, stdout=output,
                                  stderr=subprocess.STDOUT) as child:
                try:
                    rc = child.wait(timeout=remaining)
                except subprocess.TimeoutExpired:
                    try:
                        subprocess.run(["taskkill", "/pid", str(child.pid), "/t", "/f"],
                                       stdout=output, stderr=subprocess.STDOUT,
                                       timeout=3, check=False)
                    except (OSError, subprocess.TimeoutExpired):
                        pass
                    finally:
                        if child.poll() is None:
                            child.kill()
                    raise TimeoutError(f"{stage} exceeded the 54 s tool budget") from None
                finally:
                    command["elapsed_s"] = round(time.monotonic() - start, 3)
        command["returncode"] = rc
        if rc:
            raise RuntimeError(f"{stage} exited {rc}; see {log.name}")
        return log

    try:
        if eg:
            inputs += [path for folder in INCLUDES for path in folder.iterdir() if path.is_file()]
        status["input_sha256"] = hashes(inputs)
        version_log = run("model_version", "vsim", "-version")
        status["modelsim"] = version_log.read_text(encoding="utf-8", errors="replace").strip()
        run("ini", "vmap", "-c")
        run("vlib_work", "vlib", "work")
        run("vmap_work", "vmap", "work", "work")
        if eg:
            run("vlib_ph1", "vlib", "ph1")
            run("vmap_ph1", "vmap", "ph1", "ph1")
            run("compile_ph1", "vlog", "-work", "ph1", *models)
        args_rtl = []
        if eg:
            args_rtl += ["-L", "ph1", "+define+PH1", *[f"+incdir+{path}" for path in INCLUDES],
                         gsr]
        run("compile_rtl", "vlog", "-work", "work", *args_rtl, *dict.fromkeys(sources))
        bench = [HERE / "egress_vectors.sv"] if eg else []
        bench += [HERE / f"{GATES[suite][0]}.sv" for suite in suites]
        run("compile_testbench", "vlog", "-work", "work", "-sv", f"+incdir+{HERE}", *bench)
        for suite in suites:
            module, marker = GATES[suite]
            globals_ = ["-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl"] if suite != "hdr" else []
            try:
                log = run(f"sim_{suite}", "vsim", "-c", "-onfinish", "exit", *globals_,
                          f"work.{module}", "-do",
                          "onerror {quit -f -code 2}; run -all; quit -f -code 0")
                transcript = log.read_text(encoding="utf-8", errors="replace")
                if not re.search(rf"^\s*(?:#\s*)?{marker}\s+PASS\s*$", transcript, re.M):
                    raise RuntimeError(f"{marker} PASS absent; see {log.name}")
                status["gates"][suite] = "PASS"
            except (OSError, RuntimeError, TimeoutError) as error:
                status["gates"][suite] = str(error)
        if status["input_sha256"] != hashes(inputs):
            raise RuntimeError("a bound source or oracle changed during this run")
        status["result"] = "PASS" if all(value == "PASS" for value in status["gates"].values()) else "FAIL"
    except (OSError, RuntimeError, TimeoutError) as error:
        status["result"] = "FAIL"
        status["error"] = str(error)
    finally:
        status["elapsed_s"] = round(time.monotonic() - started, 3)
        (run_dir / "result.json").write_text(json.dumps(status, indent=2) + "\n", encoding="utf-8")
    print(status["result"], status["gates"], status.get("error", ""), flush=True)
    return 0 if status["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
