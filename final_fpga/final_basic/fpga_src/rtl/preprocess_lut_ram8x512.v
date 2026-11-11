module preprocess_lut_ram8x512 #(parameter integer EYES=1) (
    input wire clk, wr_en, rd_en,
    input wire [9:0] wr_addr, rd_addr,
    input wire [7:0] wr_data,
    output wire [7:0] rd_data
);
    localparam ADDR_BITS = EYES == 2 ? 10 : 9;
    td_sdp_ram #(.WIDTH(8),.DEPTH(512*EYES),.ADDR_WIDTH(ADDR_BITS)) u_ram (
        .clk(clk),.wr_en(wr_en),.wr_addr(wr_addr[ADDR_BITS-1:0]),.wr_data(wr_data),
        .rd_en(rd_en),.rd_addr(rd_addr[ADDR_BITS-1:0]),.rd_data(rd_data));
endmodule
