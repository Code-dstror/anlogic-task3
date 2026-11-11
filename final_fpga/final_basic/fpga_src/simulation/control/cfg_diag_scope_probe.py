"""Tiny mapped observer-only SDC scope check; never places or routes a design."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[3]
REPO = PROJECT.parents[1]
PREFIX = 'g_production$g_status_uart$u_observer/'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signatures(path):
    body = path.read_text()
    return sorted(re.findall(
        r'Begin Point\s*:\s*([^\n]+)\nEnd Point\s*:\s*([^\n]+)\nCheck Type\s*:\s*([^\n]+)', body))


def validate_evidence(run, result):
    check_text=(run/'mapped_check.timing').read_text()
    assert 'checking invalid constraint(0)' in check_text
    assert 'There are 0 constraints that have no timing paths.' in check_text
    check_log=(run/'check.log').read_text()
    assert 'CFG_PROBE_MAPPED_SCOPE_DONE' in check_log and 'CFG_PROBE_NATIVE_REOPEN_DONE' in check_log
    rows=re.findall(r'CFG_PROBE_SELECTOR (\d+) COUNT=(\d+)',check_log)
    assert len(rows)==len(result['selectors']) and all(int(count)>0 for _,count in rows)
    smd_rows=re.findall(r'^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_max_delay[^\n]+)',check_text,re.M)
    assert len(smd_rows)==7
    assert all(int(total)>0 and total==dominated and int(shadowed)==int(ignored)==0
               for total,dominated,shadowed,ignored,_ in smd_rows)
    before,after=signatures(run/'protected_before.timing'),signatures(run/'protected_after.timing')
    assert before and before==after, 'Protected stage-2/business timing paths changed'
    assert any('business_stage2' in row[1] for row in after)
    assert all('setup' in row[2] for row in after)
    # TD Synthesized reports no min endpoints for these ordinary local paths.
    # Do not invent mapped hold coverage. Every hold-only exception collection
    # was checked disjoint from the protected actual mapped register sets in
    # check.tcl; physical hold/removal still requires implementation evidence.
    for entry in result['inputs']:
        if Path(entry['path']).resolve()!=Path(__file__).resolve():
            assert sha(Path(entry['path']))==entry['sha256'], 'Source changed during probe'
    result.pop('error',None)
    result.update(status='PASS',matched_selector_counts=rows,
                  protected_timing_signatures_unchanged=len(after),invalid_constraints=0,
                  no_timing_path_constraints=0,smd_path_counts=[int(row[0]) for row in smd_rows],
                  max_delay_all_dominated=True,shadowed_constraints=0,ignored_constraints=0,
                  protected_hold_scope='MAPPED_SELECTOR_DISJOINTNESS_ONLY',
                  physical_hold_analysis='NOT_RUN',
                  synthesized_min_endpoint_limit='Protected local groups have zero reported Min endpoints',
                  validation_script_sha256=sha(Path(__file__)))
    print('PASS tiny mapped CFG observer scope: 7 SMD + 7 hold-only, selectors nonempty, protected setup paths unchanged')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--td-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--validate-existing', action='store_true',
                        help='parse existing mapped evidence only; never launch TD')
    args = parser.parse_args()
    run = args.output.resolve()
    if args.validate_existing:
        result=json.loads((run/'RESULTS.json').read_text())
        result['previous_validation_status']=result['status']
        result['revalidation_note']='Parsing-only correction of an unsupported mapped hold-path assertion; original failure preserved'
        validate_evidence(run,result)
        (run/'MAPPED_SCOPE_RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
        return
    run.mkdir(parents=True, exist_ok=False)
    sdc = PROJECT/'fpga_prj/constraints/observer_cdc.sdc'
    added = sdc.read_text().split('# CFG diagnostic mailboxes', 1)[1].split('\n', 1)[1]
    commands = [line.strip() for line in added.splitlines()
                if line.strip() and not line.lstrip().startswith('#')]
    assert len(commands) == 14
    assert sum(line.startswith('set_max_delay ') for line in commands) == 7
    assert sum(line.startswith('set_false_path -hold ') for line in commands) == 7
    assert all('get_clocks' not in line and 'get_pins' not in line for line in commands)
    selectors = list(dict.fromkeys(re.findall(r'\[get_regs \{([^}]+)\}\]', '\n'.join(commands))))
    assert all(pattern.startswith(PREFIX) for pattern in selectors)
    protected = [PREFIX+'cfg_ack_sync[*]', PREFIX+'cfg_reset_sync[*]',
                 PREFIX+'g_cfg_diag$g_domain[0]$u_snapshot/request_sync[1]',
                 PREFIX+'g_cfg_diag$g_domain[1]$u_snapshot/request_sync[1]',
                 'business_stage2[*]']
    rtl = r'''module cfg_diag_scope_probe(
 input sys_clk,pixel_clk,dfi_clk,user_clk,rst_n,
 input [31:0] user_data,pixel_data,
 input [2:0] observer_reset_n,domain_reset_n,
 input [1:0] cfg_reset_n,
 input [35:0] domain_flags,input [11:0] faults,input [5:0] progress,
 input [7:0] sys_status,input business_input,
 output tx,output [1:0] business_output);
 (* preserve="true" *) reg [223:0] user_payload,pixel_payload;
 (* preserve="true" *) reg [1:0] business_stage2;
 always @(posedge user_clk)user_payload<={user_payload[191:0],user_data};
 always @(posedge pixel_clk)pixel_payload<={pixel_payload[191:0],pixel_data};
 always @(posedge sys_clk)business_stage2<={business_stage2[0],business_input};
 assign business_output=business_stage2;
 generate if(1)begin:g_production
  if(1)begin:g_status_uart
   uart_status_observer #(.CFG_DIAG_ENABLE(1)) u_observer(
    .i_sys_clk(sys_clk),.i_sys_rst_n(rst_n),.i_pixel_clk(pixel_clk),
    .i_dfi_clk(dfi_clk),.i_user_clk(user_clk),
    .i_domain_observer_rst_n(observer_reset_n),.i_domain_reset_n(domain_reset_n),
    .i_sys_status({sys_status,sys_status}),.i_domain_flags(domain_flags),
    .i_domain_faults(faults),.i_domain_progress(progress),
    .i_cfg_domains({pixel_payload,user_payload}),.i_cfg_domain_reset_n(cfg_reset_n),
    .o_uart_tx(tx));
  end
 end endgenerate
endmodule
'''
    (run/'probe.v').write_text(rtl, newline='\n')
    (run/'base.sdc').write_text(''.join(
        f'create_clock -name {name}_probe -period {period} [get_ports {{{name}_clk}}]\n'
        for name,period in [('sys',40),('pixel',8),('dfi',7.5),('user',16)]), newline='\n')
    (run/'added.sdc').write_text('\n'.join(commands)+'\n', newline='\n')
    sources = [PROJECT/'src_fpga/rtl'/name for name in
               ('uart_observer_snapshot.v','cfg_diag_snapshot.v','uart_status_observer.v')]
    root = run.as_posix()
    common = f'cd {{{root}}}\nimport_device ph1_90.db -package PH1A90SEG324 -speed 2\n'
    build = common + '''create_project cfg_diag_scope_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module cfg_diag_scope_probe
add_files ./probe.v
add_files ./base.sdc
'''
    build += ''.join(f'add_files {{{path.as_posix()}}}\n' for path in sources)
    build += '''set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
exit 0
'''
    (run/'build.tcl').write_text(build, newline='\n')
    check = common + '''open_project ./cfg_diag_scope_probe.al -noanalyze
open_run syn_1
update_timing
'''
    check += 'set protected {}\n'
    for pattern in protected:
        check += (f'set nodes [get_regs {{{pattern}}}]\n'
                  f'if {{[llength $nodes]==0}} {{error {{PROTECTED_SELECTOR_EMPTY {pattern}}}}}\n'
                  'foreach node $nodes {lappend protected $node}\n')
    check += 'puts "CFG_PROBE_PROTECTED=$protected"\n'
    for index,pattern in enumerate(selectors):
        check += (f'set nodes [get_regs {{{pattern}}}]\n'
                  f'if {{[llength $nodes]==0}} {{error {{CFG_SELECTOR_EMPTY {index} {pattern}}}}}\n'
                  f'puts "CFG_PROBE_SELECTOR {index} COUNT=[llength $nodes] NODES=$nodes"\n'
                  'foreach node $nodes {if {[lsearch -exact $protected $node]>=0} '
                  '{error "CFG_SELECTOR_OVERLAPS_PROTECTED $node"}}\n')
    check += '''report_timing_path -to [get_regs {'''+' '.join(protected)+'''}] -ep_num 100 -path_num 2 -file protected_before.timing
read_sdc ./added.sdc
update_timing
check_timing -file mapped_check.timing
report_timing_summary -report_type max_min -include_ignored -ep_num 500 -path_num 1 -file mapped_exceptions.timing
report_timing_path -to [get_regs {'''+ ' '.join(protected)+'''}] -ep_num 100 -path_num 2 -file protected_after.timing
puts "CFG_PROBE_MAPPED_SCOPE_DONE"
close_project
open_project ./cfg_diag_scope_probe.al -noanalyze
open_run syn_1
puts "CFG_PROBE_NATIVE_REOPEN_DONE"
close_project
exit 0
'''
    (run/'check.tcl').write_text(check, newline='\n')
    result = {'status':'IN_PROGRESS', 'scope':'TINY_OBSERVER_MAPPED_SDC_ONLY',
              'td_root':str(args.td_root.resolve()),'added_smd':7,'added_hold_only':7,
              'selectors':selectors,'protected_selectors':protected,'commands':[],
              'inputs':[{'path':str(path),'sha256':sha(path)} for path in [sdc,*sources,Path(__file__)]],
              'production_synthesis':'NOT_RUN','production_physical':'NOT_RUN',
              'production_timing':'NOT_RUN','tiny_place':'NOT_RUN','tiny_route':'NOT_RUN',
              'bitgen':'NOT_RUN','board':'NOT_RUN'}
    try:
        for stage in ('build','check'):
            command = [sys.executable,str(REPO/'tools/run_td.py'),str(run/f'{stage}.tcl'),
                       '--td-root',str(args.td_root.resolve()),'--workdir',str(run),
                       '--log',str(run/f'{stage}.log')]
            result['commands'].append(command)
            subprocess.run(command,cwd=REPO,check=True,timeout=120)
        validate_evidence(run,result)
    except Exception as error:
        result.update(status='FAIL',error=str(error))
        raise
    finally:
        (run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')


if __name__=='__main__':
    main()
