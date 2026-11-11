"""Check both official CSI FIFO profiles and all occupancy truth cases vs a4."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
BASE='a4ce0e9ddfa46379386c67791962ce9d8ce814d7'
BASE_PATH='refactor/hdr_jpeg_timing/src_fpga/rtl/csi2_async_event_fifo.v'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--depth',type=int,choices=[512,8192],required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    parser.add_argument('--td-root',type=Path,required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',args.name):
        parser.error('unsafe run name')
    run=PROJECT/'tmp/event_fifo'/args.name
    run.mkdir(parents=True,exist_ok=False)
    source=PROJECT/'src_fpga/rtl/csi2_async_event_fifo.v'
    bench=HERE/'tb_timing_event_fifo.sv'
    baseline=subprocess.check_output(['git','show',f'{BASE}:{BASE_PATH}'],cwd=REPO)
    reference=run/'timing_event_fifo_reference.v'
    # Keep the frozen caller behavior while both sides instantiate the selected native IP.
    bound_reference=baseline.replace(b'csi_event_fifo_47x', b'camera_event_fifo_47x')
    reference.write_bytes(bound_reference.replace(b'module csi2_async_event_fifo (',b'module timing_event_fifo_reference (',1))
    ip=PROJECT/'src_fpga/ip'/f'camera_event_fifo_47x{args.depth}'
    if args.depth==8192:
        ip_sources=[ip/'RTL/camera_event_fifo_47x8192_soft_fifo_core.v',ip/'RTL/camera_event_fifo_47x8192_soft_fifo.v',ip/'camera_event_fifo_47x8192.v']
    else:
        ip_sources=[ip/'RTL/camera_event_fifo_47x512_soft_fifo_core.v', ip/'RTL/camera_event_fifo_47x512_soft_fifo.v',ip/'camera_event_fifo_47x512.v']
    models=[args.td_root/'sim_release'/p for p in ['common/al_phy_glbl.v',
        'ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v',
        'ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
    sources=[args.td_root/'sim_release/ph1/ph1_phy_gsr.v']+ip_sources+[source,reference]
    inputs=models+sources+[bench,Path(__file__)]
    identity=[{'path':str(p),'sha256':sha(p)} for p in inputs]
    result={'status':'IN_PROGRESS','baseline':{'commit':BASE,'path':BASE_PATH,'sha256':hashlib.sha256(baseline).hexdigest()},
        'inputs':identity,'depth':args.depth,'modelsim_bin':str(args.modelsim_bin),'td_root':str(args.td_root),
        'latency_change_cycles':0,'new_state_bits':0,'synthesis':'NOT_RUN','place_route':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        argv=[str(args.modelsim_bin/exe)]+list(map(str,words))
        completed=subprocess.run(argv,cwd=run,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(completed.stdout)
        if completed.returncode:
            raise RuntimeError(exe+' failed '+completed.stdout[-10000:])

    try:
        command('vmap','vmap.exe',['-c'])
        command('work','vlib.exe',['work'])
        command('ph1','vlib.exe',['ph1'])
        command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        definitions=['+define+PH1']+(['+define+R8_STAGE1'] if args.depth==8192 else [])
        command('rtl','vlog.exe',['-quiet','-l','rtl.log']+definitions+sources)
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log']+definitions+[bench])
        command('run','vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.tb_timing_event_fifo',
            '-l','run.log','-do','run -all; quit -f'])
        log=(run/'run.log').read_text(errors='replace')
        metrics=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS timing_event_fifo' in line]
        if len(metrics)!=1:
            raise RuntimeError('missing PASS '+log[-10000:])
        warnings=[]
        for path in run.glob('*.log'):
            if path.name.endswith('.console.log'):
                continue
            for index,line in enumerate(path.read_text(errors='replace').splitlines()):
                if re.search(r'\*\* (Error|Fatal):',line):
                    raise RuntimeError(path.name+': '+line)
                if '** Warning:' in line:
                    if not re.search(r'ph1_logic_eram.v\(1287\).*INIT_FILE.*out of bounds',line):
                        raise RuntimeError('unclassified warning '+line)
                    warnings.append({'log':path.name,'line':index+1,'message':line})
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:
                raise RuntimeError('input drift '+row['path'])
        result.update(status='PASS',metrics=metrics,accepted_vendor_warnings=warnings)
        print(metrics[0])
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'RESULTS.json')


if __name__=='__main__':
    main()
