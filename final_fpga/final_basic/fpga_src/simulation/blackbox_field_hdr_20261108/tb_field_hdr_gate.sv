`timescale 1ns/1ps

module tb_field_hdr_gate;
    localparam integer TIMEOUT = 64;
    localparam integer WAIT_CYCLES = 160;
    localparam integer LONG = 0;
    localparam integer SHORT = 1;
    localparam logic [3:0] RAW = 4'd0, FS = 4'd7, FE = 4'd6, BAD = 4'd8;

    logic clk = 0;
    logic rst_n = 0;
    logic fault = 0;
    logic stable = 0;
    logic [31:0] session_id = 32'h1234abcd;
    logic [31:0] epoch = 32'h713b;
    logic [63:0] capture_time = 64'd700_000;
    logic [31:0] phase = 0;
    logic [146:0] token_in[2];
    logic [1:0] s_valid = 0;
    wire [1:0] s_ready;
    wire [39:0] m_data[2];
    wire [1:0] m_valid, m_sof, m_eol, m_abort;
    wire [31:0] sequence_out[2];
    wire [31:0] capture_session, capture_epoch;
    logic [1:0] source_ready = 2'b11;
    wire [1:0] source_valid, source_ok;
    wire [31:0] source_session[2], source_epoch[2], source_sequence[2];
    wire [7:0] source_error[2];
    wire pair_event, pair_ok, quiet;
    wire [31:0] good_pairs, bad_pairs;

    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(TIMEOUT), .EXTERNAL_PHASE_ENABLE(1)) dut (
        .i_clk(clk), .i_reset_n(rst_n), .i_fault(fault), .i_stable(stable),
        .i_admit_enable(1'b1), .i_session(session_id), .i_epoch(epoch),
        .i_time(capture_time), .i_time_valid(1'b1), .i_capture0_idle(1'b1),
        .i_capture1_idle(1'b1), .i_timeout_phase(phase),
        .s0_data(token_in[LONG]), .s1_data(token_in[SHORT]), .s0_valid(s_valid[LONG]),
        .s1_valid(s_valid[SHORT]), .s0_ready(s_ready[LONG]), .s1_ready(s_ready[SHORT]),
        .m0_data(m_data[LONG]), .m1_data(m_data[SHORT]), .m0_valid(m_valid[LONG]),
        .m1_valid(m_valid[SHORT]), .m0_sof(m_sof[LONG]), .m1_sof(m_sof[SHORT]),
        .m0_eol(m_eol[LONG]), .m1_eol(m_eol[SHORT]), .m0_abort(m_abort[LONG]), .m1_abort(m_abort[SHORT]),
        .o_sequence0(sequence_out[LONG]), .o_sequence1(sequence_out[SHORT]),
        .o_session(capture_session), .o_epoch(capture_epoch), .o_metadata0(), .o_metadata1(),
        .o_source0_valid(source_valid[LONG]), .o_source1_valid(source_valid[SHORT]),
        .i_source0_ready(source_ready[LONG]), .i_source1_ready(source_ready[SHORT]),
        .o_source_session(source_session[LONG]), .o_source_epoch(source_epoch[LONG]),
        .o_source0_sequence(source_sequence[LONG]), .o_source1_sequence(source_sequence[SHORT]),
        .o_source_ok(source_ok[LONG]), .o_source_error(source_error[LONG]),
        .o_source1_session(source_session[SHORT]), .o_source1_epoch(source_epoch[SHORT]),
        .o_source1_ok(source_ok[SHORT]), .o_source1_error(source_error[SHORT]),
        .o_pair_event(pair_event), .o_pair_ok(pair_ok), .o_diag_pair(), .o_diag_counts(),
        .o_good_pairs(good_pairs), .o_bad_pairs(bad_pairs), .o_not_admitted_pairs(), .o_quiet(quiet)
    );

    typedef struct packed {
        logic [39:0] data;
        logic sof, eol;
        logic [31:0] session_id, epoch, seq;
    } raw_record;
    typedef struct packed {
        logic [31:0] session_id, epoch, seq;
        logic ok;
    } source_record;

    string case_name;
    bit terminal_printed = 0;
    raw_record raw_plan[2][32];
    source_record source_plan[2][16];
    int raw_planned[2], raw_seen[2], source_planned[2], source_seen[2];
    int good_events, bad_events;
    bit [1:0] source_held;
    logic [104:0] held_source[2];
    time source_not_before[2];

    always #4 clk = !clk;
    always @(negedge clk) begin
        capture_time <= capture_time + 8;
        phase <= (!rst_n || phase == TIMEOUT - 1) ? 0 : phase + 1;
    end

    task automatic fail(input string reason);
        if (!terminal_printed) begin
            terminal_printed = 1;
            $display("HDR_BLACKBOX FAIL case=%s sim_time=%0t %s", case_name, $time, reason);
        end
        $fatal(1, "%s", reason);
    endtask

    initial begin
        #20000;
        fail("cycle-gate simulation watchdog");
    end

    function automatic logic [39:0] payload(input int lane, input logic [31:0] seq, input int beat);
        return {8'(lane + 8), seq[15:0], 16'(16'hdea0 + beat)};
    endfunction

    function automatic logic [146:0] token(
        input logic [3:0] code, input logic [31:0] group_id, input logic [31:0] seq,
        input logic [39:0] data, input bit sof, input bit eol
    );
        logic [146:0] result;
        result = '0;
        result[39:0] = data;
        result[40] = sof;
        result[41] = eol;
        result[42] = (code == BAD);
        result[46:43] = code;
        result[78:47] = group_id;
        result[110:79] = seq;
        result[112:111] = 2'b11;
        return result;
    endfunction

    task automatic plan_member(input int lane, input logic [31:0] seq, input bit ok);
        for (int beat = 0; beat < 2; beat++) begin
            raw_plan[lane][raw_planned[lane]] =
                {payload(lane, seq, beat), (beat == 0), (beat == 1), session_id, epoch, seq};
            raw_planned[lane]++;
        end
        source_plan[lane][source_planned[lane]] = {session_id, epoch, seq, ok};
        source_planned[lane]++;
    endtask

    always @(posedge clk) begin : public_scoreboard
        raw_record observed_raw;
        logic [104:0] observed_source;
        if (!rst_n) begin
            for (int lane = 0; lane < 2; lane++) begin
                raw_seen[lane] = 0;
                source_seen[lane] = 0;
                source_held[lane] = 0;
            end
            good_events = 0;
            bad_events = 0;
        end else begin
            for (int lane = 0; lane < 2; lane++) begin
                if (m_valid[lane] === 1'b1) begin
                    observed_raw = {m_data[lane], m_sof[lane], m_eol[lane],
                                    capture_session, capture_epoch, sequence_out[lane]};
                    if (raw_seen[lane] >= raw_planned[lane] ||
                        observed_raw !== raw_plan[lane][raw_seen[lane]] || m_abort[lane] !== 1'b0)
                        fail($sformatf("unexpected RAW lane=%0d beat=%0d seq=%08h data=%010h sof/eol=%b%b",
                                       lane, raw_seen[lane], sequence_out[lane], m_data[lane],
                                       m_sof[lane], m_eol[lane]));
                    raw_seen[lane]++;
                end
                observed_source = {source_session[lane], source_epoch[lane], source_sequence[lane],
                                   source_ok[lane], source_error[lane]};
                if (source_held[lane] &&
                    (source_valid[lane] !== 1'b1 || observed_source !== held_source[lane]))
                    fail($sformatf("SOURCE changed under backpressure lane=%0d", lane));
                source_held[lane] = (source_valid[lane] === 1'b1 && !source_ready[lane]);
                if (source_held[lane]) held_source[lane] = observed_source;
                if (source_valid[lane] === 1'b1 && $time < source_not_before[lane])
                    fail($sformatf("SOURCE timeout fired before one full period lane=%0d", lane));
                if (source_valid[lane] === 1'b1 && source_ready[lane]) begin
                    if (source_seen[lane] >= source_planned[lane] ||
                        observed_source[104:8] !== source_plan[lane][source_seen[lane]])
                        fail($sformatf("unexpected SOURCE lane=%0d seq=%08h cohort=%08h/%08h ok=%b error=%02h",
                                       lane, source_sequence[lane], source_session[lane],
                                       source_epoch[lane], source_ok[lane], source_error[lane]));
                    if (source_ok[lane] && source_error[lane] !== 8'h00)
                        fail($sformatf("positive SOURCE has error lane=%0d", lane));
                    source_seen[lane]++;
                    $display("HDR_SOURCE lane=%0d seq=%08h ok=%b at=%0t", lane,
                             source_sequence[lane], source_ok[lane], $time);
                end
            end
            if (pair_event === 1'b1) begin
                case (pair_ok)
                    1'b1: good_events++;
                    1'b0: bad_events++;
                    default: fail("unknown pair event result");
                endcase
                $display("HDR_PAIR_EVENT ok=%b at=%0t", pair_ok, $time);
            end
        end
    end

    task automatic send_token(input int lane, input logic [146:0] word, output time edge_time);
        @(negedge clk);
        token_in[lane] = word;
        s_valid[lane] = 1;
        for (int cycle = 0; cycle < WAIT_CYCLES; cycle++) begin
            @(posedge clk);
            if (s_ready[lane] === 1'b1) begin
                edge_time = $time;
                if (word[46:43] != RAW)
                    $display("HDR_TOKEN lane=%0d code=%0d group=%08h seq=%08h phase=%0d at=%0t",
                             lane, word[46:43], word[78:47], word[110:79], phase, $time);
                @(negedge clk);
                s_valid[lane] = 0;
                return;
            end
        end
        fail($sformatf("token timeout lane=%0d code=%0d group=%08h", lane, word[46:43], word[78:47]));
    endtask

    task automatic send_event(
        input int lane, input logic [3:0] code, input logic [31:0] group_id, input logic [31:0] seq
    );
        time ignored;
        send_token(lane, token(code, group_id, seq, 0, 0, 0), ignored);
    endtask

    task automatic stream_raw(input int lane, input logic [31:0] group_id, input logic [31:0] seq);
        @(negedge clk);
        s_valid[lane] = 1;
        for (int beat = 0; beat < 2; beat++) begin
            token_in[lane] = token(RAW, group_id, seq, payload(lane, seq, beat), beat == 0, beat == 1);
            @(posedge clk);
            if (s_ready[lane] !== 1'b1)
                fail($sformatf("healthy RAW unexpectedly stalled lane=%0d group=%08h beat=%0d",
                               lane, group_id, beat));
            @(negedge clk);
        end
        s_valid[lane] = 0;
    endtask

    task automatic await_source_valid(input int lane);
        for (int cycle = 0; cycle < WAIT_CYCLES; cycle++) begin
            @(negedge clk);
            if (source_valid[lane] === 1'b1) return;
        end
        fail($sformatf("held SOURCE never arrived lane=%0d", lane));
    endtask

    task automatic await_sources;
        for (int cycle = 0; cycle < WAIT_CYCLES; cycle++) begin
            @(negedge clk);
            if (source_seen[LONG] == source_planned[LONG] &&
                source_seen[SHORT] == source_planned[SHORT]) return;
        end
        fail("SOURCE count did not reach the expected handshakes");
    endtask

    task automatic check_terminals(
        input int good, input int bad, input int reported_bad, input int extra_bad_events = 0
    );
        await_sources();
        for (int cycle = 0; cycle < WAIT_CYCLES; cycle++) begin
            @(negedge clk);
            if (quiet === 1'b1) begin
                repeat (4) @(negedge clk);
                if (raw_seen[LONG] != raw_planned[LONG] || raw_seen[SHORT] != raw_planned[SHORT] ||
                    good_events != good || bad_events < reported_bad ||
                    bad_events > reported_bad + extra_bad_events ||
                    good_pairs !== 32'(good) || bad_pairs !== 32'(bad))
                    fail($sformatf("terminal mismatch RAW=%0d/%0d vs %0d/%0d events=%0d/%0d vs %0d/%0d-%0d counters=%0d/%0d vs %0d/%0d",
                                   raw_seen[LONG], raw_seen[SHORT], raw_planned[LONG], raw_planned[SHORT],
                                   good_events, bad_events, good, reported_bad, reported_bad + extra_bad_events,
                                   good_pairs, bad_pairs, good, bad));
                return;
            end
        end
        fail("gate did not return to quiet after terminal handshakes");
    endtask

    task automatic requalify;
        await_sources();
        stable = 0;
        repeat (3) @(negedge clk);
        stable = 1;
        repeat (3) @(negedge clk);
    endtask

    task automatic start_two(input logic [31:0] group_id, input logic [31:0] seq0, seq1);
        send_event(LONG, FS, group_id, seq0);
        send_event(SHORT, FS, group_id, seq1);
        fork
            stream_raw(LONG, group_id, seq0);
            stream_raw(SHORT, group_id, seq1);
        join
    endtask

    task automatic healthy_group(input logic [31:0] group_id, input logic [31:0] seq0, seq1);
        plan_member(LONG, seq0, 1);
        plan_member(SHORT, seq1, 1);
        start_two(group_id, seq0, seq1);
        fork
            send_event(LONG, FE, group_id, seq0);
            send_event(SHORT, FE, group_id, seq1);
        join
    endtask

    task automatic replay_rejected(input logic [31:0] group_id, input logic [31:0] seq0, seq1);
        time ignored0, ignored1;
        send_event(LONG, FS, group_id, seq0);
        send_event(SHORT, FS, group_id, seq1);
        fork
            begin
                send_token(LONG, token(RAW, group_id, seq0, 40'h345673a1bc, 1, 1), ignored0);
                send_event(LONG, FE, group_id, seq0);
            end
            begin
                send_token(SHORT, token(RAW, group_id, seq1, 40'h95bcaa821f, 1, 1), ignored1);
                send_event(SHORT, FE, group_id, seq1);
            end
        join
    endtask

    task automatic interleaved;
        plan_member(LONG, 11, 1);
        plan_member(SHORT, 91, 1);
        start_two(1, 11, 91);
        source_ready[LONG] = 0;
        send_event(LONG, FE, 1, 11);
        await_source_valid(LONG);
        plan_member(LONG, 12, 1);
        plan_member(SHORT, 92, 1);
        fork
            begin
                send_event(LONG, FS, 2, 12);
                if (source_seen[LONG] != 1)
                    fail("next LONG acquired ingress before old LONG SOURCE retired");
                stream_raw(LONG, 2, 12);
                send_event(LONG, FE, 2, 12);
            end
            begin
                repeat (5) @(negedge clk);
                source_ready[LONG] = 1;
            end
        join
        send_event(SHORT, FE, 1, 91);
        send_event(SHORT, FS, 2, 92);
        stream_raw(SHORT, 2, 92);
        send_event(SHORT, FE, 2, 92);
        check_terminals(2, 0, 0);
    endtask

    task automatic fe_peer_bad;
        time fe_at, bad_at;
        plan_member(LONG, 110, 0);
        plan_member(SHORT, 210, 0);
        start_two(10, 110, 210);
        fork
            send_token(LONG, token(FE, 10, 110, 0, 0, 0), fe_at);
            send_token(SHORT, token(BAD, 10, 210, 0, 0, 0), bad_at);
        join
        if (fe_at != bad_at) fail("fixture did not realize same-edge FE and peer BAD");
        check_terminals(0, 1, 1);
        requalify();

        plan_member(LONG, 111, 1);
        plan_member(SHORT, 211, 0);
        start_two(11, 111, 211);
        source_ready[LONG] = 0;
        send_event(LONG, FE, 11, 111);
        await_source_valid(LONG);
        send_event(SHORT, BAD, 11, 211);
        repeat (5) @(negedge clk);
        source_ready[LONG] = 1;
        check_terminals(0, 2, 2);
        requalify();
        replay_rejected(11, 112, 212);
        healthy_group(12, 113, 213);
        check_terminals(1, 2, 2);
    endtask

    task automatic fault_wrap;
        plan_member(LONG, 300, 1);
        plan_member(SHORT, 400, 0);
        start_two(32'hfffffffe, 300, 400);
        send_event(LONG, FE, 32'hfffffffe, 300);
        while (source_seen[LONG] == 0) @(negedge clk);
        plan_member(LONG, 301, 0);
        send_event(LONG, FS, 32'hffffffff, 301);
        stream_raw(LONG, 32'hffffffff, 301);
        source_ready = 0;
        fault = 1;
        @(negedge clk);
        fault = 0;
        fork
            await_source_valid(LONG);
            await_source_valid(SHORT);
        join
        repeat (4) @(negedge clk);
        source_ready = 2'b11;
        check_terminals(0, 2, 1);
        requalify();
        replay_rejected(32'hfffffffe, 302, 401);
        replay_rejected(32'hffffffff, 303, 402);
        healthy_group(1, 304, 403);
        check_terminals(1, 2, 1);
    endtask

    task automatic clear_plan;
        for (int lane = 0; lane < 2; lane++) begin
            raw_planned[lane] = 0;
            source_planned[lane] = 0;
            source_not_before[lane] = 0;
        end
    endtask

    task automatic timeout_reset;
        time fs_at;
        plan_member(LONG, 510, 0);
        while (phase != TIMEOUT - 4) @(posedge clk);
        send_token(LONG, token(FS, 90, 510, 0, 0, 0), fs_at);
        source_not_before[LONG] = fs_at + 8 * TIMEOUT;
        stream_raw(LONG, 90, 510);
        check_terminals(0, 1, 1);
        source_not_before[LONG] = 0;
        requalify();
        replay_rejected(90, 511, 610);
        healthy_group(91, 512, 611);
        check_terminals(1, 1, 1);

        rst_n = 0;
        stable = 0;
        session_id++;
        epoch++;
        clear_plan();
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        stable = 1;
        healthy_group(5, 10, 20);
        check_terminals(1, 0, 0);
    endtask

    task automatic timeout_peer_bad;
        localparam logic [31:0] OLD_GROUP = 32'hfffffff0;
        localparam logic [31:0] NEW_GROUP = 32'hfffffff2;
        time fs_at, bad_at, expires;
        plan_member(LONG, 710, 1);
        plan_member(SHORT, 810, 0);
        send_token(LONG, token(FS, OLD_GROUP, 710, 0, 0, 0), fs_at);
        send_event(SHORT, FS, OLD_GROUP, 810);
        fork
            stream_raw(LONG, OLD_GROUP, 710);
            stream_raw(SHORT, OLD_GROUP, 810);
        join
        send_event(LONG, FE, OLD_GROUP, 710);
        while (source_seen[LONG] == 0) @(negedge clk);

        plan_member(LONG, 711, 0);
        send_event(LONG, FS, NEW_GROUP, 711);
        stream_raw(LONG, NEW_GROUP, 711);
        expires = fs_at + 8 * TIMEOUT;
        source_not_before[SHORT] = expires;
        // Present BAD at the full-period deadline and keep it valid until READY.
        while ($time + 12 < expires) @(negedge clk);
        if ($time + 12 != expires) fail("fixture missed the older group timeout edge");
        send_token(LONG, token(BAD, NEW_GROUP, 711, 0, 0, 0), bad_at);
        $display("HDR_TIMEOUT_OVERLAP deadline=%0t bad_accepted=%0t", expires, bad_at);
        // The one-bit pair event can report the two bad contexts together.
        check_terminals(0, 2, 1, 1);
        requalify();
        replay_rejected(OLD_GROUP, 712, 811);
        replay_rejected(NEW_GROUP, 713, 812);
        healthy_group(1, 714, 813);
        check_terminals(1, 2, 1, 1);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) begin
            case_name = "missing";
            fail("specify +CASE");
        end
        clear_plan();
        token_in[LONG] = 0;
        token_in[SHORT] = 0;
        repeat (8) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        stable = 1;
        case (case_name)
            "interleaved": interleaved();
            "fe_peer_bad": fe_peer_bad();
            "fault_wrap": fault_wrap();
            "timeout_reset": timeout_reset();
            "timeout_peer_bad": timeout_peer_bad();
            default: fail("unknown test case");
        endcase
        terminal_printed = 1;
        $display("HDR_BLACKBOX PASS case=%s RAW=%0d/%0d SOURCE=%0d/%0d events=%0d/%0d",
                 case_name, raw_seen[LONG], raw_seen[SHORT], source_seen[LONG], source_seen[SHORT],
                 good_events, bad_events);
        $finish;
    end
endmodule
