`timescale 1ns/1ps
module tb_pair;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear_all=0,clear_row=0,write_valid=0;
reg [3:0] write_address=0,rmw_address=0,selector_address=0;
reg [53:0] write_pair=0;wire [53:0] rmw_pair,selector_pair;
lane_winner_pair_lutram dut(.*);
reg [53:0] expected[0:11];reg [11:0] valid=0;
integer checks=0,i,t;
task tick;begin @(posedge clk);#1;end endtask
task check_reads;
 reg [53:0] a,b;
 begin
 a=rmw_address<12&&valid[rmw_address]?expected[rmw_address]:54'd0;
 b=selector_address<12&&valid[selector_address]?expected[selector_address]:54'd0;
 if(rmw_pair!==a||selector_pair!==b)$fatal(1,"async pair read a%h/%h b%h/%h",rmw_pair,a,selector_pair,b);
 checks=checks+1;
 end
endtask
always @(posedge clk)begin
 if(!rst_n||clear_all||clear_row)valid=0;
 else if(write_valid&&write_address<12)begin valid[write_address]=1;expected[write_address]=write_pair;end
 #1;check_reads();
end
task update;
 input integer address,value;
 begin
 @(negedge clk);write_valid=1;write_address=address;write_pair={22'h12345,32'(value)};
 rmw_address=address;selector_address=(address+1)%12;tick();
 end
endtask
initial begin
 repeat(5)tick();rst_n=1;
 // Every clock A/A/A, then A/B/A. Both asynchronous readers must observe
 // the newly clocked word after the official model's write-to-read delta.
 update(1,101);update(1,102);update(1,103);
 update(1,201);update(3,202);update(1,203);
 @(negedge clk);write_valid=0;
 for(t=0;t<12;t=t+1)begin rmw_address=t;selector_address=11-t;#1;check_reads();end
 @(negedge clk);clear_row=1;write_valid=1;write_address=1;write_pair=54'h3fffffffffffff;
 rmw_address=1;selector_address=3;tick();if(rmw_pair!==0||selector_pair!==0)$fatal(1,"row clear lost priority");
 @(negedge clk);clear_row=0;write_valid=0;tick();
 for(t=0;t<12;t=t+1)begin rmw_address=t;selector_address=t;#1;check_reads();end
 update(1,301);update(3,302);
 @(negedge clk);clear_all=1;write_valid=1;tick();
 @(negedge clk);clear_all=0;write_valid=0;rmw_address=1;selector_address=3;#1;check_reads();
 update(1,401);update(15,999);
 @(negedge clk);write_valid=0;rmw_address=15;selector_address=12;#1;check_reads();
 $display("RESULT: PASS WINNER_LUTRAM_PAIR checks%0d AA_A ABA async_dual_read empty reset rowclear_write_collision invalid_address",checks);$finish;
end
initial begin #10000;$fatal(1,"pair watchdog");end
endmodule
