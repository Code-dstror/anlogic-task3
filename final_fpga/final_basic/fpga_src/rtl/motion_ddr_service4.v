`timescale 1ns / 1ps

// Atomic composition of real F26 BUILD/publication and DDR map projection.
module motion_ddr_service4 #(parameter [3:0] AXI_ID=4'd2,parameter integer EXTERNAL_FIFO_ENABLE=0) (
    input wire i_external_fifo_reset_done,
    output wire [146:0] q_mw_source_data,output wire q_mw_source_valid,input wire q_mw_source_ready,
    input wire [146:0] q_mw_sink_data,input wire q_mw_sink_valid,output wire q_mw_sink_ready,
    input wire [9:0] q_mw_available,
    output wire o_build_quiescent,
    input wire clk,rst_n,i_ddr_reset_done,i_source_reset_done,
    output wire o_reset_done,
    input wire i_start_valid,output wire o_start_ready,
    input wire [383:0] i_frame,i_history_frame,
    input wire [63:0] i_key,input wire [159:0] i_context,
    input wire [31:0] i_tag,i_history_tag,
    input wire [8:0] i_width,input wire [7:0] i_height,
    input wire i_history_available,
    input wire [7:0] i_static_threshold,i_weak_threshold,i_motion_threshold,
    input wire i_rgb_available,
    input wire [383:0] i_rgb_frame,i_rgb_history_frame,
    input wire [63:0] i_rgb_key,i_rgb_tag,i_rgb_history_tag,
    output wire o_offer_valid,o_backend_offer_valid,
    output wire [383:0] o_offer_frame,output wire [63:0] o_offer_key,
    output wire [159:0] o_offer_context,output wire [31:0] o_offer_tag,
    output wire o_history_used,output wire [7:0] o_history_reason,
    input wire s_valid,output wire s_ready,input wire [31:0] s_y,
    input wire [3:0] s_keep,input wire s_sof,s_eol,s_last,input wire [31:0] s_tag,
    input wire i_source_valid,output wire o_source_ready,
    input wire [383:0] i_source_frame,input wire [63:0] i_source_key,
    input wire [159:0] i_source_context,input wire [31:0] i_source_tag,
    input wire i_source_ok,i_source_read_quiescent,i_cancel,
    output wire o_abort_request,o_busy,o_read_quiescent,output reg o_job_done,
    output wire m_result_valid,input wire m_result_ready,
    output wire [1:0] m_result_kind,
    output wire [383:0] m_result_frame,m_result_history_frame,
    output wire [63:0] m_result_key,output wire [159:0] m_result_context,
    output wire [31:0] m_result_tag,m_result_history_tag,
    output wire m_result_success,m_result_source_ok,m_result_history_publish,m_result_map_commit,
    output wire [7:0] m_result_error,m_result_backend_error,
    output wire m_result_temporal_trust,m_result_global_change,m_result_brightness_change,
    output wire [15:0] m_result_pixels,m_result_foreground,
    output wire [15:0] m_result_confidence0,m_result_confidence1,m_result_confidence2,m_result_confidence3,
    output wire [23:0] m_result_sum_abs,m_result_sum_y,
    output wire signed [24:0] m_result_sum_diff,
    input wire i_projection_cancel,i_motion_discard,
    output wire m_motion_valid,input wire m_motion_ready,
    output wire [7:0] m_motion_confidence,output wire [3:0] m_motion_lane_valid,m_motion_keep,
    output wire m_motion_sof,m_motion_eol,m_motion_last,output wire [31:0] m_motion_index,
    output wire [383:0] m_motion_frame,m_motion_history_frame,
    output wire [63:0] m_motion_key,m_motion_tag,m_motion_history_tag,
    output wire [159:0] m_motion_context,
    output wire m_projection_valid,input wire m_projection_ready,
    output wire [1:0] m_projection_kind,output wire [7:0] m_projection_error,m_projection_reason,
    output wire m_projection_qualified,
    output wire [31:0] m_projection_map_groups,m_projection_output_groups,m_projection_output_pixels,
    output wire o_map_committed,o_backend_fault,output wire [7:0] o_backend_error,
    output wire [3:0] o_active_banks,o_pinned_banks,
    input wire i_debug_clear,
    output reg [31:0] o_stale_sources,o_late_cancels,o_completed_jobs,
    output wire [31:0] o_aw_count,o_w_count,o_b_count,o_ar_count,o_r_count,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire  m_axi_awvalid,
    input wire  m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire  m_axi_wlast,
    output wire  m_axi_wvalid,
    input wire  m_axi_wready,
    input wire [3:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire  m_axi_bvalid,
    output wire  m_axi_bready,
    output wire [3:0] m_axi_arid,
    output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire  m_axi_arvalid,
    input wire  m_axi_arready,
    input wire [3:0] m_axi_rid,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire  m_axi_rlast,
    input wire  m_axi_rvalid,
    output wire  m_axi_rready
);
    localparam [3:0] IDLE=0,LAUNCH=1,BUILD=2,SKIP_DRAIN=3,SKIP_RESULT=4,
        PROJECT_LAUNCH=5,PROJECT=6,QUARANTINE=7;
    reg [3:0] state;
    reg [383:0] frame,history_frame,rgb_frame,rgb_history_frame;
    reg [63:0] key,rgb_key,rgb_tag,rgb_history_tag;
    reg [159:0] context_locked;
    reg [31:0] tag,history_tag;
    reg [8:0] width;
    reg [7:0] height,static_threshold,weak_threshold,motion_threshold,skip_reason;
    reg history_available,rgb_available,source_seen,source_ok,aborted;
    reg mirror_valid0,mirror_valid1;
    reg [383:0] mirror_frame0,mirror_frame1;
    reg [63:0] mirror_key0,mirror_key1;
    reg [159:0] mirror_context0,mirror_context1;
    reg [31:0] mirror_tag0,mirror_tag1;
    reg [8:0] mirror_width0,mirror_width1;
    reg [7:0] mirror_height0,mirror_height1;
    wire  f_start_ready;
    wire  f_begin_valid;
    wire [383:0] f_o_frame;
    wire [383:0] f_o_history_frame;
    wire [63:0] f_o_pipeline_key;
    wire [159:0] f_o_context;
    wire [31:0] f_o_tag;
    wire [31:0] f_o_history_tag;
    wire [8:0] f_o_width;
    wire [7:0] f_o_height;
    wire  f_o_history_used;
    wire [7:0] f_o_history_reason;
    wire  f_current_ready;
    wire  f_history_ready;
    wire  f_mask_valid;
    wire [3:0] f_mask_bits;
    wire [7:0] f_mask_confidence;
    wire [3:0] f_mask_keep;
    wire  f_mask_sof;
    wire  f_mask_eol;
    wire  f_mask_eof;
    wire [8:0] f_mask_x;
    wire [7:0] f_mask_y;
    wire [15:0] f_mask_native_x;
    wire [15:0] f_mask_native_y;
    wire  f_write_valid;
    wire [31:0] f_write_y;
    wire [3:0] f_write_keep;
    wire  f_write_sof;
    wire  f_write_eol;
    wire  f_write_eof;
    wire  f_source_done_ready;
    wire  f_close_valid;
    wire  f_close_commit_candidate;
    wire [15:0] f_close_write_pixels;
    wire  f_ack_ready;
    wire  f_status_valid;
    wire  f_status_success;
    wire  f_history_publish;
    wire [7:0] f_status_error;
    wire [15:0] f_pixel_count;
    wire [15:0] f_mask_count;
    wire [15:0] f_write_count;
    wire [15:0] f_foreground_count;
    wire [15:0] f_confidence0_count;
    wire [15:0] f_confidence1_count;
    wire [15:0] f_confidence2_count;
    wire [15:0] f_confidence3_count;
    wire [23:0] f_sum_absdiff;
    wire [23:0] f_sum_y;
    wire [24:0] f_sum_diff;
    wire  f_global_change_hint;
    wire  f_brightness_shift_hint;
    wire  f_temporal_trust;
    wire [31:0] f_frames_started;
    wire [31:0] f_frames_completed;
    wire [31:0] f_frames_failed;
    wire  f_first_fault_valid;
    wire [7:0] f_first_fault_code;
    wire [383:0] f_first_fault_frame;
    wire [31:0] f_first_fault_tag;
    wire  b_o_reset_done;
    wire  b_o_offer_valid;
    wire [383:0] b_o_offer_frame;
    wire [63:0] b_o_offer_key;
    wire [159:0] b_o_offer_context;
    wire [31:0] b_o_offer_tag;
    wire  b_o_begin_ready;
    wire  b_s_y_ready;
    wire  b_s_map_ready;
    wire  b_h_valid;
    wire [31:0] b_h_y;
    wire [3:0] b_h_keep;
    wire  b_h_sof;
    wire  b_h_eol;
    wire  b_h_last;
    wire [31:0] b_h_tag;
    wire b_o_read_quiescent,b_o_write_quiescent;
    assign o_build_quiescent=b_o_write_quiescent && b_o_read_quiescent;
    wire  b_o_close_ready;
    wire  b_m_ack_valid;
    wire [383:0] b_m_ack_frame;
    wire [63:0] b_m_ack_key;
    wire [159:0] b_m_ack_context;
    wire [31:0] b_m_ack_tag;
    wire  b_m_ack_quiescent;
    wire  b_m_ack_write_ok;
    wire [15:0] b_m_ack_write_pixels;
    wire [7:0] b_m_ack_error;
    wire  b_o_publish_ready;
    wire  b_o_map_committed;
    wire  b_o_map_f26_success;
    wire  b_o_map_temporal_trust;
    wire  b_o_map_global_change;
    wire  b_o_map_brightness_change;
    wire [383:0] b_o_map_frame;
    wire [383:0] b_o_map_history_frame;
    wire [63:0] b_o_map_key;
    wire [159:0] b_o_map_context;
    wire [31:0] b_o_map_tag;
    wire [31:0] b_o_map_history_tag;
    wire [8:0] b_o_map_width;
    wire [7:0] b_o_map_height;
    wire [15:0] b_o_map_full_pixels;
    wire  b_o_project_plan_ready;
    wire  b_map_valid;
    wire [7:0] b_map_confidence;
    wire [3:0] b_map_keep;
    wire  b_map_sof;
    wire  b_map_eol;
    wire  b_map_last;
    wire [31:0] b_map_index;
    wire [63:0] b_map_stream_tag;
    wire  b_o_project_close_ready;
    wire  b_m_project_ack_valid;
    wire [383:0] b_m_project_ack_frame;
    wire [63:0] b_m_project_ack_key;
    wire [63:0] b_m_project_ack_tag;
    wire  b_m_project_ack_quiescent;
    wire  b_m_project_ack_ok;
    wire [31:0] b_m_project_ack_groups;
    wire  b_o_release_ready;
    wire  b_o_busy;
    wire  b_o_fault;
    wire [7:0] b_o_error;
    wire [3:0] b_o_active_banks;
    wire [3:0] b_o_pinned_banks;
    wire [31:0] b_o_aw_count;
    wire [31:0] b_o_w_count;
    wire [31:0] b_o_b_count;
    wire [31:0] b_o_ar_count;
    wire [31:0] b_o_r_count;
    wire [31:0] b_o_Y_commit_count;
    wire [31:0] b_o_map_commit_count;
    wire [31:0] b_o_release_count;
    wire [31:0] b_o_fault_count;
    wire  p_start_ready;
    wire  p_plan_valid;
    wire  p_plan_use_map;
    wire [383:0] p_o_frame;
    wire [383:0] p_o_history_frame;
    wire [63:0] p_o_key;
    wire [63:0] p_o_tag;
    wire [63:0] p_o_history_tag;
    wire [8:0] p_o_map_width;
    wire [7:0] p_o_map_height;
    wire  p_map_ready;
    wire  p_motion_valid;
    wire [7:0] p_motion_confidence;
    wire [3:0] p_motion_lane_valid;
    wire [3:0] p_motion_keep;
    wire  p_motion_sof;
    wire  p_motion_eol;
    wire  p_motion_last;
    wire [31:0] p_motion_index;
    wire  p_abort_request;
    wire  p_close_valid;
    wire  p_close_cancel;
    wire  p_ack_ready;
    wire  p_status_valid;
    wire [1:0] p_status_kind;
    wire [7:0] p_status_error;
    wire  p_status_qualified;
    wire [7:0] p_status_bypass_reason;
    wire [31:0] p_status_map_groups;
    wire [31:0] p_status_output_groups;
    wire [31:0] p_status_output_pixels;
    wire [31:0] p_stale_acks;
    wire [31:0] p_frames_projected;
    wire [31:0] p_frames_skipped;
    wire [31:0] p_frames_failed;
    wire offer_camera=state==IDLE ? i_frame[4] : frame[4];
    wire mirror_match=offer_camera ?
        mirror_valid1 && b_o_offer_frame==mirror_frame1 && b_o_offer_key==mirror_key1 &&
        b_o_offer_context==mirror_context1 && b_o_offer_tag==mirror_tag1 :
        mirror_valid0 && b_o_offer_frame==mirror_frame0 && b_o_offer_key==mirror_key0 &&
        b_o_offer_context==mirror_context0 && b_o_offer_tag==mirror_tag0;
    assign o_offer_valid=b_o_offer_valid && mirror_match && state!=LAUNCH && state!=BUILD;
    assign o_backend_offer_valid=b_o_offer_valid;
    assign o_offer_frame=b_o_offer_frame;assign o_offer_key=b_o_offer_key;
    assign o_offer_context=b_o_offer_context;assign o_offer_tag=b_o_offer_tag;
    wire [15:0] native_width=({7'd0,i_width}<<2)+({7'd0,i_width}<<1);
    wire [15:0] native_height=({8'd0,i_height}<<2)+({8'd0,i_height}<<1);
    wire bad_geometry=i_width==0 || i_width>320 || i_height==0 || i_height>180 ||
        i_frame[220:205]!=native_width || i_frame[236:221]!=native_height;
    wire bad_metadata=!i_frame[0] || i_frame[383:367]!=0 || i_frame[12:5]>=4 ||
        i_frame[44:13]==0 || i_frame[76:45]==0 || i_frame[302:271]==0 ||
        i_frame[2:1]==3 || (i_frame[238:237]!=1 && i_frame[238:237]!=2) || i_tag==0;
    wire bad_threshold=i_static_threshold>i_weak_threshold || i_weak_threshold>i_motion_threshold;
    wire start_bad=bad_geometry || bad_metadata || bad_threshold;
    wire requested_history=i_history_available && o_offer_valid &&
        i_history_frame==b_o_offer_frame && i_history_tag==b_o_offer_tag && i_key==b_o_offer_key &&
        (i_frame[4] ? i_width==mirror_width1 && i_height==mirror_height1 :
                     i_width==mirror_width0 && i_height==mirror_height0);
    assign o_reset_done=b_o_reset_done && i_source_reset_done;
    assign o_start_ready=rst_n && o_reset_done && state==IDLE && f_start_ready && b_o_begin_ready && !i_cancel;
    wire start_fire=i_start_valid && o_start_ready;
    wire source_match=i_source_frame==frame && i_source_key==key &&
        i_source_context==context_locked && i_source_tag==tag;
    wire source_quiet=i_source_read_quiescent && !s_valid;
    wire skip_active=state==SKIP_DRAIN || state==SKIP_RESULT;
    wire build_active=state==LAUNCH || state==BUILD;
    wire source_accept=state==SKIP_DRAIN || (state==BUILD && f_source_done_ready &&
        (!i_source_ok || source_quiet));
    assign o_source_ready=rst_n && state!=IDLE && state!=QUARANTINE &&
        (!source_match || source_seen || source_accept);
    wire source_fire=i_source_valid && o_source_ready;
    wire source_failure=source_fire && source_match && !source_seen && !i_source_ok;
    // STATUS is the same immutable cutoff for both frozen transaction owners.
    wire abort_event=build_active && !f_status_valid && (i_cancel || b_o_fault || source_failure);
    wire abort_active=build_active && !f_status_valid && (aborted || abort_event);
    assign o_abort_request=aborted || abort_event;
    assign s_ready=rst_n && ((state==SKIP_DRAIN) || (state==BUILD &&
        ((aborted && !source_quiet) || abort_active || (!f_status_valid && f_current_ready))));
    wire f_source_valid=i_source_valid && source_match && !source_seen && state==BUILD &&
        (!i_source_ok || source_quiet);
    wire qualification_ready=source_seen && source_quiet;
    assign o_busy=state!=IDLE || b_o_busy;
    assign o_read_quiescent=b_o_read_quiescent && i_source_read_quiescent;
    assign o_history_used=build_active ? f_o_history_used : b_o_map_history_tag!=0;
    assign o_history_reason=f_o_history_reason;
    wire f_result_qualified=state==BUILD && f_status_valid && b_o_publish_ready && qualification_ready;
    assign m_result_valid=rst_n && (state==SKIP_RESULT || f_result_qualified);
    wire result_fire=m_result_valid && m_result_ready;
    wire publish_fire=result_fire && state==BUILD;
    assign m_result_kind=skip_active ? 2'd0 : f_status_success ? 2'd1 : 2'd2;
    assign m_result_frame=frame;assign m_result_key=key;assign m_result_context=context_locked;
    assign m_result_tag=tag;assign m_result_history_frame=skip_active ? 384'd0 : f_o_history_frame;
    assign m_result_history_tag=skip_active ? 32'd0 : f_o_history_tag;
    assign m_result_success=!skip_active && f_status_success;
    assign m_result_source_ok=source_seen && source_ok;
    assign m_result_history_publish=m_result_success;
    assign m_result_map_commit=m_result_success && f_o_history_used;
    assign m_result_error=skip_active ? skip_reason : f_status_error;
    assign m_result_backend_error=skip_active ? 8'd0 : b_o_error;
    assign m_result_temporal_trust=!skip_active && f_temporal_trust;
    assign m_result_global_change=!skip_active && f_global_change_hint;
    assign m_result_brightness_change=!skip_active && f_brightness_shift_hint;
    assign m_result_pixels=skip_active ? 16'd0 : f_pixel_count;
    assign m_result_foreground=skip_active ? 16'd0 : f_foreground_count;
    assign m_result_confidence0=skip_active ? 16'd0 : f_confidence0_count;
    assign m_result_confidence1=skip_active ? 16'd0 : f_confidence1_count;
    assign m_result_confidence2=skip_active ? 16'd0 : f_confidence2_count;
    assign m_result_confidence3=skip_active ? 16'd0 : f_confidence3_count;
    assign m_result_sum_abs=skip_active ? 24'd0 : f_sum_absdiff;
    assign m_result_sum_y=skip_active ? 24'd0 : f_sum_y;
    assign m_result_sum_diff=skip_active ? 25'sd0 : f_sum_diff;
    wire rgb_pair_ok=rgb_available && rgb_frame==frame && rgb_history_frame==f_o_history_frame &&
        rgb_key==key && rgb_tag=={32'd0,tag} && rgb_history_tag=={32'd0,f_o_history_tag};
    assign m_motion_valid=p_motion_valid;
    assign m_motion_confidence=p_motion_confidence;assign m_motion_lane_valid=p_motion_lane_valid;
    assign m_motion_keep=p_motion_keep;assign m_motion_sof=p_motion_sof;
    assign m_motion_eol=p_motion_eol;assign m_motion_last=p_motion_last;assign m_motion_index=p_motion_index;
    assign m_motion_frame=p_o_frame;assign m_motion_history_frame=p_o_history_frame;
    assign m_motion_key=p_o_key;assign m_motion_tag=p_o_tag;assign m_motion_history_tag=p_o_history_tag;
    assign m_motion_context=context_locked;
    assign m_projection_valid=rst_n && state==PROJECT && p_status_valid && b_o_release_ready;
    wire release_fire=m_projection_valid && m_projection_ready;
    assign m_projection_kind=p_status_kind;assign m_projection_error=p_status_error;
    assign m_projection_reason=p_status_bypass_reason;assign m_projection_qualified=p_status_qualified;
    assign m_projection_map_groups=p_status_map_groups;assign m_projection_output_groups=p_status_output_groups;
    assign m_projection_output_pixels=p_status_output_pixels;
    assign o_map_committed=b_o_map_committed;assign o_backend_fault=b_o_fault;assign o_backend_error=b_o_error;
    assign o_active_banks=b_o_active_banks;assign o_pinned_banks=b_o_pinned_banks;
    assign o_aw_count=b_o_aw_count;assign o_w_count=b_o_w_count;assign o_b_count=b_o_b_count;
    assign o_ar_count=b_o_ar_count;assign o_r_count=b_o_r_count;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;frame<=0;history_frame<=0;key<=0;context_locked<=0;tag<=0;history_tag<=0;
            width<=0;height<=0;static_threshold<=0;weak_threshold<=0;motion_threshold<=0;skip_reason<=0;
            history_available<=0;rgb_available<=0;rgb_frame<=0;rgb_history_frame<=0;rgb_key<=0;rgb_tag<=0;rgb_history_tag<=0;
            source_seen<=0;source_ok<=0;aborted<=0;o_job_done<=0;
            mirror_valid0<=0;mirror_valid1<=0;mirror_frame0<=0;mirror_frame1<=0;
            mirror_key0<=0;mirror_key1<=0;mirror_context0<=0;mirror_context1<=0;mirror_tag0<=0;mirror_tag1<=0;
            mirror_width0<=0;mirror_width1<=0;mirror_height0<=0;mirror_height1<=0;
        end else begin
            o_job_done<=0;
            if(abort_event) aborted<=1;
            if(source_fire && source_match && !source_seen) begin source_seen<=1;source_ok<=i_source_ok;end
            case(state)
                IDLE:if(start_fire) begin
                    frame<=i_frame;history_frame<=i_history_frame;key<=i_key;context_locked<=i_context;
                    tag<=i_tag;history_tag<=i_history_tag;width<=i_width;height<=i_height;
                    static_threshold<=i_static_threshold;weak_threshold<=i_weak_threshold;motion_threshold<=i_motion_threshold;
                    history_available<=requested_history;rgb_available<=i_rgb_available;
                    rgb_frame<=i_rgb_frame;rgb_history_frame<=i_rgb_history_frame;rgb_key<=i_rgb_key;
                    rgb_tag<=i_rgb_tag;rgb_history_tag<=i_rgb_history_tag;
                    source_seen<=0;source_ok<=0;aborted<=0;
                    skip_reason<=bad_metadata ? 8'd1 : bad_geometry ? 8'd2 : 8'd3;
                    state<=start_bad ? SKIP_DRAIN : LAUNCH;
                end
                LAUNCH:if(f_start_ready) state<=BUILD;
                BUILD:if(publish_fire) begin
                    if(frame[4]) begin
                        mirror_valid1<=f_status_success;
                        if(f_status_success) begin mirror_frame1<=frame;mirror_key1<=key;mirror_context1<=context_locked;
                            mirror_tag1<=tag;mirror_width1<=width;mirror_height1<=height;end
                    end else begin
                        mirror_valid0<=f_status_success;
                        if(f_status_success) begin mirror_frame0<=frame;mirror_key0<=key;mirror_context0<=context_locked;
                            mirror_tag0<=tag;mirror_width0<=width;mirror_height0<=height;end
                    end
                    state<=PROJECT_LAUNCH;
                end
                SKIP_DRAIN:if(qualification_ready) state<=SKIP_RESULT;
                SKIP_RESULT:if(result_fire) begin state<=IDLE;o_job_done<=1;end
                PROJECT_LAUNCH:if(p_start_ready) state<=PROJECT;
                PROJECT:if(release_fire) begin state<=IDLE;o_job_done<=1;end
                QUARANTINE:begin end
                default:state<=QUARANTINE;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin o_stale_sources<=0;o_late_cancels<=0;o_completed_jobs<=0;end
        else if(i_debug_clear) begin o_stale_sources<=0;o_late_cancels<=0;o_completed_jobs<=0;end
        else begin
            if(source_fire && (!source_match || source_seen)) o_stale_sources<=o_stale_sources+1'b1;
            if(state==BUILD && f_status_valid && i_cancel) o_late_cancels<=o_late_cancels+1'b1;
            if(release_fire || (state==SKIP_RESULT && result_fire)) o_completed_jobs<=o_completed_jobs+1'b1;
        end
    end
    preprocess_motion4 u_f_(
        .clk(clk),
        .rst_n(rst_n),
        .cancel(abort_active),
        .source_error(source_failure),
        .debug_clear(i_debug_clear),
        .source_reset_done(i_source_reset_done),
        .backend_reset_done(b_o_reset_done),
        .start_valid(state==LAUNCH),
        .start_ready(f_start_ready),
        .start_frame(frame),
        .start_history_frame(history_frame),
        .start_pipeline_key(key),
        .start_context(context_locked),
        .start_tag(tag),
        .start_history_tag(history_tag),
        .start_width(width),
        .start_height(height),
        .start_history_available(history_available),
        .start_static_threshold(static_threshold),
        .start_weak_threshold(weak_threshold),
        .start_motion_threshold(motion_threshold),
        .begin_valid(f_begin_valid),
        .begin_ready(b_o_begin_ready),
        .o_frame(f_o_frame),
        .o_history_frame(f_o_history_frame),
        .o_pipeline_key(f_o_pipeline_key),
        .o_context(f_o_context),
        .o_tag(f_o_tag),
        .o_history_tag(f_o_history_tag),
        .o_width(f_o_width),
        .o_height(f_o_height),
        .o_history_used(f_o_history_used),
        .o_history_reason(f_o_history_reason),
        .current_valid(s_valid && state==BUILD && !f_status_valid),
        .current_ready(f_current_ready),
        .current_y(s_y),
        .current_keep(s_keep),
        .current_sof(s_sof),
        .current_eol(s_eol),
        .current_eof(s_last),
        .current_tag(s_tag),
        .history_valid(b_h_valid),
        .history_ready(f_history_ready),
        .history_y(b_h_y),
        .history_keep(b_h_keep),
        .history_sof(b_h_sof),
        .history_eol(b_h_eol),
        .history_eof(b_h_last),
        .history_tag(b_h_tag),
        .mask_valid(f_mask_valid),
        .mask_ready(b_s_map_ready),
        .mask_bits(f_mask_bits),
        .mask_confidence(f_mask_confidence),
        .mask_keep(f_mask_keep),
        .mask_sof(f_mask_sof),
        .mask_eol(f_mask_eol),
        .mask_eof(f_mask_eof),
        .mask_x(f_mask_x),
        .mask_y(f_mask_y),
        .mask_native_x(f_mask_native_x),
        .mask_native_y(f_mask_native_y),
        .write_valid(f_write_valid),
        .write_ready(b_s_y_ready),
        .write_y(f_write_y),
        .write_keep(f_write_keep),
        .write_sof(f_write_sof),
        .write_eol(f_write_eol),
        .write_eof(f_write_eof),
        .source_done_valid(f_source_valid),
        .source_done_ready(f_source_done_ready),
        .source_done_frame(i_source_frame),
        .source_done_key(i_source_key),
        .source_done_context(i_source_context),
        .source_done_tag(i_source_tag),
        .source_done_ok(i_source_ok),
        .close_valid(f_close_valid),
        .close_ready(b_o_close_ready),
        .close_commit_candidate(f_close_commit_candidate),
        .close_write_pixels(f_close_write_pixels),
        .ack_valid(b_m_ack_valid),
        .ack_ready(f_ack_ready),
        .ack_frame(b_m_ack_frame),
        .ack_key(b_m_ack_key),
        .ack_context(b_m_ack_context),
        .ack_tag(b_m_ack_tag),
        .ack_quiescent(b_m_ack_quiescent),
        .ack_write_ok(b_m_ack_write_ok),
        .ack_write_pixels(b_m_ack_write_pixels),
        .status_valid(f_status_valid),
        .status_ready(publish_fire),
        .status_success(f_status_success),
        .history_publish(f_history_publish),
        .status_error(f_status_error),
        .pixel_count(f_pixel_count),
        .mask_count(f_mask_count),
        .write_count(f_write_count),
        .foreground_count(f_foreground_count),
        .confidence0_count(f_confidence0_count),
        .confidence1_count(f_confidence1_count),
        .confidence2_count(f_confidence2_count),
        .confidence3_count(f_confidence3_count),
        .sum_absdiff(f_sum_absdiff),
        .sum_y(f_sum_y),
        .sum_diff(f_sum_diff),
        .global_change_hint(f_global_change_hint),
        .brightness_shift_hint(f_brightness_shift_hint),
        .temporal_trust(f_temporal_trust),
        .frames_started(f_frames_started),
        .frames_completed(f_frames_completed),
        .frames_failed(f_frames_failed),
        .first_fault_valid(f_first_fault_valid),
        .first_fault_code(f_first_fault_code),
        .first_fault_frame(f_first_fault_frame),
        .first_fault_tag(f_first_fault_tag)
    );
    motion_history_store4 #(.AXI_ID(AXI_ID),.EXTERNAL_FIFO_ENABLE(EXTERNAL_FIFO_ENABLE)) u_b_(
        .i_external_fifo_reset_done(i_external_fifo_reset_done),
        .q_mw_source_data(q_mw_source_data),.q_mw_source_valid(q_mw_source_valid),.q_mw_source_ready(q_mw_source_ready),
        .q_mw_sink_data(q_mw_sink_data),.q_mw_sink_valid(q_mw_sink_valid),.q_mw_sink_ready(q_mw_sink_ready),.q_mw_available(q_mw_available),
        .o_write_quiescent(b_o_write_quiescent),
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_ddr_reset_done(i_ddr_reset_done),
        .o_reset_done(b_o_reset_done),
        .i_offer_camera(offer_camera),
        .o_offer_valid(b_o_offer_valid),
        .o_offer_frame(b_o_offer_frame),
        .o_offer_key(b_o_offer_key),
        .o_offer_context(b_o_offer_context),
        .o_offer_tag(b_o_offer_tag),
        .i_begin_valid(f_begin_valid),
        .o_begin_ready(b_o_begin_ready),
        .i_begin_frame(f_o_frame),
        .i_begin_history_frame(f_o_history_frame),
        .i_begin_key(f_o_pipeline_key),
        .i_begin_context(f_o_context),
        .i_begin_tag(f_o_tag),
        .i_begin_history_tag(f_o_history_tag),
        .i_begin_width(f_o_width),
        .i_begin_height(f_o_height),
        .i_begin_history_used(f_o_history_used),
        .s_y_valid(f_write_valid),
        .s_y_ready(b_s_y_ready),
        .s_y(f_write_y),
        .s_y_keep(f_write_keep),
        .s_y_sof(f_write_sof),
        .s_y_eol(f_write_eol),
        .s_y_last(f_write_eof),
        .s_map_valid(f_mask_valid),
        .s_map_ready(b_s_map_ready),
        .s_confidence(f_mask_confidence),
        .s_mask(f_mask_bits),
        .s_map_keep(f_mask_keep),
        .s_map_sof(f_mask_sof),
        .s_map_eol(f_mask_eol),
        .s_map_last(f_mask_eof),
        .s_map_x(f_mask_x),
        .s_map_y(f_mask_y),
        .h_valid(b_h_valid),
        .h_ready(abort_active || f_history_ready),
        .h_y(b_h_y),
        .h_keep(b_h_keep),
        .h_sof(b_h_sof),
        .h_eol(b_h_eol),
        .h_last(b_h_last),
        .h_tag(b_h_tag),
        .o_read_quiescent(b_o_read_quiescent),
        .i_close_valid(f_close_valid),
        .o_close_ready(b_o_close_ready),
        .i_close_frame(f_o_frame),
        .i_close_key(f_o_pipeline_key),
        .i_close_context(f_o_context),
        .i_close_tag(f_o_tag),
        .i_close_commit_candidate(f_close_commit_candidate),
        .i_close_write_pixels(f_close_write_pixels),
        .m_ack_valid(b_m_ack_valid),
        .m_ack_ready(f_ack_ready),
        .m_ack_frame(b_m_ack_frame),
        .m_ack_key(b_m_ack_key),
        .m_ack_context(b_m_ack_context),
        .m_ack_tag(b_m_ack_tag),
        .m_ack_quiescent(b_m_ack_quiescent),
        .m_ack_write_ok(b_m_ack_write_ok),
        .m_ack_write_pixels(b_m_ack_write_pixels),
        .m_ack_error(b_m_ack_error),
        .i_publish_valid(publish_fire),
        .o_publish_ready(b_o_publish_ready),
        .i_publish_frame(frame),
        .i_publish_key(key),
        .i_publish_context(context_locked),
        .i_publish_tag(tag),
        .i_publish_success(f_status_success),
        .i_publish_temporal_trust(f_temporal_trust),
        .i_publish_global_change(f_global_change_hint),
        .i_publish_brightness_change(f_brightness_shift_hint),
        .o_map_committed(b_o_map_committed),
        .o_map_f26_success(b_o_map_f26_success),
        .o_map_temporal_trust(b_o_map_temporal_trust),
        .o_map_global_change(b_o_map_global_change),
        .o_map_brightness_change(b_o_map_brightness_change),
        .o_map_frame(b_o_map_frame),
        .o_map_history_frame(b_o_map_history_frame),
        .o_map_key(b_o_map_key),
        .o_map_context(b_o_map_context),
        .o_map_tag(b_o_map_tag),
        .o_map_history_tag(b_o_map_history_tag),
        .o_map_width(b_o_map_width),
        .o_map_height(b_o_map_height),
        .o_map_full_pixels(b_o_map_full_pixels),
        .i_project_plan_valid(p_plan_valid),
        .o_project_plan_ready(b_o_project_plan_ready),
        .i_project_use_map(p_plan_use_map),
        .i_project_frame(p_o_frame),
        .i_project_history_frame(p_o_history_frame),
        .i_project_key(p_o_key),
        .i_project_tag(p_o_tag),
        .i_project_history_tag(p_o_history_tag),
        .map_valid(b_map_valid),
        .map_ready(p_map_ready),
        .map_confidence(b_map_confidence),
        .map_keep(b_map_keep),
        .map_sof(b_map_sof),
        .map_eol(b_map_eol),
        .map_last(b_map_last),
        .map_index(b_map_index),
        .map_stream_tag(b_map_stream_tag),
        .i_project_close_valid(p_close_valid),
        .o_project_close_ready(b_o_project_close_ready),
        .i_project_close_frame(p_o_frame),
        .i_project_close_key(p_o_key),
        .i_project_close_tag(p_o_tag),
        .i_project_close_cancel(p_close_cancel),
        .m_project_ack_valid(b_m_project_ack_valid),
        .m_project_ack_ready(p_ack_ready),
        .m_project_ack_frame(b_m_project_ack_frame),
        .m_project_ack_key(b_m_project_ack_key),
        .m_project_ack_tag(b_m_project_ack_tag),
        .m_project_ack_quiescent(b_m_project_ack_quiescent),
        .m_project_ack_ok(b_m_project_ack_ok),
        .m_project_ack_groups(b_m_project_ack_groups),
        .i_release_valid(release_fire),
        .o_release_ready(b_o_release_ready),
        .i_release_frame(p_o_frame),
        .i_release_key(p_o_key),
        .i_release_tag(p_o_tag),
        .i_cancel(abort_active),
        .i_project_cancel(i_projection_cancel || p_abort_request),
        .o_busy(b_o_busy),
        .o_fault(b_o_fault),
        .o_error(b_o_error),
        .o_active_banks(b_o_active_banks),
        .o_pinned_banks(b_o_pinned_banks),
        .i_debug_clear(i_debug_clear),
        .o_aw_count(b_o_aw_count),
        .o_w_count(b_o_w_count),
        .o_b_count(b_o_b_count),
        .o_ar_count(b_o_ar_count),
        .o_r_count(b_o_r_count),
        .o_Y_commit_count(b_o_Y_commit_count),
        .o_map_commit_count(b_o_map_commit_count),
        .o_release_count(b_o_release_count),
        .o_fault_count(b_o_fault_count),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );
    preprocess_motion_projection4 u_p_(
        .clk(clk),
        .rst_n(rst_n),
        .reader_reset_done(b_o_reset_done),
        .cancel(i_projection_cancel),
        .start_valid(state==PROJECT_LAUNCH),
        .start_ready(p_start_ready),
        .start_frame(frame),
        .start_history_frame(f_o_history_frame),
        .start_key(key),
        .start_tag({32'd0,tag}),
        .start_history_tag({32'd0,f_o_history_tag}),
        .nr_history_available(rgb_pair_ok),
        .map_frame(b_o_map_frame),
        .map_history_frame(b_o_map_history_frame),
        .map_key(b_o_map_key),
        .map_tag(b_o_map_tag),
        .map_history_tag(b_o_map_history_tag),
        .map_committed(b_o_map_committed),
        .f26_success(b_o_map_f26_success),
        .f26_temporal_trust(b_o_map_temporal_trust),
        .global_change(b_o_map_global_change),
        .brightness_change(b_o_map_brightness_change),
        .map_width(b_o_map_width),
        .map_height(b_o_map_height),
        .map_full_pixels(b_o_map_full_pixels),
        .plan_valid(p_plan_valid),
        .plan_ready(b_o_project_plan_ready),
        .plan_use_map(p_plan_use_map),
        .o_frame(p_o_frame),
        .o_history_frame(p_o_history_frame),
        .o_key(p_o_key),
        .o_tag(p_o_tag),
        .o_history_tag(p_o_history_tag),
        .o_map_width(p_o_map_width),
        .o_map_height(p_o_map_height),
        .map_valid(b_map_valid),
        .map_ready(p_map_ready),
        .map_confidence(b_map_confidence),
        .map_keep(b_map_keep),
        .map_sof(b_map_sof),
        .map_eol(b_map_eol),
        .map_last(b_map_last),
        .map_index(b_map_index),
        .map_stream_tag(b_map_stream_tag),
        .read_error(b_o_fault),
        .motion_valid(p_motion_valid),
        .motion_ready(m_motion_ready || i_motion_discard),
        .motion_confidence(p_motion_confidence),
        .motion_lane_valid(p_motion_lane_valid),
        .motion_keep(p_motion_keep),
        .motion_sof(p_motion_sof),
        .motion_eol(p_motion_eol),
        .motion_last(p_motion_last),
        .motion_index(p_motion_index),
        .abort_request(p_abort_request),
        .close_valid(p_close_valid),
        .close_ready(b_o_project_close_ready),
        .close_cancel(p_close_cancel),
        .ack_valid(b_m_project_ack_valid),
        .ack_ready(p_ack_ready),
        .ack_frame(b_m_project_ack_frame),
        .ack_key(b_m_project_ack_key),
        .ack_tag(b_m_project_ack_tag),
        .ack_quiescent(b_m_project_ack_quiescent),
        .ack_ok(b_m_project_ack_ok),
        .ack_groups(b_m_project_ack_groups),
        .status_valid(p_status_valid),
        .status_ready(release_fire),
        .status_kind(p_status_kind),
        .status_error(p_status_error),
        .status_qualified(p_status_qualified),
        .status_bypass_reason(p_status_bypass_reason),
        .status_map_groups(p_status_map_groups),
        .status_output_groups(p_status_output_groups),
        .status_output_pixels(p_status_output_pixels),
        .debug_clear(i_debug_clear),
        .stale_acks(p_stale_acks),
        .frames_projected(p_frames_projected),
        .frames_skipped(p_frames_skipped),
        .frames_failed(p_frames_failed)
    );
endmodule
