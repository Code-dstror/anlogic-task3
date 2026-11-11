`timescale 1ns / 1ps

// 对八乘八像素块执行定点二维离散余弦变换
module jpeg_dct8x8 #(
    parameter integer FAST_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 输入像素块
    input wire i_block_valid,
    output wire o_block_ready,
    input wire [511:0] i_samples,
    input wire [1:0] i_component,
    input wire [8:0] i_mcu_x,
    input wire [8:0] i_mcu_y,
    input wire [1:0] i_block_index,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,

    // 输出变换系数
    output wire o_block_valid,
    input wire i_block_ready,
    output wire [1023:0] o_coeffs,
    output wire [1:0] o_component,
    output wire [8:0] o_mcu_x,
    output wire [8:0] o_mcu_y,
    output wire [1:0] o_block_index,
    output wire o_frame_last,
    output wire [31:0] o_capture_id
);
    function signed [15:0] round_q14;
        input signed [31:0] value;
        begin
            // 采用对称四舍五入，半值朝远离零的方向取整
            // 对负值先加 8191 再算术向下取整，等价于按幅值舍入后恢复符号
            round_q14 = (value + (value[31] ? 32'sd8191 : 32'sd8192)) >>> 14;
        end
    endfunction

    generate if (FAST_ENABLE) begin : g_fast
        jpeg_dct8x8_pipeline #(.OUTPUT_STREAM_MODE(0)) u_pipeline (
            .i_clk(i_clk),.i_rst_n(i_rst_n),.i_block_valid(i_block_valid),.o_block_ready(o_block_ready),
            .i_samples(i_samples),.i_component(i_component),.i_mcu_x(i_mcu_x),.i_mcu_y(i_mcu_y),
            .i_block_index(i_block_index),.i_frame_last(i_frame_last),.i_capture_id(i_capture_id),
            .o_block_valid(o_block_valid),.i_block_ready(i_block_ready),.o_coeffs(o_coeffs),
            .o_component(o_component),.o_mcu_x(o_mcu_x),.o_mcu_y(o_mcu_y),
            .o_block_index(o_block_index),.o_frame_last(o_frame_last),.o_capture_id(o_capture_id),
            .o_column_valid(),.i_column_ready(1'b0),.o_column_data(),.o_column_index(),
            .o_column_component(),.o_column_mcu_x(),.o_column_mcu_y(),
            .o_column_block_index(),.o_column_frame_last(),.o_column_capture_id(),
            .i_row_valid(1'b0),.o_row_ready(),.i_row_data(64'd0),.i_row_index(3'd0));
    end else begin : g_legacy
        reg legacy_o_block_valid;
        reg [1023:0] legacy_o_coeffs;
        reg [1:0] legacy_o_component;
        reg [8:0] legacy_o_mcu_x;
        reg [8:0] legacy_o_mcu_y;
        reg [1:0] legacy_o_block_index;
        reg legacy_o_frame_last;
        reg [31:0] legacy_o_capture_id;
        assign o_block_valid=legacy_o_block_valid;
        assign o_coeffs=legacy_o_coeffs;
        assign o_component=legacy_o_component;
        assign o_mcu_x=legacy_o_mcu_x;
        assign o_mcu_y=legacy_o_mcu_y;
        assign o_block_index=legacy_o_block_index;
        assign o_frame_last=legacy_o_frame_last;
        assign o_capture_id=legacy_o_capture_id;
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_ROW = 2'd1;
    localparam [1:0] ST_COL = 2'd2;
    localparam [1:0] ST_OUT = 2'd3;

    reg [1:0] state;
    reg [3:0] phase;
    reg [511:0] samples;
    reg signed [15:0] row_data [0:63];
    reg signed [31:0] product [0:63];
    reg signed [31:0] half_a_q [0:7];
    reg signed [31:0] half_b_q [0:7];
    wire signed [31:0] half_a [0:7];
    wire signed [31:0] half_b [0:7];
    wire signed [31:0] final_sum [0:7];
    integer lane;
    integer tap;
    genvar lane_gen;
    for (lane_gen = 0; lane_gen < 8; lane_gen = lane_gen + 1) begin: add_tree
        wire signed [31:0] pair_a = product[lane_gen*8+0] + product[lane_gen*8+1];
        wire signed [31:0] pair_b = product[lane_gen*8+2] + product[lane_gen*8+3];
        wire signed [31:0] pair_c = product[lane_gen*8+4] + product[lane_gen*8+5];
        wire signed [31:0] pair_d = product[lane_gen*8+6] + product[lane_gen*8+7];
        // 蝶形加法产生一维变换的偶项
        assign half_a[lane_gen] = pair_a + pair_b;
        assign half_b[lane_gen] = pair_c + pair_d;
        assign final_sum[lane_gen] = half_a_q[lane_gen] + half_b_q[lane_gen];
    end

    // 系数来源 tools/jpeg_ref/table_data.json，规范 SHA-256
    // 9d31c1ac24802e101d4fc6ac9ad3e34cfe7227b9da3ff74a9bbeb34c9450357e
    function signed [15:0] dct_coeff;
        input [2:0] freq;
        input [2:0] sample;
        begin
            case ({freq, sample})
            6'd0: dct_coeff = 16'sd5793;
            6'd1: dct_coeff = 16'sd5793;
            6'd2: dct_coeff = 16'sd5793;
            6'd3: dct_coeff = 16'sd5793;
            6'd4: dct_coeff = 16'sd5793;
            6'd5: dct_coeff = 16'sd5793;
            6'd6: dct_coeff = 16'sd5793;
            6'd7: dct_coeff = 16'sd5793;
            6'd8: dct_coeff = 16'sd8035;
            6'd9: dct_coeff = 16'sd6811;
            6'd10: dct_coeff = 16'sd4551;
            6'd11: dct_coeff = 16'sd1598;
            6'd12: dct_coeff = -16'sd1598;
            6'd13: dct_coeff = -16'sd4551;
            6'd14: dct_coeff = -16'sd6811;
            6'd15: dct_coeff = -16'sd8035;
            6'd16: dct_coeff = 16'sd7568;
            6'd17: dct_coeff = 16'sd3135;
            6'd18: dct_coeff = -16'sd3135;
            6'd19: dct_coeff = -16'sd7568;
            6'd20: dct_coeff = -16'sd7568;
            6'd21: dct_coeff = -16'sd3135;
            6'd22: dct_coeff = 16'sd3135;
            6'd23: dct_coeff = 16'sd7568;
            6'd24: dct_coeff = 16'sd6811;
            6'd25: dct_coeff = -16'sd1598;
            6'd26: dct_coeff = -16'sd8035;
            6'd27: dct_coeff = -16'sd4551;
            6'd28: dct_coeff = 16'sd4551;
            6'd29: dct_coeff = 16'sd8035;
            6'd30: dct_coeff = 16'sd1598;
            6'd31: dct_coeff = -16'sd6811;
            6'd32: dct_coeff = 16'sd5793;
            6'd33: dct_coeff = -16'sd5793;
            6'd34: dct_coeff = -16'sd5793;
            6'd35: dct_coeff = 16'sd5793;
            6'd36: dct_coeff = 16'sd5793;
            6'd37: dct_coeff = -16'sd5793;
            6'd38: dct_coeff = -16'sd5793;
            6'd39: dct_coeff = 16'sd5793;
            6'd40: dct_coeff = 16'sd4551;
            6'd41: dct_coeff = -16'sd8035;
            6'd42: dct_coeff = 16'sd1598;
            6'd43: dct_coeff = 16'sd6811;
            6'd44: dct_coeff = -16'sd6811;
            6'd45: dct_coeff = -16'sd1598;
            6'd46: dct_coeff = 16'sd8035;
            6'd47: dct_coeff = -16'sd4551;
            6'd48: dct_coeff = 16'sd3135;
            6'd49: dct_coeff = -16'sd7568;
            6'd50: dct_coeff = 16'sd7568;
            6'd51: dct_coeff = -16'sd3135;
            6'd52: dct_coeff = -16'sd3135;
            6'd53: dct_coeff = 16'sd7568;
            6'd54: dct_coeff = -16'sd7568;
            6'd55: dct_coeff = 16'sd3135;
            6'd56: dct_coeff = 16'sd1598;
            6'd57: dct_coeff = -16'sd4551;
            6'd58: dct_coeff = 16'sd6811;
            6'd59: dct_coeff = -16'sd8035;
            6'd60: dct_coeff = 16'sd8035;
            6'd61: dct_coeff = -16'sd6811;
            6'd62: dct_coeff = 16'sd4551;
            6'd63: dct_coeff = -16'sd1598;
                default: dct_coeff = 16'sd0;
            endcase
        end
    endfunction


    assign o_block_ready = (state == ST_IDLE) && i_rst_n;

    // 按行列阶段依次计算定点余弦变换系数
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= ST_IDLE;
            phase <= 4'd0;
            samples <= 512'd0;
            legacy_o_block_valid <= 1'b0;
            legacy_o_coeffs <= 1024'd0;
            legacy_o_component <= 2'd0;
            legacy_o_mcu_x <= 9'd0;
            legacy_o_mcu_y <= 9'd0;
            legacy_o_block_index <= 2'd0;
            legacy_o_frame_last <= 1'b0;
            legacy_o_capture_id <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (i_block_valid) begin
                        samples <= i_samples;
                        legacy_o_component <= i_component;
                        legacy_o_mcu_x <= i_mcu_x;
                        legacy_o_mcu_y <= i_mcu_y;
                        legacy_o_block_index <= i_block_index;
                        legacy_o_frame_last <= i_frame_last;
                        legacy_o_capture_id <= i_capture_id;
                        phase <= 4'd0;
                        state <= ST_ROW;
                    end
                end
                ST_ROW: begin
                    // 乘积经过两级加法树流水线，下一拍完成求和与舍入
                    if (phase < 4'd8) begin
                        for (lane = 0; lane < 8; lane = lane + 1)
                            for (tap = 0; tap < 8; tap = tap + 1)
                                product[lane*8+tap] <=
                                    (32'sd0 + $signed({1'b0, samples[(phase*8+tap)*8 +: 8]}) - 32'sd128)
                                    * dct_coeff(lane[2:0], tap[2:0]);
                    end
                    if (phase >= 4'd1 && phase <= 4'd8)
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            half_a_q[lane] <= half_a[lane];
                            half_b_q[lane] <= half_b[lane];
                        end
                    if (phase >= 4'd2)
                        for (lane = 0; lane < 8; lane = lane + 1)
                            row_data[(phase-4'd2)*8+lane] <= round_q14(final_sum[lane]);
                    if (phase == 4'd9) begin
                        phase <= 4'd0;
                        state <= ST_COL;
                    end else
                        phase <= phase + 4'd1;
                end
                ST_COL: begin
                    // 列变换复用流水线乘积与加法树
                    if (phase < 4'd8) begin
                        for (lane = 0; lane < 8; lane = lane + 1)
                            for (tap = 0; tap < 8; tap = tap + 1)
                                product[lane*8+tap] <= row_data[tap*8+lane]
                                    * dct_coeff(phase[2:0], tap[2:0]);
                    end
                    if (phase >= 4'd1 && phase <= 4'd8)
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            half_a_q[lane] <= half_a[lane];
                            half_b_q[lane] <= half_b[lane];
                        end
                    if (phase >= 4'd2)
                        for (lane = 0; lane < 8; lane = lane + 1)
                            legacy_o_coeffs[((phase-4'd2)*8+lane)*16 +: 16] <=
                                round_q14(final_sum[lane]);
                    if (phase == 4'd9) begin
                        legacy_o_block_valid <= 1'b1;
                        state <= ST_OUT;
                    end else
                        phase <= phase + 4'd1;
                end
                ST_OUT: begin
                    if (i_block_ready) begin
                        legacy_o_block_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                default: begin
                    legacy_o_block_valid <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
    end endgenerate
endmodule
