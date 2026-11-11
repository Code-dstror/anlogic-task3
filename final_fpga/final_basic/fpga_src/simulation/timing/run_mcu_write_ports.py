"""Check registered MCU RAM writes against the immutable routed source and pixels."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]
BASE='f3fc9adb5462ea91b50886be6dfa23449eec4d74'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name):ap.error('invalid name')
    run=ROOT/'tmp/mcu_write_ports'/a.name;run.mkdir(parents=True,exist_ok=False)
    baselines=[];origin=[]
    for name,new in [('jpeg_mcu_packed_plane','plane_baseline'),('jpeg_mcu_422','mcu_baseline')]:
        path='refactor/hdr_jpeg/src_fpga/rtl/'+name+'.v'
        raw=subprocess.check_output(['git','show',BASE+':'+path],cwd=REPO)
        body=raw.decode().replace('\r\n','\n').replace('jpeg_mcu_packed_plane','plane_baseline').replace('module jpeg_mcu_422','module mcu_baseline')
        target=run/(new+'.v');target.write_text(body,encoding='utf-8',newline='\n');baselines.append(target)
        origin.append({'commit':BASE,'path':path,'sha256':hashlib.sha256(raw).hexdigest()})
    models=[a.td_root/'sim_release'/p for p in ['common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_phy_eram.v']]
    sources=[a.td_root/'sim_release/ph1/ph1_phy_gsr.v',ROOT/'src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v']
    sources+=[ROOT/'src_fpga/rtl'/n for n in ['jpeg_mcu_packed_plane.v','jpeg_mcu_422.v','jpeg_mcu_read_align8.v']]
    sources+=baselines+[HERE/'tb_mcu_write_ports.sv']
    inputs=[{'path':p.as_posix(),'sha256':sha(p)} for p in models+sources+[Path(__file__)]]
    report={'status':'IN_PROGRESS','baseline':origin,'inputs':inputs,'td_root':str(a.td_root),
            'synthesis':'NOT_RUN','physical':'NOT_RUN','board':'NOT_RUN'}
    def execute(exe,args):
        r=subprocess.run([str(a.modelsim_bin/exe)]+[str(x) for x in args],cwd=run,
                         capture_output=True,text=True,errors='replace')
        if r.returncode:raise RuntimeError(r.stdout[-10000:]+r.stderr[-1000:])
    try:
        execute('vmap.exe',['-c'])
        for lib in ['work','ph1']:
            execute('vlib.exe',[lib]);execute('vmap.exe',[lib,lib])
        execute('vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        execute('vlog.exe',['-quiet','-sv','-timescale','1ns/1ps','+define+PH1','-l','compile.log']+sources)
        execute('vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_mcu_write_ports',
                           '-l','run.log','-do','onerror {quit -code 1}; run -all; quit -f'])
        body=(run/'run.log').read_text(errors='replace')
        if 'RESULT: PASS mcu_write_ports' not in body or re.search(r'\*\* (Error|Fatal):',body):raise RuntimeError(body[-10000:])
        if re.search(r'\*\* (Warning|Error|Fatal):',(run/'compile.log').read_text()):raise RuntimeError('Compile diagnostics')
        lines=body.splitlines();warnings=0
        for index,line in enumerate(lines):
            if '** Warning:' not in line:continue
            warnings+=1
            allowed=('ram40_sdp_fixed.v(69)' in line and '(vopt-2241)' in line and 'ecc_' in line)
            allowed|=('ph1_logic_eram.v' in line and '(vopt-2697)' in line and "into 'INIT_FILE'" in line)
            allowed|=('(vsim-3015)' in line and 'ecc_' in line and index+1<len(lines) and 'ram40_sdp_fixed.v Line: 69' in lines[index+1])
            if not allowed:raise RuntimeError('Unclassified warning: '+line)
        for row in inputs:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('Input changed '+row['path'])
        report.update(status='PASS',vendor_warning_count=warnings,metrics=[x for x in lines if 'RESULT: PASS' in x])
        print('\n'.join(report['metrics']))
    except Exception as e:
        report.update(status='FAIL',error=str(e));raise
    finally:
        (run/'qualification.json').write_text(json.dumps(report,indent=2)+'\n');print('Logs:',run)
if __name__=='__main__':main()
