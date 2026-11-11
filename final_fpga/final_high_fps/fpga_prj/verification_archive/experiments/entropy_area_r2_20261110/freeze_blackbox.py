"""Bind a mapped candidate to an opaque JPEG compilation manifest."""

import argparse
import json
from pathlib import Path
import re
import shutil

from run_area import BASE_COMMIT, LEAF, PROJECT, REPO, RUN_ROOT, VARIANTS, digest, frozen_file


PUBLIC_JPEG = PROJECT.parent / "camera_rate_r3/verification_reference/jpeg_throughput_public"


def mapped_leaf(work, variant):
    evidence = json.loads((work / "evidence.json").read_bytes())
    leaf = work / "jpeg_entropy.v"
    mapped = evidence["status"] == "PASS"
    if evidence["status"] == "TIMEOUT":
        # A bounded first process may finish opt_gate before stopping in
        # reporting. Require its original artifacts and a completed reopen.
        reopen_log = work / "data_pins_device_td.log"
        original_reports = (
            "uhd_probe_Runs/syn_1/.opt_gate.end.f",
            "uhd_probe_Runs/syn_1/uhd_probe_gate.db",
            "uhd_probe_Runs/syn_1/uhd_probe_gate.area",
            "effective.params", "reopened.area",
        )
        mapped = (
            reopen_log.is_file()
            and "ENTROPY_AREA_DATA_PINS_REPORTED" in reopen_log.read_text(encoding="utf-8", errors="replace")
            and all(digest(work / report) == evidence["artifact_sha256"].get(report)
                    for report in original_reports)
        )
    if (not mapped or evidence["baseline_commit"] != BASE_COMMIT
            or evidence["variant"] != variant or evidence["input_sha256"][leaf.name] != digest(leaf)):
        raise ValueError(f"Source-bound native evidence required: {work}")
    return leaf


def freeze_blackbox(work, variant, compile_id, td_root):
    baseline = mapped_leaf(work / "baseline", "baseline")
    manifest = json.loads((PUBLIC_JPEG / "compile.json").read_bytes())
    seal_path = PROJECT / "docs/SOURCE_SEAL.json"
    seal = frozen_file(seal_path)
    checksums = json.loads(seal)["production_inputs"]
    leaf_key = f"src_fpga/{LEAF}"
    if digest(baseline) != checksums[leaf_key]:
        raise ValueError("Mapped baseline differs from the production seal")
    for group in ("sources", "vendor_verilog_sources", "include_files", "rom_initializers"):
        for entry in manifest[group]:
            relative = entry["path"]
            if not relative.startswith("src_fpga/simulation/assets/"):
                entry["sha256"] = checksums[relative]
            source = baseline if relative == leaf_key else PROJECT / relative
            if digest(source) != entry["sha256"]:
                raise ValueError(f"Compiler input differs: {relative}")
    for group in ("model_sources", "td_work_sources"):
        for entry in manifest[group]:
            if digest(td_root / entry["path"]) != entry["sha256"]:
                raise ValueError(f"TD simulation input differs: {entry['path']}")
    inputs = work / "blackbox_inputs" / compile_id
    overrides = {"production": {leaf_key: {
        "path": baseline.relative_to(PROJECT).as_posix(),
        "sha256": digest(baseline),
    }}}
    if variant == "baseline":
        inputs.mkdir(parents=True)
    else:
        candidate = mapped_leaf(work / variant, variant)
        opaque_candidate = inputs / "candidate/jpeg_entropy.v"
        opaque_candidate.parent.mkdir(parents=True)
        shutil.copyfile(candidate, opaque_candidate)
        overrides["candidate"] = {leaf_key: {
            "path": opaque_candidate.relative_to(PROJECT).as_posix(),
            "sha256": digest(opaque_candidate),
        }}
    manifest.update({
        "project_root": PROJECT.relative_to(REPO).as_posix(),
        "production_commit": BASE_COMMIT,
        "compiler_helper_sha256": digest(PUBLIC_JPEG / "compile_inputs.py"),
        "source_overrides": overrides,
    })
    output = inputs / "compile.json"
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--variant", required=True, choices=VARIANTS)
    parser.add_argument("--compile-id")
    parser.add_argument("--td-root", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("use an existing ASCII native run name")
    compile_id = args.compile_id or ("production" if args.variant == "baseline" else "qualification")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", compile_id):
        parser.error("use a fresh ASCII compile id")
    freeze_blackbox(RUN_ROOT / args.name, args.variant, compile_id, args.td_root.resolve())


if __name__ == "__main__":
    main()
