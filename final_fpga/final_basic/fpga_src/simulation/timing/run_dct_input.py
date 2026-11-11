"""Check the elastic DCT input against fixed Q14 numbers and the routed baseline."""
from pathlib import Path
import argparse
import hashlib
import json
import random
import re
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REPO = ROOT.parents[1]
BASE = 'f3fc9adb5462ea91b50886be6dfa23449eec4d74'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', required=True, type=Path)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    a = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name):
        ap.error('invalid run name')
    run = ROOT / 'tmp' / 'dct' / a.name
    run.mkdir(parents=True, exist_ok=False)
    table = ROOT / 'verification_reference/tools/jpeg_ref/table_data.json'
    matrix = json.loads(table.read_text())['dct']
    def rounded(x):
        return (x + (8191 if x < 0 else 8192)) // 16384
    def transform(block):
        rows = [[rounded(sum((block[r*8+x]-128)*matrix[u][x] for x in range(8)))
                 for u in range(8)] for r in range(8)]
        return [rounded(sum(rows[r][u]*matrix[v][r] for r in range(8)))
                for v in range(8) for u in range(8)]
    rng = random.Random(20261023)
    blocks = [[0]*64, [128]*64, [255]*64, [255]+[128]*63,
              [255 if (r+c)%2 else 0 for r in range(8) for c in range(8)]]
    blocks += [[rng.randrange(256) for _ in range(64)] for _ in range(32-len(blocks))]
    (run / 'samples.hex').write_text(''.join(f'{int.from_bytes(bytes(b),"little"):0128x}\n' for b in blocks))
    (run / 'coeffs.hex').write_text(''.join(f'{sum((v&65535)<<(16*i) for i,v in enumerate(transform(b))):0256x}\n' for b in blocks))
    baseline_path = 'refactor/hdr_jpeg/src_fpga/rtl/jpeg_dct8x8_pipeline.v'
    baseline = subprocess.check_output(['git','show',f'{BASE}:{baseline_path}'],cwd=REPO)
    (run / 'dct_baseline.v').write_text(baseline.decode().replace('module jpeg_dct8x8_pipeline','module dct_baseline'))
    fixture = json.loads((ROOT / 'src_fpga/simulation/MAIN_FIXTURE.json').read_text())
    models = [a.td_root / p for p in fixture['models']]
    macros = [ROOT / r['path'] for r in fixture['groups']['mac_compile.args']]
    multiply = [ROOT / r['path'] for r in fixture['groups']['compile.args']
                if 'dsp_mult_fixed/mult_19s14s_p1/' in r.get('path','')]
    sources = [a.td_root / 'sim_release/ph1/ph1_phy_gsr.v'] + multiply + [
        ROOT / 'src_fpga/ip/isp_line_ram_20x1024_ip/isp_line_ram_20x1024_ip.v']
    sources += [ROOT / 'src_fpga/rtl' / n for n in ['td_sdp_ram.v','td_dsp_mult.v','jpeg_fdct1d.v','jpeg_dct8x8_pipeline.v']]
    sources += [run / 'dct_baseline.v', HERE / 'tb_dct_input.sv']
    inputs = models + macros + sources + [Path(__file__),table]
    identity = [{'path':p.resolve().as_posix(),'sha256':sha(p)} for p in inputs]
    report = {'status':'IN_PROGRESS','baseline_commit':BASE,'baseline_path':baseline_path,
              'baseline_sha256':hashlib.sha256(baseline).hexdigest(),'inputs':identity,
              'td_root':str(a.td_root),'physical':'NOT_RUN','board':'NOT_RUN'}
    def execute(exe, args):
        done = subprocess.run([str(a.modelsim_bin / exe)] + [str(x) for x in args],cwd=run,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
        if done.returncode:
            raise RuntimeError(done.stdout[-12000:])
    try:
        execute('vmap.exe',['-c'])
        for lib in ['work','ph1']:
            execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        defs = ['+define+PH1'] + ['+define+fdct_mac19s14s_z33s_p34_m1p1_USE_'+x+'=1' for x in ['A','CE','PH1A','RST','Y','Z']]
        execute('vlog.exe',['-quiet','-l','mac.log']+defs+macros)
        execute('vlog.exe',['-quiet','-sv','-timescale','1ns/1ps','-l','compile.log']+defs+sources)
        report['metrics'] = []
        for reference in [1,0]:
            log = f'reference{reference}.log'
            execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_dct_input',
                               f'-gREFERENCE={reference}','-l',log,'-do','onerror {quit -code 1}; run -all; quit -f'])
            body=(run / log).read_text(errors='replace')
            if 'RESULT: PASS dct_input' not in body or re.search(r'\*\* (Error|Fatal):',body):
                raise RuntimeError(body[-12000:])
            warnings=[line for line in body.splitlines() if '** Warning:' in line]
            for line in warnings:
                allowed = ('fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.v(466)' in line and
                           re.search(r'\((vopt-2685|vopt-2718)\)',line))
                allowed = allowed or ('ph1_logic_dram.v(221)' in line and
                                      '(vopt-2697)' in line and "into 'INIT_FILE' is out of bounds" in line)
                if not allowed:
                    raise RuntimeError('Unclassified warning: '+line)
            report['metrics'] += [line for line in body.splitlines() if 'DCT_METRIC' in line or 'RESULT: PASS' in line]
        for log in ['mac.log','compile.log']:
            if re.search(r'\*\* (Warning|Error|Fatal):',(run/log).read_text(errors='replace')):
                raise RuntimeError(log+' contains diagnostics')
        for row in identity:
            if sha(Path(row['path'])) != row['sha256']:
                raise RuntimeError('Input changed: '+row['path'])
        report['status']='PASS'
        print('\n'.join(report['metrics']))
    except Exception as error:
        report.update(status='FAIL',error=str(error))
        raise
    finally:
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
        print('Logs:',run)


if __name__ == '__main__':
    main()
