module hdr_tone96_shared4 (
    input wire clk, rst_n, clear,
    input wire [167:0] s_data,
    input wire s_hdr, s_valid, s_sof, s_eol, s_clipped,
    output wire s_ready,
    output wire [119:0] m_data,
    output wire m_valid,
    input wire m_ready,
    output wire m_sof, m_eol, m_clipped
);
