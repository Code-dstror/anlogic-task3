`timescale 1ns/1ps
module tb_full_overlap_rx;
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
wire [191:0] hdr_counts;wire [63:0] hdr_progress;wire [31:0] hdr_raw_header,cancel_diag;
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
 .I_lan_data_in(data[k*8+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(phy_done),
 .O_data_out_vaild(byte_valid[k]),.O_data_out(bytes[k*8+:8]),.o_diag_offset(),.o_diag_found());
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
wire pair_event,pair_ok,pair_event_cfg,pair_ok_cfg,pair_overflow,stable,config_error,xclr,scl;
wire [127:0] cfg_diag;wire [31:0] pair_diag;wire [47:0] pair_counts;
wire [31:0] good_pairs,bad_pairs,not_admitted;
real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(1000000)) gate(
 .i_clk(pixel_clk),.i_reset_n(cohort_n),.i_fault(identity_fault||receive_fault),.i_stable(stable),
 .i_admit_enable(1'b1),.i_session(32'd1),.i_epoch(32'd0),.i_time(64'd100000),.i_time_valid(1'b1),
 .i_capture0_idle(1'b1),.i_capture1_idle(1'b1),.s0_data(token0),.s1_data(token1),
 .s0_valid(token0_v),.s1_valid(token1_v),.s0_ready(token0_r),.s1_ready(token1_r),
 .m0_data(),.m1_data(),.m0_valid(),.m1_valid(),.m0_sof(),.m1_sof(),.m0_eol(),.m1_eol(),.m0_abort(),.m1_abort(),
 .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),.o_metadata0(),.o_metadata1(),
 .o_source0_valid(),.o_source1_valid(),.i_source0_ready(1'b1),.i_source1_ready(1'b1),
 .o_source_session(),.o_source_epoch(),.o_source0_sequence(),.o_source1_sequence(),.o_source_ok(),.o_source_error(),
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
begin cohort_n=0;front_n=0;data='1;direct_data='1;valid=0;start=0;word_running=1;
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
// Testbench-only passive observations; no production diagnostic ports/state.
reg [31:0] observed_fe0=0,observed_fe1=0,observed_raw=0;
wire parser_header_slot=(&rx.u_parser.wait_sync)||(&rx.u_parser.boundary_open);
always @(posedge word_clk)begin
 if(!rx.identity_word_reset_n)begin observed_fe0<=0;observed_fe1<=0;observed_raw<=0;end
 else if(rx.u_parser.packet_valid&&rx.u_parser.header_good&&parser_header_slot)begin
  if(rx.u_parser.header_corrected[5:0]==1)begin
   if(rx.u_parser.header_corrected[7:6]==0)observed_fe0<=observed_fe0+1;
   if(rx.u_parser.header_corrected[7:6]==1)observed_fe1<=observed_fe1+1;
  end
  if(rx.u_parser.header_corrected[5:0]==6'h2c)observed_raw<=rx.u_parser.packet_word;
 end
end
assign hdr_counts={rx.g_member[1].u_crop.o_geometry_errors,rx.g_member[0].u_crop.o_geometry_errors,
 rx.g_member[1].u_crop.o_complete_frames,rx.g_member[0].u_crop.o_complete_frames,observed_fe1,observed_fe0};
assign hdr_progress={rx.g_member[1].u_crop.group_count,rx.g_member[1].u_crop.row_count,
 rx.g_member[0].u_crop.group_count,rx.g_member[0].u_crop.row_count};
assign hdr_raw_header=observed_raw;
assign cancel_diag={16'd0,pair_diag[31:16]};

integer retained,group_number,skip_count=0,pair_ok_count=0;
reg [15:0] skipped_groups=0,retained_groups=0;
reg [31:0] observed_pair_fe_group=0;
always @(posedge pixel_clk)begin
 if(!cohort_n)begin skip_count=0;pair_ok_count=0;skipped_groups=0;retained_groups=0;observed_pair_fe_group<=0;end
 else begin
  // Passive tokens bind true FE and consumed FS to transmitter identity,
  // independently of which one of the two context entries owns the group.
  if(token1_v&&token1_r&&!token1[42]&&token1[46:43]==6)
   observed_pair_fe_group<=token1[78:47];
  if(token0_v&&token0_r&&!token0[42]&&token0[46:43]==7&&!gate.fs_accept[0])begin
   skip_count=skip_count+1;
   if(token0[78:47]>=1&&token0[78:47]<=16)skipped_groups[token0[78:47]-1]=1'b1;
  end
  if(pair_event&&pair_ok)begin
   pair_ok_count=pair_ok_count+1;
   if(observed_pair_fe_group>=1&&observed_pair_fe_group<=16)retained_groups[observed_pair_fe_group-1]=1'b1;
  end
 end
end
task initial_members(input integer number,seed);
begin
 word(header(0,0,number));word(header(1,0,number));
 raw12(0,2916,seed,0,'1);raw12(1,2916,seed+6,0,'1);
end endtask
task overlapping_physical_cycles(input integer number,seed);
begin
 initial_members(number,seed);
 // Exact required input order. LONG(g) completes; next LONG FS is already
 // on the wire before SHORT(g) completes. Both members of the retained
 // next group still carry their complete real raster, CRC and FE.
 word(header(0,1,number));word(header(0,0,number+1));
 word(header(1,1,number));word(header(1,0,number+1));
 raw12(0,2916,seed+1,0,'1);raw12(1,2916,seed+7,0,'1);
 word(header(0,1,number+1));word(header(1,1,number+1));
end endtask
task report_full(input string name);
begin
 report(name);
 $display("FULL_RX %s FE=%0d/%0d complete=%0d/%0d geometry=%0d/%0d row_group=%016h raw_header=%08h CRC=%0d overflow=%0d format=%0d skipped=%0d skipped_mask=%04h kept_mask=%04h observed_pair_ok=%0d cancel=%08h cfg_good=%0d",
 name,hdr_counts[31:0],hdr_counts[63:32],hdr_counts[95:64],hdr_counts[127:96],
 hdr_counts[159:128],hdr_counts[191:160],hdr_progress,hdr_raw_header,
 crc_errors,overflow_errors,format_errors,skip_count,skipped_groups,retained_groups,
 pair_ok_count,cancel_diag,cfg_diag[95:80]);
end endtask
initial begin
 cold(0);burst_start();initial_members(1,1);
 word(header(0,1,1));word(header(1,1,1));trail('1);ct(12);
 check(good_pairs==1&&bad_pairs==0&&skip_count==0&&pair_ok_count==1,
       "ordinary pair passes real RX/FIFO/gate path");
 check(!identity_fault&&!config_error&&crc_errors==0&&overflow_errors==0&&format_errors==0,
       "ordinary pair remains clean");
 check(hdr_counts[127:0]=={32'd1,32'd1,32'd1,32'd1}&&hdr_counts[191:128]==0,
       "ordinary real FE and complete observations match both members");
 report_full("ordinary_nonoverlap_pair");

 cold(0);burst_start();
 for(retained=0;retained<8;retained=retained+1)begin
  group_number=retained*2+1;
  overlapping_physical_cycles(group_number,retained+1);
 end
 trail('1);ct(16);
 check(fs0==16&&fs1==16&&skip_count==0&&skipped_groups==0,
       "sixteen physical cycles have no overlap skips");
 check(good_pairs==16&&bad_pairs==0&&pair_ok_count==16&&retained_groups==16'hffff,
       "all sixteen physical groups produce real good events");
 check(stable&&written&&!config_error&&cfg_diag[15:12]==7&&cfg_diag[95:80]>=8,
       "retained pairs qualify real serial-I2C sensor owner");
 check(!identity_fault&&crc_errors==0&&overflow_errors==0&&format_errors==0&&cancel_diag==0,
       "continuous full retained payload drains finite FIFOs without faults or cancellations");
 check(hdr_counts[127:0]=={32'd16,32'd16,32'd16,32'd16}&&hdr_counts[191:128]==0,
       "all sixteen wire cycles complete both actual crop rasters");
 check(not_admitted>=8&&not_admitted<16&&cfg_diag[47:32]==139&&cfg_diag[63:48]==0,
       "warmup remains unadmitted with 139 actual ACKs and no I2C error");
 report_full("sixteen_physical_cycles_sixteen_retained_owner_stable");

 cold(0);burst_start();initial_members(1,1);
 // Intentionally omit old LONG FE; a new LONG FS is not eligible for the
 // overlap exception. New group FEs below also have no raster and must fail.
 word(header(0,0,2));word(header(1,1,1));word(header(1,0,2));
 word(header(0,1,2));word(header(1,1,2));trail('1);wt(200);ct(16);
 check(good_pairs==0&&pair_ok_count==0&&bad_pairs>0&&!stable,
       "missing old FE and new FS reentry never fabricate good or stable");
 check(cancel_diag!=0&&skip_count==0,
       "incomplete old member still produces reason5 evidence rather than overlap skip");
 check(!identity_fault&&crc_errors==0&&overflow_errors==0,
       "negative terminal comes from frame boundaries rather than forced identity/CRC/overflow");
 report_full("missing_old_FE_reentry_negative");
 $display("RESULT: PASS FULL_OVERLAP_RX_TWO_CONTEXT cases=%0d checks=%0d",cases,checks);$finish;
end
initial begin #30000000;$fatal(1,"bounded full RX overlap watchdog");end

endmodule
