"""Map one isolated, source-bound JPEG entropy area variant."""

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parents[1]
PARENT_PROBE = PROJECT.parent / "camera_rate_r1/experiments/uhd_resources"
sys.path.insert(0, str(PARENT_PROBE))
from run import digest, run_native


BASE_COMMIT = "eade457d7477110605f90eb5abc08420d8936642"
RUN_ROOT = PROJECT / "tmp/entropy_area_r2_20261110"
LEAF = "rtl/jpeg_entropy.v"
HUFF_IP = "ip/jpeg_rom_fixed/jpeg_rom_huff/jpeg_rom_huff"
RAM_IP = "ip/isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip"
SOURCES = (
    "rtl/jpeg_huff_ac_rom.v", "rtl/jpeg_quant_rom20x1024.v", "rtl/td_sdp_ram.v",
    HUFF_IP + ".ipc", RAM_IP + ".ipc",
)
ASSETS = (
    HUFF_IP + ".v", HUFF_IP + ".vhd", RAM_IP + ".v", RAM_IP + ".vhd",
    "rtl/include/02_jpeg/jpeg_quant_config.vh", "rtl/include/02_jpeg/jpeg_huff_rom.vh",
    "rtl/jpeg/quant_data/ac_huffman.mif",
)
READY_SOURCES = ("rtl/jpeg_encoder_top.v", "rtl/jpeg_file_formatter.v")
VARIANTS = ("baseline", "fused_slice", "mask", "coarse64")
TIMING = (
    "uhd_probe_Runs/syn_1/uhd_probe_gate.timing", "reopened.timing",
    "reopened_check.timing", "path_objects.txt", "count_to_reservoir.timing",
    "ready_to_reservoir.timing", "length_to_reservoir.timing",
    "ready_to_state.timing", "magnitude_to_ac_bits.timing",
)
READY_GROUPS = ("formatter", "buffer_valid", "buffer_last", "queue", "encoder", "abort_release")
READY_TIMING = (
    "uhd_probe_Runs/syn_1/uhd_probe_gate.timing", "reopened.timing",
    "reopened_check.timing", "path_objects.txt",
    *(f"{group}_to_reservoir_{pin}.timing" for group in READY_GROUPS for pin in ("d", "ce")),
)


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Expected exactly one occurrence in the frozen leaf")
    return source.replace(old, new)


def fused_slice(source):
    source = replace_once(
        source, "    reg [63:0] bits_work;\n",
        "    reg [63:0] bits_work;\n"
        "    reg [71:0] bits_before_drain;\n"
        "    reg append_selected;\n",
    )
    source = replace_once(
        source, "        bits_work = ac_byte_out ? (reservoir << 8) : reservoir;\n",
        "        append_selected = 1'b0;\n",
    )
    source = replace_once(
        source, "                bits_work = bits_work | (ac_byte_out ?\n"
        "                    aligned_append[63:0] : aligned_append[71:8]);\n",
        "                append_selected = 1'b1;\n",
    )
    source = replace_once(
        source, "            bits_work = bits_work | (ac_byte_out ?\n"
        "                aligned_append[63:0] : aligned_append[71:8]);\n",
        "            append_selected = 1'b1;\n",
    )
    return replace_once(
        source, "                                       count_with_symbol;\n"
        "        end\n"
        "    end\n",
        "                                       count_with_symbol;\n"
        "        end\n"
        "        // Merge in the pre-drain coordinate before selecting one fixed slice.\n"
        "        bits_before_drain = {reservoir, 8'd0};\n"
        "        if (append_selected)\n"
        "            bits_before_drain = bits_before_drain | aligned_append;\n"
        "        bits_work = ac_byte_out ? bits_before_drain[63:0] : bits_before_drain[71:8];\n"
        "    end\n",
    )


def amplitude_mask(source):
    source = replace_once(
        source, "    // The run nibble and the two scheduling limits have different needs.\n",
        "    function [9:0] ac_amplitude_mask;\n"
        "        input [3:0] category;\n"
        "        integer bit_index;\n"
        "        begin\n"
        "            for (bit_index=0; bit_index<10; bit_index=bit_index+1)\n"
        "                ac_amplitude_mask[bit_index] = category > bit_index[3:0];\n"
        "        end\n"
        "    endfunction\n"
        "    // The run nibble and the two scheduling limits have different needs.\n",
    )
    return replace_once(
        source, "{16'd0,((10'd1 << ac2_magnitude[k])-10'd1)}",
        "{16'd0,ac_amplitude_mask(ac2_magnitude[k])}",
    )


