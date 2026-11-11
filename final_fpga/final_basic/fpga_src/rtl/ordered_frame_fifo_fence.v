`timescale 1ns/1ps
// The same official147-bit FIFO carries a private tail marker after the paused,
// idle producer's final real token. No payload FIFO or wide context bank is added.
// RAW's existing source count is borrowed through the marker handshake; pause
// must freeze that counter and session until the matching proof returns.
module ordered_frame_fifo_fence (
    input wire i_source_clk,i_source_rst_n,
    input wire [146:0] i_source_data,input wire i_source_valid,
    output wire o_source_ready,output wire o_source_reset_done,
    input wire i_sink_clk,i_sink_rst_n,
    output wire [146:0] o_sink_data,output wire o_sink_valid,
    input wire i_sink_ready,output wire o_sink_reset_done,
    input wire i_fence_request,i_source_idle,input wire [31:0] i_source_session,
    input wire [63:0] i_raw_enqueued,
    input wire i_sink_quiet,input wire [31:0] i_sink_session,
    input wire [63:0] i_raw_consumed,input wire i_raw_consume_fire,
    output wire o_source_proven,output wire o_source_fault,output wire o_sink_fault
);
    localparam [31:0] MARKER=32'h44524e31;
    wire [146:0] fifo_out;
    wire fifo_valid,fifo_ready,fifo_write_ready;
    reg offered,sent,expected_ack,acknowledged;
    reg source_held,sink_held;
    reg source_fault,sink_fault,ack_toggle;
    (* ASYNC_REG="TRUE" *) reg [1:0] ack_sync,sink_fault_sync,source_fault_sync;
    wire locked=offered||sent;
    wire [146:0] marker={2'b00,1'b1,16'd0,MARKER,i_source_session,i_raw_enqueued};
    wire marker_shape=fifo_out[146:145]==0&&fifo_out[143:128]==0;
    wire marker_ok=fifo_out[144]&&fifo_out[127:96]==MARKER&&
        fifo_out[95:64]!=0&&fifo_out[95:64]==i_sink_session;
    wire marker_fire=fifo_valid&&marker_shape&&fifo_ready;
    assign o_source_fault=source_fault||sink_fault_sync[1];
    assign o_sink_fault=sink_fault||source_fault_sync[1];
    wire payload_write=i_source_valid&&!locked&&(!o_source_fault||source_held);
    assign o_source_ready=fifo_write_ready&&!locked&&(!o_source_fault||source_held);
    assign o_source_proven=sent&&acknowledged&&!o_source_fault&&i_source_idle&&!i_source_valid;
    assign o_sink_data=fifo_out;
    assign o_sink_valid=fifo_valid&&!marker_shape&&(!o_sink_fault||sink_held);
    assign fifo_ready=marker_shape ?
        (!o_sink_fault&&marker_ok&&i_raw_consumed==fifo_out[63:0]&&
         !i_raw_consume_fire&&i_sink_quiet) : o_sink_valid&&i_sink_ready;
    axis_frame_fifo_ip fifo(
        .i_source_clk(i_source_clk),.i_source_rst_n(i_source_rst_n),
        .i_source_data(offered?marker:i_source_data),
        .i_source_valid(offered||payload_write),
        .o_source_ready(fifo_write_ready),.o_source_reset_done(o_source_reset_done),
        .i_sink_clk(i_sink_clk),.i_sink_rst_n(i_sink_rst_n),
        .o_sink_data(fifo_out),.o_sink_valid(fifo_valid),
        .i_sink_ready(fifo_ready),.o_sink_reset_done(o_sink_reset_done));
    always @(posedge i_source_clk or negedge i_source_rst_n)begin
        if(!i_source_rst_n)begin
            offered<=0;sent<=0;expected_ack<=0;acknowledged<=0;
            source_fault<=0;ack_sync<=0;sink_fault_sync<=0;source_held<=0;
        end else begin
            ack_sync<={ack_sync[0],ack_toggle};sink_fault_sync<={sink_fault_sync[0],sink_fault};
            if(payload_write&&!fifo_write_ready)source_held<=1;
            if(payload_write&&fifo_write_ready)source_held<=0;
            if(i_fence_request&&!locked&&!i_source_valid&&i_source_idle&&o_source_reset_done&&!o_source_fault)begin
                if(i_source_session==0)source_fault<=1;
                else offered<=1;
            end
            if(offered&&fifo_write_ready)begin offered<=0;sent<=1;expected_ack<=!expected_ack;end
            if(sent&&ack_sync[1]==expected_ack)acknowledged<=1;
            if(locked&&i_source_valid)source_fault<=1;
            if(!i_fence_request&&locked)begin
                if(acknowledged)begin sent<=0;acknowledged<=0;end
                else source_fault<=1;
            end
        end
    end
    always @(posedge i_sink_clk or negedge i_sink_rst_n)begin
        if(!i_sink_rst_n)begin sink_fault<=0;ack_toggle<=0;source_fault_sync<=0;sink_held<=0;end
        else begin
            source_fault_sync<={source_fault_sync[0],source_fault};
            if(o_sink_valid&&!i_sink_ready)sink_held<=1;
            if(o_sink_valid&&i_sink_ready)sink_held<=0;
            if(fifo_valid&&marker_shape&&(!marker_ok||i_raw_consumed>fifo_out[63:0]))sink_fault<=1;
            if(marker_fire)ack_toggle<=!ack_toggle;
        end
    end
endmodule
