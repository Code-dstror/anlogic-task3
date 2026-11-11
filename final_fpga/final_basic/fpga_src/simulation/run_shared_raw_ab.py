"""R2 shared two-member decoder cycle miter, bounded stalls and aborts."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

BASELINE = '14df01dcce'
BASELINE_FILE = 'refactor/dual_lane_s1/src_fpga/rtl/shared_raw10_decoder.v'
BENCH = r'''
`timescale 1ns/1ps
module tb_shared_raw_ab;
    localparam GROUPS=68,BYTES=GROUPS*5;
    reg clk=0;always #4 clk=~clk;
    reg rst=0,start=0,member=0,valid=0,last=0,ready=1;
    reg [1:0] abort_request=0;
    reg [31:0] total_bytes=BYTES,total_groups=GROUPS;
    reg [15:0] keep=0;reg [127:0] data=0;
    wire dr,rr,dm,rm,dv,rv;wire [39:0] dp,rp;wire [1:0] dd,rd,da,ra;
    shared_raw10_decoder dut(.i_clk(clk),.i_rst_n(rst),.i_start(start),
        .i_total_bytes(total_bytes),.i_total_groups(total_groups),.i_abort(abort_request),
        .i_axis_member(member),.i_axis_data(data),.i_axis_keep(keep),.i_axis_valid(valid),.i_axis_last(last),
        .o_axis_ready(dr),.o_member(dm),.o_data(dp),.o_valid(dv),.i_ready(ready),.o_done(dd),.o_abort(da));
    shared_raw10_decoder_baseline ref_dut(.i_clk(clk),.i_rst_n(rst),.i_start(start),
        .i_total_bytes(total_bytes),.i_total_groups(total_groups),.i_abort(abort_request),
        .i_axis_member(member),.i_axis_data(data),.i_axis_keep(keep),.i_axis_valid(valid),.i_axis_last(last),
        .o_axis_ready(rr),.o_member(rm),.o_data(rp),.o_valid(rv),.i_ready(ready),.o_done(rd),.o_abort(ra));
    integer checks=0,words=0,groups=0,completions=0,aborts=0,stalls=0,resets=0;
    integer n,seq,amount,lane,step,offset0,offset1,offset;
    reg fire,held=0;reg [40:0] held_data;
    reg [5:0] phases=0;reg [1:0] done_mask=0;
    reg [31:0] rng=32'hb831cad1;
    task randomize;
        begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);end
    endtask
    task check;
        begin
            checks=checks+1;
            if({dr,dm,dv,dd,da} !== {rr,rm,rv,rd,ra})
                $fatal(1,"shared decoder control mismatch check=%0d states=%0d/%0d",checks,dut.state_long,dut.state_short);
            if(dv && dp!==rp)$fatal(1,"shared decoder data mismatch check=%0d actual=%h ref=%h",checks,dp,rp);
        end
    endtask
    task cycle;
        begin
            #1;check();
            if(valid&&dr)begin words=words+1;phases[dut.after_pop]=1;end
            if(dv&&ready)groups=groups+1;
            @(posedge clk);#1;check();
            if(rst&&held&&!ready&&(!dv||{dm,dp}!==held_data))
                $fatal(1,"shared decoder stalled group changed check=%0d",checks);
            held=rst&&dv&&!ready;held_data={dm,dp};
            if(held)stalls=stalls+1;
            completions=completions+dd[0]+dd[1];aborts=aborts+da[0]+da[1];done_mask=done_mask|dd;
            @(negedge clk);
        end
    endtask
    task reset_now;
        begin
            rst=0;held=0;resets=resets+1;valid=0;start=0;ready=1;abort_request=0;
            cycle();cycle();rst=1;cycle();
        end
    endtask
    task pair(input integer frame_id,input integer fault_mode);
        begin
            reset_now();total_bytes=BYTES;total_groups=GROUPS;start=1;cycle();start=0;
            offset0=0;offset1=0;done_mask=0;
            for(step=0;step<BYTES*6+100;step=step+1)begin
                randomize();member=rng[2];
                if(offset0>=BYTES)member=1;if(offset1>=BYTES)member=0;
                offset=member?offset1:offset0;valid=offset<BYTES;
                if(frame_id[0]&&rng[6:4]==0)valid=0;
                ready=frame_id[0]?(rng[0]|rng[1]):1;
                amount=BYTES-offset>=16?16:BYTES-offset;
                keep=amount>=16?16'hffff:(16'hffff>>(16-amount));last=offset+16>=BYTES;
                for(lane=0;lane<16;lane=lane+1)data[lane*8+:8]=(frame_id*17+member*71+offset+lane)&255;
                if(fault_mode==1&&!member&&offset==0)keep=keep^1;
                if(fault_mode==2&&step==6)begin ready=0;abort_request=3;end
                else abort_request=0;
                #1;fire=valid&&dr;cycle();
                if(fire)begin if(member)offset1=offset1+amount;else offset0=offset0+amount;end
                if(dut.state_long==0&&dut.state_short==0)begin
                    if(fault_mode==0&&done_mask!=3)$fatal(1,"missing shared good terminal");
                    valid=0;ready=1;repeat(3)cycle();step=BYTES*6+100;
                end
            end
            if(dut.state_long!=0||dut.state_short!=0)$fatal(1,"shared pair did not retire");
            valid=0;ready=1;repeat(3)cycle();
        end
    endtask
    initial begin
        reset_now();
        for(seq=0;seq<12;seq=seq+1)pair(seq,0);
        if(completions!=24)$fatal(1,"missing shared legal completions count=%0d",completions);
        pair(21,1);pair(23,2);
        for(n=0;n<16000;n=n+1)begin
            randomize();valid=rng[0]|rng[1];ready=rng[2]|rng[3];start=rng[9:4]==0;
            member=rng[10];data={rng,~rng,rng,~rng};keep=rng[11]?16'hffff:rng[31:16];last=rng[12];
            abort_request=rng[18:13]==0?rng[20:19]:0;
            total_bytes=rng[21]?BYTES:5;total_groups=rng[21]?GROUPS:1;
            if(n%337==0)begin rst=0;held=0;resets=resets+1;end else rst=1;
            cycle();
        end
        pair(31,0);
        if(stalls==0||aborts<2||words<12||groups<12||phases!=6'b111111)$fatal(1,"missing shared coverage phases=%b",phases);
        $display("SHARED_RAW_AB_PASS checks=%0d words=%0d groups=%0d done=%0d abort=%0d stalls=%0d resets=%0d phases=%b",
            checks,words,groups,completions,aborts,stalls,resets,phases);
        $display("RESULT: PASS shared RAW decoder 14df cycle equivalence");$finish;
    end
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
    run = project/'tmp/shared_raw_ab'/args.name
    run.mkdir(parents=True, exist_ok=False)
    rtl = project/'src_fpga/rtl/shared_raw10_decoder.v'
    baseline = subprocess.run(['git', 'show', BASELINE+':'+BASELINE_FILE], cwd=repo,
                              check=True, capture_output=True).stdout
    baseline_path = run/'shared_raw10_decoder_baseline.v'
    baseline_path.write_bytes(baseline.replace(b'module shared_raw10_decoder (',
                                             b'module shared_raw10_decoder_baseline (', 1))
    bench = run/'tb_shared_raw_ab.sv'
    bench.write_text(BENCH)
    sources = [rtl, baseline_path, bench]
    identity = [{'path': str(p), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]
    (run/'sources.json').write_text(json.dumps({'baseline_commit': BASELINE,
        'baseline_sha256': hashlib.sha256(baseline).hexdigest(), 'sources': identity}, indent=2)+'\n')
    commands = [['vmap.exe', '-c'], ['vlib.exe', 'work'],
        ['vlog.exe', '-sv', '-work', 'work', '-l', 'compile.log']+list(map(str,sources)),
        ['vsim.exe', '-c', 'work.tb_shared_raw_ab', '-l', 'run.log', '-do', 'run -all;quit -f']]
    for index, command in enumerate(commands):
        result = subprocess.run([str(args.modelsim_bin/command[0])]+command[1:], cwd=run,
                                text=True, capture_output=True, errors='replace')
        (run/f'{index}.console.log').write_text(result.stdout+result.stderr)
        if result.returncode:
            raise RuntimeError(command[0]+' failed: '+result.stdout+result.stderr)
    log = (run/'run.log').read_text(errors='replace')
    if 'RESULT: PASS shared RAW decoder 14df cycle equivalence' not in log or re.search(r'\*\* (Error|Fatal|Warning):', log):
        raise RuntimeError('shared RAW decoder check failed: '+log)
    print('\n'.join(x for x in log.splitlines() if 'PASS' in x))


if __name__ == '__main__':
    main()
