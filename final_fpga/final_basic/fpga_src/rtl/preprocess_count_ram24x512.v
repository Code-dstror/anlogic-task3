// Histogram bank and bin form a nine-bit address; payload uses official ERAM.
module preprocess_count_ram24x512 (
    input wire clk, wr_en, rd_en,
    input wire [8:0] wr_addr, rd_addr,
    input wire [23:0] wr_data,
    output wire [23:0] rd_data
);
    // The caller forwards this previous increment for a consecutive same-bin
    // request. Suppress the undefined physical collision; do not latch its X
    // output/collision state into later noncolliding background reads.
    wire read_collision=wr_en && rd_en && wr_addr==rd_addr;
    td_sdp_ram40 #(.WIDTH(24),.DEPTH(512),.ADDR_WIDTH(9)) u_count (
        .clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data),
        .rd_en(rd_en && !read_collision),.rd_addr(rd_addr),.rd_data(rd_data));
endmodule
