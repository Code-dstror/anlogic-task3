`timescale 1ns/1ps
`default_nettype none

// Observer-only source mailbox. Inputs must belong to i_clk. The reset is the
// independent observer cold reset, never an application/session reset.
module uart_observer_snapshot (
    input wire i_clk,
    input wire i_rst_n,
    input wire i_request,
    input wire [11:0] i_flags,
    input wire [3:0] i_faults,
    input wire [1:0] i_progress,
    output reg o_ack,
    output reg [47:0] o_snapshot
);
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] request_sync;
    reg [3:0] sticky_faults;
    reg [15:0] progress0,progress1;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            request_sync<=0;o_ack<=0;sticky_faults<=0;progress0<=0;progress1<=0;
        end else begin
            request_sync<={request_sync[0],i_request};
            sticky_faults<=sticky_faults|i_faults;
            if(i_progress[0])progress0<=progress0+1'b1;
            if(i_progress[1])progress1<=progress1+1'b1;
            if(!request_sync[1])o_ack<=0;
            else if(!o_ack)o_ack<=1;
        end
    end
    // No reset on the bundled-data bank. Once ACK is high the entire word
    // stays frozen until the synchronized request is released. A source reset
    // cannot asynchronously erase a word whose ACK is still in flight.
    always @(posedge i_clk) begin
        if(i_rst_n&&request_sync[1]&&!o_ack)
            o_snapshot<={progress1,progress0,sticky_faults,i_flags};
    end
endmodule
`default_nettype wire
