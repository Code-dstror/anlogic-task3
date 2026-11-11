`timescale 1ns / 1ps

// One post-ISP owner: original RGB enters once, actual product tails retire it.
module private_rgb_nr_pipeline4 #(
    parameter integer MAX_WIDTH=1920, MAX_HEIGHT=1080,
    parameter integer NR_ENABLE=0,NEUTRAL_STATS_ENABLE=0,DEHAZE_ENABLE=0
) (
    input wire [66:0] i_f21_config,input wire [31:0] i_f21_required_lut_generation,
    input wire f21_cfg_begin_valid,output wire f21_cfg_begin_ready,input wire [31:0] f21_cfg_generation,
    input wire f21_cfg_valid,output wire f21_cfg_ready,input wire [8:0] f21_cfg_index,input wire [10:0] f21_cfg_value,
    input wire f21_cfg_commit_valid,output wire f21_cfg_commit_ready,input wire f21_cfg_abort,
    output wire f21_cfg_status_valid,input wire f21_cfg_status_ready,output wire f21_cfg_status_ok,
    output wire [7:0] f21_cfg_status_error,output wire [31:0] f21_cfg_status_generation,
    output wire o_f21_lut_valid,output wire [31:0] o_f21_lut_generation,
    output wire o_f21_start_eligible,o_f21_busy,o_f21_read_quiescent,o_f21_protocol_fault,
    output wire o_f21_fence_valid,output wire [575:0] o_f21_fence_identity,
    output wire o_f21_fence_ok,output wire [7:0] o_f21_fence_error,output wire [31:0] o_f21_fence_pixels,
    output wire o_f21_history_used,o_f21_metadata_bypass,output wire [31:0] o_f21_frame_lut_generation,
    output wire o_f21_map_commit,output wire [31:0] o_f21_map_commit_frame,
    input wire i_neutral_stats_request,i_neutral_record_begin,
    input wire [159:0] i_neutral_record_context,
    output wire m_neutral_stats_valid,input wire m_neutral_stats_ready,
    output wire [159:0] m_neutral_stats_context,
    output wire [183:0] m_neutral_statistics,
    output wire [31:0] o_neutral_stats_stale_count,
    input wire i_pixel_clk, i_pixel_rst_n, i_dfi_clk, i_dfi_rst_n,
    input wire [575:0] s_context,
    input wire s_context_valid,
    output wire s_context_ready,
    input wire i_owner_valid,
    input wire [383:0] i_owner_frame,
    input wire [63:0] i_owner_lease, i_owner_job, i_owner_pair, i_owner_native_tag,
    input wire [31:0] i_owner_writer_tag,
    input wire i_owner_member,
    input wire [95:0] s_rgb,
    input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_last, s_valid,
    output wire s_ready,
    input wire [63:0] s_tag,
    input wire [31:0] s_index,
    input wire s_status_valid,
    output wire s_status_ready,
    input wire [575:0] s_status_context,
    input wire [63:0] s_status_tag,
    input wire s_status_ok,
    input wire [7:0] s_status_error,
    input wire [31:0] s_status_groups,
    input wire i_original_read_quiescent,
    output wire [575:0] m_context,
    output wire m_context_valid,
    input wire m_context_ready,
    output wire [95:0] m_rgb,
    output wire [3:0] m_keep,
    output wire m_sof, m_eol, m_last, m_valid,
    input wire m_ready,
    output wire [63:0] m_tag,
    output wire [31:0] m_index,
    output wire m_source_notice_valid,
    input wire m_source_notice_ready,
    output wire [575:0] m_source_notice_context,
    output wire m_source_notice_ok,
    output wire [7:0] m_source_notice_error,
    input wire i_processed_sof_fire, i_writer_source_start_fire,
    input wire i_pipeline_quiescent, i_pipeline_ok,
    input wire [7:0] i_pipeline_error,
    output wire m_processed_source_valid,
    input wire m_processed_source_ready,
    output wire [383:0] m_processed_source_frame,
    output wire [63:0] m_processed_source_lease, m_processed_source_job,
    output wire [63:0] m_processed_source_pair, m_processed_source_write_tag,
    output wire m_processed_source_member, m_processed_source_error,
    output wire o_pixel_fault, o_dfi_fault,
    output wire o_context_available, o_pool_idle,
    output wire [31:0] o_stale_original_status_count,
    // Real DFI writer START/after-B ownership, independently from native tag64.
    output wire o_writer_start_permitted,
    output wire o_nr_start_fire,
    input wire i_writer_start_fire,
    input wire s_write_valid,
    output wire s_write_ready,
    input wire [31:0] s_write_tag, s_write_sequence, s_write_session, s_write_epoch,
    input wire s_write_camera, s_write_ok,
    input wire [7:0] s_write_error,
    input wire i_ddr_reset_done, i_matrix_fault, i_matrix_hard_fault, i_dfi_cancel,
    input wire i_nr_enable, i_history_reset,
    input wire [7:0] i_motion_guard, i_static_threshold, i_weak_threshold, i_motion_threshold,
    output wire m_nr_result_valid,
    input wire m_nr_result_ready,
    output wire [383:0] m_nr_result_frame,
    output wire [63:0] m_nr_result_tag, m_nr_result_key, m_nr_result_aux,
    output wire m_nr_result_ok, m_nr_result_current_ok, m_nr_result_capture_ok,
    output wire m_nr_result_history_commit,
    output wire [7:0] m_nr_result_error,
    output wire [31:0] m_nr_result_input_pixels, m_nr_result_output_pixels,
    output wire o_history_selected, o_observation_ok, o_motion_qualified,
    output wire [1:0] o_nr_history_valid,
    output wire o_dfi_read_quiescent,
    output wire [3:0] rgb_axi_awid, rgb_axi_arid,
    output wire [27:0] rgb_axi_awaddr, rgb_axi_araddr,
    output wire [7:0] rgb_axi_awlen, rgb_axi_arlen,
    output wire [2:0] rgb_axi_awsize, rgb_axi_arsize,
    output wire [1:0] rgb_axi_awburst, rgb_axi_arburst,
    output wire rgb_axi_awvalid, rgb_axi_arvalid,
    input wire rgb_axi_awready, rgb_axi_arready,
    output wire [127:0] rgb_axi_wdata,
    output wire [15:0] rgb_axi_wstrb,
    output wire rgb_axi_wlast, rgb_axi_wvalid,
    input wire rgb_axi_wready,
    input wire [3:0] rgb_axi_bid, rgb_axi_rid,
    input wire [1:0] rgb_axi_bresp, rgb_axi_rresp,
    input wire rgb_axi_bvalid, rgb_axi_rlast, rgb_axi_rvalid,
    output wire rgb_axi_bready, rgb_axi_rready,
    input wire [127:0] rgb_axi_rdata,
    output wire [3:0] map_axi_awid, map_axi_arid,
    output wire [27:0] map_axi_awaddr, map_axi_araddr,
    output wire [7:0] map_axi_awlen, map_axi_arlen,
    output wire [2:0] map_axi_awsize, map_axi_arsize,
    output wire [1:0] map_axi_awburst, map_axi_arburst,
    output wire map_axi_awvalid, map_axi_arvalid,
    input wire map_axi_awready, map_axi_arready,
    output wire [127:0] map_axi_wdata,
    output wire [15:0] map_axi_wstrb,
    output wire map_axi_wlast, map_axi_wvalid,
    input wire map_axi_wready,
    input wire [3:0] map_axi_bid, map_axi_rid,
    input wire [1:0] map_axi_bresp, map_axi_rresp,
    input wire map_axi_bvalid, map_axi_rlast, map_axi_rvalid,
    output wire map_axi_bready, map_axi_rready,
    input wire [127:0] map_axi_rdata
);
    generate if(DEHAZE_ENABLE!=0 && (DEHAZE_ENABLE!=1 || NR_ENABLE!=1))begin: bad_dehaze_backend
        PRIVATE_DEHAZE_REQUIRES_COMPILED_STAGING_BACKEND invalid_configuration();
    end endgenerate
    wire cohort_reset_n=i_pixel_rst_n && i_dfi_rst_n;
    wire pixel_reset_n, dfi_reset_n;
    reset_release_sync u_pixel_reset(.i_clk(i_pixel_clk),.i_async_rst_n(cohort_reset_n),.o_rst_n(pixel_reset_n));
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(cohort_reset_n),.o_rst_n(dfi_reset_n));
    generate if(NR_ENABLE!=0 && (NR_ENABLE!=1 || MAX_WIDTH>1920 || MAX_HEIGHT>1080 ||
        MAX_WIDTH%6!=0 || MAX_HEIGHT%6!=0)) begin : bad_nr_geometry
        PRIVATE_NR_REQUIRES_FROZEN_1080_OBSERVATION_GEOMETRY invalid_configuration();
    end endgenerate

    localparam [2:0] IDLE=0, OPEN=1, RUN=2, DRAIN=3, FAULT=4;
    reg [2:0] state, state_next;
    reg [575:0] native_context;
    wire [383:0] frame=native_context[383:0];
    wire [63:0] native_tag=native_context[447:384];
    reg [63:0] job, pair, lease;
    reg member;
    reg [31:0] writer_tag, original_input_groups, stale_original_status_count;
    reg notice_pending, notice_seen, notice_ok;
    reg [7:0] notice_error;
    reg processed_source_pending, processed_source_error;
    reg processed_seen, writer_source_started, bind_pending, protocol_fault;
    reg hard_fault_meta, hard_fault_sync;
    always @(posedge i_pixel_clk or negedge pixel_reset_n)begin
        if(!pixel_reset_n)begin hard_fault_meta<=0;hard_fault_sync<=0;end
        else begin hard_fault_meta<=i_matrix_hard_fault;hard_fault_sync<=hard_fault_meta;end
    end
    wire owner_match=i_owner_valid && i_owner_frame==s_context[383:0] &&
        i_owner_native_tag==s_context[447:384] && i_owner_lease!=0 &&
        i_owner_job!=0 && i_owner_writer_tag!=0 && i_owner_native_tag!=0;
    wire geometry_good=s_context[220:205]!=0 && s_context[220:205]<=MAX_WIDTH &&
        s_context[206:205]==0 && s_context[236:221]!=0 && s_context[236:221]<=MAX_HEIGHT;
    wire neutral_context_available;
    wire original_stats_valid,original_stats_ready;
    wire [63:0] original_stats_tag;
    wire [159:0] original_stats_context;wire [183:0] original_statistics;
    wire [159:0] incoming_neutral_context={16'd1,16'd0,8'd1,6'd0,s_context[238:237],7'd0,s_context[3],
        7'd0,s_context[4],s_context[108:77],s_context[140:109],s_context[76:45]};
    wire [159:0] locked_neutral_context={16'd1,16'd0,8'd1,6'd0,native_context[238:237],7'd0,native_context[3],
        7'd0,native_context[4],native_context[108:77],native_context[140:109],native_context[76:45]};
    wire context_fire=s_context_valid && s_context_ready;
    wire status_match=s_status_context==native_context && s_status_tag==native_tag;
    wire [31:0] accepted_groups=original_input_groups+(s_valid && s_ready ? 32'd1 : 32'd0);
    wire status_count_match=s_status_groups==accepted_groups;
    wire original_status_ready, adapter_source_ready, original_ready;
    wire original_context_valid=pixel_reset_n && state==OPEN;
    wire native_context_fire=original_context_valid && adapter_source_ready;
    wire original_valid=pixel_reset_n && state==RUN && s_valid;
    wire original_status_valid=pixel_reset_n && state==RUN && s_status_valid &&
        status_match && status_count_match && i_original_read_quiescent;
    wire [575:0] original_context=native_context;
    wire [95:0] original_rgb=s_rgb;
    wire [3:0] original_keep=s_keep;
    wire original_sof=s_sof, original_eol=s_eol, original_last=s_last;
    wire [63:0] original_tag=s_tag, original_status_tag=s_status_tag;
    wire [31:0] original_index=s_index, original_status_groups=s_status_groups;
    wire original_status_ok=s_status_ok, original_quiet=i_original_read_quiescent;
    wire [7:0] original_status_error=s_status_error;
    assign s_context_ready=o_context_available && i_owner_valid;
    assign s_ready=pixel_reset_n && state==RUN && original_ready;
    assign s_status_ready=pixel_reset_n && state==RUN &&
        (!status_match || (status_count_match && i_original_read_quiescent && original_status_ready));
    wire filtered_status_valid, filtered_status_ready, filtered_status_ok;
    wire [7:0] filtered_status_error;
    wire [31:0] filtered_status_groups;
    wire [63:0] filtered_status_tag;
    wire native_pixel_fault, native_dfi_fault;
    wire bridge_owned, bridge_done_valid, bridge_done_ok, bridge_bind_ready;
    wire [575:0] bridge_done_context;
    wire [31:0] bridge_done_tag;
    wire [7:0] bridge_done_error;
    wire bind_fire=bind_pending && bridge_bind_ready;
    wire nr_pixel_pending;
    wire bridge_matches=bridge_done_valid && bridge_done_context==native_context && bridge_done_tag==writer_tag;
    wire no_writer=!processed_seen && !writer_source_started && !bind_pending && !bridge_owned;
    wire writer_proof=NR_ENABLE==0 || no_writer || bridge_matches;
    wire terminal_allowed=notice_seen && i_pipeline_quiescent && writer_proof && !hard_fault_sync;
    assign filtered_status_ready=pixel_reset_n && state==RUN && terminal_allowed;
    wire filtered_status_fire=filtered_status_valid && filtered_status_ready;
    wire terminal_ok=filtered_status_ok && i_pipeline_ok && (NR_ENABLE==0 || no_writer || bridge_done_ok);
    wire [7:0] terminal_error=i_pipeline_error!=0 ? i_pipeline_error :
        NR_ENABLE!=0 && !no_writer && !bridge_done_ok ? bridge_done_error : filtered_status_error;
    assign m_source_notice_valid=pixel_reset_n && notice_pending;
    assign m_source_notice_context=native_context;
    assign m_source_notice_ok=notice_ok;
    assign m_source_notice_error=notice_error;
    assign m_processed_source_valid=pixel_reset_n && processed_source_pending;
    assign m_processed_source_frame=frame;
    assign m_processed_source_lease=lease;
    assign m_processed_source_job=job;
    assign m_processed_source_pair=pair;
    assign m_processed_source_member=member;
    assign m_processed_source_write_tag={32'd0,writer_tag};
    assign m_processed_source_error=processed_source_error;
    assign o_stale_original_status_count=stale_original_status_count;
    assign o_pixel_fault=protocol_fault || native_pixel_fault || hard_fault_sync;
    assign o_dfi_fault=native_dfi_fault || i_matrix_hard_fault;
    // An ACTIVE owner was admitted before this context; retirement proof may
    // already be withheld. Only new upstream owner admission uses pool_idle.
    assign o_context_available=pixel_reset_n && neutral_context_available && state==IDLE &&
        !nr_pixel_pending && !bridge_owned && !o_pixel_fault;
    assign o_pool_idle=o_context_available && i_pipeline_quiescent;

    always @(*) begin
        state_next=state;
        case(state)
            IDLE: if(context_fire) state_next=owner_match && geometry_good ? OPEN : FAULT;
            OPEN: if(native_context_fire) state_next=RUN;
            RUN: if(filtered_status_fire) state_next=DRAIN;
            DRAIN: if(!processed_source_pending && !notice_pending && !nr_pixel_pending &&
                !bridge_owned && i_pipeline_quiescent) state_next=IDLE;
            FAULT: state_next=FAULT;
            default: state_next=FAULT;
        endcase
        if(state==RUN && s_status_valid && status_match && !status_count_match)state_next=FAULT;
    end
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n)state<=IDLE;
        else state<=state_next;
    end
    // Context acceptance freezes only metadata; upstream keeps its RAW lease.
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n)begin
            native_context<=0;job<=0;pair<=0;lease<=0;member<=0;writer_tag<=0;
            original_input_groups<=0;stale_original_status_count<=0;
            notice_pending<=0;notice_seen<=0;notice_ok<=0;notice_error<=0;
            processed_source_pending<=0;processed_source_error<=0;
            processed_seen<=0;writer_source_started<=0;bind_pending<=0;protocol_fault<=0;
        end else begin
            if(state_next==FAULT)protocol_fault<=1;
            if(context_fire && state_next==OPEN)begin
                native_context<=s_context;job<=i_owner_job;pair<=i_owner_pair;
                lease<=i_owner_lease;member<=i_owner_member;writer_tag<=i_owner_writer_tag;
                original_input_groups<=0;notice_pending<=0;notice_seen<=0;
                processed_source_pending<=0;processed_seen<=0;writer_source_started<=0;bind_pending<=0;
            end
            if(s_valid && s_ready)original_input_groups<=original_input_groups+1'b1;
            if(s_status_valid && s_status_ready && !status_match && !(&stale_original_status_count))
                stale_original_status_count<=stale_original_status_count+1'b1;
            if(filtered_status_valid && !notice_seen && !notice_pending)begin
                notice_pending<=1;notice_ok<=filtered_status_ok;notice_error<=filtered_status_error;
            end
            if(m_source_notice_valid && m_source_notice_ready)begin notice_pending<=0;notice_seen<=1;end
            if(i_processed_sof_fire && state==RUN)begin
                if(processed_seen)protocol_fault<=1;
                else begin processed_seen<=1;if(NR_ENABLE!=0)bind_pending<=1;end
            end
            if(i_writer_source_start_fire && state==RUN)begin
                if(writer_source_started || !(processed_seen || i_processed_sof_fire))protocol_fault<=1;
                writer_source_started<=1;
            end
            if(bind_fire)bind_pending<=0;
            if(filtered_status_fire)begin
                processed_source_pending<=1;processed_source_error<=!terminal_ok;
                if(filtered_status_tag!=native_tag)protocol_fault<=1;
            end
            if(m_processed_source_valid && m_processed_source_ready)processed_source_pending<=0;
            if(m_context_valid && m_context_ready && m_context!=native_context)protocol_fault<=1;
        end
    end

    generate if(NR_ENABLE!=0 && NEUTRAL_STATS_ENABLE!=0)begin: g_neutral_stats
        nr_original_stats_cdc4 u_stats(
            .i_dfi_clk(i_dfi_clk),.i_dfi_rst_n(cohort_reset_n),.i_pixel_clk(i_pixel_clk),.i_pixel_rst_n(cohort_reset_n),
            .s_valid(original_stats_valid),.s_ready(original_stats_ready),.s_tag(original_stats_tag),
            .s_context(original_stats_context),.s_statistics(original_statistics),
            .o_dfi_reset_done(),.o_pixel_reset_done(),
            .i_context_fire(context_fire && owner_match && geometry_good),.i_context_tag(s_context[447:384]),
            .i_context(incoming_neutral_context),.i_request(i_neutral_stats_request),
            .i_product_begin(i_neutral_record_begin),.i_product_context(i_neutral_record_context),
            .i_frame_released(m_processed_source_valid && m_processed_source_ready),.i_release_context(locked_neutral_context),
            .o_context_available(neutral_context_available),.m_valid(m_neutral_stats_valid),.m_ready(m_neutral_stats_ready),
            .m_context(m_neutral_stats_context),.m_statistics(m_neutral_statistics),.o_stale_count(o_neutral_stats_stale_count));
    end else begin: g_no_neutral_stats
        assign neutral_context_available=1'b1;
        assign m_neutral_stats_valid=1'b0;assign m_neutral_stats_context=160'd0;
        assign m_neutral_statistics=184'd0;assign o_neutral_stats_stale_count=32'd0;
        assign original_stats_ready=1'b1;
    end endgenerate
    generate if(NR_ENABLE!=0) begin : nr
        reg retire_toggle;
        reg retire_meta,retire_sync,retire_seen,pending;
        always @(posedge i_dfi_clk or negedge dfi_reset_n) begin
            if(!dfi_reset_n) retire_toggle<=0;
            else if(m_nr_result_valid && m_nr_result_ready)retire_toggle<=!retire_toggle;
        end
        always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
            if(!pixel_reset_n)begin retire_meta<=0;retire_sync<=0;retire_seen<=0;pending<=0;end
            else begin
                retire_meta<=retire_toggle;retire_sync<=retire_meta;
                if(native_context_fire)pending<=1;
                if(retire_sync!=retire_seen)begin retire_seen<=retire_sync;pending<=0;end
            end
        end
        assign nr_pixel_pending=pending;
        rgb_product_retire_cdc u_writer_proof(
            .i_pixel_clk(i_pixel_clk),.i_pixel_rst_n(cohort_reset_n),.i_dfi_clk(i_dfi_clk),.i_dfi_rst_n(cohort_reset_n),
            .s_bind_context(native_context),.s_bind_writer_tag(writer_tag),.s_bind_valid(bind_pending),
            .s_bind_ready(bridge_bind_ready),.o_pixel_reset_done(),.o_dfi_reset_done(),.o_pixel_owned(bridge_owned),
            .o_bind_ready(o_writer_start_permitted),.o_bind_context(),.o_bind_writer_tag(),
            .i_writer_start_fire(i_writer_start_fire),.s_write_valid(s_write_valid),.s_write_ready(s_write_ready),
            .s_write_tag(s_write_tag),.s_write_sequence(s_write_sequence),.s_write_session(s_write_session),
            .s_write_epoch(s_write_epoch),.s_write_camera(s_write_camera),.s_write_ok(s_write_ok),.s_write_error(s_write_error),
            .o_stale_write_count(),.o_stale_reply_count(),.m_done_valid(bridge_done_valid),
            .m_done_ready(filtered_status_fire),.m_done_context(bridge_done_context),.m_done_writer_tag(bridge_done_tag),
            .m_done_ok(bridge_done_ok),.m_done_error(bridge_done_error));
        staged_motion_nr_pixel_service4 #(.SOURCE_WIDTH(MAX_WIDTH),.SOURCE_HEIGHT(MAX_HEIGHT),.PREOWNED_CONTEXT_ENABLE(1),.SHARED_PHASE_FIFO_ENABLE(1),.NEUTRAL_STATS_ENABLE(NEUTRAL_STATS_ENABLE),.DEHAZE_ENABLE(DEHAZE_ENABLE)) u_nr(
            .i_f21_config(i_f21_config),
            .i_f21_required_lut_generation(i_f21_required_lut_generation),
            .f21_cfg_begin_valid(f21_cfg_begin_valid),
            .f21_cfg_begin_ready(f21_cfg_begin_ready),
            .f21_cfg_generation(f21_cfg_generation),
            .f21_cfg_valid(f21_cfg_valid),
            .f21_cfg_ready(f21_cfg_ready),
            .f21_cfg_index(f21_cfg_index),
            .f21_cfg_value(f21_cfg_value),
            .f21_cfg_commit_valid(f21_cfg_commit_valid),
            .f21_cfg_commit_ready(f21_cfg_commit_ready),
            .f21_cfg_abort(f21_cfg_abort),
            .f21_cfg_status_valid(f21_cfg_status_valid),
            .f21_cfg_status_ready(f21_cfg_status_ready),
            .f21_cfg_status_ok(f21_cfg_status_ok),
            .f21_cfg_status_error(f21_cfg_status_error),
            .f21_cfg_status_generation(f21_cfg_status_generation),
            .o_f21_lut_valid(o_f21_lut_valid),
            .o_f21_lut_generation(o_f21_lut_generation),
            .o_f21_start_eligible(o_f21_start_eligible),
            .o_f21_busy(o_f21_busy),
            .o_f21_read_quiescent(o_f21_read_quiescent),
            .o_f21_protocol_fault(o_f21_protocol_fault),
            .o_f21_fence_valid(o_f21_fence_valid),
            .o_f21_fence_identity(o_f21_fence_identity),
            .o_f21_fence_ok(o_f21_fence_ok),
            .o_f21_fence_error(o_f21_fence_error),
            .o_f21_fence_pixels(o_f21_fence_pixels),
            .o_f21_history_used(o_f21_history_used),
            .o_f21_metadata_bypass(o_f21_metadata_bypass),
            .o_f21_frame_lut_generation(o_f21_frame_lut_generation),
            .o_f21_map_commit(o_f21_map_commit),
            .o_f21_map_commit_frame(o_f21_map_commit_frame),
            .m_original_stats_valid(original_stats_valid),.m_original_stats_ready(original_stats_ready),
            .m_original_stats_tag(original_stats_tag),.m_original_stats_context(original_stats_context),
            .m_original_statistics(original_statistics),
            .i_pixel_clk(i_pixel_clk),.i_pixel_rst_n(cohort_reset_n),.i_dfi_clk(i_dfi_clk),.i_dfi_rst_n(cohort_reset_n),
            .o_pixel_reset_done(),.o_dfi_reset_done(),.s_context(original_context),.s_context_valid(original_context_valid),
            .s_context_ready(adapter_source_ready),.s_rgb(original_rgb),.s_keep(original_keep),
            .s_sof(original_sof),.s_eol(original_eol),.s_last(original_last),.s_valid(original_valid),.s_ready(original_ready),
            .s_tag(original_tag),.s_index(original_index),.s_status_valid(original_status_valid),.s_status_ready(original_status_ready),
            .s_status_context(native_context),.s_status_tag(original_status_tag),.s_status_ok(original_status_ok),
            .s_status_error(original_status_error),.i_pixel_source_read_quiescent(original_quiet),
            .o_source_stale_status_count(),.o_pixel_protocol_fault(native_pixel_fault),.o_dfi_protocol_fault(native_dfi_fault),
            .o_dfi_context(),.o_dfi_context_valid(),.o_start_fire(o_nr_start_fire),.i_cancel(i_dfi_cancel),
            .m_context(m_context),.m_context_valid(m_context_valid),.m_context_ready(m_context_ready),
            .m_rgb(m_rgb),.m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_valid(m_valid),.m_ready(m_ready),
            .m_tag(m_tag),.m_index(m_index),.m_bad(),.m_status_valid(filtered_status_valid),.m_status_ready(filtered_status_ready),
            .m_status_tag(filtered_status_tag),.m_status_ok(filtered_status_ok),.m_status_error(filtered_status_error),
            .m_status_groups(filtered_status_groups),.i_pixel_filtered_context(native_context),
            .i_pixel_filtered_read_quiescent(terminal_allowed),.i_pixel_filtered_ok(terminal_ok),.i_pixel_filtered_error(terminal_error),
            .o_pixel_read_quiescent(),.o_filtered_stale_proof_count(),.o_dfi_stale_ack_count(),
            .o_reverse_fence_sent(),.o_source_done(),.o_gray_empty(),.m_result_valid(m_nr_result_valid),.m_result_ready(m_nr_result_ready),
            .o_dfi_read_quiescent(o_dfi_read_quiescent),.i_ddr_reset_done(i_ddr_reset_done),.i_matrix_fault(i_matrix_fault),.i_matrix_hard_fault(i_matrix_hard_fault),
            .m_capture_ack_valid(),.m_capture_ack_ready(1'b1),.m_capture_ack_frame(),.m_capture_ack_tag(),.m_capture_ack_key(),.m_capture_ack_aux(),
            .m_capture_ack_ok(),.m_capture_ack_error(),.m_capture_ack_pixels(),.i_enable(i_nr_enable),.i_history_reset(i_history_reset),
            .m_result_frame(m_nr_result_frame),.m_result_tag(m_nr_result_tag),.m_result_key(m_nr_result_key),.m_result_aux(m_nr_result_aux),
            .m_result_ok(m_nr_result_ok),.m_result_current_ok(m_nr_result_current_ok),.m_result_capture_ok(m_nr_result_capture_ok),
            .m_result_history_commit(m_nr_result_history_commit),.m_result_error(m_nr_result_error),.m_result_capture_pixels(),
            .m_result_input_pixels(m_nr_result_input_pixels),.m_result_output_pixels(m_nr_result_output_pixels),.m_result_raw_pixels(),
            .o_offer_valid(),.o_backend_offer_valid(),.o_offer_frame(),.o_offer_tag(),.o_offer_key(),.o_offer_aux(),
            .o_history_selected(o_history_selected),.o_busy(),.o_abort_request(),.o_quarantined(),.o_nr_history_valid(o_nr_history_valid),
            .o_rgb_active_banks(),.o_rgb_pinned_banks(),.o_stale_control_count(),
            .rgb_axi_awid(rgb_axi_awid),.rgb_axi_arid(rgb_axi_arid),.rgb_axi_awaddr(rgb_axi_awaddr),.rgb_axi_araddr(rgb_axi_araddr),
            .rgb_axi_awlen(rgb_axi_awlen),.rgb_axi_arlen(rgb_axi_arlen),.rgb_axi_awsize(rgb_axi_awsize),.rgb_axi_arsize(rgb_axi_arsize),
            .rgb_axi_awburst(rgb_axi_awburst),.rgb_axi_arburst(rgb_axi_arburst),.rgb_axi_awvalid(rgb_axi_awvalid),.rgb_axi_arvalid(rgb_axi_arvalid),
            .rgb_axi_awready(rgb_axi_awready),.rgb_axi_arready(rgb_axi_arready),.rgb_axi_wdata(rgb_axi_wdata),.rgb_axi_wstrb(rgb_axi_wstrb),
            .rgb_axi_wlast(rgb_axi_wlast),.rgb_axi_wvalid(rgb_axi_wvalid),.rgb_axi_wready(rgb_axi_wready),.rgb_axi_bid(rgb_axi_bid),
            .rgb_axi_rid(rgb_axi_rid),.rgb_axi_bresp(rgb_axi_bresp),.rgb_axi_rresp(rgb_axi_rresp),.rgb_axi_bvalid(rgb_axi_bvalid),
            .rgb_axi_rlast(rgb_axi_rlast),.rgb_axi_rvalid(rgb_axi_rvalid),.rgb_axi_bready(rgb_axi_bready),.rgb_axi_rready(rgb_axi_rready),.rgb_axi_rdata(rgb_axi_rdata),
            .i_motion_guard(i_motion_guard),.i_static_threshold(i_static_threshold),.i_weak_threshold(i_weak_threshold),.i_motion_threshold(i_motion_threshold),
            .o_observation_ok(o_observation_ok),.o_motion_success(),.o_motion_qualified(o_motion_qualified),.o_motion_skipped(),
            .o_map_committed(),.o_motion_backend_fault(),.o_observation_error(),.o_motion_error(),.o_projection_error(),
            .o_observation_pixels(),.o_observation_delivered(),.o_observation_dropped(),.o_y_pinned_banks(),
            .map_axi_awid(map_axi_awid),.map_axi_arid(map_axi_arid),.map_axi_awaddr(map_axi_awaddr),.map_axi_araddr(map_axi_araddr),
            .map_axi_awlen(map_axi_awlen),.map_axi_arlen(map_axi_arlen),.map_axi_awsize(map_axi_awsize),.map_axi_arsize(map_axi_arsize),
            .map_axi_awburst(map_axi_awburst),.map_axi_arburst(map_axi_arburst),.map_axi_awvalid(map_axi_awvalid),.map_axi_arvalid(map_axi_arvalid),
            .map_axi_awready(map_axi_awready),.map_axi_arready(map_axi_arready),.map_axi_wdata(map_axi_wdata),.map_axi_wstrb(map_axi_wstrb),
            .map_axi_wlast(map_axi_wlast),.map_axi_wvalid(map_axi_wvalid),.map_axi_wready(map_axi_wready),.map_axi_bid(map_axi_bid),
            .map_axi_rid(map_axi_rid),.map_axi_bresp(map_axi_bresp),.map_axi_rresp(map_axi_rresp),.map_axi_bvalid(map_axi_bvalid),
            .map_axi_rlast(map_axi_rlast),.map_axi_rvalid(map_axi_rvalid),.map_axi_bready(map_axi_bready),.map_axi_rready(map_axi_rready),.map_axi_rdata(map_axi_rdata));
    end else begin : direct
        assign f21_cfg_begin_ready=1'd0;
        assign f21_cfg_ready=1'd0;
        assign f21_cfg_commit_ready=1'd0;
        assign f21_cfg_status_valid=1'd0;
        assign f21_cfg_status_ok=1'd0;
        assign f21_cfg_status_error=8'd0;
        assign f21_cfg_status_generation=32'd0;
        assign o_f21_lut_valid=1'd0;
        assign o_f21_lut_generation=32'd0;
        assign o_f21_start_eligible=1'd0;
        assign o_f21_busy=1'd0;
        assign o_f21_read_quiescent=1'd1;
        assign o_f21_protocol_fault=1'd0;
        assign o_f21_fence_valid=1'd0;
        assign o_f21_fence_identity=576'd0;
        assign o_f21_fence_ok=1'd0;
        assign o_f21_fence_error=8'd0;
        assign o_f21_fence_pixels=32'd0;
        assign o_f21_history_used=1'd0;
        assign o_f21_metadata_bypass=1'd0;
        assign o_f21_frame_lut_generation=32'd0;
        assign o_f21_map_commit=1'd0;
        assign o_f21_map_commit_frame=32'd0;
        assign m_context=original_context;assign m_context_valid=original_context_valid;
        assign adapter_source_ready=m_context_ready;assign m_rgb=original_rgb;assign m_keep=original_keep;
        assign m_sof=original_sof;assign m_eol=original_eol;assign m_last=original_last;assign m_valid=original_valid;
        assign original_ready=m_ready;assign m_tag=original_tag;assign m_index=original_index;
        assign filtered_status_valid=original_status_valid;assign original_status_ready=filtered_status_ready;
        assign filtered_status_ok=original_status_ok;assign filtered_status_error=original_status_error;
        assign filtered_status_tag=original_status_tag;assign filtered_status_groups=original_status_groups;
        assign native_pixel_fault=0;assign native_dfi_fault=0;assign nr_pixel_pending=0;
        assign bridge_owned=0;assign bridge_done_valid=0;assign bridge_done_context=0;assign bridge_done_tag=0;
        assign bridge_done_ok=0;assign bridge_done_error=0;assign bridge_bind_ready=0;
        assign o_writer_start_permitted=1;assign s_write_ready=1;
        assign m_nr_result_valid=0;assign m_nr_result_frame=0;assign m_nr_result_tag=0;assign m_nr_result_key=0;
        assign m_nr_result_aux=0;assign m_nr_result_ok=0;assign m_nr_result_current_ok=0;assign m_nr_result_capture_ok=0;
        assign m_nr_result_history_commit=0;assign m_nr_result_error=0;assign m_nr_result_input_pixels=0;assign m_nr_result_output_pixels=0;
        assign o_nr_start_fire=1'b0;
        assign o_history_selected=0;assign o_observation_ok=0;assign o_motion_qualified=0;assign o_nr_history_valid=0;assign o_dfi_read_quiescent=1;
        assign rgb_axi_awid=0;assign rgb_axi_arid=0;assign rgb_axi_awaddr=0;assign rgb_axi_araddr=0;assign rgb_axi_awlen=0;assign rgb_axi_arlen=0;
        assign rgb_axi_awsize=0;assign rgb_axi_arsize=0;assign rgb_axi_awburst=0;assign rgb_axi_arburst=0;assign rgb_axi_awvalid=0;assign rgb_axi_arvalid=0;
        assign rgb_axi_wdata=0;assign rgb_axi_wstrb=0;assign rgb_axi_wlast=0;assign rgb_axi_wvalid=0;assign rgb_axi_bready=0;assign rgb_axi_rready=0;
        assign map_axi_awid=0;assign map_axi_arid=0;assign map_axi_awaddr=0;assign map_axi_araddr=0;assign map_axi_awlen=0;assign map_axi_arlen=0;
        assign map_axi_awsize=0;assign map_axi_arsize=0;assign map_axi_awburst=0;assign map_axi_arburst=0;assign map_axi_awvalid=0;assign map_axi_arvalid=0;
        assign map_axi_wdata=0;assign map_axi_wstrb=0;assign map_axi_wlast=0;assign map_axi_wvalid=0;assign map_axi_bready=0;assign map_axi_rready=0;
    end endgenerate
endmodule
