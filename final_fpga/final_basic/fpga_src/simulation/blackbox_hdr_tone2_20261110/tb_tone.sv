`timescale 1ns/1ps

module tb_tone #(
    parameter integer HDR_STRIDE = 2,
    parameter integer HDR_FIRST_LATENCY = 12
);
    localparam integer QUEUE_CAPACITY = 8192;
    localparam longint unsigned WHITE_LEVEL = 16368;
    localparam longint unsigned SHOULDER = 1024;
    localparam longint unsigned UNITY_GAIN = 65536;
    localparam longint unsigned WHITE_CODE = 1023;
    localparam bit [31:0] DATA_SEED = 32'h243f6a88;
    localparam bit [31:0] STALL_SEED = 32'hc0017a55;

    bit clk = 0;
    always #4 clk = !clk;

    bit rst_n = 0;
    bit clear = 0;
    bit [167:0] s_data = '0;
    bit s_hdr = 0, s_valid = 0, s_sof = 0, s_eol = 0, s_clipped = 0;
    wire s_ready;
    wire [119:0] m_data;
    wire m_valid, m_sof, m_eol, m_clipped;
    bit manual_ready = 1, random_mode = 0, random_ready = 1;
    wire m_ready = random_mode ? random_ready : manual_ready;

    hdr_tone96_shared4 dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .s_data(s_data),
        .s_hdr(s_hdr), .s_valid(s_valid), .s_sof(s_sof), .s_eol(s_eol),
        .s_clipped(s_clipped), .s_ready(s_ready), .m_data(m_data),
        .m_valid(m_valid), .m_ready(m_ready), .m_sof(m_sof), .m_eol(m_eol),
        .m_clipped(m_clipped)
    );

    wire [171:0] input_offer = {s_data, s_hdr, s_sof, s_eol, s_clipped};
    wire [122:0] output_offer = {m_data, m_sof, m_eol, m_clipped};
    logic [171:0] prior_input;
    logic [122:0] prior_output;
    bit input_stalled = 0, output_stalled = 0;
    logic [122:0] expected [0:QUEUE_CAPACITY-1];
    bit expected_hdr [0:QUEUE_CAPACITY-1];
    integer accept_cycle [0:QUEUE_CAPACITY-1];
    integer retire_cycle [0:QUEUE_CAPACITY-1];
    integer cycle = 0, head = 0, tail = 0, pending_hdr = 0;
    integer retired = 0, discarded = 0, trace_fd;
    integer input_stalls = 0, output_stalls = 0, eol_stalls = 0;
    integer accepted_sof = 0, accepted_eol = 0, accepted_clipped = 0;
    bit [31:0] stall_state = STALL_SEED;
    integer stall_remaining = 0;
    string scenario, stage = "startup";

    function automatic longint unsigned round_half_up(
        input longint unsigned numerator, denominator
    );
        return (2 * numerator + denominator) / (2 * denominator);
    endfunction

    function automatic longint unsigned gain_at(input longint unsigned knot);
        return round_half_up(UNITY_GAIN * WHITE_CODE * (WHITE_LEVEL + SHOULDER),
                             WHITE_LEVEL * (knot + SHOULDER));
    endfunction

    function automatic longint unsigned tone_at(input longint unsigned knot);
        longint unsigned code;
        code = round_half_up(knot * WHITE_CODE * (WHITE_LEVEL + SHOULDER),
                             WHITE_LEVEL * (knot + SHOULDER));
        return code < WHITE_CODE ? code : WHITE_CODE;
    endfunction

    function automatic logic [9:0] hdr_component(
        input longint unsigned component, peak, gain, mapped_peak
    );
        longint unsigned scaled;
        if (component == peak)
            return mapped_peak[9:0];
        scaled = round_half_up(component * gain, UNITY_GAIN);
        return scaled < mapped_peak ? scaled[9:0] : mapped_peak[9:0];
    endfunction

    function automatic logic [9:0] sdr_component(input logic [13:0] component);
        return component > 14'd1023 ? 10'd1023 : component[9:0];
    endfunction

    function automatic logic [29:0] map_pixel(input logic [41:0] pixel, input bit hdr);
        longint unsigned r, g, b, peak, stride, lower, upper, offset, gain, mapped_peak;
        if (!hdr)
            return {sdr_component(pixel[41:28]), sdr_component(pixel[27:14]),
                    sdr_component(pixel[13:0])};

        r = pixel[41:28];
        g = pixel[27:14];
        b = pixel[13:0];
        peak = r > g ? r : g;
        if (b > peak)
            peak = b;
        if (peak < 1024)
            stride = 32;
        else if (peak < 2048)
            stride = 64;
        else if (peak < 4096)
            stride = 128;
        else if (peak < 8192)
            stride = 256;
        else
            stride = 512;

        lower = (peak / stride) * stride;
        upper = lower + stride;
        offset = peak - lower;
        gain = gain_at(lower) - round_half_up((gain_at(lower) - gain_at(upper)) * offset, stride);
        mapped_peak = tone_at(lower) + round_half_up((tone_at(upper) - tone_at(lower)) * offset, stride);
        return {hdr_component(r, peak, gain, mapped_peak), hdr_component(g, peak, gain, mapped_peak),
                hdr_component(b, peak, gain, mapped_peak)};
    endfunction

    function automatic logic [119:0] map_group(input logic [167:0] pixels, input bit hdr);
        logic [119:0] mapped;
        for (integer lane = 0; lane < 4; lane++)
            mapped[30*lane +: 30] = map_pixel(pixels[42*lane +: 42], hdr);
        return mapped;
    endfunction

    function automatic bit [31:0] advance_random(input bit [31:0] previous);
        bit [31:0] next;
        next = previous ^ (previous << 13);
        next = next ^ (next >> 17);
        return next ^ (next << 5);
    endfunction

    function automatic bit [41:0] rgb(input integer r, g, b);
        return {r[13:0], g[13:0], b[13:0]};
    endfunction

    function automatic bit [41:0] hdr_pixel(
        input integer peak, shape, input bit [31:0] draw_a, draw_b
    );
        integer a, b;
        a = 0;
        b = 0;
        if (peak > 0) begin
            a = draw_a[0] ? peak - 1 : (draw_a % peak);
            b = draw_b[0] ? 0 : (draw_b % peak);
        end
        case (shape)
            0: return rgb(peak, a, b);
            1: return rgb(a, peak, b);
            2: return rgb(a, b, peak);
            3: return rgb(peak, peak, b);
            4: return rgb(peak, a, peak);
            5: return rgb(a, peak, peak);
            default: return rgb(peak, peak, peak);
        endcase
    endfunction

    function automatic bit [167:0] hdr_group(input integer tag);
        bit [167:0] pixels;
        integer peak;
        for (integer lane = 0; lane < 4; lane++) begin
            peak = (4817 * (tag + 1) + 1927 * lane) % 16384;
            pixels[42*lane +: 42] = hdr_pixel(peak, (tag + lane) % 7,
                                              23 * tag + lane, 31 * tag + lane);
        end
        return pixels;
    endfunction

    function automatic bit [167:0] sdr_group(input integer tag);
        bit [167:0] pixels;
        if (tag == 0) begin
            pixels[0 +: 42] = rgb(0, 1, 1022);
            pixels[42 +: 42] = rgb(1023, 1024, 16383);
            pixels[84 +: 42] = rgb(1025, 7, 1023);
            pixels[126 +: 42] = rgb(16, 2048, 16382);
        end else begin
            for (integer lane = 0; lane < 4; lane++)
                pixels[42*lane +: 42] = rgb((29 * tag + 211 * lane) % 1100,
                                            (13 * tag + 257 * lane + 999) % 2048,
                                            (307 * tag + 199 * lane + 1) % 16384);
        end
        return pixels;
    endfunction

    task automatic fail(input string kind, reason);
        $fatal(1, "TONE_FAIL case=%s stage=%s kind=%s cycle=%0d accepts=%0d retires=%0d drops=%0d %s",
               scenario, stage, kind, cycle, tail, retired, discarded, reason);
    endtask

    always @(negedge clk) begin
        if (!rst_n || clear || !random_mode) begin
            random_ready = 1;
            stall_state = STALL_SEED;
            stall_remaining = 0;
        end else if (stall_remaining > 0) begin
            random_ready = 0;
            stall_remaining = stall_remaining - 1;
        end else if (!random_ready) begin
            random_ready = 1;
        end else begin
            stall_state = advance_random(stall_state);
            if (stall_state[2:0] == 0) begin
                random_ready = 0;
                stall_remaining = stall_state[6:4];
            end
        end
    end

    // Compare every valid offer against the accepted FIFO, including held outputs.
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!rst_n || clear) begin
            if (s_ready !== 1'b0 || m_valid !== 1'b0)
                fail("dut", "READY/VALID asserted across reset or clear");
            discarded = discarded + tail - head;
            head = tail;
            pending_hdr = 0;
            input_stalled = 0;
            output_stalled = 0;
        end else begin
            if ($isunknown({s_ready, m_valid}))
                fail("dut", "READY or VALID contains an unknown value");
            if (input_stalled && (s_valid !== 1'b1 || input_offer !== prior_input))
                fail("fixture", "input changed before acceptance");
            if (output_stalled && (m_valid !== 1'b1 || output_offer !== prior_output))
                fail("dut", "output changed before retirement");

            input_stalled = s_valid && !s_ready;
            output_stalled = m_valid && !m_ready;
            prior_input = input_offer;
            prior_output = output_offer;
            if (input_stalled)
                input_stalls = input_stalls + 1;
            if (output_stalled) begin
                output_stalls = output_stalls + 1;
                if (m_eol)
                    eol_stalls = eol_stalls + 1;
            end

            if (m_valid) begin
                if (head == tail)
                    fail("dut", "output offered without an accepted group");
                if (output_offer !== expected[head])
                    fail("dut", $sformatf("group=%0d expected=%031h got=%031h",
                                          head, expected[head], output_offer));
                if (m_ready) begin
                    $fdisplay(trace_fd, "%030h %0b %0b %0b", m_data, m_sof, m_eol, m_clipped);
                    retire_cycle[head] = cycle;
                    if (expected_hdr[head])
                        pending_hdr = pending_hdr - 1;
                    head = head + 1;
                    retired = retired + 1;
                end
            end

            if (s_valid && s_ready) begin
                if (tail == QUEUE_CAPACITY)
                    fail("fixture", "scoreboard capacity exhausted");
                if (!s_hdr && pending_hdr != 0)
                    fail("dut", "SDR accepted before earlier HDR retired");
                expected[tail] = {map_group(s_data, s_hdr), s_sof, s_eol, s_clipped};
                expected_hdr[tail] = s_hdr;
                accept_cycle[tail] = cycle;
                tail = tail + 1;
                if (s_hdr)
                    pending_hdr = pending_hdr + 1;
                accepted_sof = accepted_sof + int'(s_sof);
                accepted_eol = accepted_eol + int'(s_eol);
                accepted_clipped = accepted_clipped + int'(s_clipped);
            end
        end
    end

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic offer(input bit [167:0] pixels, input bit hdr, sof, eol, clipped);
        if (s_valid)
            fail("fixture", "new offer while a prior input is pending");
        s_data = pixels;
        s_hdr = hdr;
        s_sof = sof;
        s_eol = eol;
        s_clipped = clipped;
        s_valid = 1;
    endtask

    task automatic sample_offer;
        bit accepted_now;
        @(posedge clk);
        accepted_now = s_valid && (s_ready === 1'b1);
        #1;
        if (accepted_now)
            s_valid = 0;
    endtask

    task automatic finish_offer;
        while (s_valid)
            sample_offer();
    endtask

    task automatic send_group(input bit [167:0] pixels, input bit hdr, sof, eol, clipped);
        offer(pixels, hdr, sof, eol, clipped);
        finish_offer();
    endtask

    task automatic wait_retired(input integer target);
        while (retired < target)
            tick();
        if (retired != target)
            fail("fixture", "test skipped its intended retirement boundary");
    endtask

    task automatic wait_held_eol;
        do begin
            tick();
        end while (m_valid !== 1'b1);
        if (m_ready !== 1'b0)
            fail("fixture", "downstream READY did not settle low");
        if (m_eol !== 1'b1)
            fail("dut", "held offer was not end-of-line");
    endtask

    task automatic check_gate;
        #1;
        if (s_ready !== 1'b0 || m_valid !== 1'b0)
            fail("dut", "READY/VALID did not close before the next clock edge");
    endtask

    task automatic run_cadence(input bit hdr, input integer stride, first_latency);
        localparam integer GROUPS = 24;
        integer first, limit, retirement_target, spacing, min_spacing, max_spacing;
        integer observed_first_latency;
        bit [167:0] pixels;
        stage = hdr ? "cadence_hdr" : "cadence_sdr";
        first = tail;
        retirement_target = retired + GROUPS;
        for (integer group = 0; group < GROUPS; group++) begin
            pixels = hdr ? hdr_group(group) : sdr_group(group);
            send_group(pixels, hdr, group % 12 == 0, group % 6 == 5, group % 3 == 1);
        end
        wait_retired(retirement_target);
        limit = first + GROUPS;
        min_spacing = GROUPS;
        max_spacing = 0;
        for (integer group = first + 1; group < limit; group++) begin
            spacing = accept_cycle[group] - accept_cycle[group-1];
            if (spacing != stride)
                fail("dut", $sformatf("group=%0d accept_interval=%0d expected=%0d",
                                      group - first, spacing, stride));
            spacing = retire_cycle[group] - retire_cycle[group-1];
            if (spacing < min_spacing)
                min_spacing = spacing;
            if (spacing > max_spacing)
                max_spacing = spacing;
        end
        observed_first_latency = retire_cycle[first] - accept_cycle[first];
        if (observed_first_latency != first_latency)
            fail("dut", $sformatf("first_latency=%0d expected=%0d", observed_first_latency, first_latency));

        $display("TONE_CADENCE hdr=%0b groups=%0d accept_interval=%0d retire_interval_min=%0d retire_interval_max=%0d first_latency=%0d tail_drain=%0d accept_edges=%0d..%0d retire_edges=%0d..%0d",
                 hdr, GROUPS, stride, min_spacing, max_spacing, observed_first_latency,
                 retire_cycle[limit-1] - accept_cycle[limit-1], accept_cycle[first], accept_cycle[limit-1],
                 retire_cycle[first], retire_cycle[limit-1]);
        repeat (4) tick();
    endtask

    task automatic run_numeric;
        bit [31:0] data_state, draw_a;
        bit [167:0] pixels;
        bit [16383:0] seen_peak;
        bit [6:0] seen_shape [0:3];
        integer peak, shape;
        stage = "numeric_sweep";
        data_state = DATA_SEED;
        seen_peak = '0;
        for (integer lane = 0; lane < 4; lane++)
            seen_shape[lane] = '0;
        random_mode = 1;
        for (integer group = 0; group < 4096; group++) begin
            for (integer lane = 0; lane < 4; lane++) begin
                peak = 4 * group + (lane + group / 8) % 4;
                shape = (group + 2 * lane) % 7;
                if (seen_peak[peak])
                    fail("fixture", "repeated maximum in numerical sweep");
                seen_peak[peak] = 1;
                if (peak > 0)
                    seen_shape[lane][shape] = 1;
                draw_a = advance_random(data_state);
                data_state = advance_random(draw_a);
                pixels[42*lane +: 42] = hdr_pixel(peak, shape, draw_a, data_state);
            end
            send_group(pixels, 1, group % 256 == 0, group % 64 == 63, group % 5 == 1);
            if (group % 43 == 42)
                repeat (1 + group % 3) tick();
        end
        wait_retired(4096);
        random_mode = 0;
        if (seen_peak !== '1 || input_stalls == 0 || output_stalls == 0 || eol_stalls == 0)
            fail("fixture", "incomplete numeric or bounded-stall coverage");
        for (integer lane = 0; lane < 4; lane++)
            if (seen_shape[lane] !== 7'b1111111)
                fail("fixture", "incomplete maximum-channel and tie coverage");
        $display("TONE_NUMERIC maxima=16384 pixels=16384 groups=4096 lanes=4 shapes_per_lane=7 data_seed=%08h stall_seed=%08h",
                 DATA_SEED, STALL_SEED);
    endtask

    task automatic run_flow;
        integer start_sdr, start_hdr;
        stage = "hdr_to_sdr";
        send_group(hdr_group(51), 1, 1, 0, 0);
        send_group(hdr_group(52), 1, 0, 0, 1);
        send_group(hdr_group(53), 1, 0, 1, 1);
        wait_retired(2);
        manual_ready = 0;
        wait_held_eol();
        start_sdr = tail;
        offer(sdr_group(54), 0, 1, 0, 0);
        repeat (5) sample_offer();
        if (!s_valid || retired != 2)
            fail("dut", "HDR tail did not hold the waiting SDR frame");
        manual_ready = 1;
        finish_offer();
        $display("TONE_TRANSITION hdr_to_sdr old_retire=%0d new_accept=%0d wait_cycles=5",
                 retire_cycle[start_sdr-1], accept_cycle[start_sdr]);

        stage = "sdr_to_hdr";
        send_group(sdr_group(55), 0, 0, 1, 0);
        wait_retired(4);
        manual_ready = 0;
        wait_held_eol();
        start_hdr = tail;
        offer(hdr_group(56), 1, 1, 1, 1);
        repeat (5) sample_offer();
        if (retired != 4)
            fail("dut", "SDR tail retired with downstream stopped");
        manual_ready = 1;
        finish_offer();
        wait_retired(6);
        $display("TONE_TRANSITION sdr_to_hdr old_retire=%0d new_accept=%0d new_retire=%0d wait_cycles=5",
                 retire_cycle[start_hdr-1], accept_cycle[start_hdr], retire_cycle[start_hdr]);

        stage = "clear_in_flight";
        send_group(hdr_group(61), 1, 1, 0, 1);
        if (m_valid !== 1'b0)
            fail("fixture", "clear_in_flight reached an already visible output");
        clear = 1;
        check_gate();
        tick();
        clear = 0;
        if (discarded != 1)
            fail("fixture", "clear_in_flight did not exercise one pending group");
        send_group(hdr_group(62), 1, 1, 1, 0);
        wait_retired(7);
        repeat (4) tick();

        stage = "clear_held_eol";
        manual_ready = 0;
        send_group(hdr_group(63), 1, 1, 1, 1);
        wait_held_eol();
        repeat (3) tick();
        clear = 1;
        check_gate();
        tick();
        clear = 0;
        manual_ready = 1;
        if (discarded != 2)
            fail("fixture", "clear_held_eol did not exercise a second pending group");
        send_group(sdr_group(64), 0, 1, 1, 0);
        wait_retired(8);
        repeat (4) tick();

        stage = "reset_held_eol";
        manual_ready = 0;
        send_group(sdr_group(65), 0, 1, 1, 1);
        wait_held_eol();
        repeat (3) tick();
        rst_n = 0;
        check_gate();
        repeat (3) tick();
        rst_n = 1;
        manual_ready = 1;
        if (discarded != 3)
            fail("fixture", "reset_held_eol did not exercise a third pending group");
        send_group(hdr_group(66), 1, 1, 1, 0);
        wait_retired(9);
        $display("TONE_FLOW held_hdr_eol=1 held_sdr_eol=1 clear_in_flight=1 clear_held_eol=1 reset_held_eol=1 recovered=3");
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", scenario))
            fail("fixture", "missing CASE plusarg");
        trace_fd = $fopen({scenario, "_public.txt"}, "w");
        if (trace_fd == 0)
            fail("fixture", "cannot open the public retirement trace");
        check_gate();
        repeat (8) tick();
        rst_n = 1;
        case (scenario)
            "cadence": begin
                run_cadence(1, HDR_STRIDE, HDR_FIRST_LATENCY);
                run_cadence(0, 1, 1);
            end
            "numeric": run_numeric();
            "flow": run_flow();
            default: fail("fixture", "unknown CASE plusarg");
        endcase
        stage = "final_drain";
        repeat (24) tick();
        if (head != tail || tail != retired + discarded || pending_hdr != 0)
            fail("dut", "accepted/retired/discarded ledger did not close");
        $fclose(trace_fd);
        $display("TONE_PASS case=%s accepts=%0d retires=%0d drops=%0d input_stalls=%0d output_stalls=%0d eol_stalls=%0d sof=%0d eol=%0d clipped=%0d cycles=%0d",
                 scenario, tail, retired, discarded, input_stalls, output_stalls, eol_stalls,
                 accepted_sof, accepted_eol, accepted_clipped, cycle);
        $finish;
    end

    initial begin
        #400000;
        fail("liveness", "50000-cycle watchdog expired");
    end
endmodule
