`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// S04 domain boundary: all bulk and command crossings use configured TD FIFOs.
module hdr_raw_capture_store #(
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
    input wire i_identity_rst_n,i_pair_stop,i_pair_fault,
    input wire i_pair_config_valid,output wire o_pair_config_ready,o_pair_config_error,
    input wire [31:0] i_pair_session,i_pair_epoch,i_pair_max_wait,i_pair_max_age,
    input wire [63:0] i_pair_max_delta,input wire [2:0] i_pair_ratio,
    input wire i_pair_hdr_enable,
    output wire o_pair_valid,o_pair_bank,input wire i_pair_ready,
    output wire [63:0] o_pair_id,
    input wire i_pair_release_valid,i_pair_release_bank,
    input wire [63:0] i_pair_release_id,
    input wire i_pair_read_quiet,i_pair_product_quiet,i_pair_ticket_released,
    output wire o_pair_release_ready,
    input wire i_pair_directory_valid,input wire [1:0] i_pair_directory_slot,
    output wire o_pair_directory_ready,
    output wire [31:0] m_pair_directory_data,output wire [3:0] m_pair_directory_word,
    output wire m_pair_directory_valid,m_pair_directory_last,input wire m_pair_directory_ready,
    input wire [63:0] i_pair_now,
    input wire i_capture_enable,
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

    // CFS, MASK, public RAW and stored-MONO are absent in this application
    // profile. A separate generic raw_frame_service remains in the repository.
    generate if(CAMERA_COUNT!=1||DUAL_CAPTURE_ENABLE!=0||CFS_ENABLE!=0||
        MASK_EXPORT_ENABLE!=0||PHYSICAL_MONO_CURRENT_ENABLE!=0||
        CANONICAL_PRIVATE_FETCH_ENABLE!=1||SHARED_REPLAY_FIFO_ENABLE!=1||
        DESCRIPTOR_ENABLE!=1||PAIR_METADATA_ENABLE!=1)begin:g_bad_profile
        HDR_STORE_REQUIRES_SINGLE_QUALIFIED_CANONICAL_PROFILE invalid_profile();
    end endgenerate
    wire [146:0] capture_source, capture_sink;
    wire [9:0] capture_available, capture1_available;
    wire [146:0] capture1_sink;
    wire capture1_sink_valid, capture1_sink_ready;
    wire capture_source_valid, capture_source_ready, capture_sink_valid, capture_sink_ready;
    raw10_frame_ingress #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
        .CONTEXT_ENABLE(DESCRIPTOR_ENABLE),.EXTERNAL_SEQUENCE_ENABLE(DESCRIPTOR_ENABLE),
        .PAIR_METADATA_ENABLE(PAIR_METADATA_ENABLE),.SOURCE_TERMINAL_ENABLE(SOURCE_TERMINAL_ENABLE)) u_ingress (
        .i_clk(i_pixel_clk), .i_rst_n(i_pixel_rst_n), .i_enable(i_capture_enable),
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
            .i_clk(i_capture1_clk), .i_rst_n(i_capture1_rst_n), .i_enable(i_capture_enable),
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

    wire [383:0] pair_capture_frame;
    wire pair_begin_valid,pair_begin_ready,pair_begin_accepted;
    wire [1:0] pair_capture_slot;
    wire [31:0] pair_capture_generation;
    wire [63:0] pair_capture_lease;
    wire pair_finish_valid,pair_finish_ok,pair_finish_ready;
    wire pair_writer_fault,pair_owner_fault;
    wire pair_cfg_ready,pair_cfg_error;
    wire bad_delta=|i_pair_max_delta[63:32];
    assign o_pair_config_ready=bad_delta || pair_cfg_ready;
    assign o_pair_config_error=pair_cfg_error || bad_delta;
    hdr_pair_capture_writer #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_writer(
        .i_clk(i_dfi_clk),.i_identity_rst_n(i_identity_rst_n),.i_stop(i_pair_stop),
        .s_data(capture_sink[127:0]),.s_keep(capture_sink[143:128]),
        .s_user(capture_sink[146:145]),.s_valid(capture_sink_valid),.s_last(capture_sink[144]),
        .i_available(capture_available),.s_ready(capture_sink_ready),
        .o_frame(pair_capture_frame),.o_begin_valid(pair_begin_valid),
        .i_begin_ready(pair_begin_ready),.i_begin_accepted(pair_begin_accepted),.i_capture_slot(pair_capture_slot),
        .o_finish_valid(pair_finish_valid),.o_finish_ok(pair_finish_ok),.i_finish_ready(pair_finish_ready),
        .o_quiet(o_capture_write_quiescent),.o_protocol_fault(pair_writer_fault),.o_success_count(),.o_error_count(),
        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready));
    hdr_pair_bank_owner #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.CAMERA_COUNT(CAMERA_COUNT)) u_pair_owner(
        .i_clk(i_dfi_clk),.i_identity_rst_n(i_identity_rst_n),.i_stop(i_pair_stop),
        .i_transport_fault(i_pair_fault || pair_writer_fault),.i_now(i_pair_now),
        .i_config_valid(i_pair_config_valid && !bad_delta),.o_config_ready(pair_cfg_ready),
        .i_session(i_pair_session),.i_epoch(i_pair_epoch),.i_max_delta(i_pair_max_delta[31:0]),
        .i_max_wait(i_pair_max_wait),.i_max_age(i_pair_max_age),.i_ratio_log2(i_pair_ratio),
        .i_hdr_enable(i_pair_hdr_enable),.o_config_error(pair_cfg_error),
        .s_frame(pair_capture_frame),.s_begin_valid(pair_begin_valid),.s_begin_ready(pair_begin_ready),
        .o_begin_accepted(pair_begin_accepted),.o_capture_slot(pair_capture_slot),
        .o_capture_generation(pair_capture_generation),.o_capture_lease(pair_capture_lease),
        .i_finish_valid(pair_finish_valid),.i_finish_ok(pair_finish_ok),.o_finish_ready(pair_finish_ready),
        .o_pair_valid(o_pair_valid),.i_pair_ready(i_pair_ready),.o_pair_bank(o_pair_bank),.o_pair_id(o_pair_id),
        .i_release_valid(i_pair_release_valid),.i_release_bank(i_pair_release_bank),.i_release_pair_id(i_pair_release_id),
        .i_read_quiet(i_pair_read_quiet),.i_write_quiet(o_capture_write_quiescent && i_pair_product_quiet),
        .i_ticket_released(i_pair_ticket_released),.o_release_ready(o_pair_release_ready),
        .i_directory_read_valid(i_pair_directory_valid),.i_directory_read_slot(i_pair_directory_slot),
        .o_directory_read_ready(o_pair_directory_ready),.m_directory_data(m_pair_directory_data),
        .m_directory_word(m_pair_directory_word),.m_directory_valid(m_pair_directory_valid),
        .m_directory_last(m_pair_directory_last),.m_directory_ready(m_pair_directory_ready),
        .o_empty(o_private_ownership_quiescent),.o_capture_busy(),.o_exhausted(),.o_fault(pair_owner_fault),
        .o_bank_states(),.o_reject_count(),.o_expire_count());
    assign o_reference_fault=pair_owner_fault;
    // Diagnostic observations only; no legacy COMMIT/REF command may mutate
    // the deterministic owner. Production authority stays in u_pair_owner.
    assign o_commit_valid=pair_finish_valid && pair_finish_ready && pair_finish_ok;
    assign o_commit_frame={pair_capture_frame[383:45],pair_capture_generation,
        6'd0,pair_capture_slot,pair_capture_frame[4:0]};
    assign o_commit_lease=pair_capture_lease;
    assign o_ref_ready=0;
    assign o_cfs_compressed_count=0;assign o_cfs_no_benefit_count=0;
    assign o_cfs_overflow_count=0;assign o_cfs_busy_count=0;assign o_cfs_protocol_fault=0;
    assign capture1_sink_ready=0;
    assign o_private_req_ready=0;assign o_private_rsp_valid=0;
    assign o_private_rsp_code=4'd6;assign o_private_rsp_camera=0;assign o_private_rsp_slot=0;
    assign o_private_rsp_generation=0;assign o_private_rsp_session=0;assign o_private_rsp_sequence=0;
    assign o_private_rsp_epoch=0;assign o_private_rsp_descriptor=0;assign o_private_rsp_metadata_valid=0;
    assign o_private_read_data=0;assign o_private_read_keep=0;assign o_private_read_valid=0;
    assign o_private_read_last=0;assign o_private_read_complete=0;assign o_private_read_error=0;
    assign o_private_read_protocol_fault=pair_owner_fault;
    assign o_read_quiescent=i_pair_read_quiet;
    assign o_public_read_quiescent=1;
    // The new read cursor directly owns the original RAW AXI read wires in
    // MAIN. These former wrapper outputs are intentionally left unconnected.
    assign m_axi_arid=0;assign m_axi_araddr=0;assign m_axi_arlen=0;
    assign m_axi_arsize=0;assign m_axi_arburst=0;assign m_axi_arvalid=0;assign m_axi_rready=0;

    // The sole DFI->PIX payload FIFO remains official and phase-owned. Its
    // entries are never consumed by a public or ordinary RAW10 replay path.
    wire [146:0] replay_sink;
    wire replay_valid,replay_ready;
    axis_frame_fifo_ip u_replay_fifo(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(i_dfi_rst_n),
        .i_source_data(s_shared_replay_data),.i_source_valid(s_shared_replay_valid&&i_shared_replay_source_select),
        .o_source_ready(replay_ready),.o_source_reset_done(o_shared_replay_source_reset_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(i_pixel_rst_n),
        .o_sink_data(replay_sink),.o_sink_valid(replay_valid),
        .i_sink_ready(m_shared_replay_ready&&i_shared_replay_sink_select),
        .o_sink_reset_done(o_shared_replay_sink_reset_done));
    assign s_shared_replay_ready=replay_ready&&i_shared_replay_source_select;
    assign m_shared_replay_data=replay_sink;
    assign m_shared_replay_valid=replay_valid&&i_shared_replay_sink_select;
    // Public RAW register access has a deterministic negative response. The
    // general profile provides this capability; no silent success is returned.
    reg bar_read_pending;
    always @(posedge i_user_clk or negedge i_user_rst_n)begin
        if(!i_user_rst_n)bar_read_pending<=0;else bar_read_pending<=i_bar_read_valid;
    end
    assign o_bar_write_response=2'b10;assign o_bar_read_response=2'b10;
    assign o_bar_read_response_valid=bar_read_pending;
    assign o_mask_command_data=0;
    assign o_mask_command_valid=0;
    assign o_mask_response_ready=0;
    assign o_mask_block_ready=0;
    assign o_mask_cache_retire=0;
    assign o_private_native_done=0;
    assign o_private_native_error=0;
    assign o_private_native_job_id=0;
    assign o_private_native_member_index=0;
    assign o_replay_context_valid=0;
    assign o_replay_descriptor=0;
    assign o_replay_job_id=0;
    assign o_replay_pair_id=0;
    assign o_replay_member_index=0;
    assign o_replay_private=0;
    assign o_replay_protocol_fault=0;
    assign o_host_replay_context_valid=0;
    assign o_host_replay_descriptor=0;
    assign o_host_replay_metadata_valid=0;
    assign o_replay_native_done=0;
    assign o_replay_native_error=0;
    assign o_replay_active=0;
    assign o_replay_data=0;
    assign o_replay_valid=0;
    assign o_replay_sof=0;
    assign o_replay_eol=0;
    assign o_replay_abort=0;
    assign o_bar_read_data=0;
endmodule
