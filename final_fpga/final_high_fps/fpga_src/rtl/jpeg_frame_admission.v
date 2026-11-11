`timescale 1ns / 1ps

// 按槽位信用控制像素帧进入JPEG编码器
module jpeg_frame_admission #(
    parameter integer EXTERNAL_SEQUENCE_ENABLE = 0,
    parameter integer SHARED_LUMA_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 槽位与会话控制
    input wire i_credit_grant,
    input wire i_credit_ack,
    input wire i_session_armed,
    input wire i_app_enable,
    input wire i_fault,
    output wire o_credit_request,
    output wire o_credit_take,

    // 相机像素输入
    input wire [95:0] i_rgb_data,
    input wire [31:0] i_luma,
    input wire [31:0] i_frame_sequence,
    input wire i_rgb_valid,
    output reg o_rgb_ready,
    input wire i_rgb_sof,
    input wire i_rgb_eol,

    // 相机帧结果
    input wire i_camera_done,
    input wire i_camera_error,

    // 编码器像素输出
    output reg [95:0] o_jpeg_rgb,
    output wire [31:0] o_jpeg_luma,
    output reg o_jpeg_valid,
    input wire i_jpeg_ready,
    output reg o_jpeg_sof,
    output reg o_jpeg_eol,

    // 存储帧启动
    output reg o_start_valid,
    input wire i_start_ready,
    input wire [63:0] i_time_ns,
    output wire [63:0] o_timestamp_ns,
    output wire [31:0] o_capture_id,

    // 帧状态输出
    output reg o_status_valid,
    input wire i_status_ready,
    output wire [31:0] o_status_id,
    output reg o_status_ok,

    // 编码结果确认
    input wire i_result_valid,
    input wire i_result_ready,
    input wire [31:0] i_result_id,

    // 故障与活动状态
    output reg o_protocol_fault, // 帧准入或结果配对出现协议错误
    output wire o_active,
    // S04 may switch to RAW replay only when SOF would be admitted now.
    output wire o_replay_ready_boundary,
    output wire o_rgb_buffered,
    output wire o_state_idle,
    output wire [2:0] o_diag_state
);
    localparam [2:0] IDLE=0, START=1, RUN=2, DROP=3,
                     WAIT_RESULT=4, WAIT_CREDIT_CLEAR=5;
    reg [2:0] state;
    // Local PIX observation only; DROP and WAIT_CREDIT_CLEAR stay distinct.
    assign o_diag_state=state;
    reg [31:0] capture_id;
    reg [63:0] start_time;
    reg end_seen, bad_seen;
    reg encoder_started;
    reg credit_request;
    reg buf_valid, buf_sof, buf_eol;
    reg [95:0] buf_data;
    reg [31:0] buf_luma;
    wire service_enabled = i_session_armed && i_app_enable &&
                           !i_fault && !o_protocol_fault;
    wire admit = i_credit_grant && service_enabled;
    wire result_fire = i_result_valid && i_result_ready;
    wire matching_result = result_fire && encoder_started &&
                           (state == RUN || state == WAIT_RESULT) &&
                           i_result_id == capture_id;
    wire pop = o_jpeg_valid && i_jpeg_ready;
    wire push = i_rgb_valid && o_rgb_ready;
    // 数据有效位只在时钟沿清除；异步清零的 state 立即遮断外部 valid。
    // 这样停钟复位期间旧缓冲数据不会传播到下游 RAM 访问控制。
    always @(posedge i_clk) begin
        if (!i_rst_n)
            buf_valid <= 1'b0;
        else if (matching_result)
            buf_valid <= 1'b0;
        else case (state)
            IDLE: buf_valid <= i_rgb_valid && i_rgb_sof && admit;
            RUN: begin
                if (push)
                    buf_valid <= 1'b1;
                else if (pop)
                    buf_valid <= 1'b0;
            end
            default: begin end
        endcase
    end
    // Payload sampling depends only on buffer capacity. IDLE may pre-sample
    // invalid offers; buf_valid still grants ownership only to an admitted SOF.
    // START holds that first group. In RUN an occupied, stalled group holds;
    // otherwise speculative data remains hidden unless the unchanged push fires.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            buf_data <= 0; buf_luma <= 0; buf_sof <= 0; buf_eol <= 0;
        end else if (state == IDLE || (state == RUN && (!buf_valid || i_jpeg_ready))) begin
            buf_data <= i_rgb_data;
            buf_luma <= SHARED_LUMA_ENABLE ? i_luma : 32'd0;
            buf_sof <= i_rgb_sof; buf_eol <= i_rgb_eol;
        end
    end
    // 信用请求保持到源侧预留握手完成
    assign o_credit_request = credit_request;
    // IDLE always drains the offered source beat (o_rgb_ready is 1), including
    // coordinated reset. Do not route its SOF decision through RUN's JPEG ready.
    assign o_credit_take = state == IDLE && i_rgb_valid && i_rgb_sof && admit;
    assign o_capture_id = capture_id;
    assign o_status_id = capture_id;
    assign o_timestamp_ns = start_time;
    assign o_jpeg_luma = buf_luma;
    assign o_active = state == START || state == RUN || state == WAIT_RESULT;
    assign o_replay_ready_boundary = state == IDLE && admit;
    // START hides the reserved first group from o_jpeg_valid; it remains owned.
    assign o_rgb_buffered = buf_valid;
    assign o_state_idle = state == IDLE;
    // 根据槽位信用和像素缓冲状态生成握手
    always @(*) begin
        o_rgb_ready = 1'b1; // 未准入帧完整排空，不交付部分帧
        o_start_valid = state == START;
        o_jpeg_valid = state == RUN && buf_valid;
        o_jpeg_rgb = buf_data;
        o_jpeg_sof = buf_sof;
        o_jpeg_eol = buf_eol;
        if (state == START)
            o_rgb_ready = 1'b0;
        else if (state == RUN)
            o_rgb_ready = !end_seen && !i_camera_done && !i_camera_error &&
                          !i_fault && (!buf_valid || i_jpeg_ready);
    end
    // 在帧边界推进准入状态并核对编码结果
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= IDLE; capture_id <= 0; start_time <= 0;
            end_seen <= 0; bad_seen <= 0;
            encoder_started <= 0; credit_request <= 0;
            o_protocol_fault <= 0;
            o_status_valid <= 0; o_status_ok <= 0;
        end else begin
            // 信用请求一旦发出，即使帧被拒绝或应用暂时禁用也保持有效
            // 只有信用被消费或整体复位才结束源侧预留握手
            if (o_credit_take)
                credit_request <= 0;
            else if (state == IDLE && service_enabled)
                credit_request <= 1;
            if (o_status_valid && i_status_ready)
                o_status_valid <= 0;
            if (result_fire && !matching_result)
                o_protocol_fault <= 1;
            if (pop && buf_sof)
                encoder_started <= 1;
            if ((state == START || state == RUN) &&
                (i_camera_done || i_camera_error || i_fault)) begin
                end_seen <= 1;
                if (i_camera_error || i_fault) bad_seen <= 1;
            end
            case (state)
                IDLE: begin
                    encoder_started <= 0;
                    end_seen <= 0; bad_seen <= 0;
                    if (i_rgb_valid && i_rgb_sof) begin
                        if (admit) begin
                            start_time <= i_time_ns;
                            if(EXTERNAL_SEQUENCE_ENABLE != 0) capture_id <= i_frame_sequence;
                            end_seen <= i_camera_done || i_camera_error;
                            bad_seen <= i_camera_error;
                            state <= START;
                        end else if (!i_camera_done && !i_camera_error)
                            state <= DROP;
                        else
                            state <= IDLE;
                    end
                end
                START: if (i_start_ready) state <= RUN;
                RUN: begin
                    // 等待已接收 RGB 像素离开弹性寄存器
                    // 错误帧可能在正常末行 EOL 到达前结束
                    if (end_seen && !buf_valid) begin
                        o_status_valid <= 1;
                        o_status_ok <= !(bad_seen || i_camera_error || i_fault);
                        state <= WAIT_RESULT;
                    end
                end
                DROP: if (i_camera_done || i_camera_error) state <= IDLE;
                WAIT_RESULT: begin end
                WAIT_CREDIT_CLEAR: if (!i_credit_ack) state <= IDLE;
                default: state <= IDLE;
            endcase
            // 编码结果是私有 RGB 和状态端口唯一的取消事件
            // 拒绝过期帧标识以及编码器取得 SOF 前到达的结果
            // 已取消的状态不得等待已经结束接收的下游
            if (matching_result) begin
                o_status_valid <= 0;
                encoder_started <= 0;
                if(EXTERNAL_SEQUENCE_ENABLE == 0) capture_id <= capture_id + 32'd1;
                state <= WAIT_CREDIT_CLEAR;
            end
        end
    end
endmodule
