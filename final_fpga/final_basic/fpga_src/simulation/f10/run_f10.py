"""Two bounded F10 production-composition checks; no main/board/server work."""
from pathlib import Path
import argparse
import collections
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from PIL import Image

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='f3fc9adb5462ea91b50886be6dfa23449eec4d74'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(name,p):
    spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec)
    sys.modules[name]=m;spec.loader.exec_module(m);return m
def packed(values,bits):return sum(v<<(bits*n) for n,v in enumerate(values))
def write_hex(p,values,digits):p.write_text(''.join(f'{v:0{digits}x}\n' for v in values))


def prepare(run,fixture):
    refs=ROOT/'verification_reference'
    jpeg_path=refs/'src_fpga/simulation/jpeg_shared_encoder_reference.py'
    jpeg=load('f10_frozen_jpeg',jpeg_path)
    cases=[dict(case=0,width=240,height=16,quality=37,restart=3,pattern='texture'),
           dict(case=1,width=240,height=16,quality=91,restart=5,pattern='noise')]
    for case in cases:jpeg.generate_frame(run,case)
    source='tools/hdr_ref/hdr_ref.py'
    raw=subprocess.check_output(['git','show',BASE+':'+source],cwd=REPO)
    frozen=run/'frozen_hdr_ref.py';frozen.write_bytes(raw)
    hdr=load('f10_frozen_hdr',frozen)
    tone_path=refs/'src_fpga/stages/r8_stage3/pending/hdr_pairbank_20261014/numerical/tone96_reference.py'
    tone=load('f10_frozen_t96',tone_path)
    gamma=[int(v,16) for v in (refs/'src_fpga/rtl/isp/color/gamma22_10to8.dath').read_text().split()]
    sw,sh,w,h=248,19,240,16;knees=[767,768,769,775,776,895,896,897]
    long12=[];short12=[]
    for y in range(sh):
        for x in range(sw):
            radiance=(47*x+811*y+13*x*y+117*((x+2*y)%3))%15000
            lr=min(1023,radiance+32);sr=min(1023,(radiance+8)//16+16)
            residue=(x+2*y)%4
            if x%48<8:lr=knees[x%8];sr=16+(lr-32+8)//16;residue=0
            if 64<=x<96 and 4<=y<8:lr=300+(x*3+y*5)%250;sr=100+(x+3*y)%60
            long12.append(min(4095,4*lr+residue));short12.append(min(4095,4*sr+(residue^1)))
    crop=lambda a:[min(1023,(a[y*sw+x]+2)//4) for y in range(1,17) for x in range(4,244)]
    longs,shorts=crop(long12),crop(short12)
    fused,masks=hdr.merge_frame(longs,shorts)
    rgb14=hdr.demosaic(fused,w,h,3)
    corrected=[tuple(min(16383,(v*g+128)//256) for v,g in zip(pixel,(909,410,832))) for pixel in rgb14]
    rgb=[tuple(gamma[v] for v in tone.tone_rgb(pixel)) for pixel in corrected]
    write_hex(run/'sensor.hex',[packed(long12[i:i+4],12)|(packed(short12[i:i+4],12)<<48) for i in range(0,sw*sh,4)],24)
    write_hex(run/'crop.hex',[packed(longs[i:i+4],10)|(packed(shorts[i:i+4],10)<<40) for i in range(0,w*h,4)],20)
    write_hex(run/'merge.hex',[packed(fused[i:i+4],14)|(masks[i//4]<<56) for i in range(0,w*h,4)],15)
    write_hex(run/'rgb.hex',[packed([(r<<16)|(g<<8)|b for r,g,b in rgb[i:i+4]],24) for i in range(0,w*h,4)],24)
    assert any(masks) and not all(masks),'Need both static and motion regions'
    assert set(knees)<=set(longs),'Need all clipping-knee boundaries'
    rom=run/'rom_init';rom.mkdir()
    rom_paths=[]
    for name,relative in fixture['local_rom_initializers'].items():
        p=ROOT/relative;text=p.read_text();depth=int(re.search(r'DEPTH\s*=\s*(\d+)',text).group(1))
        width=int(re.search(r'WIDTH\s*=\s*(\d+)',text).group(1));entries=re.findall(r'(?m)^\s*([\da-fA-F]+)\s*:\s*([\da-fA-F]+)\s*;',text)
        values={int(a,16):int(v,16) for a,v in entries};assert len(entries)==depth and set(values)==set(range(depth))
        image=rom/name;write_hex(image,[values[n] for n in range(depth)],(width+3)//4);rom_paths += [p,image]
    authority=[p for p in refs.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    return cases,jpeg,authority+[frozen]+rom_paths,dict(width=w,height=h,sensor_width=sw,sensor_height=sh,crop=[4,1],bayer_phase=3,
        motion_groups=sum(bool(m) for m in masks),static_groups=sum(not m for m in masks),knee_codes=knees,
        frozen_hdr_origin=dict(commit=BASE,path=source,sha256=hashlib.sha256(raw).hexdigest()))


def closure(fixture):
    paths=list(dict.fromkeys(ROOT/r['path'] for group in fixture['groups'].values() for r in group if 'path' in r))
    mapping={};body={}
    for p in paths:
        if p.suffix not in ('.v','.sv') or '.enc.' in p.name:continue
        raw=p.read_text(errors='replace')
        if '`pragma protect begin_protected' in raw:
            mapping[p.stem]=p;body[p]='';continue
        text=re.sub(r'/\*.*?\*/|//[^\n]*','',raw,flags=re.S);body[p]=text
        for module in re.findall(r'\bmodule\s+(\w+)',text):mapping[module]=p
    selected=set();todo=['jpeg_encoder_top','real_hdr_member_crop10','hdr_merge4','shared_wide_isp']
    while todo:
        module=todo.pop();p=mapping[module]
        if p in selected:continue
        selected.add(p);tokens=set(re.findall(r'\b\w+\b',body[p]));todo += [n for n in mapping if n in tokens and mapping[n] not in selected]
    return {name:[ROOT/r['path'] for r in group if 'path' in r and ROOT/r['path'] in selected]
            for name,group in fixture['groups'].items()}


def jpeg_check(run,case,jpeg):
    index=case['case'];actual=run/f'case{index}.actual.jpg';expected=run/f'case{index}.expected.jpg'
    data=actual.read_bytes();assert data==expected.read_bytes(),f'JPEG case{index} differs from independent encoder'
    segments={};offset=2
    while data[offset:offset+2]!=b'\xff\xda':
        assert data[offset]==255;marker=data[offset+1];size=int.from_bytes(data[offset+2:offset+4],'big')
        segments[marker]=data[offset+4:offset+2+size];offset+=2+size
    table=segments[0xdb]
    for start,chroma in [(1,False),(66,True)]:
        assert list(table[start:start+64])==[jpeg.qtable(case['quality'],chroma)[n] for n in jpeg.ref.ZIGZAG]
    assert int.from_bytes(segments[0xdd],'big')==case['restart']
    rst=[data[n+1] for n in range(len(data)-1) if data[n]==255 and 0xd0<=data[n+1]<=0xd7]
    assert rst==[0xd0+n%8 for n in range((case['mcus']-1)//case['restart'])]
    with Image.open(actual) as image:
        image.load();assert image.size==(240,16);decoded=list(image.convert('RGB').getdata())
    original=list(jpeg.pixels_for(240,16,case['pattern']))
    diffs=[abs(a-b) for p,q in zip(decoded,original) for a,b in zip(p,q)]
    return dict(case=index,quality=case['quality'],restart=case['restart'],bytes=len(data),sha256=sha(actual),
                exact_bytes='PASS',DQT='PASS',DRI='PASS',RST_count=len(rst),RST_sequence='PASS',decode='PASS',
                decoded_max_error=max(diffs),decoded_mae=sum(diffs)/len(diffs))


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True);ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/f10'/a.name;run.mkdir(parents=True,exist_ok=False)
    fixture=json.loads((ROOT/'src_fpga/simulation/MAIN_FIXTURE.json').read_text())
    cases,jpeg,refs,hdr=prepare(run,fixture);groups=closure(fixture)
    models=[a.td_root/p for p in fixture['models']]
    groups['compile.args'].insert(0,a.td_root/'sim_release/ph1/ph1_phy_gsr.v')
    groups['compile.args'] += [HERE/'tb_jpeg_dynamic.sv',HERE/'tb_hdr_spatial.sv']
    includes=[ROOT/p for p in fixture['include_dirs']]
    inputs=set(models+refs+[Path(__file__),ROOT/'src_fpga/simulation/MAIN_FIXTURE.json'])
    for group in groups.values():inputs.update(group)
    queue=list(inputs);visited=set()
    while queue:
        p=queue.pop()
        if p in visited:continue
        visited.add(p)
        if p.suffix in ('.v','.sv','.vh'):
            for name in re.findall(r'`include\s+"([^"]+)"',p.read_text(errors='replace')):
                found=next((q for q in [p.parent/name,*[d/name for d in includes]] if q.is_file()),None)
                if found and found not in inputs:inputs.add(found);queue.append(found)
    inputs.update(run.glob('*.hex'));inputs.update(run.glob('*.expected.jpg'))
    identity=[dict(path=p.resolve().as_posix(),sha256=sha(p)) for p in sorted(inputs)]
    report=dict(status='IN_PROGRESS',scope=__doc__,inputs=identity,jpeg_cases=cases,hdr_case=hdr,
        production_jpeg_parameters=dict(SHARED_STREAM_ENABLE=1,MCU_ROW_STREAM_ENABLE=1,FIXED_GEOMETRY_ENABLE=1,
            TINY_DISTRIBUTED_RAM_ENABLE=1,COEFF_BANKED_STORAGE_ENABLE=1),physical='NOT_RUN',board='NOT_RUN')
    def execute(exe,args):
        p=subprocess.run([str(a.modelsim_bin/exe),*[str(x) for x in args]],cwd=run,capture_output=True,text=True,errors='replace')
        if p.returncode:raise RuntimeError(p.stdout[-10000:]+p.stderr[-2000:])
    try:
        execute('vmap.exe',['-c'])
        for lib in ['work','ph1']:execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        defs=['PH1']+['fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        for name,group in groups.items():
            if not group:continue
            args=['-quiet','-work','work','-l',name+'.log','-timescale','1ns/1ps']
            if name=='compile.args':args+=['-sv']
            args += ['+define+'+v for v in defs]+['+incdir+'+p.as_posix() for p in includes]+group
            execute('vlog.exe',args)
            assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(run/(name+'.log')).read_text(errors='replace'))
        metrics=[];warnings=collections.Counter()
        for top,log in [('tb_jpeg_dynamic','jpeg.log'),('tb_hdr_spatial','hdr.log')]:
            execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.'+top,'-l',log,
                '-do','onerror {quit -code 1}; run -all; quit -f'])
            text=(run/log).read_text(errors='replace');assert 'RESULT: PASS' in text and not re.search(r'\*\* (?:Error|Fatal):',text),text[-8000:]
            for line in text.splitlines():
                if '** Warning:' in line:
                    assert '/src_fpga/rtl/' not in line.replace('\\','/'),line
                    m=re.search(r'\((vopt-\d+|vsim-\d+)\)',line);warnings[m.group(1) if m else line]+=1
            metrics += [line for line in text.splitlines() if 'PASS' in line]
        checked=[jpeg_check(run,c,jpeg) for c in cases]
        for x in identity:assert sha(Path(x['path']))==x['sha256'],x['path']
        report.update(status='PASS',metrics=metrics,jpeg_checks=checked,vendor_warning_codes=dict(warnings),owned_warnings=0)
        print('\n'.join(metrics));print('JPEG exact bytes/DQT/DRI/RST/complete decode PASS')
    except Exception as e:report.update(status='FAIL',error=str(e));raise
    finally:(run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n');print('Evidence',run)


if __name__=='__main__':main()
