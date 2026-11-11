"""Compare native opt_gate and reopen of isolated RAW10 capture ingress."""

import argparse
from hashlib import file_digest
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
LEAF = "shared_raw10_frame_ingress.v"
BASELINE = HERE / "baseline" / LEAF
BASELINE_SHA = "787acfaef657a6cf709f2e808bfdaaa2e750546d0dd89ed0b8800f3f227e7ccd"
TIMEOUT = 160
PROFILES = {
    "compact_uhd": (1, 0, 3840, 2160, {"i_camera": "1'b0", "i_source_camera": "1'b0"}),
    "fixed_long": (0, 1, 0, 0, {
        "i_camera": "1'b1", "i_source_camera": "1'b1",
        "i_accept": "1'b1", "i_sdr_profile": "1'b0", "i_uhd": "1'b0",
    }),
}
OPEN_OUTPUTS = {"o_drop_count", "o_error_count", "o_source_stale_count"}


def digest(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def ports(source):
    block = source.read_text(encoding="utf-8").split(") (", 1)[1].split("\n);", 1)[0]
    for line in block.splitlines():
        declaration = line.split("//", 1)[0].strip().rstrip(",")
        if not declaration:
            continue
        match = re.fullmatch(r"(input|output)\s+wire\s+(?:\[(\d+):(\d+)\]\s+)?(.+)", declaration)
        if match is None:
            raise ValueError(f"Unsupported port declaration: {declaration}")
        direction, left, right, names = match.groups()
        width = int(left) - int(right) + 1 if left is not None else 1
        for name in names.split(","):
            yield direction, width, name.strip()


def carrier(profile, declarations):
    compact, role, uhd_width, uhd_height, constants = PROFILES[profile]
    inputs = [(width, name) for direction, width, name in declarations
              if direction == "input" and name not in {"i_clk", "i_rst_n", *constants}]
    outputs = [(width, name) for direction, width, name in declarations
               if direction == "output" and name not in OPEN_OUTPUTS]
    in_bits = sum(width for width, _ in inputs)
    out_bits = sum(width for width, _ in outputs)
    padded = (out_bits + 31) // 32 * 32
    view_bits = (padded // 32 - 1).bit_length()
    lines = [
        "module raw_pack_probe(input wire i_clk, i_rst_n, load,",
        f"    input wire [31:0] stimulus_word, input wire [{view_bits - 1}:0] view,",
        "    output wire [31:0] observe);",
        f"    reg [{in_bits - 1}:0] stimulus;",
        f"    always @(posedge i_clk) if (load) stimulus <= {{stimulus[{in_bits - 33}:0],stimulus_word}};",
    ]
    offset = 0
    for width, name in inputs:
        lines.append(f"    wire [{width - 1}:0] {name} = stimulus[{offset}+:{width}];")
        offset += width
    for width, name in outputs:
        lines.append(f"    wire [{width - 1}:0] {name};")
    names = ",".join(name for _, name in outputs)
    lines.extend([
        f"    wire [{padded - 1}:0] results = {{{padded - out_bits}'d0,{names}}};",
        "    assign observe = results >> {view,5'b0};",
        "    shared_raw10_frame_ingress #(.WIDTH(1920), .HEIGHT(1080), .CONTEXT_ENABLE(1),",
        "        .EXTERNAL_SEQUENCE_ENABLE(1), .PAIR_METADATA_ENABLE(1), .SOURCE_TERMINAL_ENABLE(1),",
        f"        .FIXED_HDR_ROLE({role}), .COMPACT_CAPTURE_HEADER({compact}),",
        f"        .UHD_WIDTH({uhd_width}), .UHD_HEIGHT({uhd_height})) u_leaf (",
        ",\n".join(f"        .{name}({'' if name in OPEN_OUTPUTS else constants.get(name, name)})"
                    for _, _, name in declarations),
        "    );",
        "endmodule",
    ])
    return "\n".join(lines) + "\n"


def run(args, profile, variant):
    work = HERE / "runs" / args.name / profile / variant
    work.mkdir(parents=True)
    source = HERE / variant / LEAF
    declarations = list(ports(BASELINE))
    if declarations != list(ports(source)):
        raise SystemExit("Candidate ports differ from the fixed baseline")
    shutil.copyfile(source, work / LEAF)
    shutil.copyfile(HERE / "clock.sdc", work / "clock.sdc")
    (work / "raw_pack_probe.v").write_text(carrier(profile, declarations), encoding="ascii")
    wrapper = REPO / "tools" / "run_td.py"
    tcl = HERE / "synth.tcl"
    command = [sys.executable, "-B", str(wrapper), str(tcl), "--td-root", str(args.td_root),
               "--workdir", str(work), "--log", str(work / "td.log")]
    inputs = [work / LEAF, work / "raw_pack_probe.v", work / "clock.sdc", tcl, wrapper,
              REPO / ".agents/skills/anlogic-td-fpga/scripts/run_td.py",
              args.td_root / "bin/td_commands_prompt.exe", Path(__file__).resolve()]
    result = {
        "status": "RUNNING", "scope": "Leaf-only native opt_gate and reopen",
        "reference_sha256": BASELINE_SHA, "profile": profile, "variant": variant,
        "timeout_seconds": TIMEOUT, "command": command,
        "input_sha256": {str(path): digest(path) for path in inputs},
    }
    manifest = work / "RESULT.json"
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    start = time.monotonic()
    timed_out = False
    with (work / "launcher.log").open("wb") as log:
        process = subprocess.Popen(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                           stdout=log, stderr=subprocess.STDOUT, timeout=5, check=False)
            code = process.wait(timeout=5)
    native = work / "raw_pack_probe_Runs/syn_1"
    required = [work / "raw_pack_probe.al", work / "effective.params", work / "reopened.area",
                work / "reopened.timing", work / "td.log", native / "raw_pack_probe_gate.db",
                native / "raw_pack_probe_gate.area", native / ".opt_gate.end.f"]
    optional = [work / name for name in ("launcher.log", "objects.txt", "history_to_data.timing",
                                         "count_to_data.timing")] + [native / "run.log", native / "run.logw"]
    passed = (code == 0 and not timed_out and
              all(path.is_file() and path.stat().st_size for path in required[:-1]) and
              required[-1].is_file() and not list(native.glob(".*.error.f")) and
              "RAW_PACK_PROBE_NATIVE_REOPENED" in (work / "td.log").read_text(encoding="utf-8", errors="replace"))
    result.update(status="PASS" if passed else "TIMEOUT" if timed_out else "FAIL", exit_code=code,
                  elapsed_seconds=round(time.monotonic() - start, 3),
                  output_sha256={str(path.relative_to(work)): digest(path)
                                 for path in required + optional if path.is_file()})
    manifest.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"{profile}/{variant} {result['status']} in {result['elapsed_seconds']} s", flush=True)
    return passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--profile", choices=PROFILES, nargs="+", default=list(PROFILES))
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_-]+", args.name):
        parser.error("Use a fresh run name with lower-case letters, digits, underscores or dashes")
    args.td_root = args.td_root.resolve(strict=True)
    if digest(BASELINE) != BASELINE_SHA:
        raise SystemExit("Baseline SHA256 mismatch")
    results = [run(args, profile, variant) for profile in args.profile for variant in ("baseline", "candidate")]
    sys.exit(0 if all(results) else 1)
