`timescale 1ns/1ps
// Frozen Q14 matrix: eight four-term DSP dot products, six advance edges.
// Existing official IP bytes/parameters are reused without regeneration.
module jpeg_fdct1d #(
    parameter integer TAG_WIDTH = 1,
    parameter integer INPUT_SAMPLE_WIDTH = 16
) (
    input wire i_clk, i_rst_n,
    input wire i_valid,
    output wire o_ready,
    input wire [127:0] i_data,
    input wire [TAG_WIDTH-1:0] i_tag,
    output wire o_valid,
    input wire i_ready,
    output wire [127:0] o_data,
    output wire [TAG_WIDTH-1:0] o_tag
);
    reg [5:0] valid_pipe;
    reg [TAG_WIDTH-1:0] tag0, tag1, tag2, tag3, tag4, tag5;
    reg signed [INPUT_SAMPLE_WIDTH:0] even0 [0:3], odd0 [0:3];
    reg signed [INPUT_SAMPLE_WIDTH:0] even2_delay, odd2_delay;
    reg signed [INPUT_SAMPLE_WIDTH:0] even3_delay1, odd3_delay1;
    reg signed [INPUT_SAMPLE_WIDTH:0] even3_delay2, odd3_delay2;
    reg [127:0] result;
    wire advance = !valid_pipe[5] || i_ready;
    assign o_ready = i_rst_n && advance;
    assign o_valid = i_rst_n && valid_pipe[5];
    assign o_data = result;
    assign o_tag = tag5;

    generate if (INPUT_SAMPLE_WIDTH < 8 || INPUT_SAMPLE_WIDTH > 16) begin : g_bad_input_width
        JPEG_FDCT_INPUT_WIDTH_REQUIRES_8_TO_16 invalid_configuration();
    end endgenerate

    // The even rows operate on x[n]+x[7-n]; odd rows on x[n]-x[7-n].
    // This is the same integer matrix as the frozen butterfly implementation.
    function signed [13:0] coefficient;
        input integer frequency;
        input integer term;
        begin
            case (frequency*4+term)
                0,1,2,3,16,19: coefficient = 14'sd5793;
                17,18: coefficient = -14'sd5793;
                4: coefficient = 14'sd8035;
                5,12,23,30: coefficient = 14'sd6811;
                6,20: coefficient = 14'sd4551;
                7,22,28: coefficient = 14'sd1598;
                8,26: coefficient = 14'sd7568;
                9,24: coefficient = 14'sd3135;
                10,27: coefficient = -14'sd3135;
                11,25: coefficient = -14'sd7568;
                13: coefficient = -14'sd1598;
                14,21,31: coefficient = -14'sd8035;
                15,29: coefficient = -14'sd4551;
                default: coefficient = 14'sd0;
            endcase
        end
    endfunction

    // Exact signed round-to-nearest, ties away from zero, then 16-bit wrap.
    // Bits below bit 14 affect only this carry; no wide fabric adder is needed.
    function [15:0] round_q14;
        input signed [33:0] value;
        reg increment;
        begin
            increment = value[13] && (!value[33] || |value[12:0]);
            round_q14 = value[29:14] + increment;
        end
    endfunction

    wire signed [33:0] dot_sum [0:7];
    genvar f;
    generate for (f=0; f<8; f=f+1) begin : g_frequency
        wire signed [18:0] operand0 = (f%2) ? odd0[0] : even0[0];
        wire signed [18:0] operand1 = (f%2) ? odd0[1] : even0[1];
        wire signed [18:0] operand2 = (f%2) ? odd2_delay : even2_delay;
        wire signed [18:0] operand3 = (f%2) ? odd3_delay2 : even3_delay2;
        wire signed [32:0] product0;
        wire signed [33:0] sum01, sum012;
        td_dsp_mult #(.A_WIDTH(19), .B_WIDTH(14), .INPUT_FORMAT("SIGNED")) u_first (
            .clk(i_clk), .rst_n(i_rst_n), .en(advance),
            .a(operand0), .b(coefficient(f,0)), .p(product0));
        // Each MAC has MREG+PREG. Its preceding DSP result reaches Z one
        // advance edge after A/Y, so the four-term sum finishes on edge five.
        fdct_mac19s14s_z33s_p34_m1p1 u_second (
            .CLK(i_clk), .RST(!i_rst_n), .CE(advance),
            .A(operand1), .Y(coefficient(f,1)), .Z(product0), .P(sum01));
        fdct_mac19s14s_z33s_p34_m1p1 u_third (
            .CLK(i_clk), .RST(!i_rst_n), .CE(advance),
            .A(operand2), .Y(coefficient(f,2)), .Z(sum01[32:0]), .P(sum012));
        fdct_mac19s14s_z33s_p34_m1p1 u_fourth (
            .CLK(i_clk), .RST(!i_rst_n), .CE(advance),
            .A(operand3), .Y(coefficient(f,3)), .Z(sum012[32:0]), .P(dot_sum[f]));
        // At maximum signed input width, each term is below 2^30 and every
        // partial four-term sum fits signed 33 bits; Z truncates no value.
    end endgenerate

    integer n;
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            valid_pipe <= 0;
            tag0 <= 0; tag1 <= 0; tag2 <= 0; tag3 <= 0; tag4 <= 0; tag5 <= 0;
        end else if (advance) begin
            valid_pipe <= {valid_pipe[4:0],i_valid};
            tag0 <= i_tag; tag1 <= tag0; tag2 <= tag1;
            tag3 <= tag2; tag4 <= tag3; tag5 <= tag4;
        end
        if (advance) begin
            for (n=0; n<4; n=n+1) begin
                even0[n] <= $signed(i_data[n*16 +:INPUT_SAMPLE_WIDTH]) +
                            $signed(i_data[(7-n)*16 +:INPUT_SAMPLE_WIDTH]);
                odd0[n] <= $signed(i_data[n*16 +:INPUT_SAMPLE_WIDTH]) -
                           $signed(i_data[(7-n)*16 +:INPUT_SAMPLE_WIDTH]);
            end
            even2_delay <= even0[2]; odd2_delay <= odd0[2];
            even3_delay1 <= even0[3]; odd3_delay1 <= odd0[3];
            even3_delay2 <= even3_delay1; odd3_delay2 <= odd3_delay1;
            for (n=0; n<8; n=n+1)
                result[n*16 +:16] <= round_q14(dot_sum[n]);
        end
    end
endmodule
