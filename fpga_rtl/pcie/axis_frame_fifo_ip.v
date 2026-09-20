`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     axis_frame_fifo_ip
// Module Name:     axis_frame_fifo_ip
// Description:     Ready-valid adapter for the Anlogic asynchronous Soft FIFO.
// Dependencies:    Anlogic Soft_FIFO 3.0 encrypted vendor RTL
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        axis_frame_fifo_ip
// 模块名称:        axis_frame_fifo_ip
// 模块说明:        安路异步Soft FIFO的ready-valid适配层。
// 依赖文件:        安路Soft_FIFO 3.0加密官方RTL

module axis_frame_fifo_ip (
    input  wire         i_source_clk,
    input  wire         i_source_rst_n,
    input  wire [146:0] i_source_data,
    input  wire         i_source_valid,
    output wire         o_source_ready,

    input  wire         i_sink_clk,
    input  wire         i_sink_rst_n,
    output wire [146:0] o_sink_data,
    output wire         o_sink_valid,
    input  wire         i_sink_ready
);

    wire fifo_reset;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire fifo_valid;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire fifo_almost_empty;
    wire [9:0] fifo_write_used;
    wire [9:0] fifo_read_used;
    wire fifo_overflow;
    wire fifo_underflow;
    wire fifo_write_success;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;

    assign fifo_reset = !i_source_rst_n || !i_sink_rst_n;
    assign o_source_ready = fifo_write_reset_done && !fifo_full;
    assign fifo_write_enable = i_source_valid && o_source_ready;
    assign fifo_read_enable = o_sink_valid && i_sink_ready;
    assign o_sink_valid = fifo_read_reset_done && fifo_valid && !fifo_empty;

    // This is the official Anlogic Soft_FIFO 3.0 implementation copied
    // byte-for-byte from the installed TD 6.2.1 IP depot.  This wrapper owns
    // only the AXI-Stream ready/valid adaptation; storage, Gray-pointer CDC and
    // reset synchronization remain inside the vendor IP.
    soft_fifo #(
        .COMMON_CLK_EN(0),
        .MEMORY_TYPE(0),
        .RST_TYPE(1),
        .DATA_WIDTH_W(147),
        .ADDR_WIDTH_W(9),
        .DATA_WIDTH_R(147),
        .ADDR_WIDTH_R(9),
        .DOUT_INITVAL(147'h0),
        .OUTREG_EN("NOREG"),
        .SHOW_AHEAD_EN(1),
        .AL_FULL_NUM(504),
        .AL_EMPTY_NUM(2),
        .RDUSEDW_WIDTH(10),
        .WRUSEDW_WIDTH(10),
        .ASYNC_RST_SYNC_RELS(1),
        .SYNC_STAGE(2)
    ) u_pcie_axis_async_fifo (
        .rst(fifo_reset),
        .srst(1'b0),
        .wrst(fifo_reset),
        .rrst(fifo_reset),
        .clk(1'b0),
        .clkw(i_source_clk),
        .clkr(i_sink_clk),
        .we(fifo_write_enable),
        .di(i_source_data),
        .re(fifo_read_enable),
        .dout(o_sink_data),
        .valid(fifo_valid),
        .full_flag(fifo_full),
        .empty_flag(fifo_empty),
        .afull(fifo_almost_full),
        .aempty(fifo_almost_empty),
        .wrusedw(fifo_write_used),
        .rdusedw(fifo_read_used),
        .overflow(fifo_overflow),
        .underflow(fifo_underflow),
        .wr_success(fifo_write_success),
        .wr_rst_done(fifo_write_reset_done),
        .rd_rst_done(fifo_read_reset_done)
    );

    wire unused_fifo_status;
    assign unused_fifo_status = fifo_almost_full ^ fifo_almost_empty ^
                                fifo_overflow ^ fifo_underflow ^
                                fifo_write_success ^ ^fifo_write_used ^
                                ^fifo_read_used;

endmodule
