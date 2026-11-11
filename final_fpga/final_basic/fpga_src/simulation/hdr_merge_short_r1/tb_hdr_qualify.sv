`timescale 1ns/1ps
module tb_hdr_qualify;
reg word_clk=0,pixel_clk=0,cfg_clk=0,ref_clk=0,word_running=1;
always #4.444444 if(word_running)word_clk=~word_clk;
always #4 pixel_clk=~pixel_clk;
always #20 cfg_clk=~cfg_clk;
always #5 ref_clk=~ref_clk;
reg cohort_n=0,front_n=0,valid=0,start=0,word_direct=0;
reg [31:0] data=32'hffffffff,direct_data=0;
wire [31:0] bytes,aligned,geared;
wire [3:0] byte_valid;
wire av,gv,done,continuation,wait_sync,phy_done,identity_fault;
wire [1:0] diag_uncertain;wire [31:0] candidate_word;wire candidate_valid;wire [3:0] byte_found;
reg sink_enable=1,skew_mode=0;wire gate_ready0,gate_ready1;reg [31:0] fs_group0=0,fs_group1=0;
reg [31:0] raw_history[0:4];integer history_index;
always @(posedge word_clk)begin
 if(!cohort_n)for(history_index=0;history_index<5;history_index=history_index+1)raw_history[history_index]<=0;
 else begin raw_history[0]<=data;for(history_index=1;history_index<5;history_index=history_index+1)raw_history[history_index]<=raw_history[history_index-1];end
end
wire [31:0] fs0,fs1;wire [146:0] token0,token1;wire token0_v,token1_v,token0_r,token1_r;
wire [31:0] crc_errors,overflow_errors,format_errors;
wire watchdog_healthy,watchdog_reset,clock_lost;
wire written;
reg receive_fault=0;
reg watch_enable=0;
csi_clock_watchdog #(.TIMEOUT_REF_CYCLES(1024)) watchdog(
 .I_ref_clk(ref_clk),.I_ext_clk(word_clk),.I_arst_n(cohort_n),.I_enable(watch_enable),
 .O_healthy_ref(watchdog_healthy),.O_clock_lost_pulse_ref(clock_lost),.O_ext_rst_n(watchdog_reset));
reg use_watchdog=0;
wire decoder_n=front_n&&(!use_watchdog||watchdog_reset);
genvar k;
generate for(k=0;k<4;k=k+1)begin:g_byte
 csi_rx_byte_align_observed b(.I_clock(word_clk),.I_reset_n(decoder_n),.I_enable(1'b1),
 .I_lan_data_in(skew_mode&&k==0?raw_history[4][k*8+:8]:data[k*8+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(phy_done),
 .O_data_out_vaild(byte_valid[k]),.O_data_out(bytes[k*8+:8]),.o_diag_offset(),.o_diag_found(byte_found[k]));
end endgenerate
csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(word_clk),.I_reset_n(decoder_n),
 .I_enable(1'b1),.I_packet_done(phy_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(),
 .I_word_in(bytes),.I_valid_in(byte_valid),.O_word_out(aligned),.O_valid_out(av),.o_diag_taps());
csi_rx_word_gear_box #(.MIPI_LAN(4)) gb(.I_word_clock(word_clk),.I_reset_n(decoder_n),.I_enable(1'b1),
 .I_lane_data(aligned),.I_lane_data_valid(av),.O_word_out(geared),.O_valid_out(gv));
assign phy_done=done&&!continuation;
// Actual production crop and official asynchronous token FIFOs are included.
// Only height is reduced to one sensor row for bounded geometry checks.
real_hdr_csi_capture_stream #(.SENSOR_HEIGHT(1),.CROP_Y(0),.HEIGHT(1)) rx(
 .i_word_clk(word_clk),.i_pixel_clk(pixel_clk),.i_reset_n(decoder_n),.i_decoder_reset_n(1'b1),
 .i_identity_rst_n(cohort_n),.i_publish_enable(1'b1),.i_cycle_enable(written),
 .i_word(word_direct?direct_data:geared),.i_word_valid(word_direct?valid:gv),
 .o_fifo_write_ready(),.o_wait_for_sync(wait_sync),.o_packet_done(done),.o_packet_continue(continuation),
 .o_identity_fault(identity_fault),.m0_data(token0),.m1_data(token1),.m0_valid(token0_v),.m1_valid(token1_v),
 .m0_ready(token0_r),.m1_ready(token1_r),.o_crc_errors(crc_errors),.o_overflow_errors(overflow_errors),
 .o_format_errors(format_errors),.o_sequence_count0(fs0),.o_sequence_count1(fs1),
 .o_fs0_observe_valid(),.o_fs1_observe_valid(),.o_fs0_number(),.o_fs1_number());
assign diag_uncertain={rx.u_parser.u_short.uncertain_header,rx.u_parser.u_long.uncertain_header};
assign candidate_word=rx.u_parser.packet_word;
assign candidate_valid=rx.u_parser.packet_valid;
wire pair_event,pair_ok,pair_event_cfg,pair_ok_cfg,pair_overflow,stable,config_error,xclr,scl;
wire [127:0] cfg_diag;wire [31:0] pair_diag;wire [47:0] pair_counts;
wire [31:0] good_pairs,bad_pairs,not_admitted;
real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(5000)) gate(
 .i_clk(pixel_clk),.i_reset_n(cohort_n),.i_fault(identity_fault||receive_fault),.i_stable(stable),
 .i_admit_enable(1'b1),.i_session(32'd1),.i_epoch(32'd0),.i_time(64'd100000),.i_time_valid(1'b1),
 .i_capture0_idle(1'b1),.i_capture1_idle(1'b1),.s0_data(token0),.s1_data(token1),
 .s0_valid(token0_v&&sink_enable),.s1_valid(token1_v&&sink_enable),.s0_ready(gate_ready0),.s1_ready(gate_ready1),
 .m0_data(),.m1_data(),.m0_valid(),.m1_valid(),.m0_sof(),.m1_sof(),.m0_eol(),.m1_eol(),.m0_abort(),.m1_abort(),
 .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),.o_metadata0(),.o_metadata1(),
 .o_source0_valid(),.o_source1_valid(),.i_source0_ready(1'b1),.i_source1_ready(1'b1),
 .o_source_session(),.o_source_epoch(),.o_source0_sequence(),.o_source1_sequence(),.o_source_ok(),.o_source_error(),
 .o_pair_event(pair_event),.o_pair_ok(pair_ok),.o_diag_pair(pair_diag),.o_diag_counts(pair_counts),
 .o_good_pairs(good_pairs),.o_bad_pairs(bad_pairs),.o_not_admitted_pairs(not_admitted),.o_quiet());
assign token0_r=gate_ready0&&sink_enable;
assign token1_r=gate_ready1&&sink_enable;
always @(posedge pixel_clk)begin
 if(cohort_n&&token0_v&&token0_r&&!token0[42]&&token0[46:43]==7)fs_group0=token0[78:47];
 if(cohort_n&&token1_v&&token1_r&&!token1[42]&&token1[46:43]==7)fs_group1=token1[78:47];
end
// This is the actual source-fault policy from real_hdr_camera_observe_axis:
// WORD fault already has its real two-PIX synchronizer inside capture_stream.
reg source_fault_sticky=0;reg [1:0] fault_cfg=0;
reg phy_previous=0,identity_fault_seen=0;
wire phy_ready=!use_watchdog||watchdog_reset;
always @(posedge pixel_clk or negedge cohort_n)begin
 if(!cohort_n)begin source_fault_sticky<=0;phy_previous<=0;receive_fault<=0;identity_fault_seen<=0;end
 else begin
  if(receive_fault||identity_fault||pair_overflow)source_fault_sticky<=1;
  phy_previous<=phy_ready;receive_fault<=0;identity_fault_seen<=identity_fault;
  if(identity_fault&&!identity_fault_seen)receive_fault<=1;
  if(phy_previous&&!phy_ready)receive_fault<=1;
 end
end
always @(posedge cfg_clk or negedge cohort_n)
 if(!cohort_n)fault_cfg<=0;else fault_cfg<={fault_cfg[0],source_fault_sticky};
tri sda;pullup(sda);reg slave_low=0,transfer=0,ack_release=0;integer bit_count=0;
assign sda=slave_low?1'b0:1'bz;
real_hdr_event_cdc pair_cdc(.s_clk(pixel_clk),.s_reset_n(cohort_n),.s_event(pair_event),.s_ok(pair_ok),
 .s_overflow(pair_overflow),.m_clk(cfg_clk),.m_reset_n(cohort_n),.m_event(pair_event_cfg),.m_ok(pair_ok_cfg));
real_hdr_sensor_config #(.I2C_HALF_PERIOD(2),.RESET_HOLD_CYCLES(4),.RELEASE_WAIT_CYCLES(6),
 .REGULATOR_WAIT_CYCLES(5)) owner(.i_clk(cfg_clk),.i_rst_n(cohort_n),.i_start(start),
 .i_clock_locked(1'b1),.i_abort(1'b0),.i_source_fault(fault_cfg[1]),.i_pair_event(pair_event_cfg),.i_pair_ok(pair_ok_cfg),
 .o_start_ready(),.o_xclr(xclr),.o_scl(scl),.io_sda(sda),.o_config_written(written),.o_stable(stable),
 .o_error(config_error),.o_register_index(),.o_rx_diag_cfg(cfg_diag));
always @(negedge sda)if(cohort_n&&scl===1'b1&&!slave_low)begin transfer=1;ack_release=0;bit_count=0;end
always @(posedge sda)if(cohort_n&&scl===1'b1&&transfer&&!slave_low)transfer=0;
always @(posedge scl)if(cohort_n&&transfer)if(bit_count<8)bit_count=bit_count+1;else bit_count=0;
always @(negedge scl)begin
 if(!cohort_n||!transfer)begin slave_low=0;ack_release=0;end
 else if(ack_release)begin slave_low=0;ack_release=0;end
 else if(bit_count==8)begin slave_low=1;ack_release=1;end
end
function [5:0] ecc(input [23:0] h);
begin ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);end endfunction
function [31:0] header(input integer vc,dt,wc);
reg [23:0] h;begin h={16'(wc),2'(vc),6'(dt)};header={2'd0,ecc(h),h};end endfunction
function [15:0] crc_byte(input [15:0] c,input [7:0] b);
reg [15:0] n;integer i;begin n=c^b;for(i=0;i<8;i=i+1)n=n[0]?(n>>1)^16'h8408:n>>1;crc_byte=n;end endfunction
integer checks=0,cases=0,fault_cases=0,limit,j,mask;
integer fs_token0=0,uncertain=0;reg fault_seen=0;reg [31:0] first_uncertain_word;
always @(posedge word_clk)if(cohort_n&&decoder_n)begin
 if((|diag_uncertain)&&!uncertain)first_uncertain_word=candidate_word;
 if((|diag_uncertain))uncertain=uncertain+1;
end
always @(posedge pixel_clk)if(cohort_n&&token0_v&&token0_r&&!token0[42]&&token0[46:43]==7)fs_token0=fs_token0+1;
task wt(input integer n);repeat(n)begin @(negedge word_clk);end endtask
task ct(input integer n);repeat(n)begin @(negedge cfg_clk);end endtask
task check(input bit yes,input string why);begin checks=checks+1;if(!yes)$fatal(1,"%s cfg%032h pair%08h fs%0d/%0d identity%0d uncertain%0d",why,cfg_diag,pair_diag,fs0,fs1,identity_fault,uncertain);end endtask
task cold(input bit watching);
begin cohort_n=0;front_n=0;data='1;direct_data='1;valid=0;start=0;word_running=1;
slave_low=0;transfer=0;ack_release=0;bit_count=0;watch_enable=watching;use_watchdog=watching;word_direct=0;sink_enable=1;skew_mode=0;fs_group0=0;fs_group1=0;
ct(5);cohort_n=1;front_n=1;ct(3);start=1;ct(1);start=0;limit=0;
while(!written&&!config_error&&limit<50000)begin ct(1);limit=limit+1;end
check(written&&!config_error&&cfg_diag[47:32]==139&&cfg_diag[63:48]==0,"139 actual I2C ACKs before stimulus");
wt(40);fs_token0=0;uncertain=0;first_uncertain_word=0;
end endtask
task word(input [31:0] w);begin data=w;direct_data=w;valid=1;wt(1);end endtask
task burst_start;begin data=0;valid=0;wt(5);word(32'hb8b8b8b8);end endtask
task trail(input [31:0] t);begin data=t;direct_data=t;valid=0;wt(45);ct(8);end endtask
task raw12(input integer vc,wc,seed,corrupt,input [31:0] pad);
integer a,b;reg [31:0] w;reg [15:0] c;reg [7:0] v;
begin word(header(vc,6'h2c,wc));c=16'hffff;
for(a=0;a<wc+2;a=a+4)begin w=pad;
for(b=0;b<4;b=b+1)begin
if(a+b<wc)begin v=8'(a+b+seed);c=crc_byte(c,v);w[b*8+:8]=v;end
else if(a+b==wc)w[b*8+:8]=c[7:0]^(corrupt?1:0);
else if(a+b==wc+1)w[b*8+:8]=c[15:8];
end word(w);end end endtask
task report(input string name);
begin cases=cases+1;if(identity_fault)fault_cases=fault_cases+1;
$display("CASE %s fs=%0d/%0d fs_token0=%0d uncertain=%0d first_uncertain=%08h identity=%0d cfg_state=%0d index=%0d writes=%0d i2c_errors=%0d warmup=%0d xclr=%0d bad=%0d not_admitted=%0d reason=%0d good=%0d",name,fs0,fs1,fs_token0,uncertain,first_uncertain_word,identity_fault,cfg_diag[15:12],cfg_diag[23:16],cfg_diag[47:32],cfg_diag[63:48],cfg_diag[31:24],xclr,bad_pairs,not_admitted,pair_diag[23:16],good_pairs);
end endtask
// Constructed raw-byte qualification; no final-state force.
reg [31:0] q_tail,q_last;
reg [15:0] q_crc;
integer q_n,q_lane,q_wc,q_pair;
integer word_cycle=0,metric_crc=0,metric_done=-1,metric_low=-1,metric_found=-1;
reg metric_enable=0,metric_previous_gv=0;reg [3:0] metric_previous_found=0;
always @(posedge word_clk)begin
 word_cycle=word_cycle+1;
 if(metric_enable)begin
  if(phy_done&&metric_done<0)metric_done=word_cycle;
  if(metric_done>=0&&metric_previous_gv&&!gv&&metric_low<0)metric_low=word_cycle;
  if(metric_done>=0&&(|byte_found)&&!(|metric_previous_found)&&metric_found<0)metric_found=word_cycle;
 end
 metric_previous_gv=gv;metric_previous_found=byte_found;
end
task natural_tail(input integer vc,dt,wc,seed);
reg [7:0] value;
begin
 q_crc=16'hffff;
 for(q_n=0;q_n<wc;q_n=q_n+1)q_crc=crc_byte(q_crc,8'(q_n+seed));
 q_last=header(vc,dt,wc);
 for(q_n=0;q_n<wc+2;q_n=q_n+1)begin
  if(q_n<wc)value=8'(q_n+seed);
  else if(q_n==wc)value=q_crc[7:0];else value=q_crc[15:8];
  q_last[(q_n%4)*8+:8]=value;
 end
 for(q_lane=0;q_lane<4;q_lane=q_lane+1)
  q_tail[q_lane*8+:8]=q_last[q_lane*8+7]?8'h00:8'hff;
end endtask
task long_packet(input integer vc,dt,wc,seed,corrupt,input [31:0] header_xor,pad);
integer a,b;reg [31:0] w;reg [15:0] c;reg [7:0] v;
begin word(header(vc,dt,wc)^header_xor);c=16'hffff;
 for(a=0;a<wc+2;a=a+4)begin w=pad;
  for(b=0;b<4;b=b+1)begin
   if(a+b<wc)begin v=8'(a+b+seed);c=crc_byte(c,v);w[b*8+:8]=v;end
   else if(a+b==wc)w[b*8+:8]=c[7:0]^(corrupt?1:0);
   else if(a+b==wc+1)w[b*8+:8]=c[15:8];
  end word(w);
 end
end endtask
task contiguous_pair(input integer number,seed);
begin
 word(header(0,0,number));word(header(1,0,number));
 raw12(0,2916,seed,0,'1);raw12(1,2916,seed+6,0,'1);
 word(header(0,1,number));word(header(1,1,number));
end endtask
task settle_negative;
begin
 burst_start();word(header(0,0,2));word(header(1,0,2));trail('1);
 wt(7000);ct(12);
end endtask
initial begin
 if($test$plusargs("BASELINE"))begin
  cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h2c,2916,1);
  check(q_crc==16'heb76&&q_tail==32'hffff00ff,"frozen mixed-tail independent reference");
  raw12(0,2916,1,0,q_tail);trail(q_tail);
  check(identity_fault&&config_error&&bad_pairs==1&&pair_diag[23:16]==9,
        "R1 defect is present on real byte chain");report("baseline_seed1_defect");
  cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h2c,2916,5);
  check(q_crc==16'h6e70&&q_tail==32'hffffffff,"frozen all-ones reference");
  raw12(0,2916,5,0,q_tail);trail(q_tail);
  check(!identity_fault&&!config_error,"R1 all-ones control healthy");report("baseline_seed5_control");
  $display("RESULT: PASS BASELINE_DEFECT_PRESENT cases=%0d checks=%0d",cases,checks);$finish;
 end
 cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h2c,2916,1);
 check(q_crc==16'heb76&&q_tail==32'hffff00ff,"natural seed1 CRC/tail reference");
 raw12(0,2916,1,0,q_tail);trail(q_tail);
 check(!identity_fault&&!config_error&&bad_pairs==0&&fs0==1,
       "natural mixed tail must not poison cohort or add FS");report("fixed_seed1_mixed_tail");
 cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h2c,2916,5);
 raw12(0,2916,5,0,q_tail);trail(q_tail);
 check(!identity_fault&&!config_error&&bad_pairs==0&&fs0==1,
       "natural all-ones control remains healthy");report("fixed_seed5_allones");
 cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h2c,2916,33);
 check(q_crc==16'hedf8&&q_tail==0,"natural all-zero trail reference");
 raw12(0,2916,33,0,q_tail);trail(q_tail);
 check(!identity_fault&&!config_error&&bad_pairs==0&&fs0==1,
       "natural zero tail cannot fabricate an FS");report("fixed_seed33_zero_tail");
 cold(0);burst_start();contiguous_pair(1,1);trail('1);
 check(good_pairs==1&&!identity_fault&&!config_error&&fs0==1&&fs1==1,
       "full same-burst pair is lossless");report("contiguous_full_pair");
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 long_packet(0,6'h12,3,2,0,0,'1);long_packet(1,6'h37,7,8,0,0,'1);
 raw12(0,2916,1,0,'1);raw12(1,2916,7,0,'1);
 word(header(0,1,1));word(header(1,1,1));trail('1);
 check(good_pairs==1&&fs0==1&&fs1==1&&!identity_fault&&!config_error,
       "embedded and OB then RAW preserve full same-burst pair");report("embedded_OB_RAW_sameburst_pair");
 cold(0);skew_mode=1;burst_start();contiguous_pair(1,1);trail('1);
 check(good_pairs==1&&!identity_fault&&!config_error&&fs0==1&&fs1==1,
       "five-byte lane skew retains acquisition and full pair");report("lane_skew_5_0_full_pair");
 cold(0);skew_mode=1;burst_start();word(header(0,0,1));word(header(1,0,1));
 natural_tail(0,6'h2c,2916,1);raw12(0,2916,1,0,q_tail);
 metric_enable=1;metric_crc=word_cycle;metric_done=-1;metric_low=-1;metric_found=-1;
 data=q_tail;wt(20);burst_start();raw12(1,2916,7,0,'1);
 data='1;wt(20);burst_start();word(header(0,1,1));word(header(1,1,1));trail('1);metric_enable=0;
 check(good_pairs==1&&!identity_fault&&metric_done>=metric_crc&&metric_low>=0&&metric_found>=0,
       "skewed short-gap bursts reacquire with measured feedback");
 $display("BOUNDARY_LATENCY skew=5/0 trail_WORD=20 preSoT_zero_WORD=5 CRC_to_phy_done=%0d CRC_to_geared_valid_low=%0d CRC_to_new_byte_found=%0d",
          metric_done-metric_crc,metric_low-metric_crc,metric_found-metric_crc);
 report("lane_skew_5_0_short_gap_reacquire");
 cold(0);burst_start();contiguous_pair(0,1);trail('1);
 check(header(0,0,0)==0&&good_pairs==1&&fs0==1&&fs1==1&&!identity_fault,
       "fresh SoT FS0 remains legal");report("fresh_SoT_FS0_pair");
 cold(0);burst_start();word(header(0,1,1));contiguous_pair(0,1);trail('1);
 check(good_pairs==1&&fs0==1&&fs1==1&&!identity_fault&&fs_group0==1&&fs_group1==1,
       "peek FS0 and VC1 FS publish separately with one group increment");report("drain_FS0_peek_VC1_group");
 cold(0);burst_start();word(header(0,1,1));word(header(0,0,0));raw12(0,2916,1,0,'1);
 word(header(1,0,0));raw12(1,2916,7,0,'1);word(header(0,1,0));word(header(1,1,0));trail('1);
 check(good_pairs==1&&fs0==1&&fs1==1&&!identity_fault&&fs_group0==fs_group1,
       "peek FS0 followed by RAW retains packet and group");report("drain_FS0_peek_RAW");
 cold(0);burst_start();word(header(0,1,1));word(0);trail('1);
 check(fs0==0&&good_pairs==0&&!identity_fault,
       "unsupported trailing DRAIN FS0 is discarded");report("unsupported_trailing_FS0_discard");
 cold(0);burst_start();word(header(0,1,1));trail(0);
 check(fs0==0&&good_pairs==0&&!identity_fault,"zero trail cannot fabricate FS");report("zero_trail_no_fake_FS");
 cold(0);burst_start();word(header(0,1,1));word(32'h01000000);trail('1);
 check(fs0==0&&good_pairs==0&&!identity_fault,"ECC-corrected zero needs peek");report("corrected_zero_without_peek_discard");
 cold(0);burst_start();word(header(0,1,1));word(32'h01000000);word(header(1,0,0));
 raw12(0,2916,1,0,'1);raw12(1,2916,7,0,'1);word(header(0,1,0));word(header(1,1,0));trail('1);
 check(good_pairs==1&&fs0==1&&fs1==1&&!identity_fault&&fs_group0==fs_group1,
       "ECC-corrected zero can be confirmed without merging FS clocks");report("corrected_zero_with_peek_pair");
 cold(0);burst_start();word(header(0,1,1));word(0);word(32'h01000000);trail('1);
 check(fs0==0&&good_pairs==0,"corrected-zero confirming word is still ambiguous");report("corrected_zero_cannot_confirm_zero");
 cold(0);burst_start();word(header(0,1,1));word(0);word(header(1,0,1)^32'hc0000000);trail('1);
 check(fs0==0&&good_pairs==0,"failed peek cannot publish pending FS");report("zero_peek_bad_header_discard");
 cold(0);burst_start();word(header(0,1,1));word(0);
 front_n=0;wt(8);front_n=1;wt(40);burst_start();word(header(0,0,1));trail('1);
 check(fs0==1&&!identity_fault&&good_pairs==0,"reset clears in-flight zero before fresh SoT");report("inflight_zero_reset_cancellation");
 cold(0);burst_start();word(header(0,0,1));trail('1);
 burst_start();word(header(1,0,1));trail('1);
 check(fs0==1&&fs1==1&&!identity_fault,"new SoT reacquires after drain");report("new_SoT_reacquire");
 cold(0);burst_start();word(header(0,0,1));trail('1);
 burst_start();word(header(1,0,1)^32'hc0000000);trail('1);
 check(identity_fault&&config_error&&cfg_diag[15:12]==8&&good_pairs==0,
       "fresh SoT bad header remains strict after first FS");report("new_SoT_bad_header_negative");
 // Corrupt continuous headers must not produce an image completion.
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 long_packet(0,6'h2c,2916,1,0,32'hc0000000,'1);
 raw12(1,2916,7,0,'1);word(header(0,1,1));word(header(1,1,1));trail('1);settle_negative();
 check(good_pairs==0&&bad_pairs>0,"lost RAW header cannot complete image");report("lost_RAW_header_negative");
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 raw12(0,2916,1,0,'1);raw12(1,2916,7,0,'1);
 word(header(0,1,1)^32'hc0000000);word(header(1,1,1));trail('1);settle_negative();
 check(good_pairs==0&&bad_pairs>0,"lost FE cannot complete image");report("lost_FE_header_negative");
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 raw12(0,2916,1,1,'1);raw12(1,2916,7,0,'1);
 word(header(0,1,1));word(header(1,1,1));trail('1);
 check(good_pairs==0&&bad_pairs>0&&crc_errors>0,
       "true RAW CRC failure remains negative");report("bad_CRC_negative");
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 word(header(0,6'h2c,2916));
 for(q_n=0;q_n<16;q_n=q_n+4)word(32'h04030201+q_n*32'h01010101);
 trail('1);wt(1000);settle_negative();
 check(good_pairs==0&&bad_pairs>0&&crc_errors>0,
       "truncated RAW into LP-high samples cannot complete an image");report("truncated_RAW_sampled_high_negative");
 // Withhold the real FIFO sink handshake, while the sensor keeps sending.
 cold(0);sink_enable=0;
 for(q_pair=1;q_pair<=2;q_pair=q_pair+1)begin
  burst_start();word(header(0,0,q_pair));raw12(0,2916,q_pair,0,'1);
  word(header(0,1,q_pair));trail('1);
 end
 sink_enable=1;wt(7000);ct(12);
 check(overflow_errors>0&&good_pairs==0&&bad_pairs>0,
       "real FIFO backpressure overflow remains negative");report("FIFO_overflow_negative");
 // WC modulo4, including split CRC; generated metadata, not sensor capture.
 for(q_wc=0;q_wc<8;q_wc=q_wc+1)begin
  cold(0);burst_start();word(header(0,0,1));natural_tail(0,6'h12,q_wc,q_wc+1);
  long_packet(0,6'h12,q_wc,q_wc+1,0,0,q_tail);trail(q_tail);
  check(!identity_fault&&!config_error&&fs0==1&&good_pairs==0,
        "embedded WC/CRC tail neither fabricates FS nor poisons identity");
  report($sformatf("embedded_WC%0d_natural_tail_%08h",q_wc,q_tail));
 end
 // Eight real completions drive serial-I2C owner warmup through event CDC.
 cold(0);
 for(q_pair=1;q_pair<=8;q_pair=q_pair+1)begin
  burst_start();word(header(0,0,q_pair));word(header(1,0,q_pair));
  natural_tail(0,6'h2c,2916,1);raw12(0,2916,1,0,q_tail);trail(q_tail);
  burst_start();raw12(1,2916,7,0,'1);trail('1);
  burst_start();word(header(0,1,q_pair));word(header(1,1,q_pair));trail('1);
  check(good_pairs==q_pair&&!identity_fault&&!config_error&&fs0==q_pair&&fs1==q_pair,
        "each natural-tail pair qualifies exactly once");
 end
 ct(16);
 check(stable&&written&&!config_error&&cfg_diag[95:80]==8&&good_pairs==8,
       "eight actual good pairs qualify owner warmup");report("eight_natural_tail_pairs_owner_stable");
 cold(1);wt(200);ct(10);word_running=0;repeat(1100)@(negedge ref_clk);
 ct(8);word_running=1;wt(180);ct(8);
 check(config_error&&fs0==0&&bad_pairs==0,"pre-FS clock loss remains fault");report("clock_loss_before_FS");
 cold(1);wt(200);ct(10);burst_start();word(header(0,0,1));trail('1);
 check(fs_token0==1,"FS crossed real FIFO before clock stop");
 word_running=0;repeat(1100)@(negedge ref_clk);ct(8);word_running=1;wt(180);ct(8);
 check(identity_fault&&config_error&&bad_pairs>0&&good_pairs==0,
       "post-FS clock loss remains sticky identity fault");report("clock_loss_after_FS");
 $display("RESULT: PASS RESTRICTED_HDR_BOUNDARY_QUALIFICATION cases=%0d checks=%0d",cases,checks);$finish;
end
initial begin #150000000;$fatal(1,"bounded qualification watchdog");end

endmodule
