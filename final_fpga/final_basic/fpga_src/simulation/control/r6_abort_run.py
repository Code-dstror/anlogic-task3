"""Source-bound R6 F22/F23 abort retirement self-check with official TD models."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='a650568da1b54532548469be304d9cd644857bd6'


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def clean(text):return re.sub(r'/\*.*?\*/|//[^\n]*','',text,flags=re.S)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True,type=Path)
    ap.add_argument('--modelsim-bin',required=True,type=Path)
    a=ap.parse_args();assert re.fullmatch(r'[a-z][a-z0-9_]+',a.name)
    run=ROOT/'tmp/r6_abort'/a.name;run.mkdir(parents=True,exist_ok=False)
    fixture_path=ROOT/'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture=json.loads(fixture_path.read_text())
    paths=list(dict.fromkeys(ROOT/row['path'] for group in fixture['groups'].values() for row in group if 'path' in row))
    mapping={};texts={}
    for p in paths:
        if p.suffix not in ['.v','.sv']:continue
        text=clean(p.read_text(errors='replace'));texts[p]=text
        mapping[p.stem]=p
        for module in re.findall(r'\bmodule\s+(\w+)',text):mapping[module]=p
    selected=set();queue=['stage3_filter_color_analysis4','preprocess_live_lane_owner',
                         'frame_record_v3_join','ordered_frame_ingress','production_soft_reset_fence']
    while queue:
        module=queue.pop();p=mapping[module]
        if p in selected:continue
        selected.add(p);words=set(re.findall(r'\b\w+\b',texts[p]))
        queue += [name for name in mapping if name in words and mapping[name] not in selected]
    groups={name:[ROOT/row['path'] for row in group if 'path' in row and ROOT/row['path'] in selected]
            for name,group in fixture['groups'].items()}
    models=[a.td_root/p for p in fixture['models']]+[a.td_root/'sim_release/ph1/ph1_phy_gsr.v']
    includes=[ROOT/p for p in fixture['include_dirs']]
    inputs=set(selected)|set(models)|{fixture_path,HERE/'r6_abort_tb.sv',Path(__file__)}
    work=list(selected);visited=set()
    while work:
        p=work.pop()
        if p in visited:continue
        visited.add(p)
        for name in re.findall(r'`include\s+"([^"]+)"',p.read_text(errors='replace')):
            found=next((q for q in [p.parent/name,*[d/name for d in includes]] if q.is_file()),None)
            if found and found not in inputs:inputs.add(found);work.append(found)
    origins=[]
    for p in sorted(inputs):
        if p.is_relative_to(ROOT) and p not in [HERE/'r6_abort_tb.sv',Path(__file__)]:
            relative=p.relative_to(REPO).as_posix()
            raw=subprocess.check_output(['git','show',BASE+':'+relative],cwd=REPO)
            if p.name!='stage3_filter_color_analysis4.v':
                assert p.read_bytes().replace(b'\r\n',b'\n')==raw.replace(b'\r\n',b'\n'),relative+' unexpectedly differs from fixed a650'
            origins.append({'path':relative,'git_blob_sha256':hashlib.sha256(raw).hexdigest()})
    identity=[{'path':str(p.resolve()),'sha256':sha(p)} for p in sorted(inputs)]
    result={'status':'RUNNING','parent_commit':BASE,'fixed_source_comparisons':origins,'inputs':identity,
            'scope':'32x32 masks16/48/61 plus production 1920x1080/fullheight F22/F23, actual lane owner/JOIN/ordered ingress/soft-reset fence; controlled byte+RESULT protocol driver, not full JPEG/CSI/RK or numerical qualification.',
            'tests':[],'synthesis':'NOT_RUN','physical':'NOT_RUN','board':'NOT_RUN'}
    def execute(label,exe,args):
        done=subprocess.run([str(a.modelsim_bin/exe),*[str(x) for x in args]],cwd=run,
                            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
        (run/(label+'.console.log')).write_text(done.stdout)
        if done.returncode:raise RuntimeError(label+': '+done.stdout[-9000:])
    try:
        execute('map','vmap.exe',['-c'])
        for lib in ['work','ph1']:
            execute('lib_'+lib,'vlib.exe',[lib]);execute('map_'+lib,'vmap.exe',[lib,lib])
        execute('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        defs=['PH1','C15_F23_FULLHEIGHT_PROFILE=1']+['fdct_mac19s14s_z33s_p34_m1p1_USE_'+x+'=1' for x in ['A','CE','PH1A','RST','Y','Z']]
        for group,source in groups.items():
            if not source:continue
            args=['-quiet','-l',group+'.log',*['+define+'+d for d in defs],*['+incdir+'+str(d) for d in includes]]
            execute(group,'vlog.exe',[*args,*source])
        execute('bench','vlog.exe',['-quiet','-sv','-l','bench.log',*['+define+'+d for d in defs],
            *['+incdir+'+str(d) for d in includes],HERE/'r6_abort_tb.sv'])
        for mode,label in [(0,'generic'),(1,'production')]:
            execute(label,'vsim.exe',['-c','-L','ph1','ph1.PH1_PHY_GSR','ph1.glbl','work.r6_abort_tb',
                '-gPRODUCTION='+str(mode),'-l',label+'.log','-do','run -all;quit -f'])
            log=(run/(label+'.log')).read_text()
            assert 'RESULT: PASS R6_ABORT_ALL' in log and not re.search(r'\*\* (?:Error|Fatal):',log),log[-9000:]
            warnings=[line for line in log.splitlines() if '** Warning:' in line]
            expected=[r'ram40_sdp_fixed.*\(vopt-2241\).*ecc_[sd]biterrinj',
                      r'ph1_logic_eram.*\(vopt-2697\).*INIT_FILE',
                      r'fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.*\(vopt-2685\)',
                      r'fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0.*\(vopt-2718\)']
            assert all(any(re.search(pattern,line) for pattern in expected) for line in warnings),warnings
            result['tests'].append({'name':label,'metrics':[line.strip('# ') for line in log.splitlines() if 'RESULT:' in line],
                                    'vendor_model_elaboration_warnings_retained':warnings})
        for row in identity:assert sha(Path(row['path']))==row['sha256'],'Executed input drift: '+row['path']
        result['status']='PASS'
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'status':result['status'],'tests':result['tests'],'result':str(run/'RESULTS.json')},indent=2))


if __name__=='__main__':main()
