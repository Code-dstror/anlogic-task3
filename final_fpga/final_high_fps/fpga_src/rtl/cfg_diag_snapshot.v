`timescale 1ns/1ps
`default_nettype none

// Observer-only bundled-data mailbox. i_data and the independent observer
// reset belong to i_clk. Application resets are payload facts, not this reset.
// The destination owns the four-phase request; no output controls CFG traffic.
// Observer cold reset must reset both handshake endpoints coherently. Local
// business resets must not reset either endpoint of this observer channel.
module cfg_diag_snapshot #(
    parameter integer DATA_WIDTH=192
) (
    input wire i_clk,
    input wire i_observer_rst_n,
    input wire i_request,
    input wire [DATA_WIDTH-1:0] i_data,
    output reg o_ack,
    output reg [DATA_WIDTH-1:0] o_snapshot
);
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] request_sync;

    always @(posedge i_clk or negedge i_observer_rst_n) begin
        if(!i_observer_rst_n) begin
            request_sync<=0;
            o_ack<=0;
        end else begin
            request_sync<={request_sync[0],i_request};
            if(!request_sync[1]) o_ack<=0;
            else if(!o_ack) o_ack<=1;
        end
    end

    // Deliberately unreset: once ACK has entered the destination synchronizer,
    // source reset must not erase the held data behind that ACK. The consumer
    // may use the bank only after synchronized ACK plus one settle edge, and
    // must complete request-low/ACK-low before issuing another request.
    // Integration must constrain this exact bank to its destination bank.
    always @(posedge i_clk) begin
        if(i_observer_rst_n&&request_sync[1]&&!o_ack)
            o_snapshot<=i_data;
    end

    generate if(DATA_WIDTH<1) begin:g_invalid_width
        CFG_DIAG_SNAPSHOT_REQUIRES_POSITIVE_WIDTH invalid_configuration();
    end endgenerate
endmodule
`default_nettype wire
