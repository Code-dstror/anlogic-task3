`timescale 1ns/1ps

module tb_field_hdr;
    localparam integer WIDTH = 16;
    localparam integer HEIGHT = 4;
    localparam integer RESPONSE_CYCLES = 192;
    localparam logic [31:0] SESSION = 32'h13579bdf;
    localparam logic [31:0] FIRST_EPOCH = 32'h00008015;

    logic clk = 0;
    logic rst_n = 0;
    logic stop = 0;
    logic transport_fault = 0;
    logic [63:0] now_ns = 64'd2_001_000_000;
    logic config_valid = 0;
    wire config_ready, config_error;
    logic [31:0] cfg_session = SESSION;
    logic [31:0] cfg_epoch = FIRST_EPOCH;
    logic [31:0] cfg_delta = 32'd50_000_000;
    logic [31:0] cfg_wait = 32'd100_000_000;
    logic [31:0] cfg_age = 32'd1_000_000_000;
    logic [2:0] cfg_ratio = 3'd4;
    logic cfg_hdr = 1;
    logic [767:0] frames = 0;
    logic [1:0] begin_valid = 0;
    logic [1:0] member = 0;
    wire [1:0] begin_ready, accepted;
    wire [3:0] capture_slots;
    wire [31:0] camera0_generation;
    wire [63:0] camera0_lease;
    logic [3:0] finish_valid = 0;
    logic [3:0] finish_ok = 0;
    wire [3:0] finish_ready;
    wire [1:0] pair_valid, pair_bank;
    wire [127:0] pair_ids;
    logic [1:0] pair_take = 0;
    logic [1:0] release_valid = 0;
    logic release_bank = 0;
    logic [63:0] release_id = 0;
    logic read_quiet = 1;
    logic ticket_released = 1;
    logic [1:0] write_quiet = 2'b11;
    wire [1:0] release_ready;
    logic [1:0] ext_req = 0;
    logic [1:0] ext_slot = 0;
    logic [1:0] ext_consume = 0;
    wire [1:0] ext_ready, ext_valid, ext_last;
    wire [63:0] ext_data;
    wire [7:0] ext_word;
    wire [1:0] empty;
    wire fault;

    hdr_eye_shared #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (
        .clk(clk), .rst_n(rst_n), .stop(stop), .transport_fault(transport_fault),
        .now_ns(now_ns), .config_valid(config_valid), .config_ready(config_ready),
        .config_error(config_error), .cfg_session(cfg_session), .cfg_epoch(cfg_epoch),
        .cfg_delta(cfg_delta), .cfg_wait(cfg_wait), .cfg_age(cfg_age), .cfg_ratio(cfg_ratio),
        .cfg_hdr(cfg_hdr), .frames(frames), .begin_valid(begin_valid), .member(member),
        .begin_ready(begin_ready), .accepted(accepted), .capture_slots(capture_slots),
        .camera0_generation(camera0_generation), .camera0_lease(camera0_lease),
        .finish_valid(finish_valid), .finish_ok(finish_ok), .finish_ready(finish_ready),
        .pair_valid(pair_valid), .pair_bank(pair_bank), .pair_ids(pair_ids), .pair_take(pair_take),
        .release_valid(release_valid), .release_bank(release_bank), .release_id(release_id),
        .read_quiet(read_quiet), .ticket_released(ticket_released), .write_quiet(write_quiet),
        .release_ready(release_ready), .ext_req(ext_req), .ext_slot(ext_slot),
        .ext_consume(ext_consume), .ext_ready(ext_ready), .ext_valid(ext_valid),
        .ext_last(ext_last), .ext_data(ext_data), .ext_word(ext_word), .empty(empty), .fault(fault)
    );

    string case_name;
    bit terminal_printed = 0;
    bit [3:0] writer_pending = 0;
    bit job_borrowed = 0;
    integer accepted_count[2];
    integer rejected_count[2];
    integer taken_count[2];
    integer retired_count[2];
    logic [63:0] seen_pair_ids[2][16];
    logic [31:0] left_long_generation[2];
    logic [63:0] left_long_lease[2];

    always #4 clk = !clk;
    always @(negedge clk) now_ns = now_ns + 8;

    task automatic fail(input string reason);
        if (!terminal_printed) begin
            terminal_printed = 1;
            $display("HDR_BLACKBOX FAIL case=%s time_ns=%0d %s", case_name, now_ns, reason);
        end
        $fatal(1, "%s", reason);
    endtask

    initial begin
        #50000;
        fail("simulation watchdog");
    end

    function automatic logic [31:0] sequence_for(input bit role, input integer ordinal);
        return (role ? 32'd500 : 32'd100) + 32'(ordinal);
    endfunction

    function automatic logic [63:0] timestamp_for(input bit role, input integer ordinal);
        return 64'd2_000_000_000 + 64'(ordinal) * 1000 + (role ? 80 : 0);
    endfunction

    function automatic logic [383:0] descriptor(
        input int eye, input bit role, input logic [31:0] group_id, input int ordinal
    );
        logic [383:0] result;
        result = '0;
        result[0] = 1;
        result[2:1] = role ? 2'd2 : 2'd1;
        result[3] = 1;
        result[4] = 1'(eye);
        result[76:45] = SESSION;
        result[108:77] = sequence_for(role, ordinal);
        result[140:109] = cfg_epoch;
        result[204:141] = timestamp_for(role, ordinal);
        result[220:205] = 16'(WIDTH);
        result[236:221] = 16'(HEIGHT);
        result[238:237] = 2'd1;
        result[270:239] = 32'h56a3d02f;
        result[302:271] = role ? 32'd200 : 32'd3200;
        result[334:303] = 32'd256;
        result[366:335] = group_id;
        return result;
    endfunction

    task automatic configure(input logic [31:0] epoch);
        @(negedge clk);
        cfg_epoch = epoch;
        config_valid = 1;
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (config_ready === 1'b1) begin
                if (config_error !== 1'b0)
                    fail("legal configuration signaled error on its handshake");
                @(negedge clk);
                if (config_error !== 1'b0)
                    fail("legal configuration signaled error after its handshake");
                config_valid = 0;
                return;
            end
        end
        fail("configuration handshake timeout");
    endtask

    task automatic present_begin(
        input int eye, input bit role, input logic [31:0] group_id, input int ordinal
    );
        if (writer_pending[eye*2 + int'(role)])
            fail("BFM attempted to reuse a writer before FINISH");
        frames[eye*384+:384] = descriptor(eye, role, group_id, ordinal);
        member[eye] = role;
        begin_valid[eye] = 1;
    endtask

    task automatic sample_begin(
        input int eye, input bit role, input logic [31:0] group_id,
        input bit should_accept, output bit bank
    );
        logic [1:0] slot;
        slot = capture_slots[eye*2+:2];
        $display("HDR_BEGIN eye=%0d role=%0d group=%08h accepted=%b slot=%b now_ns=%0d",
                 eye, role, group_id, accepted[eye], slot, now_ns);
        if (accepted[eye] !== should_accept)
            fail($sformatf("BEGIN eye=%0d role=%0d group=%08h expected_accept=%0d observed=%b",
                           eye, role, group_id, should_accept, accepted[eye]));
        bank = 0;
        if (should_accept) begin
            if ((slot[0] !== role) || $isunknown(slot[1]))
                fail($sformatf("BEGIN assigned invalid capture slot %b", slot));
            bank = slot[1];
            writer_pending[eye*2 + int'(role)] = 1;
            accepted_count[eye]++;
            if (eye == 0 && role == 0) begin
                if ($isunknown(camera0_generation) || $isunknown(camera0_lease))
                    fail("accepted camera0 identity contains unknown bits");
                left_long_generation[bank] = camera0_generation;
                left_long_lease[bank] = camera0_lease;
            end
        end else begin
            rejected_count[eye]++;
        end
    endtask

    task automatic offer_begin(
        input int eye, input bit role, input logic [31:0] group_id, input int ordinal,
        input bit should_accept, output bit bank
    );
        @(negedge clk);
        present_begin(eye, role, group_id, ordinal);
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (begin_ready[eye] === 1'b1) begin
                sample_begin(eye, role, group_id, should_accept, bank);
                @(negedge clk);
                begin_valid[eye] = 0;
                return;
            end
        end
        fail($sformatf("BEGIN timeout eye=%0d role=%0d group=%08h", eye, role, group_id));
    endtask

    task automatic present_finish(input int eye, input bit role, input bit ok);
        int lane;
        lane = eye*2 + int'(role);
        if (!writer_pending[lane])
            fail("BFM attempted FINISH without an accepted BEGIN");
        finish_valid[lane] = 1;
        finish_ok[lane] = ok;
    endtask

    task automatic sample_finish(input int eye, input bit role);
        int lane;
        lane = eye*2 + int'(role);
        $display("HDR_FINISH eye=%0d role=%0d ok=%0d now_ns=%0d",
                 eye, role, finish_ok[lane], now_ns);
        writer_pending[lane] = 0;
    endtask

    task automatic finish_member(input int eye, input bit role, input bit ok);
        int lane;
        lane = eye*2 + int'(role);
        @(negedge clk);
        present_finish(eye, role, ok);
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (finish_ready[lane] === 1'b1) begin
                sample_finish(eye, role);
                @(negedge clk);
                finish_valid[lane] = 0;
                return;
            end
        end
        fail($sformatf("FINISH timeout eye=%0d role=%0d", eye, role));
    endtask

    task automatic complete_group(
        input int eye, input bit first_role, input logic [31:0] group_id, input int ordinal,
        output bit bank
    );
        bit other_bank;
        offer_begin(eye, first_role, group_id, ordinal, 1, bank);
        offer_begin(eye, !first_role, group_id, ordinal, 1, other_bank);
        if (bank != other_bank)
            fail($sformatf("exposures assigned different banks eye=%0d group=%08h", eye, group_id));
        finish_member(eye, !first_role, 1);
        finish_member(eye, first_role, 1);
    endtask

    task automatic no_pair(input int eye, input int cycles);
        repeat (cycles) begin
            @(posedge clk);
            if (pair_valid[eye] !== 1'b0)
                fail($sformatf("unexpected pair offer eye=%0d", eye));
        end
    endtask

    task automatic take_job(
        input int eye, input bit expected_bank, input int stall_cycles, output logic [63:0] id
    );
        if (job_borrowed)
            fail("BFM attempted to borrow two global consumer jobs");
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(negedge clk);
            if (pair_valid[eye] === 1'b1) begin
                id = pair_ids[eye*64+:64];
                if ($isunknown(id) || id == 0 || pair_bank[eye] !== expected_bank)
                    fail($sformatf("wrong pair offer eye=%0d expected_bank=%0d bank=%b id=%016h",
                                   eye, expected_bank, pair_bank[eye], id));
                for (int previous = 0; previous < taken_count[eye]; previous++)
                    if (seen_pair_ids[eye][previous] == id)
                        fail($sformatf("pair identity reused eye=%0d id=%016h", eye, id));
                repeat (stall_cycles) begin
                    @(posedge clk);
                    if (pair_valid[eye] !== 1'b1 || pair_bank[eye] !== expected_bank ||
                        pair_ids[eye*64+:64] !== id)
                        fail($sformatf("pair changed under backpressure eye=%0d", eye));
                end
                if (stall_cycles > 0)
                    @(negedge clk);
                pair_take[eye] = 1;
                @(posedge clk);
                if (pair_valid[eye] !== 1'b1 || pair_bank[eye] !== expected_bank ||
                    pair_ids[eye*64+:64] !== id)
                    fail("pair offer changed at TAKE");
                seen_pair_ids[eye][taken_count[eye]] = id;
                taken_count[eye]++;
                job_borrowed = 1;
                $display("HDR_TAKE eye=%0d bank=%0d id=%016h now_ns=%0d",
                         eye, expected_bank, id, now_ns);
                @(negedge clk);
                pair_take[eye] = 0;
                return;
            end
        end
        fail($sformatf("pair offer timeout eye=%0d bank=%0d", eye, expected_bank));
    endtask

    task automatic check_directory_word(
        input int eye, input bit bank, input int word_index, input logic [31:0] data,
        input logic [31:0] group_id, input int ordinal
    );
        logic [63:0] long_time;
        long_time = timestamp_for(0, ordinal);
        case (word_index)
            0: if (data[4] !== 1'(eye) || data[2:1] !== 2'd1)
                fail($sformatf("wrong directory eye/role eye=%0d word0=%08h", eye, data));
            1: if (eye == 0 && data !== left_long_generation[bank])
                fail("directory generation differs from LONG BEGIN identity");
            2: if (data !== SESSION) fail("wrong directory session");
            3: if (data !== sequence_for(0, ordinal)) fail("wrong directory LONG sequence");
            4: if (data !== cfg_epoch) fail("wrong directory epoch");
            5: if (data !== long_time[31:0]) fail("wrong directory time low");
            6: if (data !== long_time[63:32]) fail("wrong directory time high");
            7: if (data !== {16'(HEIGHT), 16'(WIDTH)}) fail("wrong directory geometry");
            11: if (data !== group_id) fail("wrong directory group");
            12: if (eye == 0 && data !== left_long_lease[bank][31:0])
                fail("directory lease low differs from LONG BEGIN identity");
            13: if (eye == 0 && data !== left_long_lease[bank][63:32])
                fail("directory lease high differs from LONG BEGIN identity");
        endcase
    endtask

    task automatic read_long(
        input int eye, input bit bank, input logic [31:0] group_id, input int ordinal,
        input bit stall_words
    );
        bit got_handshake;
        logic [31:0] word_data;
        if (!job_borrowed)
            fail("BFM attempted directory read before TAKE");
        @(negedge clk);
        ext_slot = {bank, 1'b0};
        ext_req[eye] = 1;
        got_handshake = 0;
        for (int cycle = 0; cycle < RESPONSE_CYCLES && !got_handshake; cycle++) begin
            @(posedge clk);
            got_handshake = (ext_ready[eye] === 1'b1);
        end
        if (!got_handshake)
            fail($sformatf("directory request timeout eye=%0d bank=%0d", eye, bank));
        @(negedge clk);
        ext_req[eye] = 0;
        for (int word_index = 0; word_index < 16; word_index++) begin
            got_handshake = 0;
            for (int cycle = 0; cycle < RESPONSE_CYCLES && !got_handshake; cycle++) begin
                @(posedge clk);
                got_handshake = (ext_valid[eye] === 1'b1);
            end
            if (!got_handshake)
                fail($sformatf("directory data timeout eye=%0d word=%0d", eye, word_index));
            word_data = ext_data[eye*32+:32];
            if (ext_word[eye*4+:4] !== 4'(word_index) || ext_last[eye] !== (word_index == 15))
                fail($sformatf("directory word index/last mismatch eye=%0d word=%0d", eye, word_index));
            check_directory_word(eye, bank, word_index, word_data, group_id, ordinal);
            if (stall_words && (word_index == 0 || word_index == 7 || word_index == 15)) begin
                repeat (3) begin
                    @(posedge clk);
                    if (ext_valid[eye] !== 1'b1 || ext_data[eye*32+:32] !== word_data ||
                        ext_word[eye*4+:4] !== 4'(word_index) || ext_last[eye] !== (word_index == 15))
                        fail($sformatf("directory changed under backpressure eye=%0d word=%0d", eye, word_index));
                end
            end
            @(negedge clk);
            ext_consume[eye] = 1;
            @(posedge clk);
            if (ext_valid[eye] !== 1'b1 || ext_data[eye*32+:32] !== word_data ||
                ext_word[eye*4+:4] !== 4'(word_index) || ext_last[eye] !== (word_index == 15))
                fail($sformatf("directory changed at consume eye=%0d word=%0d", eye, word_index));
            @(negedge clk);
            ext_consume[eye] = 0;
        end
        $display("HDR_DIRECTORY eye=%0d bank=%0d group=%08h sequence=%0d words=16 now_ns=%0d",
                 eye, bank, group_id, sequence_for(0, ordinal), now_ns);
    endtask

    task automatic present_release(input int eye, input bit bank, input logic [63:0] id);
        if (!job_borrowed)
            fail("BFM attempted RELEASE without a job");
        release_bank = bank;
        release_id = id;
        release_valid[eye] = 1;
    endtask

    task automatic sample_release(input int eye);
        job_borrowed = 0;
        retired_count[eye]++;
        $display("HDR_RELEASE eye=%0d bank=%0d id=%016h now_ns=%0d",
                 eye, release_bank, release_id, now_ns);
    endtask

    task automatic release_job(input int eye, input bit bank, input logic [63:0] id);
        @(negedge clk);
        present_release(eye, bank, id);
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (release_ready[eye] === 1'b1) begin
                sample_release(eye);
                @(negedge clk);
                release_valid[eye] = 0;
                return;
            end
        end
        fail($sformatf("RELEASE timeout eye=%0d bank=%0d id=%016h", eye, bank, id));
    endtask

    task automatic retire_group(
        input int eye, input bit bank, input logic [31:0] group_id, input int ordinal,
        input bit with_stalls
    );
        logic [63:0] id;
        take_job(eye, bank, with_stalls ? 5 : 0, id);
        read_long(eye, bank, group_id, ordinal, with_stalls);
        release_job(eye, bank, id);
    endtask

    task automatic check_drained;
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (pair_valid !== 2'b00)
                fail("unexpected pair after all expected jobs retired");
            if (fault !== 1'b0)
                fail("fault while waiting for normal drain");
            if (empty === 2'b11) begin
                if (writer_pending != 0 || job_borrowed)
                    fail("BFM left a transaction pending");
                no_pair(0, 5);
                no_pair(1, 5);
                return;
            end
        end
        fail($sformatf("banks did not drain, empty=%b", empty));
    endtask

    task automatic first_both(input int first_eye);
        int other_eye;
        bit first_bank, other_bank, spare;
        logic [63:0] id;
        other_eye = 1 - first_eye;
        fork
            offer_begin(first_eye, 0, 1, 1, 1, first_bank);
            offer_begin(other_eye, 1, 1, 1, 1, other_bank);
        join
        offer_begin(first_eye, 1, 1, 1, 1, spare);
        if (spare != first_bank) fail("first eye's exposures use different banks");
        offer_begin(other_eye, 0, 1, 1, 1, spare);
        if (spare != other_bank) fail("second eye's exposures use different banks");
        fork
            finish_member(first_eye, 1, 1);
            finish_member(other_eye, 0, 1);
        join
        fork
            no_pair(first_eye, 20);
            no_pair(other_eye, 20);
        join
        finish_member(first_eye, 0, 1);
        take_job(first_eye, first_bank, 5, id);
        fork
            read_long(first_eye, first_bank, 1, 1, 1);
            finish_member(other_eye, 1, 1);
        join
        release_job(first_eye, first_bank, id);
        retire_group(other_eye, other_bank, 1, 1, 1);
        complete_group(other_eye, 0, 2, 2, other_bank);
        complete_group(first_eye, 1, 2, 2, first_bank);
        retire_group(other_eye, other_bank, 2, 2, 0);
        retire_group(first_eye, first_bank, 2, 2, 0);
    endtask

    task automatic capacity(input int eye, input bit first_role);
        bit oldest, retained, spare, other_eye_bank;
        logic [63:0] oldest_id;
        complete_group(eye, first_role, 10, 10, oldest);
        take_job(eye, oldest, 2, oldest_id);
        read_long(eye, oldest, 10, 10, 1);
        complete_group(eye, first_role, 11, 11, retained);
        if (retained == oldest) fail("borrowed bank overwritten by group 11");
        offer_begin(eye, first_role, 12, 12, 0, spare);
        offer_begin(eye, first_role, 13, 13, 0, spare);
        complete_group(1-eye, !first_role, 10, 10, other_eye_bank);
        release_job(eye, oldest, oldest_id);
        offer_begin(eye, !first_role, 12, 12, 0, spare);
        offer_begin(eye, !first_role, 13, 13, 0, spare);
        complete_group(eye, !first_role, 14, 14, spare);
        if (spare != oldest) fail("group 14 did not use the actual retired bank");
        retire_group(1-eye, other_eye_bank, 10, 10, 1);
        retire_group(eye, retained, 11, 11, 1);
        retire_group(eye, spare, 14, 14, 1);
        for (int ordinal = 15; ordinal <= 16; ordinal++) begin
            complete_group(eye, first_role, 32'(ordinal), ordinal, spare);
            retire_group(eye, spare, 32'(ordinal), ordinal, 0);
        end
        if (rejected_count[eye] != 4 || retired_count[eye] != 5 || retired_count[1-eye] != 1)
            fail("capacity test scoreboard mismatch");
    endtask

    task automatic older_admitted(input int eye, input bit first_role);
        bit oldest, retained, spare;
        logic [63:0] oldest_id;
        complete_group(eye, first_role, 20, 20, oldest);
        take_job(eye, oldest, 0, oldest_id);
        read_long(eye, oldest, 20, 20, 0);
        offer_begin(eye, first_role, 21, 21, 1, retained);
        if (retained == oldest) fail("borrowed bank overwritten by group 21");
        finish_member(eye, first_role, 1);
        offer_begin(eye, first_role, 22, 22, 0, spare);
        offer_begin(eye, !first_role, 21, 21, 1, spare);
        if (spare != retained) fail("older admitted group assigned a different bank");
        finish_member(eye, !first_role, 1);
        release_job(eye, oldest, oldest_id);
        offer_begin(eye, !first_role, 22, 22, 0, spare);
        retire_group(eye, retained, 21, 21, 1);
        complete_group(eye, !first_role, 23, 23, spare);
        retire_group(eye, spare, 23, 23, 0);
        if (rejected_count[eye] != 2 || retired_count[eye] != 3)
            fail("older admitted test scoreboard mismatch");
    endtask

    task automatic release_phase(input int eye, input bit role, input int phase);
        bit oldest, retained, new_bank, peer_bank;
        bit began, retired, allowed, live;
        int begin_cycle, release_cycle;
        logic [63:0] oldest_id;
        complete_group(eye, role, 30, 30, oldest);
        take_job(eye, oldest, 0, oldest_id);
        read_long(eye, oldest, 30, 30, 1);
        complete_group(eye, role, 31, 31, retained);
        if (retained == oldest) fail("group 31 overwrote the borrowed bank");

        // phase is RELEASE presentation minus BEGIN presentation in clock cycles.
        begin_cycle = phase < 0 ? -phase : 0;
        release_cycle = phase > 0 ? phase : 0;
        began = 0;
        retired = 0;
        @(negedge clk);
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            if (cycle == begin_cycle) present_begin(eye, role, 32, 32);
            if (cycle == release_cycle) present_release(eye, oldest, oldest_id);
            @(posedge clk);
            if (release_valid[eye] && release_ready[eye] === 1'b1) begin
                sample_release(eye);
                retired = 1;
            end
            if (cycle == begin_cycle && phase <= 0 && !retired)
                fail("phase fixture did not realize RELEASE at or before BEGIN presentation");
            if (begin_valid[eye] && begin_ready[eye] === 1'b1) begin
                if ($isunknown(accepted[eye])) fail("unknown BEGIN result in release phase test");
                allowed = (phase <= 0) || accepted[eye];
                if (allowed && !retired)
                    fail("BEGIN allocated borrowed bank before real RELEASE");
                sample_begin(eye, role, 32, allowed, new_bank);
                if (allowed && new_bank != oldest)
                    fail("BEGIN did not reuse the retired bank");
                live = allowed;
                began = 1;
            end
            @(negedge clk);
            if (retired) release_valid[eye] = 0;
            if (began) begin_valid[eye] = 0;
            if (retired && began) break;
        end
        if (!began || !retired) fail("release phase handshake timed out");
        offer_begin(eye, !role, 32, 32, live, peer_bank);
        if (live) begin
            if (new_bank != peer_bank) fail("retired-bank reuse split a group");
            finish_member(eye, role, 1);
            finish_member(eye, !role, 1);
        end
        retire_group(eye, retained, 31, 31, 1);
        if (live) retire_group(eye, new_bank, 32, 32, 1);
        complete_group(eye, !role, 33, 33, new_bank);
        retire_group(eye, new_bank, 33, 33, 0);
    endtask

    task automatic stopped_drain(input int eye, input bit role);
        bit oldest, partial_bank, new_bank, peer_bank;
        bit drained, responded, resumed_group;
        logic [63:0] oldest_id;
        complete_group(eye, role, 40, 40, oldest);
        take_job(eye, oldest, 0, oldest_id);
        offer_begin(eye, role, 41, 41, 1, partial_bank);
        if (partial_bank == oldest) fail("group 41 overwrote the borrowed bank");
        @(negedge clk);
        stop = 1;
        fork
            read_long(eye, oldest, 40, 40, 1);
            finish_member(eye, role, 1);
        join
        @(negedge clk);
        present_release(eye, oldest, oldest_id);
        present_begin(eye, !role, 42, 42);
        drained = 0;
        responded = 0;
        for (int cycle = 0; cycle < RESPONSE_CYCLES; cycle++) begin
            @(posedge clk);
            if (release_valid[eye] && release_ready[eye] === 1'b1)
                sample_release(eye);
            if (begin_valid[eye] && begin_ready[eye] === 1'b1) begin
                sample_begin(eye, !role, 42, 0, new_bank);
                responded = 1;
            end
            if (pair_valid !== 2'b00 || fault !== 1'b0)
                fail("STOP produced an unexpected pair or fault while draining");
            drained = !job_borrowed && empty === 2'b11;
            @(negedge clk);
            if (!job_borrowed) release_valid[eye] = 0;
            if (responded) begin_valid[eye] = 0;
            if (drained) break;
        end
        if (!drained) fail("STOP did not drain the committed writer and job");
        stop = 0;
        resumed_group = 0;
        // A held BEGIN is allowed to wait out STOP. Check its first actual response.
        for (int cycle = 0; cycle < RESPONSE_CYCLES && !responded; cycle++) begin
            @(posedge clk);
            if (begin_ready[eye] === 1'b1) begin
                if ($isunknown(accepted[eye])) fail("unknown held BEGIN result after STOP");
                resumed_group = accepted[eye];
                sample_begin(eye, !role, 42, resumed_group, new_bank);
                responded = 1;
                @(negedge clk);
                begin_valid[eye] = 0;
            end
        end
        if (!responded) fail("BEGIN remained stalled after STOP was deasserted");
        if (resumed_group) begin
            offer_begin(eye, role, 42, 42, 1, peer_bank);
            if (peer_bank != new_bank) fail("resumed group split across banks");
            finish_member(eye, !role, 1);
            finish_member(eye, role, 1);
            retire_group(eye, new_bank, 42, 42, 1);
        end
        complete_group(eye, !role, 43, 43, new_bank);
        retire_group(eye, new_bank, 43, 43, 1);
    endtask

    task automatic failed_source(input int eye, input bit role);
        bit bad_bank, peer_bank, good_bank;
        offer_begin(eye, role, 50, 50, 1, bad_bank);
        finish_member(eye, role, 0);
        offer_begin(eye, !role, 50, 50, 0, peer_bank);
        no_pair(eye, 15);

        // A peer admitted before the negative SOURCE retains its FINISH debt.
        offer_begin(eye, role, 51, 51, 1, bad_bank);
        offer_begin(eye, !role, 51, 51, 1, peer_bank);
        if (bad_bank != peer_bank) fail("group 51 assigned two banks");
        finish_member(eye, role, 0);
        finish_member(eye, !role, 1);
        no_pair(eye, 15);

        complete_group(eye, !role, 52, 52, good_bank);
        retire_group(eye, good_bank, 52, 52, 1);
        if (retired_count[eye] != 1) fail("negative SOURCE group reached pair retirement");
    endtask

    task automatic wrap(input int eye, input bit role);
        bit oldest, retained, new_bank, spare;
        logic [63:0] oldest_id;
        complete_group(eye, role, 32'hfffffffc, 60, oldest);
        take_job(eye, oldest, 0, oldest_id);
        read_long(eye, oldest, 32'hfffffffc, 60, 1);
        complete_group(eye, role, 32'hfffffffd, 61, retained);
        if (retained == oldest) fail("wrap fixture overwrote the borrowed bank");
        offer_begin(eye, role, 32'hfffffffe, 62, 0, spare);
        offer_begin(eye, role, 32'hffffffff, 63, 0, spare);
        release_job(eye, oldest, oldest_id);

        // The lane that was ahead has already wrapped. The lagging lane is ordered
        // and still owes the peer offers of both rejected groups before it wraps.
        offer_begin(eye, role, 32'd1, 64, 1, new_bank);
        if (new_bank != oldest) fail("wrapped group did not reuse retired bank");
        retire_group(eye, retained, 32'hfffffffd, 61, 1);
        offer_begin(eye, !role, 32'hfffffffe, 62, 0, spare);
        offer_begin(eye, !role, 32'hffffffff, 63, 0, spare);
        offer_begin(eye, !role, 32'd1, 64, 1, spare);
        if (spare != new_bank) fail("wrapped group exposures assigned two banks");
        finish_member(eye, !role, 1);
        finish_member(eye, role, 1);
        retire_group(eye, new_bank, 32'd1, 64, 1);
        complete_group(eye, !role, 32'd2, 65, spare);
        retire_group(eye, spare, 32'd2, 65, 0);
        if (rejected_count[eye] != 4 || retired_count[eye] != 4)
            fail("wrapped group scoreboard mismatch");
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) begin
            case_name = "missing";
            fail("specify +CASE");
        end
        for (int eye = 0; eye < 2; eye++) begin
            accepted_count[eye] = 0;
            rejected_count[eye] = 0;
            taken_count[eye] = 0;
            retired_count[eye] = 0;
        end
        repeat (32) @(negedge clk);
        rst_n = 1;
        configure(FIRST_EPOCH);
        case (case_name)
            "first_left": first_both(0);
            "first_right": first_both(1);
            "capacity_left": capacity(0, 0);
            "capacity_right": capacity(1, 1);
            "older_left": older_admitted(0, 1);
            "older_right": older_admitted(1, 0);
            "phase_aligned_left": release_phase(0, 0, 0);
            "phase_aligned_right": release_phase(1, 1, 0);
            "phase_early": release_phase(0, 1, -2);
            "phase_late": release_phase(1, 0, 2);
            "stop_drain": stopped_drain(0, 1);
            "failed_source_left": failed_source(0, 0);
            "failed_source_right": failed_source(1, 1);
            "wrap": wrap(1, 0);
            default: fail("unknown test case");
        endcase
        check_drained();
        terminal_printed = 1;
        $display("HDR_BLACKBOX PASS case=%s accepted=%0d/%0d rejected=%0d/%0d retired=%0d/%0d now_ns=%0d",
                 case_name, accepted_count[0], accepted_count[1], rejected_count[0], rejected_count[1],
                 retired_count[0], retired_count[1], now_ns);
        $finish;
    end
endmodule
