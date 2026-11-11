// One histogram update lane, two logical banks in official 512x24 ERAM.
// Same-address forwarding covers READBEFOREWRITE and consecutive increments.
module preprocess_hist_lane #(
    parameter integer COUNT_BITS=24,
    parameter integer UNIT_INCREMENT=0
) (
    input wire clk, cancel,
    input wire inc_valid, inc_bank,
    input wire [7:0] inc_bin,
    input wire [2:0] inc_amount,
    input wire bg_rd_en, bg_rd_bank,
    input wire [7:0] bg_rd_addr,
    output wire [23:0] bg_rd_data,
    input wire clear_en, clear_bank,
    input wire [7:0] clear_addr,
    output reg overflow
);
    reg pending, last_valid;
    reg [8:0] pending_addr, last_addr;
    reg [2:0] pending_amount;
    reg [COUNT_BITS-1:0] last_count;
    wire [23:0] read_data;
    wire [COUNT_BITS-1:0] old_count = last_valid && last_addr == pending_addr ? last_count : read_data[COUNT_BITS-1:0];
    wire [COUNT_BITS:0] total = {1'b0,old_count} + (UNIT_INCREMENT ? 1'b1 : pending_amount);
    wire [COUNT_BITS-1:0] incremented = total[COUNT_BITS] ? {COUNT_BITS{1'b1}} : total[COUNT_BITS-1:0];
    wire write_increment = pending && !cancel;
    preprocess_count_ram24x512 u_ram (
        .clk(clk),.wr_en(write_increment || (clear_en && !cancel)),
        .wr_addr(write_increment ? pending_addr : {clear_bank,clear_addr}),
        .wr_data(write_increment ? {{(24-COUNT_BITS){1'b0}},incremented} : 24'd0),
        .rd_en(!cancel && (inc_valid || bg_rd_en)),
        .rd_addr(inc_valid ? {inc_bank,inc_bin} : {bg_rd_bank,bg_rd_addr}),
        .rd_data(read_data));
    assign bg_rd_data = read_data;
    always @(posedge clk) begin
        if (cancel) begin
            pending <= 1'b0; last_valid <= 1'b0; overflow <= 1'b0;
            pending_addr <= 9'd0; last_addr <= 9'd0;
            pending_amount <= 3'd0; last_count <= 0;
        end else begin
            overflow <= pending && total[COUNT_BITS];
            pending <= inc_valid;
            if (inc_valid) begin
                pending_addr <= {inc_bank,inc_bin};
                pending_amount <= inc_amount;
            end
            if (write_increment) begin
                last_valid <= 1'b1; last_addr <= pending_addr; last_count <= incremented;
            end else if (clear_en) last_valid <= 1'b0;
        end
    end
endmodule
