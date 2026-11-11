"""Qualify physical live-SOF admission through the real small wide ISP."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--pipeline-source', type=Path)
    ap.add_argument('--expect-leak', type=int, choices=(0, 1), default=0)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,47}', a.name):
        ap.error('name must be unique lowercase run identifier')
    run = ROOT / 'tmp/first_job_r1' / a.name
    run.mkdir(parents=True, exist_ok=False)
    td, ms = a.td_root.resolve(), a.modelsim_bin.resolve()
    models = [td / 'sim_release' / p for p in (
        'common/al_phy_glbl.v', 'ph1/ph1_logic_eram.v', 'ph1/ph1_phy_eram.v',
        'ph1/ph1_logic_mult.v', 'ph1/ph1_phy_dspmult.v', 'ph1/ph1_phy_dspmult_v2.v')]
    sources = [td / 'sim_release/ph1/ph1_phy_gsr.v'] + [ROOT / p for p in (
        'src_fpga/ip/isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v',
        'src_fpga/rtl/reset_release_sync.v', 'src_fpga/rtl/physical_camera_crop.v',
        'src_fpga/rtl/isp_line_ram_native4.v', 'src_fpga/rtl/raw_blc.v', 'src_fpga/rtl/raw_row_window.v',
        'src_fpga/rtl/raw_demosaic.v', 'src_fpga/rtl/raw_isp_top.v', 'src_fpga/rtl/shared_wide_isp.v',
        'src_fpga/rtl/wide_color_pipeline.v', 'src_fpga/rtl/td_dsp_mult.v',
        'src_fpga/rtl/hdr_tone96_shared4.v', 'src_fpga/rtl/gamma_lut_10to8.v',
        'src_fpga/simulation/assets/gamma_rom_8x1024_ip_sim.v',
        'src_fpga/simulation/assets/tone96_rom0_sim.v', 'src_fpga/simulation/assets/tone96_rom1_sim.v')]
    for ip in ('mult_14u10u_p1', 'mult_15s11s_p1', 'mult_18s18s_p1'):
        base = ROOT / 'src_fpga/ip/dsp_mult_fixed' / ip
        sources += [base / 'RTL' / f'{ip}_multiplier.v', base / 'RTL' / f'{ip}_multiplier_top.v', base / f'{ip}.v']
    sources += [(a.pipeline_source.resolve() if a.pipeline_source else ROOT / 'src_fpga/rtl/physical_camera_rgb_pipeline.v'),
                HERE / 'tb_live_gate.sv']
    rom_dir = run / 'rom_init'
    rom_dir.mkdir()
    rom_paths = []
    for dest, relative in {
        'gamma22_10to8.mif.dath': 'src_fpga/rtl/isp/color/gamma22_10to8.mif',
        'tone96_0.mif.dath': 'src_fpga/ip/coefficients/tone96_0.mif',
        'tone96_1.mif.dath': 'src_fpga/ip/coefficients/tone96_1.mif',
    }.items():
        path = ROOT / relative
        body = path.read_text()
        depth = int(re.search(r'DEPTH\s*=\s*(\d+)', body).group(1))
        width = int(re.search(r'WIDTH\s*=\s*(\d+)', body).group(1))
        values = {int(k, 16): int(v, 16) for k, v in re.findall(r'(?m)^\s*([\da-fA-F]+)\s*:\s*([\da-fA-F]+)\s*;', body)}
        if set(values) != set(range(depth)):
            raise ValueError(f'incomplete canonical MIF {path}')
        dest_path = rom_dir / dest
        dest_path.write_text(''.join(f'{values[i]:0{(width+3)//4}X}\n' for i in range(depth)))
        rom_paths += [path, dest_path]
    paths = models + sources + rom_paths + [Path(__file__).resolve()]
    identity = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
    (run / 'SOURCE_START.json').write_text(json.dumps(identity, indent=2) + '\n')
    q = dict(status='RUNNING', simulation='RUNNING', expect_leak=a.expect_leak,
             pipeline_source=sources[-2].as_posix(), td_root=td.as_posix(), modelsim_bin=ms.as_posix(),
             scope='actual physical crop/elastic boundary/wide ISP, official RAM/DSP, canonical ROMs, legal 8x3 RAW BFM; no production TOP/DDR/JPEG/PCIe',
             synthesis='NOT_RUN', physical='NOT_RUN', timing='NOT_RUN', board='NOT_RUN', board_root_cause='NOT_ESTABLISHED')
    started = time.monotonic()

    def command(words):
        with (run / 'commands.jsonl').open('a') as out:
            out.write(json.dumps([str(w) for w in words]) + '\n')
        result = subprocess.run([str(w) for w in words], cwd=run, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, errors='replace', timeout=90)
        with (run / 'console.log').open('a', encoding='utf-8') as out:
            out.write(result.stdout)
        if result.returncode:
            raise RuntimeError(f'{words[0].name} exit {result.returncode}: {result.stdout[-5000:]}')

    try:
        for lib in ('work', 'ph1'):
            command([ms / 'vlib.exe', lib])
            command([ms / 'vmap.exe', lib, lib])
        command([ms / 'vlog.exe', '-quiet', '-work', 'ph1', '-l', 'models.log'] + models)
        command([ms / 'vlog.exe', '-sv', '-quiet', '+define+PH1', '-work', 'work', '-l', 'compile.log'] + sources)
        command([ms / 'vsim.exe', '-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl', 'work.tb_live_gate',
                 f'-gEXPECT_LEAK={a.expect_leak}', '-l', 'run.log', '-do', 'run -all; quit -f'])
        logs = '\n'.join((run / p).read_text(errors='replace') for p in ('models.log', 'compile.log', 'run.log'))
        if re.search(r'\*\* (Error|Fatal):', logs):
            raise RuntimeError('ModelSim error/fatal; inspect raw logs')
        warning_lines = [line for line in logs.splitlines() if '** Warning:' in line]
        patterns = {
            'official_tone96_ecc_input_width': (r'assets[\\/]tone96_rom[01]_sim\.v.*\(vopt-2241\).*ecc_[sd]biterrinj', 4),
            'official_gamma_unused_ecc_ports': (r'assets[\\/]gamma_rom_8x1024_ip_sim\.v.*\(vopt-2685\)', 1),
            'official_gamma_unused_ecc_output': (r'assets[\\/]gamma_rom_8x1024_ip_sim\.v.*\(vopt-2718\).*ecc_[sd]biterr', 2),
            'td_eram_init_filename_part_select': (r'sim_release[\\/]ph1[\\/]ph1_logic_eram\.v.*\(vopt-2697\).*part-select into .INIT_FILE. is out of bounds', 8),
            'official_tone96_ecc_runtime_width': (r'\(vsim-3015\).*port .ecc_[sd]biterrinj.', 4),
        }
        classified = {name: sum(bool(re.search(pattern, line)) for line in warning_lines)
                      for name, (pattern, _) in patterns.items()}
        if sum(classified.values()) != len(warning_lines) or any(classified[name] != count for name, (_, count) in patterns.items()):
            raise RuntimeError(f'unclassified/count-mismatched ModelSim warnings {classified}; inspect raw logs')
        (run / 'WARNING_CLASSIFICATION.json').write_text(json.dumps(classified, indent=2) + '\n')
        match = re.search(r'RESULT: PASS LIVE_GATE[^\r\n]+', logs)
        if not match:
            raise RuntimeError('missing self-checking PASS marker')
        after = [{'path': p.as_posix(), 'sha256': sha(p)} for p in paths]
        (run / 'SOURCE_END.json').write_text(json.dumps(after, indent=2) + '\n')
        if after != identity:
            q['status'] = 'STALE'
            raise RuntimeError('test input changed during run')
        q.update(status='PASS', simulation='PASS', result=match.group(0), warnings=len(warning_lines),
                 owned_warning_count=0, warning_classification=classified, input_hash_recheck='PASS')
        print(q['result'], flush=True)
    except Exception as error:
        q.update(status=q['status'] if q['status'] == 'STALE' else 'FAIL', simulation='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - started, 3)
        (run / 'RESULTS.json').write_text(json.dumps(q, indent=2) + '\n')
        print(json.dumps({'run': run.as_posix(), 'status': q['status'], 'elapsed_seconds': q['elapsed_seconds']}), flush=True)


if __name__ == '__main__':
    main()
