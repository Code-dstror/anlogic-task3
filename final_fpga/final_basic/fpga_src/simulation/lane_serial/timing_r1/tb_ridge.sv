`timescale 1ns/1ps
module tb_ridge;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,cancel=0,start=0,event_valid=0,event_bad=0;
reg [159:0] start_context=160'h123456;
reg [8:0] event_x=0,event_y=0;
reg [43:0] event_gx=0,event_gy=0;
reg [31:0] event_center_y=0;
reg [7:0] event_hint=0;
reg hint_valid=1,hint_error=0,frame_complete=0,frame_error=0;
wire record_valid;reg record_ready=0;
wire [176:0] record_data;
reg read_enable=0;reg [8:0] read_index=0;
wire [39:0] read_data;wire read_valid;
wire [31:0] started,finished,failed,drops;
wire terminal_valid,terminal_error;wire [159:0] terminal_identity;
lane_sparse_serial4 dut(.*,.terminal_context(start_context),
 .frames_started(started),.frames_finished(finished),.frames_failed(failed),.record_drop_count(drops));
reg [31:0] samples[0:5759];reg [39:0] expected[0:3635];
integer sizes[0:11];integer c,y,x,l,t,index,n,cycles,mode,sample_offset,gap;
integer serial_samples=0,frame_samples=0,maximum_resident=0,maximum_legal_resident=0;
reg checking_legal=1;
reg [176:0] held;
always @(posedge clk)begin
 if(rst_n&&!cancel)begin
   if(dut.queue_valid)begin serial_samples=serial_samples+1;frame_samples=frame_samples+1;end
   if(dut.queue_resident>maximum_resident)maximum_resident=dut.queue_resident;
   if(checking_legal&&dut.queue_resident>maximum_legal_resident)maximum_legal_resident=dut.queue_resident;
 end
end
task tick;begin @(posedge clk);#1;end endtask
task begin_frame;begin
 frame_samples=0;checking_legal=1;
 @(negedge clk);start=1;start_context=start_context+1;tick();@(negedge clk);start=0;
end endtask
task send_frame;
 input integer which,repeat_rows,stalls,local_bad;
 begin
 checking_legal=stalls!=-1;
 for(y=0;y<270;y=y+1)for(x=0;x<480;x=x+4)begin
   @(negedge clk);
   if(stalls==1&&((x+y)%28==0))begin event_valid=0;repeat(2)tick();@(negedge clk);end
   event_valid=1;event_x=x;event_y=y;event_bad=local_bad&&x==100&&y==180;
   for(l=0;l<4;l=l+1)begin
     sample_offset=(which==6?6+y-200:which)*480+x+l;
     if((which==6&&y>=200&&y<=202)||(which!=6&&((repeat_rows&&y>=169)||y==200)))begin
       event_gx[l*11+:11]=samples[sample_offset][10:0];
       event_gy[l*11+:11]=samples[sample_offset][21:11];
       event_center_y[l*8+:8]=samples[sample_offset][29:22];
       event_hint[l*2+:2]=samples[sample_offset][31:30];
     end else begin event_gx[l*11+:11]=0;event_gy[l*11+:11]=0;event_center_y[l*8+:8]=0;event_hint[l*2+:2]=0;end
   end
   tick();
   event_valid=0;
   gap=3;
   if(stalls==-1)gap=0;
   else if(stalls==2&&y==268)gap=(x<36||x==476)?0:2;
   else if(stalls==2&&y==269)gap=0;
   repeat(gap)tick();
 end
 @(negedge clk);event_valid=0;event_bad=0;frame_complete=1;tick();@(negedge clk);frame_complete=0;
 end
endtask
task await_record;
 input integer expected_count,expected_status;
 begin
 cycles=0;while(!record_valid&&cycles<1200)begin tick();cycles=cycles+1;end
 if(!record_valid)$fatal(1,"timeout count=%d tail=%d sel=%d pending=%d",dut.worker.count,dut.worker.tail_pending,dut.worker.selecting,dut.worker.row_pending);
 if(record_data[16:8]!==expected_count||record_data[7:0]!==expected_status)
   $fatal(1,"descriptor count=%d status=%h expected=%d/%h fault=%d",record_data[16:8],record_data[7:0],expected_count,expected_status,dut.worker.local_fault);
 if((expected_status==0||expected_status==1)&&frame_samples!=129600)$fatal(1,"serial frame sample count%0d",frame_samples);
 if(terminal_error!==(expected_status==129))$fatal(1,"LOCAL/SOURCE terminal_error classification");
 held=record_data;repeat(7)begin tick();if(record_data!==held||!record_valid)$fatal(1,"stalled descriptor changed");end
 end
endtask
task compare_points;
 input integer which,repeated;
 reg [39:0] reference_word;
 begin
 n=record_data[16:8];
 for(index=0;index<n;index=index+1)begin
   @(negedge clk);read_enable=1;read_index=index;tick();
   if(!read_valid)$fatal(1,"sync read missing index%0d",index);
   reference_word=expected[which*303+(repeated?index%sizes[which]:index)];
   if(repeated)reference_word[19:11]=169+index/sizes[which];
   if(read_data!==reference_word)$fatal(1,"point %0d got%h expected%h",index,read_data,reference_word);
   @(negedge clk);read_enable=0;tick();if(read_valid)$fatal(1,"read valid stale");
 end
 @(negedge clk);read_enable=1;read_index=n;tick();if(read_valid)$fatal(1,"unwritten read published");
 @(negedge clk);read_enable=0;record_ready=1;tick();@(negedge clk);record_ready=0;
 if(record_valid)$fatal(1,"release failed");
 end
endtask
task fill_to_full;
 begin
 checking_legal=0;t=0;
 while(dut.queue_resident<256&&t<500)begin
   @(negedge clk);event_valid=1;event_x=(t%120)*4;event_y=t/120;
   event_gx=0;event_gy=0;event_center_y=0;event_hint=0;event_bad=0;
   tick();t=t+1;
 end
 @(negedge clk);event_valid=0;
 if(dut.queue_resident!=256||dut.local_bad)$fatal(1,"wrapper full fixture t%0d resident%0d",t,dut.queue_resident);
 end
endtask
initial begin
 $readmemh("samples.hex",samples);$readmemh("expected.hex",expected);$readmemh("sizes.hex",sizes);
 repeat(5)tick();rst_n=1;repeat(3)tick();
 for(c=0;c<6;c=c+1)begin
   begin_frame();send_frame(c,0,c!=0,0);await_record(sizes[c],sizes[c]==0?1:0);compare_points(c,0);
   $display("C1 vector %0d matched %0d points",c,sizes[c]);
 end
 begin_frame();send_frame(6,0,0,0);await_record(sizes[6],0);compare_points(6,0);
 for(c=10;c<12;c=c+1)begin
   begin_frame();send_frame(c,0,0,0);await_record(sizes[c],0);compare_points(c,0);
 end
 // Full-service serial samples and legal normal+BOTTOM worst burst at EOF.
 if(sizes[9]!=3)$fatal(1,"dense303 fixture must provide three row points");
 begin_frame();send_frame(9,1,2,0);await_record(303,0);
 $display("MAX candidate_count%0d all303_words_compared_next",record_data[16:8]);compare_points(9,1);
 begin_frame();send_frame(0,0,0,1);await_record(0,128);compare_points(0,0);
 begin_frame();@(negedge clk);frame_error=1;tick();@(negedge clk);frame_error=0;
 await_record(0,129);compare_points(0,0);
 begin_frame();repeat(3)tick();@(negedge clk);cancel=1;tick();@(negedge clk);cancel=0;
 if(record_valid)$fatal(1,"cancel retained publication");
 begin_frame();send_frame(0,0,0,0);await_record(sizes[0],0);compare_points(0,0);
 // Zero-candidate valid frame is an immediate normal terminal.
 // Artificial input above the proven production envelope must degrade
 // only lane and recover on the next frame, without changing the interface.
 begin_frame();send_frame(0,0,-1,0);await_record(0,128);compare_points(0,0);
 // Wrapper-level capacity boundary: full plus simultaneous final-lane pop
 // and a new push is accepted; the following full non-pop rejects one group.
 begin_frame();fill_to_full();
 while(!(dut.fifo.head_valid&&dut.fifo.phase==3))begin tick();@(negedge clk);end
 event_valid=1;event_x=(t%120)*4;event_y=t/120;#1;
 if(!dut.queue_ready||dut.overflow_detect)$fatal(1,"full+pop misclassified");
 tick();if(dut.local_bad||dut.queue_resident!=256)$fatal(1,"full+pop transfer lost");
 @(negedge clk);event_x=((t+1)%120)*4;event_y=(t+1)/120;#1;
 if(!dut.overflow_detect)$fatal(1,"full without pop overflow missing");
 tick();@(negedge clk);event_valid=0;frame_complete=1;tick();@(negedge clk);frame_complete=0;
 await_record(0,128);compare_points(0,0);
 begin_frame();fill_to_full();
 frame_error=1;event_valid=1;#1;if(dut.overflow_detect)$fatal(1,"SOURCE must override local overflow");
 tick();@(negedge clk);frame_error=0;event_valid=0;await_record(0,129);compare_points(0,0);
 begin_frame();send_frame(0,0,0,0);await_record(sizes[0],0);
 held=record_data;
 @(negedge clk);start=1;read_enable=1;read_index=0;tick();
 if(!record_valid||record_data!==held||!read_valid)$fatal(1,"borrowed frame overwritten on rejected start");
 @(negedge clk);start=0;read_enable=0;compare_points(0,0);
 for(t=0;t<5760;t=t+1)samples[t]=0;
 begin_frame();send_frame(0,0,0,0);await_record(0,1);compare_points(0,0);
 if(maximum_legal_resident>127)$fatal(1,"legal frame exceeded proven resident bound %0d",maximum_legal_resident);
 $display("SERIAL_SAMPLES %0d MAX_LEGAL_RESIDENT %0d OVERLOAD_MAX %0d",serial_samples,maximum_legal_resident,maximum_resident);
 $display("RESULT: PASS LANE_SERIAL_RIDGE max303 center_inverse samebin EOL finite_stall zero negative cancel recovery");
 $finish;
end
initial begin #50000000;$fatal(1,"watchdog");end
endmodule
