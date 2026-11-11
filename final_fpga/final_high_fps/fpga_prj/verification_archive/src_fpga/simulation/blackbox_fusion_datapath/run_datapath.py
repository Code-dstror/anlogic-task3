import argparse
import json
import re
import shutil
import sys
from pathlib import Path

from datapath_oracle import write_vectors
from sim_runner import BENCH_DIR, PROJECT, SimFailure, Simulator, fingerprint, write_json


QUALITY = PROJECT.parent / "camera_hdr_quality_r1"
PROJECT_SOURCES = (
    "src_fpga/rtl/shared_wide_isp.v",
    "src_fpga/rtl/raw_isp_top.v",
    "src_fpga/rtl/raw_blc.v",
    "src_fpga/rtl/raw_row_window.v",
    "src_fpga/rtl/raw_demosaic.v",
    "src_fpga/rtl/isp_line_ram_native4.v",
    "src_fpga/rtl/wide_color_pipeline.v",
    "src_fpga/rtl/hdr_tone96_shared4.v",
    "src_fpga/rtl/gamma_lut_10to8.v",
    "src_fpga/rtl/td_dsp_mult.v",
    "src_fpga/rtl/hdr_merge4.v",
    "src_fpga/simulation/assets/tone96_rom0_sim.v",
    "src_fpga/simulation/assets/tone96_rom1_sim.v",
    "src_fpga/simulation/assets/gamma_rom_8x1024_ip_sim.v",
    "src_fpga/ip/isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v",
    "src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/mult_18s18s_p1.v",
    "src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier.v",
    "src_fpga/ip/dsp_mult_fixed/mult_18s18s_p1/RTL/mult_18s18s_p1_multiplier_top.v",
    "src_fpga/ip/stage3/fdct_mac19s14s_z33s_p34_m1p1/fdct_mac19s14s_z33s_p34_m1p1.v",
    "src_fpga/ip/stage3/fdct_mac19s14s_z33s_p34_m1p1/RTL/fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v",
)
TD_MODELS = (
    "common/al_phy_glbl.v",
    "ph1/ph1_logic_eram.v",
    "ph1/ph1_phy_eram.v",
    "ph1/ph1_logic_mult.v",
    "ph1/ph1_phy_dspmult.v",
    "ph1/ph1_phy_dspmult_v2.v",
    "ph1/ph1_phy_dspsiou.v",
    "ph1/ph1_phy_dspadd_v2.v",
    "ph1/ph1_phy_dsptadd_v2.v",
    "ph1/ph1_phy_dsplogic_v2.v",
)
DEFINES = ["+define+PH1=1", *(f"+define+fdct_mac19s14s_z33s_p34_m1p1_USE_{flag}=1"
                            for flag in ("A", "CE", "PH1A", "RST", "Y", "Z"))]
BENCHES = [BENCH_DIR / f"{name}.sv" for name in ("stream_checker", "tb_hdr_merge", "tb_hdr_tone", "tb_color_path")]
CONTRACTS = [QUALITY / name for name in (
    "analysis/fusion/PUBLIC_CONTRACT.md", "analysis/tone/PUBLIC_CONTRACT.md", "docs/blackbox/ISP.md",
    "docs/blackbox/hdr_tone96_shared4.ports.vh", "docs/blackbox/shared_wide_isp.ports.vh",
    "docs/blackbox/wide_color_pipeline.ports.vh",
)]


def mif_values(path, count, width):
    """Decode only MIF initialization records. Tone data is not an oracle input."""
    raw = path.read_text(encoding="ascii")
    fields = dict(re.findall(r"(?i)(\w+)\s*=\s*(\w+)\s*;", raw))
    if int(fields["DEPTH"]) != count or int(fields["WIDTH"]) != width:
        raise ValueError(f"unexpected initialization dimensions for {path}")
    radix = {"HEX": 16, "UNS": 10, "DEC": 10, "BIN": 2, "OCT": 8}
    address_radix = radix[fields["ADDRESS_RADIX"]]
    data_radix = radix[fields["DATA_RADIX"]]
    values = {}
    records = re.findall(r"(?mi)^\s*(?:\[\s*([0-9a-f]+)\s*\.\.\s*([0-9a-f]+)\s*\]|([0-9a-f]+))"
                         r"\s*:\s*([0-9a-f]+)\s*;", raw)
    for first, last, address, data in records:
        start = int(first or address, address_radix)
        end = int(last or address, address_radix)
        value = int(data, data_radix)
        for index in range(start, end + 1):
            if index in values or not 0 <= index < count or value >= 1 << width:
                raise ValueError(f"invalid initialization record in {path}")
            values[index] = value
    if len(values) != count:
        raise ValueError(f"incomplete initialization in {path} ({len(values)}/{count})")
    return [values[index] for index in range(count)]


