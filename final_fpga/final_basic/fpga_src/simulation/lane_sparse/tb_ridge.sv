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
lane_ridge_candidates4 dut(.*,.terminal_context(start_context),
 .frames_started(started),.frames_finished(finished),.frames_failed(failed),.record_drop_count(drops));
reg [31:0] samples[0:5759];reg [39:0] expected[0:3635];
integer sizes[0:11];integer c,y,x,l,t,index,n,cycles,mode,sample_offset;
integer compact_batches=0,reverse_batches=0,mixed_batches=0;
integer winner_cycles=0,samebin_updates=0,adjacent_updates=0,mixed_updates=0,feedback_updates=0;
reg [53:0] shadow[0:23];reg shadow_valid=0;reg [23:0] previous_writes=0;
reg [176:0] held;
// Compare every FF entry to the original per-row/per-bin ordered update.
// insert math is unchanged and independently checked by C1 point outputs;
// this shadow isolates the R3 address/parity routing and clear priority.
always @(posedge clk)begin:check_shared_winner
 integer i,address;
 reg [23:0] writes;
 if(!rst_n||cancel)begin shadow_valid=0;previous_writes=0;end
 else if(start&&(!record_valid||record_ready))begin
   for(i=0;i<24;i=i+1)shadow[i]=0;
   shadow_valid=1;previous_writes=0;
 end else if(dut.active&&shadow_valid)begin
   writes=0;
   for(i=0;i<2;i=i+1)if(dut.evaluated[i][26])begin
     address=dut.evaluated_y[i][0]*12+dut.evaluated_bin[i];
     shadow[address]=dut.insert(shadow[address],dut.evaluated[i]);writes[address]=1;
   end
   if(dut.evaluated[0][26]&&dut.evaluated[1][26])begin
     if(dut.evaluated_y[0]!=dut.evaluated_y[1])mixed_updates=mixed_updates+1;
     else if(dut.evaluated_bin[0]==dut.evaluated_bin[1])samebin_updates=samebin_updates+1;
     else adjacent_updates=adjacent_updates+1;
     if(dut.evaluated_bin[0][0]==dut.evaluated_bin[1][0]&&
       (dut.evaluated_y[0][0]!=dut.evaluated_y[1][0]||dut.evaluated_bin[0]!=dut.evaluated_bin[1]))
       $fatal(1,"bin parity single-address invariant violated");
   end
   if(|(writes&previous_writes))feedback_updates=feedback_updates+1;
   previous_writes=writes;winner_cycles=winner_cycles+1;
   if(dut.selecting&&dut.scan==23&&dut.pass==3)
     for(i=0;i<12;i=i+1)shadow[dut.select_bank*12+i]=0;
   #1;
   for(i=0;i<12;i=i+1)begin
     if(dut.winners_even[i]!==shadow[(i/6)*12+(i%6)*2])$fatal(1,"even shared winner mismatch index%0d",i);
     if(dut.winners_odd[i]!==shadow[(i/6)*12+(i%6)*2+1])$fatal(1,"odd shared winner mismatch index%0d",i);
   end
 end
end
// Check every real candidate->evaluated boundary, including idle identities.
always @(posedge clk)begin:check_compaction
 reg [26:0] exp_payload[0:1];
 reg [8:0] exp_y[0:1];
 integer i,used;
 if(rst_n&&!cancel&&!start&&dut.active)begin
   used=0;for(i=0;i<2;i=i+1)begin exp_payload[i]=0;exp_y[i]=0;end
   for(i=0;i<4;i=i+1)if(dut.candidate[i][26])begin
     if(used>=2)$fatal(1,"positive peak candidate bound violated");
     exp_payload[used]=dut.candidate[i];exp_y[used]=dut.candidate_y[i];used=used+1;
   end
   compact_batches=compact_batches+1;
   if(used==2)begin
     if(exp_y[0]!=exp_y[1])mixed_batches=mixed_batches+1;
     else if(exp_payload[0][10:0]>exp_payload[1][10:0])reverse_batches=reverse_batches+1;
   end
   #1;
   for(i=0;i<2;i=i+1)begin
     if(dut.evaluated[i]!==exp_payload[i])$fatal(1,"compaction payload/order slot%0d",i);
     if(exp_payload[i][26]&&(dut.evaluated_y[i]!==exp_y[i]||dut.evaluated_bin[i]!==exp_payload[i][10:0]/160))
       $fatal(1,"compaction y/bin slot%0d",i);
   end
 end
