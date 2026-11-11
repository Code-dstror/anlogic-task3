`timescale 1ns / 1ps
`default_nettype none

// Exact token-count fence, not FIFO-empty or elapsed-time inference.
// Instantiate once per independent capture clock; writer quiet is global DFI.
module raw_capture_drain_cdc #(
    parameter integer CAMERA_ID = 0,
    parameter integer CAPTURE_ENABLE = 1
) (
    input wire i_source_clk, i_source_rst_n,
    input wire i_dfi_clk, i_dfi_rst_n,
    input wire i_enqueue_fire, i_source_idle,
    input wire i_consume_fire, i_write_quiescent,
    input wire s_drain_valid,
    output wire s_drain_ready,
    input wire [31:0] s_drain_session, s_drain_epoch,
    output reg m_drain_valid,
    input wire m_drain_ready,
    output reg [31:0] m_drain_session, m_drain_epoch,
    output reg [63:0] m_drain_target, m_drain_id,
    output wire o_apply_quiescent,
    output reg [63:0] o_enqueued_count, o_consumed_count,
    output reg o_source_fault, o_dfi_fault,
    output reg [31:0] o_stale_ack_count,
    output wire o_source_reset_done, o_dfi_reset_done
);
    // bit199 is ACK-success; request199:193 and ACK198:193 are zero.
    // [192]=camera, [191:128]=unique id, [127:96]=session,
    // [95:64]=future epoch, [63:0]=exact enqueue target.
    wire cohort_rst_n=i_source_rst_n && i_dfi_rst_n;
    wire source_rst_n,dfi_rst_n;
    reset_release_sync u_source_reset(.i_clk(i_source_clk),
        .i_async_rst_n(cohort_rst_n),.o_rst_n(source_rst_n));
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),
        .i_async_rst_n(cohort_rst_n),.o_rst_n(dfi_rst_n));
    generate if ((CAMERA_ID!=0 && CAMERA_ID!=1) ||
                 (CAPTURE_ENABLE!=0 && CAPTURE_ENABLE!=1)) begin : bad_parameters
        RAW_CAPTURE_DRAIN_REQUIRES_CAMERA_0_OR_1_AND_BOOLEAN_ENABLE invalid_configuration();
    end endgenerate

    reg [199:0] source_packet,dfi_packet;
    reg source_busy,request_pending,dfi_owned,ack_pending,source_quiet;
    reg [63:0] next_id,dfi_last_id;
    reg [31:0] source_session,dfi_session;
    reg dfi_fault_meta,dfi_fault_sync;
    wire request_ready,request_valid,request_sink_ready;
    wire [199:0] request_data,ack_data;
    wire ack_ready,ack_valid;
    wire request_source_done,request_sink_done,ack_source_done,ack_sink_done;

    // The existing owner banks hold packet data until the final real flit.
    // Pending flags are never withdrawn on a fault; cohort reset cancels both.
    control_message_fifo_ip #(.MESSAGE_WIDTH(200),.BORROW_SOURCE(1)) u_request (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_source_clk),.i_source_rst_n(source_rst_n),
        .i_source_data(source_packet),.i_source_valid(request_pending),
        .o_source_ready(request_ready),.o_source_reset_done(request_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(dfi_rst_n),
        .o_sink_data(request_data),.o_sink_valid(request_valid),
        .i_sink_ready(request_sink_ready),.o_sink_reset_done(request_sink_done));
    control_message_fifo_ip #(.MESSAGE_WIDTH(200),.BORROW_SOURCE(1)) u_ack (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_rst_n),
        .i_source_data({1'b1,6'd0,dfi_packet[192:0]}),.i_source_valid(ack_pending),
        .o_source_ready(ack_ready),.o_source_reset_done(ack_source_done),
        .i_sink_clk(i_source_clk),.i_sink_rst_n(source_rst_n),
        .o_sink_data(ack_data),.o_sink_valid(ack_valid),
        .i_sink_ready(o_source_reset_done),.o_sink_reset_done(ack_sink_done));
    assign o_source_reset_done=source_rst_n && request_source_done && ack_sink_done;
    assign o_dfi_reset_done=dfi_rst_n && request_sink_done && ack_source_done;
    assign s_drain_ready=o_source_reset_done && !source_busy && !m_drain_valid &&
                         !o_source_fault && i_source_idle && !i_enqueue_fire;
    assign request_sink_ready=o_dfi_reset_done && !dfi_owned && !o_dfi_fault;
    assign o_apply_quiescent=o_source_reset_done && source_quiet &&
        !o_source_fault && i_source_idle && !i_enqueue_fire;

    // Count every real payload FIFO handshake, even while control FIFOs release.
    // Saturation makes exhaustion observable; no old target can alias a wrap.
    always @(posedge i_source_clk or negedge source_rst_n) begin
        if(!source_rst_n) begin
            o_enqueued_count<=0;o_source_fault<=0;o_stale_ack_count<=0;
            source_packet<=0;source_busy<=0;request_pending<=0;source_quiet<=0;
            next_id<=0;source_session<=0;m_drain_valid<=0;
            m_drain_session<=0;m_drain_epoch<=0;m_drain_target<=0;m_drain_id<=0;
            dfi_fault_meta<=0;dfi_fault_sync<=0;
        end else begin
            dfi_fault_meta<=o_dfi_fault;dfi_fault_sync<=dfi_fault_meta;
            if(dfi_fault_sync)begin o_source_fault<=1;source_quiet<=0;end
            // READY acknowledges application of this exact held result, not
            // merely receipt of the FIFO packet; it ends the proof lease.
            if(m_drain_valid && m_drain_ready)begin m_drain_valid<=0;source_quiet<=0;end
            if(!i_source_idle)source_quiet<=0;
            if(i_enqueue_fire) begin
                source_quiet<=0;
                if(CAPTURE_ENABLE==0 || &o_enqueued_count)o_source_fault<=1;
                else o_enqueued_count<=o_enqueued_count+64'd1;
            end
            if((source_busy || source_quiet) && (!i_source_idle || i_enqueue_fire))begin
                o_source_fault<=1;source_quiet<=0;
            end
            if(s_drain_valid && s_drain_ready) begin
                source_quiet<=0;
                if(s_drain_session==0 || (source_session!=0 && source_session!=s_drain_session) || &next_id)
                    o_source_fault<=1;
                else begin
                    source_session<=s_drain_session;next_id<=next_id+64'd1;
                    source_packet<={7'd0,(CAMERA_ID!=0),next_id+64'd1,
                                    s_drain_session,s_drain_epoch,o_enqueued_count};
                    source_busy<=1;request_pending<=1;
                end
            end
            // Fault never withdraws a request already held at the FIFO input.
            if(request_pending && request_ready)request_pending<=0;
            if(ack_valid && o_source_reset_done) begin
                if(source_busy && ack_data=={1'b1,6'd0,source_packet[192:0]}) begin
                    source_busy<=0;
                    if(!o_source_fault && !dfi_fault_sync && i_source_idle && !i_enqueue_fire)begin
                        source_quiet<=1;m_drain_valid<=1;
                        m_drain_session<=source_packet[127:96];m_drain_epoch<=source_packet[95:64];
                        m_drain_target<=source_packet[63:0];m_drain_id<=source_packet[191:128];
                    end
                end else if(!(&o_stale_ack_count))o_stale_ack_count<=o_stale_ack_count+32'd1;
            end
        end
    end

    always @(posedge i_dfi_clk or negedge dfi_rst_n) begin
        if(!dfi_rst_n) begin
            o_consumed_count<=0;o_dfi_fault<=0;dfi_packet<=0;
            dfi_owned<=0;ack_pending<=0;dfi_last_id<=0;dfi_session<=0;
        end else begin
            if(i_consume_fire) begin
                if(CAPTURE_ENABLE==0 || &o_consumed_count)o_dfi_fault<=1;
                else o_consumed_count<=o_consumed_count+64'd1;
            end
            if(request_valid && request_sink_ready) begin
                dfi_packet<=request_data;dfi_owned<=1;
                if(request_data[199:193]!=0 || request_data[192]!=(CAMERA_ID!=0) ||
                   request_data[127:96]==0 || request_data[191:128]==0 ||
                   request_data[191:128]<=dfi_last_id ||
                   (dfi_session!=0 && request_data[127:96]!=dfi_session) ||
                   (CAPTURE_ENABLE==0 && request_data[63:0]!=0))o_dfi_fault<=1;
                else begin dfi_session<=request_data[127:96];dfi_last_id<=request_data[191:128];end
            end
            if(dfi_owned && !o_dfi_fault) begin
                if(o_consumed_count>dfi_packet[63:0] ||
                   (i_consume_fire && o_consumed_count>=dfi_packet[63:0]))o_dfi_fault<=1;
                else if(!ack_pending && o_consumed_count==dfi_packet[63:0] &&
                        !i_consume_fire && i_write_quiescent)ack_pending<=1;
            end
            if(ack_pending && ack_ready)begin ack_pending<=0;dfi_owned<=0;end
        end
    end
endmodule
`default_nettype wire
