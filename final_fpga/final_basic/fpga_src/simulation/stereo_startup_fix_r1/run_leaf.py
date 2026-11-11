"""Candidate-bound owner, PHY recovery and official-FIFO SOF phase checks."""
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
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--name', required=True)
    a = ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('name must be a lowercase run identifier')
    td, ms = a.td_root.resolve(), a.modelsim_bin.resolve()
    run = ROOT / 'tmp/stereo_startup_fix_r1' / a.name
    run.mkdir(parents=True, exist_ok=False)
    rtl, ip = ROOT / 'src_fpga/rtl', ROOT / 'src_fpga/ip'
    models = [td / 'sim_release' / p for p in (
        'common/al_phy_glbl.v', 'ph1/ph1_logic_dram.v', 'ph1/ph1_logic_eram.v',
        'ph1/ph1_logic_fifo.v', 'ph1/ph1_logic_ramfifo.v', 'ph1/ph1_phy_eram.v',
        'ph1/ph1_phy_fifoctrl.v')]
    sources = [td / 'sim_release/ph1/ph1_phy_gsr.v']
    sources += [ip / p for p in (
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'camera_control_fifo_40x512/camera_control_fifo_40x512.v')]
    sources += [rtl / p for p in (
        'control_fifo_40x512.v', 'control_message_fifo_ip.v', 'record_format_bar.v',
        'record_format_service.v', 'frame_admission_qualification.v',
        'production_source_identity_guard.v', 'physical_capture_router.v',
        'physical_identity_source_fence.v', 'stereo_capture_source4.v')]
    sources += [HERE / p for p in ('tb_phy_fs_race.sv', 'tb_source_quiet.sv', 'tb_sof_phase.sv')]
    sources += [ROOT / 'src_fpga/simulation/stereo_source/tb_stereo_source.sv']
    inc = [rtl / 'include/04_include', rtl / 'include/00_rtl']
    paths = sources + models + [Path(__file__), inc[0] / 'pcie_protocol_v1.vh']
    inputs = [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in paths]
    q = dict(status='IN_PROGRESS', scope='LEAF_AND_COMPONENT_NOT_COMPLETE_TOP',
             td_root=td.as_posix(), modelsim_bin=ms.as_posix(), inputs=inputs,
             commands=[], metrics=[], synthesis='NOT_RUN', place_route='NOT_RUN',
             timing='NOT_RUN', board='NOT_RUN')
    start = time.monotonic()

    def command(name, exe, args):
        argv = [str(ms / exe)] + list(map(str, args))
        p = subprocess.run(argv, cwd=run, capture_output=True, text=True,
                           errors='replace', timeout=60)
        q['commands'].append(dict(argv=argv, returncode=p.returncode))
        (run / (name + '.console.log')).write_text(p.stdout + p.stderr)
        if p.returncode:
            raise RuntimeError(name + ': ' + (p.stdout + p.stderr)[-5000:])

    try:
        command('map', 'vmap.exe', ['-c'])
        for lib in ('work', 'ph1'):
            command(lib, 'vlib.exe', [lib])
        command('models', 'vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log', *models])
        command('rtl', 'vlog.exe', ['-quiet', '-sv', '+define+PH1',
                                  *['+incdir+' + p.as_posix() for p in inc],
                                  '-l', 'compile.log', *sources])
        for top, extra in [('tb_phy_fs_race', []), ('tb_source_quiet', ['+candidate=1']),
                           ('tb_stereo_source', []), ('tb_sof_phase', ['-gCOMBO=1'])]:
            command(top, 'vsim.exe', ['-c', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                    'work.' + top, *extra, '-l', top + '.log', '-do', 'run -all; quit -f'])
            log = (run / (top + '.log')).read_text()
            if 'RESULT: PASS' not in log or re.search(r'\*\* (Error|Fatal):', log):
                raise RuntimeError(log[-6000:])
            q['metrics'] += [s.strip('# ') for s in log.splitlines() if 'RESULT: PASS' in s]
        for row in inputs:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('Input changed during run: ' + row['path'])
        warnings = [s for p in run.glob('*.log') if not p.name.endswith('.console.log')
                    for s in p.read_text().splitlines() if '** Warning:' in s]
        if warnings:
            raise RuntimeError('Unexpected warnings: ' + '\n'.join(warnings))
        q.update(status='PASS', input_hash_recheck='PASS', warning_count=0)
        print('\n'.join(q['metrics']))
    except Exception as error:
        q.update(status='FAIL', error=str(error))
        raise
    finally:
        q['elapsed_seconds'] = round(time.monotonic() - start, 3)
        (run / 'qualification.json').write_text(json.dumps(q, indent=2) + '\n')
        print(json.dumps(dict(run=run.as_posix(), status=q['status'], elapsed=q['elapsed_seconds'])))


if __name__ == '__main__':
    main()
