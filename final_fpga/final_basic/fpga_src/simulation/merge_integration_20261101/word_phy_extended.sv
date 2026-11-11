`timescale 1ns/1ps
// Electrical boundary only. Tests control recovered clock, PHY-ready and
// calibration separately. Receiver aligner, gearbox, parser and FIFOs are real.
module csi2_ph1_phy_wrapper #(parameter MIPI_LAN=4,parameter DEVICE="PH1A")(
 input I_debug_button,I_ref_clock,I_clk_hs_rx_p,I_reset_n,I_decoder_reset_n,
 input [MIPI_LAN-1:0] I_hs_data_p,input I_enable,I_wait_for_sync,I_packet_done,
 output O_hs_div_clk,O_reset_out,
 output [MIPI_LAN-1:0] O_rx_byte_data_align_vaild,
 output [8*MIPI_LAN-1:0] O_rx_byte_data_align,
 output O_delay_value,O_auto_delay_done,output [7:0] O_dbg_delay,
 output [5:0] O_dbg_best_len,output [8*MIPI_LAN-1:0] O_diag_raw_bytes,
 output [3*MIPI_LAN-1:0] O_diag_byte_offset,
 output [MIPI_LAN-1:0] O_diag_byte_found,output [15:0] O_diag_calibration);
 reg word_clk=0,clock_run=1,health=1,cal_done=1;
 reg use_watchdog=0;
 initial use_watchdog=$test$plusargs("REAL_WATCHDOG");
 reg [31:0] bytes=0;reg [3:0] valid=0;
 always #4.444444 if(clock_run)word_clk=~word_clk;else word_clk=0;
 assign O_hs_div_clk=word_clk;
 wire watchdog_ready;
 csi_clock_watchdog #(.TIMEOUT_REF_CYCLES(1024),.GOOD_ACKS(3),.RELEASE_STAGES(3)) watchdog(
  .I_ref_clk(I_ref_clock),.I_ext_clk(word_clk),.I_arst_n(I_reset_n),.I_enable(I_enable),
  .O_healthy_ref(),.O_clock_lost_pulse_ref(),.O_ext_rst_n(watchdog_ready));
 reg [2:0] core_release;
 always @(posedge word_clk or negedge watchdog_ready)
  if(!watchdog_ready)core_release<=0;else core_release<={core_release[1:0],1'b1};
 assign O_reset_out=use_watchdog?core_release[2]:(I_reset_n&&health);
 assign O_auto_delay_done=I_reset_n&&cal_done;
 assign O_rx_byte_data_align_vaild=valid;
 assign O_rx_byte_data_align=bytes;
 assign O_delay_value=0;assign O_dbg_delay=16;assign O_dbg_best_len=16;
 assign O_diag_raw_bytes=bytes;assign O_diag_byte_offset=0;
 assign O_diag_byte_found=valid;assign O_diag_calibration={4'd0,cal_done,11'd0};
endmodule
