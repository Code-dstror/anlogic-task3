"""Source-bound fixed-F21 history -> interpolated RGB test with official TD models.

The default is a short two-row elaboration/numerical smoke. --full-hd executes
four complete 1920x1080 foreground frames and three full original observations.
"""
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
ROOT = HERE.parents[3]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', required=True, type=Path)
    ap.add_argument('--modelsim-bin', required=True, type=Path)
    ap.add_argument('--full-hd', action='store_true')
    ap.add_argument('--compile-only', action='store_true')
    args = ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}', args.name): ap.error('invalid run name')
    run = ROOT / 'tmp/autof21/history' / args.name
    run.mkdir(parents=True, exist_ok=False)
    reference = load('autof21_history_reference', HERE/'reference.py')
    generated = reference.generate(run/'fixtures', smoke=not args.full_hd)
    fixture_path = ROOT/'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture = json.loads(fixture_path.read_text())
    helper_path = HERE.parent/'core/run.py'
    helper = load('autof21_history_source_closure', helper_path)
    groups = helper.closure(fixture, ['preprocess_dehaze_map_qualified', 'preprocess_dehaze_qualified_rgb4'])
    td, ms = args.td_root.resolve(), args.modelsim_bin.resolve()
    groups['compile.args'].insert(0, td/'sim_release/ph1/ph1_phy_gsr.v')
    groups['compile.args'].append(HERE/'tb_history.sv')
    models = [td/path for path in fixture['models']]
    # The coordinate ROM models consume these run-local images. They come only
    # from the candidate's unchanged MIFs, and both images and MIFs are bound.
    rom_dir = run/'rom_init'
    rom_dir.mkdir()
    paths = {Path(__file__), HERE/'reference.py', helper_path,
             ROOT/'src_fpga/simulation/timing/r3_run_zero_latency.py', fixture_path}
    paths.update(p for p in (HERE/'oracle').iterdir() if p.is_file())
    paths.update(p for p in (run/'fixtures').iterdir() if p.is_file())
    for name in ('x_1920.mif.dath', 'y_1080.mif.dath'):
        source = ROOT/fixture['local_rom_initializers'][name]
        body = source.read_text()
        depth = int(re.search(r'DEPTH\s*=\s*(\d+)', body).group(1))
        width = int(re.search(r'WIDTH\s*=\s*(\d+)', body).group(1))
        entries = {int(a,16):int(b,16) for a,b in re.findall(r'(?m)^\s*([\da-fA-F]+)\s*:\s*([\da-fA-F]+)\s*;', body)}
        assert set(entries)==set(range(depth))
        image = rom_dir/name
        image.write_text(''.join(f'{entries[i]:0{(width+3)//4}x}\n' for i in range(depth)))
        paths.update((source,image))
    paths.update(models)
    for group in groups.values(): paths.update(group)
    includes = [ROOT/path for path in fixture['include_dirs']]
    pending, visited = list(paths), set()
    while pending:
        path = pending.pop()
        if path in visited or path.suffix.lower() not in ('.v','.sv','.vh'): continue
        visited.add(path)
        for name in re.findall(r'(?m)^\s*`include\s+"([^"\r\n]+)"', path.read_text(errors='replace')):
            found = next((p.resolve() for p in [path.parent/name]+[d/name for d in includes] if p.is_file()), None)
            if found is None: raise FileNotFoundError(f'{path}: {name}')
            paths.add(found);pending.append(found)
    identity = [{'path':p.resolve().as_posix(),'sha256':sha(p)} for p in sorted(paths)]
    (run/'source_identity.json').write_text(json.dumps(dict(inputs=identity,td_root=td.as_posix(),
        modelsim_bin=ms.as_posix(),mode='full_hd' if args.full_hd else 'two_row_smoke'),indent=2)+'\n')
    report = dict(status='IN_PROGRESS', command=sys.argv, python=sys.executable,
        full_hd=args.full_hd, compile_only=args.compile_only, oracle=generated,
        source_identity_sha256=sha(run/'source_identity.json'), td_root=td.as_posix(),
        scope='Numerical leaf map owner and interpolated RGB; electrical/complete TOP JPEG covered by complementary MAIN',
        synthesis='NOT_RUN',physical='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    started = time.monotonic()
    def execute(exe, words):
        result = subprocess.run([str(ms/exe),*map(str,words)],cwd=run,capture_output=True,text=True,errors='replace')
        (run/(exe+'.stdout.log')).open('a').write(result.stdout+result.stderr)
        if result.returncode: raise RuntimeError(result.stdout[-10000:]+result.stderr[-1000:])
    try:
        execute('vmap.exe',['-c'])
        for lib in ('work','ph1'):
            execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        for name,group in groups.items():
            if group:
                execute('vlog.exe',['-quiet',*(['-sv'] if name=='compile.args' else []),'-work','work','-l',name+'.log','-timescale','1ns/1ps',
                    '+define+PH1',*['+define+fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ('A','CE','PH1A','RST','Y','Z')],
                    *['+incdir+'+p.as_posix() for p in includes],*group])
        execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_autof21_history',
            '-gROWS='+str(1080 if args.full_hd else 2),'-l','run.log','-do',
            'onerror {quit -code 1}; '+('run 0' if args.compile_only else 'run -all')+'; quit -f'])
        logs='\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert not re.search(r'\*\* (?:Error|Fatal):',logs),logs[-16000:]
        if not args.compile_only: assert 'RESULT: PASS AUTO_F21_HISTORY' in logs,logs[-16000:]
        warnings=[line for line in logs.splitlines() if '** Warning:' in line]
        owned=[line for line in warnings if '/src_fpga/rtl/' in line.replace('\\','/')]
        assert not owned,owned
        known_vendor = (r'INIT_FILE.*out of bounds|ecc_(?:sbit|dbit)errinj|'
            r'fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0\.v\(466\): \(vopt-(?:2685|2718)\).*'
            r"(?:Too few port connections for 'u_siou'|Missing connection for port 'c(?:co|po|yo|xabo|xbo|xao|ci|pi|yi|xabi|xbi|xai)')")
        unknown=[line for line in warnings if not re.search(known_vendor,line)]
        assert not unknown,unknown
        for row in identity: assert sha(Path(row['path']))==row['sha256'],row['path']
        report.update(status='PASS_ELABORATION_ONLY' if args.compile_only else 'PASS_FULL_HD_HISTORY' if args.full_hd else 'PASS_TWO_ROW_HISTORY_SMOKE',
            results=list(dict.fromkeys(line for line in logs.splitlines() if 'PASS' in line)),
            owned_warning_count=0,vendor_warnings=warnings)
        print('\n'.join(report['results']),flush=True)
    except Exception as error:
        report.update(status='FAIL',error=str(error));raise
    finally:
        report['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(run=run.as_posix(),status=report['status'],elapsed_seconds=report['elapsed_seconds'])),flush=True)


if __name__=='__main__':main()
