`timescale 1ns/1ps
// BUILD uses only A(original RAW) and B(candidate); no FETCH bank is exposed.
module cfs_snapshot_cache2(
    input wire i_clk,
    input wire [1:0] i_write_enable,
    input wire [19:0] i_write_address,
    input wire [63:0] i_write_data,
    input wire [1:0] i_read_enable,
    input wire [19:0] i_read_address,
    output wire [63:0] o_read_data
);
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1) begin : cache_bank
        td_sdp_ram #(.WIDTH(20),.DEPTH(640),.ADDR_WIDTH(10)) u_low(
            .clk(i_clk),.wr_en(i_write_enable[bank]),
            .wr_addr(i_write_address[bank*10+:10]),.wr_data(i_write_data[bank*32+:20]),
            .rd_en(i_read_enable[bank]),.rd_addr(i_read_address[bank*10+:10]),
            .rd_data(o_read_data[bank*32+:20]));
        td_sdp_ram #(.WIDTH(12),.DEPTH(640),.ADDR_WIDTH(10)) u_high(
            .clk(i_clk),.wr_en(i_write_enable[bank]),
            .wr_addr(i_write_address[bank*10+:10]),.wr_data(i_write_data[bank*32+20+:12]),
            .rd_en(i_read_enable[bank]),.rd_addr(i_read_address[bank*10+:10]),
            .rd_data(o_read_data[bank*32+20+:12]));
    end endgenerate
endmodule
