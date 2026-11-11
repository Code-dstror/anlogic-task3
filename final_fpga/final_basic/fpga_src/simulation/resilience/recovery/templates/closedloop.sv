`timescale 1ns/1ps
module tb_closedloop;
reg clk=0,rst=0,id_rst=0;always #5 clk=~clk;
reg [31:0] raw=0;reg ready=1;
wire [31:0] bd,aw,gw;wire [3:0] lv,found;wire [11:0] offsets,taps;wire av,gv,ws,pd;
wire [39:0] data;wire ov,sof,eol,abort,fault,ee,ce,le;wire [3:0] code;wire [31:0] source;wire [63:0] trace,diag;
genvar lane;generate for(lane=0;lane<4;lane++)begin:gb
csi_rx_byte_align_observed u(.I_clock(clk),.I_reset_n(rst),.I_enable(1'b1),.I_lan_data_in(raw[8*lane+:8]),
.I_wait_for_sync(ws),.I_packet_done(pd),.O_data_out_vaild(lv[lane]),.O_data_out(bd[8*lane+:8]),.o_diag_offset(offsets[3*lane+:3]),.o_diag_found(found[lane]));end endgenerate
csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),.I_packet_done(pd),.I_wait_for_sync(ws),
.O_packet_done_out(),.I_word_in(bd),.I_valid_in(lv),.O_word_out(aw),.O_valid_out(av),.o_diag_taps(taps));
csi_rx_word_gear_box #(.MIPI_LAN(4)) gear(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),.I_lane_data(aw),.I_lane_data_valid(av),.O_word_out(gw),.O_valid_out(gv));
physical_csi_word_core #(.RX_DIAG_ENABLE(1)) dut(.i_clk(clk),.i_reset_n(rst),.i_identity_rst_n(id_rst),.i_word(gw),.i_word_valid(gv),.i_sink_ready(ready),
.o_data(data),.o_valid(ov),.o_sof(sof),.o_eol(eol),.o_abort(abort),.o_error_code(code),.o_source_sequence_count(source),.o_identity_fault(fault),
.o_identity_diag(diag),.o_trace_parser(trace),.o_trace_trigger(),.o_header_ecc_error(ee),.o_payload_crc_error(ce),.o_length_error(le),.o_wait_for_sync(ws),.o_packet_done(pd));
integer checks=0,failures=0,errors=0,cases=0,findings=0,cycle=0,nctrl=0,expected_ctrl=0;
integer data1=0,data2=0,bad1=0,bad2=0,eol1=0,eol2=0,positive=0,negs=0,done_count=0,headers=0;
integer fd,fw,timeout_count;string label="";reg active=0,owner=0,strict_first=1,held=0;
reg [32:0] owner_id;reg [46:0] held_token;reg [36:0] controls[0:31],expected[0:31];
reg [39:0] golden[0:15];
task check(input bit okay,input string why);begin checks++;if(!okay)begin failures++;errors++;if(errors<8)$display("MISMATCH|%s|%s",label,why);end end endtask
task zero(input integer n);begin raw=0;repeat(n)@(negedge clk);end endtask
task ww(input [31:0] x);begin raw=x;@(negedge clk);end endtask
task short_packet(input [31:0] h,input integer gap);begin ww(32'hb8b8b8b8);ww(h);zero(gap);end endtask
task want(input [3:0] c,input bit good,input [31:0] seq);begin expected[expected_ctrl]={c,good,seq};expected_ctrl++;end endtask
task start_case(input string name,input bit strict);begin
 @(negedge clk);active=0;raw=0;rst=0;id_rst=0;ready=1;repeat(8)@(negedge clk);rst=1;id_rst=1;zero(20);
 label=name;strict_first=strict;active=1;owner=0;owner_id=0;held=0;nctrl=0;expected_ctrl=0;errors=0;
 data1=0;data2=0;bad1=0;bad2=0;eol1=0;eol2=0;positive=0;negs=0;done_count=0;headers=0;cases++;
end endtask
task finish_case(input integer seq,input bit identity_fault,input [2:0] err,input integer nd1,input integer nd2);
begin zero(50);
 if(seq>=0)check(source==seq,"source counter");check(fault===identity_fault,"identity trust");check({le,ce,ee}===err,"sticky errors");
 if(nd1>=0)check(data1==nd1,"source1 data groups");if(nd2>=0)check(data2==nd2,"source2 data groups");
 if(expected_ctrl>=0)begin check(nctrl==expected_ctrl,"control count");for(integer j=0;j<nctrl&&j<expected_ctrl;j++)check(controls[j]===expected[j],$sformatf("control%0d got=%010h expected=%010h",j,controls[j],expected[j]));end
 check(!owner,"announced source still lacks terminal at end");
 $display("CASE|%s|%s|source=%0d|fault=%b|flags=%b|ctrl=%0d|data1=%0d|data2=%0d|wrong1=%0d|wrong2=%0d|eol1=%0d|positive=%0d|negative=%0d|packet_done=%0d|headers=%0d",label,errors==0?"PASS":"FAIL",source,fault,{le,ce,ee},nctrl,data1,data2,bad1,bad2,eol1,positive,negs,done_count,headers);active=0;
end endtask
task detected(input string message_text);begin findings++;$display("DETECTED|%s|%s",label,message_text);end endtask
always @(posedge clk)begin
 cycle++;
 if(!rst)held=0;
 else if(active)begin
 if(pd)done_count++;
 if(gv)begin $fwrite(fw,"%s,%0d,%08h,%0d,%b,%b,%03h,%03h\n",label,cycle,gw,trace[33:32],ws,pd,offsets,taps);if(trace[33:32]==0)headers++;end
 if(held)check(ov&&{code,abort,eol,sof,data}===held_token,"stalled public token changed");held=ov&&!ready;held_token={code,abort,eol,sof,data};
 if(ov&&ready)begin
 $fwrite(fd,"%s,%0d,%0d,%b,%b,%b,%010h\n",label,cycle,code,abort,sof,eol,data);
 if(code==7&&!abort)begin check(!owner,"FS overwritten prior announced owner");owner=1;owner_id=data[32:0];controls[nctrl]={code,data[32:0]};nctrl++;end
 else if(code==6||abort)begin check(owner&&data[32:0]===owner_id,"terminal identity/ownership mismatch");owner=0;controls[nctrl]={code,data[32:0]};nctrl++;if(abort)negs++;else if(data[32])positive++;end
 else if(code==0)begin
 check(owner,"data without announced FS");
 if(owner_id[31:0]==1)begin
 if(data!==golden[data1])begin bad1++;if(strict_first)check(0,"golden source1 payload mismatch");end
 if(strict_first)check(sof===(data1==0),"source1 SOF placement");
 data1++;if(eol)eol1++;
 end else if(owner_id[31:0]==2)begin
 if(data!==golden[data2])begin bad2++;check(0,"golden source2 payload mismatch");end
 check(sof===(data2==0),"source2 SOF placement");data2++;if(eol)eol2++;
 end
 end
 end
 end
end
initial begin fd=$fopen("closedloop_tokens.csv","w");fw=$fopen("closedloop_geared.csv","w");
$fwrite(fd,"case,cycle,code,abort,sof,eol,data\n");$fwrite(fw,"case,cycle,word,parser_state,wait_sync,packet_done,offset,taps\n");
__CASES__
$display("RESULT|cases=%0d|checks=%0d|failures=%0d|detected=%0d",cases,checks,failures,findings);$fclose(fd);$fclose(fw);$finish;end
initial begin #2000000;$fatal(1,"bounded closed-loop timeout");end
endmodule
