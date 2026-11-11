`timescale 1ns/1ps
`include "reader_sizes.vh"

module tb_hdr_reader;
    localparam int WIDTH = 68, HEIGHT = 63;
    localparam int GROUPS_PER_ROW = WIDTH / 4;
    localparam int GROUPS = GROUPS_PER_ROW * HEIGHT;
    localparam int WORDS = (GROUPS * 5 + 15) / 16;
    localparam int MEMBER_STRIDE = 32'h01000000;
    localparam int GOOD = 0, SLVERR = 1, CANCEL_AR = 2, CANCEL_RAW = 3, RESET_RAW = 4;

    bit i_clk = 0;
    always #3.751 i_clk = !i_clk;
    bit i_identity_rst_n;
    bit i_start_valid, i_pair_bank, i_pair_camera;
    wire o_start_ready;
    bit [2:0] i_ratio_log2;
    bit [9:0] i_black_long, i_black_short;
    bit [13:0] i_motion_base;
    bit [3:0] i_motion_shift;
    bit [1:0] i_fusion_preset;
    bit i_cancel;
    wire [55:0] m_raw;
    wire [3:0] m_motion;
    wire m_valid, m_sof, m_eol, m_eof;
    wire [31:0] m_index;
    wire o_result_valid, o_result_ok, o_read_quiet, o_protocol_fault;
    bit i_result_ready;
    wire [9:0] o_long_occupancy, o_short_occupancy;
    wire [3:0] m_axi_arid;
    wire [27:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire m_axi_arvalid, m_axi_rready;
    bit [3:0] m_axi_rid;
    bit [127:0] m_axi_rdata;
    bit [1:0] m_axi_rresp;
    bit m_axi_rlast, m_axi_rvalid;
    bit block_ar, block_r, block_raw;
    int schedule_tick = 0, tail_left = 0, last_tail_job = -1;
    wire m_axi_arready = !block_ar && schedule_tick % 11 < 8;
    wire m_ready = !block_raw && tail_left == 0 && schedule_tick % 23 < 20;

    quality_hdr_reader_carrier #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) dut (.*);

    typedef struct packed {
        logic camera, bank;
        logic [1:0] preset;
        logic [13:0] base;
        logic [3:0] shift;
        logic [2:0] mode;
    } job_t;

    typedef struct packed {
        int unsigned member;
        int unsigned next_word;
        int unsigned remaining;
    } burst_t;

    job_t jobs[0:`READER_JOBS-1], job;
    logic [127:0] memory[0:`READER_JOBS*2*WORDS-1];
    logic [59:0] raw_expected[0:`READER_JOBS*GROUPS-1];
    burst_t pending[$];
    int job_slot = -1;
    int requested[2], returned[2], outstanding;
    bit cross_page[2];
    bit live, r_transfer, held_ar, held_raw, held_result;
    logic [44:0] ar_snapshot;
    logic [94:0] raw_snapshot;
    logic result_snapshot;
    int raw_count, results, tail_stalls, error_responses;
    int ar_stalls = 0, response_gaps = 0, r_stalls = 0;

    task automatic fail(input string reason);
        $fatal(1, "READER_FAIL job=%0d mode=%0d raw=%0d outstanding=%0d %s",
               job_slot, job.mode, raw_count, outstanding, reason);
    endtask

    function automatic int unsigned frame_address(input job_t descriptor);
        return 32'h02000000 + (4 * int'(descriptor.camera) + 2 * int'(descriptor.bank)) * MEMBER_STRIDE;
    endfunction

    always @(posedge i_clk) begin : observe
        burst_t burst;
        int unsigned addr, offset, member, length;
        logic [44:0] ar_offer;
        logic [94:0] raw_offer, want;
        if (!i_identity_rst_n) begin
            pending.delete();
            live = 0;
            held_ar = 0;
            held_raw = 0;
            held_result = 0;
            r_transfer = 0;
            outstanding = 0;
            raw_count = 0;
            results = 0;
            tail_stalls = 0;
            error_responses = 0;
        end else begin
            if ($isunknown({m_axi_arvalid, m_axi_rready, m_valid, o_result_valid, o_start_ready}))
                fail("unknown public handshake control");
            if ($isunknown({o_long_occupancy, o_short_occupancy}) ||
                o_long_occupancy > 512 || o_short_occupancy > 512)
                fail("occupancy outside 0..512 groups");
            if (i_start_valid && o_start_ready) begin
                if (live || outstanding != 0 || pending.size() != 0)
                    fail("START before previous job retired");
                live = 1;
                raw_count = 0;
                results = 0;
                tail_stalls = 0;
                error_responses = 0;
                foreach (requested[index]) begin
                    requested[index] = 0;
                    returned[index] = 0;
                    cross_page[index] = 0;
                end
            end

            ar_offer = {m_axi_arid, m_axi_araddr, m_axi_arlen, m_axi_arsize, m_axi_arburst};
            if (held_ar && (!m_axi_arvalid || ar_offer !== ar_snapshot))
                fail("stalled AR offer changed before acceptance");
            held_ar = m_axi_arvalid && !m_axi_arready;
            ar_snapshot = ar_offer;
            if (held_ar)
                ar_stalls++;
            if (m_axi_arvalid && m_axi_arready) begin
                if (!live || $isunknown(ar_offer))
                    fail("unexpected or unknown AR");
                addr = m_axi_araddr;
                length = int'(m_axi_arlen) + 1;
                if (m_axi_arid != 1 || m_axi_arsize != 4 || m_axi_arburst != 1 || addr % 16 != 0 ||
                    length > 16 || addr % 4096 + length * 16 > 4096)
                    fail($sformatf("illegal AR address=%07x beats=%0d", addr, length));
                if (addr < frame_address(job) || addr >= frame_address(job) + 2 * MEMBER_STRIDE)
                    fail($sformatf("AR wrong camera/bank address=%07x", addr));
                member = (addr - frame_address(job)) / MEMBER_STRIDE;
                offset = (addr - frame_address(job)) % MEMBER_STRIDE;
                if (offset != requested[member] * 16 || requested[member] + length > WORDS)
                    fail($sformatf("AR discontinuity member=%0d offset=%0d expected=%0d beats=%0d",
                                   member, offset, requested[member] * 16, length));
                cross_page[member] |= offset >= 4096;
                burst = {member, requested[member], length};
                pending.push_back(burst);
                requested[member] += length;
                outstanding += length;
            end

            r_transfer = m_axi_rvalid && m_axi_rready;
            if (m_axi_rvalid && !m_axi_rready)
                r_stalls++;
            if (r_transfer) begin
                if (pending.size() == 0 || outstanding <= 0)
                    fail("BFM response without accepted AR");
                burst = pending.pop_front();
                returned[burst.member]++;
                outstanding--;
                if (m_axi_rresp == 2'b10)
                    error_responses++;
                if (burst.remaining > 1) begin
                    burst.remaining--;
                    burst.next_word++;
                    pending.push_front(burst);
                end
            end

            raw_offer = {m_index, m_sof, m_eol, m_eof, m_motion, m_raw};
            if (held_raw && (!m_valid || raw_offer !== raw_snapshot))
                fail("stalled RAW offer changed before acceptance");
            held_raw = m_valid && !m_ready;
            raw_snapshot = raw_offer;
            if (held_raw && m_eof)
                tail_stalls++;
            if (m_valid) begin
                if (!live || raw_count >= GROUPS)
                    fail("extra RAW output");
                want = {32'(raw_count), raw_count == 0, raw_count % GROUPS_PER_ROW == GROUPS_PER_ROW-1,
                        raw_count == GROUPS-1, raw_expected[job_slot * GROUPS + raw_count]};
                if (raw_offer !== want)
                    fail($sformatf("RAW got %024x expected %024x", raw_offer, want));
                if (m_ready)
                    raw_count++;
            end

            if (held_result && (!o_result_valid || o_result_ok !== result_snapshot))
                fail("held RESULT changed before acceptance");
            held_result = o_result_valid && !i_result_ready;
            result_snapshot = o_result_ok;
            if (o_result_valid) begin
                if (!live || o_result_ok !== (job.mode == GOOD))
                    fail($sformatf("unexpected RESULT status=%b", o_result_ok));
                if (i_result_ready) begin
                    if (o_read_quiet !== 1'b1 || outstanding != 0 || pending.size() != 0 || held_ar || held_raw)
                        fail("RESULT before accepted read or RAW obligations drained");
                    if (job.mode == GOOD && (raw_count != GROUPS || tail_stalls < 6 ||
                        returned[0] != WORDS || returned[1] != WORDS || !cross_page[0] || !cross_page[1]))
                        fail($sformatf("incomplete legal job R words=%0d/%0d tail_hold=%0d",
                                       returned[0], returned[1], tail_stalls));
                    if (job.mode == SLVERR && error_responses != 1)
                        fail("SLVERR scenario did not transfer exactly one error response");
                    live = 0;
                    results++;
                end
            end
        end
    end

    always @(negedge i_clk) begin : memory_responder
        burst_t burst;
        schedule_tick++;
        if (!i_identity_rst_n) begin
            m_axi_rvalid = 0;
            last_tail_job = -1;
            tail_left = 0;
        end else begin
            if (tail_left > 0)
                tail_left--;
            else if (m_valid && m_eof && last_tail_job != job_slot) begin
                last_tail_job = job_slot;
                tail_left = 7;
            end
            if (r_transfer)
                m_axi_rvalid = 0;
            if (!m_axi_rvalid && pending.size() != 0) begin
                if (!block_r && schedule_tick % 13 < 10) begin
                    burst = pending[0];
                    m_axi_rid = 1;
                    m_axi_rdata = memory[(job_slot * 2 + burst.member) * WORDS + burst.next_word];
                    m_axi_rlast = burst.remaining == 1;
                    m_axi_rresp = job.mode == SLVERR && returned[0] + returned[1] == 3 ? 2'b10 : 2'b00;
                    m_axi_rvalid = 1;
                end else begin
                    response_gaps++;
                end
            end
        end
    end

    task automatic step;
        @(negedge i_clk);
    endtask

    task automatic poison_parameters(input bit later);
        // START is deasserted. These pins must not alter the borrowed job.
        i_pair_camera = !job.camera;
        i_pair_bank = !job.bank;
        i_fusion_preset = job.preset ^ 2'd1;
        i_ratio_log2 = later ? 3'd5 : 3'd1;
        i_black_long = later ? 10'd0 : 10'd511;
        i_black_short = later ? 10'd327 : 10'd0;
        i_motion_base = ~job.base;
        i_motion_shift = ~job.shift;
    endtask

    task automatic start_job(input int slot);
        while (o_start_ready !== 1'b1)
            step();
        job_slot = slot;
        job = jobs[slot];
        i_pair_camera = job.camera;
        i_pair_bank = job.bank;
        i_fusion_preset = job.preset;
        i_ratio_log2 = 4;
        i_black_long = 50;
        i_black_short = 50;
        i_motion_base = job.base;
        i_motion_shift = job.shift;
        i_start_valid = 1;
        step();
        if (!live)
            fail("fixture START did not handshake");
        i_start_valid = 0;
        poison_parameters(0);
    endtask

    task automatic retire;
        while (o_result_valid !== 1'b1)
            step();
        repeat (6) step();
        i_result_ready = 1;
        step();
        i_result_ready = 0;
        repeat (4) step();
        if (results != 1 || live)
            fail("expected exactly one accepted RESULT");
        $display("READER_JOB_PASS slot=%0d mode=%0d camera=%0d bank=%0d preset=%0d raw_groups=%0d r_words=%0d/%0d tail_hold=%0d slverr=%0d protocol_fault=%b",
                 job_slot, job.mode, job.camera, job.bank, job.preset, raw_count,
                 returned[0], returned[1], tail_stalls, error_responses, o_protocol_fault);
    endtask

    task automatic cancel;
        i_cancel = 1;
        step();
        i_cancel = 0;
    endtask

    initial begin
        int good_jobs, failed_jobs;
        job_t next_job;
        good_jobs = 0;
        failed_jobs = 0;
        $readmemh("reader_jobs.mem", jobs);
        $readmemh("reader_ddr.mem", memory);
        $readmemh("reader_raw.mem", raw_expected);
        repeat (8) step();
        i_identity_rst_n = 1;
        repeat (8) step();
        for (int slot = 0; slot < `READER_JOBS; slot++) begin
            next_job = jobs[slot];
            block_ar = next_job.mode == CANCEL_AR;
            block_raw = next_job.mode == CANCEL_RAW || next_job.mode == RESET_RAW;
            start_job(slot);
            case (job.mode)
                GOOD: begin
                    while (!(m_valid && m_eof && !m_ready))
                        step();
                    poison_parameters(1);
                    retire();
                    good_jobs++;
                end
                SLVERR: begin
                    retire();
                    failed_jobs++;
                end
                CANCEL_AR: begin
                    while (!m_axi_arvalid)
                        step();
                    repeat (3) step();
                    cancel();
                    repeat (3) step();
                    block_ar = 0;
                    retire();
                    if (returned[0] + returned[1] == 0)
                        fail("fixture did not retire an AR offered before cancellation");
                    failed_jobs++;
                end
                CANCEL_RAW: begin
                    while (!m_valid)
                        step();
                    block_r = 1;
                    while (outstanding == 0)
                        step();
                    repeat (3) step();
                    cancel();
                    repeat (4) step();
                    block_raw = 0;
                    block_r = 0;
                    retire();
                    if (raw_count == 0)
                        fail("fixture did not retire held RAW after cancellation");
                    failed_jobs++;
                end
                RESET_RAW: begin
                    while (!m_valid)
                        step();
                    repeat (3) step();
                    #1 i_identity_rst_n = 0;
                    repeat (8) step();
                    i_identity_rst_n = 1;
                    block_raw = 0;
                    repeat (8) step();
                    if (m_valid || o_result_valid || pending.size() != 0)
                        fail("stale response or result after coordinated reset");
                    $display("READER_RESET_PASS slot=%0d held_RAW_discarded=1", slot);
                end
                default: fail("unknown fixture mode");
            endcase
        end
        if (good_jobs != 6 || failed_jobs != 3 || ar_stalls == 0 || response_gaps == 0)
            fail("job or AXI stall coverage incomplete");
        $display("READER_PASS geometry=68x63 good_jobs=%0d failed_jobs=%0d good_groups=%0d ar_stalls=%0d response_gaps=%0d r_stalls=%0d",
                 good_jobs, failed_jobs, good_jobs * GROUPS, ar_stalls, response_gaps, r_stalls);
        $finish;
    end

    initial begin
        #1500000;
        fail("simulation watchdog (200000 DFI edges)");
    end
endmodule