def coarse_alignment(source):
    source = replace_once(
        source, "    // Select their right-aligned payload before one shared 72-bit aligner.\n",
        "    // Select their right-aligned payload before one shared 64-bit aligner.\n",
    )
    source = replace_once(
        source, "    // Counts with bit 7 set shift the original 72-bit word entirely\n"
        "    // out of range. Keep that zero case explicit and use a seven-bit subtract.\n"
        "    wire [6:0] append_shift = 7'd72 - append_count[6:0];\n"
        "    wire [71:0] aligned_append = append_count[7] ? 72'd0 :\n"
        "        ({20'd0,append_payload} << append_shift);\n",
        "    // A valid append uses 1 to 64 bits after the optional drain.\n"
        "    // Draining a byte leaves the bit-within-byte shift unchanged.\n"
        "    wire [5:0] append_base_shift = 6'd0 - append_count[5:0];\n"
        "    wire [2:0] append_byte_shift = append_base_shift[5:3] + {2'b0,ac_byte_out};\n"
        "    wire [58:0] append_bit_aligned = {7'd0,append_payload} << append_base_shift[2:0];\n"
        "    wire [63:0] aligned_append = {5'd0,append_bit_aligned} << {append_byte_shift,3'b000};\n",
    )
    source = replace_once(
        source, "                bits_work = bits_work | (ac_byte_out ?\n"
        "                    aligned_append[63:0] : aligned_append[71:8]);\n",
        "                bits_work = bits_work | aligned_append;\n",
    )
    return replace_once(
        source, "            bits_work = bits_work | (ac_byte_out ?\n"
        "                aligned_append[63:0] : aligned_append[71:8]);\n",
        "            bits_work = bits_work | aligned_append;\n",
    )


def frozen_file(path):
    return subprocess.check_output(
        ["git", "show", f"{BASE_COMMIT}:{path.relative_to(REPO).as_posix()}"], cwd=REPO,
    )


def sealed_inputs(extra_sources=()):
    checksums = json.loads(frozen_file(PROJECT / "docs/SOURCE_SEAL.json"))["production_inputs"]
    paths = {}
    for relative in (*SOURCES, *ASSETS, *extra_sources):
        source = PROJECT / "src_fpga" / relative
        if digest(source) != checksums[f"src_fpga/{relative}"]:
            raise ValueError(f"Source differs from the fusion seal: {relative}")
        paths[relative] = source
    leaf = frozen_file(PROJECT / "src_fpga" / LEAF)
    if sha256(leaf).hexdigest() != checksums[f"src_fpga/{LEAF}"]:
        raise ValueError("Frozen entropy leaf differs from the fusion seal")
    return paths, leaf


def prepare(work, variant, ready_return=False, threads=16):
    inputs, leaf = sealed_inputs(READY_SOURCES if ready_return else ())
    work.mkdir(parents=True)
    for relative in (*SOURCES, *ASSETS):
        target = work / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(inputs[relative], target)
    if variant != "baseline":
        line_end = "\r\n" if b"\r\n" in leaf else "\n"
        source = leaf.decode("utf-8").replace("\r\n", "\n")
        if variant == "fused_slice":
            source = fused_slice(source)
        if variant == "mask":
            source = amplitude_mask(source)
        if variant == "coarse64":
            source = coarse_alignment(source)
        leaf = source.replace("\n", line_end).encode("utf-8")
    (work / "jpeg_entropy.v").write_bytes(leaf)
    probe = HERE / "ready_return_probe.v" if ready_return else PARENT_PROBE / "entropy_ab/entropy_probe.v"
    report = HERE / ("report_ready_return.tcl" if ready_return else "report_paths.tcl")
    shutil.copyfile(probe, work / "uhd_probe.v")
    shutil.copyfile(PARENT_PROBE / "clock.sdc", work / "clock.sdc")
    shutil.copyfile(report, work / "report_paths.tcl")
    synth = (PARENT_PROBE / "synth.tcl").read_text(encoding="ascii")
    synth = replace_once(synth, "add_include_dir .\n", "add_include_dir ./rtl/include/02_jpeg\n")
    synth = replace_once(synth, "set_param -run syn_1 flow thread 16\n",
                         f"set_param -run syn_1 flow thread {threads}\n")
    synth = replace_once(synth, "report_run_param syn_1 -file effective.params\n",
                         "report_run_param syn_1 -file effective.params\nsource report_paths.tcl\n")
    (work / "synth.tcl").write_bytes(synth.encode("ascii"))
    (work / "sources.lst").write_bytes(
        ("\n".join([*SOURCES, "jpeg_entropy.v", "uhd_probe.v", "clock.sdc"]) + "\n").encode("ascii")
    )
    return {relative: digest(inputs[relative]) for relative in READY_SOURCES} if ready_return else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--variant", required=True, choices=VARIANTS)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--ready-return", action="store_true")
    parser.add_argument("--threads", type=int, choices=(4, 16), default=16)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("use a fresh ASCII run name")
    if args.ready_return and args.variant not in ("baseline", "coarse64"):
        parser.error("use baseline or coarse64 with the production READY return cone")
    work = RUN_ROOT / args.name / args.variant
    ready_hashes = prepare(work, args.variant, args.ready_return, args.threads)
    if args.prepare_only:
        print(f"PREPARED {work}")
        return 0
    evidence = {
        "target": "entropy_area",
        "variant": args.variant,
        "baseline_commit": BASE_COMMIT,
        "runner_sha256": digest(Path(__file__)),
        "native_runner_sha256": digest(PARENT_PROBE / "run.py"),
        "requested_synthesis_threads": args.threads,
        "functional_simulation": "NOT_RUN",
        "whole_design_synthesis": "NOT_RUN",
        "place_route": "NOT_RUN",
        "physical_sta": "NOT_RUN",
        "bitgen": "NOT_RUN",
        "board": "NOT_RUN",
    }
    if ready_hashes:
        evidence["ready_return_logic_sha256"] = ready_hashes
    reports = READY_TIMING if args.ready_return else TIMING
    return 0 if run_native(work, args.td_root.resolve(), evidence, 170, reports) else 1


if __name__ == "__main__":
    sys.exit(main())
