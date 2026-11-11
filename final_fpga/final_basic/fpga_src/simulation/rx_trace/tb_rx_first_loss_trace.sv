`timescale 1ns/1ps
module tb_rx_first_loss_trace;
 reg word_clk=0,sys_clk=0,word_running=1;
 always #7 begin if(word_running)word_clk=~word_clk;else word_clk=0;end
 always #5 sys_clk=~sys_clk;
 reg observer_rst=0,sys_rst=0,cohort_rst=0,enable=0,trigger=0,request=0;
 reg [5:0] index=0;
 reg [255:0] sample=0;
 wire ack;
 wire [319:0] data;
 rx_first_loss_trace dut(.i_word_clk(word_clk),.i_observer_rst_n(observer_rst),
  .i_cohort_rst_n(cohort_rst),.i_enable(enable),.i_trigger(trigger),.i_sample(sample),
  .i_sys_clk(sys_clk),.i_sys_rst_n(sys_rst),.i_request(request),.i_index(index),.o_ack(ack),.o_data(data));
 integer sample_id=0,checks=0,cases=0;
 reg [31:0] word_cycle=0;
 function [255:0] pattern(input integer n);
 begin pattern={32'h13579bdf^32'(n),32'h2468ace0+32'(n),~32'(n),32'(n)*32'd17,
  32'hc001d00d^32'(n),32'h5aa55aa5+32'(n),32'hf00dcafe-32'(n),32'(n)};end endfunction
 always @(negedge word_clk)if(word_running)begin sample_id=sample_id+1;sample=pattern(sample_id);end
 always @(posedge word_clk)begin
  if(!observer_rst)word_cycle<=0;else word_cycle<=word_cycle+1'b1;
 end
 task check(input bit okay,input string message_text);
 begin checks=checks+1;if(!okay)$fatal(1,"%s",message_text);end endtask

 reg score_arm=0,score_triggered=0;
 reg [255:0] history[0:31],expected[0:39];
 integer history_count=0,pre_expected=0,post_slot=40;
 reg [31:0] trigger_cycle_expected=0;
 reg [15:0] generation_expected=0;
 reg [255:0] status_sample_expected;
 integer j;
 always @(posedge word_clk)begin
  if(score_arm && observer_rst && cohort_rst)begin
   if(!score_triggered)begin
    if(!enable)history_count=0;
    else if(trigger)begin
     pre_expected=history_count;trigger_cycle_expected=word_cycle;
     for(j=0;j<32;j=j+1)begin
      if(j<32-history_count)expected[j]=0;
      else expected[j]=history[j-(32-history_count)];
     end
     expected[32]=sample;post_slot=33;score_triggered=1;
    end else begin
     if(history_count<32)begin history[history_count]=sample;history_count=history_count+1;end
     else begin for(j=0;j<31;j=j+1)history[j]=history[j+1];history[31]=sample;end
    end
   end else if(post_slot<40)begin expected[post_slot]=sample;post_slot=post_slot+1;end
  end
  if(observer_rst && dut.read_state==3'd1 && dut.request_sync && dut.request_index==63)
   status_sample_expected=sample;
 end
 reg held_ack=0;
 reg [319:0] held_data;
 always @(negedge sys_clk)begin
  if(!sys_rst)held_ack=0;
  else begin
   if(ack && held_ack)check(data===held_data,"SYS response changed while ACK held");
   held_ack=ack;held_data=data;
  end
 end
 task word_edges(input integer count);
 integer k;begin for(k=0;k<count;k=k+1)begin @(posedge word_clk);#1;end end endtask
 task sys_edges(input integer count);
 integer k;begin for(k=0;k<count;k=k+1)begin @(posedge sys_clk);#1;end end endtask
 task clear_score;
 begin score_arm=0;score_triggered=0;history_count=0;pre_expected=0;post_slot=40;trigger_cycle_expected=0;end endtask
 task new_cohort;
 begin
  @(negedge word_clk);#1;enable=0;trigger=0;score_arm=0;cohort_rst=0;
  word_edges(3);@(negedge word_clk);#1;cohort_rst=1;
  if(generation_expected!=16'hffff)generation_expected=generation_expected+1'b1;
  word_edges(5);clear_score();
 end endtask
 task arm_trigger(input integer before_count);
 begin
  @(negedge word_clk);#1;clear_score();score_arm=1;enable=1;
  word_edges(before_count);trigger=1;
  word_edges(1);trigger=0;
 end endtask
 task complete_capture(input integer before_count);
 begin arm_trigger(before_count);word_edges(7);
  check(post_slot==40,"scoreboard did not observe eight trigger/post samples");
  check(dut.capture_ready && !dut.capturing_post,"capture did not freeze after seven post clocks");
 end endtask
 task wait_ack(input bit target);
 integer k;begin
  k=0;while(ack!==target && k<180)begin @(negedge sys_clk);#1;k=k+1;end
  check(ack===target,"mailbox handshake timeout");
 end endtask
 task begin_read(input [5:0] selected,output [319:0] response);
 begin
  @(negedge sys_clk);#1;index=selected;
  @(negedge sys_clk);#1;request=1;
  wait_ack(1);response=data;
 end endtask
 task end_read;
 begin @(negedge sys_clk);#1;request=0;wait_ack(0);sys_edges(3);end endtask
 task read_sample(input [5:0] selected,output [319:0] response);
 begin begin_read(selected,response);end_read();end endtask
 task verify_sample(input integer selected);
 reg [319:0] response;reg should_be_valid;
 begin
  read_sample(6'(selected),response);
  should_be_valid=selected<40 && (selected>=32 || selected>=32-pre_expected);
  check(response[309:304]==selected,"response index mismatch");
  check(response[271:256]==generation_expected,"response generation mismatch");
  check(response[303:272]==trigger_cycle_expected,"trigger cycle mismatch");
  check(response[315:310]==pre_expected,"valid pre-count mismatch");
  check(response[316] && !response[317],"complete capture flags mismatch");
  check(response[318]==should_be_valid,"sample validity mismatch");
  check(response[319]==enable,"enabled snapshot mismatch");
  if(should_be_valid)check(response[255:0]===expected[selected],"chronological sample data mismatch");
  else check(response[255:0]==0,"invalid sample leaked old RAM contents");
 end endtask
 task verify_capture;
 integer k;begin for(k=0;k<40;k=k+1)verify_sample(k);end endtask
 reg [319:0] response,saved;
 integer k;
 initial begin
  sys_edges(6);observer_rst=1;sys_rst=1;
  new_cohort();
  read_sample(63,response);
  check(response[255:0]===status_sample_expected,"live status sample mismatch");
  check(response[271:256]==1 && response[309:304]==63,"initial status generation/index mismatch");
  check(response[319]===1'b0 && response[318:316]==0,"initial status validity mismatch");
  cases=cases+1;$display("CASE idle_status PASS");

  complete_capture(32);verify_capture();
  check(pre_expected==32,"full prehistory count mismatch");
  cases=cases+1;$display("CASE exact_32_pre_plus_8_trigger_post PASS");
  trigger=1;word_edges(5);trigger=0;word_edges(20);verify_sample(32);verify_sample(39);
  cases=cases+1;$display("CASE repeated_trigger_and_frozen_data PASS");
  verify_sample(40);verify_sample(62);
  read_sample(63,response);
  check(response[255:0]===status_sample_expected && !response[318] && response[316],"status index63 after capture mismatch");
  cases=cases+1;$display("CASE index_39_40_62_63_boundaries PASS");

  new_cohort();complete_capture(0);verify_capture();
  check(pre_expected==0,"zero-prehistory trigger mismatch");
  new_cohort();complete_capture(3);verify_capture();
  cases=cases+1;$display("CASE early_trigger_zero_and_three_pre_samples PASS");
  new_cohort();complete_capture(93);verify_capture();
  cases=cases+1;$display("CASE late_trigger_ring_wrap PASS");

  new_cohort();arm_trigger(10);
  read_sample(63,response);
  check(response[317] && !response[316] && !response[318],"post-capture status flags mismatch");
  word_edges(8);verify_capture();
  cases=cases+1;$display("CASE capturing_post_status PASS");
  new_cohort();arm_trigger(8);enable=0;word_edges(7);
  check(dut.capture_ready && !dut.capturing_post,"enable drop interrupted consecutive post samples");
  verify_capture();
  cases=cases+1;$display("CASE post_completes_while_disabled_and_old_capture_readable PASS");

  begin_read(32,response);saved=response;
  new_cohort();sys_edges(8);
  check(ack && data===saved,"cohort reset tore held response");
  end_read();read_sample(63,response);
  check(response[271:256]==generation_expected && response[318:316]==0,"new cohort status retained old capture");
  cases=cases+1;$display("CASE cohort_reset_during_held_response PASS");

  complete_capture(40);
  @(negedge sys_clk);#1;index=5;
  @(negedge sys_clk);#1;request=1;
  wait(dut.read_state==3'd2);#1;score_arm=0;cohort_rst=0;
  wait_ack(1);response=data;
  check(!response[318] && !response[316] && response[255:0]==0,"pending RAM read survived cohort reset");
  end_read();@(negedge word_clk);#1;cohort_rst=1;generation_expected=generation_expected+1'b1;
  word_edges(5);clear_score();read_sample(63,response);
  check(response[271:256]==generation_expected && response[318:316]==0,"generation after pending-read reset mismatch");
  cases=cases+1;$display("CASE cohort_reset_during_sync_ram_read PASS");

  arm_trigger(12);word_edges(2);new_cohort();read_sample(32,response);
  check(!response[318] && !response[316],"partial post capture survived reset");
  complete_capture(6);verify_capture();
  cases=cases+1;$display("CASE cohort_reset_during_partial_capture_and_fresh_capture PASS");

  @(negedge sys_clk);#1;index=1;
  @(negedge sys_clk);#1;request=1;
  wait(dut.read_state==3'd1);#1;request=0;
  sys_edges(18);check(!ack,"cancelled request left ACK stuck");
  verify_sample(39);
  cases=cases+1;$display("CASE interrupted_request_drains_and_next_read_works PASS");

  @(negedge word_clk);#1;word_running=0;
  @(negedge sys_clk);#1;index=63;
  @(negedge sys_clk);#1;request=1;
  sys_edges(24);check(!ack,"stopped WORD unexpectedly acknowledged");
  score_arm=0;cohort_rst=0;sys_edges(4);cohort_rst=1;generation_expected=generation_expected+1'b1;
  sys_edges(4);word_running=1;wait_ack(1);response=data;
  check(response[271:256]==generation_expected && !response[318] && !response[316],"stopped-clock reset pulse was not remembered");
  end_read();
  cases=cases+1;$display("CASE stopped_word_timeout_resume_and_reset_generation PASS");

  @(negedge word_clk);#1;dut.generation=16'hfffe;generation_expected=16'hfffe;
  new_cohort();complete_capture(4);verify_sample(32);
  check(generation_expected==16'hffff,"maximum valid generation not reached");
  new_cohort();enable=1;trigger=1;word_edges(12);trigger=0;
  read_sample(63,response);
  check(response[271:256]==16'hffff && response[319:316]==0,"generation exhaustion wrapped or allowed ambiguous capture");
  read_sample(32,response);check(!response[318] && !response[316],"exhausted generation exposed stale RAM");
  cases=cases+1;$display("CASE generation_saturates_and_inhibits_ambiguous_capture PASS");
  $display("RESULT: PASS rx_first_loss_trace cases=%0d checks=%0d",cases,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"watchdog");end
endmodule
