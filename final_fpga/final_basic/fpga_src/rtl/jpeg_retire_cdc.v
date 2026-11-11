`timescale 1ns / 1ps

// Destination retirement protects SENDING beyond enqueue into the record FIFO.
module jpeg_retire_cdc (
    input wire i_dfi_clk, i_dfi_rst_n, i_user_clk, i_user_rst_n,
    input wire i_meta_valid, output wire o_meta_ready,
    input wire [31:0] i_meta_session, i_meta_generation,
    input wire [15:0] i_meta_slot,
    input wire [31:0] i_user_session_id,
    input wire i_user_session_ready, i_host_dma_ready,
    output wire o_destination_armed,
    output wire [31:0] o_destination_session, o_destination_generation,
    output wire [15:0] o_destination_slot,
    input wire i_destination_valid, i_destination_ready, i_destination_last, i_destination_error,
    output wire o_retire_valid, input wire i_retire_ready,
    output wire [31:0] o_retire_session, o_retire_generation,
    output wire [15:0] o_retire_slot,
    output wire o_retire_error,
    output reg o_user_protocol_fault,
    output reg [31:0] o_stale_retire_count
);
    wire paired_reset=i_dfi_rst_n&&i_user_rst_n;
    wire dfi_reset,user_reset;
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(paired_reset),.o_rst_n(dfi_reset));
    reset_release_sync u_user_reset(.i_clk(i_user_clk),.i_async_rst_n(paired_reset),.o_rst_n(user_reset));
    wire [146:0] meta_sink,retire_sink;
    wire meta_ready,meta_valid,meta_sink_ready,return_ready,return_valid,return_sink_ready;
    wire meta_source_done,meta_sink_done,return_source_done,return_sink_done;
    wire dfi_transport_ready=meta_source_done&&return_sink_done;
    wire user_transport_ready=meta_sink_done&&return_source_done;
    reg source_owned,user_owned,return_pending,user_error;
    reg [31:0] source_session,source_generation,user_session,user_generation;
    reg [15:0] source_slot,user_slot;
    wire source_fire=i_meta_valid&&o_meta_ready;
    wire destination_fire=o_destination_armed&&i_destination_valid&&i_destination_ready;
    wire return_matches=source_owned && retire_sink[31:0]==source_session &&
                        retire_sink[63:32]==source_generation && retire_sink[79:64]==source_slot;
    assign o_meta_ready=dfi_reset&&dfi_transport_ready&&!source_owned&&meta_ready;
    assign meta_sink_ready=user_reset&&user_transport_ready&&i_user_session_ready&&!user_owned&&!return_pending&&!o_user_protocol_fault;
    assign o_destination_armed=user_reset&&user_transport_ready&&user_owned&&!return_pending&&!o_user_protocol_fault&&
        i_user_session_ready&&i_host_dma_ready&&user_session==i_user_session_id;
    assign o_destination_session=user_session;assign o_destination_generation=user_generation;assign o_destination_slot=user_slot;
    assign o_retire_valid=dfi_reset&&dfi_transport_ready&&return_valid&&return_matches;
    assign return_sink_ready=dfi_reset&&dfi_transport_ready&&(return_matches?i_retire_ready:1'b1);
    assign o_retire_session=retire_sink[31:0];assign o_retire_generation=retire_sink[63:32];
    assign o_retire_slot=retire_sink[79:64];assign o_retire_error=retire_sink[80];
    // Complete outer messages are captured once and assembled before exposure.
    // The inherited full-width padding preserves the exact token layout.
    control_message_fifo_ip #(.MESSAGE_WIDTH(147)) u_metadata_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_reset),.i_source_data({67'd0,i_meta_slot,i_meta_generation,i_meta_session}),
        .i_source_valid(i_meta_valid&&!source_owned&&dfi_transport_ready),.o_source_ready(meta_ready),.o_source_reset_done(meta_source_done),
        .i_sink_clk(i_user_clk),.i_sink_rst_n(user_reset),.o_sink_data(meta_sink),.o_sink_valid(meta_valid),
        .i_sink_ready(meta_sink_ready),.o_sink_reset_done(meta_sink_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(147)) u_retire_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_user_clk),.i_source_rst_n(user_reset),.i_source_data({66'd0,user_error,user_slot,user_generation,user_session}),
        .i_source_valid(return_pending&&user_transport_ready),.o_source_ready(return_ready),.o_source_reset_done(return_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(dfi_reset),.o_sink_data(retire_sink),.o_sink_valid(return_valid),
        .i_sink_ready(return_sink_ready),.o_sink_reset_done(return_sink_done));
    always @(posedge i_dfi_clk or negedge dfi_reset) begin
        if(!dfi_reset) begin source_owned<=0;source_session<=0;source_generation<=0;source_slot<=0;o_stale_retire_count<=0;end
        else begin
            if(source_fire) begin source_owned<=1;source_session<=i_meta_session;source_generation<=i_meta_generation;source_slot<=i_meta_slot;end
            if(return_valid&&return_sink_ready) begin
                if(return_matches) source_owned<=0;else o_stale_retire_count<=o_stale_retire_count+1'b1;
            end
        end
    end
    always @(posedge i_user_clk or negedge user_reset) begin
        if(!user_reset) begin user_owned<=0;return_pending<=0;user_error<=0;user_session<=0;user_generation<=0;user_slot<=0;o_user_protocol_fault<=0;end
        else begin
            if(meta_valid&&meta_sink_ready) begin
                user_owned<=1;user_session<=meta_sink[31:0];user_generation<=meta_sink[63:32];user_slot<=meta_sink[79:64];user_error<=0;
                if(meta_sink[31:0]!=i_user_session_id || meta_sink[63:32]==0 || meta_sink[79:64]>=6) o_user_protocol_fault<=1;
            end
            if(user_owned && (!i_user_session_ready || user_session!=i_user_session_id)) o_user_protocol_fault<=1;
            if(destination_fire) begin
                if(i_destination_error) user_error<=1;
                if(i_destination_last) begin return_pending<=1;user_error<=user_error||i_destination_error;end
            end
            if(return_pending&&user_transport_ready&&return_ready) begin return_pending<=0;user_owned<=0;end
        end
    end
endmodule
