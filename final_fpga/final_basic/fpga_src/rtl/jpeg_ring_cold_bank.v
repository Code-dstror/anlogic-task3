`timescale 1ns/1ps
// One small read view of the cold descriptor. Four logical words keep their
// independent writes; physical storage uses existing 16x16 official DRAM.
// A read/write collision is not sent to the RAM: the
// already-updated single writer tuple supplies exactly that return word.
module jpeg_ring_cold_bank #(parameter integer FORWARD_LIVE_WRITER=0) (
    input wire clk,rst_n,
    input wire [3:0] write_enable,
    input wire [2:0] write_address,
    input wire [128:0] write_data,hot_data,
    input wire read_enable,
    input wire [2:0] read_address,
    output wire [128:0] read_data
);
    reg [3:0] forwarded;
    // A one-clock delayed writer mirror is authoritative in hot_data while
    // its owner is selected, even before the pending write reaches RAM.
    wire [3:0] collision=(FORWARD_LIVE_WRITER!=0 ? 4'hf : write_enable) &
                         {4{write_address==read_address}};
    wire [128:0] ram_data;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)forwarded<=0;
        else forwarded<=read_enable ? collision : 4'd0;
    end
    genvar word,lane;
    generate for(word=0;word<4;word=word+1)begin:words
        localparam integer BITS=word==3 ? 33 : 32;
        localparam integer LANES=(BITS+15)/16;
        wire [LANES*16-1:0] write_word={{(LANES*16-BITS){1'b0}},write_data[word*32+:BITS]};
        wire [LANES*16-1:0] read_word;
        for(lane=0;lane<LANES;lane=lane+1)begin:lanes
            td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),.DISTRIBUTED_ENABLE(1)) ram(
                .clk(clk),.wr_en(write_enable[word]),.wr_addr({1'b0,write_address}),
                .wr_data(write_word[lane*16+:16]),
                .rd_en(read_enable && !collision[word]),.rd_addr({1'b0,read_address}),
                .rd_data(read_word[lane*16+:16]));
        end
        assign ram_data[word*32+:BITS]=read_word[BITS-1:0];
        assign read_data[word*32+:BITS]=forwarded[word] ? hot_data[word*32+:BITS] : ram_data[word*32+:BITS];
    end endgenerate
endmodule
