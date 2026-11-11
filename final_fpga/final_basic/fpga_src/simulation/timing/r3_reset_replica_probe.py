"""Tiny native proof of foreign joint-reset selectors and local timing sentinels."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
REPO = PROJECT.parents[1]

RTL = r'''module bank(input source_clk,sink_clk,source_n,sink_n,data,
 output [2:0] source_q,sink_q,output [31:0] functional,output ordinary_d,ordinary_ce);
 wire fifo_async_reset_n=source_n&&sink_n;
 (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] source_reset_release_pipe,sink_reset_release_pipe;
 (* preserve="true" *) reg [31:0] payload;
 (* preserve="true" *) reg d,ce;
 always @(posedge source_clk or negedge fifo_async_reset_n)
 if(!fifo_async_reset_n)source_reset_release_pipe<=0;
 else source_reset_release_pipe<={source_reset_release_pipe[1:0],1'b1};
 always @(posedge sink_clk or negedge fifo_async_reset_n)
 if(!fifo_async_reset_n)sink_reset_release_pipe<=0;
 else sink_reset_release_pipe<={sink_reset_release_pipe[1:0],1'b1};
 always @(posedge source_clk or negedge source_reset_release_pipe[2])
 if(!source_reset_release_pipe[2])payload<=0;else payload<={payload[30:0],data};
 // Foreign ordinary data/CE deliberately remain timed even though the same
 // remote reset Q enters the dedicated joint-reset ASR above.
 always @(posedge source_clk or negedge source_n)
 if(!source_n)begin d<=0;ce<=0;end
 else begin d<=sink_n;if(sink_n)ce<=data;end
 assign source_q=source_reset_release_pipe;assign sink_q=sink_reset_release_pipe;
 assign functional=payload;assign ordinary_d=d;assign ordinary_ce=ce;
endmodule
module r3_reset_scope(input user_clk,dfi_clk,cold_n,data,
 output [2:0] user_status,dfi_status,cmd_source,cmd_sink,rsp_source,rsp_sink,
 output [31:0] cmd_payload,rsp_payload,output cmd_d,cmd_ce,rsp_d,rsp_ce);
 (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] user_release,dfi_release;
 always @(posedge user_clk or negedge cold_n)
 if(!cold_n)user_release<=0;else user_release<={user_release[1:0],1'b1};
 always @(posedge dfi_clk or negedge cold_n)
 if(!cold_n)dfi_release<=0;else dfi_release<={dfi_release[1:0],1'b1};
 bank u_command(.source_clk(user_clk),.sink_clk(dfi_clk),.source_n(user_release[2]),.sink_n(dfi_release[2]),.data(data),
 .source_q(cmd_source),.sink_q(cmd_sink),.functional(cmd_payload),.ordinary_d(cmd_d),.ordinary_ce(cmd_ce));
 bank u_response(.source_clk(dfi_clk),.sink_clk(user_clk),.source_n(dfi_release[2]),.sink_n(user_release[2]),.data(data),
 .source_q(rsp_source),.sink_q(rsp_sink),.functional(rsp_payload),.ordinary_d(rsp_d),.ordinary_ce(rsp_ce));
 assign user_status=user_release;assign dfi_status=dfi_release;
endmodule
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paths(path):
    lines = path.read_text().splitlines()
    result = []
    for i, line in enumerate(lines):
        if not line.startswith('Begin Point'):
            continue
        launch = re.search(r'triggered by clock (\S+)', line)
        capture = re.search(r'triggered by clock (\S+)', lines[i + 1])
        if not launch or not capture:
            continue
        result.append(dict(source=line, target=lines[i+1], kind=lines[i+2].split(':',1)[1].strip(),
                           launch=launch.group(1),capture=capture.group(1),slack=lines[i-1]))
    return {key:[r for r in result if ((r['kind'] in ('recovery','removal')) == reset)
                 and ((r['launch'] != r['capture']) == foreign)]
            for key,reset,foreign in [('foreign_asr',True,True),('local_asr',True,False),
                                      ('foreign_data',False,True),('local_data',False,False)]}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--td-root',type=Path,required=True)
    ap.add_argument('--name',required=True)
    ap.add_argument('--target-clocks',action='store_true')
    ap.add_argument('--reuse-gate',type=Path)
    args=ap.parse_args()
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,48}',args.name):ap.error('unsafe name')
    run=PROJECT/'tmp/reset_r3'/args.name
    run.mkdir(parents=True,exist_ok=False)
    (run/'probe.v').write_text(RTL,newline='\n')
    (run/'base.sdc').write_text('create_clock -name USER -period 8 [get_ports user_clk]\n'
                               'create_clock -name DFI -period 7.502 -waveform {0.229 3.980} [get_ports dfi_clk]\n',newline='\n')
    scope=[]
    for inst,side,remote in [('u_command','source','DFI'),('u_command','sink','USER'),
                              ('u_response','source','USER'),('u_response','sink','DFI')]:
        # Pair FIFOs have the same joint Boolean reset, hence synthesis may
        # choose either hierarchy's net as its physical name.
        target=' '.join(f'{inst}/{side}_reset_release_pipe[{b}]*' for b in range(3))
        capture='USER' if remote=='DFI' else 'DFI'
        endpoint=f'[get_clocks {{{capture}}}]' if args.target_clocks else f'[get_regs {{{target}}}]'
        scope.append(f'set_false_path -from [get_clocks {{{remote}}}] '
                     '-through [get_nets {u_command/fifo_async_reset_n* u_response/fifo_async_reset_n*}] '
                     f'-to {endpoint}')
    (run/'new.sdc').write_text('\n'.join(dict.fromkeys(scope))+'\n',newline='\n')
    root=run.as_posix()
    (run/'build.tcl').write_text(f'''cd {{{root}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project r3_reset_scope . -family ph1 -device PH1A90SEG324 -speed -2
top_module r3_reset_scope
add_files ./probe.v
add_files ./base.sdc
set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
exit 0
''',newline='\n')
    gate=args.reuse_gate.resolve().as_posix() if args.reuse_gate else f'{root}/r3_reset_scope_Runs/syn_1/r3_reset_scope_gate.db'
    report='report_timing_summary -report_type max_min -ep_num 200 -path_num 3'
    (run/'check.tcl').write_text(f'''cd {{{root}}}
import_device ph1_90.db -package PH1A90SEG324 -speed 2
import_db {{{gate}}}
update_timing
{report} -file baseline_gate.timing
read_sdc {{{root}/new.sdc}}
update_timing
{report} -file bound_gate.timing
puts "R3_GATE_JOINT=[get_nets {{u_command/fifo_async_reset_n* u_response/fifo_async_reset_n*}}]"
puts "R3_GATE_EXACT=[get_regs {{u_response/source_reset_release_pipe[*]}}]"
puts "R3_GATE_SUFFIX=[get_regs {{u_response/source_reset_release_pipe[0]* u_response/source_reset_release_pipe[1]* u_response/source_reset_release_pipe[2]*}}]"
place
update_timing -mode manhattan
{report} -file bound_place.timing
puts "R3_PLACE_JOINT=[get_nets {{u_command/fifo_async_reset_n* u_response/fifo_async_reset_n*}}]"
puts "R3_PLACE_EXACT=[get_regs {{u_response/source_reset_release_pipe[*]}}]"
puts "R3_PLACE_SUFFIX=[get_regs {{u_response/source_reset_release_pipe[0]* u_response/source_reset_release_pipe[1]* u_response/source_reset_release_pipe[2]*}}]"
check_timing -file bound_place_check.timing
export_db bound_place.db
puts R3_RESET_SCOPE_DONE
exit 0
''',newline='\n')
    result={'status':'IN_PROGRESS','scope':'TINY_NATIVE_MAPPING_ONLY_NOT_PRODUCTION',
            'td_root':str(args.td_root),'run':str(run),'commands':[],
            'inputs':[{'path':str(p),'sha256':sha(p)} for p in [Path(__file__),*sorted(run.glob('*'))] if p.is_file()]}
    try:
        for stage in (('check',) if args.reuse_gate else ('build','check')):
            cmd=[sys.executable,str(REPO/'tools/run_td.py'),str(run/f'{stage}.tcl'),'--td-root',str(args.td_root),
                 '--workdir',str(run),'--log',str(run/f'{stage}.log')]
            result['commands'].append(cmd)
            proc=subprocess.run(cmd,cwd=REPO,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
            (run/f'{stage}.console.log').write_text(proc.stdout)
            if proc.returncode:raise RuntimeError(proc.stdout[-5000:])
        reports={p.stem:paths(p) for p in run.glob('*.timing') if '_check' not in p.stem}
        assert reports['baseline_gate']['foreign_asr'],'baseline did not exercise foreign ASR'
        for stage in ('gate','place'):
            p=reports[f'bound_{stage}']
            assert not p['foreign_asr'],f'foreign ASR remained at {stage}'
            for keep in ('local_asr','local_data','foreign_data'):
                assert p[keep],f'{keep} disappeared at {stage}'
        check=(run/'bound_place_check.timing').read_text()
        assert 'There are 0 invalid constraints.' in check
        assert 'There are 0 constraints that have no timing paths.' in check
        result.update(status='PASS',reports=reports)
        print('R3_RESET_SCOPE_PASS',{s:{k:len(v) for k,v in reports[s].items()} for s in reports})
    except Exception as error:
        result.update(status='FAIL',error=str(error));raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':main()
