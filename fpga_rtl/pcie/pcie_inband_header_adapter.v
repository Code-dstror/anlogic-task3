`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/15
// Design Name:     pcie_inband_header_adapter
// Module Name:     pcie_inband_header_adapter
// Description:     Validates an in-band frame header and exposes payload metadata.
// Dependencies:    pcie_protocol_v1.vh
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月15日
// 设计名称:        pcie_inband_header_adapter
// 模块名称:        pcie_inband_header_adapter
// 模块说明:        校验带内帧头并输出负载及元数据。
// 依赖文件:        pcie_protocol_v1.vh

`include "pcie_protocol_v1.vh"

module pcie_inband_header_adapter (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire [127:0] i_src_tdata,
    input  wire [15:0]  i_src_tkeep,
    input  wire         i_src_tvalid,
    output wire         o_src_tready,
    input  wire         i_src_tlast,
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
    output wire [127:0] o_payload_tdata,
    output wire [15:0]  o_payload_tkeep,
    output wire         o_payload_tvalid,
    input  wire         i_payload_tready,
    output wire         o_payload_tlast,
    output wire         o_header_error,
    output wire [31:0]  o_last_error,
    output wire         o_busy
);

    localparam [2:0] STATE_HEADER = 3'd0;
    localparam [2:0] STATE_META = 3'd1;
    localparam [2:0] STATE_PAYLOAD = 3'd2;
    localparam [2:0] STATE_DRAIN = 3'd3;

    reg [2:0] state_current;
    reg [2:0] state_next;
    reg [1:0] header_index;
    reg [127:0] header_zero;
    reg [127:0] header_one;
    reg [127:0] header_two;
    reg header_error_o;
    reg [31:0] last_error_o;

    wire source_fire;
    wire header_beat_valid;
    wire final_header_valid;

    assign o_src_tready = (state_current == STATE_HEADER) ||
                          (state_current == STATE_DRAIN) ||
                          ((state_current == STATE_PAYLOAD) && i_payload_tready);
    assign source_fire = i_src_tvalid && o_src_tready;
    assign o_meta_valid = state_current == STATE_META;
    assign o_payload_tdata = i_src_tdata;
    assign o_payload_tkeep = i_src_tkeep;
    assign o_payload_tvalid = (state_current == STATE_PAYLOAD) && i_src_tvalid;
    assign o_payload_tlast = i_src_tlast;
    assign o_header_error = header_error_o;
    assign o_last_error = last_error_o;
    assign o_busy = state_current != STATE_HEADER || header_index != 2'd0;

    assign o_meta_frame_sequence = header_zero[95:64];
    assign o_meta_payload_length = header_zero[127:96];
    assign o_meta_width = header_one[15:0];
    assign o_meta_height = header_one[31:16];
    assign o_meta_pixel_format = header_one[39:32];
    assign o_meta_compression = header_one[47:40];
    assign o_meta_quality = header_one[55:48];
    assign o_meta_timestamp_ns = header_one[127:64];
    assign o_meta_status = header_two[31:0];
    assign o_meta_error_code = header_two[63:32];
    assign o_meta_slot_id = header_two[79:64];
    assign o_meta_payload_crc32 = header_two[127:96];

    assign header_beat_valid = (i_src_tkeep == 16'hffff) && !i_src_tlast;
    assign final_header_valid = header_beat_valid && (i_src_tdata == 128'd0) &&
                                (header_zero[31:0] == `PCIE_FRAME_MAGIC) &&
                                (header_zero[47:32] == `PCIE_PROTOCOL_VERSION) &&
                                (header_zero[63:48] == 16'd64) &&
                                (header_zero[127:96] != 32'd0) &&
                                (header_zero[127:96] <= `PCIE_MAX_PAYLOAD) &&
                                (header_one[63:56] == 8'h01) &&
                                (header_two[95:80] == 16'd0);

    always @(*) begin
        state_next = state_current;
        case (state_current)
            STATE_HEADER: begin
                if (source_fire) begin
                    if (!header_beat_valid) begin
                        state_next = i_src_tlast ? STATE_HEADER : STATE_DRAIN;
                    end else if (header_index == 2'd3) begin
                        state_next = final_header_valid ? STATE_META : STATE_DRAIN;
                    end
                end
            end
            STATE_META: begin
                if (i_meta_ready) begin
                    state_next = STATE_PAYLOAD;
                end
            end
            STATE_PAYLOAD: begin
                if (source_fire && i_src_tlast) begin
                    state_next = STATE_HEADER;
                end
            end
            STATE_DRAIN: begin
                if (source_fire && i_src_tlast) begin
                    state_next = STATE_HEADER;
                end
            end
            default: state_next = STATE_HEADER;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_current <= STATE_HEADER;
        end else begin
            state_current <= state_next;
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            header_index <= 2'd0;
            header_zero <= 128'd0;
            header_one <= 128'd0;
            header_two <= 128'd0;
            header_error_o <= 1'b0;
            last_error_o <= `PCIE_ERROR_NONE;
        end else begin
            header_error_o <= 1'b0;
            if ((state_current == STATE_HEADER) && source_fire) begin
                if (!header_beat_valid) begin
                    header_index <= 2'd0;
                    header_error_o <= 1'b1;
                    last_error_o <= `PCIE_ERROR_HEADER_FORMAT;
                end else begin
                    case (header_index)
                        2'd0: header_zero <= i_src_tdata;
                        2'd1: header_one <= i_src_tdata;
                        2'd2: header_two <= i_src_tdata;
                        default: begin
                            header_index <= 2'd0;
                            if (!final_header_valid) begin
                                header_error_o <= 1'b1;
                                last_error_o <= `PCIE_ERROR_HEADER_FORMAT;
                            end else begin
                                last_error_o <= `PCIE_ERROR_NONE;
                            end
                        end
                    endcase
                    if (header_index != 2'd3) begin
                        header_index <= header_index + 1'b1;
                    end
                end
            end else if ((state_current == STATE_DRAIN) && source_fire && i_src_tlast) begin
                header_index <= 2'd0;
            end
        end
    end

endmodule
