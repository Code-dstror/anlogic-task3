`timescale 1ns/1ps

// PH1A HR input delay has exactly 32 physical codes (UG910 v1.6, section 36).
// Score the same all-lanes-aligned cycles as the frozen auto_delay_ctl. This
// score is not an ECC/CRC check or a measured electrical eye. Raw activity
// starts at most two scans per health reset; no acceptable window fails closed.
module ph1a_rx_delay_scan #(
    parameter integer MIPI_LAN = 4,
    parameter integer TEST_LEN = 32767,
    parameter integer PASS_THRESH = 64,
    parameter integer SETTLE_CYCLES = 256,
    parameter integer ACTIVITY_THRESHOLD = 8,
    parameter integer WAIT_CYCLES = 8388608,
    parameter integer MAX_SCANS = 2
) (
    input wire I_byte_clk,
    input wire I_reset_n,
    input wire [8*MIPI_LAN-1:0] I_raw_bytes,
    input wire [MIPI_LAN-1:0] I_byte_align_done,
    output reg [4:0] O_delay_value,
    output reg O_delay_vaild,
    output reg O_scan_done,
    output wire [5:0] O_window_len,
    output reg O_window_valid,
    output reg O_scan_failed
);
    localparam [3:0] ST_WAIT_DATA=0, ST_WAIT_SET=1, ST_SET_TAP=2,
        ST_SETTLE=3, ST_TEST=4, ST_NEXT=5, ST_FIND=6, ST_APPLY=7,
        ST_DONE=8, ST_ACQUIRE=9;
    reg [3:0] state;
    reg [4:0] scan_tap, cur_start, best_start;
    reg [5:0] cur_len, best_len;
    reg [15:0] cnt, align_cnt;
    reg [23:0] wait_cnt;
    reg pass_flag, in_run, retry_used;
    reg [8*MIPI_LAN-1:0] raw_previous;
    reg [3:0] activity_count [0:MIPI_LAN-1];
    reg [MIPI_LAN-1:0] seen_low;
    wire [MIPI_LAN-1:0] activity_qualified;
    wire all_aligned = &I_byte_align_done;
    integer lane;
    genvar activity_lane;
    generate for (activity_lane=0; activity_lane<MIPI_LAN;
        activity_lane=activity_lane+1) begin : g_activity
        // Include this edge so the final change at a window boundary counts.
        assign activity_qualified[activity_lane] =
            (activity_count[activity_lane]>=ACTIVITY_THRESHOLD) ||
            ((activity_count[activity_lane]==ACTIVITY_THRESHOLD-1) &&
             (I_raw_bytes[8*activity_lane+:8]!=raw_previous[8*activity_lane+:8]));
    end endgenerate
    assign O_window_len = best_len;

    // Fixed register widths support these simulation/production parameters.
    // synthesis translate_off
    initial begin
        if (ACTIVITY_THRESHOLD<1 || ACTIVITY_THRESHOLD>15 ||
            WAIT_CYCLES<1 || WAIT_CYCLES>16777216 ||
            TEST_LEN<1 || TEST_LEN>65535 || PASS_THRESH<1 || PASS_THRESH>TEST_LEN ||
            SETTLE_CYCLES<1 || SETTLE_CYCLES>65536 ||
            (MAX_SCANS!=1 && MAX_SCANS!=2)) begin
            $display("ERROR invalid ph1a_rx_delay_scan parameters");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge I_byte_clk or negedge I_reset_n) begin
        if (!I_reset_n) begin
            state<=ST_WAIT_DATA;
            scan_tap<=0; cur_start<=0; best_start<=0;
            cur_len<=0; best_len<=0;
            cnt<=0; align_cnt<=0; wait_cnt<=0;
            pass_flag<=0; in_run<=0; retry_used<=0;
            raw_previous<=0; seen_low<=0;
            for (lane=0; lane<MIPI_LAN; lane=lane+1) activity_count[lane]<=0;
            O_delay_value<=5'd16;
            O_delay_vaild<=0; O_scan_done<=0;
            O_window_valid<=0; O_scan_failed<=0;
        end else begin
            O_delay_vaild<=0;
            raw_previous<=I_raw_bytes;
            case (state)
                ST_WAIT_DATA: begin
                    O_delay_value<=5'd16;
                    O_delay_vaild<=1;
                    wait_cnt<=0; cnt<=0;
                    for (lane=0; lane<MIPI_LAN; lane=lane+1) activity_count[lane]<=0;
                    state<=ST_WAIT_SET;
                end
                ST_WAIT_SET: begin
                    // Activity is only a launch condition, not a passing tap.
                    // No-data windows remain pending instead of empty scans.
                    for (lane=0; lane<MIPI_LAN; lane=lane+1)
                        if (activity_count[lane]<ACTIVITY_THRESHOLD &&
                            I_raw_bytes[8*lane+:8]!=raw_previous[8*lane+:8])
                            activity_count[lane]<=activity_count[lane]+1'b1;
                    if (&activity_qualified) begin
                        scan_tap<=0;
                        state<=ST_SET_TAP;
                    end else if (wait_cnt==WAIT_CYCLES-1) begin
                        wait_cnt<=0;
                        for (lane=0; lane<MIPI_LAN; lane=lane+1) activity_count[lane]<=0;
                    end else wait_cnt<=wait_cnt+1'b1;
                end
                ST_SET_TAP: begin
                    O_delay_value<=scan_tap;
                    O_delay_vaild<=1;
                    cnt<=0; align_cnt<=0; wait_cnt<=0;
                    seen_low<=0; pass_flag<=0;
                    state<=ST_SETTLE;
                end
                ST_SETTLE: begin
                    if (cnt==SETTLE_CYCLES-1) begin
                        cnt<=0; pass_flag<=0;
                        wait_cnt<=0; seen_low<=0;
                        state<=ST_ACQUIRE;
                    end else cnt<=cnt+1'b1;
                end
                ST_ACQUIRE: begin
                    // Each lane must retire its pre-tap valid state after
                    // settling. A held old packet cannot score a new code.
                    seen_low<=seen_low | ~I_byte_align_done;
                    if ((&seen_low) && all_aligned) begin
                        // Acquisition is the first of TEST_LEN scoring edges.
                        cnt<=1; align_cnt<=1;
                        state<=ST_TEST;
                    end else if (wait_cnt==WAIT_CYCLES-1) begin
                        pass_flag<=0;
                        state<=ST_NEXT;
                    end else wait_cnt<=wait_cnt+1'b1;
                end
                ST_TEST: begin
                    if (cnt==TEST_LEN) begin
                        pass_flag<=(align_cnt>=PASS_THRESH);
                        state<=ST_NEXT;
                    end else begin
                        cnt<=cnt+1'b1;
                        if (all_aligned) align_cnt<=align_cnt+1'b1;
                    end
                end
                ST_NEXT: begin
                    if (pass_flag) begin
                        if (!in_run) begin
                            in_run<=1; cur_start<=scan_tap; cur_len<=6'd1;
                        end else cur_len<=cur_len+1'b1;
                    end else if (in_run) begin
                        // Strict comparison keeps the earliest equal-length run.
                        if (cur_len>best_len) begin
                            best_start<=cur_start; best_len<=cur_len;
                        end
                        in_run<=0; cur_len<=0;
                    end
                    if (scan_tap==5'd31) state<=ST_FIND;
                    else begin scan_tap<=scan_tap+1'b1; state<=ST_SET_TAP; end
                end
                ST_FIND: begin
                    // Do not join the ending run to the beginning of the scan.
                    if (in_run && cur_len>best_len) begin
                        best_start<=cur_start; best_len<=cur_len;
                    end
                    state<=ST_APPLY;
                end
                ST_APPLY: begin
                    O_delay_vaild<=1;
                    if (best_len==0 && MAX_SCANS==2 && !retry_used) begin
                        // Retry only after newly observed raw activity. It
                        // never grants publication or repeats a passed scan.
                        retry_used<=1;
                        O_delay_value<=5'd16;
                        O_scan_done<=0; O_window_valid<=0; O_scan_failed<=0;
                        scan_tap<=0; cur_start<=0; best_start<=0;
                        cur_len<=0; best_len<=0; in_run<=0; pass_flag<=0;
                        cnt<=0; align_cnt<=0; wait_cnt<=0; seen_low<=0;
                        for (lane=0; lane<MIPI_LAN; lane=lane+1) activity_count[lane]<=0;
                        state<=ST_WAIT_SET;
                    end else begin
                        O_window_valid<=(best_len!=0);
                        O_scan_failed<=(best_len==0);
                        O_delay_value<=(best_len!=0) ? best_start+best_len[5:1] : 5'd16;
                        state<=ST_DONE;
                    end
                end
                ST_DONE: O_scan_done<=1;
                default: state<=ST_WAIT_DATA;
            endcase
        end
    end
endmodule
