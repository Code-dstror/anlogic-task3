`timescale 1ns/1ps
`include "vectors_sizes.vh"

module tb_hdr_tone;
    bit clk = 0;
    always #4 clk = !clk;
    bit rst_n, clear;
    bit [167:0] s_data;
    bit s_hdr, s_valid, s_sof, s_eol, s_clipped;
    bit [1:0] s_preset;
    bit [23:0] s_highlight_weight;
    wire s_ready;
    wire [119:0] m_data;
    wire m_valid, m_sof, m_eol, m_clipped;
    bit force_hold, throttle;
    int cycle = 0;
    always @(negedge clk) cycle++;
    wire m_ready = !force_hold && (!throttle || cycle % 17 < 10);

    hdr_tone96_shared4 dut (.*);

    typedef struct packed {
        logic [167:0] raw;
        logic hdr;
        logic [1:0] page;
        logic [23:0] weights;
        logic sof, eol, clipped;
        logic [119:0] rgb;
    } sample_t;

    sample_t samples[0:`TONE_COUNT-1];
    logic [122:0] expected;
    int accepted, received, stalled, spacing = 0;
    stream_checker #(.WIDTH(123)) scoreboard (
        .clk(clk), .flush(!rst_n || clear), .s_valid(s_valid), .s_ready(s_ready),
        .m_valid(m_valid), .m_ready(m_ready), .s_expected(expected),
        .m_payload({m_sof, m_eol, m_clipped, m_data}), .latency(0), .spacing(spacing),
        .accepted(accepted), .received(received), .stalled(stalled)
    );

    always @(posedge clk) begin
        if ((!rst_n || clear) && (s_ready === 1'b1 || m_valid === 1'b1))
            $fatal(1, "DATAPATH_FAIL tone cancel did not suppress handshakes");
    end

    task automatic send_sample(input int index);
        sample_t sample;
        bit took;
        sample = samples[index];
        {s_data, s_hdr, s_preset, s_highlight_weight, s_sof, s_eol, s_clipped} =
            {sample.raw, sample.hdr, sample.page, sample.weights, sample.sof, sample.eol, sample.clipped};
        expected = {sample.sof, sample.eol, sample.clipped, sample.rgb};
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
        repeat (12) @(negedge clk);
    endtask

    task automatic discard_pending(input bit by_reset);
        force_hold = 1;
        send_sample(4096);
        while (!m_valid)
            @(negedge clk);
        repeat (3) @(negedge clk);
        #1;
        if (by_reset)
            rst_n = 0;
        else
            clear = 1;
        repeat (8) @(negedge clk);
        rst_n = 1;
        clear = 0;
        force_hold = 0;
        repeat (12) @(negedge clk);
        if (received != 0 || accepted != 0)
            $fatal(1, "DATAPATH_FAIL tone old work after cancel");
    endtask

    initial begin
        int stalled_total;
        $readmemh("tone.mem", samples);
        repeat (8) @(negedge clk);
        rst_n = 1;
        spacing = 2;
        for (int index = 0; index < 16384; index++)
            send_sample(index);
        drain();
        if (received != 16384)
            $fatal(1, "DATAPATH_FAIL tone grayscale sweep did not retire every group");

        spacing = 0;
        throttle = 1;
        for (int index = 16384; index < `TONE_COUNT; index++)
            send_sample(index);
        drain();
        throttle = 0;
        stalled_total = stalled;
        if (received != `TONE_COUNT || stalled_total == 0)
            $fatal(1, "DATAPATH_FAIL tone chromatic/SDR throttle fixture did not reach coverage");

        discard_pending(0);
        for (int index = 8192; index < 8256; index++)
            send_sample(index);
        drain();
        if (received != 64)
            $fatal(1, "DATAPATH_FAIL tone recovery after clear");
        discard_pending(1);
        for (int index = 12288; index < 12352; index++)
            send_sample(index);
        drain();
        if (received != 64)
            $fatal(1, "DATAPATH_FAIL tone recovery after reset");

        $display("TONE_PASS gray_codes=65536 pages=4 hdr_accept_spacing=2 mixed_groups=%0d stall_cycles=%0d recovery_groups=128",
                 `TONE_COUNT - 16384, stalled_total);
        $finish;
    end

    initial begin
        #800000;
        $fatal(1, "DATAPATH_FAIL tone simulation watchdog at in=%0d out=%0d", accepted, received);
    end
endmodule
