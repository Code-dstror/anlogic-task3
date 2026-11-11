`timescale 1ns/1ps
`default_nettype none

// Short digital startup carrier. The bench models the sensor's I2C slave
// and the aligned WORD stream after the physical receiver's training barrier.
module seed12_hdr_startup_carrier (
    input wire i_cfg_clk,i_word_clk,i_pixel_clk,i_reset_n,
    input wire i_config_start,i_clock_locked,i_hdr_profile,
    output wire o_start_ready,o_config_written,o_config_error,o_xclr,o_scl,
    output wire [7:0] o_register_index,
    inout wire io_sda,
    input wire i_word_enable,
    input wire [31:0] i_word,
    input wire i_word_valid,
    output wire o_word_fifo_ready,o_identity_fault,o_pair_overflow,
    input wire i_peer_stable,i_admit_enable,
    output wire o_hdr_stable,
    input wire [31:0] i_session,i_epoch,
    input wire [63:0] i_time_ns,
    input wire i_time_valid,
    input wire [1:0] i_capture_idle,i_source_ready,
    output wire [79:0] o_raw_data,
    output wire [1:0] o_raw_valid,o_raw_sof,o_raw_eol,o_raw_abort,
    output wire [393:0] o_metadata,
    output wire [1:0] o_source_valid,o_source_ok,
    output wire [63:0] o_source_session,o_source_epoch,o_source_sequence,
    output wire [15:0] o_source_error,
    output wire o_pair_event,o_pair_ok,o_quiet,
    output wire [31:0] o_good_pairs,o_bad_pairs,o_not_admitted_pairs
);
    wire cfg_reset_n, pixel_reset_n, sensor_stable;
    wire pair_event_cfg, pair_ok_cfg;
    wire [146:0] long_token, short_token;
    wire long_valid, short_valid, long_ready, short_ready;
    reg [1:0] written_word, stable_pixel, source_fault_cfg;

    reset_release_sync u_cfg_reset(
        .i_clk(i_cfg_clk),.i_async_rst_n(i_reset_n),.o_rst_n(cfg_reset_n));
    reset_release_sync u_pixel_reset(
        .i_clk(i_pixel_clk),.i_async_rst_n(i_reset_n),.o_rst_n(pixel_reset_n));
    always @(posedge i_word_clk or negedge i_reset_n) begin
        if (!i_reset_n) written_word<=0;
        else written_word<={written_word[0],o_config_written};
    end
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) stable_pixel<=0;
        else stable_pixel<={stable_pixel[0],sensor_stable};
    end
    always @(posedge i_cfg_clk or negedge cfg_reset_n) begin
        if (!cfg_reset_n) source_fault_cfg<=0;
        else source_fault_cfg<={source_fault_cfg[0],o_identity_fault||o_pair_overflow};
    end
    assign o_hdr_stable=stable_pixel[1]&&i_hdr_profile;

    imx415_sensor_config #(
        .I2C_HALF_PERIOD(4),.WARMUP_PAIRS(8),
        .SDR_RESET_HOLD_CYCLES(4),.SDR_RELEASE_WAIT_CYCLES(4),.SDR_WAKE_CYCLES(4),
        .HDR_RESET_HOLD_CYCLES(4),.HDR_RELEASE_WAIT_CYCLES(4),.HDR_REGULATOR_WAIT_CYCLES(4)
    ) u_config(
        .i_clk(i_cfg_clk),.i_rst_n(cfg_reset_n),.i_start(i_config_start),
        .o_start_ready(o_start_ready),.i_clock_locked(i_clock_locked),.i_abort(1'b0),
        .i_source_fault(source_fault_cfg[1]),.i_hdr(i_hdr_profile),.i_sdr_30(1'b1),.i_gain_code(8'd0),
        .i_pair_event(pair_event_cfg),.i_pair_ok(pair_ok_cfg),.o_xclr(o_xclr),
        .o_scl(o_scl),.io_sda(io_sda),.o_config_written(o_config_written),
        .o_stable(sensor_stable),.o_error(o_config_error),
        .o_register_index(o_register_index),.o_rx_diag_cfg());

    real_hdr_csi_capture_stream #(
        .SENSOR_WIDTH(4),.SENSOR_HEIGHT(1),.CROP_X(0),.CROP_Y(0),.WIDTH(4),.HEIGHT(1)
    ) u_receiver(
        .i_word_clk(i_word_clk),.i_pixel_clk(i_pixel_clk),.i_reset_n(i_reset_n),
        .i_decoder_reset_n(i_word_enable),.i_identity_rst_n(i_reset_n&&i_word_enable),
        .i_publish_enable(i_word_enable),.i_cycle_enable(written_word[1]),
        .i_word(i_word),.i_word_valid(i_word_valid),.o_fifo_write_ready(o_word_fifo_ready),
        .o_wait_for_sync(),.o_packet_done(),.o_packet_continue(),.o_identity_fault(o_identity_fault),
        .m0_data(long_token),.m1_data(short_token),.m0_valid(long_valid),.m1_valid(short_valid),
        .m0_ready(long_ready),.m1_ready(short_ready),.o_crc_errors(),.o_overflow_errors(),
        .o_format_errors(),.o_sequence_count0(),.o_sequence_count1(),
        .o_fs0_observe_valid(),.o_fs1_observe_valid(),.o_fs0_number(),.o_fs1_number());

    localparam integer PAIR_TIMEOUT_CYCLES=4096;
    reg [11:0] timeout_phase;
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) timeout_phase<=0;
        else timeout_phase<=timeout_phase+1'b1;
    end
    real_hdr_pair_cycle_gate #(
        .TIMEOUT_CYCLES(PAIR_TIMEOUT_CYCLES),.EXTERNAL_PHASE_ENABLE(1)
    ) u_pair(
        .i_clk(i_pixel_clk),.i_reset_n(pixel_reset_n),.i_fault(o_identity_fault),
        .i_stable(o_hdr_stable&&i_peer_stable),.i_admit_enable(i_admit_enable),
        .i_session(i_session),.i_epoch(i_epoch),.i_time(i_time_ns),.i_time_valid(i_time_valid),
        .i_capture0_idle(i_capture_idle[0]),.i_capture1_idle(i_capture_idle[1]),
        .s0_data(long_token),.s1_data(short_token),.s0_valid(long_valid),.s1_valid(short_valid),
        .s0_ready(long_ready),.s1_ready(short_ready),
        .m0_data(o_raw_data[39:0]),.m1_data(o_raw_data[79:40]),
        .m0_valid(o_raw_valid[0]),.m1_valid(o_raw_valid[1]),
        .m0_sof(o_raw_sof[0]),.m1_sof(o_raw_sof[1]),.m0_eol(o_raw_eol[0]),.m1_eol(o_raw_eol[1]),
        .m0_abort(o_raw_abort[0]),.m1_abort(o_raw_abort[1]),
        .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),
        .o_metadata0(o_metadata[196:0]),.o_metadata1(o_metadata[393:197]),
        .o_source0_valid(o_source_valid[0]),.o_source1_valid(o_source_valid[1]),
        .i_source0_ready(i_source_ready[0]),.i_source1_ready(i_source_ready[1]),
        .o_source_session(o_source_session[31:0]),.o_source1_session(o_source_session[63:32]),
        .o_source_epoch(o_source_epoch[31:0]),.o_source1_epoch(o_source_epoch[63:32]),
        .o_source0_sequence(o_source_sequence[31:0]),.o_source1_sequence(o_source_sequence[63:32]),
        .o_source_ok(o_source_ok[0]),.o_source1_ok(o_source_ok[1]),
        .o_source_error(o_source_error[7:0]),.o_source1_error(o_source_error[15:8]),
        .o_pair_event(o_pair_event),.o_pair_ok(o_pair_ok),.o_diag_pair(),.o_diag_counts(),
        .o_good_pairs(o_good_pairs),.o_bad_pairs(o_bad_pairs),.o_not_admitted_pairs(o_not_admitted_pairs),
        .o_quiet(o_quiet),.i_timeout_phase({20'd0,timeout_phase}));

    real_hdr_event_cdc u_pair_cdc(
        .s_clk(i_pixel_clk),.s_reset_n(pixel_reset_n),.s_event(o_pair_event),.s_ok(o_pair_ok),
        .s_overflow(o_pair_overflow),.m_clk(i_cfg_clk),.m_reset_n(cfg_reset_n),
        .m_event(pair_event_cfg),.m_ok(pair_ok_cfg));
endmodule
`default_nettype wire
