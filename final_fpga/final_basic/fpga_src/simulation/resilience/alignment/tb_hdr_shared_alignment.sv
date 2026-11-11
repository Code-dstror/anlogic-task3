`timescale 1ns/1ps
module tb_hdr_shared_alignment;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,direct_valid=0,ready0=1,ready1=1;
 reg [31:0] data=32'hffffffff,direct_data=0;
 reg [1:0] source_mode=0;
 wire [31:0] byte_data,aligned,geared;
 wire [3:0] byte_valid;
 wire av,gv,done,wait_sync,continuation,phy_done;
 wire [31:0] word_in=source_mode==2 ? direct_data : geared;
 wire word_valid=source_mode==2 ? direct_valid : gv;
 wire [31:0] align_in=source_mode==1 ? byte_data : data;
 wire [3:0] align_valid=source_mode==1 ? byte_valid : {4{valid}};
 wire [47:0] p0,p1;wire v0,v1,s0,s1,e0,e1,a0,a1;
 wire [3:0] c0,c1;wire [31:0] seq0,seq1,g0,g1;
 wire fault,ecc_error,crc_error,length_error;
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:g_byte
  csi_rx_byte_align_observed byte_aligner(.I_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
   .I_lan_data_in(data[lane*8+:8]),.I_wait_for_sync(wait_sync),.I_packet_done(phy_done),
   .O_data_out_vaild(byte_valid[lane]),.O_data_out(byte_data[lane*8+:8]),
   .o_diag_offset(),.o_diag_found());
 end endgenerate
 csi_rx_word_align_observed #(.MIPI_LAN(4)) aligner(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_packet_done(phy_done),.I_wait_for_sync(wait_sync),.O_packet_done_out(),
  .I_word_in(align_in),.I_valid_in(align_valid),.O_word_out(aligned),.O_valid_out(av),.o_diag_taps());
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gearbox(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_lane_data(aligned),.I_lane_data_valid(av),.O_word_out(geared),.O_valid_out(gv));
`ifdef BASELINE
 assign continuation=0;
`endif
 assign phy_done=done && !continuation;
 real_hdr_csi_dual_word_rx parser(.i_clk(clk),.i_reset_n(rst),.i_identity_rst_n(rst),.i_cycle_enable(1'b1),
  .i_word(word_in),.i_word_valid(word_valid),.i_long_ready(ready0),.i_short_ready(ready1),
  .o_long_data(p0),.o_short_data(p1),.o_long_valid(v0),.o_short_valid(v1),
  .o_long_sof(s0),.o_short_sof(s1),.o_long_eol(e0),.o_short_eol(e1),
  .o_long_abort(a0),.o_short_abort(a1),.o_long_error(c0),.o_short_error(c1),
  .o_long_sequence_count(seq0),.o_short_sequence_count(seq1),.o_long_group(g0),.o_short_group(g1),
  .o_long_event_sequence(),.o_short_event_sequence(),.o_long_identity_valid(),.o_short_identity_valid(),
  .o_long_cycle_valid(),.o_short_cycle_valid(),.o_long_event_frame_number(),.o_short_event_frame_number(),
  .o_long_fs_observe_valid(),.o_short_fs_observe_valid(),.o_long_fs_number(),.o_short_fs_number(),
  .o_long_fs_observe_sequence(),.o_short_fs_observe_sequence(),.o_long_fs_observe_trusted(),.o_short_fs_observe_trusted(),
  .o_identity_fault(fault),.o_wait_for_sync(wait_sync),.o_packet_done(done),
`ifndef BASELINE
  .o_packet_continue(continuation),
