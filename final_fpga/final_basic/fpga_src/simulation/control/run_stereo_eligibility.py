"""Qualify cold-stereo eligibility only on real USER APPLIED publication."""
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


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    args=ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',args.name):
        ap.error('unsafe run name')
    run=PROJECT/'tmp/stereo_eligibility'/args.name
    run.mkdir(parents=True,exist_ok=False)
    rtl,ip=PROJECT/'src_fpga/rtl',PROJECT/'src_fpga/ip'
    manifest=json.loads((PROJECT/'SOURCE_MANIFEST.json').read_text())
    includes=[PROJECT/p for p in manifest['include_dirs']]
    headers=[path for directory in includes for path in directory.glob('*.vh')]
    baselines=[]
    references=[]
    models=[args.td_root/'sim_release'/name for name in ['common/al_phy_glbl.v',
        'ph1/ph1_logic_eram.v','ph1/ph1_logic_fifo.v','ph1/ph1_logic_ramfifo.v',
        'ph1/ph1_phy_eram.v','ph1/ph1_phy_fifoctrl.v']]
    sources=[args.td_root/'sim_release/ph1/ph1_phy_gsr.v']+[ip/name for name in [
        'ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo_core.v',
        'camera_control_fifo_40x512/RTL/camera_control_fifo_40x512_soft_fifo.v',
        'camera_control_fifo_40x512/camera_control_fifo_40x512.v']]
    sources += [rtl/name for name in ['td_sdp_ram40.v','reset_release_sync.v','control_fifo_40x512.v','control_message_fifo_ip.v',
        'mono_config_byte_store_v2.v','mono_config_legacy_scan_v1.v','mono_config_scan_v2.v',
        'mono_config_bar_v2.v','mono_config_engine_v2.v','mono_config_service_v2.v']]+references
    benches=[HERE/'tb_stereo_config_eligibility.sv']
    inputs=models+sources+benches+[Path(__file__)]+headers
    identity=[{'path':str(path),'sha256':sha(path)} for path in inputs]
    result={'status':'IN_PROGRESS','baseline_negative_controls':baselines,'inputs':identity,
        'tool':'ModelSim SE-64 2020.4','modelsim_bin':str(args.modelsim_bin),'td_root':str(args.td_root),
        'defines':['PH1','C15_F23_FULLHEIGHT_PROFILE=0'],'synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        proc=subprocess.run([str(args.modelsim_bin/exe)]+list(map(str,words)),cwd=run,
            text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(proc.stdout)
        if proc.returncode:
            raise RuntimeError(name+' failed '+proc.stdout[-12000:])

    try:
        command('vmap','vmap.exe',['-c'])
        command('work','vlib.exe',['work'])
        command('ph1','vlib.exe',['ph1'])
        command('models','vlog.exe',['-quiet','-work','ph1','-l','models.log']+models)
        definitions=['+define+PH1','+define+C15_F23_FULLHEIGHT_PROFILE=0']
        inc=['+incdir+'+str(path) for path in includes]
        command('rtl','vlog.exe',['-quiet','-l','rtl.log']+definitions+inc+sources)
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log']+definitions+inc+benches)
        metrics=[]
        for top in ['tb_stereo_config_eligibility']:
            name=top.removeprefix('tb_')
            command(name,'vsim.exe',['-c','-L','ph1','work.PH1_PHY_GSR','ph1.glbl','work.'+top,
                '-l',name+'.log','-do','run -all; quit -f'])
            log=(run/(name+'.log')).read_text(errors='replace')
            matches=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS STEREO_CONFIG_ELIGIBILITY' in line]
            if len(matches)!=1:
                raise RuntimeError('missing PASS '+name+': '+log[-12000:])
            metrics+=matches
        warnings=[]
        for path in run.glob('*.log'):
            if path.name.endswith('.console.log'):
                continue
            lines=path.read_text(errors='replace').splitlines()
            for index,line in enumerate(lines):
                if re.search(r'\*\* (Error|Fatal):',line):
                    raise RuntimeError(path.name+': '+line)
                if '** Warning:' not in line:
                    continue
                ecc_compile=re.search(r'ram40_sdp_fixed.v\(69\).*ecc_[sd]biterrinj',line)
                ecc_runtime=(re.search(r"\(vsim-3015\).*port 'ecc_[sd]biterrinj'.*ph1_logic_eram.v\(52\)",line)
                    and index+1<len(lines) and '/src_fpga/ip/ram40_sdp_fixed/ram40_sdp_fixed/ram40_sdp_fixed.v Line: 69'
                    in lines[index+1].replace('\\','/'))
                init_bound=re.search(r'ph1_logic_eram.v\(1287\).*INIT_FILE.*out of bounds',line)
                if not (ecc_compile or ecc_runtime or init_bound):
                    raise RuntimeError('unclassified warning '+path.name+': '+line)
                warnings.append({'log':path.name,'line':index+1,'message':line})
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:
                raise RuntimeError('source drift '+row['path'])
        result.update(status='PASS',metrics=metrics,accepted_vendor_warnings=warnings)
        print('\n'.join(metrics))
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'RESULTS.json')


if __name__=='__main__':
    main()
