// One rowbank, twelve54bit pairs. Two identical official distributed-RAM
// copies provide independent asynchronous RMW and selector reads. Writes
// are clocked; only the twelve logical-valid bits are cleared per row.
module lane_winner_pair_lutram(
    input wire clk,rst_n,clear_all,clear_row,
    input wire write_valid,input wire [3:0] write_address,input wire [53:0] write_pair,
    input wire [3:0] rmw_address,selector_address,
    output wire [53:0] rmw_pair,selector_pair
);
    reg [11:0] row_valid;
    wire write_fire=rst_n&&!clear_all&&!clear_row&&write_valid&&write_address<12;
    wire [53:0] stored_rmw,stored_selector;
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(54),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(54),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.READREG("DISABLE"),.RESETMODE("SYNC")
    ) rmw_copy(
        .di(write_pair),.waddr(write_address),.we(write_fire),.wclk(clk),
        .raddr(rmw_address),.rdo(stored_rmw),.rdoq(),.rclk(clk),.rrst(1'b0),.rce(1'b0));
    PH1_LOGIC_DRAM #(
        .DATA_WIDTH_W(54),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
        .DATA_WIDTH_R(54),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
        .INIT_FILE("NONE"),.FILL_ALL("NONE"),.READREG("DISABLE"),.RESETMODE("SYNC")
    ) selector_copy(
        .di(write_pair),.waddr(write_address),.we(write_fire),.wclk(clk),
        .raddr(selector_address),.rdo(stored_selector),.rdoq(),.rclk(clk),.rrst(1'b0),.rce(1'b0));
    assign rmw_pair=rmw_address<12&&row_valid[rmw_address]?stored_rmw:54'd0;
    assign selector_pair=selector_address<12&&row_valid[selector_address]?stored_selector:54'd0;
    always @(posedge clk)begin
        if(!rst_n||clear_all||clear_row)row_valid<=0;
        else if(write_fire)row_valid[write_address]<=1;
    end
endmodule
