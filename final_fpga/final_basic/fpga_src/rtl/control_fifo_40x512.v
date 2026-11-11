`timescale 1ns / 1ps

// Port-only adapter to the official TD-generated, GUI-manageable configuration.
module control_fifo_40x512 (
    input wire [39:0] di,
    input wire clkr, rrst, re,
    input wire clkw, wrst, we,
    output wire [39:0] dout,
    output wire empty_flag, aempty, full_flag, afull, valid,
    output wire overflow, underflow, wr_success,
    output wire [9:0] rdusedw, wrusedw,
    output wire wr_rst_done, rd_rst_done
);
    camera_control_fifo_40x512 u_configured_ip (
        .clkr(clkr), .rrst(rrst), .re(re),
        .clkw(clkw), .wrst(wrst), .we(we), .di(di), .dout(dout),
        .empty_flag(empty_flag), .aempty(aempty),
        .full_flag(full_flag), .afull(afull), .valid(valid),
        .overflow(overflow), .underflow(underflow), .wr_success(wr_success),
        .rdusedw(rdusedw), .wrusedw(wrusedw),
        .wr_rst_done(wr_rst_done), .rd_rst_done(rd_rst_done)
    );
endmodule
