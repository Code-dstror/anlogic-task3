`timescale 1ns/1ps
module tb_hdr_boundary;
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
wire [31:0] fs0,fs1;wire [146:0] token0,token1;wire token0_v,token1_v,token0_r,token1_r;
wire gate_ready0,gate_ready1;reg stall_tokens=0;
assign token0_r=gate_ready0&&!stall_tokens;
assign token1_r=gate_ready1&&!stall_tokens;
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
 .I_lan_data_in(data[k*8+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(phy_done),
 .O_data_out_vaild(byte_valid[k]),.O_data_out(bytes[k*8+:8]));
end endgenerate
csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(word_clk),.I_reset_n(decoder_n),
 .I_enable(1'b1),.I_packet_done(phy_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(),
 .I_word_in(bytes),.I_valid_in(byte_valid),.O_word_out(aligned),.O_valid_out(av),.o_diag_taps());
csi_rx_word_gear_box #(.MIPI_LAN(4)) gb(.I_word_clock(word_clk),.I_reset_n(decoder_n),.I_enable(1'b1),
 .I_lane_data(aligned),.I_lane_data_valid(av),.O_word_out(geared),.O_valid_out(gv));
assign phy_done=done&&!continuation;
// Actual production crop and official asynchronous token FIFOs are included.
// Only height is reduced to one sensor row for bounded geometry checks.
real_hdr_csi_capture_stream #(.SENSOR_HEIGHT(1),.CROP_Y(0),.HEIGHT(1)
`ifdef PHYSICAL_BURST_MODE
 ,.INDEPENDENT_BURSTS(1)
