`timescale 1ns / 1ps
`default_nettype none

// One session timebase. Cross registered unit-count Gray code, then scale to ns.
// See the spec for the required per-bit physical delay bounds and reset cohort.
module frame_common_time_cdc (
    input wire i_source_clk, i_source_rst_n,
    input wire i_sink0_clk, i_sink0_rst_n,
    input wire i_sink1_clk, i_sink1_rst_n,
    output wire [63:0] o_source_ns,
    output wire o_source_valid,
    output wire o_source_overflow,
    output wire [63:0] o_sink0_ns, o_sink1_ns,
    output wire o_sink0_valid, o_sink1_valid
);
    // All participants must abandon the previous session before its clock resets.
    wire cohort_rst_n=i_source_rst_n && i_sink0_rst_n && i_sink1_rst_n;
    wire source_rst_n,sink0_rst_n,sink1_rst_n;
    reset_release_sync u_source_reset(.i_clk(i_source_clk),
        .i_async_rst_n(cohort_rst_n),.o_rst_n(source_rst_n));
    reset_release_sync u_sink0_reset(.i_clk(i_sink0_clk),
        .i_async_rst_n(cohort_rst_n),.o_rst_n(sink0_rst_n));
    reset_release_sync u_sink1_reset(.i_clk(i_sink1_clk),
        .i_async_rst_n(cohort_rst_n),.o_rst_n(sink1_rst_n));

    reg [60:0] source_units,source_gray;
    wire [60:0] next_units=source_units+61'd1;
    assign o_source_ns={source_units,3'b000};
    // 64-bit nanoseconds wrap only after about 584 years. The video platform
    // cold-starts long before that; do not distribute a century-scale overflow
    // latch as an enable across the counter, Gray publisher and both receivers.
    // Keep the existing status port ABI; the timebase now advances modulo 2^64.
    assign o_source_overflow=1'b0;
    assign o_source_valid=source_rst_n;
    always @(posedge i_source_clk or negedge source_rst_n) begin
        if(!source_rst_n) begin source_units<=0;source_gray<=0;end
        else begin
            source_units<=next_units;
            source_gray<=next_units ^ (next_units >> 1);
        end
    end
    frame_common_time_receiver u_sink0(
        .clk(i_sink0_clk),.rst_n(sink0_rst_n),.i_gray(source_gray),
        .i_source_ready(source_rst_n),
        .o_time_ns(o_sink0_ns),.o_valid(o_sink0_valid));
    frame_common_time_receiver u_sink1(
        .clk(i_sink1_clk),.rst_n(sink1_rst_n),.i_gray(source_gray),
        .i_source_ready(source_rst_n),
        .o_time_ns(o_sink1_ns),.o_valid(o_sink1_valid));
endmodule

module frame_common_time_receiver (
    input wire clk,rst_n,
    input wire [60:0] i_gray,
    input wire i_source_ready,
    output reg [63:0] o_time_ns,
    output reg o_valid
);
    reg [60:0] gray_meta,gray_sync;
    reg ready_meta,ready_sync;
    wire [60:0] decoded_units;
    genvar bit_index;
    generate for(bit_index=0;bit_index<61;bit_index=bit_index+1) begin : decode
        // Static reduction permits a balanced XOR tree instead of a ripple XOR.
        assign decoded_units[bit_index]=^gray_sync[60:bit_index];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            gray_meta<=0;gray_sync<=0;ready_meta<=0;ready_sync<=0;
            o_time_ns<=0;o_valid<=0;
        end else begin
            gray_meta<=i_gray;gray_sync<=gray_meta;
            ready_meta<=i_source_ready;ready_sync<=ready_meta;
            o_valid<=ready_sync;
            if(ready_sync) o_time_ns<={decoded_units,3'b000};
        end
    end
endmodule
`default_nettype wire
