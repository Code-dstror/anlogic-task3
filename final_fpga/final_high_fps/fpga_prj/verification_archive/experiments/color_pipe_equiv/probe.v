`timescale 1ns/1ps

module hdr_quality_color_probe (
    input wire clk, rst_n,
    input wire [15:0] stimulus_word,
    input wire [3:0] observe_select,
    output wire [15:0] observe_word
);
    reg [207:0] stimulus;
    reg color_rst_n;
    reg [255:0] observed;
    wire [95:0] data;
    wire ready,valid,sof,eol;
    wire [31:0] beats,frames,saturated;
    always @(posedge clk) begin
        color_rst_n <= rst_n;
        stimulus <= {stimulus[191:0],stimulus_word};
        // Keep the external configuration stimulus observable in both arms.
        observed <= {28'd0,stimulus[205:174],ready,valid,sof,eol,data,beats,frames,saturated};
    end
    assign observe_word = observed[observe_select*16+:16];

    wide_color_pipeline #(.GAMMA_BYPASS(0)) u_color (
        .clk(clk),.rst_n(color_rst_n),.cfg_hdr(stimulus[168]),.cfg_tone_shift(4'd0),
`ifdef HDR_QUALITY_PROBE
        .cfg_tone_preset(stimulus[175:174]),.cfg_wb_gains(stimulus[205:176]),
`else
        .cfg_wb_gains({10'd832,10'd410,10'd909}),
`endif
        .s_data(stimulus[167:0]),.s_valid(stimulus[169]),.s_ready(ready),
        .s_sof(stimulus[170]),.s_eol(stimulus[171]),.m_ready(stimulus[172]),
        .m_data(data),.m_valid(valid),.m_sof(sof),.m_eol(eol),
        .stat_beats(beats),.stat_frames(frames),.stat_saturated(saturated)
    );
endmodule
