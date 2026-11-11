`timescale 1ns/1ps
// Single JPEG USER-domain lifecycle. Native DMA owns the host fence/ACK;
// this owner returns the producer lease only after SAFE and source drain.
module jpeg_product_owner (
    input wire i_clk,i_ownership_rst_n,i_app_enable,i_app_reset_n,
    input wire i_record_valid,output wire o_record_ready,
    input wire [31:0] i_record_length,input wire [127:0] i_record_identity,
    input wire [127:0] i_axis_data,input wire [15:0] i_axis_keep,
    input wire i_axis_valid,i_axis_last,output wire o_axis_ready,
    input wire i_done_valid,i_done_ok,i_drained,output wire o_cancel,
    output wire o_retire_valid,input wire i_retire_ready,
    output wire [127:0] o_retire_identity,output wire [31:0] o_retire_status,
    output wire m_record_valid,input wire m_record_ready,
    output wire [31:0] m_record_length,output wire [127:0] m_record_identity,
    output wire [127:0] m_axis_data,output wire [15:0] m_axis_keep,
    output wire m_axis_valid,m_axis_last,input wire m_axis_ready,
    output wire o_source_abort,
    input wire i_transport_cancel,i_transport_quarantine,
    input wire i_safe_valid,input wire [127:0] i_safe_identity,
    input wire [31:0] i_safe_status,
    output wire o_busy,o_quarantine
);
    reg active,offer_locked,safe_seen,cancel_seen,protocol_fault,retire_published;
    reg [31:0] safe_status;
    wire enabled=i_app_enable && i_app_reset_n;
    wire cancel_request=cancel_seen || !enabled || i_transport_cancel || o_quarantine;
    wire record_fire=m_record_valid && m_record_ready;
    wire publish_retire=active && safe_seen && i_done_valid && i_drained &&
        !i_axis_valid && !o_quarantine;
    wire retire_fire=o_retire_valid && i_retire_ready;
    assign o_busy=active || offer_locked;
    assign o_quarantine=protocol_fault || i_transport_quarantine;
    assign m_record_valid=i_ownership_rst_n && !active && enabled &&
        !o_quarantine && i_record_valid;
    assign m_record_length=i_record_length;
    assign m_record_identity=i_record_identity;
    assign o_record_ready=m_record_valid && m_record_ready;
    assign m_axis_data=i_axis_data;
    assign m_axis_keep=i_axis_keep;
    assign m_axis_last=i_axis_last;
    // STOP cannot withdraw a held beat; cancellation is a separate debt.
    assign m_axis_valid=active && i_axis_valid;
    assign o_axis_ready=active && m_axis_ready;
    assign o_source_abort=active && i_done_valid && !i_done_ok && i_drained && !i_axis_valid;
    assign o_cancel=active && cancel_request;
    // Publication freezes an irrevocable safe event. Later unrelated faults
    // prevent new work, but cannot revoke VALID while its consumer stalls.
    assign o_retire_valid=active && retire_published;
    assign o_retire_identity=i_record_identity;
    assign o_retire_status=safe_status;
    always @(posedge i_clk or negedge i_ownership_rst_n)begin
        if(!i_ownership_rst_n)begin
            active<=0;offer_locked<=0;safe_seen<=0;cancel_seen<=0;
            protocol_fault<=0;retire_published<=0;safe_status<=0;
        end else begin
            if(!active && enabled && !o_quarantine && i_record_valid)offer_locked<=1;
            if(!active && !enabled)offer_locked<=0;
            if(record_fire)begin
                active<=1;offer_locked<=0;safe_seen<=0;cancel_seen<=0;retire_published<=0;
            end
            if(active && cancel_request)cancel_seen<=1;
            if(i_safe_valid)begin
                if(!active || safe_seen || i_safe_identity!=i_record_identity)protocol_fault<=1;
                else begin safe_seen<=1;safe_status<=i_safe_status;end
            end
            if(publish_retire)retire_published<=1;
            if(retire_fire)begin
                active<=0;safe_seen<=0;cancel_seen<=0;retire_published<=0;
            end
        end
    end
endmodule
