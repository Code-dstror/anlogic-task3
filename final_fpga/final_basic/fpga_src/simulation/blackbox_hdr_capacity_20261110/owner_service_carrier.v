`timescale 1ns/1ps
`default_nettype none

module owner_service_carrier (
    input wire dfi_clk, pixel_clk, rst_n,
    input wire [63:0] i_now_ns,
    input wire i_cfg_valid,
    output wire o_cfg_ready, o_cfg_done, o_cfg_error, o_policy_admit,

    input wire [159:0] s_raw_data,
    input wire [3:0] s_raw_valid, s_raw_sof, s_raw_eol,
    input wire [127:0] s_raw_sequence,
    input wire [787:0] s_raw_metadata,
    input wire [3:0] s_source_valid,
    input wire [127:0] s_source_sequence,
    output wire [3:0] s_source_ready, o_capture_admit,

    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast, m_axi_wvalid,
    input wire m_axi_wready,
    input wire [3:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,

    output wire o_pair_valid, o_pair_ready, o_pair_bank,
    output wire [63:0] o_pair_id,
    output wire o_job_valid, o_job_ready,
    output wire [63:0] o_job_id, o_job_pair_id, o_job_lease0, o_job_lease1,
    output wire [383:0] o_job_frame,
    output wire o_release_valid, o_release_ready, o_release_bank,
    output wire [63:0] o_release_id,
    output wire o_retire_done,

    output wire o_member_valid, o_member_index,
    input wire i_member_ready,
    output wire o_context_valid, o_start_valid,
    input wire i_context_ready, i_start_ready,
    input wire i_result_valid, i_result_ready, i_result_ok,
    output wire o_result_ready,
    input wire i_processing_done, i_processing_error,
    input wire [63:0] i_processing_job_id,
    input wire i_reader_quiet, i_product_quiet, i_writer_quiet, i_ticket_released,

    output wire [1:0] o_begin_reject, o_pair_expire,
    output wire [3:0] o_bad_finish,
    output wire [7:0] o_bank_states,
    output wire o_capture_write_quiet, o_scheduler_busy, o_quiescent, o_fault
);
    localparam [31:0] SESSION = 32'd11, EPOCH = 32'd1;
    localparam [63:0] MAX_DELTA = 64'd50000000;
    localparam [31:0] MAX_WAIT = 32'd100000000, MAX_AGE = 32'd1000000000;
    wire dfi_rst_n, dfi_data_rst_n, pixel_rst_n;
    reset_release_sync_data #(.DATA_RESET_COPIES(1),.FALLING_RELEASE(1)) u_dfi_reset (
        .i_clk(dfi_clk),.i_async_rst_n(rst_n),.o_rst_n(dfi_rst_n),.o_data_rst_n(dfi_data_rst_n));
    reset_release_sync u_pixel_reset (
        .i_clk(pixel_clk),.i_async_rst_n(rst_n),.o_rst_n(pixel_rst_n));

    wire pair_cfg_valid, pair_cfg_ready, pair_cfg_error;
    wire pair_empty, pair_fault, read_quiet, public_read_quiet;
    wire dir_req, dir_ready, dir_valid, dir_last, dir_take;
    wire [1:0] dir_slot;
    wire [31:0] dir_data;
    wire [3:0] dir_word;
    wire result_enable, job_quiet;

    assign o_result_ready = result_enable && i_result_ready;
    assign o_quiescent = job_quiet && o_capture_write_quiet;

    full_raw_store #(
        .WIDTH(16),.HEIGHT(4),.DESCRIPTOR_ENABLE(1),.DUAL_CAPTURE_ENABLE(1),
        .PAIR_METADATA_ENABLE(1),.CAMERA_COUNT(1),.CANONICAL_PRIVATE_FETCH_ENABLE(1),
        .SHARED_REPLAY_FIFO_ENABLE(1),.PRIVATE_REPLAY_ENABLE(1),.SOURCE_TERMINAL_ENABLE(1),
        .OFFICIAL_CRC_QUALIFIED(1),.STEREO_ENABLE(1),.STEREO_RUNTIME_CADENCE(1),
        .SECOND_HDR_CAMERA(1),.SHARED_DECODE_ENABLE(1),.RAW_EXPORT_ENABLE(1),
        .HDR_SLOT_LOCAL_RETIRE_ENABLE(1),.SEPARATE_DFI_DATA_RESET(1)
    ) u_store (
        .i_identity_rst_n(dfi_rst_n),.i_identity_data_rst_n(dfi_data_rst_n),
        .i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n),.i_ddr_ready(1'b1),
        .i_pixel_clk(pixel_clk),.i_pixel_rst_n(pixel_rst_n),
        .i_capture1_clk(pixel_clk),.i_capture1_rst_n(pixel_rst_n),
        .i_user_clk(dfi_clk),.i_user_rst_n(dfi_rst_n),
        .i_pair_stop(1'b0),.i_pair_fault(1'b0),.i_pair_now(i_now_ns),
        .i_pair_config_valid(pair_cfg_valid),.o_pair_config_ready(pair_cfg_ready),
        .o_pair_config_error(pair_cfg_error),.i_pair_session(SESSION),.i_pair_epoch(EPOCH),
        .i_pair_max_delta(MAX_DELTA),.i_pair_max_wait(MAX_WAIT),.i_pair_max_age(MAX_AGE),
        .i_pair_ratio(3'd4),.i_pair_hdr_enable(1'b1),.o_raw_policy_admit(o_policy_admit),

        .i_capture_enable(1'b1),.i_capture_time_valid(1'b1),.i_bayer_valid(1'b1),.i_isp_bayer_phase(2'd0),
        .i_capture_data(s_raw_data[39:0]),.i_capture_valid(s_raw_valid[0]),.i_capture_accept(1'b1),
        .i_capture_sof(s_raw_sof[0]),.i_capture_eol(s_raw_eol[0]),.i_capture_abort(1'b0),
        .i_capture_epoch(EPOCH),.i_session_id(SESSION),.i_mode_epoch(EPOCH),
        .i_frame_sequence(s_raw_sequence[31:0]),.i_capture_metadata(s_raw_metadata[196:0]),
        .i_capture_source_valid(s_source_valid[0]),.o_capture_source_ready(s_source_ready[0]),
        .i_capture_source_session(SESSION),.i_capture_source_epoch(EPOCH),
        .i_capture_source_sequence(s_source_sequence[31:0]),.i_capture_source_camera(1'b0),
        .i_capture_source_ok(1'b1),.i_capture_source_error(8'd0),.o_capture0_frame_accept(o_capture_admit[0]),

        .i_capture1_data(s_raw_data[79:40]),.i_capture1_valid(s_raw_valid[1]),.i_capture1_accept(1'b1),
        .i_capture1_sof(s_raw_sof[1]),.i_capture1_eol(s_raw_eol[1]),.i_capture1_abort(1'b0),
        .i_capture1_session(SESSION),.i_capture1_epoch(EPOCH),
        .i_capture1_sequence(s_raw_sequence[63:32]),.i_capture1_metadata(s_raw_metadata[393:197]),
        .i_capture1_source_valid(s_source_valid[1]),.o_capture1_source_ready(s_source_ready[1]),
        .i_capture1_source_session(SESSION),.i_capture1_source_epoch(EPOCH),
        .i_capture1_source_sequence(s_source_sequence[63:32]),.i_capture1_source_camera(1'b0),
        .i_capture1_source_ok(1'b1),.i_capture1_source_error(8'd0),.o_capture1_frame_accept(o_capture_admit[1]),

        .i_cam1_hdr_enable(1'b1),.i_cam1_hdr_data(s_raw_data[159:80]),.i_cam1_hdr_valid(s_raw_valid[3:2]),
        .i_cam1_hdr_sof(s_raw_sof[3:2]),.i_cam1_hdr_eol(s_raw_eol[3:2]),.i_cam1_hdr_abort(2'b00),
        .i_cam1_hdr_sequence(s_raw_sequence[127:64]),.i_cam1_hdr_metadata(s_raw_metadata[787:394]),
        .i_cam1_hdr_source_valid(s_source_valid[3:2]),.o_cam1_hdr_source_ready(s_source_ready[3:2]),
        .i_cam1_hdr_source_session({SESSION,SESSION}),.i_cam1_hdr_source_epoch({EPOCH,EPOCH}),
        .i_cam1_hdr_source_sequence(s_source_sequence[127:64]),.i_cam1_hdr_source_ok(2'b11),
        .i_cam1_hdr_source_error(16'd0),.o_cam1_hdr_admit(o_capture_admit[3:2]),

        .o_pair_valid(o_pair_valid),.i_pair_ready(o_pair_ready),.o_pair_bank(o_pair_bank),.o_pair_id(o_pair_id),
        .i_pair_release_valid(o_release_valid),.o_pair_release_ready(o_release_ready),
        .i_pair_release_bank(o_release_bank),.i_pair_release_id(o_release_id),
        .i_pair_read_quiet(i_reader_quiet),.i_pair_product_quiet(i_writer_quiet),
        .i_pair_ticket_released(i_ticket_released),.o_private_ownership_quiescent(pair_empty),
        .i_pair_directory_valid(dir_req),.i_pair_directory_slot(dir_slot),.o_pair_directory_ready(dir_ready),
        .m_pair_directory_data(dir_data),.m_pair_directory_word(dir_word),.m_pair_directory_valid(dir_valid),
        .m_pair_directory_last(dir_last),.m_pair_directory_ready(dir_take),
        .o_reference_fault(pair_fault),.o_read_quiescent(read_quiet),.o_public_read_quiescent(public_read_quiet),
        .o_capture_write_quiescent(o_capture_write_quiet),.o_hdr_begin_reject(o_begin_reject),
        .o_hdr_pair_expire(o_pair_expire),.o_hdr_bad_finish(o_bad_finish),.o_hdr_bank_states(o_bank_states),

        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),.m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),

        // Dormant SDR, host, replay and mask clients in the fixed HDR profile.
        .i_stereo_mode(1'b0),.i_stereo_mode_pixel(1'b0),.i_stereo_frame_divisor_pixel(8'd4),
        .i_stereo_job_ready(1'b0),.i_stereo_retire_valid(1'b0),.i_stereo_retire_job_id(64'd0),
        .i_stereo_processing_done(1'b0),.i_stereo_processing_error(1'b0),.i_stereo_processing_job_id(64'd0),
        .i_raw_export(1'b0),.i_raw_cancel(1'b0),.i_raw_record_ready(1'b0),.i_raw_ready(1'b0),
        .i_raw_retire_valid(1'b0),.i_raw_retire_identity(128'd0),
        .i_decode_start_ready(1'b0),.i_decode_ready(1'b0),.i_decode_raw(40'd0),.i_decode_raw_valid(1'b0),
        .i_decode_sof(1'b0),.i_decode_eol(1'b0),.i_decode_done(1'b0),.i_decode_aborted(1'b0),
        .i_decode_quiet(1'b1),.i_decode_active(1'b0),
        .i_sdr_lz_enable(1'b0),.i_lz_fault(1'b0),.i_lz_region_quiet(1'b1),
        .i_sdr_read_request_valid(1'b0),.i_sdr_read_request_context(448'd0),.i_sdr_read_ready(1'b0),
        .i_sdr_reader_cancel(1'b0),.i_sdr_release_valid(1'b0),.i_sdr_release_context(448'd0),
        .i_sdr_consumer_quiet(1'b1),.i_cfs_enable(1'b0),.i_physical_mono_current_enable(1'b0),
        .s_hdr_axi_arid(4'd0),.s_hdr_axi_araddr(28'd0),.s_hdr_axi_arlen(8'd0),
        .s_hdr_axi_arsize(3'd0),.s_hdr_axi_arburst(2'd0),.s_hdr_axi_arvalid(1'b0),.s_hdr_axi_rready(1'b0),
        .m_axi_arready(1'b0),.m_axi_rid(4'd0),.m_axi_rdata(128'd0),
        .m_axi_rresp(2'd0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),
        .i_commit_ready(1'b1),.i_ref_valid(1'b0),.i_ref_op(2'd0),.i_ref_mask(2'd0),
        .i_ref_frame0(384'd0),.i_ref_frame1(384'd0),.i_ref_lease0(64'd0),.i_ref_lease1(64'd0),.i_ref_job_id(64'd0),
        .i_shared_replay_source_select(1'b0),.i_shared_replay_sink_select(1'b0),
        .s_shared_replay_data(147'd0),.s_shared_replay_valid(1'b0),.m_shared_replay_ready(1'b0),
        .i_private_req_valid(1'b0),.i_private_req_op(3'd0),.i_private_req_camera(1'b0),.i_private_req_slot(2'd0),
        .i_private_req_generation(32'd0),.i_private_req_session(32'd0),.i_private_req_lease(64'd0),
        .i_private_req_job_id(64'd0),.i_private_req_offset(32'd0),.i_private_req_length(32'd0),
        .i_public_read_admission_enable(1'b0),.i_mask_command_ready(1'b0),
        .i_mask_response_data(147'd0),.i_mask_response_valid(1'b0),
        .i_mask_block_data(147'd0),.i_mask_block_valid(1'b0),.i_mask_owner_complete(1'b1),
        .i_private_descriptor(384'd0),.i_private_pair_id(64'd0),.i_private_member_index(1'b0),
        .i_private_rsp_ready(1'b0),.i_private_read_ready(1'b0),.i_replay_context_ready(1'b0),
        .i_host_replay_context_ready(1'b0),.i_replay_safe(1'b1),.i_replay_ready(1'b0),
        .i_bar_write_valid(1'b0),.i_bar_write_offset(12'd0),.i_bar_write_data(32'd0),.i_bar_write_strobes(4'd0),
        .i_bar_read_valid(1'b0),.i_bar_read_offset(12'd0)
    );

    raw_pair_job_service #(.WIDTH(16),.HEIGHT(4),.HDR_PROCESSING_ENABLE(1),.STEREO_ENABLE(1)) u_job (
        .clk(dfi_clk),.rst_n(dfi_rst_n),.i_identity_rst_n(dfi_rst_n),.i_now(i_now_ns),
        .i_config_valid(i_cfg_valid),.o_config_ready(o_cfg_ready),.o_config_done(o_cfg_done),
        .o_config_error(o_cfg_error),.i_session(SESSION),.i_epoch(EPOCH),.i_mode(2'd2),.i_mono_enable(1'b0),
        .i_max_delta(MAX_DELTA),.i_max_wait(MAX_WAIT),.i_max_age(MAX_AGE),
        .o_pair_config_valid(pair_cfg_valid),.i_pair_config_ready(pair_cfg_ready),.i_pair_config_error(pair_cfg_error),
        .i_pair_valid(o_pair_valid),.o_pair_ready(o_pair_ready),.i_pair_bank(o_pair_bank),.i_pair_id(o_pair_id),
        .i_pair_empty(pair_empty),.i_pair_fault(pair_fault),
        .o_pair_directory_valid(dir_req),.o_pair_directory_slot(dir_slot),.i_pair_directory_ready(dir_ready),
        .s_pair_directory_data(dir_data),.s_pair_directory_word(dir_word),.s_pair_directory_valid(dir_valid),
        .s_pair_directory_last(dir_last),.s_pair_directory_ready(dir_take),
        .o_pair_release_valid(o_release_valid),.i_pair_release_ready(o_release_ready),
        .o_pair_release_bank(o_release_bank),.o_pair_release_id(o_release_id),.o_retire_done(o_retire_done),
        .o_job_valid(o_job_valid),.o_job_ready(o_job_ready),.o_job_id(o_job_id),.o_pair_id(o_job_pair_id),
        .o_job_lease0(o_job_lease0),.o_job_lease1(o_job_lease1),.o_job_frame0(o_job_frame),
        .o_scheduler_busy(o_scheduler_busy),.o_quiescent(job_quiet),.o_fault(o_fault),

        .m_member_valid(o_member_valid),.m_member_index(o_member_index),.m_member_ready(i_member_ready),
        .o_hdr_context_valid(o_context_valid),.i_hdr_context_ready(i_context_ready),
        .o_hdr_start_valid(o_start_valid),.i_hdr_start_ready(i_start_ready),
        .o_hdr_result_transport_enable(result_enable),.i_hdr_result_valid(i_result_valid),
        .i_hdr_result_ready(o_result_ready),.i_hdr_result_ok(i_result_ok),.i_hdr_result_error(8'd0),
        .i_processing_done(i_processing_done),.i_processing_error(i_processing_error),
        .i_processing_job_id(i_processing_job_id),.i_processing_member_index(1'b0),
        .i_retire_inhibit(!i_ticket_released),.i_product_quiescent(i_product_quiet),
        .i_read_quiescent(read_quiet),.i_public_read_quiescent(public_read_quiet),
        .i_hdr_read_quiescent(i_reader_quiet),.i_hdr_reset_done(1'b1),.i_hdr_fault(1'b0),.i_hard_fault(1'b0),
        .i_cancel(1'b0),.i_hdr_cancel_ready(1'b0),.i_processing_cancel_ready(1'b0),
        .i_native_done(1'b0),.i_native_error(1'b0),.i_native_job_id(64'd0),.i_native_member_index(1'b0),

        .i_stereo_mode(1'b0),.i_stereo_job_valid(1'b0),.i_stereo_empty(1'b1),
        .i_stereo_job_frame(384'd0),.i_stereo_job_lease(64'd0),.i_stereo_job_id(64'd0),
        .i_stereo_retire_ready(1'b0),.i_stereo_retire_done(1'b0),.i_stereo_retire_error(1'b0),
        .i_commit_valid(1'b0),.i_descriptor(384'd0),.i_lease(64'd0),.i_ref_ready(1'b0),
        .i_req_ready(1'b0),.i_rsp_valid(1'b0),.i_rsp_code(4'd0),.i_rsp_camera(1'b0),.i_rsp_slot(2'd0),
        .i_rsp_generation(32'd0),.i_rsp_session(32'd0),.i_rsp_sequence(32'd0),.i_rsp_epoch(32'd0)
    );
endmodule

`default_nettype wire
