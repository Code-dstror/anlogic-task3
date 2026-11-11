"""Check real restored RGB/Y entering one shared HE and the resulting pixels under stall."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
SIM=HERE.parent


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--td-root',type=Path,required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    a=parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name):parser.error('invalid run name')
    run=ROOT/'tmp/dehaze_joint'/a.name;run.mkdir(parents=True,exist_ok=False)
    helper_file=SIM/'autof21/core/run.py'
    spec=importlib.util.spec_from_file_location('closure_for_joint',helper_file)
    helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
    fixture_file=SIM/'MAIN_FIXTURE.json';fixture=json.loads(fixture_file.read_bytes())
    groups=helper.closure(fixture,['preprocess_live_f21_pipeline4'])
    core=ROOT/'src_fpga/rtl/dehaze_dcp_restore4.v'
    if not any(core in g for g in groups.values()):raise RuntimeError('DCP missing from MAIN fixture source closure')
    models=[a.td_root / p for p in fixture['models']]
    includes=[ROOT/d for d in fixture['include_dirs']]
    pipeline=ROOT/'src_fpga/rtl/preprocess_live_f21_pipeline4.v'
    _,_,ports=helper.header(pipeline.read_text(),pipeline.stem)
    tb=['`timescale 1ns/1ps','module tb_dcp_joint;']
    for direction,width,name in ports:
        tb.append(f'    reg {width} {name}=0;' if direction=='input' else f'    wire {width} {name};')
    tb+=['always #4 clk=~clk;', 'preprocess_live_f21_pipeline4 #(.MAX_WIDTH(256),.MAX_HEIGHT(128),',
         '.HE_SOURCE_QUALIFY_ENABLE(1),.HE_FIXED_CONFIG_SESSION_ENABLE(1),.SHARED_Y_PROFILE(1),',
         '.NEUTRAL_TAP_ENABLE(1),.DCP_ENABLE(1),.STEREO_HE_ENABLE(1),.HE_COLOR_PRESERVE(1)) dut(.*);',
         (HERE/'joint.vh').read_text(encoding='utf-8-sig'),'endmodule']
    rendered=run/'tb_joint.sv';rendered.write_text('\n'.join(tb)+'\n',encoding='utf-8')
    groups['compile.args'].insert(0,a.td_root/'sim_release/ph1/ph1_phy_gsr.v')
    source_files={p for g in groups.values() for p in g}
    queue=list(source_files)
    while queue:
        src=queue.pop()
        for name in re.findall(r'(?m)^\s*`include\s+"([^"]+)"',src.read_text(errors='replace')):
            path=next((d/name for d in [src.parent,*includes] if (d/name).is_file()),None)
            if path is None:raise FileNotFoundError(name)
            if path not in source_files:source_files.add(path);queue.append(path)
    inputs=source_files|set(models)|{helper_file,fixture_file,HERE/'joint.vh',Path(__file__),rendered,SIM/'timing/r3_run_zero_latency.py'}
    before={str(p):sha(p) for p in inputs};ms=a.modelsim_bin.resolve()
    result=dict(simulation='FAIL',inputs=before,synthesis='NOT_RUN',place_route='NOT_RUN',board='NOT_RUN')
    def call(exe,args,label):
        log=run/(label+'.log')
        with log.open('w') as f:
            r=subprocess.run([ms/(exe+'.exe'),*map(str,args)],cwd=run,stdout=f,stderr=subprocess.STDOUT,timeout=180)
        body=log.read_text(errors='replace')
        if r.returncode or re.search(r'\*\* (?:Error|Fatal):',body):raise RuntimeError(body[-2300:])
        return body
    try:
        call('vmap',['-c'],'map')
        for lib in ('work','ph1'):call('vlib',[lib],'lib_'+lib)
        call('vlog',['-quiet','-work','ph1',*models],'models')
        flags=['+define+PH1']+['+incdir+'+str(d) for d in includes]
        for name,files in groups.items():
            if files:
                call('vlog',['-quiet','-work','work','-timescale','1ns/1ps',*(['-sv'] if name=='compile.args' else []),*flags,*files],name)
        call('vlog',['-quiet','-sv',rendered],'bench')
        body=call('vsim',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_dcp_joint','-do','run -all; quit -f'],'simulation')
        if 'RESULT: PASS JOINT_DCP_HE frame_count=5 checked_pixels=163840' not in body:
            raise RuntimeError('incomplete numerical run')
        if before!={str(p):sha(p) for p in inputs}: raise RuntimeError('source drift')
        result['simulation']='PASS'
        result['metrics']=[s.strip('# ') for s in body.splitlines() if 'DCP_HE_FRAME' in s or 'RESULT: PASS' in s]
        print('\n'.join(result['metrics']))
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__': main()
