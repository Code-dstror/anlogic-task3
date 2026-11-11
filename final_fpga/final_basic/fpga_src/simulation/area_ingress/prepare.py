"""Create immutable fixed-source ingress reference and parameterized A/B bench."""
from pathlib import Path
import subprocess, hashlib, json, re
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
def fixed(commit,path):return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)
reference=fixed('ed50d4e753','refactor/hdr_lane_sparse/src_fpga/rtl/shared_raw10_frame_ingress.v')
p=HERE/'baseline/shared_raw10_frame_ingress.v';p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(reference)
(p.parent/'MANIFEST.json').write_text(json.dumps({'commit':'ed50d4e7534b1574213d173e941dbfbcfdf20351','path':'refactor/hdr_lane_sparse/src_fpga/rtl/shared_raw10_frame_ingress.v','sha256':hashlib.sha256(reference).hexdigest()},indent=2)+'\n')
# Reuse the donor's independent scalar RAW10 byte oracle and token/control
# comparator, with dimensions/compile profiles exposed as actual parameters.
t=fixed('6effdfaef6','refactor/dual_basic/src_fpga/simulation/raw10_packing/tb_ingress_equivalence.sv').decode().replace('\r\n','\n')
t=t.replace('module tb_ingress_equivalence;\n    localparam W=68,H=5,GROUPS=W*H/4,FRAME_BYTES=GROUPS*5;',
'''module tb_ingress_equivalence #(parameter W=68,H=5,C=1,P=1,S=1,E=1);
    localparam GROUPS=W*H/4,FRAME_BYTES=GROUPS*5;
    localparam [15:0] FINAL_KEEP=FRAME_BYTES%16==0?16'hffff:(16'hffff>>(16-FRAME_BYTES%16));''')
t=t.replace('.CONTEXT_ENABLE(1),.PAIR_METADATA_ENABLE(1)', '.CONTEXT_ENABLE(C),.PAIR_METADATA_ENABLE(P)')
t=t.replace('.EXTERNAL_SEQUENCE_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1)', '.EXTERNAL_SEQUENCE_ENABLE(E),.SOURCE_TERMINAL_ENABLE(S)')
t=t.replace('out_keep[0]==16\'h01ff', 'out_keep[0]==FINAL_KEEP')
t=t.replace('if(scenario==3&&group_id==3)eol=1;', 'if(scenario==3&&group_id==3)eol=!eol;')
t=t.replace('if(scenario==1)ready=0;', 'if(scenario==1&&S)ready=0;')
t=t.replace('if(out_valid[0]&&ready)begin', 'if(out_valid[0]&&ready&&frame_number!=0)begin')
t=t.replace('reg expect_good=0,stalled=0;', '''reg [31:0] next_sequence=0;
    always @(posedge clk)begin
        if(!rst_n)next_sequence<=0;
        else if(frame_accept[0])next_sequence<=next_sequence+1;
    end
    reg expect_good=0,stalled=0;''')
t=t.replace('source_sequence=sequence_number;source_camera=camera;', 'source_sequence=E?sequence_number:next_sequence;source_camera=camera;')
t=t.replace('reg expect_good=0,stalled=0;', 'reg chain_entry=0;integer terminal_restarts=0;\n    reg expect_good=0,stalled=0;')
t=t.replace('if(valid&&accept&&implementations[0].current.dut.context_pending!=0)', 'if(frame_accept[0]&&implementations[0].current.dut.terminal_fire)terminal_restarts++;\n        if(valid&&accept&&implementations[0].current.dut.context_pending!=0)')
t=t.replace('@(negedge clk);frame_number=id;expect_good=scenario<2;camera=id%2;', 'if(!chain_entry)@(negedge clk);else chain_entry=0;frame_number=id;expect_good=scenario<2||scenario==5;camera=id%2;')
t=t.replace('if(scenario<2)continuous=continuous+1;', 'if(scenario<2||scenario==5)continuous=continuous+1;')
t=t.replace('waits=0;while(!capture_idle[0]&&waits<200)', '''if(scenario==5)begin
                waits=0;while(!(out_valid[0]&&out_user[0]==2)&&waits<200)begin @(negedge clk);waits++;end
                check(waits<200,"chain waits for actual held success terminal");chain_entry=1;
            end
            waits=0;while(scenario!=5&&!capture_idle[0]&&waits<200)''')
t=t.replace('if(scenario<2)check(end_count==1&&abort_count==0&&byte_count==FRAME_BYTES,"complete good frame");\n            else check', 'if(scenario<2)check(end_count==1&&abort_count==0&&byte_count==FRAME_BYTES,"complete good frame");\n            else if(scenario!=5)check')
t=t.replace('repeat(3)@(negedge clk);\n        end\n    endtask', 'if(scenario!=5)repeat(3)@(negedge clk);\n        end\n    endtask')
t=t.replace('send_frame(1,0);send_frame(2,1);send_frame(3,2);send_frame(4,3);send_frame(5,4);send_frame(6,0);',
'''send_frame(1,0);send_frame(2,1);
        if(S)send_frame(3,2);
        if(GROUPS>16)begin send_frame(4,3);send_frame(5,4);end
        send_frame(6,0);
        if(S)begin send_frame(9,5);send_frame(10,0);check(terminal_restarts!=0,"terminal handshake shares new SOF admission");end
        // Independent non-sensor accepts, unexpected SOFs, disable/abort,
        // mismatched SOURCE and finite random output stalls. Every cycle is
        // compared, including negative terminals and diagnostic counters.
        expect_good=0;frame_number=0;
        for(integer n=0;n<400;n++)begin
            @(negedge clk);valid=$urandom_range(0,1);accept=$urandom_range(0,1);
            sof=$urandom_range(0,3)==0;eol=$urandom_range(0,1);
            raw_data={$urandom,$urandom};enable=$urandom_range(0,15)!=0;
            abort=$urandom_range(0,31)==0;ready=$urandom_range(0,3)!=0;
            source_valid=$urandom_range(0,7)==0;source_ok=$urandom_range(0,1);
            source_error=$urandom_range(0,1);source_camera=$urandom_range(0,1);
            source_session=session;source_epoch=epoch;source_sequence=sequence_number;
        end
        @(negedge clk);valid=0;sof=0;eol=0;abort=0;enable=1;ready=1;source_valid=0;
        rst_n=0;stalled=0;repeat(3)@(negedge clk);rst_n=1;''')
t=t.replace('check(early_raw>0&&append_emit>0&&tail_stalls>0&&continuous>=4*GROUPS,"required peak/metadata/tail cases observed");',
'''check(continuous>=4*GROUPS,"required continuous good-frame input observed");
        if(C&&GROUPS>1)check(early_raw>0,"metadata overlaps accepted RAW");
        if(GROUPS>16)check(append_emit>0,"simultaneous append and emit observed");
        if(S&&GROUPS>16)check(tail_stalls>0,"held DATA tail observed");''')
t=t.replace('checks=%0d early_raw=', 'W=%0d H=%0d C=%0d P=%0d S=%0d E=%0d checks=%0d early_raw=')
t=t.replace('checks,early_raw,append_emit,tail_stalls,continuous);', 'W,H,C,P,S,E,checks,early_raw,append_emit,tail_stalls,continuous);')
(HERE/'tb_ingress_equivalence.sv').write_text(t,encoding='utf-8',newline='\n')
print('frozen ed50 reference and parameterized donor miter prepared')
