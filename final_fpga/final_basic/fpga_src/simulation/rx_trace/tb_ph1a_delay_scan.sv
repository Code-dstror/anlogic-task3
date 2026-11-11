`timescale 1ns/1ps
module delay_scan_case #(
    parameter [31:0] MASK=0,
    parameter integer EXPECT_LEN=0,
    parameter integer EXPECT_TAP=16
) (input wire clk,rst_n,output reg finished=0);
    wire [4:0] tap;
    wire [5:0] window;
    wire load,done,window_valid,failed;
    reg [31:0] raw_bytes=0;
    integer acquire_cycles=0;
    wire [3:0] aligned = finished || (dut.state==9 && acquire_cycles<2) ?
        4'b0000 : MASK[tap] ? 4'b1111 : 4'b0001;
    always @(negedge clk) begin
        if(!rst_n)begin raw_bytes=0;acquire_cycles=0;end
        else begin
            raw_bytes=raw_bytes+32'h01010101;
            if(dut.state==9)acquire_cycles=acquire_cycles+1;
            else acquire_cycles=0;
        end
    end
    integer scans=0,stable_cycles=0;
    ph1a_rx_delay_scan #(.MIPI_LAN(4),.TEST_LEN(16),.PASS_THRESH(4),
        .SETTLE_CYCLES(4),.WAIT_CYCLES(32),.MAX_SCANS(1)) dut (
        .I_byte_clk(clk),.I_reset_n(rst_n),.I_raw_bytes(raw_bytes),.I_byte_align_done(aligned),
        .O_delay_value(tap),.O_delay_vaild(load),.O_scan_done(done),
        .O_window_len(window),.O_window_valid(window_valid),.O_scan_failed(failed));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin scans=0;finished=0;stable_cycles=0;end
        else begin
            if(dut.state==4'd5) begin
                if(dut.scan_tap!==scans[4:0])$fatal(1,"scan omitted/repeated physical code");
                if(dut.pass_flag!==MASK[scans])$fatal(1,"tap score mismatch");
                scans=scans+1;
            end
            if(done) begin
                if(scans!=32 || window!==6'(EXPECT_LEN) || tap!==5'(EXPECT_TAP) ||
                    window_valid!==(EXPECT_LEN!=0) || failed!==(EXPECT_LEN==0))
                    $fatal(1,"scan MASK=%h got len=%0d tap=%0d valid=%0d failed=%0d scans=%0d",
                        MASK,window,tap,window_valid,failed,scans);
                stable_cycles=stable_cycles+1;
                if(stable_cycles==1) $display("CASE mask=%h len=%0d tap=%0d valid=%0d failed=%0d",MASK,window,tap,window_valid,failed);
                finished=1;
            end
        end
    end
endmodule

module tb_ph1a_delay_scan;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire [5:0] finished;
    delay_scan_case #(.MASK(32'hffffffff),.EXPECT_LEN(32),.EXPECT_TAP(16)) all_pass(clk,rst_n,finished[0]);
    delay_scan_case #(.MASK(32'h00000000),.EXPECT_LEN(0),.EXPECT_TAP(16)) no_pass(clk,rst_n,finished[1]);
    delay_scan_case #(.MASK(32'h80000000),.EXPECT_LEN(1),.EXPECT_TAP(31)) narrow(clk,rst_n,finished[2]);
    delay_scan_case #(.MASK(32'h00007fc0),.EXPECT_LEN(9),.EXPECT_TAP(10)) normal(clk,rst_n,finished[3]);
    delay_scan_case #(.MASK(32'h00f0003c),.EXPECT_LEN(4),.EXPECT_TAP(4)) earliest_tie(clk,rst_n,finished[4]);
    delay_scan_case #(.MASK(32'he0000007),.EXPECT_LEN(3),.EXPECT_TAP(1)) no_wrap(clk,rst_n,finished[5]);
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        // A health reset while scanning must discard every partial score.
        repeat(83)@(negedge clk);rst_n=0;
        #1;
        if(all_pass.dut.O_scan_done || all_pass.dut.O_window_valid || all_pass.dut.O_scan_failed ||
            all_pass.dut.O_delay_value!==5'd16 || all_pass.dut.best_len!==0)
            $fatal(1,"asynchronous health reset did not clear calibration");
        repeat(3)@(negedge clk);rst_n=1;
        wait(&finished);
        repeat(20)@(negedge clk);
        if(all_pass.scans!=32 || no_pass.scans!=32)$fatal(1,"unexpected automatic rescan");
        $display("PASS PH1A calibration all-pass/no-pass/narrow/normal/tie/nonwrap/reset/no-rescan");
        $finish;
    end
    initial begin #200000;$fatal(1,"calibration test timeout");end
endmodule
