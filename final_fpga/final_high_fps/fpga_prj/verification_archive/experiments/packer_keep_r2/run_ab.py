"""Bounded mapping of exactly equivalent AXIS byte-valid decode."""
import argparse, hashlib, json, subprocess, sys, time
from pathlib import Path

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
REPO=PROJECT.parents[1]

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--name',required=True)
    ap.add_argument('--td-root',required=True)
    a=ap.parse_args()
    if not a.name.replace('_','').isalnum(): ap.error('Use an ASCII run label')
    original=(PROJECT/'src_fpga/rtl/jpeg_byte_packer.v').read_bytes().decode('utf-8')
    start=original.index('    assign o_axis_tkeep  =')
    end=original.index(';',start)+1
    replacement='''    // Byte n is valid exactly when more than n bytes are owned.
    genvar keep_byte;
    generate for (keep_byte=0; keep_byte<16; keep_byte=keep_byte+1) begin:g_keep
        assign o_axis_tkeep[keep_byte] = byte_count > keep_byte;
    end endgenerate'''
    candidate=original[:start]+replacement+original[end:]
    # All 32 possible public count encodings preserve the original full/default mask.
    for n in range(32):
        old=(1<<n)-1 if n<16 else 65535
        new=sum((n>b)<<b for b in range(16))
        assert old==new
    wrapper='''module packer_probe(input wire clk,rst_n,abort,valid,last,ready,
    input wire [7:0] data,output reg [27:0] observe);
    reg [12:0] stimulus;
    wire [127:0] packed_data; wire [15:0] keep;
    wire in_ready,out_valid,out_last,frame_error,overflow,idle;
    wire [7:0] folded;
    genvar b,k;
    generate for(b=0;b<8;b=b+1)begin:fold
        wire [15:0] terms;
        for(k=0;k<16;k=k+1)begin:t
            assign terms[k]=packed_data[k*8+b];
        end
        assign folded[b]=^terms;
    end endgenerate
    always @(posedge clk) begin
        stimulus<={rst_n,abort,valid,last,ready,data};
        observe<={idle,frame_error|overflow,in_ready,out_valid,out_last,keep,folded[6:0]};
    end
    jpeg_byte_packer dut(.i_clk(clk),.i_rst_n(stimulus[12]),.i_abort(stimulus[11]),
        .i_valid(stimulus[10]),.i_last(stimulus[9]),.i_axis_tready(stimulus[8]),.i_byte(stimulus[7:0]),
        .o_ready(in_ready),.o_axis_tdata(packed_data),.o_axis_tkeep(keep),.o_axis_tvalid(out_valid),
        .o_axis_tlast(out_last),.o_frame_error(frame_error),.o_overflow(overflow),.o_idle(idle));
endmodule
'''
    # Include every output byte bit; identical wrapper in both arms.
    wrapper=wrapper.replace('[27:0] observe','[28:0] observe').replace('folded[6:0]','folded')
    root=PROJECT/'tmp/packer_keep_r2'/a.name;root.mkdir(parents=True,exist_ok=False)
    summary=[]
    for label,source in [('baseline',original),('threshold',candidate)]:
        arm=HERE/label;arm.mkdir(exist_ok=True)
        frozen=arm/'jpeg_byte_packer.v'
        if frozen.exists() and frozen.read_bytes()!=source.encode('utf-8'): raise RuntimeError('Refuse changed candidate')
        frozen.write_bytes(source.encode('utf-8'))
        work=root/label;work.mkdir()
        (work/'jpeg_byte_packer.v').write_bytes(frozen.read_bytes())
        (work/'packer_probe.v').write_text(wrapper)
        (work/'clock.sdc').write_text('create_clock -name PIX -period 8.000 [get_ports clk]\n')
        tcl='''import_device ph1_90.db -package PH1A90SEG324 -speed 2
create_project packer_probe . -family ph1 -device PH1A90SEG324 -speed -2
add_files jpeg_byte_packer.v
add_files packer_probe.v
add_files clock.sdc
top_module packer_probe
set_param -run syn_1 flow thread 4
set_param -run syn_1 rtl min_control_set 2
set_param -run syn_1 gate map_mode area_prior
set_param -run syn_1 gate multi_thread_mapping partition
set_param -run syn_1 gate add_map_lut_struct on
launch_runs -step opt_gate syn_1
wait_run syn_1
if {![file exists packer_probe_Runs/syn_1/.opt_gate.end.f] || [llength [glob -nocomplain packer_probe_Runs/syn_1/.*.error.f]]} {error "Native stage failed"}
close_project
open_project packer_probe.al -noanalyze
open_run syn_1
report_area -file reopened.area
report_run_param syn_1 -file effective.params
read_sdc [file normalize clock.sdc]
update_timing
check_timing -file checked.timing
report_timing_summary -ep_num 12 -path_num 2 -file reopened.timing
report_timing_path -from [get_regs -nowarn {dut/byte_count*}] -ep_num 12 -path_num 2 -file count.timing
report_timing_path -from [get_regs -nowarn {stimulus*}] -to [get_regs -nowarn {dut/*}] -ep_num 12 -path_num 2 -file input.timing
close_project
puts PACKER_KEEP_NATIVE_PASS
exit 0
'''
        (work/'synth.tcl').write_text(tcl)
        inputs={str(p):sha(p) for p in (frozen,work/'jpeg_byte_packer.v',work/'packer_probe.v',work/'clock.sdc',work/'synth.tcl',Path(__file__))}
        cmd=[sys.executable,'-B',str(REPO/'tools/run_td.py'),str(work/'synth.tcl'),'--td-root',a.td_root,'--workdir',str(work),'--log',str(work/'td.log')]
        begun=time.monotonic();expired=False
        with (work/'launcher.log').open('wb') as log:
            p=subprocess.Popen(cmd,cwd=REPO,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            try: code=p.wait(timeout=90)
            except subprocess.TimeoutExpired:
                expired=True
                subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],stdout=log,stderr=subprocess.STDOUT,timeout=5)
                code=p.wait(timeout=5)
        good=code==0 and not expired and (work/'reopened.area').exists() and 'PACKER_KEEP_NATIVE_PASS' in (work/'td.log').read_text(errors='replace') and all(sha(Path(p))==h for p,h in inputs.items())
        result=dict(variant=label,status='PASS' if good else 'FAIL',exit_code=code,elapsed_s=round(time.monotonic()-begun,3),wall_limit_s=90,command=cmd,inputs=inputs)
        (work/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
        summary.append(result)
        (root/'RESULTS.json').write_text(json.dumps(summary,indent=2)+'\n')
        print(json.dumps({k:v for k,v in result.items() if k not in ('inputs','command')}),flush=True)
    return 0 if all(x['status']=='PASS' for x in summary) else 1

if __name__=='__main__': raise SystemExit(main())
