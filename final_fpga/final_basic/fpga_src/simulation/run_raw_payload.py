"""Cycle-by-cycle RAW token equivalence against the fixed R2 14df source."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess


BASELINE = '14df01dcce'
BASELINE_FILE = 'refactor/dual_lane_s1/src_fpga/rtl/shared_raw10_frame_ingress.v'

BENCH = r'''
`timescale 1ns/1ps
module raw_payload_case #(parameter W=24,H=3,C=1,P=1,S=1,ID=0)(output reg done=0);
    localparam GROUPS=W/4;
    reg i_clk=0;
    always #4 i_clk=~i_clk;
__DECLARATIONS__
    integer checks=0, transfers=0, starts=0, contexts=0, data_tokens=0, ends=0, aborts=0;
    integer stalls=0, resets=0, n, g, seq, random_seed;
    reg [31:0] rng=32'h7a031109+ID;
    reg held=0;
    reg [146:0] held_word;
    shared_raw10_frame_ingress #(.WIDTH(W),.HEIGHT(H),.CONTEXT_ENABLE(C),
        .EXTERNAL_SEQUENCE_ENABLE(1),.PAIR_METADATA_ENABLE(P),.SOURCE_TERMINAL_ENABLE(S)) dut(
__DUT_PORTS__);
    shared_raw10_frame_ingress_baseline #(.WIDTH(W),.HEIGHT(H),.CONTEXT_ENABLE(C),
        .EXTERNAL_SEQUENCE_ENABLE(1),.PAIR_METADATA_ENABLE(P),.SOURCE_TERMINAL_ENABLE(S)) ref_dut(
__REF_PORTS__);
    task cycle;
        begin
            @(posedge i_clk); #1;
            checks=checks+1;
            if ({__CONTROL_DUT__} !== {__CONTROL_REF__})
                $fatal(1,"control mismatch case=%0d cycle=%0d state=%0d ref=%0d",ID,checks,dut.state,ref_dut.state);
            if (dut_o_axis_tvalid &&
                {dut_o_axis_tdata,dut_o_axis_tkeep,dut_o_axis_tlast,dut_o_axis_tuser} !==
                {ref_o_axis_tdata,ref_o_axis_tkeep,ref_o_axis_tlast,ref_o_axis_tuser})
                $fatal(1,"payload mismatch case=%0d cycle=%0d state=%0d raw=%b actual=%h ref=%h",ID,checks,dut.state,i_valid,
                    {dut_o_axis_tuser,dut_o_axis_tkeep,dut_o_axis_tlast,dut_o_axis_tdata},
                    {ref_o_axis_tuser,ref_o_axis_tkeep,ref_o_axis_tlast,ref_o_axis_tdata});
            if (i_rst_n && held && !i_axis_tready && (!dut_o_axis_tvalid ||
                {dut_o_axis_tuser,dut_o_axis_tlast,dut_o_axis_tkeep,dut_o_axis_tdata} !== held_word))
                $fatal(1,"stalled payload changed case=%0d cycle=%0d",ID,checks);
            held=i_rst_n && dut_o_axis_tvalid && !i_axis_tready;
            held_word={dut_o_axis_tuser,dut_o_axis_tlast,dut_o_axis_tkeep,dut_o_axis_tdata};
            if (held) stalls=stalls+1;
            if (dut_o_axis_tvalid && i_axis_tready && i_rst_n) begin
                transfers=transfers+1;
                case(dut_o_axis_tuser)
                    0:data_tokens=data_tokens+1;
                    1:if(dut_o_axis_tlast)contexts=contexts+1;else starts=starts+1;
                    2:ends=ends+1;
                    3:aborts=aborts+1;
                endcase
            end
            @(negedge i_clk);
        end
    endtask
    task clear_input;
        begin
__INITIALIZE__
            i_accept=1;i_axis_tready=1;i_enable=1;
            i_session_id=23;i_epoch=5;i_metadata_valid=1;i_bayer_valid=1;i_time_valid=1;
            i_source_qualified=1;i_source_ok=1;i_source_session=23;i_source_epoch=5;
        end
    endtask
    task reset_now;
        begin
            i_rst_n=0; held=0;resets=resets+1;#1;
            if(dut_o_axis_tvalid || ref_o_axis_tvalid)$fatal(1,"async reset did not revoke token");
            repeat(3)cycle();i_rst_n=1;repeat(2)cycle();
        end
    endtask
    task settle;
        begin i_valid=0;i_sof=0;i_eol=0;i_abort=0;i_source_valid=0;i_axis_tready=1;repeat(30)cycle();end
    endtask
    task source_result(input integer sequence_id,input bit bad);
        begin
            i_valid=0;i_sof=0;i_eol=0;
            i_source_valid=1;i_source_sequence=sequence_id;i_source_ok=!bad;i_source_error=bad?8'h80:0;
            cycle();i_source_valid=0;i_source_error=0;i_source_ok=1;
        end
    endtask
    task frame_pixels(input integer sequence_id,input bit bad_geometry);
        begin
            i_external_sequence=sequence_id;
            for(g=0;g<GROUPS*H;g=g+1)begin
                i_valid=1;i_sof=g==0;i_eol=(g%GROUPS)==GROUPS-1;
                if(bad_geometry && g==1)i_eol=!i_eol;
                i_data=40'hcab0123400+g+sequence_id;
                i_timestamp=64'h1234567890+sequence_id;i_gain=sequence_id+7;
                cycle();
            end
            i_valid=0;i_sof=0;i_eol=0;
        end
    endtask
    initial begin
        clear_input();reset_now();
        // Continuous legal RAW, every metadata token, partial tail and SOURCE.
        for(seq=1;seq<=8;seq=seq+1)begin
            frame_pixels(seq,0);source_result(seq,0);settle();
        end
        if(ends<8 || data_tokens<1 || starts<8 || (C && contexts<8))
            $fatal(1,"missing legal token coverage case=%0d start=%0d ctx=%0d data=%0d end=%0d",ID,starts,contexts,data_tokens,ends);
        // SOURCE mismatch is stale, never a completion; a true error aborts.
        frame_pixels(20,0);source_result(19,0);source_result(20,1);settle();
        frame_pixels(21,1);source_result(21,0);settle();
        // Stall a presented token, then revoke ownership with async reset.
        i_axis_tready=0;i_external_sequence=30;i_valid=1;i_sof=1;i_eol=GROUPS==1;
        i_data=40'h0504030201;cycle();i_valid=0;i_sof=0;i_eol=0;
        repeat(5)cycle();reset_now();settle();
        // Finite stalls during terminal waiting and late successful SOURCE.
        frame_pixels(31,0);repeat(10)cycle();
        i_axis_tready=0;source_result(31,0);repeat(6)cycle();
        i_axis_tready=1;settle();
        // Arbitrary errors, finite backpressure, new SOFs and resets: compare
        // every control cycle and every valid token, including both stalls.
        for(n=0;n<12000;n=n+1)begin
            rng=rng ^ (rng<<13);rng=rng ^ (rng>>17);rng=rng ^ (rng<<5);
            i_valid=rng[0];i_accept=rng[1]|rng[2];i_sof=rng[5:3]==0;
            i_eol=rng[8:6]==0;i_abort=rng[13:9]==0;i_enable=rng[16:14]!=0;
            i_axis_tready=rng[17]|rng[18];i_data={rng,rng[7:0]};
            i_source_valid=rng[22:19]==0;i_source_ok=rng[23];i_source_error=rng[24]?0:1;
            i_source_sequence=rng[25]?i_external_sequence:rng;
            i_external_sequence=rng[31:26];i_sdr_profile=rng[10];
            i_timestamp={rng,rng};i_actual_exposure=rng;i_gain=~rng;
            i_calibration_id=rng;i_exposure_group=~rng;i_exposure_role=rng[1:0];
            if(n%379==0)begin i_rst_n=0;held=0;resets=resets+1;end
            else i_rst_n=1;
            cycle();
        end
        clear_input();reset_now();frame_pixels(88,0);source_result(88,0);settle();
        if(stalls==0 || resets<2 || (S && aborts==0))$fatal(1,"missing reset/stall/error coverage");
        $display("RAW_PAYLOAD_PASS case=%0d cycles=%0d transfers=%0d starts=%0d context=%0d data=%0d end=%0d abort=%0d stalls=%0d resets=%0d",
            ID,checks,transfers,starts,contexts,data_tokens,ends,aborts,stalls,resets);
        done=1;
    end
endmodule
module tb_raw_payload;
    wire a,b,c;
    raw_payload_case #(.W(24),.H(3),.C(1),.P(1),.S(1),.ID(0)) production(a);
    raw_payload_case #(.W(4),.H(1),.C(1),.P(0),.S(0),.ID(1)) single_group(b);
    raw_payload_case #(.W(20),.H(2),.C(0),.P(0),.S(0),.ID(2)) no_context(c);
    initial begin wait(a&&b&&c);$display("RESULT: PASS RAW payload cycle equivalence");$finish;end
    initial begin #2000000;$fatal(1,"watchdog");end
endmodule
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--name', required=True)
    ap.add_argument('--modelsim-bin', type=Path, required=True)
    args = ap.parse_args()
    if not re.fullmatch('[a-z0-9_]+', args.name):
        ap.error('unsafe name')
    here = Path(__file__).resolve().parent
    project, repo = here.parents[1], here.parents[3]
    run = project/'tmp/raw_payload'/args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl = project/'src_fpga/rtl'
    baseline = subprocess.run(['git', 'show', BASELINE+':'+BASELINE_FILE], cwd=repo,
                              check=True, capture_output=True).stdout
    baseline_path = run/'shared_raw10_frame_ingress_baseline.v'
    baseline_path.write_bytes(baseline.replace(b'module shared_raw10_frame_ingress #(',
                                             b'module shared_raw10_frame_ingress_baseline #(', 1))
    ports = []
    header = re.sub(r'//[^\n]*', '', baseline.decode().split('    localparam', 1)[0])
    for line in header.splitlines():
        match = re.match(r'\s*(input|output)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(.*)', line)
        if match:
            direction, width, names = match.groups()
            for name in re.findall(r'\b[io]_\w+', names):
                ports.append((direction, width or '', name))
    assert len(ports) == 45, len(ports)
    inputs = [(width, name) for direction, width, name in ports if direction == 'input']
    outputs = [(width, name) for direction, width, name in ports if direction == 'output']
    declarations = [f'    reg {width} {name};' for width, name in inputs if name != 'i_clk']
    declarations += [f'    wire {width} {prefix}_{name};' for width, name in outputs for prefix in ['dut', 'ref']]
    controls = [name for _, name in outputs if name not in ['o_axis_tdata','o_axis_tkeep','o_axis_tlast','o_axis_tuser']]
    bench = BENCH.replace('__DECLARATIONS__', '\n'.join(declarations))
    for prefix in ['dut', 'ref']:
        connections = [f'        .{name}({name if direction == "input" else prefix+"_"+name})'
                       for direction, _, name in ports]
        bench = bench.replace('__'+prefix.upper()+'_PORTS__', ',\n'.join(connections))
        bench = bench.replace('__CONTROL_'+prefix.upper()+'__', ','.join(prefix+'_'+x for x in controls))
    bench = bench.replace('__INITIALIZE__', '\n'.join(f'            {name}=0;' for _, name in inputs if name != 'i_clk'))
    (run/'tb_raw_payload.sv').write_text(bench)
    sources = [rtl/'raw10_append5.v', rtl/'shared_raw10_frame_ingress.v', baseline_path, run/'tb_raw_payload.sv']
    identity = [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]
    (run/'sources.json').write_text(json.dumps({'baseline_commit':BASELINE,
        'baseline_sha256':hashlib.sha256(baseline).hexdigest(),'sources':identity}, indent=2)+'\n')
    commands = [['vmap.exe','-c'], ['vlib.exe','work'],
        ['vlog.exe','-sv','-work','work','-l','compile.log']+list(map(str,sources)),
        ['vsim.exe','-c','work.tb_raw_payload','-l','run.log','-do','run -all;quit -f']]
    for index, command in enumerate(commands):
        result = subprocess.run([str(args.modelsim_bin/command[0])]+command[1:], cwd=run,
                                text=True, capture_output=True, errors='replace')
        (run/f'{index}.console.log').write_text(result.stdout+result.stderr)
        if result.returncode:
            raise RuntimeError(command[0]+' failed: '+result.stdout+result.stderr)
    log=(run/'run.log').read_text(errors='replace')
    if 'RESULT: PASS RAW payload cycle equivalence' not in log or re.search(r'\*\* (Error|Fatal|Warning):', log):
        raise RuntimeError('RAW payload check failed: '+log)
    print('\n'.join(x for x in log.splitlines() if 'PASS' in x))


if __name__ == '__main__':
    main()
