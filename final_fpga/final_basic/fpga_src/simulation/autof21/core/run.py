"""Short fixed-LUT reset/control/history miter against a manual G1 load."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT / 'src_fpga/simulation/timing'))
from r3_run_zero_latency import header, clean


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def closure(fixture, targets):
    paths = list(dict.fromkeys(ROOT / r['path'] for g in fixture['groups'].values() for r in g if 'path' in r))
    mapping, bodies = {}, {}
    for p in paths:
        if p.suffix not in ('.v', '.sv') or '.enc.' in p.name:
            continue
        body = p.read_text(errors='replace')
        if '`pragma protect begin_protected' in body:
            mapping[p.stem] = p
            bodies[p] = ''
            continue
        bodies[p] = clean(body)
        for module in re.findall(r'\bmodule\s+(\w+)', bodies[p]):
            mapping[module] = p
    selected, queue = set(), list(targets)
    while queue:
        p = mapping[queue.pop()]
        if p in selected:
            continue
        selected.add(p)
        words = set(re.findall(r'\b\w+\b', bodies[p]))
        queue += [n for n in mapping if n in words and mapping[n] not in selected]
    return {n: [ROOT / r['path'] for r in g if 'path' in r and ROOT / r['path'] in selected]
            for n, g in fixture['groups'].items()}


def bench(run):
    source = ROOT / 'src_fpga/rtl/preprocess_dehaze_map_qualified.v'
    _, _, ports = header(source.read_text(), source.stem)
    text = 'module tb_autof21_core;\n'
    for d, w, n in ports:
        if d == 'input' and n.startswith('cfg_'):
            text += f'reg {w} a_{n}=0,m_{n}=0;\n'
        elif d == 'input':
            text += f'reg {w} {n}=0;\n'
        else:
            text += f'wire {w} {n},m_{n};\n'
    text += 'always #4 clk=~clk;\nreg compare=0; integer comparisons=0;\n'
    for auto, name in [(1, 'auto_core'), (0, 'manual_core')]:
        conns = []
        for d, w, n in ports:
            signal = ('a_' if auto else 'm_') + n if n.startswith('cfg_') and d == 'input' else n
            if d == 'output' and not auto:
                signal = 'm_' + n
            conns.append(f'.{n}({signal})')
        # Deliberately omit AUTO parameter on manual instance to test default0.
        parameters = '.SOURCE_WIDTH(120),.SOURCE_HEIGHT(120),.FIXED_CONFIG_SESSION_ENABLE(1)'
        if auto:
            parameters += ',.AUTO_FIXED_LUT_ENABLE(1)'
        text += f'preprocess_dehaze_map_qualified #({parameters}) {name}('+','.join(conns)+');\n'
    checked = [n for d, w, n in ports if d == 'output' and not n.startswith('cfg_') and n != 'control_rejects']
    text += 'always @(posedge clk)if(compare)begin #1; comparisons=comparisons+1;\n'
    for n in checked:
        text += f'if({n}!==m_{n})$fatal(1,"AUTO/manual mismatch {n} a=%h m=%h",{n},m_{n});\n'
    text += 'end\n' + (HERE / 'body.vh').read_text() + '\nendmodule\n'
    out = run / 'tb.sv'
    out.write_text(text)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', required=True, type=Path)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    a = ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
    run = ROOT / 'tmp/autof21/core' / a.name
    run.mkdir(parents=True, exist_ok=False)
    fixture_path = ROOT / 'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture = json.loads(fixture_path.read_text())
    groups = closure(fixture, ['preprocess_dehaze_map_qualified'])
    models = [a.td_root / p for p in fixture['models']]
    groups['compile.args'].insert(0, a.td_root / 'sim_release/ph1/ph1_phy_gsr.v')
    groups['compile.args'].append(bench(run))
    inputs = set(models + [Path(__file__), HERE / 'body.vh', fixture_path])
    for g in groups.values():
        inputs.update(g)
    identity = [{'path': p.resolve().as_posix(), 'sha256': sha(p)} for p in sorted(inputs)]
    report = dict(status='IN_PROGRESS', inputs=identity, td_root=str(a.td_root),
                  synthesis='NOT_RUN', physical='NOT_RUN', board='NOT_RUN')
    def execute(exe, args):
        result = subprocess.run([str(a.modelsim_bin / exe), *map(str, args)], cwd=run,
                                capture_output=True, text=True, errors='replace')
        (run / (exe + '.stdout.log')).open('a').write(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(result.stdout[-12000:] + result.stderr[-1000:])
    try:
        execute('vmap.exe', ['-c'])
        for lib in ['work', 'ph1']:
            execute('vlib.exe', [lib])
            execute('vmap.exe', [lib, lib])
        execute('vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log', *models])
        for name, group in groups.items():
            if group:
                execute('vlog.exe', ['-quiet', '-sv', '-work', 'work', '-l', name + '.log',
                                     '-timescale', '1ns/1ps', '+define+PH1', *group])
        execute('vsim.exe', ['-c', '-voptargs=+acc', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                             'work.tb_autof21_core', '-l', 'run.log',
                             '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        logs = '\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert 'RESULT: PASS AUTO_F21_CORE' in logs and not re.search(r'\*\* (?:Error|Fatal):', logs), logs[-12000:]
        warnings = [x for x in logs.splitlines() if '** Warning:' in x]
        unknown = [x for x in warnings if not re.search(r'ph1_logic_eram\.v\(1287\).*INIT_FILE.*out of bounds', x)]
        assert not unknown, unknown
        for row in identity:
            assert sha(Path(row['path'])) == row['sha256'], row['path']
        report.update(status='PASS', results=[x for x in logs.splitlines() if 'RESULT: PASS' in x],
                      warnings=warnings, owned_warnings=0)
        print('\n'.join(dict.fromkeys(report['results'])))
    except Exception as e:
        report.update(status='FAIL', error=str(e))
        raise
    finally:
        (run / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Evidence', run)


if __name__ == '__main__':
    main()
