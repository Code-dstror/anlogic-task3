`timescale 1ns/1ps
// Borrow the original SOURCE head until each real kernel consumer accepts it.
// Only its narrow key crosses the synchronous publication boundary.
module source_terminal_sync_boundary #(
    parameter integer WIDTH=98
)(
    input wire clk,run_n,async_n,frame_begin,
    input wire [1:0] s_valid,s_cancel,output wire [1:0] s_ready,
    input wire [WIDTH-1:0] s_key,
    output wire [1:0] m_valid,m_cancel,input wire [1:0] m_ready,
    output wire [WIDTH-1:0] m_key
);
    (* preserve="true" *) reg [1:0] pending=0,taken=0,seen=0,cancel_q=0;
    reg [WIDTH-1:0] key_q;
    wire [1:0] capture=s_valid&~seen;
    assign s_ready={2{async_n&&run_n}}&taken;
    assign m_valid={2{run_n}}&pending;
    assign m_cancel={2{run_n}}&cancel_q;
    assign m_key=key_q;
    always @(posedge clk)begin
        if(!run_n||!async_n||frame_begin)begin
            pending<=0;taken<=0;seen<=0;cancel_q<=0;
        end else begin
            cancel_q<=s_cancel;
            // The upstream broadcast qualifies VALID with the kernel's
            // owner-match, which itself reads this key. Preload the borrowed
            // head before VALID; freeze it after the first offered consumer.
            if(seen==0)key_q<=s_key;
            pending<=(pending&~m_ready)|capture;
            // READY acknowledges a real inner take, never mere enqueue.
            taken<=taken|(pending&m_ready);
            seen<=seen|capture;
        end
    end
endmodule
