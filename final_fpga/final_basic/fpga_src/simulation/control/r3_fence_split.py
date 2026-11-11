"""R1 cycle miter for split fence data masks; original async/state code exact."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]
BASE='d86edbed408230828e6cd8a887bceec80c242307'
BASE_PATH='refactor/hdr_jpeg_timing/src_fpga/rtl/physical_identity_source_fence.v'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--modelsim-bin',type=Path,required=True)
    args=ap.parse_args()
    if not re.fullmatch(r'r3_[a-z0-9_]+',args.name):
        ap.error('independent name must start r3_')
    run=PROJECT/'tmp/r3_fence'/args.name;run.mkdir(parents=True,exist_ok=False)
    source=PROJECT/'src_fpga/rtl/physical_identity_source_fence.v'
    template=HERE/'r3_tb_fence_split.sv'
    baseline=subprocess.check_output(['git','show',BASE+':'+BASE_PATH],cwd=REPO)
    original=baseline.decode().replace('\r\n','\n');candidate=source.read_text()
    # No control event equation, state block or asynchronous reset process may
    # change. Only the header/new mask wire/four output assignments differ.
    assert candidate[candidate.index('    always @'):]==original[original.index('    always @'):]
    for name in ['event_fire','context_fire','raw_fire','native_fire','new_owned','terminal_event','terminal_bad']:
        pattern=r'\bwire\s+'+name+r'\s*=([^;]+);'
        assert re.search(pattern,candidate).group(1)==re.search(pattern,original).group(1),name
    header=re.sub(r'//[^\n]*','',original.split('    localparam',1)[0]);ports=[]
    for m in re.finditer(r'\b(input|output)\s+wire\s*(\[[^\]]+\])?\s*([^\n]*?)(?=\binput\b|\boutput\b|$)',header,re.M):
        direction,width,names=m.groups()
        ports += [(direction,width or '',name) for name in re.findall(r'\b[io]_\w+',names)]
    assert len(ports)==len(set(name for _,_,name in ports)) and len(ports)>40
    inputs=[(width,name) for direction,width,name in ports if direction=='input']
    outputs=[(width,name) for direction,width,name in ports if direction=='output']
    body=template.read_text()
    declarations=[f'    reg {width} {name};' for width,name in inputs if name not in ['i_clk','i_rst_n']]
    declarations += [f'    wire {width} {prefix}_{name};' for width,name in outputs for prefix in ['dut','reference']]
    body=body.replace('__DECLARATIONS__','\n'.join(declarations))
    body=body.replace('__INITIALIZE__','\n'.join(f'            {name}=0;' for _,name in inputs if name not in ['i_clk','i_rst_n']))
    for prefix in ['dut','reference']:
        connections=[f'        .{name}({name if direction=="input" else prefix+"_"+name})' for direction,_,name in ports]
        body=body.replace('__'+prefix.upper()+'_PORTS__',',\n'.join(connections))
        body=body.replace('__OUTPUTS_'+prefix.upper()+'__',','.join(prefix+'_'+name for _,name in outputs))
    bench=run/'r3_tb_fence_split.sv';bench.write_text(body,newline='\n')
    reference=run/'r3_fence_reference.v'
    reference.write_text(original.replace('module physical_identity_source_fence (','module r3_fence_reference (',1),newline='\n')
    top=PROJECT/'src_fpga/rtl/anlogic2026.v';top_text=re.sub(r'\s+','',top.read_text())
    production='physical_identity_source_fence#(.SEPARATE_DATA_RESET(1))u_fence('
    assert production in top_text
    assert '.i_rst_n(pixel_rst_n&&camera_mode_running&&!camera_hdr_mode)' in top_text
    assert '.i_data_reset_n(pixel_reset_local_n&&camera_mode_running&&!camera_hdr_mode)' in top_text
    identity=[{'path':str(p),'sha256':sha(p)} for p in [source,template,bench,reference,Path(__file__)]]
    result={'status':'IN_PROGRESS','baseline':{'commit':BASE,'path':BASE_PATH,'sha256':hashlib.sha256(baseline).hexdigest()},
        'inputs':identity,'unchanged_state_event_async_processes':'BYTE_EQUIVALENT_AFTER_HEADER',
        'readonly_production_wiring':{'asr':'pixel_rst_n&&camera_mode_running&&!camera_hdr_mode',
            'data_mask':'pixel_reset_local_n&&camera_mode_running&&!camera_hdr_mode','top_snapshot_sha256':sha(top)},
        'physical_delay_model':'NONE: strict logical masks equal in production case; all outputs compared after clock edges and explicit asynchronous assertion windows.',
        'new_state_bits':0,'latency_change_cycles':0,'synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        proc=subprocess.run([str(args.modelsim_bin/exe)]+list(map(str,words)),cwd=run,text=True,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(proc.stdout)
        if proc.returncode:
            raise RuntimeError(name+' failed '+proc.stdout[-10000:])

    try:
        command('map','vmap.exe',['-c']);command('lib','vlib.exe',['work'])
        command('rtl','vlog.exe',['-quiet','-l','rtl.log',source,reference])
        command('bench','vlog.exe',['-quiet','-sv','-l','bench.log',bench])
        command('run','vsim.exe',['-c','work.r3_tb_fence_split','-l','run.log','-do','run -all;quit -f'])
        log=(run/'run.log').read_text()
        if 'RESULT: PASS r3_fence_all' not in log:
            raise RuntimeError(log[-12000:])
        for filename in ['rtl.log','bench.log','run.log']:
            if re.search(r'\*\* (Warning|Error|Fatal):',(run/filename).read_text()):
                raise RuntimeError('unclassified diagnostic '+filename)
        for row in identity:
            assert sha(Path(row['path']))==row['sha256'],'executed source drift '+row['path']
        result.update(status='PASS',metrics=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line])
        print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'r3_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'r3_RESULTS.json')


if __name__=='__main__':
    main()
