"""R1/current MCU matrix, then only the existing two-frame F10 JPEG case."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='d86edbed408230828e6cd8a887bceec80c242307'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec)
    sys.modules[name]=m;spec.loader.exec_module(m);return m


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True,type=Path);ap.add_argument('--modelsim-bin',required=True,type=Path)
    a=ap.parse_args();assert re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name)
    run=ROOT/'tmp/r3_mcu_select'/a.name;run.mkdir(parents=True,exist_ok=False)
    def execute(directory,exe,args):
        p=subprocess.run([str(a.modelsim_bin/exe),*[str(x) for x in args]],cwd=directory,
                         capture_output=True,text=True,errors='replace')
        if p.returncode:raise RuntimeError(p.stdout[-12000:]+p.stderr[-2000:])
    def libraries(directory,models):
        execute(directory,'vmap.exe',['-c'])
        for lib in ['work','ph1']:execute(directory,'vlib.exe',[lib]);execute(directory,'vmap.exe',[lib,lib])
        execute(directory,'vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
    def identity(paths):return [{'path':p.resolve().as_posix(),'sha256':sha(p)} for p in sorted(set(paths))]
    def stable(rows):
        for row in rows:assert sha(Path(row['path']))==row['sha256'],row['path']
    report={'status':'IN_PROGRESS','baseline_commit':BASE,'scope':__doc__,'tests':[],
            'synthesis':'NOT_RUN','physical':'NOT_RUN','board':'NOT_RUN'}
    try:
        refs=[];origins=[]
        for module in ['jpeg_mcu_422','jpeg_mcu_packed_plane']:
            path='refactor/hdr_jpeg_timing/src_fpga/rtl/'+module+'.v'
            raw=subprocess.check_output(['git','show',BASE+':'+path],cwd=REPO)
            if module.endswith('packed_plane'):
                assert raw==(ROOT/'src_fpga/rtl'/f'{module}.v').read_bytes(),'Plane source changed; re-evaluate baseline scope'
            text=raw.decode()
            for old in ['jpeg_mcu_422','jpeg_mcu_packed_plane']:text=re.sub(r'\b'+old+r'\b','r3_ref_'+old,text)
            target=run/('r3_ref_'+module+'.v');target.write_text(text);refs.append(target)
            origins.append({'commit':BASE,'path':path,'sha256':hashlib.sha256(raw).hexdigest()})
        models=[a.td_root/'sim_release'/p for p in ['common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v']]
        sources=[a.td_root/'sim_release/ph1/ph1_phy_gsr.v',
                 ROOT/'src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v']
        sources += [ROOT/'src_fpga/rtl'/n for n in ['jpeg_mcu_packed_plane.v','jpeg_mcu_422.v','jpeg_mcu_read_align8.v']]
        sources += refs+[HERE/'r3_mcu_select_tb.sv']
        matrix_inputs=identity(models+sources+[Path(__file__)])
        report.update(baseline=origins,matrix_inputs=matrix_inputs)
        libraries(run,models)
        execute(run,'vlog.exe',['-quiet','-sv','-timescale','1ns/1ps','+define+PH1','-l','compile.log',*sources])
        assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(run/'compile.log').read_text(errors='replace'))
        for row in [0,1]:
            for fixed in [0,1]:
                log=f'row{row}_fixed{fixed}.log'
                execute(run,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.r3_mcu_select_tb',
                    '-gROW_STREAM='+str(row),'-gFIXED='+str(fixed),'-l',log,
                    '-do','onerror {quit -code 1}; run -all; quit -f'])
                body=(run/log).read_text(errors='replace')
                assert 'RESULT: PASS R3_MCU_SELECT' in body and not re.search(r'\*\* (?:Error|Fatal):',body),body[-10000:]
                warnings=[x for x in body.splitlines() if '** Warning:' in x]
                for line in warnings:
                    assert '/src_fpga/rtl/' not in line.replace('\\','/'),line
                    assert re.search(r'vopt-2241|vopt-2697|vsim-3015',line),line
                metrics=[x for x in body.splitlines() if 'RESULT: PASS' in x];print('\n'.join(metrics),flush=True)
                report['tests'].append({'row_stream':row,'fixed_geometry':fixed,'status':'PASS','metrics':metrics,
                                        'vendor_warning_count':len(warnings),'log':log})
        stable(matrix_inputs)

        # Reuse the unchanged F10 testbench and frozen JPEG authority, but do
        # not rerun its separate HDR spatial simulation or any full MAIN.
        jpegdir=run/'jpeg';jpegdir.mkdir()
        f10_path=ROOT/'src_fpga/simulation/f10/run_f10.py';f10=load('r3_mcu_f10_support',f10_path)
        reference_path=ROOT/'verification_reference/src_fpga/simulation/jpeg_shared_encoder_reference.py'
        reference=load('r3_mcu_frozen_jpeg',reference_path)
        cases=[dict(case=0,width=240,height=16,quality=37,restart=3,pattern='texture'),
               dict(case=1,width=240,height=16,quality=91,restart=5,pattern='noise')]
        for case in cases:reference.generate_frame(jpegdir,case)
        # The frozen inventory prevents unrelated concurrent MAIN fixture edits
        # from changing this bounded test's source selection.
        fixture_origin='refactor/hdr_jpeg_timing/src_fpga/simulation/MAIN_FIXTURE.json'
        raw=subprocess.check_output(['git','show',BASE+':'+fixture_origin],cwd=REPO)
        fixture=json.loads(raw);fixture_path=jpegdir/'r3_fixture.json';fixture_path.write_bytes(raw)
        rom=jpegdir/'rom_init';rom.mkdir();rom_inputs=[]
        for name,relative in fixture['local_rom_initializers'].items():
            path=ROOT/relative;text=path.read_text();depth=int(re.search(r'DEPTH\s*=\s*(\d+)',text).group(1))
            width=int(re.search(r'WIDTH\s*=\s*(\d+)',text).group(1))
            pairs=re.findall(r'(?m)^\s*([\da-fA-F]+)\s*:\s*([\da-fA-F]+)\s*;',text)
            values={int(k,16):int(v,16) for k,v in pairs};assert len(pairs)==depth and set(values)==set(range(depth))
            target=rom/name;target.write_text(''.join(f'{values[i]:0{(width+3)//4}x}\n' for i in range(depth)))
            rom_inputs += [path,target]
        groups=f10.closure(fixture);jpeg_models=[a.td_root/p for p in fixture['models']]
        groups['compile.args'].insert(0,a.td_root/'sim_release/ph1/ph1_phy_gsr.v')
        groups['compile.args'].append(ROOT/'src_fpga/simulation/f10/tb_jpeg_dynamic.sv')
        includes=[ROOT/p for p in fixture['include_dirs']]
        authorities=[p for p in (ROOT/'verification_reference').rglob('*') if p.is_file() and '__pycache__' not in p.parts]
        paths=set(jpeg_models+rom_inputs+authorities+[Path(__file__),f10_path,fixture_path])
        for group in groups.values():paths.update(group)
        queue=list(paths);visited=set()
        while queue:
            path=queue.pop()
            if path in visited:continue
            visited.add(path)
            if path.suffix in ('.v','.sv','.vh'):
                for name in re.findall(r'`include\s+"([^"]+)"',path.read_text(errors='replace')):
                    found=next((p for p in [path.parent/name,*[d/name for d in includes]] if p.is_file()),None)
                    if found and found not in paths:paths.add(found);queue.append(found)
        paths.update(jpegdir.glob('*.hex'));paths.update(jpegdir.glob('*.expected.jpg'))
        jpeg_inputs=identity(paths);report['jpeg_inputs']=jpeg_inputs
        libraries(jpegdir,jpeg_models)
        defs=['PH1']+['fdct_mac19s14s_z33s_p34_m1p1_USE_'+n+'=1' for n in ['A','CE','PH1A','RST','Y','Z']]
        for name,group in groups.items():
            if not group:continue
            args=['-quiet','-work','work','-timescale','1ns/1ps','-l',name+'.log']+(['-sv'] if name=='compile.args' else [])
            execute(jpegdir,'vlog.exe',args+['+define+'+d for d in defs]+['+incdir+'+d.as_posix() for d in includes]+group)
            assert not re.search(r'\*\* (?:Warning|Error|Fatal):',(jpegdir/(name+'.log')).read_text(errors='replace'))
        execute(jpegdir,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_jpeg_dynamic',
            '-l','run.log','-do','onerror {quit -code 1}; run -all; quit -f'])
        body=(jpegdir/'run.log').read_text(errors='replace')
        assert 'RESULT: PASS F10_DYNAMIC_JPEG' in body and not re.search(r'\*\* (?:Error|Fatal):',body),body[-12000:]
        report['jpeg_metrics']=[s for s in body.splitlines() if 'PASS' in s]
        report['jpeg_checks']=[f10.jpeg_check(jpegdir,case,reference) for case in cases]
        stable(jpeg_inputs);stable(matrix_inputs)
        report.update(status='PASS',mcu_sha256=sha(ROOT/'src_fpga/rtl/jpeg_mcu_422.v'),
                      added_state_bits=2,added_external_cycles=0)
        print('\n'.join(report['jpeg_metrics']));print('RESULT: PASS R3_MCU_SELECT_MATRIX_AND_JPEG',flush=True)
    except Exception as e:report.update(status='FAIL',error=str(e));raise
    finally:
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n');print('Evidence',run)


if __name__=='__main__':main()
