"""Qualify ordinary CFG activation against the real fixed F21 map and lease."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    ap.add_argument('--td-root', required=True, type=Path)
    a = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('unsafe run name')
    run = PROJECT / 'tmp' / 'autof21_control' / a.name
    run.mkdir(parents=True, exist_ok=False)
    rtl, ip = PROJECT / 'src_fpga/rtl', PROJECT / 'src_fpga/ip'
    includes = [rtl / 'include' / part for part in [
        '00_rtl', '01_include', '03_mono_config_v2_20261015', '04_include']]
    headers = [path for directory in includes for path in directory.glob('*.vh')]
    models = [a.td_root / 'sim_release' / path for path in [
        'common/al_phy_glbl.v', 'ph1/ph1_logic_eram.v', 'ph1/ph1_phy_eram.v',
        'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_fifoctrl.v',
        'ph1/ph1_logic_mult.v', 'ph1/ph1_phy_dspmult.v', 'ph1/ph1_phy_dspmult_v2.v']]
    sources = [a.td_root / 'sim_release/ph1/ph1_phy_gsr.v'] + [ip / path for path in [
        'isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v',
        'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'camera_control_fifo_40x512/camera_control_fifo_40x512.v',
        'dsp_mult_fixed/mult_25u16u_p1/RTL/mult_25u16u_p1_multiplier.v',
        'dsp_mult_fixed/mult_25u16u_p1/RTL/mult_25u16u_p1_multiplier_top.v',
        'dsp_mult_fixed/mult_25u16u_p1/mult_25u16u_p1.v']]
    sources += [rtl / name for name in [
        'td_sdp_ram.v', 'td_sdp_ram40.v', 'td_dsp_mult.v', 'reset_release_sync.v',
        'control_fifo_40x512.v', 'control_message_fifo_ip.v',
        'mono_config_byte_store_v2.v', 'mono_config_legacy_scan_v1.v', 'mono_config_scan_v2.v',
        'mono_config_bar_v2.v', 'mono_config_engine_v2.v', 'mono_config_service_v2.v',
        'frame_config_extension_validate.v', 'pixel_lut_config_lease.v',
        'preprocess_dehaze_map_qualified.v']]
    benches = [HERE / 'tb_autof21_generation.sv', HERE / 'tb_autof21_control.sv']
    identity = [{'path': str(path), 'sha256': sha(path)}
                for path in models + sources + benches + headers + [Path(__file__)]]
    result = {'status': 'IN_PROGRESS', 'inputs': identity,
              'modelsim_bin': str(a.modelsim_bin), 'td_root': str(a.td_root),
              'synthesis': 'NOT_RUN', 'place_route': 'NOT_RUN', 'timing': 'NOT_RUN', 'board': 'NOT_RUN'}

    def command(name, exe, args):
        p = subprocess.run([str(a.modelsim_bin / exe)] + list(map(str, args)), cwd=run,
                           text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors='replace')
        (run / (name + '.console.log')).write_text(p.stdout)
        if p.returncode:
            raise RuntimeError(name + ' failed: ' + p.stdout[-10000:])

    try:
        command('vmap', 'vmap.exe', ['-c'])
        for library in ['ph1', 'work', 'manual']:
            command(library, 'vlib.exe', [library])
        command('models', 'vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log'] + models)
        inc = ['+incdir+' + str(path) for path in includes]
        definitions = ['+define+PH1', '+define+C15_F23_FULLHEIGHT_PROFILE=0']
        command('auto_rtl', 'vlog.exe', ['-quiet', '-sv', '-l', 'auto_rtl.log'] + definitions +
                ['+define+F21_AUTO_FIXED_LUT_PROFILE=1'] + inc + sources + benches)
        command('manual_rtl', 'vlog.exe', ['-quiet', '-sv', '-work', 'manual', '-l', 'manual_rtl.log'] +
                definitions + inc + sources + [benches[0]])
        metrics = []
        for name, top in [('auto_generation', 'work.tb_autof21_generation'),
                          ('manual_generation', 'manual.tb_autof21_generation'),
                          ('ordinary_cfg', 'work.tb_autof21_control')]:
            command(name, 'vsim.exe', ['-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl', top,
                                     '-l', name + '.log', '-do', 'run -all; quit -f'])
            log = (run / (name + '.log')).read_text(errors='replace')
            passed = [line.strip('# ') for line in log.splitlines() if 'RESULT: PASS AUTOF21' in line]
            if len(passed) != 1:
                raise RuntimeError(name + ' missing PASS: ' + log[-10000:])
            metrics += passed
        warnings = []
        for path in run.glob('*.log'):
            if path.name.endswith('.console.log'):
                continue
            lines = path.read_text(errors='replace').splitlines()
            for i, line in enumerate(lines):
                if re.search(r'\*\* (Error|Fatal):', line):
                    raise RuntimeError(path.name + ': ' + line)
                if '** Warning:' not in line:
                    continue
                known = (re.search(r'ram40_sdp_fixed.v\(69\).*ecc_[sd]biterrinj', line) or
                         re.search(r'ph1_logic_eram.v\(1287\).*INIT_FILE.*out of bounds', line) or
                         re.search(r"\(vsim-3015\).*port 'ecc_[sd]biterrinj'.*ph1_logic_eram.v\(52\)", line))
                if not known:
                    raise RuntimeError('unclassified warning ' + path.name + ': ' + line)
                warnings.append({'log': path.name, 'line': i+1, 'message': line})
        for item in identity:
            if sha(Path(item['path'])) != item['sha256']:
                raise RuntimeError('source changed during test: ' + item['path'])
        result.update(status='PASS', metrics=metrics, accepted_vendor_warnings=warnings)
        print('\n'.join(metrics))
    except Exception as e:
        result.update(status='FAIL', error=str(e))
        raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
    print('Results:', run / 'RESULTS.json')


if __name__ == '__main__':
    main()
