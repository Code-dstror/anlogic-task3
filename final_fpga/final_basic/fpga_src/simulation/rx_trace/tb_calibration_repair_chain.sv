`timescale 1ns/1ps
// Byte-boundary counterexample, not an electrical PHY model. The scorer,
// wrapper, watchdog, byte/word aligners, gearbox and parser are actual RTL.
module calibration_repair_chain #(parameter integer START=200, NOISE=0)(
 input clk, rst, output ready, output [15:0] cal);
 reg [31:0] raw=0;
 wire [3:0] lane_valid; wire [31:0] lanes,aligned,geared;
 wire av,gv,ws,pd,phy_rst,wordclk;
 reg [1:0] word_release=0;
 integer cycle=0,phase=0,all_valid_after_scan=0,scan_count=0;
 integer first_scan=-1,done_cycle=-1,min_score=65535,max_score=0;
 function [15:0] cb(input [15:0] c,input [7:0] b);
  reg [15:0] v;integer k;
  begin v=c^b;for(k=0;k<8;k=k+1)v=v[0]?((v>>1)^16'h8408):(v>>1);cb=v;end
 endfunction
 reg [15:0] crc=16'hffff;integer n;
 initial begin for(n=0;n<2430;n=n+1)crc=cb(crc,0);end
 always @(negedge clk) begin
  if(!rst)begin cycle=0;raw=0;end
  else begin
   cycle=cycle+1;raw=0;
   if(NOISE && cycle==100)raw=32'h000000b8;
   if(cycle>=START)begin
    phase=(cycle-START)%680;
    if(phase==16)raw=32'hb8b8b8b8;
    else if(phase==17)raw=32'h21097e2b; // target VC0 RAW10, WC2430, valid ECC
    else if(phase==625)raw={crc,16'd0};
    else if(phase>=626 && phase<666)raw=32'hffffffff;
   end
  end
 end
 csi2_ph1_phy_wrapper #(.MIPI_LAN(4),.DEVICE("PH1A")) phy(
  .I_ref_clock(clk),.I_clk_hs_rx_p(clk),.I_reset_n(rst),.I_decoder_reset_n(1'b1),
  .I_hs_data_p(4'b0),.I_enable(1'b1),.I_debug_button(1'b1),
  .I_wait_for_sync(ws),.I_packet_done(pd),.O_hs_div_clk(wordclk),.O_reset_out(phy_rst),
  .O_rx_byte_data_align_vaild(lane_valid),.O_rx_byte_data_align(lanes),
  .O_auto_delay_done(ready),.O_diag_calibration(cal),.O_delay_value(),.O_dbg_delay(),
  .O_dbg_best_len(),.O_diag_raw_bytes(),.O_diag_byte_offset(),.O_diag_byte_found());
 // Only substitute raw deserialized bytes. Never force aligned valid/score.
 initial force phy.w_rx_byte_data=raw;
 always @(posedge clk or negedge phy_rst)
  if(!phy_rst)word_release<=0;else word_release<={word_release[0],1'b1};
 csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(clk),.I_reset_n(word_release[1]),
  .I_enable(1'b1),.I_packet_done(pd),.I_wait_for_sync(ws),.I_word_in(lanes),.I_valid_in(lane_valid),
  .O_word_out(aligned),.O_valid_out(av),.O_packet_done_out(),.o_diag_taps());
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gb(.I_word_clock(clk),.I_reset_n(word_release[1]),
  .I_enable(1'b1),.I_lane_data(aligned),.I_lane_data_valid(av),.O_word_out(geared),.O_valid_out(gv));
 physical_csi_word_core #(.RX_DIAG_ENABLE(1)) parser(.i_clk(clk),.i_reset_n(word_release[1]),
  .i_identity_rst_n(1'b0),.i_word(geared),.i_word_valid(gv),.i_sink_ready(1'b1),
  .o_wait_for_sync(ws),.o_packet_done(pd));
 always @(posedge clk)begin
  if(!rst)begin first_scan=-1;done_cycle=-1;scan_count=0;all_valid_after_scan=0;min_score=65535;max_score=0;end
  else begin
   if(phy.g_ph1a_delay_scan.u_auto_delay_ctl.state==2 && first_scan<0)first_scan=cycle;
   if(phy.g_ph1a_delay_scan.u_auto_delay_ctl.state==5)begin
    scan_count=scan_count+1;
    if(phy.g_ph1a_delay_scan.u_auto_delay_ctl.align_cnt<min_score)min_score=phy.g_ph1a_delay_scan.u_auto_delay_ctl.align_cnt;
    if(phy.g_ph1a_delay_scan.u_auto_delay_ctl.align_cnt>max_score)max_score=phy.g_ph1a_delay_scan.u_auto_delay_ctl.align_cnt;
   end
   if(cal[11] && done_cycle<0)done_cycle=cycle;
   if(cal[11] && (&lane_valid))all_valid_after_scan=all_valid_after_scan+1;
  end
 end
endmodule

module tb_calibration_repair_chain;
 reg clk=0,rst=0;always #5 clk=~clk;
 wire ra,rb,rc;wire [15:0] ca,cb,cc;
 calibration_repair_chain #(.START(200),.NOISE(0)) immediate(clk,rst,ra,ca);
 calibration_repair_chain #(.START(1100000),.NOISE(0)) delayed(clk,rst,rb,cb);
 calibration_repair_chain #(.START(1100000),.NOISE(1)) false_start(clk,rst,rc,cc);
 initial begin
  repeat(8)@(negedge clk);rst=1;
  repeat(2200000)@(negedge clk);#1;
  if(ca!==16'h9c10 || cb!==16'h9c10 || !ra || !rb)$fatal(1,"clean controls failed %h %h",ca,cb);
  if(cc!==16'h9c10 || !rc)$fatal(1,"late stream did not recover with qualified training %h",cc);
  if(false_start.scan_count!=32 || false_start.min_score<64 || false_start.first_scan<1100000)
   $fatal(1,"repaired scan started without real training or accepted bad scores");
  if(delayed.first_scan<1100000)$fatal(1,"delayed control did not wait for late traffic");
  $display("CASE immediate_clean cal=%h first_scan=%0d done=%0d min_score=%0d max_score=%0d PASS",ca,immediate.first_scan,immediate.done_cycle,immediate.min_score,immediate.max_score);
  $display("CASE same_late_clean_no_prelude cal=%h first_scan=%0d done=%0d min_score=%0d max_score=%0d PASS",cb,delayed.first_scan,delayed.done_cycle,delayed.min_score,delayed.max_score);
  $display("CASE one_lane_prelude_same_late_clean cal=%h first_scan=%0d done=%0d scanned=%0d max_score=%0d healthy_aligned_cycles_after_done=%0d PASS_LATE_START_REPAIRED",cc,false_start.first_scan,false_start.done_cycle,false_start.scan_count,false_start.max_score,false_start.all_valid_after_scan);
  $display("RESULT PASS calibration repair real-feedback paired regression; electrical/actual_board_trigger NOT_PROVEN");$finish;
 end
 initial begin #23000000;$fatal(1,"test timeout");end
endmodule

// Explicit clock/IDDR boundary substitutes. Watchdog itself is real.
module rx_clk_gen #(parameter DEVICE="PH1A")(input I_mipi_clk_p,I_rst,output O_clk,O_clk_x2,O_clk_x4);
 assign O_clk=I_mipi_clk_p;assign O_clk_x2=I_mipi_clk_p;assign O_clk_x4=I_mipi_clk_p;
endmodule
module PH1_PHY_SCLK_V2 #(parameter GSR="ENABLE",BYPASS="ENABLE",DELAY=0)(input ce,clkin,output clkout);
 assign clkout=clkin;
endmodule
module csi_rx_hs_data_phy #(parameter DEVICE="PH1A")
 (input I_rxclk,I_rxclk_div_x2,I_rxclk_div_x4,I_reset_n,I_hs_data_p,
  input [5:0] I_delay_value,input I_delay_vaild,output [7:0] O_rx_data,output O_delay_data_val);
 assign O_rx_data=0;assign O_delay_data_val=1;
endmodule
