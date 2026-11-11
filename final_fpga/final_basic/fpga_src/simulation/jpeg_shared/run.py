"""Native row-stream 4:2:2 JPEG leaf, SRAM/ERAM/DSP models and independent byte oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REF = ROOT / "verification_reference/src_fpga/simulation"
sys.path.insert(0, str(REF))
import jpeg_shared_encoder_reference as reference


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--td-root", type=Path, required=True)
    parser.add_argument("--modelsim-bin", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,48}", args.name):
        parser.error("invalid evidence directory name")
    run = ROOT / "tmp/jpeg_shared" / args.name
    run.mkdir(parents=True, exist_ok=False)
    rom = run / "rom_init"
    rom.mkdir()
    fixture = json.loads((HERE.parent / "MAIN_FIXTURE.json").read_text())
    rtl = ROOT / "src_fpga/rtl"
    bench = HERE / "tb_jpeg_shared_encoder.sv"
    models = [args.td_root / s for s in fixture["models"]]
    mac = [ROOT / row["path"] for row in fixture["groups"]["mac_compile.args"]]
    jpeg = """jpeg_encoder_top jpeg_mcu_422 jpeg_mcu_read_align8 jpeg_mcu_packed_plane jpeg_dct8x8_pipeline
              jpeg_fdct1d jpeg_quant_sync_fifo jpeg_quant_stream jpeg_quant_table_rom
              jpeg_quant_rom10x2048 jpeg_quant_recip_rom40x512 jpeg_quant_rom20x1024
              jpeg_huff_ac_rom jpeg_entropy jpeg_byte_packer jpeg_file_formatter
              td_sdp_ram td_sdp_ram40 td_dsp_mult""".split()
    sources = [rtl / (n + ".v") for n in jpeg]
    color = rtl / "jpeg/jpeg_rgb_to_ycbcr_422.v"
    project = ROOT / "fpga_prj/rfcamera_shared_r1.al"
    if '../src_fpga/rtl/jpeg/jpeg_rgb_to_ycbcr_422.v' not in project.read_text(encoding="utf-8"):
        raise ValueError("unbound chroma implementation")
    sources += [color, args.td_root / "sim_release/ph1/ph1_phy_gsr.v"]
    for row in fixture["groups"]["compile.args"]:
        s = row.get("path", "")
        if any(key in s for key in ("/dsp_mult_fixed/", "/isp_line_ram_20x1024_ip/",
                                    "/ram40_sdp_fixed/", "/assets/jpeg_rom_")):
            sources.append(ROOT / s)
    includes = [ROOT / p for p in fixture["include_dirs"]]
    paths = set([*models, *mac, *sources, project, bench, Path(__file__),
                 REF / "jpeg_shared_encoder_reference.py",
                 ROOT / "verification_reference/tools/jpeg_ref/jpeg_ref.py",
                 ROOT / "verification_reference/tools/jpeg_ref/table_data.json",
                 ROOT / "verification_reference/src_fpga/rtl/jpeg/quant_data/q50_base.json",
                 HERE.parent / "MAIN_FIXTURE.json"])
    for name, relative in fixture["local_rom_initializers"].items():
        source = ROOT / relative
        body = source.read_text()
        depth = int(re.search(r"DEPTH\s*=\s*(\d+)", body).group(1))
        values = {int(a, 16): b for a, b in re.findall(r"(?m)^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;", body)}
        if values.keys() != set(range(depth)):
            raise ValueError(f"incomplete MIF {source}")
        path = rom / name
        path.write_text("".join(values[i]+"\n" for i in range(depth)))
        paths.update((path, source))
    for item in list(paths):
        if item.suffix in (".v", ".sv"):
            for name in re.findall(r'(?m)^\s*`include\s+"([^"]+)"', item.read_text(errors="replace")):
                hit = next((d / name for d in [item.parent, *includes] if (d/name).is_file()), None)
                if hit:
                    paths.add(hit)
    def snapshot():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}
    inputs = snapshot()
    (run/"inputs.json").write_text(json.dumps(inputs, indent=2))
    rows = [dict(case=1, width=240, height=8, quality=75, restart=0, pattern="noise"),
            dict(case=2, width=240, height=16, quality=37, restart=3, pattern="texture")]
    result = dict(status="RUNNING", td=str(args.td_root), cases=rows, commands=[])
    def tool(name, argv, log):
        cmd = [str(args.modelsim_bin / (name+".exe")), *map(str, argv)]
        result["commands"].append(cmd)
        with (run/(log+".log")).open("w") as out:
            proc = subprocess.run(cmd, cwd=run, stdout=out, stderr=subprocess.STDOUT, timeout=150)
        body = (run/(log+".log")).read_text(errors="replace")
        if proc.returncode or re.search(r"\*\* (Error|Fatal):", body):
            raise RuntimeError(log+" "+body[-6000:])
        return body
    try:
        for row in rows:
            reference.generate_frame(run,row)
        (run/"encoder_manifest.json").write_text(json.dumps(rows))
        tool("vmap", ["-c"], "vmap")
        for lib in ("work","ph1"):
            tool("vlib", [lib], "lib_"+lib)
            tool("vmap", [lib,lib], "map_"+lib)
        tool("vlog", ["-quiet","-work","ph1",*models], "models")
        opts = ["-quiet","-work","work","-timescale","1ns/1ps","+define+PH1","+define+R8_STAGE1",
                *["+incdir+"+str(p) for p in includes]]
        defs = ["+define+fdct_mac19s14s_z33s_p34_m1p1_USE_"+p+"=1" for p in ("A","CE","PH1A","RST","Y","Z")]
        tool("vlog", [*opts,*defs,*mac], "mac")
        af = run/"compile.args"
        af.write_text("\n".join('"'+str(p).replace("\\","/")+'"' for p in [*opts,*defs,"-sv",*sources,bench]))
        tool("vlog", ["-f",af], "compile")
        for row in rows:
            body = tool("vsim", ["-c","-L","ph1","work.PH1_PHY_GSR","ph1.glbl","work.tb_jpeg_shared_encoder",
                        "-gROM_ROOT="+rom.as_posix(),"-gOUTPUT_STALLS=1",
                        *["-g"+k+"="+str(row[key]) for k,key in (("CASE_INDEX","case"),("WIDTH","width"),
                              ("HEIGHT","height"),("QUALITY","quality"),("RESTART","restart"),("EXPECTED_BYTES","bytes"))],
                        "-do","run -all; quit -f"], "case"+str(row["case"]))
            if "RESULT: PASS shared encoder" not in body:
                raise RuntimeError("self-check incomplete")
            row["metrics"] = [l.strip() for l in body.splitlines() if "ENCODER_METRIC" in l or "RESULT: PASS" in l]
        reference.check(run,{r["case"] for r in rows})
        if snapshot() != inputs:
            raise ValueError("input changed during test")
        result["status"] = "PASS"
    except Exception as exc:
        result.update(status="FAIL", error=str(exc))
        raise
    finally:
        (run/"result.json").write_text(json.dumps(result, indent=2))
    print("RESULT: PASS JPEG_SHARED", run)


if __name__ == "__main__":
    main()
