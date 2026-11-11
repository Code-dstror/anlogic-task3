`timescale 1ns/1ps
module tb_alignment_control;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,en=1,pd=0,ws=1;
 reg [31:0] wd=0;reg [3:0] wv=0;reg [7:0] raw=0;
 wire [31:0] out;wire ov,bv,bfound;wire [7:0] bd;wire [2:0] bo;
 csi_rx_word_align_observed #(.MIPI_LAN(4)) word_dut(.I_word_clock(clk),.I_reset_n(rst),.I_enable(en),
 .I_packet_done(pd),.I_wait_for_sync(ws),.O_packet_done_out(),.I_word_in(wd),.I_valid_in(wv),
 .O_word_out(out),.O_valid_out(ov),.o_diag_taps());
 csi_rx_byte_align_observed byte_dut(.I_clock(clk),.I_reset_n(rst),.I_enable(en),
 .I_lan_data_in(raw),.I_wait_for_sync(ws),.I_packet_done(pd),.O_data_out_vaild(bv),
 .O_data_out(bd),.o_diag_offset(bo),.o_diag_found(bfound));
 integer checks=0,n;
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task check(input bit okay,input string message_text);begin checks++;if(!okay)$fatal(1,"%s",message_text);end endtask
 task cold;begin rst=0;en=1;pd=0;ws=1;raw=0;wv=0;wd=0;repeat(3)tick();rst=1;end endtask
 initial begin
  cold();wv=15;wd=32'hb8b8b8b8;tick();
  // Delayed all-valid is now present, but packet-done cancels this edge.
  pd=1;wd=32'h12003c2b;tick();wv=0;pd=0;
  repeat(8)begin check(!ov,"packet-done coincident acquisition leaked valid");tick();end
  $display("CASE packet_done_over_acquisition PASS");

  cold();wv=15;wd=32'hb8b8b8b8;tick();wd=32'h12345678;repeat(3)tick();
  check(ov,"legal candidate did not acquire before disable");en=0;tick();
  check(!ov,"disabled aligner repeated a valid word");repeat(4)begin tick();check(!ov,"held disabled valid");end
  wv=0;en=1;repeat(8)begin tick();check(!ov,"disabled candidate history survived restart");end
  $display("CASE disable_cancels_valid_history PASS");

  cold();wv=1;wd=32'h000000b8;repeat(4)tick();rst=0;tick();rst=1;wv=0;
  repeat(8)begin tick();check(!ov,"reset-mid-candidate leaked a stale word");end
  check(word_dut.r_valid_dly_5===0&&word_dut.r_valid_dly_6===0,"deep valid history not reset");
  $display("CASE reset_cancels_partial_candidate PASS");

  cold();raw=8'hb8;tick();raw=0;tick();check(bfound,"sync candidate not found");
  pd=1;tick();check(!bfound&&!bv,"packet-done kept byte found/valid");pd=0;
  repeat(8)begin tick();check(!bv,"stale found admitted after packet-done");end
  $display("CASE byte_done_cancels_found PASS");

  cold();raw=8'hb8;tick();raw=0;tick();check(bfound,"disabled candidate setup");
  en=0;tick();check(!bfound&&!bv,"disable kept byte candidate");en=1;
  repeat(8)begin tick();check(!bv,"stale found admitted after enable");end
  $display("CASE byte_disable_cancels_found PASS");
  $display("RESULT: PASS alignment cancellation checks=%0d",checks);$finish;
 end
 initial begin #10000;$fatal(1,"control watchdog");end
endmodule
