// Public declaration only. Do not compile this file as a module.
module jpeg_entropy #(
    parameter integer STREAM_INPUT_ENABLE = 0,
    parameter integer RESTART_ENABLE = 0,
    parameter ROM_INIT_ROOT = `JPEG_QUANT_DEFAULT_ROOT,
    parameter ROM_INIT_SUFFIX = ".mif",
    parameter integer COEFF_BANKED_STORAGE_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 中止控制
    input wire i_abort,

    // 输入量化系数
    input wire i_block_valid,
    output wire o_block_ready,
    input wire [1023:0] i_coeffs,
    input wire [1:0] i_component,
    input wire [1:0] i_block_index,
    input wire [8:0] i_mcu_x,
    input wire [8:0] i_mcu_y,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,

    // Optional narrow coefficient stream: HEADER then eight batches.
    input wire i_token_valid,
    output wire o_token_ready,
    input wire [127:0] i_token_data,
    input wire [15:0] i_token_keep,
    input wire i_token_last,
    input wire [1:0] i_token_user,
    input wire [15:0] i_restart_mcus,

    // 输出熵编码字节
    output wire o_byte_valid,
    input wire i_byte_ready,
    output reg [7:0] o_byte,
    output reg o_byte_last,

    // 完成与错误状态
    output wire o_entropy_done, // 当前帧熵数据已完成输出
    output wire o_error_valid,
    output reg [31:0] o_error_capture_id,
    output reg [7:0] o_error_code,
    output wire o_idle
);
