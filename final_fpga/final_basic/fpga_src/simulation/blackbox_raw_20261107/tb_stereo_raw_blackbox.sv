`timescale 1ns/1ps

module tb_stereo_raw_blackbox #(
    parameter integer WIDTH = 8,
    parameter integer HEIGHT = 2
);
    import raw_blackbox_support::*;

    localparam integer PAYLOAD_BYTES = WIDTH * HEIGHT * 5 / 4;
    localparam integer PAYLOAD_BEATS = (PAYLOAD_BYTES + 15) / 16;
    localparam integer MAX_TAG = 31;

    logic clk = 0;
    always #3.75 clk = ~clk;

    logic rst_n = 0, stop = 0, cancel_raw = 0, release_quiet = 1;
    logic [31:0] session = 32'h5318ac09, epoch = 32'h07398cfe;
    logic [383:0] begin_frame = 0;
    logic begin_valid = 0, begin_camera = 0;
    wire begin_ready, begin_accepted;
    wire [1:0] capture_slot;
    logic [1:0] finish_valid = 0, finish_ok = 0;
    wire [1:0] finish_ready;

    wire [383:0] job_frame;
    wire [63:0] job_id;
    wire [1:0] job_bayer;
    wire job_time_valid, read_quiet, store_empty, store_fault;
    wire jpeg_fifo_valid, decode_start_valid;

    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arvalid, rready;
    logic arready = 0, rvalid = 0, rlast = 0;
    logic [3:0] rid = 0;
    logic [127:0] rdata = 0;
    logic [1:0] rresp = 0;

    logic offer_ready = 0, consumer_ready = 0, random_consumer = 0;
    logic coupled = 0, formatter_abort = 0, random_ready = 0;
    wire record_valid, raw_valid, raw_last, raw_done, raw_ok, raw_drained;
    wire [31:0] record_length;
    wire [127:0] record_identity, raw_data;
    wire [15:0] raw_keep;
    wire fmt_start_ready, fmt_in_ready, fmt_valid, fmt_last, fmt_done, fmt_drained;
    wire [127:0] fmt_data;
    wire [15:0] fmt_keep;
    wire host_ready = random_consumer ? random_ready : consumer_ready;
    wire record_ready = offer_ready && (!coupled || fmt_start_ready);
    wire raw_ready = coupled ? fmt_in_ready : host_ready;
    logic retire_valid = 0;
    logic [127:0] retire_identity = 0;
    wire retire_ready, retire_done, retire_error;

    stereo_raw_store #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .EXTERNAL_DECODER(1),
        .RAW_EXPORT_ENABLE(1), .VERIFY_DECODE_ACTIVE(1)
    ) store (
        .clk(clk), .rst_n(rst_n), .i_enable(1'b1), .i_stop(stop),
        .i_session(session), .i_epoch(epoch),
        .s_frame(begin_frame), .s_begin_valid(begin_valid), .i_begin_camera(begin_camera),
        .s_begin_ready(begin_ready), .o_begin_accepted(begin_accepted), .o_capture_slot(capture_slot),
        .i_finish_valid(finish_valid), .i_finish_ok(finish_ok), .o_finish_ready(finish_ready),
        .o_job_frame(job_frame), .i_job_ready(1'b0), .o_job_id(job_id),
        .o_job_bayer(job_bayer), .o_job_time_valid(job_time_valid),
        .i_retire_valid(1'b0), .i_retire_job_id(64'b0), .i_release_quiet(release_quiet),
        .o_retire_done(retire_done), .o_retire_error(retire_error),
        .i_req_valid(1'b0), .i_req_op(3'b0), .i_req_camera(1'b0), .i_req_slot(2'b0),
        .i_req_generation(32'b0), .i_req_session(32'b0), .i_req_lease(64'b0), .i_req_job_id(64'b0),
        .i_rsp_ready(1'b1),
        .i_processing_done(1'b0), .i_processing_error(1'b0), .i_processing_job_id(64'b0),
        .m_fifo_ready(1'b1), .m_fifo_valid(jpeg_fifo_valid),
        .o_read_quiet(read_quiet), .o_empty(store_empty), .o_fault(store_fault),
        .o_decode_start_valid(decode_start_valid), .i_decode_start_ready(1'b0),
        .i_decode_ready(1'b0), .i_decode_raw(40'b0), .i_decode_raw_valid(1'b0),
        .i_decode_sof(1'b0), .i_decode_eol(1'b0), .i_decode_done(1'b0),
        .i_decode_aborted(1'b0), .i_decode_quiet(1'b1), .i_decode_active(1'b0),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .i_raw_export(1'b1), .i_raw_cancel(cancel_raw),
        .o_raw_record_valid(record_valid), .i_raw_record_ready(record_ready),
        .o_raw_record_length(record_length), .o_raw_record_identity(record_identity),
        .o_raw_data(raw_data), .o_raw_keep(raw_keep), .o_raw_valid(raw_valid),
        .o_raw_last(raw_last), .i_raw_ready(raw_ready), .o_raw_done_valid(raw_done),
        .o_raw_done_ok(raw_ok), .o_raw_drained(raw_drained),
        .i_raw_retire_valid(retire_valid), .o_raw_retire_ready(retire_ready),
        .i_raw_retire_identity(retire_identity)
    );

    raw_video_record_formatter formatter (
        .i_clk(clk), .i_rst_n(rst_n),
        .i_start_valid(coupled && offer_ready && record_valid), .o_start_ready(fmt_start_ready),
        .i_abort(formatter_abort), .o_drained(fmt_drained),
        .i_payload_bytes(PAYLOAD_BYTES), .i_width(16'(WIDTH)), .i_height(16'(HEIGHT)),
        .i_sequence(job_frame[108:77]), .i_session(job_frame[76:45]),
        .i_epoch(job_frame[140:109]), .i_camera(job_frame[4]),
        .i_bayer_phase(job_bayer), .i_time_valid(job_time_valid),
        .i_capture_time_ns(job_frame[204:141]), .i_job_id(job_id),
        .s_data(raw_data), .s_keep(raw_keep), .s_valid(coupled && raw_valid),
        .s_last(raw_last), .s_ready(fmt_in_ready),
        .m_data(fmt_data), .m_keep(fmt_keep), .m_valid(fmt_valid), .m_last(fmt_last),
        .m_ready(host_ready), .o_done(fmt_done)
    );

    string case_name;
    int unsigned seed = 32'h953f0d12, flow_rng;
    int cycle = 0;
    logic [383:0] source_frame [1:MAX_TAG];
    int source_slot [1:MAX_TAG];
    int slot_owner [0:1][0:1], writer [0:1];
    logic [31:0] prior_generation [0:1][0:1];
    int completed_queue [0:1][0:MAX_TAG];
    int queue_head [0:1], queue_tail [0:1];

    int begin_count, begin_ack_count, offer_begin_count, offer_ack_count;
    logic [1:0] acknowledged_slot;
    int finish_count [0:1];
    int record_count, safe_count, retire_count, active_tag;
    bit record_started, safe_received, expect_success, allow_fault;
    logic [127:0] active_identity;
    logic [383:0] active_descriptor;
    logic [63:0] active_job_id;
    logic [511:0] expected_header;

    int ar_count, ar_stall_cycles, raw_stall_cycles, fmt_stall_cycles;
    int request_beats, responses_due, response_count, raw_bytes, fmt_bytes;
    int raw_done_count, raw_success_count, fmt_done_count;
    int raw_last_cycle, fmt_last_cycle;
    logic [3:0] response_id;
    bit ar_held, raw_held, fmt_held;
    logic [44:0] held_ar;
    logic [144:0] held_raw, held_fmt;

    function automatic logic [27:0] slot_base(input int camera, input int slot);
        return 28'h2000000 + camera*28'h4000000 + slot*28'h1000000;
    endfunction

    function automatic int unsigned stream_key(input int tag);
        return 32'h4ea175b8 ^ source_frame[tag][108:77] ^
               (tag * 32'h1bfe0173) ^ (source_frame[tag][4] ? 32'hf87cda3b : 32'h0b4cd2c4);
    endfunction

    function automatic logic [383:0] capture_descriptor(
        input bit camera, input logic [31:0] seq_num, input int tag
    );
        logic [383:0] descriptor;
        descriptor = '0;
        descriptor[3] = 1;
        descriptor[4] = camera;
        descriptor[76:45] = session;
        descriptor[108:77] = seq_num;
        descriptor[140:109] = epoch;
        descriptor[204:141] = 64'h5f219d3caf166281 + 17*tag;
        descriptor[220:205] = 16'(WIDTH);
        descriptor[236:221] = 16'(HEIGHT);
        descriptor[238:237] = 2'd1;
        descriptor[369:368] = tag[1:0];
        descriptor[370] = 1;
        descriptor[371] = !tag[2];
        return descriptor;
    endfunction

    always @(negedge clk) begin
        if (rst_n) begin
            flow_rng = next_random(flow_rng);
            random_ready = flow_rng[2:0] >= 3;
        end
    end

    always @(posedge clk) begin
        if (rst_n && rvalid && rready)
            rvalid <= 0;
        if (rst_n && retire_valid && retire_ready)
            retire_valid <= 0;
    end

    task automatic check_beat(
        input logic [127:0] data,
        input logic [15:0] keep,
        input logic last,
        input int offset, header_bytes,
        output int count
    );
        logic [7:0] expected_byte;
        count = header_bytes + PAYLOAD_BYTES - offset;
        if (count > 16)
            count = 16;
        if (count < 1 || keep !== low_keep(count))
            $fatal(1, "tag=%0d stream header=%0d offset=%0d KEEP=%h expected=%h",
                   active_tag, header_bytes, offset, keep, low_keep(count));
        if (last !== (offset + count == header_bytes + PAYLOAD_BYTES))
            $fatal(1, "tag=%0d stream header=%0d offset=%0d unexpected LAST=%b",
                   active_tag, header_bytes, offset, last);
        for (int lane = 0; lane < count; lane++) begin
            if (offset < header_bytes)
                expected_byte = expected_header[8*(offset+lane) +: 8];
            else
                expected_byte = payload_byte(stream_key(active_tag), offset+lane-header_bytes);
            if ((header_bytes == 0 || offset != 32 || lane >= 8 || source_frame[active_tag][371]) &&
                data[8*lane +: 8] !== expected_byte)
                $fatal(1, "tag=%0d stream header=%0d byte=%0d got=%h expected=%h",
                       active_tag, header_bytes, offset+lane, data[8*lane +: 8], expected_byte);
        end
    endtask

    always @(posedge clk) begin : public_scoreboard
        int camera, slot, tag, count, burst_beats;
        logic [383:0] expected_descriptor;
        logic [63:0] expected_job;
        logic [27:0] expected_addr;

        cycle++;
        if (!rst_n) begin
            begin_count = 0;
            begin_ack_count = 0;
            record_count = 0;
            safe_count = 0;
            retire_count = 0;
            active_tag = 0;
            record_started = 0;
            safe_received = 0;
            ar_held = 0;
            raw_held = 0;
            fmt_held = 0;
            responses_due = 0;
            response_count = 0;
            raw_done_count = 0;
            raw_success_count = 0;
            fmt_done_count = 0;
            for (int eye = 0; eye < 2; eye++) begin
                finish_count[eye] = 0;
                writer[eye] = 0;
                queue_head[eye] = 0;
                queue_tail[eye] = 0;
                for (int s = 0; s < 2; s++) begin
                    slot_owner[eye][s] = 0;
                    prior_generation[eye][s] = 0;
                end
            end
        end else begin
            if (jpeg_fifo_valid !== 0 || decode_start_valid !== 0)
                $fatal(1, "exclusive RAW mode presented JPEG or decode traffic at cycle=%0d", cycle);
            if (!allow_fault && store_fault !== 0)
                $fatal(1, "unexpected store fault tag=%0d cycle=%0d", active_tag, cycle);

            if (begin_valid && begin_ready) begin
                begin_count++;
                if ($isunknown(begin_accepted))
                    $fatal(1, "BEGIN handshake without a valid accepted result");
                if (begin_accepted) begin
                    begin_ack_count++;
                    acknowledged_slot = capture_slot;
                end
            end
            for (int eye = 0; eye < 2; eye++) begin
                if (finish_valid[eye] && finish_ready[eye]) begin
                    finish_count[eye]++;
                    tag = writer[eye];
                    if (tag == 0)
                        $fatal(1, "TB finished eye %0d without a captured slot", eye);
                    writer[eye] = 0;
                    if (finish_ok[eye]) begin
                        completed_queue[eye][queue_tail[eye]] = tag;
                        queue_tail[eye]++;
                    end else begin
                        slot_owner[eye][source_slot[tag]] = 0;
                    end
                end
            end

            if (record_valid && active_tag == 0) begin
                if ($isunknown({job_frame[4], job_frame[6:5], job_frame[44:13], record_identity}))
                    $fatal(1, "record had unknown camera, slot, generation, or identity");
                camera = int'(job_frame[4]);
                if (queue_head[camera] >= queue_tail[camera])
                    $fatal(1, "eye %0d offered an unpublished record", camera);
                tag = completed_queue[camera][queue_head[camera]];
                slot = source_slot[tag];
                expected_descriptor = source_frame[tag];
                expected_descriptor[6:5] = 2'(slot);
                expected_descriptor[44:13] = job_frame[44:13];
                expected_descriptor[383:367] = '0;
                expected_descriptor[0] = 0;
                expected_job = {32'h80000000, job_frame[44:13]};
                if (job_frame !== expected_descriptor)
                    $fatal(1, "descriptor mismatch eye=%0d tag=%0d seq=%h expected=%h frame=%h expected_frame=%h",
                           camera, tag, job_frame[108:77], expected_descriptor[108:77], job_frame, expected_descriptor);
                if (job_frame[44:13] == 0 || job_frame[44:13] == prior_generation[camera][slot] ||
                    job_id !== expected_job || job_bayer !== source_frame[tag][369:368] ||
                    job_time_valid !== source_frame[tag][371] || record_length !== PAYLOAD_BYTES+64)
                    $fatal(1, "bad generation/job/length/metadata eye=%0d tag=%0d job=%h length=%0d",
                           camera, tag, job_id, record_length);
                prior_generation[camera][slot] = job_frame[44:13];
                active_tag = tag;
                active_identity = record_identity;
                active_descriptor = expected_descriptor;
                active_job_id = expected_job;
                expected_header = araw_header(PAYLOAD_BYTES, 16'(WIDTH), 16'(HEIGHT),
                    source_frame[tag][108:77], source_frame[tag][76:45], source_frame[tag][140:109],
                    source_frame[tag][4], source_frame[tag][369:368], source_frame[tag][371],
                    source_frame[tag][204:141], expected_job);
                ar_count = 0;
                ar_stall_cycles = 0;
                raw_stall_cycles = 0;
                fmt_stall_cycles = 0;
                request_beats = 0;
                responses_due = 0;
                response_count = 0;
                raw_bytes = 0;
                fmt_bytes = 0;
                raw_done_count = 0;
                raw_success_count = 0;
                fmt_done_count = 0;
                raw_last_cycle = -100;
                fmt_last_cycle = -100;
                $display("CHECK offer tag=%0d eye=%0d slot=%0d seq=%h gen=%h identity=%h",
                         tag, camera, slot, job_frame[108:77], job_frame[44:13], record_identity);
            end
            if (active_tag != 0 && !safe_received) begin
                if ({record_identity, job_frame, job_id, record_length, job_bayer, job_time_valid} !==
                    {active_identity, active_descriptor, active_job_id, 32'(PAYLOAD_BYTES+64),
                     source_frame[active_tag][369:368], source_frame[active_tag][371]})
                    $fatal(1, "descriptor or identity changed before SAFE tag=%0d", active_tag);
                if (!record_started && record_valid !== 1)
                    $fatal(1, "store withdrew a pending RAW offer tag=%0d cycle=%0d", active_tag, cycle);
            end
            if (record_valid && record_ready) begin
                if (active_tag == 0 || record_started)
                    $fatal(1, "duplicate or anonymous RAW START");
                record_started = 1;
                record_count++;
                $display("CHECK RAW START tag=%0d cycle=%0d", active_tag, cycle);
            end

            if (ar_held && {arvalid, arid, araddr, arlen, arsize, arburst} !== {1'b1, held_ar})
                $fatal(1, "AXI AR changed while stalled tag=%0d cycle=%0d", active_tag, cycle);
            ar_held = arvalid && !arready;
            held_ar = {arid, araddr, arlen, arsize, arburst};
            if (ar_held)
                ar_stall_cycles++;
            if (arvalid) begin
                if (!record_started || active_tag == 0)
                    $fatal(1, "AXI AR presented before record acceptance");
                if ($isunknown({arid, araddr, arlen, arsize, arburst}))
                    $fatal(1, "AXI AR contains unknown bits");
                expected_addr = slot_base(int'(source_frame[active_tag][4]), source_slot[active_tag]) + 16*request_beats;
                burst_beats = int'(arlen) + 1;
                if (araddr !== expected_addr || arsize !== 3'd4 || arburst !== 2'd1 ||
                    burst_beats > 16 || burst_beats + request_beats > PAYLOAD_BEATS ||
                    int'(araddr[11:0]) + 16*burst_beats > 4096)
                    $fatal(1, "bad AXI AR tag=%0d addr=%h expected=%h len=%0d size=%0d burst=%0d",
                           active_tag, araddr, expected_addr, burst_beats, arsize, arburst);
            end

            if (rvalid && rready) begin
                if (responses_due == 0)
                    $fatal(1, "DUT accepted R without an accepted AR tag=%0d", active_tag);
                response_count++;
                responses_due--;
            end
            if (arvalid && arready) begin
                if (responses_due != 0)
                    $fatal(1, "DUT accepted multiple outstanding AR requests");
                ar_count++;
                request_beats += burst_beats;
                responses_due = burst_beats;
                response_id = arid;
                if (araddr[11:0] == 0)
                    $display("CHECK AXI burst page start addr=%h beats=%0d", araddr, burst_beats);
            end

            if (raw_held && {raw_valid, raw_data, raw_keep, raw_last} !== {1'b1, held_raw})
                $fatal(1, "RAW payload changed while stalled tag=%0d byte=%0d cycle=%0d stop=%b cancel=%b",
                       active_tag, raw_bytes, cycle, stop, cancel_raw);
            raw_held = raw_valid && !raw_ready;
            held_raw = {raw_data, raw_keep, raw_last};
            if (raw_held)
                raw_stall_cycles++;
            if (raw_valid && (!record_started || active_tag == 0))
                $fatal(1, "RAW payload presented before accepted record");
            if (raw_valid && raw_ready) begin
                if (response_count <= raw_bytes / 16)
                    $fatal(1, "RAW payload transferred without a corresponding AXI response");
                check_beat(raw_data, raw_keep, raw_last, raw_bytes, 0, count);
                raw_bytes += count;
                if (raw_last)
                    raw_last_cycle = cycle;
            end
            if ((ar_held || raw_held || responses_due != 0) &&
                (raw_drained !== 0 || read_quiet !== 0))
                $fatal(1, "store declared drain/quiet with pending AXI or RAW tag=%0d cycle=%0d", active_tag, cycle);
            if (raw_done_count != 0 && active_tag != 0 && !safe_received &&
                {raw_done, raw_ok} !== {1'b1, 1'(raw_success_count)})
                $fatal(1, "held RAW DONE or status changed before SAFE tag=%0d", active_tag);
            if (raw_done && raw_done_count == 0) begin
                if (!record_started || $isunknown(raw_ok))
                    $fatal(1, "anonymous or unknown RAW DONE tag=%0d started=%b cycle=%0d", active_tag, record_started, cycle);
                if (raw_ok) begin
                    if (!expect_success || raw_last_cycle < 0 ||
                        raw_bytes != PAYLOAD_BYTES || response_count != PAYLOAD_BEATS || responses_due != 0)
                        $fatal(1, "invalid successful RAW DONE tag=%0d bytes=%0d R=%0d outstanding=%0d cycle=%0d last_cycle=%0d",
                               active_tag, raw_bytes, response_count, responses_due, cycle, raw_last_cycle);
                    raw_success_count++;
                end else if (!allow_fault && (raw_held || ar_held || responses_due != 0)) begin
                    $fatal(1, "negative RAW DONE with AXI or payload commitments still pending");
                end
                raw_done_count++;
                $display("CHECK RAW DONE tag=%0d ok=%b cycle=%0d last_cycle=%0d outstanding=%0d",
                         active_tag, raw_ok, cycle, raw_last_cycle, responses_due);
            end

            if (fmt_held && {fmt_valid, fmt_data, fmt_keep, fmt_last} !== {1'b1, held_fmt})
                $fatal(1, "combined record changed while stalled tag=%0d byte=%0d", active_tag, fmt_bytes);
            fmt_held = fmt_valid && !host_ready;
            held_fmt = {fmt_data, fmt_keep, fmt_last};
            if (fmt_held)
                fmt_stall_cycles++;
            if (fmt_valid && (!coupled || !record_started || active_tag == 0))
                $fatal(1, "formatter presented a record without a joint START");
            if (fmt_valid && host_ready) begin
                check_beat(fmt_data, fmt_keep, fmt_last, fmt_bytes, 64, count);
                fmt_bytes += count;
                if (fmt_last)
                    fmt_last_cycle = cycle;
            end
            if (fmt_done) begin
                if (fmt_done_count != 0 || (cycle != fmt_last_cycle && cycle != fmt_last_cycle+1))
                    $fatal(1, "combined formatter DONE without a unique last handshake");
                fmt_done_count++;
            end

            if (retire_valid && retire_ready) begin
                if (active_tag == 0 || !record_started || raw_done_count != 1 || safe_received ||
                    retire_identity !== active_identity || store_fault)
                    $fatal(1, "unqualified SAFE accepted tag=%0d done=%0d fault=%b identity=%h active=%h",
                           active_tag, raw_done_count, store_fault, retire_identity, active_identity);
                safe_received = 1;
                safe_count++;
            end
            if (retire_error)
                $fatal(1, "owner retirement error tag=%0d after SAFE=%b", active_tag, safe_received);
            if (retire_done) begin
                if (!safe_received || !release_quiet || active_tag == 0 || store_fault)
                    $fatal(1, "owner retired without qualified SAFE and release quiet tag=%0d quiet=%b fault=%b",
                           active_tag, release_quiet, store_fault);
                camera = int'(active_descriptor[4]);
                slot_owner[camera][source_slot[active_tag]] = 0;
                queue_head[camera]++;
                retire_count++;
                $display("CHECK SAFE tag=%0d eye=%0d AR=%0d R=%0d RAW_bytes=%0d record_bytes=%0d stalls=%0d/%0d/%0d success=%0d",
                         active_tag, camera, ar_count, response_count, raw_bytes, fmt_bytes,
                         ar_stall_cycles, raw_stall_cycles, fmt_stall_cycles, raw_success_count);
                active_tag = 0;
                record_started = 0;
                safe_received = 0;
            end
        end
    end

    task automatic step(input int count = 1);
        repeat (count) @(negedge clk);
    endtask

    task automatic reset_store(input bit change_identity = 0);
        rst_n = 0;
        begin_valid = 0;
        finish_valid = 0;
        finish_ok = 0;
        stop = 0;
        cancel_raw = 0;
        release_quiet = 1;
        retire_valid = 0;
        offer_ready = 0;
        consumer_ready = 0;
        random_consumer = 0;
        coupled = 0;
        formatter_abort = 0;
        arready = 0;
        rvalid = 0;
        allow_fault = 0;
        expect_success = 1;
        if (change_identity) begin
            session ^= 32'hfc1b7a55;
            epoch += 23;
        end
        step(20);
        rst_n = 1;
        step(28);
        if (store_empty !== 1 || read_quiet !== 1 || record_valid !== 0 || arvalid !== 0 ||
            raw_valid !== 0 || fmt_drained !== 1)
            $fatal(1, "store did not reset to idle empty=%b read_quiet=%b raw_drained=%b record_valid=%b",
                   store_empty, read_quiet, raw_drained, record_valid);
    endtask

    task automatic present_begin(input int tag, input bit camera, input logic [31:0] seq_num);
        if (begin_valid || writer[camera] != 0)
            $fatal(1, "TB attempted to overlap capture BEGIN on eye=%0d", camera);
        source_frame[tag] = capture_descriptor(camera, seq_num, tag);
        begin_frame = source_frame[tag];
        begin_camera = camera;
        offer_begin_count = begin_count;
        offer_ack_count = begin_ack_count;
        begin_valid = 1;
    endtask

    task automatic await_begin(input int tag);
        int camera, slot;
        camera = int'(source_frame[tag][4]);
        for (int tries = 0; begin_count == offer_begin_count && tries < 80; tries++)
            step();
        if (begin_count != offer_begin_count + 1)
            $fatal(1, "capture BEGIN did not handshake tag=%0d eye=%0d", tag, camera);
        begin_valid = 0;
        if (begin_ack_count != offer_ack_count + 1 || $isunknown(acknowledged_slot) || acknowledged_slot > 1)
            $fatal(1, "capture BEGIN acknowledgement invalid tag=%0d eye=%0d slot=%h ack_count=%0d expected=%0d",
                   tag, camera, acknowledged_slot, begin_ack_count, offer_ack_count+1);
        slot = int'(acknowledged_slot);
        if (slot_owner[camera][slot] != 0)
            $fatal(1, "capture reused an unretired slot tag=%0d eye=%0d slot=%0d prior_tag=%0d",
                   tag, camera, slot, slot_owner[camera][slot]);
        source_slot[tag] = slot;
        slot_owner[camera][slot] = tag;
        writer[camera] = tag;
        $display("CHECK capture tag=%0d eye=%0d slot=%0d", tag, camera, slot);
    endtask

    task automatic begin_capture(input int tag, input bit camera, input logic [31:0] seq_num);
        present_begin(tag, camera, seq_num);
        await_begin(tag);
    endtask

    task automatic reject_begin(input int tag, input bit camera, input logic [31:0] seq_num);
        present_begin(tag, camera, seq_num);
        for (int tries = 0; begin_count == offer_begin_count && tries < 80; tries++)
            step();
        begin_valid = 0;
        if (begin_count != offer_begin_count+1 || begin_ack_count != offer_ack_count)
            $fatal(1, "full eye did not explicitly reject BEGIN tag=%0d eye=%0d", tag, camera);
    endtask

    task automatic finish_capture(input int tag, input bit success);
        int camera, prior_finishes;
        camera = int'(source_frame[tag][4]);
        if (writer[camera] != tag)
            $fatal(1, "TB finish does not match writer tag=%0d eye=%0d", tag, camera);
        prior_finishes = finish_count[camera];
        finish_ok[camera] = success;
        finish_valid[camera] = 1;
        for (int tries = 0; finish_count[camera] == prior_finishes && tries < 80; tries++)
            step();
        if (finish_count[camera] != prior_finishes+1)
            $fatal(1, "writer+SOURCE finish did not handshake tag=%0d eye=%0d", tag, camera);
        finish_valid[camera] = 0;
        finish_ok[camera] = 0;
    endtask

    task automatic capture_ok(input int tag, input bit camera, input logic [31:0] seq_num);
        begin_capture(tag, camera, seq_num);
        finish_capture(tag, 1);
    endtask

    task automatic wait_offer(input int wanted_tag = 0);
        for (int tries = 0; active_tag == 0 && tries < 100; tries++)
            step();
        if (record_valid !== 1 || active_tag == 0 || (wanted_tag != 0 && active_tag != wanted_tag))
            $fatal(1, "RAW offer not presented or out of order wanted_tag=%0d actual_tag=%0d valid=%b",
                   wanted_tag, active_tag, record_valid);
    endtask

    task automatic accept_offer;
        int prior_starts;
        prior_starts = record_count;
        offer_ready = 1;
        for (int tries = 0; record_count == prior_starts && tries < 80; tries++)
            step();
        offer_ready = 0;
        if (record_count != prior_starts+1)
            $fatal(1, "pending RAW offer did not handshake tag=%0d", active_tag);
    endtask

    task automatic accept_ar(input int stall_cycles);
        int previous_ar_count;
        previous_ar_count = ar_count;
        for (int tries = 0; arvalid !== 1 && tries < 80; tries++)
            step();
        if (arvalid !== 1)
            $fatal(1, "AXI AR was not presented tag=%0d offset=%0d", active_tag, 16*request_beats);
        step(stall_cycles);
        arready = 1;
        step();
        arready = 0;
        if (ar_count != previous_ar_count+1 || responses_due < 1)
            $fatal(1, "AXI AR did not transfer tag=%0d", active_tag);
    endtask

    task automatic present_response(
        input logic [1:0] response,
        input bit bad_id,
        input int override_last
    );
        if (responses_due < 1 || rvalid)
            $fatal(1, "TB sent an unsolicited or overlapping R response");
        rid = response_id ^ (bad_id ? 4'h1 : 4'h0);
        rdata = payload_word(stream_key(active_tag), 16*response_count);
        rresp = response;
        rlast = override_last < 0 ? responses_due == 1 : override_last == 1;
        rvalid = 1;
    endtask

    task automatic await_response(input int previous_r_count);
        for (int tries = 0; response_count == previous_r_count && tries < 100; tries++)
            step();
        if (response_count != previous_r_count+1)
            $fatal(1, "AXI R was not consumed tag=%0d beat=%0d RID=%h RRESP=%h RLAST=%b raw_valid=%b raw_ready=%b fault=%b",
                   active_tag, previous_r_count, rid, rresp, rlast, raw_valid, raw_ready, store_fault);
        rvalid = 0;
    endtask

    task automatic send_response(
        input logic [1:0] response = 0,
        input bit bad_id = 0,
        input int override_last = -1
    );
        int prior_responses;
        prior_responses = response_count;
        present_response(response, bad_id, override_last);
        await_response(prior_responses);
    endtask

    task automatic complete_burst;
        while (responses_due != 0) begin
            seed = next_random(seed);
            step(int'(seed % 4));
            send_response();
        end
    endtask

    task automatic wait_terminal(input bit success);
        for (int tries = 0; (raw_done_count == 0 || raw_drained !== 1 || read_quiet !== 1) && tries < 100; tries++)
            step();
        step(4);
        if (raw_done_count != 1 || raw_success_count != int'(success) || raw_drained !== 1 ||
            read_quiet !== 1 || raw_valid !== 0 || arvalid !== 0 || responses_due != 0 || store_empty !== 0)
            $fatal(1, "terminal tag=%0d done=%0d ok=%0d/%0d drained=%b quiet=%b raw=%b ar=%b outstanding=%0d empty=%b",
                   active_tag, raw_done_count, raw_success_count, success, raw_drained, read_quiet,
                   raw_valid, arvalid, responses_due, store_empty);
        if (coupled && success && (fmt_done_count != 1 || fmt_bytes != PAYLOAD_BYTES+64 || fmt_drained !== 1))
            $fatal(1, "combined record terminal done=%0d bytes=%0d drained=%b", fmt_done_count, fmt_bytes, fmt_drained);
    endtask

    task automatic reject_safe(input logic [127:0] identity);
        int previous_safes;
        previous_safes = safe_count;
        retire_identity = identity;
        retire_valid = 1;
        step(2);
        retire_valid = 0;
        if (safe_count != previous_safes)
            $fatal(1, "store accepted invalid or premature SAFE");
    endtask

    task automatic present_matching_safe;
        retire_identity = active_identity;
        retire_valid = 1;
    endtask

    task automatic await_safe(input int previous_safes);
        for (int tries = 0; safe_count == previous_safes && tries < 80; tries++)
            step();
        retire_valid = 0;
        if (safe_count != previous_safes+1)
            $fatal(1, "matching SAFE did not handshake tag=%0d release_quiet=%b fault=%b",
                   active_tag, release_quiet, store_fault);
    endtask

    task automatic await_retire(input int prior_retires);
        for (int tries = 0; retire_count == prior_retires && tries < 80; tries++)
            step();
        if (retire_count != prior_retires+1)
            $fatal(1, "matching SAFE did not retire owner slot tag=%0d release_quiet=%b fault=%b",
                   active_tag, release_quiet, store_fault);
    endtask

    task automatic retire_active;
        int previous_safes, prior_retires;
        previous_safes = safe_count;
        prior_retires = retire_count;
        present_matching_safe();
        await_safe(previous_safes);
        await_retire(prior_retires);
    endtask

    task automatic wait_empty;
        for (int tries = 0; store_empty !== 1 && tries < 100; tries++)
            step();
        if (store_empty !== 1 || record_valid !== 0 || arvalid !== 0 || raw_valid !== 0)
            $fatal(1, "store failed to return empty; empty=%b record=%b ar=%b raw=%b",
                   store_empty, record_valid, arvalid, raw_valid);
    endtask

    task automatic normal_transfer;
        expect_success = 1;
        random_consumer = 1;
        accept_offer();
        reject_safe(active_identity);
        while (request_beats < PAYLOAD_BEATS) begin
            seed = next_random(seed);
            accept_ar(2 + int'(seed % 6));
            if (PAYLOAD_BEATS > 16 && ar_count == 1) begin
                // A slave is allowed to keep ARREADY high while delaying all R beats.
                arready = 1;
                step(11);
                arready = 0;
                $display("CHECK ARREADY high for 11 cycles with first burst outstanding and RVALID low");
            end
            complete_burst();
        end
        wait_terminal(1);
        random_consumer = 0;
        if (ar_stall_cycles == 0)
            $fatal(1, "TB did not exercise AR backpressure");
    endtask

    task automatic check_order_and_safe;
        logic [127:0] retired_identity;
        int released_slot, previous_safes, prior_retires;
        coupled = 1;
        begin_capture(6, 0, 32'hfffffffe);
        step(15);
        if (record_valid !== 0 || arvalid !== 0)
            $fatal(1, "BEGIN alone published a RAW record");
        finish_capture(6, 0);
        step(15);
        if (record_valid !== 0 || arvalid !== 0)
            $fatal(1, "unsuccessful writer+SOURCE finish published a record");
        wait_empty();

        begin_capture(1, 0, 32'hffffffff);
        begin_capture(3, 1, 32'hffffffff);
        finish_capture(3, 1);
        wait_offer(3);
        finish_capture(1, 1);
        begin_capture(2, 0, 32'h00000001);
        capture_ok(4, 1, 32'h00000001);
        reject_safe(active_identity);
        normal_transfer();

        retired_identity = active_identity;
        released_slot = source_slot[3];
        reject_begin(5, 1, 32'h00000002);
        for (int bit_index = 0; bit_index < 128; bit_index++)
            reject_safe(retired_identity ^ (128'b1 << bit_index));
        release_quiet = 0;
        previous_safes = safe_count;
        prior_retires = retire_count;
        present_matching_safe();
        for (int tries = 0; safe_count == previous_safes && tries < 10; tries++)
            step();
        if (safe_count != previous_safes)
            retire_valid = 0;
        reject_begin(5, 1, 32'h00000002);
        if (retire_count != prior_retires || store_empty !== 0)
            $fatal(1, "owner released a slot before release quiet");
        $display("CHECK matching SAFE accepted while release_quiet=0: %0d", safe_count != previous_safes);
        release_quiet = 1;
        if (writer[0] != 2)
            $fatal(1, "TB lost independent WRITING pressure during SAFE");
        await_safe(previous_safes);
        await_retire(prior_retires);
        begin_capture(5, 1, 32'h00000002);
        if (source_slot[5] != released_slot)
            $fatal(1, "camera did not reuse its uniquely retired slot");
        finish_capture(2, 1);
        finish_capture(5, 1);
        $display("CHECK rejected every single-bit SAFE mutation and delayed owner retirement until release_quiet=1");

        repeat (4) begin
            wait_offer();
            if (active_identity === retired_identity)
                $fatal(1, "distinct live records share a SAFE identity");
            normal_transfer();
            reject_safe(retired_identity);
            retire_active();
        end
        wait_empty();
        if (record_count != 5 || retire_count != 5)
            $fatal(1, "eye ordering/fairness did not complete all five records");
    endtask

    task automatic check_page_crossing;
        if (PAYLOAD_BYTES != 4160)
            $fatal(1, "4KiB case must be parameterized for 4160 bytes");
        coupled = 1;
        capture_ok(1, 1, 32'hc13700a2);
        wait_offer(1);
        normal_transfer();
        if (request_beats != 260 || ar_count < 17 || response_count != 260 || fmt_stall_cycles == 0)
            $fatal(1, "4KiB case missed AXI boundary or record backpressure");
        retire_active();
        wait_empty();
    endtask

    task automatic assert_pending_drain(input string location);
        if (raw_drained !== 0 || read_quiet !== 0 || raw_done_count != 0)
            $fatal(1, "%s prematurely drained: raw_drained=%b quiet=%b done=%0d ARVALID=%b outstanding=%0d RAW_VALID=%b",
                   location, raw_drained, read_quiet, raw_done_count, arvalid, responses_due, raw_valid);
    endtask

    task automatic stop_pending_offer;
        capture_ok(1, 0, 32'hc701a309);
        wait_offer(1);
        capture_ok(2, 1, 32'hc701a309);
        step(8);
        expect_success = 0;
        stop = 1;
        step(12);
        if (record_valid !== 1 || arvalid !== 0)
            $fatal(1, "STOP withdrew a pending RAW offer or started an unaccepted read");
        reject_safe(active_identity);
        accept_offer();
        consumer_ready = 1;
        wait_terminal(0);
        if (ar_count != 0 || raw_bytes != 0)
            $fatal(1, "STOPped pending offer created AXI or payload traffic");
        retire_active();
        wait_empty();
        if (record_count != 1)
            $fatal(1, "STOP published another record that had never been presented");
    endtask

    task automatic cancel_pending_ar(input bit already_accepted);
        capture_ok(1, 0, 32'h497e00d5);
        wait_offer(1);
        accept_offer();
        if (already_accepted) begin
            accept_ar(4);
        end else begin
            for (int tries = 0; arvalid !== 1 && tries < 80; tries++)
                step();
            if (arvalid !== 1)
                $fatal(1, "AXI AR did not reach the backpressure boundary");
            step(4);
        end
        expect_success = 0;
        cancel_raw = 1;
        step(10);
        assert_pending_drain(already_accepted ? "cancel awaiting AXI R" : "cancel on stalled AXI AR");
        reject_safe(active_identity);
        if (!already_accepted)
            accept_ar(4);
        consumer_ready = 1;
        complete_burst();
        wait_terminal(0);
        if (ar_count != 1)
            $fatal(1, "cancel produced an extra read after satisfying committed burst");
        retire_active();
        wait_empty();
    endtask

    task automatic stop_or_cancel_pending_payload(input bit is_stop, input bit combined);
        int previous_r_count, expected_prefix;
        coupled = combined;
        capture_ok(1, 1, 32'hdb00922e);
        wait_offer(1);
        accept_offer();
        accept_ar(5);
        if (is_stop) begin
            if (responses_due != 2)
                $fatal(1, "TB expects one two-beat burst for stalled-final fixture");
            consumer_ready = 1;
            send_response();
            consumer_ready = 0;
        end
        previous_r_count = response_count;
        present_response(0, 0, -1);
        for (int tries = 0; raw_valid !== 1 && tries < 80; tries++)
            step();
        if (raw_valid !== 1 || raw_ready !== 0 || raw_last !== is_stop)
            $fatal(1, "RAW payload did not reach backpressure boundary, valid=%b ready=%b last=%b",
                   raw_valid, raw_ready, raw_last);
        step(5);
        expect_success = 0;
        stop = is_stop;
        cancel_raw = !is_stop;
        step(9);
        assert_pending_drain(is_stop ? "STOP on stalled final RAW beat" : "cancel on stalled first RAW beat");
        reject_safe(active_identity);
        consumer_ready = 1;
        await_response(previous_r_count);
        complete_burst();
        wait_terminal(0);
        expected_prefix = is_stop ? PAYLOAD_BYTES : 16;
        if (raw_bytes != expected_prefix || raw_stall_cycles == 0)
            $fatal(1, "cancel/STOP delivered %0d bytes, expected already-presented prefix %0d", raw_bytes, expected_prefix);
        if (combined) begin
            formatter_abort = 1;
            for (int tries = 0; fmt_drained !== 1 && tries < 40; tries++)
                step();
            if (fmt_drained !== 1 || fmt_done_count != 0 || fmt_bytes != 64 + expected_prefix)
                $fatal(1, "combined abort did not preserve accepted record prefix or fabricated DONE");
            formatter_abort = 0;
        end
        retire_active();
        wait_empty();
    endtask

    task automatic verify_reset_recovery(input logic [127:0] prior_identity);
        reset_store(1);
        coupled = 1;
        capture_ok(3, 1, 32'hf0070e22);
        wait_offer(3);
        if (active_identity === prior_identity)
            $fatal(1, "changed session/epoch did not change external SAFE identity after reset");
        normal_transfer();
        reject_safe(prior_identity);
        retire_active();
        wait_empty();
    endtask

    task automatic check_bad_response(input string kind);
        logic [127:0] prior_identity;
        int previous_r_count;
        capture_ok(1, 1, 32'hf0070e22);
        wait_offer(1);
        prior_identity = active_identity;
        expect_success = 0;
        accept_offer();
        consumer_ready = 1;
        accept_ar(3);
        if (kind == "store_rresp" || kind == "store_rresp_final") begin
            if (kind == "store_rresp_final") begin
                if (responses_due != PAYLOAD_BEATS)
                    $fatal(1, "TB final RRESP fixture needs one burst");
                while (responses_due > 1)
                    send_response();
                send_response(2'b11);
            end else begin
                send_response(2'b10);
            end
            complete_burst();
            wait_terminal(0);
            retire_active();
            wait_empty();
        end else begin
            allow_fault = 1;
            if (responses_due < 2)
                $fatal(1, "TB malformed response fixture needs an initial burst of at least two beats");
            if (kind == "store_missing_rlast")
                send_response();
            previous_r_count = response_count;
            present_response(0, kind == "store_bad_rid", kind == "store_early_rlast" ? 1 : 0);
            for (int tries = 0; store_fault !== 1 && tries < 100; tries++) begin
                step();
                if (response_count != previous_r_count)
                    rvalid = 0;
            end
            if (store_fault !== 1 || raw_drained !== 0 || read_quiet !== 0 || store_empty !== 0 || raw_success_count != 0)
                $fatal(1, "malformed AXI response escaped isolation fault=%b drained=%b quiet=%b empty=%b ok=%0d",
                       store_fault, raw_drained, read_quiet, store_empty, raw_success_count);
            reject_safe(prior_identity);
            step(14);
            if (store_fault !== 1 || raw_drained !== 0 || read_quiet !== 0 || arvalid !== 0 || raw_success_count != 0)
                $fatal(1, "protocol fault did not remain isolated until common reset");
            $display("CHECK malformed AXI response held fault, blocked SAFE, and remained non-quiet kind=%s R handshakes=%0d",
                     kind, response_count);
        end

        verify_reset_recovery(prior_identity);
    endtask

    task automatic check_reset_pending_raw;
        logic [127:0] prior_identity;
        coupled = 1;
        capture_ok(1, 1, 32'hf0070e22);
        wait_offer(1);
        prior_identity = active_identity;
        accept_offer();
        accept_ar(3);
        present_response(0, 0, -1);
        for (int tries = 0; raw_valid !== 1 && tries < 80; tries++)
            step();
        if (raw_valid !== 1 || raw_ready !== 0 || fmt_valid !== 1 || host_ready !== 0)
            $fatal(1, "TB common-reset fixture did not reach stalled RAW and header");
        step(8);
        assert_pending_drain("before common reset with RAW and record stalled");
        $display("CHECK common reset with RAW and record stalled R accepted=%0d outstanding=%0d",
                 response_count, responses_due);
        verify_reset_recovery(prior_identity);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name))
            $fatal(1, "missing +CASE");
        void'($value$plusargs("SEED=%d", seed));
        if (seed == 0)
            $fatal(1, "seed must be nonzero");
        flow_rng = seed ^ 32'hbd308d42;
        $display("BEGIN case=%s seed=%0d geometry=%0dx%0d payload_bytes=%0d", case_name, seed, WIDTH, HEIGHT, PAYLOAD_BYTES);
        step();
        reset_store();
        case (case_name)
            "store_order_and_safe": check_order_and_safe();
            "store_4k": check_page_crossing();
            "store_stop_offer": stop_pending_offer();
            "store_cancel_ar": cancel_pending_ar(0);
            "store_cancel_await_r": cancel_pending_ar(1);
            "store_cancel_payload": stop_or_cancel_pending_payload(0, 0);
            "store_stop_last": stop_or_cancel_pending_payload(1, 0);
            "store_cancel_combined": stop_or_cancel_pending_payload(0, 1);
            "store_rresp", "store_rresp_final", "store_bad_rid", "store_early_rlast", "store_missing_rlast":
                check_bad_response(case_name);
            "store_reset_pending_raw": check_reset_pending_raw();
            default: $fatal(1, "unknown case %s", case_name);
        endcase
        $display("BLACKBOX_PASS %s cycles=%0d", case_name, cycle);
        $finish;
    end

    initial begin
        #60000;
        $fatal(1, "store watchdog case=%s cycle=%0d tag=%0d AR=%0d R=%0d bytes=%0d fmt_bytes=%0d",
               case_name, cycle, active_tag, ar_count, response_count, raw_bytes, fmt_bytes);
    end
endmodule
