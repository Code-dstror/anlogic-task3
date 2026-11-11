"""Short CPU golden + real RTL; all comparisons include RGB, luma and group framing."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess
import numpy as np
from reference import estimate, restore, luma
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def hexfile(path,arrays):
    with path.open('w') as f:
        for rgb in arrays:
            groups=rgb.reshape(-1,4,3)[:,::-1,:].reshape(-1,12)
            ys=luma(rgb).astype('uint8').reshape(-1,4)[:,::-1]
            f.writelines(b.tobytes().hex()+'\n' for b in np.column_stack((ys,groups)))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--name',required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    parser.add_argument('--rtl',type=Path,default=ROOT/'src_fpga/rtl/dehaze_dcp_restore4.v')
    a=parser.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,40}',a.name):parser.error('invalid output identifier')
    out=ROOT/'tmp/dehaze_dcp'/a.name;out.mkdir(parents=True)
    yy,xx=np.indices((128,256));images=[];correct=[];last={}
    specs=[(0,0xffffffff,1),(1,0xffffffff,1),(0,0,1),(0,1,1),(1,0,1),(0,9,1),(0,9,1),(1,1,1),(0,8,2),(0,9,2)]
    for k,(eye,seq,session) in enumerate(specs):
        # Distinct spatially varying haze with aligned patch/row/tile boundaries.
        base=(xx//41)*8+(yy//23)*6 + (112+15*eye+3*k)
        img=np.stack([np.clip(base+(xx+yy+k)%19,0,255),np.clip(base+(xx*3+k)%29,0,255),
                      np.clip(base+(xx+3*yy+5)%24,0,255)],axis=2).astype('uint8')
        img[::11,9::19]=[31,56,20];img[3::17,7::13]=[245,251,242]
        if k==1:
            # Near-achromatic, auto-gained night scene with headlight patches.
            gray=np.where((xx%64)<16,242,126+(yy%23)).astype(np.uint8)
            img=np.repeat(gray[...,None],3,axis=2)
            assert np.any(estimate(img)[1] != estimate(img,protect=False)[1])
        if k==7:last.clear()
        enable=k!=9;previous=last.get(eye)
        valid=enable and previous and previous[0]==session and 0<((seq-previous[1])&0xffffffff)<=4
        correct.append(restore(img,previous[2] if valid else None));images.append(img)
        if enable and k!=3:last[eye]=(session,seq,estimate(img))
    hexfile(out/'input.hex',images);hexfile(out/'expected.hex',correct)
    paths=[a.rtl.resolve(),HERE/'tb_dehaze_dcp.sv',HERE/'reference.py',Path(__file__)]
    def hashes():return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    before=hashes()
    def command(words,name):
        q=subprocess.run(list(map(str,words)),cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=50)
        (out/name).write_text(q.stdout)
        if q.returncode or re.search(r'\*\* (Error|Fatal|Warning):',q.stdout):raise RuntimeError(q.stdout[-4000:])
        return q.stdout
    command([a.modelsim_bin/'vlib.exe','work'],'vlib.log')
    defines=['+define+DCP_STATISTICS_PORT'] if 's_dark_statistics' in a.rtl.read_text().split(');',1)[0] else []
    command([a.modelsim_bin/'vlog.exe','-sv',*defines,*paths[:2]],'compile.log')
    log=command([a.modelsim_bin/'vsim.exe','-c','tb_dehaze_dcp','-do','run -all; quit -f'],'sim.log')
    marker=next(line for line in log.splitlines() if 'RESULT: PASS DCP_PIXEL' in line)
    if hashes()!=before:raise RuntimeError('source drift')
    (out/'result.json').write_text(json.dumps({'status':'PASS','scope':marker,'inputs':before,'warnings':0},indent=2))
    print(marker)
if __name__=='__main__':main()
