"""Bounded ingress A/B miter against fixed ed50, pure RTL/ModelSim only."""
from pathlib import Path
import argparse,subprocess,re,json,hashlib,time
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True);ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--leaf',type=Path,default=PROJECT/'src_fpga/rtl/shared_raw10_frame_ingress.v')
    ap.add_argument('--reference',type=Path,help='compare to a specified production revision')
    ap.add_argument('--before-cam1',action='store_true',help='use the frozen generic ingress before the compact CAM1 wire format')
    ap.add_argument('--production-profile',action='store_true', help='only the configured four-member ingress profile')
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]*',a.name)
    out=PROJECT/'tmp/area_ingress'/a.name;out.mkdir(parents=True,exist_ok=False)
    old=HERE/'baseline/shared_raw10_frame_ingress.v'
    manifest=HERE/'baseline/MANIFEST.json';assert sha(old)==json.loads(manifest.read_text())['sha256']
    if a.before_cam1:
        if a.reference:ap.error('--reference and --before-cam1 select different baselines')
        old=out/'before_cam1.v'
        old.write_bytes(subprocess.check_output(['git','show',
            '40ad33a6:refactor/camera_shared_r1/src_fpga/rtl/shared_raw10_frame_ingress.v'],cwd=PROJECT))
    elif a.reference:
        old=a.reference.resolve()
    renamed=out/'shared_raw10_frame_ingress_before.v'
    renamed.write_text(re.sub(r'\bshared_raw10_frame_ingress\b','shared_raw10_frame_ingress_before',old.read_text()),newline='\n')
    sources=[PROJECT/'src_fpga/rtl/raw10_append5.v',a.leaf.resolve(),renamed,HERE/'tb_ingress_equivalence.sv']
    inputs=[dict(path=str(p.resolve()),sha256=sha(p)) for p in sources+[old,manifest,Path(__file__)]]
    profiles=[]
    for c,p,s,e in [(1,1,1,1),(1,0,1,0),(0,0,0,0),(1,0,0,1)]:
        if a.production_profile and (c,p,s,e)!=(1,1,1,1):
            continue
        profiles.extend([dict(W=4,H=h,C=c,P=p,S=s,E=e) for h in range(1,17)])
        profiles.extend([dict(W=68,H=5,C=c,P=p,S=s,E=e),dict(W=20,H=3,C=c,P=p,S=s,E=e)])
        if (a.reference or a.before_cam1) and c and p:
            profiles.extend([dict(W=64,H=7,C=c,P=p,S=s,E=e),dict(W=1920,H=1,C=c,P=p,S=s,E=e)])
    result=dict(status='RUNNING',baseline_commit='ed50d4e7534b1574213d173e941dbfbcfdf20351',inputs=inputs,profiles=[],commands=[],td_root=str(a.td_root.resolve()),td_models='NOT_REQUIRED_PURE_RTL',synthesis='NOT_RUN',pnr='NOT_RUN',board='NOT_RUN')
    if a.reference or a.before_cam1:
        result.pop('baseline_commit')
        result['reference_sha256']=sha(old)
    start=time.monotonic()
    def call(argv,name):
        argv=list(map(str,argv));result['commands'].append(argv)
        r=subprocess.run(argv,cwd=out,capture_output=True,text=True,errors='replace',timeout=50)
        t=r.stdout+r.stderr;(out/name).write_text(t)
        if r.returncode or re.search(r'\*\*\s+(Warning|Error|Fatal):',t):raise RuntimeError(name+': '+t[-4500:])
        return t
    try:
        call([a.modelsim_bin/'vlib.exe','work'],'vlib.log')
        call([a.modelsim_bin/'vlog.exe','-sv','-work','work',*sources],'compile.log')
        for n,profile in enumerate(profiles):
            t=call([a.modelsim_bin/'vsim.exe','-c','work.tb_ingress_equivalence',*[f'-g{k}={v}' for k,v in profile.items()],'-do','onerror {quit -code 1}; run -all; quit -f'],f'profile_{n:02}.log')
            markers=re.findall('RESULT: PASS [^\r\n]+',t)
            if len(markers)!=1:raise RuntimeError(f'profile{n}: missing PASS')
            result['profiles'].append(dict(parameters=profile,metric=markers[0]));print(n,markers[0],flush=True)
        for row in inputs:assert sha(Path(row['path']))==row['sha256'],'input drift'
        result.update(status='PASS',owned_warnings=0)
    except Exception as exc:result.update(status='FAIL',error=str(exc));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-start,3)
        (out/'qualification.json').write_text(json.dumps(result,indent=2)+'\n')
        print(out/'qualification.json',flush=True)
if __name__=='__main__':main()
