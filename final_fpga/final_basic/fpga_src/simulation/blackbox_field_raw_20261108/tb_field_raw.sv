`timescale 1ps/1ps

module tb_field_raw;
    localparam [31:0] SESSION = 32'h1234abcd;
    localparam [31:0] EPOCH = 0;
    localparam integer W = 8, H = 2, PAYLOAD = W*H*10/8, RECORD = 64+PAYLOAD;
    localparam integer FREE = 0, WRITING = 1, READY = 2, OWNED = 3, SAFE = 4;
    localparam integer NO_STOP = 0, STOP_AFTER_EDGE = 1, STOP_AT_RESPONSE = 2,
                       STOP_AFTER_RESPONSE = 3;
    string scenario;
    integer phase_ps, first_eye, cycle = 0;
    reg clk = 0, rst_n = 0, stop = 0, release_quiet = 1;
    reg [383:0] begin_frame = 0;
    reg begin_valid = 0, begin_camera = 0;
    wire begin_ready, begin_accepted;
    wire [1:0] capture_slot;
    reg [1:0] finish_valid = 0, finish_ok = 0;
    wire [1:0] finish_ready;
    wire [383:0] job_frame;
    wire [63:0] job_id, job_lease;
    wire [1:0] job_bayer;
    wire job_time_valid, retire_done, retire_error, empty, read_quiet;

    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid, arready, rready;
    reg [3:0] rid = 0;
    reg [127:0] rdata = 0;
    reg rlast = 0, rvalid = 0;
    reg ar_gate = 1;

    wire raw_offer, raw_offer_ready;
    wire [31:0] raw_length;
    wire [127:0] raw_identity, raw_data;
    wire [15:0] raw_keep;
    wire raw_valid, raw_last, raw_ready, raw_done_valid, raw_done_ok, raw_drained;
    wire raw_safe_ready;
    reg offer_gate = 1, sink_gate = 1, hold_tail = 0, hold_body = 0;
    reg auto_safe = 1, manual_safe = 0;
    reg [127:0] manual_identity = 0;
    wire [127:0] fmt_data;
    wire [15:0] fmt_keep;
    wire fmt_start_ready, fmt_drained, fmt_valid, fmt_last, fmt_done;

    integer state [0:3], pending_finish [0:1];
    reg [383:0] frozen_capture [0:3];
    integer capture_order [0:3];
    reg [127:0] memory [0:3][0:1];
    integer expected_seq [0:1][0:31];
    integer enqueued [0:1], delivered [0:1], retired [0:1];
    integer accepted [0:1], rejected [0:1], finish_count [0:1];
    integer negative_finish [0:1];
    reg [63:0] leases [0:31];
    integer lease_capture_order [0:31];
    integer begin_count = 0, begin_slot_key = -1;
    reg begin_result = 0;
    integer bursts = 0, bursts_done = 0, read_key = -1, read_index = 0, read_left = 0;
    integer records = 0, terminal_good_count = 0, terminal_bad_count = 0;
    integer safe_count = 0, retired_total = 0, raw_beats = 0, seen_bytes = 0;
    integer stalled_offer_cycles = 0, stalled_fmt_cycles = 0, stalled_ar_cycles = 0;
    integer stalled_raw_cycles = 0;
    integer current_key = -1, current_eye = -1, current_seq = -1;
    reg active = 0, want_failed_record = 0, terminal_seen = 0, terminal_good = 0;
    reg last_seen = 0, formatter_done_seen = 0, safe_seen = 0;
    reg [127:0] current_identity;
    reg [383:0] current_job_frame;
    reg [63:0] current_job_id, current_lease;
    reg [1:0] current_bayer;
    reg current_time_valid;
    reg [511:0] expected_header;

    wire safe_auto_valid = auto_safe && active && terminal_seen && !safe_seen &&
                           fmt_drained && (!terminal_good || formatter_done_seen);
    wire safe_valid = manual_safe || safe_auto_valid;
    wire [127:0] safe_identity = manual_safe ? manual_identity : current_identity;
    wire fmt_abort = active && !safe_seen &&
        ((raw_done_valid && !raw_done_ok && raw_drained) || (terminal_seen && !terminal_good));
    wire sink_ready = sink_gate && !(hold_tail && fmt_valid && fmt_last) &&
        !(hold_body && active && seen_bytes >= 64);
    assign raw_offer_ready = offer_gate && !active && fmt_start_ready;
    assign arready = rst_n && ar_gate && !rvalid && (cycle % 5 != 1);

    stereo_raw_store #(.WIDTH(W), .HEIGHT(H), .RAW_EXPORT_ENABLE(1),
                       .EXTERNAL_DECODER(1), .VERIFY_DECODE_ACTIVE(1)) store (
        .clk(clk), .rst_n(rst_n), .i_enable(1'b1), .i_stop(stop),
        .i_session(SESSION), .i_epoch(EPOCH), .s_frame(begin_frame),
        .s_begin_valid(begin_valid), .i_begin_camera(begin_camera), .s_begin_ready(begin_ready),
        .o_begin_accepted(begin_accepted), .o_capture_slot(capture_slot),
        .i_finish_valid(finish_valid), .i_finish_ok(finish_ok), .o_finish_ready(finish_ready),
        .i_job_ready(1'b0), .o_job_frame(job_frame), .o_job_id(job_id), .o_job_lease(job_lease),
        .o_job_bayer(job_bayer), .o_job_time_valid(job_time_valid),
        .i_retire_valid(1'b0), .i_retire_job_id(64'b0), .i_release_quiet(release_quiet),
        .o_retire_done(retire_done), .o_retire_error(retire_error),
        .i_req_valid(1'b0), .i_req_op(3'b0), .i_req_camera(1'b0), .i_req_slot(2'b0),
        .i_req_generation(32'b0), .i_req_session(32'b0), .i_req_lease(64'b0),
        .i_req_job_id(64'b0), .i_rsp_ready(1'b1), .i_processing_done(1'b0),
        .i_processing_error(1'b0), .i_processing_job_id(64'b0), .m_fifo_ready(1'b1),
        .o_read_quiet(read_quiet), .o_empty(empty), .i_decode_start_ready(1'b0),
        .i_decode_ready(1'b0), .i_decode_raw(40'b0), .i_decode_raw_valid(1'b0),
        .i_decode_sof(1'b0), .i_decode_eol(1'b0), .i_decode_done(1'b0),
        .i_decode_aborted(1'b0), .i_decode_quiet(1'b1), .i_decode_active(1'b0),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(2'b0), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .i_raw_export(1'b1), .i_raw_cancel(1'b0), .o_raw_record_valid(raw_offer),
        .i_raw_record_ready(raw_offer_ready), .o_raw_record_length(raw_length),
        .o_raw_record_identity(raw_identity), .o_raw_data(raw_data), .o_raw_keep(raw_keep),
        .o_raw_valid(raw_valid), .o_raw_last(raw_last), .i_raw_ready(raw_ready),
        .o_raw_done_valid(raw_done_valid), .o_raw_done_ok(raw_done_ok), .o_raw_drained(raw_drained),
        .i_raw_retire_valid(safe_valid), .o_raw_retire_ready(raw_safe_ready),
        .i_raw_retire_identity(safe_identity)
    );

    raw_video_record_formatter formatter (
        .i_clk(clk), .i_rst_n(rst_n), .i_start_valid(raw_offer && offer_gate && !active),
        .o_start_ready(fmt_start_ready), .i_abort(fmt_abort), .o_drained(fmt_drained),
        .i_payload_bytes(raw_length - 32'd64), .i_width(job_frame[220:205]),
        .i_height(job_frame[236:221]), .i_sequence(job_frame[108:77]),
        .i_session(job_frame[76:45]), .i_epoch(job_frame[140:109]), .i_camera(job_frame[4]),
        .i_bayer_phase(job_bayer), .i_time_valid(job_time_valid),
        .i_capture_time_ns(job_frame[204:141]), .i_job_id(job_id),
        .s_data(raw_data), .s_keep(raw_keep), .s_valid(raw_valid), .s_last(raw_last),
        .s_ready(raw_ready), .m_data(fmt_data), .m_keep(fmt_keep), .m_valid(fmt_valid),
        .m_last(fmt_last), .m_ready(sink_ready), .o_done(fmt_done)
    );

    function automatic [63:0] capture_time(input integer eye, input integer seq);
        capture_time = 64'h16f1_37ab_91f0_3b25 + 64'd1000297*seq + 64'd678013*eye;
    endfunction

    function automatic [1:0] bayer(input integer eye, input integer seq);
        bayer = (seq + 2*eye) % 4;
    endfunction

    function automatic [383:0] descriptor(input integer eye, input integer seq);
        descriptor = 0;
        descriptor[4] = eye[0];
        descriptor[76:45] = SESSION;
        descriptor[108:77] = seq;
        descriptor[140:109] = EPOCH;
        descriptor[204:141] = capture_time(eye, seq);
        descriptor[220:205] = W;
        descriptor[236:221] = H;
        descriptor[238:237] = 1;
        descriptor[371:368] = {2'b11, bayer(eye, seq)};
    endfunction

    function automatic [9:0] sample(input integer eye, input integer seq, input integer pixel);
        sample = (17 + 373*eye + 97*seq + 49*pixel + 17*(pixel/4)) % 1024;
    endfunction

    function automatic [7:0] raw10_byte(input integer eye, input integer seq, input integer offset);
        integer b, pixel, shift;
        reg [9:0] value;
        for (b = 0; b < 8; b = b + 1) begin
            pixel = (8*offset + b) / 10;
            shift = (8*offset + b) % 10;
            value = sample(eye, seq, pixel);
            raw10_byte[b] = value[shift];
        end
    endfunction

    task automatic write_model(input integer key, input integer eye, input integer seq);
        reg [255:0] packed_pixels;
        integer group_index, lane;
        packed_pixels = 0;
        for (group_index = 0; group_index < W*H/4; group_index = group_index + 1)
            for (lane = 0; lane < 4; lane = lane + 1)
                packed_pixels[group_index*40 + lane*10 +: 10] = sample(eye, seq, 4*group_index+lane);
        memory[key][0] = packed_pixels[127:0];
        memory[key][1] = packed_pixels[255:128];
    endtask

    function automatic integer address_key(input [27:0] address);
        case (address[27:24])
            4'h2: address_key = 0;
            4'h3: address_key = 1;
            4'h6: address_key = 2;
            4'h7: address_key = 3;
            default: address_key = -1;
        endcase
    endfunction

    reg held_ar = 0, held_offer = 0, held_raw = 0, held_fmt = 0;
    reg [44:0] previous_ar;
    reg [674:0] previous_offer;
    reg [144:0] previous_raw, previous_fmt;
    wire [44:0] ar_fields = {arid, araddr, arlen, arsize, arburst};
    wire [674:0] offer_fields = {raw_length, raw_identity, job_frame, job_id,
                                 job_lease, job_bayer, job_time_valid};
    wire [144:0] raw_fields = {raw_data, raw_keep, raw_last};
    wire [144:0] fmt_fields = {fmt_data, fmt_keep, fmt_last};

    // All sampled signals are public IO. Scoreboard updates use NBA so BFM controls
    // cannot feed a same-edge scoreboard result back into a DUT sampling process.
    always @(posedge clk) if (rst_n) begin : monitor
        integer eye, key, seq, n, i, byte_index, bytes_this_beat, mem_index;
        reg [383:0] wanted_frame;
        reg [127:0] wanted_identity;
        reg [511:0] hdr;
        reg [7:0] wanted_byte;
        reg [15:0] wanted_keep;
        cycle <= cycle + 1;

        if (held_ar && (!arvalid || ar_fields !== previous_ar)) $fatal(1, "AR offer lost or changed under stall");
        if (held_offer && (!raw_offer || offer_fields !== previous_offer)) $fatal(1, "record offer changed under stall");
        if (held_raw && (!raw_valid || raw_fields !== previous_raw)) $fatal(1, "RAW beat changed under stall");
        if (held_fmt && (!fmt_valid || fmt_fields !== previous_fmt)) $fatal(1, "ARAW beat changed under stall");
        held_ar <= arvalid && !arready;
        held_offer <= raw_offer && !raw_offer_ready;
        held_raw <= raw_valid && !raw_ready;
        held_fmt <= fmt_valid && !sink_ready;
        previous_ar <= ar_fields;
        previous_offer <= offer_fields;
        previous_raw <= raw_fields;
        previous_fmt <= fmt_fields;
        if (held_ar) stalled_ar_cycles <= stalled_ar_cycles + 1;
        if (held_offer) stalled_offer_cycles <= stalled_offer_cycles + 1;
        if (held_raw) stalled_raw_cycles <= stalled_raw_cycles + 1;
        if (held_fmt) stalled_fmt_cycles <= stalled_fmt_cycles + 1;

        if (begin_valid && begin_ready) begin
            if (begin_accepted !== 1'b0 && begin_accepted !== 1'b1) $fatal(1, "unknown BEGIN result");
            eye = int'(begin_camera);
            begin_count <= begin_count + 1;
            begin_result <= begin_accepted;
            if (begin_accepted) begin
                if (capture_slot !== 2'd0 && capture_slot !== 2'd1)
                    $fatal(1, "invalid per-eye capture slot %0d", capture_slot);
                key = 2*eye + int'(capture_slot);
                if (state[key] != FREE || pending_finish[eye] != -1)
                    $fatal(1, "occupied capture slot reused before retirement: eye=%0d slot=%0d state=%0d", eye, capture_slot, state[key]);
                begin_slot_key <= key;
                pending_finish[eye] <= key;
                state[key] <= WRITING;
                frozen_capture[key] <= begin_frame;
                capture_order[key] <= begin_count;
                write_model(key, eye, int'(begin_frame[108:77]));
                accepted[eye] <= accepted[eye] + 1;
            end else begin
                begin_slot_key <= -1;
                rejected[eye] <= rejected[eye] + 1;
            end
        end

        for (eye = 0; eye < 2; eye = eye + 1) if (finish_valid[eye] && finish_ready[eye]) begin
            key = pending_finish[eye];
            if (key < 0 || state[key] != WRITING) $fatal(1, "finish without capture ownership: eye=%0d", eye);
            finish_count[eye] <= finish_count[eye] + 1;
            pending_finish[eye] <= -1;
            if (finish_ok[eye]) begin
                if (stop) $fatal(1, "fixture: successful finish while stopped");
                state[key] <= READY;
                expected_seq[eye][enqueued[eye]] <= int'(frozen_capture[key][108:77]);
                enqueued[eye] <= enqueued[eye] + 1;
            end else begin
                state[key] <= FREE;
                negative_finish[eye] <= negative_finish[eye] + 1;
            end
        end

        if (arvalid && arready) begin
            key = address_key(araddr);
            mem_index = int'(araddr[23:4]);
            n = int'(arlen) + 1;
            if (key < 0 || mem_index + n > 2 || araddr[3:0] !== 4'd0 ||
                arsize !== 3'd4 || arburst !== 2'b01)
                $fatal(1, "invalid RAW AR addr=%h len=%0d size=%0d burst=%0d", araddr, arlen, arsize, arburst);
            if (state[key] != READY && state[key] != OWNED)
                $fatal(1, "RAW read from slot without successful SOURCE: key=%0d state=%0d", key, state[key]);
            if (active && !safe_seen && key != current_key)
                $fatal(1, "RAW read used a different slot from current record");
            bursts <= bursts + 1;
            rid <= arid;
            rvalid <= 1;
            rdata <= memory[key][mem_index];
            rlast <= n == 1;
            read_key <= key;
            read_index <= mem_index;
            read_left <= n;
        end else if (rvalid && rready) begin
            if (rlast) begin
                rvalid <= 0;
                rlast <= 0;
                read_left <= 0;
                bursts_done <= bursts_done + 1;
            end else begin
                rdata <= memory[read_key][read_index+1];
                read_index <= read_index + 1;
                read_left <= read_left - 1;
                rlast <= read_left == 2;
            end
        end

        if (raw_offer) begin
            eye = int'(job_frame[4]);
            seq = int'(job_frame[108:77]);
            if ((job_frame[4] !== 1'b0 && job_frame[4] !== 1'b1) ||
                delivered[eye] >= enqueued[eye] || seq != expected_seq[eye][delivered[eye]])
                $fatal(1, "unexpected job or per-eye sequence loss/reorder: eye=%0d seq=%0d next=%0d ready=%0d", eye, seq, expected_seq[eye][delivered[eye]], enqueued[eye]);
            key = -1;
            for (i = 2*eye; i < 2*eye+2; i = i + 1)
                if (state[i] == READY && int'(frozen_capture[i][108:77]) == seq) key = i;
            if (key < 0) $fatal(1, "RAW offer lacks ready matching capture slot");
            wanted_frame = descriptor(eye, seq);
            wanted_frame[383:367] = 0;
            wanted_frame[44:13] = job_lease[31:0];
            wanted_frame[12:5] = {7'd0, key[0]};
            wanted_identity = {16'h5241, SESSION, job_lease[31:0], 13'd0, eye[0], 1'b0, key[0], seq[31:0]};
            if (job_frame !== wanted_frame || job_bayer !== bayer(eye, seq) || job_time_valid !== 1'b1)
                $fatal(1, "frozen job descriptor mismatch: eye=%0d seq=%0d frame_xor=%h bayer=%h expected_bayer=%h time_valid=%b",
                       eye, seq, job_frame ^ wanted_frame, job_bayer, bayer(eye, seq), job_time_valid);
            if ((^job_lease === 1'bx) || job_lease[63:32] !== 32'b0 || job_lease[31:0] == 0 ||
                job_id !== (64'h8000_0000_0000_0000 | job_lease) || raw_identity !== wanted_identity || raw_length !== RECORD)
                $fatal(1, "lease, job identity or ARAW length mismatch: eye=%0d seq=%0d len=%0d", eye, seq, raw_length);

            if (raw_offer_ready) begin
                for (i = 0; i < records; i = i + 1)
                    if (job_lease === leases[i] ||
                        (lease_capture_order[i] < capture_order[key] && leases[i] >= job_lease) ||
                        (lease_capture_order[i] > capture_order[key] && leases[i] <= job_lease))
                        $fatal(1, "non-increasing lease allocation in BEGIN response order");
                leases[records] <= job_lease;
                lease_capture_order[records] <= capture_order[key];
                records <= records + 1;
                active <= 1;
                state[key] <= OWNED;
                delivered[eye] <= delivered[eye] + 1;
                current_key <= key;
                current_eye <= eye;
                current_seq <= seq;
                current_identity <= raw_identity;
                current_job_frame <= job_frame;
                current_job_id <= job_id;
                current_lease <= job_lease;
                current_bayer <= job_bayer;
                current_time_valid <= job_time_valid;
                terminal_seen <= 0;
                terminal_good <= 0;
                safe_seen <= 0;
                seen_bytes <= 0;
                last_seen <= 0;
                formatter_done_seen <= 0;
                hdr = 0;
                hdr[0*8 +: 32] = 32'h57415241;
                hdr[4*8 +: 16] = 1;
                hdr[6*8 +: 16] = 64;
                hdr[8*8 +: 32] = PAYLOAD;
                hdr[12*8 +: 16] = W;
                hdr[14*8 +: 16] = H;
                hdr[16*8 +: 32] = seq;
                hdr[20*8 +: 32] = SESSION;
                hdr[24*8 +: 32] = EPOCH;
                hdr[28*8 +: 8] = eye;
                hdr[29*8 +: 8] = 1;
                hdr[30*8 +: 8] = {6'b0, bayer(eye, seq)};
                hdr[31*8 +: 8] = 1;
                hdr[32*8 +: 64] = capture_time(eye, seq);
                hdr[40*8 +: 64] = 64'h8000_0000_0000_0000 | job_lease;
                expected_header <= hdr;
                $display("RECORD_START eye=%0d seq=%0d slot=%0d lease=%0d", eye, seq, key[0], job_lease);
            end
        end

        if (active && !safe_seen &&
            {raw_identity, job_frame, job_id, job_lease, job_bayer, job_time_valid} !==
            {current_identity, current_job_frame, current_job_id, current_lease, current_bayer, current_time_valid})
            $fatal(1, "borrowed identity or descriptor changed before SAFE");

        if (raw_valid && raw_ready) raw_beats <= raw_beats + 1;
        if (fmt_valid && sink_ready) begin
            if (!active || last_seen || safe_seen) $fatal(1, "ARAW data outside a live record");
            bytes_this_beat = (RECORD-seen_bytes > 16) ? 16 : RECORD-seen_bytes;
            wanted_keep = (32'd1 << bytes_this_beat) - 1;
            if (fmt_keep !== wanted_keep || fmt_last !== (seen_bytes + bytes_this_beat == RECORD))
                $fatal(1, "invalid ARAW keep/last at byte %0d: %h/%b", seen_bytes, fmt_keep, fmt_last);
            for (i = 0; i < bytes_this_beat; i = i + 1) begin
                byte_index = seen_bytes + i;
                wanted_byte = byte_index < 64 ? expected_header[byte_index*8 +: 8] :
                    raw10_byte(current_eye, current_seq, byte_index-64);
                if (fmt_data[i*8 +: 8] !== wanted_byte)
                    $fatal(1, "ARAW byte mismatch: eye=%0d seq=%0d offset=%0d got=%h want=%h",
                        current_eye, current_seq, byte_index, fmt_data[i*8 +: 8], wanted_byte);
            end
            seen_bytes <= seen_bytes + bytes_this_beat;
            if (fmt_last) begin
                if (want_failed_record) $fatal(1, "cancelled record produced a successful ARAW LAST");
                last_seen <= 1;
            end
        end
        if (fmt_done) begin
            if (!active || !(last_seen || (fmt_valid && sink_ready && fmt_last)))
                $fatal(1, "formatter DONE before actual last handshake");
            formatter_done_seen <= 1;
        end
        if (active && !safe_seen && raw_done_valid && !terminal_seen) begin
            if (!raw_drained || arvalid || rvalid || bursts != bursts_done)
                $fatal(1, "RAW terminal reported with undrained AXI obligation");
            if (raw_done_ok !== !want_failed_record) $fatal(1, "unexpected RAW DONE_OK=%b", raw_done_ok);
            terminal_seen <= 1;
            terminal_good <= raw_done_ok;
            if (raw_done_ok) begin
                if (!(last_seen || (fmt_valid && sink_ready && fmt_last))) $fatal(1, "RAW success before last ARAW handshake");
                terminal_good_count <= terminal_good_count + 1;
            end else begin
                if (last_seen || formatter_done_seen || raw_valid) $fatal(1, "RAW negative terminal with published success or undrained data");
                terminal_bad_count <= terminal_bad_count + 1;
            end
        end
        if (safe_valid && raw_safe_ready) begin
            if (!active || safe_seen || safe_identity !== current_identity)
                $fatal(1, "wrong, stale, or duplicate SAFE accepted");
            if (!terminal_seen || !fmt_drained || (terminal_good && !formatter_done_seen))
                $fatal(1, "fixture: SAFE was sent before record was consumed and drained");
            state[current_key] <= SAFE;
            safe_seen <= 1;
            safe_count <= safe_count + 1;
        end
        if (retire_error) $fatal(1, "retirement reported an error");
        if (retire_done) begin
            if (!active || !safe_seen || state[current_key] != SAFE || !release_quiet)
                $fatal(1, "retirement before exact SAFE or release quiet");
            state[current_key] <= FREE;
            retired[current_eye] <= retired[current_eye] + 1;
            retired_total <= retired_total + 1;
            active <= 0;
            $display("RECORD_RETIRED eye=%0d seq=%0d good=%b bytes=%0d", current_eye, current_seq, terminal_good, seen_bytes);
        end
    end

    // Driver changes inputs on falling edges and waits for the sampled public response.
    task automatic submit(input integer eye, input integer seq, input integer expected_accept,
                          input integer stop_position);
        integer before_count;
        before_count = begin_count;
        begin_frame = descriptor(eye, seq);
        begin_camera = eye[0];
        begin_valid = 1;
        if (stop_position == STOP_AFTER_EDGE) begin
            @(negedge clk);
            if (begin_count != before_count) $fatal(1, "coverage: no pending BEGIN after its first sample");
            stop = 1;
        end
        if (stop_position == STOP_AT_RESPONSE) begin
            @(negedge clk);
            while (begin_count == before_count && !(begin_ready && begin_accepted)) @(negedge clk);
            if (begin_count != before_count) $fatal(1, "coverage: no accepted response offered before handshake");
            stop = 1;
        end
        while (begin_count == before_count) @(negedge clk);
        if (stop_position == STOP_AFTER_RESPONSE) stop = 1;
        begin_valid = 0;
        if (expected_accept >= 0 && begin_result !== (expected_accept == 1))
            $fatal(1, "wrong BEGIN response eye=%0d seq=%0d got=%b want=%0d stop_position=%0d", eye, seq, begin_result, expected_accept, stop_position);
        $display("BEGIN_RESPONSE eye=%0d seq=%0d accepted=%b stop=%b boundary=%0d slot_key=%0d",
                 eye, seq, begin_result, stop, stop_position, begin_slot_key);
    endtask

    task automatic finish(input [1:0] mask, input [1:0] status);
        integer count0, count1;
        count0 = finish_count[0];
        count1 = finish_count[1];
        finish_valid = mask;
        finish_ok = status;
        while (finish_valid != 0) begin
            @(negedge clk);
            if (finish_count[0] != count0) finish_valid[0] = 0;
            if (finish_count[1] != count1) finish_valid[1] = 0;
        end
        finish_ok = 0;
    endtask

    task automatic wait_idle;
        while (!(empty && read_quiet && fmt_drained && !active)) @(negedge clk);
        repeat (3) @(negedge clk);
    endtask

    task automatic wait_retired(input integer n);
        while (retired_total < n) @(negedge clk);
        if (retired_total != n) $fatal(1, "unexpected additional retirement");
    endtask

    task automatic send_safe;
        integer before_safe;
        before_safe = safe_count;
        if (!active || !terminal_seen || !fmt_drained || (terminal_good && !formatter_done_seen))
            $fatal(1, "fixture: manual SAFE requires drained record");
        manual_safe = 1;
        manual_identity = current_identity;
        while (safe_count == before_safe) @(negedge clk);
        manual_safe = 0;
    endtask

    task automatic good_pair(input integer lead, input integer seq, input integer skew);
        // Both frame sources offer work in this interval. The public BEGIN channel is scalar.
        submit(lead, seq, 1, NO_STOP);
        submit(1-lead, seq, 1, NO_STOP);
        if (skew == 0) finish(2'b11, 2'b11);
        else begin
            finish(2'b01 << (1-lead), 2'b11);
            repeat (skew) @(negedge clk);
            finish(2'b01 << lead, 2'b11);
        end
    endtask

    task automatic startup_case;
        integer seq;
        for (seq = 1; seq <= 6; seq = seq + 1) begin
            good_pair((first_eye+seq-1)%2, seq, (seq % 2 == 0) ? 3 : 0);
            wait_retired(2*seq);
        end
        if (rejected[0] != 0 || rejected[1] != 0 || retired[0] != 6 || retired[1] != 6)
            $fatal(1, "serviced startup/continuous case lost a sequence");
    endtask

    task automatic pressure_case;
        integer n;
        offer_gate = 0;
        sink_gate = 0;
        hold_tail = 1;
        auto_safe = 0;
        submit(first_eye, 1, 1, NO_STOP);
        finish(2'b01 << first_eye, 2'b11);
        while (!raw_offer) @(negedge clk);
        submit(1-first_eye, 1, 1, NO_STOP);
        finish(2'b01 << (1-first_eye), 2'b11);
        good_pair(1-first_eye, 2, 0);
        submit(first_eye, 3, 0, NO_STOP);
        submit(1-first_eye, 3, 0, NO_STOP);
        if (records != 0 || retired_total != 0 || rejected[0] != 1 || rejected[1] != 1)
            $fatal(1, "fixture: full requests must occur before any host release");
        repeat (9) @(negedge clk);
        offer_gate = 1;
        while (records == 0) @(negedge clk);
        if (current_eye != first_eye || current_seq != 1) $fatal(1, "held first record was replaced");
        repeat (6) @(negedge clk);
        sink_gate = 1;
        while (!(fmt_valid && fmt_last)) @(negedge clk);
        repeat (5) @(negedge clk);
        if (terminal_seen || formatter_done_seen || safe_count != 0 || retired_total != 0)
            $fatal(1, "completion/SAFE/retire before held final beat");
        hold_tail = 0;
        while (!(terminal_seen && fmt_drained && formatter_done_seen)) @(negedge clk);
        repeat (11) @(negedge clk);
        if (retired_total != 0) $fatal(1, "retirement before host SAFE");
        manual_identity = current_identity ^ 128'd1;
        manual_safe = 1;
        repeat (4) @(negedge clk);
        manual_safe = 0;
        if (safe_count != 0 || retired_total != 0) $fatal(1, "wrong SAFE released ownership");
        release_quiet = 0;
        send_safe();
        repeat (8) @(negedge clk);
        if (retired_total != 0 || safe_count != 1 || empty)
            $fatal(1, "SAFE confused with actual retirement");
        release_quiet = 1;
        wait_retired(1);
        auto_safe = 1;
        wait_retired(4);
        good_pair(first_eye, 4, 2);
        wait_retired(6);
        for (n = 0; n < 2; n = n + 1)
            if (retired[n] != 3 || accepted[n] != 3 || rejected[n] != 1)
                $fatal(1, "full case mismatch eye=%0d accepted=%0d rejected=%0d retired=%0d", n, accepted[n], rejected[n], retired[n]);
        if (stalled_offer_cycles < 3 || stalled_fmt_cycles < 3 || stalled_raw_cycles < 3)
            $fatal(1, "coverage: missing directed stall");
    endtask

    task automatic negative_source_case;
        submit(first_eye, 1, 1, NO_STOP);
        submit(1-first_eye, 1, 1, NO_STOP);
        finish(2'b01 << first_eye, 2'b00);
        repeat (8) @(negedge clk);
        if (records != 0 || bursts != 0) $fatal(1, "negative SOURCE produced job or read");
        finish(2'b01 << (1-first_eye), 2'b11);
        wait_retired(1);
        if (retired[first_eye] != 0 || retired[1-first_eye] != 1)
            $fatal(1, "healthy other eye did not progress independently");
        good_pair(first_eye, 2, 2);
        wait_retired(3);
        if (negative_finish[first_eye] != 1 || retired[first_eye] != 1 || retired[1-first_eye] != 2)
            $fatal(1, "negative SOURCE recovery mismatch");
    endtask

    task automatic stop_begin_case;
        stop = 1;
        @(negedge clk);
        submit(0, 1, 0, NO_STOP);
        wait_idle();
        stop = 0;
        @(negedge clk);
        submit(1, 1, -1, STOP_AFTER_EDGE);
        if (begin_result) finish(2'b10, 2'b00);
        wait_idle();
        stop = 0;
        @(negedge clk);
        submit(0, 2, -1, STOP_AT_RESPONSE);
        if (begin_result) finish(2'b01, 2'b00);
        wait_idle();
        stop = 0;
        @(negedge clk);
        submit(1, 2, 1, STOP_AFTER_RESPONSE);
        finish(2'b10, 2'b00);
        wait_idle();
        if (records != 0 || bursts != 0 || accepted[0] != negative_finish[0] || accepted[1] != negative_finish[1])
            $fatal(1, "STOP/BEGIN leaked ownership or published a cancelled frame");
        stop = 0;
        @(negedge clk);
        good_pair(1, 3, 2);
        wait_retired(2);
    endtask

    task automatic stop_record_case(input bit stop_with_ar);
        integer r_before, raw_before;
        auto_safe = 0;
        if (stop_with_ar) ar_gate = 0;
        else hold_body = 1;
        submit(first_eye, 1, 1, NO_STOP);
        finish(2'b01 << first_eye, 2'b11);
        while (!active) @(negedge clk);
        if (stop_with_ar) begin
            while (!arvalid) @(negedge clk);
        end else begin
            // Prove this is a sampled offer, already held across an edge, before STOP.
            while (!(held_raw && raw_valid && !raw_ready && !raw_last && seen_bytes == 64)) @(negedge clk);
        end
        r_before = bursts_done;
        raw_before = raw_beats;
        stop = 1;
        want_failed_record = 1;
        repeat (6) @(negedge clk);
        if (terminal_seen || safe_count || retired_total) $fatal(1, "STOP declared drain with held transaction");
        if (stop_with_ar) ar_gate = 1;
        else hold_body = 0;
        while (!(terminal_seen && fmt_drained)) @(negedge clk);
        if (terminal_good || last_seen || formatter_done_seen) $fatal(1, "STOP minted success");
        if (stop_with_ar && (bursts_done <= r_before || stalled_ar_cycles < 3))
            $fatal(1, "STOP failed to drain a committed AR through RLAST");
        if (!stop_with_ar && (raw_beats <= raw_before || stalled_raw_cycles < 3))
            $fatal(1, "STOP failed to drain a committed RAW data beat: before=%0d after=%0d stalled=%0d",
                   raw_before, raw_beats, stalled_raw_cycles);
        send_safe();
        wait_retired(1);
        wait_idle();
        stop = 0;
        want_failed_record = 0;
        auto_safe = 1;
        @(negedge clk);
        good_pair(first_eye, 2, 0);
        wait_retired(3);
        if (terminal_bad_count != 1 || terminal_good_count != 2)
            $fatal(1, "STOP record did not complete negative and recover");
    endtask

    initial begin
        if (!$value$plusargs("PHASE=%d", phase_ps)) phase_ps = 0;
        #(phase_ps);
        forever #3750 clk = ~clk;
    end

    initial begin : drive
        integer i;
        if (!$value$plusargs("CASE=%s", scenario)) $fatal(1, "fixture: specify CASE");
        if (!$value$plusargs("FIRST=%d", first_eye)) first_eye = 0;
        if (first_eye != 0 && first_eye != 1) $fatal(1, "fixture: invalid FIRST");
        for (i = 0; i < 4; i = i + 1) state[i] = FREE;
        for (i = 0; i < 2; i = i + 1) begin
            pending_finish[i] = -1;
            enqueued[i] = 0;
            delivered[i] = 0;
            retired[i] = 0;
            accepted[i] = 0;
            rejected[i] = 0;
            finish_count[i] = 0;
            negative_finish[i] = 0;
        end
        repeat (6) @(negedge clk);
        #((phase_ps == 0) ? 200 : 1700) rst_n = 1;
        @(negedge clk);
        wait_idle();
        case (scenario)
            "startup": startup_case();
            "pressure": pressure_case();
            "negative_source": negative_source_case();
            "stop_begin": stop_begin_case();
            "stop_ar": stop_record_case(1);
            "stop_data": stop_record_case(0);
            default: $fatal(1, "fixture: unknown CASE %s", scenario);
        endcase
        wait_idle();
        if (records == 0 || records != retired_total || safe_count != retired_total ||
            terminal_good_count + terminal_bad_count != retired_total || bursts != bursts_done ||
            enqueued[0] != delivered[0] || enqueued[1] != delivered[1])
            $fatal(1, "unaccounted transaction at end of case");
        for (i = 0; i < 4; i = i + 1)
            if (state[i] != FREE) $fatal(1, "owned slot at end of case");
        $display("PASS_FIELD_RAW case=%s first=%0d phase_ps=%0d records=%0d good=%0d bad=%0d rejected=%0d/%0d safe=%0d retired=%0d bursts=%0d sim_ps=%0t",
                 scenario, first_eye, phase_ps, records, terminal_good_count, terminal_bad_count,
                 rejected[0], rejected[1], safe_count, retired_total, bursts, $time);
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "watchdog case=%s begin=%0d records=%0d terminal=%0d/%0d safe=%0d retire=%0d empty=%b read_quiet=%b fmt_drained=%b AR=%b/%b R=%b/%b RAW=%b/%b",
            scenario, begin_count, records, terminal_good_count, terminal_bad_count,
            safe_count, retired_total, empty, read_quiet, fmt_drained, arvalid, arready,
            rvalid, rready, raw_valid, raw_ready);
    end
endmodule
