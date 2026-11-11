`timescale 1ns/1ps
// Digital byte path -> real parser -> RX snapshot and RT RAM/SYS mailbox.
// No header is patched in the test. First fault is formed by real aligners.
module tb_trace_recovery;
 parameter integer EXPECT_RECOVERY=0;
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
 physical_csi_word_core #(.RX_DIAG_ENABLE(1),.SEQUENCE_INITIAL(32'd2319)
`ifdef RECOVERY_TRACE
  ,.FRAME_RESYNC_ENABLE(1)
`endif
 ) parser(.i_clk(word_clk),.i_reset_n(rst),.i_identity_rst_n(rst),
  .o_source_sequence_count(sequence_count),.o_identity_fault(identity_fault),.o_identity_diag(diag),
  .o_trace_parser(trace_parser),.o_trace_trigger(o_rx_trace_trigger),
  .i_word(geared_word),.i_word_valid(geared_word_valid),.i_sink_ready(1'b1),
  .o_data(pixels),.o_valid(pv),.o_sof(sof),.o_eol(eol),.o_abort(abort_out),.o_error_code(code),
  .o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),.o_length_error(length_error),
  .o_wait_for_sync(wait_for_sync),.o_packet_done(packet_done));

 // Exact production receiver RT packing, checked by the runner.
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
 reg rx_request=0;
 wire rx_ack_word;wire [127:0] rx_snapshot;
 reg [1:0] rx_ack_sync=0;
 always @(posedge sys_clk or negedge rst)
  if(!rst)rx_ack_sync<=0;else rx_ack_sync<={rx_ack_sync[0],rx_ack_word};
 // UART RX word-domain uses this exact production mailbox and width.
 cfg_diag_snapshot #(.DATA_WIDTH(128)) rx_mailbox(
  .i_clk(word_clk),.i_observer_rst_n(rst),.i_request(rx_request),
  .i_data({64'd0,diag}),.o_ack(rx_ack_word),.o_snapshot(rx_snapshot));

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
 integer checks=0,word_cycle=0,trigger_count=0,first_trigger_cycle=-1;
 integer freeze_count=0,bad_count=0,fs_count=0,trusted_fs=0,abort_count=0;
 reg [31:0] bad_word[0:1];reg [32:0] last_fs,last_abort;
 reg [255:0] sample_log[0:8191];
 reg ready_last=0,protect_first=0,hold_mailboxes=0;
 reg [63:0] first_diag;
 reg [127:0] held_rx;
 reg [319:0] held_trace;
 always @(posedge word_clk)begin
  if(!rst)begin
   word_cycle=0;trigger_count=0;first_trigger_cycle=-1;freeze_count=0;
   bad_count=0;fs_count=0;trusted_fs=0;abort_count=0;ready_last=0;
  end else begin
   sample_log[word_cycle]=o_rx_trace_sample;
   if(o_rx_trace_trigger)begin trigger_count++;
    if(first_trigger_cycle<0)first_trigger_cycle=word_cycle;end
   if(recorder.capture_ready && !ready_last)freeze_count++;
   ready_last=recorder.capture_ready;
   if(geared_word_valid && wait_for_sync && !parser.good)begin
    if(bad_count<2)bad_word[bad_count]=geared_word;
    bad_count++;
   end
   if(pv && !abort_out && code==7)begin fs_count++;last_fs=pixels[32:0];if(pixels[32])trusted_fs++;end
   if(pv && abort_out)begin abort_count++;last_abort=pixels[32:0];end
   if(protect_first && diag!==first_diag)$fatal(1,"live RX first-loss record overwritten");
   word_cycle++;
  end
 end
 always @(posedge sys_clk)if(rst && hold_mailboxes)begin
  if(!ack || response!==held_trace)$fatal(1,"held RT mailbox changed");
  if(!rx_ack_sync[1] || rx_snapshot!==held_rx)$fatal(1,"held RX mailbox changed");
 end
 task check(input bit okay,input string message_text);
 begin checks++;if(!okay)$fatal(1,"%s",message_text);end endtask
 task tick;@(negedge word_clk);endtask
 task word(input [31:0] value);begin raw=value;tick();end endtask
 task gap;begin raw=32'hffffffff;repeat(40)tick();raw=0;repeat(16)tick();end endtask
 task cold;
 begin protect_first=0;hold_mailboxes=0;rst=0;request=0;rx_request=0;raw=0;
  repeat(8)tick();rst=1;repeat(12)tick();end endtask
 task healthy_fs(input integer frame_number,input integer expected_sequence);
 begin
  word(32'hb8b8b8b8);word(header(0,frame_number));gap();
  check(sequence_count==expected_sequence,"FS source count did not advance exactly once");
  check(wait_for_sync && !geared_word_valid && lane_byte_valid==0,"FS did not drain before recovery");
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
  gap();
 end endtask
 task wait_ack(input bit target);
 integer n;begin n=0;while(ack!==target && n<100)begin @(negedge sys_clk);#1;n++;end
  check(ack===target,"RT SYS mailbox timeout");end endtask
 task read_trace(input [5:0] selected,output [319:0] value);
 begin
  @(negedge sys_clk);#1;index=selected;
  @(negedge sys_clk);#1;request=1;wait_ack(1);value=response;
  @(negedge sys_clk);#1;request=0;wait_ack(0);
  repeat(3)begin @(posedge sys_clk);#1;end
 end endtask
 task wait_rx(input bit target);
 integer n;begin n=0;while(rx_ack_sync[1]!==target && n<100)begin @(negedge sys_clk);#1;n++;end
  check(rx_ack_sync[1]===target,"RX snapshot mailbox timeout");
  if(target)begin @(posedge sys_clk);#1;end
 end endtask
 integer i,expected_cycle;reg [319:0] result,frozen_bank[0:39];
 initial begin
  check(header(6'h2b,2430)==32'h21097e2b,"reference header mismatch");
  cold();healthy_fs(1,2320);raw_line(0);
  check(!identity_fault && !ecc_error && !crc_error && !length_error,"normal byte-path control failed");
  check(trigger_count==0 && diag==0 && freeze_count==0,"normal control froze recorder");
  read_trace(63,result);check(result[319:316]==4'b1000,"normal RT status mismatch");
  $display("CASE normal_byte_path_no_capture PASS mode=%0d",EXPECT_RECOVERY);

  cold();healthy_fs(1,2320);raw_line(1);
  check(identity_fault && diag==64'h00097e2b_09108791,"first fault did not reproduce exact observed RX words");
  check(trigger_count==1 && freeze_count==1 && first_trigger_cycle>=32,"first freeze/history mismatch");
  check(bad_count==1 && bad_word[0]==32'h00097e2b,"first bad word was not formed by actual aligner path");
  check(abort_count==1 && last_abort=={1'b1,32'd2320},"first bad frame did not terminate with original identity");
  first_diag=diag;protect_first=1;
  for(i=0;i<40;i++)begin
   read_trace(6'(i),result);expected_cycle=first_trigger_cycle-32+i;frozen_bank[i]=result;
   check(result[319:316]==4'b1101 && result[315:310]==32 && result[309:304]==i,"first RT metadata mismatch");
   check(result[303:272]==first_trigger_cycle && result[271:256]==1,"first RT cycle/generation mismatch");
   check(result[255:0]===sample_log[expected_cycle],"first RT chronological payload mismatch");
   if(i==32)begin
    check(result[127:96]==32'h00097e2b,"first RT trigger lacks bad geared header");
    check(result[191:160]==2320 && result[215:210]==6'h21 && !result[216],"first RT source/syndrome mismatch");
   end
   $display("TRACE_FIRST index=%0d mailbox=%080x",i,result);
  end
  // Hold both real mailboxes while business state loses/reacquires identity.
  @(negedge sys_clk);#1;rx_request=1;wait_rx(1);held_rx=rx_snapshot;
  check(held_rx=={64'd0,first_diag},"RX first W0/W1 snapshot mismatch");
  @(negedge sys_clk);#1;index=32;
  @(negedge sys_clk);#1;request=1;wait_ack(1);held_trace=response;
  check(held_trace==frozen_bank[32],"held trigger response differs from first read");hold_mailboxes=1;
  healthy_fs(2,2321);
  check(identity_fault==(EXPECT_RECOVERY==0),"live identity recovery differs from opt-in/default contract");
  check(last_fs=={EXPECT_RECOVERY!=0,32'd2321},"new FS token did not carry distinct identity validity");
  check(ecc_error && diag==first_diag,"recovery cleared real error or first RX evidence");
  $display("CASE first_bad_then_FS PASS mode=%0d count=%0d valid=%0d W0=%08x W1=%08x",EXPECT_RECOVERY,sequence_count,last_fs[32],diag[31:0],diag[63:32]);
  // A different uncorrectable header enters unmodified through the same bytes.
  word(32'hb8b8b8b8);word(32'h80000000);gap();
  check(identity_fault && bad_count==2 && bad_word[1]==32'h80000000,"different second byte-path bad header missing");
  check(diag==first_diag && freeze_count==1 && recorder.generation==1,"second fault replaced first RX/RT generation");
  check(trigger_count==(EXPECT_RECOVERY?2:1),"parser trigger count differs from live trust transitions");
  check(abort_count==2 && last_abort=={EXPECT_RECOVERY!=0,32'd2321},"second fault lost genuine negative identity");
  healthy_fs(3,2322);
  check(identity_fault==(EXPECT_RECOVERY==0) && last_fs=={EXPECT_RECOVERY!=0,32'd2322},"second recovery FS contract failed");
  check(fs_count==3 && trusted_fs==(EXPECT_RECOVERY?3:1),"accepted/trusted FS counts mismatch");
  hold_mailboxes=0;
  @(negedge sys_clk);#1;request=0;rx_request=0;wait_ack(0);wait_rx(0);
  @(negedge sys_clk);#1;rx_request=1;wait_rx(1);
  check(rx_snapshot==held_rx,"fresh RX mailbox read replaced first W0/W1");
  @(negedge sys_clk);#1;rx_request=0;wait_rx(0);
  for(i=0;i<40;i++)begin
   read_trace(6'(i),result);
   check(result===frozen_bank[i],"RT slot or metadata changed after second fault/recovery");
   $display("TRACE_FINAL index=%0d mailbox=%080x",i,result);
  end
  read_trace(63,result);
  check(result[271:256]==1 && result[303:272]==first_trigger_cycle && result[319:316]==4'b1001,"final live RT metadata mismatch");
  check(result[191:160]==2322 && result[219]==(EXPECT_RECOVERY!=0),"live trace failed to show current identity independent of frozen evidence");
  check(diag==first_diag && freeze_count==1 && recorder.generation==1,"final first-loss ownership changed");
  $display("CASE two_distinct_faults_first_RX_RT_immutable PASS mode=%0d bad0=%08x bad1=%08x triggers=%0d freezes=%0d generation=%0d live_sequence=%0d live_fault=%0d",EXPECT_RECOVERY,bad_word[0],bad_word[1],trigger_count,freeze_count,recorder.generation,sequence_count,identity_fault);
  $display("RESULT: PASS trace_recovery mode=%0d checks=%0d slots=40 electrical=NOT_RUN board=NOT_RUN",EXPECT_RECOVERY,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"bounded trace recovery timeout");end
endmodule
