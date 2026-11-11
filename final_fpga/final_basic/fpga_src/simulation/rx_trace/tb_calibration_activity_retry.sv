`timescale 1ns/1ps

// Scanner control tests. Raw activity is independent of tap quality; lane
// feedback supplies fresh low-to-high acquisition or the stated counterexample.
module calibration_activity_case #(
    parameter integer KIND=0,
    parameter integer START_CYCLE=24,
    parameter integer WAIT_LIMIT=64,
    parameter integer SCAN_LIMIT=2,
    parameter integer EXPECT_LEN=32,
    parameter integer EXPECT_TAP=16,
    parameter integer EXPECT_SCANS=32
)(input wire clk,rst_n,output reg finished=0);
    localparam [31:0] OTHER_TAPS=32'h000000f0;
    reg [31:0] raw_bytes=0;
    reg [3:0] aligned=0;
    wire [4:0] tap;
    wire [5:0] window;
    wire load,done,valid,failed;
    integer cycles=0,acquire_cycles=0,retry_wait_cycles=0;
    integer scans=0,test_entries=0,stable_cycles=0,first_scan=-1;
    reg [3:0] previous_state=0;
    reg expected_pass;

    ph1a_rx_delay_scan #(.TEST_LEN(64),.PASS_THRESH(64),.SETTLE_CYCLES(4),
        .WAIT_CYCLES(WAIT_LIMIT),.MAX_SCANS(SCAN_LIMIT)) dut (
        .I_byte_clk(clk),.I_reset_n(rst_n),.I_raw_bytes(raw_bytes),
        .I_byte_align_done(aligned),.O_delay_value(tap),.O_delay_vaild(load),
        .O_scan_done(done),.O_window_len(window),.O_window_valid(valid),
        .O_scan_failed(failed));

    always @(negedge clk) begin
        if(!rst_n)begin
            cycles=0;raw_bytes=0;acquire_cycles=0;retry_wait_cycles=0;
        end else if(!finished)begin
            cycles=cycles+1;
            if(dut.state==9)acquire_cycles=acquire_cycles+1;
            else acquire_cycles=0;
            if(KIND==2 && dut.retry_used && dut.state==1)
                retry_wait_cycles=retry_wait_cycles+1;
            if(cycles<START_CYCLE)begin
                if(KIND==0 && cycles>=4 && cycles<20)
                    raw_bytes={24'd0,cycles[7:0]}; // only lane0 changes
                else if(KIND==8 && cycles%WAIT_LIMIT>=2 && cycles%WAIT_LIMIT<=5)
                    raw_bytes={4{8'(cycles%WAIT_LIMIT)}}; // fewer than eight changes/window
                else raw_bytes=0;
            end else if(!(KIND==2 && dut.retry_used && retry_wait_cycles<100))
                raw_bytes=raw_bytes+32'h01010101;
        end
    end

    always @* begin
        aligned=4'b1111;
        if(KIND==4)begin
            // A previous packet remains valid across every new physical code.
            aligned=4'b1111;
        end else if(KIND!=9 && dut.state==9 && acquire_cycles<2)begin
            aligned=0;
        end else if(KIND==9 && dut.state==9 && acquire_cycles<6)begin
            // Lanes need not retire their old valid on the same clock.
            case(acquire_cycles)
                2:aligned=4'b1110;
                3:aligned=4'b1101;
                4:aligned=4'b1011;
                5:aligned=4'b0111;
                default:aligned=4'b1111;
            endcase
        end else if(KIND==3 || (KIND==2 && !dut.retry_used))begin
            aligned=4'b0001;
        end else if(KIND==7 && !OTHER_TAPS[tap])begin
            aligned=4'b0001;
        end else if(KIND==5 && dut.state==4 && dut.cnt>=63)begin
            aligned=4'b0001;
        end
        if(cycles<START_CYCLE)aligned=(KIND==0 && cycles==10)?4'b0001:4'b0000;
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            scans=0;test_entries=0;stable_cycles=0;first_scan=-1;
            previous_state=0;finished=0;
        end else if(!finished)begin
            if(cycles<START_CYCLE && dut.state!=0 && dut.state!=1)
                $fatal(1,"KIND%0d started without all-lane activity at %0d",KIND,cycles);
            if(KIND==1 && cycles==8388610)begin
                if(done || valid || failed || scans!=0 || tap!=16)
                    $fatal(1,"old no-data timeout consumed a scan");
                $display("CASE no_data_beyond_old_2pow23_timeout pending/no_scan PASS");
            end
            if(dut.state==2 && first_scan<0)first_scan=cycles;
            if(dut.state==4 && previous_state!=4)test_entries=test_entries+1;
            previous_state=dut.state;
            if(dut.retry_used && dut.state==1)begin
                if(done || valid || failed || window!=0 || tap!=16)
                    $fatal(1,"retry wait published a result");
                if(KIND==2 && retry_wait_cycles<100 && scans!=32)
                    $fatal(1,"retry did not wait for new activity");
            end
            if(dut.state==5)begin
                if(dut.scan_tap!==5'(scans%32))$fatal(1,"tap order KIND%0d",KIND);
                expected_pass=!(KIND==3 || KIND==4 || KIND==5 ||
                    (KIND==2 && scans<32) || (KIND==7 && !OTHER_TAPS[tap]));
                if(dut.pass_flag!==expected_pass)$fatal(1,"tap score KIND%0d tap%0d",KIND,tap);
                scans=scans+1;
            end
            if(done)begin
                if(window!==6'(EXPECT_LEN) || tap!==5'(EXPECT_TAP) ||
                    valid!==(EXPECT_LEN!=0) || failed!==(EXPECT_LEN==0) || scans!=EXPECT_SCANS)
                    $fatal(1,"result KIND%0d len%0d tap%0d valid%0d failed%0d scans%0d",
                        KIND,window,tap,valid,failed,scans);
                if(KIND==4 && test_entries!=0)$fatal(1,"sticky valid scored a new tap");
                if(first_scan<START_CYCLE)$fatal(1,"early scan KIND%0d",KIND);
                stable_cycles=stable_cycles+1;
                if(stable_cycles==128)begin
                    $display("CASE activity KIND=%0d first_scan=%0d taps=%0d tests=%0d len=%0d tap=%0d PASS",
                        KIND,first_scan,scans,test_entries,window,tap);
                    finished=1;
                end
            end
        end
    end
endmodule

module calibration_retry_reset_case(input wire clk,start,output reg finished=0);
    reg rst_n=0,pass_mode=0;
    reg [31:0] raw_bytes=0;
    integer acquire_cycles=0;
    wire [3:0] aligned=(dut.state==9 && acquire_cycles<2)?4'b0000:
        pass_mode?4'b1111:4'b0001;
    wire [4:0] tap;
    wire [5:0] window;
    wire done,valid,failed;
    ph1a_rx_delay_scan #(.TEST_LEN(16),.PASS_THRESH(4),.SETTLE_CYCLES(4),
        .WAIT_CYCLES(32)) dut (.I_byte_clk(clk),.I_reset_n(rst_n),
        .I_raw_bytes(raw_bytes),.I_byte_align_done(aligned),.O_delay_value(tap),
        .O_delay_vaild(),.O_scan_done(done),.O_window_len(window),
        .O_window_valid(valid),.O_scan_failed(failed));
    always @(negedge clk)begin
        if(!rst_n)begin raw_bytes=0;acquire_cycles=0;end
        else if(!finished)begin
            raw_bytes=raw_bytes+32'h01010101;
            if(dut.state==9)acquire_cycles=acquire_cycles+1;
            else acquire_cycles=0;
        end
    end
    initial begin
        wait(start);@(negedge clk);rst_n=1;
        wait(dut.retry_used && dut.state==1);
        repeat(3)@(negedge clk);rst_n=0;
        #1;
        if(done || valid || failed || tap!=16 || window!=0 || dut.retry_used || dut.seen_low!=0)
            $fatal(1,"reset retained retry/acquisition/result state");
        pass_mode=1;repeat(2)@(negedge clk);rst_n=1;
        wait(done);#1;
        if(!valid || failed || window!=32 || tap!=16 || dut.retry_used)
            $fatal(1,"reset did not restore first scan budget");
        finished=1;
        $display("CASE health_reset_clears_retry_and_partial_acquisition PASS");
    end
endmodule

module tb_calibration_activity_retry;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    wire [10:0] finished;
    calibration_activity_case #(.KIND(0),.START_CYCLE(1000))
        one_lane_then_late(clk,rst_n,finished[0]);
    calibration_activity_case #(.KIND(1),.START_CYCLE(8388736),.WAIT_LIMIT(8388608))
        late_after_old_timeout(clk,rst_n,finished[1]);
    calibration_activity_case #(.KIND(2),.EXPECT_SCANS(64))
        new_activity_retry(clk,rst_n,finished[2]);
    calibration_activity_case #(.KIND(3),.EXPECT_LEN(0),.EXPECT_SCANS(64))
        bounded_two_failures(clk,rst_n,finished[3]);
    calibration_activity_case #(.KIND(4),.SCAN_LIMIT(1),.EXPECT_LEN(0))
        sticky_old_valid(clk,rst_n,finished[4]);
    calibration_activity_case #(.KIND(5),.SCAN_LIMIT(1),.EXPECT_LEN(0))
        only63(clk,rst_n,finished[5]);
    calibration_activity_case #(.KIND(6),.SCAN_LIMIT(1))
        exact64(clk,rst_n,finished[6]);
    calibration_activity_case #(.KIND(7),.EXPECT_LEN(4),.EXPECT_TAP(6))
        bad16_other_taps_pass(clk,rst_n,finished[7]);
    calibration_activity_case #(.KIND(8),.START_CYCLE(320))
        clear_activity_each_window(clk,rst_n,finished[8]);
    calibration_activity_case #(.KIND(9))
        staggered_lane_retirement(clk,rst_n,finished[9]);
    calibration_retry_reset_case reset_retry(clk,rst_n,finished[10]);
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        wait(&finished);
        $display("PASS PH1A activity launch/fresh acquisition/bounded retry/default no-data timeout");
        $finish;
    end
    initial begin #100000000;$fatal(1,"activity/retry test timeout");end
endmodule