def build_arm(sim, cwd, project_files, gsr, data_files):
    sim.library(cwd)
    sim.invoke(cwd, "vmap_ph1.log", "vmap", "ph1", sim.run_dir / "ph1")
    sim.invoke(cwd, "vlog_gsr.log", "vlog", "-work", "work", gsr)
    sim.invoke(cwd, "vlog_dut.log", "vlog", "-L", "ph1", "-work", "work", *DEFINES, *project_files)
    sim.invoke(cwd, "vlog_tb.log", "vlog", "-sv", "-work", "work", f"+incdir+{sim.run_dir}", *BENCHES)
    for file in data_files:
        target = cwd / file.relative_to(sim.run_dir)
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(file, target)


def main():
    parser = argparse.ArgumentParser(description="HDR/Tone/color and real shared ISP black-box short gate")
    parser.add_argument("--modelsim-bin", required=True, type=Path)
    parser.add_argument("--td-root", required=True, type=Path)
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--color-candidate", type=Path)
    parser.add_argument("--cases", nargs="+", choices=("merge", "tone", "color", "isp"),
                        default=("merge", "tone", "color", "isp"))
    args = parser.parse_args()

    td_root = args.td_root.resolve(strict=True)
    td_files = [td_root / "sim_release" / name for name in TD_MODELS]
    gsr = td_root / "sim_release/ph1/ph1_phy_gsr.v"
    project_files = [PROJECT / name for name in PROJECT_SOURCES]
    gamma_mif = PROJECT / "src_fpga/rtl/isp/color/gamma22_10to8.mif"
    tone_mifs = [PROJECT / f"src_fpga/ip/coefficients/tone96_{part}.mif" for part in range(2)]
    inputs = [Path(__file__), BENCH_DIR / "datapath_oracle.py", BENCH_DIR / "sim_runner.py", *BENCHES,
              *CONTRACTS, *project_files, *td_files, gsr, gamma_mif, *tone_mifs]
    if args.color_candidate:
        inputs.append(args.color_candidate)
    sealed = fingerprint(inputs)

    overall_seconds = 180
    sim = Simulator(args.run_dir, args.modelsim_bin, overall_seconds)
    run = sim.run_dir
    write_json(run / "inputs.json", {"files": sealed, "python": sys.version, "td_root": str(td_root),
                                    "overall_seconds": overall_seconds})
    results = {}
    try:
        gamma = mif_values(gamma_mif, 1024, 8)
        counts = write_vectors(run, gamma)
        (run / "rom_init").mkdir()
        roms = ((gamma_mif, gamma, 8), *((path, mif_values(path, 512, 40), 40) for path in tone_mifs))
        data_files = [run / f"{name.lower()}.mem" for name in counts]
        for source, values, width in roms:
            target = run / "rom_init" / f"{source.name}.dath"
            target.write_text("".join(f"{value:0{width // 4}x}\n" for value in values), encoding="ascii")
            data_files.append(target)
        generated = fingerprint([*data_files, run / "vectors_sizes.vh"])
        write_json(run / "vectors.json", {"counts": counts, "files": generated})

        sim.invoke(run, "version.log", "vsim", "-version")
        sim.invoke(run, "vmap_copy.log", "vmap", "-c")
        sim.invoke(run, "vlib_ph1.log", "vlib", "ph1")
        sim.invoke(run, "vmap_ph1.log", "vmap", "ph1", "ph1")
        sim.invoke(run, "vlog_ph1.log", "vlog", "-work", "ph1", *td_files)

        original = PROJECT / "src_fpga/rtl/wide_color_pipeline.v"
        arms = {"production": project_files}
        if args.color_candidate:
            arms["color_candidate"] = [args.color_candidate.resolve() if path == original else path
                                       for path in project_files]
        case_commands = {
            "merge": ("tb_hdr_merge", "MERGE_PASS ", ()),
            "tone": ("tb_hdr_tone", "TONE_PASS ", ()),
            "color": ("tb_color_path", "COLOR_PASS ", ("-gISP=0",)),
            "isp": ("tb_color_path", "ISP_PASS ", ("-gISP=1",)),
        }
        globals_args = ("-L", "ph1", "work.PH1_PHY_GSR", "ph1.glbl")
        for arm, source_files in arms.items():
            cwd = run / arm
            try:
                build_arm(sim, cwd, source_files, gsr, data_files)
            except SimFailure as failure:
                results[arm] = {"status": failure.status, "reason": str(failure)}
                continue
            for case in args.cases:
                if arm == "color_candidate" and case in ("merge", "tone"):
                    continue
                top, marker, options = case_commands[case]
                try:
                    markers = sim.simulate(cwd, case, top, marker, "DATAPATH_FAIL", "-t", "1ps", *options,
                                           *globals_args)
                    results[f"{arm}_{case}"] = {"status": "PASS", "markers": markers}
                except SimFailure as failure:
                    results[f"{arm}_{case}"] = {"status": failure.status, "reason": str(failure)}
    except (SimFailure, ValueError, KeyError) as failure:
        results["setup"] = {"status": "BLOCKED", "reason": str(failure)}

    results["input_identity"] = {"status": "PASS" if sealed == fingerprint(inputs) else "STALE"}
    write_json(run / "results.json", results)
    print(json.dumps(results, indent=2))
    return 0 if all(result["status"] == "PASS" for result in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
