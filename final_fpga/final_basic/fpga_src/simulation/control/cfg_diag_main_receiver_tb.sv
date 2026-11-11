`timescale 1ns/1ps
// Unit harness for the modified passive MAIN receiver. The actual business
// integration is checked by source-bound HDR/SDR MAIN separately.
module cfg_diag_main_receiver_model(input wire clk,rst_n,output wire tx);
    wire i_rx_word_clk=0; wire [383:0] i_rx_domains=0; wire [2:0] i_rx_reset_n=0;
    parameter integer READONLY_UART_ENABLE=1,DEBUG_UART_ENABLE=0;
    parameter integer CFG_TEST_VERSION=2;
    wire frame_active_pixel=1,jpeg_idle=0,writer_ack_valid=0;
    uart_status_observer #(.UART_DIV(217),.REPORT_INTERVAL_CYCLES(100000),
        .SNAPSHOT_TIMEOUT_CYCLES(30),.CFG_DIAG_ENABLE(1),.CFG_FRAME_VERSION(CFG_TEST_VERSION)) observer(
        .i_sys_clk(clk),.i_sys_rst_n(rst_n),.i_pixel_clk(clk),.i_dfi_clk(clk),.i_user_clk(clk),
        .i_domain_observer_rst_n({3{rst_n}}),.i_domain_reset_n(3'b111),.i_sys_status(16'h1234),
        .i_domain_flags(36'd0),.i_domain_faults(12'd0),.i_domain_progress(6'h3f),
        .i_cfg_domains(448'd0),.i_cfg_domain_reset_n(2'b11),
        .i_rx_word_clk(1'b0),.i_rx_domains(384'd0),.i_rx_reset_n(3'd0),
        .o_trace_request(),.o_trace_index(),.i_trace_ack(1'b0),.i_trace_data(320'd0),.o_uart_tx(tx));
endmodule
module cfg_diag_main_receiver_tb;
    parameter integer CFG_TEST_VERSION=2;
    reg sys_clk=0;always #20 sys_clk=~sys_clk;
    reg rst_n=0,uart_rx=1,done_o=0;
    wire uart_tx;
    integer checks=0;
    cfg_diag_main_receiver_model #(.CFG_TEST_VERSION(CFG_TEST_VERSION)) dut(sys_clk,rst_n,uart_tx);
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"MAIN receiver harness: %s",why);end
    endtask
    `include "readonly_uart_main_decode.vh"
    initial begin
        repeat(10)@(negedge sys_clk);rst_n=1;
        wait(observer_frames>=3&&observer_cfg_frames>=2);@(negedge sys_clk);
        done_o=1;readonly_uart_finish();
        $display("RESULT: PASS cfg_diag_main_receiver version=%0d checks=%0d",CFG_TEST_VERSION,checks);$finish;
    end
    initial begin #30000000;$fatal(1,"MAIN receiver harness watchdog");end
endmodule
