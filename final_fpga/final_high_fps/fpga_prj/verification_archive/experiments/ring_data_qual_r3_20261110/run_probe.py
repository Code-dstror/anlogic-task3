"""Run a bounded native DFI ring and ordered FIFO timing comparison."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import sys
import xml.etree.ElementTree as ET

from prepare_ring import (
    BASE_COMMIT, BOUNDARY, COMMON, DDR, HERE, LEAF, PROJECT, RUN_ROOT,
    frozen_file, frozen_rtl, prepare,
)


NATIVE = PROJECT.parent / "camera_rate_r1/experiments/uhd_resources"
sys.path.insert(0, str(NATIVE))
from run import digest, run_native


RTL = (
    "ordered_frame_fifo_fence.v", "axis_frame_fifo_ip.v", "ordered_frame_egress.v",
    "ddr_extension_staging_ram.v", "lane_sparse_extension_checker.v", "td_sdp_ram40.v",
)
FIFO_ROOT = "ip/camera_packet_fifo_147x512"
RAM = "ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed"
IP = (f"{FIFO_ROOT}/camera_packet_fifo_147x512.xml", RAM + ".ipc")
ASSETS = (
    f"{FIFO_ROOT}/camera_packet_fifo_147x512.v",
    f"{FIFO_ROOT}/camera_packet_fifo_147x512.tcl",
    f"{FIFO_ROOT}/Design.xml", f"{FIFO_ROOT}/DesignConfiguration.xml",
    f"{FIFO_ROOT}/RTL/camera_packet_fifo_147x512_soft_fifo.v",
    f"{FIFO_ROOT}/RTL/camera_packet_fifo_147x512_soft_fifo_core.v",
    f"{FIFO_ROOT}/RTL/include/define.v",
    RAM + ".v", RAM + ".vhd",
)
HEADERS = (
    "rtl/include/01_include/pcie_record_v3_validate.vh",
    "rtl/include/04_include/pcie_protocol_v1.vh",
)
GROUPS = ("token_d", "fifo_ce", "fifo_data", "quiet_d", "hdr_d", "slot_d", "slot_ce", "asr", "f3")
TIMING = (
    "uhd_probe_Runs/syn_1/uhd_probe_gate.timing", "reopened.timing", "reopened_check.timing",
    "objects.txt", "f3_all.timing", "r3_all.timing",
    *(f"{start}_to_{group}.timing" for start in ("f3", "r3") for group in GROUPS),
    "f3_through_egress_to_fifo.timing", "r3_through_egress_to_fifo.timing",
)


def copy_assets(work):
    checksums = json.loads(frozen_file(PROJECT / "docs/SOURCE_SEAL.json"))["production_inputs"]
    for relative in (*IP, *ASSETS, *HEADERS):
        source = PROJECT / "src_fpga" / relative
        data = source.read_bytes()
        if sha256(data).hexdigest() != checksums[f"src_fpga/{relative}"]:
            raise ValueError(f"Current controlled asset differs from eade: {relative}")
        target = work / "include" / source.name if relative in HEADERS else work / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    package = (work / FIFO_ROOT).resolve()
    pending = [package / name for name in ("camera_packet_fifo_147x512.xml", "Design.xml", "DesignConfiguration.xml")]
    checked = set()
    ns = "{http://www.accellera.org/XMLSchema/IPXACT/1685-2014}"
    while pending:
        xml = pending.pop()
        if xml in checked:
            continue
        checked.add(xml)
        for entry in ET.parse(xml).iter(ns + "file"):
            name = entry.findtext(ns + "name")
            if not name:
                raise ValueError(f"Unnamed FIFO dependency in {xml}")
            path = (xml.parent / name).resolve()
            if not path.is_relative_to(package) or not path.is_file():
                raise ValueError(f"Missing or external FIFO dependency: {name}")
            if path.suffix == ".xml":
                pending.append(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--variant", required=True, choices=("baseline", "candidate"))
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("use a fresh ASCII run name")
    td_root = args.td_root.resolve()
    inputs = prepare(td_root)
    work = RUN_ROOT / args.name / args.variant
    work.mkdir(parents=True)
    for name in COMMON:
        shutil.copyfile(inputs / "common" / name, work / name)
    for name in (LEAF, BOUNDARY):
        shutil.copyfile(inputs / args.variant / name, work / name)
    for name, data in frozen_rtl(RTL).items():
        (work / name).write_bytes(data)
    copy_assets(work)
    shutil.copyfile(HERE / "ring_probe.v", work / "uhd_probe.v")
    for name in ("synth.tcl", "clock.sdc"):
        shutil.copyfile(HERE / name, work / name)
    sources = (*COMMON, LEAF, BOUNDARY, *RTL, *IP, "uhd_probe.v", "clock.sdc")
    (work / "sources.lst").write_bytes(("\n".join(sources) + "\n").encode("ascii"))
    if args.prepare_only:
        print(work)
        return 0
    relation_sources = frozen_rtl(("anlogic2026.v", "jpeg_record_metadata_gate.v", "full_raw_store.v", "hdr_eye_shared.v"))
    evidence = {
        "baseline_commit": BASE_COMMIT,
        "target": "dfi_ring_qualification",
        "variant": args.variant,
        "runner_sha256": digest(Path(__file__)),
        "source_preparer_sha256": digest(HERE / "prepare_ring.py"),
        "native_runner_sha256": digest(NATIVE / "run.py"),
        "production_wrapper_variant_sha256": digest(inputs / args.variant / DDR),
        "ready_relation_sources_sha256": {name: sha256(data).hexdigest() for name, data in relation_sources.items()},
        "functional_simulation": "NOT_RUN",
        "whole_design_synthesis": "NOT_RUN",
        "place_route": "NOT_RUN",
        "physical_sta": "NOT_RUN",
        "bitgen": "NOT_RUN",
        "board": "NOT_RUN",
    }
    return 0 if run_native(work, td_root, evidence, 170, TIMING) else 1


if __name__ == "__main__":
    sys.exit(main())
