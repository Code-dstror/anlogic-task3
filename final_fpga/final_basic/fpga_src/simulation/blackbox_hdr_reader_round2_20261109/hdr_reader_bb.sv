`timescale 1ns/1ps
`default_nettype none

module hdr_reader_bb;
    localparam integer WIDTH = 68;
    localparam integer HEIGHT = 63;
    localparam integer GROUPS_PER_LINE = WIDTH / 4;
    localparam integer GROUPS = GROUPS_PER_LINE * HEIGHT;
    localparam integer FRAME_BYTES = GROUPS * 5;
    localparam integer WORDS = (FRAME_BYTES + 15) / 16;
    localparam integer PADDED_BYTES = WORDS * 16;
    localparam integer MAX_COMMANDS = 2 * WORDS;
    localparam integer CASE_WATCHDOG_EDGES = 200000;

    bit clk = 0;
    always #5 clk = ~clk;

    bit rst_n = 0;
    bit start_valid = 0;
    bit pair_bank = 0;
    bit pair_camera = 0;
    wire start_ready;
    bit cancel = 0;
    wire [55:0] raw;
    wire [3:0] motion;
    wire raw_valid, sof, eol, eof;
    wire [31:0] index;
    bit raw_ready = 1;
    wire result_valid, result_ok;
    bit result_ready = 1;
    wire read_quiet, protocol_fault;
    wire [9:0] long_occupancy, short_occupancy;
    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid;
    bit hold_ar = 0;
    wire arready = !hold_ar;
    logic [3:0] rid = 0;
    logic [127:0] rdata = 0;
    logic rlast = 0;
    logic rvalid = 0;
    wire rready;

    PH1_PHY_GSR PH1_PHY_GSR();
    seed12_hdr_reader_carrier #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (
        .i_clk(clk), .i_identity_rst_n(rst_n),
        .i_start_valid(start_valid), .i_pair_bank(pair_bank), .i_pair_camera(pair_camera),
        .o_start_ready(start_ready), .i_ratio_log2(3'd4),
        .i_black_long(10'd50), .i_black_short(10'd50),
        .i_motion_base(14'd64), .i_motion_shift(4'd3), .i_cancel(cancel),
        .m_raw(raw), .m_motion(motion), .m_valid(raw_valid), .m_sof(sof),
        .m_eol(eol), .m_eof(eof), .m_index(index), .m_ready(raw_ready),
        .o_result_valid(result_valid), .o_result_ok(result_ok), .i_result_ready(result_ready),
        .o_read_quiet(read_quiet), .o_protocol_fault(protocol_fault),
        .o_long_occupancy(long_occupancy), .o_short_occupancy(short_occupancy),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arvalid(arvalid),
        .m_axi_arready(arready), .m_axi_rid(rid), .m_axi_rdata(rdata),
        .m_axi_rresp(2'b00), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
        .m_axi_rready(rready)
    );

    byte unsigned memory [0:1][0:PADDED_BYTES-1];
    int command_member [0:MAX_COMMANDS-1];
    int command_offset [0:MAX_COMMANDS-1];
    int command_beats [0:MAX_COMMANDS-1];
    int command_edge [0:MAX_COMMANDS-1];
    bit command_offered [0:MAX_COMMANDS-1];
    int command_tail = 0;
    int command_head = 0;
    int beat_index = 0;
    bit r_accepted = 0;
    int frame_base [0:1];
    int next_offset [0:1];
    int ar_member [0:1];

    string label = "startup";
    int seed;
    int latency;
    bit expect_success;
    int watchdog_start = 0;
    bit watchdog_enabled = 1;
    int cycle = 0;
    int start_edge;
    bit active = 0;
    bit completed = 0;
    bit cancel_seen = 0;
    bit promised_ar = 0;
    int groups_seen;
    int moving_groups;
    int r_beats;
    int peak_long, peak_short;
    int raw_stall_edges, result_stall_edges, ar_stall_edges;
    int first_r_min, first_r_max;
    bit [1:0] page_splits, frame_tails;
    bit held_ar, held_raw, held_result;
    logic [44:0] held_ar_fields;
    logic [94:0] held_raw_fields;
    logic held_result_ok;
    int trace;
    int frame_file;

    task automatic fail(input string reason);
        $fatal(1, "BB_FAIL case=%s edge=%0d %s", label, cycle, reason);
    endtask

    function automatic int stimulus_sample(input int member, group, lane, pattern);
        int long_sample;
        int short_sample;
        case (group % 5)
            0: begin
                long_sample = 70 + (31*group + 11*lane + 17*pattern) % 630;
                short_sample = 50 + (long_sample - 42) / 16;
            end
            1: begin
                long_sample = 896 + (7*group + 13*lane + 3*pattern) % 128;
                short_sample = 180 + (11*group + 19*lane + 23*pattern) % 810;
            end
            2: begin
                long_sample = 769 + (7*group + 23*lane + 5*pattern) % 127;
                short_sample = 51 + (long_sample - 50) / 16;
            end
            3: begin
                long_sample = 120 + (17*group + 41*lane + 13*pattern) % 730;
                if (lane == (group + pattern) % 4)
                    short_sample = 1000 + (group + pattern) % 24;
                else
                    short_sample = (19*group + 101*lane + 41*pattern) % 1024;
            end
            default: begin
                long_sample = (group + lane + pattern) % 67;
                short_sample = (group + 3*lane + pattern) % 55;
            end
        endcase
        return member == 0 ? long_sample : short_sample;
    endfunction

    task automatic fill_memory(input int pattern);
        logic [39:0] packed_group;
        for (int member = 0; member < 2; member++) begin
            for (int group = 0; group < GROUPS; group++) begin
                for (int lane = 0; lane < 4; lane++)
                    packed_group[10*lane +: 10] = stimulus_sample(member, group, lane, pattern);
                for (int byte_index = 0; byte_index < 5; byte_index++)
                    memory[member][5*group + byte_index] = packed_group[8*byte_index +: 8];
            end
            for (int offset = FRAME_BYTES; offset < PADDED_BYTES; offset++)
                memory[member][offset] = 8'hd5 ^ offset ^ (member*19) ^ pattern;
        end
    endtask

    function automatic int subtract_black(input int sample);
        return sample > 50 ? sample - 50 : 0;
    endfunction

    task automatic expected_output(input int group, output logic [55:0] expected_raw,
                                   output logic [3:0] expected_motion);
        int corrected_long [0:3];
        int corrected_short [0:3];
        int weight [0:3];
        int long_sample, short_sample, difference;
        bit moving;
        moving = 0;
        for (int lane = 0; lane < 4; lane++) begin
            long_sample = stimulus_sample(0, group, lane, seed);
            short_sample = stimulus_sample(1, group, lane, seed);
            corrected_long[lane] = subtract_black(long_sample);
            corrected_short[lane] = 16 * subtract_black(short_sample);
            if (long_sample < 768)
                weight[lane] = 0;
            else if (long_sample >= 896)
                weight[lane] = 16;
            else
                weight[lane] = (long_sample - 768) / 8;
            difference = corrected_long[lane] - corrected_short[lane];
            if (difference < 0)
                difference = -difference;
            if (long_sample < 896 && short_sample > 54 &&
                difference > 64 + corrected_long[lane] / 8)
                moving = 1;
        end
        expected_motion = moving ? 4'hf : 4'h0;
        for (int lane = 0; lane < 4; lane++) begin
            if (moving)
                expected_raw[14*lane +: 14] = corrected_short[lane];
            else
                expected_raw[14*lane +: 14] = ((16-weight[lane]) * corrected_long[lane] +
                                              weight[lane] * corrected_short[lane] + 8) / 16;
        end
    endtask

    task automatic drive_phase;
        @(negedge clk);
        #1;
    endtask

    task automatic begin_job(input string name, input int pattern, first_latency,
                             input bit camera, bank, want_success,
                             input bit hold_output, hold_result, hold_command);
        drive_phase();
        label = name;
        watchdog_start = cycle;
        watchdog_enabled = 1;
        seed = pattern;
        latency = first_latency;
        expect_success = want_success;
        frame_base[0] = 'h02000000 + (4*int'(camera) + 2*int'(bank)) * 'h01000000;
        frame_base[1] = frame_base[0] + 'h01000000;
        fill_memory(pattern);
        while (start_ready !== 1'b1)
            drive_phase();
        completed = 0;
        pair_camera = camera;
        pair_bank = bank;
        raw_ready = !hold_output;
        result_ready = !hold_result;
        hold_ar = hold_command;
        frame_file = $fopen({name, ".pixels"}, "w");
        if (frame_file == 0)
            fail("opening output evidence");
        start_valid = 1;
        while (!active)
            drive_phase();
        start_valid = 0;
    endtask

    task automatic finish_job;
        while (!completed)
            drive_phase();
        repeat (12)
            drive_phase();
        watchdog_enabled = 0;
    endtask

    initial begin
        trace = $fopen("axi.tsv", "w");
        if (trace == 0)
            fail("opening AXI trace");
        $fdisplay(trace, "case\tevent\tedge\tmember\tbyte_offset\tbeats");
        repeat (10)
            drive_phase();
        rst_n = 1;

        begin_job("first", 5, 32, 0, 0, 1, 0, 0, 0);
        finish_job();

        begin_job("full", 17, 1, 1, 1, 1, 1, 1, 0);
        repeat (4096)
            drive_phase();
        raw_ready = 1;
        while (groups_seen < 819 && !completed)
            drive_phase();
        raw_ready = 0;
        repeat (11)
            drive_phase();
        raw_ready = 1;
        while (result_valid !== 1'b1)
            drive_phase();
        repeat (9)
            drive_phase();
        result_ready = 1;
        finish_job();

        begin_job("cancel", 37, 32, 0, 1, 0, 0, 0, 1);
        while (ar_stall_edges < 3)
            drive_phase();
        cancel = 1;
        repeat (4)
            drive_phase();
        hold_ar = 0;
        while (!completed)
            drive_phase();
        cancel = 0;
        finish_job();

        begin_job("recovery", 53, 32, 1, 0, 1, 0, 0, 0);
        finish_job();
        $fclose(trace);
        $display("BB_PASS cases=4 geometry=%0dx%0d watchdog_edges_per_case=%0d",
                 WIDTH, HEIGHT, CASE_WATCHDOG_EDGES);
        $finish;
    end

    always @(negedge clk) begin : responder
        int offset;
        int member;
        if (!rst_n) begin
            rvalid = 0;
        end else if (!rvalid || r_accepted) begin
            rvalid = command_head < command_tail &&
                     cycle + 1 >= command_edge[command_head] + latency;
            if (rvalid) begin
                member = command_member[command_head];
                offset = command_offset[command_head] + 16*beat_index;
                rid = 1;
                rlast = beat_index == command_beats[command_head] - 1;
                for (int byte_index = 0; byte_index < 16; byte_index++)
                    rdata[8*byte_index +: 8] = memory[member][offset + byte_index];
            end
        end
    end

    always @(posedge clk) begin : scoreboard
        int member, offset, length, delay_edges;
        logic [55:0] oracle_raw;
        logic [3:0] oracle_motion;
        logic oracle_sof, oracle_eol, oracle_eof;
        cycle++;
        if (watchdog_enabled && cycle - watchdog_start > CASE_WATCHDOG_EDGES)
            fail($sformatf("watchdog start=%0b active=%0b output_groups=%0d accepted_AR=%0d finished_bursts=%0d result_valid=%0b quiet=%0b",
                           start_ready, active, groups_seen, command_tail, command_head,
                           result_valid, read_quiet));
        if (rst_n) begin
            if (protocol_fault !== 1'b0)
                fail("protocol fault asserted or unknown");
            if ($isunknown({long_occupancy, short_occupancy}) ||
                long_occupancy > 512 || short_occupancy > 512)
                fail($sformatf("occupancy out of range long=%0d short=%0d",
                               long_occupancy, short_occupancy));

            if (start_valid && start_ready) begin
                if (active)
                    fail("overlapping START");
                active = 1;
                start_edge = cycle;
                command_tail = 0;
                command_head = 0;
                beat_index = 0;
                groups_seen = 0;
                moving_groups = 0;
                r_beats = 0;
                peak_long = 0;
                peak_short = 0;
                raw_stall_edges = 0;
                result_stall_edges = 0;
                ar_stall_edges = 0;
                first_r_min = CASE_WATCHDOG_EDGES;
                first_r_max = 0;
                page_splits = 0;
                frame_tails = 0;
                cancel_seen = 0;
                promised_ar = 0;
                for (int exposure = 0; exposure < 2; exposure++) begin
                    next_offset[exposure] = 0;
                    ar_member[exposure] = 0;
                end
                $display("BB_START case=%s edge=%0d camera=%0b bank=%0b pattern=%0d latency_min=%0d",
                         label, cycle, pair_camera, pair_bank, seed, latency);
            end

            if (active) begin
                if (long_occupancy > peak_long)
                    peak_long = long_occupancy;
                if (short_occupancy > peak_short)
                    peak_short = short_occupancy;
            end

            if (cancel && active && !cancel_seen) begin
                if (expect_success || arvalid !== 1'b1 || arready !== 1'b0 || !held_ar)
                    fail("cancel injection missed a previously held AR offer");
                cancel_seen = 1;
                promised_ar = 1;
                $display("BB_CANCEL case=%s edge=%0d held_addr=0x%07x held_beats=%0d",
                         label, cycle, araddr, int'(arlen) + 1);
            end

            if (held_ar && (arvalid !== 1'b1 ||
                {arid, araddr, arlen, arsize, arburst} !== held_ar_fields))
                fail("AR offer changed while stalled");
            held_ar = arvalid && !arready;
            if (held_ar) begin
                ar_stall_edges++;
                held_ar_fields = {arid, araddr, arlen, arsize, arburst};
            end
            if (arvalid) begin
                if (!active || (cancel_seen && !promised_ar))
                    fail("new AR offer after cancellation or outside a job");
                if (arready) begin
                    if ($isunknown({arid, araddr, arlen, arsize, arburst}) ||
                        arid != 4'd1 || arsize != 3'd4 || arburst != 2'b01 ||
                        araddr[3:0] != 0 || arlen >= 16)
                        fail($sformatf("illegal AR addr=0x%07x len=%0d id=%0d size=%0d burst=%0d",
                                       araddr, arlen, arid, arsize, arburst));
                    length = int'(arlen) + 1;
                    if (int'(araddr[11:0]) + 16*length > 4096)
                        fail("AR crosses a 4 KiB boundary");
                    if (araddr >= frame_base[0] && araddr < frame_base[0] + PADDED_BYTES)
                        member = 0;
                    else if (araddr >= frame_base[1] && araddr < frame_base[1] + PADDED_BYTES)
                        member = 1;
                    else
                        fail($sformatf("AR outside either expected exposure addr=0x%07x", araddr));
                    offset = int'(araddr) - frame_base[member];
                    if (offset != next_offset[member] || offset + 16*length > PADDED_BYTES)
                        fail($sformatf("AR coverage member=%0d offset=%0d next=%0d beats=%0d",
                                       member, offset, next_offset[member], length));
                    next_offset[member] = offset + 16*length;
                    if (offset == 4096)
                        page_splits[member] = 1;
                    if (next_offset[member] == PADDED_BYTES)
                        frame_tails[member] = 1;
                    if (command_tail >= MAX_COMMANDS)
                        fail("AR count exceeds all legal bursts");
                    command_member[command_tail] = member;
                    command_offset[command_tail] = offset;
                    command_beats[command_tail] = length;
                    command_edge[command_tail] = cycle;
                    command_offered[command_tail] = 0;
                    command_tail++;
                    ar_member[member]++;
                    if (cancel_seen)
                        promised_ar = 0;
                    $fdisplay(trace, "%s\tAR\t%0d\t%0d\t%0d\t%0d",
                              label, cycle, member, offset, length);
                end
            end

            if (rvalid && !command_offered[command_head]) begin
                if (beat_index != 0 || command_head >= command_tail)
                    fail("responder offered an untracked first beat");
                command_offered[command_head] = 1;
                delay_edges = cycle - command_edge[command_head];
                if (delay_edges < latency)
                    fail("responder offered a beat before its latency floor");
                if (delay_edges < first_r_min)
                    first_r_min = delay_edges;
                if (delay_edges > first_r_max)
                    first_r_max = delay_edges;
                $fdisplay(trace, "%s\tR_FIRST\t%0d\t%0d\t%0d\t%0d",
                          label, cycle, command_member[command_head],
                          command_offset[command_head], command_beats[command_head]);
            end
            if (rvalid && $isunknown(rready))
                fail("RREADY unknown during an offered read beat");
            r_accepted = rvalid && rready;
            if (r_accepted) begin
                r_beats++;
                if (rlast) begin
                    $fdisplay(trace, "%s\tR_LAST\t%0d\t%0d\t%0d\t%0d",
                              label, cycle, command_member[command_head],
                              command_offset[command_head], command_beats[command_head]);
                    command_head++;
                    beat_index = 0;
                end else begin
                    beat_index++;
                end
            end

            if (held_raw && (raw_valid !== 1'b1 ||
                {raw, motion, index, sof, eol, eof} !== held_raw_fields))
                fail("output offer changed while stalled");
            held_raw = raw_valid && !raw_ready;
            if (held_raw) begin
                held_raw_fields = {raw, motion, index, sof, eol, eof};
                raw_stall_edges++;
            end
            if (raw_valid) begin
                if (!active || groups_seen >= GROUPS)
                    fail("extra output offer outside its expected frame");
                if (raw_ready) begin
                    expected_output(groups_seen, oracle_raw, oracle_motion);
                    oracle_sof = groups_seen == 0;
                    oracle_eol = (groups_seen + 1) % GROUPS_PER_LINE == 0;
                    oracle_eof = groups_seen == GROUPS - 1;
                    if (index !== groups_seen || {sof, eol, eof} !== {oracle_sof, oracle_eol, oracle_eof} ||
                        raw !== oracle_raw || motion !== oracle_motion)
                        fail($sformatf("output group=%0d index=%0d raw=%014x expected=%014x motion=%x expected=%x markers=%b%b%b expected=%b%b%b",
                                       groups_seen, index, raw, oracle_raw, motion, oracle_motion,
                                       sof, eol, eof, oracle_sof, oracle_eol, oracle_eof));
                    $fdisplay(frame_file, "%04d %014x %x %b%b%b", index, raw, motion, sof, eol, eof);
                    groups_seen++;
                    if (motion != 0)
                        moving_groups++;
                end
            end

            if (held_result && (result_valid !== 1'b1 || result_ok !== held_result_ok))
                fail("result offer changed while stalled");
            held_result = result_valid && !result_ready;
            if (held_result) begin
                held_result_ok = result_ok;
                result_stall_edges++;
            end
            if (result_valid) begin
                if (!active || completed)
                    fail("extra result outside its job");
                if (result_ready) begin
                    if (read_quiet !== 1'b1 || command_head != command_tail || promised_ar)
                        fail("terminal result before the accepted reads and promised AR drained");
                    if (result_ok !== expect_success)
                        fail($sformatf("result success=%b expected=%b", result_ok, expect_success));
                    if (expect_success && (groups_seen != GROUPS ||
                        page_splits != 2'b11 || frame_tails != 2'b11 || r_beats != 2*WORDS))
                        fail($sformatf("terminal coverage groups=%0d page_splits=%b frame_tails=%b R_beats=%0d",
                                       groups_seen, page_splits, frame_tails, r_beats));
                    if (label == "full" && (raw_stall_edges == 0 || result_stall_edges < 8))
                        fail("output/result stall did not exercise a valid offer");
                    if (!expect_success && (!cancel_seen || command_tail != 1 ||
                        r_beats != command_beats[0] || groups_seen != 0))
                        fail("clean cancel did not drain its single promised AR and produce zero groups");
                    $fclose(frame_file);
                    active = 0;
                    completed = 1;
                    $display("BB_RESULT case=%s ok=%0b start_edge=%0d result_edge=%0d cycles=%0d ar=%0d ar_long=%0d ar_short=%0d r_beats=%0d groups=%0d moving=%0d peak_long=%0d peak_short=%0d page_splits=%b tails=%b r_latency_min=%0d r_latency_max=%0d output_stall=%0d result_stall=%0d ar_stall=%0d quiet=%0b fault=%0b",
                             label, result_ok, start_edge, cycle, cycle-start_edge, command_tail,
                             ar_member[0], ar_member[1], r_beats, groups_seen, moving_groups,
                             peak_long, peak_short, page_splits, frame_tails, first_r_min,
                             first_r_max, raw_stall_edges, result_stall_edges, ar_stall_edges,
                             read_quiet, protocol_fault);
                end
            end
        end
    end
endmodule

`default_nettype wire
