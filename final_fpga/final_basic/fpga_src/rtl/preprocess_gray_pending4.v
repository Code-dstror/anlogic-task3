`timescale 1ns / 1ps

// Four RGB888 lanes; BT.601 integer luma with round-to-nearest.
// Three advance edges with the existing MREG/PREG DSP MAC; clear cancels a private epoch.
// Synchronous clear/cancel flushes only the original valid/control pipeline.
// It must not reach the MAC asynchronous RST: parent fault may pulse between
// clock edges while a source advances a legally accepted beat. Invalid DSP
// data drains before the first subsequent valid output; global rst_n alone
// resets DSP storage asynchronously.
module preprocess_gray_pending4 #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer NEUTRAL_TAP_ENABLE = 0
) (
    input wire clk, rst_n, clear, enable,
    input wire [12:0] width, height,
    input wire s_valid,
    output wire s_ready,
    input wire [95:0] s_data,
    input wire s_sof, s_eol,
    output wire m_valid,
    input wire m_ready,
    output wire [95:0] m_data,
    output wire m_sof, m_eol,
    output wire [31:0] m_luma,
    output wire [95:0] m_original_data,
    output wire o_pending
);
    reg [2:0] valid_pipe, sof_pipe, eol_pipe, enable_pipe;
    reg [95:0] bypass0, bypass1, original2;
    // Stored accepted tokens, including stages not yet presented downstream.
    // Functional clear still acts on the original edge; it cannot fake quiet.
    assign o_pending = |valid_pipe;
    wire advance = !valid_pipe[2] || m_ready;
    assign s_ready = rst_n && !clear && advance;
    assign m_valid = rst_n && !clear && valid_pipe[2];
    assign m_original_data = NEUTRAL_TAP_ENABLE ? original2 : 96'd0;
    assign m_sof = sof_pipe[2];
    assign m_eol = eol_pipe[2];
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        wire signed [8:0] red_green =
            $signed({1'b0,s_data[lane*24+16 +:8]}) -
            $signed({1'b0,s_data[lane*24+8 +:8]});
        wire signed [8:0] blue_green =
            $signed({1'b0,bypass0[lane*24 +:8]}) -
            $signed({1'b0,bypass0[lane*24+8 +:8]});
        wire [33:0] red_green_sum, rounded_y;
        // MREG at stage0, PREG at stage1; green is aligned by bypass0.
        fdct_mac19s14s_z33s_p34_m1p1 u_red_green (
            .CLK(clk),.CE(advance),.RST(!rst_n),
            .A({{10{red_green[8]}},red_green}),.Y(14'd77),
            .Z({17'd0,bypass0[lane*24+8 +:8],8'd128}),.P(red_green_sum));
        // MREG at stage1, PREG at stage2. Full sum is 128..65408.
        fdct_mac19s14s_z33s_p34_m1p1 u_blue_green (
            .CLK(clk),.CE(advance),.RST(!rst_n),
            .A({{10{blue_green[8]}},blue_green}),.Y(14'd29),
            .Z(red_green_sum[32:0]),.P(rounded_y));
        assign m_luma[lane*8 +:8] = rounded_y[15:8];
        assign m_data[lane*24 +:24] = enable_pipe[2] ?
            {rounded_y[15:8],rounded_y[15:8],rounded_y[15:8]} : original2[lane*24 +:24];
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 0; sof_pipe <= 0; eol_pipe <= 0; enable_pipe <= 0;
        end else if (clear) begin
            valid_pipe <= 0; sof_pipe <= 0; eol_pipe <= 0; enable_pipe <= 0;
        end else if (advance) begin
            valid_pipe <= {valid_pipe[1:0], s_valid};
            sof_pipe <= {sof_pipe[1:0], s_sof};
            eol_pipe <= {eol_pipe[1:0], s_eol};
            enable_pipe <= {enable_pipe[1:0], enable};
        end
    end
    always @(posedge clk) begin
        if (advance) begin
            bypass0 <= s_data;
            bypass1 <= bypass0;
            original2 <= bypass1;
        end
    end
endmodule
