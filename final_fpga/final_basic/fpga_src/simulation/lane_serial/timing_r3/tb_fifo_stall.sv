`timescale 1ns/1ps
module tb_fifo_stall;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,s_valid=0,m_ready=0;reg [146:0] s_data=0;
wire s_ready,m_valid,m_bad,empty,overflow;wire [31:0] m_sample;wire [8:0] m_x,m_y,resident;
lane_quarter_fifo4_to1 dut(.*);
integer cycle=0,pushed=0,taken=0,held_checks=0,max_resident=0,j;
reg drive=0,was_stalled=0;reg [50:0] held;
function [31:0] sample;input integer group,lane;begin sample=(group*4+lane)*32'h01020307+32'h87654321;end endfunction
always @(negedge clk)if(drive)begin
 m_ready=cycle%19>=5;
 s_valid=s_ready&&pushed<600&&cycle%11!=0;
 for(integer l=0;l<4;l=l+1)s_data[l*32+:32]=sample(pushed,l);
 s_data[146:128]={pushed%13==0,9'(pushed/120),9'((pushed%120)*4)};
end
always @(posedge clk)if(rst_n&&!clear&&drive)begin
 if(was_stalled)begin
  if(!m_valid||{m_bad,m_y,m_x,m_sample}!==held)$fatal(1,"held scalar output changed");
  held_checks=held_checks+1;
 end
 was_stalled=m_valid&&!m_ready;held={m_bad,m_y,m_x,m_sample};
 if(s_valid&&s_ready)pushed=pushed+1;
 if(m_valid&&m_ready)begin
  if(m_sample!==sample(taken/4,taken%4)||m_x!==((taken/4)%120)*4+taken%4||m_y!==taken/480||m_bad!==((taken/4)%13==0))
   $fatal(1,"stall/wrap scalar order mismatch sample%0d",taken);
  taken=taken+1;
 end
 if(overflow)$fatal(1,"capacity-respecting producer overflow");
 if(resident>max_resident)max_resident=resident;
 cycle=cycle+1;
end
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(5)tick();rst_n=1;@(negedge clk);drive=1;
 while(taken<2400)tick();
 @(negedge clk);drive=0;s_valid=0;m_ready=0;
 if(!empty||pushed!=600||held_checks<10)$fatal(1,"stall/wrap coverage count");
 for(j=0;j<5;j=j+1)begin s_valid=1;tick();@(negedge clk);end
 s_valid=0;repeat(5)tick();
 if(!m_valid||resident!=5)$fatal(1,"clear during stalled head fixture");
 @(negedge clk);clear=1;tick();@(negedge clk);clear=0;repeat(5)tick();
 if(m_valid||resident!=0||!empty)$fatal(1,"clear leaked held/preload word");
 $display("RESULT: PASS TIMING_FIFO_STALL groups600 samples2400 held_checks%0d max_resident%0d wrap full_pop clear_stalled_head",held_checks,max_resident);$finish;
end
initial begin #100000;$fatal(1,"FIFO stall watchdog");end
endmodule
