"""Two complete small SDR frames through the actual shared ISP and JPEG.

Frozen scalar ISP and JPEG authorities generate expectations before execution.
No camera/DDR/v4 slot proof is inferred from this isolated arithmetic test.
"""
from pathlib import Path
import argparse, collections, hashlib, importlib.util, json, re, subprocess, sys, time
from PIL import Image

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module)
    return module

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True);ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--td-root',type=Path,required=True);a=ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/dual_pipeline'/a.name;run.mkdir(parents=True,exist_ok=False)
    fixture_path=ROOT/'src_fpga/simulation/MAIN_FIXTURE.json'
    fixture=json.loads(fixture_path.read_text())
    helpers=load('candidate_f10_helpers',HERE.parent/'f10/run_f10.py')
    refs=ROOT/'verification_reference'
    isp=load('dual_frozen_isp',refs/'src_fpga/simulation/shared_wide_isp_reference.py')
    jpeg=load('dual_frozen_jpeg',refs/'src_fpga/simulation/jpeg_shared_encoder_reference.py')
    raw,rgb,_,_=isp.fixture(240,16,False)
    (run/'raw.hex').write_text(''.join(f'{v:014x}\n' for v in raw))
    (run/'rgb.hex').write_text(''.join(f'{v:024x}\n' for v in rgb))
    pixels=[tuple(((v>>(24*lane))>>shift)&255 for shift in (16,8,0)) for v in rgb for lane in range(4)]
    # The expected JPEG consumes only independent expected ISP pixels, never DUT output.
    jpeg.pixels_for=lambda width,height,pattern:iter(pixels)
    cases=[dict(case=n,width=240,height=16,quality=q,restart=r,pattern='scalar_isp')
           for n,(q,r) in enumerate([(37,3),(91,5)])]
    for row in cases:jpeg.generate_frame(run,row)
    rom=run/'rom_init';rom.mkdir()
    extra=[]
    for name,relative in fixture['local_rom_initializers'].items():
        p=ROOT/relative;text=p.read_text();depth=int(re.search(r'DEPTH\s*=\s*(\d+)',text).group(1))
        entries=re.findall(r'(?m)^\s*([\da-fA-F]+)\s*:\s*([\da-fA-F]+)\s*;',text)
        values={int(k,16):v for k,v in entries};assert len(values)==depth
        dest=rom/name;dest.write_text(''.join(values[n]+'\n' for n in range(depth)));extra.extend([p,dest])
    groups=helpers.closure(fixture)
    groups['compile.args'].insert(0,a.td_root/'sim_release/ph1/ph1_phy_gsr.v')
    groups['compile.args'].append(HERE/'tb_dual_pipeline.sv')
    models=[a.td_root/p for p in fixture['models']]
    includes=[ROOT/p for p in fixture['include_dirs']]
    inputs=set(models+extra+[Path(__file__),HERE.parent/'f10/run_f10.py',fixture_path])
    inputs.update(p for p in refs.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
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
    report=dict(status='IN_PROGRESS',scope=__doc__,inputs=identity,commands=[],
        geometry=[240,16],eyes=2,sustained_fps='NOT_RUN',record_v4='SEPARATE_TEST',
        physical='NOT_RUN',synthesis='NOT_RUN',board='NOT_RUN')
    start=time.monotonic()
    def call(name,exe,args):
        argv=[str(a.modelsim_bin/exe),*[str(x) for x in args]]
        p=subprocess.run(argv,cwd=run,capture_output=True,text=True,errors='replace',timeout=120)
        (run/(name+'.console.log')).write_text(p.stdout+p.stderr)
        report['commands'].append(dict(argv=argv,returncode=p.returncode))
        if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-10000:])
    try:
        call('map','vmap.exe',['-c'])
        for lib in ['work','ph1']:call('lib_'+lib,'vlib.exe',[lib]);call('map_'+lib,'vmap.exe',[lib,lib])
        call('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        defs=['PH1']+['fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        for name,group in groups.items():
            if not group:continue
            args=['-quiet','-work','work','-l',name+'.log','-timescale','1ns/1ps']
            if name=='compile.args':args+=['-sv']
            args+=['+define+'+v for v in defs]+['+incdir+'+p.as_posix() for p in includes]+group
            call(name,'vlog.exe',args)
            assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(run/(name+'.log')).read_text(errors='replace'))
        call('sim','vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_dual_pipeline','-l','run.log',
            '-do','onerror {quit -code 1}; run -all; quit -f'])
        log=(run/'run.log').read_text(errors='replace')
        assert 'RESULT: PASS DUAL_SHARED_ISP_JPEG' in log and not re.search(r'\*\* (?:Error|Fatal):',log),log[-9000:]
        warnings=collections.Counter()
        for line in log.splitlines():
            if '** Warning:' in line:
                assert '/src_fpga/rtl/' not in line.replace('\\','/'),line
                code=re.search(r'\((vopt-\d+|vsim-\d+)\)',line);warnings[code.group(1) if code else line]+=1
        decoded=[]
        for row in cases:
            actual=run/f"case{row['case']}.actual.jpg";expected=run/f"case{row['case']}.expected.jpg"
            assert actual.read_bytes()==expected.read_bytes(),'Exact independent JPEG byte mismatch'
            with Image.open(actual) as image:image.load();assert image.size==(240,16)
            decoded.append(dict(camera=row['case'],capture_id=101+row['case'],epoch=21+row['case'],
                quality=row['quality'],restart=row['restart'],bytes=actual.stat().st_size,sha256=sha(actual),
                exact_independent_bytes='PASS',complete_decode='PASS'))
        for row in identity:assert sha(Path(row['path']))==row['sha256'],'Input drift '+row['path']
        report.update(status='PASS',metrics=[l.strip('# ') for l in log.splitlines() if 'PASS' in l],
            jpeg=decoded,owned_warnings=0,reviewed_vendor_warning_codes=dict(warnings))
        print('\n'.join(report['metrics']));print('Independent ISP pixels / complete JPEG bytes+decode PASS')
    except Exception as exc:report.update(status='FAIL',error=str(exc));raise
    finally:
        report['elapsed_seconds']=round(time.monotonic()-start,3)
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n');print(run)

if __name__=='__main__':main()
