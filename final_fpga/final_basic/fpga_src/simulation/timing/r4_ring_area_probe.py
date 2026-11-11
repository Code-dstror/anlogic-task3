"""Bounded one-thread tiny native ring 2x2 area attribution, no physical flow."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[2]
REPO=PROJECT.parents[1]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True,type=Path)
    a=ap.parse_args()
    if not re.fullmatch('[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    out=PROJECT/'tmp/r4_ring_area'/a.name
    out.mkdir(parents=True,exist_ok=False)
    rtl=PROJECT/'src_fpga/rtl'
    old=subprocess.check_output(['git','show','14df01dcce:refactor/dual_lane_s1/src_fpga/rtl/jpeg_frame_ring.v'],cwd=REPO).decode()
    full=(rtl/'jpeg_frame_ring.v').read_text()
    idle_begin=full.index('    // An IDLE read is private speculation')
    idle_end=full.index('    wire cold_commit=',idle_begin)
    old_read=old[old.index('    wire cold_query_read='):old.index('    wire cold_commit=')]
    retire_only=full[:idle_begin]+old_read+full[idle_end:]

    def restore_retire(s):
        begin=s.index('    // Decode the retained read owner')
        end=s.index('    assign o_retire_ready=',begin)
        s=s[:begin]+s[end:]
        s=s.replace('                R_HOLD: if(retire_fire && retire_complete)rs<=R_IDLE;\n','')
        s=s.replace('            if(retire_fire) begin','            if(i_retire_valid && o_retire_ready) begin')
        s=s.replace('if(!retire_slot_live) o_retire_rsp_code<=NO_FRAME;','if(i_retire_slot>=SLOT_COUNT || rs==R_IDLE) o_retire_rsp_code<=NO_FRAME;')
        s=s.replace('else if(!retire_identity_match) o_retire_rsp_code<=STALE;','else if(i_retire_slot!=reader || i_retire_session!=ready_session || i_retire_generation!=ready_generation) o_retire_rsp_code<=STALE;')
        s=s.replace('                    o_read_error<=0;read_bad<=0;\n                end\n            end\n            case(request_state)',
            '                    rs<=R_IDLE;o_read_error<=0;read_bad<=0;\n                end\n            end\n            case(request_state)')
        return s

    def semantic_text(s):return re.sub(r'\s+','',re.sub(r'//[^\n]*','',s))
    assert semantic_text(restore_retire(retire_only))==semantic_text(old),'Unexpected ring changes beyond two scoped edits'
    cases=[('r2',old),('retire_only',retire_only),('idle_read_only',restore_retire(full)),('r3',full)]
    header=re.sub(r'//[^\n]*','',old.split('    localparam',1)[0])
    ports=[]
    for m in re.finditer(r'\b(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(.*?)(?=\binput\b|\boutput\b|$)',header,re.S):
        direction,width,names=m.groups()
        bit_range=re.fullmatch(r'\[(\d+):(\d+)\]',width or '')
        bits=int(bit_range[1])-int(bit_range[2])+1 if bit_range else 1
        for name in re.findall(r'\b[io]_\w+',names):ports.append((direction,bits,name))
    input_bits=sum(bits for d,bits,n in ports if d=='input' and n not in ['i_clk','i_rst_n'])
    output_bits=sum(bits for d,bits,n in ports if d=='output')
    padded=(output_bits+31)//32*32
    wrapper=f'''module ring_probe(input i_clk,i_rst_n,load,input [31:0] stimulus_word,input [5:0] view,output [31:0] observe);
reg [{input_bits-1}:0] stimulus;
always @(posedge i_clk)if(load)stimulus<={{stimulus[{input_bits-33}:0],stimulus_word}};
'''
    offset=0
    for direction,bits,name in ports:
        if name in ['i_clk','i_rst_n']:continue
        wrapper+=f'wire [{bits-1}:0] {name}'
        if direction=='input':
            wrapper+=f'=stimulus[{offset}+:{bits}]'
            offset+=bits
        wrapper+=';\n'
    outputs=','.join(n for d,bits,n in ports if d=='output')
    if padded>output_bits:outputs=f"{padded-output_bits}'d0,"+outputs
    wrapper+=f'wire [{padded-1}:0] results={{{outputs}}};\nassign observe=results >> {{view,5\'d0}};\n'
    wrapper+='jpeg_frame_ring #(.CAMERA_COUNT(2),.MASK_ENABLE(0),.WRITE_RESULT_ENABLE(1),.WRITE_TAG_ENABLE(1)) u_leaf(\n'
    wrapper+=',\n'.join(f'.{n}({n})' for d,bits,n in ports)+'\n);\nendmodule\n'
    result={'scope':'TINY_NATIVE_RING_2X2_GATE_AREA_ONLY','threads':1,'td_root':str(a.td_root),
        'input_bits':input_bits,'output_bits':output_bits,'cases':[],
        'pnr':'NOT_RUN','timing':'NOT_RUN','board':'NOT_RUN'}
    begin_time=time.monotonic()
    try:
        for variant,source in cases:
            case=out/variant
            case.mkdir()
            (case/'jpeg_frame_ring.v').write_text(source,newline='\n')
            for name in ['jpeg_ring_cold_bank.v','td_sdp_ram.v']:(case/name).write_bytes((rtl/name).read_bytes())
            (case/'ring_probe.v').write_text(wrapper,newline='\n')
            (case/'clock.sdc').write_text('create_clock -name DFI -period 7.502 [get_ports i_clk]\n')
            (case/'build.tcl').write_text('''import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project ring_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module ring_probe
foreach source {td_sdp_ram.v jpeg_ring_cold_bank.v jpeg_frame_ring.v ring_probe.v clock.sdc} {add_files $source}
set_param -run syn_1 flow thread 1
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate mapper_lut_delay off
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate pack_effort medium
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate add_map_lut_struct on
close_project
open_project ring_probe.al
report_run_param syn_1 -file native.params
launch_runs -step opt_gate syn_1
wait_run syn_1 -quiet
open_run syn_1
report_area -io_info -file gate_reopened.area
close_project
open_project ring_probe.al -noanalyze
open_run syn_1
close_project
puts R4_RING_TINY_AREA_DONE
exit 0
''',newline='\n')
            command=[sys.executable,'-B',str(REPO/'tools/run_td.py'),str(case/'build.tcl'),
                '--td-root',str(a.td_root),'--workdir',str(case),'--log',str(case/'wrapper.log')]
            row={'variant':variant,'inputs':[{'path':str(p),'sha256':sha(p)} for p in sorted(case.glob('*')) if p.is_file()],
                'command':command}
            result['cases'].append(row)
            done=subprocess.run(command,cwd=REPO,capture_output=True,text=True,errors='replace',timeout=150)
            (case/'launcher.log').write_text(done.stdout+done.stderr)
            if done.returncode:raise RuntimeError(variant+': '+(done.stdout+done.stderr)[-5000:])
            parameters=(case/'native.params').read_text()
            assert re.search(r'set_param flow thread\s+1\b',parameters),parameters
            area=(case/'gate_reopened.area').read_text()
            stats={k:int(v) for k,v in re.findall(r'^#(slice\*|reg|lut)\s+(\d+)',area,re.M)}
            leaf=next(line for line in area.splitlines() if '|  u_leaf' in line and 'jpeg_frame_ring' in line)
            row.update(status='PASS',stats=stats,leaf=leaf)
            print(variant,stats,leaf,flush=True)
        result['status']='PASS'
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        result['elapsed_seconds']=round(time.monotonic()-begin_time,3)
        (out/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        print(out/'RESULTS.json',flush=True)


if __name__=='__main__':main()
