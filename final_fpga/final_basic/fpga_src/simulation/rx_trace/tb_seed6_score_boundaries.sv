`timescale 1ns/1ps
module score_boundary #(parameter integer MODE=0)(input clk,rst,output reg finished=0);
 wire [4:0] tap;wire [5:0] len;wire done,valid,failed,load;
 wire [3:0] lanes = MODE==0 ? (done?4'hf:4'h0) :
  MODE==1 ? (dut.state==4 && dut.cnt<63 ?4'hf:4'h1) :
            (dut.state==4 && dut.cnt<64 ?4'hf:4'h1);
 ph1a_rx_delay_scan dut(.I_byte_clk(clk),.I_reset_n(rst),.I_byte_align_done(lanes),
  .O_delay_value(tap),.O_delay_vaild(load),.O_scan_done(done),.O_window_len(len),
  .O_window_valid(valid),.O_scan_failed(failed));
 integer cycles=0,after_done=0,first_scan=-1,score_min=65535,score_max=0;
 always @(posedge clk)if(rst)begin
  cycles=cycles+1;
  if(dut.state==2 && first_scan<0)first_scan=cycles;
  if(dut.state==5)begin
   if(dut.align_cnt<score_min)score_min=dut.align_cnt;
   if(dut.align_cnt>score_max)score_max=dut.align_cnt;
  end
  if(done && !finished)begin
   after_done=after_done+1;
   if(after_done==128)begin
    if(MODE==2)begin if(len!=32 || !valid || failed || tap!=16)$fatal(1,"64 threshold failed");end
    else if(len!=0 || valid || !failed || tap!=16)$fatal(1,"zero/63 accepted");
    if(MODE==0 && first_scan<8388608)$fatal(1,"timeout started too early");
    $display("CASE score MODE=%0d len=%0d valid=%0d failed=%0d first_scan=%0d min=%0d max=%0d PASS",MODE,len,valid,failed,first_scan,score_min,score_max);
    finished=1;
   end
  end
 end
endmodule
module tb_seed6_score_boundaries;
 reg clk=0,rst=0;always #5 clk=~clk;wire [2:0] f;
 score_boundary #(.MODE(0)) no_data_timeout(clk,rst,f[0]);
 score_boundary #(.MODE(1)) only63(clk,rst,f[1]);
 score_boundary #(.MODE(2)) exact64(clk,rst,f[2]);
 initial begin repeat(4)@(negedge clk);rst=1;wait(&f);$display("RESULT PASS full default score boundaries/no-data-timeout/no-rescan");$finish;end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
