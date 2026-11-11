`timescale 1ns/1ps
module tb_phy_calibration_wrapper;
    reg clk=0,rst_n=0,button=1;
    always #5 clk=~clk;
    wire ready_good,ready_bad;
    wire [15:0] cal_good,cal_bad;
    wire [31:0] raw_good;
    wire [11:0] offset_good;
    wire [3:0] found_good;
    csi2_ph1_phy_wrapper #(.MIPI_LAN(4),.DEVICE("PH1A")) good (
        .I_debug_button(1'b1),.I_ref_clock(clk),.I_clk_hs_rx_p(clk),.I_reset_n(rst_n),
        .I_decoder_reset_n(1'b1),.I_hs_data_p(4'b1010),.I_enable(1'b1),
        .I_wait_for_sync(1'b1),.I_packet_done(1'b0),.O_auto_delay_done(ready_good),
        .O_diag_calibration(cal_good),.O_diag_raw_bytes(raw_good),
        .O_diag_byte_offset(offset_good),.O_diag_byte_found(found_good),
        .O_hs_div_clk(),.O_reset_out(),.O_rx_byte_data_align_vaild(),
        .O_rx_byte_data_align(),.O_delay_value(),.O_dbg_delay(),.O_dbg_best_len());
    csi2_ph1_phy_wrapper #(.MIPI_LAN(4),.DEVICE("PH1A")) bad (
        .I_debug_button(button),.I_ref_clock(clk),.I_clk_hs_rx_p(clk),.I_reset_n(rst_n),
        .I_decoder_reset_n(1'b1),.I_hs_data_p(4'b0000),.I_enable(1'b1),
        .I_wait_for_sync(1'b1),.I_packet_done(1'b0),.O_auto_delay_done(ready_bad),
        .O_diag_calibration(cal_bad),.O_diag_raw_bytes(),.O_diag_byte_offset(),.O_diag_byte_found(),
        .O_hs_div_clk(),.O_reset_out(),.O_rx_byte_data_align_vaild(),
        .O_rx_byte_data_align(),.O_delay_value(),.O_dbg_delay(),.O_dbg_best_len());
    defparam good.g_ph1a_delay_scan.u_auto_delay_ctl.TEST_LEN=16;
    defparam good.g_ph1a_delay_scan.u_auto_delay_ctl.PASS_THRESH=4;
    defparam good.g_ph1a_delay_scan.u_auto_delay_ctl.SETTLE_CYCLES=4;
    defparam bad.g_ph1a_delay_scan.u_auto_delay_ctl.TEST_LEN=16;
    defparam bad.g_ph1a_delay_scan.u_auto_delay_ctl.PASS_THRESH=4;
    defparam bad.g_ph1a_delay_scan.u_auto_delay_ctl.SETTLE_CYCLES=4;
    defparam good.g_ph1a_delay_scan.u_auto_delay_ctl.WAIT_CYCLES=32;
    defparam bad.g_ph1a_delay_scan.u_auto_delay_ctl.WAIT_CYCLES=32;
    integer manual_steps,training_cycles=0;
    reg [31:0] training_raw=0;
    reg [3:0] good_training_valid=0;
    always @(negedge clk) begin
        training_cycles=training_cycles+1;
        training_raw=~training_raw;
        good_training_valid=(training_cycles%8==0)?4'b0000:4'b1111;
    end
    task press;begin button=0;repeat(5)@(negedge clk);button=1;repeat(5)@(negedge clk);end endtask
    initial begin
        // Inject only the scan scorer's lane-valid inputs. Clock/reset and
        // publication wiring remain the production wrapper implementation.
        force good.w_rx_byte_data_align_vaild=good_training_valid;
        force bad.w_rx_byte_data_align_vaild=4'b0001;
        force good.w_rx_byte_data=training_raw;
        force bad.w_rx_byte_data=training_raw;
        repeat(4)@(negedge clk);rst_n=1;
        wait(cal_good[11] && cal_bad[11]);#1;
        if(!ready_good || ready_bad || cal_good!==16'h9c10 || cal_bad!==16'ha810)
            $fatal(1,"PH1A calibration publication/diagnostic packing mismatch good=%h bad=%h",cal_good,cal_bad);
        release good.w_rx_byte_data;#1;
        if(raw_good!==32'hff00ff00)$fatal(1,"raw byte alias changed lane order");
        if(good.gen_channel_wrapper[0].u_csi_rx_hs_data_phy.I_delay_vaild!==1'b1)
            $fatal(1,"PH1A dynamic delay enable is not held high");
        press();
        if(!ready_bad || !cal_bad[14] || !cal_bad[15] || cal_bad[4:0]!==5'd16)
            $fatal(1,"manual entry did not use effective PH1A code");
        for(manual_steps=0;manual_steps<16;manual_steps=manual_steps+1)press();
        if(cal_bad[4:0]!==0 || bad.r_manual_delay[5]!==0)$fatal(1,"PH1A manual delay did not wrap within 32 codes");
        rst_n=0;#1;
        if(ready_good || ready_bad || cal_good[15] || cal_bad[15])$fatal(1,"health reset retained publication authority");
        $display("PASS PH1A wrapper publication gate/manual wrap/diagnostic packing/reset");
        $finish;
    end
    initial begin #200000;$fatal(1,"wrapper test timeout");end
endmodule

// Interface-only clock/data substitutes; no claim of PHY electrical modeling.
module rx_clk_gen #(parameter DEVICE="PH1A") (input I_mipi_clk_p,I_rst,output O_clk,O_clk_x2,O_clk_x4);
    assign O_clk=I_mipi_clk_p;assign O_clk_x2=I_mipi_clk_p;assign O_clk_x4=I_mipi_clk_p;
endmodule
module PH1_PHY_SCLK_V2 #(parameter GSR="ENABLE",BYPASS="ENABLE",DELAY=0)(input ce,clkin,output clkout);
    assign clkout=clkin;
endmodule
module csi_clock_watchdog #(parameter TIMEOUT_REF_CYCLES=1024,GOOD_ACKS=3,RELEASE_STAGES=3)
    (input I_ref_clk,I_ext_clk,I_arst_n,I_enable,output O_healthy_ref,O_clock_lost_pulse_ref,O_ext_rst_n);
    assign O_ext_rst_n=I_arst_n;assign O_healthy_ref=I_arst_n;assign O_clock_lost_pulse_ref=0;
endmodule
module csi_rx_hs_data_phy #(parameter DEVICE="PH1A")
    (input I_rxclk,I_rxclk_div_x2,I_rxclk_div_x4,I_reset_n,I_hs_data_p,
     input [5:0] I_delay_value,input I_delay_vaild,output [7:0] O_rx_data,output O_delay_data_val);
    assign O_rx_data={8{I_hs_data_p}};assign O_delay_data_val=1;
endmodule
