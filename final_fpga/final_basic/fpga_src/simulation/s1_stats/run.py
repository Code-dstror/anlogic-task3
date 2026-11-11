"""Bounded full-observation S1 stats self-check using the explicit TD ERAM model."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE))
from reference import generate


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--modelsim-bin', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT/'src_fpga/rtl/preprocess_light_haze_stats.v')
    a = parser.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
    run = ROOT / 'tmp/s1_stats' / a.name
    run.mkdir(parents=True, exist_ok=False)
    generate(run)
    helper_path = ROOT / 'src_fpga/simulation/timing/r3_run_zero_latency.py'
    spec = importlib.util.spec_from_file_location('s1_stats_header', helper_path)
    helper = importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    rtl = ROOT / 'src_fpga/rtl'
    source = a.source.resolve()
    _, _, ports = helper.header(source.read_text(), source.stem)
    tb = '`timescale 1ns/1ps\nmodule tb_s1_stats;\n'
    for d, w, n in ports:
        tb += f'{"reg" if d == "input" else "wire"} {w} {n}' + ('=0;' if d == 'input' else f',t_{n};') + '\n'
    tb += 'always #4 clk=~clk;\n'
    for name, temporal in [('dut', 0), ('temporal', 1)]:
        conns = ','.join(f'.{n}({"t_" if d=="output" and temporal else ""}{n})' for d,w,n in ports)
        tb += f'preprocess_light_haze_stats #(.FIXED_CONFIG_SESSION_ENABLE(1),.AUTO_FIXED_LUT_ENABLE(1),.TEMPORAL_SLEW_ENABLE({temporal})) {name}({conns});\n'
    tb += (HERE / 'body.vh').read_text() + '\nendmodule\n'
    (run / 'tb.sv').write_text(tb)
    td = a.td_root.resolve(); ms = a.modelsim_bin.resolve()
    models = [td / 'sim_release/common/al_phy_glbl.v', td / 'sim_release/ph1/ph1_logic_eram.v',
              td / 'sim_release/ph1/ph1_phy_eram.v']
    sources = [td / 'sim_release/ph1/ph1_phy_gsr.v',
               ROOT / 'src_fpga/ip/isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v',
               rtl / 'td_sdp_ram.v', source, run / 'tb.sv']
    paths = models + sources + [Path(__file__), HERE / 'reference.py', HERE / 'body.vh', helper_path,
                                run / 'samples.hex', run / 'expected.hex', run / 'gains.hex', run / 'histograms.hex']
    identities = [{'path': p.as_posix(), 'sha256': digest(p)} for p in paths]
    report = dict(status='IN_PROGRESS', command=sys.argv, inputs=identities,
                  synthesis='NOT_RUN', physical='NOT_RUN', timing='NOT_RUN', board='NOT_RUN')
    started = time.monotonic()

    def execute(exe, args):
        result = subprocess.run([str(ms / exe), *map(str, args)], cwd=run,
                                capture_output=True, text=True, errors='replace', timeout=180)
        (run / (exe + '.stdout.log')).open('a').write(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(result.stdout[-10000:] + result.stderr[-1000:])
    try:
        execute('vmap.exe', ['-c'])
        for lib in ('work', 'ph1'):
            execute('vlib.exe', [lib]);execute('vmap.exe', [lib, lib])
        execute('vlog.exe', ['-quiet', '-work', 'ph1', '-l', 'models.log', *models])
        execute('vlog.exe', ['-quiet', '-sv', '-work', 'work', '-l', 'compile.log', *sources])
        execute('vsim.exe', ['-c', '-voptargs=+acc', '-L', 'ph1', 'work.PH1_PHY_GSR', 'ph1.glbl',
                             'work.tb_s1_stats', '-l', 'run.log', '-do', 'onerror {quit -code 1}; run -all; quit -f'])
        logs = '\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert 'RESULT: PASS S1_STATS' in logs and not re.search(r'\*\* (?:Error|Fatal):', logs), logs[-12000:]
        warnings = [x for x in logs.splitlines() if '** Warning:' in x]
        assert all('INIT_FILE' in x and 'out of bounds' in x for x in warnings), warnings
        for item in identities:
            assert digest(Path(item['path'])) == item['sha256'], item['path']
        report.update(status='PASS', results=list(dict.fromkeys(x for x in logs.splitlines() if 'RESULT: PASS' in x)), warnings=warnings)
        print('\n'.join(report['results']))
    except Exception as e:
        report.update(status='FAIL', error=str(e))
        raise
    finally:
        report['elapsed_seconds'] = time.monotonic() - started
        (run / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
        print('Evidence:', run)


if __name__ == '__main__':
    main()
