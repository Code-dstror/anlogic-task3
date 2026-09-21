`timescale 1ns / 1ps

module csi2_async_event_fifo (
    input  wire        i_write_clk,
    input  wire        i_reset_n,
    input  wire [46:0] i_write_data,
    input  wire        i_write_valid,
    output wire        o_write_ready,
    input  wire        i_read_clk,
    output wire [46:0] o_read_data,
    output wire        o_read_valid,
    input  wire        i_read_ready
);
    // The vendor FIFO synchronizes release of rst in each clock domain.
    // Combining locally released resets here would release its internal
    // asynchronous reset from the other domain at an arbitrary clock edge.
    wire fifo_reset = !i_reset_n;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_valid;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;
    wire [9:0] fifo_write_used;
    wire [9:0] fifo_read_used;
    wire unused_status;

    assign o_write_ready = fifo_write_reset_done && !fifo_full &&
                           (fifo_write_used < 10'd504);
    assign o_read_valid = fifo_read_reset_done && fifo_valid && !fifo_empty;

    soft_fifo #(
        .COMMON_CLK_EN(0), .MEMORY_TYPE(0), .RST_TYPE(1),
        .DATA_WIDTH_W(47), .ADDR_WIDTH_W(9),
        .DATA_WIDTH_R(47), .ADDR_WIDTH_R(9),
        .DOUT_INITVAL(47'd0), .OUTREG_EN("NOREG"), .SHOW_AHEAD_EN(1),
        .AL_FULL_NUM(504), .AL_EMPTY_NUM(2),
        .RDUSEDW_WIDTH(10), .WRUSEDW_WIDTH(10),
        .ASYNC_RST_SYNC_RELS(1), .SYNC_STAGE(2)
    ) u_event_fifo (
        .rst(fifo_reset), .srst(1'b0), .wrst(1'b0), .rrst(1'b0),
        .clk(1'b0), .clkw(i_write_clk), .clkr(i_read_clk),
        .we(i_write_valid && o_write_ready), .di(i_write_data),
        .re(o_read_valid && i_read_ready), .dout(o_read_data),
        .valid(fifo_valid), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(fifo_write_used), .rdusedw(fifo_read_used),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done), .rd_rst_done(fifo_read_reset_done)
    );

    assign unused_status = ^fifo_read_used;
endmodule
