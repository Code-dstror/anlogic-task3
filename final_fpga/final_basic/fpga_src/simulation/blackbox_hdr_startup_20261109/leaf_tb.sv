`timescale 1ns/1ps
`default_nettype none

module leaf_tb;
    localparam integer SERVICE = 64;
    localparam [3:0] FS = 4'd7, FE = 4'd6, RAW = 4'd0;
    localparam [39:0] LONG_WORD = 40'hca9385217d, SHORT_WORD = 40'h3564a71e82;

    reg clk = 0, reset_n = 0;
    reg stable = 0, admit = 1;
    reg [31:0] session = 1, epoch = 19;
    reg [63:0] time_ns = 0;
    reg [146:0] in0 = 0, in1 = 0;
    reg valid0 = 0, valid1 = 0, source_ready0 = 1, source_ready1 = 1;
    wire ready0, ready1;
    wire [39:0] raw0, raw1;
    wire raw_valid0, raw_valid1, sof0, sof1, eol0, eol1, abort0, abort1;
    wire [31:0] raw_session, raw_epoch, raw_seq0, raw_seq1;
    wire source_valid0, source_valid1, source_ok0, source_ok1;
    wire [31:0] source_session0, source_session1, source_epoch0, source_epoch1;
    wire [31:0] source_seq0, source_seq1;
    wire [7:0] source_error0, source_error1;
    wire pair_event, pair_ok, quiet;
    wire [104:0] source_bundle0 = {source_session0, source_epoch0, source_seq0,
                                   source_ok0, source_error0};
    wire [104:0] source_bundle1 = {source_session1, source_epoch1, source_seq1,
                                   source_ok1, source_error1};

    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(512), .EXTERNAL_PHASE_ENABLE(0)) dut (
        .i_clk(clk), .i_reset_n(reset_n), .i_fault(1'b0), .i_stable(stable),
        .i_admit_enable(admit), .i_session(session), .i_epoch(epoch),
        .i_time(time_ns), .i_time_valid(1'b1), .i_capture0_idle(1'b1), .i_capture1_idle(1'b1),
        .s0_data(in0), .s1_data(in1), .s0_valid(valid0), .s1_valid(valid1),
        .s0_ready(ready0), .s1_ready(ready1),
        .m0_data(raw0), .m1_data(raw1), .m0_valid(raw_valid0), .m1_valid(raw_valid1),
        .m0_sof(sof0), .m1_sof(sof1), .m0_eol(eol0), .m1_eol(eol1),
        .m0_abort(abort0), .m1_abort(abort1),
        .o_sequence0(raw_seq0), .o_sequence1(raw_seq1), .o_session(raw_session), .o_epoch(raw_epoch),
        .o_source0_valid(source_valid0), .o_source1_valid(source_valid1),
        .i_source0_ready(source_ready0), .i_source1_ready(source_ready1),
        .o_source_session(source_session0), .o_source_epoch(source_epoch0),
        .o_source0_sequence(source_seq0), .o_source1_sequence(source_seq1),
        .o_source_ok(source_ok0), .o_source_error(source_error0),
        .o_source1_session(source_session1), .o_source1_epoch(source_epoch1),
        .o_source1_ok(source_ok1), .o_source1_error(source_error1),
        .o_pair_event(pair_event), .o_pair_ok(pair_ok), .o_quiet(quiet), .i_timeout_phase(32'd0)
    );

    always #5 clk = ~clk;
    always @(posedge clk) time_ns <= time_ns + 64'd10;

    string scenario = "reset";
    integer accepted0 = 0, accepted1 = 0;
    integer raw_count0 = 0, raw_count1 = 0, source_count0 = 0, source_count1 = 0;
    integer pair_good = 0, pair_bad = 0;
    reg [1:0] want_raw = 0, want_source = 0, want_source_ok = 0;
    reg want_good_pair = 0, may_bad_pair = 0, may_abort = 0;
    reg [31:0] want_seq0 = 0, want_seq1 = 0, want_session = 0, want_epoch = 0;
    reg stalled_in0 = 0, stalled_in1 = 0, stalled_source0 = 0, stalled_source1 = 0;
    reg [146:0] prev_in0, prev_in1;
    reg [104:0] prev_source0, prev_source1;

    task automatic fail(input string why);
        $display("LEAF_GATE_FAIL scenario=%s time_ns=%0t %s", scenario, $time, why);
        $fatal(1, "Public interface assertion failed");
    endtask

    // Scoreboard samples exactly the rising edge used by the interface.
    always @(posedge clk) begin
        if (!reset_n) begin
            stalled_in0 = 0;
            stalled_in1 = 0;
            stalled_source0 = 0;
            stalled_source1 = 0;
        end else begin
            if (stalled_in0 && (valid0 !== 1'b1 || in0 !== prev_in0))
                fail("fixture withdrew LONG before acceptance");
            if (stalled_in1 && (valid1 !== 1'b1 || in1 !== prev_in1))
                fail("fixture withdrew SHORT before acceptance");
            stalled_in0 = valid0 && !ready0;
            stalled_in1 = valid1 && !ready1;
            prev_in0 = in0;
            prev_in1 = in1;
            if (valid0 && ready0) accepted0 = accepted0 + 1;
            if (valid1 && ready1) accepted1 = accepted1 + 1;

            if (!may_abort && (abort0 || abort1)) fail("unexpected RAW abort");
            if (raw_valid0 && !abort0) begin
                if (!want_raw[0] || raw_count0 != 0 ||
                    {raw0, sof0, eol0, raw_seq0, raw_session, raw_epoch} !==
                    {LONG_WORD, 2'b11, want_seq0, want_session, want_epoch})
                    fail($sformatf("unexpected LONG RAW: data=%010h seq=%0d cohort=%0d/%0d SOF/EOL=%b%b",
                                   raw0, raw_seq0, raw_session, raw_epoch, sof0, eol0));
                raw_count0 = raw_count0 + 1;
            end
            if (raw_valid1 && !abort1) begin
                if (!want_raw[1] || raw_count1 != 0 ||
                    {raw1, sof1, eol1, raw_seq1, raw_session, raw_epoch} !==
                    {SHORT_WORD, 2'b11, want_seq1, want_session, want_epoch})
                    fail($sformatf("unexpected SHORT RAW: data=%010h seq=%0d cohort=%0d/%0d SOF/EOL=%b%b",
                                   raw1, raw_seq1, raw_session, raw_epoch, sof1, eol1));
                raw_count1 = raw_count1 + 1;
            end

            if (stalled_source0 && (source_valid0 !== 1'b1 || source_bundle0 !== prev_source0))
                fail("LONG SOURCE changed while stalled");
            if (stalled_source1 && (source_valid1 !== 1'b1 || source_bundle1 !== prev_source1))
                fail("SHORT SOURCE changed while stalled");
            stalled_source0 = source_valid0 && !source_ready0;
            stalled_source1 = source_valid1 && !source_ready1;
            prev_source0 = source_bundle0;
            prev_source1 = source_bundle1;
            if (source_valid0) begin
                if (!want_source[0] || raw_count0 != 1 || source_count0 != 0 ||
                    {source_session0, source_epoch0, source_seq0, source_ok0} !==
                    {want_session, want_epoch, want_seq0, want_source_ok[0]} ||
                    (^source_error0 === 1'bx) || (source_ok0 != (source_error0 == 0)))
                    fail($sformatf("unexpected LONG SOURCE: seq=%0d cohort=%0d/%0d ok=%b error=%02x",
                                   source_seq0, source_session0, source_epoch0, source_ok0, source_error0));
                if (source_ready0) source_count0 = source_count0 + 1;
            end
            if (source_valid1) begin
                if (!want_source[1] || raw_count1 != 1 || source_count1 != 0 ||
                    {source_session1, source_epoch1, source_seq1, source_ok1} !==
                    {want_session, want_epoch, want_seq1, want_source_ok[1]} ||
                    (^source_error1 === 1'bx) || (source_ok1 != (source_error1 == 0)))
                    fail($sformatf("unexpected SHORT SOURCE: seq=%0d cohort=%0d/%0d ok=%b error=%02x",
                                   source_seq1, source_session1, source_epoch1, source_ok1, source_error1));
                if (source_ready1) source_count1 = source_count1 + 1;
            end

            if (pair_event) begin
                if (pair_ok === 1'b1) begin
                    if (!want_good_pair || pair_good != 0) fail("unexpected successful pair event");
                    pair_good = pair_good + 1;
                end else if (pair_ok === 1'b0) begin
                    if (!may_bad_pair) fail("unexpected failed pair event");
                    pair_bad = pair_bad + 1;
                end else fail("pair result is unknown");
            end
        end
    end

    function automatic [146:0] token(input [3:0] kind, input [31:0] grp, seq,
                                     input id_ok, cycle_ok, input [39:0] word);
        token = 147'd0;
        token[39:0] = word;
        token[41:40] = (kind == RAW) ? 2'b11 : 2'b00;
        token[46:43] = kind;
        token[78:47] = grp;
        token[110:79] = seq;
        token[111] = id_ok;
        token[112] = cycle_ok;
    endfunction

    task automatic send0(input [146:0] word);
        @(negedge clk);
        in0 = word;
        valid0 = 1;
        for (integer k = 0; k < SERVICE; k = k + 1) begin
            @(posedge clk);
            if (ready0 === 1'b1) begin
                #1 valid0 = 0;
                return;
            end
        end
        fail($sformatf("LONG token not accepted within %0d edges: type=%0d group=%0d id=%b cycle=%b",
                       SERVICE, word[46:43], word[78:47], word[111], word[112]));
    endtask

    task automatic offer1(input [146:0] word);
        @(negedge clk);
        in1 = word;
        valid1 = 1;
    endtask

    task automatic accept1;
        for (integer k = 0; k < SERVICE; k = k + 1) begin
            @(posedge clk);
            if (ready1 === 1'b1) begin
                #1 valid1 = 0;
                return;
            end
        end
        fail($sformatf("SHORT token not accepted within %0d edges: type=%0d group=%0d id=%b cycle=%b",
                       SERVICE, in1[46:43], in1[78:47], in1[111], in1[112]));
    endtask

    task automatic send1(input [146:0] word);
        offer1(word);
        accept1();
    endtask

    task automatic tick(input integer n);
        repeat (n) begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic begin_case(input string name, input [31:0] seq0, seq1,
                              input [1:0] raw_mask, source_mask, ok_mask,
                              input good_pair, bad_pair, can_abort);
        @(negedge clk);
        if (reset_n && quiet !== 1'b1) fail("previous case not quiet");
        scenario = name;
        want_seq0 = seq0;
        want_seq1 = seq1;
        want_session = session;
        want_epoch = epoch;
        want_raw = raw_mask;
        want_source = source_mask;
        want_source_ok = ok_mask;
        want_good_pair = good_pair;
        may_bad_pair = bad_pair;
        may_abort = can_abort;
        accepted0 = 0;
        accepted1 = 0;
        raw_count0 = 0;
        raw_count1 = 0;
        source_count0 = 0;
        source_count1 = 0;
        pair_good = 0;
        pair_bad = 0;
        $display("LEAF_GATE_CASE %s", scenario);
    endtask

    task automatic end_case(input integer n0, n1);
        for (integer k = 0; k < SERVICE; k = k + 1) begin
            tick(1);
            if (quiet === 1'b1 && pair_good == integer'(want_good_pair) &&
                raw_count0 == integer'(want_raw[0]) && raw_count1 == integer'(want_raw[1]) &&
                source_count0 == integer'(want_source[0]) && source_count1 == integer'(want_source[1])) begin
                tick(4);
                if (quiet !== 1'b1 || accepted0 != n0 || accepted1 != n1)
                    fail("incomplete input accounting or quiet did not hold");
                $display("LEAF_GATE_STATS %s input=%0d/%0d raw=%0d/%0d source=%0d/%0d pair_good=%0d pair_bad=%0d",
                         scenario, accepted0, accepted1, raw_count0, raw_count1,
                         source_count0, source_count1, pair_good, pair_bad);
                return;
            end
        end
        fail($sformatf("missing completion: quiet=%b RAW=%0d/%0d SOURCE=%0d/%0d pair_good=%0d pair_bad=%0d",
                       quiet, raw_count0, raw_count1, source_count0, source_count1, pair_good, pair_bad));
    endtask

    task automatic orphan(input string name, input [31:0] grp, seq, input id_ok, cycle_ok);
        begin_case(name, 0, seq, 0, 0, 0, 0, 1, 0);
        send1(token(FS, grp, seq, id_ok, cycle_ok, 0));
        tick(3);
        if (quiet !== 1'b1) fail("rejected SHORT tail kept a context busy");
        send1(token(RAW, grp, seq, id_ok, cycle_ok, SHORT_WORD));
        send1(token(FE, grp, seq, id_ok, cycle_ok, 0));
        end_case(0, 3);
    endtask

    task automatic send_body(input [31:0] grp, seq0, seq1);
        send0(token(RAW, grp, seq0, 1, 1, LONG_WORD));
        send1(token(RAW, grp, seq1, 1, 1, SHORT_WORD));
        send0(token(FE, grp, seq0, 1, 1, 0));
        send1(token(FE, grp, seq1, 1, 1, 0));
    endtask

    task automatic send_pair(input [31:0] grp, seq0, seq1);
        send0(token(FS, grp, seq0, 1, 1, 0));
        send1(token(FS, grp, seq1, 1, 1, 0));
        send_body(grp, seq0, seq1);
    endtask

    task automatic healthy(input string name, input [31:0] grp, seq0, seq1);
        begin_case(name, seq0, seq1, 2'b11, 2'b11, 2'b11, 1, 0, 0);
        send_pair(grp, seq0, seq1);
        end_case(3, 3);
    endtask

    task automatic await_offer(input [1:0] mask);
        for (integer k = 0; k < SERVICE; k = k + 1) begin
            tick(1);
            if (({source_valid1, source_valid0} & mask) === mask) return;
        end
        fail("expected SOURCE offer was not published");
    endtask

    initial begin
        $timeformat(-9, 0, "", 0);
        tick(5);
        @(negedge clk) reset_n = 1;

        orphan("cold_short_group_zero", 0, 203, 1, 1);
        begin_case("trusted_warmup", 101, 204, 0, 0, 0, 1, 0, 0);
        send_pair(1, 101, 204);
        end_case(3, 3);

        begin_case("first_admitted_source_backpressure", 102, 205, 3, 3, 3, 1, 0, 0);
        stable = 1;
        source_ready0 = 0;
        source_ready1 = 0;
        send_pair(2, 102, 205);
        await_offer(2'b11);
        tick(10);
        if (quiet !== 1'b0 || source_count0 != 0 || source_count1 != 0)
            fail("held SOURCE missing from quiet accounting");
        @(negedge clk) source_ready1 = 1;
        tick(4);
        if (quiet !== 1'b0 || source_count0 != 0 || source_count1 != 1)
            fail("SHORT SOURCE did not drain independently of LONG");
        @(negedge clk) source_ready0 = 1;
        end_case(3, 3);

        orphan("short_identity_invalid", 3, 206, 0, 1);
        healthy("after_invalid_identity", 4, 103, 207);
        orphan("short_cycle_invalid", 5, 208, 1, 0);
        healthy("after_invalid_cycle", 6, 104, 209);

        begin_case("trustworthy_future_short_waits", 105, 210, 3, 3, 3, 1, 0, 0);
        offer1(token(FS, 7, 210, 1, 1, 0));
        repeat (12) begin
            @(posedge clk);
            if (ready1 !== 1'b0) fail("trustworthy SHORT consumed before a matching LONG offer");
            #1;
        end
        fork
            send0(token(FS, 7, 105, 1, 1, 0));
            accept1();
        join
        send_body(7, 105, 210);
        end_case(3, 3);

        begin_case("matched_short_bad_fs", 106, 211, 1, 1, 0, 0, 1, 1);
        source_ready0 = 0;
        send0(token(FS, 8, 106, 1, 1, 0));
        send0(token(RAW, 8, 106, 1, 1, LONG_WORD));
        tick(3);
        if (raw_count0 != 1) fail("fixture never started the matched LONG");
        send1(token(FS, 8, 211, 0, 1, 0));
        await_offer(2'b01);
        tick(7);
        if (quiet !== 1'b0) fail("cancelled LONG SOURCE disappeared from quiet accounting");
        @(negedge clk) source_ready0 = 1;
        send0(token(FE, 8, 106, 1, 1, 0));
        send1(token(RAW, 8, 211, 0, 1, SHORT_WORD));
        send1(token(FE, 8, 211, 0, 1, 0));
        end_case(3, 3);

        begin_case("warmup_after_matched_cancel", 107, 212, 0, 0, 0, 1, 0, 0);
        stable = 0;
        send_pair(9, 107, 212);
        end_case(3, 3);

        begin_case("stop_drains_matched_group", 108, 213, 3, 3, 3, 1, 0, 0);
        stable = 1;
        send0(token(FS, 10, 108, 1, 1, 0));
        send1(token(FS, 10, 213, 1, 1, 0));
        send0(token(RAW, 10, 108, 1, 1, LONG_WORD));
        tick(3);
        if (raw_count0 != 1) fail("no LONG RAW observed before closing admission");
        @(negedge clk) admit = 0;
        send1(token(RAW, 10, 213, 1, 1, SHORT_WORD));
        send0(token(FE, 10, 108, 1, 1, 0));
        send1(token(FE, 10, 213, 1, 1, 0));
        end_case(3, 3);

        begin_case("reset_clears_held_sources", 109, 214, 3, 3, 3, 1, 0, 0);
        admit = 1;
        source_ready0 = 0;
        source_ready1 = 0;
        send_pair(11, 109, 214);
        await_offer(2'b11);
        tick(4);
        if (source_count0 != 0 || source_count1 != 0 || accepted0 != 3 || accepted1 != 3)
            fail("invalid reset fixture");
        @(negedge clk);
        #2 reset_n = 0;
        #1;
        if (source_valid0 !== 1'b0 || source_valid1 !== 1'b0)
            fail("reset did not clear held SOURCE before the next clock edge");
        tick(4);
        @(negedge clk);
        session = 2;
        epoch = 28;
        source_ready0 = 1;
        source_ready1 = 1;
        begin_case("first_pair_after_reset_new_cohort", 19, 23, 3, 3, 3, 1, 0, 0);
        reset_n = 1;
        tick(3);
        if (quiet !== 1'b1) fail("new cohort did not start quiet");
        send_pair(1, 19, 23);
        end_case(3, 3);

        $display("LEAF_GATE_PASS");
        $finish;
    end

    initial begin
        #200000;
        fail("simulation watchdog");
    end
endmodule

`default_nettype wire
