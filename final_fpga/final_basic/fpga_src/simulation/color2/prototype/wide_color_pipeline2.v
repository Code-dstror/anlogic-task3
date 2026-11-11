`timescale 1ns / 1ps

// Stage3-only common color path. WB/CCM, shared Tone96 and Gamma are separate
// handshake stages; Stage2's frozen linear color source is never modified.
module wide_color_pipeline2 #(
    parameter integer GAMMA_BYPASS = 0,
    parameter signed [10:0] CCM00 = 11'sd256, CCM01 = 0, CCM02 = 0,
    parameter signed [10:0] CCM10 = 0, CCM11 = 11'sd256, CCM12 = 0,
    parameter signed [10:0] CCM20 = 0, CCM21 = 0, CCM22 = 11'sd256
) (
    input wire clk, input wire rst_n,
    input wire cfg_hdr, input wire [3:0] cfg_tone_shift,
    input wire [29:0] cfg_wb_gains,
    input wire [167:0] s_data, input wire s_valid, output wire s_ready,
    input wire s_sof, input wire s_eol,
    output wire [95:0] m_data, output wire m_valid, input wire m_ready,
    output wire m_sof, output wire m_eol,
    output reg [31:0] stat_beats, output reg [31:0] stat_frames,
    output reg [31:0] stat_saturated
);
    reg hdr;
    reg [29:0] gains;
    wire input_fire=s_valid&&s_ready;
    wire hdr_input=s_sof?cfg_hdr:hdr;
    wire [29:0] gains_input=s_sof?cfg_wb_gains:gains;
    wire [167:0] corrected_rgb;
    wire pre_valid,pre_ready,pre_hdr,pre_sof,pre_eol,pre_clipped;
    wire [119:0] tone_rgb;
    wire tone_valid,tone_ready,tone_sof,tone_eol,tone_clipped;
    wire output_clipped;
    color_wbccm2 #(.CCM00(CCM00),.CCM01(CCM01),.CCM02(CCM02),
        .CCM10(CCM10),.CCM11(CCM11),.CCM12(CCM12),.CCM20(CCM20),.CCM21(CCM21),.CCM22(CCM22)) pre(
        .clk(clk),.rst_n(rst_n),.s_hdr(hdr_input),.s_gains(gains_input),
        .s_data(s_data),.s_valid(s_valid),.s_ready(s_ready),.s_sof(s_sof),.s_eol(s_eol),
        .m_data(corrected_rgb),.m_valid(pre_valid),.m_ready(pre_ready),
        .m_hdr(pre_hdr),.m_sof(pre_sof),.m_eol(pre_eol),.m_clipped(pre_clipped));
    // Same frozen Tone96 implementation and4PPC interface; no changes.
    hdr_tone96_shared4 u_tone96(
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.s_data(corrected_rgb),.s_hdr(pre_hdr),
        .s_valid(pre_valid),.s_ready(pre_ready),.s_sof(pre_sof),.s_eol(pre_eol),.s_clipped(pre_clipped),
        .m_data(tone_rgb),.m_valid(tone_valid),.m_ready(tone_ready),
        .m_sof(tone_sof),.m_eol(tone_eol),.m_clipped(tone_clipped));
    color_gamma2 #(.GAMMA_BYPASS(GAMMA_BYPASS)) post(
        .clk(clk),.rst_n(rst_n),.s_data(tone_rgb),.s_valid(tone_valid),.s_ready(tone_ready),
        .s_sof(tone_sof),.s_eol(tone_eol),.s_clipped(tone_clipped),
        .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_sof(m_sof),.m_eol(m_eol),.m_clipped(output_clipped));
    always @(posedge clk)begin
        if(!rst_n)begin
            hdr<=0;gains<={3{10'd256}};stat_beats<=0;stat_frames<=0;stat_saturated<=0;
        end else begin
            if(input_fire&&s_sof)begin hdr<=cfg_hdr;gains<=cfg_wb_gains;end
            if(m_valid&&m_ready)begin
                stat_beats<=stat_beats+1'b1;
                if(m_sof)stat_frames<=stat_frames+1'b1;
                if(output_clipped)stat_saturated<=stat_saturated+1'b1;
            end
        end
    end
endmodule
