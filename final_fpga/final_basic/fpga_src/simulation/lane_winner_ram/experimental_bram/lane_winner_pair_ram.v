// One rowbank: twelve54bit pairs in two existing27bit official SDP ERAMs.
// Read latency is one clock. Last-write forwarding resolves same-address
// read/write without depending on the vendor primitive's collision mode.
// clear_row suppresses the old write, invalidates old payload/forwarding, but
// accepts a simultaneous new read as zero for the new row epoch.
module lane_winner_pair_ram(
    input wire clk,rst_n,clear_all,clear_row,
    input wire write_valid,input wire [3:0] write_address,input wire [53:0] write_pair,
    input wire read_enable,input wire [3:0] read_address,
    output reg response_valid,output wire [53:0] response_pair
);
    reg [11:0] row_valid;
    reg last_write_valid;
    reg [3:0] last_write_address,response_address;
    reg [53:0] last_write_pair;
    reg response_written;
    wire run=rst_n&&!clear_all;
    wire write_fire=run&&!clear_row&&write_valid&&write_address<12;
    wire read_fire=run&&read_enable&&read_address<12;
    wire ram_read=read_fire&&!(write_fire&&write_address==read_address);
    wire [53:0] stored;
    td_sdp_ram40 #(.WIDTH(27),.DEPTH(16),.ADDR_WIDTH(4)) low_pair(
        .clk(clk),.wr_en(write_fire),.wr_addr(write_address),.wr_data(write_pair[26:0]),
        .rd_en(ram_read),.rd_addr(read_address),.rd_data(stored[26:0]));
    td_sdp_ram40 #(.WIDTH(27),.DEPTH(16),.ADDR_WIDTH(4)) high_pair(
        .clk(clk),.wr_en(write_fire),.wr_addr(write_address),.wr_data(write_pair[53:27]),
        .rd_en(ram_read),.rd_addr(read_address),.rd_data(stored[53:27]));
    wire forward=last_write_valid&&last_write_address==response_address;
    assign response_pair=!response_valid?54'd0:forward?last_write_pair:response_written?stored:54'd0;
    always @(posedge clk)begin
        if(!rst_n||clear_all)begin
            row_valid<=0;last_write_valid<=0;response_valid<=0;response_written<=0;
        end else begin
            response_valid<=read_fire;
            if(read_fire)begin
                response_address<=read_address;
                response_written<=!clear_row&&row_valid[read_address];
            end
            if(clear_row)begin row_valid<=0;last_write_valid<=0;end
            else if(write_fire)begin
                row_valid[write_address]<=1;
                last_write_valid<=1;last_write_address<=write_address;last_write_pair<=write_pair;
            end
        end
    end
endmodule
