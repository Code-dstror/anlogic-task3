// Exact alpha=1/2 brightness blend, with luma arithmetic in eight existing DSPs.
// Five accepted advance edges, identical to the frozen color-filter leaf.
// Synchronous clear/cancel flushes only the original valid/control pipeline.
// It must not reach the MAC asynchronous RST: parent fault may pulse between
// clock edges while a source advances a legally accepted beat. Invalid DSP
// data drains before the first subsequent valid output; global rst_n alone
// resets DSP storage asynchronously.
module stage3_luma_blend4 (
    input clk, rst_n, clear,
    input s_valid, output s_ready,
    input [95:0] s_rgb, input [31:0] s_center_y, s_filtered_y,
    input s_sof, s_eol,
    output m_valid, input m_ready,
    output [95:0] m_rgb, output [31:0] m_y, output m_sof, m_eol
);
    reg [4:0] valid_pipe, sof_pipe, eol_pipe;
    reg [95:0] rgb0, rgb1, rgb2, rgb3, rgb4;
    reg signed [8:0] delta [0:3];
    wire advance = !valid_pipe[4] || m_ready;
    wire run = rst_n && !clear;
    assign s_ready = run && advance;
    assign m_valid = run && valid_pipe[4];
    assign m_rgb = rgb4;
    assign m_sof = sof_pipe[4];
    assign m_eol = eol_pipe[4];

    function signed [8:0] half_delta;
        input [7:0] filtered, center;
        reg signed [9:0] difference;
        begin
            difference = $signed({1'b0,filtered}) - $signed({1'b0,center});
            if (difference < 0) half_delta = -((-difference + 10'sd1) >>> 1);
            else half_delta = (difference + 10'sd1) >>> 1;
        end
    endfunction
    function [7:0] saturated;
        input [7:0] component;
        input signed [8:0] adjustment;
        reg signed [9:0] corrected;
        begin
            corrected = $signed({1'b0,component}) + adjustment;
            if (corrected < 0) saturated = 8'd0;
            else if (corrected > 255) saturated = 8'd255;
            else saturated = corrected[7:0];
        end
    endfunction

    genvar lane;
    generate for (lane=0; lane<4; lane=lane+1) begin : g_lane
        wire signed [8:0] red_minus_green =
            $signed({1'b0,rgb1[lane*24+16 +:8]}) -
            $signed({1'b0,rgb1[lane*24+8 +:8]});
        wire signed [8:0] blue_minus_green =
            $signed({1'b0,rgb2[lane*24 +:8]}) -
            $signed({1'b0,rgb2[lane*24+8 +:8]});
        wire [33:0] red_green_sum, rounded_y;

        // The existing official macro has MREG and PREG, but no ZREG.
        // MREG captures 77*(R-G) at stage2. At stage3, PREG adds 256*G+128
        // from rgb2, aligned to that MREG. This is 77*R+179*G+128.
        fdct_mac19s14s_z33s_p34_m1p1 u_red_green (
            .CLK(clk), .CE(advance), .RST(!rst_n),
            .A({{10{red_minus_green[8]}},red_minus_green}), .Y(14'd77),
            .Z({17'd0,rgb2[lane*24+8 +:8],8'd128}), .P(red_green_sum));

        // MREG captures 29*(B-G) one edge later, at stage3. PREG at stage4
        // adds stage3's first MAC output: 77*R+150*G+29*B+128 exactly.
        // Maximum 65408 fits16 bits; the minimum is128. No clipping/overflow.
        fdct_mac19s14s_z33s_p34_m1p1 u_blue_green (
            .CLK(clk), .CE(advance), .RST(!rst_n),
            .A({{10{blue_minus_green[8]}},blue_minus_green}), .Y(14'd29),
            .Z(red_green_sum[32:0]), .P(rounded_y));
        assign m_y[lane*8 +:8] = rounded_y[15:8];

        always @(posedge clk) if (advance) begin
            delta[lane] <= half_delta(s_filtered_y[lane*8 +:8],s_center_y[lane*8 +:8]);
            rgb1[lane*24 +:8] <= saturated(rgb0[lane*24 +:8],delta[lane]);
            rgb1[lane*24+8 +:8] <= saturated(rgb0[lane*24+8 +:8],delta[lane]);
            rgb1[lane*24+16 +:8] <= saturated(rgb0[lane*24+16 +:8],delta[lane]);
        end
    end endgenerate
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            valid_pipe <= 0; sof_pipe <= 0; eol_pipe <= 0;
        end else if (advance) begin
            valid_pipe <= {valid_pipe[3:0],s_valid};
            sof_pipe <= {sof_pipe[3:0],s_sof};
            eol_pipe <= {eol_pipe[3:0],s_eol};
        end
        if (advance) begin
            rgb0 <= s_rgb; rgb2 <= rgb1; rgb3 <= rgb2; rgb4 <= rgb3;
        end
    end
endmodule
