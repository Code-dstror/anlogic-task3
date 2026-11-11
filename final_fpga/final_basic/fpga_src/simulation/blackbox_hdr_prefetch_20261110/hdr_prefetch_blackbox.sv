`timescale 1ns/1ps

module hdr_prefetch_blackbox;
    localparam int WIDTH = 68;
    localparam int HEIGHT = 63;
    localparam int GROUPS = WIDTH * HEIGHT / 4;
    localparam int FRAME_BYTES = GROUPS * 5;
    localparam int FRAME_WORDS = (FRAME_BYTES + 15) / 16;
    localparam int MAX_BURSTS = 2 * FRAME_WORDS + 1;
    localparam int OTHER_ADDR = 'h00ff00;
    localparam int OTHER_BEATS = 4;
    localparam int PERF = 0, STALL = 1, CANCEL_AR = 2, CANCEL_R = 3;
    localparam int BAD_RESP = 4, BAD_ID = 5, BAD_LAST = 6, OVERLAP = 7;

    logic clk = 0;
    always #3.751 clk = ~clk;
    PH1_PHY_GSR PH1_PHY_GSR();

    logic reset_n = 0, start_valid = 0, camera = 0, bank = 0, cancel = 0;
    logic out_ready = 1, result_ready = 1;
    wire start_ready, result_valid, result_ok, read_quiet, reader_fault;
    wire out_valid, out_sof, out_eol, out_eof;
    wire [31:0] out_index;
    wire [55:0] out_raw;
    wire [3:0] out_motion;
    wire [9:0] long_occupancy, short_occupancy;

    wire s1_arvalid, s1_arready, s1_rvalid, s1_rready, s1_rlast;
    wire [3:0] s1_arid, s1_rid;
    wire [27:0] s1_araddr;
    wire [7:0] s1_arlen;
    wire [2:0] s1_arsize;
    wire [1:0] s1_arburst, s1_rresp;
    wire [127:0] s1_rdata;

    logic s0_arvalid = 0, s0_rready = 1;
    wire s0_arready, s0_rvalid, s0_rlast;
    wire [3:0] s0_rid;
    wire [1:0] s0_rresp;
    wire [127:0] s0_rdata;

    wire m_arvalid, m_rready, arb_fault, arb_recovery;
    wire [3:0] m_arid;
    wire [27:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_awvalid, m_wvalid, s0_bvalid, s1_bvalid;
    logic allow_ar = 1, gap_r = 0;
    wire m_arready = reset_n && allow_ar;
    logic m_rvalid = 0, m_rlast = 0;
    logic [3:0] m_rid = 0;
    logic [127:0] m_rdata = 0;
    logic [1:0] m_rresp = 0;

    seed12_hdr_reader_carrier #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) reader (
        .i_clk(clk), .i_identity_rst_n(reset_n),
        .i_start_valid(start_valid), .i_pair_bank(bank), .i_pair_camera(camera),
        .o_start_ready(start_ready), .i_ratio_log2(3'd4),
        .i_black_long(10'd50), .i_black_short(10'd50),
        .i_motion_base(14'd64), .i_motion_shift(4'd3), .i_cancel(cancel),
        .m_raw(out_raw), .m_motion(out_motion), .m_valid(out_valid),
        .m_sof(out_sof), .m_eol(out_eol), .m_eof(out_eof), .m_index(out_index),
        .m_ready(out_ready), .o_result_valid(result_valid), .o_result_ok(result_ok),
        .i_result_ready(result_ready), .o_read_quiet(read_quiet), .o_protocol_fault(reader_fault),
        .o_long_occupancy(long_occupancy), .o_short_occupancy(short_occupancy),
        .m_axi_arid(s1_arid), .m_axi_araddr(s1_araddr), .m_axi_arlen(s1_arlen),
        .m_axi_arsize(s1_arsize), .m_axi_arburst(s1_arburst), .m_axi_arvalid(s1_arvalid),
        .m_axi_arready(s1_arready), .m_axi_rid(s1_rid), .m_axi_rdata(s1_rdata),
        .m_axi_rresp(s1_rresp), .m_axi_rlast(s1_rlast), .m_axi_rvalid(s1_rvalid),
        .m_axi_rready(s1_rready)
    );

    ddr_axi_two_client_arbiter arbiter (
        .clk(clk), .rst_n(reset_n), .fault(arb_fault), .o_recovery_required(arb_recovery),
        .s0_awid(4'd0), .s0_awaddr(28'd0), .s0_awlen(8'd0),
        .s0_awsize(3'd0), .s0_awburst(2'd0), .s0_awvalid(1'b0),
        .s0_wdata(128'd0), .s0_wstrb(16'd0), .s0_wlast(1'b0), .s0_wvalid(1'b0),
        .s0_bvalid(s0_bvalid), .s0_bready(1'b1),
        .s0_arid(4'd6), .s0_araddr(28'h00ff00), .s0_arlen(8'd3),
        .s0_arsize(3'd4), .s0_arburst(2'd1), .s0_arvalid(s0_arvalid), .s0_arready(s0_arready),
        .s0_rid(s0_rid), .s0_rdata(s0_rdata), .s0_rresp(s0_rresp),
        .s0_rlast(s0_rlast), .s0_rvalid(s0_rvalid), .s0_rready(s0_rready),
        .s1_awid(4'd0), .s1_awaddr(28'd0), .s1_awlen(8'd0),
        .s1_awsize(3'd0), .s1_awburst(2'd0), .s1_awvalid(1'b0),
        .s1_wdata(128'd0), .s1_wstrb(16'd0), .s1_wlast(1'b0), .s1_wvalid(1'b0),
        .s1_bvalid(s1_bvalid), .s1_bready(1'b1),
        .s1_arid(s1_arid), .s1_araddr(s1_araddr), .s1_arlen(s1_arlen),
        .s1_arsize(s1_arsize), .s1_arburst(s1_arburst), .s1_arvalid(s1_arvalid), .s1_arready(s1_arready),
        .s1_rid(s1_rid), .s1_rdata(s1_rdata), .s1_rresp(s1_rresp),
        .s1_rlast(s1_rlast), .s1_rvalid(s1_rvalid), .s1_rready(s1_rready),
        .m_awvalid(m_awvalid), .m_awready(1'b1), .m_wvalid(m_wvalid), .m_wready(1'b1),
        .m_bid(4'd0), .m_bresp(2'd0), .m_bvalid(1'b0),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    typedef struct packed {
        int address;
        int beats;
        int member;
        int sequence_no;
        int first_edge;
        logic [3:0] id;
    } read_request;

    read_request reader_requests[0:MAX_BURSTS-1];
    read_request memory_requests[0:MAX_BURSTS-1];

    int scenario, cycle = 0, tag = 0, fault_mode = 0, latency = 32;
    int camera_id, bank_id;
    logic job_live = 0, expect_ok;
    int start_cycle = -1, result_cycle, result_offers, results;
    int reader_ar, reader_ar_forwarded, reader_r, reader_done, reader_beat;
    int master_ar, master_r, master_done, master_beat, master_last_cycle;
    int other_ar, other_ar_forwarded, other_r;
    int outputs, motion_groups, member_words[0:1], peak_long, peak_short;
    int cancel_limit, ar_stalls, output_stalls, master_r_stalls, reader_r_stalls;
    int idle_edges, idle_intervals, max_idle, first_min, first_max;
    int r_holes, simultaneous, first_overlap_cycle;
    logic [2:0] simultaneous_regions;
    logic [1:0] wrap_stalls;
    logic result_was_stalled, last_result_ok;
    logic out_was_stalled, reader_ar_was_stalled, master_ar_was_stalled;
    logic reader_r_was_stalled, master_r_was_stalled, other_r_was_stalled;
    logic [94:0] last_out;
    logic [44:0] last_reader_ar, last_master_ar;
    logic [134:0] last_reader_r, last_master_r, last_other_r;
    logic master_r_accepted = 0, gap_offered = 0, bad_offer_now = 0;
    logic bad_offered, bad_accepted;
    logic [63:0] digest;

    function automatic int base_addr(input int cam, selected_bank, member);
        return 'h02000000 + (4 * cam + 2 * selected_bank + member) * 'h01000000;
    endfunction

    function automatic int pixel(input int member, job_tag, index, lane);
        int variation, long_raw, short_raw;
        variation = index * 19 + (index / 17) * 23 + lane * 11 + job_tag * 31;
        case ((index + job_tag) % 8)
            0: begin
                long_raw = 45 + variation % 13;
                short_raw = 47 + variation % 8;
            end
            1: begin
                long_raw = 180 + variation % 580;
                short_raw = 50 + (long_raw - 50 + 8) / 16 + variation % 3 - 1;
            end
            2: begin
                case (lane)
                    0: long_raw = 767;
                    1: long_raw = 768;
                    2: long_raw = 775;
                    3: long_raw = 776;
                endcase
                short_raw = 50 + (long_raw - 50 + 8) / 16 + variation % 5 - 2;
            end
            3: begin
                case (lane)
                    0: long_raw = 887;
                    1: long_raw = 888;
                    2: long_raw = 895;
                    3: long_raw = 896;
                endcase
                short_raw = 50 + (long_raw - 50 + 8) / 16 + variation % 5 - 2;
            end
            4: begin
                long_raw = 500 + variation % 180;
                short_raw = 50 + (long_raw - 50 + 8) / 16;
                if (lane == (index / 8 + job_tag) % 4)
                    short_raw = 170 + variation % 110;
            end
            5: begin
                long_raw = 896 + variation % 128;
                short_raw = 150 + variation % 874;
            end
            6: begin
                long_raw = 50 + 128 * (lane + 1);
                short_raw = 50 + (long_raw - 50 + 64 + (long_raw - 50) / 8) / 16;
            end
            default: begin
                long_raw = 200 + variation % 500;
                short_raw = 50 + (long_raw - 50 + 8) / 16;
                if (lane == (index / 8 + job_tag) % 4) begin
                    long_raw = 192;
                    short_raw = 64;
                end
            end
        endcase
        return member == 0 ? long_raw : short_raw;
    endfunction

    function automatic logic [7:0] image_byte(input int member, offset);
        logic [39:0] packed_raw10;
        if (offset >= FRAME_BYTES)
            return 8'('ha5 ^ (offset * 7) ^ (tag * 13) ^ member);
        for (int lane = 0; lane < 4; lane++)
            packed_raw10[lane * 10 +: 10] = 10'(pixel(member, tag, offset / 5, lane));
        return packed_raw10[(offset % 5) * 8 +: 8];
    endfunction

    function automatic logic [127:0] response_data(input read_request request, input int beat);
        logic [127:0] data;
        int offset;
        if (request.member < 0) begin
            for (int octet = 0; octet < 16; octet++)
                data[octet * 8 +: 8] = 8'('hd6 ^ (beat * 29 + octet * 13));
        end else begin
            offset = request.address - base_addr(camera_id, bank_id, request.member) + beat * 16;
            for (int octet = 0; octet < 16; octet++)
                data[octet * 8 +: 8] = image_byte(request.member, offset + octet);
        end
        return data;
    endfunction

    function automatic logic [59:0] expected_output(input int index);
        int long_linear[0:3], short_linear[0:3], weight[0:3];
        int long_raw, short_raw, distance, value;
        bit motion;
        logic [55:0] data;
        motion = 0;
        for (int lane = 0; lane < 4; lane++) begin
            long_raw = pixel(0, tag, index, lane);
            short_raw = pixel(1, tag, index, lane);
            long_linear[lane] = long_raw > 50 ? long_raw - 50 : 0;
            short_linear[lane] = short_raw > 50 ? (short_raw - 50) * 16 : 0;
            weight[lane] = long_raw < 768 ? 0 : (long_raw - 768) / 8;
            if (weight[lane] > 16)
                weight[lane] = 16;
            distance = long_linear[lane] - short_linear[lane];
            if (distance < 0)
                distance = -distance;
            if (long_raw < 896 && short_raw > 54 && distance > 64 + long_linear[lane] / 8)
                motion = 1;
        end
        for (int lane = 0; lane < 4; lane++) begin
            value = ((16 - weight[lane]) * long_linear[lane] + weight[lane] * short_linear[lane] + 8) / 16;
            data[lane * 14 +: 14] = 14'(motion ? short_linear[lane] : value);
        end
        return {motion ? 4'hf : 4'h0, data};
    endfunction

    function automatic logic damaged(input read_request request, input int beat);
        if (fault_mode == 0 || request.member < 0 || request.sequence_no != 0)
            return 0;
        return fault_mode == BAD_LAST ? beat == request.beats - 1 : beat == 0;
    endfunction

    function automatic logic [6:0] response_header(input read_request request, input int beat);
        logic [3:0] id;
        logic [1:0] resp;
        logic last;
        id = request.id;
        resp = 2'b00;
        last = beat == request.beats - 1;
        if (damaged(request, beat)) begin
            case (fault_mode)
                BAD_RESP: resp = 2'b10;
                BAD_ID: id = request.id ^ 4'h8;
                BAD_LAST: last = 0;
            endcase
        end
        return {id, resp, last};
    endfunction

    task automatic demand(input logic condition, input string detail);
        if (condition !== 1'b1) begin
            $display("CHECK_FAIL case=%0d tag=%0d edge=%0d start=%0d reader_ar=%0d reader_r=%0d master_ar=%0d master_r=%0d raw=%0d %s",
                     scenario, tag, cycle, start_cycle, reader_ar, reader_r, master_ar, master_r, outputs, detail);
            $fatal(1, "%s", detail);
        end
    endtask

    always @(negedge clk) begin : memory_source
        read_request request;
        gap_offered = 0;
        if (!reset_n || !job_live) begin
            m_rvalid = 0;
            bad_offer_now = 0;
        end else if (!m_rvalid || master_r_accepted) begin
            m_rvalid = 0;
            bad_offer_now = 0;
            if (master_done < master_ar) begin
                request = memory_requests[master_done];
                if (cycle + 1 >= request.first_edge) begin
                    if (gap_r && master_beat != 0 && (cycle + 1) % 4 == 0) begin
                        gap_offered = 1;
                    end else begin
                        {m_rid, m_rresp, m_rlast} = response_header(request, master_beat);
                        m_rdata = response_data(request, master_beat);
                        m_rvalid = 1;
                        bad_offer_now = damaged(request, master_beat);
                    end
                end
            end
        end
    end

    always @(posedge clk) begin : scoreboard
        int bytes, member, idle, latency_seen;
        logic [59:0] reference_out;
        read_request request;
        cycle = cycle + 1;
        master_r_accepted = 0;
        if (!reset_n) begin
            result_was_stalled = 0;
            out_was_stalled = 0;
            reader_ar_was_stalled = 0;
            master_ar_was_stalled = 0;
            reader_r_was_stalled = 0;
            master_r_was_stalled = 0;
            other_r_was_stalled = 0;
        end else if (job_live) begin
            demand(!$isunknown({m_awvalid, m_wvalid, s0_bvalid, s1_bvalid}) &&
                   !(m_awvalid || m_wvalid || s0_bvalid || s1_bvalid), "unexpected write traffic");
            demand(!$isunknown({long_occupancy, short_occupancy}) &&
                   long_occupancy <= 512 && short_occupancy <= 512, "member occupancy outside 0..512");
            if (long_occupancy > peak_long)
                peak_long = long_occupancy;
            if (short_occupancy > peak_short)
                peak_short = short_occupancy;
            if (fault_mode == 0)
                demand(!(reader_fault || arb_fault || arb_recovery), "unexpected read fault");
            if (fault_mode == BAD_RESP)
                demand(!arb_recovery, "a legal error response entered protocol recovery");

            if (start_valid && start_ready) begin
                demand(start_cycle < 0, "duplicate START handshake");
                start_cycle = cycle;
            end
            if (out_was_stalled)
                demand(out_valid && {out_raw, out_motion, out_index, out_sof, out_eol, out_eof} === last_out,
                       "RAW offer changed while stalled");
            if (result_was_stalled)
                demand(result_valid && result_ok === last_result_ok, "RESULT changed while stalled");
            if (reader_ar_was_stalled)
                demand(s1_arvalid && {s1_arid, s1_araddr, s1_arlen, s1_arsize, s1_arburst} === last_reader_ar,
                       "reader AR offer changed while stalled");
            if (master_ar_was_stalled && !(bad_offered && fault_mode inside {BAD_ID, BAD_LAST}))
                demand(m_arvalid && {m_arid, m_araddr, m_arlen, m_arsize, m_arburst} === last_master_ar,
                       "master AR offer changed while stalled");
            if (reader_r_was_stalled && !(bad_offered && fault_mode inside {BAD_ID, BAD_LAST}))
                demand(s1_rvalid && {s1_rid, s1_rresp, s1_rlast, s1_rdata} === last_reader_r,
                       "reader R offer changed while stalled");
            if (master_r_was_stalled)
                demand(m_rvalid && {m_rid, m_rresp, m_rlast, m_rdata} === last_master_r,
                       "memory R offer changed while stalled");
            if (other_r_was_stalled)
                demand(s0_rvalid && {s0_rid, s0_rresp, s0_rlast, s0_rdata} === last_other_r,
                       "competing client R offer changed while stalled");

            out_was_stalled = out_valid && !out_ready;
            result_was_stalled = result_valid && !result_ready;
            reader_ar_was_stalled = s1_arvalid && !s1_arready;
            master_ar_was_stalled = m_arvalid && !m_arready;
            reader_r_was_stalled = s1_rvalid && !s1_rready;
            master_r_was_stalled = m_rvalid && !m_rready;
            other_r_was_stalled = s0_rvalid && !s0_rready;
            last_out = {out_raw, out_motion, out_index, out_sof, out_eol, out_eof};
            last_result_ok = result_ok;
            last_reader_ar = {s1_arid, s1_araddr, s1_arlen, s1_arsize, s1_arburst};
            last_master_ar = {m_arid, m_araddr, m_arlen, m_arsize, m_arburst};
            last_reader_r = {s1_rid, s1_rresp, s1_rlast, s1_rdata};
            last_master_r = {m_rid, m_rresp, m_rlast, m_rdata};
            last_other_r = {s0_rid, s0_rresp, s0_rlast, s0_rdata};

            if (out_was_stalled) begin
                output_stalls++;
                if (out_index == 510)
                    wrap_stalls[0] = 1;
                if (out_index == 1022)
                    wrap_stalls[1] = 1;
            end
            if (master_ar_was_stalled)
                ar_stalls++;
            if (master_r_was_stalled)
                master_r_stalls++;
            if (reader_r_was_stalled)
                reader_r_stalls++;
            if (gap_offered)
                r_holes++;
            if (bad_offer_now)
                bad_offered = 1;

            if (s1_arvalid && cancel_limit >= 0)
                demand(reader_ar < cancel_limit, "new, unpromised reader AR after cancel");
            if (s1_arvalid && s1_arready) begin
                demand(start_cycle >= 0 && results == 0 && reader_ar < MAX_BURSTS,
                       "reader AR without an active START or beyond scoreboard bounds");
                demand(!$isunknown({s1_arid, s1_araddr, s1_arlen, s1_arsize, s1_arburst}) &&
                       s1_arid == 1 && s1_arsize == 4 && s1_arburst == 1 && s1_arlen <= 15 && s1_araddr[3:0] == 0,
                       "reader AR format");
                bytes = (int'(s1_arlen) + 1) * 16;
                demand(int'(s1_araddr[11:0]) + bytes <= 4096, "reader AR crosses 4 KiB");
                member = int'(s1_araddr) >= base_addr(camera_id, bank_id, 1) ? 1 : 0;
                demand(int'(s1_araddr) == base_addr(camera_id, bank_id, member) + 16 * member_words[member],
                       $sformatf("incorrect reader byte address %h, member=%0d next_word=%0d", s1_araddr,
                                 member, member_words[member]));
                member_words[member] += int'(s1_arlen) + 1;
                demand(member_words[member] <= FRAME_WORDS, "reader requested bytes past rounded frame");
                reader_requests[reader_ar] = '{int'(s1_araddr), int'(s1_arlen) + 1, member, reader_ar, 0, s1_arid};
                $display("READER_AR tag=%0d edge=%0d addr=%h beats=%0d member=%0d", tag, cycle,
                         s1_araddr, int'(s1_arlen) + 1, member);
                reader_ar++;
            end
            if (s0_arvalid && s0_arready) begin
                demand(other_ar == 0 && scenario == OVERLAP, "unexpected competing AR acceptance");
                other_ar++;
            end
            if (m_arvalid && m_arready) begin
                demand(master_ar < MAX_BURSTS && !$isunknown({m_arid, m_araddr, m_arlen, m_arsize, m_arburst}),
                       "invalid master AR");
                if (int'(m_araddr) == OTHER_ADDR) begin
                    demand(other_ar_forwarded < other_ar, "master accepted an unpromised competing AR");
                    request = '{OTHER_ADDR, OTHER_BEATS, -1, 0, 0, 4'd6};
                    other_ar_forwarded++;
                end else begin
                    demand(reader_ar_forwarded < reader_ar, "master accepted an unpromised reader AR");
                    request = reader_requests[reader_ar_forwarded];
                    reader_ar_forwarded++;
                end
                demand({m_arid, m_araddr, m_arlen, m_arsize, m_arburst} ===
                       {request.id, 28'(request.address), 8'(request.beats - 1), 3'd4, 2'd1},
                       "arbiter altered AR identity, address or length");
                idle = -1;
                if (master_ar == master_done && master_last_cycle >= 0) begin
                    idle = cycle - master_last_cycle - 1;
                    idle_edges += idle;
                    idle_intervals++;
                    if (idle > max_idle)
                        max_idle = idle;
                end
                request.first_edge = cycle + latency;
                memory_requests[master_ar] = request;
                $display("MASTER_AR tag=%0d edge=%0d addr=%h beats=%0d id=%0d idle_since_previous_rlast=%0d",
                         tag, cycle, m_araddr, request.beats, m_arid, idle);
                master_ar++;
            end

            if (m_rvalid && m_rready) begin
                master_r_accepted = 1;
                demand(master_done < master_ar, "memory response without accepted master AR");
                request = memory_requests[master_done];
                if (bad_offer_now)
                    bad_accepted = 1;
                if (master_beat == 0) begin
                    latency_seen = cycle - request.first_edge + latency;
                    if (latency_seen < first_min)
                        first_min = latency_seen;
                    if (latency_seen > first_max)
                        first_max = latency_seen;
                    $display("MASTER_RFIRST tag=%0d edge=%0d addr=%h accepted_ar_to_r=%0d",
                             tag, cycle, request.address, latency_seen);
                end
                master_beat++;
                master_r++;
                if (master_beat == request.beats) begin
                    $display("MASTER_RTAIL tag=%0d edge=%0d addr=%h observed_rlast=%b", tag, cycle,
                             request.address, m_rlast);
                    master_beat = 0;
                    master_done++;
                    master_last_cycle = cycle;
                end
            end
            if (s1_rvalid && s1_rready) begin
                demand(reader_done < reader_ar && reader_r + other_r < master_r,
                       "reader response without a matching accepted memory beat");
                request = reader_requests[reader_done];
                demand({s1_rid, s1_rresp, s1_rlast} === response_header(request, reader_beat) &&
                       s1_rdata === response_data(request, reader_beat), "incorrect routed reader R beat");
                if (reader_beat == 0 || reader_beat + 1 == request.beats)
                    $display("READER_R tag=%0d edge=%0d addr=%h burst_beat=%0d observed_rlast=%b",
                             tag, cycle, request.address, reader_beat, s1_rlast);
                reader_r++;
                reader_beat++;
                if (reader_beat == request.beats) begin
                    reader_beat = 0;
                    reader_done++;
                end
            end
            if (s0_rvalid && s0_rready) begin
                demand(other_ar == 1 && other_r < OTHER_BEATS && reader_r + other_r < master_r,
                       "competing client response without a matching accepted memory beat");
                request = '{OTHER_ADDR, OTHER_BEATS, -1, 0, 0, 4'd6};
                demand({s0_rid, s0_rresp, s0_rlast} === response_header(request, other_r) &&
                       s0_rdata === response_data(request, other_r), "incorrect routed competing client R beat");
                other_r++;
            end

            if (out_valid && out_ready) begin
                demand(start_cycle >= 0 && outputs < GROUPS && results == 0, "output outside accepted job");
                reference_out = expected_output(outputs);
                demand({out_motion, out_raw} === reference_out,
                       $sformatf("RAW oracle index=%0d actual=%h expected=%h", outputs,
                                 {out_motion, out_raw}, reference_out));
                demand(out_index === 32'(outputs) && out_sof === (outputs == 0) &&
                       out_eol === (outputs % (WIDTH / 4) == WIDTH / 4 - 1) && out_eof === (outputs == GROUPS - 1),
                       $sformatf("RAW boundary/index at expected index=%0d", outputs));
                if (s1_rvalid && s1_rready) begin
                    simultaneous++;
                    simultaneous_regions[outputs / 512] = 1;
                end
                if (out_motion != 0)
                    motion_groups++;
                digest = (digest ^ {4'b0, out_motion, out_raw}) * 64'h100000001b3;
                outputs++;
            end
            if (read_quiet)
                demand(!out_valid && !s1_arvalid && !s1_rvalid && reader_ar == reader_done &&
                       long_occupancy == 0 && short_occupancy == 0, "read_quiet with public reader work outstanding");
            if (result_valid) begin
                result_offers++;
                demand(start_cycle >= 0 && results == 0 && result_ok === expect_ok,
                       "unexpected or duplicate RESULT");
                demand(read_quiet && reader_ar == reader_ar_forwarded && reader_ar == reader_done &&
                       master_ar == master_done && !out_valid, "RESULT before real reader and master drain");
                if (expect_ok)
                    demand(outputs == GROUPS && reader_r == 2 * FRAME_WORDS &&
                           member_words[0] == FRAME_WORDS && member_words[1] == FRAME_WORDS,
                           "good RESULT before complete coverage and accepted RAW");
                if (result_ready) begin
                    result_cycle = cycle;
                    results++;
                end
            end
            if (first_overlap_cycle == 0 && s0_arvalid && (s1_arvalid || reader_ar > reader_done))
                first_overlap_cycle = cycle;
        end else begin
            demand(!m_arvalid && !s1_arvalid && !out_valid && !result_valid, "traffic without a job");
        end
    end

    task automatic coordinated_reset;
        reset_n = 0;
        job_live = 0;
        start_valid = 0;
        cancel = 0;
        s0_arvalid = 0;
        repeat (10) @(negedge clk);
        reset_n = 1;
        @(negedge clk);
        wait (start_ready === 1'b1);
        @(negedge clk);
        demand(!reader_fault && !arb_fault && !arb_recovery, "fault state persisted after coordinated reset");
    endtask

    task automatic start_job(input int cam, selected_bank, job_tag, injected, first_latency, input logic ok);
        wait (start_ready === 1'b1);
        @(negedge clk);
        camera_id = cam;
        bank_id = selected_bank;
        camera = 1'(cam);
        bank = 1'(selected_bank);
        tag = job_tag;
        latency = first_latency;
        fault_mode = injected;
        expect_ok = ok;
        start_cycle = -1;
        result_cycle = -1;
        results = 0;
        result_offers = 0;
        reader_ar = 0;
        reader_ar_forwarded = 0;
        reader_r = 0;
        reader_done = 0;
        reader_beat = 0;
        master_ar = 0;
        master_r = 0;
        master_done = 0;
        master_beat = 0;
        master_last_cycle = -1;
        other_ar = 0;
        other_ar_forwarded = 0;
        other_r = 0;
        member_words[0] = 0;
        member_words[1] = 0;
        outputs = 0;
        motion_groups = 0;
        peak_long = 0;
        peak_short = 0;
        cancel_limit = -1;
        ar_stalls = 0;
        output_stalls = 0;
        reader_r_stalls = 0;
        master_r_stalls = 0;
        idle_edges = 0;
        idle_intervals = 0;
        max_idle = 0;
        first_min = 1000000;
        first_max = 0;
        r_holes = 0;
        simultaneous = 0;
        simultaneous_regions = 0;
        wrap_stalls = 0;
        first_overlap_cycle = 0;
        bad_offered = 0;
        bad_accepted = 0;
        digest = 64'hcbf29ce484222325;
        job_live = 1;
        start_valid = 1;
        wait (start_cycle >= 0);
        @(negedge clk);
        start_valid = 0;
        $display("START tag=%0d edge=%0d cam=%0d bank=%0d latency=%0d", tag, start_cycle, cam, selected_bank, latency);
    endtask

    task automatic end_job;
        wait (results == 1);
        repeat (10) @(negedge clk);
        demand(read_quiet && !m_arvalid && !s1_arvalid && !m_rvalid && !s1_rvalid &&
               !out_valid && !result_valid, "job did not stay drained after RESULT");
        if (cancel_limit >= 0)
            demand(reader_ar == cancel_limit, "an offered reader AR was never drained after cancel");
        if (expect_ok)
            demand(motion_groups > 0 && motion_groups < GROUPS, "oracle did not cover both motion and static outputs");
        $display("METRIC case=%0d tag=%0d ok=%0d start=%0d result=%0d cycles=%0d outputs=%0d motion=%0d digest=%h",
                 scenario, tag, expect_ok, start_cycle, result_cycle, result_cycle - start_cycle,
                 outputs, motion_groups, digest);
        $display("BUS tag=%0d reader_ar=%0d reader_r=%0d master_ar=%0d master_r=%0d first_min=%0d first_max=%0d idle_intervals=%0d idle_edges=%0d idle_max=%0d ar_stalls=%0d reader_r_stalls=%0d master_r_stalls=%0d r_holes=%0d",
                 tag, reader_ar, reader_r, master_ar, master_r, first_min, first_max, idle_intervals,
                 idle_edges, max_idle, ar_stalls, reader_r_stalls, master_r_stalls, r_holes);
        $display("COVERAGE tag=%0d peak_long=%0d peak_short=%0d raw_stalls=%0d wrap_stalls=%b simultaneous=%0d simultaneous_regions=%b result_offers=%0d other_r=%0d overlap_edge=%0d",
                 tag, peak_long, peak_short, output_stalls, wrap_stalls, simultaneous,
                 simultaneous_regions, result_offers, other_r, first_overlap_cycle);
        job_live = 0;
    endtask

    task automatic arm_cancel;
        cancel_limit = reader_ar + int'(s1_arvalid === 1'b1);
        $display("CANCEL tag=%0d edge=%0d reader_ar=%0d ar_limit=%0d reader_r=%0d master_ar=%0d master_r=%0d reader_ar_vr=%b%b master_ar_vr=%b%b addr=%h len=%0d raw_vr=%b%b occupancy=%0d/%0d",
                 tag, cycle, reader_ar, cancel_limit, reader_r, master_ar, master_r, s1_arvalid, s1_arready,
                 m_arvalid, m_arready, m_araddr, m_arlen, out_valid, out_ready, long_occupancy, short_occupancy);
        cancel = 1;
    endtask

    task automatic pause_wrap(input int index);
        wait (outputs == index);
        @(negedge clk);
        out_ready = 0;
        wait (out_valid === 1'b1);
        repeat (11) @(negedge clk);
        out_ready = 1;
    endtask

    initial begin : stimulus
        demand($value$plusargs("CASE=%d", scenario) && scenario inside {[PERF:OVERLAP]}, "unknown +CASE");
        coordinated_reset();
        case (scenario)
            PERF: begin
                start_job(0, 0, 1, 0, 32, 1);
                end_job();
                demand(first_min >= 32 && first_max >= 32 && ar_stalls == 0 && output_stalls == 0,
                       "performance fixture applied an unintended stall or early R");
            end
            STALL: begin
                allow_ar = 0;
                out_ready = 0;
                result_ready = 0;
                start_job(0, 0, 1, 0, 1, 1);
                wait (m_arvalid === 1'b1);
                repeat (9) @(negedge clk);
                allow_ar = 1;
                wait (out_valid === 1'b1);
                repeat (550) @(negedge clk);
                gap_r = 1;
                out_ready = 1;
                pause_wrap(510);
                pause_wrap(1022);
                wait (result_valid === 1'b1);
                repeat (8) @(negedge clk);
                result_ready = 1;
                end_job();
                demand(ar_stalls >= 8 && output_stalls >= 22 && wrap_stalls == 2'b11 &&
                       r_holes > 0 && result_offers >= 8, "missing coverage of a requested stall");
                if ($test$plusargs("REQUIRE_FULL"))
                    demand(peak_long == 512 || peak_short == 512, "candidate queue never reached 512");
            end
            CANCEL_AR: begin
                allow_ar = 0;
                start_job(0, 0, 1, 0, 32, 0);
                wait (m_arvalid === 1'b1);
                repeat (4) @(negedge clk);
                demand(m_arvalid && !m_arready && master_ar == 0 && reader_r == 0,
                       "missing presented unaccepted AR before cancel");
                arm_cancel();
                repeat (9) @(negedge clk);
                demand(m_arvalid && master_ar == 0 && results == 0 && !read_quiet,
                       "cancel retired an unaccepted promised AR");
                allow_ar = 1;
                end_job();
                demand(master_ar == 1 && master_r > 0 && outputs == 0, "cancelled AR debt was not exactly one real burst");
                cancel = 0;
                start_job(1, 1, 3, 0, 32, 1);
                end_job();
            end
            CANCEL_R: begin
                out_ready = 0;
                start_job(0, 0, 1, 0, 32, 0);
                wait (out_valid === 1'b1);
                repeat (5) @(negedge clk);
                demand(reader_r > 0 && out_valid && !out_ready && (long_occupancy > 0 || short_occupancy > 0),
                       "missing accepted reader data and held RAW before cancel");
                arm_cancel();
                repeat (12) @(negedge clk);
                demand(out_valid && !read_quiet && results == 0, "cancel retired the held RAW offer");
                out_ready = 1;
                end_job();
                demand(outputs > 0 && outputs < GROUPS, "cancelled held RAW did not drain as an incomplete prefix");
                cancel = 0;
                start_job(1, 1, 3, 0, 32, 1);
                end_job();
            end
            BAD_RESP: begin
                start_job(0, 0, 1, BAD_RESP, 32, 0);
                end_job();
                demand(bad_offered && bad_accepted && arb_fault && !arb_recovery && reader_r > 0,
                       "legal RRESP injection was not accepted and diagnosed");
                $display("RRESP_DIAG arb_fault=%b reader_fault=%b recovery_required=%b", arb_fault, reader_fault, arb_recovery);
            end
            BAD_ID, BAD_LAST: begin
                start_job(0, 0, 1, scenario, 32, 0);
                wait (bad_offered);
                repeat (48) @(negedge clk);
                demand(arb_fault && (arb_recovery || reader_fault), "malformed response did not isolate the bus or reader");
                $display("PROTOCOL_DIAG case=%0d offered=%b accepted=%b reader_fault=%b arb_fault=%b recovery=%b results=%0d",
                         scenario, bad_offered, bad_accepted, reader_fault, arb_fault, arb_recovery, results);
                coordinated_reset();
                start_job(1, 1, 3, 0, 32, 1);
                end_job();
            end
            OVERLAP: begin
                start_job(0, 0, 1, 0, 32, 1);
                wait (s1_arvalid === 1'b1);
                @(negedge clk);
                s0_rready = 0;
                s0_arvalid = 1;
                wait (other_ar == 1);
                @(negedge clk);
                s0_arvalid = 0;
                wait (s0_rvalid === 1'b1);
                repeat (7) @(negedge clk);
                s0_rready = 1;
                end_job();
                demand(other_r == OTHER_BEATS && other_ar_forwarded == 1 && first_overlap_cycle > 0,
                       "missing bounded competing read overlap or correct routing");
            end
        endcase
        $display("BLACKBOX_PASS case=%0d", scenario);
        $finish;
    end

    initial begin
        #1ms;
        demand(1'b0, "1 ms simulation watchdog");
    end
endmodule
