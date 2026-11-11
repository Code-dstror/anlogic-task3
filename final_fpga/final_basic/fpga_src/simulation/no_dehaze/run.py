"""Two bounded HD frames through actual no-dehaze service/Gray/Gaussian/HE/C1."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import time
import numpy as np

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_hex(path,values,digits):
    path.write_text(''.join(f'{int(v):0{digits}x}\n' for v in values))


def pixels(path,rgb):
    v=rgb.astype(np.int64)
    y=(77*v[:,:,0]+150*v[:,:,1]+29*v[:,:,2]+128)>>8
    p=((v[:,:,0]<<16)|(v[:,:,1]<<8)|v[:,:,2]).reshape(-1,4)
    ys=y.reshape(-1,4)
    write_hex(path,(sum(int(row[k])<<(24*k) for k in range(4))+
        (sum(int(yrow[k])<<(8*k) for k in range(4))<<96) for row,yrow in zip(p,ys)),32)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/no_dehaze'/a.name;run.mkdir(parents=True,exist_ok=False)
    c1_path=ROOT/'model/c1_reference.py';c1=load('no_dehaze_c1',c1_path)
    yy,xx=np.indices((1080,1920))
    base=42+((xx//80+yy//90)%9)*14
    rgb=np.stack((base+8,base+4,base),axis=2).astype(np.uint8)
    rgb[:,694:707]=(220,220,220);rgb[:,1194:1207]=(210,195,80)
    v=rgb.astype(np.int32);y=((77*v[:,:,0]+150*v[:,:,1]+29*v[:,:,2]+128)>>8).astype(np.uint8)
    # Gray selection precedes the alpha=1/2 color-preserving Gaussian image path.
    gy=c1.gaussian(y).astype(np.int32);delta=gy-y.astype(np.int32)
    half=np.where(delta<0,-((-delta+1)//2),(delta+1)//2)
    filtered=np.clip(y.astype(np.int32)+half,0,255).astype(np.uint8)
    histogram=np.bincount(filtered.ravel(),minlength=256).astype(np.int64)
    cdf=np.cumsum(histogram);first=int(cdf[np.flatnonzero(histogram)[0]])
    lut=np.maximum(cdf-first,0)*255//(filtered.size-first)
    adjustment=np.clip(lut[filtered]-filtered.astype(np.int64),-32,32)
    enhanced=np.clip(filtered.astype(np.int64)+adjustment,0,255).astype(np.uint8)
    assert np.count_nonzero(enhanced!=filtered)>100000
    pixels(run/'source.hex',rgb)
    pixels(run/'expected0.hex',np.repeat(filtered[:,:,None],3,axis=2))
    pixels(run/'expected1.hex',np.repeat(enhanced[:,:,None],3,axis=2))
    q,gx,gy,flags=c1.features(rgb[:,:,::-1].copy())
    packed=(gx.astype(np.int64)&2047)|((gy.astype(np.int64)&2047)<<11)|(q.astype(np.int64)<<22)|(flags.astype(np.int64)<<30)
    write_hex(run/'quarter.hex',packed.ravel(),8)
    points=c1.select_rows(c1.ridge_candidates(q,gx,gy,flags));assert points
    write_hex(run/'points.hex',[int.from_bytes(c1.pack_point(p),'little') for p in points]+[0]*(303-len(points)),10)
    samples=y[3::6,3::6]
    write_hex(run/'stats.hex',[len(points),int(samples.sum()),int(samples.min()),int(samples.max()),int((samples<32).sum()),int((samples>=224).sum())],8)
    (run/'reference.json').write_text(json.dumps(dict(points=points,he_histogram=histogram.tolist(),he_lut=lut.tolist(),enhanced_pixels=int(np.count_nonzero(enhanced!=filtered))),indent=2)+'\n')
    fixture_path=ROOT/'src_fpga/simulation/MAIN_FIXTURE.json';fixture=json.loads(fixture_path.read_text())
    helper_path=ROOT/'src_fpga/simulation/autof21/core/run.py';helper=load('no_dehaze_closure',helper_path)
    groups=helper.closure(fixture,['preprocess_live_f21_service4'])
    forbidden=('preprocess_light_haze','preprocess_dehaze','fixed_dehaze','preprocess_gain_','preprocess_restore_rgb')
    assert not any(any(token in p.name for token in forbidden) for group in groups.values() for p in group)
    parser_path=ROOT/'src_fpga/simulation/timing/r3_run_zero_latency.py';parser=load('no_dehaze_header',parser_path)
    _,_,ports=parser.header((ROOT/'src_fpga/rtl/preprocess_live_f21_service4.v').read_text(),'preprocess_live_f21_service4')
    tb='`timescale 1ns/1ps\nmodule tb_no_dehaze;\n'
    for direction,width,name in ports:
        tb+=('reg ' if direction=='input' else 'wire ')+width+' '+name+('=0;\n' if direction=='input' else ';\n')
    tb+='always #4 clk=~clk;\npreprocess_live_f21_service4 #(.HE_FIXED_CONFIG_SESSION_ENABLE(1),.STEREO_PASSTHROUGH_ENABLE(1)) dut('
    tb+=','.join(f'.{name}({name})' for _,_,name in ports)+');\n'+(HERE/'body.vh').read_text()+'\nendmodule\n'
    (run/'tb.sv').write_text(tb)
    td=a.td_root.resolve();ms=a.modelsim_bin.resolve()
    groups['compile.args']=[td/'sim_release/ph1/ph1_phy_gsr.v',*groups['compile.args'],run/'tb.sv']
    models=[td/p for p in fixture['models']];includes=[ROOT/p for p in fixture['include_dirs']]
    paths={Path(__file__),HERE/'body.vh',c1_path,fixture_path,helper_path,parser_path,*models}
    for group in groups.values():paths.update(group)
    queue=[p for group in groups.values() for p in group];headers=set()
    while queue:
        source=queue.pop()
        for name in re.findall(r'^\s*`include\s+"([^"]+)"',source.read_text(errors='replace'),re.M):
            header=next((directory/name for directory in [source.parent,*includes] if (directory/name).is_file()),None)
            assert header is not None,(source,name)
            if header not in headers:headers.add(header);queue.append(header)
    paths.update(headers);paths.update(run.glob('*.hex'));paths.add(run/'reference.json')
    identity=[dict(path=p.resolve().as_posix(),sha256=sha(p)) for p in sorted(paths)]
    report=dict(status='IN_PROGRESS',command=sys.argv,inputs=identity,commands=[],scope='Two actual HD no-dehaze Gray/colorGaussian/qualifiedHE frames with C1/native-color/neutral stats oracle',synthesis='NOT_RUN',PNR='NOT_RUN',STA='NOT_RUN',board='NOT_RUN')
    started=time.monotonic()
    def execute(exe,args):
        cmd=[str(ms/exe),*map(str,args)];report['commands'].append(cmd)
        with (run/(exe+'.console.log')).open('a') as log:
            proc=subprocess.Popen(cmd,cwd=run,stdout=log,stderr=subprocess.STDOUT)
            try:code=proc.wait(timeout=600)
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                raise RuntimeError('Bounded600s watchdog stopped owned process tree')
        assert code==0,(exe,code)
    try:
        execute('vmap.exe',['-c'])
        for lib in ['work','ph1']:execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        for name,group in groups.items():
            if group:execute('vlog.exe',['-quiet',*(['-sv'] if name=='compile.args' else []),'-work','work','-l',name+'.log','-timescale','1ns/1ps','+define+PH1',*['+incdir+'+p.as_posix() for p in includes],*group])
        execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_no_dehaze','-l','run.log','-do','onerror {quit -code 1}; run -all; quit -f'])
        logs='\n'.join(p.read_text(errors='replace') for p in run.glob('*.log'))
        assert 'RESULT: PASS NO_DEHAZE_SERVICE' in logs and not re.search(r'\*\* (?:Error|Fatal):',logs),logs[-6000:]
        for item in identity:assert sha(item['path'])==item['sha256'],item['path']
        warnings=list(dict.fromkeys(line for line in logs.splitlines() if '** Warning:' in line))
        assert not [line for line in warnings if '/src_fpga/rtl/' in line.replace('\\','/')]
        report.update(status='PASS',results=list(dict.fromkeys(line.strip('# ') for line in logs.splitlines() if ' PASS ' in line)),warnings=warnings)
    except Exception as error:report.update(status='FAIL',error=str(error));raise
    finally:
        report['elapsed_seconds']=round(time.monotonic()-started,3)
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(dict(run=run.as_posix(),status=report['status'],elapsed_seconds=report['elapsed_seconds'])),flush=True)


if __name__=='__main__':main()
