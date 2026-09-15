`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     c2h_test_source
// Module Name:     c2h_test_source
// Description:     Produces deterministic packet payloads for C2H testing.
// Dependencies:    None
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        c2h_test_source
// 模块名称:        c2h_test_source
// 模块说明:        产生确定性C2H测试负载。
// 依赖文件:        无

module c2h_test_source (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_start,
    input  wire [31:0]  i_payload_length,
    input  wire [1:0]   i_pattern_select,
    output wire         o_busy,

    output wire         o_meta_valid,
    input  wire         i_meta_ready,
    output wire [31:0]  o_meta_frame_sequence,
    output wire [31:0]  o_meta_payload_length,
    output wire [15:0]  o_meta_width,
    output wire [15:0]  o_meta_height,
    output wire [7:0]   o_meta_pixel_format,
    output wire [7:0]   o_meta_compression,
    output wire [7:0]   o_meta_quality,
    output wire [63:0]  o_meta_timestamp_ns,
    output wire [31:0]  o_meta_status,
    output wire [31:0]  o_meta_error_code,
    output wire [15:0]  o_meta_slot_id,
    output wire [31:0]  o_meta_payload_crc32,

    output wire [127:0] o_src_tdata,
    output wire [15:0]  o_src_tkeep,
    output wire         o_src_tvalid,
    input  wire         i_src_tready,
    output wire         o_src_tlast
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_META = 2'd1;
    localparam [1:0] STATE_DATA = 2'd2;

    reg [1:0] state_current;
    reg [1:0] state_next;
    reg [31:0] frame_sequence;
    reg [31:0] payload_length;
    reg [31:0] byte_offset;
    reg [1:0] pattern_select;
    reg [127:0] source_data;
    reg [15:0] source_keep;
    integer byte_lane;
    reg [31:0] byte_position;

    wire meta_fire;
    wire data_fire;
    wire final_beat;
    wire [31:0] bytes_remaining;

    assign o_busy = state_current != STATE_IDLE;
    assign o_meta_valid = state_current == STATE_META;
    assign o_meta_frame_sequence = frame_sequence;
    assign o_meta_payload_length = payload_length;
    assign o_meta_width = 16'd1920;
    assign o_meta_height = 16'd1080;
    assign o_meta_pixel_format = 8'd1;
    assign o_meta_compression = 8'd1;
    assign o_meta_quality = 8'd75;
    assign o_meta_timestamp_ns = 64'd0;
    assign o_meta_status = 32'd0;
    assign o_meta_error_code = 32'd0;
    assign o_meta_slot_id = 16'd0;
    assign o_meta_payload_crc32 = 32'd0;
    assign o_src_tdata = source_data;
    assign o_src_tkeep = source_keep;
    assign o_src_tvalid = state_current == STATE_DATA;
    assign bytes_remaining = payload_length - byte_offset;
    assign final_beat = bytes_remaining <= 32'd16;
    assign o_src_tlast = final_beat;
    assign meta_fire = o_meta_valid && i_meta_ready;
    assign data_fire = o_src_tvalid && i_src_tready;

    always @(*) begin
        source_data = 128'd0;
        for (byte_lane = 0; byte_lane < 16; byte_lane = byte_lane + 1) begin
            byte_position = byte_offset + byte_lane;
            case (pattern_select)
                2'd0: source_data[(byte_lane * 8) +: 8] = byte_position[7:0];
                2'd1: source_data[(byte_lane * 8) +: 8] = 8'ha5;
                default: source_data[(byte_lane * 8) +: 8] =
                    byte_position[7:0] ^ byte_position[15:8] ^ 8'h5a;
            endcase
        end

        source_keep = 16'hffff;
        if (final_beat) begin
            case (bytes_remaining[4:0])
                5'd1:  source_keep = 16'h0001;
                5'd2:  source_keep = 16'h0003;
                5'd3:  source_keep = 16'h0007;
                5'd4:  source_keep = 16'h000f;
                5'd5:  source_keep = 16'h001f;
                5'd6:  source_keep = 16'h003f;
                5'd7:  source_keep = 16'h007f;
                5'd8:  source_keep = 16'h00ff;
                5'd9:  source_keep = 16'h01ff;
                5'd10: source_keep = 16'h03ff;
                5'd11: source_keep = 16'h07ff;
                5'd12: source_keep = 16'h0fff;
                5'd13: source_keep = 16'h1fff;
                5'd14: source_keep = 16'h3fff;
                5'd15: source_keep = 16'h7fff;
                default: source_keep = 16'hffff;
            endcase
        end
    end

    always @(*) begin
        state_next = state_current;
        case (state_current)
            STATE_IDLE: begin
                if (i_start) begin
                    state_next = STATE_META;
                end
            end
            STATE_META: begin
                if (meta_fire) begin
                    state_next = STATE_DATA;
                end
            end
            STATE_DATA: begin
                if (data_fire && final_beat) begin
                    state_next = STATE_IDLE;
                end
            end
            default: state_next = STATE_IDLE;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_current <= STATE_IDLE;
        end else begin
            state_current <= state_next;
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            frame_sequence <= 32'd0;
            payload_length <= 32'd1;
            byte_offset <= 32'd0;
            pattern_select <= 2'd0;
        end else begin
            if ((state_current == STATE_IDLE) && i_start) begin
                payload_length <= i_payload_length;
                pattern_select <= i_pattern_select;
                byte_offset <= 32'd0;
            end
            if (data_fire) begin
                if (final_beat) begin
                    frame_sequence <= frame_sequence + 1'b1;
                    byte_offset <= 32'd0;
                end else begin
                    byte_offset <= byte_offset + 32'd16;
                end
            end
        end
    end

endmodule
