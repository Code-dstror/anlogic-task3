"""Run source-bound four-band F23 numerical/control checks with explicit ModelSim."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
from core_reference import generate

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    ap.add_argument('--name', required=True)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('name must be a fresh lowercase run identifier')
    out = ROOT/'tmp/lane4_core'/a.name
    out.mkdir(parents=True, exist_ok=False)
    paths = [ROOT/'src_fpga/rtl/stage3_lane_candidates_terminal4.v',
             HERE/'core_tb.sv', HERE/'core_reference.py', Path(__file__)]
    report = dict(status='IN_PROGRESS', inputs=[{'path':p.as_posix(),'sha256':sha(p)} for p in paths],
                  scope='scalar all1356 bits: existing generic and narrowed MONO fourband; no production RTL rewrite',
                  synthesis='NOT_RUN', physical_timing='NOT_RUN', board='NOT_RUN')
    def execute(exe, args):
        argv = [str(a.modelsim_bin/exe), *map(str,args)]
        report.setdefault('commands', []).append(argv)
        r = subprocess.run(argv, cwd=out, capture_output=True, text=True, errors='replace', timeout=120)
        if r.returncode:
            raise RuntimeError(r.stdout[-12000:]+r.stderr[-2000:])
    try:
        cases = generate(out)
        report['case_count'] = len(cases)
        execute('vmap.exe',['-c'])
        execute('vlib.exe',['work'])
        execute('vlog.exe',['-sv','-work','work','-l','compile.log',*paths[:2]])
        execute('vsim.exe',['-c','work.core_tb','-l','run.log','-do',
                            'onerror {quit -code 1}; run -all; quit -f'])
        for log in ['compile.log', 'run.log']:
            body = (out/log).read_text(errors='replace')
            if re.search(r'\*\* (?:Error|Fatal|Warning):', body):
                raise RuntimeError(body[-14000:])
        body = (out/'run.log').read_text(errors='replace')
        assert 'RESULT: PASS LANE4_CORE' in body, body[-14000:]
        report['metrics'] = [s for s in body.splitlines() if 'PASS' in s or 'LIMITATION' in s]
        for row in report['inputs']:
            assert sha(Path(row['path'])) == row['sha256'], row['path']
        report['fixtures'] = [{'path':p.name,'sha256':sha(p)} for p in sorted(out.glob('*.hex'))]
        report['status'] = 'PASS'
        print('\n'.join(report['metrics']))
    except Exception as e:
        report.update(status='FAIL',error=str(e))
        raise
    finally:
        (out/'qualification.json').write_text(json.dumps(report, indent=2)+'\n')
        print('Evidence', out)


if __name__ == '__main__':
    main()
