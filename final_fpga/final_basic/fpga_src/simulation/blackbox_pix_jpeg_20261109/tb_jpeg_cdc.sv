`timescale 1ns/1ps

module tb_jpeg_cdc;
    localparam integer NORMAL = 0, NEGATIVE = 1, BAD_ID = 2, BAD_LENGTH = 3, BAD_COHORT = 4,
                       BAD_FLIT1 = 5, BAD_FLIT7 = 6;
    localparam integer COMPLETE = 0, CUT_CONTEXT = 1, CUT_START = 2, CUT_DATA = 3,
                       CUT_EXT = 4, CUT_FENCE = 5;
    typedef struct packed {
        logic [31:0] id, session_id, epoch, tag;
        logic [15:0] width, height;
        logic [63:0] stamp;
        logic camera, mask;
        logic [7:0] quality, format_id;
        logic [2:0] source_type;
    } start_t;
    typedef struct packed {
        logic ok;
        logic [31:0] id, epoch;
        logic [24:0] length;
        logic [7:0] error_id, quality;
    } result_t;
    typedef struct packed {
        logic [127:0] data;
        logic [15:0] keep;
        logic last;
    } beat_t;

    logic src_clk = 0, sink_clk = 0, src_clock_on = 1, sink_clock_on = 1;
    logic src_reset_n = 1, sink_reset_n = 1;
    wire src_reset_done, sink_reset_done;
    start_t start_in = '0;
    wire start_t start_out;
    result_t result_in = '0;
    wire result_t result_out;
    beat_t beat_in = '0;
    wire beat_t beat_out;
    logic start_in_valid = 0, jpeg_in_valid = 0, result_in_valid = 0, prefix_in_valid = 0;
    wire start_in_ready, jpeg_in_ready, result_in_ready, prefix_in_ready;
    wire start_out_valid, jpeg_out_valid, result_out_valid;
    logic [2047:0] prefix_in = 0;
    logic stream_valid = 0;
    logic [127:0] stream_data = 0;
    wire stream_ready, stream_start, src_protocol_fault, sink_protocol_fault;
    wire [16383:0] ext_out;
    wire ext_out_valid, ext_shape_valid;
    logic ext_out_ready = 0, result_out_ready = 0;
    logic ext_read = 0;
    logic [8:0] ext_index = 0;
    wire [39:0] ext_read_data;
    logic fence_request = 0, source_idle = 0, sink_quiet = 0;
    logic [31:0] fence_session = 0;
    wire fence_proven, src_fence_fault, sink_fence_fault;

    integer start_wait = 0, last_wait = 0;
    logic hold_start = 0;
    wire start_out_ready = !hold_start && start_wait >= 3;
    wire jpeg_out_ready = beat_out.last !== 1'b1 || last_wait >= 3;

    ordered_frame_cdc #(
        .CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1), .RECORD_EXTENSION_ENABLE(1),
        .RECORD_EXTENSION_WIDTH(16384), .BORROW_EXTENSION(1), .MASK_CONTEXT_ENABLE(0),
        .EXTENSION_RAM_ENABLE(1), .STREAM_EXTENSION(1)
    ) dut (
        .i_source_clk(src_clk), .i_source_rst_n(src_reset_n),
        .i_sink_clk(sink_clk), .i_sink_rst_n(sink_reset_n),
        .o_source_reset_done(src_reset_done), .o_sink_reset_done(sink_reset_done),
        .i_start_valid(start_in_valid), .o_start_ready(start_in_ready),
        .i_capture_id(start_in.id), .i_session_id(start_in.session_id), .i_mode_epoch(start_in.epoch),
        .i_write_tag(start_in.tag), .i_width(start_in.width), .i_height(start_in.height),
        .i_timestamp_ns(start_in.stamp), .i_camera_id(start_in.camera), .i_start_mask(start_in.mask),
        .i_quality(start_in.quality), .i_format(start_in.format_id), .i_start_source_type(start_in.source_type),
        .o_start_valid(start_out_valid), .i_start_ready(start_out_ready),
        .o_capture_id(start_out.id), .o_session_id(start_out.session_id), .o_mode_epoch(start_out.epoch),
        .o_write_tag(start_out.tag), .o_width(start_out.width), .o_height(start_out.height),
        .o_timestamp_ns(start_out.stamp), .o_camera_id(start_out.camera), .o_start_mask(start_out.mask),
        .o_quality(start_out.quality), .o_format(start_out.format_id), .o_start_source_type(start_out.source_type),
        .i_jpeg_tdata(beat_in.data), .i_jpeg_tkeep(beat_in.keep), .i_jpeg_tlast(beat_in.last),
        .i_jpeg_tvalid(jpeg_in_valid), .o_jpeg_tready(jpeg_in_ready),
        .o_jpeg_tdata(beat_out.data), .o_jpeg_tkeep(beat_out.keep), .o_jpeg_tlast(beat_out.last),
        .o_jpeg_tvalid(jpeg_out_valid), .i_jpeg_tready(jpeg_out_ready),
        .i_result_valid(result_in_valid), .o_result_ready(result_in_ready), .i_result_ok(result_in.ok),
        .i_result_id(result_in.id), .i_result_epoch(result_in.epoch), .i_result_length(result_in.length),
        .i_result_error(result_in.error_id), .i_result_quality(result_in.quality),
        .o_result_valid(result_out_valid), .i_result_ready(result_out_ready), .o_result_ok(result_out.ok),
        .o_result_id(result_out.id), .o_result_epoch(result_out.epoch), .o_result_length(result_out.length),
        .o_result_error(result_out.error_id), .o_result_quality(result_out.quality),
        .i_record_extension(prefix_in), .i_record_extension_valid(prefix_in_valid),
        .o_record_extension_ready(prefix_in_ready), .i_extension_stream_data(stream_data),
        .i_extension_stream_valid(stream_valid), .o_extension_stream_ready(stream_ready),
        .o_extension_stream_start(stream_start), .o_source_protocol_fault(src_protocol_fault),
        .o_record_extension(ext_out), .o_record_extension_valid(ext_out_valid),
        .i_record_extension_ready(ext_out_ready), .o_extension_shape_valid(ext_shape_valid),
        .i_extension_read_enable(ext_read), .i_extension_read_index(ext_index),
        .o_extension_read_data(ext_read_data), .o_protocol_fault(sink_protocol_fault),
        .i_fence_request(fence_request), .i_source_fence_idle(source_idle),
        .i_source_fence_session(fence_session), .i_sink_fence_session(fence_session),
        .i_raw_enqueued(64'h0000000100000142), .i_raw_consumed(64'h0000000100000142),
        .i_raw_consume_fire(1'b0), .i_sink_fence_quiet(sink_quiet),
        .o_source_fence_proven(fence_proven), .o_source_fence_fault(src_fence_fault),
        .o_sink_fence_fault(sink_fence_fault)
    );

    always #5 if (src_clock_on) src_clk = ~src_clk;
    initial begin
        #2;
        forever #7 if (sink_clock_on) sink_clk = ~sink_clk;
    end

    start_t expected_start;
    result_t offered_result, expected_result;
    beat_t expected_beats [0:2];
    logic [16383:0] expected_extension;
    logic [2047:0] offered_prefix;
    integer want_beats = 0;
    integer src_starts = 0, src_bytes = 0, src_beats = 0, src_results = 0;
    integer src_prefixes = 0, src_flits = 0;
    integer sink_starts = 0, sink_bytes = 0, sink_beats = 0, sink_exts = 0, sink_results = 0;
    integer ext_wait = 0, result_wait = 0;
    integer total_starts = 0, total_bytes = 0, total_exts = 0, total_results = 0;
    integer total_ram_reads = 0, total_proofs = 0;
    logic seen_stream_start = 0, configured = 0, monitors_on = 0, malformed = 0;
    logic source_early_reject = 0;
    logic held_start = 0, held_jpeg = 0, held_ext = 0, held_result = 0;
    beat_t held_beat;
    string case_name;

    function automatic start_t descriptor(input integer variant);
        start_t s;
        s.id = variant == 0 ? 32'hffffffff : variant - 1;
        s.session_id = 32'h921dc002 + 32'h1021 * variant;
        s.epoch = 32'h31415982 + variant;
        s.tag = 32'ha5c0ff09 ^ (32'h10231003 * variant);
        s.width = 16'd32 + 16 * variant;
        s.height = 16'd16 + 8 * variant;
        s.stamp = 64'hfeedbcfa05941230 + 64'h100010100 * variant;
        s.camera = variant % 2 != 0;
        s.mask = 0;
        s.quality = 75 - 4 * variant;
        s.format_id = 1;
        s.source_type = 0;
        return s;
    endfunction

    function automatic logic [16383:0] extension_wire(input start_t s);
        logic [16383:0] bits;
        bits = '0;
        bits[31:0] = 32'h32585443;
        bits[47:32] = 16'd1;
        bits[48] = 1;
        bits[95:64] = s.session_id;
        bits[127:96] = s.epoch;
        bits[159:128] = s.id;
        bits[167:160] = {7'd0, s.camera};
        bits[1024 +: 128] = 128'h010d00a9000000000000050134565053;
        return bits;
    endfunction

    function automatic beat_t payload_wire(input integer variant, index, mode);
        beat_t beat;
        for (integer byte_idx = 0; byte_idx < 16; byte_idx++)
            beat.data[byte_idx * 8 +: 8] = 8'h93 ^ (variant * 17) ^ (index * 61) ^ (byte_idx * 13);
        beat.last = index == 2 && mode != NEGATIVE;
        beat.keep = beat.last ? 16'h001f : 16'hffff;
        return beat;
    endfunction

    function automatic logic [39:0] ram_word(input integer idx);
        logic [39:0] word;
        word = 0;
        for (integer b = 0; b < 5; b++) begin
            if (5 * idx + b < 2048) word[b * 8 +: 8] = expected_extension[(5 * idx + b) * 8 +: 8];
        end
        return word;
    endfunction

    function automatic logic payload_matches(input beat_t actual, expected);
        if (actual.keep !== expected.keep || actual.last !== expected.last) return 0;
        for (integer b = 0; b < 16; b++) begin
            if (expected.keep[b] && actual.data[b * 8 +: 8] !== expected.data[b * 8 +: 8]) return 0;
        end
        return 1;
    endfunction
    always @(posedge src_clk) begin
        if (monitors_on && src_reset_n && sink_reset_n && src_reset_done) begin
            if (src_fence_fault !== 1'b0 || (!source_early_reject && src_protocol_fault !== 1'b0))
                $fatal(1, "JPEG_FAIL unexpected source protocol/fence fault");
            if (fence_request && sink_results == 0 && fence_proven !== 1'b0)
                $fatal(1, "JPEG_FAIL fence proven with EXT or RESULT still pending");
            if (start_in_valid && start_in_ready) begin
                if (!configured || src_starts != 0 || start_in !== expected_start)
                    $fatal(1, "JPEG_FIXTURE unexpected source START handshake");
                src_starts++;
                $display("JPEG_SRC_START id=%h eye=%b session=%h epoch=%h tag=%h", start_in.id,
                         start_in.camera, start_in.session_id, start_in.epoch, start_in.tag);
            end
            if (jpeg_in_valid && jpeg_in_ready) begin
                if (src_starts != 1 || src_beats >= want_beats || beat_in !== expected_beats[src_beats])
                    $fatal(1, "JPEG_FIXTURE unexpected source JPEG handshake");
                src_bytes += $countones(beat_in.keep);
                src_beats++;
            end
            if (stream_start) seen_stream_start = 1;
            if (stream_valid && stream_ready) begin
                if (!seen_stream_start || src_flits >= 128 || stream_data !== expected_extension[src_flits * 128 +: 128])
                    $fatal(1, "JPEG_FIXTURE unexpected source EXT flit handshake index=%0d", src_flits);
                src_flits++;
            end
            if (prefix_in_valid && prefix_in_ready) begin
                if (src_prefixes != 0 || prefix_in !== offered_prefix)
                    $fatal(1, "JPEG_FIXTURE unexpected source EXT prefix handshake");
                src_prefixes++;
            end
            if (result_in_valid && result_in_ready) begin
                if (src_results != 0 || src_flits != 128 || result_in !== offered_result)
                    $fatal(1, "JPEG_FAIL source RESULT handshake before complete extension or with wrong descriptor");
                src_results++;
                $display("JPEG_SRC_RESULT id=%h ok=%b length=%0d bytes=%0d flits=%0d", result_in.id,
                         result_in.ok, result_in.length, src_bytes, src_flits);
            end
        end
    end

    always @(posedge sink_clk) begin
        if (monitors_on && src_reset_n && sink_reset_n && sink_reset_done) begin
            if (sink_fence_fault !== 1'b0 || (!malformed && sink_protocol_fault !== 1'b0))
                $fatal(1, "JPEG_FAIL unexpected sink protocol/fence fault");
            if (malformed && ((!source_early_reject && sink_protocol_fault && src_flits != 128) ||
                              {ext_out_valid, ext_shape_valid, result_out_valid} !== 0))
                $fatal(1, "JPEG_FAIL malformed extension published or quarantined before 128 accepted flits");
            if ((held_start && start_out_valid !== 1'b1) || (held_jpeg && jpeg_out_valid !== 1'b1) ||
                (held_ext && ext_out_valid !== 1'b1) || (held_result && result_out_valid !== 1'b1))
                $fatal(1, "JPEG_FAIL withdrew stalled sink offer");
            if (start_out_valid) begin
                if (!configured || sink_starts != 0 || start_out !== expected_start)
                    $fatal(1, "JPEG_FAIL START metadata got=%h expected=%h", start_out, expected_start);
                if (start_out_ready) begin
                    sink_starts++;
                    total_starts++;
                    $display("JPEG_SINK_START id=%h eye=%b session=%h epoch=%h tag=%h held=%0d", start_out.id,
                             start_out.camera, start_out.session_id, start_out.epoch, start_out.tag, start_wait);
                end else start_wait <= start_wait + 1;
            end
            if (jpeg_out_valid) begin
                if (held_jpeg && beat_out !== held_beat)
                    $fatal(1, "JPEG_FAIL stalled JPEG DATA/KEEP/LAST changed");
                if (!configured || sink_starts != 1 || sink_beats >= want_beats ||
                    !payload_matches(beat_out, expected_beats[sink_beats]))
                    $fatal(1, "JPEG_FAIL payload/KEEP/LAST order index=%0d got=%h expected=%h",
                           sink_beats, beat_out, expected_beats[sink_beats]);
                if (jpeg_out_ready) begin
                    sink_bytes += $countones(beat_out.keep);
                    total_bytes += $countones(beat_out.keep);
                    sink_beats++;
                end else if (beat_out.last) last_wait <= last_wait + 1;
            end
            if (ext_out_valid) begin
                if (!configured || sink_starts != 1 || sink_beats != want_beats || sink_exts != 0 ||
                    ext_shape_valid !== 1'b1 || ext_out !== 16384'd0)
                    $fatal(1, "JPEG_FAIL extension offered with wrong ordering or shape");
                if (ext_out_ready) begin
                    sink_exts++;
                    total_exts++;
                    $display("JPEG_SINK_EXT id=%h shape=1 held=%0d", expected_start.id, ext_wait);
                end else ext_wait++;
            end
            if (result_out_valid) begin
                if (!configured || sink_exts != 1 || sink_results != 0 || result_out !== expected_result)
                    $fatal(1, "JPEG_FAIL RESULT got=%h expected=%h ext_transfers=%0d",
                           result_out, expected_result, sink_exts);
                if (result_out_ready) begin
                    sink_results++;
                    total_results++;
                    $display("JPEG_SINK_RESULT id=%h ok=%b error=%h length=%0d bytes=%0d held=%0d", result_out.id,
                             result_out.ok, result_out.error_id, result_out.length, sink_bytes, result_wait);
                end else result_wait++;
            end
            held_start = start_out_valid && !start_out_ready;
            held_jpeg = jpeg_out_valid && !jpeg_out_ready;
            held_ext = ext_out_valid && !ext_out_ready;
            held_result = result_out_valid && !result_out_ready;
            held_beat = beat_out;
        end
    end

    task automatic configure_frame(input integer variant, mode, cut);
        expected_start = descriptor(variant);
        expected_extension = extension_wire(expected_start);
        malformed = mode == BAD_FLIT1 || mode == BAD_FLIT7;
        source_early_reject = mode == BAD_FLIT1;
        if (source_early_reject) expected_extension[128] = ~expected_extension[128];
        offered_prefix = expected_extension[2047:0];
        if (mode == BAD_FLIT7) expected_extension[1023] = 1;
        for (integer idx = 0; idx < 3; idx++) expected_beats[idx] = payload_wire(variant, idx, mode);
        want_beats = mode == NEGATIVE ? 2 : 3;
        offered_result = {mode != NEGATIVE, expected_start.id, expected_start.epoch,
                          mode == NEGATIVE ? 25'd32 : 25'd37, mode == NEGATIVE ? 8'd8 : 8'd0, expected_start.quality};
        case (mode)
            BAD_ID: offered_result.id = expected_start.id ^ 32'h20200000;
            BAD_LENGTH: offered_result.length = 38;
            BAD_COHORT: begin
                offered_result.epoch = expected_start.epoch ^ 32'h4000;
                offered_result.quality = expected_start.quality + 1;
            end
        endcase
        expected_result = offered_result;
        expected_result.id = expected_start.id;
        if (mode == BAD_ID || mode == BAD_LENGTH || mode == BAD_COHORT) begin
            expected_result.ok = 0;
            expected_result.error_id = mode == BAD_ID ? 8'he1 : mode == BAD_LENGTH ? 8'he2 : 8'he4;
        end
        src_starts = 0;
        src_bytes = 0;
        src_beats = 0;
        src_results = 0;
        src_prefixes = 0;
        src_flits = 0;
        sink_starts = 0;
        sink_bytes = 0;
        sink_beats = 0;
        sink_exts = 0;
        sink_results = 0;
        start_wait = 0;
        last_wait = 0;
        ext_wait = 0;
        result_wait = 0;
        hold_start = cut == CUT_CONTEXT || cut == CUT_START;
        seen_stream_start = 0;
        configured = 1;
    endtask

    task automatic send_start(input integer cut);
        @(negedge src_clk);
        start_in = expected_start;
        start_in_valid = 1;
        if (cut == CUT_CONTEXT) begin
            while (!start_in_ready && src_starts == 0) @(negedge src_clk);
            if (start_in_ready !== 1'b1 || src_starts != 0 || start_out_valid !== 1'b0)
                $fatal(1, "JPEG_FIXTURE CONTEXT window missed before actual START handshake");
            src_clock_on = 0;
            $display("JPEG_CUT CONTEXT source_ready=1 source_START_fires=0 sink_START_valid=0");
        end else begin
            do @(negedge src_clk); while (src_starts == 0);
            start_in_valid = 0;
            start_in = ~expected_start;
        end
    endtask

    task automatic send_payload(input integer count);
        @(negedge src_clk);
        for (integer idx = 0; idx < count; idx++) begin
            beat_in = expected_beats[idx];
            jpeg_in_valid = 1;
            do @(negedge src_clk); while (src_beats <= idx);
        end
        jpeg_in_valid = 0;
        beat_in = '1;
    endtask

    task automatic mutate_transferred_trailer;
        if (src_results == 1 && result_in_valid) begin
            result_in_valid = 0;
            result_in = ~offered_result;
        end
        if (src_prefixes == 1 && prefix_in_valid) begin
            prefix_in_valid = 0;
            prefix_in = ~offered_prefix;
        end
    endtask

    task automatic offer_trailer;
        @(negedge src_clk);
        result_in = offered_result;
        result_in_valid = 1;
        prefix_in = offered_prefix;
        prefix_in_valid = 1;
    endtask

    task automatic send_trailer(input integer cut_flit = -1);
        offer_trailer();
        while (!seen_stream_start) begin
            @(negedge src_clk);
            mutate_transferred_trailer();
        end
        for (integer idx = 0; idx < 128; idx++) begin
            stream_valid = 1;
            stream_data = expected_extension[idx * 128 +: 128];
            if (idx == cut_flit) begin
                src_clock_on = 0;
                if (src_flits != idx || src_results != 0)
                    $fatal(1, "JPEG_FIXTURE incorrect extension reset position");
                $display("JPEG_CUT EXT presented_flit=%0d accepted_flits=%0d source_RESULT_fires=%0d",
                         idx, src_flits, src_results);
                return;
            end
            do begin
                @(negedge src_clk);
                mutate_transferred_trailer();
            end while (src_flits <= idx);
        end
        stream_valid = 0;
        stream_data = '1;
        while (src_results == 0 || src_prefixes == 0) begin
            @(negedge src_clk);
            mutate_transferred_trailer();
        end
    endtask
    task automatic check_ram(input integer first_idx, last_idx);
        for (integer idx = first_idx; idx <= last_idx; idx++) begin
            @(negedge sink_clk);
            if (ext_shape_valid !== 1'b1) $fatal(1, "JPEG_FAIL RAM lease lost idx=%0d", idx);
            ext_read = 1;
            ext_index = idx;
            @(posedge sink_clk);
            #2;
            if (ext_read_data !== ram_word(idx))
                $fatal(1, "JPEG_FAIL RAM word idx=%0d got=%h expected=%h", idx, ext_read_data, ram_word(idx));
            total_ram_reads++;
        end
        @(negedge sink_clk);
        ext_read = 0;
    endtask

    task automatic begin_fence;
        wait (src_results == 1 && src_prefixes == 1);
        @(negedge src_clk);
        fence_session = expected_start.session_id;
        source_idle = 1;
        sink_quiet = 1;
        fence_request = 1;
        $display("JPEG_FENCE request session=%h EXT=%0d RESULT=%0d", fence_session, sink_exts, sink_results);
        repeat (12) @(negedge src_clk);
        if (fence_proven !== 1'b0 || sink_results != 0)
            $fatal(1, "JPEG_FAIL pending consumer did not withhold fence proof");
    endtask

    task automatic end_fence;
        do @(negedge src_clk); while (fence_proven !== 1'b1);
        total_proofs++;
        $display("JPEG_FENCE proven after sink RESULT id=%h", expected_start.id);
        repeat (3) begin
            @(negedge src_clk);
            if (fence_proven !== 1'b1) $fatal(1, "JPEG_FAIL fence proof was not held");
        end
        fence_request = 0;
        do @(negedge src_clk); while (fence_proven !== 1'b0);
        source_idle = 0;
        sink_quiet = 0;
    endtask

    task automatic consume_frame(input logic with_fence, cut_on_result);
        do @(negedge sink_clk); while (ext_out_valid !== 1'b1);
        if (with_fence) begin_fence();
        check_ram(0, 409);
        ext_out_ready = 1;
        do @(negedge sink_clk); while (sink_exts == 0);
        ext_out_ready = 0;
        do @(negedge sink_clk); while (result_out_valid !== 1'b1);
        repeat (5) @(negedge sink_clk);
        if (cut_on_result) begin
            @(negedge src_clk);
            if (!result_out_valid || result_out_ready || fence_proven || src_results != 1 || sink_results != 0)
                $fatal(1, "JPEG_FIXTURE FENCE/RESULT cut did not hold actual pending RESULT");
            src_clock_on = 0;
            $display("JPEG_CUT FENCE source_RESULT_fires=1 sink_RESULT_stalled=1 fence_proven=0");
        end else begin
            result_out_ready = 1;
            do @(negedge sink_clk); while (sink_results == 0);
            result_out_ready = 0;
            check_ram(0, 0);
            if (with_fence) end_fence();
        end
    endtask

    task automatic complete_frame(input integer variant, mode, input logic with_fence);
        configure_frame(variant, mode, COMPLETE);
        fork
            begin
                send_start(COMPLETE);
                send_payload(want_beats);
                send_trailer();
            end
            consume_frame(with_fence, 0);
        join
        if (src_starts != 1 || sink_starts != 1 || src_beats != want_beats || sink_beats != want_beats ||
            src_bytes != sink_bytes || src_flits != 128 || src_prefixes != 1 || sink_exts != 1 ||
            src_results != 1 || sink_results != 1 || start_wait != 3 || ext_wait == 0 || result_wait < 3 ||
            (mode != NEGATIVE && last_wait != 3))
            $fatal(1, "JPEG_FAIL incomplete public handshakes src/sink starts=%0d/%0d beats=%0d/%0d ext=%0d/%0d/%0d result=%0d/%0d",
                   src_starts, sink_starts, src_beats, sink_beats, src_flits, src_prefixes, sink_exts, src_results, sink_results);
        configured = 0;
    endtask

    task automatic clear_canceled_offers;
        configured = 0;
        malformed = 0;
        source_early_reject = 0;
        start_in_valid = 0;
        jpeg_in_valid = 0;
        result_in_valid = 0;
        prefix_in_valid = 0;
        stream_valid = 0;
        ext_out_ready = 0;
        result_out_ready = 0;
        ext_read = 0;
        source_idle = 0;
        sink_quiet = 0;
        fence_request = 0;
        held_start = 0;
        held_jpeg = 0;
        held_ext = 0;
        held_result = 0;
        sink_results = 0;
    endtask

    task automatic check_async_reset;
        #2;
        if ({start_in_ready, jpeg_in_ready, result_in_ready, prefix_in_ready, stream_ready,
             start_out_valid, jpeg_out_valid, ext_out_valid, result_out_valid, src_reset_done,
             sink_reset_done, fence_proven} !== 0)
            $fatal(1, "JPEG_FAIL reset did not immediately withdraw public offers/ready src=%b sink=%b done=%b fence=%b",
                   {start_in_ready, jpeg_in_ready, result_in_ready, prefix_in_ready, stream_ready},
                   {start_out_valid, jpeg_out_valid, ext_out_valid, result_out_valid},
                   {src_reset_done, sink_reset_done}, fence_proven);
        $display("JPEG_RESET public offers withdrawn source_stopped=%b sink_stopped=%b", !src_clock_on, !sink_clock_on);
    endtask

    task automatic release_reset;
        #23;
        src_clock_on = 1;
        sink_clock_on = 1;
        #2;
        src_reset_n = 1;
        sink_reset_n = 1;
        wait (src_reset_done === 1'b1 && sink_reset_done === 1'b1);
        monitors_on = 1;
        repeat (7) @(negedge sink_clk);
    endtask

    task automatic cancel_and_restart(input integer cut, cut_flit = -1);
        configure_frame(0, NORMAL, cut);
        send_start(cut);
        case (cut)
            CUT_CONTEXT: begin end
            CUT_START: begin
                do @(negedge src_clk); while (start_out_valid !== 1'b1);
                if (start_out_ready || sink_starts != 0)
                    $fatal(1, "JPEG_FIXTURE START cut was not stalled");
                src_clock_on = 0;
                @(negedge sink_clk);
                sink_clock_on = 0;
                $display("JPEG_CUT START source_START_fires=1 sink_START_held=1");
            end
            CUT_DATA: begin
                send_payload(1);
                do @(negedge src_clk); while (sink_beats != 1);
                jpeg_in_valid = 1;
                beat_in = expected_beats[1];
                src_clock_on = 0;
                $display("JPEG_CUT DATA source_beats=%0d sink_beats=%0d LAST=0", src_beats, sink_beats);
            end
            CUT_EXT: begin
                send_payload(want_beats);
                send_trailer(cut_flit);
            end
            CUT_FENCE: begin
                send_payload(want_beats);
                fork
                    send_trailer();
                    consume_frame(1, 1);
                join
                @(negedge sink_clk);
                sink_clock_on = 0;
            end
        endcase
        #1;
        src_reset_n = 0;
        sink_reset_n = 0;
        check_async_reset();
        clear_canceled_offers();
        release_reset();
        complete_frame(1, NORMAL, 1);
    endtask

    task automatic reject_malformed(input integer mode);
        configure_frame(0, mode, COMPLETE);
        send_start(COMPLETE);
        send_payload(want_beats);
        if (source_early_reject) begin
            offer_trailer();
            do @(negedge src_clk); while (src_protocol_fault !== 1'b1);
            $display("JPEG_PREFIX_FAULT src_fault=%b seen_stream_start=%b src_flits=%0d src_results=%0d",
                     src_protocol_fault, seen_stream_start, src_flits, src_results);
            if (seen_stream_start) begin
                stream_data = expected_extension[127:0];
                stream_valid = 1;
            end
            repeat (8) begin
                @(negedge src_clk);
                mutate_transferred_trailer();
                if (src_protocol_fault !== 1'b1 || src_flits != 0 || src_results != 0)
                    $fatal(1, "JPEG_FAIL prefix quarantine fault=%b flits=%0d source_RESULTS=%0d",
                           src_protocol_fault, src_flits, src_results);
            end
            $display("JPEG_PREFIX_REJECT accepted_flits=%0d sink_EXT_fires=%0d sink_RESULT_fires=%0d source_fault_now=%b",
                     src_flits, sink_exts, sink_results, src_protocol_fault);
        end else begin
            send_trailer();
            do @(negedge sink_clk); while (sink_protocol_fault !== 1'b1);
            repeat (8) begin
                @(negedge sink_clk);
                if (sink_protocol_fault !== 1'b1) $fatal(1, "JPEG_FAIL malformed extension fault failed to latch");
            end
            $display("JPEG_SHAPE_REJECT accepted_flits=%0d ext_fires=%0d result_fires=%0d",
                     src_flits, sink_exts, sink_results);
        end
        #1;
        src_reset_n = 0;
        sink_reset_n = 0;
        check_async_reset();
        clear_canceled_offers();
        release_reset();
        complete_frame(1, NORMAL, 1);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) $fatal(1, "JPEG_FIXTURE missing CASE");
        #1;
        src_reset_n = 0;
        sink_reset_n = 0;
        #146;
        release_reset();
        case (case_name)
            "two_frames": begin complete_frame(0, NORMAL, 0); complete_frame(1, NORMAL, 1); end
            "reset_context": cancel_and_restart(CUT_CONTEXT);
            "reset_start": cancel_and_restart(CUT_START);
            "reset_data": cancel_and_restart(CUT_DATA);
            "reset_ext_head": cancel_and_restart(CUT_EXT, 0);
            "reset_ext_mid": cancel_and_restart(CUT_EXT, 64);
            "reset_ext_final": cancel_and_restart(CUT_EXT, 127);
            "reset_fence": cancel_and_restart(CUT_FENCE);
            "negative": begin complete_frame(0, NEGATIVE, 1); complete_frame(1, NORMAL, 0); end
            "wrong_identity": begin complete_frame(0, BAD_ID, 1); complete_frame(1, NORMAL, 0); end
            "wrong_length": begin complete_frame(0, BAD_LENGTH, 1); complete_frame(1, NORMAL, 0); end
            "wrong_cohort": begin complete_frame(0, BAD_COHORT, 1); complete_frame(1, NORMAL, 0); end
            "malformed_prefix_flit1": reject_malformed(BAD_FLIT1);
            "malformed_stream_flit7": reject_malformed(BAD_FLIT7);
            default: $fatal(1, "JPEG_FIXTURE unknown CASE %s", case_name);
        endcase
        repeat (7) @(negedge sink_clk);
        if (fence_proven !== 1'b0 || total_proofs != 1)
            $fatal(1, "JPEG_FAIL expected one completed fence and no remaining proof");
        $display("BLACKBOX_PASS case=%s sink_starts=%0d bytes=%0d extensions=%0d results=%0d ram_reads=%0d proofs=%0d",
                 case_name, total_starts, total_bytes, total_exts, total_results, total_ram_reads, total_proofs);
        $finish;
    end

    initial begin
        #50000;
        $fatal(1, "JPEG_WATCHDOG %s source=%0d/%0d/%0d/%0d/%0d sink=%0d/%0d/%0d/%0d fault=%b%b fence=%b",
               case_name, src_starts, src_beats, src_flits, src_prefixes, src_results,
               sink_starts, sink_beats, sink_exts, sink_results, src_protocol_fault, sink_protocol_fault, fence_proven);
    end
endmodule
