`timescale 1ns/1ps

module tb_jpeg_ring_reset;
    localparam integer FIRST_LENGTH = 16 * 260 + 7;
    localparam logic [3:0] RETIRE_OK = 4'd0;
    localparam logic [3:0] RETIRE_STALE = 4'd2;
    localparam logic [3:0] RETIRE_BUSY = 4'd3;
    localparam logic [27:0] SLOT_BASE [0:5] = '{
        28'h0000000, 28'hA000000, 28'hB000000,
        28'hC000000, 28'hD000000, 28'hE000000
    };

    logic i_clk = 0, i_cold_rst_n = 1, clock_running = 0;
    logic i_ddr_ready = 1;
    logic i_start_valid = 0;
    wire o_start_ready;
    logic [31:0] i_capture_id = 0, i_write_tag = 0, i_session_id = 0, i_mode_epoch = 0;
    logic [15:0] i_width = 0, i_height = 0;
    logic [63:0] i_timestamp_ns = 0;
    logic [7:0] i_quality = 0;
    logic i_camera_id = 0;
    logic [127:0] i_jpeg_tdata = 0;
    logic [15:0] i_jpeg_tkeep = 0;
    logic i_jpeg_tvalid = 0, i_jpeg_tlast = 0;
    wire o_jpeg_tready;
    logic i_result_valid = 0, i_result_ok = 0;
    logic [31:0] i_result_id = 0, i_result_epoch = 0;
    logic [24:0] i_result_length = 0;
    logic [7:0] i_result_quality = 0;
    wire o_result_ready;

    logic i_write_result_ready = 0;
    wire o_write_result_valid, o_write_result_ok, o_write_result_camera;
    wire [7:0] o_write_result_error;
    wire [31:0] o_write_result_capture_id, o_write_result_session, o_write_result_epoch;
    wire [31:0] o_write_result_generation, o_write_result_tag;
    wire [15:0] o_write_result_slot;
    wire [24:0] o_write_result_payload_length;
    logic i_ready_claim = 0;
    wire o_ready_valid, o_camera_id;
    wire [31:0] o_capture_id, o_session_id, o_mode_epoch, o_generation;
    wire [15:0] o_width, o_height, o_slot_id;
    wire [63:0] o_timestamp_ns;
    wire [7:0] o_quality;
    wire [24:0] o_payload_length;
    logic i_payload_tready = 0;
    wire o_payload_tvalid, o_payload_tlast;
    wire [127:0] o_payload_tdata;
    wire [15:0] o_payload_tkeep;
    wire o_read_complete, o_read_error, o_stream_recovery_required;
    wire o_drop_pulse, o_read_done_pulse;
    wire o_write_quiescent, o_record_quiescent;
    logic i_retire_valid = 0, i_retire_rsp_ready = 0, i_retire_error = 0;
    logic [31:0] i_retire_session = 0, i_retire_generation = 0;
    logic [15:0] i_retire_slot = 0;
    wire o_retire_ready, o_retire_rsp_valid;
    wire [3:0] o_retire_rsp_code;

    wire [3:0] o_axi_awid, o_axi_arid;
    wire [27:0] o_axi_awaddr, o_axi_araddr;
    wire [7:0] o_axi_awlen, o_axi_arlen;
    wire [2:0] o_axi_awsize, o_axi_arsize;
    wire [1:0] o_axi_awburst, o_axi_arburst;
    wire o_axi_awvalid, o_axi_wvalid, o_axi_wlast, o_axi_bready;
    wire o_axi_arvalid, o_axi_rready;
    wire [127:0] o_axi_wdata;
    wire [15:0] o_axi_wstrb;
    logic i_axi_awready = 0, i_axi_wready = 0, i_axi_arready = 0;
    logic [3:0] i_axi_bid = 0, i_axi_rid = 0;
    logic [1:0] i_axi_bresp = 0, i_axi_rresp = 0;
    logic i_axi_bvalid = 0, i_axi_rvalid = 0, i_axi_rlast = 0;
    logic [127:0] i_axi_rdata = 0;

    jpeg_ring_reset_boundary #(
        .CAMERA_COUNT(2), .SLOT_BYTES(32'h01000000),
        .WRITE_RESULT_ENABLE(1), .WRITE_TAG_ENABLE(1), .MASK_ENABLE(0)
    ) dut (
        .i_clk(i_clk), .i_cold_rst_n(i_cold_rst_n), .i_ddr_ready(i_ddr_ready),
        .i_start_valid(i_start_valid), .o_start_ready(o_start_ready),
        .i_capture_id(i_capture_id), .i_width(i_width), .i_height(i_height),
        .i_timestamp_ns(i_timestamp_ns), .i_write_tag(i_write_tag),
        .i_session_id(i_session_id), .i_mode_epoch(i_mode_epoch),
        .i_quality(i_quality), .i_camera_id(i_camera_id),
        .i_jpeg_tdata(i_jpeg_tdata), .i_jpeg_tkeep(i_jpeg_tkeep),
        .i_jpeg_tvalid(i_jpeg_tvalid), .o_jpeg_tready(o_jpeg_tready),
        .i_jpeg_tlast(i_jpeg_tlast), .i_result_valid(i_result_valid),
        .o_result_ready(o_result_ready), .i_result_id(i_result_id),
        .i_result_ok(i_result_ok), .i_result_length(i_result_length),
        .i_result_quality(i_result_quality), .i_result_epoch(i_result_epoch),
        .o_write_result_valid(o_write_result_valid), .i_write_result_ready(i_write_result_ready),
        .o_write_result_ok(o_write_result_ok), .o_write_result_error(o_write_result_error),
        .o_write_result_capture_id(o_write_result_capture_id),
        .o_write_result_session(o_write_result_session), .o_write_result_epoch(o_write_result_epoch),
        .o_write_result_camera(o_write_result_camera), .o_write_result_slot(o_write_result_slot),
        .o_write_result_generation(o_write_result_generation),
        .o_write_result_payload_length(o_write_result_payload_length),
        .o_write_result_tag(o_write_result_tag),
        .o_ready_valid(o_ready_valid), .i_ready_claim(i_ready_claim), .o_capture_id(o_capture_id),
        .o_payload_length(o_payload_length), .o_width(o_width), .o_height(o_height),
        .o_timestamp_ns(o_timestamp_ns), .o_slot_id(o_slot_id), .o_generation(o_generation),
        .o_session_id(o_session_id), .o_mode_epoch(o_mode_epoch), .o_camera_id(o_camera_id),
        .o_quality(o_quality), .o_payload_tdata(o_payload_tdata), .o_payload_tkeep(o_payload_tkeep),
        .o_payload_tvalid(o_payload_tvalid), .i_payload_tready(i_payload_tready),
        .o_payload_tlast(o_payload_tlast),
        .o_read_complete(o_read_complete), .o_read_error(o_read_error),
        .o_stream_recovery_required(o_stream_recovery_required),
        .o_drop_pulse(o_drop_pulse), .o_read_done_pulse(o_read_done_pulse),
        .o_write_quiescent(o_write_quiescent), .o_record_quiescent(o_record_quiescent),
        .i_retire_valid(i_retire_valid), .o_retire_ready(o_retire_ready),
        .i_retire_session(i_retire_session), .i_retire_generation(i_retire_generation),
        .i_retire_slot(i_retire_slot), .i_retire_error(i_retire_error),
        .o_retire_rsp_valid(o_retire_rsp_valid), .i_retire_rsp_ready(i_retire_rsp_ready),
        .o_retire_rsp_code(o_retire_rsp_code),
        .o_axi_awid(o_axi_awid), .o_axi_awaddr(o_axi_awaddr), .o_axi_awlen(o_axi_awlen),
        .o_axi_awsize(o_axi_awsize), .o_axi_awburst(o_axi_awburst), .o_axi_awvalid(o_axi_awvalid),
        .i_axi_awready(i_axi_awready), .o_axi_wdata(o_axi_wdata), .o_axi_wstrb(o_axi_wstrb),
        .o_axi_wlast(o_axi_wlast), .o_axi_wvalid(o_axi_wvalid), .i_axi_wready(i_axi_wready),
        .i_axi_bid(i_axi_bid), .i_axi_bresp(i_axi_bresp), .i_axi_bvalid(i_axi_bvalid),
        .o_axi_bready(o_axi_bready), .o_axi_arid(o_axi_arid), .o_axi_araddr(o_axi_araddr),
        .o_axi_arlen(o_axi_arlen), .o_axi_arsize(o_axi_arsize), .o_axi_arburst(o_axi_arburst),
        .o_axi_arvalid(o_axi_arvalid), .i_axi_arready(i_axi_arready), .i_axi_rid(i_axi_rid),
        .i_axi_rdata(i_axi_rdata), .i_axi_rresp(i_axi_rresp), .i_axi_rlast(i_axi_rlast),
        .i_axi_rvalid(i_axi_rvalid), .o_axi_rready(o_axi_rready),
        .i_req_valid(1'b0), .i_req_op(2'b0), .i_req_camera(1'b0), .i_req_slot(16'b0),
        .i_req_generation(32'b0), .i_req_session(32'b0), .i_rsp_ready(1'b0),
        .i_start_mask(1'b0), .i_mask_allocation_ready(1'b0), .i_start_source_type(3'b0),
        .i_mask_result_valid(1'b0), .i_mask_result_context(160'b0), .i_mask_result_tag(32'b0),
        .i_mask_result_generation(32'b0), .i_mask_result_slot(16'b0), .i_mask_result_ok(1'b0),
        .i_mask_result_error(8'b0), .i_mask_result_width(13'b0), .i_mask_result_height(13'b0),
        .i_mask_result_written_bytes(17'b0), .i_mask_result_terminal_body(48'b0),
        .i_req_mask(1'b0), .i_req_read_lock(1'b0), .i_mask_read_lease_release(1'b0)
    );

    typedef struct packed {
        logic [31:0] capture_id, session, epoch, tag, generation;
        logic [63:0] timestamp;
        logic [15:0] width, height, slot;
        logic [24:0] length;
        logic [7:0] quality;
        logic camera;
        logic [1:0] final_bresp;
    } frame_t;

    typedef enum {FREE, WRITING, READY_RECORD, READING} slot_state_t;
    slot_state_t slot_state [0:5];
    int unsigned generations [0:5];
    int next_slot [0:1];
    frame_t offered_frame, write_frame, read_frame;
    frame_t ready_queue [$];
    bit writer_live, reader_live, published, result_taken, tail_taken, read_tail_taken;
    bit retire_outstanding, good_retire_taken, external_safe;
    logic [3:0] expected_retire_code;
    int cycle, reset_case, trace_fd;
    int starts, acks, claims, retires, data_beats, payload_beats;
    int start_stalls, data_stalls, result_stalls, ack_stalls, ready_stalls, payload_stalls;
    int positive_acks = 0, failed_acks = 0, retired_records = 0;
    bit [5:0] allocated_slots = 0;
    int reused_slots = 0;
    string scenario;

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1)
            $fatal(1, "RING_BLACKBOX_FAIL %s reset=%0d cycle=%0d %s",
                   scenario, reset_case, cycle, message);
    endtask

    function automatic int beat_count(input int length);
        return (length + 15) / 16;
    endfunction

    function automatic logic [15:0] keep_for(input int length, input int beat);
        logic [15:0] keep;
        keep = 0;
        for (int lane = 0; lane < 16; lane++)
            keep[lane] = beat * 16 + lane < length;
        return keep;
    endfunction

    function automatic logic [127:0] mask_data(
        input logic [127:0] data, input logic [15:0] keep
    );
        logic [127:0] masked;
        masked = 0;
        for (int lane = 0; lane < 16; lane++)
            if (keep[lane])
                masked[lane * 8 +: 8] = data[lane * 8 +: 8];
        return masked;
    endfunction

    function automatic logic [7:0] byte_for(input frame_t frame, input int offset);
        return 61 * frame.capture_id + 37 * offset + 13 * (offset / 16)
             + frame.session + frame.quality;
    endfunction

    function automatic logic [127:0] beat_for(input frame_t frame, input int beat);
        logic [127:0] data;
        for (int lane = 0; lane < 16; lane++)
            data[lane * 8 +: 8] = byte_for(frame, beat * 16 + lane);
        return data;
    endfunction

    function automatic frame_t frame_spec(
        input int capture, input logic camera, input int length, input logic [1:0] bresp
    );
        frame_t frame;
        frame = '0;
        frame.capture_id = capture;
        frame.session = 32'h19002000 + capture;
        frame.epoch = 32'h20001000 + capture;
        frame.tag = 32'h71008000 + capture;
        frame.timestamp = 64'h001b12c3ff009800 + capture;
        frame.width = camera ? 16'd1280 : 16'd1920;
        frame.height = camera ? 16'd720 : 16'd1080;
        frame.quality = 8'd70 + (capture % 20);
        frame.length = length;
        frame.camera = camera;
        frame.final_bresp = bresp;
        return frame;
    endfunction

    `include "ring_test_bfm.svh"

    bit hold_ack, hold_ready, hold_payload, hold_retire, read_complete_seen;
    logic [210:0] previous_ack;
    logic [273:0] previous_ready;
    logic [144:0] previous_payload;
    logic [3:0] previous_retire;
    wire [210:0] ack_offer = {
        o_write_result_ok, o_write_result_error, o_write_result_capture_id, o_write_result_session,
        o_write_result_epoch, o_write_result_camera, o_write_result_slot, o_write_result_generation,
        o_write_result_payload_length, o_write_result_tag
    };
    wire [273:0] ready_offer = {
        o_capture_id, o_payload_length, o_width, o_height, o_timestamp_ns, o_slot_id, o_generation,
        o_session_id, o_mode_epoch, o_camera_id, o_quality
    };
    wire [144:0] payload_offer = {o_payload_tdata, o_payload_tkeep, o_payload_tlast};

    task automatic reset_scoreboard;
        cycle = 0;
        {writer_live, reader_live, published, result_taken, tail_taken, read_tail_taken} = '0;
        {retire_outstanding, good_retire_taken, external_safe, read_complete_seen} = '0;
        {hold_ack, hold_ready, hold_payload, hold_retire} = '0;
        starts = 0;
        acks = 0;
        claims = 0;
        retires = 0;
        data_beats = 0;
        payload_beats = 0;
        start_stalls = 0;
        data_stalls = 0;
        result_stalls = 0;
        ack_stalls = 0;
        ready_stalls = 0;
        payload_stalls = 0;
        ready_queue.delete();
        next_slot[0] = 0;
        next_slot[1] = 0;
        for (int slot = 0; slot < 6; slot++) begin
            slot_state[slot] = FREE;
            generations[slot] = 0;
        end
        reset_axi();
    endtask

    task automatic accept_start;
        int camera_base, chosen, index;
        check(!writer_live, "START took ownership before previous writer ACK was accepted");
        check({i_capture_id, i_session_id, i_mode_epoch, i_write_tag, i_timestamp_ns,
               i_width, i_height, i_quality, i_camera_id} ===
              {offered_frame.capture_id, offered_frame.session, offered_frame.epoch,
               offered_frame.tag, offered_frame.timestamp, offered_frame.width,
               offered_frame.height, offered_frame.quality, offered_frame.camera}, "fixture START");
        camera_base = offered_frame.camera ? 3 : 0;
        chosen = -1;
        for (int offset = 0; offset < 3; offset++) begin
            index = camera_base + (next_slot[offered_frame.camera] + offset) % 3;
            if (chosen == -1 && slot_state[index] == FREE)
                chosen = index;
        end
        check(chosen >= 0, "START transferred without a free slot of its camera");
        write_frame = offered_frame;
        write_frame.slot = chosen;
        generations[chosen]++;
        if (generations[chosen] == 0)
            generations[chosen] = 1;
        write_frame.generation = generations[chosen];
        next_slot[offered_frame.camera] = (chosen - camera_base + 1) % 3;
        slot_state[chosen] = WRITING;
        allocated_slots[chosen] = 1;
        if (write_frame.generation > 1)
            reused_slots++;
        writer_live = 1;
        starts++;
        data_beats = 0;
        {published, result_taken, tail_taken} = '0;
        new_axi_write();
        $fdisplay(trace_fd, "%0d:%0d START %0d cam=%0d slot=%0d gen=%0d",
                  reset_case, cycle, i_capture_id, i_camera_id, chosen, generations[chosen]);
    endtask

    task automatic sample_data_result;
        if (i_jpeg_tvalid && o_jpeg_tready) begin
            check(writer_live && !tail_taken, "DATA accepted outside its START and LAST");
            check(i_jpeg_tdata === beat_for(write_frame, data_beats) &&
                  i_jpeg_tkeep === keep_for(write_frame.length, data_beats) &&
                  i_jpeg_tlast === (data_beats == beat_count(write_frame.length) - 1),
                  "fixture DATA mismatch");
            $fdisplay(trace_fd, "%0d:%0d DATA %h %h %b", reset_case, cycle,
                      i_jpeg_tdata, i_jpeg_tkeep, i_jpeg_tlast);
            data_beats++;
            tail_taken = i_jpeg_tlast;
        end
        if (i_result_valid && o_result_ready) begin
            check(writer_live && tail_taken && !result_taken, "RESULT outside the accepted tail");
            check({i_result_id, i_result_ok, i_result_length, i_result_quality, i_result_epoch} ===
                  {write_frame.capture_id, 1'b1, write_frame.length, write_frame.quality,
                   write_frame.epoch}, "fixture RESULT mismatch");
            result_taken = 1;
            $fdisplay(trace_fd, "%0d:%0d RESULT %0d bytes=%0d epoch=%h quality=%0d",
                      reset_case, cycle, i_result_id, i_result_length, i_result_epoch, i_result_quality);
        end
    endtask

    task automatic sample_writer_ack;
        bit terminal, good;
        terminal = writer_live && tail_taken && result_taken && writes_complete();
        good = terminal && !write_b_error;
        if (good && !published) begin
            ready_queue.push_back(write_frame);
            slot_state[write_frame.slot] = READY_RECORD;
            published = 1;
        end
        if (o_write_result_valid) begin
            check(terminal, "write ACK appeared before accepted DATA/RESULT and AXI B");
            check(ack_offer ===
                  {good, (good ? 8'd0 : 8'd3), write_frame.capture_id, write_frame.session,
                   write_frame.epoch, write_frame.camera, write_frame.slot, write_frame.generation,
                   (good ? write_frame.length : 25'd0), write_frame.tag}, "writer ACK identity or result");
            if (i_write_result_ready) begin
                $fdisplay(trace_fd, "%0d:%0d ACK %h", reset_case, cycle, ack_offer);
                if (good)
                    positive_acks++;
                else begin
                    failed_acks++;
                    slot_state[write_frame.slot] = FREE;
                end
                writer_live = 0;
                acks++;
            end
        end
    endtask

    task automatic sample_ready;
        frame_t head;
        if (o_ready_valid) begin
            check(ready_queue.size() != 0, "READY has no committed successful record");
            head = ready_queue[0];
            check(ready_offer ===
                  {head.capture_id, head.length, head.width, head.height, head.timestamp, head.slot,
                   head.generation, head.session, head.epoch, head.camera, head.quality},
                  "READY metadata or oldest-record order");
            if (i_ready_claim) begin
                check(!reader_live && slot_state[head.slot] == READY_RECORD,
                      "READY claim reused an owned reader");
                $fdisplay(trace_fd, "%0d:%0d READY %h", reset_case, cycle, ready_offer);
                read_frame = ready_queue.pop_front();
                slot_state[head.slot] = READING;
                reader_live = 1;
                {read_tail_taken, good_retire_taken, external_safe, read_complete_seen} = '0;
                payload_beats = 0;
                claims++;
                new_axi_read();
            end
        end
    endtask

    task automatic sample_payload;
        logic [15:0] keep;
        if (o_payload_tvalid)
            check(reader_live && !read_tail_taken, "payload offered without a live unread tail");
        if (o_payload_tvalid && i_payload_tready) begin
            keep = keep_for(read_frame.length, payload_beats);
            check(o_payload_tkeep === keep &&
                  o_payload_tlast === (payload_beats == beat_count(read_frame.length) - 1),
                  "read KEEP or LAST mismatch");
            check(mask_data(o_payload_tdata, keep) ===
                  mask_data(beat_for(read_frame, payload_beats), keep),
                  $sformatf("read byte mismatch at word %0d", payload_beats));
            check(mask_data(o_payload_tdata, keep) ===
                  mask_data(ddr_word(SLOT_BASE[read_frame.slot] + payload_beats * 16), keep),
                  "read payload differs from written DDR");
            $fdisplay(trace_fd, "%0d:%0d PAYLOAD %h %h %b", reset_case, cycle,
                      mask_data(o_payload_tdata, keep), keep, o_payload_tlast);
            payload_beats++;
            read_tail_taken = o_payload_tlast;
        end
        check(!reader_live || payload_beats <= r_words, "payload outran accepted R beats");
    endtask

    task automatic sample_retire;
        if (i_retire_valid && o_retire_ready) begin
            check(reader_live && !retire_outstanding, "fixture RETIRE has no unique claimed record");
            case (expected_retire_code)
                RETIRE_OK: begin
                    check(external_safe && read_tail_taken && reads_drained(),
                          "fixture RETIRE preceded modeled host SAFE or read drain");
                    check(i_retire_generation == read_frame.generation, "fixture matching generation");
                    good_retire_taken = 1;
                end
                RETIRE_STALE:
                    check(i_retire_generation != read_frame.generation, "fixture STALE generation");
                RETIRE_BUSY:
                    check(!read_tail_taken, "fixture BUSY after accepted payload LAST");
                default: check(1'b0, "fixture unexpected RETIRE status");
            endcase
            check(i_retire_slot == read_frame.slot && i_retire_session == read_frame.session &&
                  !i_retire_error, "fixture RETIRE tuple");
            retire_outstanding = 1;
            $fdisplay(trace_fd, "%0d:%0d RETIRE slot=%0d session=%h gen=%0d safe=%b",
                      reset_case, cycle, i_retire_slot, i_retire_session, i_retire_generation,
                      external_safe);
        end
        if (o_retire_rsp_valid) begin
            check(retire_outstanding && o_retire_rsp_code === expected_retire_code,
                  $sformatf("RETIRE response code=%0d expected=%0d",
                            o_retire_rsp_code, expected_retire_code));
            if (i_retire_rsp_ready) begin
                $fdisplay(trace_fd, "%0d:%0d RETIRE_RSP %0d", reset_case, cycle, o_retire_rsp_code);
                retires++;
                retire_outstanding = 0;
                if (good_retire_taken) begin
                    slot_state[read_frame.slot] = FREE;
                    reader_live = 0;
                    retired_records++;
                end
            end
        end
    endtask

    task automatic check_holding;
        if (hold_ack)
            check(o_write_result_valid && ack_offer === previous_ack, "write ACK changed under stall");
        if (hold_ready)
            check(o_ready_valid && ready_offer === previous_ready, "READY changed under stall");
        if (hold_payload)
            check(o_payload_tvalid && payload_offer === previous_payload, "payload changed under stall");
        if (hold_retire)
            check(o_retire_rsp_valid && o_retire_rsp_code === previous_retire, "RETIRE response changed under stall");
        hold_ack = o_write_result_valid && !i_write_result_ready;
        hold_ready = o_ready_valid && !i_ready_claim;
        hold_payload = o_payload_tvalid && !i_payload_tready;
        hold_retire = o_retire_rsp_valid && !i_retire_rsp_ready;
        previous_ack = ack_offer;
        previous_ready = ready_offer;
        previous_payload = payload_offer;
        previous_retire = o_retire_rsp_code;
        start_stalls += i_start_valid && !o_start_ready;
        data_stalls += i_jpeg_tvalid && !o_jpeg_tready;
        result_stalls += i_result_valid && !o_result_ready;
        ack_stalls += hold_ack;
        ready_stalls += hold_ready;
        payload_stalls += hold_payload;
    endtask

    always @(posedge i_clk or negedge i_cold_rst_n) begin : score_pins
        bit start_taken, old_writer;
        if (!i_cold_rst_n) begin
            reset_scoreboard();
        end else begin
            cycle++;
            check(cycle <= 6000, "6000-edge simulation watchdog");
            $fdisplay(trace_fd, "%0d:%0d SAMPLE start_ready=%b write_quiet=%b record_quiet=%b ready=%b",
                      reset_case, cycle, o_start_ready, o_write_quiescent, o_record_quiescent, o_ready_valid);
            if (cycle < 4)
                check(o_start_ready === 1'b0, "START READY before R4 sample");
            if (cycle >= 4) begin
                check(!$isunknown({o_start_ready, o_write_result_valid,
                                  o_ready_valid, o_payload_tvalid, o_retire_rsp_valid,
                                  o_write_quiescent, o_record_quiescent}), "unknown handshake or quiet flag");
                if (i_start_valid || writer_live)
                    check(o_write_quiescent === 1'b0, "write quiet with pending START, data, AXI or ACK");
                if (o_ready_valid || (!writer_live && ready_queue.size() != 0) ||
                    reader_live || retire_outstanding)
                    check(o_record_quiescent === 1'b0, "record quiet with pending record, read or RETIRE");
            end
            if (o_drop_pulse)
                $fdisplay(trace_fd, "%0d:%0d DROP_PULSE", reset_case, cycle);
            if (o_read_done_pulse)
                $fdisplay(trace_fd, "%0d:%0d READ_DONE_PULSE", reset_case, cycle);
            if (reader_live && !read_tail_taken)
                check(o_read_complete === 1'b0, "read-complete before accepted payload LAST");
            if (reader_live && read_tail_taken && !good_retire_taken) begin
                if (read_complete_seen)
                    check(o_read_complete === 1'b1, "read-complete dropped before matching retirement");
                if (o_read_complete && !read_complete_seen) begin
                    check(!o_read_error && !o_stream_recovery_required, "unexpected read fault or recovery flag");
                    $fdisplay(trace_fd, "%0d:%0d READ_COMPLETE", reset_case, cycle);
                end
                read_complete_seen |= o_read_complete;
            end
            check_holding();
            start_taken = i_start_valid && o_start_ready;
            old_writer = writer_live;
            if (start_taken && !old_writer)
                accept_start();
            sample_data_result();
            sample_axi_holds();
            sample_axi_write();
            sample_writer_ack();
            if (start_taken && old_writer)
                accept_start();
            sample_ready();
            sample_axi_read();
            sample_payload();
            sample_retire();
        end
    end

    // Drive after the falling edge and wait for the pin scoreboard to finish
    // each rising edge. The scoreboard samples before DUT NBA updates.
    task automatic drive;
        @(negedge i_clk);
        #1ps;
    endtask

    task automatic sample;
        @(posedge i_clk);
        #1ps;
    endtask

    task automatic present_start(input frame_t frame);
        offered_frame = frame;
        i_capture_id = frame.capture_id;
        i_session_id = frame.session;
        i_mode_epoch = frame.epoch;
        i_write_tag = frame.tag;
        i_timestamp_ns = frame.timestamp;
        i_width = frame.width;
        i_height = frame.height;
        i_quality = frame.quality;
        i_camera_id = frame.camera;
        i_start_valid = 1;
    endtask

    task automatic start_frame(input frame_t frame);
        int before_starts;
        before_starts = starts;
        drive();
        present_start(frame);
        while (starts == before_starts)
            sample();
        drive();
        i_start_valid = 0;
    endtask

    task automatic send_data(input frame_t frame);
        for (int beat = 0; beat < beat_count(frame.length); beat++) begin
            i_jpeg_tdata = beat_for(frame, beat);
            i_jpeg_tkeep = keep_for(frame.length, beat);
            i_jpeg_tlast = beat == beat_count(frame.length) - 1;
            i_jpeg_tvalid = 1;
            while (data_beats == beat)
                sample();
            drive();
        end
        i_jpeg_tvalid = 0;
    endtask

    task automatic present_result(input frame_t frame);
        i_result_id = frame.capture_id;
        i_result_ok = 1;
        i_result_length = frame.length;
        i_result_quality = frame.quality;
        i_result_epoch = frame.epoch;
        i_result_valid = 1;
    endtask

    task automatic delayed_final_b(input frame_t frame, input int hold_cycles);
        final_b_open = 0;
        send_data(frame);
        present_result(frame);
        while (!result_taken)
            sample();
        drive();
        i_result_valid = 0;
        while (!final_write_waiting())
            sample();
        repeat (hold_cycles) begin
            sample();
            check(final_write_waiting() && !i_axi_bvalid && !o_write_result_valid,
                  "terminal crossed withheld final B");
            check(!o_ready_valid || o_capture_id != frame.capture_id, "READY before final B");
        end
    endtask

    task automatic same_edge_result_b(input frame_t frame);
        final_b_open = 0;
        send_data(frame);
        while (!final_write_waiting())
            sample();
        final_b_open = 1;
        drive();
        present_result(frame);
        sample();
        check(result_taken && b_taken && writes_complete(),
              "directed RESULT and final B did not transfer on the same edge");
        $display("RING_BLACKBOX_CASE RESULT and final B accepted together at cycle %0d", cycle);
        drive();
        i_result_valid = 0;
    endtask

    task automatic wait_ack_offer;
        final_b_open = 1;
        while (o_write_result_valid !== 1'b1)
            sample();
    endtask

    task automatic take_ack;
        int before_acks;
        before_acks = acks;
        drive();
        i_write_result_ready = 1;
        while (acks == before_acks)
            sample();
        drive();
        i_write_result_ready = 0;
    endtask

    task automatic take_ack_with_held_start(input frame_t following);
        int before_starts, before_acks;
        before_starts = starts;
        before_acks = acks;
        drive();
        present_start(following);
        repeat (6) begin
            sample();
            check(starts == before_starts && hold_ack && !o_start_ready && !o_write_quiescent,
                  "START or write quiet while old ACK was held");
        end
        drive();
        i_write_result_ready = 1;
        while (acks == before_acks)
            sample();
        drive();
        i_write_result_ready = 0;
        if (starts == before_starts) begin
            while (starts == before_starts)
                sample();
            drive();
        end
        i_start_valid = 0;
    endtask

    task automatic complete_write(input frame_t frame);
        start_frame(frame);
        delayed_final_b(frame, 2);
        wait_ack_offer();
        take_ack();
    endtask

    task automatic wait_writer_only_quiet;
        while (o_write_quiescent !== 1'b1 || o_ready_valid !== 1'b1)
            sample();
        repeat (3) begin
            sample();
            check(o_write_quiescent && !o_record_quiescent && o_ready_valid,
                  "writer and record quiet did not distinguish a pending READY record");
        end
    endtask

    task automatic claim_frame(input frame_t frame);
        int before_claims;
        before_claims = claims;
        while (o_ready_valid !== 1'b1)
            sample();
        check(o_capture_id === frame.capture_id, "driver expected a different oldest READY");
        drive();
        i_ready_claim = 1;
        while (claims == before_claims)
            sample();
        drive();
        i_ready_claim = 0;
    endtask

    task automatic retire_case(input logic [3:0] code);
        int before_retires;
        before_retires = retires;
        drive();
        expected_retire_code = code;
        i_retire_session = read_frame.session;
        i_retire_slot = read_frame.slot;
        i_retire_generation = read_frame.generation + (code == RETIRE_STALE);
        i_retire_valid = 1;
        while (!retire_outstanding)
            sample();
        drive();
        i_retire_valid = 0;
        while (o_retire_rsp_valid !== 1'b1)
            sample();
        repeat (4) begin
            sample();
            check(hold_retire && !o_record_quiescent, "held retirement response lost ownership");
        end
        drive();
        i_retire_rsp_ready = 1;
        while (retires == before_retires)
            sample();
        drive();
        i_retire_rsp_ready = 0;
    endtask

    task automatic read_and_retire(input frame_t frame, input bit check_bad_retire);
        claim_frame(frame);
        if (!writer_live)
            check(o_write_quiescent && !o_record_quiescent, "writer quiet while reader owns a record");
        if (check_bad_retire)
            retire_case(RETIRE_BUSY);
        if (beat_count(frame.length) > 1) begin
            drive();
            i_payload_tready = 1;
            while (payload_beats < beat_count(frame.length) - 1)
                sample();
            drive();
            i_payload_tready = 0;
        end
        while (o_payload_tvalid !== 1'b1)
            sample();
        repeat (6) begin
            sample();
            check(hold_payload && o_payload_tlast && !o_read_complete,
                  "read tail was not held before read-complete");
        end
        drive();
        i_payload_tready = 1;
        while (!read_tail_taken)
            sample();
        drive();
        i_payload_tready = 0;
        while (o_read_complete !== 1'b1 || !reads_drained())
            sample();
        // External SAFE model: downstream accepted and checked the entire
        // payload, then completes after a finite independent transport delay.
        repeat (3)
            sample();
        external_safe = 1;
        $fdisplay(trace_fd, "%0d:%0d MODELED_HOST_SAFE %0d", reset_case, cycle, frame.capture_id);
        if (check_bad_retire)
            retire_case(RETIRE_STALE);
        retire_case(RETIRE_OK);
    endtask

    task automatic wait_empty;
        while (o_write_quiescent !== 1'b1 || o_record_quiescent !== 1'b1)
            sample();
        repeat (3) begin
            sample();
            check(!writer_live && !reader_live && ready_queue.size() == 0 &&
                  o_write_quiescent && o_record_quiescent && !o_ready_valid,
                  "both quiet flags without an empty ring");
        end
    endtask

    task automatic verify_r4_start;
        repeat (3) begin
            sample();
            check(starts == 0, "held first START transferred before R4");
        end
        sample();
        check(cycle == 4 && starts == 1, "held first START did not transfer at R4");
        $display("RING_BLACKBOX_CASE reset=%0d first START accepted at R4", reset_case);
        drive();
        i_start_valid = 0;
    endtask

    task automatic restart(input frame_t first, input bit stop_high);
        check(aw_count == b_count && ar_count == r_burst && !writer_live && !reader_live,
              "fixture coordinated reset with outstanding AXI or claimed data");
        if (stop_high)
            @(posedge i_clk);
        else
            @(negedge i_clk);
        #173ps;
        clock_running = 0;
        #881ps;
        reset_case++;
        i_cold_rst_n = 0;
        #23.677;
        present_start(first);
        if (stop_high) begin
            clock_running = 1;
            @(posedge i_clk);
            #1.327;
            check(starts == 0 && o_start_ready === 1'b0, "START during asserted cold reset");
            i_cold_rst_n = 1;
        end else begin
            i_cold_rst_n = 1;
            #11.593;
            check(starts == 0 && cycle == 0, "stopped DFI consumed a held START");
            clock_running = 1;
        end
        verify_r4_start();
    endtask

    initial begin : exercise_contract
        frame_t first, other_eye, failed, recovered, reused, eye_one_second, eye_one_third;
        frame_t discarded, after_stop_low, after_stop_high;
        trace_fd = $fopen("events.trace", "w");
        check(trace_fd != 0, "cannot open pin trace");
        reset_case = 0;
        first = frame_spec(101, 0, FIRST_LENGTH, 0);
        other_eye = frame_spec(201, 1, 39, 0);
        failed = frame_spec(102, 0, 55, 2'b10);
        recovered = frame_spec(103, 0, 29, 0);
        reused = frame_spec(104, 0, 25, 0);
        eye_one_second = frame_spec(202, 1, 35, 0);
        eye_one_third = frame_spec(203, 1, 23, 0);
        discarded = frame_spec(204, 1, 42, 0);
        after_stop_low = frame_spec(301, 1, 31, 0);
        after_stop_high = frame_spec(302, 0, 34, 0);

        scenario = "cold first frame and delayed write terminal";
        #503ps;
        i_cold_rst_n = 0;
        clock_running = 1;
        #1us;
        drive();
        present_start(first);
        aw_pause = 4;
        w_pause = 13;
        ar_pause = 4;
        #1.327;
        i_cold_rst_n = 1;
        verify_r4_start();
        delayed_final_b(first, 9);
        check(aw_count >= 2 && aw_stalls >= 4 && w_stalls >= 13,
              "first frame missed multiple bursts and finite AW/W stalls");
        wait_ack_offer();
        take_ack_with_held_start(other_eye);

        scenario = "retire one eye while other eye owes B";
        delayed_final_b(other_eye, 4);
        read_and_retire(first, 1);
        check(final_write_waiting() && !o_write_quiescent, "independent retirement consumed other writer debt");
        wait_ack_offer();
        take_ack();
        wait_writer_only_quiet();
        read_and_retire(other_eye, 0);
        wait_empty();
        $display("RING_BLACKBOX_CASE burst/stream stall samples AW=%0d W=%0d AR=%0d R=%0d START=%0d DATA=%0d RESULT=%0d ACK=%0d READY=%0d PAYLOAD=%0d",
                 aw_stalls, w_stalls, ar_stalls, r_stalls, start_stalls, data_stalls,
                 result_stalls, ack_stalls, ready_stalls, payload_stalls);

        scenario = "failing last B and consecutive legal recovery";
        complete_write(failed);
        check(failed_acks == 1, "missing failed write terminal");
        wait_empty();
        start_frame(recovered);
        same_edge_result_b(recovered);
        wait_ack_offer();
        take_ack();
        complete_write(reused);
        read_and_retire(recovered, 0);
        read_and_retire(reused, 0);
        wait_empty();

        scenario = "two eyes rotate slots and generation";
        complete_write(eye_one_second);
        complete_write(eye_one_third);
        read_and_retire(eye_one_second, 0);
        read_and_retire(eye_one_third, 0);
        complete_write(discarded);
        wait_writer_only_quiet();
        check(o_capture_id == discarded.capture_id && ready_stalls > 0,
              "coordinated reset fixture has no held READY to discard");

        scenario = "stop low, release while stopped, new first transaction";
        restart(after_stop_low, 0);
        delayed_final_b(after_stop_low, 3);
        wait_ack_offer();
        take_ack();
        read_and_retire(after_stop_low, 0);
        wait_empty();

        scenario = "stop high, resume under reset, new first transaction";
        restart(after_stop_high, 1);
        delayed_final_b(after_stop_high, 3);
        wait_ack_offer();
        take_ack();
        read_and_retire(after_stop_high, 0);
        wait_empty();
        check(positive_acks == 9 && failed_acks == 1 && retired_records == 8 &&
              allocated_slots == 6'h3f && reused_slots == 2,
              "fixture terminal, six-slot or generation coverage");
        $display("RING_BLACKBOX_PASS good_ack=%0d failed_ack=%0d retired=%0d slots=%h reused=%0d reset_cases=%0d",
                 positive_acks, failed_acks, retired_records, allocated_slots, reused_slots, reset_case + 1);
        $fclose(trace_fd);
        $finish;
    end

    always begin
        #3.751;
        if (clock_running)
            i_clk = !i_clk;
    end

    initial begin
        #75us;
        check(1'b0, "75 us simulation watchdog");
    end
endmodule
