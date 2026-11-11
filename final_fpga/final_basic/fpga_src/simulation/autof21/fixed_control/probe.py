"""Bounded one-thread native SYN of fixed control; mapped SDC/area evidence only."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REPO = ROOT.parents[1]
PREFIX = 'g_dehaze_lut_control$u_lut_control/'
RTL = r'''module fixed_control_probe(
 input user_clk,pixel_clk,user_rst_n,pixel_rst_n,
 input user_session_ready,pixel_session_ready,lut_available,
 input write_valid,input [11:0] write_offset,input [31:0] write_data,input [3:0] write_strobes,
 input read_valid,input [11:0] read_offset,
 output [31:0] read_data,output [1:0] write_response,read_response,
 output read_response_valid,output [7:0] flags);
 (* preserve="true" *) reg pixel_table_valid;
 (* preserve="true" *) reg local_driver,ordinary_d,ordinary_ce,ordinary_asr;
 always @(posedge pixel_clk)pixel_table_valid<=lut_available;
 always @(posedge user_clk)begin
  local_driver<=write_data[0];ordinary_d<=local_driver;
  if(local_driver)ordinary_ce<=write_data[1];
 end
 always @(posedge user_clk or negedge local_driver)
  if(!local_driver)ordinary_asr<=0;else ordinary_asr<=write_data[2];
 assign flags[7:5]={ordinary_asr^write_data[0],ordinary_ce^write_data[1],ordinary_d^write_data[2]};
 generate if(1)begin:g_dehaze_lut_control
  fixed_dehaze_lut_control u_lut_control(
   .i_user_clk(user_clk),.i_user_rst_n(user_rst_n),.i_pixel_clk(pixel_clk),.i_pixel_rst_n(pixel_rst_n),
   .i_user_session(32'd1),.i_pixel_session(32'd1),
   .i_user_session_ready(user_session_ready),.i_pixel_session_ready(pixel_session_ready),
   .i_user_load_permitted(1'b0),.i_pixel_load_permitted(1'b0),
   .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),.write_strobes(write_strobes),
   .write_response(write_response),.read_valid(read_valid),.read_offset(read_offset),
   .read_response_valid(read_response_valid),.read_data(read_data),.read_response(read_response),
   .o_user_busy(),.o_user_reset_done(flags[0]),.o_pixel_reset_done(flags[1]),
   .o_core_reset_n(flags[2]),.o_core_async_reset_n(flags[3]),
   .cfg_begin_valid(),.cfg_begin_ready(1'b0),.cfg_generation(),.cfg_valid(),.cfg_ready(1'b0),
   .cfg_index(),.cfg_value(),.cfg_commit_valid(),.cfg_commit_ready(1'b0),.cfg_abort(),
   .cfg_status_valid(1'b0),.cfg_status_ready(),.cfg_status_ok(1'b0),
   .cfg_status_error(8'd0),.cfg_status_generation(32'd0),
   .lut_valid(pixel_table_valid),.lut_generation(32'd1),
   .o_pixel_lut_valid(flags[4]),.o_pixel_lut_generation(),.o_pixel_loading(),.o_pixel_update_busy(),
   .o_pixel_fault(),.o_stale_reply_count());
 end endgenerate
endmodule
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signatures(path):
    return sorted(re.findall(r'Begin Point\s*:\s*([^\n]+)\nEnd Point\s*:\s*([^\n]+)\nCheck Type\s*:\s*([^\n]+)',
                             path.read_text(errors='replace')))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--td-root', type=Path, required=True)
    ap.add_argument('--name', required=True)
    a = ap.parse_args()
    assert re.fullmatch('[a-z][a-z0-9_]{0,48}', a.name)
    run = ROOT / 'tmp/autof21/fixed_control_probe' / a.name
    run.mkdir(parents=True, exist_ok=False)
    sdc = ROOT / 'fpga_prj/constraints/stream_cdc.sdc'
    commands = [line.strip() for line in sdc.read_text().splitlines()
                if PREFIX + 'ready_meta' in line and line.strip().startswith(('set_max_delay ', 'set_false_path '))]
    assert len(commands) == 2 and commands[0].startswith('set_max_delay ') and commands[1].startswith('set_false_path -hold ')
    assert '-datapath_only 7.000' in commands[0]
    (run / 'probe.v').write_text(RTL, newline='\n')
    (run / 'base.sdc').write_text(
        'create_clock -name user_probe -period 16.000 [get_ports {user_clk}]\n'
        'create_clock -name {u_pixel_pll/pll_inst.clkc[0]} -period 7.500 [get_ports {pixel_clk}]\n', newline='\n')
    (run / 'added.sdc').write_text('\n'.join(commands) + '\n', newline='\n')
    sources = [ROOT / 'src_fpga/rtl' / n for n in ('fixed_dehaze_lut_control.v', 'reset_release_sync.v')]
    header = ROOT / 'src_fpga/rtl/include/04_include/pcie_protocol_v1.vh'
    common = f'cd {{{run.as_posix()}}}\nimport_device ph1_90.db -package PH1A90SEG324 -speed 2\n'
    build = common + '''create_project fixed_control_probe . -family ph1 -device PH1A90SEG324 -speed -2
top_module fixed_control_probe
add_files ./probe.v
add_files ./base.sdc
'''
    build += f'add_include_dir {{{header.parent.as_posix()}}}\n'
    build += ''.join(f'add_files {{{p.as_posix()}}}\n' for p in sources)
    build += '''set_param -run syn_1 flow thread 1
launch_runs syn_1
wait_run syn_1
close_project
exit 0
'''
    (run / 'build.tcl').write_text(build, newline='\n')
    protected = [PREFIX + 'ready_sync', 'ordinary_d', 'ordinary_ce', 'ordinary_asr',
                 PREFIX + 'u_user_reset/release_pipe[0]*', PREFIX + 'u_user_reset/release_pipe[1]*',
                 PREFIX + 'u_pixel_reset/release_pipe[0]*', PREFIX + 'u_pixel_reset/release_pipe[1]*']
    check = common + '''open_project ./fixed_control_probe.al -noanalyze
open_run syn_1
update_timing
'''
    check += 'set protected {}\n'
    for pattern in protected:
        check += f'set nodes [get_regs {{{pattern}}}]\n'
        check += f'if {{[llength $nodes]==0}} {{error {{FIXED_PROTECTED_EMPTY {pattern}}}}}\n'
        check += 'foreach node $nodes {lappend protected $node}\n'
    check += f'set first [get_regs {{{PREFIX}ready_meta}}]\n'
    check += 'if {[llength $first]!=1} {error "FIXED_FIRST_SELECTOR_NOT_EXACTLY_ONE $first"}\n'
    check += 'puts "FIXED_FIRST COUNT=[llength $first] NODES=$first"\n'
    check += 'foreach node $first {if {[lsearch -exact $protected $node]>=0} {error "FIXED_FIRST_OVERLAPS_PROTECTED $node"}}\n'
    # Actual stage 1 -> stage 2, and deliberately retained ordinary local D/CE/ASR.
    targets = PREFIX + 'ready_sync ordinary_d ordinary_ce ordinary_asr'
    check += f'report_timing_path -to [get_regs {{{targets}}}] -ep_num 100 -path_num 3 -file protected_before.timing\n'
    check += '''read_sdc ./added.sdc
update_timing
check_timing -file mapped_check.timing
report_area -io_info -file leaf.area
report_timing_exception -ep_num 100 -path_num 3 -file timing_exception.rpt
report_timing_summary -report_type max_min -include_ignored -ep_num 100 -path_num 3 -file mapped.timing
report_run_param syn_1 -file syn_1.params
'''
    check += f'report_timing_path -to [get_regs {{{targets}}}] -ep_num 100 -path_num 3 -file protected_after.timing\n'
    check += '''puts "FIXED_PROBE_SCOPE_DONE"
close_project
open_project ./fixed_control_probe.al -noanalyze
open_run syn_1
puts "FIXED_PROBE_NATIVE_REOPEN_DONE"
close_project
exit 0
'''
    (run / 'check.tcl').write_text(check, newline='\n')
    paths = [Path(__file__), *sources, header, *[run / n for n in ('probe.v', 'base.sdc', 'added.sdc', 'build.tcl', 'check.tcl')]]
    result = dict(status='IN_PROGRESS', scope='TINY_FIXED_CONTROL_MAPPED_SDC_RESOURCE_ONLY',
                  td_root=str(a.td_root.resolve()), source_sdc_origin=str(sdc), source_sdc_sha256=sha(sdc),
                  copied_constraints=commands, protected_selectors=protected, commands=[],
                  inputs=[dict(path=p.resolve().as_posix(), sha256=sha(p)) for p in paths],
                  synthesis='NOT_RUN', place='NOT_RUN', route='NOT_RUN', bitgen='NOT_RUN',
                  physical_hold_removal='NOT_RUN', board='NOT_RUN')
    try:
        for stage in ('build', 'check'):
            cmd = [sys.executable, str(REPO / 'tools/run_td.py'), str(run / f'{stage}.tcl'),
                   '--td-root', str(a.td_root.resolve()), '--workdir', str(run), '--log', str(run / f'{stage}.log')]
            result['commands'].append(cmd)
            with (run / (stage + '.stdout.log')).open('w') as output:
                proc = subprocess.Popen(cmd, cwd=REPO, stdout=output, stderr=subprocess.STDOUT)
                try:
                    code = proc.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    stopped = subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True, text=True)
                    result.update(status='BLOCKED', error=f'{stage} exceeded fixed 120s limit',
                                  timeout_process_tree_stop=stopped.stdout + stopped.stderr)
                    raise
            if code:
                raise RuntimeError(f'{stage} returned {code}: {run / (stage + ".log")}')
            if stage == 'build':
                result['synthesis'] = 'PASS'
        log = (run / 'check.log').read_text(errors='replace')
        text = (run / 'mapped_check.timing').read_text(errors='replace')
        assert 'FIXED_PROBE_SCOPE_DONE' in log and 'FIXED_PROBE_NATIVE_REOPEN_DONE' in log
        assert 'FIXED_FIRST COUNT=1' in log
        assert 'checking invalid constraint(0)' in text
        assert 'There are 0 constraints that have no timing paths.' in text
        rows = re.findall(r'^\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_max_delay[^\n]+)', text, re.M)
        assert len(rows) == 1 and int(rows[0][0]) > 0 and rows[0][0] == rows[0][1] and rows[0][2:4] == ('0', '0'), rows
        before = signatures(run / 'protected_before.timing')
        after = signatures(run / 'protected_after.timing')
        assert before and before == after, 'stage 2/local paths were changed'
        assert any('ready_sync_reg.d' in end for _, end, _ in after), after
        assert any('ordinary_d' in end and kind == 'setup' for _, end, kind in after), after
        assert any('ordinary_ce' in end and kind == 'setup' for _, end, kind in after), after
        assert any('ordinary_asr' in end and kind == 'recovery' for _, end, kind in after), after
        area = (run / 'leaf.area').read_text(errors='replace')
        for row in result['inputs']:
            assert sha(Path(row['path'])) == row['sha256'], row['path']
        result.update(status='PASS', first_selector_count=1, smd_path_count=int(rows[0][0]),
                      smd_all_dominated=True, smd_shadowed=0, smd_ignored=0,
                      invalid_constraints=0, no_path_constraints=0,
                      protected_path_signatures=after, protected_min_scope='MAPPED_SELECTOR_DISJOINTNESS_ONLY',
                      area_report='leaf.area', estimated_timing_only=True)
        print('RESULT: PASS FIXED_CONTROL_MAPPED nonempty=1 max_delay7ns_hold_only=1 shadowed=0 local_stage2_D_CE_ASR_preserved=1')
    except Exception as e:
        if result['status'] != 'BLOCKED':
            result.update(status='FAIL', error=str(e))
        raise
    finally:
        (run / 'RESULTS.json').write_text(json.dumps(result, indent=2) + '\n')
        print('Evidence', run)


if __name__ == '__main__':
    main()
