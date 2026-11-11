"""Miter the actual complete sink always block vs R1; no FIFO model needed."""
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
BASE_PATH='refactor/hdr_jpeg_timing/src_fpga/rtl/axis_frame_fifo_ip.v'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean(text):
    return re.sub(r'\s+','',re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S))


def sink_block(text):
    found=[]
    for match in re.finditer(r'always\s*@\(posedge i_sink_clk\)\s*begin',text):
        depth=1
        for token in re.finditer(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\bbegin\b|\bend\b',text[match.end():],re.S):
            if token[0]=='begin':depth+=1
            elif token[0]=='end':depth-=1
            if depth==0:
                body=text[match.start():match.end()+token.end()]
                if 'read_count' in body and 'read_buffer' in body:found.append(body)
                break
    if len(found)!=1:raise RuntimeError('one full actual sink count/payload process required')
    return found[0]


def wrapper(name,body):
    return '''`timescale 1ns/1ps
module '''+name+'''(
    input wire i_sink_clk,input wire [2:0] sink_reset_release_pipe,
    input wire fifo_read_reset,fifo_read_reset_done,fifo_valid,fifo_empty,
    input wire [146:0] fifo_read_data,input wire i_sink_ready,
    input wire inject_ops,injected_push,injected_pop,
    output wire [146:0] o_sink_data,output wire o_sink_valid,o_sink_reset_done
);
    reg sink_run=1'b0;
    reg [146:0] read_buffer[0:1];
    reg read_head,read_tail;
    reg [1:0] read_count;
    wire fifo_read_enable=inject_ops?injected_push:
        (sink_run&&fifo_valid&&!fifo_empty&&read_count<2);
    wire sink_fire=inject_ops?injected_pop:(o_sink_valid&&i_sink_ready);
    assign o_sink_reset_done=sink_reset_release_pipe[2]&&sink_run;
    assign o_sink_valid=o_sink_reset_done&&read_count!=0;
    assign o_sink_data=read_buffer[read_head];
'''+body+'\nendmodule\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name',required=True)
    parser.add_argument('--modelsim-bin',type=Path,required=True)
    args=parser.parse_args()
    if not re.fullmatch(r'r3_axis_[a-z0-9_]+',args.name):parser.error('independent name must start r3_axis_')
    run=PROJECT/'tmp/r3_axis'/args.name;run.mkdir(parents=True,exist_ok=False)
    source=PROJECT/'src_fpga/rtl/axis_frame_fifo_ip.v';bench=HERE/'r3_axis_tb_count.sv'
    raw=subprocess.check_output(['git','show',BASE+':'+BASE_PATH],cwd=REPO)
    original=raw.decode().replace('\r\n','\n');current=source.read_text()
    original_case=re.search(r'case\s*\(\s*\{fifo_read_enable,sink_fire\}\s*\).*?endcase',original,re.S)
    boolean=re.search(r'read_count\[0\]\s*<=.*?;\s*read_count\[1\]\s*<=.*?;',current,re.S)
    assert original_case and boolean
    assert clean(original[:original_case.start()]+original[original_case.end():])==clean(current[:boolean.start()]+current[boolean.end():]),'source changed outside count arithmetic'
    actual=run/'r3_axis_actual.sv';reference=run/'r3_axis_reference.sv'
    actual.write_text(wrapper('r3_axis_actual',sink_block(current)),newline='\n')
    reference.write_text(wrapper('r3_axis_reference',sink_block(original)),newline='\n')
    inputs=[source,bench,Path(__file__),actual,reference]
    identity=[{'path':str(path),'sha256':sha(path)} for path in inputs]
    result={'status':'IN_PROGRESS','inputs':identity,'baseline':{'commit':BASE,'path':BASE_PATH,'sha256':hashlib.sha256(raw).hexdigest()},
        'static_scope':'whole module token-equivalent except exactly the two-bit occupancy arithmetic',
        'scope':'Actual complete sink always block: run update, reset/run priority, pointers and both147-bit buffers. Other domains/official FIFO are unchanged and not re-simulated.',
        'new_state_bits':0,'latency_change_cycles':0,'synthesis':'NOT_RUN','physical_timing':'NOT_RUN','board':'NOT_RUN'}

    def command(name,exe,words):
        proc=subprocess.run([str(args.modelsim_bin/exe)]+list(map(str,words)),cwd=run,text=True,
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,errors='replace')
        (run/(name+'.console.log')).write_text(proc.stdout)
        if proc.returncode:raise RuntimeError(name+' failed '+proc.stdout[-10000:])

    try:
        command('map','vmap.exe',['-c']);command('lib','vlib.exe',['work'])
        command('compile','vlog.exe',['-quiet','-sv','-l','compile.log',actual,reference,bench])
        command('run','vsim.exe',['-c','work.r3_axis_tb_count','-l','run.log','-do','run -all;quit -f'])
        log=(run/'run.log').read_text()
        if 'RESULT: PASS r3_axis_count' not in log:raise RuntimeError(log[-10000:])
        for name in ['compile.log','run.log']:
            if re.search(r'\*\* (Warning|Error|Fatal):',(run/name).read_text()):raise RuntimeError('diagnostic '+name)
        for row in identity:
            if sha(Path(row['path']))!=row['sha256']:raise RuntimeError('source drift '+row['path'])
        result.update(status='PASS',metrics=[line.strip('# ') for line in log.splitlines() if 'RESULT: PASS' in line]);print('\n'.join(result['metrics']))
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'r3_axis_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Results:',run/'r3_axis_RESULTS.json')


if __name__=='__main__':
    main()
