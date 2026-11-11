import argparse
import json
import random
import sys
from pathlib import Path

from datapath_oracle import fuse, lanes, pack
from run_datapath import DEFINES, QUALITY, TD_MODELS
from sim_runner import BENCH_DIR, PROJECT, SimFailure, Simulator, fingerprint, write_json


GROUPS = 68 // 4 * 63
WORDS = (GROUPS * 5 + 15) // 16

# camera, bank, preset, base, shift, scenario (0 OK, 1 SLVERR, 2 AR cancel,
# 3 held RAW cancel, 4 coordinated reset).
JOBS = (
    (0, 0, 0, 0, 15, 0), (1, 1, 1, 0, 15, 0),
    (0, 1, 0, 64, 7, 1), (1, 0, 1, 96, 9, 0),
    (1, 1, 0, 27, 6, 2), (0, 1, 0, 17, 8, 0),
    (1, 0, 1, 63, 3, 3), (0, 0, 1, 128, 15, 0),
    (0, 1, 0, 14, 10, 4), (1, 1, 0, 16383, 0, 0),
)

READER_SOURCES = (
    "src_fpga/simulation/quality_carriers/quality_hdr_reader_carrier.v",
    "src_fpga/rtl/hdr_pair_pixel_reader.v",
    "src_fpga/rtl/hdr_pair_read_cursor.v",
    "src_fpga/rtl/shared_raw10_decode_service.v",
    "src_fpga/rtl/shared_raw10_decoder_masked.v",
    "src_fpga/rtl/hdr_merge4.v",
    "src_fpga/rtl/ddr_response_bank16.v",
    "src_fpga/rtl/td_sdp_ram40.v",
    "src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v",
    "src_fpga/ip/stage3/fdct_mac19s14s_z33s_p34_m1p1/fdct_mac19s14s_z33s_p34_m1p1.v",
    "src_fpga/ip/stage3/fdct_mac19s14s_z33s_p34_m1p1/RTL/fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v",
)


def write_records(cwd):
    rng = random.Random(0xB4D6F1)
    job_file = cwd / "reader_jobs.mem"
    ddr_file = cwd / "reader_ddr.mem"
    rgb_file = cwd / "reader_raw.mem"
    with job_file.open("w", encoding="ascii") as jobs, ddr_file.open("w", encoding="ascii") as ddr, \
            rgb_file.open("w", encoding="ascii") as raw:
        for camera, bank, preset, base, shift, mode in JOBS:
            job = pack(zip((1, 1, 2, 14, 4, 3), (camera, bank, preset, base, shift, mode)))
            jobs.write(f"{job:07x}\n")
            members = [bytearray(), bytearray()]
            for index in range(GROUPS):
                if index % 17 == 0:
                    # D=112 in one lane, enough to separate the two presets when base=0.
                    long, short = (578, 178, 178, 178), (90, 58, 58, 58)
                elif index % 17 == 16:
                    long, short = (775, 776, 895, 896), (1023, 54, 55, 58)
                else:
                    long = tuple(rng.randrange(1024) for _ in range(4))
                    short = tuple(rng.randrange(1024 if index % 2 else 100) for _ in range(4))
                for payload, samples in zip(members, (long, short)):
                    payload.extend(lanes(samples, 10).to_bytes(5, "little"))
                result, motion = fuse(long, short, base, shift, preset)
                raw.write(f"{(motion << 56) | lanes(result, 14):015x}\n")
            for member, payload in enumerate(members):
                padding = [0xA0 + 8 * member + n for n in range(WORDS * 16 - len(payload))]
                payload.extend(padding)
                for offset in range(0, len(payload), 16):
                    ddr.write(f"{int.from_bytes(payload[offset:offset + 16], 'little'):032x}\n")
    header = cwd / "reader_sizes.vh"
    header.write_text(f"`define READER_JOBS {len(JOBS)}\n", encoding="ascii")
    return (job_file, ddr_file, rgb_file, header)


def main():
    parser = argparse.ArgumentParser(description="Independent short HDR reader-to-RESULT functional gate")
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--run-dir", required=True, type=Path)
    args = parser.parse_args()

    td_root = args.td_root.resolve(strict=True)
    td_files = [td_root / "sim_release" / name for name in TD_MODELS]
    gsr = td_root / "sim_release/ph1/ph1_phy_gsr.v"
    project_files = [PROJECT / name for name in READER_SOURCES]
    tb = BENCH_DIR / "tb_hdr_reader.sv"
    inputs = [Path(__file__), BENCH_DIR / "run_datapath.py", BENCH_DIR / "datapath_oracle.py",
              BENCH_DIR / "sim_runner.py", tb, QUALITY / "analysis/fusion/PUBLIC_CONTRACT.md",
              QUALITY / "docs/blackbox/READER.md", QUALITY / "docs/blackbox/READER_PORTS.vh",
              *project_files, *td_files, gsr]
    sealed = fingerprint(inputs)
    overall_seconds = 120
    sim = Simulator(args.run_dir, args.modelsim_bin, overall_seconds)
    run = sim.run_dir
    cwd = run / "reader"
    write_json(run / "inputs.json", {"files": sealed, "python": sys.version, "td_root": str(td_root),
                                    "overall_seconds": overall_seconds})
    results = {}
    try:
        sim.invoke(run, "version.log", "vsim", "-version")
        sim.library(cwd)
        generated = fingerprint(write_records(cwd))
        write_json(run / "vectors.json", {"files": generated, "jobs": JOBS, "groups_per_frame": GROUPS,
                                          "words_per_member": WORDS})
        sim.invoke(cwd, "vlib_ph1.log", "vlib", "ph1")
        sim.invoke(cwd, "vmap_ph1.log", "vmap", "ph1", "ph1")
        sim.invoke(cwd, "vlog_ph1.log", "vlog", "-work", "ph1", *td_files)
        sim.invoke(cwd, "vlog_gsr.log", "vlog", "-work", "work", gsr)
        sim.invoke(cwd, "vlog_dut.log", "vlog", "-L", "ph1", "-work", "work", *DEFINES, *project_files)
        sim.invoke(cwd, "vlog_tb.log", "vlog", "-sv", "-work", "work", f"+incdir+{cwd}", tb)
        markers = sim.simulate(cwd, "simulation", "tb_hdr_reader", "READER_PASS ", "READER_FAIL",
                               "-t", "1ps", "-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl")
        results["reader"] = {"status": "PASS", "markers": markers}
    except SimFailure as failure:
        results["reader"] = {"status": failure.status, "reason": str(failure)}

    results["input_identity"] = {"status": "PASS" if sealed == fingerprint(inputs) else "STALE"}
    write_json(run / "results.json", results)
    print(json.dumps(results, indent=2))
    return 0 if all(result["status"] == "PASS" for result in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
