`timescale 1ns/1ps
// Electrical sampling/eye scan boundary only. Tests inject packet-aligned
// words after the real gearbox, as in the production MAIN fixture. The real
// watchdog remains present to exercise stopped/restarted WORD clock behavior.
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
    assign O_diag_raw_bytes=0;assign O_diag_byte_offset=0;assign O_diag_byte_found=0;assign O_diag_calibration=0;
    wire healthy,lost;
    assign O_hs_div_clk=I_clk_hs_rx_p;
    csi_clock_watchdog #(.TIMEOUT_REF_CYCLES(64),.GOOD_ACKS(3)) u_watchdog(
        .I_ref_clk(I_ref_clock),.I_ext_clk(I_clk_hs_rx_p),.I_arst_n(I_reset_n),
        .I_enable(I_enable),.O_healthy_ref(healthy),.O_clock_lost_pulse_ref(lost),
        .O_ext_rst_n(O_reset_out));
    assign O_auto_delay_done=O_reset_out;
    assign O_rx_byte_data_align_vaild=0;
    assign O_rx_byte_data_align=0;
    assign O_delay_value=0;assign O_dbg_delay=8'h42;assign O_dbg_best_len=6'd12;
endmodule

// Dedicated pad-clock buffer is a digital wire boundary here; no clock-routing claim.
module PH1_LOGIC_BUFG(input wire i,output wire o);assign o=i;endmodule
