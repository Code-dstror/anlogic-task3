`timescale 1ns/1ps

// Explicit electrical boundary model. All receiver alignment, gearbox,
// parser, official CDC FIFO, continuity guard and source fence are real.
module csi2_ph1_phy_wrapper #(parameter MIPI_LAN=4, parameter DEVICE="PH1A")(
 input I_debug_button,I_ref_clock,I_clk_hs_rx_p,I_reset_n,I_decoder_reset_n,
 input [MIPI_LAN-1:0] I_hs_data_p,input I_enable,I_wait_for_sync,I_packet_done,
 output O_hs_div_clk,O_reset_out,
 output [MIPI_LAN-1:0] O_rx_byte_data_align_vaild,
 output [8*MIPI_LAN-1:0] O_rx_byte_data_align,
 output O_delay_value,O_auto_delay_done,output [7:0] O_dbg_delay,
 output [5:0] O_dbg_best_len,
 output [8*MIPI_LAN-1:0] O_diag_raw_bytes,
 output [3*MIPI_LAN-1:0] O_diag_byte_offset,
 output [MIPI_LAN-1:0] O_diag_byte_found,output [15:0] O_diag_calibration);
 reg test_phy_health=0,test_cal_done=0;
 reg [8*MIPI_LAN-1:0] test_bytes=0;
 reg [MIPI_LAN-1:0] test_valid=0;
 assign O_hs_div_clk=I_clk_hs_rx_p;
 assign O_reset_out=I_reset_n&&test_phy_health;
 assign O_auto_delay_done=test_cal_done;
 assign O_rx_byte_data_align=test_bytes;
 assign O_rx_byte_data_align_vaild=test_valid;
 assign O_delay_value=0;assign O_dbg_delay=8'd16;assign O_dbg_best_len=test_cal_done?6'd16:0;
 assign O_diag_raw_bytes=test_bytes;assign O_diag_byte_offset=0;
 assign O_diag_byte_found=test_valid;assign O_diag_calibration={4'd0,test_cal_done,11'd0};
endmodule

module recovery_receiver_tb;
 parameter [31:0] RNG_INITIAL=32'h3a53c19b;
 reg word_clk=0,pixel_clk=0,outer_reset=0;
 always #5 word_clk=~word_clk;
 always #7 pixel_clk=~pixel_clk;
 reg raw_ready=1,event_gate=1,raw_source_ready=1,native_source_ready=1;
 reg random_stalls=0;
 reg [31:0] rng=RNG_INITIAL;
 reg recovery_quiet_allow=1;
 integer pixel_cycles=0;
 reg [31:0] intentionally_corrupt_sequence=0;
 integer corrupt_raw_beats=0;
 wire [39:0] raw_data;wire raw_valid,raw_sof,raw_eol,raw_identity;
 wire [31:0] raw_sequence,event_sequence;
 wire event_valid,event_identity,event_ok,event_ready;wire [1:0] event_kind;
 wire [3:0] event_error,raw_error;wire raw_abort;
 wire identity_fault,phy_ready,publish,decoder_n,cal_done;
 wire [127:0] diag;
 wire [31:0] ecc_errors,crc_errors,overflow_errors,length_errors;
 real_hdr_physical_csi_rx #(.RX_DIAG_ENABLE(1)) dut(
  .i_ref_clk(word_clk),.i_mipi_clk_p(word_clk),.i_mipi_data_p(4'd0),
  .i_pixel_clk(pixel_clk),.i_reset_n(outer_reset),.i_enable(1'b1),
  .i_hdr_mode(1'b0),.i_hdr_cycle_enable(1'b1),.i_debug_button(1'b1),
  .m_hdr0_data(),.m_hdr1_data(),.m_hdr0_valid(),.m_hdr1_valid(),
  .m_hdr0_ready(1'b1),.m_hdr1_ready(1'b1),
  .o_raw_data(raw_data),.o_raw_valid(raw_valid),.i_raw_ready(raw_ready),.o_raw_sof(raw_sof),.o_raw_eol(raw_eol),
  .m_frame_event_valid(event_valid),.m_frame_event_ready(event_ready),
  .m_frame_event_kind(event_kind),.m_frame_event_ok(event_ok),.m_frame_event_error(event_error),
  .m_frame_event_sequence(event_sequence),.m_frame_event_identity_valid(event_identity),
  .o_raw_sequence(raw_sequence),.o_raw_identity_valid(raw_identity),.o_source_identity_fault(identity_fault),
  .o_rx_diag_word(diag),.o_rx_trace_sample(),.o_rx_trace_trigger(),.o_rx_trace_cohort_n(),.o_rx_trace_enable(),
  .o_frame_abort(raw_abort),.o_error_code(raw_error),.o_header_ecc_error_count(ecc_errors),.o_payload_crc_error_count(crc_errors),
  .o_overflow_error_count(overflow_errors),.o_length_error_count(length_errors),.o_hs_word_clk(),
  .o_auto_delay_done(cal_done),.o_delay_debug(),.o_delay_window(),.o_phy_ready(phy_ready),
  .o_diag_lane_bytes(),.o_diag_lane_valid(),.o_diag_aligned_word(),.o_diag_aligned_valid(),
  .o_diag_geared_word(),.o_diag_geared_valid(),.o_diag_wait_sync(),.o_diag_packet_done(),
  .o_diag_publish_enable(publish),.o_diag_word_reset_n(decoder_n));

 wire quarantine,fence_event_ready,raw_source_valid,native_source_valid,source_idle;
 wire raw_source_ok,native_source_ok;wire [31:0] raw_source_sequence;
 wire [7:0] raw_source_error,native_source_error;
 wire [63:0] native_tag;
 wire [31:0] drop_count,stale_count;
 reg [31:0] context_sequence=0;
 wire event_fire=event_valid&&event_ready;
 assign event_ready=event_gate&&fence_event_ready;
 production_source_identity_guard guard(.clk(pixel_clk),.rst_n(outer_reset),
  .phy_ready(phy_ready),.receive_fault(1'b0),.parser_identity_fault(identity_fault),
  .i_recovery_quiet(recovery_quiet_allow&&source_idle&&!raw_valid),
  .event_valid(event_fire),.event_kind(event_kind),.event_identity_valid(event_identity),.quarantine(quarantine));
 always @(posedge pixel_clk or negedge outer_reset)
  if(!outer_reset)context_sequence<=0;
  else if(event_fire&&event_kind==0)context_sequence<=event_sequence;
 // Geometry/quiet and context are a prompt-completion boundary model.
 // No fabricated frame terminal is supplied: FE/ABORT remain real parser events.
 physical_identity_source_fence fence(.i_clk(pixel_clk),.i_rst_n(outer_reset),
  .i_admit_enable(!quarantine),.i_event_valid(event_valid&&event_gate),.o_event_ready(fence_event_ready),
  .i_event_kind(event_kind),.i_event_ok(event_ok),.i_continuity_fault(quarantine),
  .i_event_error({4'd0,event_error}),.i_event_sequence(event_sequence),.i_event_identity_valid(event_identity),
  .i_context_valid(1'b1),.o_context_ready(),.i_context(576'd0),.i_context_tag({32'd0,context_sequence}),
  .i_context_session(32'd17),.i_context_epoch(32'd23),.i_context_sequence(context_sequence),.i_context_camera(1'b0),
  .i_crop_geometry_done(1'b1),.i_crop_input_quiet(1'b1),.i_rgb_geometry_done(1'b1),.i_rgb_output_quiet(1'b1),
  .i_source_fault(1'b0),.i_source_error(8'd0),.o_capture_frame_enable(),.o_source_idle(source_idle),
  .o_raw_source_valid(raw_source_valid),.i_raw_source_ready(raw_source_ready),.o_raw_source_session(),.o_raw_source_epoch(),
  .o_raw_source_sequence(raw_source_sequence),.o_raw_source_camera(),.o_raw_source_ok(raw_source_ok),.o_raw_source_error(raw_source_error),
  .o_native_source_valid(native_source_valid),.i_native_source_ready(native_source_ready),.o_native_source_context(),.o_native_source_tag(native_tag),
  .o_native_source_ok(native_source_ok),.o_native_source_error(native_source_error),.o_drop_count(drop_count),.o_stale_event_count(stale_count),.i_data_reset_n(outer_reset));

 integer admitted[0:255],raw_taken[0:255],native_taken[0:255];
 integer raw_result[0:255],native_result[0:255],terminal_events[0:255];
 integer successes=0,negatives=0,native_successes=0,native_negatives=0;
 integer fs_seen=0,fe_seen=0,abort_seen=0,raw_beats=0,admit_total=0,checks=0;
 integer raw_stall_cycles=0,event_stall_cycles=0,source_stall_cycles=0;
 reg [31:0] last_parser_sequence=0;
 integer k,seq;reg monitor_event=0,monitor_raw=0,monitor_rs=0,monitor_ns=0;
 reg [39:0] held_event;reg [79:0] held_raw;
 reg [40:0] held_rs;reg [72:0] held_ns;
 // Readies change only away from the consuming edge. A forced all-ready
 // cycle every 19 cycles bounds every independent downstream stall.
 always @(negedge pixel_clk)begin
  if(outer_reset&&random_stalls)begin
   rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   pixel_cycles=pixel_cycles+1;
   raw_ready=(pixel_cycles%19==0)||(|rng[1:0]);
   event_gate=(pixel_cycles%19==0)||(|rng[3:2]);
   raw_source_ready=(pixel_cycles%19==0)||(|rng[5:4]);
   native_source_ready=(pixel_cycles%19==0)||(|rng[7:6]);
  end
 end
 always @(posedge pixel_clk or negedge outer_reset)begin
  if(!outer_reset)begin
   successes=0;negatives=0;native_successes=0;native_negatives=0;
   fs_seen=0;fe_seen=0;abort_seen=0;raw_beats=0;admit_total=0;corrupt_raw_beats=0;
   raw_stall_cycles=0;event_stall_cycles=0;source_stall_cycles=0;
   last_parser_sequence=0;monitor_event=0;monitor_raw=0;monitor_rs=0;monitor_ns=0;
   for(k=0;k<256;k=k+1)begin
    admitted[k]=0;raw_taken[k]=0;native_taken[k]=0;
    raw_result[k]=-1;native_result[k]=-1;terminal_events[k]=0;
   end
  end else begin
   if(dut.u_stream.u_word_core.sequence_counter<last_parser_sequence)$fatal(1,"parser source counter rewound");
   last_parser_sequence=dut.u_stream.u_word_core.sequence_counter;
   if(monitor_event&&publish&&(!event_valid||{event_sequence,event_error,event_kind,event_ok,event_identity}!==held_event))
    $fatal(1,"event changed under stall");
   if(monitor_raw&&publish&&(!raw_valid||{raw_data,raw_sequence,raw_sof,raw_eol,raw_identity,raw_abort,raw_error}!==held_raw))
    $fatal(1,"RAW/ABORT changed under stall");
   if(monitor_rs&&(!raw_source_valid||{raw_source_sequence,raw_source_ok,raw_source_error}!==held_rs))
    $fatal(1,"raw SOURCE changed under stall");
   if(monitor_ns&&(!native_source_valid||{native_tag,native_source_ok,native_source_error}!==held_ns))
    $fatal(1,"native SOURCE changed under stall");
   // PHY loss explicitly asserts the publication/FIFO reset. A held FIFO
   // item may be cancelled there; the independent SOURCE owner must still
   // retire negatively and its ready/valid promise remains checked below.
   monitor_event=publish&&event_valid&&!event_ready;held_event={event_sequence,event_error,event_kind,event_ok,event_identity};
   monitor_raw=publish&&raw_valid&&!raw_ready;held_raw={raw_data,raw_sequence,raw_sof,raw_eol,raw_identity,raw_abort,raw_error};
   monitor_rs=raw_source_valid&&!raw_source_ready;held_rs={raw_source_sequence,raw_source_ok,raw_source_error};
   monitor_ns=native_source_valid&&!native_source_ready;held_ns={native_tag,native_source_ok,native_source_error};
   if(monitor_raw)raw_stall_cycles=raw_stall_cycles+1;
   if(monitor_event)event_stall_cycles=event_stall_cycles+1;
   if(monitor_rs||monitor_ns)source_stall_cycles=source_stall_cycles+1;
   if(raw_valid&&raw_ready&&!raw_abort)begin
    raw_beats=raw_beats+1;
    if(raw_sequence==intentionally_corrupt_sequence)corrupt_raw_beats=corrupt_raw_beats+1;
    else if(raw_identity&&raw_data!=={10'd272,10'd205,10'd138,10'd71})$fatal(1,"RAW10 bytes changed data=%h",raw_data);
   end
   if(event_fire)begin
    seq=event_sequence;
    if(seq>255)$fatal(1,"scoreboard sequence range");
    if(event_kind==0)begin
     fs_seen=fs_seen+1;
     if(!quarantine&&event_identity)begin admitted[seq]=admitted[seq]+1;admit_total=admit_total+1;end
     if(admitted[seq]>1)$fatal(1,"duplicate admission seq=%0d",seq);
    end else if(event_kind==1||event_kind==2)begin
     terminal_events[seq]=terminal_events[seq]+1;
     if(event_kind==1)fe_seen=fe_seen+1;else abort_seen=abort_seen+1;
    end
   end
   if(raw_source_valid&&raw_source_ready)begin
    seq=raw_source_sequence;
    if(seq>255||admitted[seq]!=1||raw_taken[seq]!=0)$fatal(1,"raw SOURCE without unique owner seq=%0d admit=%0d taken=%0d",seq,admitted[seq],raw_taken[seq]);
    raw_taken[seq]=raw_taken[seq]+1;raw_result[seq]=raw_source_ok;
    if(raw_source_ok)successes=successes+1;else negatives=negatives+1;
   end
   if(native_source_valid&&native_source_ready)begin
    seq=native_tag[31:0];
    if(seq>255||admitted[seq]!=1||native_taken[seq]!=0)$fatal(1,"native SOURCE without unique owner seq=%0d",seq);
    native_taken[seq]=native_taken[seq]+1;native_result[seq]=native_source_ok;
    if(native_source_ok)native_successes=native_successes+1;else native_negatives=native_negatives+1;
   end
  end
 end
 function [5:0] ecc(input [23:0] d);
 begin
  ecc[0]=^(d&24'hf12cb7);ecc[1]=^(d&24'hf2555b);ecc[2]=^(d&24'h749a6d);
  ecc[3]=^(d&24'hb8e38e);ecc[4]=^(d&24'hdf03f0);ecc[5]=^(d&24'heffc00);
 end endfunction
 function [15:0] crc_byte(input [15:0] c,input [7:0] b);
  reg [15:0] v;integer j;
  begin v=c^b;for(j=0;j<8;j=j+1)v=v[0]?((v>>1)^16'h8408):(v>>1);crc_byte=v;end
 endfunction
 function [7:0] payload_byte(input integer n);
  begin case(n%5)0:payload_byte=8'h11;1:payload_byte=8'h22;2:payload_byte=8'h33;3:payload_byte=8'h44;default:payload_byte=8'h1b;endcase end
 endfunction
 task tick;begin @(negedge word_clk);#1;end endtask
 task ticks(input integer n);begin repeat(n)tick();end endtask
 task byte_word(input [31:0] data,input [3:0] valid);begin
  dut.u_phy.test_bytes=data;dut.u_phy.test_valid=valid;tick();
 end endtask
 task gap;
  integer n;begin
   byte_word(0,0);n=random_stalls?(rng[12:8]%25):5;ticks(19+n);
  end
 endtask
 task short_packet_mask(input [5:0] dt,input [15:0] number,input [31:0] mask);
  reg [23:0] h;
  begin
   h={number,2'd0,dt};
   byte_word(32'hb8b8b8b8,4'hf);byte_word({2'd0,ecc(h),h}^mask,4'hf);gap();
  end
 endtask
 task short_packet(input [5:0] dt,input [15:0] number);
  begin short_packet_mask(dt,number,0);end
 endtask
 task raw_packet(input integer wc,input integer bad_crc,input [31:0] header_mask);
  reg [23:0] h;reg [15:0] crc;reg [31:0] w;integer n,j,pos;
  begin
   h={wc[15:0],2'd0,6'h2b};crc=16'hffff;
   for(n=0;n<wc;n=n+1)crc=crc_byte(crc,payload_byte(n));
   if(bad_crc!=0)crc=crc^16'h0001;
   byte_word(32'hb8b8b8b8,4'hf);byte_word({2'd0,ecc(h),h}^header_mask,4'hf);
   for(n=0;n<wc+2;n=n+4)begin
    w=0;
    for(j=0;j<4;j=j+1)begin
     pos=n+j;
     if(pos<wc)w[8*j+:8]=payload_byte(pos);
     else if(pos==wc)w[8*j+:8]=crc[7:0];
     else if(pos==wc+1)w[8*j+:8]=crc[15:8];
    end
    byte_word(w,4'hf);
   end
   gap();
  end
 endtask
 task frame(input integer n);
  begin short_packet(0,n);raw_packet(5,0,0);short_packet(1,n);end
 endtask
 task cold;
  begin
   random_stalls=0;recovery_quiet_allow=1;outer_reset=0;intentionally_corrupt_sequence=0;dut.u_phy.test_phy_health=0;dut.u_phy.test_cal_done=0;
   dut.u_phy.test_valid=0;dut.u_phy.test_bytes=0;
   raw_ready=1;event_gate=1;raw_source_ready=1;native_source_ready=1;
   ticks(10);outer_reset=1;dut.u_phy.test_phy_health=1;ticks(14);dut.u_phy.test_cal_done=1;ticks(80);
   if(!publish||!decoder_n||!phy_ready||identity_fault||quarantine)$fatal(1,"cold barrier failed");
   random_stalls=1;
  end
 endtask
 task prefix(input integer n);
  integer j;begin cold();for(j=1;j<=n;j=j+1)frame(j);ticks(100);
   if(successes!=n||native_successes!=n||negatives||native_negatives||identity_fault||quarantine)
    $fatal(1,"healthy prefix failed n=%0d RAW=%0d/%0d native=%0d/%0d",n,successes,negatives,native_successes,native_negatives);
  end
 endtask
 task check_all(input integer good,input integer bad);
  integer j;begin
   ticks(120);
   if(successes!=good||native_successes!=good||negatives!=bad||native_negatives!=bad)
    $fatal(1,"SOURCE count expected=%0d/%0d raw=%0d/%0d native=%0d/%0d",good,bad,successes,negatives,native_successes,native_negatives);
   for(j=0;j<256;j=j+1)if(admitted[j])begin
    if(raw_taken[j]!=1||native_taken[j]!=1||raw_result[j]!=native_result[j])
     $fatal(1,"owner not retired exactly once seq=%0d raw=%0d native=%0d",j,raw_taken[j],native_taken[j]);
   end
   if(!source_idle)$fatal(1,"SOURCE fence not idle after bounded tail state=%0d",fence.state);
   checks=checks+1;
  end
 endtask
 task snapshot(input [8*48-1:0] name,input integer p);
  begin
   $display("SNAPSHOT name=%0s prefix=%0d parser_seq=%0d identity_fault=%b quarantine=%b source_idle=%b fs=%0d fe=%0d abort=%0d admitted=%0d raw_ok=%0d raw_negative=%0d native_ok=%0d native_negative=%0d ecc=%0d crc=%0d overflow=%0d length=%0d RX=%h CG_admission_faults_model=000%b%b",name,p,dut.u_stream.u_word_core.sequence_counter,identity_fault,quarantine,source_idle,fs_seen,fe_seen,abort_seen,admit_total,successes,negatives,native_successes,native_negatives,ecc_errors,crc_errors,overflow_errors,length_errors,diag,identity_fault,quarantine);
  end
 endtask
 task tail_frames(input integer start,input integer count);
  integer j;begin for(j=start;j<start+count;j=j+1)frame(j);ticks(100);end
 endtask
 task recoverable(input integer kind,input integer p);
  integer j;reg [8*48-1:0] name;
  begin
   prefix(p);
   short_packet(0,p+1);
   case(kind)
    0:begin name="payload_crc";raw_packet(5,1,0);short_packet(1,p+1);end
    1:begin name="correctable_header_data_bit";raw_packet(5,0,32'h00000100);short_packet(1,p+1);end
    2:begin name="correctable_header_ecc_bit";raw_packet(5,0,32'h01000000);short_packet(1,p+1);end
    3:begin name="illegal_RAW10_length_6";raw_packet(6,0,0);short_packet(1,p+1);end
    4:begin
     name="missing_FE_then_next_FS";raw_packet(5,0,0);ticks(5000);
     if(successes!=p||negatives||identity_fault||quarantine||source_idle)
      $fatal(1,"missing FE waiting state violated");
     $display("PENDING missing_FE prefix=%0d observation_WORD_cycles=5000 identity_healthy=1 no_false_success=1 no_timeout_terminal=1 fence_state=%0d",p,fence.state);
    end
    5:begin name="FS_reentry_immediate";end
    6:begin name="duplicate_FE";raw_packet(5,0,0);short_packet(1,p+1);short_packet(1,p+1);end
    7:begin
     name="RAW_truncate_no_FE";
     intentionally_corrupt_sequence=p+1;
     byte_word(32'hb8b8b8b8,4'hf);byte_word({2'd0,ecc({16'd10,2'd0,6'h2b}),16'd10,2'd0,6'h2b},4'hf);
     byte_word(32'h44332211,4'hf);byte_word(0,0);ticks(200);
    end
   endcase
   tail_frames(p+2,4);
   if(kind==1||kind==2||kind==6)check_all(p+5,0);else check_all(p+4,1);
   if(identity_fault||quarantine)$fatal(1,"recoverable case destroyed continuity kind=%0d p=%0d",kind,p);
   if(kind==0&&crc_errors!=1)$fatal(1,"CRC error count mismatch");
   if(kind==3&&length_errors!=1)$fatal(1,"length error count mismatch");
   if((kind==1||kind==2)&&ecc_errors!=0)$fatal(1,"correctable header counted uncorrectable");
   snapshot(name,p);
   if(kind==7)$display("PENDING truncated_RAW prefix=%0d pre_terminal_RAW_beats=%0d final_negative_SOURCE=1 CRC_errors=%0d",p,corrupt_raw_beats,crc_errors);
   $display("CASE recovery name=%0s prefix=%0d subsequent_good_frames=4 all_admitted_owners_exactly_once PASS",name,p);
  end
 endtask
 task sticky(input integer kind,input integer p);
  reg [8*48-1:0] name;integer before_sequence;
  begin
   prefix(p);
   if(kind!=2)begin short_packet(0,p+1);raw_packet(5,0,0);end
   if(kind==0)begin
    name="recorded_uncorrectable_header_00097e2b";
    if(ecc(24'h097e2b)!==6'h21)$fatal(1,"recorded syndrome assumption wrong");
    byte_word(32'hb8b8b8b8,4'hf);byte_word(32'h00097e2b,4'hf);gap();ticks(100);
    if(diag[63:32]!==32'h00097e2b||diag[15:10]!==6'h21||!diag[4])
     $fatal(1,"RX first loss did not capture recorded bad header RX=%h",diag);
   end else begin
    name=kind==1?"PHY_loss_open_frame":"PHY_loss_between_frames";
    dut.u_phy.test_phy_health=0;dut.u_phy.test_cal_done=0;ticks(30);
    dut.u_phy.test_phy_health=1;ticks(14);dut.u_phy.test_cal_done=1;ticks(100);
   end
   if(!identity_fault||!quarantine)$fatal(1,"sticky loss failed to quarantine kind=%0d prefix=%0d",kind,p);
   before_sequence=dut.u_stream.u_word_core.sequence_counter;
   tail_frames(p+2,8);
   if(kind==2)check_all(p+7,0);else check_all(p+7,1);
   if(dut.u_stream.u_word_core.sequence_counter!=before_sequence+8||identity_fault||quarantine)
    $fatal(1,"safe recovery failed to restore later full frames with monotonic identity");
   snapshot(name,p);
   $display("CASE safe_recovery name=%0s prefix=%0d subsequent_good_frames=8 parser_progress=8 recovered_full_frames=7 all_admitted_owners_exactly_once PASS",name,p);
  end
 endtask

 task quiet_barrier;
  integer before_count;
  begin
   prefix(5);short_packet(0,6);raw_packet(5,0,0);
   byte_word(32'hb8b8b8b8,4'hf);byte_word(32'h00097e2b,4'hf);gap();ticks(120);
   if(!identity_fault||!quarantine)$fatal(1,"barrier fault not established");
   before_count=admit_total;recovery_quiet_allow=0;
   tail_frames(7,3);check_all(5,1);
   if(!quarantine||admit_total!=before_count)$fatal(1,"FS recovered before real quiet authority");
   ticks(5000);
   if(!quarantine||successes!=5||negatives!=1)$fatal(1,"silence fabricated recovery or terminal");
   recovery_quiet_allow=1;tail_frames(10,1);
   if(quarantine||admit_total!=before_count)$fatal(1,"boundary frame improperly admitted");
   tail_frames(11,4);check_all(9,1);
   $display("CASE explicit_quiet_barrier blocked_FS=3 silent_WORD_cycles=5000 first_boundary_ignored=1 recovered_frames=4 PASS");
  end
 endtask
 task repeated_recovery;
  integer n,base,cycle;reg [63:0] first_record;
  begin
   prefix(5);base=5;
   for(cycle=0;cycle<4;cycle=cycle+1)begin
    short_packet(0,base+1);raw_packet(5,0,0);
    byte_word(32'hb8b8b8b8,4'hf);byte_word(32'h00097e2b,4'hf);gap();ticks(120);
    if(!identity_fault||!quarantine)$fatal(1,"repeat error did not revoke trust");
    if(cycle==0)first_record=diag[63:0];
    else if(diag[63:0]!==first_record)$fatal(1,"second loss replaced RX first-loss record");
    ticks(1000);
    if(!quarantine)$fatal(1,"silence improperly rearms repeated failure");
    tail_frames(base+2,1);
    if(identity_fault||quarantine)$fatal(1,"repeat clean boundary did not rearm");
    tail_frames(base+3,2);base=base+4;
    check_all(5+2*(cycle+1),cycle+1);
   end
   $display("CASE repeated_runtime_fault_same_cohort errors=4 silent_WORD_cycles_each=1000 no_counter_rewind=1 exact_SOURCE_owners=1 PASS");
  end
 endtask
 integer p,j;
 initial begin
  // Healthy sustained control with identical finite random gaps/stalls.
  prefix(32);check_all(32,0);
  if(raw_stall_cycles==0||event_stall_cycles==0||source_stall_cycles==0)$fatal(1,"random stalls did not exercise all paths");
  snapshot("healthy_random_gaps_and_finite_stalls",32);
  $display("CASE healthy_32_frames raw_stall_cycles=%0d event_stall_cycles=%0d source_stall_cycles=%0d PASS",raw_stall_cycles,event_stall_cycles,source_stall_cycles);
  // Before the first FS, the same recorded uncorrectable header does not
  // destroy an identity that has not yet been published.
  cold();byte_word(32'hb8b8b8b8,4'hf);byte_word(32'h00097e2b,4'hf);gap();ticks(100);
  if(identity_fault||quarantine||dut.u_stream.u_word_core.sequence_counter!=0)$fatal(1,"pre-FS bad header poisoned future identity");
  tail_frames(1,3);check_all(3,0);snapshot("recorded_bad_header_before_first_FS",0);
  $display("CASE pre_FS_bad_header first_FS_still_trusted PASS");
  cold();dut.u_phy.test_phy_health=0;dut.u_phy.test_cal_done=0;ticks(30);
  dut.u_phy.test_phy_health=1;ticks(14);dut.u_phy.test_cal_done=1;ticks(100);
  tail_frames(1,3);check_all(3,0);
  if(identity_fault||quarantine)$fatal(1,"pre-FS PHY retrain poisoned future identity");
  snapshot("PHY_loss_before_first_FS",0);$display("CASE pre_FS_PHY_loss first_FS_still_trusted PASS");
  for(j=0;j<3;j=j+1)begin
   case(j)0:p=1;1:p=5;default:p=17;endcase
   recoverable(0,p);recoverable(1,p);recoverable(2,p);recoverable(3,p);
   recoverable(4,p);recoverable(5,p);recoverable(6,p);recoverable(7,p);
   sticky(0,p);sticky(1,p);sticky(2,p);
  end
  // Matched control for the exact seed15 original RAW header: ECC 0x21,
  // WC 0x097e = 2430 bytes, valid payload CRC, still the real FIFO chain.
  prefix(5);short_packet(0,6);raw_packet(2430,0,0);short_packet(1,6);tail_frames(7,4);
  check_all(10,0);
  if(identity_fault||quarantine||ecc_errors||crc_errors||overflow_errors||length_errors)$fatal(1,"correct recorded header control failed");
  snapshot("expected_header_21097e2b_control",5);
  $display("CASE expected_21097e2b_payload2430_matches_recorded_control subsequent_good_frames=4 PASS");
  quiet_barrier();repeated_recovery();
  $display("RESULT: PASS recovery_receiver_tb cases=%0d per_sequence_RAW_and_native_exactly_once=1",checks);
  $finish;
 end
 initial begin #50000000;$fatal(1,"recovery test watchdog");end
endmodule
