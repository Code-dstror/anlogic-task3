`timescale 1ns/1ps
`default_nettype none
// One-way cold ownership transfer. Only sys_clk/POR owns these controls;
// PCIe app_enable/soft_reset and C2H STOP/fence/ACK remain their real owners.
// LOCAL maintenance is available only in the separately selected UART image.
module stage3_production_boot (
    input wire i_clk,
    output wire o_debug_rst_n,
    output wire o_app_rst_n,
    output wire o_local,
    output wire o_run
);
    reg [9:0] por_count = 0;
    reg por_done = 0;
    reg [9:0] app_count = 10'd1023;
    assign o_debug_rst_n = por_done;
    // The endpoint may enumerate while the application is still reset.
    // This is not host-buffer authorization: app_enable and grant remain off.
    assign o_local = !por_done;
    assign o_run = 1'b0;
    assign o_app_rst_n = por_done && app_count == 0;
    always @(posedge i_clk) begin
        if (!por_done) begin
            por_count <= por_count + 1'b1;
            if (&por_count) por_done <= 1'b1;
            app_count <= 10'd1023;
        end else if (app_count != 0) app_count <= app_count - 1'b1;
    end
endmodule
`default_nettype wire
