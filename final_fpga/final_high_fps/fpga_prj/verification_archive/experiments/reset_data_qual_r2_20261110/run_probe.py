"""Measure the fixed-source PIX reset and data qualification variants."""

import argparse
from hashlib import sha256
from pathlib import Path
import re
import shutil
import sys

from prepare_inputs import BASE_COMMIT, COMMON, HERE, LEAF, PROJECT, RUN_ROOT, frozen_rtl, prepare


NATIVE = PROJECT.parent / "camera_rate_r1/experiments/uhd_resources"
sys.path.insert(0, str(NATIVE))
from run import digest, run_native


INGRESS = "shared_raw10_frame_ingress.v"
TIMING_GROUPS = ("qual_d", "ingress_d", "ingress_ce", "private_d", "private_ce", "asr", "f3")
TIMING = (
    "uhd_probe_Runs/syn_1/uhd_probe_gate.timing", "reopened.timing",
    "reopened_check.timing", "objects.txt",
    *(f"{reset}_to_{group}.timing" for reset in ("f3", "r3") for group in TIMING_GROUPS),
    "f3_all.timing", "r3_all.timing",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--variant", required=True, choices=("baseline", "candidate"))
    parser.add_argument("--td-root", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("use a fresh ASCII run name")
    inputs = prepare()
    work = RUN_ROOT / args.name / args.variant
    work.mkdir(parents=True)
    for name in COMMON:
        shutil.copyfile(inputs / "common" / name, work / name)
    shutil.copyfile(inputs / args.variant / LEAF, work / LEAF)
    (work / INGRESS).write_bytes(frozen_rtl((INGRESS,))[INGRESS])
    shutil.copyfile(HERE / "ready_probe.v", work / "uhd_probe.v")
    for name in ("synth.tcl", "clock.sdc"):
        shutil.copyfile(HERE / name, work / name)
    sources = (*COMMON, LEAF, INGRESS, "uhd_probe.v", "clock.sdc")
    (work / "sources.lst").write_bytes(("\n".join(sources) + "\n").encode("ascii"))
    wrapper_sources = frozen_rtl(("anlogic2026.v", "physical_camera_rgb_pipeline.v"))
    evidence = {
        "baseline_commit": BASE_COMMIT,
        "target": "original_source_pixel_reset",
        "variant": args.variant,
        "runner_sha256": digest(Path(__file__)),
        "source_preparer_sha256": digest(HERE / "prepare_inputs.py"),
        "native_runner_sha256": digest(NATIVE / "run.py"),
        "ready_relation_sources_sha256": {
            name: sha256(data).hexdigest() for name, data in wrapper_sources.items()
        },
        "functional_simulation": "NOT_RUN",
        "whole_design_synthesis": "NOT_RUN",
        "place_route": "NOT_RUN",
        "physical_sta": "NOT_RUN",
        "bitgen": "NOT_RUN",
        "board": "NOT_RUN",
    }
    return 0 if run_native(work, args.td_root.resolve(), evidence, 170, TIMING) else 1


if __name__ == "__main__":
    sys.exit(main())
