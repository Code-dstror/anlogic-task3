`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     h2c_stream_checker
// Module Name:     h2c_stream_checker
// Description:     Checks incrementing-byte H2C test traffic.
// Dependencies:    None
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        h2c_stream_checker
// 模块名称:        h2c_stream_checker
// 模块说明:        检查按字节递增的H2C测试流。
// 依赖文件:        无

module h2c_stream_checker (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire [127:0] i_axis_tdata,
    input  wire [15:0]  i_axis_tkeep,
    input  wire         i_axis_tvalid,
    output wire         o_axis_tready,
    input  wire         i_axis_tlast,
    output wire [31:0]  o_byte_count,
    output wire [31:0]  o_frame_count,
    output wire [31:0]  o_error_count,
    output wire [31:0]  o_first_error_offset
);

    reg [31:0] byte_count_o;
    reg [31:0] frame_count_o;
    reg [31:0] error_count_o;
    reg [31:0] first_error_offset_o;
    reg [31:0] frame_byte_offset;
    reg [4:0] keep_count;
    reg [4:0] beat_error_count;
    reg [31:0] beat_first_error_offset;
    reg beat_error_seen;
    integer keep_lane;

    wire stream_fire;

    assign o_axis_tready = i_rst_n;
    assign stream_fire = i_axis_tvalid && o_axis_tready;
    assign o_byte_count = byte_count_o;
    assign o_frame_count = frame_count_o;
    assign o_error_count = error_count_o;
    assign o_first_error_offset = first_error_offset_o;

    always @(*) begin
        keep_count = 5'd0;
        beat_error_count = 5'd0;
        beat_first_error_offset = 32'hffff_ffff;
        beat_error_seen = 1'b0;
        for (keep_lane = 0; keep_lane < 16; keep_lane = keep_lane + 1) begin
            keep_count = keep_count + i_axis_tkeep[keep_lane];
            if (i_axis_tkeep[keep_lane] &&
                (i_axis_tdata[(keep_lane * 8) +: 8] !=
                 (frame_byte_offset[7:0] + keep_lane))) begin
                beat_error_count = beat_error_count + 1'b1;
                if (!beat_error_seen) begin
                    beat_error_seen = 1'b1;
                    beat_first_error_offset = frame_byte_offset + keep_lane;
                end
            end
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            byte_count_o <= 32'd0;
            frame_count_o <= 32'd0;
            error_count_o <= 32'd0;
            first_error_offset_o <= 32'hffff_ffff;
            frame_byte_offset <= 32'd0;
        end else if (stream_fire) begin
            byte_count_o <= byte_count_o + keep_count;
            error_count_o <= error_count_o + beat_error_count;
            if ((error_count_o == 32'd0) && beat_error_seen) begin
                first_error_offset_o <= beat_first_error_offset;
            end
            if (i_axis_tlast) begin
                frame_count_o <= frame_count_o + 1'b1;
                frame_byte_offset <= 32'd0;
            end else begin
                frame_byte_offset <= frame_byte_offset + keep_count;
            end
        end
    end

endmodule
