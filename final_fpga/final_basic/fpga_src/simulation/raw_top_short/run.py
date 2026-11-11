"""Bounded actual-TOP ARAW and legacy cold BAR checks at a crop boundary."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


HERE = Path(__file__).resolve().parent
SIM = HERE.parent
PROJECT = HERE.parents[2]
TOP = "tb_raw_top_short"
CASES = {"mono": 0, "dual": 1, "jpeg": 2}
TINY_HE_FALLBACK_PORTS = ("cancel_done", "decision_capture", "decision_collect", "decision_valid",
                          "accepted", "owner_match")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    parser.add_argument("--compile-only", action="store_true")
    parser.add_argument("--case", choices=(*CASES, "raw"), default="raw")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,40}", args.name):
        parser.error("use a fresh lower-case run name")
    td, ms = args.td_root.resolve(), args.modelsim_bin.resolve()
    run = PROJECT / "tmp/raw_top_short" / args.name
    run.mkdir(parents=True, exist_ok=False)

    bench = HERE / (TOP + ".sv")
    boundary = SIM / "unified_dual_rate/axi_boundaries.sv"
    fixture_file = SIM / "MAIN_FIXTURE.json"
    manifest_file = PROJECT / "SOURCE_MANIFEST.json"
    fixture = json.loads(fixture_file.read_text())
    manifest = json.loads(manifest_file.read_text())
    groups = {}
    for name, rows in fixture["groups"].items():
        group = []
        for row in rows:
            if "modes" in row and "dual" not in row["modes"]:
                continue
            path = td / row["td_model"] if "td_model" in row else PROJECT / row["path"]
            if path.name == "tb_dual_imx415.sv":
                path = bench
            elif path.name == "anlogic2026_s08_boundaries.sv":
                path = boundary
            group.append(path)
        groups[name] = group

    models = [td / path for path in fixture["models"]]
    includes = [HERE, *(PROJECT / path for path in fixture["include_dirs"])]
    production = [PROJECT / row["path"] for row in manifest["files"]]
    paths = set(production + models + [fixture_file, manifest_file, bench, boundary, Path(__file__)])
    for group in groups.values():
        paths.update(group)

    rom_root = run / "rom_init"
    rom_root.mkdir()
    for name, relative in fixture["local_rom_initializers"].items():
        source = PROJECT / relative
        body = source.read_text()
        depth = int(re.search(r"DEPTH\s*=\s*(\d+)", body)[1])
        values = {int(address, 16): value for address, value in
                  re.findall(r"(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;", body)}
        if set(values) != set(range(depth)):
            raise ValueError(f"incomplete ROM initializer {source}")
        target = rom_root / name
        target.write_text("".join(values[index] + "\n" for index in range(depth)))
        paths.update((source, target))

    queue = list(paths)
    while queue:
        path = queue.pop()
        if path.suffix not in (".v", ".sv", ".vh"):
            continue
        for name in re.findall(r'(?m)^\s*`include\s+"([^"\r\n]+)"', path.read_text(errors="replace")):
            found = next((directory / name for directory in [path.parent, *includes]
                          if (directory / name).is_file()), None)
            if found is None:
                raise FileNotFoundError(f"{path}: {name}")
            if found not in paths:
                paths.add(found)
                queue.append(found)
    inputs = {str(path.resolve()): digest(path) for path in sorted(paths)}
    defines = ["PH1", "R8_STAGE1", "R8_BASIC_PREPROCESS", "S08_CONFIGURED_CAPTURE", "S04_RAW_FRAME_STORE",
               "R8_HE_FIXED_CONFIG_SESSION", "F21_AUTO_FIXED_LUT_PROFILE=0", "DUAL_IMX415_MAIN=1"]
    if args.case == "jpeg":
        defines += ["R8_LIVE_F21", "R8_STAGE2_COMPACT_TRANSPORT", "R8_F21_FIXED_CONFIG_SESSION",
                    "S08_SIM_WIDTH=1920", "S08_SIM_HEIGHT=1080"]
    else:
        defines += ["RAW_TOP_TINY", "S08_SIM_WIDTH=12", "S08_SIM_HEIGHT=6"]
    defines += [f"fdct_mac19s14s_z33s_p34_m1p1_USE_{port}=1" for port in ("A", "CE", "PH1A", "RST", "Y", "Z")]
    identity_file = run / "source_identity.json"
    identity_file.write_text(json.dumps({"inputs": inputs, "defines": defines, "td_root": str(td),
        "modelsim_bin": str(ms), "fixture": str(bench), "production_count": len(production)}, indent=2) + "\n")
    result = {"status": "RUNNING", "scope": __doc__, "source_identity_sha256": digest(identity_file),
              "synthesis": "NOT_RUN", "pnr": "NOT_RUN", "routed_sta": "NOT_RUN", "board": "NOT_RUN",
              "compile_only": args.compile_only, "commands": {}, "cases": {}}
    started = time.monotonic()
    budget = 30 if args.compile_only else 180

    def command(label, *argv):
        remaining = budget - (time.monotonic() - started)
        if remaining <= 0:
            raise TimeoutError("bounded ModelSim wall budget exhausted")
        command_line = list(map(str, argv))
        result["commands"][label] = command_line
        log = run / (label + ".console.log")
        with log.open("w", encoding="utf-8") as output:
            process = subprocess.run(command_line, cwd=run, stdout=output, stderr=subprocess.STDOUT,
                                     timeout=remaining)
        body = log.read_text(errors="replace")
        if process.returncode or re.search(r"\*\* (Error|Fatal):", body):
            raise RuntimeError(f"{label} failed\n{body[-9000:]}")
        return body

    try:
        command("vmap", ms / "vmap.exe", "-c")
        for lib in ("work", "ph1"):
            command("lib_" + lib, ms / "vlib.exe", lib)
            command("map_" + lib, ms / "vmap.exe", lib, lib)
        command("models", ms / "vlog.exe", "-quiet", "-work", "ph1", *models)
        for name, group in groups.items():
            arguments = ["-quiet", "-work", "work", "-timescale", "1ns/1ps"]
            if name == "compile.args":
                arguments.append("-sv")
            arguments.extend("+define+" + define for define in defines)
            arguments.extend("+incdir+" + path.as_posix() for path in includes)
            argument_file = run / name
            argument_file.write_text("\n".join('"' + (part.as_posix() if isinstance(part, Path) else part) + '"'
                                                for part in [*arguments, *group]) + "\n")
            body = command(name, ms / "vlog.exe", "-f", argument_file)
            if "** Warning:" in body:
                raise RuntimeError(f"{name} has compiler warnings\n{body[-5000:]}")
        cases = ("mono", "dual") if args.case == "raw" else (args.case,)
        if args.compile_only:
            cases = cases[:1]
        action = "run 0; quit -f" if args.compile_only else "run -all; quit -f"
        for case in cases:
            transcript = run / (case + ".sim.log")
            command(case, ms / "vsim.exe", "-c", "-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl", "work." + TOP,
                    "-gROM_ROOT=" + rom_root.as_posix(), f"-gTEST_CASE={CASES[case]}", "-l", transcript, "-do", action)
            body = transcript.read_text(errors="replace")
            markers = [line.strip("# ") for line in body.splitlines() if "RESULT: PASS RAW_TOP_SHORT" in line]
            if not args.compile_only and len(markers) != 1:
                raise RuntimeError(f"{case} missing terminal check\n{body[-7000:]}")
            warnings = [line for line in body.splitlines() if "** Warning:" in line]
            owned = [line for line in warnings if "/src_fpga/rtl/" in line.replace("\\", "/")]
            # The 12x6 build uses the dormant non-F21 preprocessor. Its six
            # optional HE observation outputs are open in the real fallback.
            known = [line for line in owned if case != "jpeg" and "anlogic2026.v(" in line and (
                "Too few port connections for 'u_preprocess'.  Expected 57, found 51." in line
                or any(f"Missing connection for port 'o_he_source_{port}'." in line
                       for port in TINY_HE_FALLBACK_PORTS))]
            unexpected = [line for line in owned if line not in known]
            if unexpected:
                raise RuntimeError("unexpected owned runtime warnings\n" + "\n".join(unexpected))
            result["cases"][case] = {"markers": markers, "warnings": warnings,
                                     "known_tiny_fallback_warnings": known, "log_sha256": digest(transcript)}
        if any(digest(Path(path)) != expected for path, expected in inputs.items()):
            raise RuntimeError("source drift during short simulation")
        result["status"] = "PASS_ELABORATION_ONLY" if args.compile_only else "PASS"
        for case, outcome in result["cases"].items():
            print(result["status"], case, outcome["markers"], "warnings", len(outcome["warnings"]), flush=True)
    except Exception as error:
        result.update(status="FAIL", error=str(error))
        raise
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (run / "RESULTS.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
