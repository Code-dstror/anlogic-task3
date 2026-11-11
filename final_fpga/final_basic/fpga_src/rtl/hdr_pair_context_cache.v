`timescale 1ns / 1ps

// One borrowed LONG publication. Only the retained bank owner grants/releases
// authority; this register bank translates its serial directory representation.
module hdr_pair_context_cache (
    input wire i_clk, i_identity_rst_n,
    input wire i_begin,
    input wire [1:0] i_expected_slot,
    output wire o_begin_ready,
    input wire [31:0] s_data,
    input wire [3:0] s_word,
    input wire s_last, s_valid,
    output wire s_ready,
    output reg [383:0] o_frame,
    output reg [63:0] o_lease,
    output reg o_valid,
    input wire i_clear,
    output reg o_fault
);
    reg loading;
    reg [1:0] expected_slot;
    reg [3:0] next_word;
    reg word_ok;
    wire begin_fire = i_begin && o_begin_ready;
    wire data_fire = s_valid && s_ready;
    wire identity_ok = o_frame[44:13] != 0 &&
        o_frame[76:45] != 0 && o_lease != 0;

    assign o_begin_ready = i_identity_rst_n && !loading && !o_valid &&
        !o_fault && !i_clear;
    assign s_ready = i_identity_rst_n && loading;

    always @* begin
        word_ok = s_word == next_word && s_last == (next_word == 15);
        case (next_word)
            0: word_ok = word_ok && s_data[31:13] == 0 &&
                s_data[12:5] == {6'd0, expected_slot} &&
                !expected_slot[0] && s_data[2:0] == 3'b011;
            1, 2: word_ok = word_ok && s_data != 0;
            14: word_ok = word_ok && s_data == 32'd1;
            15: word_ok = word_ok && s_data == 0;
            default: begin end
        endcase
    end

    // Every payload field is assigned during LOAD, before o_valid can rise.
    // Cold reset invalidates payload instead of adding resets to448 data FFs.
    always @(posedge i_clk) begin
        if (begin_fire) o_frame[383:367] <= 0;
        if (data_fire) begin
            case (next_word)
                0: o_frame[12:0] <= s_data[12:0];
                1: o_frame[44:13] <= s_data;
                2: o_frame[76:45] <= s_data;
                3: o_frame[108:77] <= s_data;
                4: o_frame[140:109] <= s_data;
                5: o_frame[172:141] <= s_data;
                6: o_frame[204:173] <= s_data;
                7: o_frame[236:205] <= s_data;
                8: o_frame[302:271] <= s_data;
                9: o_frame[334:303] <= s_data;
                10: o_frame[270:239] <= s_data;
                11: o_frame[366:335] <= s_data;
                12: o_lease[31:0] <= s_data;
                13: o_lease[63:32] <= s_data;
                14: o_frame[238:237] <= s_data[1:0];
                default: begin end
            endcase
        end
    end

    always @(posedge i_clk or negedge i_identity_rst_n) begin
        if (!i_identity_rst_n) begin
            loading <= 0;
            expected_slot <= 0;
            next_word <= 0;
            o_valid <= 0;
            o_fault <= 0;
        end else begin
            if (i_clear) begin
                if (loading) o_fault <= 1;
                else o_valid <= 0;
            end
            if (begin_fire) begin
                loading <= 1;
                expected_slot <= i_expected_slot;
                next_word <= 0;
            end
            if (data_fire) begin
                if (!word_ok) o_fault <= 1;
                if (next_word == 15) begin
                    loading <= 0;
                    if (!o_fault && !i_clear && word_ok && identity_ok)
                        o_valid <= 1;
                    else o_fault <= 1;
                end else next_word <= next_word + 1'b1;
            end
        end
    end
endmodule
