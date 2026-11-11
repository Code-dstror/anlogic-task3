`timescale 1ns / 1ps
// Eight lanes of the already-reviewed official 16x16 registered distributed RAM.
// Only addresses 0..7 are used. There is no inferred array or RAM content reset.
module c2h_packet_ram (
    input wire i_clk, input wire i_write,
    input wire [2:0] i_write_address, input wire [127:0] i_write_data,
    input wire i_read, input wire [2:0] i_read_address,
    output wire [127:0] o_read_data
);
    genvar lane;
    generate for (lane=0; lane<8; lane=lane+1) begin : g_lane
        td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),.DISTRIBUTED_ENABLE(1)) memory (
            .clk(i_clk),.wr_en(i_write),.wr_addr({1'b0,i_write_address}),
            .wr_data(i_write_data[lane*16 +: 16]),.rd_en(i_read),
            .rd_addr({1'b0,i_read_address}),.rd_data(o_read_data[lane*16 +: 16])
        );
    end endgenerate
endmodule
