`timescale 1ns/1ps
// Digital PHY-byte boundary only. All observed aligners, gearbox, SDR parser
// and the WORD/SYS recorder are production RTL. Calibration is held settled.
module tb_false_sot_trace;
 reg word_clk=0,sys_clk=0,rst=0;
 always #5 word_clk=~word_clk;
 always #7 sys_clk=~sys_clk;
 reg [31:0] raw=0;
 wire [31:0] trace_raw_bytes=raw;
 wire [31:0] lane_byte_data,aligned_word,geared_word;
 wire [3:0] lane_byte_valid,trace_byte_found;
 wire [11:0] trace_byte_offset,trace_word_taps;
 wire aligned_word_valid,geared_word_valid,packet_done,wait_for_sync;
 wire phy_packet_done=packet_done;
 wire [63:0] trace_parser,diag;
 wire o_rx_trace_trigger;
 wire [255:0] o_rx_trace_sample;
 wire o_rx_trace_cohort_n,o_rx_trace_enable;
 wire cohort_word_rst_n=rst,phy_reset_n=rst,word_reset_n=rst,decoder_reset_n=rst;
 wire identity_started=1'b1,publish_enable=1'b1;
 wire [1:0] hdr_mode_word=2'b00;
 wire [15:0] trace_calibration=16'h94d5;
 wire [31:0] sequence_count;
 wire identity_fault,ecc_error,crc_error,length_error;
 wire [39:0] pixels;
 wire pv,sof,eol,abort_out;wire [3:0] code;
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:g_lane
  csi_rx_byte_align_observed byte_aligner(
   .I_clock(word_clk),.I_reset_n(rst),.I_enable(1'b1),
   .I_lan_data_in(raw[lane*8+:8]),.I_wait_for_sync(wait_for_sync),.I_packet_done(phy_packet_done),
   .O_data_out_vaild(lane_byte_valid[lane]),.O_data_out(lane_byte_data[lane*8+:8]),
   .o_diag_offset(trace_byte_offset[lane*3+:3]),.o_diag_found(trace_byte_found[lane]));
 end endgenerate
 csi_rx_word_align_observed #(.MIPI_LAN(4)) aligner(
  .I_word_clock(word_clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_packet_done(phy_packet_done),.I_wait_for_sync(wait_for_sync),.O_packet_done_out(),
  .I_word_in(lane_byte_data),.I_valid_in(lane_byte_valid),
  .O_word_out(aligned_word),.O_valid_out(aligned_word_valid),.o_diag_taps(trace_word_taps));
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gearbox(
  .I_word_clock(word_clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_lane_data(aligned_word),.I_lane_data_valid(aligned_word_valid),
  .O_word_out(geared_word),.O_valid_out(geared_word_valid));
 physical_csi_word_core #(.RX_DIAG_ENABLE(1),.SEQUENCE_INITIAL(32'd2319)) parser(
  .i_clk(word_clk),.i_reset_n(rst),.i_identity_rst_n(rst),
  .o_source_sequence_count(sequence_count),.o_identity_fault(identity_fault),.o_identity_diag(diag),
  .o_trace_parser(trace_parser),.o_trace_trigger(o_rx_trace_trigger),
  .i_word(geared_word),.i_word_valid(geared_word_valid),.i_sink_ready(1'b1),
  .o_data(pixels),.o_valid(pv),.o_sof(sof),.o_eol(eol),.o_abort(abort_out),.o_error_code(code),
  .o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),.o_length_error(length_error),
  .o_wait_for_sync(wait_for_sync),.o_packet_done(packet_done));

 // This expression is checked against the actual receiver by the runner.
 assign o_rx_trace_cohort_n=cohort_word_rst_n && identity_started && !hdr_mode_word[1];
 assign o_rx_trace_enable=!hdr_mode_word[1];
 assign o_rx_trace_sample={3'd0,o_rx_trace_trigger,cohort_word_rst_n,phy_reset_n,
     identity_started,hdr_mode_word[1],publish_enable,word_reset_n,decoder_reset_n,
     phy_packet_done,packet_done,wait_for_sync,geared_word_valid,aligned_word_valid,
     trace_calibration,trace_parser,trace_word_taps,trace_byte_found,trace_byte_offset,
     lane_byte_valid,geared_word,aligned_word,lane_byte_data,trace_raw_bytes};
 reg request=0;reg [5:0] index=0;
 wire ack;wire [319:0] response;
 rx_first_loss_trace recorder(.i_word_clk(word_clk),.i_observer_rst_n(rst),
  .i_cohort_rst_n(o_rx_trace_cohort_n),.i_enable(o_rx_trace_enable),
  .i_trigger(o_rx_trace_trigger),.i_sample(o_rx_trace_sample),
  .i_sys_clk(sys_clk),.i_sys_rst_n(rst),.i_request(request),.i_index(index),
  .o_ack(ack),.o_data(response));

 function [5:0] ecc(input [23:0] h);
 begin
  ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
  ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);
 end endfunction
 function [31:0] header(input integer dt,input integer wc);
 reg [23:0] h;begin h={16'(wc),2'd0,6'(dt)};header={2'd0,ecc(h),h};end endfunction
 function [15:0] crc_byte(input [15:0] c,input [7:0] b);
 reg [15:0] n;integer k;
 begin n=c^b;for(k=0;k<8;k=k+1)n=n[0]?(n>>1)^16'h8408:n>>1;crc_byte=n;end endfunction
 integer checks=0,cases=0,word_cycle=0,trigger_count=0,first_trigger_cycle=-1;
 reg [255:0] sample_log[0:8191];
 always @(posedge word_clk)begin
  if(!rst)begin word_cycle=0;trigger_count=0;first_trigger_cycle=-1;end
  else begin
   sample_log[word_cycle]=o_rx_trace_sample;
   if(o_rx_trace_trigger)begin
    trigger_count=trigger_count+1;
    if(first_trigger_cycle<0)first_trigger_cycle=word_cycle;
   end
   word_cycle=word_cycle+1;
  end
 end
 task check(input bit okay,input string message_text);
 begin checks=checks+1;if(!okay)$fatal(1,"%s",message_text);end endtask
 task tick;@(negedge word_clk);endtask
 task word(input [31:0] value);begin raw=value;tick();end endtask
 task cold;
 begin rst=0;request=0;raw=0;repeat(8)tick();rst=1;repeat(12)tick();end endtask
 task healthy_fs;
 begin
  word(32'hb8b8b8b8);word(header(0,1));raw=32'hffffffff;repeat(40)tick();
  raw=0;repeat(16)tick();
  check(sequence_count==2320 && !identity_fault && diag==0,"healthy FS did not establish trusted source2320");
  check(wait_for_sync && !geared_word_valid && lane_byte_valid==0,"healthy FS did not drain");
 end endtask
 task raw_line(input bit false_sot);
 integer j,k;reg [31:0] value;reg [15:0] crc;
 begin
  if(false_sot)begin word(32'hb8000000);word(0);end
  word(32'hb8b8b8b8);word(32'h21097e2b);crc=16'hffff;
  for(j=0;j<2432;j=j+4)begin
   value=0;
   for(k=0;k<4;k=k+1)begin
    if(j+k<2430)crc=crc_byte(crc,0);
    else if(j+k==2430)value[k*8+:8]=crc[7:0];
    else value[k*8+:8]=crc[15:8];
   end
   word(value);
  end
  raw=32'hffffffff;repeat(40)tick();raw=0;repeat(16)tick();
 end endtask
 task wait_ack(input bit target);
 integer n;begin
  n=0;while(ack!==target && n<100)begin @(negedge sys_clk);#1;n=n+1;end
  check(ack===target,"trace SYS mailbox timeout");
 end endtask
 task read_trace(input [5:0] selected,output [319:0] value);
 begin
  @(negedge sys_clk);#1;index=selected;
  @(negedge sys_clk);#1;request=1;
  wait_ack(1);value=response;
  @(negedge sys_clk);#1;request=0;wait_ack(0);
  repeat(3)begin @(posedge sys_clk);#1;end
 end endtask
 integer i,expected_cycle,correct_byte_index=-1,tap_index=-1,aligned_bad_index=-1;
 reg [319:0] result;
 initial begin
  check(header(6'h2b,2430)==32'h21097e2b,"reference header mismatch");
  cold();healthy_fs();raw_line(0);
  check(!identity_fault && !ecc_error && !crc_error && !length_error,"normal RAW10 line reported parser fault");
  check(trigger_count==0 && diag==0,"normal RAW10 line falsely triggered trace");
  read_trace(63,result);
  check(result[319] && !result[318] && !result[317] && !result[316],"normal control falsely froze recorder");
  cases=cases+1;$display("CASE normal_source2320_crc_valid_RAW10_no_capture PASS");

  cold();healthy_fs();raw_line(1);
  check(identity_fault && diag==64'h00097e2b_09108791,"lead2 failed to reproduce exact R1 W0/W1");
  check(trigger_count==1 && first_trigger_cycle>=32,"first-loss trigger count/history mismatch");
  for(i=0;i<40;i=i+1)begin
   read_trace(6'(i),result);expected_cycle=first_trigger_cycle-32+i;
   check(result[319:316]==4'b1101,"frozen mailbox flags mismatch");
   check(result[315:310]==32 && result[309:304]==i,"pre-count/index mismatch");
   check(result[303:272]==first_trigger_cycle && result[271:256]==1,"trigger cycle/generation mismatch");
   check(result[255:0]===sample_log[expected_cycle],"readback failed chronological reconstruction");
   if(i<32 && result[63:32]==32'h21097e2b && result[131:128]==4'hf)correct_byte_index=i;
   if(i<32 && result[159:157]==3'd2)tap_index=i;
   if(i<32 && result[95:64]==32'h00097e2b && result[240])aligned_bad_index=i;
   if(i==32)begin
    check(result[127:96]==32'h00097e2b,"trigger sample does not contain actual bad geared word");
    check(result[191:160]==2320 && result[193:192]==0,"trigger source/parser HDR mismatch");
    check(result[215:210]==6'h21 && !result[216],"trigger ECC syndrome/good mismatch");
    check(result[252] && result[241] && result[219] && result[218],"trigger lost same-cycle control/identity context");
    check(result[159:157]==2,"trigger word-align lane3 tap mismatch");
   end
   $display("TRACE_READ index=%0d word_cycle=%0d mailbox=%080x",i,expected_cycle,result);
  end
  check(correct_byte_index>=0 && tap_index>=0 && aligned_bad_index>=0,"prehistory lost correct byte header, tap3=2 or corrupted aligned word");
  check(correct_byte_index<aligned_bad_index && aligned_bad_index<32,"prehistory causal ordering mismatch");
  cases=cases+1;
  $display("CASE false_SoT_lead2_source2320_W0_09108791_W1_00097e2b_trace40 PASS correct_byte_index=%0d aligned_bad_index=%0d tap_index=%0d trigger_index=32",correct_byte_index,aligned_bad_index,tap_index);
  $display("RESULT: PASS false_sot_trace cases=%0d checks=%0d samples=40 trigger_count=%0d; electrical_false_sot=NOT_OBSERVED",cases,checks,trigger_count);
  $finish;
 end
 initial begin #200000;$fatal(1,"watchdog");end
endmodule
