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
    input [1:0] cfg_fusion_preset,
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
    localparam [9:0] FIRST_BLEND_CODE = KNEE_LOW + 8;

    reg [5:0] valid_pipe, sof_pipe, eol_pipe;
    wire advance = !valid_pipe[5] || m_ready;
    wire advance_payload = rst_n && !clear && advance;
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
    reg legacy0;
    // Stage 1: normalize short exposure to the long-exposure radiance scale.
    reg [13:0] long1 [0:3];
    reg [13:0] short1 [0:3];
    reg [9:0] raw_long1 [0:3];
    reg [14:0] threshold1 [0:3];
    reg [3:0] reliable1;
    reg legacy1, all_short_trusted1;
    // Stage 2: residual, clipping-knee weight and their aligned operands.
    reg signed [14:0] difference2 [0:3];
    reg [13:0] short2 [0:3];
    reg [13:0] residual2 [0:3];
    reg [14:0] threshold2 [0:3];
    reg [4:0] weight_long2 [0:3];
    reg [3:0] reliable2;
    reg use_any_hit2, all_short_trusted2;
    // Stage 3: blend product in MREG and registered lane evidence.
    reg [13:0] short3 [0:3];
    reg [3:0] direct_hit3, credible_hit3;
    reg all_short_trusted3;
    // Stage 4: rounded blend in PREG and shared motion reference.
    wire [33:0] rounded4 [0:3];
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
    wire corroborated_hit3 = (&credible_hit3[1:0]) || (&credible_hit3[3:2]) ||
                             ((|credible_hit3[1:0]) && (|credible_hit3[3:2]));
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
        // Calculate both signs in parallel: one carry chain plus a mux,
        // instead of comparator -> subtractor or subtractor -> negation.
        assign subtract_ls[15*lane +: 15] = {1'b0, long1[lane]} - {1'b0, short1[lane]};
        assign subtract_sl[14*lane +: 14] = short1[lane] - long1[lane];
        assign motion_hits[lane] = reliable2[lane] &&
                                  ({1'b0, residual2[lane]} > threshold2[lane]);
        // (16 - weight_long) * short + weight_long * long + 8
        // = 16 * short + weight_long * (long - short) + 8.
        // The difference uses the same normalized operands as the motion test.
        // MREG advances with short3; PREG adds its aligned bias one edge later.
        // Payload validity flushes on reset and clear, so storage needs no RST.
        fdct_mac19s14s_z33s_p34_m1p1 u_blend (
            .CLK(clk), .CE(advance_payload), .RST(1'b0),
            .A({{4{difference2[lane][14]}}, difference2[lane]}),
            .Y({9'd0, weight_long2[lane]}),
            .Z({15'd0, short3[lane], 4'd8}), .P(rounded4[lane])
        );
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
        if (advance_payload) begin
            ratio0 <= cfg_ratio_log2;
            motion_base0 <= cfg_motion_base;
            motion_shift0 <= cfg_motion_shift;
            legacy0 <= cfg_fusion_preset != 2'd0;
            reliable1 <= reliable0;
            reliable2 <= reliable1;
            legacy1 <= legacy0;
            // Eight corrected SHORT codes are 128 codes at the production ratio.
            all_short_trusted1 <= (|short0[0][9:3]) && (|short0[1][9:3]) &&
                                  (|short0[2][9:3]) && (|short0[3][9:3]);
            all_short_trusted2 <= all_short_trusted1;
            all_short_trusted3 <= all_short_trusted2;
            // Preserve the original single-hit policy whenever any lane has
            // nonzero SHORT weight. Otherwise the static blend is all LONG.
            use_any_hit2 <= legacy1 ||
                            (raw_long1[0] >= FIRST_BLEND_CODE) ||
                            (raw_long1[1] >= FIRST_BLEND_CODE) ||
                            (raw_long1[2] >= FIRST_BLEND_CODE) ||
                            (raw_long1[3] >= FIRST_BLEND_CODE);
            motion4 <= (|direct_hit3) || (all_short_trusted3 && corroborated_hit3);
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

                difference2[k] <= subtract_ls[k*15 +: 15];
                short2[k] <= short1[k];
                residual2[k] <= subtract_ls[k*15+14]
                                ? subtract_sl[k*14 +: 14]
                                : subtract_ls[k*15 +: 14];
                threshold2[k] <= threshold1[k];
                weight_long2[k] <= 5'd16 - short_weight(raw_long1[k]);

                short3[k] <= short2[k];
                direct_hit3[k] <= motion_hits[k] && (use_any_hit2 || (|residual2[k][13:7]));
                credible_hit3[k] <= motion_hits[k] && (|residual2[k][13:6]);

                short4[k] <= short3[k];

                raw5[k*14 +: 14] <= motion4 ? short4[k] : rounded4[k][17:4];
            end
        end
    end
endmodule
