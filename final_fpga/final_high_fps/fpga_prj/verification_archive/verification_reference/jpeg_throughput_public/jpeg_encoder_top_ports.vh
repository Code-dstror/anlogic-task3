// Public declaration only. Do not compile this file as a module.
module jpeg_encoder_top #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer SHARED_STREAM_ENABLE = 0,
    parameter ROM_INIT_ROOT = `JPEG_QUANT_DEFAULT_ROOT,
    parameter ROM_INIT_SUFFIX = ".mif",
    parameter integer TINY_DISTRIBUTED_RAM_ENABLE = 0,
    parameter integer COEFF_BANKED_STORAGE_ENABLE = 0,
    parameter integer MCU_ROW_STREAM_ENABLE = 0,
    parameter integer FIXED_GEOMETRY_ENABLE = 0,
    parameter integer DUAL_GEOMETRY_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 像素输入流
    input wire [95:0] i_rgb,
    input wire [31:0] i_luma,
    input wire [7:0] i_quality,
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id,
    input wire [15:0] i_restart_mcus,
    input wire i_rgb_valid,
    output wire o_rgb_ready,
    input wire i_sof,
    input wire i_eol,
    input wire [31:0] i_capture_id,
    input wire [12:0] i_width,
    input wire [12:0] i_height,

    // 帧状态输入
    input wire i_frame_status_valid,
    output wire o_frame_status_ready,
    input wire [31:0] i_frame_status_id,
    input wire i_frame_ok,

    // 编码载荷输出
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,

    // 帧结果输出
    output wire o_result_valid,
    input wire i_result_ready,
    output wire [31:0] o_result_id,
    output wire o_result_ok,
    output wire [24:0] o_payload_length, // 编码结束时得到的实际字节数
    output wire [7:0] o_error_code,
    output wire [7:0] o_result_quality,
    output wire [31:0] o_result_epoch,
    output wire o_idle
);
