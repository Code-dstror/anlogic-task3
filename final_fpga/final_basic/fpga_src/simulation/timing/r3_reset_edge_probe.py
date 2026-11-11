"""Map the actual transport FSM reset process with USER rise0/fall2/period8."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
REPO=ROOT.parents[1]


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--reuse-gate',type=Path)
    ap.add_argument('--route',action='store_true',help='optional tiny routed min check')
    ap.add_argument('--verify-existing',type=Path,help='validate an existing exact-probe placed report without launching TD')
    a=ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',a.name):ap.error('unsafe name')
    run=ROOT/'tmp/reset_r3'/a.name;run.mkdir(parents=True,exist_ok=False)
    source=ROOT/'src_fpga/rtl/c2h_native_rx_transport.v';body=source.read_text()
    start=body.index('    (* preserve="true" *) reg state_reset_n')
    end=body.index('\n    end\n',body.index('else state <= next_state;',start))+len('\n    end\n')
    snippet=body[start:end]
    assert 'always @(negedge i_clk or negedge i_rst_n)' in snippet
    assert 'always @(posedge i_clk or negedge state_reset_n)' in snippet
    text='module reset_edge(input i_clk,cold_n,input [3:0] next_state,output [3:0] q,output release_q);\n'
    text+='(* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] ownership_reset_sync;\n'
    text+="always @(posedge i_clk or negedge cold_n)if(!cold_n)ownership_reset_sync<=0;else ownership_reset_sync<={ownership_reset_sync[0],1'b1};\n"
    text+='wire i_rst_n=ownership_reset_sync[1];\n'
    text+='localparam [3:0] S_IDLE=0;(* preserve="true" *) reg [3:0] state;\n'+snippet
    text+='assign q=state;assign release_q=state_reset_n;endmodule\n'
    (run/'probe.v').write_text(text)
    (run/'base.sdc').write_text('create_clock -name USER -period 8 -waveform {0 2} [get_ports i_clk]\n')
    root=run.as_posix()
    script=f'''cd {{{root}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
'''
    if not a.reuse_gate:
        script+=f'''
create_project reset_edge . -family ph1 -device PH1A90SEG324 -speed -2
top_module reset_edge
add_files ./probe.v
add_files ./base.sdc
set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
'''
    gate=a.reuse_gate.resolve() if a.reuse_gate else run/'reset_edge_Runs/syn_1/reset_edge_gate.db'
    if a.reuse_gate:
        assert (gate.parents[2]/'probe.v').read_bytes()==(run/'probe.v').read_bytes(),'gate probe source changed'
        assert (gate.parents[2]/'base.sdc').read_bytes()==(run/'base.sdc').read_bytes(),'gate clocks changed'
    script+=f'''
import_db {{{gate.as_posix()}}}
update_timing
report_timing_summary -report_type max_min -ep_num 100 -path_num 3 -file {{{root}/edge_gate.timing}}
check_timing -file {{{root}/edge_check.timing}}
place
update_timing -mode manhattan
report_timing_summary -report_type max_min -ep_num 100 -path_num 3 -file {{{root}/edge_place.timing}}
'''
    if a.route:script+=f'''
route
update_timing -mode final
report_timing_summary -report_type max_min -ep_num 100 -path_num 3 -file {{{root}/edge_route.timing}}
'''
    script+='''
puts "R3_EDGE_RELEASE=[get_regs {{state_reset_n*}}] STATE=[get_regs {{state[*]*}}]"
puts R3_EDGE_MAPPING_DONE
exit 0
'''
    (run/'build.tcl').write_text(script)
    cmd=[sys.executable,str(REPO/'tools/run_td.py'),str(run/'build.tcl'),'--td-root',str(a.td_root),
         '--workdir',str(run),'--log',str(run/'build.log')]
    result={'status':'IN_PROGRESS','source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'exact_extracted_process':snippet,'USER':'rise0/fall2/period8','command':None if a.verify_existing else cmd,
            'scope':'TINY_NATIVE_MAPPING_NOT_PRODUCTION_STA','production_timing':'NOT_RUN',
            'tiny_route':'NOT_RUN' if not a.route else 'IN_PROGRESS'}
    try:
        if a.verify_existing:
            report_path=a.verify_existing.resolve()
            assert (report_path.parent/'probe.v').read_bytes()==(run/'probe.v').read_bytes(),'existing report probe changed'
            assert (report_path.parent/'base.sdc').read_bytes()==(run/'base.sdc').read_bytes(),'existing report clocks changed'
        else:
            r=subprocess.run(cmd,cwd=REPO,capture_output=True,text=True,timeout=120)
            (run/'build.console.log').write_text(r.stdout+r.stderr)
            if r.returncode:raise RuntimeError((r.stdout+r.stderr)[-4000:])
            report_path=run/('edge_route.timing' if a.route else 'edge_place.timing')
        report=report_path.read_text()
        paths=[]
        for m in re.finditer(r'Slack\s+:.*?\nBegin Point\s+:.*?\nEnd Point\s+:.*?\nCheck Type\s+:.*?\nProcess\s+:.*?\nBudget\s+:.*?\n',report):
            block=m.group(0)
            if 'state_reset_n' in block or 'release_q' in block:paths.append(block)
        assert any('falling edge triggered by clock USER' in p and 'Check Type          : recovery' in p and 'Budget              : 6.000ns' in p for p in paths),paths
        assert any('rising edge triggered by clock USER' in p and 'Check Type          : recovery' in p and 'Budget              : 2.000ns' in p for p in paths),paths
        if a.route:
            assert any('falling edge triggered by clock USER' in p and 'Check Type          : removal' in p and 'Budget              : 2.000ns' in p for p in paths),paths
        check=(report_path.parent/'edge_check.timing').read_text();assert 'There are 0 invalid constraints.' in check
        result.update(status='PASS',paths=paths,report=str(report_path),report_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest())
        print('R3_USER_EDGE_MAPPING_PASS ownership_to_falling_recovery=2ns falling_to_state_recovery=6ns')
    except Exception as e:result.update(status='FAIL',error=str(e));raise
    finally:(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
