// A single frame owns one physical 40x512 ERAM until record_ready. There is
// no resettable point array, speculative prefetch, or per-point identity.
module lane_candidate_store(
    input wire clk,rst_n,clear,
    input wire write_enable,
    input wire [8:0] write_index,
    input wire [36:0] write_data,
    input wire read_enable,
    input wire [8:0] read_index,
    input wire [8:0] point_count,
    input wire published,
    output wire [39:0] read_data,
    output reg read_valid
);
    wire read_fire=rst_n&&!clear&&published&&read_enable&&read_index<point_count;
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) memory(
        .clk(clk),.wr_en(rst_n&&!clear&&write_enable&&write_index<303),
        .wr_addr(write_index),.wr_data({3'd0,write_data}),
        .rd_en(read_fire),.rd_addr(read_index),.rd_data(read_data));
    always @(posedge clk)begin
        if(!rst_n||clear)read_valid<=0;
        else read_valid<=read_fire;
    end
endmodule
