// Public declaration only. Do not compile this file as a module.
module jpeg_mcu_422 #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer ROW_STREAM_ENABLE = 0,
    parameter integer FIXED_GEOMETRY_ENABLE = 0,
    parameter integer DUAL_GEOMETRY_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 输入四二二像素
    input wire i_valid,
    output wire o_ready,
    input wire [31:0] i_y,
    input wire [15:0] i_cb,
    input wire [15:0] i_cr,
    input wire i_sof,
    input wire i_eol,
    input wire [31:0] i_capture_id,
    input wire [12:0] i_width,
    input wire [12:0] i_height,

    // 输出编码块
    output reg o_block_valid,
    input wire i_block_ready,
    output reg [511:0] o_samples,
    output reg [1:0] o_component,
    output reg [1:0] o_block_index,
    output reg [8:0] o_mcu_x,
    output reg [8:0] o_mcu_y,
    output reg o_frame_last, // 当前块是本帧最后一个编码块
    output reg [31:0] o_capture_id,

    // 错误状态
    output reg o_error_valid,
    output reg [31:0] o_error_capture_id,
    output reg [2:0] o_error_code,

    // Optional row stream: eight low-byte-first rows per block.
    output wire o_row_valid,
    input wire i_row_ready,
    output wire [63:0] o_row_data,
    output wire [2:0] o_row_index
);
