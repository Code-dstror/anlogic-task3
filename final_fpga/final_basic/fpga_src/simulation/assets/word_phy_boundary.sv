`timescale 1ns/1ps
// Electrical PHY/calibration boundary only. The test drives packet-aligned
// words after the real gearbox; all CSI ECC/CRC/VC/crop/CDC stays real RTL.
module csi2_ph1_phy_wrapper #(parameter MIPI_LAN=4,parameter DEVICE="PH1A")(
    input wire I_debug_button,I_ref_clock,I_clk_hs_rx_p,I_reset_n,I_decoder_reset_n,
    input wire [MIPI_LAN-1:0] I_hs_data_p,
    input wire I_enable,I_wait_for_sync,I_packet_done,
    output wire O_hs_div_clk,O_reset_out,
    output wire [MIPI_LAN-1:0] O_rx_byte_data_align_vaild,
    output wire [8*MIPI_LAN-1:0] O_rx_byte_data_align,
    output wire O_delay_value,O_auto_delay_done,
    output wire [7:0] O_dbg_delay,
    output wire [5:0] O_dbg_best_len,
    output wire [8*MIPI_LAN-1:0] O_diag_raw_bytes,
    output wire [3*MIPI_LAN-1:0] O_diag_byte_offset,
    output wire [MIPI_LAN-1:0] O_diag_byte_found,
    output wire [15:0] O_diag_calibration
);
    reg word_clk=0;always #4.444444 word_clk=~word_clk;
    assign O_hs_div_clk=word_clk;
    assign O_reset_out=I_reset_n;
    assign O_auto_delay_done=I_reset_n;
    assign O_rx_byte_data_align_vaild=0;
    assign O_rx_byte_data_align=0;
    assign O_delay_value=0;assign O_dbg_delay=8'h42;assign O_dbg_best_len=6'd12;
    // Explicit simulated calibration only; MAIN does not qualify electrical IO.
    assign O_diag_raw_bytes=0;assign O_diag_byte_offset=0;assign O_diag_byte_found=0;
    assign O_diag_calibration={1'b1,1'b0,1'b0,1'b1,1'b1,6'd12,5'd2};
endmodule
