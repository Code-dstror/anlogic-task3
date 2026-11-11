"""Actual candidate aligners with focused HDR packet-boundary/controls checks."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[3]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output-root',type=Path,required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    args=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',args.name):ap.error('new lowercase name required')
    run=args.output_root.resolve()/args.name;run.mkdir(parents=True,exist_ok=False)
    result=dict(simulation='IN_PROGRESS',inputs=[],commands=[],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',board='NOT_RUN')
    try:
        names=['rtl/csi_rx_byte_align_observed.v','rtl/csi_rx_word_align_observed.v',
               'ip/vendor/anlogic_camera/phy/csi_rx_word_gear_box.v',
               'rtl/real_hdr_csi_word_core.v','rtl/real_hdr_csi_dual_word_rx.v']
        sources=[]
        for name in names:
            original=PROJECT/'src_fpga'/name;dest=run/'inputs'/name
            dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(original.read_bytes());sources.append(dest)
            result['inputs'].append(dict(original=str(original),path=str(dest),sha256=sha(dest)))
        for name in ['tb_hdr_shared_alignment.sv','tb_alignment_control.sv']:
            original=HERE/name;dest=run/name;dest.write_bytes(original.read_bytes());sources.append(dest)
            result['inputs'].append(dict(original=str(original),path=str(dest),sha256=sha(dest)))
        def call(label,exe,params):
            argv=[str(args.modelsim_bin/exe),*map(str,params)]
            p=subprocess.run(argv,cwd=run,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
            result['commands'].append(dict(argv=argv,cwd=str(run),exit_code=p.returncode))
            (run/(label+'.console.log')).write_text(p.stdout,encoding='utf-8')
            if p.returncode:raise RuntimeError(label+': '+p.stdout[-6000:])
        call('version','vsim.exe',['-version']);call('vmap','vmap.exe',['-c']);call('vlib','vlib.exe',['work'])
        call('compile','vlog.exe',['-quiet','-sv','-l','compile.log',*sources])
        (run/'run.do').write_text('onerror {quit -code 1}\nonbreak {quit -code 1}\nrun -all\nquit -code 0 -f\n')
        result['suites']=[]
        for top,log in [('tb_hdr_shared_alignment','hdr.log'),('tb_alignment_control','control.log')]:
            call(top,'vsim.exe',['-c','work.'+top,'-l',log,'-do','run.do'])
            body=(run/log).read_text(errors='replace')
            if 'RESULT: PASS' not in body or '** Fatal:' in body or '** Error:' in body:raise RuntimeError(body[-6000:])
            result['suites'].append(dict(top=top,simulation='PASS',observations=[s.strip('# ') for s in body.splitlines() if 'PASS' in s or 'TWO_FS' in s]))
        warnings=[s for p in [run/'compile.log',run/'hdr.log',run/'control.log'] for s in p.read_text(errors='replace').splitlines() if '** Warning:' in s]
        if warnings:raise RuntimeError('unexpected warnings '+str(warnings))
        for item in result['inputs']:
            if sha(Path(item['original']))!=item['sha256'] or sha(Path(item['path']))!=item['sha256']:raise RuntimeError('input changed during simulation')
        result.update(simulation='PASS',warnings=0,input_hashes_stable=True)
    except Exception as e:result.update(simulation='FAIL',error=str(e));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps({k:result.get(k) for k in ['simulation','error']}))

if __name__=='__main__':main()
