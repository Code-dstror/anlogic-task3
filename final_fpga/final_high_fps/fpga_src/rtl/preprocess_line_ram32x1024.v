// Preserve the synchronous row interface while selecting a fitting official IP.
module preprocess_line_ram32x1024 #(
    parameter integer DEPTH = 1024
) (
    input wire clk, wr_en, rd_en,
    input wire [9:0] wr_addr, rd_addr,
    input wire [31:0] wr_data,
    output wire [31:0] rd_data
);
    generate if (DEPTH <= 512) begin : compact
        // Qualify the full logical address before narrowing it; bit9 must never
        // alias an invalid access onto the first physical 512-word bank.
        td_sdp_ram40 #(.WIDTH(32),.DEPTH(DEPTH),.ADDR_WIDTH(9)) u_ram (
            .clk(clk),.wr_en(wr_en && wr_addr < DEPTH),.wr_addr(wr_addr[8:0]),
            .wr_data(wr_data),.rd_en(rd_en && rd_addr < DEPTH),
            .rd_addr(rd_addr[8:0]),.rd_data(rd_data));
    end else begin : full_depth
    td_sdp_ram #(.WIDTH(20),.DEPTH(DEPTH),.ADDR_WIDTH(10)) u_low (
        .clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data[19:0]),
        .rd_en(rd_en),.rd_addr(rd_addr),.rd_data(rd_data[19:0]));
    td_sdp_ram #(.WIDTH(12),.DEPTH(DEPTH),.ADDR_WIDTH(10)) u_high (
        .clk(clk),.wr_en(wr_en),.wr_addr(wr_addr),.wr_data(wr_data[31:20]),
        .rd_en(rd_en),.rd_addr(rd_addr),.rd_data(rd_data[31:20]));
    end endgenerate
    generate if (DEPTH < 1 || DEPTH > 1024) begin : invalid_depth
        PREPROCESS_ROW_DEPTH_MUST_BE_1_TO_1024 invalid_configuration();
    end endgenerate
endmodule
