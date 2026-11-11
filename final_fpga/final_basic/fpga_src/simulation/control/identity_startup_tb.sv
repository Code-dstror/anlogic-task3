`timescale 1ns/1ps

module identity_guard_startup_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,phy=0,rx_fault=0,parser_fault=0,ev=0,idvalid=1;
 reg [1:0] kind=0;
 wire quarantine;
 production_source_identity_guard dut(.clk(clk),.rst_n(rst),.phy_ready(phy),
  .receive_fault(rx_fault),.parser_identity_fault(parser_fault),.event_valid(ev),
  .event_kind(kind),.event_identity_valid(idvalid),.quarantine(quarantine));
 // Exercise the production owner with the existing registered quarantine.
 // A same-edge first-FS fault can briefly own a frame, but it must terminate
 // negatively before either SOURCE becomes successful.
 wire raw_valid,raw_ok,native_valid,native_ok;
 integer raw_negative=0,native_negative=0,success=0;
 physical_identity_source_fence fence(.i_clk(clk),.i_rst_n(rst),.i_admit_enable(!quarantine),
  .i_event_valid(ev),.o_event_ready(),.i_event_kind(kind),.i_event_ok(1'b1),
  .i_continuity_fault(quarantine),.i_event_error(8'd0),.i_event_sequence(32'd1),.i_event_identity_valid(idvalid),
  .i_context_valid(1'b1),.o_context_ready(),.i_context(576'd0),.i_context_tag(64'd0),
  .i_context_session(32'd1),.i_context_epoch(32'd1),.i_context_sequence(32'd1),.i_context_camera(1'b0),
  .i_crop_geometry_done(1'b1),.i_crop_input_quiet(1'b1),.i_rgb_geometry_done(1'b1),.i_rgb_output_quiet(1'b1),
  .i_source_fault(1'b0),.i_source_error(8'd0),.o_capture_frame_enable(),.o_source_idle(),
  .o_raw_source_valid(raw_valid),.i_raw_source_ready(1'b1),.o_raw_source_session(),.o_raw_source_epoch(),
  .o_raw_source_sequence(),.o_raw_source_camera(),.o_raw_source_ok(raw_ok),.o_raw_source_error(),
  .o_native_source_valid(native_valid),.i_native_source_ready(1'b1),.o_native_source_context(),
  .o_native_source_tag(),.o_native_source_ok(native_ok),.o_native_source_error(),
  .o_drop_count(),.o_stale_event_count(),.i_data_reset_n(rst));
 always @(posedge clk)begin
  if(!rst)begin raw_negative<=0;native_negative<=0;success<=0;end
  else begin
   if(raw_valid)begin if(raw_ok)success<=success+1;else raw_negative<=raw_negative+1;end
   if(native_valid)begin if(native_ok)success<=success+1;else native_negative<=native_negative+1;end
  end
 end
 task tick;@(negedge clk);endtask
 task cold;begin
  rst=0;phy=0;rx_fault=0;parser_fault=0;ev=0;idvalid=1;kind=0;
  repeat(3)tick();rst=1;repeat(2)tick();
 end endtask
 task fs;begin ev=1;kind=0;tick();ev=0;tick();end endtask
 task lock_check;begin
  phy=1;rx_fault=0;parser_fault=0;ev=0;repeat(10)tick();
  if(!quarantine)$fatal(1,"quarantine auto-cleared without cohort reset");
  if(success!=0)$fatal(1,"faulted frame produced OK SOURCE");
 end endtask
 initial begin
  cold();phy=1;tick();phy=0;rx_fault=1;tick();phy=1;rx_fault=0;repeat(3)tick();
  if(quarantine)$fatal(1,"pre-FS PHY/receive transient poisoned startup");
  fs();if(quarantine)$fatal(1,"healthy first FS failed to establish cohort");
  phy=0;tick();lock_check();
  if(raw_negative!=1||native_negative!=1)$fatal(1,"PHY loss did not retire original SOURCE negatively");
  cold();phy=1;tick();fs();rx_fault=1;tick();lock_check();
  cold();parser_fault=1;tick();lock_check();
  cold();phy=1;tick();fs();parser_fault=1;tick();lock_check();
  cold();phy=1;idvalid=0;fs();lock_check();
  // Simultaneous first FS and PHY decline must fail even before cohort_started.
  cold();phy=1;tick();phy=0;ev=1;tick();ev=0;lock_check();
  if(raw_negative!=1||native_negative!=1)$fatal(1,"same-edge first FS/PHY loss escaped negative retirement");
  cold();phy=1;rx_fault=1;ev=1;tick();ev=0;lock_check();
  cold();if(quarantine)$fatal(1,"coordinated cohort reset did not recover");
  phy=1;tick();fs();if(quarantine)$fatal(1,"fresh cohort did not start after reset");
  $display("RESULT: PASS identity_guard_startup pre_FS_recovery post_FS_sticky same_edge_negative_SOURCE reset_recovery");
  $finish;
 end
 initial begin #20000;$fatal(1,"guard watchdog");end
endmodule

module identity_parser_startup_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,idrst=0,valid=0;reg [31:0] data=0;
 wire fault,outvalid;wire [31:0] sequence_count;wire [63:0] diag;
 wire [39:0] outdata;wire [3:0] code;wire ecc_error;
 integer trusted_fs=0;
 physical_csi_word_core #(.RX_DIAG_ENABLE(1)) dut(.i_clk(clk),.i_reset_n(rst),.i_identity_rst_n(idrst),
  .o_source_sequence_count(sequence_count),.o_identity_fault(fault),.o_identity_diag(diag),
  .i_word(data),.i_word_valid(valid),.i_sink_ready(1'b1),.o_data(outdata),.o_valid(outvalid),
  .o_sof(),.o_eol(),.o_abort(),.o_error_code(code),.o_header_ecc_error(ecc_error),
  .o_payload_crc_error(),.o_length_error(),.o_wait_for_sync(),.o_packet_done());
 always @(posedge clk)begin
  if(!idrst)trusted_fs<=0;
  else if(outvalid&&code==7&&outdata[32])trusted_fs<=trusted_fs+1;
 end
 function [5:0] ecc(input [23:0] d);
 begin
  ecc[0]=^(d&24'hf12cb7);ecc[1]=^(d&24'hf2555b);ecc[2]=^(d&24'h749a6d);
  ecc[3]=^(d&24'hb8e38e);ecc[4]=^(d&24'hdf03f0);ecc[5]=^(d&24'heffc00);
 end endfunction
 task tick;@(negedge clk);endtask
 task cold;begin rst=0;idrst=0;valid=0;repeat(3)tick();rst=1;idrst=1;repeat(3)tick();end endtask
 task packet(input [31:0] word_data);begin data=word_data;valid=1;tick();valid=0;repeat(3)tick();end endtask
 task fs(input [1:0] vc);reg [23:0] h;begin h={16'd1,vc,6'd0};packet({2'd0,ecc(h),h});end endtask
 initial begin
  cold();packet(32'hffffffff);
  if(!ecc_error||fault||diag!=0||sequence_count!=0)$fatal(1,"pre-FS bad header permanently destroyed unestablished identity");
  rst=0;repeat(2)tick();rst=1;repeat(3)tick();
  if(fault)$fatal(1,"pre-FS decoder reset poisoned identity");
  fs(1);if(sequence_count!=0||fault)$fatal(1,"non-target FS established SDR sequence");
  fs(0);if(sequence_count!=1||fault||trusted_fs!=1)$fatal(1,"first valid target FS did not establish trusted sequence");
  packet(32'hffffffff);
  if(!fault||diag[6:4]!==1||diag[31:16]!==1||diag[63:32]!==32'hffffffff)$fatal(1,"post-FS header loss attribution missing");
  fs(0);if(!fault||sequence_count!=2||trusted_fs!=1)$fatal(1,"post-FS bad header silently re-established identity");
  rst=0;tick();rst=1;repeat(3)tick();
  if(!fault||diag[6:4]!==1)$fatal(1,"soft reset cleared fault or overwrote first loss");
  cold();fs(0);rst=0;repeat(2)tick();
  if(!fault||diag[6:4]!==2||diag[31:16]!==1)$fatal(1,"post-FS decoder reset did not lock trust");
  rst=1;repeat(3)tick();fs(0);
  if(!fault||trusted_fs!=1)$fatal(1,"decoder recovery reused old trusted SOURCE");
  cold();fs(0);if(fault||sequence_count!=1||trusted_fs!=1||diag!=0)$fatal(1,"cohort reset failed to create fresh sequence");
  $display("RESULT: PASS identity_parser_startup pre_FS_bad_header_recovery post_FS_header_reset_sticky fresh_cohort");
  $finish;
 end
 initial begin #20000;$fatal(1,"parser watchdog");end
endmodule
