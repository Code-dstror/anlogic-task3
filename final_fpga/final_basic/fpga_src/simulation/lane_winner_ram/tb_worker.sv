`timescale 1ns/1ps
module tb_worker;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,cancel=0,start=0,event_valid=0,event_bad=0,local_error=0,frame_complete=0,frame_error=0;
reg [159:0] start_context=160'h123400;
reg [8:0] event_x=0,event_y=0;reg [31:0] event_sample=0;
wire [1:0] record_valid,read_valid,terminal_valid,terminal_error;
reg record_ready=0,read_enable=0;reg [8:0] read_index=0;
wire [176:0] descriptor[0:1];wire [39:0] data[0:1];wire [159:0] identity[0:1];
wire [31:0] started[0:1],finished[0:1],failed[0:1],drops[0:1];
lane_ridge_candidates1 fixed_ff(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.start(start),.start_context(start_context),
 .event_valid(event_valid),.event_bad(event_bad),.event_x(event_x),.event_y(event_y),.event_sample(event_sample),
 .local_error(local_error),.frame_complete(frame_complete),.frame_error(frame_error),.terminal_context(start_context),
 .record_valid(record_valid[0]),.record_ready(record_ready),.record_data(descriptor[0]),
 .read_enable(read_enable),.read_index(read_index),.read_data(data[0]),.read_valid(read_valid[0]),
 .frames_started(started[0]),.frames_finished(finished[0]),.frames_failed(failed[0]),.record_drop_count(drops[0]),
 .terminal_valid(terminal_valid[0]),.terminal_error(terminal_error[0]),.terminal_identity(identity[0]));
lane_ridge_candidates1_lutram lutram(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.start(start),.start_context(start_context),
 .event_valid(event_valid),.event_bad(event_bad),.event_x(event_x),.event_y(event_y),.event_sample(event_sample),
 .local_error(local_error),.frame_complete(frame_complete),.frame_error(frame_error),.terminal_context(start_context),
 .record_valid(record_valid[1]),.record_ready(record_ready),.record_data(descriptor[1]),
 .read_enable(read_enable),.read_index(read_index),.read_data(data[1]),.read_valid(read_valid[1]),
 .frames_started(started[1]),.frames_finished(finished[1]),.frames_failed(failed[1]),.record_drop_count(drops[1]),
 .terminal_valid(terminal_valid[1]),.terminal_error(terminal_error[1]),.terminal_identity(identity[1]));
reg [31:0] samples[0:5759];reg [39:0] expected[0:3635];integer sizes[0:11];
integer c,y,x,index,k,offset,waits,frames=0,overlap=0,cycles=0;
reg [176:0] held;
reg [1:0] terminal_seen=0, terminal_was_error=0;
reg [159:0] terminal_key[0:1];
task tick;begin @(posedge clk);#1;end endtask
// The original FF selector advances each clock. The shipped implementation
// fetches a candidate, checks spacing, then ranks it over three clocks.
// Compare public records/terminal identities independently of internal phase.
always @(posedge clk)begin
 if(!rst_n||cancel||start)begin terminal_seen<=0;terminal_was_error<=0;end
 else begin
   cycles=cycles+1;
   if(lutram.selecting&&lutram.evaluated[26]&&lutram.evaluated_y[0]!=lutram.select_bank)overlap=overlap+1;
   for(integer n=0;n<2;n++)if(terminal_valid[n])begin
     if(terminal_seen[n])$fatal(1,"duplicate worker terminal");
     terminal_seen[n]<=1;
     terminal_was_error[n]<=terminal_error[n];
     terminal_key[n]<=identity[n];
   end
 end
end
task begin_frame;begin
 @(negedge clk);start=1;start_context=start_context+1;tick();@(negedge clk);start=0;
end endtask
task send_frame;
 input integer which,repeated,stalls,bad;
 begin
 for(y=0;y<270;y=y+1)for(x=0;x<480;x=x+1)begin
   @(negedge clk);
   if(stalls&&(x+y)%37==0)begin event_valid=0;repeat(2)tick();@(negedge clk);end
   event_valid=1;event_x=x;event_y=y;event_bad=bad==1&&x==100&&y==180;
   local_error=bad==2&&x==100&&y==180;
   offset=(which==6?6+y-200:which)*480+x;
   if((which==6&&y>=200&&y<=202)||(which!=6&&((repeated&&y>=169)||y==200)))event_sample=samples[offset];
   else event_sample=0;
   tick();
 end
 @(negedge clk);event_valid=0;event_bad=0;local_error=0;frame_complete=1;tick();@(negedge clk);frame_complete=0;
 end
endtask
task compare_record;
 input integer which,repeated,count,status;
 reg [39:0] golden;
 begin
 waits=0;while(record_valid!=3&&waits<480)begin tick();waits=waits+1;end
 if(record_valid!=3)$fatal(1,"worker terminal timeout");
 if(descriptor[0]!==descriptor[1]||descriptor[0][176:17]!==start_context||descriptor[0][16:8]!==count||descriptor[0][7:0]!==status)
   $fatal(1,"descriptor AB/expected mismatch a%h b%h expected%0d/%0d",descriptor[0],descriptor[1],count,status);
 held=descriptor[0];repeat(7)begin tick();if(record_valid!=3||descriptor[0]!==held||descriptor[1]!==held)$fatal(1,"held descriptor changed");end
 if(terminal_seen!==2'b11||terminal_was_error!=={2{status==129}}||
    terminal_key[0]!==start_context||terminal_key[1]!==start_context)
    $fatal(1,"wrong terminal status, count, or frame identity");
 for(index=0;index<count;index=index+1)begin
   @(negedge clk);read_enable=1;read_index=index;tick();
   golden=expected[which*303+(repeated?index%sizes[which]:index)];
   if(repeated)golden[19:11]=169+index/sizes[which];
   if(read_valid!=3||data[0]!==data[1]||data[0]!==golden)$fatal(1,"point AB/golden mismatch index%0d a%h b%h g%h",index,data[0],data[1],golden);
   @(negedge clk);read_enable=0;tick();
 end
 @(negedge clk);read_enable=1;read_index=count;tick();if(read_valid!=0)$fatal(1,"unwritten point read");
 @(negedge clk);read_enable=0;record_ready=1;tick();@(negedge clk);record_ready=0;
 frames=frames+1;
 end
endtask
initial begin
 $readmemh("samples.hex",samples);$readmemh("expected.hex",expected);$readmemh("sizes.hex",sizes);
 repeat(5)tick();rst_n=1;repeat(3)tick();
 for(c=0;c<6;c=c+1)begin begin_frame();send_frame(c,0,c!=0,0);compare_record(c,0,sizes[c],sizes[c]==0?1:0);end
 begin_frame();send_frame(6,0,0,0);compare_record(6,0,sizes[6],0);
 for(c=10;c<12;c=c+1)begin begin_frame();send_frame(c,0,0,0);compare_record(c,0,sizes[c],0);end
 begin_frame();send_frame(9,1,0,0);compare_record(9,1,303,0);
 begin_frame();send_frame(0,0,0,1);compare_record(0,0,0,128);
 begin_frame();send_frame(0,0,0,2);compare_record(0,0,0,128);
 begin_frame();repeat(4)tick();@(negedge clk);frame_error=1;tick();@(negedge clk);frame_error=0;compare_record(0,0,0,129);
 begin_frame();@(negedge clk);event_valid=1;event_x=0;event_y=0;event_sample=0;repeat(4)tick();
 @(negedge clk);cancel=1;event_valid=0;tick();@(negedge clk);cancel=0;if(record_valid!=0)$fatal(1,"cancel publication leak");
 for(k=0;k<5760;k=k+1)samples[k]=0;
 begin_frame();send_frame(0,0,0,0);compare_record(0,0,0,1);
 if(overlap==0)$fatal(1,"missing row overlap coverage");
 $display("RESULT: PASS WINNER_LUTRAM_WORKER_AB frames%0d cycles%0d overlap%0d golden303 actual_input empty yellow_white SOURCE cancel row_reuse",frames,cycles,overlap);$finish;
end
initial begin #50000000;$fatal(1,"AB watchdog");end
endmodule
