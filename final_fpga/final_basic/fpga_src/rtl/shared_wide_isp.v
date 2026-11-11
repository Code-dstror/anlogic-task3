`timescale 1ns / 1ps

// A whole native4 frame owns the unique wide ISP until its RGB tail drains.
module shared_wide_isp #(
    parameter integer MAX_WIDTH = 1920,
    parameter integer MAX_HEIGHT = 1080,
    parameter integer GAMMA_BYPASS = 0,
    // hdr_merge4 has already removed the measured long/short black levels.
    // The default retains the established uncorrected RAW14 input contract.
    parameter integer HDR_BLACK_CORRECTED_ENABLE = 0
) (
    input wire clk, input wire rst_n,
    input wire [12:0] cfg_width, input wire [12:0] cfg_height,
    input wire [1:0] cfg_bayer_phase, input wire cfg_hdr,
    input wire [3:0] cfg_tone_shift, input wire [29:0] cfg_wb_gains,
    input wire [55:0] s_data, input wire s_valid, output wire s_ready,
    input wire s_sof, input wire s_eol,
    output wire [95:0] m_data, output wire m_valid, input wire m_ready,
    output wire m_sof, output wire m_eol, output wire o_job_idle,
    output wire [31:0] stat_beats, stat_frames, stat_saturated
);
    reg [12:0] width, height;
    reg [1:0] phase;
    reg hdr;
    reg [3:0] tone_shift;
    reg [29:0] gains;
    reg job_active;
    reg [12:0] output_rows;
    wire raw_ready;
    wire [167:0] rgb14;
    wire rgb_valid, rgb_ready, rgb_sof, rgb_eol;
    wire start = s_valid && s_ready && s_sof;
    wire start_allowed = !s_sof || !job_active;
    // Geometry validates READY itself. Preview an offered new SOF without
    // using READY; ownership/configuration still latch only on `start`.
    wire preview_start = s_valid && s_sof && start_allowed;
    wire input_black_corrected = HDR_BLACK_CORRECTED_ENABLE != 0 &&
        (preview_start ? cfg_hdr : hdr);
    assign o_job_idle = rst_n && !job_active && !m_valid;
    assign s_ready = rst_n && raw_ready && start_allowed;
    always @(posedge clk) begin
        if (!rst_n) begin
            width <= MAX_WIDTH; height <= MAX_HEIGHT; phase <= 0;
            hdr <= 0; tone_shift <= 0; gains <= {3{10'd256}};
            job_active <= 0; output_rows <= 0;
        end else begin
            if (start) begin
                width <= cfg_width; height <= cfg_height; phase <= cfg_bayer_phase;
                hdr <= cfg_hdr; tone_shift <= cfg_tone_shift; gains <= cfg_wb_gains;
                job_active <= 1; output_rows <= 0;
            end
            if (m_valid && m_ready && m_eol) begin
                output_rows <= output_rows + 1'b1;
                if (output_rows+1'b1 == height) job_active <= 0;
            end
        end
    end
    raw_isp_top #(.SAMPLE_BITS(14),.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .RUNTIME_BLC_BYPASS_ENABLE(HDR_BLACK_CORRECTED_ENABLE),
        .BLC_OFFSET_L0(14'd50),.BLC_OFFSET_L1(14'd50),
        .BLC_OFFSET_L2(14'd50),.BLC_OFFSET_L3(14'd50)) u_raw (
        .clk(clk),.rst_n(rst_n),
        .cfg_width(preview_start ? cfg_width : width),.cfg_height(preview_start ? cfg_height : height),
        .cfg_bayer_phase(phase),.cfg_edge_g(1'b0),
        .cfg_blc_bypass(input_black_corrected),
        .s_tdata(s_data),.s_tvalid(s_valid && rst_n && start_allowed),.s_tready(raw_ready),
        .s_tuser(s_sof),.s_tlast(s_eol),.m_tdata(rgb14),
        .m_tvalid(rgb_valid),.m_tready(rgb_ready),.m_tuser(rgb_sof),
        .m_tlast(rgb_eol),.dbg_state());
    wide_color_pipeline #(.GAMMA_BYPASS(GAMMA_BYPASS)) u_color (
        .clk(clk),.rst_n(rst_n),.cfg_hdr(hdr),.cfg_tone_shift(tone_shift),
        .cfg_wb_gains(gains),.s_data(rgb14),.s_valid(rgb_valid),
        .s_ready(rgb_ready),.s_sof(rgb_sof),.s_eol(rgb_eol),
        .m_data(m_data),.m_valid(m_valid),.m_ready(m_ready),.m_sof(m_sof),.m_eol(m_eol),
        .stat_beats(stat_beats),.stat_frames(stat_frames),.stat_saturated(stat_saturated));
endmodule
