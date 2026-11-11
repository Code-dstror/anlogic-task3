`timescale 1ns / 1ps

// One DFI clock. Two accepted 16-beat reads bound this queue to 32 beats.
// The GUI-managed official IP owns storage, FWFT and reset release.
module ddr_response_fifo_ip (
    input wire i_clk, i_rst_n,
    input wire [146:0] i_data,
    input wire i_valid,
    output wire o_ready, o_reset_done,
    output wire [146:0] o_data,
    output wire o_valid,
    input wire i_ready
);
    wire fifo_full, fifo_empty, fifo_valid;
    wire write_reset_done, read_reset_done;
    assign o_reset_done=i_rst_n && write_reset_done && read_reset_done;
    assign o_ready=o_reset_done && !fifo_full;
    assign o_valid=o_reset_done && fifo_valid && !fifo_empty;
    matrix_response_fifo_147x32 u_configured_ip (
        .rst(!i_rst_n),.clk(i_clk),.di(i_data),.we(i_valid && o_ready),
        .re(o_valid && i_ready),.dout(o_data),
        .empty_flag(fifo_empty),.aempty(),.full_flag(fifo_full),.afull(),
        .valid(fifo_valid),.overflow(),.underflow(),.wr_success(),
        .rdusedw(),.wrusedw(),
        .wr_rst_done(write_reset_done),.rd_rst_done(read_reset_done)
    );
endmodule
