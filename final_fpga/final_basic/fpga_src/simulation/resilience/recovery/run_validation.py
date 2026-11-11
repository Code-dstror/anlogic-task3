"""Candidate-only bounded recovery validation; no Git, server or board calls."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent
MATRIX_RTL=['real_hdr_physical_csi_rx.v','reset_release_sync.v','csi_rx_word_align_observed.v','physical_csi_rx_stream.v','physical_csi_word_core.v','csi2_async_event_fifo.v','real_hdr_csi_capture_stream.v','real_hdr_csi_dual_word_rx.v','real_hdr_csi_word_core.v','real_hdr_member_crop10.v','raw_capture_fifo_eram_safe.v','production_source_identity_guard.v','physical_identity_source_fence.v']
MATRIX_IP=['vendor/anlogic_camera/phy/csi_rx_word_gear_box.v','camera_event_fifo_47x512/RTL/camera_event_fifo_47x512_soft_fifo_core.v', 'camera_event_fifo_47x512/RTL/camera_event_fifo_47x512_soft_fifo.v','camera_event_fifo_47x512/camera_event_fifo_47x512.v','camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo_core.v', 'camera_packet_fifo_147x512/RTL/camera_packet_fifo_147x512_soft_fifo.v','camera_packet_fifo_147x512/camera_packet_fifo_147x512.v']
PHYSICAL_RTL=['reset_release_sync.v','csi2_async_event_fifo.v','raw10_frame_ingress.v','physical_csi_word_core.v','physical_csi_rx_stream.v','physical_camera_crop.v','physical_capture_router.v','physical_identity_source_fence.v','production_source_identity_guard.v']
PHYSICAL_IP=['camera_event_fifo_47x8192/camera_event_fifo_47x8192.v','camera_event_fifo_47x8192/RTL/camera_event_fifo_47x8192_soft_fifo.v','camera_event_fifo_47x8192/RTL/camera_event_fifo_47x8192_soft_fifo_core.v']
MODELS=['common/al_phy_glbl.v','ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v','ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-root',type=Path,required=True)
    ap.add_argument('--output-root',type=Path,required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--suite',choices=['matrix','physical','word'],required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--strict',action='store_true')
    ap.add_argument('--rng',default='3a53c19b')
    args=ap.parse_args()
    if not re.fullmatch('[a-z0-9_]+',args.name): ap.error('name must use lowercase ASCII letters, digits and underscore')
    run=args.output_root.resolve()/args.name
    run.mkdir(parents=True,exist_ok=False)
    result=dict(status='IN_PROGRESS',simulation='IN_PROGRESS',source_root=str(args.source_root.resolve()),suite=args.suite,strict=args.strict,inputs=[],commands=[],synthesis='NOT_RUN',place_route='NOT_RUN',timing='NOT_RUN',bitgen='NOT_RUN',board='NOT_RUN')
    start=time.monotonic()
    def copy(src,rel):
        dest=run/'inputs'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(src.read_bytes())
        result['inputs'].append(dict(original=str(src.resolve()),path=str(dest),sha256=sha(dest)));return dest
    def command(name,exe,words,timeout=60):
        argv=[str(args.modelsim_bin/exe),*map(str,words)];result['commands'].append(argv)
        proc=subprocess.run(argv,cwd=run,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace',timeout=timeout)
        (run/(name+'.console.log')).write_text(proc.stdout,encoding='utf-8')
        if proc.returncode: raise RuntimeError(name+' exit='+str(proc.returncode)+': '+proc.stdout[-5000:])
    try:
        if args.suite=='matrix': rtls,ips,top=MATRIX_RTL,MATRIX_IP,'recovery_receiver_tb'
        elif args.suite=='physical':rtls,ips,top=PHYSICAL_RTL,PHYSICAL_IP,'tb_physical_recovery'
        else:rtls,ips,top=['physical_csi_word_core.v'],[],'tb_word_recovery'
        sources=[]
        for group,names in [('rtl',rtls),('ip',ips)]:
            sources += [copy(args.source_root/'src_fpga'/group/n,Path(group)/n) for n in names]
        bench=copy(HERE/(top+'.sv'),Path('testbench')/(top+'.sv'))
        copy(Path(__file__),Path('testbench')/Path(__file__).name)
        models=[]
        if args.suite!='word':
            models=[copy(args.td_root/'sim_release'/n,Path('models')/n) for n in MODELS]
            sources.insert(0,copy(args.td_root/'sim_release/ph1/ph1_phy_gsr.v',Path('models/ph1/ph1_phy_gsr.v')))
        command('version','vsim.exe',['-version']);command('vmap','vmap.exe',['-c']);command('work','vlib.exe',['work'])
        if models:
            command('ph1','vlib.exe',['ph1']);command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log',*models])
        rtl_flags=['+define+PH1'] if models else []
        if args.suite=='physical':
            include=args.source_root/'src_fpga/ip/camera_event_fifo_47x8192/RTL/include'
            for f in include.glob('*'):
                if f.is_file(): copy(f,Path('ip/camera_event_fifo_47x8192/RTL/include')/f.name)
            rtl_flags += ['+define+R8_STAGE1','+incdir+'+str(run/'inputs/ip/camera_event_fifo_47x8192/RTL/include')]
        command('rtl','vlog.exe',['-quiet',*rtl_flags,'-l','rtl.log',*sources])
        defs=[]
        if args.suite=='word' and not args.strict:defs=['+define+RECOVERY_CORE']
        if args.suite=='physical':defs=['+define+RECOVERY_GUARD']
        command('bench','vlog.exe',['-quiet','-sv',*defs,'-l','bench.log',bench])
        sim=['-c','-voptargs=+acc']
        if models:sim+=['-L','ph1','work.PH1_PHY_GSR','ph1.glbl']
        sim += ['work.'+top]
        if args.suite in ('word','physical'):sim+=['-gEXPECT_RECOVERY='+str(int(not args.strict))]
        if args.suite=='matrix':sim += ["-gRNG_INITIAL=32'h"+args.rng]
        command('run','vsim.exe',[*sim,'-l','run.log','-do','run -all; quit -f'],150)
        logs=['run.log']
        if args.suite=='word':
            command('saturation','vsim.exe',[*sim,"-gINITIAL_SEQUENCE=32'hfffffffe",'-l','saturation.log','-do','run -all; quit -f'],60);logs+=['saturation.log']
        for log in logs:
            body=(run/log).read_text(errors='replace')
            if 'RESULT: PASS' not in body:raise RuntimeError('missing PASS '+log+': '+body[-5000:])
        warnings=[]
        for log in run.glob('*.log'):
            if log.name.endswith('.console.log'):continue
            for number,line in enumerate(log.read_text(errors='replace').splitlines(),1):
                if re.search(r'\*\* (Error|Fatal):',line):raise RuntimeError(log.name+': '+line)
                if '** Warning:' in line:
                    if 'ph1_logic_eram.v(1287)' not in line or 'INIT_FILE' not in line:raise RuntimeError('unclassified '+log.name+': '+line)
                    warnings.append(dict(log=log.name,line=number,message=line))
        for row in result['inputs']:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('compiled input drift '+row['path'])
            if sha(Path(row['original']))!=row['sha256']:raise RuntimeError('original input drift '+row['original'])
        result.update(status='PASS',simulation='PASS',accepted_vendor_warnings=warnings,metrics=[line.strip('# ') for log in logs for line in (run/log).read_text(errors='replace').splitlines() if any(token in line for token in ['CASE ','SNAPSHOT ','RESULT:','EVIDENCE','PENDING '])])
    except Exception as e:
        result.update(status='FAIL',simulation='FAIL',error=str(e));raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-start,3)
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(dict(run=str(run),status=result['status'],error=result.get('error'))))

if __name__=='__main__':main()
