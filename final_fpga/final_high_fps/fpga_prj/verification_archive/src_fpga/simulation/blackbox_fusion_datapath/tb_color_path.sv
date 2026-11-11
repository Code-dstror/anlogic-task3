`timescale 1ns/1ps
`include "vectors_sizes.vh"

module tb_color_path #(parameter integer ISP = 0);
    localparam integer SAMPLE_COUNT = ISP ? `ISP_COUNT : `COLOR_COUNT;

    bit clk = 0;
    always #4 clk = !clk;
    bit rst_n;
    bit [12:0] cfg_width, cfg_height;
    bit [1:0] cfg_bayer_phase, cfg_tone_preset;
    bit cfg_hdr;
    bit [3:0] cfg_tone_shift;
    bit [29:0] cfg_wb_gains;
    bit [167:0] s_data;
    bit s_valid, s_sof, s_eol;
    wire s_ready;
    wire [95:0] m_data;
    wire m_valid, m_sof, m_eol, o_job_idle;
    wire [31:0] stat_beats, stat_frames, stat_saturated;
    bit force_hold;
    int remaining_hold = 0, last_held = -1;
    wire m_ready = !force_hold && remaining_hold == 0;

    if (ISP) begin : shared
        shared_wide_isp #(.MAX_WIDTH(3840), .MAX_HEIGHT(2160), .GAMMA_BYPASS(0),
                          .HDR_BLACK_CORRECTED_ENABLE(1)) dut (.s_data(s_data[55:0]), .*);
    end else begin : direct
        wide_color_pipeline #(.GAMMA_BYPASS(0)) dut (.*);
        assign o_job_idle = 1;
    end

    typedef struct packed {
        logic [167:0] input_data;
        logic [12:0] width, height;
        logic [1:0] phase;
        logic hdr;
        logic [1:0] page;
        logic [29:0] gains;
        logic [3:0] shift;
        logic sof, eol;
        logic [95:0] rgb;
        logic clipped, frame_end;
    } sample_t;

    sample_t samples[0:SAMPLE_COUNT-1];
    logic [97:0] expected;
    int accepted, received, stalled;
    stream_checker #(.WIDTH(98)) scoreboard (
        .clk(clk), .flush(!rst_n), .s_valid(s_valid), .s_ready(s_ready),
        .m_valid(m_valid), .m_ready(m_ready), .s_expected(expected),
        .m_payload({m_sof, m_eol, m_data}), .latency(0), .spacing(0),
        .accepted(accepted), .received(received), .stalled(stalled)
    );

    bit expected_clip, expected_frame_end, watch_idle;
    bit clips[$], ends[$];
    bit clipped, frame_end;
    int beats, frames, saturation, input_frames, output_ends, overlaps, tail_stalls;
    int job_goal;

    always @(posedge clk) begin
        if (!rst_n) begin
            clips.delete();
            ends.delete();
            beats = 0;
            frames = 0;
            saturation = 0;
            input_frames = 0;
            output_ends = 0;
            overlaps = 0;
            tail_stalls = 0;
        end else begin
            if (watch_idle && beats < job_goal && o_job_idle !== 1'b0)
                $fatal(1, "DATAPATH_FAIL ISP released ownership early at RGB group=%0d goal=%0d", beats, job_goal);
            if (watch_idle && beats == job_goal - 1 && m_valid && !m_ready)
                tail_stalls++;
            if (s_valid && s_ready) begin
                clips.push_back(expected_clip);
                ends.push_back(expected_frame_end);
                if (s_sof) begin
                    if (input_frames > output_ends)
                        overlaps++;
                    input_frames++;
                end
            end
            if (m_valid && m_ready) begin
                if (clips.size() == 0 || ends.size() == 0)
                    $fatal(1, "DATAPATH_FAIL unexpected RGB transfer");
                clipped = clips.pop_front();
                frame_end = ends.pop_front();
                beats++;
                if (m_sof)
                    frames++;
                if (clipped)
                    saturation++;
                if (frame_end)
                    output_ends++;
            end
        end
    end

    always @(negedge clk) begin
        if (!rst_n) begin
            remaining_hold = 0;
            last_held = -1;
        end else begin
            if ({stat_beats, stat_frames, stat_saturated} !== {beats, frames, saturation})
                $fatal(1, "DATAPATH_FAIL statistics got %0d/%0d/%0d expected %0d/%0d/%0d",
                       stat_beats, stat_frames, stat_saturated, beats, frames, saturation);
            if (remaining_hold != 0)
                remaining_hold--;
            else if (!force_hold && m_valid && beats != last_held && (m_sof || m_eol || beats % 53 == 9)) begin
                remaining_hold = m_eol ? 6 : 4;
                last_held = beats;
            end
        end
    end

    task automatic send_sample(input int index, input bit allow_cancel = 0);
        sample_t sample;
        bit took;
        sample = samples[index];
        {s_data, s_sof, s_eol} = {sample.input_data, sample.sof, sample.eol};
        expected = {sample.sof, sample.eol, sample.rgb};
        expected_clip = sample.clipped;
        expected_frame_end = sample.frame_end;
        cfg_tone_shift = sample.shift;
        if (s_sof) begin
            {cfg_width, cfg_height, cfg_bayer_phase, cfg_hdr, cfg_tone_preset, cfg_wb_gains} =
                {sample.width, sample.height, sample.phase, sample.hdr, sample.page, sample.gains};
        end else begin
            cfg_width = index % 2 ? 8 : 16;
            cfg_height = index % 2 ? 4 : 3;
            cfg_bayer_phase = index % 2 ? 0 : 2;
            cfg_hdr = !sample.hdr;
            cfg_tone_preset = ~sample.page;
            cfg_wb_gains = ~sample.gains;
        end
        s_valid = 1;
        do begin
            @(posedge clk);
            took = s_ready;
            @(negedge clk);
            if (!took && allow_cancel && m_valid)
                return; // Keep the pending offer intact until reset.
        end while (!took);
        s_valid = 0;
    endtask

    function automatic int frame_end_index(input int start_index);
        sample_t sample;
        for (int index = start_index; index < SAMPLE_COUNT; index++) begin
            sample = samples[index];
            if (sample.frame_end)
                return index + 1;
        end
        return -1;
    endfunction

    task automatic drain;
        while (received < accepted || o_job_idle !== 1'b1)
            @(negedge clk);
        repeat (4) @(negedge clk);
    endtask

    task automatic shared_frame(input int first, input int limit);
        int before_tail;
        sample_t sample;
        if (o_job_idle !== 1'b1)
            $fatal(1, "DATAPATH_FAIL ISP missing initial idle");
        before_tail = tail_stalls;
        job_goal = received + limit - first;
        send_sample(first);
        watch_idle = 1;
        for (int index = first + 1; index < limit; index++)
            send_sample(index);
        drain();
        watch_idle = 0;
        if (received != job_goal || tail_stalls == before_tail)
            $fatal(1, "DATAPATH_FAIL ISP final RGB/idle/stall missing expected=%0d got=%0d", job_goal, received);
        sample = samples[first];
        $display("ISP_FRAME_PASS width=%0d height=%0d hdr=%0d page=%0d groups=%0d tail_hold=%0d",
                 sample.width, sample.height, sample.hdr, sample.page, limit - first, tail_stalls - before_tail);
    endtask

    task automatic reset_held_frame;
        force_hold = 1;
        for (int index = 0; index < frame_end_index(0) && !m_valid; index++)
            send_sample(index, 1);
        while (!m_valid)
            @(negedge clk);
        repeat (4) @(negedge clk);
        #1 rst_n = 0;
        s_valid = 0;
        repeat (8) @(negedge clk);
        rst_n = 1;
        force_hold = 0;
        repeat (12) @(negedge clk);
        if (received != 0 || accepted != 0 || o_job_idle !== 1'b1)
            $fatal(1, "DATAPATH_FAIL stale RGB or ownership after reset");
    endtask

    initial begin
        int initial_stalls, initial_frames, initial_saturation, initial_overlaps, next_frame;
        if (ISP)
            $readmemh("isp.mem", samples);
        else
            $readmemh("color.mem", samples);
        repeat (8) @(negedge clk);
        rst_n = 1;
        repeat (8) @(negedge clk);
        if (ISP) begin
            for (int first = 0; first < SAMPLE_COUNT; first = next_frame) begin
                next_frame = frame_end_index(first);
                if (next_frame <= first)
                    $fatal(1, "DATAPATH_FAIL fixture missing frame end at input %0d", first);
                shared_frame(first, next_frame);
            end
        end else begin
            for (int index = 0; index < SAMPLE_COUNT; index++)
                send_sample(index);
            drain();
            if (overlaps == 0)
                $fatal(1, "DATAPATH_FAIL fixture did not present adjacent frame configurations in flight");
        end
        if (accepted != SAMPLE_COUNT || received != SAMPLE_COUNT || stalled == 0)
            $fatal(1, "DATAPATH_FAIL RGB missing data or backpressure fixture coverage");

        initial_stalls = stalled;
        initial_frames = frames;
        initial_saturation = saturation;
        initial_overlaps = overlaps;
        reset_held_frame();
        next_frame = frame_end_index(0);
        if (ISP) begin
            shared_frame(next_frame, frame_end_index(next_frame));
            $display("ISP_PASS groups=%0d frames=%0d saturated=%0d stalls=%0d recovery_groups=%0d",
                     SAMPLE_COUNT, initial_frames, initial_saturation, initial_stalls, received);
        end else begin
            for (int index = next_frame; index < frame_end_index(next_frame); index++)
                send_sample(index);
            drain();
            $display("COLOR_PASS groups=%0d frames=%0d saturated=%0d stalls=%0d overlaps=%0d recovery_groups=%0d",
                     SAMPLE_COUNT, initial_frames, initial_saturation, initial_stalls, initial_overlaps, received);
        end
        $finish;
    end

    initial begin
        #1600000;
        $fatal(1, "DATAPATH_FAIL ISP=%0d simulation watchdog at in=%0d out=%0d", ISP, accepted, received);
    end
endmodule
