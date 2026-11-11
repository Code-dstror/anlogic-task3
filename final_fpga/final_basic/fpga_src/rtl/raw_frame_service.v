`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// S04 domain boundary: all bulk and command crossings use configured TD FIFOs.
module raw_frame_service #(
    parameter integer WIDTH = 1920, parameter integer HEIGHT = 1080,
    parameter integer DESCRIPTOR_ENABLE = 0,
    parameter integer DUAL_CAPTURE_ENABLE = 0,
    parameter integer PAIR_METADATA_ENABLE = 0,
    parameter integer PHYSICAL_MONO_CURRENT_ENABLE = 0,
    parameter integer CAMERA_COUNT = 2,
    parameter integer CANONICAL_PRIVATE_FETCH_ENABLE = 0,
    parameter integer MASK_EXPORT_ENABLE = 0,
    parameter integer SHARED_REPLAY_FIFO_ENABLE = 0,
    parameter integer PRIVATE_REPLAY_ENABLE = 0,
    parameter integer HOST_REPLAY_CONTEXT_ENABLE = 0,
    parameter integer SOURCE_TERMINAL_ENABLE = 0,
    parameter integer CFS_ENABLE = 0,
    parameter integer OFFICIAL_CRC_QUALIFIED = 0
) (
    input wire i_pixel_clk, input wire i_pixel_rst_n,
    input wire i_dfi_clk, input wire i_dfi_rst_n, input wire i_ddr_ready,
    input wire i_cfs_enable,
    input wire i_physical_mono_current_enable,
    output wire [31:0] o_cfs_compressed_count,o_cfs_no_benefit_count,o_cfs_overflow_count,o_cfs_busy_count,
    output wire o_cfs_protocol_fault,
    input wire i_user_clk, input wire i_user_rst_n,
    input wire [39:0] i_capture_data,
    input wire i_capture_valid, input wire i_capture_accept,
    input wire i_capture_sof, input wire i_capture_eol, input wire i_capture_abort,
    input wire [31:0] i_capture_epoch,
    input wire [31:0] i_session_id, i_frame_sequence, i_mode_epoch,
    input wire [196:0] i_capture_metadata,
    input wire i_capture_source_valid, output wire o_capture_source_ready,
    input wire [31:0] i_capture_source_session, i_capture_source_epoch, i_capture_source_sequence,
    input wire i_capture_source_camera, i_capture_source_ok,
    input wire [7:0] i_capture_source_error,
    output wire [31:0] o_capture_source_stale_count,
    // Optional independent capture domain; absent in the default board profile.
    input wire i_capture1_clk, input wire i_capture1_rst_n,
    input wire [39:0] i_capture1_data,
    input wire i_capture1_valid, input wire i_capture1_accept,
    input wire i_capture1_sof, input wire i_capture1_eol, input wire i_capture1_abort,
    input wire [31:0] i_capture1_session, i_capture1_sequence, i_capture1_epoch,
    input wire [196:0] i_capture1_metadata,
    input wire i_capture1_source_valid, output wire o_capture1_source_ready,
    input wire [31:0] i_capture1_source_session, i_capture1_source_epoch, i_capture1_source_sequence,
    input wire i_capture1_source_camera, i_capture1_source_ok,
    input wire [7:0] i_capture1_source_error,
    output wire [31:0] o_capture1_source_stale_count,
    // Local handshake observations for the independent count-fence owner.
    // capture0 outputs belong to pixel; capture1 outputs to capture1; consume
    // and global write-quiescent belong to DFI. None performs CDC by itself.
    output wire o_capture0_enqueue_fire, o_capture1_enqueue_fire,
    output wire o_capture0_consume_fire, o_capture1_consume_fire,
    output wire o_capture0_idle, o_capture1_idle,
    output wire o_capture0_frame_accept, o_capture1_frame_accept,
    output wire o_capture_write_quiescent,
    output wire o_private_ownership_quiescent,
    // Private DFI-domain candidate/job owner; host pins are independent.
    output wire o_commit_valid,
    output wire [383:0] o_commit_frame,
    output wire [63:0] o_commit_lease,
    input wire i_commit_ready,
    input wire i_ref_valid,
    output wire o_ref_ready,
    input wire [1:0] i_ref_op, i_ref_mask,
    input wire [383:0] i_ref_frame0, i_ref_frame1,
    input wire [63:0] i_ref_lease0, i_ref_lease1, i_ref_job_id,
    output wire o_reference_fault,
    output wire o_read_quiescent,
    // Optional held phase reuses the complete 147x512 replay FIFO. DFI and
    // PIX selects belong to their respective domains and remain held until
    // the real source/product/reference owners have retired.
    input wire i_shared_replay_source_select,i_shared_replay_sink_select,
    input wire [146:0] s_shared_replay_data,input wire s_shared_replay_valid,
    output wire s_shared_replay_ready,o_shared_replay_source_reset_done,
    output wire [146:0] m_shared_replay_data,output wire m_shared_replay_valid,
    input wire m_shared_replay_ready,
    output wire o_shared_replay_sink_reset_done,
    // DFI-domain private read client. This interface has no BAR ABI exposure.
    input wire i_private_req_valid, output wire o_private_req_ready,
    input wire [2:0] i_private_req_op,
    input wire i_private_req_camera,
    input wire [1:0] i_private_req_slot,
    input wire [31:0] i_private_req_generation, i_private_req_session,
    input wire [63:0] i_private_req_lease, i_private_req_job_id,
    input wire [31:0] i_private_req_offset,i_private_req_length,
    input wire i_public_read_admission_enable,
    output wire o_public_read_quiescent,
    // Optional public MASK target in DFI. These packets borrow the existing
    // command/response/block transport; the target owns it through cache RETIRE.
    output wire [133:0] o_mask_command_data,
    output wire o_mask_command_valid,
    input wire i_mask_command_ready,
    input wire [146:0] i_mask_response_data,
    input wire i_mask_response_valid,
    output wire o_mask_response_ready,
    input wire [146:0] i_mask_block_data,
    input wire i_mask_block_valid,
    output wire o_mask_block_ready,
    output wire o_mask_cache_retire,
    input wire i_mask_owner_complete,
    input wire [383:0] i_private_descriptor,
    input wire [63:0] i_private_pair_id,
    input wire i_private_member_index,
    output wire o_private_rsp_valid, input wire i_private_rsp_ready,
    output wire [3:0] o_private_rsp_code,
    output wire o_private_rsp_camera,
    output wire [1:0] o_private_rsp_slot,
    output wire [31:0] o_private_rsp_generation, o_private_rsp_session,
    output wire [31:0] o_private_rsp_sequence, o_private_rsp_epoch,
    output wire [383:0] o_private_rsp_descriptor,
    output wire o_private_rsp_metadata_valid,
    output wire [127:0] o_private_read_data,
    output wire [15:0] o_private_read_keep,
    output wire o_private_read_valid,o_private_read_last,
    input wire i_private_read_ready,
    output wire o_private_read_complete,o_private_read_error,o_private_read_protocol_fault,
    output wire o_private_native_done, o_private_native_error,
    output wire [63:0] o_private_native_job_id,
    output wire o_private_native_member_index,
    // Pixel-domain original frame context, admitted before native SOF.
    output wire o_replay_context_valid, input wire i_replay_context_ready,
    output wire [383:0] o_replay_descriptor,
    output wire [63:0] o_replay_job_id, o_replay_pair_id,
    output wire o_replay_member_index, o_replay_private,
    output wire o_replay_protocol_fault,
    output wire o_host_replay_context_valid,
    input wire i_host_replay_context_ready,
    output wire [383:0] o_host_replay_descriptor,
    output wire o_host_replay_metadata_valid,
    // Pixel-domain true private source completion, including a zero-pixel error.
    output wire o_replay_native_done,o_replay_native_error,
    input wire i_replay_safe,
    output wire o_replay_active,
    output wire [39:0] o_replay_data, output wire o_replay_valid,
    input wire i_replay_ready,
    output wire o_replay_sof, output wire o_replay_eol, output wire o_replay_abort,
    input wire i_bar_write_valid, input wire [11:0] i_bar_write_offset,
    input wire [31:0] i_bar_write_data, input wire [3:0] i_bar_write_strobes,
    output wire [1:0] o_bar_write_response,
    input wire i_bar_read_valid, input wire [11:0] i_bar_read_offset,
    output wire o_bar_read_response_valid, output wire [31:0] o_bar_read_data,
    output wire [1:0] o_bar_read_response,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    input wire [3:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [3:0] m_axi_arid,
    output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,
    input wire m_axi_rvalid,
    output wire m_axi_rready
);
    generate if(CANONICAL_PRIVATE_FETCH_ENABLE!=0 &&
        (CANONICAL_PRIVATE_FETCH_ENABLE!=1 || PRIVATE_REPLAY_ENABLE!=1 ||
         PAIR_METADATA_ENABLE!=1 || DESCRIPTOR_ENABLE!=1))begin: bad_canonical_private_fetch
        CANONICAL_PRIVATE_FETCH_REQUIRES_AUTHENTICATED_PRIVATE_CONTEXT invalid_configuration();
    end endgenerate
    generate if(SHARED_REPLAY_FIFO_ENABLE!=0 &&
        (SHARED_REPLAY_FIFO_ENABLE!=1 || CANONICAL_PRIVATE_FETCH_ENABLE!=1))begin: bad_shared_replay
        SHARED_REPLAY_FIFO_REQUIRES_CANONICAL_PRIVATE_READER invalid_configuration();
    end endgenerate
    // BAR identity survives an application reset, while every command/data
    // FIFO endpoint must discard that session's queued transactions.
    wire user_stream_rst_n;
    reset_release_sync u_user_stream_reset (
        .i_clk(i_user_clk), .i_async_rst_n(i_user_rst_n && i_dfi_rst_n),
        .o_rst_n(user_stream_rst_n)
    );
    wire [146:0] capture_source, capture_sink;
    wire [9:0] capture_available, capture1_available;
    wire [146:0] capture1_sink;
    wire capture1_sink_valid, capture1_sink_ready;
    wire capture_source_valid, capture_source_ready, capture_sink_valid, capture_sink_ready;
    raw10_frame_ingress #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
        .CONTEXT_ENABLE(DESCRIPTOR_ENABLE),.EXTERNAL_SEQUENCE_ENABLE(DESCRIPTOR_ENABLE),
        .PAIR_METADATA_ENABLE(PAIR_METADATA_ENABLE),.SOURCE_TERMINAL_ENABLE(SOURCE_TERMINAL_ENABLE)) u_ingress (
        .i_clk(i_pixel_clk), .i_rst_n(i_pixel_rst_n), .i_enable(1'b1),
        .i_data(i_capture_data), .i_valid(i_capture_valid), .i_accept(i_capture_accept),
        .i_sof(i_capture_sof), .i_eol(i_capture_eol), .i_abort(i_capture_abort),
        .i_camera(1'b0), .i_epoch(DESCRIPTOR_ENABLE ? i_mode_epoch : i_capture_epoch),
        .i_session_id(i_session_id),.i_external_sequence(i_frame_sequence),
        .i_metadata_valid(i_capture_metadata[196]), .i_timestamp(i_capture_metadata[63:0]),
        .i_actual_exposure(i_capture_metadata[95:64]), .i_gain(i_capture_metadata[127:96]),
        .i_calibration_id(i_capture_metadata[159:128]), .i_source_kind(i_capture_metadata[192]),
        .i_exposure_role(i_capture_metadata[194:193]), .i_exposure_group(i_capture_metadata[191:160]),
        .i_source_qualified(i_capture_metadata[195]),
        .i_source_valid(i_capture_source_valid),.o_source_ready(o_capture_source_ready),
        .i_source_session(i_capture_source_session),.i_source_epoch(i_capture_source_epoch),
        .i_source_sequence(i_capture_source_sequence),.i_source_camera(i_capture_source_camera),
        .i_source_ok(i_capture_source_ok),.i_source_error(i_capture_source_error),
        .o_source_stale_count(o_capture_source_stale_count),
        .o_axis_tdata(capture_source[127:0]), .o_axis_tkeep(capture_source[143:128]),
        .o_axis_tlast(capture_source[144]), .o_axis_tuser(capture_source[146:145]),
        .o_axis_tvalid(capture_source_valid), .i_axis_tready(capture_source_ready),
        .o_capture_idle(o_capture0_idle),.o_frame_accept(o_capture0_frame_accept),
        .o_drop_count(), .o_error_count()
    );
    raw_capture_fifo_ip u_capture_fifo (
        .i_source_clk(i_pixel_clk), .i_source_rst_n(i_pixel_rst_n),
        .i_source_data(capture_source), .i_source_valid(capture_source_valid),
        .o_source_ready(capture_source_ready), .o_source_reset_done(),
        .i_sink_clk(i_dfi_clk), .i_sink_rst_n(i_dfi_rst_n),
        .o_sink_data(capture_sink), .o_sink_valid(capture_sink_valid),
        .i_sink_ready(capture_sink_ready), .o_sink_reset_done(),
        .o_available_count(capture_available)
    );

    generate if (DUAL_CAPTURE_ENABLE != 0) begin : g_capture1
        wire [146:0] source_data;
        wire source_valid, source_ready;
        raw10_frame_ingress #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
            .CONTEXT_ENABLE(DESCRIPTOR_ENABLE),.EXTERNAL_SEQUENCE_ENABLE(DESCRIPTOR_ENABLE),
            .PAIR_METADATA_ENABLE(PAIR_METADATA_ENABLE),.SOURCE_TERMINAL_ENABLE(SOURCE_TERMINAL_ENABLE)) u_ingress (
            .i_clk(i_capture1_clk), .i_rst_n(i_capture1_rst_n), .i_enable(1'b1),
            .i_data(i_capture1_data), .i_valid(i_capture1_valid), .i_accept(i_capture1_accept),
            .i_sof(i_capture1_sof), .i_eol(i_capture1_eol), .i_abort(i_capture1_abort),
            .i_camera(1'b1), .i_epoch(i_capture1_epoch),
            .i_session_id(i_capture1_session), .i_external_sequence(i_capture1_sequence),
            .i_metadata_valid(i_capture1_metadata[196]), .i_timestamp(i_capture1_metadata[63:0]),
            .i_actual_exposure(i_capture1_metadata[95:64]), .i_gain(i_capture1_metadata[127:96]),
            .i_calibration_id(i_capture1_metadata[159:128]), .i_source_kind(i_capture1_metadata[192]),
            .i_exposure_role(i_capture1_metadata[194:193]), .i_exposure_group(i_capture1_metadata[191:160]),
            .i_source_qualified(i_capture1_metadata[195]),
            .i_source_valid(i_capture1_source_valid),.o_source_ready(o_capture1_source_ready),
            .i_source_session(i_capture1_source_session),.i_source_epoch(i_capture1_source_epoch),
            .i_source_sequence(i_capture1_source_sequence),.i_source_camera(i_capture1_source_camera),
            .i_source_ok(i_capture1_source_ok),.i_source_error(i_capture1_source_error),
            .o_source_stale_count(o_capture1_source_stale_count),
            .o_axis_tdata(source_data[127:0]), .o_axis_tkeep(source_data[143:128]),
            .o_axis_tlast(source_data[144]), .o_axis_tuser(source_data[146:145]),
            .o_axis_tvalid(source_valid), .i_axis_tready(source_ready),
            .o_capture_idle(o_capture1_idle),.o_frame_accept(o_capture1_frame_accept),
            .o_drop_count(), .o_error_count()
        );
        assign o_capture1_enqueue_fire=source_valid && source_ready;
        raw_capture_fifo_ip u_capture_fifo (
            .i_source_clk(i_capture1_clk), .i_source_rst_n(i_capture1_rst_n),
            .i_source_data(source_data), .i_source_valid(source_valid),
            .o_source_ready(source_ready), .o_source_reset_done(),
            .i_sink_clk(i_dfi_clk), .i_sink_rst_n(i_dfi_rst_n),
            .o_sink_data(capture1_sink), .o_sink_valid(capture1_sink_valid),
            .i_sink_ready(capture1_sink_ready), .o_sink_reset_done(),
            .o_available_count(capture1_available)
        );
    end else begin : g_single_capture
        assign capture1_sink = 147'd0;
        assign capture1_sink_valid = 1'b0;
        assign capture1_available = 10'd0;
        assign o_capture1_enqueue_fire=1'b0;
        assign o_capture1_idle=1'b1;
        assign o_capture1_frame_accept=1'b0;
        assign o_capture1_source_ready=1'b0;
        assign o_capture1_source_stale_count=32'd0;
    end endgenerate

    assign o_capture0_enqueue_fire=capture_source_valid && capture_source_ready;
    assign o_capture0_consume_fire=capture_sink_valid && capture_sink_ready;
    assign o_capture1_consume_fire=capture1_sink_valid && capture1_sink_ready;

    wire [127:0] command_source;
    wire [31:0] command_session;
    wire command_source_valid, command_source_ready;
    wire [146:0] command_sink;
    wire command_sink_valid, command_sink_ready;
    wire command_sink_reset_done;
    control_message_fifo_ip u_command_fifo (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_user_clk), .i_source_rst_n(user_stream_rst_n),
        .i_source_data({12'd0,(MASK_EXPORT_ENABLE!=0 && command_source[102]),command_session,command_source[101:0]}), .i_source_valid(command_source_valid),
        .o_source_ready(command_source_ready), .o_source_reset_done(),
        .i_sink_clk(i_dfi_clk), .i_sink_rst_n(i_dfi_rst_n),
        .o_sink_data(command_sink), .o_sink_valid(command_sink_valid),
        .i_sink_ready(command_sink_ready), .o_sink_reset_done(command_sink_reset_done)
    );
    wire [146:0] response_source, response_sink;
    wire response_source_valid, response_source_ready, response_sink_valid, response_sink_ready;
    control_message_fifo_ip u_response_fifo (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk), .i_source_rst_n(i_dfi_rst_n),
        .i_source_data(response_source), .i_source_valid(response_source_valid),
        .o_source_ready(response_source_ready), .o_source_reset_done(),
        .i_sink_clk(i_user_clk), .i_sink_rst_n(user_stream_rst_n),
        .o_sink_data(response_sink), .o_sink_valid(response_sink_valid),
        .i_sink_ready(response_sink_ready), .o_sink_reset_done()
    );
    wire [146:0] block_source, block_sink, replay_source, replay_sink;
    wire block_source_valid, block_source_ready, block_sink_valid, block_sink_ready;
    wire replay_source_valid, replay_source_ready, replay_sink_valid, replay_sink_ready;
    axis_frame_fifo_ip u_block_fifo (
        .i_source_clk(i_dfi_clk), .i_source_rst_n(i_dfi_rst_n),
        .i_source_data(block_source), .i_source_valid(block_source_valid),
        .o_source_ready(block_source_ready), .o_source_reset_done(),
        .i_sink_clk(i_user_clk), .i_sink_rst_n(user_stream_rst_n),
        .o_sink_data(block_sink), .o_sink_valid(block_sink_valid),
        .i_sink_ready(block_sink_ready), .o_sink_reset_done()
    );
    wire [146:0] replay_fifo_sink;
    wire replay_fifo_source_ready,replay_fifo_sink_valid;
    wire shared_source=SHARED_REPLAY_FIFO_ENABLE!=0 && i_shared_replay_source_select;
    wire shared_sink=SHARED_REPLAY_FIFO_ENABLE!=0 && i_shared_replay_sink_select;
    assign replay_source_ready=!shared_source && replay_fifo_source_ready;
    assign s_shared_replay_ready=shared_source && replay_fifo_source_ready;
    assign replay_sink=replay_fifo_sink;
    assign replay_sink_valid=!shared_sink && replay_fifo_sink_valid;
    assign m_shared_replay_data=replay_fifo_sink;
    assign m_shared_replay_valid=shared_sink && replay_fifo_sink_valid;
    axis_frame_fifo_ip u_replay_fifo (
        .i_source_clk(i_dfi_clk), .i_source_rst_n(i_dfi_rst_n),
        .i_source_data(shared_source ? s_shared_replay_data : replay_source),
        .i_source_valid(shared_source ? s_shared_replay_valid : replay_source_valid),
        .o_source_ready(replay_fifo_source_ready), .o_source_reset_done(o_shared_replay_source_reset_done),
        .i_sink_clk(i_pixel_clk), .i_sink_rst_n(i_pixel_rst_n),
        .o_sink_data(replay_fifo_sink), .o_sink_valid(replay_fifo_sink_valid),
        .i_sink_ready(shared_sink ? m_shared_replay_ready : replay_sink_ready),
        .o_sink_reset_done(o_shared_replay_sink_reset_done)
    );
    wire fetch_retire_toggle;
    raw_frame_bar #(.DESCRIPTOR_ENABLE(DESCRIPTOR_ENABLE),.MASK_EXPORT_ENABLE(MASK_EXPORT_ENABLE)) u_bar (
        .i_clk(i_user_clk), .i_rst_n(i_user_rst_n), .i_session_ready(i_dfi_rst_n && i_ddr_ready),
        .i_write_valid(i_bar_write_valid), .i_write_offset(i_bar_write_offset),
        .i_write_data(i_bar_write_data), .i_write_strobes(i_bar_write_strobes),
        .o_write_response(o_bar_write_response),
        .i_read_valid(i_bar_read_valid), .i_read_offset(i_bar_read_offset),
        .o_read_response_valid(o_bar_read_response_valid), .o_read_data(o_bar_read_data),
        .o_read_response(o_bar_read_response),
        .o_command_session(command_session), .o_command_data(command_source), .o_command_valid(command_source_valid),
        .i_command_ready(command_source_ready),
        .i_response_data(response_sink[127:0]), .i_response_kind(response_sink[146:145]),
        .i_response_valid(response_sink_valid), .o_response_ready(response_sink_ready),
        .i_block_data(block_sink[127:0]), .i_block_keep(block_sink[143:128]),
        .i_block_last(block_sink[144]), .i_block_error(block_sink[146:145] == 3),
        .i_block_valid(block_sink_valid), .o_block_ready(block_sink_ready),
        .o_retire_toggle(fetch_retire_toggle)
    );

    wire req_valid, req_ready, rsp_valid, rsp_ready;
    wire select_private;
    wire [2:0] req_operation;
    wire req_camera, rsp_camera, rsp_pinned;
    wire [1:0] req_slot, rsp_slot;
    wire [31:0] req_generation, req_offset, req_length;
    wire [3:0] rsp_code;
    wire [31:0] rsp_generation, rsp_sequence, rsp_epoch, rsp_samples, rsp_bytes;
    wire [15:0] rsp_width, rsp_height;
    wire [2:0] rsp_state;
    wire [127:0] read_data;
    wire [15:0] read_keep;
    wire read_last, read_valid, read_ready, read_error, read_complete;
    wire [31:0] capture_count, read_count, drop_count, error_count;
    wire [31:0] req_session, rsp_session;
    wire [7:0] rsp_format;
    wire [383:0] rsp_descriptor;
    wire rsp_metadata_valid;
    raw_frame_store #(.CONTEXT_ENABLE(DESCRIPTOR_ENABLE),
        .CAMERA_COUNT(CAMERA_COUNT),
        .DUAL_CAPTURE_ENABLE(DUAL_CAPTURE_ENABLE),
        .PAIR_METADATA_ENABLE(PAIR_METADATA_ENABLE),.PHYSICAL_MONO_CURRENT_ENABLE(PHYSICAL_MONO_CURRENT_ENABLE),
        .CFS_ENABLE(CFS_ENABLE),
        .OFFICIAL_CRC_QUALIFIED(OFFICIAL_CRC_QUALIFIED)) u_store (
        .i_clk(i_dfi_clk), .i_rst_n(i_dfi_rst_n),
        .i_cfs_enable(i_cfs_enable),.i_physical_mono_current_enable(i_physical_mono_current_enable),
        .o_cfs_compressed_count(o_cfs_compressed_count),
        .o_cfs_no_benefit_count(o_cfs_no_benefit_count),.o_cfs_overflow_count(o_cfs_overflow_count),
        .o_cfs_busy_count(o_cfs_busy_count),.o_cfs_protocol_fault(o_cfs_protocol_fault),
        .i_tdata(capture_sink[127:0]), .i_tkeep(capture_sink[143:128]),
        .i_tlast(capture_sink[144]), .i_tuser(capture_sink[146:145]),
        .i_tvalid(capture_sink_valid), .o_tready(capture_sink_ready),
        .i_tavailable(capture_available),
        .i_t1data(capture1_sink[127:0]), .i_t1keep(capture1_sink[143:128]),
        .i_t1last(capture1_sink[144]), .i_t1user(capture1_sink[146:145]),
        .i_t1valid(capture1_sink_valid), .o_t1ready(capture1_sink_ready),
        .i_t1available(capture1_available),
        .o_commit_valid(o_commit_valid), .o_commit_frame(o_commit_frame),
        .o_commit_lease(o_commit_lease), .i_commit_ready(i_commit_ready),
        .i_ref_valid(i_ref_valid), .o_ref_ready(o_ref_ready),
        .i_ref_op(i_ref_op), .i_ref_mask(i_ref_mask),
        .i_ref_frame0(i_ref_frame0), .i_ref_frame1(i_ref_frame1),
        .i_ref_lease0(i_ref_lease0), .i_ref_lease1(i_ref_lease1), .i_ref_job_id(i_ref_job_id),
        .o_reference_fault(o_reference_fault),
        .i_req_valid(req_valid), .o_req_ready(req_ready), .i_req_op(req_operation),
        .i_req_camera(req_camera), .i_req_slot(req_slot),
        .i_req_session(req_session), .i_req_generation(req_generation), .i_req_offset(req_offset), .i_req_length(req_length),
        .i_req_private(select_private),
        .i_req_lease(select_private ? i_private_req_lease : 64'd0),
        .i_req_job_id(select_private ? i_private_req_job_id : 64'd0),
        .o_rsp_valid(rsp_valid), .i_rsp_ready(rsp_ready), .o_rsp_code(rsp_code),
        .o_rsp_camera(rsp_camera), .o_rsp_slot(rsp_slot), .o_rsp_generation(rsp_generation),
        .o_rsp_session(rsp_session), .o_rsp_format(rsp_format), .o_rsp_sequence(rsp_sequence), .o_rsp_epoch(rsp_epoch),
        .o_rsp_width(rsp_width), .o_rsp_height(rsp_height),
        .o_rsp_sample_count(rsp_samples), .o_rsp_payload_bytes(rsp_bytes),
        .o_rsp_pinned(rsp_pinned), .o_rsp_state(rsp_state),
        .o_rsp_descriptor(rsp_descriptor),.o_rsp_metadata_valid(rsp_metadata_valid),
        .o_read_data(read_data), .o_read_keep(read_keep), .o_read_last(read_last),
        .o_read_valid(read_valid), .i_read_ready(read_ready),
        .o_read_error(read_error), .o_read_complete(read_complete),
        .o_capture_count(capture_count), .o_read_count(read_count),
        .o_capture_write_quiescent(o_capture_write_quiescent),
        .o_private_ownership_quiescent(o_private_ownership_quiescent),
        .o_drop_count(drop_count), .o_error_count(error_count),
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

    reg [2:0] active_operation;
    reg active_private, private_priority;
    reg [383:0] private_descriptor;
    reg [63:0] private_job_id, private_pair_id;
    reg private_member_index;
    reg read_host_context,host_metadata_valid;
    reg [2:0] private_header_count;
    reg read_pending, retire_pending, read_fault, replay_header_pending, read_end_sent;
    reg [31:0] read_generation, read_session;
    reg read_camera;
    reg [1:0] read_slot;
    reg [15:0] read_width, read_height;
    reg [1:0] fetch_ack_sync, replay_ack_sync, replay_error_sync;
    reg fetch_ack_previous, replay_ack_previous;
    reg [1:0] response_index;
    reg response_busy, response_retire;
    reg mask_owner;
    reg mask_command_pending;
    reg [127:0] response_words0, response_words1, response_words2, response_context;
    reg replay_retire_toggle, replay_completion_error;
    assign o_read_quiescent = !read_pending && !retire_pending && !response_busy && !mask_owner;
    // Describe the admitted public range only. HDR's own private FETCH must
    // not be diagnosed as a public intrusion; genuine public RETIRE drains.
    assign o_public_read_quiescent=!(read_pending && !active_private) &&
        !(retire_pending && !active_private) && !(response_busy && !active_private) && !mask_owner;
    wire idle_request = !read_pending && !response_busy && !retire_pending && !mask_owner;
    wire command_mask = MASK_EXPORT_ENABLE!=0 && command_sink[134];
    wire public_request_allowed=CANONICAL_PRIVATE_FETCH_ENABLE==0 ||
        i_public_read_admission_enable || command_sink[2:0]<3;
    wire private_retire = PRIVATE_REPLAY_ENABLE && active_private && read_pending &&
                          !response_busy && i_private_req_op == 5;
    assign select_private = PRIVATE_REPLAY_ENABLE && !retire_pending &&
        i_private_req_valid && (private_retire ||
        (idle_request && (!command_sink_valid || !public_request_allowed || private_priority)));
    assign req_valid = retire_pending || select_private ||
        (command_sink_valid && !command_mask && idle_request && public_request_allowed);
    assign req_operation = retire_pending ? 3'd5 :
                           select_private ? i_private_req_op : command_sink[2:0];
    assign req_camera = retire_pending ? read_camera :
                        select_private ? i_private_req_camera : command_sink[3];
    assign req_slot = retire_pending ? read_slot :
                      select_private ? i_private_req_slot : command_sink[5:4];
    assign req_generation = retire_pending ? read_generation :
                            select_private ? i_private_req_generation : command_sink[37:6];
    assign req_session = retire_pending ? read_session :
                         select_private ? i_private_req_session : command_sink[133:102];
    assign req_offset = retire_pending ? 32'd0 : select_private ?
        (CANONICAL_PRIVATE_FETCH_ENABLE!=0 ? i_private_req_offset : 32'd0) : command_sink[69:38];
    assign req_length = retire_pending ? 32'd0 : select_private ?
        (CANONICAL_PRIVATE_FETCH_ENABLE!=0 ? i_private_req_length : 32'd0) : command_sink[101:70];
    wire mask_candidate=command_mask && command_sink_valid && idle_request &&
        !select_private && public_request_allowed && req_ready && command_sink_reset_done;
    assign command_sink_ready = mask_command_pending ? (command_sink_reset_done && i_mask_command_ready) :
        idle_request && !select_private && public_request_allowed && req_ready &&
        !command_mask;
    assign o_mask_command_data=MASK_EXPORT_ENABLE!=0 ? command_sink[133:0] : 134'd0;
    assign o_mask_command_valid=mask_command_pending && command_sink_reset_done;
    assign o_mask_response_ready=mask_owner && !mask_command_pending && response_source_ready;
    assign o_mask_block_ready=mask_owner && !mask_command_pending && block_source_ready;
    assign o_mask_cache_retire=mask_owner && fetch_ack_sync[1]!=fetch_ack_previous;
    assign o_private_req_ready = select_private && req_ready;
    assign rsp_ready = !mask_owner && (active_private ? i_private_rsp_ready : !response_busy);
    assign o_private_rsp_valid = PRIVATE_REPLAY_ENABLE && active_private && rsp_valid;
    assign o_private_rsp_code = rsp_code;
    assign o_private_rsp_camera = rsp_camera;
    assign o_private_rsp_slot = rsp_slot;
    assign o_private_rsp_generation = rsp_generation;
    assign o_private_rsp_session = rsp_session;
    assign o_private_rsp_sequence = rsp_sequence;
    assign o_private_rsp_epoch = rsp_epoch;
    assign o_private_rsp_descriptor=CANONICAL_PRIVATE_FETCH_ENABLE!=0 ? rsp_descriptor : 384'd0;
    assign o_private_rsp_metadata_valid=CANONICAL_PRIVATE_FETCH_ENABLE!=0 && rsp_metadata_valid;
    wire private_canonical_fetch=CANONICAL_PRIVATE_FETCH_ENABLE!=0 &&
        read_pending && active_private && active_operation==3;
    assign o_private_read_data=CANONICAL_PRIVATE_FETCH_ENABLE!=0 ? read_data : 128'd0;
    assign o_private_read_keep=CANONICAL_PRIVATE_FETCH_ENABLE!=0 ? read_keep : 16'd0;
    assign o_private_read_valid=private_canonical_fetch && read_valid;
    assign o_private_read_last=CANONICAL_PRIVATE_FETCH_ENABLE!=0 && read_last;
    assign o_private_read_complete=private_canonical_fetch && read_complete;
    assign o_private_read_error=private_canonical_fetch && (read_error || read_fault);
    assign o_private_read_protocol_fault=CANONICAL_PRIVATE_FETCH_ENABLE!=0 &&
        (o_reference_fault || o_cfs_protocol_fault);
    assign response_source_valid = mask_owner ? (!mask_command_pending && i_mask_response_valid) : response_busy;
    wire [1:0] response_kind = response_retire ? 2'd3 :
        DESCRIPTOR_ENABLE && response_index == 2 ? 2'd1 :
        response_index == 3 ? 2'd2 : response_index;
    wire [127:0] response_word = response_index == 0 ? response_words0 :
                                 response_index == 1 ? response_words1 :
                                 DESCRIPTOR_ENABLE && response_index == 2 ? response_context : response_words2;
    assign response_source = mask_owner ? i_mask_response_data :
        {response_kind,(response_retire || response_index == (DESCRIPTOR_ENABLE ? 3 : 2)),16'hffff,response_word};

    wire error_end = read_pending && read_error && read_complete && !read_valid && !read_end_sent;
    assign block_source = mask_owner ? i_mask_block_data : {error_end ? 2'd3 : 2'd0,
                           error_end || read_last, error_end ? 16'd0 : read_keep,
                           error_end ? 128'd0 : read_data};
    assign block_source_valid = mask_owner ? (!mask_command_pending && i_mask_block_valid) :
        read_pending && active_operation == 3 && !private_canonical_fetch && (read_valid || error_end);
    // Reuse the resident descriptor/serializer for host context. Host AUX is
    // validity only; private job/pair capabilities never enter a host header.
    wire [127:0] private_header_word = private_header_count == 4 ? private_descriptor[127:0] :
        private_header_count == 3 ? private_descriptor[255:128] :
        private_header_count == 2 ? private_descriptor[383:256] :
        read_host_context ? {127'd0,host_metadata_valid} : {private_pair_id,private_job_id};
    assign replay_source = replay_header_pending ?
                           {2'd1,1'b0,16'hffff,93'd0,read_host_context,
                            (active_private && private_member_index),active_private,read_height,read_width} :
                           private_header_count != 0 ? {2'd2,1'b0,16'hffff,private_header_word} :
                           {error_end ? 2'd3 : 2'd0,
                            error_end || read_last,error_end ? 16'd0 : read_keep,
                            error_end ? 128'd0 : read_data};
    assign replay_source_valid = replay_header_pending || private_header_count != 0 ||
                                 (read_pending && active_operation == 4 && (read_valid || error_end));
    assign read_ready = private_canonical_fetch ? i_private_read_ready : read_pending && (active_operation == 4 ?
                         (!replay_header_pending && private_header_count == 0 && replay_source_ready) : (!mask_owner && block_source_ready));

    // Response data is frozen before crossing; retire acknowledges the destination, not DDR alone.
    always @(posedge i_dfi_clk or negedge i_dfi_rst_n) begin
        if (!i_dfi_rst_n) begin
            active_operation <= 0; read_pending <= 0; retire_pending <= 0;
            active_private <= 0; private_priority <= 0;
            private_descriptor <= 0; private_job_id <= 0; private_pair_id <= 0;
            private_member_index <= 0; private_header_count <= 0;
            read_host_context<=0;host_metadata_valid<=0;
            read_fault <= 0; replay_header_pending <= 0; read_end_sent <= 0;
            read_session <= 0; read_generation <= 0; read_camera <= 0; read_slot <= 0; read_width <= 0; read_height <= 0;
            fetch_ack_sync <= 0; replay_ack_sync <= 0; replay_error_sync <= 0;
            fetch_ack_previous <= 0; replay_ack_previous <= 0;
            response_index <= 0; response_busy <= 0; response_retire <= 0;
            mask_owner <= 0;
            mask_command_pending <= 0;
            response_words0 <= 0; response_words1 <= 0; response_words2 <= 0; response_context <= 0;
        end else begin
            if(mask_candidate) begin
                mask_owner<=1;
                mask_command_pending<=1;
                private_priority<=1;
            end
            if(mask_command_pending && i_mask_command_ready) mask_command_pending<=0;
            // A common FIFO/cache/leaf control reset cancels a command which
            // the leaf never accepted. Accepted physical owners still drain.
            if(mask_command_pending && !command_sink_reset_done) begin
                mask_command_pending<=0;
                mask_owner<=0;
            end
            // The selected target must prove the actual final FIFO handshake.
            // Neither cache TLAST nor an unselected completion releases it.
            if(mask_owner && !mask_command_pending && i_mask_owner_complete && i_mask_response_valid &&
                o_mask_response_ready && i_mask_response_data[144] &&
                (i_mask_response_data[146:145]==2 || i_mask_response_data[146:145]==3)) mask_owner<=0;
            fetch_ack_sync <= {fetch_ack_sync[0],fetch_retire_toggle};
            replay_ack_sync <= {replay_ack_sync[0],replay_retire_toggle};
            replay_error_sync <= {replay_error_sync[0],replay_completion_error};
            fetch_ack_previous <= fetch_ack_sync[1];
            replay_ack_previous <= replay_ack_sync[1];
            if (read_pending && read_error) read_fault <= 1;
            if (read_pending && !active_private && ((active_operation == 3 && fetch_ack_sync[1] != fetch_ack_previous) ||
                                 (active_operation == 4 && replay_ack_sync[1] != replay_ack_previous))) begin
                retire_pending <= 1;
                if (active_operation == 4 && replay_error_sync[1]) read_fault <= 1;
            end
            if (req_valid && req_ready) begin
                active_operation <= req_operation;
                active_private <= select_private;
                if (!retire_pending && !private_retire) private_priority <= !select_private;
                if (select_private && req_operation == 4) begin
                    private_descriptor <= i_private_descriptor;
                    private_job_id <= i_private_req_job_id; private_pair_id <= i_private_pair_id;
                    private_member_index <= i_private_member_index;
                end
                if (retire_pending) retire_pending <= 0;
                else if (req_operation == 3 || req_operation == 4) begin
                    read_pending <= 1; read_fault <= 0; read_end_sent <= 0;
                end
            end
            if (rsp_valid && rsp_ready) begin
                response_busy <= !active_private; response_index <= 0;
                response_retire <= active_operation == 5;
                response_words0 <= active_operation == 5 ?
                                   {124'd0,(read_fault || read_error ? 4'd5 : rsp_code)} :
                                   {rsp_bytes,rsp_generation,rsp_epoch,rsp_sequence};
                response_words1 <= {53'd0,rsp_code,rsp_pinned,rsp_state,rsp_camera,rsp_slot,
                                    rsp_samples,rsp_height,rsp_width};
                response_words2 <= {error_count,drop_count,read_count,capture_count};
                response_context <= {1'b1,87'd0,rsp_format,rsp_session};
                if (active_operation == 5) read_pending <= 0;
                else if ((active_operation == 3 || active_operation == 4) && rsp_code == 0) begin
                    read_session <= rsp_session; read_generation <= rsp_generation; read_camera <= rsp_camera; read_slot <= rsp_slot;
                    read_width <= rsp_width; read_height <= rsp_height;
                    if (active_operation == 4) begin
                        replay_header_pending <= 1;
                        read_host_context<=HOST_REPLAY_CONTEXT_ENABLE && !active_private;
                        if (active_private) private_header_count <= 4;
                        else if(HOST_REPLAY_CONTEXT_ENABLE) begin
                            private_descriptor<=rsp_descriptor;host_metadata_valid<=rsp_metadata_valid;
                            private_job_id<=0;private_pair_id<=0;private_member_index<=0;
                            private_header_count<=4;
                        end
                    end
                end else if (rsp_code != 0) read_pending <= 0;
            end
            if (!mask_owner && response_source_valid && response_source_ready) begin
                if (response_retire || response_index == (DESCRIPTOR_ENABLE ? 3 : 2)) response_busy <= 0;
                else response_index <= response_index + 1'b1;
            end
            if (replay_header_pending && replay_source_ready) replay_header_pending <= 0;
            else if (private_header_count != 0 && replay_source_ready)
                private_header_count <= private_header_count - 1'b1;
            if ((read_valid && read_ready && read_last) ||
                (error_end && (active_operation == 4 ? replay_source_ready : block_source_ready)))
                read_end_sent <= 1;
        end
    end

    generate if (PRIVATE_REPLAY_ENABLE != 0) begin : g_private_boundary
        wire done_valid, done_ready, done_error;
        wire [146:0] done_source, done_sink;
        wire done_sink_valid, done_source_ready;
        raw_replay_context_boundary #(.HOST_REPLAY_CONTEXT_ENABLE(HOST_REPLAY_CONTEXT_ENABLE)) u_boundary (
            .clk(i_pixel_clk), .rst_n(i_pixel_rst_n), .i_safe(i_replay_safe),
            .s_data(replay_sink), .s_valid(replay_sink_valid), .s_ready(replay_sink_ready),
            .o_active(o_replay_active), .o_data(o_replay_data), .o_valid(o_replay_valid),
            .i_ready(i_replay_ready), .o_sof(o_replay_sof), .o_eol(o_replay_eol),
            .o_abort(o_replay_abort), .o_context_valid(o_replay_context_valid),
            .i_context_ready(i_replay_context_ready), .o_descriptor(o_replay_descriptor),
            .o_job_id(o_replay_job_id), .o_pair_id(o_replay_pair_id),
            .o_member_index(o_replay_member_index), .o_private(o_replay_private),
            .o_host_replay_context_valid(o_host_replay_context_valid),
            .i_host_replay_context_ready(i_host_replay_context_ready),
            .o_host_replay_descriptor(o_host_replay_descriptor),
            .o_host_replay_metadata_valid(o_host_replay_metadata_valid),
            .o_done_valid(done_valid), .i_done_ready(done_ready),
            .o_done_error(done_error), .o_protocol_fault(o_replay_protocol_fault)
        );
        assign done_source = {81'd0,done_error,o_replay_member_index,o_replay_job_id};
        assign done_ready = o_replay_private ? done_source_ready : 1'b1;
        assign o_replay_native_done=done_valid && done_ready && o_replay_private;
        assign o_replay_native_error=done_error;
        control_message_fifo_ip u_native_done_fifo (
            .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
            .i_source_clk(i_pixel_clk), .i_source_rst_n(i_pixel_rst_n),
            .i_source_data(done_source), .i_source_valid(done_valid && o_replay_private),
            .o_source_ready(done_source_ready), .o_source_reset_done(),
            .i_sink_clk(i_dfi_clk), .i_sink_rst_n(i_dfi_rst_n),
            .o_sink_data(done_sink), .o_sink_valid(done_sink_valid),
            .i_sink_ready(1'b1), .o_sink_reset_done()
        );
        assign o_private_native_done = done_sink_valid;
        assign o_private_native_job_id = done_sink[63:0];
        assign o_private_native_member_index = done_sink[64];
        assign o_private_native_error = done_sink[65];
        always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
            if (!i_pixel_rst_n) begin replay_retire_toggle<=0; replay_completion_error<=0; end
            else if (done_valid && done_ready && !o_replay_private) begin
                replay_retire_toggle<=!replay_retire_toggle;
                replay_completion_error<=done_error;
            end
        end
    end else if(HOST_REPLAY_CONTEXT_ENABLE!=0) begin : g_host_context_boundary
        wire done_valid,done_error;
        raw_replay_context_boundary #(.HOST_REPLAY_CONTEXT_ENABLE(1)) u_boundary (
            .clk(i_pixel_clk),.rst_n(i_pixel_rst_n),.i_safe(i_replay_safe),
            .s_data(replay_sink),.s_valid(replay_sink_valid),.s_ready(replay_sink_ready),
            .o_active(o_replay_active),.o_data(o_replay_data),.o_valid(o_replay_valid),.i_ready(i_replay_ready),
            .o_sof(o_replay_sof),.o_eol(o_replay_eol),.o_abort(o_replay_abort),
            .o_context_valid(),.i_context_ready(1'b0),.o_descriptor(),.o_job_id(),.o_pair_id(),
            .o_member_index(),.o_private(),.o_done_valid(done_valid),.i_done_ready(1'b1),.o_done_error(done_error),
            .o_protocol_fault(o_replay_protocol_fault),.o_host_replay_context_valid(o_host_replay_context_valid),
            .i_host_replay_context_ready(i_host_replay_context_ready),.o_host_replay_descriptor(o_host_replay_descriptor),
            .o_host_replay_metadata_valid(o_host_replay_metadata_valid));
        assign o_replay_context_valid=0;assign o_replay_descriptor=0;
        assign o_replay_job_id=0;assign o_replay_pair_id=0;assign o_replay_member_index=0;assign o_replay_private=0;
        assign o_private_native_done=0;assign o_private_native_job_id=0;assign o_private_native_member_index=0;
        assign o_private_native_error=0;assign o_replay_native_done=0;assign o_replay_native_error=0;
        always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
            if(!i_pixel_rst_n) begin replay_retire_toggle<=0;replay_completion_error<=0;end
            else if(done_valid) begin replay_retire_toggle<=!replay_retire_toggle;replay_completion_error<=done_error;end
        end
    end else begin : g_host_boundary
    reg replay_active_legacy;
    assign o_replay_active = replay_active_legacy;
    assign o_replay_context_valid = 1'b0;
    assign o_replay_descriptor = 384'd0;
    assign o_replay_job_id = 64'd0;
    assign o_replay_pair_id = 64'd0;
    assign o_replay_member_index = 1'b0;
    assign o_replay_private = 1'b0;
    assign o_replay_protocol_fault = 1'b0;
    assign o_private_native_done = 1'b0;
    assign o_private_native_job_id = 64'd0;
    assign o_private_native_member_index = 1'b0;
    assign o_private_native_error = 1'b0;
    assign o_replay_native_done=1'b0;
    assign o_replay_native_error=1'b0;
    assign o_host_replay_context_valid=1'b0;assign o_host_replay_descriptor=384'd0;
    assign o_host_replay_metadata_valid=1'b0;
    wire replay_start = replay_sink_valid && replay_sink[146:145] == 1 &&
                        !o_replay_active && i_replay_safe;
    wire replay_axis_ready, replay_done, replay_abort;
    reg replay_failed, replay_last_seen;
    assign replay_sink_ready = replay_sink[146:145] == 1 ?
                               (!o_replay_active && i_replay_safe) :
                               (replay_failed || !o_replay_active ? 1'b1 : replay_axis_ready);
    raw10_frame_replay u_replay (
        .i_clk(i_pixel_clk), .i_rst_n(i_pixel_rst_n), .i_start(replay_start),
        .i_width(replay_sink[15:0]), .i_height(replay_sink[31:16]),
        .i_axis_tdata(replay_sink[127:0]), .i_axis_tkeep(replay_sink[143:128]),
        .i_axis_tvalid(replay_sink_valid && o_replay_active && !replay_failed &&
                       replay_sink[146:145] != 1),
        .i_axis_tlast(replay_sink[144]), .o_axis_tready(replay_axis_ready),
        .o_data(o_replay_data), .o_valid(o_replay_valid), .i_ready(i_replay_ready),
        .o_sof(o_replay_sof), .o_eol(o_replay_eol), .o_abort(replay_abort), .o_done(replay_done)
    );
    assign o_replay_abort = replay_abort;
    always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
        if (!i_pixel_rst_n) begin
            replay_active_legacy <= 0; replay_failed <= 0; replay_last_seen <= 0;
            replay_retire_toggle <= 0; replay_completion_error <= 0;
        end else begin
            if (replay_start) begin
                replay_active_legacy <= 1; replay_failed <= 0; replay_last_seen <= 0;
                replay_completion_error <= 0;
            end
            if (replay_sink_valid && replay_sink_ready && replay_sink[146:145] != 1 && replay_sink[144])
                replay_last_seen <= 1;
            if (replay_abort) begin replay_failed <= 1; replay_completion_error <= 1; end
            if (replay_done ||
                ((replay_failed || replay_abort) &&
                 (replay_last_seen || (replay_sink_valid && replay_sink_ready && replay_sink[144])))) begin
                replay_active_legacy <= 0; replay_failed <= 0; replay_last_seen <= 0;
                replay_retire_toggle <= !replay_retire_toggle;
            end
        end
    end
    end endgenerate
endmodule
