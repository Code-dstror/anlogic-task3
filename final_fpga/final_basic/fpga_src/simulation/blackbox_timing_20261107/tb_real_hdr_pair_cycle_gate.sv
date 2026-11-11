`timescale 1ps/1ps

module tb_real_hdr_pair_cycle_gate;
    localparam integer TIMEOUT_CYCLES = 48;
    localparam [3:0] RAW = 0, FE = 6, FS = 7, BAD = 8;
    localparam [39:0] LONG_PIXELS = {10'd621, 10'd509, 10'd302, 10'd103};
    localparam [39:0] SHORT_PIXELS = {10'd29, 10'd11, 10'd7, 10'd1};

    reg clk = 0, rst_n = 1, fault = 0, stable = 1, admit = 1;
    reg [31:0] session = 32'h1234_5678, epoch = 7, timeout_phase = 0;
    reg [63:0] clock_count = 0;
    reg [1:0] capture_idle = 2'b11, token_valid = 0, source_ready = 2'b11;
    reg [146:0] token_data [0:1];
    wire [1:0] token_ready, raw_valid, raw_sof, raw_eol, raw_abort, source_valid;
    wire [39:0] raw_data [0:1];
    wire [31:0] capture_seq [0:1], capture_session, capture_epoch;
    wire [104:0] source_bundle [0:1];
    wire pair_event, pair_ok;
    wire [31:0] good_pairs, bad_pairs, not_admitted_pairs;

    string scenario;
    string stage = "initial";
    integer profile;
    // Expected outputs come from the stimulus ledger, with separate ordered lanes.
    typedef logic [137:0] raw_expectation;
    typedef logic [96:0] source_expectation;
    typedef logic [32:0] pair_expectation;
    raw_expectation raw_long[$], raw_short[$];
    source_expectation source_long[$], source_short[$];
    pair_expectation pairs[$];
    reg [1:0] held = 0, may_abort = 0;
    reg [104:0] held_bundle [0:1];
    reg [31:0] abort_seq [0:1];
    reg [31:0] latest_fe_group [0:1], preceding_fe_group [0:1], latest_fe_seq [0:1];
    reg allow_negative_drain = 0;
    time last_long_fs_time;

    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES), .EXTERNAL_PHASE_ENABLE(1)) dut (
        .i_clk(clk), .i_reset_n(rst_n), .i_fault(fault), .i_stable(stable), .i_admit_enable(admit),
        .i_session(session), .i_epoch(epoch), .i_time(clock_count), .i_time_valid(1'b1),
        .i_capture0_idle(capture_idle[0]), .i_capture1_idle(capture_idle[1]),
        .s0_data(token_data[0]), .s1_data(token_data[1]), .s0_valid(token_valid[0]),
        .s1_valid(token_valid[1]), .s0_ready(token_ready[0]), .s1_ready(token_ready[1]),
        .m0_data(raw_data[0]), .m1_data(raw_data[1]), .m0_valid(raw_valid[0]), .m1_valid(raw_valid[1]),
        .m0_sof(raw_sof[0]), .m1_sof(raw_sof[1]), .m0_eol(raw_eol[0]), .m1_eol(raw_eol[1]),
        .m0_abort(raw_abort[0]), .m1_abort(raw_abort[1]), .o_sequence0(capture_seq[0]),
        .o_sequence1(capture_seq[1]), .o_session(capture_session), .o_epoch(capture_epoch),
        .o_metadata0(), .o_metadata1(), .o_diag_pair(), .o_diag_counts(), .o_quiet(),
        .o_source0_valid(source_valid[0]), .o_source1_valid(source_valid[1]),
        .i_source0_ready(source_ready[0]), .i_source1_ready(source_ready[1]),
        .o_source_session(source_bundle[0][104:73]), .o_source_epoch(source_bundle[0][72:41]),
        .o_source0_sequence(source_bundle[0][40:9]), .o_source_ok(source_bundle[0][8]),
        .o_source_error(source_bundle[0][7:0]),
        .o_source1_session(source_bundle[1][104:73]), .o_source1_epoch(source_bundle[1][72:41]),
        .o_source1_sequence(source_bundle[1][40:9]), .o_source1_ok(source_bundle[1][8]),
        .o_source1_error(source_bundle[1][7:0]), .o_pair_event(pair_event), .o_pair_ok(pair_ok),
        .o_good_pairs(good_pairs), .o_bad_pairs(bad_pairs), .o_not_admitted_pairs(not_admitted_pairs),
        .i_timeout_phase(timeout_phase)
    );

    always #4000 clk = ~clk;
    always @(posedge clk) begin
        clock_count <= clock_count + 1;
        if (timeout_phase == TIMEOUT_CYCLES - 1) timeout_phase <= 0;
        else timeout_phase <= timeout_phase + 1;
    end

    task automatic fail(input string reason);
        $display("BLACKBOX_FAIL real_hdr_pair_cycle_gate case=%s profile=%0d phase=%s t=%0t %s",
                 scenario, profile, stage, $time, reason);
        $fatal(1, "External contract check failed");
    endtask

    task automatic step(input string description);
        stage = description;
        $display("BLACKBOX_STEP real_hdr_pair_cycle_gate case=%s profile=%0d %s",
                 scenario, profile, description);
    endtask

    function automatic [146:0] token(input [3:0] code, input [31:0] group_id,
                                      input [31:0] seq_id, input [39:0] pixels = 0);
        reg [146:0] word;
        word = '0;
        word[112:111] = 2'b11;
        word[110:79] = seq_id;
        word[78:47] = group_id;
        word[46:43] = code;
        word[42] = (code == BAD);
        word[41:40] = (code == RAW) ? 2'b11 : 2'b00;
        word[39:0] = pixels;
        return word;
    endfunction

    task automatic expect_raw(input bit lane, input [31:0] seq_id, input [39:0] pixels);
        raw_expectation wanted;
        wanted = {session, epoch, seq_id, pixels, 2'b11};
        if (lane == 0) raw_long.push_back(wanted);
        else raw_short.push_back(wanted);
    endtask

    task automatic expect_source(input bit lane, input [31:0] seq_id, input bit ok);
        source_expectation wanted;
        wanted = {session, epoch, seq_id, ok};
        if (lane == 0) source_long.push_back(wanted);
        else source_short.push_back(wanted);
        if (!ok) begin
            may_abort[lane] = 1;
            abort_seq[lane] = seq_id;
        end
    endtask

    task automatic observe_lane(input bit lane);
        raw_expectation wanted_raw, observed_raw;
        source_expectation wanted_source, removed;
        reg [7:0] source_error;
        if (held[lane] && (source_valid[lane] !== 1'b1 || source_bundle[lane] !== held_bundle[lane]))
            fail($sformatf("lane %0d changed stalled SOURCE %h to %h valid=%b", lane,
                           held_bundle[lane], source_bundle[lane], source_valid[lane]));
        held[lane] = source_valid[lane] && !source_ready[lane];
        if (held[lane]) held_bundle[lane] = source_bundle[lane];
        if ($isunknown({source_valid[lane], raw_abort[lane], raw_valid[lane]}))
            fail($sformatf("lane %0d has an unknown output qualifier", lane));
        if (source_valid[lane]) begin
            if ((lane == 0 ? source_long.size() : source_short.size()) == 0)
                fail($sformatf("unexpected lane %0d SOURCE %h", lane, source_bundle[lane]));
            wanted_source = lane == 0 ? source_long[0] : source_short[0];
            source_error = source_bundle[lane][7:0];
            if (source_bundle[lane][104:8] !== wanted_source || $isunknown(source_error) ||
                (wanted_source[0] ? source_error != 0 : source_error == 0))
                fail($sformatf("lane %0d SOURCE expected %h got %h", lane, wanted_source,
                               source_bundle[lane]));
            if (wanted_source[0] && latest_fe_seq[lane] !== wanted_source[32:1])
                fail($sformatf("positive lane %0d SOURCE preceded its true FE", lane));
            if (source_ready[lane]) begin
                if (lane == 0) removed = source_long.pop_front();
                else removed = source_short.pop_front();
            end
        end
        if (raw_abort[lane] && (!may_abort[lane] || capture_seq[lane] !== abort_seq[lane]))
            fail($sformatf("unexpected lane %0d abort for sequence %h", lane, capture_seq[lane]));
        if (raw_valid[lane] && !raw_abort[lane]) begin
            if ((lane == 0 ? raw_long.size() : raw_short.size()) == 0)
                fail($sformatf("unexpected lane %0d positive RAW for sequence %h", lane, capture_seq[lane]));
            if (lane == 0) wanted_raw = raw_long.pop_front();
            else wanted_raw = raw_short.pop_front();
            observed_raw = {capture_session, capture_epoch, capture_seq[lane], raw_data[lane],
                            raw_sof[lane], raw_eol[lane]};
            if (observed_raw !== wanted_raw)
                fail($sformatf("lane %0d RAW expected %h got %h", lane, wanted_raw, observed_raw));
        end
    endtask

    always @(posedge clk) begin : monitor_outputs
        pair_expectation wanted_pair;
        reg [31:0] group_id;
        if (rst_n && clock_count > 0) begin
            for (integer lane = 0; lane < 2; lane++) begin
                if (token_valid[lane] && token_ready[lane]) begin
                    if (lane == 0 && token_data[0][46:43] == FS) last_long_fs_time = $time;
                    if (token_data[lane][46:43] == FE) begin
                        preceding_fe_group[lane] = latest_fe_group[lane];
                        latest_fe_group[lane] = token_data[lane][78:47];
                        latest_fe_seq[lane] = token_data[lane][110:79];
                    end
                end
                observe_lane(lane);
            end
            if ($isunknown(pair_event)) fail("unknown pair-event qualifier");
            if (pair_event) begin
                if (pairs.size() != 0) begin
                    wanted_pair = pairs.pop_front();
                    group_id = wanted_pair[31:0];
                    if (pair_ok !== wanted_pair[32])
                        fail($sformatf("pair event OK expected=%b got=%b", wanted_pair[32], pair_ok));
                    if (pair_ok && ((latest_fe_group[0] !== group_id && preceding_fe_group[0] !== group_id) ||
                                    (latest_fe_group[1] !== group_id && preceding_fe_group[1] !== group_id)))
                        fail("positive pair event preceded a matching physical FE");
                end else if (!allow_negative_drain || pair_ok !== 1'b0) begin
                    fail($sformatf("unexpected pair event OK=%b", pair_ok));
                end
            end
        end
    end

    task automatic send(input [146:0] long_token, input [146:0] short_token,
                        input bit same_edge = 0);
        reg [1:0] transferred;
        @(negedge clk);
        token_data[0] = long_token;
        token_data[1] = short_token;
        token_valid = {short_token != 0, long_token != 0};
        for (integer cycle = 0; cycle < 20; cycle++) begin
            @(posedge clk);
            transferred = token_valid & token_ready;
            if ($isunknown(transferred)) fail("unknown input handshake");
            for (integer lane = 0; lane < 2; lane++) begin
                if (token_valid[lane] && token_data[lane][46:43] == RAW && !transferred[lane])
                    fail($sformatf("lane %0d stalled a RAW token", lane));
            end
            if (same_edge && transferred inside {2'b01, 2'b10})
                fail("simultaneous FS did not transfer on the same edge");
            @(negedge clk);
            token_valid = token_valid & ~transferred;
            if (token_valid == 0) return;
        end
        fail($sformatf("ingress handshake timeout valid=%b ready=%b", token_valid, token_ready));
    endtask

    task automatic wait_expected;
        for (integer cycle = 0; cycle < 24; cycle++) begin
            @(negedge clk);
            if (raw_long.size() == 0 && raw_short.size() == 0 && source_long.size() == 0 &&
                source_short.size() == 0 && pairs.size() == 0) begin
                repeat (2) @(negedge clk);
                may_abort = 0;
                return;
            end
        end
        fail($sformatf("expected output timeout RAW=%0d/%0d SOURCE=%0d/%0d pairs=%0d",
                       raw_long.size(), raw_short.size(), source_long.size(), source_short.size(), pairs.size()));
    endtask

    task automatic reset_gate;
        @(negedge clk);
        rst_n = 0;
        token_valid = 0;
        source_ready = 2'b11;
        capture_idle = 2'b11;
        fault = 0;
        stable = 1;
        admit = 1;
        raw_long.delete();
        raw_short.delete();
        source_long.delete();
        source_short.delete();
        pairs.delete();
        held = 0;
        may_abort = 0;
        allow_negative_drain = 0;
        for (integer lane = 0; lane < 2; lane++) begin
            latest_fe_seq[lane] = 0;
            latest_fe_group[lane] = 0;
            preceding_fe_group[lane] = 0;
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
    endtask

    task automatic require_counts(input [31:0] good, input [31:0] bad);
        if (good_pairs !== good || bad_pairs !== bad)
            fail($sformatf("expected good/bad=%0d/%0d got %0d/%0d not-admitted=%0d", good, bad,
                           good_pairs, bad_pairs, not_admitted_pairs));
    endtask

    task automatic send_raw_pair(input [31:0] group_id, input [31:0] long_seq,
                                 input [31:0] short_seq, input bit capture);
        if (capture) begin
            expect_raw(0, long_seq, LONG_PIXELS);
            expect_raw(1, short_seq, SHORT_PIXELS);
        end
        send(token(RAW, group_id, long_seq, LONG_PIXELS), token(RAW, group_id, short_seq, SHORT_PIXELS));
    endtask

    task automatic good_group(input [31:0] group_id, input [31:0] long_seq,
                              input [31:0] short_seq, input bit capture = 1);
        send(token(FS, group_id, long_seq), token(FS, group_id, short_seq), 1);
        send_raw_pair(group_id, long_seq, short_seq, capture);
        if (capture) begin
            expect_source(0, long_seq, 1);
            expect_source(1, short_seq, 1);
        end
        pairs.push_back({1'b1, group_id});
        send(token(FE, group_id, long_seq), token(FE, group_id, short_seq));
        wait_expected();
    endtask

    task automatic drain_group(input [31:0] group_id, input [31:0] long_seq,
                               input [31:0] short_seq);
        send(token(FS, group_id, long_seq), token(FS, group_id, short_seq));
        send_raw_pair(group_id, long_seq, short_seq, 0);
        send(token(FE, group_id, long_seq), token(FE, group_id, short_seq));
        repeat (3) @(negedge clk);
    endtask

    task automatic wait_sources(input [1:0] expected);
        for (integer cycle = 0; cycle < 16; cycle++) begin
            @(negedge clk);
            if (source_valid === expected) return;
        end
        fail($sformatf("held SOURCE expected valid=%b got=%b", expected, source_valid));
    endtask

    task automatic requalify_capture;
        stable = 0;
        repeat (4) @(negedge clk);
        stable = 1;
        repeat (2) @(negedge clk);
    endtask

    task automatic basic_case;
        step("staggered FS and independent stalled SOURCE bundles");
        source_ready = 0;
        send(token(FS, 21, 101), 0);
        send(0, token(FS, 21, 307));
        send_raw_pair(21, 101, 307, 1);
        expect_source(0, 101, 1);
        send(token(FE, 21, 101), 0);
        wait_sources(2'b01);
        expect_source(1, 307, 1);
        pairs.push_back({1'b1, 32'd21});
        send(0, token(FE, 21, 307));
        wait_sources(2'b11);
        repeat (5) @(negedge clk);
        source_ready = 2'b10;
        wait_sources(2'b01);
        repeat (5) @(negedge clk);
        source_ready = 2'b11;
        wait_expected();
        require_counts(1, 0);

        step("same-edge LONG/SHORT FS and admitted tail completion during STOP");
        send(token(FS, 22, 102), token(FS, 22, 309), 1);
        admit = 0;
        send_raw_pair(22, 102, 309, 1);
        expect_source(0, 102, 1);
        expect_source(1, 309, 1);
        pairs.push_back({1'b1, 32'd22});
        send(token(FE, 22, 102), token(FE, 22, 309));
        wait_expected();
        require_counts(2, 0);
    endtask

    task automatic overlap_case;
        reg [1:0] transferred;
        bit released_short;
        step("new LONG starts while old SHORT still owns its ingress");
        send(token(FS, 100, 41), token(FS, 100, 91), 1);
        send_raw_pair(100, 41, 91, 1);
        capture_idle[1] = 0;
        expect_source(0, 41, 1);
        send(token(FE, 100, 41), 0);
        wait_expected();
        send(token(FS, 101, 42), 0);
        expect_raw(0, 42, LONG_PIXELS);
        send(token(RAW, 101, 42, LONG_PIXELS), 0);
        expect_source(0, 42, 1);
        send(token(FE, 101, 42), 0);
        wait_expected();

        step("full contexts hold third LONG while permitting older SHORT FE");
        @(negedge clk);
        token_data[0] = token(FS, 102, 43);
        token_valid = 2'b01;
        repeat (6) begin
            @(posedge clk);
            if (token_ready[0] !== 1'b0) fail("third LONG advanced while both contexts were unresolved");
            @(negedge clk);
        end
        expect_source(1, 91, 1);
        pairs.push_back({1'b1, 32'd100});
        token_data[1] = token(FE, 100, 91);
        token_valid = 2'b11;
        released_short = 0;
        for (integer cycle = 0; cycle < 12 && token_valid != 0; cycle++) begin
            @(posedge clk);
            transferred = token_valid & token_ready;
            if (transferred[0] && !transferred[1] && !released_short)
                fail("third LONG advanced before the older SHORT FE");
            if (transferred[1]) released_short = 1;
            @(negedge clk);
            token_valid = token_valid & ~transferred;
        end
        if (token_valid !== 0) fail("older SHORT FE or third LONG remained stalled");
        capture_idle[1] = 1;
        wait_expected();

        send(0, token(FS, 101, 92));
        expect_raw(0, 43, LONG_PIXELS);
        expect_raw(1, 92, SHORT_PIXELS);
        send(token(RAW, 102, 43, LONG_PIXELS), token(RAW, 101, 92, SHORT_PIXELS));
        expect_source(0, 43, 1);
        expect_source(1, 92, 1);
        pairs.push_back({1'b1, 32'd101});
        send(token(FE, 102, 43), token(FE, 101, 92));
        wait_expected();
        send(0, token(FS, 102, 93));
        expect_raw(1, 93, SHORT_PIXELS);
        send(0, token(RAW, 102, 93, SHORT_PIXELS));
        expect_source(1, 93, 1);
        pairs.push_back({1'b1, 32'd102});
        send(0, token(FE, 102, 93));
        wait_expected();
        require_counts(3, 0);
    endtask

    task automatic drain_serial_case;
        reg [31:0] bad_before;
        step("warmup has physical pair events without capture outputs");
        stable = 0;
        good_group(41, 700, 800, 0);
        require_counts(1, 0);
        stable = 1;

        step("STOP drains new group and replay without admitting it");
        admit = 0;
        drain_group(42, 701, 801);
        admit = 1;
        drain_group(42, 701, 801);
        require_counts(1, 0);

        step("same-edge negative wins, failed group replay drains, then serial wrap");
        reset_gate();
        send(token(FS, 32'hffff_fffe, 501), token(FS, 32'hffff_fffe, 601), 1);
        send_raw_pair(32'hffff_fffe, 501, 601, 1);
        expect_source(0, 501, 0);
        expect_source(1, 601, 0);
        pairs.push_back({1'b0, 32'hffff_fffe});
        send(token(FE, 32'hffff_fffe, 501), token(BAD, 32'hffff_fffe, 601));
        wait_expected();
        require_counts(0, 1);
        drain_group(32'hffff_fffe, 501, 601);
        require_counts(0, 1);
        requalify_capture();
        good_group(32'hffff_ffff, 502, 602);
        allow_negative_drain = 1;
        drain_group(0, 503, 603);
        allow_negative_drain = 0;
        bad_before = bad_pairs;
        if (bad_before != 1) requalify_capture();
        good_group(1, 504, 604);
        require_counts(2, bad_before);

        step("backward and forward offsets inside the open serial half-range");
        admit = 0;
        drain_group(2, 505, 605);
        admit = 1;
        bad_before = bad_pairs;
        allow_negative_drain = 1;
        drain_group(32'h8000_0003, 506, 606);
        allow_negative_drain = 0;
        if (bad_pairs != bad_before) requalify_capture();
        bad_before = bad_pairs;
        good_group(32'h8000_0001, 507, 607);
        require_counts(3, bad_before);
    endtask

    task automatic cancel_case;
        step("old SHORT fails after positive LONG; next LONG is untouched");
        send(token(FS, 201, 321), token(FS, 201, 421), 1);
        send_raw_pair(201, 321, 421, 1);
        expect_source(0, 321, 1);
        send(token(FE, 201, 321), 0);
        wait_expected();
        send(token(FS, 202, 322), 0);
        expect_raw(0, 322, LONG_PIXELS);
        send(token(RAW, 202, 322, LONG_PIXELS), 0);
        expect_source(1, 421, 0);
        pairs.push_back({1'b0, 32'd201});
        send(0, token(BAD, 201, 421));
        wait_expected();
        require_counts(0, 1);
        send(0, token(FS, 202, 422));
        expect_raw(1, 422, SHORT_PIXELS);
        send(0, token(RAW, 202, 422, SHORT_PIXELS));
        expect_source(0, 322, 1);
        expect_source(1, 422, 1);
        pairs.push_back({1'b1, 32'd202});
        send(token(FE, 202, 322), token(FE, 202, 422));
        wait_expected();
        require_counts(1, 1);

        step("one fault cancels two contexts and each original SOURCE is retained");
        requalify_capture();
        send(token(FS, 203, 323), token(FS, 203, 423), 1);
        send_raw_pair(203, 323, 423, 1);
        expect_source(0, 323, 1);
        send(token(FE, 203, 323), 0);
        wait_expected();
        send(token(FS, 204, 324), 0);
        expect_raw(0, 324, LONG_PIXELS);
        send(token(RAW, 204, 324, LONG_PIXELS), 0);
        source_ready = 0;
        expect_source(0, 324, 0);
        expect_source(1, 423, 0);
        pairs.push_back({1'b0, 32'd203});
        fault = 1;
        @(negedge clk);
        fault = 0;
        wait_sources(2'b11);
        require_counts(1, 3);
        repeat (5) @(negedge clk);
        source_ready = 2'b01;
        wait_sources(2'b10);
        session = session + 1;
        epoch = epoch + 1;
        requalify_capture();
        send(token(FS, 205, 325), 0);
        expect_raw(0, 325, LONG_PIXELS);
        send(token(RAW, 205, 325, LONG_PIXELS), 0);
        source_ready = 2'b11;
        wait_expected();
        send(0, token(FS, 205, 425));
        expect_raw(1, 425, SHORT_PIXELS);
        send(0, token(RAW, 205, 425, SHORT_PIXELS));
        expect_source(0, 325, 1);
        expect_source(1, 425, 1);
        pairs.push_back({1'b1, 32'd205});
        send(token(FE, 205, 325), token(FE, 205, 425));
        wait_expected();
        require_counts(2, 3);
    endtask

    task automatic timeout_reset_case;
        time accepted_fs;
        step("external phase wraps; unfinished group times out only after a full period");
        source_ready = 0;
        while (timeout_phase != 44) @(negedge clk);
        send(token(FS, 301, 12), 0);
        accepted_fs = last_long_fs_time;
        expect_raw(0, 12, LONG_PIXELS);
        send(token(RAW, 301, 12, LONG_PIXELS), 0);
        expect_source(0, 12, 0);
        pairs.push_back({1'b0, 32'd301});
        while ($time - accepted_fs < (TIMEOUT_CYCLES - 1) * 8000) begin
            if (source_valid !== 0 || pair_event !== 0 || bad_pairs !== 0)
                fail("timeout occurred before one external phase period");
            @(negedge clk);
        end
        wait_sources(2'b01);
        if ($time - accepted_fs > (TIMEOUT_CYCLES + 5) * 8000)
            fail("timeout exceeded one external phase period plus bounded terminal latency");
        repeat (4) @(negedge clk);
        require_counts(0, 1);
        if (pairs.size() != 0) fail("timeout did not report a negative pair event");

        step("reset discards a held terminal and clears serial drain state");
        reset_gate();
        require_counts(0, 0);
        good_group(301, 13, 15);
        require_counts(1, 0);
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        if (!$value$plusargs("profile=%d", profile)) fail("missing profile");
        if (!$value$plusargs("case=%s", scenario)) fail("missing case");
        reset_gate();
        case (scenario)
            "basic": basic_case();
            "overlap": overlap_case();
            "drain_serial": drain_serial_case();
            "cancel": cancel_case();
            "timeout_reset": timeout_reset_case();
            default: fail("unknown case");
        endcase
        $display("BLACKBOX_PASS real_hdr_pair_cycle_gate case=%s profile=%0d", scenario, profile);
        $finish;
    end

    initial begin
        #15000000;
        fail("15 us simulation watchdog");
    end
endmodule
