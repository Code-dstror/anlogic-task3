`timescale 1ns / 1ps

// 跨时钟域传递单槽预留与领取握手
module single_slot_credit_cdc #(
    parameter integer MULTI_SLOT_ENABLE = 0
) (
    // 源时钟与复位
    input wire i_source_clk,
    input wire i_source_rst_n,

    // 源侧预留握手
    input wire i_source_request,
    output wire o_source_grant, // 源时钟域有效的单槽预留许可
    output wire o_source_ack,

    // 目的时钟与复位
    input wire i_sink_clk,
    input wire i_sink_rst_n,

    // 目的侧槽位状态
    input wire i_sink_slot_available,
    input wire i_sink_claim,
    output wire o_sink_reserved,
    output reg o_protocol_fault
);
    reg req_meta, req_sync, ack_sink, ack_meta, ack_sync;
    reg request_eligible, grant_active;
    reg slot_reserved, slot_claimed;
    // 目的侧确认经同步后返回源时钟域
    assign o_source_ack = ack_sync;
    assign o_source_grant = grant_active && i_source_request;
    assign o_sink_reserved = slot_reserved;
    // 将源侧请求同步到目的时钟域
    always @(posedge i_sink_clk or negedge i_sink_rst_n)
        if (!i_sink_rst_n) begin req_meta<=0; req_sync<=0; end
        else begin req_meta<=i_source_request; req_sync<=req_meta; end
    // 在槽位可用时确认一次预留请求
    always @(posedge i_sink_clk or negedge i_sink_rst_n)
        if (!i_sink_rst_n) ack_sink<=0;
        else if (!req_sync) ack_sink<=0;
        else if (!ack_sink && !slot_reserved && i_sink_slot_available) ack_sink<=1;
    // 撤销 Ack 只结束请求握手，不代表帧生命周期结束
    // START 可在 grant 之后很久到达，尤其是提前出现错误时
    // 跟踪槽位预留领取及协议故障
    always @(posedge i_sink_clk or negedge i_sink_rst_n) begin
        if (!i_sink_rst_n) begin
            slot_reserved<=0; slot_claimed<=0; o_protocol_fault<=0;
        end else begin
            if (req_sync && !ack_sink && !slot_reserved && i_sink_slot_available) begin
                slot_reserved<=1; slot_claimed<=0;
            end
            if (i_sink_claim) begin
                if (!slot_reserved || slot_claimed) o_protocol_fault<=1;
                else if (MULTI_SLOT_ENABLE != 0) begin
                    // The accepted START consumed this reserved free slot.
                    // ACK must still fall before another request can be granted.
                    slot_reserved<=0; slot_claimed<=0;
                end else slot_claimed<=1;
            end
            if (MULTI_SLOT_ENABLE == 0 && slot_reserved && slot_claimed && i_sink_slot_available) begin
                slot_reserved<=0; slot_claimed<=0;
            end
        end
    end
    // 将目的侧确认同步回源时钟域
    always @(posedge i_source_clk or negedge i_source_rst_n) begin
        if (!i_source_rst_n) begin
            ack_meta<=0; ack_sync<=0; request_eligible<=0; grant_active<=0;
        end else begin
            ack_meta<=ack_sink; ack_sync<=ack_meta;
            if (!i_source_request) grant_active<=0;
            else if (request_eligible && ack_sync) begin
                grant_active<=1; request_eligible<=0;
            end
            if (!i_source_request && !ack_sync) request_eligible<=1;
        end
    end
endmodule
