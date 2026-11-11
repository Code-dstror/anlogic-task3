`timescale 1ns / 1ps

// 集成 IMX415 配置、CSI 接收和 RGB AXIS 输出
module real_hdr_camera_observe_axis #(
    // 传感器采集模式
    parameter integer MODE_4K = 0,
    parameter integer SDR_RATE_CONTROL_ENABLE=0,
    parameter integer RX_DIAG_ENABLE=0,
    parameter integer HDR_WARMUP_PAIRS=8,
    parameter integer HDR_I2C_HALF_PERIOD=125,
    parameter integer HDR_RESET_HOLD_CYCLES=250000,
    parameter integer HDR_RELEASE_WAIT_CYCLES=750000,
    parameter integer HDR_REGULATOR_WAIT_CYCLES=600000,
    parameter integer SDR_WAKE_CYCLES=600000,
    parameter integer FRAME_EVENTS_ENABLE = 1,
    // RGB 输出路径
    parameter integer RGB_TAP = 0,
    // 裁剪起点与 Bayer 相位
    parameter integer FIRST_ROW = MODE_4K ? 36 : 20,
    parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00,
    parameter integer COLOR_CONFIG_ENABLE = 0,
    parameter integer RAW_REPLAY_ENABLE = 0,
    parameter integer RAW_REPLAY_SAMPLE_BITS = 10,
    parameter integer SHARED_WIDE_ISP_ENABLE = 0,
    parameter integer JOB_CONTROL_ENABLE = 0,
    parameter integer SEPARATE_REPLAY_JOB_CONTROL = 0,
    parameter integer CONTROLLED_ABORT_ENABLE = 0,
    parameter integer CONTROLLED_REPLAY_ABORT_ENABLE = 0,
    // 时钟与时序配置
    parameter integer SILENCE_CYCLES = 12500000
) (
    // 时钟与复位
    input wire i_pixel_clk,
    input wire i_sensor_clk,
    input wire i_cfg_clk,i_hdr_mclk,i_clock_locked,i_hdr_request,i_mode_quiet,
    input wire i_sdr_30_request,
    output wire o_sdr_30_mode,
    input wire i_hdr_pair_event,i_hdr_pair_ok,
    output wire o_hdr_mode,o_mode_running,o_hdr_stable,
    output wire o_rx_diag_word_clk,
    output wire [127:0] o_rx_diag_word,o_rx_diag_cfg,
    output wire [255:0] o_rx_trace_sample,
    output wire o_rx_trace_trigger,o_rx_trace_cohort_n,o_rx_trace_enable,
    output wire [146:0] m_hdr0_data,m_hdr1_data,
    output wire m_hdr0_valid,m_hdr1_valid,
    input wire m_hdr0_ready,m_hdr1_ready,
    input wire i_ref_clk,
    input wire i_reset_n,
    input wire i_processing_reset_n,
    input wire [29:0] i_wb_gains,
    input wire [1:0] i_bayer_phase, // Pixel-domain configuration, stable for session
    input wire [7:0] i_gain_code,   // Sensor-domain configuration, stable for session
    input wire i_job_enable, input wire i_job_pause,
    input wire i_replay_job_enable, input wire i_replay_job_pause,
    output wire o_job_start, output wire o_job_idle, output wire o_job_replay,
    // CSI 与传感器引脚
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk,
    output wire cam_xclr,
    // AXIS 输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,
    output wire m_frame_event_valid,
    input wire m_frame_event_ready,
    output wire [1:0] m_frame_event_kind,
    output wire m_frame_event_ok,
    output wire [3:0] m_frame_event_error,
    output wire [31:0] m_frame_event_sequence,
    output wire m_frame_event_identity_valid,
    output wire o_source_identity_fault,
    // 配置、帧状态与接收错误
    output wire o_frame_error,
    output wire o_frame_done,
    output wire o_config_done,
    output wire o_config_error,
    output wire [31:0] o_ecc_errors,
    output wire [31:0] o_crc_errors,
    output wire [31:0] o_overflows,
    output wire [31:0] o_format_errors,
    output wire o_delay_ready,
    output reg [7:0] o_delay_debug,
    output reg [5:0] o_delay_window,
    output reg o_delay_status_valid,
    output wire o_phy_ready,
    // RGB 像素流
    output wire [95:0] o_rgb_tdata,
    output wire o_rgb_tvalid,
    input wire i_rgb_tready,
    output wire o_rgb_tuser,
    output wire o_rgb_tlast,
    // S04 crop tap and replay share the original pixel-domain ISP.
    output wire [39:0] o_cropped_raw_data,
    output wire o_cropped_raw_valid, o_cropped_raw_ready,
    output wire o_cropped_raw_sof, o_cropped_raw_eol, o_cropped_raw_abort,
    output wire [31:0] o_cropped_raw_sequence,output wire o_cropped_raw_identity_valid,
    input wire i_replay_active,
    input wire [4*RAW_REPLAY_SAMPLE_BITS-1:0] i_replay_data,
    input wire i_replay_hdr_enable,
    input wire [3:0] i_replay_tone_shift,
    input wire i_replay_valid, i_replay_sof, i_replay_eol, i_replay_abort,
    output wire o_replay_ready, o_replay_safe,
    // Passive pixel-domain receiver taps; never drive functional READY/data.
    output wire o_observe_raw_valid,
    output wire o_observe_raw_ready,
    output wire o_observe_raw_sof,
    output wire o_observe_raw_eol,
    output wire o_observe_raw_abort,
    output wire o_observe_receive_fault
);
    localparam integer WIDTH = MODE_4K ? 3840 : 1920;
    localparam integer HEIGHT = MODE_4K ? 2160 : 1080;
    localparam integer CONFIG_WAIT_CYCLES=240000, I2C_HALF_PERIOD=120, EVENT_FIFO_DEPTH=0;
    wire sdr_event_activity=1'b0;
    `include "camera_physical_capture.vh"
    assign raw_ready=pipeline_raw_ready&&!receive_fault;
    physical_camera_rgb_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FIRST_ROW(FIRST_ROW),
        .RGB_TAP(RGB_TAP),
        .FIRST_GROUP(FIRST_GROUP),.BAYER_PHASE(BAYER_PHASE),
        .RUNTIME_BAYER_ENABLE(COLOR_CONFIG_ENABLE),
        .RUNTIME_WB_ENABLE(COLOR_CONFIG_ENABLE),
        .RAW_REPLAY_ENABLE(RAW_REPLAY_ENABLE),.RAW_REPLAY_SAMPLE_BITS(RAW_REPLAY_SAMPLE_BITS),.SHARED_WIDE_ISP_ENABLE(SHARED_WIDE_ISP_ENABLE),
        .JOB_CONTROL_ENABLE(JOB_CONTROL_ENABLE),
        .SEPARATE_REPLAY_JOB_CONTROL(SEPARATE_REPLAY_JOB_CONTROL),
        .CONTROLLED_ABORT_ENABLE(CONTROLLED_ABORT_ENABLE),
        .CONTROLLED_REPLAY_ABORT_ENABLE(CONTROLLED_REPLAY_ABORT_ENABLE)) u_pipeline (
        .i_clk(i_pixel_clk),.i_rst_n(pixel_reset[1]),
        .i_processing_reset_n(i_processing_reset_n),.i_raw_data(raw_data),
        .i_bayer_phase(i_bayer_phase), .i_wb_gains(i_wb_gains),
        .i_job_enable(i_job_enable),.i_job_pause(i_job_pause),
        .i_replay_job_enable(i_replay_job_enable),.i_replay_job_pause(i_replay_job_pause),
        .o_job_start(o_job_start),.o_job_idle(o_job_idle),.o_job_replay(o_job_replay),
        .i_raw_valid(raw_valid || receive_fault),.o_raw_ready(pipeline_raw_ready),
        .i_raw_sof(raw_sof && !receive_fault),
        .i_raw_sequence(raw_sequence),.i_raw_identity_valid(raw_identity_valid && !receive_fault),
        .i_raw_eol(raw_eol && !receive_fault),.i_raw_abort(raw_abort || receive_fault),
        .o_axis_tdata(o_axis_tdata),.o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),.i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),.o_frame_error(o_frame_error),.o_frame_done(o_frame_done),
        .o_rgb_tdata(o_rgb_tdata),.o_rgb_tvalid(o_rgb_tvalid),
        .i_rgb_tready(i_rgb_tready),.o_rgb_tuser(o_rgb_tuser),
        .o_rgb_tlast(o_rgb_tlast),
        .o_cropped_raw_data(o_cropped_raw_data),
        .o_cropped_raw_valid(o_cropped_raw_valid),
        .o_cropped_raw_ready(o_cropped_raw_ready),
        .i_cropped_raw_ready(1'b1),
        .o_cropped_raw_sof(o_cropped_raw_sof),
        .o_cropped_raw_eol(o_cropped_raw_eol),
        .o_cropped_raw_abort(o_cropped_raw_abort),
        .o_cropped_raw_sequence(o_cropped_raw_sequence),.o_cropped_raw_identity_valid(o_cropped_raw_identity_valid),
        .i_replay_active(i_replay_active), .i_replay_data(i_replay_data),
        .i_replay_hdr_enable(i_replay_hdr_enable),.i_replay_tone_shift(i_replay_tone_shift),
        .i_replay_valid(i_replay_valid), .i_replay_sof(i_replay_sof),
        .i_replay_eol(i_replay_eol), .i_replay_abort(i_replay_abort),
        .o_replay_ready(o_replay_ready), .o_replay_safe(o_replay_safe),
        .i_external_rgb_data(96'd0), .i_external_rgb_valid(1'b0),
        .i_external_rgb_sof(1'b0), .i_external_rgb_eol(1'b0),
        .i_external_rgb_abort(1'b0), .o_external_rgb_ready()
    );
    assign o_observe_raw_valid = raw_valid;
    assign o_observe_raw_ready = raw_ready;
    assign o_observe_raw_sof = raw_sof;
    assign o_observe_raw_eol = raw_eol;
    assign o_observe_raw_abort = raw_abort;
    assign o_observe_receive_fault = receive_fault;
endmodule
