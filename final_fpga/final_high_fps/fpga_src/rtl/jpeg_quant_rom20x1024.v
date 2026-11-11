`timescale 1ns/1ps
// Fixed official DP20x1024 AC Huffman contents; both write ports disabled.
module jpeg_quant_rom20x1024 (
    input wire i_clk,i_read_enable,
    input wire [9:0] i_address,
    output wire [19:0] o_data,
    input wire i_table_enable,
    input wire [9:0] i_table_address,
    output wire [19:0] o_table_data
);
    jpeg_rom_huff u_rom (
        .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
        .dia(20'd0),.wea(1'b0),.ceb(i_table_enable),
        .addrb(i_table_address),.dob(o_table_data),.dib(20'd0),.web(1'b0));
endmodule
