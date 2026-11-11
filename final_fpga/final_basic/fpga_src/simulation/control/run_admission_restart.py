"""Check the actual top restart latch against the frozen owned-payload contract."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('Use an independent lowercase run name')
    run = ROOT / 'tmp' / 'admission' / args.name
    run.mkdir(parents=True, exist_ok=False)
    top = ROOT / 'src_fpga/rtl/anlogic2026.v'
    admission = ROOT / 'src_fpga/rtl/jpeg_frame_admission.v'
    bench = HERE / 'tb_admission_restart.sv'
    body = top.read_text()
    match = re.search(r'always\s*@\(posedge pixel_clk\)\s*begin\s*'
                      r'if\(admission_state_idle\)\s*admitted_restart\s*<=\s*job_restart;\s*end', body)
    if match is None:
        raise RuntimeError('Actual top restart owner block changed; re-evaluate this focused test')
    block = run / 'actual_restart_latch.vh'
    block.write_text(match.group()+'\n')
    paths = [Path(__file__), top, admission, bench, block]
    identity = [{'path': p.resolve().as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                for p in paths]
    (run / 'source_identity.json').write_text(json.dumps(identity, indent=2)+'\n')
    tool = args.modelsim_bin.resolve()
    result = {'status': 'RUNNING', 'scope': 'Actual admission FSM plus extracted actual top restart block; old admission-take latch reference',
              'inputs': identity, 'synthesis': 'NOT_RUN', 'physical': 'NOT_RUN', 'board': 'NOT_RUN'}
    try:
        for command in ([tool/'vlib.exe', 'work'],
                        [tool/'vlog.exe', '-sv', '-work', 'work', '-l', 'compile.log',
                         '+incdir+'+run.as_posix(), admission, bench],
                        [tool/'vsim.exe', '-c', 'work.tb_admission_restart', '-l', 'run.log',
                         '-do', 'run -all; quit -f']):
            completed = subprocess.run([str(x) for x in command], cwd=run,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, errors='replace')
            if completed.returncode:
                raise RuntimeError(completed.stdout[-8000:])
        log = (run/'run.log').read_text(errors='replace')
        if re.search(r'\*\* (?:Warning|Error|Fatal):', log) or 'RESULT: PASS ADMISSION_RESTART' not in log:
            raise RuntimeError(log[-8000:])
        for row in identity:
            if hashlib.sha256(Path(row['path']).read_bytes()).hexdigest() != row['sha256']:
                raise RuntimeError('Focused input changed during run: '+row['path'])
        result['status'] = 'PASS'
        result['metrics'] = [line for line in log.splitlines() if 'RESULT:' in line]
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL', error=str(error))
        raise
    finally:
        (run/'qualification.json').write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
    main()
