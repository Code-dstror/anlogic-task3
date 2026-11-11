`timescale 1ns / 1ps

// Stage3-only common color path. WB/CCM, shared Tone96 and Gamma are separate
// handshake stages; Stage2's frozen linear color source is never modified.
module wide_color_pipeline #(
    parameter integer GAMMA_BYPASS = 0,
    parameter signed [10:0] CCM00 = 11'sd256, CCM01 = 0, CCM02 = 0,
    parameter signed [10:0] CCM10 = 0, CCM11 = 11'sd256, CCM12 = 0,
    parameter signed [10:0] CCM20 = 0, CCM21 = 0, CCM22 = 11'sd256
) (
    input wire clk, input wire rst_n,
    input wire cfg_hdr, input wire [3:0] cfg_tone_shift,
    input wire [1:0] cfg_tone_preset,
    input wire [29:0] cfg_wb_gains,
    input wire [167:0] s_data, input wire s_valid, output wire s_ready,
    input wire s_sof, input wire s_eol,
    output wire [95:0] m_data, output wire m_valid, input wire m_ready,
    output wire m_sof, output wire m_eol,
    output reg [31:0] stat_beats, output reg [31:0] stat_frames,
    output reg [31:0] stat_saturated
);
    // cfg_tone_shift remains an interface compatibility field. HDR page zero
    // uses the original WB scale and Tone96 curve. SDR always uses RGB10.
    // Only the exact identity matrix uses this specialization. All signed
    // configurable matrix products and clipping retain the general path.
    localparam integer IDENTITY_CCM = CCM00==256 && CCM01==0 && CCM02==0 &&
        CCM10==0 && CCM11==256 && CCM12==0 && CCM20==0 && CCM21==0 && CCM22==256;
    localparam integer PRE_LAST = IDENTITY_CCM ? 2 : 4;
    reg hdr;
    reg [1:0] preset;
    reg [29:0] gains;
    reg [4:0] pre_valid, pre_sof, pre_eol, pre_hdr, pre_clipped;
    reg [9:0] pre_preset;
    reg normalize0, normalize1;
    wire tone_input_ready;
    wire pre_advance = !rst_n || !pre_valid[PRE_LAST] || tone_input_ready;
    wire input_fire = s_valid && s_ready;
    wire hdr_input = s_sof ? cfg_hdr : hdr;
    wire [1:0] preset_input = s_sof ? cfg_tone_preset : preset;
    wire [29:0] gains_input = s_sof ? cfg_wb_gains : gains;
    wire [32:0] wb_round_bias = normalize0 ? 33'd512 : 33'd128;
    wire [167:0] corrected_rgb;
    wire [11:0] wb_clip, ccm_clip;
    wire [23:0] highlight_weight;

    wire [119:0] tone_rgb;
    wire tone_valid, tone_ready, tone_sof, tone_eol, tone_clipped;
    reg [1:0] gamma_valid, gamma_sof, gamma_eol, gamma_clipped;
    wire gamma_advance = !rst_n || !gamma_valid[1] || m_ready;
    wire [95:0] gamma_rgb;
    reg [95:0] rgb_output;

    assign s_ready = rst_n && pre_advance;
    assign tone_ready = rst_n && gamma_advance;
    assign m_data = rgb_output;
    assign m_valid = rst_n && gamma_valid[1];
    assign m_sof = gamma_sof[1];
    assign m_eol = gamma_eol[1];

    always @(posedge clk) begin
        if (!rst_n) begin
            hdr <= 0;
            preset <= 0;
            gains <= {3{10'd256}};
            pre_valid <= 0; pre_sof <= 0; pre_eol <= 0;
            pre_hdr <= 0; pre_clipped <= 0;
            pre_preset <= 0; normalize0 <= 0; normalize1 <= 0;
            gamma_valid <= 0; gamma_sof <= 0; gamma_eol <= 0;
            gamma_clipped <= 0; rgb_output <= 0;
            stat_beats <= 0; stat_frames <= 0; stat_saturated <= 0;
        end else begin
            if (pre_advance) begin
                pre_valid <= {pre_valid[3:0],s_valid};
                pre_sof <= {pre_sof[3:0],s_sof};
                pre_eol <= {pre_eol[3:0],s_eol};
                pre_hdr <= {pre_hdr[3:0],hdr_input};
                pre_preset <= {pre_preset[7:0],preset_input};
                normalize0 <= hdr_input && preset_input != 0;
                normalize1 <= normalize0;
                pre_clipped[0] <= 0;
                if (IDENTITY_CCM) begin
                    pre_clipped[1] <= 0;
                    pre_clipped[2] <= |wb_clip;
                    pre_clipped[3] <= pre_clipped[2];
                    pre_clipped[4] <= pre_clipped[3];
                end else begin
                    pre_clipped[1] <= |wb_clip;
                    pre_clipped[2] <= pre_clipped[1];
                    pre_clipped[3] <= pre_clipped[2];
                    pre_clipped[4] <= pre_clipped[3] || |ccm_clip;
                end
            end
            if (input_fire && s_sof) begin
                hdr <= cfg_hdr;
                preset <= cfg_tone_preset;
                gains <= cfg_wb_gains;
            end
            if (gamma_advance) begin
                gamma_valid <= {gamma_valid[0],tone_valid};
                gamma_sof <= {gamma_sof[0],tone_sof};
                gamma_eol <= {gamma_eol[0],tone_eol};
                gamma_clipped <= {gamma_clipped[0],tone_clipped};
                rgb_output <= gamma_rgb;
            end
            if (m_valid && m_ready) begin
                stat_beats <= stat_beats + 1'b1;
                if (m_sof) stat_frames <= stat_frames + 1'b1;
                if (gamma_clipped[1]) stat_saturated <= stat_saturated + 1'b1;
            end
        end
    end

    hdr_tone96_shared4 u_tone96 (
        .clk(clk),.rst_n(rst_n),.clear(1'b0),
        .s_data(corrected_rgb),.s_hdr(pre_hdr[PRE_LAST]),
        .s_preset(pre_preset[PRE_LAST*2+:2]),.s_highlight_weight(highlight_weight),
        .s_valid(rst_n && pre_valid[PRE_LAST]),.s_ready(tone_input_ready),
        .s_sof(pre_sof[PRE_LAST]),.s_eol(pre_eol[PRE_LAST]),.s_clipped(pre_clipped[PRE_LAST]),
        .m_data(tone_rgb),.m_valid(tone_valid),.m_ready(tone_ready),
        .m_sof(tone_sof),.m_eol(tone_eol),.m_clipped(tone_clipped)
    );

    genvar pixel, channel, term;
    generate for (pixel=0; pixel<4; pixel=pixel+1) begin : lane
        // A low raw channel protects hue. At high values the minimum sets
        // the floor weight. Buckets of 64 raw codes keep both compares narrow.
        wire [7:0] raw_r_bucket=s_data[pixel*42+34+:8];
        wire [7:0] raw_g_bucket=s_data[pixel*42+20+:8];
        wire [7:0] raw_b_bucket=s_data[pixel*42+6+:8];
        reg [7:0] min_rg0,raw_b0,minimum1;
        reg [5:0] weight2,weight3,weight4;
        wire [7:0] offset=minimum1-8'd188;
        always @(posedge clk) if (pre_advance) begin
            min_rg0 <= raw_r_bucket < raw_g_bucket ? raw_r_bucket : raw_g_bucket;
            raw_b0 <= raw_b_bucket;
            minimum1 <= min_rg0 < raw_b0 ? min_rg0 : raw_b0;
            weight2 <= minimum1 < 8'd188 ? 6'd0 :
                minimum1 >= 8'd220 ? 6'd32 : offset[5:0];
            weight3 <= weight2;
            weight4 <= weight3;
        end
        assign highlight_weight[pixel*6+:6]=IDENTITY_CCM ? weight2 : weight4;

        if (IDENTITY_CCM) begin : g_identity
            for (channel=0; channel<3; channel=channel+1) begin : wb
                wire [9:0] gain=gains_input[(2-channel)*10 +:10];
                wire [33:0] rounded;
                // A/Y are zero extended before entering the signed MAC.
                // Even with the HDR bias, 16383*1023+512 is below 2^24.
                // Z is applied after MREG. normalize0 follows the product
                // into that register and normalize1 selects the PREG slice.
                wire [15:0] scaled=rounded[23:8];
                wire [13:0] maximum=pre_hdr[1] ? 14'd16383 : 14'd1023;
                wire clipped=!normalize1 && (|scaled[15:14] ||
                    (!pre_hdr[1] && |scaled[13:10]));
                reg [13:0] value,delayed,corrected;
                fdct_mac19s14s_z33s_p34_m1p1 u_gain_round (
                    .CLK(clk),.CE(pre_advance),.RST(!rst_n),
                    .A({5'd0,s_data[pixel*42+channel*14 +:14]}),
                    .Y({4'd0,gain}),.Z(wb_round_bias),.P(rounded));
                // MREG/PREG consume edges0/1, WB clamp edge2 and the original
                // identity value consumes edges3/4. Capacity and CE are five
                // edges exactly as in the general WB/CCM path.
                always @(posedge clk)if(pre_advance)begin
                    value<=normalize1 ? rounded[23:10] :
                        clipped ? maximum : scaled[13:0];
                    delayed<=value;
                    corrected<=delayed;
                end
                assign wb_clip[pixel*3+channel]=clipped;
                assign ccm_clip[pixel*3+channel]=1'b0;
                // Identity CCM needs no extra two-cycle matrix delay.
                assign corrected_rgb[pixel*42+channel*14 +:14]=value;
                gamma_lut_10to8 #(.C_GAMMA_LINEAR_BYPASS(GAMMA_BYPASS),.C_USE_CE(1)) u_gamma (
                    .i_clk(clk),.i_rstn(rst_n),.i_index(tone_rgb[pixel*30+channel*10 +:10]),
                    .o_value(gamma_rgb[pixel*24+channel*8 +:8]),.i_ce(gamma_advance));
            end
        end else begin : g_general
        wire [41:0] wb_rgb;
        for (channel=0; channel<3; channel=channel+1) begin : wb
            wire [9:0] gain = gains_input[(2-channel)*10 +: 10];
            wire [23:0] product;
            reg [13:0] value;
            reg hdr_q;
            wire [24:0] rounded = {1'b0,product} + wb_round_bias[24:0];
            wire [16:0] scaled = rounded[24:8];
            wire [13:0] maximum = hdr_q ? 14'd16383 : 14'd1023;
            td_dsp_mult #(.A_WIDTH(14),.B_WIDTH(10),.INPUT_FORMAT("UNSIGNED")) u_gain (
                .clk(clk),.rst_n(rst_n),.en(pre_advance),
                .a(s_data[pixel*42+channel*14 +: 14]),.b(gain),.p(product));
            always @(posedge clk) if (pre_advance) begin
                hdr_q <= hdr_input;
                value <= normalize0 ? rounded[23:10] :
                    scaled > {3'd0,maximum} ? maximum : scaled[13:0];
            end
            assign wb_clip[pixel*3+channel] = !normalize0 && scaled > {3'd0,maximum};
            assign wb_rgb[channel*14 +: 14] = value;
        end
        for (channel=0; channel<3; channel=channel+1) begin : ccm
            localparam signed [10:0] C0 = channel==2 ? CCM00 : channel==1 ? CCM10 : CCM20;
            localparam signed [10:0] C1 = channel==2 ? CCM01 : channel==1 ? CCM11 : CCM21;
            localparam signed [10:0] C2 = channel==2 ? CCM02 : channel==1 ? CCM12 : CCM22;
            wire [77:0] products;
            for (term=0; term<3; term=term+1) begin : item
                localparam signed [10:0] COEFF = term==0 ? C0 : term==1 ? C1 : C2;
                if (COEFF == 0) begin : zero
                    assign products[term*26 +: 26] = 26'd0;
                end else if (COEFF == 256) begin : identity
                    reg [25:0] delayed;
                    always @(posedge clk) if (pre_advance)
                        delayed <= {4'd0,wb_rgb[(2-term)*14 +: 14],8'd0};
                    assign products[term*26 +: 26] = delayed;
                end else begin : multiply
                    td_dsp_mult #(.A_WIDTH(15),.B_WIDTH(11)) u_coefficient (
                        .clk(clk),.rst_n(rst_n),.en(pre_advance),
                        .a({1'b0,wb_rgb[(2-term)*14 +: 14]}),.b(COEFF),
                        .p(products[term*26 +: 26]));
                end
            end
            wire signed [25:0] p0 = products[0 +: 26];
            wire signed [25:0] p1 = products[26 +: 26];
            wire signed [25:0] p2 = products[52 +: 26];
            reg signed [27:0] partial;
            reg signed [25:0] third;
            reg [13:0] corrected;
            wire signed [28:0] sum = partial + third + 29'sd128;
            wire signed [28:0] shifted = sum >>> 8;
            wire [13:0] maximum = pre_hdr[3] ? 14'd16383 : 14'd1023;
            always @(posedge clk) if (pre_advance) begin
                partial <= p0 + p1;
                third <= p2;
                corrected <= shifted < 0 ? 14'd0 :
                    shifted > $signed({1'b0,maximum}) ? maximum : shifted[13:0];
            end
            assign ccm_clip[pixel*3+channel] = shifted < 0 || shifted > $signed({1'b0,maximum});
            assign corrected_rgb[pixel*42+channel*14 +: 14] = corrected;
            gamma_lut_10to8 #(.C_GAMMA_LINEAR_BYPASS(GAMMA_BYPASS),.C_USE_CE(1)) u_gamma (
                .i_clk(clk),.i_rstn(rst_n),.i_index(tone_rgb[pixel*30+channel*10 +: 10]),
                .o_value(gamma_rgb[pixel*24+channel*8 +: 8]),.i_ce(gamma_advance));
        end
        end
    end endgenerate
endmodule
