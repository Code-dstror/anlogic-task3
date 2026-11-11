`timescale 1ns/1ps
// Fixed official ROM ports; legacy INIT parameters do not configure contents.
module jpeg_quant_table_rom #(
    parameter integer LANE=0,
    parameter INIT_ROOT="./quant_data",
    parameter INIT_SUFFIX=".mif"
) (
    input wire i_clk,i_read_enable,i_reciprocal_enable,
    input wire [10:0] i_address,
    output wire [32:0] o_data,
    input wire i_table_enable,
    input wire [10:0] i_table_address,
    output wire [7:0] o_quantizer
);
    wire [9:0] quantizer_data,table_data;
    wire [24:0] reciprocal_data;
    reg [7:0] aligned_quantizer;
    // CE advances the aligned quantizer and reciprocal together.
    always @(posedge i_clk) if(i_reciprocal_enable) aligned_quantizer<=quantizer_data[7:0];
    assign o_data={aligned_quantizer,reciprocal_data};
    assign o_quantizer=table_data[7:0];
    jpeg_quant_recip_rom40x512 u_reciprocal (
        .i_clk(i_clk),.i_read_enable(i_reciprocal_enable),
        .i_quantizer(quantizer_data[7:0]),.o_reciprocal(reciprocal_data));
    jpeg_quant_rom10x2048 #(.LANE(LANE)) u_quantizer (
        .i_clk(i_clk),.i_read_enable(i_read_enable),.i_address(i_address),.o_data(quantizer_data),
        .i_table_enable(i_table_enable),.i_table_address(i_table_address),.o_table_data(table_data));
endmodule
