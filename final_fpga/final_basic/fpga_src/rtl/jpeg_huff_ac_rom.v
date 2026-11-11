// Two synchronous AC Huffman reads share one official PH1 ERAM.
module jpeg_huff_ac_rom #(
    // Legacy caller compatibility only; IPC fixes the hardware contents.
    parameter INIT_FILE = "NONE"
) (
    input wire i_clk,
    input wire i_read_enable,
    input wire i_chroma,
    input wire [7:0] i_symbol0,
    input wire [7:0] i_symbol1,
    output wire [15:0] o_code0,
    output wire [15:0] o_code1,
    output wire [4:0] o_length0,
    output wire [4:0] o_length1
);
    wire [19:0] entry0, entry1;
    jpeg_quant_rom20x1024 u_rom (
        .i_clk(i_clk),.i_read_enable(i_read_enable),
        .i_address({1'b0,i_chroma,i_symbol0}),.o_data(entry0),
        .i_table_enable(i_read_enable),
        .i_table_address({1'b0,i_chroma,i_symbol1}),.o_table_data(entry1));
    assign o_code0 = entry0[15:0];
    assign o_code1 = entry1[15:0];
    // Length16 is encoded as nibble0; all-zero is the invalid sentinel.
    assign o_length0 = entry0[19:16] != 0 ? {1'b0,entry0[19:16]} :
                       entry0[15:0] != 0 ? 5'd16 : 5'd0;
    assign o_length1 = entry1[19:16] != 0 ? {1'b0,entry1[19:16]} :
                       entry1[15:0] != 0 ? 5'd16 : 5'd0;
endmodule
