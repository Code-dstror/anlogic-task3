`timescale 1ns/1ps
`default_nettype none

// Maintainer-owned wiring fixture. The independent bench owns the input
// traffic, external ingress/write obligations and all output expectations.
module hdr_cfg_drain_carrier (
    input wire i_pixel_clk,i_pixel_rst_n,i_dfi_clk,i_dfi_rst_n,
    input wire i_hdr_rst_n,i_admit_enable,i_stable,i_hdr_fault,
    input wire [31:0] i_timeout_phase,
    input wire [63:0] i_time,
    input wire i_time_valid,
    input wire [146:0] s_long_data,s_short_data,
    input wire s_long_valid,s_short_valid,
    output wire s_long_ready,s_short_ready,
    output wire [79:0] o_raw_data,
    output wire [1:0] o_raw_valid,o_raw_sof,o_raw_eol,o_raw_abort,
    output wire [1:0] o_source_valid,o_source_ok,
    input wire [1:0] i_source_ready,
    output wire [191:0] o_source_identity,
    output wire [15:0] o_source_error,
    output wire o_hdr_quiet,
    input wire [1:0] i_ingress_idle,i_enqueue_fire,i_consume_fire,
    input wire i_write_quiet,
    input wire [1183:0] s_cfg_data,
    input wire s_cfg_valid,
    output wire s_cfg_ready,
    output wire [1183:0] m_cfg_ack_data,
    output wire m_cfg_ack_valid,m_cfg_ack_ok,
    input wire m_cfg_ack_ready,
    output wire [1183:0] o_active_config,
    output wire o_initialized,o_cfg_busy,o_cfg_reset_done,o_cfg_fault,
    output wire [1:0] o_source_drain_fault,o_dfi_drain_fault
);
    wire cohort_rst_n=i_pixel_rst_n&&i_dfi_rst_n;
    wire owner_rst_n;
    reset_release_sync u_owner_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(owner_rst_n));

    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(12500000),.EXTERNAL_PHASE_ENABLE(1)) u_hdr(
        .i_clk(i_pixel_clk),.i_reset_n(owner_rst_n&&i_hdr_rst_n),
        .i_fault(i_hdr_fault),.i_stable(i_stable),.i_admit_enable(i_admit_enable),
        .i_session(o_active_config[63:32]),.i_epoch(o_active_config[159:128]),
        .i_time(i_time),.i_time_valid(i_time_valid),.i_timeout_phase(i_timeout_phase),
        .i_capture0_idle(i_ingress_idle[0]),.i_capture1_idle(i_ingress_idle[1]),
        .s0_data(s_long_data),.s0_valid(s_long_valid),.s0_ready(s_long_ready),
        .s1_data(s_short_data),.s1_valid(s_short_valid),.s1_ready(s_short_ready),
        .m0_data(o_raw_data[39:0]),.m1_data(o_raw_data[79:40]),
        .m0_valid(o_raw_valid[0]),.m1_valid(o_raw_valid[1]),
        .m0_sof(o_raw_sof[0]),.m1_sof(o_raw_sof[1]),
        .m0_eol(o_raw_eol[0]),.m1_eol(o_raw_eol[1]),
        .m0_abort(o_raw_abort[0]),.m1_abort(o_raw_abort[1]),
        .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),.o_metadata0(),.o_metadata1(),
        .o_source0_valid(o_source_valid[0]),.o_source1_valid(o_source_valid[1]),
        .i_source0_ready(i_source_ready[0]),.i_source1_ready(i_source_ready[1]),
        .o_source_session(o_source_identity[95:64]),.o_source_epoch(o_source_identity[63:32]),
        .o_source0_sequence(o_source_identity[31:0]),.o_source1_sequence(o_source_identity[127:96]),
        .o_source1_session(o_source_identity[191:160]),.o_source1_epoch(o_source_identity[159:128]),
        .o_source_ok(o_source_ok[0]),.o_source1_ok(o_source_ok[1]),
        .o_source_error(o_source_error[7:0]),.o_source1_error(o_source_error[15:8]),
        .o_pair_event(),.o_pair_ok(),.o_diag_pair(),.o_diag_counts(),
        .o_good_pairs(),.o_bad_pairs(),.o_not_admitted_pairs(),.o_quiet(o_hdr_quiet));

    physical_pair_config_owner #(.TRUSTED_INPUT(1)) u_owner(
        .clk(i_pixel_clk),.owner_rst_n(owner_rst_n),.cohort_rst_n(cohort_rst_n),.dfi_clk(i_dfi_clk),
        .s_config_data(s_cfg_data),.s_config_valid(s_cfg_valid),.s_config_ready(s_cfg_ready),
        .m_config_ack_data(m_cfg_ack_data),.m_config_ack_valid(m_cfg_ack_valid),
        .m_config_ack_ok(m_cfg_ack_ok),.m_config_ack_ready(m_cfg_ack_ready),
        .source0_idle(o_hdr_quiet&&i_ingress_idle[0]),.source1_idle(i_ingress_idle[1]),
        .enqueue0(i_enqueue_fire[0]),.enqueue1(i_enqueue_fire[1]),
        .consume0(i_consume_fire[0]),.consume1(i_consume_fire[1]),.write_quiet(i_write_quiet),
        .active_config(o_active_config),.initialized(o_initialized),.busy(o_cfg_busy),
        .config_fault(o_cfg_fault),.drain_fault(o_source_drain_fault),.dfi_fault(o_dfi_drain_fault),
        .local_reset_done(),.config_reset_done(o_cfg_reset_done),
        .enqueued0(),.enqueued1(),.consumed0(),.consumed1());
endmodule
`default_nettype wire
