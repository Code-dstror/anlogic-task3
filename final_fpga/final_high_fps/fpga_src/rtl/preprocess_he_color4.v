`timescale 1ns / 1ps

// Paired RGB/Y/LUT adapter. History qualification belongs to its upstream owner.
// Four reconstruction stages feed the existing three-stage exact Q8 Y core.
module preprocess_he_color4 (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire enable,
    input wire s_valid,
    output wire s_ready,
    input wire [95:0] s_data,
    input wire [31:0] s_luma,
    input wire [31:0] s_mapped_luma,
    input wire s_sof,
    input wire s_eol,
    output wire m_valid,
    input wire m_ready,
    output wire [95:0] m_data,
    output wire [31:0] m_luma,
    output wire m_sof,
    output wire m_eol,
    output wire m_enable
);
    reg [3:0] valid_pipe, sof_pipe, eol_pipe, enable_pipe;
    reg [95:0] original_rgb, delayed_rgb, rebuilt_rgb;
    reg signed [8:0] delta [0:3];
    reg signed [6:0] bounded_delta [0:3];
    // Captured with the three modular sums, never taken from a live input.
    reg [3:0] sum_delta_negative;
    reg [8:0] red_sum [0:3];
    reg [8:0] green_sum [0:3];
    reg [8:0] blue_sum [0:3];
    reg [2:0] luma_enable_pipe;
    wire luma_ready;
    wire advance = !valid_pipe[3] || luma_ready;
    assign s_ready = rst_n && !clear && advance;
    assign m_enable = luma_enable_pipe[2];

    // Global advance freezes all reconstruction data and tags together.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 4'd0;
            sof_pipe <= 4'd0;
            eol_pipe <= 4'd0;
            enable_pipe <= 4'd0;
            luma_enable_pipe <= 3'd0;
        end else if (clear) begin
            valid_pipe <= 4'd0;
            sof_pipe <= 4'd0;
            eol_pipe <= 4'd0;
            enable_pipe <= 4'd0;
            luma_enable_pipe <= 3'd0;
        end else begin
            if (advance) begin
                valid_pipe <= {valid_pipe[2:0], s_valid};
                sof_pipe <= {sof_pipe[2:0], s_sof};
                eol_pipe <= {eol_pipe[2:0], s_eol};
                enable_pipe <= {enable_pipe[2:0], enable};
            end
            // This is the exact advance used inside preprocess_gray4.
            if (luma_ready)
                luma_enable_pipe <= {luma_enable_pipe[1:0], enable_pipe[3]};
        end
    end

    always @(posedge clk) begin
        if (advance) begin
            original_rgb <= s_data;
            delayed_rgb <= original_rgb;
        end
    end

    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        // Delta clips to -32..32. Modulo512 RGB+delta is enough when its
        // upper bit is decoded with one shared, equally delayed delta sign.
        always @(posedge clk) begin
            if (advance) begin
                delta[lane] <= $signed({1'b0, s_mapped_luma[lane*8 +: 8]}) -
                    $signed({1'b0, s_luma[lane*8 +: 8]});
                if (!enable_pipe[0]) bounded_delta[lane] <= 7'sd0;
                else if (delta[lane] > 9'sd32) bounded_delta[lane] <= 7'sd32;
                else if (delta[lane] < -9'sd32) bounded_delta[lane] <= -7'sd32;
                else bounded_delta[lane] <= delta[lane][6:0];
                sum_delta_negative[lane] <= bounded_delta[lane][6];
                red_sum[lane] <= $signed({1'b0, delayed_rgb[lane*24+16 +: 8]}) +
                    $signed({{2{bounded_delta[lane][6]}}, bounded_delta[lane]});
                green_sum[lane] <= $signed({1'b0, delayed_rgb[lane*24+8 +: 8]}) +
                    $signed({{2{bounded_delta[lane][6]}}, bounded_delta[lane]});
                blue_sum[lane] <= $signed({1'b0, delayed_rgb[lane*24 +: 8]}) +
                    $signed({{2{bounded_delta[lane][6]}}, bounded_delta[lane]});
                rebuilt_rgb[lane*24+16 +: 8] <= red_sum[lane][8] ?
                    {8{!sum_delta_negative[lane]}} : red_sum[lane][7:0];
                rebuilt_rgb[lane*24+8 +: 8] <= green_sum[lane][8] ?
                    {8{!sum_delta_negative[lane]}} : green_sum[lane][7:0];
                rebuilt_rgb[lane*24 +: 8] <= blue_sum[lane][8] ?
                    {8{!sum_delta_negative[lane]}} : blue_sum[lane][7:0];
            end
        end
    end endgenerate

    // Keep RGB in color; independently recompute exact Y from the clamped RGB.
    preprocess_gray4 u_rebuilt_luma (
        .clk(clk), .rst_n(rst_n), .clear(clear), .enable(1'b0),
        .width(13'd0), .height(13'd0),
        .s_valid(valid_pipe[3]), .s_ready(luma_ready), .s_data(rebuilt_rgb),
        .s_sof(sof_pipe[3]), .s_eol(eol_pipe[3]),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
        .m_sof(m_sof), .m_eol(m_eol), .m_luma(m_luma), .m_original_data()
    );
endmodule
