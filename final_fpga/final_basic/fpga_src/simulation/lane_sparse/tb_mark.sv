`timescale 1ns/1ps
module tb_mark;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,start=0,enable=1,pixel_fire=0,pixel_eol=0,query=0;
reg [95:0] pixel_rgb=0;reg [8:0] query_x=0,query_y=0;
wire [7:0] hint;wire hint_valid,alignment_error;
lane_mark_hint4 dut(.*);
reg [23:0] pixels[0:15359];reg [1:0] golden[0:959];
integer x,y,l,j,count;
task tick;begin @(posedge clk);#1;end endtask
task produce;
 begin
 for(y=0;y<8;y=y+1)for(x=0;x<1920;x=x+4)begin
   @(negedge clk);pixel_fire=0;
   if((x+y)%52==0)repeat(3)tick();
   @(negedge clk);pixel_fire=1;pixel_eol=x==1916;
   for(l=0;l<4;l=l+1)pixel_rgb[l*24+:24]=pixels[y*1920+x+l];
   tick();
 end
 @(negedge clk);pixel_fire=0;pixel_eol=0;
 end
endtask
initial begin
 $readmemh("mark_pixels.hex",pixels);$readmemh("mark_golden.hex",golden);
 repeat(5)tick();rst_n=1;@(negedge clk);start=1;tick();@(negedge clk);start=0;
 produce();count=0;
 for(y=0;y<2;y=y+1)for(x=0;x<480;x=x+4)begin
   @(negedge clk);query=1;query_x=x;query_y=y;tick();
   if(!hint_valid||alignment_error)$fatal(1,"valid hint unavailable");
   for(j=0;j<4;j=j+1)begin
     if(hint[j*2+:2]!==golden[y*480+x+j])$fatal(1,"4x4 phase/threshold qx%0d y%0d got%h exp%h",x+j,y,hint[j*2+:2],golden[y*480+x+j]);
     count=count+1;
   end
   if(x%24==0)begin @(negedge clk);query=0;repeat(4)tick();if(hint_valid)$fatal(1,"query valid extended");end
 end
 @(negedge clk);query=1;query_x=0;query_y=3;tick();
 if(hint_valid||!alignment_error)$fatal(1,"unproduced row accepted");
 @(negedge clk);query=0;start=1;tick();if(alignment_error)$fatal(1,"new frame did not clear local error");
 @(negedge clk);start=0;query=1;query_y=0;tick();if(hint_valid||!alignment_error)$fatal(1,"old frame hint reused");
 @(negedge clk);query=0;clear=1;tick();@(negedge clk);clear=0;produce();
 @(negedge clk);query=1;query_x=476;query_y=1;tick();
 if(!hint_valid||alignment_error)$fatal(1,"hint recovery");
 for(j=0;j<4;j=j+1)if(hint[j*2+:2]!==golden[956+j])$fatal(1,"hint recovery data");
 $display("RESULT: PASS LANE_SPARSE_MARK checked960 threshold_equal_overflow strict_yellow all16_native_phases x1919 last_word finite_stall unproduced_local_error clear_recovery");$finish;
end
initial begin #300000;$fatal(1,"hint watchdog");end
endmodule
