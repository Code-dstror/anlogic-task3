// Public declaration only. Compile the opaque source instead.
module jpeg_byte_packer #(
    // 存储与时序参数
    parameter integer MAX_PAYLOAD_BYTES = 16777216
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 帧控制
    input  wire i_abort,

    // 输入字节流
    input  wire [7:0] i_byte,
    input  wire i_valid,
    output wire o_ready,
    input  wire i_last,

    // AXI输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input  wire i_axis_tready,
    output wire o_axis_tlast,

    // 错误与空闲状态
    output wire o_frame_error,
    output wire o_overflow, // 帧长度超出配置上限
    output wire o_idle
);
