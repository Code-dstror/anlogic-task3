`timescale 1ns/1ps
// Fixed official SDP40x512 reciprocal contents. CEA=0 prevents all writes.
module jpeg_quant_recip_rom40x512 (
    input wire i_clk,i_read_enable,
    input wire [7:0] i_quantizer,
    output wire [24:0] o_reciprocal
);
    wire [39:0] reciprocal_data;
    jpeg_rom_recip u_rom (
        .clka(i_clk),.cea(1'b0),.dia(40'd0),.addra(9'd0),
        .ceb(i_read_enable),.addrb({1'b0,i_quantizer}),.dob(reciprocal_data));
    assign o_reciprocal = reciprocal_data[24:0];
endmodule
