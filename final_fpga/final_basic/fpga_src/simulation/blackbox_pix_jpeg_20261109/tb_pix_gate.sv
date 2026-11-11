`timescale 1ns/1ps

module tb_pix_gate;
    localparam integer PHASES = 64;
    localparam logic [3:0] RAW = 0, FE = 6, FS = 7, BAD = 8;
    localparam logic [39:0] A = 40'h0123456789, B = 40'hfedcba9876;
    localparam logic [39:0] C = 40'h385bda721c, D = 40'hbf0144eda2;

    logic clk = 0, clock_on = 1, reset_n = 1;
    logic fault = 0, stable = 1, permit = 1, time_valid = 1;
    logic [31:0] session = 32'ha1041003, epoch = 32'h44110202;
    logic [63:0] stamp;
    logic [31:0] phase;
    logic [146:0] s0_data = 0, s1_data = 0;
    logic s0_valid = 0, s1_valid = 0;
    logic source0_ready = 1, source1_ready = 1;
    wire s0_ready, s1_ready;
    wire [39:0] m0_data, m1_data;
    wire m0_valid, m1_valid, m0_sof, m1_sof, m0_eol, m1_eol, m0_abort, m1_abort;
    wire [31:0] seq0, seq1, out_session, out_epoch;
    wire [196:0] meta0, meta1;
    wire source0_valid, source1_valid, source0_ok, source1_ok;
    wire [31:0] source0_session, source1_session, source0_epoch, source1_epoch;
    wire [31:0] source0_seq, source1_seq;
    wire [7:0] source0_error, source1_error;
    wire pair_event, pair_ok, quiet;
    wire [31:0] good_pairs, bad_pairs, skipped_pairs;

    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(PHASES), .EXTERNAL_PHASE_ENABLE(1)) dut (
        .i_clk(clk), .i_reset_n(reset_n), .i_fault(fault), .i_stable(stable),
        .i_admit_enable(permit), .i_session(session), .i_epoch(epoch),
        .i_time(stamp), .i_time_valid(time_valid), .i_timeout_phase(phase),
        .i_capture0_idle(1'b1), .i_capture1_idle(1'b1),
        .s0_data(s0_data), .s0_valid(s0_valid), .s0_ready(s0_ready),
        .s1_data(s1_data), .s1_valid(s1_valid), .s1_ready(s1_ready),
        .m0_data(m0_data), .m0_valid(m0_valid), .m0_sof(m0_sof), .m0_eol(m0_eol),
        .m1_data(m1_data), .m1_valid(m1_valid), .m1_sof(m1_sof), .m1_eol(m1_eol),
        .m0_abort(m0_abort), .m1_abort(m1_abort),
        .o_sequence0(seq0), .o_sequence1(seq1), .o_session(out_session), .o_epoch(out_epoch),
        .o_metadata0(meta0), .o_metadata1(meta1),
        .o_source0_valid(source0_valid), .i_source0_ready(source0_ready),
        .o_source1_valid(source1_valid), .i_source1_ready(source1_ready),
        .o_source_session(source0_session), .o_source_epoch(source0_epoch),
        .o_source0_sequence(source0_seq), .o_source_ok(source0_ok), .o_source_error(source0_error),
        .o_source1_session(source1_session), .o_source1_epoch(source1_epoch),
        .o_source1_sequence(source1_seq), .o_source1_ok(source1_ok), .o_source1_error(source1_error),
        .o_pair_event(pair_event), .o_pair_ok(pair_ok), .o_diag_pair(), .o_diag_counts(),
        .o_good_pairs(good_pairs), .o_bad_pairs(bad_pairs), .o_not_admitted_pairs(skipped_pairs),
        .o_quiet(quiet)
    );

    always #5 if (clock_on) clk = ~clk;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            phase <= 0;
            stamp <= 64'hfd98765401234560;
        end else begin
            phase <= phase == PHASES - 1 ? 0 : phase + 1;
            stamp <= stamp + 64'h100b;
        end
    end

    typedef logic [104:0] terminal_t;
    wire [104:0] source0 = {source0_session, source0_epoch, source0_seq, source0_ok, source0_error};
    wire [104:0] source1 = {source1_session, source1_epoch, source1_seq, source1_ok, source1_error};
    terminal_t want0 [0:31], want1 [0:31];
    logic want_pair [0:31];
    integer read0 = 0, read1 = 0, write0 = 0, write1 = 0;
    integer pair_read = 0, pair_write = 0, want_good = 0, want_bad = 0;
    integer raw0 = 0, raw1 = 0;
    logic hold_input0 = 0, hold_input1 = 0;
    logic [146:0] held0, held1;
    logic [196:0] want_meta0, want_meta1;
    logic [31:0] long_phase;
    logic [1:0] last_fired;
    string case_name;

    function automatic logic [146:0] token(
        input logic [3:0] kind, input logic [31:0] group_id, input logic [31:0] sequence_id,
        input logic [39:0] payload = 0, input logic sof = 0, input logic eol = 0
    );
        return {34'd0, 2'b11, sequence_id, group_id, kind, (kind == BAD), eol, sof, payload};
    endfunction

    function automatic logic [196:0] metadata(
        input logic [1:0] exposure, input logic [31:0] group_id, input logic [63:0] ts
    );
        return {1'b1, 1'b1, exposure, 1'b1, group_id, 32'h56a3d02f,
                32'd256, exposure == 1 ? 32'd3200 : 32'd200, ts};
    endfunction

    task automatic expect_source(input integer lane, input logic [31:0] seq_id,
                                 input logic [7:0] err,
                                 input logic [31:0] frame_session, frame_epoch);
        terminal_t expected;
        expected = {frame_session, frame_epoch, seq_id, (err == 0), err};
        if (lane == 0) begin
            want0[write0] = expected;
            write0++;
        end else begin
            want1[write1] = expected;
            write1++;
        end
    endtask

    task automatic expect_pair(input logic ok, input integer groups = 1);
        want_pair[pair_write] = ok;
        pair_write++;
        if (ok) want_good++;
        else want_bad += groups;
    endtask

    task automatic check_source;
        if (source0_valid && (read0 == write0 || source0 !== want0[read0]))
            $fatal(1, "PIX_FAIL unexpected LONG SOURCE got=%h expected=%h pending=%0d", source0,
                   want0[read0], write0 - read0);
        if (source1_valid && (read1 == write1 || source1 !== want1[read1]))
            $fatal(1, "PIX_FAIL unexpected SHORT SOURCE got=%h expected=%h pending=%0d", source1,
                   want1[read1], write1 - read1);
        if ((^{source0_valid, source1_valid}) === 1'bx)
            $fatal(1, "PIX_FAIL unknown SOURCE VALID");
    endtask

    task automatic drive(input logic [1:0] valid_lanes = 0,
                         input logic [146:0] long_token = 0, short_token = 0);
        @(negedge clk);
        {s1_valid, s0_valid} = valid_lanes;
        s0_data = long_token;
        s1_data = short_token;
    endtask

    task automatic observe(input logic [1:0] transfers,
                           input logic [1:0] raws = 0, starts = 0, aborts = 0, published = 0,
                           transfer_checks = 3);
        logic [1:0] fired, stalled_source;
        terminal_t before0, before1;
        @(posedge clk);
        fired = {s1_valid && s1_ready, s0_valid && s0_ready};
        last_fired = fired;
        if ((hold_input0 && (!s0_valid || s0_data !== held0)) ||
            (hold_input1 && (!s1_valid || s1_data !== held1)))
            $fatal(1, "PIX_FIXTURE changed a stalled offer");
        hold_input0 = s0_valid && !s0_ready;
        hold_input1 = s1_valid && !s1_ready;
        held0 = s0_data;
        held1 = s1_data;
        if ((^fired) === 1'bx || ((fired ^ transfers) & transfer_checks) != 0)
            $fatal(1, "PIX_FAIL transfers=%b wanted=%b kinds=%0d/%0d groups=%h/%h phase=%0d",
                   fired, transfers, s0_data[46:43], s1_data[46:43], s0_data[78:47], s1_data[78:47], phase);
        check_source();
        stalled_source = {source1_valid && !source1_ready, source0_valid && !source0_ready};
        before0 = source0;
        before1 = source1;
        if (source0_valid && source0_ready) begin
            $display("PIX_SOURCE lane=LONG seq=%h ok=%b error=%0d", source0_seq, source0_ok, source0_error);
            read0++;
        end
        if (source1_valid && source1_ready) begin
            $display("PIX_SOURCE lane=SHORT seq=%h ok=%b error=%0d", source1_seq, source1_ok, source1_error);
            read1++;
        end
        if (starts[0]) begin
            want_meta0 = metadata(1, s0_data[78:47], stamp);
            long_phase = phase;
        end
        if (starts[1]) want_meta1 = metadata(2, s1_data[78:47], stamp);

        #2;
        if (starts[0] && {out_session, out_epoch} !== {session, epoch})
            $fatal(1, "PIX_FAIL accepted LONG FS cohort got=%h/%h expected=%h/%h",
                   out_session, out_epoch, session, epoch);
        if ({m1_valid, m0_valid} !== raws || {m1_abort, m0_abort} !== aborts)
            $fatal(1, "PIX_FAIL RAW valid=%b abort=%b wanted valid=%b abort=%b",
                   {m1_valid, m0_valid}, {m1_abort, m0_abort}, raws, aborts);
        if (raws[0]) begin
            if ({m0_eol, m0_sof, m0_data, seq0, meta0} !== {s0_data[41:0], s0_data[110:79], want_meta0})
                $fatal(1, "PIX_FAIL LONG RAW or FS identity data=%h seq=%h meta=%h expected_meta=%h",
                       m0_data, seq0, meta0, want_meta0);
            raw0++;
        end
        if (raws[1]) begin
            if ({m1_eol, m1_sof, m1_data, seq1, meta1} !== {s1_data[41:0], s1_data[110:79], want_meta1})
                $fatal(1, "PIX_FAIL SHORT RAW or FS identity data=%h seq=%h meta=%h expected_meta=%h",
                       m1_data, seq1, meta1, want_meta1);
            raw1++;
        end
        if ((stalled_source[0] && (!source0_valid || source0 !== before0)) ||
            (stalled_source[1] && (!source1_valid || source1 !== before1)))
            $fatal(1, "PIX_FAIL withdrew or changed stalled SOURCE");
        if (({source1_valid, source0_valid} & published) !== published)
            $fatal(1, "PIX_FAIL SOURCE missing on its terminal edge wanted=%b", published);
        check_source();
        if (pair_event === 1'b1) begin
            if (pair_read == pair_write || pair_ok !== want_pair[pair_read])
                $fatal(1, "PIX_FAIL unexpected pair event ok=%b pending=%0d", pair_ok, pair_write - pair_read);
            $display("PIX_PAIR ok=%b good=%0d bad=%0d", pair_ok, good_pairs, bad_pairs);
            pair_read++;
        end else if (pair_event !== 1'b0) $fatal(1, "PIX_FAIL unknown pair event");
    endtask

    task automatic drain_offers(input logic [1:0] pending_lanes,
                                input logic [146:0] long_token, short_token);
        logic [1:0] pending;
        pending = pending_lanes;
        while (pending != 0) begin
            drive(pending, long_token, short_token);
            observe(0, 0, 0, 0, 0, 0);
            pending &= ~last_fired;
        end
    endtask

    task automatic idle(input integer edges = 1);
        repeat (edges) begin
            drive();
            observe(0);
        end
    endtask

    task automatic first_long(input logic [31:0] g, seq_id);
        drive(1, token(FS, g, seq_id));
        reset_n = 1;
        observe(1, 0, 1);
    endtask

    task automatic start_both(input logic [31:0] g, l, s);
        drive(3, token(FS, g, l), token(FS, g, s));
        reset_n = 1;
        observe(3, 0, 3);
    endtask

    task automatic short_start(input logic [31:0] g, s);
        drive(2, 0, token(FS, g, s));
        observe(2, 0, 2);
    endtask

    task automatic crop_both(input logic [31:0] g, l, s);
        drive(3, token(RAW, g, l, A, 1), token(RAW, g, s, C, 1));
        observe(3, 3);
        drive(3, token(RAW, g, l, B, 0, 1), token(RAW, g, s, D, 0, 1));
        observe(3, 3);
    endtask

    task automatic good_fe(input logic [31:0] g, l, s);
        drive(3, token(FE, g, l), token(FE, g, s));
        expect_source(0, l, 0, session, epoch);
        expect_source(1, s, 0, session, epoch);
        expect_pair(1);
        observe(3, 0, 0, 0, 3);
    endtask

    task automatic healthy(input logic [31:0] g, l, s);
        start_both(g, l, s);
        crop_both(g, l, s);
        good_fe(g, l, s);
        idle(3);
    endtask

    task automatic retrain;
        drive();
        stable = 0;
        observe(0);
        drive();
        stable = 1;
        observe(0);
    endtask

    task automatic first_overlap;
        first_long(17, 32'h1007);
        idle(2);
        short_start(17, 32'hba76);
        crop_both(17, 32'h1007, 32'hba76);
        drive(1, token(FE, 17, 32'h1007));
        source0_ready = 0;
        expect_source(0, 32'h1007, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        idle(4);
        drive();
        source0_ready = 1;
        observe(0);
        drive(3, token(FS, 18, 32'h1008), token(FE, 17, 32'hba76));
        source1_ready = 0;
        expect_source(1, 32'hba76, 0, session, epoch);
        expect_pair(1);
        observe(3, 0, 1, 0, 2);
        drive(1, token(RAW, 18, 32'h1008, B, 1, 1));
        observe(1, 1);
        idle(3);
        drive();
        source1_ready = 1;
        observe(0);
        short_start(18, 32'hba77);
        drive(2, 0, token(RAW, 18, 32'hba77, C, 1, 1));
        observe(2, 2);
        good_fe(18, 32'h1008, 32'hba77);
    endtask

    task automatic skipped_short(input logic [31:0] g, s);
        drive(2, 0, token(FS, g, s));
        permit = 1;
        time_valid = 1;
        fault = 0;
        observe(0);
        drive(2, 0, token(FS, g, s));
        observe(2);
    endtask

    task automatic stop_wrap;
        start_both(32'hfffffffd, 31, 131);
        crop_both(32'hfffffffd, 31, 131);
        drive(3, token(FE, 32'hfffffffd, 31), token(FE, 32'hfffffffd, 131));
        permit = 0;
        expect_source(0, 31, 0, session, epoch);
        expect_source(1, 131, 0, session, epoch);
        expect_pair(1);
        observe(3, 0, 0, 0, 3);
        drive();
        permit = 1;
        observe(0);
        drive(1, token(FS, 32'hfffffffe, 32));
        permit = 0;
        observe(1);
        skipped_short(32'hfffffffe, 132);
        idle(2);
        drive(1, token(FS, 32'hffffffff, 33));
        time_valid = 0;
        observe(1);
        drain_offers(2, 0, token(FS, 32'hffffffff, 133));
        drain_offers(3, token(RAW, 32'hffffffff, 33, A, 1, 1),
                       token(RAW, 32'hffffffff, 133, C, 1, 1));
        expect_pair(0);
        drain_offers(3, token(FE, 32'hffffffff, 33), token(FE, 32'hffffffff, 133));
        idle(3);
        retrain();
        drive();
        permit = 0;
        time_valid = 1;
        observe(0);
        drive(3, token(FS, 1, 34), token(FS, 1, 134));
        permit = 1;
        observe(3, 0, 3);
        crop_both(1, 34, 134);
        good_fe(1, 34, 134);
        idle(3);
        drive(2, 0, token(FS, 2, 135));
        observe(0);
        drive(3, token(FS, 2, 35), token(FS, 2, 135));
        observe(3, 0, 3);
        crop_both(2, 35, 135);
        good_fe(2, 35, 135);
    endtask

    task automatic peer_faults;
        start_both(31, 41, 141);
        drive(2, 0, token(RAW, 31, 141, C, 1, 1));
        observe(2, 2);
        drive(3, token(RAW, 31, 41, A, 1, 1), token(BAD, 31, 141));
        expect_source(0, 41, 8, session, epoch);
        expect_source(1, 141, 8, session, epoch);
        expect_pair(0);
        observe(3, 0, 0, 3, 3);
        idle(3);
        retrain();
        start_both(32, 42, 142);
        drive(1, token(RAW, 32, 42, B, 1, 1));
        observe(1, 1);
        drive(3, token(BAD, 32, 42), token(RAW, 32, 142, D, 1, 1));
        expect_source(0, 42, 8, session, epoch);
        expect_pair(0);
        observe(3, 0, 0, 1, 1);
        idle(3);
        retrain();
        start_both(33, 43, 143);
        crop_both(33, 43, 143);
        drive(3, token(FS, 34, 44), token(BAD, 33, 143));
        expect_source(0, 43, 5, session, epoch);
        expect_source(1, 143, 5, session, epoch);
        expect_pair(0);
        observe(2, 0, 0, 3, 3);
        drive(1, token(FS, 34, 44));
        observe(0);
        drive(1, token(FS, 34, 44));
        stable = 0;
        observe(0, 0, 0, 0, 0, 0);
        if (!last_fired[0]) drain_offers(1, token(FS, 34, 44), 0);
        drain_offers(2, 0, token(FS, 34, 144));
        expect_pair(1);
        drain_offers(3, token(FE, 34, 44), token(FE, 34, 144));
        while (quiet !== 1'b1 || pair_read != pair_write || read0 != write0 || read1 != write1)
            idle();
        retrain();
        healthy(35, 45, 145);
    endtask

    task automatic cohort;
        logic [31:0] previous_session, previous_epoch;
        previous_session = session;
        previous_epoch = epoch;
        start_both(61, 61, 161);
        crop_both(61, 61, 161);
        drive(1, token(FE, 61, 61));
        expect_source(0, 61, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        idle(2);
        drive(1, token(FS, 62, 62));
        session = 32'h816af77c;
        epoch = 32'h66413ace;
        expect_source(1, 161, 9, previous_session, previous_epoch);
        expect_pair(0);
        observe(1, 0, 1, 2, 2);
        drive(1, token(RAW, 62, 62, C, 1, 1));
        observe(0);
        drive(1, token(RAW, 62, 62, C, 1, 1));
        observe(1, 1);
        short_start(62, 162);
        drive(2, 0, token(RAW, 62, 162, B, 1, 1));
        observe(2, 2);
        good_fe(62, 62, 162);
    endtask

    task automatic stopped_reset;
        start_both(32'hffffffff, 32'hffffffff, 32'h80000000);
        crop_both(32'hffffffff, 32'hffffffff, 32'h80000000);
        drive(1, token(FE, 32'hffffffff, 32'hffffffff));
        source0_ready = 0;
        expect_source(0, 32'hffffffff, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        idle(2);
        drive();
        clock_on = 0;
        #1 reset_n = 0;
        #2;
        if ({source1_valid, source0_valid, m1_valid, m0_valid, m1_abort, m0_abort, pair_event} !== 0)
            $fatal(1, "PIX_FAIL old published state survived asynchronous stopped-clock reset");
        $display("PIX_RESET canceled held LONG SOURCE and active SHORT with stopped clock");
        read0 = 0;
        read1 = 0;
        write0 = 0;
        write1 = 0;
        pair_read = 0;
        pair_write = 0;
        want_good = 0;
        want_bad = 0;
        source0_ready = 1;
        session = 32'h901d2d30;
        epoch = 32'h0a6de883;
        #28;
        {s1_valid, s0_valid} = 3;
        s0_data = token(FS, 1, 0);
        s1_data = token(FS, 1, 32'h80000001);
        reset_n = 1;
        clock_on = 1;
        observe(3, 0, 3);
        crop_both(1, 0, 32'h80000001);
        good_fe(1, 0, 32'h80000001);
    endtask

    task automatic wait_deadline;
        drive();
        while (phase != long_phase) begin
            observe(0);
            drive();
        end
    endtask

    task automatic deadline;
        start_both(51, 51, 151);
        crop_both(51, 51, 151);
        wait_deadline();
        expect_source(0, 51, 11, session, epoch);
        expect_source(1, 151, 11, session, epoch);
        expect_pair(0);
        observe(0, 0, 0, 3, 3);
        idle(3);
        retrain();
        healthy(52, 52, 152);
    endtask

    task automatic cancel_on_peer_edge(input logic [31:0] g, l, s,
                                      input logic [3:0] short_kind, input logic [7:0] reason,
                                      input logic at_deadline);
        start_both(g, l, s);
        crop_both(g, l, s);
        if (at_deadline) wait_deadline();
        else drive();
        {s1_valid, s0_valid} = 3;
        s0_data = token(FE, g, l);
        s1_data = token(short_kind, g, s);
        expect_source(0, l, reason, session, epoch);
        expect_source(1, s, reason, session, epoch);
        expect_pair(0);
        observe(0, 0, 0, 3, 3, 0);
        drain_offers(3 & ~last_fired, token(FE, g, l), token(short_kind, g, s));
        idle(3);
        retrain();
    endtask

    task automatic terminal_priority;
        cancel_on_peer_edge(55, 55, 155, BAD, 8, 0);
        cancel_on_peer_edge(56, 56, 156, FE, 11, 1);
        cancel_on_peer_edge(57, 57, 157, BAD, 11, 1);
        healthy(58, 58, 158);
    endtask

    task automatic old_short_fault;
        start_both(71, 71, 171);
        crop_both(71, 71, 171);
        drive(1, token(FE, 71, 71));
        source0_ready = 0;
        expect_source(0, 71, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        drive(2, 0, token(BAD, 71, 171));
        expect_source(1, 171, 8, session, epoch);
        expect_pair(0);
        observe(2, 0, 0, 2, 2);
        idle(3);
        drive();
        source0_ready = 1;
        observe(0);
        retrain();
        start_both(72, 72, 172);
        crop_both(72, 72, 172);
        drive(1, token(FE, 72, 72));
        expect_source(0, 72, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        idle(2);
        first_long(73, 73);
        drive(3, token(RAW, 73, 73, A, 1, 1), token(BAD, 72, 172));
        expect_source(1, 172, 8, session, epoch);
        expect_pair(0);
        observe(3, 1, 0, 2, 2);
        idle(2);
        short_start(73, 173);
        drive(2, 0, token(RAW, 73, 173, C, 1, 1));
        observe(2, 2);
        good_fe(73, 73, 173);
    endtask

    task automatic dual_cancel;
        start_both(80, 80, 180);
        crop_both(80, 80, 180);
        drive(1, token(FE, 80, 80));
        expect_source(0, 80, 0, session, epoch);
        observe(1, 0, 0, 0, 1);
        idle(2);
        first_long(81, 81);
        drive(1, token(RAW, 81, 81, A, 1, 1));
        observe(1, 1);
        drive(3, token(FE, 81, 81), token(FS, 81, 181));
        fault = 1;
        expect_source(0, 81, 9, session, epoch);
        expect_source(1, 180, 9, session, epoch);
        expect_pair(0, 2);
        observe(0, 0, 0, 3, 3, 0);
        drain_offers(3 & ~last_fired, token(FE, 81, 81), token(FS, 81, 181));
        idle(3);
        drive();
        fault = 0;
        observe(0);
        retrain();
        healthy(82, 82, 182);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) $fatal(1, "PIX_FIXTURE missing CASE");
        #1 reset_n = 0;
        case (case_name)
            "first_overlap": first_overlap();
            "stop_wrap": stop_wrap();
            "peer_faults": peer_faults();
            "cohort": cohort();
            "stopped_reset": stopped_reset();
            "deadline": deadline();
            "terminal_priority": terminal_priority();
            "old_short_fault": old_short_fault();
            "dual_cancel": dual_cancel();
            default: $fatal(1, "PIX_FIXTURE unknown CASE %s", case_name);
        endcase
        idle(5);
        if (quiet !== 1'b1 || read0 != write0 || read1 != write1 || pair_read != pair_write ||
            good_pairs !== want_good || bad_pairs !== want_bad)
            $fatal(1, "PIX_FAIL final quiet=%b SOURCE pending=%0d/%0d pair events pending=%0d counters=%0d/%0d wanted=%0d/%0d",
                   quiet, write0 - read0, write1 - read1, pair_write - pair_read,
                   good_pairs, bad_pairs, want_good, want_bad);
        $display("BLACKBOX_PASS case=%s raw=%0d/%0d sources=%0d/%0d events=%0d good=%0d bad=%0d skipped=%0d",
                 case_name, raw0, raw1, read0, read1, pair_read, good_pairs, bad_pairs, skipped_pairs);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "PIX_WATCHDOG %s", case_name);
    end
endmodule
