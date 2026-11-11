`timescale 1ns/1ps
`include "vectors_sizes.vh"

module tb_hdr_merge;
    bit clk = 0, clock_running = 1;
    always #3.751 if (clock_running) clk = !clk;
    bit rst_n, clear;
    wire [2:0] cfg_ratio_log2 = 3'd4;
    wire [9:0] cfg_black_long = 10'd50, cfg_black_short = 10'd50;
    bit [13:0] cfg_motion_base;
    bit [3:0] cfg_motion_shift;
    bit [1:0] cfg_fusion_preset;
    bit [39:0] s_long, s_short;
    bit s_valid, s_sof, s_eol;
    wire s_ready;
    wire [55:0] m_raw;
    wire [3:0] m_motion;
    wire m_valid, m_sof, m_eol;
    bit force_hold, throttle;
    int cycle = 0;
    always @(negedge clk) cycle++;
    wire m_ready = !force_hold && (!throttle || cycle % 19 < 12);

    hdr_merge4 #(.KNEE_LOW(768), .KNEE_HIGH(896)) dut (.*);

    typedef struct packed {
        logic [39:0] long_raw, short_raw;
        logic [13:0] base;
        logic [3:0] shift;
        logic [1:0] preset;
        logic sof, eol;
        logic [55:0] raw;
        logic [3:0] motion;
    } sample_t;

    sample_t samples[0:`MERGE_COUNT-1];
    logic [61:0] expected;
    int accepted, received, stalled, latency = 0;
    stream_checker #(.WIDTH(62)) scoreboard (
        .clk(clk), .flush(!rst_n || clear), .s_valid(s_valid), .s_ready(s_ready),
        .m_valid(m_valid), .m_ready(m_ready), .s_expected(expected),
        .m_payload({m_sof, m_eol, m_motion, m_raw}), .latency(latency), .spacing(0),
        .accepted(accepted), .received(received), .stalled(stalled)
    );

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            if (m_valid !== 0 || s_ready !== 0)
                $fatal(1, "DATAPATH_FAIL merge cancel failed to mask handshakes");
        end else if (s_ready !== (!m_valid || m_ready)) begin
            $fatal(1, "DATAPATH_FAIL merge input READY did not follow contract");
        end
    end

    task automatic send_sample(input int index);
        sample_t sample;
        bit took;
        sample = samples[index];
        {s_long, s_short, cfg_motion_base, cfg_motion_shift, cfg_fusion_preset, s_sof, s_eol} =
            {sample.long_raw, sample.short_raw, sample.base, sample.shift, sample.preset, sample.sof, sample.eol};
        expected = {sample.sof, sample.eol, sample.motion, sample.raw};
        s_valid = 1;
        do begin
            @(posedge clk);
            took = s_ready;
            @(negedge clk);
        end while (!took);
        s_valid = 0;
    endtask

    task automatic drain;
        while (received < accepted)
            @(negedge clk);
        repeat (8) @(negedge clk);
    endtask

    task automatic discard_pending(input bit by_reset);
        force_hold = 1;
        for (int index = 0; index < 6; index++)
            send_sample(index);
        while (!m_valid)
            @(negedge clk);
        repeat (3) @(negedge clk);

        // Assert the cancellation while the clock is parked low, then resume under it.
        clock_running = 0;
        #10;
        if (by_reset)
            rst_n = 0;
        else
            clear = 1;
        #1;
        if (m_valid !== 0 || s_ready !== 0)
            $fatal(1, "DATAPATH_FAIL merge cancel did not immediately mask while clock stopped");
        clock_running = 1;
        repeat (8) @(negedge clk);
        rst_n = 1;
        clear = 0;
        force_hold = 0;
        repeat (9) @(negedge clk);
        if (received != 0 || accepted != 0)
            $fatal(1, "DATAPATH_FAIL merge old work after cancel");
    endtask

    initial begin
        int stalled_total;
        $readmemh("merge.mem", samples);
        repeat (8) @(negedge clk);
        rst_n = 1;
        latency = 6;
        for (int index = 0; index < `MERGE_COUNT; index++)
            send_sample(index);
        drain();
        if (received != `MERGE_COUNT)
            $fatal(1, "DATAPATH_FAIL merge continuous groups count=%0d", received);

        latency = 0;
        throttle = 1;
        for (int index = 0; index < 160; index++)
            send_sample(index);
        drain();
        throttle = 0;
        stalled_total = stalled;
        if (received != `MERGE_COUNT + 160 || stalled_total == 0)
            $fatal(1, "DATAPATH_FAIL merge throttle fixture did not reach coverage");

        discard_pending(0);
        for (int index = 64; index < 128; index++)
            send_sample(index);
        drain();
        if (received != 64)
            $fatal(1, "DATAPATH_FAIL merge recovery after clear");
        discard_pending(1);
        for (int index = 128; index < 192; index++)
            send_sample(index);
        drain();
        if (received != 64)
            $fatal(1, "DATAPATH_FAIL merge recovery after reset");

        $display("MERGE_PASS paired_groups=%0d throttled_groups=160 stall_cycles=%0d recovery_groups=128",
                 `MERGE_COUNT, stalled_total);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "DATAPATH_FAIL merge simulation watchdog at in=%0d out=%0d", accepted, received);
    end
endmodule
