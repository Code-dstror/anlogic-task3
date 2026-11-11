`timescale 1ns/1ps

// Actual USER/PIX/DFI transaction path. The external frame and DFI job
// endpoints are intentionally driven through the public carrier ports.
module quality_config_carrier #(
    parameter integer QUALITY_CONTROL_ENABLE=1
) (
    input wire user_clk,user_rst_n,pixel_clk,pixel_rst_n,dfi_clk,dfi_rst_n,
    input wire i_stereo_mode,i_uhd_mode,
    input wire write_valid,input wire [11:0] write_offset,
    input wire [31:0] write_data,input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,input wire [11:0] read_offset,
    output wire read_response_valid,output wire [31:0] read_data,
    output wire [1:0] read_response,
    input wire [1:0] i_source_idle,i_capture_enqueue,i_capture_consume,
    input wire i_write_quiet,i_pipeline_idle,i_frame_accept,
    input wire [31:0] i_frame_sequence,
    output wire o_source_ready,o_pause_new_frames,
    output wire o_job_config_valid,input wire i_job_config_ready,
    input wire i_job_config_done,i_job_config_error,i_job_config_busy,
    output wire [1183:0] o_job_config,o_dfi_active,o_pixel_active,o_service_active,
    input wire i_release_whole_ack,
    output wire o_whole_ack_valid,
    input wire i_inject_ack_valid,i_inject_ack_ok,
    input wire [1183:0] i_inject_ack_data,
    output wire o_inject_ack_ready,
    output wire o_cfg_fault,output wire [31:0] o_stale_ack_count,
    output wire o_user_initialized,o_pixel_initialized
);
    `include "pcie_protocol_v1.vh"
    `include "mono_config_transport_v2.vh"
    wire [1183:0] request,frontend_ack;
    wire request_valid,request_ready,frontend_valid,frontend_ready,frontend_ok;
    wire [MONO_TUPLE_BITS-1:0] whole_ack,job_config,dfi_active;
    wire whole_ack_ok,service_ack_ready;
    wire capture_fault,engine_fault;
    wire [1:0] drain_fault,drain_dfi_fault;
    wire source_fault,dfi_fault;
    wire cohort=pixel_rst_n&&dfi_rst_n;
    assign o_job_config=mono_unpack_tuple(job_config);
    assign o_dfi_active=mono_unpack_tuple(dfi_active);
    assign o_cfg_fault=capture_fault||engine_fault||(|drain_fault)||(|drain_dfi_fault)||source_fault||dfi_fault;
    assign o_inject_ack_ready=service_ack_ready;

    mono_config_service_v2 #(.STEREO_CAPABLE(1),.EXT_SUPPORTED(8'h34),
        .V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f),.APPLY_SOURCE_FAULT_ENABLE(1)
`ifndef QUALITY_CONTROL_PARENT
        ,.QUALITY_CONTROL_ENABLE(QUALITY_CONTROL_ENABLE)
        ,.UHD_COLOR_ENABLE(1),.UHD_PREPROCESS_ENABLE(1)
`endif
    ) config_service (
        .user_clk(user_clk),.user_rst_n(user_rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),
        .i_stereo_mode(i_stereo_mode),.o_user_transaction_idle(),.o_user_stereo_compatible(),
        .write_valid(write_valid),.write_offset(write_offset),.write_data(write_data),
        .write_strobes(write_strobes),.write_response(write_response),
        .read_valid(read_valid),.read_offset(read_offset),.read_response_valid(read_response_valid),
        .read_data(read_data),.read_response(read_response),
        .pipeline_idle(i_pipeline_idle),.frame_accept(i_frame_accept),.frame_sequence(i_frame_sequence),
        .source_ready(o_source_ready),.pause_new_jobs(o_pause_new_frames),
        .active_mode(),.active_quality(),.adaptive_quality(),.minimum_quality(),.frame_budget(),.restart_mcus(),
        .source_session(),.mode_epoch(),.user_session(),.user_initialized(o_user_initialized),.pixel_initialized(o_pixel_initialized),
        .m_config_data(request),.m_config_valid(request_valid),.m_config_ready(request_ready),
        .s_config_ack_data(i_inject_ack_valid?i_inject_ack_data:mono_unpack_tuple(whole_ack)),
        .s_config_ack_valid(i_inject_ack_valid||(i_release_whole_ack&&o_whole_ack_valid)),
        .s_config_ack_ok(i_inject_ack_valid?i_inject_ack_ok:whole_ack_ok),.s_config_ack_ready(service_ack_ready),
        .config_fault(engine_fault),.config_stale_ack_count(o_stale_ack_count),.active_config(o_service_active),
        .active_schema2(),.active_legacy_gaussian(),.active_product_mode(),.active_processing_enables(),
        .diag_observer_rst_n(2'b00),.diag_source_fs(1'b0),.diag_source_gates(16'd0),
        .diag_domains(),.diag_domain_reset_n(),.i_apply_source_fault(capture_fault),.o_apply_diagnostics()
`ifndef QUALITY_CONTROL_PARENT
        ,.i_uhd_mode_user(i_uhd_mode),.i_uhd_mode_pixel(i_uhd_mode)
