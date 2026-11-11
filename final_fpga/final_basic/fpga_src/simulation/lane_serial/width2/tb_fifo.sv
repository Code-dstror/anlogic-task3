`timescale 1ns/1ps
module tb_fifo;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,s_valid=0,m_ready=0;
wire s_ready,m_valid;reg [146:0] s_data=0;
wire [31:0] m_sample;wire [8:0] m_x,m_y,resident;wire m_bad,empty,overflow;
lane_quarter_fifo4_to1 dut(.*);
always @(negedge clk)m_ready=~m_ready;
integer cycle=0,pushed=0,taken=0,first_push=-1,first_take=-1,max_resident=0;
integer i,j,time_slot,n,finish_wait;
function [31:0] sample;
 input integer group,lane;
 begin sample=(group*4+lane)*32'h01020307+32'h87654321;end
endfunction
always @(posedge clk)begin
 if(rst_n&&!clear)begin
   if(s_valid&&s_ready)begin if(first_push<0)first_push=cycle;pushed=pushed+1;end
   if(overflow)$fatal(1,"legal envelope overflow");
   if(m_valid&&m_ready)begin
     if(first_take<0)first_take=cycle;
     if(m_sample!==sample(taken/4,taken%4)||m_x!==((taken/4)%120)*4+taken%4||
       m_y!==(taken/480==0?268:269)||m_bad!==((taken/4)%13==0))
       $fatal(1,"FIFO sample/metadata mismatch %0d",taken);
     taken=taken+1;
   end
   if(first_take>=0&&taken<960&&resident>=2&&!m_valid)$fatal(1,"prefetch bubble under backlog");
   if(resident>max_resident)max_resident=resident;
   cycle=cycle+1;
 end
end
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(5)tick();rst_n=1;@(negedge clk);clear=1;tick();@(negedge clk);clear=0;
 n=0;
 // Normal120 groups satisfies T>=3Q-21, followed immediately by independent
 // BOTTOM120 groups at one group/clock. Consumer never inserts a bubble.
 for(time_slot=0;time_slot<460;time_slot=time_slot+1)begin
   @(negedge clk);s_valid=0;
   if(time_slot<10||(time_slot>=12&&time_slot<=339&&(time_slot-12)%3==0)||time_slot>=340)begin
     s_valid=1;s_data[127:0]=0;
     for(j=0;j<4;j=j+1)s_data[j*32+:32]=sample(n,j);
     s_data[146:128]={n%13==0,(n<120?9'd268:9'd269),9'((n%120)*4)};
     n=n+1;
   end
   tick();
 end
 @(negedge clk);s_valid=0;finish_wait=0;
 while(!empty&&finish_wait<2200)begin tick();finish_wait=finish_wait+1;end
 if(pushed!=240||taken!=960||!empty)$fatal(1,"FIFO count p%0d t%0d",pushed,taken);
 if(first_take-first_push>3)$fatal(1,"FIFO startup >2 clocks");
 if(max_resident>224)$fatal(1,"arrival-bound resident exceeded %0d",max_resident);
 $display("SERIAL_FIFO legal_normal_BOTTOM groups240 samples960 startup%0d max_resident%0d",first_take-first_push,max_resident);
 // Explicit clear does not reset payload, but retires all old valid state.
 @(negedge clk);clear=1;tick();@(negedge clk);clear=0;repeat(4)tick();
 if(m_valid||resident!=0)$fatal(1,"FIFO clear leak");
 $display("RESULT: PASS LANE_SERIAL_FIFO legal_peak startup2 ordered147bit clear_no_payload_reset");$finish;
end
initial begin #100000;$fatal(1,"FIFO watchdog");end
endmodule
