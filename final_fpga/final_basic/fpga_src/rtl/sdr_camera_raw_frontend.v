`timescale 1ns / 1ps
`default_nettype none

// Capture-only CAM1 frontend (historical module name), with one PHY for SDR and DOL2. Both cameras
// deliver to the same PIX domain; the caller owns frame selection and the ISP.
module sdr_camera_raw_frontend #(
    parameter integer WIDTH = 1920,
    parameter integer SDR_RATE_CONTROL_ENABLE=0,
    parameter integer HEIGHT = 1080,
    parameter integer FIRST_ROW = 16,
    parameter integer FIRST_GROUP = 1,
    parameter integer CONFIG_WAIT_CYCLES = 240000,
    parameter integer SDR_WAKE_CYCLES = 600000,
    parameter integer I2C_HALF_PERIOD = 120,
    parameter integer SILENCE_CYCLES = 12500000,
    parameter integer RUNTIME_GAIN_ENABLE = 1,
    parameter integer EVENT_FIFO_DEPTH = 0,
    parameter integer HDR_WARMUP_PAIRS=8, HDR_I2C_HALF_PERIOD=125,
    parameter integer HDR_RESET_HOLD_CYCLES=250000, HDR_RELEASE_WAIT_CYCLES=750000,
    parameter integer HDR_REGULATOR_WAIT_CYCLES=600000
)(
    input wire i_pixel_clk, i_sensor_clk, i_ref_clk, i_reset_n,
    input wire i_cfg_clk, i_hdr_mclk, i_clock_locked, i_hdr_request, i_mode_quiet,
    input wire i_sdr_30_request,
    output wire o_sdr_30_mode,
    input wire i_hdr_pair_event, i_hdr_pair_ok,
    output wire o_hdr_mode, o_mode_running, o_hdr_stable,
    output wire [146:0] m_hdr0_data, m_hdr1_data,
    output wire m_hdr0_valid, m_hdr1_valid,
    input wire m_hdr0_ready, m_hdr1_ready,
    input wire [7:0] i_gain_code,
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk, cam_xclr,
    output wire [39:0] o_cropped_raw_data,
    output wire o_cropped_raw_valid,
    input wire i_cropped_raw_ready,
    output wire o_cropped_raw_sof, o_cropped_raw_eol, o_cropped_raw_abort,
    output wire [31:0] o_cropped_raw_sequence,
    output wire o_cropped_raw_identity_valid,
    output wire m_frame_event_valid,
    input wire m_frame_event_ready,
    output wire [1:0] m_frame_event_kind,
    output wire m_frame_event_ok,
    output wire [3:0] m_frame_event_error,
    output wire [31:0] m_frame_event_sequence,
    output wire m_frame_event_identity_valid,
    output wire o_config_done, o_config_error, o_phy_ready,
    output wire o_delay_ready,
    output reg [7:0] o_delay_debug,
    output reg [5:0] o_delay_window,
    output reg o_delay_status_valid,
    output wire [31:0] o_ecc_errors, o_crc_errors, o_overflows, o_format_errors,
    output wire o_source_identity_fault,
    output wire o_receive_fault,
    output wire o_observe_raw_valid, o_observe_raw_ready,
    output wire o_observe_raw_sof, o_observe_raw_eol, o_observe_raw_abort,
    output wire [127:0] o_rx_diag_cfg
);
    generate if (WIDTH < 4 || WIDTH % 4 != 0 || HEIGHT < 1 ||
                 FIRST_ROW < 0 || FIRST_GROUP < 0 || SILENCE_CYCLES < 1) begin : g_invalid
        SDR_CAMERA_REQUIRES_RAW4_GEOMETRY_AND_POSITIVE_TIMEOUT invalid_configuration();
    end endgenerate

    localparam integer MODE_4K=0, RX_DIAG_ENABLE=0, FRAME_EVENTS_ENABLE=1;
    localparam integer COLOR_CONFIG_ENABLE=RUNTIME_GAIN_ENABLE;
    wire o_rx_diag_word_clk, o_rx_trace_trigger, o_rx_trace_cohort_n, o_rx_trace_enable;
    wire [127:0] o_rx_diag_word;
    wire [255:0] o_rx_trace_sample;
    wire sdr_event_activity=m_frame_event_valid;
    `include "camera_physical_capture.vh"
    wire pixel_reset_n=pixel_reset[1];
    assign o_receive_fault=receive_fault;

    wire [39:0] crop_data;
    wire crop_valid, crop_ready, crop_sof, crop_eol, crop_abort, crop_identity;
    wire [31:0] crop_sequence;
    physical_camera_crop #(.WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .FIRST_ROW(FIRST_ROW), .FIRST_GROUP(FIRST_GROUP)) u_crop(
        .i_clk(i_pixel_clk), .i_rst_n(pixel_reset_n), .i_raw_data(raw_data),
        .i_raw_valid(raw_valid), .o_raw_ready(raw_ready), .i_raw_sof(raw_sof),
        .i_raw_eol(raw_eol), .i_raw_abort(raw_abort), .i_raw_sequence(raw_sequence),
        .i_raw_identity_valid(raw_identity_valid), .o_data(crop_data),
        .o_valid(crop_valid), .i_ready(crop_ready),
        .o_sof(crop_sof), .o_eol(crop_eol), .o_abort(crop_abort),
        .o_sequence(crop_sequence), .o_identity_valid(crop_identity));

    // PHY clock loss resets its CDC FIFO. Keep any already presented crop
    // group in the always-running PIX domain until it transfers, even when
    // the upstream FIFO loses publication. Only cohort reset cancels a lease.
    reg [39:0] held_data;
    reg [31:0] held_sequence;
    reg held_valid, held_sof, held_eol, held_identity;
    reg abort_pending, abort_pulse;
    wire output_fire = held_valid && i_cropped_raw_ready;
    assign crop_ready = (!held_valid || i_cropped_raw_ready) && !abort_pending && !crop_abort;
    assign o_cropped_raw_data = held_data;
    assign o_cropped_raw_valid = held_valid;
    assign o_cropped_raw_sof = held_sof;
    assign o_cropped_raw_eol = held_eol;
    assign o_cropped_raw_sequence = held_sequence;
    assign o_cropped_raw_identity_valid = held_identity;
    assign o_cropped_raw_abort = abort_pulse;
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            held_valid <= 0; abort_pending <= 0; abort_pulse <= 0;
        end else begin
            abort_pulse <= 0;
            if (output_fire) held_valid <= 0;
            if (crop_valid && crop_ready) begin
                held_data <= crop_data; held_sequence <= crop_sequence;
                held_sof <= crop_sof; held_eol <= crop_eol; held_identity <= crop_identity;
                held_valid <= 1;
            end
            if (crop_abort) abort_pending <= 1;
            if ((abort_pending || crop_abort) && (!held_valid || output_fire)) begin
                abort_pending <= 0; abort_pulse <= 1;
            end
        end
    end

    assign o_observe_raw_valid = raw_valid;
    assign o_observe_raw_ready = raw_ready;
    assign o_observe_raw_sof = raw_sof;
    assign o_observe_raw_eol = raw_eol;
    assign o_observe_raw_abort = raw_abort;
endmodule
`default_nettype wire
