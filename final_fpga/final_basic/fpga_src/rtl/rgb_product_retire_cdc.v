`timescale 1ns / 1ps
// Full product identity binds one real writer START to its final write result.
module rgb_product_retire_cdc (
    input wire i_pixel_clk, i_pixel_rst_n, i_dfi_clk, i_dfi_rst_n,
    input wire [575:0] s_bind_context,
    input wire [31:0] s_bind_writer_tag,
    input wire s_bind_valid,
    output wire s_bind_ready,
    output wire o_pixel_reset_done, o_dfi_reset_done,
    output wire o_pixel_owned,
    output wire o_bind_ready,
    output wire [575:0] o_bind_context,
    output wire [31:0] o_bind_writer_tag,
    input wire i_writer_start_fire,
    input wire s_write_valid,
    output wire s_write_ready,
    input wire [31:0] s_write_tag, s_write_sequence, s_write_session, s_write_epoch,
    input wire s_write_camera, s_write_ok,
    input wire [7:0] s_write_error,
    output reg [31:0] o_stale_write_count,
    output reg [31:0] o_stale_reply_count,
    output wire m_done_valid,
    input wire m_done_ready,
    output wire [575:0] m_done_context,
    output wire [31:0] m_done_writer_tag,
    output wire m_done_ok,
    output wire [7:0] m_done_error
);
    wire cohort_reset_n=i_pixel_rst_n && i_dfi_rst_n;
    reg [1:0] pixel_release,dfi_release;
    always @(posedge i_pixel_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    end
    always @(posedge i_dfi_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) dfi_release<=0;
        else dfi_release<={dfi_release[0],1'b1};
    end
    wire pixel_reset_n=pixel_release[1],dfi_reset_n=dfi_release[1];
    wire bind_source_done,bind_sink_done,reply_source_done,reply_sink_done;
    wire pixel_local_done=pixel_reset_n && bind_source_done && reply_sink_done;
    wire dfi_local_done=dfi_reset_n && bind_sink_done && reply_source_done;
    reg dfi_done_meta,dfi_done_sync,pixel_done_meta,pixel_done_sync;
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin dfi_done_meta<=0;dfi_done_sync<=0;end
        else begin dfi_done_meta<=dfi_local_done;dfi_done_sync<=dfi_done_meta;end
    end
    always @(posedge i_dfi_clk or negedge dfi_reset_n) begin
        if(!dfi_reset_n) begin pixel_done_meta<=0;pixel_done_sync<=0;end
        else begin pixel_done_meta<=pixel_local_done;pixel_done_sync<=pixel_done_meta;end
    end
    assign o_pixel_reset_done=pixel_local_done && dfi_done_sync;
    assign o_dfi_reset_done=dfi_local_done && pixel_done_sync;

    reg pixel_owned,dfi_owned,producer_started,reply_pending;
    reg [575:0] pixel_context,dfi_context;
    reg [31:0] pixel_writer_tag,dfi_writer_tag;
    reg reply_ok;
    reg [7:0] reply_error;
    wire bind_source_ready,bind_sink_valid,bind_sink_ready;
    wire [607:0] bind_sink_data;
    assign s_bind_ready=o_pixel_reset_done && !pixel_owned && bind_source_ready;
    assign o_pixel_owned=pixel_owned;
    wire bind_source_fire=s_bind_valid && s_bind_ready;
    assign bind_sink_ready=o_dfi_reset_done && !dfi_owned && !reply_pending;
    wire bind_sink_fire=bind_sink_valid && bind_sink_ready;
    assign o_bind_context=dfi_context;
    assign o_bind_writer_tag=dfi_writer_tag;
    assign o_bind_ready=o_dfi_reset_done && dfi_owned && !producer_started && !reply_pending;

    wire write_identity_matches=s_write_tag==dfi_writer_tag &&
        s_write_sequence==dfi_context[108:77] && s_write_session==dfi_context[76:45] &&
        s_write_epoch==dfi_context[140:109] && s_write_camera==dfi_context[4];
    wire write_matches=dfi_owned && producer_started && !reply_pending && write_identity_matches;
    wire reply_source_ready,reply_sink_valid,reply_sink_ready;
    wire [616:0] reply_sink_data;
    // A matching result owns the empty local outcome slot. The borrowed
    // serializer cannot acknowledge until that outcome has been presented.
    // While pending, further records are stale and cannot revise the outcome.
    assign s_write_ready=o_dfi_reset_done;
    wire write_fire=s_write_valid && s_write_ready;
    wire reply_source_fire=reply_pending && reply_source_ready;
    wire [616:0] reply_source_data={dfi_writer_tag,dfi_context,reply_error,reply_ok};
    wire reply_matches=pixel_owned && reply_sink_data[616:585]==pixel_writer_tag &&
        reply_sink_data[584:9]==pixel_context;
    assign m_done_valid=o_pixel_reset_done && reply_sink_valid && reply_matches;
    assign m_done_context=reply_sink_data[584:9];
    assign m_done_writer_tag=reply_sink_data[616:585];
    assign m_done_error=reply_sink_data[8:1];
    assign m_done_ok=reply_sink_data[0];
    assign reply_sink_ready=o_pixel_reset_done && (!reply_matches || m_done_ready);
    wire reply_sink_fire=reply_sink_valid && reply_sink_ready;

    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            pixel_owned<=0;pixel_context<=0;pixel_writer_tag<=0;o_stale_reply_count<=0;
        end else begin
            if(bind_source_fire) begin
                pixel_owned<=1;pixel_context<=s_bind_context;pixel_writer_tag<=s_bind_writer_tag;
            end
            if(reply_sink_fire) begin
                if(reply_matches) pixel_owned<=0;
                else if(!(&o_stale_reply_count))o_stale_reply_count<=o_stale_reply_count+1'b1;
            end
        end
    end
    always @(posedge i_dfi_clk or negedge dfi_reset_n) begin
        if(!dfi_reset_n) begin
            dfi_owned<=0;producer_started<=0;reply_pending<=0;
            dfi_context<=0;dfi_writer_tag<=0;reply_ok<=0;reply_error<=0;o_stale_write_count<=0;
        end else begin
            if(bind_sink_fire) begin
                dfi_owned<=1;producer_started<=0;dfi_context<=bind_sink_data[575:0];
                dfi_writer_tag<=bind_sink_data[607:576];
            end
            if(i_writer_start_fire && o_bind_ready)producer_started<=1;
            if(write_fire) begin
                if(write_matches) begin
                    producer_started<=0;reply_pending<=1;reply_ok<=s_write_ok;reply_error<=s_write_error;
                end else if(!(&o_stale_write_count))o_stale_write_count<=o_stale_write_count+1'b1;
            end
            // Last real flit has copied the held tuple into the official FIFO.
            if(reply_source_fire)begin reply_pending<=0;dfi_owned<=0;end
        end
    end
    control_message_fifo_ip #(.MESSAGE_WIDTH(608),.BORROW_SOURCE(1)) u_bind (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_reset_n),
        .i_source_data({s_bind_writer_tag,s_bind_context}),
        .i_source_valid(s_bind_valid && o_pixel_reset_done && !pixel_owned),
        .o_source_ready(bind_source_ready),.o_source_reset_done(bind_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(cohort_reset_n),
        .o_sink_data(bind_sink_data),.o_sink_valid(bind_sink_valid),
        .i_sink_ready(bind_sink_ready),.o_sink_reset_done(bind_sink_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(617),.BORROW_SOURCE(1)) u_reply (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(cohort_reset_n),
        .i_source_data(reply_source_data),.i_source_valid(reply_pending),
        .o_source_ready(reply_source_ready),.o_source_reset_done(reply_source_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(cohort_reset_n),
        .o_sink_data(reply_sink_data),.o_sink_valid(reply_sink_valid),
        .i_sink_ready(reply_sink_ready),.o_sink_reset_done(reply_sink_done));
endmodule
