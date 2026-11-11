"""Prepare and optionally compile one sealed JPEG source set, with no testbench."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import subprocess


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
MANIFEST = HERE / "compile.json"
TIMEOUT_SECONDS = 90


def checked_file(root, record, identities):
    path = (root / record["path"]).resolve()
    data = path.read_bytes()
    digest = sha256(data).hexdigest()
    if digest != record["sha256"]:
        raise ValueError(f"Frozen input differs: {path}")
    identities[str(path)] = digest
    return str(path)


def rom_bytes(raw, expected_words):
    body = raw.decode("ascii")
    depth = re.search(r"(?m)^DEPTH\s*=\s*(\d+)\s*;", body)
    values = re.findall(r"(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;", body)
    words = {int(address, 16): value for address, value in values}
    if (not depth or int(depth[1]) != expected_words or len(values) != expected_words
            or set(words) != set(range(expected_words))):
        raise ValueError("ROM addresses are not complete and unique")
    return "".join(words[index] + "\n" for index in range(expected_words)).encode("ascii")


def prepare(manifest, td_root, variant, run_dir):
    identities = {}
    models = [checked_file(td_root, source, identities) for source in manifest["model_sources"]]
    td_work = [checked_file(td_root, source, identities) for source in manifest["td_work_sources"]]
    vendor = [checked_file(PROJECT, source, identities)
              for source in manifest["vendor_verilog_sources"]]
    overrides = manifest["source_overrides"][variant]
    source_paths = {entry["path"] for entry in manifest["sources"]}
    if not overrides.keys() <= source_paths:
        raise ValueError("A source override has no base entry")
    rtl = [checked_file(PROJECT, overrides.get(source["path"], source), identities)
           for source in manifest["sources"]]
    for header in manifest["include_files"]:
        checked_file(PROJECT, header, identities)

    run_dir.mkdir(parents=True)
    roms = run_dir / "rom_init"
    roms.mkdir()
    for rom in manifest["rom_initializers"]:
        source = Path(checked_file(PROJECT, rom, identities))
        image = rom_bytes(source.read_bytes(), rom["words"])
        digest = sha256(image).hexdigest()
        if digest != rom["output_sha256"]:
            raise ValueError(f"Unexpected ROM image: {source}")
        target = run_dir / rom["output"]
        with target.open("xb") as stream:
            stream.write(image)
        identities[str(target)] = digest

    common_args = ["-work", "work", "-L", manifest["models_library"]]
    common_args.extend(f"+define+{name}" for name in manifest["defines"])
    common_args.extend(f"+incdir+{PROJECT / directory}" for directory in manifest["include_dirs"])
    return identities, [
        ["vlib", "work"],
        ["vlib", manifest["models_library"]],
        ["vmap", "-c"],
        ["vmap", "work", "work"],
        ["vmap", manifest["models_library"], manifest["models_library"]],
        ["vlog", "-work", manifest["models_library"], *models],
        ["vlog", *common_args, *manifest["vendor_verilog_extra_args"], *vendor],
        ["vlog", *common_args, *td_work, *rtl],
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    manifest = json.loads(MANIFEST.read_bytes())
    parser.add_argument("--variant", required=True, choices=manifest["source_overrides"])
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    if not run_dir.is_relative_to(PROJECT / "tmp") or run_dir == PROJECT / "tmp":
        parser.error("run directory must be a fresh subdirectory of camera_fusion_r1/tmp")
    identities, steps = prepare(manifest, args.td_root.resolve(), args.variant, run_dir)
    modelsim = args.modelsim_bin.resolve()
    commands = [[str(modelsim / f"{program}.exe"), *arguments] for program, *arguments in steps]
    receipt = {
        "variant": args.variant,
        "compile_manifest_sha256": sha256(MANIFEST.read_bytes()).hexdigest(),
        "compile_script_sha256": sha256(Path(__file__).read_bytes()).hexdigest(),
        "td_root": str(args.td_root.resolve()),
        "cwd": str(run_dir),
        "timeout_seconds_per_command": TIMEOUT_SECONDS,
        "commands": commands,
        "globals": manifest["globals"],
        "inputs_sha256": identities,
    }
    (run_dir / "compile_inputs.json").write_text(json.dumps(receipt, indent=2) + "\n",
                                                 encoding="utf-8")
    if not args.prepare_only:
        for index, command in enumerate(commands):
            log_path = run_dir / f"compile_{index:02}.log"
            with log_path.open("xb") as log:
                result = subprocess.run(command, cwd=run_dir, stdout=log, stderr=subprocess.STDOUT,
                                        check=False, timeout=TIMEOUT_SECONDS)
            if result.returncode:
                raise SystemExit(f"ModelSim step {index} exited {result.returncode}. "
                                 f"Send this log path to the maintainer: {log_path}")
        (run_dir / "compile.ok").write_text("COMPILE_ONLY\n", encoding="ascii")
    print(f"{args.variant} {'PREPARED' if args.prepare_only else 'COMPILE_ONLY_PASS'} {run_dir}")


if __name__ == "__main__":
    main()