`endif
 ) rx(
 .i_word_clk(word_clk),.i_pixel_clk(pixel_clk),.i_reset_n(decoder_n),.i_decoder_reset_n(1'b1),
 .i_identity_rst_n(cohort_n),.i_publish_enable(1'b1),.i_cycle_enable(written),
 .i_word(word_direct?direct_data:geared),.i_word_valid(word_direct?valid:gv),
 .o_fifo_write_ready(),.o_wait_for_sync(wait_sync),.o_packet_done(done),.o_packet_continue(continuation),
 .o_identity_fault(identity_fault),.m0_data(token0),.m1_data(token1),.m0_valid(token0_v),.m1_valid(token1_v),
 .m0_ready(token0_r),.m1_ready(token1_r),.o_crc_errors(crc_errors),.o_overflow_errors(overflow_errors),
 .o_format_errors(format_errors),.o_sequence_count0(fs0),.o_sequence_count1(fs1),
 .o_fs0_observe_valid(),.o_fs1_observe_valid(),.o_fs0_number(),.o_fs1_number());
wire pair_event,pair_ok,pair_event_cfg,pair_ok_cfg,pair_overflow,stable,config_error,xclr,scl;
wire [127:0] cfg_diag;wire [31:0] pair_diag;wire [47:0] pair_counts;
wire [31:0] good_pairs,bad_pairs,not_admitted;
wire source0_valid,source1_valid,source_ok;wire [7:0] source_error;
integer source_good_count=0,source_bad_count=0;
always @(posedge pixel_clk or negedge cohort_n)
 if(!cohort_n)begin source_good_count=0;source_bad_count=0;end
 else if(source0_valid||source1_valid)begin
  if(source_ok)source_good_count=source_good_count+1;else source_bad_count=source_bad_count+1;
 end
real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(1000000)) gate(
 .i_clk(pixel_clk),.i_reset_n(cohort_n),.i_fault(identity_fault||receive_fault),.i_stable(stable),
 .i_admit_enable(1'b1),.i_session(32'd1),.i_epoch(32'd0),.i_time(64'd100000),.i_time_valid(1'b1),
 .i_capture0_idle(1'b1),.i_capture1_idle(1'b1),.s0_data(token0),.s1_data(token1),
 .s0_valid(token0_v&&!stall_tokens),.s1_valid(token1_v&&!stall_tokens),.s0_ready(gate_ready0),.s1_ready(gate_ready1),
 .m0_data(),.m1_data(),.m0_valid(),.m1_valid(),.m0_sof(),.m1_sof(),.m0_eol(),.m1_eol(),.m0_abort(),.m1_abort(),
 .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),.o_metadata0(),.o_metadata1(),
 .o_source0_valid(source0_valid),.o_source1_valid(source1_valid),.i_source0_ready(1'b1),.i_source1_ready(1'b1),
 .o_source_session(),.o_source_epoch(),.o_source0_sequence(),.o_source1_sequence(),.o_source_ok(source_ok),.o_source_error(source_error),
 .o_pair_event(pair_event),.o_pair_ok(pair_ok),.o_diag_pair(pair_diag),.o_diag_counts(pair_counts),
 .o_good_pairs(good_pairs),.o_bad_pairs(bad_pairs),.o_not_admitted_pairs(not_admitted),.o_quiet());
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
 if(rx.u_parser.u_long.uncertain_header&&!uncertain)first_uncertain_word=word_direct?direct_data:geared;
 if(rx.u_parser.u_long.uncertain_header)uncertain=uncertain+1;
end
always @(posedge pixel_clk)if(cohort_n&&token0_v&&token0_r&&!token0[42]&&token0[46:43]==7)fs_token0=fs_token0+1;
task wt(input integer n);repeat(n)begin @(negedge word_clk);end endtask
task ct(input integer n);repeat(n)begin @(negedge cfg_clk);end endtask
task check(input bit yes,input string why);begin checks=checks+1;if(!yes)$fatal(1,"%s cfg%032h pair%08h fs%0d/%0d identity%0d uncertain%0d",why,cfg_diag,pair_diag,fs0,fs1,identity_fault,uncertain);end endtask
task cold(input bit watching);
begin cohort_n=0;front_n=0;data='1;direct_data='1;valid=0;start=0;word_running=1;stall_tokens=0;
slave_low=0;transfer=0;ack_release=0;bit_count=0;watch_enable=watching;use_watchdog=watching;word_direct=0;
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
reg [31:0] t,last_bytes;
reg [15:0] natural_crc;
integer seed,n;
`ifdef PHYSICAL_BURST_MODE
integer physical_gap=20;
task finish_physical(input [31:0] tail_word,input integer hold_cycles);
begin data=tail_word;valid=0;wt(hold_cycles);end endtask
task physical_short(input integer vc,dt,number);
begin burst_start();word(header(vc,dt,number));finish_physical('1,physical_gap);end endtask
task physical_embedded(input integer vc,wc,seed);
integer a,b;reg [31:0] w;reg [15:0] c;reg [7:0] v;
begin burst_start();word(header(vc,6'h12,wc));c=16'hffff;
for(a=0;a<wc+2;a=a+4)begin w='1;
for(b=0;b<4;b=b+1)begin
 if(a+b<wc)begin v=8'(a+b+seed);c=crc_byte(c,v);w[b*8+:8]=v;end
 else if(a+b==wc)w[b*8+:8]=c[7:0];
 else if(a+b==wc+1)w[b*8+:8]=c[15:8];
end word(w);end finish_physical('1,physical_gap);end endtask
task physical_raw(input integer vc,seed,corrupt);
integer a;reg [15:0] c;reg [31:0] last,tail_word;
begin c=16'hffff;
for(a=0;a<2916;a=a+1)c=crc_byte(c,8'(a+seed));
last={8'(2915+seed),8'(2914+seed),c[15:8],c[7:0]};
for(a=0;a<4;a=a+1)tail_word[a*8+:8]=last[a*8+7]?8'h00:8'hff;
burst_start();raw12(vc,2916,seed,corrupt,tail_word);finish_physical(tail_word,physical_gap);end endtask
task physical_pair(input integer frame_number);
begin physical_short(0,0,frame_number);physical_short(1,0,frame_number);
physical_raw(0,1,0);physical_raw(1,33,0);
physical_short(0,1,frame_number);physical_short(1,1,frame_number);end endtask
initial begin
 // Production-mode candidates are deliberately qualified only for fresh
 // SoT per packet. The general default parser retains continuous bursts.
 for(mask=0;mask<16;mask=mask+1)begin
  t=0;for(j=0;j<4;j=j+1)t[j*8+:8]=mask[j]?8'hff:0;
  cold(0);burst_start();word(header(0,0,1));trail(t);
  check(fs0==1&&fs1==0&&!identity_fault&&!config_error,"packet completion rejects arbitrary in-flight trail without fake FS");
  report($sformatf("physical_short_trail_%08h",t));
 end
 for(seed=1;seed<=33;seed=seed==1?5:(seed==5?33:34))begin
  cold(0);physical_short(0,0,1);physical_raw(0,seed,0);ct(8);
  check(fs0==1&&!identity_fault&&!config_error&&bad_pairs==0,"natural RAW12 tails are outside completed packet");
  report($sformatf("physical_natural_RAW12_seed%0d",seed));
 end
 cold(0);physical_short(0,0,0);physical_short(1,0,0);
 for(n=0;n<8;n=n+1)physical_embedded(2,n,n+1);
 physical_raw(0,1,0);physical_raw(1,33,0);
 physical_short(0,1,0);physical_short(1,1,0);ct(20);
 check(fs0==1&&fs1==1&&good_pairs==1&&!identity_fault&&!config_error&&cfg_diag[31:24]==1,"fresh SoT FS0 / VC1 / embedded WC residues / RAW12 complete pair");
 report("physical_fresh_SoT_FS0_VC1_embedded_mod4_pair");
 // No extra fixed holdoff is inserted. Eight byte clocks of trail and five
 // zero prepare-byte clocks are the shortest exercised digital envelope;
 // no analog LP timing qualification is inferred from that fixture.
 for(physical_gap=8;physical_gap<=20;physical_gap=physical_gap+4)begin
  cold(0);physical_short(0,0,0);
  for(n=0;n<4;n=n+1)physical_embedded(2,n,n+1);
  physical_short(1,0,0);ct(8);
  check(fs0==1&&fs1==1&&!identity_fault&&!config_error,"short / WC0-3 next-SoT reacquisition");
  report($sformatf("physical_reacquisition_trail_cycles%0d",physical_gap));
 end
 physical_gap=20;
 cold(0);physical_short(0,0,1);burst_start();word(header(1,0,1)^32'h00000003);trail('1);
 check(identity_fault&&config_error&&bad_pairs==1&&pair_diag[23:16]==9&&fs1==0,"fresh SoT bad header still revokes identity and faults owner");
 report("physical_bad_header_negative");
 cold(0);physical_short(0,0,1);physical_raw(0,1,1);ct(8);
 check(!identity_fault&&!config_error&&crc_errors>0&&bad_pairs==1&&pair_diag[23:16]==2,"bad CRC remains a negative pair");
 report("physical_bad_CRC_negative");
 cold(0);stall_tokens=1;
 for(n=0;n<3;n=n+1)physical_pair(n+1);
 stall_tokens=0;wt(4000);ct(20);
 check(overflow_errors>0&&bad_pairs>0&&good_pairs<3,"official FIFO backpressure cannot create successful overrun frame");
 report("physical_FIFO_overflow_negative");
 cold(1);wt(200);ct(10);physical_short(0,0,1);ct(8);
 check(fs_token0==1,"physical FS delivered before actual clock stop");
 word_running=0;repeat(1100)@(negedge ref_clk);ct(8);word_running=1;wt(180);ct(8);
 check(identity_fault&&config_error&&bad_pairs==1&&pair_diag[23:16]==9,"physical post-FS clock loss remains sticky negative");
 report("physical_post_FS_clock_loss_negative");
 // Preserve the real owner threshold: eight complete good pairs qualify
 // STABLE. Only the ninth pair is admitted to SOURCE output. An actual bad
 // CRC then publishes a negative SOURCE and restarts eight-pair warmup.
 cold(0);
 for(n=0;n<8;n=n+1)begin physical_pair(n+1);ct(20);end
 check(stable&&!config_error&&good_pairs==8&&source_good_count==0&&bad_pairs==0,"eight real good pairs qualify stable without premature SOURCE");
 physical_pair(9);ct(20);
 check(stable&&good_pairs==9&&source_good_count==1&&source_bad_count==0,"ninth real pair admitted successfully after warmup");
 report("physical_eight_pair_warmup_ninth_SOURCE");
 physical_short(0,0,10);physical_short(1,0,10);physical_raw(0,1,1);physical_raw(1,33,0);
 physical_short(0,1,10);physical_short(1,1,10);ct(20);
 check(!stable&&!config_error&&bad_pairs==1&&crc_errors>0&&source_bad_count==1&&!identity_fault,"bad CRC after stable produces negative SOURCE and restarts warmup");
 for(n=0;n<8;n=n+1)begin physical_pair(n+11);ct(20);end
 check(stable&&!config_error&&good_pairs==17&&source_good_count==1,"eight subsequent pairs restore stable after CRC negative");
 physical_pair(19);ct(20);
 check(source_good_count==2&&source_bad_count==1&&good_pairs==18&&!identity_fault,"recovered stable admits subsequent real SOURCE");
 report("physical_CRC_negative_eight_pair_recovery_SOURCE");
 $display("RESULT: PASS HDR_PHYSICAL_BURST_CANDIDATE cases=%0d checks=%0d ASSUMPTION_NOT_BOARD_CONFIRMED no_force",cases,checks);$finish;
end
`else
initial begin
 // A packet boundary is generated by the actual delayed parser feedback,
 // not by dropping an invented source-valid after each header.
 cold(0);burst_start();word(header(0,0,1));word(header(1,0,1));
 raw12(0,2916,1,0,'1);raw12(1,2916,7,0,'1);
 word(header(0,1,1));word(header(1,1,1));trail('1);
 check(!identity_fault&&!config_error&&good_pairs==1,"clean one-row RAW12 pair baseline");report("clean_2916_crc_allones_tail");
 for(mask=0;mask<16;mask=mask+1)begin
  t=0;for(j=0;j<4;j=j+1)t[j*8+:8]=mask[j]?8'hff:0;
  cold(0);burst_start();word(header(0,0,1));trail(t);
  if(mask==15)check(!identity_fault&&!config_error,"allones known tail is accepted");
  if(identity_fault)check(config_error&&cfg_diag[15:12]==8&&cfg_diag[47:32]==139&&cfg_diag[63:48]==0&&!xclr,"tail-driven parser fault reaches real owner after successful I2C");
  report($sformatf("short_FS_tail_%08h",t));
 end
 // RAW12 WC2916 mod4=0: CRC occupies lanes0/1, unused lanes2/3 and a
 // following full trail word carry the same per-lane trail pattern.
 cold(0);burst_start();word(header(0,0,1));raw12(0,2916,31,0,32'h00ff00ff);trail(32'h00ff00ff);
 check(identity_fault&&config_error&&bad_pairs==1&&not_admitted==1&&pair_diag[23:16]==9,"RAW12 real chain reproduces report signature");report("RAW12_2916_mixed_trail");
 // Physically motivated trail construction, distinct from the stress matrix:
 // CSI bytes are LSB-first, so the last serial bit is each lane byte's bit7.
 // Derive each first trail byte as the opposite static level. Lanes0/1 end
 // with CRC low/high; lanes2/3 end with the last payload group bytes.
 for(seed=1;seed<=5;seed=seed+4)begin
  natural_crc=16'hffff;
  for(n=0;n<2916;n=n+1)natural_crc=crc_byte(natural_crc,8'(n+seed));
  last_bytes={8'(2915+seed),8'(2914+seed),natural_crc[15:8],natural_crc[7:0]};
  for(j=0;j<4;j=j+1)t[j*8+:8]=last_bytes[j*8+7]?8'h00:8'hff;
  $display("NATURAL seed=%0d WC=2916 CRC=%04h last_lane_bytes=%08h derived_tail=%08h CRC_word=%08h",seed,natural_crc,last_bytes,t,{t[31:16],natural_crc});
  cold(0);burst_start();word(header(0,0,1));raw12(0,2916,seed,0,t);trail(t);
  if(seed==1)begin
   check(natural_crc==16'heb76&&t==32'hffff00ff,"independent CRC and last-bit trail reference");
   check(identity_fault&&config_error&&bad_pairs==1&&not_admitted==1&&pair_diag[23:16]==9,"derived natural mixed trail reproduces signature");
  end else begin
   check(natural_crc==16'h6e70&&t==32'hffffffff,"independent allones natural trail reference");
   check(!identity_fault&&!config_error&&bad_pairs==0,"natural allones trail control remains healthy");
  end
  report($sformatf("natural_RAW12_seed%0d_tail_%08h",seed,t));
 end
 // A legal RAW12 payload can leave every lane's last serial bit high.
 // Its physically derived all-zero trail is byte-identical to legal FS0.
 seed=33;natural_crc=16'hffff;
 for(n=0;n<2916;n=n+1)natural_crc=crc_byte(natural_crc,8'(n+seed));
 last_bytes={8'(2915+seed),8'(2914+seed),natural_crc[15:8],natural_crc[7:0]};
 for(j=0;j<4;j=j+1)t[j*8+:8]=last_bytes[j*8+7]?8'h00:8'hff;
 cold(0);burst_start();word(header(0,0,1));raw12(0,2916,seed,0,t);trail(t);
 check(natural_crc==16'hedf8&&last_bytes==32'h8483edf8&&t==0,"independent physically derived all-zero trail");
 check(fs0>1&&config_error,"natural zero trail fabricates FS and faults owner");
 report("natural_RAW12_seed33_zero_trail_FS_ambiguity");
 // Known corrupt CRC is a distinct negative terminal, not header identity loss.
 cold(0);burst_start();word(header(0,0,1));raw12(0,2916,1,1,'1);trail('1);
 check(!identity_fault&&!config_error&&crc_errors>0,"bad CRC alone is not sticky header identity fault");report("corrupt_crc_negative_control");
 // A reset before any target FS must retain startup trust; after a real FS
 // it intentionally invalidates that cohort. No final fault is forced.
 cold(1);wt(200);ct(10);word_running=0;repeat(1100)@(negedge ref_clk);
 ct(8);word_running=1;wt(180);ct(8);check(config_error&&fs0==0&&bad_pairs==0,"pre-FS clock loss differs from observed active-pair signature");report("clock_loss_before_FS");
 cold(1);wt(200);ct(10);
 burst_start();word(header(0,0,1));trail('1);check(fs_token0==1,"pre-stop FS was received through real FIFO");
 word_running=0;repeat(1100)@(negedge ref_clk);ct(8);word_running=1;wt(180);ct(8);
 check(identity_fault&&config_error&&bad_pairs==1&&pair_diag[23:16]==9,"post-FS clock loss reproduces sticky identity and owner fault");report("clock_loss_after_FS");
 check(fault_cases>=8,"nonones tail matrix exercised distinct fault cases");
 $display("RESULT: PASS HDR_CAUSAL_REPRODUCTION cases=%0d checks=%0d fault_cases=%0d no_force_no_production_edits",cases,checks,fault_cases);$finish;
end
`endif
initial begin #100000000;$fatal(1,"bounded watchdog");end
endmodule
