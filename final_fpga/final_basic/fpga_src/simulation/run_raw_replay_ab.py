"""Focused cycle miter against the R2 RAW replay, including held abort data."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

BASELINE = '14df01dcce'
BASELINE_FILE = 'refactor/dual_lane_s1/src_fpga/rtl/raw10_frame_replay.v'

BENCH = r'''
`timescale 1ns/1ps
module replay_case #(parameter W=68,H=4,ID=0)(output reg done=0);
    localparam BYTES=W*H/4*5;
    reg clk=0;always #4 clk=~clk;
    reg rst=0,start=0,valid=0,last=0,ready=1;
    reg [15:0] width=W,height=H,keep=0;
    reg [127:0] data=0;
    wire dr,rr,dv,rv,ds,rs,de,re,da,ra,dd,rd;
    wire [39:0] dp,rp;
    raw10_frame_replay dut(.i_clk(clk),.i_rst_n(rst),.i_start(start),
        .i_width(width),.i_height(height),.i_axis_tdata(data),.i_axis_tkeep(keep),
        .i_axis_tvalid(valid),.o_axis_tready(dr),.i_axis_tlast(last),
        .o_data(dp),.o_valid(dv),.i_ready(ready),.o_sof(ds),.o_eol(de),.o_abort(da),.o_done(dd));
    raw10_frame_replay_baseline ref_dut(.i_clk(clk),.i_rst_n(rst),.i_start(start),
        .i_width(width),.i_height(height),.i_axis_tdata(data),.i_axis_tkeep(keep),
        .i_axis_tvalid(valid),.o_axis_tready(rr),.i_axis_tlast(last),
        .o_data(rp),.o_valid(rv),.i_ready(ready),.o_sof(rs),.o_eol(re),.o_abort(ra),.o_done(rd));
    integer checks=0,words=0,groups=0,completions=0,aborts=0,stalls=0,resets=0;
    integer n,seq,offset,amount,lane,step,mode;
    reg fire,held=0;reg [41:0] held_data;
    reg [5:0] phases=0;
    reg [31:0] rng=32'h591a0ca1+ID;
    task randomize;
        begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);end
    endtask
    task check;
        begin
            checks=checks+1;
            if({dr,dv,ds,de,da,dd} !== {rr,rv,rs,re,ra,rd})
                $fatal(1,"replay control mismatch case=%0d check=%0d state=%0d ref=%0d",ID,checks,dut.state,ref_dut.state);
            if(dv && dp!==rp)$fatal(1,"replay data mismatch case=%0d check=%0d actual=%h ref=%h",ID,checks,dp,rp);
        end
    endtask
    task cycle;
        begin
            #1;check();
            if(valid&&dr)begin words=words+1;phases[dut.bytes_after_pop]=1;end
            if(dv&&ready)groups=groups+1;
            @(posedge clk);#1;check();
            if(rst&&held&&!ready&&(!dv||{ds,de,dp}!==held_data))
                $fatal(1,"replay stalled group changed case=%0d check=%0d",ID,checks);
            held=rst&&dv&&!ready;held_data={ds,de,dp};
            if(held)stalls=stalls+1;
            if(dd)completions=completions+1;
            if(da)aborts=aborts+1;
            @(negedge clk);
        end
    endtask
    task reset_now;
        begin
            rst=0;held=0;resets=resets+1;valid=0;start=0;ready=1;
            cycle();cycle();rst=1;cycle();
        end
    endtask
    task frame(input integer frame_id,input integer fault_mode);
        begin
            reset_now();width=W;height=H;start=1;cycle();start=0;offset=0;
            for(step=0;step<BYTES*3+60;step=step+1)begin
                randomize();valid=offset<BYTES;
                // Continuous source for even frames; random finite bubbles otherwise.
                if(frame_id[0]&&rng[2:0]==0)valid=0;
                ready=frame_id[0]?(rng[0]|rng[1]):1;
                if(offset>=BYTES&&dut.emitted_groups==W*H/4-1&&step%9<5)ready=0;
                amount=BYTES-offset>=16?16:BYTES-offset;
                keep=amount>=16?16'hffff:(16'hffff>>(16-amount));
                last=offset+16>=BYTES;
                for(lane=0;lane<16;lane=lane+1)data[lane*8+:8]=(frame_id*17+offset+lane)&255;
                if(offset==0&&fault_mode==1)keep=keep^1;
                if(offset==0&&fault_mode==2)last=!last;
                // Invalid input while a native group is stalled must retain that group.
                if(fault_mode==3&&step==3)begin start=1;ready=0;end
                else start=0;
                #1;fire=valid&&dr;cycle();if(fire)offset=offset+amount;
                if(dd||da)begin valid=0;start=0;ready=1;repeat(3)cycle();step=BYTES*3+60;end
            end
            if(dut.state!=0)$fatal(1,"replay frame failed to retire case=%0d mode=%0d",ID,fault_mode);
            valid=0;ready=1;repeat(3)cycle();
        end
    endtask
    initial begin
        reset_now();
        for(seq=0;seq<12;seq=seq+1)frame(seq,0);
        if(completions!=12)$fatal(1,"missing legal replay completion case=%0d count=%0d",ID,completions);
        frame(21,1);frame(23,2);frame(25,3);
        // Exercise arbitrary malformed words, repeated START and finite stalls.
        for(n=0;n<14000;n=n+1)begin
            randomize();valid=rng[0]|rng[1];ready=rng[2]|rng[3];start=rng[9:4]==0;
            data={rng,~rng,rng,~rng};keep=rng[10]?16'hffff:rng[31:16];last=rng[11];
            width=rng[12]?W:4;height=rng[13]?H:1;
            if(n%337==0)begin rst=0;held=0;resets=resets+1;end else rst=1;
            cycle();
        end
        frame(31,0);
        if(stalls==0||aborts<2||words<12||groups<12)$fatal(1,"missing replay coverage case=%0d",ID);
        if(ID==0&&phases!=6'b111111)$fatal(1,"missing append phases %b",phases);
        $display("RAW_REPLAY_AB_PASS case=%0d checks=%0d words=%0d groups=%0d done=%0d abort=%0d stalls=%0d resets=%0d phases=%b",
            ID,checks,words,groups,completions,aborts,stalls,resets,phases);
        done=1;
    end
endmodule
module tb_raw_replay_ab;
    wire a,b,c;
    replay_case #(.W(68),.H(4),.ID(0)) full_phases(a);
    replay_case #(.W(4),.H(1),.ID(1)) single_group(b);
    replay_case #(.W(20),.H(2),.ID(2)) short_tail(c);
    initial begin wait(a&&b&&c);$display("RESULT: PASS RAW replay 14df cycle equivalence");$finish;end
    initial begin #5000000;$fatal(1,"watchdog");end
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
    run = project/'tmp/raw_replay_ab'/args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl = project/'src_fpga/rtl/raw10_frame_replay.v'
    baseline = subprocess.run(['git', 'show', BASELINE+':'+BASELINE_FILE], cwd=repo,
                              check=True, capture_output=True).stdout
    baseline_path = run/'raw10_frame_replay_baseline.v'
    baseline_path.write_bytes(baseline.replace(b'module raw10_frame_replay (',
                                             b'module raw10_frame_replay_baseline (', 1))
    bench = run/'tb_raw_replay_ab.sv'
    bench.write_text(BENCH)
    sources = [rtl, baseline_path, bench]
    identity = [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]
    (run/'sources.json').write_text(json.dumps({'baseline_commit': BASELINE,
        'baseline_sha256': hashlib.sha256(baseline).hexdigest(), 'sources': identity}, indent=2)+'\n')
    commands = [['vmap.exe', '-c'], ['vlib.exe', 'work'],
        ['vlog.exe', '-sv', '-work', 'work', '-l', 'compile.log']+list(map(str,sources)),
        ['vsim.exe', '-c', 'work.tb_raw_replay_ab', '-l', 'run.log', '-do', 'run -all;quit -f']]
    for index, command in enumerate(commands):
        result = subprocess.run([str(args.modelsim_bin/command[0])]+command[1:], cwd=run,
                                text=True, capture_output=True, errors='replace')
        (run/f'{index}.console.log').write_text(result.stdout+result.stderr)
        if result.returncode:
            raise RuntimeError(command[0]+' failed: '+result.stdout+result.stderr)
    log = (run/'run.log').read_text(errors='replace')
    if 'RESULT: PASS RAW replay 14df cycle equivalence' not in log or re.search(r'\*\* (Error|Fatal|Warning):', log):
        raise RuntimeError('RAW replay check failed: '+log)
    print('\n'.join(x for x in log.splitlines() if 'PASS' in x))


if __name__ == '__main__':
    main()
