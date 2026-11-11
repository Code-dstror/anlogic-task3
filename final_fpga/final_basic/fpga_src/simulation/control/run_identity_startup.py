"""Focused startup trust/failure-closed checks, using production guard/parser/fence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
p = argparse.ArgumentParser()
p.add_argument('--name', required=True)
p.add_argument('--modelsim-bin', type=Path, required=True)
p.add_argument('--before', action='store_true', help='Confirm each original-source startup failure')
a = p.parse_args()
assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
run = ROOT / 'tmp/identity_startup' / a.name
run.mkdir(parents=True, exist_ok=False)
baseline_file = ROOT / 'BASELINE_INPUTS.json'
baseline = json.loads(baseline_file.read_text())
baseline_commit = baseline['baseline_commit']
assert re.fullmatch('[0-9a-f]{40}', baseline_commit)
names = [
    'production_source_identity_guard.v', 'physical_csi_word_core.v', 'physical_identity_source_fence.v'
]
source_root = run / 'baseline' if a.before else ROOT / 'src_fpga/rtl'
sources = [source_root / n for n in names] + [HERE / 'identity_startup_tb.sv']
result = dict(status='IN_PROGRESS', phase='before' if a.before else 'after',
              baseline_commit=baseline_commit, baseline_directory=baseline['baseline_directory'], inputs=[],
              synthesis='NOT_RUN', physical='NOT_RUN', timing='NOT_RUN', board='NOT_RUN', commands=[])

def call(exe, args):
    command = [str(a.modelsim_bin / exe)] + list(map(str, args))
    result['commands'].append(command)
    r = subprocess.run(command, cwd=run, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stdout[-12000:] + r.stderr[-2000:])

try:
    if a.before:
        source_root.mkdir()
        for name in names:
            relative = 'src_fpga/rtl/' + name
            row = next(x for x in baseline['files'] if x['path'] == relative)
            assert row['source_commit'] == baseline_commit
            command = ['git', 'show', baseline_commit + ':' + row['source_path']]
            result['commands'].append(command)
            original = subprocess.run(command, cwd=ROOT, capture_output=True, check=True).stdout
            assert hashlib.sha256(original).hexdigest() == row['source_sha256']
            (source_root / name).write_bytes(original)
    identity = [dict(path=str(x), sha256=hashlib.sha256(x.read_bytes()).hexdigest())
                for x in sources + [Path(__file__), baseline_file]]
    result['inputs'] = identity
    call('vmap.exe', ['-c'])
    call('vlib.exe', ['work'])
    call('vmap.exe', ['work', 'work'])
    call('vlog.exe', ['-quiet', '-sv', '-l', 'compile.log'] + sources)
    result['checks'] = {}
    for top, original_failure in [
        ('identity_guard_startup_tb', 'pre-FS PHY/receive transient poisoned startup'),
        ('identity_parser_startup_tb', 'pre-FS bad header permanently destroyed unestablished identity'),
    ]:
        call('vsim.exe', ['-c', 'work.' + top, '-l', top + '.log', '-do',
                         'onerror {quit -code 1}; run -all; quit -f'])
        body = (run / (top + '.log')).read_text()
        if a.before:
            assert original_failure in body and 'RESULT: PASS' not in body, body[-8000:]
            result['checks'][top] = 'EXPECTED_ORIGINAL_FAILURE_REPRODUCED'
        else:
            assert 'RESULT: PASS' in body and not re.search(r'\*\*\s+(Error|Fatal):', body), body[-8000:]
            result['checks'][top] = 'PASS'
    for row in identity:
        assert hashlib.sha256(Path(row['path']).read_bytes()).hexdigest() == row['sha256']
    result['status'] = 'PASS'
except Exception as e:
    result.update(status='FAIL', error=str(e))
    raise
finally:
    (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(run=str(run), status=result['status'], error=result.get('error'))))
