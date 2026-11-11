`timescale 1ns / 1ps

// Two ordinary elastic pipeline stages; no queue pointers or payload memory.
// The historical module name is retained for source compatibility.
module preprocess_stream_pending2 #(
    parameter integer LUMA_SIDEBAND_ENABLE = 0
) (
    input wire clk, rst_n, clear,
    input wire s_valid,
    output wire s_ready,
    input wire [95:0] s_data,
    input wire s_sof, s_eol,
    output wire m_valid,
    input wire m_ready,
    output wire [95:0] m_data,
    output wire m_sof, m_eol,
    input wire [31:0] s_luma,
    output wire [31:0] m_luma,
    output wire o_pending
);
    reg first_valid, second_valid;
    reg [97:0] first_payload, second_payload;
    reg [31:0] first_luma, second_luma;
    // The first stage is an accepted hidden token even when m_valid is low.
    assign o_pending = first_valid || second_valid;
    wire second_advance = !second_valid || m_ready;
    wire first_advance = !first_valid || second_advance;
    assign s_ready = rst_n && !clear && first_advance;
    assign m_valid = rst_n && !clear && second_valid;
    assign {m_sof, m_eol, m_data} = second_payload;
    assign m_luma = LUMA_SIDEBAND_ENABLE ? second_luma : 32'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            first_valid <= 0; second_valid <= 0;
        end else if (clear) begin
            first_valid <= 0; second_valid <= 0;
        end else begin
            if (first_advance) first_valid <= s_valid;
            if (second_advance) second_valid <= first_valid;
        end
    end
    always @(posedge clk) begin
        if (first_advance && s_valid) begin
            first_payload <= {s_sof, s_eol, s_data};
            if (LUMA_SIDEBAND_ENABLE) first_luma <= s_luma;
        end
        if (second_advance && first_valid) begin
            second_payload <= first_payload;
            if (LUMA_SIDEBAND_ENABLE) second_luma <= first_luma;
        end
    end
endmodule
