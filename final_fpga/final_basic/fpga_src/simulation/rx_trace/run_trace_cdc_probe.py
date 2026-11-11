"""Short mapped RT mailbox/reset scope probe; never place, route or bitgen."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[3]
REPO = PROJECT.parents[1]
PREFIX = 'g_production$g_status_uart$'

RTL = r'''module trace_probe_observer(input sys_clk,rst_n,request_in,
 input [5:0] index_in,output reg o_trace_request,output reg [5:0] o_trace_index);
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin o_trace_request<=0;o_trace_index<=0;end
  else begin o_trace_request<=request_in;o_trace_index<=index_in;end
 end
endmodule
module rx_trace_cdc_probe(input sys_clk,word_clk,rst_n,cohort_n,
 input enable,trigger,request_in,input [5:0] index_in,input [31:0] sample_in,
 output ack,output [31:0] digest);
 (* preserve="true" *) reg cold_reset_n;
 (* preserve="true" *) reg [255:0] sample_word;
 always @(posedge sys_clk)cold_reset_n<=rst_n;
 wire [319:0] trace_data;
 always @(posedge word_clk)sample_word<={sample_word[223:0],sample_in};
 genvar bit_index;
 generate for(bit_index=0;bit_index<32;bit_index=bit_index+1)begin:g_digest
  assign digest[bit_index]=trace_data[bit_index]^trace_data[bit_index+32]^
   trace_data[bit_index+64]^trace_data[bit_index+96]^trace_data[bit_index+128]^
   trace_data[bit_index+160]^trace_data[bit_index+192]^trace_data[bit_index+224]^
   trace_data[bit_index+256]^trace_data[bit_index+288];
 end endgenerate
 generate if(1)begin:g_production
  if(1)begin:g_status_uart
   wire observer_word_n,request;
   wire [5:0] index;
   trace_probe_observer u_observer(.sys_clk(sys_clk),.rst_n(cold_reset_n),
    .request_in(request_in),.index_in(index_in),.o_trace_request(request),.o_trace_index(index));
   reset_release_sync u_trace_word_reset(.i_clk(word_clk),.i_async_rst_n(cold_reset_n),.o_rst_n(observer_word_n));
   rx_first_loss_trace u_trace(.i_word_clk(word_clk),.i_observer_rst_n(observer_word_n),
    .i_cohort_rst_n(cohort_n),.i_enable(enable),.i_trigger(trigger),.i_sample(sample_word),
    .i_sys_clk(sys_clk),.i_sys_rst_n(cold_reset_n),.i_request(request),.i_index(index),
    .o_ack(ack),.o_data(trace_data));
  end
 end endgenerate
endmodule
'''


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signatures(path: Path) -> list[tuple[str, str, str]]:
    text = path.read_text(errors='replace')
    return sorted(re.findall(r'Begin Point\s*:\s*([^\n]+)\nEnd Point\s*:\s*([^\n]+)\nCheck Type\s*:\s*([^\n]+)', text))


def validate(run: Path, result: dict) -> None:
    log = (run / result.get('check_log','check.log')).read_text(errors='replace')
    check = (run / 'mapped_check.timing').read_text(errors='replace')
    assert 'RT_PROBE_SCOPE_DONE' in log and 'RT_PROBE_NATIVE_REOPEN_DONE' in log
    matched = re.findall(r'RT_SELECTOR (\d+) COUNT=(\d+)', log)
    assert len(matched) == len(result['selectors']) and all(int(n)>0 for _, n in matched)
    assert 'checking invalid constraint(0)' in check
    assert 'There are 0 constraints that have no timing paths.' in check
    smd = re.findall(r'^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_max_delay[^\n]+)', check, re.M)
    assert len(smd) == 4
    assert all(int(total)>0 and total==dominated and int(shadowed)==int(ignored)==0
        for total, dominated, shadowed, ignored, _ in smd)
    protected_counts = []
    for index, _ in enumerate(result['protected_pairs']):
        before = signatures(run / f'protected_{index}_before.timing')
        after = signatures(run / f'protected_{index}_after.timing')
        assert before and before == after, f'Local protected paths changed: {index}'
        assert all('setup' in kind for _, _, kind in after)
        if index==1:assert all('u_trace/ack_sync_reg.d' in end for _,end,_ in after)
        protected_counts.append(len(after))
    reset_paths = signatures(run / 'reset_before.timing')
    assert reset_paths and all(re.search(r'\.(?:asr|sr)\b',end) for _, end, _ in reset_paths)
    assert all(kind in ('recovery', 'removal') for _, _, kind in reset_paths)
    # TD report_timing_path always appends its Set False Path section; unlike
    # report_timing_summary it does not accept an -include_ignored option.
    # Synthesized SEQ names the asynchronous reset pin sr; packed hardware
    # names it asr. Recovery checks plus the real RTL establish async usage.
    reset_after=(run/'reset_after.timing').read_text(errors='replace')
    regular=reset_after.split('\nSet False Path\n',1)[0]
    assert 'Begin Point' not in regular, 'Foreign SYS reset still has a timed release path'
    reset_ignored=signatures(run/'reset_after.timing')
    assert len(reset_ignored)==3 and all(re.search(r'\.(?:asr|sr)\b',end) for _,end,_ in reset_ignored)
    assert reset_after.count('Constr         :     set_false_path -from [get_clocks {sys_clk_25m}]')==3
    for entry in result['inputs']:
        if Path(entry['path']).resolve()!=Path(__file__).resolve():
            assert sha(Path(entry['path'])) == entry['sha256'], 'Source changed during probe'
    result.update(status='PASS', matched_selector_counts=matched,
        smd_path_counts=[int(row[0]) for row in smd], max_delay_all_dominated=True,
        smd_shadowed=0,smd_ignored=0,invalid_constraints=0,no_timing_path_constraints=0,
        protected_setup_signature_counts=protected_counts,
        protected_hold_scope='MAPPED_SELECTOR_DISJOINTNESS_ONLY',
        foreign_reset_original_asr_paths=len(reset_paths),
        foreign_reset_timed_after=0,foreign_reset_ignored_asr_paths=len(reset_ignored),
        physical_hold_removal='NOT_RUN',validation_script_sha256=sha(Path(__file__)))
    print('PASS mapped RT mailbox: 4 SMD + 4 hold-only nonempty/dominated; local setup preserved; SYS reset ASR-only')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=PROJECT/'tmp/rx_trace_cdc_20261028')
    parser.add_argument('--check-existing',action='store_true',help='reuse unchanged gate DB; keep original failed result/log')
    args = parser.parse_args()
    run = args.output.resolve()
    if not args.check_existing:run.mkdir(parents=True, exist_ok=False)
    sdc = PROJECT/'fpga_prj/constraints/observer_cdc.sdc'
    added = sdc.read_text().split('# RT/V1:',1)[1]
    constraints = [line.strip() for line in added.splitlines()[1:]
        if line.strip() and not line.lstrip().startswith('#')]
    smd = [line for line in constraints if line.startswith('set_max_delay ')]
    hold = [line for line in constraints if line.startswith('set_false_path -hold ')]
    reset = [line for line in constraints if line.startswith('set_false_path -from [get_clocks')]
    assert len(constraints)==11 and len(smd)==4 and len(hold)==4 and len(reset)==3
    selectors = list(dict.fromkeys(re.findall(r'\[get_regs \{([^}]+)\}\]', '\n'.join(constraints))))
    protected_pairs = [(PREFIX+'u_trace/request_meta',PREFIX+'u_trace/request_sync'),
        # The direct top-level o_ack connection is canonicalized to port ack
        # by mapped synthesis. This is the same held stage-2 register, not a
        # relaxed exception or an alternative functional endpoint.
        (PREFIX+'u_trace/ack_meta','ack*'),
        (PREFIX+'u_trace/request_index[*]',PREFIX+'u_trace/ram_read_address[*]'),
        (PREFIX+'u_trace/request_sync',PREFIX+'u_trace/read_state*'),
        (PREFIX+'u_trace_word_reset/release_pipe[0]*',PREFIX+'u_trace_word_reset/release_pipe[1]*')]
    protected = [pair[1] for pair in protected_pairs]
    # Do not compare the reset selectors against the protected local D-stage;
    # the proof for these exceptions instead inspects actual source/sink pins.
    data_selectors = list(dict.fromkeys(re.findall(r'\[get_regs \{([^}]+)\}\]', '\n'.join(smd+hold))))
    if not args.check_existing:
        (run/'probe.v').write_text(RTL, newline='\n')
        (run/'base.sdc').write_text(
            'create_clock -name sys_clk_25m -period 40.000 [get_ports {sys_clk}]\n'
            'create_clock -name word_clk_probe -period 8.888 [get_ports {word_clk}]\n', newline='\n')
        (run/'added.sdc').write_text('\n'.join(constraints)+'\n',newline='\n')
    sources = [PROJECT/'src_fpga/rtl'/name for name in ('rx_first_loss_trace.v','reset_release_sync.v')]
    common = f'cd {{{run.as_posix()}}}\nimport_device ph1_90.db -package PH1A90SEG324 -speed 2\n'
    build = common+'''create_project rx_trace_cdc_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module rx_trace_cdc_probe
add_files ./probe.v
add_files ./base.sdc
'''+''.join(f'add_files {{{path.as_posix()}}}\n' for path in sources)+'''set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
exit 0
'''
    if not args.check_existing:(run/'build.tcl').write_text(build,newline='\n')
    check = common+'''open_project ./rx_trace_cdc_probe.al -noanalyze
open_run syn_1
update_timing
set protected {}
'''
    for pattern in protected:
        check += f'set nodes [get_regs {{{pattern}}}]\nif {{[llength $nodes]==0}} {{error {{RT_PROTECTED_EMPTY {pattern}}}}}\n'
        check += 'foreach node $nodes {lappend protected $node}\n'
    for index, pattern in enumerate(selectors):
        check += f'set nodes [get_regs {{{pattern}}}]\nif {{[llength $nodes]==0}} {{error {{RT_SELECTOR_EMPTY {index} {pattern}}}}}\n'
        check += f'puts "RT_SELECTOR {index} COUNT=[llength $nodes] NODES=$nodes"\n'
        if pattern in data_selectors:
            check += 'foreach node $nodes {if {[lsearch -exact $protected $node]>=0} {error "RT_DATA_EXCEPTION_HITS_PROTECTED $node"}}\n'
    for stage in ('before','after'):
        if stage=='after':
            check += 'read_sdc ./added.sdc\nupdate_timing\ncheck_timing -file mapped_check.timing\n'
            check += 'report_timing_summary -report_type max_min -include_ignored -ep_num 500 -path_num 1 -file mapped_exceptions.timing\n'
        for index,(launch,capture) in enumerate(protected_pairs):
            check += f'report_timing_path -from [get_regs {{{launch}}}] -to [get_regs {{{capture}}}] -ep_num 100 -path_num 2 -file protected_{index}_{stage}.timing\n'
        reset_targets = ' '.join(PREFIX+f'u_trace_word_reset/release_pipe[{bit}]*' for bit in range(3))
        check += f'report_timing_path -from [get_clocks {{sys_clk_25m}}] -to [get_regs {{{reset_targets}}}] -ep_num 100 -path_num 2 -file reset_{stage}.timing\n'
    check += '''puts "RT_PROBE_SCOPE_DONE"
close_project
open_project ./rx_trace_cdc_probe.al -noanalyze
open_run syn_1
puts "RT_PROBE_NATIVE_REOPEN_DONE"
close_project
exit 0
'''
    check_name='check'
    if args.check_existing:
        revision=2
        while (run/f'check_v{revision}.tcl').exists():revision+=1
        check_name=f'check_v{revision}'
    (run/(check_name+'.tcl')).write_text(check,newline='\n')
    result = {'status':'IN_PROGRESS','scope':'TINY_REAL_RT_LEAF_MAPPED_ONLY_SYNTHETIC_SYS_DRIVER',
        'td_root':str(args.td_root.resolve()),'selectors':selectors,'protected_pairs':protected_pairs,
        'inputs':[{'path':str(path),'sha256':sha(path)} for path in [sdc,*sources,run/'probe.v',run/'base.sdc',run/'added.sdc',Path(__file__)]],
        'commands':[],'production_synthesis':'NOT_RUN','place':'NOT_RUN','route':'NOT_RUN',
        'bitgen':'NOT_RUN','board':'NOT_RUN'}
    if args.check_existing:
        previous=json.loads((run/'RESULTS.json').read_text())
        for entry in previous['inputs']:
            if Path(entry['path']).resolve()!=Path(__file__).resolve():
                assert sha(Path(entry['path']))==entry['sha256'],'Cannot reuse gate DB after input changes'
        assert (run/'added.sdc').read_text().splitlines()==constraints
        result['original_result_status']=previous['status']
        result['original_commands']=previous['commands']
        result['reused_gate_database']='rx_trace_cdc_probe_Runs/syn_1/rx_trace_cdc_probe_gate.db'
    result['check_log']=check_name+'.log'
    try:
        for stage in ([check_name] if args.check_existing else ['build',check_name]):
            command=[sys.executable,str(REPO/'tools/run_td.py'),str(run/f'{stage}.tcl'),
                '--td-root',str(args.td_root.resolve()),'--workdir',str(run),'--log',str(run/f'{stage}.log')]
            result['commands'].append(command)
            subprocess.run(command,cwd=REPO,check=True,timeout=120)
        validate(run,result)
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        result_path=run/(f'MAPPED_SCOPE_{check_name}_RESULTS.json' if args.check_existing else 'RESULTS.json')
        result_path.write_text(json.dumps(result,indent=2)+'\n')
        print(result_path)


if __name__=='__main__':
    main()
