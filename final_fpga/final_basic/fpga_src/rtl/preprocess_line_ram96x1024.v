// RGB888 four-pixel line storage. The existing generated PH1 ERAM IP supplies
// one synchronous read cycle and holds its output while rd_en is low.
module preprocess_line_ram96x1024 (
    input clk,
    input wr_en,
    input [9:0] wr_addr,
    input [95:0] wr_data,
    input rd_en,
    input [9:0] rd_addr,
    output [95:0] rd_data
);
    wire [99:0] padded_write = {4'd0, wr_data};
    wire [99:0] padded_read;
    assign rd_data = padded_read[95:0];

    genvar slice;
    generate
        for (slice = 0; slice < 5; slice = slice + 1) begin : g_eram
            isp_line_ram_20x1024 u_slice (
                .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr),
                .wr_data(padded_write[slice*20 +: 20]),
                .rd_en(rd_en), .rd_addr(rd_addr),
                .rd_data(padded_read[slice*20 +: 20])
            );
        end
    endgenerate
endmodule
