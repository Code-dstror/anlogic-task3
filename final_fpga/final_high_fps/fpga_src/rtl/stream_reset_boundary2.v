`timescale 1ns/1ps
// Two pure-clocked register entries isolate a RAM kernel from an asynchronous
// publication fence. EXTERNAL_SOURCE selects which handshake is masked.
module stream_reset_boundary2 #(
    parameter integer WIDTH=98,
    parameter integer EXTERNAL_SOURCE=1
)(
    input wire clk,run_n,async_n,
    input wire [WIDTH-1:0] s_data,input wire s_valid,output wire s_ready,
    output wire [WIDTH-1:0] m_data,output wire m_valid,input wire m_ready,
    output wire pending
);
    reg [WIDTH-1:0] storage0,storage1;
    (* preserve="true" *) reg [1:0] count=0;
    reg write_index=0,read_index=0;
    wire push=s_valid&&s_ready;
    wire pop=m_valid&&m_ready;
    assign s_ready=run_n&&count<2&&(EXTERNAL_SOURCE==0||async_n);
    assign m_valid=run_n&&count!=0&&(EXTERNAL_SOURCE!=0||async_n);
    assign m_data=read_index ? storage1 : storage0;
    assign pending=run_n&&count!=0;
    // Assertion only withdraws the external interface immediately. The
    // register ledger is cleared at a real edge; its kernel-facing signals
    // never acquire asynchronous reset or READY propagation from the fence.
    always @(posedge clk)begin
        if(!run_n||!async_n)begin count<=0;write_index<=0;read_index<=0;end
        else begin
            if(push)begin
                if(write_index)storage1<=s_data;
                else storage0<=s_data;
                write_index<=~write_index;
            end
            if(pop)read_index<=~read_index;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
        end
    end
endmodule
