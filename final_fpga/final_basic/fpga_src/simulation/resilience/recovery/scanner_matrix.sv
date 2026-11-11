`timescale 1ns/1ps

// Stimulus uses public tap-load events and externally scheduled lane-valid
// patterns. DUT state is observed only for reset coverage and score diagnostics.
module scanner_matrix_case #(
    parameter integer ID=0,
    parameter [31:0] MASK=32'hffffffff,
    parameter [31:0] SECOND_MASK=32'hffffffff,
    parameter [127:0] PATTERN=128'hffffffffffffffffffffffffffffffff,
    parameter integer EXPECT_LEN=32,
    parameter integer EXPECT_TAP=16,
    parameter integer EXPECT_SCANS=32,
    parameter integer TEST_LEN=160,
    parameter integer SETTLE=4,
    parameter integer WAIT_LIMIT=256,
    parameter integer MAX_SCANS=1,
    parameter integer START_AGE=12,
    parameter integer STUCK_MASK=0,
    parameter integer STAGGER=0,
    parameter integer RESET_STATE=-1,
    parameter integer REARM_GAP=0,
    parameter integer TRACE=0
)(output reg finished=0, output reg failed_case=0);
    reg clk=0, rst_n=0, pause_clock=0;
    always #5 if(!pause_clock) clk=~clk;
    reg [31:0] raw_bytes=0;
    reg [3:0] aligned=0;
    wire [4:0] tap;
    wire [5:0] window;
    wire load,done,valid,failed;
    integer load_count=0,next_tap=0,active_tap=-1,age=0,round_number=0;
    integer retry_age=-1,external_cycles=0,observed_scans=0;
    integer score_errors=0,order_errors=0,terminal_errors=0,stable_cycles=0;
    integer presented_count=0,first_score_count=-1;
    reg reset_failure=0;
    reg [9:0] state_coverage=0;
    reg selected_tap_good;

    ph1a_rx_delay_scan #(.TEST_LEN(TEST_LEN),.PASS_THRESH(64),
        .SETTLE_CYCLES(SETTLE),.WAIT_CYCLES(WAIT_LIMIT),
        .MAX_SCANS(MAX_SCANS)) dut (
        .I_byte_clk(clk),.I_reset_n(rst_n),.I_raw_bytes(raw_bytes),
        .I_byte_align_done(aligned),.O_delay_value(tap),.O_delay_vaild(load),
        .O_scan_done(done),.O_window_len(window),.O_window_valid(valid),
        .O_scan_failed(failed));

    // No state-dependent valid extension: one precomputed 128-edge pattern per
    // physical code, positioned after the public load pulse.
    always @(negedge clk or negedge rst_n) begin
        if(!rst_n) begin
            raw_bytes=0; aligned=0; load_count=0; next_tap=0;
            active_tap=-1; age=0; round_number=0; retry_age=-1;
            external_cycles=0; presented_count=0;
        end else if(!finished) begin
            external_cycles=external_cycles+1;
            if(retry_age<0 || retry_age>=REARM_GAP)
                raw_bytes=raw_bytes+32'h01010101;
            if(retry_age>=0) retry_age=retry_age+1;
            if(load) begin
                load_count=load_count+1;
                if(load_count==1) begin
                    if(tap!==16) order_errors=order_errors+1;
                end else if(next_tap<32) begin
                    if(tap!==5'(next_tap)) order_errors=order_errors+1;
                    if(round_number>0 && retry_age<REARM_GAP)
                        order_errors=order_errors+1;
                    active_tap=next_tap; next_tap=next_tap+1;
                    age=0; presented_count=0;
                end else begin
                    active_tap=-1;
                    if(!valid && !failed) begin
                        round_number=round_number+1; next_tap=0; retry_age=0;
                    end
                end
            end
            aligned=4'(STUCK_MASK);
            if(active_tap>=0) begin
                selected_tap_good=(round_number==0)?MASK[active_tap]:SECOND_MASK[active_tap];
                if(STAGGER && age>=SETTLE+1 && age<=SETTLE+4)
                    aligned=4'b1111 ^ (4'b0001 << (age-SETTLE-1));
                else if(age>=START_AGE && age<START_AGE+128 && selected_tap_good)
                    aligned=PATTERN[age-START_AGE]?4'b1111:4'(STUCK_MASK);
                age=age+1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            observed_scans=0; score_errors=0; order_errors=0; terminal_errors=0;
            stable_cycles=0; state_coverage=0; first_score_count=-1;
            finished=0; failed_case=0;
        end else if(!finished) begin
            state_coverage[dut.state]=1;
            if(active_tap>=0 && (&aligned)) presented_count=presented_count+1;
            if(TRACE && active_tap==0 && (dut.state==9 || dut.state==4) &&
                (presented_count<=2 || (age>=START_AGE+62 && age<=START_AGE+67)))
                $display("TRACE id=%0d cycle=%0d state=%0d tap=%0d age=%0d aligned=%h presented=%0d cnt=%0d align_cnt=%0d",
                    ID,external_cycles,dut.state,tap,age,aligned,presented_count,dut.cnt,dut.align_cnt);
            if(dut.state==5) begin
                observed_scans=observed_scans+1;
                if(TRACE && active_tap==0) begin
                    first_score_count=dut.align_cnt;
                    $display("SCORE id=%0d tap=%0d presented=%0d counted=%0d pass=%0d",
                        ID,tap,presented_count,dut.align_cnt,dut.pass_flag);
                end
            end
            if(done) begin
                if(stable_cycles==0) begin
                    if(window!==6'(EXPECT_LEN) || tap!==5'(EXPECT_TAP) ||
                        valid!==(EXPECT_LEN!=0) || failed!==(EXPECT_LEN==0) ||
                        observed_scans!=EXPECT_SCANS)
                        terminal_errors=terminal_errors+1;
                end
                stable_cycles=stable_cycles+1;
                if(stable_cycles==32) begin
                    failed_case=(terminal_errors!=0 || order_errors!=0 || reset_failure);
                    $display("CASE id=%0d verdict=%s expected_len=%0d expected_tap=%0d expected_scans=%0d got_len=%0d got_tap=%0d got_scans=%0d valid=%0d failed=%0d order_errors=%0d reset_failure=%0d coverage=%h",
                        ID,failed_case?"FAIL":"PASS",EXPECT_LEN,EXPECT_TAP,EXPECT_SCANS,
                        window,tap,observed_scans,valid,failed,order_errors,reset_failure,state_coverage);
                    finished=1;
                end
            end else if(retry_age>=0 && retry_age<REARM_GAP && (valid || failed || window!=0))
                terminal_errors=terminal_errors+1;
        end
    end

    initial begin
        #1; rst_n=0;
        #21; rst_n=1;
        if(RESET_STATE>=0) begin
            if(RESET_STATE==10) wait(dut.retry_used && dut.state==1);
            else wait(dut.state==RESET_STATE);
            #2; pause_clock=1;
            #1; rst_n=0;
            #1;
            if(done || valid || failed || load || tap!==16 || window!==0 ||
                dut.retry_used || dut.seen_low!==0 || dut.cnt!==0 ||
                dut.align_cnt!==0 || dut.wait_cnt!==0 || dut.cur_len!==0 ||
                dut.in_run || dut.pass_flag) reset_failure=1;
            $display("RESET id=%0d state=%0d stopped_clock=1 async_clear=%s",
                ID,RESET_STATE,reset_failure?"FAIL":"PASS");
            #23; pause_clock=0;
            #11; rst_n=1;
        end
    end
    initial begin
        #40000000;
        if(!finished) begin
            failed_case=1; finished=1;
            $display("CASE id=%0d verdict=FAIL timeout=1 state=%0d scans=%0d loads=%0d",
                ID,dut.state,observed_scans,load_count);
        end
    end
endmodule

// Raw launch tests count external edges after the initial public load.
module scanner_activity_case #(
    parameter integer ID=0,
    parameter integer KIND=0,
    parameter integer THRESHOLD=8,
    parameter integer WAIT_LIMIT=16,
    parameter integer LAST_CHANGE=16,
    parameter integer EXPECT_EDGE=-1
)(output reg finished=0, output reg failed_case=0);
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [31:0] raw_bytes=0;
    wire [4:0] tap;
    wire [5:0] window;
    wire load,done,valid,failed;
    integer edge_number=-1,lane,scan_edge=-1,loads=0;
    integer stimulus_edge=0;
    ph1a_rx_delay_scan #(.TEST_LEN(64),.PASS_THRESH(64),
        .SETTLE_CYCLES(4),.ACTIVITY_THRESHOLD(THRESHOLD),
        .WAIT_CYCLES(WAIT_LIMIT),.MAX_SCANS(1)) dut (
        .I_byte_clk(clk),.I_reset_n(rst_n),.I_raw_bytes(raw_bytes),
        .I_byte_align_done(4'b0000),.O_delay_value(tap),.O_delay_vaild(load),
        .O_scan_done(done),.O_window_len(window),.O_window_valid(valid),.O_scan_failed(failed));
    always @(negedge clk) if(rst_n && !finished) begin
        stimulus_edge=stimulus_edge+1;
        if(KIND==0) begin
            if(stimulus_edge>=LAST_CHANGE-THRESHOLD+1 && stimulus_edge<=LAST_CHANGE)
                raw_bytes=raw_bytes+32'h01010101;
        end else if(KIND==1) begin
            if(stimulus_edge<THRESHOLD) raw_bytes=raw_bytes+32'h01010101;
        end else if(KIND==2) begin
            if(stimulus_edge<=THRESHOLD) begin
                raw_bytes[23:0]=raw_bytes[23:0]+24'h010101;
                if(stimulus_edge<THRESHOLD)raw_bytes[31:24]=raw_bytes[31:24]+1;
            end
        end else if(KIND==3) begin
            if(stimulus_edge%4==0)raw_bytes=raw_bytes+32'h01010101;
        end else if(KIND==4) begin
            // Seven changes in the old window, one in the new one.
            if((stimulus_edge>=2 && stimulus_edge<=THRESHOLD) ||
                stimulus_edge==WAIT_LIMIT+1)raw_bytes=raw_bytes+32'h01010101;
        end else if(KIND==5) begin
            for(lane=0;lane<4;lane=lane+1)
                if(stimulus_edge>=LAST_CHANGE-THRESHOLD+1-(3-lane) &&
                    stimulus_edge<=LAST_CHANGE-(3-lane))
                    raw_bytes[8*lane+:8]=raw_bytes[8*lane+:8]+1;
        end
    end
    always @(posedge clk) if(rst_n && !finished) begin
        edge_number=edge_number+1;
        #1;
        if(load) begin
            loads=loads+1;
            if(loads==2)scan_edge=edge_number;
        end
        if(scan_edge>=0 || edge_number>=WAIT_LIMIT*5+4) begin
            failed_case=(scan_edge!=EXPECT_EDGE || done || valid || failed || window!=0);
            $display("ACTIVITY id=%0d verdict=%s kind=%0d threshold=%0d wait=%0d expected_edge=%0d got_edge=%0d",
                ID,failed_case?"FAIL":"PASS",KIND,THRESHOLD,WAIT_LIMIT,EXPECT_EDGE,scan_edge);
            finished=1;
        end
    end
    initial begin #22;rst_n=1;end
endmodule

module scanner_matrix_tb;
    `include "scanner_cases.svh"
    integer i,passes,failures;
    initial begin
        wait(&finished);
        passes=0; failures=0;
        for(i=0;i<CASE_COUNT;i=i+1) begin
            if(failed_case[i])failures=failures+1; else passes=passes+1;
        end
        $display("SCANNER_MATRIX_COMPLETE cases=%0d passed=%0d failed=%0d",CASE_COUNT,passes,failures);
        $finish;
    end
endmodule
