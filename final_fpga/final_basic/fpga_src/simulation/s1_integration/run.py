"""Bounded actual S1 service + real F20 + independent full-HD RGB/Y oracle.

No force, simulator substitute, production file mutation, synthesis or board use.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import subprocess
import sys
import time
import numpy as np

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--project-root', type=Path, default=DEFAULT_ROOT)
    ap.add_argument('--name', required=True)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    ap.add_argument('--prepare-only', action='store_true')
    ap.add_argument('--compile-only', action='store_true')
    ap.add_argument('--joint', action='store_true', help='Two full-HD S1/sparse-lane frames plus stereo-history boundary checks')
    ap.add_argument('--timeout-seconds', type=int, default=3600)
    a = ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
    assert 30 <= a.timeout_seconds <= 3600
    root, td, ms = a.project_root.resolve(), a.td_root.resolve(), a.modelsim_bin.resolve()
    run = root/'tmp/s1_integration'/a.name
    run.mkdir(parents=True, exist_ok=False)
    oracle = load('s1_service_oracle', root/'tools/s1_reference.py')
    # Bands have distinct means and dark quantiles; all four lanes vary.
    yy, xx = np.indices((1080, 1920))
    d = (xx*17+yy*3)%96 + (yy//270)*17 + 30
    image = np.stack((d, np.minimum(d+11,255), np.minimum(d+23,255)), axis=2).astype(np.uint8)
    if a.joint:
        # Hazy road with white/yellow lines; four bands exercise row interpolation.
        road = 70+(yy//270)*13
        image = np.stack((road+8,road+5,road),axis=2).astype(np.uint8)
        image[:,694:707]=(164,164,164)
        image[:,1194:1207]=(170,160,91)
    generated = oracle.export_vectors(run/'fixtures', image)
    joint_paths=[]
    if a.joint:
        c1_path=root/'model/c1_reference.py'
        c1=load('s1_sparse_c1_oracle',c1_path)
        stats=oracle.estimate(image)
        restored=oracle.restore(image,stats['band_gains_q8'],stats['band_centres'])
        points_by_frame=[]
        for index,pixels in enumerate((image,restored)):
            q,gx,gy,flags=c1.features(pixels[:,:,::-1].copy())
            packed=(gx.astype(np.int64)&2047)|((gy.astype(np.int64)&2047)<<11)|(q.astype(np.int64)<<22)|(flags.astype(np.int64)<<30)
            oracle.write_hex(run/'fixtures'/f'quarter{index}.hex',packed.ravel(),8)
            points=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags))
            assert points, 'Joint fixture must exercise actual sparse candidates'
            oracle.write_hex(run/'fixtures'/f'points{index}.hex',
                [int.from_bytes(c1.pack_point(p),'little') for p in points]+[0]*(303-len(points)),10)
            points_by_frame.append(points)
        oracle.write_hex(run/'fixtures'/'point_counts.hex',[len(p) for p in points_by_frame],8)
        (run/'fixtures'/'joint_reference.json').write_text(json.dumps(dict(stats=stats,points=points_by_frame),indent=2)+'\n')
        joint_paths=[c1_path]
        generated={p.name:oracle.sha(p) for p in (run/'fixtures').iterdir()}
    fixture_path = root/'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture = json.loads(fixture_path.read_text())
    extras = ['preprocess_light_haze_stats.v','preprocess_light_haze_rgb4.v',
              'preprocess_light_haze_row.v','preprocess_light_haze_restore4.v']
    existing = {r.get('path') for group in fixture['groups'].values() for r in group}
    fixture['groups']['compile.args'] += [dict(path='src_fpga/rtl/'+n) for n in extras
                                         if 'src_fpga/rtl/'+n not in existing]
    helper_path = root/'src_fpga/simulation/autof21/core/run.py'
    helper = load('s1_service_closure', helper_path)
    groups = helper.closure(fixture, ['preprocess_live_f21_service4'])
    parser = load('s1_service_header',root/'src_fpga/simulation/timing/r3_run_zero_latency.py')
    module = 'preprocess_live_f21_service4'
    _, _, ports = parser.header((root/f'src_fpga/rtl/{module}.v').read_text(), module)
    tb = '`timescale 1ns/1ps\nmodule tb_s1_service;\n'
    for direction, width, name in ports:
        tb += ('reg ' if direction=='input' else 'wire ')+width+' '+name
        tb += '=0;\n' if direction=='input' else ';\n'
    tb += 'always #4 clk=~clk;\n'
    tb += module+' #(.HE_FIXED_CONFIG_SESSION_ENABLE(1),.F21_FIXED_CONFIG_SESSION_ENABLE(1),.STEREO_PASSTHROUGH_ENABLE(1),.AUTO_FIXED_LUT_ENABLE(1)) dut('
    tb += ','.join(f'.{n}({n})' for _,_,n in ports)+');\n'
    body_path=HERE/('joint_body.vh' if a.joint else 'body.vh')
    tb += body_path.read_text()+'\nendmodule\n'
    (run/'tb.sv').write_text(tb)
    groups['compile.args'] = [td/'sim_release/ph1/ph1_phy_gsr.v',*groups['compile.args'],run/'tb.sv']
    models = [td/p for p in fixture['models']]
    includes = [root/p for p in fixture['include_dirs']]
    paths = {Path(__file__),body_path,root/'tools/s1_reference.py',fixture_path,helper_path,*joint_paths,
             root/'src_fpga/simulation/timing/r3_run_zero_latency.py',*models}
    for group in groups.values(): paths.update(group)
    paths.update((run/'fixtures').iterdir())
    # Bind only recursively referenced headers. A directory may also contain
    # another concurrently maintained test's monitor, which is not an input.
    queue=[p for group in groups.values() for p in group]
    headers=set()
    while queue:
        source=queue.pop()
        for name in re.findall(r'^\s*`include\s+"([^"]+)"',source.read_text(errors='replace'),re.M):
            header=next((directory/name for directory in [source.parent,*includes]
                         if (directory/name).is_file()),None)
            assert header is not None,f'Unresolved include {source}: {name}'
            header=header.resolve()
            if header not in headers:headers.add(header);queue.append(header)
    paths.update(headers)
    identity = [dict(path=p.resolve().as_posix(),sha256=oracle.sha(p)) for p in sorted(paths)]
    report = dict(status='PREPARED',command=sys.argv,project_root=root.as_posix(),td_root=td.as_posix(),
                  modelsim_bin=ms.as_posix(),inputs=identity,generated=generated,
                  scope=('Actual service/F20/S1/sparse lane: two full-HD frames, per-pixel RGB/Y, quarter p11/Gx/Gy/native-color hints, serialized samples and all candidate words; mode-switch identity/collection checks' if a.joint else 'Actual service/F20: four full-HD frames, first identity, qualified previous history, EOF stall, partial reset recovery, F21 bypass; standalone stats bench covers terminal permutations'),
                  synthesis='NOT_RUN',PNR='NOT_RUN',STA='NOT_RUN',board='NOT_RUN')
    started = time.monotonic()
    def execute(exe, words):
        command = [str(ms/exe),*map(str,words)]
        report.setdefault('commands',[]).append(command)
        with (run/(exe+'.console.log')).open('a') as log:
            proc = subprocess.Popen(command,cwd=run,stdout=log,stderr=subprocess.STDOUT)
            try: code=proc.wait(timeout=a.timeout_seconds)
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                raise RuntimeError(f'{exe} exceeded {a.timeout_seconds}s bounded watchdog')
        if code: raise RuntimeError(f'{exe} failed with {code}; inspect {run}')
    try:
        if a.prepare_only:return
        execute('vmap.exe',['-c'])
        for lib in ('work','ph1'):
            execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        for name,group in groups.items():
            if group:execute('vlog.exe',['-quiet',*(['-sv'] if name=='compile.args' else []),'-work','work','-l',name+'.log',
                '-timescale','1ns/1ps','+define+PH1',*['+incdir+'+p.as_posix() for p in includes],*group])
        execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_s1_service','-l','run.log',
                           '-do','onerror {quit -code 1}; '+('run 0' if a.compile_only else 'run -all')+'; quit -f'])
        logs='\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert not re.search(r'\*\* (?:Error|Fatal):',logs),logs[-12000:]
        if not a.compile_only:assert 'RESULT: PASS S1_SERVICE' in logs,logs[-12000:]
        for row in identity:assert oracle.sha(row['path'])==row['sha256'],row['path']
        report.update(status='PASS_ELABORATION_ONLY' if a.compile_only else 'PASS_S1_SERVICE',
                      results=list(dict.fromkeys(line for line in logs.splitlines() if ' PASS ' in line)),
                      warnings=list(dict.fromkeys(line for line in logs.splitlines() if '** Warning:' in line)))
        owned=[line for line in report['warnings'] if '/src_fpga/rtl/' in line.replace('\\','/')]
        assert not owned,owned
    except Exception as error:
        report.update(status='FAIL',error=str(error));raise
    finally:
        report['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(run=run.as_posix(),status=report['status'],elapsed_seconds=report['elapsed_seconds'])),flush=True)


if __name__=='__main__':main()
