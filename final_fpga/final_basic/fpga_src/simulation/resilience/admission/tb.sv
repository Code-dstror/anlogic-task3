`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`default_nettype none
module tb;
 reg pixel_clk=0,pixel_rst_n=0;
 always #5 pixel_clk=~pixel_clk;
 localparam R8_STAGE1_ENABLE=1;
 reg physical_admit_enable=1,cfg_source_ready=1,cfg_pause=0,capture_config_valid=0;
 reg local_stop_pause=0,reset_pause_pixel=0,live_source_block=0,physical_hdr_requested=0;
 reg [1:0] enable_pixel=3,armed_pixel=3,recovery_pixel=0,fault_pixel=0;
 reg replay_active=0,pixel_context_request=0,host_replay_context_owned=0,processing_context_owned=0;
 reg camera_receive_fault=0,physical_identity_quarantine=0,capture_frontend_fault=0;
 reg binding_fault=0,cleanup_fault=0,cleanup_pending=0,camera_mode_running=1;
 reg camera_source_identity_fault=0;
 reg modeled_pipeline_idle=1,raw_capture0_idle=1,replay_admission_ready=1;
 reg use_actual_admission=0;
 wire actual_frame_active,actual_rgb_buffered,actual_credit_take,actual_protocol_fault;
 reg actual_rgb_valid=0,actual_rgb_sof=0,actual_jpeg_ready=1,actual_result_valid=0,actual_credit_ack=0;
 reg encoder_owned=0;
 wire actual_rgb_ready,actual_jpeg_valid,actual_status_valid,actual_status_ok;
 wire [31:0] actual_capture_id;
 reg [31:0] actual_input_id=0;
 wire advanced_join_ready;
 wire native_pipeline_idle_now=use_actual_admission ? (!actual_frame_active&&!encoder_owned&&!actual_rgb_buffered&&advanced_join_ready) : modeled_pipeline_idle;
 reg modeled_builder_ready=1,lane_capacity_ready=1,lane_quiet=1,use_real_resources=0;
 wire real_builder_ready,real_join_ready;
 wire context2_begin_ready=use_real_resources?real_builder_ready:modeled_builder_ready;
 assign advanced_join_ready=use_real_resources?real_join_ready:1'b1;
 wire mask_begin_ready=1'b1;
 wire record_builder_ready=context2_begin_ready&&advanced_join_ready&&mask_begin_ready;
 reg record_product_tag_exhausted=0,record_writer_tag_exhausted=0;
 reg record_format_busy=0;
 reg [1:0] record_format_busy_pixel=0;
 wire record_product_available=(record_builder_ready&&(lane_capacity_ready||!lane_quiet)&&!record_product_tag_exhausted&&!record_writer_tag_exhausted);
 reg [63:0] source_tag_counter=0;
 wire physical_sdr_source_idle,native_pipeline_idle;
 reg pipeline_take=0;
 frame_admission_qualification native_q(.i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_available(native_pipeline_idle_now),.i_take(pipeline_take||(use_actual_admission&&actual_credit_take)),.i_inhibit(1'b0),.o_available(native_pipeline_idle));
 always @(posedge pixel_clk or negedge pixel_rst_n)
  if(!pixel_rst_n)record_format_busy_pixel<=0;
  else record_format_busy_pixel<={record_format_busy_pixel[0],record_format_busy};
 reg physical_event_valid=0;
 wire physical_event_ready,physical_fs_take;
 reg [1:0] physical_event_kind=0;
 reg [31:0] physical_event_sequence=0;
 wire cfg_diag_source_fs;
 wire [4:0] cfg_diag_admission_faults;
 wire [15:0] cfg_diag_source_gates;
 wire source_recovery_quiet;
 reg raw_capture1_idle=1,crop_quiet=1,all_presented_clear=1;
 __TOP_ADMISSION__
 reg ctx_valid=0;
 reg [31:0] ctx_seq=0;
 wire ctx_ready,capture,raw_v,native_v,raw_ok,native_ok;
 reg raw_ready=1,native_ready=1,rgb_quiet=1;
 reg crop_done=1,rgb_done=1,source_fault=0;
 wire [31:0] raw_seq,drop_count,stale_count;
 wire [575:0] native_context;
 wire [63:0] native_tag;
 wire [7:0] raw_error,native_error;
 wire camera_hdr_mode=1'b0,pixel_reset_local_n=pixel_rst_n;
 wire physical_event_ok=1'b1,physical_event_identity_valid=1'b1;
 wire [3:0] physical_event_error=4'd0;
 wire capture0_valid=ctx_valid,capture0_accept=1'b1,capture0_sof=1'b1;
 wire [575:0] source_capsule={544'd0,ctx_seq};
 wire [63:0] next_tag={32'd0,ctx_seq};
 wire [31:0] capture0_session=32'd1,capture0_epoch=32'd4,capture0_sequence=ctx_seq;
 wire capture0_geometry_done=crop_done,physical_capture_private=1'b0,processed_done=rgb_done,native_owned=capture;
 wire capture0_abort=source_fault,scoped_pipeline_error=1'b0;
 wire physical_frame_enable;
 wire context_ready;
 assign ctx_ready=context_ready;
 assign capture=physical_frame_enable;
 wire physical_raw_source_valid;
 wire physical_raw_source_ready=raw_ready;
 wire [31:0] physical_raw_source_session,physical_raw_source_epoch,physical_raw_source_sequence;
 wire physical_raw_source_camera,physical_raw_source_ok;
 wire [7:0] physical_raw_source_error;
 assign raw_v=physical_raw_source_valid;assign raw_seq=physical_raw_source_sequence;
 assign raw_ok=physical_raw_source_ok;assign raw_error=physical_raw_source_error;
 wire physical_native_source_valid;
 wire physical_native_source_ready=native_ready;
 wire [575:0] physical_native_source_context;
 wire [63:0] physical_native_source_tag;
 wire physical_native_source_ok;
 wire [7:0] physical_native_source_error;
 assign native_v=physical_native_source_valid;assign native_context=physical_native_source_context;
 assign native_tag=physical_native_source_tag;assign native_ok=physical_native_source_ok;assign native_error=physical_native_source_error;
 __TOP_FENCE__
 // Real admission closes the first frame. Encoder payload computation is out of
 // scope: this BFM returns a result only after the real admission STATUS.
 jpeg_frame_admission #(.EXTERNAL_SEQUENCE_ENABLE(1),.SHARED_LUMA_ENABLE(1)) actual_admission(
  .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_credit_grant(1'b1),.i_credit_ack(actual_credit_ack),
  .i_session_armed(1'b1),.i_app_enable(1'b1),.i_fault(1'b0),.o_credit_request(),.o_credit_take(actual_credit_take),
  .i_rgb_data(96'd0),.i_luma(32'd0),.i_frame_sequence(actual_input_id),.i_rgb_valid(actual_rgb_valid),.o_rgb_ready(actual_rgb_ready),
  .i_rgb_sof(actual_rgb_sof),.i_rgb_eol(1'b1),.i_camera_done(native_v&&native_ready&&native_ok),.i_camera_error(native_v&&native_ready&&!native_ok),
  .o_jpeg_rgb(),.o_jpeg_luma(),.o_jpeg_valid(actual_jpeg_valid),.i_jpeg_ready(actual_jpeg_ready),.o_jpeg_sof(),.o_jpeg_eol(),
  .o_start_valid(),.i_start_ready(1'b1),.i_time_ns(64'd0),.o_timestamp_ns(),.o_capture_id(actual_capture_id),
  .o_status_valid(actual_status_valid),.i_status_ready(1'b1),.o_status_id(),.o_status_ok(actual_status_ok),
  .i_result_valid(actual_result_valid),.i_result_ready(1'b1),.i_result_id(actual_capture_id),
  .o_protocol_fault(actual_protocol_fault),.o_active(actual_frame_active),.o_replay_ready_boundary(),.o_rgb_buffered(actual_rgb_buffered),.o_state_idle());
 reg [3:0] builder_features=0;
 reg builder_stats_valid=0,builder_terminal_valid=0,builder_terminal_error=0;
 reg f22_valid=0,f23_valid=0,extension_ready=0;
 wire [159:0] builder_context={16'd1,16'd0,8'd1,8'd1,8'd1,8'd0,actual_input_id,32'd4,32'd1};
 reg [183:0] builder_statistics=0;
 wire [1023:0] context_extension;
 wire context_extension_valid,context_extension_ready,builder_fault,join_fault,extension_valid;
 wire [3071:0] record_extension;
 wire [31:0] builder_stale,builder_errors,join_stale;
 frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(1),.OBSERVATION_WIDTH(2),.OBSERVATION_HEIGHT(2)) resource_builder(
  .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.s_begin_valid(use_real_resources&&actual_credit_take),.o_begin_ready(real_builder_ready),
  .i_source_session(32'd1),.i_source_epoch(32'd4),.i_source_sequence(actual_input_id),.i_source_camera(8'd0),.i_source_kind(8'd1),.i_source_format(8'd1),
  .i_exposure_role(8'd0),.i_exposure_valid(1'b0),.i_actual_exposure(32'd0),.i_exposure_group(32'd0),.i_gain_valid(1'b0),.i_actual_gain(32'd0),
  .i_calibration_valid(1'b0),.i_calibration_id(32'd0),.i_time_quality(8'd2),.i_pair_valid(1'b0),.i_pair_id(64'd0),.i_job_valid(1'b0),.i_job_id(64'd0),
  .i_write_tag_valid(1'b1),.i_write_tag({32'd0,actual_input_id}),.i_qualified(1'b0),.i_processing_member(8'd0),.i_processing_mode(8'd128),.i_record_flags(16'd0),
  .s_stats_valid(builder_stats_valid),.o_stats_ready(),.s_stats_context(builder_context),.s_statistics(builder_statistics),
  .m_extension_valid(context_extension_valid),.m_extension_ready(context_extension_ready),.m_extension_data(context_extension),
  .o_stale_count(builder_stale),.o_error_count(builder_errors),.o_input_fault(builder_fault));
 frame_record_v3_join resource_join(
  .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.s_begin_valid(use_real_resources&&actual_credit_take),.o_begin_ready(real_join_ready),
  .s_begin_context(builder_context),.s_begin_features(builder_features),.s_terminal_valid(builder_terminal_valid),.s_terminal_error(builder_terminal_error),.s_terminal_context(builder_context),
  .s_context2_extension(context_extension),.s_context2_valid(context_extension_valid),.o_context2_ready(context_extension_ready),
  .s_f22_record({builder_context,524'd0}),.s_f22_valid(f22_valid),.o_f22_ready(),.s_f23_record({builder_context,1196'd0}),.s_f23_valid(f23_valid),.o_f23_ready(),
  .s_f24_record(208'd0),.s_f24_valid(1'b0),.o_f24_ready(),.s_f25_record(265'd0),.s_f25_valid(1'b0),.o_f25_ready(),
  .m_extension(record_extension),.m_extension_valid(extension_valid),.m_extension_ready(extension_ready),.o_fault(join_fault),.o_stale_count(join_stale));
 reg diag_commit=0,diag_ack=0,diag_fs=0;
 reg [15:0] diag_gates=0;
 wire [223:0] diag_data;
 cfg_diag_pixel observer(.i_clk(pixel_clk),.i_observer_rst_n(pixel_rst_n),.i_app_rst_n(pixel_rst_n),
  .i_commit_accepted(diag_commit),.i_session(32'd1),.i_request_sequence(32'd1),.i_target_epoch(32'd4),
  .i_remote_sent(1'b0),.i_positive_ack(diag_ack),.i_negative_ack(1'b0),.i_unmatched_ack(1'b0),
  .i_frame_accept(1'b0),.i_apply_frame(1'b0),.i_applied_last_sent(1'b0),.i_frame_sequence(32'd0),.i_live_flags(32'd0),.i_frame_gates(3'd0),
  .i_source_fs(diag_fs),.i_source_gates(diag_gates),.o_data(diag_data));
 integer checks=0,raw_count=0,native_count=0,ignored=0,accepted=0,cycle=0,cases=0,tracefd;
 reg expected_ok=1;
 reg prev_rstall=0,prev_nstall=0;
 reg [40:0] held_raw;
 reg [648:0] held_native;
 task check(input bit ok,input string reason);
  begin checks++;if(!ok)$fatal(1,"cycle=%0d %s",cycle,reason);end
 endtask
 always @(posedge pixel_clk) if(pixel_rst_n)begin
  cycle++;
  $fdisplay(tracefd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycle,cases,physical_event_valid,physical_event_kind,physical_event_sequence,physical_event_ready,physical_admission_credit,deferred_fs,fs_qualification_seen,native_pipeline_idle_now,native_pipeline_idle,physical_sdr_source_idle,record_product_available,record_format_busy_pixel[1],raw_v,raw_ready,native_v,native_ready,local_stop_pause,cfg_pause,capture_config_valid);
  if(prev_rstall)check(raw_v&&{raw_seq,raw_ok,raw_error}===held_raw,"RAW source held stable under independent ready stall");
  if(prev_nstall)check(native_v&&{native_context,native_tag,native_ok,native_error}===held_native,"native source held stable under independent ready stall");
  prev_rstall=raw_v&&!raw_ready;held_raw={raw_seq,raw_ok,raw_error};
  prev_nstall=native_v&&!native_ready;held_native={native_context,native_tag,native_ok,native_error};
  if(raw_v&&raw_ready)begin check(raw_ok==expected_ok,"RAW success/negative exact");raw_count++;end
  if(native_v&&native_ready)begin check(native_ok==expected_ok,"native success/negative exact");native_count++;end
 end else begin prev_rstall=0;prev_nstall=0;end
 task tick(input integer n);repeat(n)begin @(negedge pixel_clk);#1;end endtask
 task reset_case;
  begin
   @(negedge pixel_clk);pixel_rst_n=0;physical_event_valid=0;ctx_valid=0;
   modeled_builder_ready=1;lane_capacity_ready=1;lane_quiet=1;record_format_busy=0;
   modeled_pipeline_idle=1;pipeline_take=0;raw_capture0_idle=1;replay_admission_ready=1;
   use_actual_admission=0;actual_rgb_valid=0;actual_rgb_sof=0;actual_jpeg_ready=1;actual_result_valid=0;actual_credit_ack=0;encoder_owned=0;
   use_real_resources=0;builder_stats_valid=0;builder_terminal_valid=0;builder_terminal_error=0;builder_features=0;
   f22_valid=0;f23_valid=0;extension_ready=0;diag_commit=0;diag_ack=0;diag_fs=0;
   cfg_pause=0;local_stop_pause=0;capture_config_valid=0;source_fault=0;rgb_quiet=1;crop_quiet=1;
   raw_ready=1;native_ready=1;crop_done=1;rgb_done=1;expected_ok=1;
   tick(3);pixel_rst_n=1;tick(4);
  end
 endtask
 task send_event(input [1:0] k,input [31:0] seq);
  integer waited;
  begin
   @(negedge pixel_clk);physical_event_valid=1;physical_event_kind=k;physical_event_sequence=seq;waited=0;
   do begin @(posedge pixel_clk);waited++;check(waited<100,"event bounded after environment restoration");end while(!physical_event_ready);
   @(negedge pixel_clk);physical_event_valid=0;#1;
  end
 endtask
 task context_for(input [31:0] seq);
  begin
   @(negedge pixel_clk);ctx_seq=seq;ctx_valid=1;
   @(posedge pixel_clk);check(ctx_ready,"context accepted for true admitted FS");
   @(negedge pixel_clk);ctx_valid=0;#1;
  end
 endtask
 task finish_frame(input [31:0] seq,input bit good);
  integer r,n,t;
  begin
   r=raw_count;n=native_count;send_event(1,seq);t=0;
   while(!physical_sdr_source_idle)begin tick(1);t++;check(t<80,"both true source tails release owner");end
   check(raw_count==r+1&&native_count==n+1,"one independent RAW and native terminal per admitted FS");
   tick(3);
  end
 endtask
 task ordinary_frame(input integer seq);
  begin send_event(0,seq);check(capture,"ordinary FS admitted");context_for(seq);finish_frame(seq,1);end
 endtask
 // Isolated resource hold is an environment model. It establishes skip policy,
 // not that a physical T05 cycle ever had this resource condition.
 task resource_case(input integer kind,input integer before_cycles,input integer hold_cycles);
  integer seq,r,n;bit was_owned;
  begin
   reset_case();seq=100+cases;r=raw_count;n=native_count;
   if(kind==0)modeled_builder_ready=0;else if(kind==1)record_format_busy=1;else raw_capture0_idle=0;
   tick(before_cycles);
   fork
    begin send_event(0,seq);was_owned=capture;end
    begin tick(hold_cycles);modeled_builder_ready=1;record_format_busy=0;raw_capture0_idle=1;end
   join
   if(was_owned)begin accepted++;context_for(seq);finish_frame(seq,1);end
   else begin ignored++;check(!ctx_ready,"no-credit consumed FS cannot acquire context");send_event(1,seq);tick(4);check(raw_count==r&&native_count==n,"ignored FS emits no fabricated SOURCE");end
   check(drop_count==0,"healthy no-credit FS is not reported in fence drop counter");
   check(!camera_receive_fault&&!physical_identity_quarantine,"stable epoch omission needs no RX/continuity error in this conditional subsystem");
   check(physical_sdr_source_idle,"ignored or retired owner returns idle");
   cases++;$display("CASE resource kind=%0d before=%0d hold=%0d owned=%0d drop=%0d",kind,before_cycles,hold_cycles,was_owned,drop_count);
  end
 endtask
 task source_stall_case(input integer which,input integer count,input bit negative,input integer stop_offset);
  integer seq,r,n,t;
  begin
   reset_case();seq=1000+cases;r=raw_count;n=native_count;
   send_event(0,seq);check(capture,"stall case owns initial FS");context_for(seq);
   modeled_pipeline_idle=0;rgb_quiet=0;
   raw_ready=which!=0;native_ready=which!=1;
   if(stop_offset<0)local_stop_pause=1;
   source_fault=negative;expected_ok=!negative;
   fork
    begin send_event(1,seq);end
    begin if(stop_offset==0)begin wait(physical_event_valid&&physical_event_kind==1);cfg_pause=1;end end
   join
   tick(2);
   if(stop_offset>0)capture_config_valid=1;
   check(capture&&!physical_sdr_source_idle,"STOP/CFG cannot erase accepted pre-FE owner");
   check(!source_recovery_quiet,"new TOP recovery permission cannot release a live SOURCE owner");
   check(!native_v,"native terminal waits actual RGB/record quiet");
   if(which==0)begin tick(count);check(raw_v&&raw_count==r,"RAW terminal valid held independently");end
   rgb_quiet=1;tick(3);
   if(which==1)begin tick(count);check(native_v&&native_count==n,"native terminal valid held independently");end
   check(capture&&!physical_sdr_source_idle,"one unaccepted source tail keeps accepted owner");
   raw_ready=1;native_ready=1;t=0;
   while(!physical_sdr_source_idle)begin tick(1);t++;check(t<20,"owner recovers once real consumer ready returns");end
   check(raw_count==r+1&&native_count==n+1,"stall/negative emits each SOURCE terminal exactly once");
   check(drop_count==(negative?1:0),"only negative owner increments fence drop count");
   cases++;$display("CASE source_tail which=%0d stall=%0d negative=%0d stop_offset=%0d drop=%0d",which,count,negative,stop_offset,drop_count);
  end
 endtask
 task previous_tail_next_fs(input integer raw_hold,input integer native_hold,input integer record_hold);
  integer seq,t,r,n;bit second_owned;
  begin
   reset_case();seq=2000+cases;send_event(0,seq);context_for(seq);
   modeled_pipeline_idle=0;raw_ready=0;native_ready=0;send_event(1,seq);
   modeled_builder_ready=0;replay_admission_ready=0;
   fork
    begin send_event(0,seq+1);second_owned=capture;end
    begin
     tick(raw_hold);raw_ready=1;tick(native_hold);native_ready=1;
     tick(record_hold);modeled_pipeline_idle=1;modeled_builder_ready=1;replay_admission_ready=1;
    end
   join
   // Record whether a SOURCE was actually owned; source may be consumed on
   // the first credit-publication edge, before the registered credit rises.
   if(second_owned)begin accepted++;context_for(seq+1);finish_frame(seq+1,1);end
   else begin ignored++;send_event(1,seq+1);tick(4);end
   check(physical_sdr_source_idle,"next-FS overlap leaves no stranded fence owner");
   check(drop_count==0,"healthy delayed prior retirement is not an RX/drop fault");
   cases++;$display("CASE prior_tail raw_hold=%0d native_hold=%0d record_hold=%0d next_owned=%0d",raw_hold,native_hold,record_hold,second_owned);
  end
 endtask
 task actual_pipeline_case(input integer jpeg_stall,input integer result_delay,input integer ack_delay);
  integer seq,t;bit second_owned;
  begin
   reset_case();use_actual_admission=1;seq=3000+cases;
   send_event(0,seq);check(capture,"actual admission case initial FS owned");context_for(seq);
   @(negedge pixel_clk);actual_input_id=seq;actual_rgb_valid=1;actual_rgb_sof=1;encoder_owned=1;actual_jpeg_ready=0;
   @(posedge pixel_clk);check(actual_credit_take,"real JPEG admission consumes first pixel credit");
   @(negedge pixel_clk);actual_rgb_valid=0;actual_rgb_sof=0;
   tick(jpeg_stall+2);actual_jpeg_ready=1;tick(2);
   send_event(1,seq);
   fork
    begin send_event(0,seq+1);second_owned=capture;end
    begin
     t=0;while(!actual_status_valid)begin tick(1);t++;check(t<50,"real JPEG admission STATUS follows physical SOURCE");end
     check(actual_status_ok,"healthy SOURCE produces positive actual status");
     tick(result_delay+1);actual_result_valid=1;actual_credit_ack=1;
     tick(1);actual_result_valid=0;encoder_owned=0;
     tick(ack_delay);actual_credit_ack=0;
    end
   join
   check(!actual_protocol_fault,"ordered result and physical SOURCE do not set real admission fault");
   check(second_owned,"with real frame_active/STATUS/result ordering queued next FS obtains credit");
   context_for(seq+1);finish_frame(seq+1,1);
   cases++;$display("CASE actual_admission jpeg_stall=%0d result_delay=%0d ack_delay=%0d next_owned=%0d",jpeg_stall,result_delay,ack_delay,second_owned);
  end
 endtask
 task real_resource_case(input [3:0] features,input bit negative,input integer delay_cycles,input integer control_kind);
  integer seq,t,r,n;bit second_owned;
  begin
   reset_case();use_actual_admission=1;use_real_resources=1;builder_features=features;
   seq=4000+cases;r=raw_count;n=native_count;
   send_event(0,seq);check(capture,"real builder case initial FS owned");context_for(seq);
   @(negedge pixel_clk);actual_input_id=seq;actual_rgb_valid=1;actual_rgb_sof=1;encoder_owned=1;
   @(posedge pixel_clk);check(actual_credit_take&&real_builder_ready&&real_join_ready,"real admission atomically reserves builder and join");
   @(negedge pixel_clk);actual_rgb_valid=0;actual_rgb_sof=0;tick(3);
   check(!real_builder_ready&&!real_join_ready&&!record_builder_ready,"real metadata owner prevents fabricated availability");
   source_fault=negative;expected_ok=!negative;send_event(1,seq);
   fork
    begin send_event(0,seq+1);second_owned=capture;end
    begin
     t=0;while(!actual_status_valid)begin tick(1);t++;check(t<60,"real admission status after source terminal");end
     check(actual_status_ok==!negative,"negative source reaches real JPEG status");
     actual_result_valid=1;actual_credit_ack=1;tick(1);actual_result_valid=0;encoder_owned=0;actual_credit_ack=0;
     builder_statistics=0;
     if(!negative)begin
      builder_statistics[15:0]=4;builder_statistics[31:16]=4;builder_statistics[63:32]=100;
      builder_statistics[143:128]=2;builder_statistics[159:144]=2;builder_statistics[167:160]=1;builder_statistics[183:176]=1;
     end
     if(control_kind==1)local_stop_pause=1;
     if(control_kind==2)begin cfg_pause=1;capture_config_valid=1;end
     tick(delay_cycles+1);builder_stats_valid=1;builder_terminal_valid=1;builder_terminal_error=negative;
     tick(1);builder_stats_valid=0;builder_terminal_valid=0;
     f22_valid=features[0];f23_valid=features[1];tick(2);
     check(extension_valid,"actual builder/join produce authenticated positive or negative record extension");
     repeat(delay_cycles+1)begin tick(1);check(extension_valid&&!real_join_ready,"output stall retains real metadata owner");end
     local_stop_pause=0;cfg_pause=0;capture_config_valid=0;source_fault=0;expected_ok=1;
     tick(2);extension_ready=1;tick(1);f22_valid=0;f23_valid=0;extension_ready=0;
    end
   join
   check(second_owned,"actual builder completion and ordered admission allow deferred next FS");
   check(!builder_fault&&!join_fault&&!actual_protocol_fault,"ordinary negative metadata does not latch unrelated global fault");
   check(builder_errors==(negative?1:0),"incomplete negative stats counted once without wedging builder");
   context_for(seq+1);finish_frame(seq+1,1);
   check(raw_count==r+2&&native_count==n+2,"real resource negative/positive pair preserves exact SOURCE ownership");
   check(real_builder_ready&&real_join_ready&&physical_sdr_source_idle,"all real subsystem owners boundedly retired");
   tick(3);check(source_recovery_quiet,"new TOP recovery quiet permits release after genuine source/product drain");
   cases++;$display("CASE real_resources features=%0d negative=%0d delay=%0d control=%0d builder_errors=%0d",features,negative,delay_cycles,control_kind,builder_errors);
  end
 endtask
 task diagnostic_case;
  reg [223:0] first_snapshot;
  begin
   reset_case();diag_commit=1;tick(1);diag_commit=0;diag_ack=1;tick(1);diag_ack=0;
   diag_gates=16'h125a;diag_fs=1;tick(1);diag_fs=0;first_snapshot=diag_data;
   check(diag_data[223:208]==16'h125a,"existing CFG snapshot captures first post-ACK FS gate vector");
   tick(2);diag_gates=16'hdead;diag_fs=1;tick(1);diag_fs=0;
   check(diag_data==first_snapshot,"later stable epoch FS cannot overwrite existing first-FS snapshot");
   cases++;$display("CASE observer_first_fs snapshot=%h later_rejection_not_captured=1",diag_data[223:208]);
  end
 endtask
 integer k,j,d,feat;
 initial begin
  tracefd=$fopen("trace.csv","w");
  $fdisplay(tracefd,"cycle,case,event_valid,event_kind,event_sequence,event_ready,credit,deferred,qualification_seen,idle_now,idle_q,source_idle,record_available,busy_q,raw_valid,raw_ready,native_valid,native_ready,stop,cfg_pause,cfg_valid");
  reset_case();ordinary_frame(21875);ordinary_frame(21878);cases++;
  for(k=0;k<3;k++)begin
   resource_case(k,0,0);resource_case(k,1,1);resource_case(k,3,1);resource_case(k,3,4);resource_case(k,3,9);
  end
  for(k=0;k<2;k++)for(j=-1;j<=1;j++)begin
   source_stall_case(k,1,0,j);source_stall_case(k,7,1,j);
  end
  for(k=0;k<8;k++)previous_tail_next_fs(1,7,k);
  previous_tail_next_fs(0,1,0);previous_tail_next_fs(7,1,7);
  actual_pipeline_case(0,0,0);actual_pipeline_case(1,1,1);actual_pipeline_case(7,7,7);
  for(k=0;k<3;k++)begin
   feat=k==0?0:k==1?1:3;
   for(j=0;j<2;j++)for(d=0;d<3;d++)
    real_resource_case(feat,j,d==0?0:d==1?1:7,(k+j+d)%3);
  end
  diagnostic_case();
  $fclose(tracefd);
  $display("RESULT PASS ADVERSARIAL_RETIREMENT cases=%0d checks=%0d raw=%0d native=%0d conditional_accepted=%0d conditional_ignored=%0d",cases,checks,raw_count,native_count,accepted,ignored);$finish;
 end
 initial begin #200000;$fatal(1,"watchdog");end
endmodule
`default_nettype wire