end
task tick;begin @(posedge clk);#1;end endtask
task begin_frame;begin
 @(negedge clk);start=1;start_context=start_context+1;tick();@(negedge clk);start=0;
end endtask
task send_frame;
 input integer which,repeat_rows,stalls,local_bad;
 begin
 for(y=0;y<270;y=y+1)for(x=0;x<480;x=x+4)begin
   @(negedge clk);
   if(stalls&&((x+y)%28==0))begin event_valid=0;repeat(2)tick();@(negedge clk);end
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
 end
 @(negedge clk);event_valid=0;event_bad=0;frame_complete=1;tick();@(negedge clk);frame_complete=0;
 end
endtask
task await_record;
 input integer expected_count,expected_status;
 begin
 cycles=0;while(!record_valid&&cycles<200)begin tick();cycles=cycles+1;end
 if(!record_valid)$fatal(1,"timeout count=%d tail=%d sel=%d pending=%d",dut.count,dut.tail_pending,dut.selecting,dut.row_pending);
 if(record_data[16:8]!==expected_count||record_data[7:0]!==expected_status)
   $fatal(1,"descriptor count=%d status=%h expected=%d/%h fault=%d",record_data[16:8],record_data[7:0],expected_count,expected_status,dut.local_fault);
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
 // No active source bubbles: 270*120=32400 accepted cycles, including EOL.
 if(sizes[9]!=3)$fatal(1,"dense303 fixture must provide three row points");
 begin_frame();send_frame(9,1,0,0);await_record(303,0);
 $display("MAX candidate_count%0d all303_words_compared_next",record_data[16:8]);compare_points(9,1);
 begin_frame();send_frame(0,0,0,1);await_record(0,128);compare_points(0,0);
 begin_frame();@(negedge clk);frame_error=1;tick();@(negedge clk);frame_error=0;
 await_record(0,129);compare_points(0,0);
 begin_frame();repeat(3)tick();@(negedge clk);cancel=1;tick();@(negedge clk);cancel=0;
 if(record_valid)$fatal(1,"cancel retained publication");
 begin_frame();send_frame(0,0,0,0);await_record(sizes[0],0);compare_points(0,0);
 // Zero-candidate valid frame is an immediate normal terminal.
 for(t=0;t<5760;t=t+1)samples[t]=0;
 begin_frame();send_frame(0,0,0,0);await_record(0,1);compare_points(0,0);
 if(reverse_batches==0||mixed_batches<2)$fatal(1,"missing directed compaction coverage center%0d mixed%0d",reverse_batches,mixed_batches);
 if(samebin_updates==0||adjacent_updates==0||mixed_updates<2||feedback_updates==0)$fatal(1,"missing shared winner routing coverage");
 $display("SHARED_WINNER cycles%0d samebin%0d adjacent%0d mixed%0d feedback%0d all24_words_bitexact",winner_cycles,samebin_updates,adjacent_updates,mixed_updates,feedback_updates);
 $display("COMPACTION batches%0d center_reverse%0d mixed_rows%0d",compact_batches,reverse_batches,mixed_batches);
 $display("RESULT: PASS LANE_SPARSE_RIDGE vectors5 plus_center_inverse_mixed_EoL continuous4PPC max303 finite_stall local_error source_error cancel recovery zero_candidates");
 $finish;
end
initial begin #20000000;$fatal(1,"watchdog");end
endmodule
