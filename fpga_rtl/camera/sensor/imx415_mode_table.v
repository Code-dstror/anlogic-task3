`timescale 1ns / 1ps
// Reference sensor table with explicit 24 MHz INCK / 720 Mb/s lane timing.
// The table is combinational control decode; it is not an inferred RAM.
module imx415_mode_table #(
    parameter integer MODE_4K = 0
) (
    input wire [7:0] i_index,
    output wire [23:0] o_register
);
    wire [31:0] baseline;
    wire [7:0] table_size;
    reg [7:0] value;
    ui_imx415reg u_reference (
        .MODE(MODE_4K ? 2'd1 : 2'd0),
        .REG_INDEX({1'b0,i_index}), .REG_DATA(baseline), .REG_SIZE(table_size)
    );
    always @(*) begin
        value = baseline[7:0];
        case (baseline[23:8])
            16'h3008: value = 8'h54;
            16'h300A: value = 8'h3B;
            16'h300B: value = 8'h00;
            16'h3024: value = 8'hCA; // VMAX=2250 in both modes
            16'h3025: value = 8'h08;
            16'h3028: value = MODE_4K ? 8'h2A : 8'h15;
            16'h3029: value = MODE_4K ? 8'h04 : 8'h02;
            16'h3033: value = 8'h09;
            16'h3118: value = 8'hB4;
            16'h311A: value = 8'hFC;
            16'h4004: value = 8'h00;
            16'h400C: value = 8'h00;
            16'h4018: value = 8'h6F;
            16'h401A: value = 8'h2F;
            16'h401C: value = 8'h2F;
            16'h401E: value = 8'hBF;
            16'h401F: value = 8'h00;
            16'h4020: value = 8'h2F;
            16'h4022: value = 8'h57;
            16'h4024: value = 8'h2F;
            16'h4026: value = 8'h4F;
            16'h4028: value = 8'h27;
            16'h4074: value = 8'h01;
            default: value = baseline[7:0];
        endcase
    end
    assign o_register = {baseline[23:8],value};
endmodule
