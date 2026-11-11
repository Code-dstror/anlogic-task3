`timescale 1ns / 1ps

// 检查主机发送测试流的递增字节模式
module h2c_stream_checker (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // H2C输入流
    input  wire [127:0] i_axis_tdata,
    input  wire [15:0] i_axis_tkeep,
    input  wire i_axis_tvalid,
    output wire o_axis_tready,
    input  wire i_axis_tlast,

    // 检查统计
    output wire [31:0] o_byte_count,
    output wire [31:0] o_frame_count,
    output wire [31:0] o_error_count,
    output wire [31:0] o_first_error_offset
);

    reg [31:0] byte_count_o;
    reg [31:0] frame_count_o;
    reg [31:0] error_count_o;
    reg [31:0] first_error_offset_o;
    reg [31:0] frame_byte_offset;
    wire [15:0] error_mask;
    wire [4:0] keep_count;
    wire [4:0] beat_error_count;
    wire [31:0] beat_first_error_offset;
    wire beat_error_seen;
    reg [3:0] first_error_lane;
    wire [1:0] keep_pair [0:7];
    wire [1:0] error_pair [0:7];
    wire [2:0] keep_quartet [0:3];
    wire [2:0] error_quartet [0:3];
    wire [3:0] keep_half [0:1];
    wire [3:0] error_half [0:1];
    genvar lane, pair, quartet, half;

    wire stream_fire;

    // 检查器持续接收主机方向测试数据
    assign o_axis_tready = i_rst_n;
    assign stream_fire = i_axis_tvalid && o_axis_tready;
    assign o_byte_count = byte_count_o;
    assign o_frame_count = frame_count_o;
    assign o_error_count = error_count_o;
    assign o_first_error_offset = first_error_offset_o;

    // 保留原整数lane比较的进位语义，不将期望值截断到八位。
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_compare
            wire [8:0] expected_byte;
            assign expected_byte = {1'b0, frame_byte_offset[7:0]} + lane;
            assign error_mask[lane] = i_axis_tkeep[lane] &&
                ({1'b0, i_axis_tdata[lane * 8 +: 8]} != expected_byte);
        end
        for (pair = 0; pair < 8; pair = pair + 1) begin : g_pair_count
            assign keep_pair[pair] = {1'b0, i_axis_tkeep[pair * 2]} +
                                    {1'b0, i_axis_tkeep[pair * 2 + 1]};
            assign error_pair[pair] = {1'b0, error_mask[pair * 2]} +
                                     {1'b0, error_mask[pair * 2 + 1]};
        end
        for (quartet = 0; quartet < 4; quartet = quartet + 1) begin : g_quartet_count
            assign keep_quartet[quartet] = {1'b0, keep_pair[quartet * 2]} +
                                         {1'b0, keep_pair[quartet * 2 + 1]};
            assign error_quartet[quartet] = {1'b0, error_pair[quartet * 2]} +
                                          {1'b0, error_pair[quartet * 2 + 1]};
        end
        for (half = 0; half < 2; half = half + 1) begin : g_half_count
            assign keep_half[half] = {1'b0, keep_quartet[half * 2]} +
                                    {1'b0, keep_quartet[half * 2 + 1]};
            assign error_half[half] = {1'b0, error_quartet[half * 2]} +
                                     {1'b0, error_quartet[half * 2 + 1]};
        end
    endgenerate
    assign keep_count = {1'b0, keep_half[0]} + {1'b0, keep_half[1]};
    assign beat_error_count = {1'b0, error_half[0]} + {1'b0, error_half[1]};
    assign beat_error_seen = |error_mask;
    assign beat_first_error_offset = frame_byte_offset + {28'd0, first_error_lane};

    // 只选择最小有效错误lane；宽偏移加法在选择之后共用。
    always @(*) begin
        first_error_lane = 4'd15;
        if      (error_mask[0])  first_error_lane = 4'd0;
        else if (error_mask[1])  first_error_lane = 4'd1;
        else if (error_mask[2])  first_error_lane = 4'd2;
        else if (error_mask[3])  first_error_lane = 4'd3;
        else if (error_mask[4])  first_error_lane = 4'd4;
        else if (error_mask[5])  first_error_lane = 4'd5;
        else if (error_mask[6])  first_error_lane = 4'd6;
        else if (error_mask[7])  first_error_lane = 4'd7;
        else if (error_mask[8])  first_error_lane = 4'd8;
        else if (error_mask[9])  first_error_lane = 4'd9;
        else if (error_mask[10]) first_error_lane = 4'd10;
        else if (error_mask[11]) first_error_lane = 4'd11;
        else if (error_mask[12]) first_error_lane = 4'd12;
        else if (error_mask[13]) first_error_lane = 4'd13;
        else if (error_mask[14]) first_error_lane = 4'd14;
    end

    // 在输入握手后更新字节帧和错误计数
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
