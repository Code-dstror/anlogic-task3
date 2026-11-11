"""Bounded local mapping of equivalent fixed-slice control flit routing."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REPO = PROJECT.parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def prepare_variant():
    original = (PROJECT / 'src_fpga/rtl/control_message_fifo_ip.v').read_text()
    candidate = original.replace(
        'write_word <= padded_source_message[source_flit_index*40 +: 40];',
        'write_word <= selected_source_flit;')
    anchor = '    // The assembly register also holds the sole published output message.'
    selection = '''    // Constant bit slices with a shared index decode. Protocol state is unchanged.
    wire [FLIT_COUNT-1:0] source_select;
    wire [39:0] selected_source_flit;
    genvar sf, sb;
    generate for (sf=0; sf<FLIT_COUNT; sf=sf+1) begin:g_source_select
        assign source_select[sf] = source_flit_index == sf;
    end
    for (sb=0; sb<40; sb=sb+1) begin:g_source_bit
        wire [FLIT_COUNT-1:0] terms;
        for (sf=0; sf<FLIT_COUNT; sf=sf+1) begin:g_term
            assign terms[sf] = source_select[sf] && padded_source_message[sf*40+sb];
        end
        assign selected_source_flit[sb] = |terms;
    end endgenerate
'''
    assert original.count(anchor) == 1
    candidate = candidate.replace(anchor, selection + anchor)
    old = '            sink_message[sink_flit_index*40 +: 40] <= fifo_read_data;'
    assert candidate.count(old) == 1
    candidate = candidate.replace(old, '')
    anchor = '    control_fifo_40x512 u_control_async_fifo ('
    assembly = '''    // Each flit has one constant write slice; no variable part-select mask.
    genvar rf;
    generate for (rf=0; rf<FLIT_COUNT; rf=rf+1) begin:g_sink_flit
        always @(posedge i_sink_clk)
            if (sink_local_rst_n && fifo_read_enable && sink_flit_index==rf)
                sink_message[rf*40+:40] <= fifo_read_data;
    end endgenerate

'''
    assert candidate.count(anchor) == 1
    candidate = candidate.replace(anchor, assembly + anchor)
    for label, text in [('baseline', original), ('candidate', candidate)]:
        path = HERE / label / 'control_message_fifo_ip.v'
        path.parent.mkdir(exist_ok=True)
        if path.exists() and path.read_text() != text:
            raise RuntimeError('Refuse to overwrite changed experiment source: ' + str(path))
        path.write_text(text, newline='\n')

def wrapper(width):
    return f'''module control_flit_probe(
    input wire source_clk,sink_clk,source_reset_n,sink_reset_n,
    input wire [39:0] load_data,input wire [4:0] load_index,input wire load,
    input wire valid,input wire ready,output wire source_ready,sink_valid,
    output wire source_done,sink_done,output wire [39:0] observe);
    localparam W={width}, N=(W+39)/40;
    reg [N*40-1:0] input_bank;
    wire [W-1:0] output_message;
    wire [N*40-1:0] padded_output={{{{(N*40-W){{1'b0}}}},output_message}};
    genvar a,b;
    generate for(a=0;a<N;a=a+1)begin:bank
        always @(posedge source_clk)if(load && load_index==a)
            input_bank[a*40+:40]<=load_data;
    end
    for(b=0;b<40;b=b+1)begin:tap
        wire [N-1:0] bits;
        for(a=0;a<N;a=a+1)begin:t
            assign bits[a]=padded_output[a*40+b];
        end
        assign observe[b]=^bits;
    end endgenerate
    control_message_fifo_ip #(.MESSAGE_WIDTH(W),.BORROW_SOURCE(1)) dut(
        .i_source_clk(source_clk),.i_source_rst_n(source_reset_n),
        .i_source_data(input_bank[W-1:0]),.i_source_valid(valid),
        .o_source_ready(source_ready),.o_source_reset_done(source_done),
        .i_sink_clk(sink_clk),.i_sink_rst_n(sink_reset_n),
        .o_sink_data(output_message),.o_sink_valid(sink_valid),.i_sink_ready(ready),
        .o_sink_reset_done(sink_done),.o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index());
endmodule
'''

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', required=True)
    parser.add_argument('--td-root', required=True)
    parser.add_argument('--width', type=int, default=375)
    args = parser.parse_args()
    if not args.name.replace('_', '').replace('-', '').isalnum():
        parser.error('Use an ASCII run label')
    prepare_variant()
    runs = PROJECT / 'tmp/control_flit_equiv' / args.name
    runs.mkdir(parents=True, exist_ok=False)
    results = []
    for arm in ('baseline', 'candidate'):
        work = runs / arm
        work.mkdir()
        source = HERE / arm / 'control_message_fifo_ip.v'
        inputs = [source, PROJECT / 'src_fpga/rtl/control_fifo_40x512.v']
        ipc = PROJECT / 'src_fpga/ip/camera_control_fifo_40x512/camera_control_fifo_40x512.xml'
        assert ipc.exists()
        (work / 'control_flit_probe.v').write_text(wrapper(args.width))
        files = [*inputs, ipc, work / 'control_flit_probe.v']
        tcl = '''import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project control_flit_probe . -family ph1 -device PH1A90SEG324 -speed -2
'''
        tcl += ''.join('add_files {' + p.as_posix() + '}\n' for p in files)
        tcl += '''top_module control_flit_probe
set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
set native control_flit_probe_Runs/syn_1
if {![file isfile $native/.opt_gate.end.f] || [llength [glob -nocomplain -directory $native .*.error.f]]} {error "probe opt_gate failed"}
close_project
open_project control_flit_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
read_sdc [file normalize clock.sdc]
update_timing
check_timing -file reopened_check.timing
report_timing_summary -ep_num 12 -path_num 2 -file reopened.timing
close_project
puts CONTROL_FLIT_PROBE_REOPENED
exit 0
'''
        (work / 'synth.tcl').write_text(tcl)
        (work / 'clock.sdc').write_text('create_clock -name SOURCE -period 7.502 [get_ports source_clk]\ncreate_clock -name SINK -period 8.000 [get_ports sink_clk]\nset_clock_groups -asynchronous -group [get_clocks SOURCE] -group [get_clocks SINK]\n')
        dependency_files = list((ipc.parent).rglob('*'))
        files = [*files, *(p for p in dependency_files if p.is_file()), work/'synth.tcl', work/'clock.sdc', Path(__file__)]
        frozen = {str(p):sha(p) for p in files}
        cmd = [sys.executable, '-B', str(REPO/'tools/run_td.py'), str(work/'synth.tcl'), '--td-root', args.td_root, '--workdir', str(work), '--log', str(work/'td.log')]
        start = time.monotonic()
        expired = False
        with (work/'launcher.log').open('wb') as log:
            proc = subprocess.Popen(cmd, cwd=REPO, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                code = proc.wait(timeout=150)
            except subprocess.TimeoutExpired:
                expired = True
                subprocess.run(['taskkill.exe','/PID',str(proc.pid),'/T','/F'], stdout=log, stderr=subprocess.STDOUT, timeout=5)
                code = proc.wait(timeout=5)
        native = work/'control_flit_probe_Runs/syn_1'
        logtext = (work/'td.log').read_text(errors='replace') if (work/'td.log').exists() else ''
        passed = code == 0 and not expired and 'CONTROL_FLIT_PROBE_REOPENED' in logtext and (native/'.opt_gate.end.f').exists() and not list(native.glob('.*.error.f')) and (work/'reopened.area').exists() and all(sha(Path(p))==h for p,h in frozen.items())
        record = dict(arm=arm,width=args.width,status='PASS' if passed else 'FAIL',elapsed_s=round(time.monotonic()-start,3),timeout=expired,exit=code,command=cmd,inputs=frozen)
        (work/'RESULT.json').write_text(json.dumps(record,indent=2)+'\n')
        results.append(record)
        print(json.dumps({k:v for k,v in record.items() if k not in ('inputs','command')}),flush=True)
        (runs/'RESULTS.json').write_text(json.dumps(results,indent=2)+'\n')
    return 0 if all(x['status']=='PASS' for x in results) else 1

if __name__ == '__main__':
    raise SystemExit(main())