`endif
    );

    physical_pair_config_owner #(.TRUSTED_INPUT(1)) capture_owner (
        .clk(pixel_clk),.owner_rst_n(pixel_rst_n),.cohort_rst_n(cohort),.dfi_clk(dfi_clk),
        .s_config_data(request),.s_config_valid(request_valid),.s_config_ready(request_ready),
        .m_config_ack_data(frontend_ack),.m_config_ack_valid(frontend_valid),.m_config_ack_ok(frontend_ok),
        .m_config_ack_ready(frontend_ready),.source0_idle(i_source_idle[0]),.source1_idle(i_source_idle[1]),
        .enqueue0(i_capture_enqueue[0]),.enqueue1(i_capture_enqueue[1]),
        .consume0(i_capture_consume[0]),.consume1(i_capture_consume[1]),.write_quiet(i_write_quiet),
        .active_config(o_pixel_active),.initialized(),.busy(),.config_fault(capture_fault),
        .drain_fault(drain_fault),.dfi_fault(drain_dfi_fault),.local_reset_done(),.config_reset_done(),
        .enqueued0(),.enqueued1(),.consumed0(),.consumed1());

    frame_job_config_cdc #(.EXT_WIDTH(MONO_EXTENSION_BITS),.COMPACT_STAGE2_EXTENSION_ENABLE(1),
        .EXT_SUPPORTED(8'h34),.TRUSTED_INPUT(1)) job_owner (
        .i_pixel_clk(pixel_clk),.i_pixel_rst_n(pixel_rst_n),.i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n),
        .i_dehaze_lut_valid(1'b0),.i_dehaze_lut_generation(32'd0),.i_dehaze_update_busy(1'b0),
        .o_dehaze_lut_update_inhibit(),
        .s_frontend_applied_data(mono_pack_tuple(frontend_ack)),.s_frontend_applied_valid(frontend_valid),
        .s_frontend_applied_ok(frontend_ok),.s_frontend_applied_ready(frontend_ready),
        .m_whole_ack_data(whole_ack),.m_whole_ack_valid(o_whole_ack_valid),.m_whole_ack_ok(whole_ack_ok),
        .m_whole_ack_ready(i_release_whole_ack&&!i_inject_ack_valid&&service_ack_ready),
        .i_pair_mode(2'd0),.i_mono_enable(1'b1),.i_max_delta_ns(64'd1000000),
        .i_max_wait_ns(32'd50000000),.i_max_age_ns(32'd100000000),
        .o_job_config_valid(o_job_config_valid),.i_job_config_ready(i_job_config_ready),
        .o_job_session(),.o_job_epoch(),.o_job_mode(),.o_job_mono_enable(),
        .o_job_max_delta_ns(),.o_job_max_wait_ns(),.o_job_max_age_ns(),.o_job_config_snapshot(job_config),
        .i_job_config_done(i_job_config_done),.i_job_config_error(i_job_config_error),.i_job_config_busy(i_job_config_busy),
        .o_source_reset_done(),.o_dfi_reset_done(),.o_source_busy(),.o_dfi_busy(),
        .o_active_session(),.o_active_epoch(),.o_active_valid(),.o_active_config(dfi_active),.o_active_hdr(),
        .o_source_fault(source_fault),.o_dfi_fault(dfi_fault),.o_stale_ack_count(),.o_stale_job_done_count());
endmodule
