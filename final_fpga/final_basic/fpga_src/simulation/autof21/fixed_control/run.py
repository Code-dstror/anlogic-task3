"""Two-clock fixed-table BAR service, actual map and explicit official TD models."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'src_fpga/simulation/autof21/core'))
from run import closure
sys.path.insert(0, str(ROOT / 'src_fpga/simulation/timing'))
from r3_run_zero_latency import header


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def bench(run):
    module = 'fixed_dehaze_lut_control'
    _, _, ports = header((ROOT / f'src_fpga/rtl/{module}.v').read_text(), module)
    _, _, map_ports = header((ROOT / 'src_fpga/rtl/preprocess_dehaze_map_qualified.v').read_text(),
                            'preprocess_dehaze_map_qualified')
    body = '`include "pcie_protocol_v1.vh"\nmodule tb_fixed_control;\n'
    for d, w, n in ports:
        wire_input = n in ('lut_valid', 'lut_generation')
        body += ('reg ' if d == 'input' and not wire_input else 'wire ') + w + ' ' + n
        body += '=0;\n' if d == 'input' and not wire_input else ';\n'
    for d, w, n in map_ports:
        if n in ('clk', 'rst_n', 'lut_valid', 'lut_generation') or n.startswith('cfg_'):
            continue
        body += ('reg ' if d == 'input' else 'wire ') + w + ' map_' + n
        body += '=0;\n' if d == 'input' else ';\n'
    body += 'always #5 i_user_clk=~i_user_clk;\nalways #3.5 i_pixel_clk=~i_pixel_clk;\n'
    body += module + ' dut(' + ','.join(f'.{n}({n})' for d, w, n in ports) + ');\n'
    conns = []
    for d, w, n in map_ports:
        if n == 'clk':
            signal = 'i_pixel_clk'
        elif n == 'rst_n':
            signal = 'o_core_reset_n'
        elif n in ('lut_valid', 'lut_generation'):
            signal = n
        elif n.startswith('cfg_'):
            # The fixed service must also ignore a deliberately held bogus core status.
            signal = '' if d == 'output' else n
        else:
            signal = 'map_' + n
        conns.append(f'.{n}({signal})')
    body += 'preprocess_dehaze_map_qualified #(.SOURCE_WIDTH(120),.SOURCE_HEIGHT(120),'
    body += '.FIXED_CONFIG_SESSION_ENABLE(1),.AUTO_FIXED_LUT_ENABLE(1)) map_core('
    body += ','.join(conns) + ');\n'
    body += (HERE / 'body.vh').read_text() + '\nendmodule\n'
    target = run / 'tb.sv'
    target.write_text(body)
    return target


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', required=True, type=Path)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    a = ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
    run = ROOT / 'tmp/autof21/fixed_control' / a.name
    run.mkdir(parents=True, exist_ok=False)
    fp = ROOT / 'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture = json.loads(fp.read_text())
    groups = closure(fixture, ['preprocess_dehaze_map_qualified'])
    models = [a.td_root / p for p in fixture['models']]
    groups['compile.args'] = [a.td_root / 'sim_release/ph1/ph1_phy_gsr.v', *groups['compile.args'],
                              ROOT / 'src_fpga/rtl/reset_release_sync.v',
                              ROOT / 'src_fpga/rtl/fixed_dehaze_lut_control.v', bench(run)]
    includes = [ROOT / p for p in fixture['include_dirs']]
    inputs = set(models + [Path(__file__), HERE / 'body.vh', fp,
                          ROOT / 'src_fpga/simulation/autof21/core/run.py',
                          ROOT / 'src_fpga/simulation/timing/r3_run_zero_latency.py',
                          ROOT / 'src_fpga/rtl/include/04_include/pcie_protocol_v1.vh'])
    for group in groups.values():
        inputs.update(group)
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
                                     '-timescale', '1ns/1ps', '+define+PH1',
                                     *['+incdir+' + p.as_posix() for p in includes], *group])
        execute('vsim.exe', ['-c', '-voptargs=+acc', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                             'work.tb_fixed_control', '-l', 'run.log',
                             '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        logs = '\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert 'RESULT: PASS FIXED_DEHAZE_CONTROL' in logs and not re.search(r'\*\* (?:Error|Fatal):', logs), logs[-12000:]
        warnings = [x for x in logs.splitlines() if '** Warning:' in x]
        unknown = [x for x in warnings if not re.search(r'ph1_logic_eram\.v\(1287\).*INIT_FILE.*out of bounds', x)]
        assert not unknown, unknown
        for row in identity:
            assert sha(Path(row['path'])) == row['sha256'], row['path']
        report.update(status='PASS', results=list(dict.fromkeys(x for x in logs.splitlines() if 'RESULT: PASS' in x)),
                      warnings=warnings, owned_warnings=0)
        print('\n'.join(report['results']))
    except Exception as e:
        report.update(status='FAIL', error=str(e))
        raise
    finally:
        (run / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Evidence', run)


if __name__ == '__main__':
    main()
