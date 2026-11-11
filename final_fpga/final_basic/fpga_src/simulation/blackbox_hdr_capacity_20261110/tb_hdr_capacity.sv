`timescale 1ps/1ps

module tb_hdr_capacity;
    localparam int PERIOD = 3300;
    localparam int WARMUP = 30;
    localparam int MEASURE = 60;
    localparam int FRAMES = WARMUP + MEASURE;
    localparam int AXI_DEPTH = 32;
    localparam int SLOT_BYTES = 80;
    localparam int STORE_BASE = 'h02000000;
    localparam int SLOT_STRIDE = 'h01000000;

    logic dfi_clk = 0, pixel_clk = 0, rst_n = 0;
    logic [63:0] i_now_ns = 1_000_000;
    logic i_cfg_valid = 0;
    wire o_cfg_ready, o_cfg_done, o_cfg_error, o_policy_admit;

    logic [159:0] s_raw_data = 0;
    logic [3:0] s_raw_valid = 0, s_raw_sof = 0, s_raw_eol = 0;
    logic [127:0] s_raw_sequence = 0;
    logic [787:0] s_raw_metadata = 0;
    logic [3:0] s_source_valid = 0;
    logic [127:0] s_source_sequence = 0;
    wire [3:0] s_source_ready, o_capture_admit;

    wire [3:0] m_axi_awid;
    wire [27:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire m_axi_awvalid;
    logic m_axi_awready = 1;
    wire [127:0] m_axi_wdata;
    wire [15:0] m_axi_wstrb;
    wire m_axi_wlast, m_axi_wvalid;
    logic m_axi_wready = 1;
    logic [3:0] m_axi_bid = 0;
    logic [1:0] m_axi_bresp = 0;
    logic m_axi_bvalid = 0;
    wire m_axi_bready;

    wire o_pair_valid, o_pair_ready, o_pair_bank;
    wire [63:0] o_pair_id;
    wire o_job_valid, o_job_ready;
    wire [63:0] o_job_id, o_job_pair_id, o_job_lease0, o_job_lease1;
    wire [383:0] o_job_frame;
    wire o_release_valid, o_release_ready, o_release_bank;
    wire [63:0] o_release_id;
    wire o_retire_done;

    wire o_member_valid, o_member_index, o_context_valid, o_start_valid;
    logic i_member_ready = 0, i_context_ready = 0, i_start_ready = 0;
    logic i_result_valid = 0, i_result_ready = 1, i_result_ok = 1;
    wire o_result_ready;
    logic i_processing_done = 0, i_processing_error = 0;
    logic [63:0] i_processing_job_id = 0;
    logic i_reader_quiet = 1, i_product_quiet = 1, i_writer_quiet = 1, i_ticket_released = 1;

    wire [1:0] o_begin_reject, o_pair_expire;
    wire [3:0] o_bad_finish;
    wire [7:0] o_bank_states;
    wire o_capture_write_quiet, o_scheduler_busy, o_quiescent, o_fault;

    owner_service_carrier dut (.*);

    always #3751 dfi_clk = ~dfi_clk;
    initial begin
        #1000;
        forever #4000 pixel_clk = ~pixel_clk;
    end
    initial begin
        #(64'd2500000000);
        $fatal(1, "HDRCAP watchdog expired");
    end

    string scenario;
    bit first_case, late_peer_case, rate_case;
    int service_ticks, phase_ticks;
    int tick = 0, origin;
    bit cfg_done_seen, observing;

    int sof_at[4][FRAMES+1] = '{default:'{default:0}};
    int source_at[4][FRAMES+1] = '{default:'{default:0}};
    int reject_at[4][FRAMES+1] = '{default:'{default:0}};
    int job_at[2][FRAMES+1] = '{default:'{default:0}};
    int release_at[2][FRAMES+1] = '{default:'{default:0}};
    int recent_lane[2] = '{default:0};
    int recent_frame[2] = '{default:0};
    int last_job_frame[2] = '{default:0};

    int aw_issued = 0, aw_consumed = 0;
    int aw_slot[AXI_DEPTH], aw_offset[AXI_DEPTH], aw_beats[AXI_DEPTH];
    logic [3:0] aw_id[AXI_DEPTH];
    int beat_index = 0, w_total = 0, w_stall_ticks = 0;
    bit w_stalled;
    logic [144:0] stalled_w;
    int b_issued = 0, b_consumed = 0;
    int b_slot[AXI_DEPTH], b_due[AXI_DEPTH];
    logic [3:0] b_id[AXI_DEPTH];
    int slot_pending_b[8] = '{default:0};
    int slot_good_b[8] = '{default:0};
    int slot_last_b[8] = '{default:0};
    bit [SLOT_BYTES-1:0] slot_written[8];
    logic [7:0] slot_data[8][SLOT_BYTES];

    int pair_issued = 0, pair_used = 0;
    int pair_at[2*FRAMES], pair_bank[2*FRAMES];
    logic [63:0] pair_id[2*FRAMES];
    bit service_active;
    int eye_in_service, frame_in_service, bank_in_service, acquired_at;
    int dispatched_at, member_at, context_at, start_at, result_at, processing_at;
    logic [63:0] id_in_service;
    int release_total = 0, retire_total = 0;
    int min_service = 1000000, max_service = 0;

    function automatic int group_for(input int eye, frame);
        return 1000 * eye + frame;
    endfunction

    function automatic logic [31:0] sequence_for(input int lane, frame);
        return 10000 * (lane + 1) + frame;
    endfunction

    function automatic logic [39:0] raw_word(input int lane, frame, ordinal);
        logic [23:0] group_id;
        logic [7:0] lane_tag, ordinal_tag;
        group_id = group_for(lane / 2, frame);
        lane_tag = 'hD0 + lane;
        ordinal_tag = 'hA0 + ordinal;
        return {group_id[23:16] ^ 8'h5A, group_id[15:0], lane_tag, ordinal_tag};
    endfunction

    task automatic wait_pix_tick(input int target);
        while (tick < target) @(negedge pixel_clk);
        if (tick > target + 1)
            $fatal(1, "HDRCAP input schedule slipped tick=%0d target=%0d", tick, target);
    endtask

    task automatic send_raw_group(input int lane, frame, ordinal);
        s_raw_data[40*lane +: 40] = raw_word(lane, frame, ordinal);
        s_raw_valid[lane] = 1;
        s_raw_sof[lane] = (ordinal == 0);
        s_raw_eol[lane] = (ordinal % 4 == 3);
        @(posedge pixel_clk);
        if (ordinal == 0) begin
            if (o_capture_admit[lane] !== 1'b1)
                $fatal(1, "HDRCAP legal SOF never admitted at capture tick=%0d lane=%0d frame=%0d", tick, lane, frame);
            sof_at[lane][frame] = tick;
            recent_lane[lane / 2] = lane;
            recent_frame[lane / 2] = frame;
            $display("HDRCAP SOF tick=%0d eye=%0d role=%0d frame=%0d group=%0d seq=%0d", tick,
                     lane / 2, lane % 2, frame, group_for(lane / 2, frame), sequence_for(lane, frame));
        end
        @(negedge pixel_clk);
        s_raw_valid[lane] = 0;
        s_raw_sof[lane] = 0;
        s_raw_eol[lane] = 0;
    endtask

    task automatic send_member(input int lane, frame, sof_target, source_target);
        logic [196:0] metadata;
        wait_pix_tick(sof_target);
        metadata = 0;
        metadata[63:0] = i_now_ns;
        metadata[95:64] = (lane % 2 == 0) ? 3200 : 200;
        metadata[127:96] = 256;
        metadata[159:128] = 32'h56a3d02f;
        metadata[191:160] = group_for(lane / 2, frame);
        metadata[192] = 1;
        metadata[194:193] = (lane % 2 == 0) ? 2'd1 : 2'd2;
        metadata[196:195] = 2'b11;
        s_raw_metadata[197*lane +: 197] = metadata;
        s_raw_sequence[32*lane +: 32] = sequence_for(lane, frame);
        send_raw_group(lane, frame, 0);
        wait_pix_tick(source_target - 18);
        for (int ordinal = 1; ordinal < 16; ordinal++)
            send_raw_group(lane, frame, ordinal);

        wait_pix_tick(source_target);
        s_source_sequence[32*lane +: 32] = sequence_for(lane, frame);
        s_source_valid[lane] = 1;
        $display("HDRCAP SOURCE_OFFER tick=%0d eye=%0d role=%0d frame=%0d group=%0d seq=%0d", tick,
                 lane / 2, lane % 2, frame, group_for(lane / 2, frame), sequence_for(lane, frame));
        do @(posedge pixel_clk); while (s_source_ready[lane] !== 1'b1);
        source_at[lane][frame] = tick;
        $display("HDRCAP SOURCE tick=%0d eye=%0d role=%0d frame=%0d group=%0d seq=%0d", tick,
                 lane / 2, lane % 2, frame, group_for(lane / 2, frame), sequence_for(lane, frame));
        @(negedge pixel_clk);
        s_source_valid[lane] = 0;
    endtask

    task automatic drive_lane(input int lane);
        int sof_target;
        if (first_case) begin
            sof_target = origin + 100 * (lane % 2);
            send_member(lane, 1, sof_target, sof_target + 40);
        end else if (late_peer_case) begin
            if (lane < 2) begin
                sof_target = origin + 100 * lane;
                send_member(lane, 1, sof_target, sof_target + 40);
                send_member(lane, 2, sof_target + 250, sof_target + 290);
                if (lane == 0)
                    send_member(lane, 3, origin + 550, origin + 590);
                else
                    send_member(lane, 3, origin + 2000, origin + 2040);
                send_member(lane, 4, sof_target + 2250, sof_target + 2290);
            end
        end else begin
            for (int frame = 1; frame <= FRAMES; frame++) begin
                sof_target = origin + (lane / 2) * phase_ticks + (frame - 1) * PERIOD + 100 * (lane % 2);
                send_member(lane, frame, sof_target, sof_target + 2900);
            end
        end
    endtask

    task automatic observe_axi;
        int entry, relative_addr, slot, offset, b_entry;
        if (m_axi_awvalid && m_axi_awready) begin
            relative_addr = int'(m_axi_awaddr) - STORE_BASE;
            slot = relative_addr / SLOT_STRIDE;
            offset = relative_addr % SLOT_STRIDE;
            if ($isunknown({m_axi_awid, m_axi_awaddr, m_axi_awlen, m_axi_awsize, m_axi_awburst}) ||
                relative_addr < 0 || slot >= 8 || offset >= SLOT_BYTES || offset % 16 != 0 ||
                m_axi_awsize != 4 || m_axi_awburst != 1 || aw_issued - aw_consumed >= AXI_DEPTH)
                $fatal(1, "HDRCAP invalid AW tick=%0d addr=%h len=%0d id=%0d", tick, m_axi_awaddr, m_axi_awlen, m_axi_awid);
            entry = aw_issued % AXI_DEPTH;
            aw_slot[entry] = slot;
            aw_offset[entry] = offset;
            aw_beats[entry] = int'(m_axi_awlen) + 1;
            aw_id[entry] = m_axi_awid;
            aw_issued++;
            slot_pending_b[slot]++;
        end

        if (w_stalled && (m_axi_wvalid !== 1'b1 || {m_axi_wdata, m_axi_wstrb, m_axi_wlast} !== stalled_w))
            $fatal(1, "HDRCAP W offer changed under stall tick=%0d", tick);
        w_stalled = m_axi_wvalid && !m_axi_wready;
        if (w_stalled) begin
            stalled_w = {m_axi_wdata, m_axi_wstrb, m_axi_wlast};
            w_stall_ticks++;
        end

        if (m_axi_wvalid && m_axi_wready) begin
            if (aw_consumed >= aw_issued)
                $fatal(1, "HDRCAP W without AW tick=%0d", tick);
            entry = aw_consumed % AXI_DEPTH;
            slot = aw_slot[entry];
            if ($isunknown(m_axi_wstrb) || m_axi_wlast !== (beat_index == aw_beats[entry] - 1))
                $fatal(1, "HDRCAP invalid WSTRB/WLAST tick=%0d slot=%0d beat=%0d", tick, slot, beat_index);
            for (int byte_index = 0; byte_index < 16; byte_index++) begin
                if (m_axi_wstrb[byte_index]) begin
                    offset = aw_offset[entry] + 16 * beat_index + byte_index;
                    if (offset >= SLOT_BYTES || slot_written[slot][offset])
                        $fatal(1, "HDRCAP write outside member or overwrite tick=%0d slot=%0d offset=%0d", tick, slot, offset);
                    slot_written[slot][offset] = 1;
                    slot_data[slot][offset] = m_axi_wdata[8*byte_index +: 8];
                end
            end
            w_total++;
            if (m_axi_wlast) begin
                if (b_issued - b_consumed >= AXI_DEPTH)
                    $fatal(1, "HDRCAP B queue overflow tick=%0d", tick);
                b_entry = b_issued % AXI_DEPTH;
                b_slot[b_entry] = slot;
                b_id[b_entry] = aw_id[entry];
                b_due[b_entry] = tick + (first_case ? 11 : 2);
                b_issued++;
                aw_consumed++;
                beat_index = 0;
            end else begin
                beat_index++;
            end
        end

        if (m_axi_bvalid && m_axi_bready) begin
            b_entry = b_consumed % AXI_DEPTH;
            if (b_consumed >= b_issued || m_axi_bid !== b_id[b_entry] || tick < b_due[b_entry])
                $fatal(1, "HDRCAP B without completed burst tick=%0d", tick);
            slot = b_slot[b_entry];
            slot_pending_b[slot]--;
            slot_good_b[slot]++;
            slot_last_b[slot] = tick;
            b_consumed++;
        end
    endtask

    task automatic check_member_write(input int slot, lane, frame, acquire_tick);
        logic [39:0] expected_word;
        if (source_at[lane][frame] == 0 || slot_written[slot] !== {SLOT_BYTES{1'b1}} ||
            slot_pending_b[slot] != 0 || slot_good_b[slot] == 0)
            $fatal(1, "HDRCAP JOB before SOURCE/complete write tick=%0d lane=%0d frame=%0d slot=%0d SOURCE=%0d bytes=%0d pending_B=%0d OK_B=%0d",
                   tick, lane, frame, slot, source_at[lane][frame], $countones(slot_written[slot]), slot_pending_b[slot], slot_good_b[slot]);
        if (source_at[lane][frame] >= acquire_tick || slot_last_b[slot] > acquire_tick)
            $fatal(1, "HDRCAP ACQUIRE before SOURCE/last B tick=%0d lane=%0d frame=%0d acquire=%0d SOURCE=%0d last_B=%0d",
                   tick, lane, frame, acquire_tick, source_at[lane][frame], slot_last_b[slot]);
        for (int ordinal = 0; ordinal < 16; ordinal++) begin
            expected_word = raw_word(lane, frame, ordinal);
            for (int byte_index = 0; byte_index < 5; byte_index++) begin
                if (slot_data[slot][5*ordinal+byte_index] !== expected_word[8*byte_index +: 8])
                    $fatal(1, "HDRCAP RAW byte mismatch tick=%0d lane=%0d frame=%0d offset=%0d expected=%h actual=%h",
                           tick, lane, frame, 5*ordinal+byte_index, expected_word[8*byte_index +: 8], slot_data[slot][5*ordinal+byte_index]);
            end
        end
    endtask

    task automatic observe_service;
        int eye, frame, slot, elapsed;
        if (o_member_valid && i_member_ready) begin
            if (!service_active || member_at != 0 || o_member_index !== 1'b0)
                $fatal(1, "HDRCAP unexpected member offer tick=%0d", tick);
            member_at = tick;
        end
        if (o_context_valid && i_context_ready) begin
            if (!service_active || member_at == 0 || context_at != 0)
                $fatal(1, "HDRCAP unexpected context offer tick=%0d", tick);
            context_at = tick;
        end
        if (o_start_valid && i_start_ready) begin
            if (!service_active || context_at == 0 || start_at != 0)
                $fatal(1, "HDRCAP unexpected START tick=%0d", tick);
            start_at = tick;
        end
        if (i_result_valid && o_result_ready) begin
            if (!service_active || start_at == 0 || result_at != 0 || !i_result_ready)
                $fatal(1, "HDRCAP unexpected RESULT tick=%0d", tick);
            result_at = tick;
        end
        if (i_processing_done) begin
            if (!service_active || result_at == 0 || processing_at != 0 || i_processing_job_id !== id_in_service)
                $fatal(1, "HDRCAP bad modeled processing terminal tick=%0d", tick);
            processing_at = tick;
        end

        if (o_release_valid && o_release_ready) begin
            if (!service_active || processing_at == 0 || !i_ticket_released ||
                !i_reader_quiet || !i_product_quiet || !i_writer_quiet ||
                o_release_id !== id_in_service || int'(o_release_bank) != bank_in_service)
                $fatal(1, "HDRCAP premature or mismatched RELEASE tick=%0d id=%h bank=%0d", tick, o_release_id, o_release_bank);
            elapsed = tick - acquired_at;
            if (elapsed < service_ticks - 16 || elapsed > service_ticks + 16 ||
                (service_ticks < 1650 && elapsed >= 1650) || (service_ticks > 1650 && elapsed <= 1650))
                $fatal(1, "HDRCAP service outside deadline model tick=%0d target=%0d actual=%0d", tick, service_ticks, elapsed);
            if (elapsed < min_service) min_service = elapsed;
            if (elapsed > max_service) max_service = elapsed;
            release_at[eye_in_service][frame_in_service] = tick;
            release_total++;
            $display("HDRCAP RELEASE tick=%0d eye=%0d frame=%0d group=%0d bank=%0d id=%h acquire=%0d job=%0d member=%0d context=%0d start=%0d result=%0d processing=%0d service=%0d acquire_to_job=%0d job_to_start=%0d start_to_result=%0d",
                     tick, eye_in_service, frame_in_service, group_for(eye_in_service, frame_in_service), bank_in_service, id_in_service,
                     acquired_at, dispatched_at, member_at, context_at, start_at, result_at, processing_at,
                     elapsed, dispatched_at-acquired_at, start_at-dispatched_at, result_at-start_at);
            slot = 4 * eye_in_service + 2 * bank_in_service;
            for (int role = 0; role < 2; role++) begin
                if (slot_pending_b[slot+role] != 0)
                    $fatal(1, "HDRCAP RELEASE with B pending tick=%0d slot=%0d", tick, slot+role);
                slot_written[slot+role] = 0;
                slot_good_b[slot+role] = 0;
                slot_last_b[slot+role] = 0;
            end
            service_active = 0;
        end
        if (o_retire_done) begin
            if (retire_total >= release_total)
                $fatal(1, "HDRCAP retire acknowledgment without RELEASE tick=%0d", tick);
            retire_total++;
            $display("HDRCAP RETIRE_DONE tick=%0d ordinal=%0d", tick, retire_total);
        end

        if (o_pair_valid && o_pair_ready) begin
            if (pair_issued >= 2*FRAMES || $isunknown({o_pair_id, o_pair_bank}) || o_pair_id == 0)
                $fatal(1, "HDRCAP invalid pair acquire tick=%0d id=%h bank=%0d", tick, o_pair_id, o_pair_bank);
            for (int seen = 0; seen < pair_issued; seen++) begin
                if (pair_id[seen] === o_pair_id)
                    $fatal(1, "HDRCAP reused pair ID tick=%0d id=%h", tick, o_pair_id);
            end
            pair_id[pair_issued] = o_pair_id;
            pair_bank[pair_issued] = o_pair_bank;
            pair_at[pair_issued] = tick;
            pair_issued++;
            $display("HDRCAP ACQUIRE tick=%0d bank=%0d id=%h", tick, o_pair_bank, o_pair_id);
        end

        if (o_job_valid && o_job_ready) begin
            eye = o_job_frame[4];
            frame = int'(o_job_frame[366:335]) - 1000 * eye;
            if ($isunknown({o_job_frame[4], o_job_frame[366:335], o_job_frame[108:77]}) ||
                frame < 1 || frame > FRAMES || frame <= last_job_frame[eye] ||
                o_job_frame[108:77] !== sequence_for(2*eye, frame))
                $fatal(1, "HDRCAP unexpected JOB identity tick=%0d eye=%0d group=%0d seq=%0d", tick, eye, o_job_frame[366:335], o_job_frame[108:77]);
            if (service_active || pair_used >= pair_issued ||
                o_job_pair_id !== pair_id[pair_used] || o_job_id !== pair_id[pair_used] ||
                $isunknown({o_job_lease0, o_job_lease1}) || o_job_lease0 == 0 || o_job_lease1 == 0 || o_job_lease0 == o_job_lease1)
                $fatal(1, "HDRCAP invalid JOB acquire or leases tick=%0d job=%h pair=%h lease0=%h lease1=%h",
                       tick, o_job_id, o_job_pair_id, o_job_lease0, o_job_lease1);
            slot = 4 * eye + 2 * pair_bank[pair_used];
            check_member_write(slot, 2*eye, frame, pair_at[pair_used]);
            check_member_write(slot+1, 2*eye+1, frame, pair_at[pair_used]);
            service_active = 1;
            eye_in_service = eye;
            frame_in_service = frame;
            bank_in_service = pair_bank[pair_used];
            id_in_service = o_job_id;
            acquired_at = pair_at[pair_used];
            dispatched_at = tick;
            member_at = 0;
            context_at = 0;
            start_at = 0;
            result_at = 0;
            processing_at = 0;
            pair_used++;
            last_job_frame[eye] = frame;
            job_at[eye][frame] = tick;
            $display("HDRCAP JOB tick=%0d eye=%0d frame=%0d group=%0d seq=%0d bank=%0d id=%h pair_id=%h lease0=%h lease1=%h long_B=%0d short_B=%0d long_last_B=%0d short_last_B=%0d",
                     tick, eye, frame, o_job_frame[366:335], o_job_frame[108:77], bank_in_service,
                     o_job_id, o_job_pair_id, o_job_lease0, o_job_lease1, slot_good_b[slot], slot_good_b[slot+1],
                     slot_last_b[slot], slot_last_b[slot+1]);
        end
    endtask

    always @(negedge dfi_clk) begin : drive_service_and_ddr
        int next_edge, b_entry, deadline;
        i_now_ns = 64'd1000000 + $time / 1000;
        next_edge = tick + 1;
        m_axi_wready = !first_case || tick % 11 >= 3;
        b_entry = b_consumed % AXI_DEPTH;
        m_axi_bvalid = b_consumed < b_issued && next_edge >= b_due[b_entry];
        if (m_axi_bvalid) m_axi_bid = b_id[b_entry];

        i_member_ready = service_active && member_at == 0;
        i_context_ready = service_active && member_at != 0 && context_at == 0;
        i_start_ready = service_active && context_at != 0 && start_at == 0;
        i_result_valid = 0;
        i_processing_done = 0;
        i_reader_quiet = 1;
        i_product_quiet = 1;
        i_writer_quiet = 1;
        i_ticket_released = 1;
        if (service_active && start_at != 0) begin
            deadline = acquired_at + service_ticks;
            i_result_valid = result_at == 0 && next_edge >= deadline - 12;
            i_reader_quiet = result_at != 0 && next_edge >= deadline - 9;
            i_product_quiet = result_at != 0 && next_edge >= deadline - 8;
            i_writer_quiet = result_at != 0 && next_edge >= deadline - 7;
            i_processing_done = i_reader_quiet && i_product_quiet && i_writer_quiet &&
                                processing_at == 0 && next_edge >= deadline - 5;
            i_processing_job_id = id_in_service;
            i_ticket_released = processing_at != 0 && next_edge >= deadline - 4;
        end
    end

    always @(posedge dfi_clk) begin : sample_dfi
        int lane, frame;
        tick++;
        if (rst_n) begin
            if (o_cfg_error === 1'b1) $fatal(1, "HDRCAP configuration error tick=%0d", tick);
            if (o_cfg_done) cfg_done_seen = 1;
        end
        if (observing) begin
            if ({o_fault, o_pair_expire, o_bad_finish} !== 7'b0)
                $fatal(1, "HDRCAP fault/expire/finish tick=%0d fault=%b expire=%b finish=%b", tick, o_fault, o_pair_expire, o_bad_finish);
            observe_axi();
            observe_service();
            for (int eye = 0; eye < 2; eye++) begin
                if (o_begin_reject[eye]) begin
                    lane = recent_lane[eye];
                    frame = recent_frame[eye];
                    if (frame == 0 || reject_at[lane][frame] != 0)
                        $fatal(1, "HDRCAP unmatched/duplicate BEGIN reject tick=%0d eye=%0d lane=%0d frame=%0d", tick, eye, lane, frame);
                    if (late_peer_case && eye == 0 && lane == 0 && frame == 3 &&
                        (o_bank_states[1:0] == 0 || o_bank_states[3:2] == 0))
                        $fatal(1, "HDRCAP late-peer LONG reject lacked two occupied banks tick=%0d banks=%h", tick, o_bank_states);
                    reject_at[lane][frame] = tick;
                    $display("HDRCAP BEGIN_REJECT tick=%0d eye=%0d role=%0d frame=%0d banks=%h", tick, eye, lane % 2, frame, o_bank_states);
                end
            end
        end
    end

    task automatic check_ledger;
        int first_frame, last_frame, lane, total_gaps, last_source;
        int steady_begin, steady_end, jobs, releases, rejects[2], tail_releases;
        int steady_sof[2], steady_source[2], steady_job, steady_release;
        first_frame = rate_case ? WARMUP + 1 : 1;
        last_frame = rate_case ? FRAMES : (late_peer_case ? 4 : 1);
        steady_begin = origin + WARMUP * PERIOD;
        steady_end = origin + FRAMES * PERIOD;
        total_gaps = 0;
        last_source = 0;
        for (lane = 0; lane < 4; lane++) begin
            for (int frame = 1; frame <= last_frame; frame++) begin
                if (late_peer_case && lane >= 2) continue;
                if (sof_at[lane][frame] == 0 || source_at[lane][frame] <= sof_at[lane][frame])
                    $fatal(1, "HDRCAP missing physical SOF/SOURCE lane=%0d frame=%0d", lane, frame);
                if (source_at[lane][frame] > last_source) last_source = source_at[lane][frame];
            end
        end
        for (int eye = 0; eye < 2; eye++) begin
            if (late_peer_case && eye == 1) continue;
            jobs = 0;
            releases = 0;
            rejects = '{default:0};
            tail_releases = 0;
            steady_sof = '{default:0};
            steady_source = '{default:0};
            steady_job = 0;
            steady_release = 0;
            for (int frame = 1; frame <= last_frame; frame++) begin
                if (job_at[eye][frame] != 0) begin
                    if (release_at[eye][frame] <= job_at[eye][frame] ||
                        reject_at[2*eye][frame] != 0 || reject_at[2*eye+1][frame] != 0)
                        $fatal(1, "HDRCAP JOB not retired cleanly eye=%0d frame=%0d", eye, frame);
                    if (frame >= first_frame) begin
                        jobs++;
                        releases++;
                        if (release_at[eye][frame] > last_source) tail_releases++;
                    end
                end else begin
                    if (!late_peer_case && service_ticks < 1650)
                        $fatal(1, "HDRCAP fast-service group lost eye=%0d frame=%0d", eye, frame);
                    if (release_at[eye][frame] != 0 || reject_at[2*eye][frame] == 0 || reject_at[2*eye+1][frame] == 0)
                        $fatal(1, "HDRCAP missing JOB without both negative BEGINs eye=%0d frame=%0d", eye, frame);
                    if (frame >= first_frame) total_gaps++;
                end
                for (int role = 0; role < 2; role++) begin
                    lane = 2 * eye + role;
                    if (frame >= first_frame && reject_at[lane][frame] != 0) rejects[role]++;
                    if (sof_at[lane][frame] >= steady_begin && sof_at[lane][frame] < steady_end) steady_sof[role]++;
                    if (source_at[lane][frame] >= steady_begin && source_at[lane][frame] < steady_end) steady_source[role]++;
                end
                if (job_at[eye][frame] >= steady_begin && job_at[eye][frame] < steady_end) steady_job++;
                if (release_at[eye][frame] >= steady_begin && release_at[eye][frame] < steady_end) steady_release++;
            end
            if (jobs == 0 || (!late_peer_case && service_ticks < 1650 && jobs != last_frame - first_frame + 1))
                $fatal(1, "HDRCAP measured eye capacity eye=%0d jobs=%0d offered=%0d", eye, jobs, last_frame-first_frame+1);
            if (job_at[eye][1] == 0)
                $fatal(1, "HDRCAP missing initial positive group eye=%0d", eye);
            $display("HDRCAP EYE eye=%0d offered=%0d long_SOURCE=%0d short_SOURCE=%0d jobs=%0d releases=%0d long_reject=%0d short_reject=%0d drain_releases=%0d",
                     eye, last_frame-first_frame+1, last_frame-first_frame+1, last_frame-first_frame+1,
                     jobs, releases, rejects[0], rejects[1], tail_releases);
            if (rate_case)
                $display("HDRCAP WINDOW eye=%0d begin=%0d end=%0d long_SOF=%0d short_SOF=%0d long_SOURCE=%0d short_SOURCE=%0d jobs=%0d releases=%0d",
                         eye, steady_begin, steady_end, steady_sof[0], steady_sof[1], steady_source[0], steady_source[1], steady_job, steady_release);
        end
        if (rate_case && service_ticks > 1650 && total_gaps == 0)
            $fatal(1, "HDRCAP slow-service run had no measured capacity gap");
        if (first_case && w_stall_ticks == 0)
            $fatal(1, "HDRCAP first case did not exercise W backpressure");
        if (late_peer_case) begin
            if (total_gaps != 1 || job_at[0][3] != 0 ||
                job_at[0][1] == 0 || job_at[0][2] == 0 || job_at[0][4] == 0 ||
                !(source_at[1][2] < sof_at[0][3] && reject_at[0][3] < release_at[0][1] &&
                  release_at[0][1] < sof_at[1][3] && sof_at[1][3] < reject_at[1][3] &&
                  reject_at[1][3] < sof_at[0][4] && release_at[0][2] > reject_at[1][3]))
                $fatal(1, "HDRCAP missing full/old release/late peer reject/next group recovery ordering");
            $display("HDRCAP RECOVERY long_reject=%0d old_release=%0d late_short_SOF=%0d late_short_reject=%0d next_long_SOF=%0d next_release=%0d",
                     reject_at[0][3], release_at[0][1], sof_at[1][3], reject_at[1][3], sof_at[0][4], release_at[0][4]);
        end
        if (service_active || pair_used != pair_issued || pair_used != release_total || release_total != retire_total ||
            b_consumed != b_issued || aw_issued != aw_consumed || aw_consumed != b_issued || o_bank_states !== 8'b0 ||
            o_quiescent !== 1'b1 || o_capture_write_quiet !== 1'b1 || o_scheduler_busy !== 1'b0)
            $fatal(1, "HDRCAP incomplete final drain tick=%0d acquire=%0d job=%0d release=%0d retire=%0d AW=%0d B=%0d banks=%h",
                   tick, pair_issued, pair_used, release_total, retire_total, aw_issued, b_consumed, o_bank_states);
        for (int slot = 0; slot < 8; slot++) begin
            if (slot_written[slot] !== 0 || slot_pending_b[slot] != 0 || slot_good_b[slot] != 0 || slot_last_b[slot] != 0)
                $fatal(1, "HDRCAP orphan AXI write slot=%0d", slot);
        end
        $display("HDRCAP PASS scenario=%s phase=%0d target=%0d min_service=%0d max_service=%0d acquire=%0d jobs=%0d releases=%0d retire=%0d AW=%0d W=%0d B=%0d W_stall=%0d last_SOURCE=%0d drained=%0d",
                 scenario, phase_ticks, service_ticks, min_service, max_service, pair_issued, pair_used, release_total, retire_total,
                 aw_issued, w_total, b_consumed, w_stall_ticks, last_source, tick);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", scenario)) $fatal(1, "HDRCAP missing CASE");
        phase_ticks = 0;
        service_ticks = 1590;
        case (scenario)
            "first": first_case = 1;
            "late-peer": late_peer_case = 1;
            "fast100", "fast400", "fast3200", "slow100", "slow400", "slow3200": begin
                rate_case = 1;
                if (scenario.substr(0, 3) == "slow") service_ticks = 1950;
                if ($sscanf(scenario.substr(4, scenario.len()-1), "%d", phase_ticks) != 1)
                    $fatal(1, "HDRCAP invalid phase name %s", scenario);
            end
            default: $fatal(1, "HDRCAP unknown CASE=%s", scenario);
        endcase

        repeat (24) @(negedge dfi_clk);
        rst_n = 1;
        repeat (32) @(negedge dfi_clk);
        i_cfg_valid = 1;
        do @(posedge dfi_clk); while (o_cfg_ready !== 1'b1);
        @(negedge dfi_clk);
        i_cfg_valid = 0;
        while (!cfg_done_seen || o_policy_admit !== 1'b1) @(negedge dfi_clk);
        repeat (16) @(negedge pixel_clk);

        origin = tick + 32;
        observing = 1;
        $display("HDRCAP RUN scenario=%s origin=%0d target=%0d phase=%0d", scenario, origin, service_ticks, phase_ticks);
        fork
            drive_lane(0);
            drive_lane(1);
            drive_lane(2);
            drive_lane(3);
        join

        // Do not terminate on an idle level that predates a pending CDC delivery.
        repeat (32) @(negedge dfi_clk);
        while (o_quiescent !== 1'b1 || service_active || release_total != retire_total) @(negedge dfi_clk);
        repeat (32) @(negedge dfi_clk);
        check_ledger();
        $finish;
    end
endmodule
