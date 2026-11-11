`timescale 1ns/1ps
module tb_rmw;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,cancel=0,start=0;
reg [26:0] injected_point=0;
reg [3:0] injected_bin=0,probe_bin=0;
reg [8:0] injected_y=200;
wire [176:0] record_data;wire [39:0] read_data;
wire record_valid,read_valid,terminal_valid,terminal_error;
wire [159:0] terminal_identity;
wire [31:0] frames_started,frames_finished,frames_failed,record_drop_count;
lane_ridge_candidates1_lutram dut(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.start(start),.start_context(160'h1234),
 .event_valid(1'b0),.event_bad(1'b0),.event_x(9'd0),.event_y(9'd0),.event_sample(32'd0),
 .local_error(1'b0),.frame_complete(1'b0),.frame_error(1'b0),.terminal_context(160'h1234),
 .record_valid(record_valid),.record_ready(1'b0),.record_data(record_data),
 .read_enable(1'b0),.read_index(9'd0),.read_data(read_data),.read_valid(read_valid),
 .frames_started(frames_started),.frames_finished(frames_finished),.frames_failed(frames_failed),
 .record_drop_count(record_drop_count),.terminal_valid(terminal_valid),.terminal_error(terminal_error),
 .terminal_identity(terminal_identity));
reg [53:0] golden[0:23];
integer sent=0,writes=0,forwards=0,i,b,xx,strength,width,yellow;
integer random_state=32'h13579135;
reg [53:0] expected_update;
function ref_better;
 input [26:0] a,b;
 begin ref_better=a[26]&&(!b[26]||a[21:11]>b[21:11]||
 (a[21:11]==b[21:11]&&(a[10:0]<b[10:0]||
 (a[10:0]==b[10:0]&&a[24:22]<b[24:22]))));end
endfunction
function ref_separated;
 input [26:0] a,b;
 begin ref_separated=!b[26]||(a[10:0]>=b[10:0]?
 a[10:0]-b[10:0]>=24:b[10:0]-a[10:0]>=24);end
endfunction
// Frozen R2 algorithm, including its second rank compare after the c mux.
function [53:0] ref_insert;
 input [53:0] old;input [26:0] p;
 reg [26:0] a,b,c;
 begin
 a=old[26:0];b=old[53:27];c=0;
 if(p[26])begin
   if(ref_better(p,a))begin
     if(ref_separated(a,p))c=a;
     if(ref_separated(b,p)&&ref_better(b,c))c=b;
     a=p;b=c;
   end else if(ref_separated(p,a)&&ref_better(p,b))b=p;
 end
 ref_insert={b,a};
 end
endfunction
task tick;begin @(posedge clk);#1;end endtask
task inject;
 input integer bin,bank,x,s,w,y;
 begin
 @(negedge clk);injected_bin=bin;injected_y=200+bank;probe_bin=bin;
 injected_point={1'b1,1'(y),3'(w-1),11'(s),11'(x)};sent=sent+1;tick();
 end
endtask
always @(posedge clk)begin
 if(!rst_n||cancel||start)begin
   for(integer k=0;k<24;k=k+1)golden[k]=0;
 end else if(dut.active&&dut.rmw_candidate[26])begin
   expected_update=ref_insert(golden[dut.rmw_bank*12+dut.rmw_bin],dut.rmw_candidate);
   if(dut.update_pair!==expected_update)$fatal(1,"RMW recursive update got%h exp%h bank%0d bin%0d forward%0d",dut.update_pair,expected_update,dut.rmw_bank,dut.rmw_bin,dut.forward_previous);
   golden[dut.rmw_bank*12+dut.rmw_bin]=expected_update;
   writes=writes+1;if(dut.forward_previous)forwards=forwards+1;
 end
 #1;
 if(rst_n&&!cancel&&!start)begin
   if(dut.selector_pair[0]!==golden[probe_bin]||dut.selector_pair[1]!==golden[12+probe_bin])
     $fatal(1,"RMW RAM contents differ bank/bin%0d got%h/%h exp%h/%h",probe_bin,dut.selector_pair[0],dut.selector_pair[1],golden[probe_bin],golden[12+probe_bin]);
 end
end
initial begin
 force dut.evaluated=injected_point;force dut.evaluated_bin=injected_bin;
 force dut.evaluated_y=injected_y;force dut.evaluated_row_end=1'b0;
 force dut.scan={probe_bin,1'b0};
 repeat(5)tick();rst_n=1;@(negedge clk);start=1;tick();@(negedge clk);start=0;
 // Dense A/A/A crosses all rank, equal-rank width, spacing and color choices.
 for(i=0;i<600;i=i+1)inject(0,0,(i*7)%160,(i*37)%2048,(i%8)+1,i%2);
 // A/B/A, alternating row banks and bin12-way walks cover stale read bypass.
 for(i=0;i<1200;i=i+1)begin
   b=i%3==1?1:0;
   inject(b,i%2,b*160+(i*13)%160,(i*41)%2048,(i%8)+1,(i/3)%2);
 end
 for(i=0;i<1200;i=i+1)begin
   b=($random(random_state)&32'h7fffffff)%12;
   xx=b*160+(($random(random_state)&32'h7fffffff)%160);
   strength=($random(random_state)&32'h7fffffff)%2048;
   width=1+(($random(random_state)&32'h7fffffff)%8);
   yellow=($random(random_state)&1);
   inject(b,i%2,xx,strength,width,yellow);
 end
 @(negedge clk);injected_point=0;repeat(3)tick();
 if(writes!=sent||forwards<500)$fatal(1,"II1 coverage sent%0d writes%0d forwards%0d",sent,writes,forwards);
 for(i=0;i<12;i=i+1)begin @(negedge clk);probe_bin=i;tick();end
 // Clear invalidates pending forward and RAM ownership before bank reuse.
 @(negedge clk);cancel=1;tick();@(negedge clk);cancel=0;start=1;tick();@(negedge clk);start=0;
 inject(0,0,24,100,2,0);inject(0,0,48,200,3,1);
 @(negedge clk);injected_point=0;repeat(3)tick();
 if(writes!=sent)$fatal(1,"recovery write loss");
 $display("RESULT: PASS TIMING_R3_RMW_RECURSION sent%0d writes%0d forward%0d II1_AAA_ABA_two_banks_all12bins_rank_width_spacing_clear_reuse",sent,writes,forwards);$finish;
end
initial begin #100000;$fatal(1,"RMW watchdog");end
endmodule
