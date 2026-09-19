`timescale 1ns / 1ps

module csi2_raw10_rx #(
    parameter MIPI_LAN = 4,
    parameter DEVICE = "PH1A"
)(
    input  wire                i_ref_clk,
    input  wire                i_mipi_clk_p,
    input  wire [MIPI_LAN-1:0] i_mipi_data_p,
    input  wire                i_pixel_clk,
    input  wire                i_reset_n,
    input  wire                i_enable,
    input  wire                i_debug_button,
    output wire [39:0]         o_raw_data,
    output wire                o_raw_valid,
    input  wire                i_raw_ready,
    output wire                o_raw_sof,
    output wire                o_raw_eol,
    output wire                o_frame_abort,
    output wire [3:0]          o_error_code,
    output wire [31:0]         o_header_ecc_error_count,
    output wire [31:0]         o_payload_crc_error_count,
    output wire [31:0]         o_overflow_error_count,
    output wire [31:0]         o_length_error_count,
    output wire                o_hs_word_clk,
    output wire                o_auto_delay_done,
    output wire [7:0]          o_delay_debug,
    output wire [5:0]          o_delay_window,
    output wire                o_phy_ready
);
    wire [MIPI_LAN-1:0] lane_byte_valid;
    wire [8*MIPI_LAN-1:0] lane_byte_data;
    wire [8*MIPI_LAN-1:0] aligned_word;
    wire aligned_word_valid;
    wire [31:0] geared_word;
    wire geared_word_valid;
    wire phy_reset_n;
    wire wait_for_sync;
    wire packet_done;
    wire unused_delay_value;
    reg [1:0] phy_ready_sync;
    reg [1:0] word_reset_sync;
    reg [1:0] word_enable_sync;
    wire word_reset_n = word_reset_sync[1];

    // The PHY reset is generated in the reference-clock domain. Assert it
    // asynchronously on clock loss, then release it synchronously to the
    // recovered word clock. Enable is likewise synchronized before use by
    // the word aligner and gearbox.
    always @(posedge o_hs_word_clk or negedge phy_reset_n) begin
        if (!phy_reset_n) begin
            word_reset_sync <= 2'b00;
            word_enable_sync <= 2'b00;
        end else begin
            word_reset_sync <= {word_reset_sync[0], 1'b1};
            word_enable_sync <= {word_enable_sync[0], i_enable};
        end
    end

    always @(posedge i_pixel_clk or negedge i_reset_n) begin
        if (!i_reset_n)
            phy_ready_sync <= 2'b00;
        else
            phy_ready_sync <= {phy_ready_sync[0], phy_reset_n};
    end
    assign o_phy_ready = phy_ready_sync[1];

    csi2_ph1_phy_wrapper #(.MIPI_LAN(MIPI_LAN), .DEVICE(DEVICE)) u_phy (
        .I_debug_button(i_debug_button), .I_ref_clock(i_ref_clk),
        .I_clk_hs_rx_p(i_mipi_clk_p), .I_reset_n(i_reset_n),
        .I_hs_data_p(i_mipi_data_p), .I_enable(i_enable),
        .I_wait_for_sync(wait_for_sync), .I_packet_done(packet_done),
        .O_hs_div_clk(o_hs_word_clk), .O_reset_out(phy_reset_n),
        .O_rx_byte_data_align_vaild(lane_byte_valid),
        .O_rx_byte_data_align(lane_byte_data),
        .O_delay_value(unused_delay_value),
        .O_auto_delay_done(o_auto_delay_done),
        .O_dbg_delay(o_delay_debug), .O_dbg_best_len(o_delay_window)
    );

    csi_rx_word_align #(.MIPI_LAN(MIPI_LAN)) u_word_align (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n),
        .I_enable(word_enable_sync[1]), .I_packet_done(packet_done),
        .I_wait_for_sync(wait_for_sync), .O_packet_done_out(),
        .I_word_in(lane_byte_data), .I_valid_in(lane_byte_valid),
        .O_word_out(aligned_word), .O_valid_out(aligned_word_valid)
    );

    csi_rx_word_gear_box #(.MIPI_LAN(MIPI_LAN)) u_gearbox (
        .I_word_clock(o_hs_word_clk), .I_reset_n(word_reset_n),
        .I_enable(word_enable_sync[1]), .I_lane_data(aligned_word),
        .I_lane_data_valid(aligned_word_valid),
        .O_word_out(geared_word), .O_valid_out(geared_word_valid)
    );

    csi2_raw10_rx_stream u_stream (
        .i_word_clk(o_hs_word_clk), .i_pixel_clk(i_pixel_clk),
        .i_reset_n(phy_reset_n),
        .i_aligned_word(geared_word), .i_aligned_valid(geared_word_valid),
        .o_raw_data(o_raw_data), .o_raw_valid(o_raw_valid),
        .i_raw_ready(i_raw_ready), .o_raw_sof(o_raw_sof),
        .o_raw_eol(o_raw_eol), .o_frame_abort(o_frame_abort),
        .o_error_code(o_error_code),
        .o_header_ecc_error_count(o_header_ecc_error_count),
        .o_payload_crc_error_count(o_payload_crc_error_count),
        .o_overflow_error_count(o_overflow_error_count),
        .o_length_error_count(o_length_error_count),
        .o_wait_for_sync(wait_for_sync), .o_packet_done(packet_done)
    );
endmodule
