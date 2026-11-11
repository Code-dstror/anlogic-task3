// Paired-exposure, four-pixel/clock RAW10 -> linear RAW14 merge.
// The pair/DDR controller owns exposure confirmation and freezes configuration.
module hdr_merge4 #(
    parameter KNEE_LOW = 768,
    parameter KNEE_HIGH = 896
) (
    input clk,
    input rst_n,
    input clear,
    input [2:0] cfg_ratio_log2,
    input [9:0] cfg_black_long,
    input [9:0] cfg_black_short,
    input [13:0] cfg_motion_base,
    input [3:0] cfg_motion_shift,
    input [39:0] s_long,
    input [39:0] s_short,
    input s_valid,
    output s_ready,
    input s_sof,
    input s_eol,
    output [55:0] m_raw,
    output m_valid,
    input m_ready,
    output m_sof,
    output m_eol,
    output [3:0] m_motion
);
    // The crossfade uses sixteen 8-code steps; parameters must retain a
    // 128-code separation. These are elaboration parameters, not live CSRs.
    localparam [9:0] LOW_CODE = KNEE_LOW;
    localparam [9:0] HIGH_CODE = KNEE_HIGH;

    reg [5:0] valid_pipe, sof_pipe, eol_pipe;
    wire advance = !valid_pipe[5] || m_ready;
    assign s_ready = rst_n && !clear && advance;
    assign m_valid = rst_n && !clear && valid_pipe[5];
    assign m_sof = sof_pipe[5];
    assign m_eol = eol_pipe[5];

    // Stage 0: black subtraction and capture the per-pair configuration.
    reg [9:0] long0 [0:3];
    reg [9:0] short0 [0:3];
    reg [9:0] raw_long0 [0:3];
    reg [3:0] reliable0;
    reg [2:0] ratio0;
    reg [13:0] motion_base0;
    reg [3:0] motion_shift0;
    // Stage 1: normalize short exposure to the long-exposure radiance scale.
    reg [13:0] long1 [0:3];
    reg [13:0] short1 [0:3];
    reg [9:0] raw_long1 [0:3];
    reg [14:0] threshold1 [0:3];
    reg [3:0] reliable1;
    // Stage 2: residual, clipping-knee weight and their aligned operands.
    reg [13:0] long2 [0:3];
    reg [13:0] short2 [0:3];
    reg [13:0] residual2 [0:3];
    reg [14:0] threshold2 [0:3];
    reg [4:0] weight_short2 [0:3];
    reg [4:0] weight_long2 [0:3];
    reg [3:0] reliable2;
    // Stage 3: bounded blend products and a shared four-lane motion decision.
    reg [17:0] product_long3 [0:3];
    reg [17:0] product_short3 [0:3];
    reg [13:0] short3 [0:3];
    reg motion3;
    // Stage 4: sum and round; keep the short reference aligned.
    reg [18:0] rounded4 [0:3];
    reg [13:0] short4 [0:3];
    reg motion4;
    // Stage 5: registered selection between static blend and short reference.
    reg [55:0] raw5;
    reg [3:0] motion5;
    assign m_raw = raw5;
    assign m_motion = motion5;

    function [4:0] short_weight;
        input [9:0] raw_long;
        reg [9:0] difference;
        begin
            difference = raw_long - LOW_CODE;
            if (raw_long <= LOW_CODE)
                short_weight = 5'd0;
            else if (raw_long >= HIGH_CODE)
                short_weight = 5'd16;
            else
                short_weight = {1'b0, difference[6:3]};
        end
    endfunction

    wire [59:0] subtract_ls;
    wire [55:0] subtract_sl;
    wire [3:0] motion_hits;
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        // Calculate both signs in parallel: one carry chain plus a mux,
        // instead of comparator -> subtractor or subtractor -> negation.
        assign subtract_ls[15*lane +: 15] = {1'b0, long1[lane]} - {1'b0, short1[lane]};
        assign subtract_sl[14*lane +: 14] = short1[lane] - long1[lane];
        assign motion_hits[lane] = reliable2[lane] &&
                                  ({1'b0, residual2[lane]} > threshold2[lane]);
    end endgenerate

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            valid_pipe <= 6'd0;
            sof_pipe <= 6'd0;
            eol_pipe <= 6'd0;
        end else if (advance) begin
            valid_pipe <= {valid_pipe[4:0], s_valid && s_ready};
            sof_pipe <= {sof_pipe[4:0], s_sof};
            eol_pipe <= {eol_pipe[4:0], s_eol};
        end
    end

    integer k;
    // Payload registers intentionally have no reset tree. valid_pipe flushes
    // every in-flight payload; all six stages stop together on output stall.
    always @(posedge clk) begin
        if (rst_n && !clear && advance) begin
            ratio0 <= cfg_ratio_log2;
            motion_base0 <= cfg_motion_base;
            motion_shift0 <= cfg_motion_shift;
            reliable1 <= reliable0;
            reliable2 <= reliable1;
            motion3 <= |motion_hits;
            motion4 <= motion3;
            motion5 <= {4{motion4}};
            for (k = 0; k < 4; k = k + 1) begin
                long0[k] <= s_long[k*10 +: 10] > cfg_black_long
                            ? s_long[k*10 +: 10] - cfg_black_long : 10'd0;
                short0[k] <= s_short[k*10 +: 10] > cfg_black_short
                             ? s_short[k*10 +: 10] - cfg_black_short : 10'd0;
                raw_long0[k] <= s_long[k*10 +: 10];
                reliable0[k] <= s_long[k*10 +: 10] < HIGH_CODE &&
                                {1'b0, s_short[k*10 +: 10]} >
                                ({1'b0, cfg_black_short} + 11'd4);

                long1[k] <= {4'd0, long0[k]};
                short1[k] <= {4'd0, short0[k]} << ratio0;
                raw_long1[k] <= raw_long0[k];
                threshold1[k] <= {1'b0, motion_base0} +
                                 ({5'd0, long0[k]} >> motion_shift0);

                long2[k] <= long1[k];
                short2[k] <= short1[k];
                residual2[k] <= subtract_ls[k*15+14]
                                ? subtract_sl[k*14 +: 14]
                                : subtract_ls[k*15 +: 14];
                threshold2[k] <= threshold1[k];
                weight_short2[k] <= short_weight(raw_long1[k]);
                weight_long2[k] <= 5'd16 - short_weight(raw_long1[k]);

                product_long3[k] <= long2[k] * weight_long2[k];
                product_short3[k] <= short2[k] * weight_short2[k];
                short3[k] <= short2[k];

                rounded4[k] <= {1'b0, product_long3[k]} +
                               {1'b0, product_short3[k]} + 19'd8;
                short4[k] <= short3[k];

                raw5[k*14 +: 14] <= motion4 ? short4[k] : rounded4[k][17:4];
            end
        end
    end
endmodule