`endif
  .o_header_ecc_error(ecc_error),.o_payload_crc_error(crc_error),.o_length_error(length_error));
 function [5:0] ecc(input [23:0] h);
 begin
  ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
  ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);
 end endfunction
 function [31:0] header(input integer vc,input integer dt,input integer wc);
 reg [23:0] h;begin h={16'(wc),2'(vc),6'(dt)};header={2'd0,ecc(h),h};end endfunction
 function [15:0] crc_byte(input [15:0] c,input [7:0] b);
 reg [15:0] n;integer k;begin n=c^b;for(k=0;k<8;k=k+1)n=n[0] ? (n>>1)^16'h8408 : n>>1;crc_byte=n;end endfunction
 function [47:0] expected_pixels(input integer group_index);
 reg [47:0] b;integer k;begin
  for(k=0;k<6;k=k+1)b[k*8+:8]=8'(group_index*6+k+1);
  expected_pixels={b[39:32],b[47:44],b[31:24],b[43:40],b[15:8],b[23:20],b[7:0],b[19:16]};
 end endfunction
 integer fs[0:1],fe[0:1],ab[0:1],pixels[0:1],lines[0:1],pixel_group[0:1],continued,forwarded,checks=0;
 reg held0=0,held1=0;reg [55:0] hold0,hold1;
 always @(posedge clk)begin
  if(!rst)begin
   fs[0]=0;fs[1]=0;fe[0]=0;fe[1]=0;ab[0]=0;ab[1]=0;pixels[0]=0;pixels[1]=0;lines[0]=0;lines[1]=0;
   held0=0;held1=0;continued=0;forwarded=0;pixel_group[0]=0;pixel_group[1]=0;
  end else begin
   if(held0 && (!v0 || {p0,s0,e0,a0,c0}!==hold0))$fatal(1,"long output changed under stall");
   if(held1 && (!v1 || {p1,s1,e1,a1,c1}!==hold1))$fatal(1,"short output changed under stall");
   held0=v0&&!ready0;held1=v1&&!ready1;hold0={p0,s0,e0,a0,c0};hold1={p1,s1,e1,a1,c1};
   if(v0&&ready0)begin
    if(c0==7)begin fs[0]=fs[0]+1;pixel_group[0]=0;end else if(c0==6)fe[0]=fe[0]+1;else if(a0)ab[0]=ab[0]+1;
    else if(c0==0)begin
     if(p0!==expected_pixels(pixel_group[0]))$fatal(1,"long RAW12 byte/lane order");
     pixels[0]=pixels[0]+1;pixel_group[0]=pixel_group[0]+1;if(e0)begin lines[0]=lines[0]+1;pixel_group[0]=0;end
    end
   end
   if(v1&&ready1)begin
    if(c1==7)begin fs[1]=fs[1]+1;pixel_group[1]=0;end else if(c1==6)fe[1]=fe[1]+1;else if(a1)ab[1]=ab[1]+1;
    else if(c1==0)begin
     if(p1!==expected_pixels(pixel_group[1]))$fatal(1,"short RAW12 byte/lane order");
     pixels[1]=pixels[1]+1;pixel_group[1]=pixel_group[1]+1;if(e1)begin lines[1]=lines[1]+1;pixel_group[1]=0;end
    end
   end
   if(done&&continuation)begin
    if(phy_done || !word_valid || word_in[31:30]!=0)$fatal(1,"feedback lookahead was not the current complete header");
    continued=continued+1;
   end
   if(phy_done)forwarded=forwarded+1;
  end
 end
 task tick;@(negedge clk);endtask
 task cold(input integer mode);begin
  rst=0;source_mode=mode;valid=0;direct_valid=0;data=32'hffffffff;ready0=1;ready1=1;
  repeat(8)tick();rst=1;repeat(8)tick();
 end endtask
 task word(input [31:0] w);begin
  data=w;valid=1;direct_data=w;direct_valid=1;tick();
 end endtask
 task start_burst;begin
  if(source_mode==1)begin data=0;repeat(3)tick();end
  if(source_mode!=2)word(32'hb8b8b8b8);
 end endtask
 task end_burst(input integer gap);begin
  valid=0;direct_valid=0;data=32'hffffffff;direct_data=32'hffffffff;repeat(gap)tick();
 end endtask
 task short_packet(input integer vc,input integer dt,input integer number);word(header(vc,dt,number));endtask
 task long_packet(input integer vc,input integer dt,input integer wc,input integer corrupt);
 integer j,k;reg [31:0] w;reg [15:0] crc;reg [7:0] b;
 begin
  word(header(vc,dt,wc));crc=16'hffff;
  for(j=0;j<wc+2;j=j+4)begin
   w=32'hffffffff;
   for(k=0;k<4;k=k+1)begin
    if(j+k<wc)begin b=8'(j+k+1);crc=crc_byte(crc,b);w[k*8+:8]=b;end
    else if(j+k==wc)w[k*8+:8]=crc[7:0]^(corrupt?8'h01:8'h00);
    else if(j+k==wc+1)w[k*8+:8]=crc[15:8];
   end
   word(w);
  end
 end endtask
 task check(input bit okay,input string why);begin checks=checks+1;if(!okay)$fatal(1,"%s",why);end endtask
 task pair_burst;begin
  start_burst();short_packet(0,0,1);short_packet(1,0,1);
  long_packet(0,6'h2c,12,0);long_packet(1,6'h2c,6,0);
  short_packet(0,1,1);short_packet(1,1,1);end_burst(40);
 end endtask
 integer m,j,gap;
 initial begin
  // Baseline fails this exact functional expectation, rather than passing a
  // reproduction-specific assertion that expects the second FS to disappear.
  cold(0);start_burst();short_packet(0,0,1);short_packet(1,0,1);end_burst(35);
  $display("TWO_FS long=%0d short=%0d fault=%0d",seq0,seq1,fault);
  check(seq0==1&&seq1==1&&!fault,"continuous two-FS lost a member");
  cold(0);start_burst();short_packet(0,0,1);word(32'hffffffff);word(32'h00000000);short_packet(1,0,999);end_burst(40);
  $display("TAIL_LOCK long=%0d short=%0d fault=%0d",seq0,seq1,fault);
  check(seq0==1&&seq1==0&&!fault,"tail marker was scanned past into header-shaped pipeline residue");
  for(m=0;m<3;m=m+1)begin
   cold(m);pair_burst();
   check(seq0==1&&seq1==1&&!fault,"pair sequence / identity");
   check(fs[0]==1&&fs[1]==1&&fe[0]==1&&fe[1]==1,"pair FS / successful FE");
   check(pixels[0]==2&&pixels[1]==1&&lines[0]==1&&lines[1]==1,"CRC-tail pixel/EOL accounting");
   check(ab[0]==0&&ab[1]==0&&!crc_error&&!length_error&&!ecc_error,"clean pair reported error");
   $display("PAIR mode=%0d pixels=%0d/%0d continued=%0d forwarded=%0d PASS",m,pixels[0],pixels[1],continued,forwarded);
  end
  for(m=0;m<2;m=m+1)begin
   cold(m);start_burst();
   for(j=0;j<12;j=j+1)begin short_packet(0,0,j);short_packet(0,1,j);short_packet(1,0,j);short_packet(1,1,j);end
   end_burst(40);
   check(seq0==12&&seq1==12&&fe[0]==12&&fe[1]==12&&!fault,"48 consecutive shorts or vendor sync timeout");
   check(continued>=47,"continuous short chain was not protected by feedback");
   $display("SHORT_CHAIN mode=%0d packets=48 continued=%0d PASS",m,continued);
  end
  // Non-RAW packets cover every WC residue; CRC low may be the final lane
  // of one word and CRC high the first lane of the following word (WC=7).
  cold(0);start_burst();short_packet(0,0,1);short_packet(1,0,1);
  for(j=0;j<8;j=j+1)begin long_packet(2,6'h12,j,0);short_packet(0,2,j);end
  long_packet(0,6'h2c,18,0);long_packet(1,6'h2c,12,0);
  short_packet(0,1,1);short_packet(1,1,1);end_burst(40);
  check(fe[0]==1&&fe[1]==1&&pixels[0]==3&&pixels[1]==2&&!fault&&!crc_error,"WC residues and ignored-VC length");
  $display("WC_MOD4 0/1/2/3 plus CRC-low cross-word PASS");
  // Separate physical SoTs with sticky byte-valid. Try decreasing gaps;
  // Gaps include trail and aligner drain; each next burst also has the
  // explicit pre-sync zero interval required by the real byte aligner.
  for(gap=8;gap<=16;gap=gap+4)begin
   cold(1);start_burst();short_packet(0,0,1);end_burst(gap);
   start_burst();short_packet(1,0,1);end_burst(40);
   check(seq0==1&&seq1==1&&!fault,"separate SoT short-gap resynchronization");
   $display("SEPARATE_SOT gap_word_clocks=%0d PASS",gap);
  end
  // Bad candidate is not scanned past. Identity loss survives the gap;
  // only a coordinated cold reset authorizes a new trusted sequence.
  cold(0);start_burst();short_packet(0,0,1);word(header(1,0,1)^32'h00000003);short_packet(1,0,2);end_burst(40);
  check(fault&&ecc_error&&seq1==0&&fe[0]==0&&ab[0]==1,"bad next header failed open or scanned forward");
  start_burst();short_packet(0,0,3);short_packet(0,1,3);end_burst(40);
  check(fault,"header-loss trust recovered without cohort reset");
  $display("BAD_HEADER fail_closed and sticky identity PASS");
  for(m=0;m<2;m=m+1)begin
   cold(0);start_burst();short_packet(0,0,1);
   if(m==0)long_packet(0,6'h2c,12,1);else long_packet(0,6'h2c,7,0);
   short_packet(0,1,1);short_packet(0,0,2);long_packet(0,6'h2c,6,0);short_packet(0,1,2);end_burst(45);
   check(ab[0]==1&&fe[0]==1&&seq0==2&&!fault,"bad CRC/length successful terminal or failed recovery");
   if(m==0)check(crc_error,"bad CRC not reported");else check(length_error,"bad RAW length not reported");
   $display("BAD_%s negative terminal plus following-frame recovery PASS",m==0?"CRC":"LENGTH");
  end
  cold(2);short_packet(0,0,1);word(header(0,6'h2c,12));word(32'h04030201);end_burst(8);
  short_packet(0,1,1);end_burst(8);
  check(ab[0]==1&&fe[0]==0&&length_error,"truncated packet got successful terminal");
  short_packet(0,0,2);long_packet(0,6'h2c,6,0);short_packet(0,1,2);end_burst(12);
  check(fe[0]==1&&seq0==2,"truncated packet recovery");
  $display("TRUNCATION valid-low negative terminal plus recovery PASS");
  cold(2);ready0=0;short_packet(0,0,1);long_packet(0,6'h2c,24,0);short_packet(0,1,1);end_burst(8);
  ready0=1;repeat(12)tick();check(ab[0]==1&&fe[0]==0,"finite sink stall did not terminate negatively");
  $display("FINITE_STALL output held and negative terminal PASS");
  cold(2);short_packet(0,0,1);word(header(0,6'h2c,12));word(32'h04030201);
  cold(2);pair_burst();check(seq0==1&&seq1==1&&fe[0]==1&&fe[1]==1&&!fault,"reset-mid-packet fresh cohort recovery");
  $display("RESULT: PASS hdr packet boundary checks=%0d; physical EoT absent, zero-tail/header collision not qualified",checks);$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule

