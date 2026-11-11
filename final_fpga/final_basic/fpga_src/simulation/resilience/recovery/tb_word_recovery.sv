`timescale 1ns/1ps
module tb_word_recovery;
 parameter integer EXPECT_RECOVERY=0;
 parameter [31:0] INITIAL_SEQUENCE=0;
 reg clk=0,rst_n=0,id_rst_n=0,valid=0,ready=1;
 reg [31:0] din=0;
 always #5 clk=~clk;
 wire [39:0] data;wire out_valid,sof,eol,abort,identity_fault;wire [3:0] code;wire [31:0] sequence_count;
 physical_csi_word_core #(.SEQUENCE_INITIAL(INITIAL_SEQUENCE)
`ifdef RECOVERY_CORE
 ,.FRAME_RESYNC_ENABLE(1)
`endif
 ) dut(.i_clk(clk),.i_reset_n(rst_n),.i_identity_rst_n(id_rst_n),
 .i_word(din),.i_word_valid(valid),.i_sink_ready(ready),.o_data(data),.o_valid(out_valid),.o_sof(sof),.o_eol(eol),.o_abort(abort),.o_error_code(code),
 .o_source_sequence_count(sequence_count),.o_identity_fault(identity_fault),.o_identity_diag(),.o_trace_parser(),.o_trace_trigger(),.o_header_ecc_error(),.o_payload_crc_error(),.o_length_error(),.o_wait_for_sync(),.o_packet_done());
 integer checks=0,fs_count=0,fe_count=0,abort_count=0,data_count=0;reg [32:0] last_fs,last_terminal;reg [3:0] last_abort;
 reg held=0;reg [46:0] held_value;
 task check(input bit yes,input string why);begin checks++;if(!yes)$fatal(1,"%s t=%t seq=%0d code=%0d fault=%b",why,$time,sequence_count,code,identity_fault);end endtask
 function [5:0] ecc(input [23:0] d);
 begin
 ecc[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
 ecc[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[23];
 ecc[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
 ecc[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
 ecc[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
 ecc[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
 end endfunction
 function [15:0] cb(input [15:0] c,input [7:0] b);reg [15:0] v;begin v=c^b;for(integer k=0;k<8;k++)v=v[0]?((v>>1)^16'h8408):(v>>1);cb=v;end endfunction
 task word(input [31:0] w);begin @(negedge clk);din=w;valid=1;@(negedge clk);valid=0;end endtask
 task header(input [7:0] dt,input [15:0] wc);reg [23:0] h;begin h={wc,dt};word({2'b0,ecc(h),h});repeat(3)@(negedge clk);end endtask
 task line(input bit bad_crc);reg [15:0] crc;begin
 header(8'h2b,5);crc=16'hffff;for(integer k=1;k<=5;k++)crc=cb(crc,k);
 word(32'h04030201);word({8'd0,crc[15:8],crc[7:0]^{7'd0,bad_crc},8'd5});repeat(4)@(negedge clk);
 end endtask
 task cold;begin @(negedge clk);rst_n=0;id_rst_n=0;ready=1;repeat(4)@(negedge clk);rst_n=1;id_rst_n=1;repeat(4)@(negedge clk);end endtask
 task quiet;begin repeat(12)@(negedge clk);end endtask
 always @(posedge clk)begin
 if(!rst_n)held=0;else begin
 if(held)check(out_valid&&{code,abort,eol,sof,data}===held_value,"presented parser token changed while stalled");
 held=out_valid&&!ready;held_value={code,abort,eol,sof,data};
 if(out_valid&&ready)begin
 if(code==7&&!abort)begin fs_count++;last_fs=data[32:0];end
 else if(code==6&&!abort)begin fe_count++;last_terminal=data[32:0];end
 else if(abort)begin abort_count++;last_terminal=data[32:0];last_abort=code;end
 else if(code==0)data_count++;
 end end end
 integer a,b,c;
 initial begin
 cold();
 if(INITIAL_SEQUENCE!=0)begin
 header(0,0);quiet();check(sequence_count==32'hffffffff&&last_fs=={1'b1,32'hffffffff},"last legal identity before saturation");
 header(1,0);header(0,0);quiet();check(sequence_count==32'hffffffff&&!last_fs[32]&&identity_fault,"exhaustion never wraps or recovers");
 word(32'h80000000);quiet();header(0,0);quiet();check(sequence_count==32'hffffffff&&!last_fs[32]&&identity_fault,"clean FS cannot undo exhausted counter");
 $display("RESULT: PASS word recovery saturation EXPECT_RECOVERY=%0d checks=%0d",EXPECT_RECOVERY,checks);$finish;
 end
 word(32'h80000000);quiet();header(0,16'h1234);quiet();
 check(sequence_count==1,"startup malformed header consumed no invented sequence");
 check(last_fs[31:0]==1&&last_fs[32]&&!identity_fault,"startup error recovery identity");
 $display("EVIDENCE startup_bad_then_FS sequence=%0d valid=%b fault=%b",sequence_count,last_fs[32],identity_fault);
 cold();header(0,0);line(0);a=abort_count;b=fe_count;word(32'h80000000);quiet();
 check(abort_count==a+1&&last_abort==1&&last_terminal=={1'b1,32'd1}&&fe_count==b,"runtime malformed header authentic negative terminal");
 header(0,0);quiet();check(sequence_count==2&&last_fs=={EXPECT_RECOVERY!=0,32'd2},"runtime header error next FS distinct identity");
 $display("EVIDENCE runtime_bad_then_FS sequence=%0d valid=%b fault=%b",sequence_count,last_fs[32],identity_fault);
 cold();header(0,0);a=abort_count;b=fe_count;c=data_count;line(1);quiet();
 check(abort_count==a+1&&last_abort==2&&fe_count==b&&data_count==c,"CRC failure cannot release last group or FE");
 header(0,0);line(0);header(1,0);quiet();check(last_fs=={1'b1,32'd2}&&last_terminal=={1'b1,32'd2},"CRC does not poison later identity");
 cold();header(0,0);a=abort_count;b=fe_count;ready=0;line(0);quiet();
 check(out_valid&&!abort&&code==0,"data token genuinely held before overflow");line(0);quiet();check(abort_count==a&&fe_count==b,"overflow terminal cannot consume held data");ready=1;quiet();
 check(abort_count==a+1&&last_abort==3&&last_terminal=={1'b1,32'd1},"overflow drains original token then one negative terminal");
 header(0,0);line(0);header(1,0);quiet();check(last_fs=={1'b1,32'd2}&&last_terminal=={1'b1,32'd2},"overflow subsequent frame identity");
 cold();header(0,0);line(0);header(1,0);quiet();ready=0;header(0,0);quiet();
 check(out_valid&&code==7&&data[32:0]=={1'b1,32'd2},"FS2 actually presented under stall");header(1,0);word(32'h80000000);quiet();header(0,0);quiet();
 check(out_valid&&code==7&&data[32:0]=={1'b1,32'd2},"later bad header cannot mutate held old FS");ready=1;quiet();
 check(last_terminal=={1'b1,32'd2}&&fe_count>=2,"queued old FE retains identity after next-frame error");
 cold();header(0,0);header(1,0);quiet();rst_n=0;repeat(4)@(negedge clk);rst_n=1;quiet();check(sequence_count==1&&identity_fault,"decoder reset retains count and revokes trust");header(0,0);quiet();
 check(sequence_count==2&&last_fs=={EXPECT_RECOVERY!=0,32'd2},"decoder reset recovers with nonalias next FS");
 $display("EVIDENCE decoder_reset_then_FS sequence=%0d valid=%b fault=%b",sequence_count,last_fs[32],identity_fault);
 $display("RESULT: PASS word recovery EXPECT_RECOVERY=%0d checks=%0d",EXPECT_RECOVERY,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
