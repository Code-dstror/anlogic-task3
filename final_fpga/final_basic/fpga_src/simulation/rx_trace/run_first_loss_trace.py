"""Focused RAM chronology, cohort reset and WORD/SYS mailbox verification."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}', args.name):
        parser.error('unsafe run name')
    run = PROJECT / 'tmp/rx_first_loss_trace' / args.name
    run.mkdir(parents=True, exist_ok=False)
    sources = [PROJECT / 'src_fpga/rtl/rx_first_loss_trace.v', HERE / 'tb_rx_first_loss_trace.sv']
    bound = sources + [Path(__file__), HERE / 'rx_first_loss_trace_contract.md']
    result = dict(status='IN_PROGRESS', simulation='NOT_RUN', synthesis='NOT_RUN',
                  place_route='NOT_RUN', timing='NOT_RUN', board='NOT_RUN',
                  inputs=[dict(path=str(p), sha256=sha(p)) for p in bound],
                  command=[sys.executable]+sys.argv, commands=[],
                  td_models='NOT_USED; self-authored RAM/mailbox leaf only')
    def call(name, params):
        cmd = [str(args.modelsim_bin / name)] + [str(p) for p in params]
        row = dict(command=cmd, cwd=str(run), timeout_seconds=60)
        result['commands'].append(row)
        completed = subprocess.run(cmd, cwd=run, capture_output=True, text=True,
                                   errors='replace', timeout=60)
        row['returncode'] = completed.returncode
        (run / ('command-%02d.log' % len(result['commands']))).write_text(
            completed.stdout + completed.stderr, encoding='utf-8')
        if completed.returncode:
            raise RuntimeError((completed.stdout+completed.stderr)[-8000:])
        return completed.stdout+completed.stderr
    try:
        result['tool_version'] = call('vsim.exe', ['-version']).strip()
        call('vmap.exe', ['-c'])
        call('vlib.exe', ['work'])
        call('vmap.exe', ['work', 'work'])
        call('vlog.exe', ['-quiet', '-sv', '-l', 'compile.log']+sources)
        (run / 'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n')
        call('vsim.exe', ['-c', 'work.tb_rx_first_loss_trace', '-l', 'run.log', '-do', 'run.do'])
        log = (run / 'run.log').read_text(errors='replace')
        if re.search(r'\*\*\s+(Error|Fatal):', log) or 'RESULT: PASS' not in log:
            raise RuntimeError(log[-10000:])
        for item in result['inputs']:
            if sha(Path(item['path'])) != item['sha256']:
                raise RuntimeError('input changed: '+item['path'])
        result.update(status='PASS', simulation='PASS',
                      observations=[s for s in log.splitlines() if 'CASE ' in s or 'RESULT: PASS' in s])
    except Exception as exc:
        result.update(status='FAIL', simulation='FAIL', error=str(exc))
        raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(dict(run=str(run), status=result['status'], error=result.get('error'))))

if __name__ == '__main__':
    main()
