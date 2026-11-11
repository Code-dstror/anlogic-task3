`timescale 1ps/1ps

module tb_jpeg_reset;
    localparam int EXT_FLITS = 128, EXT_WORDS = 410;
    localparam int JPEG_BEATS = 3, JPEG_BYTES = 38;

    bit i_source_clk = 0, i_sink_clk = 0;
    bit source_run = 1, sink_run = 1;
    logic i_source_rst_n = 1, i_sink_rst_n = 1;
    logic i_start_valid = 0;
    wire o_start_ready;
    logic [31:0] i_capture_id, i_session_id, i_mode_epoch, i_write_tag;
    logic [15:0] i_width, i_height;
    logic [63:0] i_timestamp_ns;
    logic i_camera_id, i_start_mask = 0;
    logic [7:0] i_quality, i_format = 1;
    logic [2:0] i_start_source_type = 0;
    logic [127:0] i_jpeg_tdata;
    logic [15:0] i_jpeg_tkeep;
    logic i_jpeg_tlast, i_jpeg_tvalid = 0;
    wire o_jpeg_tready;
    logic i_result_valid = 0, i_result_ok = 1;
    wire o_result_ready;
    logic [31:0] i_result_id, i_result_epoch;
    logic [24:0] i_result_length;
    logic [7:0] i_result_error = 0, i_result_quality;
    logic [2047:0] i_record_extension;
    logic i_record_extension_valid = 0;
    wire o_record_extension_ready;
    logic [127:0] i_extension_stream_data;
    logic i_extension_stream_valid = 0;
    wire o_extension_stream_ready, o_extension_stream_start, o_source_protocol_fault;
    logic i_fence_request = 0, i_source_fence_idle = 0;
    logic [31:0] i_source_fence_session, i_sink_fence_session;
    logic [63:0] i_raw_enqueued = 64'd37, i_raw_consumed = 64'd37;
    logic i_raw_consume_fire = 0, i_sink_fence_quiet = 0;
    wire o_source_fence_proven, o_source_fence_fault, o_sink_fence_fault;
    wire o_source_reset_done, o_sink_reset_done;

    wire o_start_valid;
    logic i_start_ready = 0;
    wire [31:0] o_capture_id, o_session_id, o_mode_epoch, o_write_tag;
    wire [15:0] o_width, o_height;
    wire [63:0] o_timestamp_ns;
    wire o_camera_id, o_start_mask;
    wire [7:0] o_quality, o_format;
    wire [2:0] o_start_source_type;
    wire [127:0] o_jpeg_tdata;
    wire [15:0] o_jpeg_tkeep;
    wire o_jpeg_tlast, o_jpeg_tvalid;
    logic i_jpeg_tready = 0;
    wire o_result_valid, o_result_ok;
    logic i_result_ready = 0;
    wire [31:0] o_result_id, o_result_epoch;
    wire [24:0] o_result_length;
    wire [7:0] o_result_error, o_result_quality;
    wire [16383:0] o_record_extension;
    wire o_record_extension_valid;
    logic i_record_extension_ready = 0;
    wire o_extension_shape_valid;
    logic i_extension_read_enable = 0;
    logic [8:0] i_extension_read_index;
    wire [39:0] o_extension_read_data;
    wire o_protocol_fault;

    ordered_frame_cdc #(
        .CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1),
        .RECORD_EXTENSION_ENABLE(1), .RECORD_EXTENSION_WIDTH(16384),
        .BORROW_EXTENSION(1), .MASK_CONTEXT_ENABLE(0),
        .EXTENSION_RAM_ENABLE(1), .STREAM_EXTENSION(1)
    ) dut (.*);

    // Source and sink rising edges have opposite time parity, including after a pause.
    always begin
        #4000;
        if (source_run) i_source_clk = ~i_source_clk;
    end

    initial begin
        #1208;
        forever begin
            #3751;
            if (sink_run) i_sink_clk = ~i_sink_clk;
        end
    end

    int scenario, frame_number = 0;
    bit expect_bad_length;
    int source_edge = 0, sink_edge = 0, source_origin = 0, sink_origin = 0;
    int source_start, source_beats, source_flits, source_extension, source_result;
    int sink_start, sink_beats, sink_extension, sink_result, sink_bytes;
    int stalled_start, stalled_last, stalled_extension, stalled_result;
    int completed_good = 0, completed_e2 = 0, cancelled_frames = 0, proofs = 0, ram_words = 0;
    bit held_start, held_data, held_extension, held_result;
    logic [3:0] held_start_aux;
    logic [144:0] held_jpeg_fields;
    logic [6:0] last_source_qual;
    logic [4:0] last_sink_qual;
    logic last_proven;

    wire [4:0] source_ready = {
        o_start_ready, o_jpeg_tready, o_result_ready,
        o_record_extension_ready, o_extension_stream_ready
    };
    wire [3:0] sink_valid = {o_start_valid, o_jpeg_tvalid, o_record_extension_valid, o_result_valid};
    wire resets_released = i_source_rst_n && i_sink_rst_n;

    task automatic check(input logic condition, input string description);
        if (condition !== 1'b1) begin
            $fatal(1, "TB_FAIL case=%0d frame=%0d ps=%0t src=%0d sink=%0d %s",
                   scenario, frame_number, $time, source_edge, sink_edge, description);
        end
    endtask

    task automatic trace_source(input string event_name);
        $display("EDGE case=%0d frame=%0d src=%0d rel=%0d ps=%0t %s",
                 scenario, frame_number, source_edge, source_edge - source_origin, $time, event_name);
    endtask

    task automatic trace_sink(input string event_name);
        $display("EDGE case=%0d frame=%0d sink=%0d rel=%0d ps=%0t %s",
                 scenario, frame_number, sink_edge, sink_edge - sink_origin, $time, event_name);
    endtask

    function automatic logic [7:0] jpeg_byte(input int index);
        case (index)
            0: jpeg_byte = 8'hff;
            1: jpeg_byte = 8'hd8;
            JPEG_BYTES - 2: jpeg_byte = 8'hff;
            JPEG_BYTES - 1: jpeg_byte = 8'hd9;
            default: jpeg_byte = 8'(8'h43 + frame_number * 11 + index * 17);
        endcase
    endfunction

    function automatic logic [127:0] jpeg_beat(input int beat);
        jpeg_beat = 0;
        for (int lane = 0; lane < 16; lane++) begin
            if (16 * beat + lane < JPEG_BYTES)
                jpeg_beat[8 * lane +: 8] = jpeg_byte(16 * beat + lane);
        end
    endfunction

    function automatic logic [15:0] jpeg_keep(input int beat);
        jpeg_keep = beat == JPEG_BEATS - 1 ? 16'h003f : 16'hffff;
    endfunction

    // Independent wire-format oracle from public record-v2 identity and v4 shape.
    function automatic logic [127:0] extension_flit(input int index);
        case (index)
            0: extension_flit = {i_mode_epoch, i_session_id, 16'h0001, 16'h0001, 32'h32585443};
            1: extension_flit = {88'd0, 7'd0, i_camera_id, i_capture_id};
            8: extension_flit = 128'h010d00a9_00000000_00000501_34565053;
            default: extension_flit = 0;
        endcase
    endfunction

    function automatic logic [39:0] extension_word(input int index);
        int offset;
        logic [127:0] flit;
        extension_word = 0;
        for (int lane = 0; lane < 5; lane++) begin
            offset = 5 * index + lane;
            if (offset < 2048) begin
                flit = extension_flit(offset / 16);
                extension_word[8 * lane +: 8] = flit[8 * (offset % 16) +: 8];
            end
        end
    endfunction

    always @(posedge i_source_clk) begin
        source_edge++;
        if (resets_released) begin
            if (!o_source_reset_done)
                check({source_ready, o_extension_stream_start} === 6'b0, "source qualified before reset_done");
            if (o_source_reset_done) begin
                check({o_source_protocol_fault, o_source_fence_fault} === 2'b0, "source protocol/fence fault");
                if (i_fence_request && sink_result == 0)
                    check(o_source_fence_proven === 1'b0, "fence proved with a sink RESULT pending");
            end
        end
        if (i_start_valid && o_start_ready) begin
            check(resets_released && o_source_reset_done, "source START before local qualification");
            check(source_start == 0, "duplicate source START");
            source_start++;
            trace_source($sformatf("START id=%08x", i_capture_id));
        end
        if (i_jpeg_tvalid && o_jpeg_tready) begin
            check(resets_released && o_source_reset_done, "source DATA before local qualification");
            check(source_start == 1 && source_beats < JPEG_BEATS, "source DATA order/count");
            trace_source($sformatf("DATA beat=%0d keep=%04x last=%b", source_beats, i_jpeg_tkeep, i_jpeg_tlast));
            source_beats++;
        end
        if (i_extension_stream_valid && o_extension_stream_ready) begin
            check(resets_released && o_source_reset_done, "source stream before local qualification");
            check(source_beats == JPEG_BEATS && source_flits < EXT_FLITS, "source EXT stream order/count");
            trace_source($sformatf("FLIT index=%0d", source_flits));
            source_flits++;
        end
        if (i_record_extension_valid && o_record_extension_ready) begin
            check(resets_released && o_source_reset_done, "source extension before local qualification");
            check(source_beats == JPEG_BEATS && source_extension == 0, "source extension order/count");
            source_extension++;
            trace_source("EXTENSION");
        end
        if (i_result_valid && o_result_ready) begin
            check(resets_released && o_source_reset_done, "source RESULT before local qualification");
            check(source_beats == JPEG_BEATS && source_result == 0, "source RESULT order/count");
            source_result++;
            trace_source($sformatf("RESULT length=%0d", i_result_length));
        end

        #1;
        if ({o_source_reset_done, source_ready, o_extension_stream_start} !== last_source_qual) begin
            last_source_qual = {o_source_reset_done, source_ready, o_extension_stream_start};
            trace_source($sformatf("QUAL_POST done=%b ready=%05b stream_start=%b",
                                   o_source_reset_done, source_ready, o_extension_stream_start));
        end
        if (o_source_fence_proven !== last_proven) begin
            last_proven = o_source_fence_proven;
            trace_source($sformatf("FENCE_POST proven=%b", o_source_fence_proven));
        end
    end

    always @(posedge i_sink_clk) begin
        sink_edge++;
        if (resets_released) begin
            if (!o_sink_reset_done)
                check(sink_valid === 4'b0, "sink offered before reset_done");
            if (o_sink_reset_done)
                check({o_protocol_fault, o_sink_fence_fault} === 2'b0, "sink protocol/fence fault");

            if (held_start) begin
                check(o_start_valid, "START withdrew during stall");
                check({o_start_mask, o_start_source_type} === held_start_aux, "START auxiliary fields changed under stall");
            end
            if (held_data) begin
                check(o_jpeg_tvalid, "DATA withdrew during stall");
                check({o_jpeg_tlast, o_jpeg_tkeep, o_jpeg_tdata} === held_jpeg_fields, "DATA changed under stall");
            end
            if (held_extension) check(o_record_extension_valid, "EXTENSION withdrew during stall");
            if (held_result) check(o_result_valid, "RESULT withdrew during stall");

            if (o_start_valid) begin
                check(o_sink_reset_done && sink_start == 0, "unqualified or duplicate sink START");
                check({o_capture_id, o_session_id, o_mode_epoch, o_write_tag,
                       o_width, o_height, o_timestamp_ns, o_camera_id, o_quality, o_format} ===
                      {i_capture_id, i_session_id, i_mode_epoch, i_write_tag,
                       i_width, i_height, i_timestamp_ns, i_camera_id, i_quality, i_format}, "sink START metadata");
                if (i_start_ready) begin
                    sink_start++;
                    trace_sink($sformatf("START id=%08x session=%08x epoch=%08x tag=%08x camera=%0d",
                                         o_capture_id, o_session_id, o_mode_epoch, o_write_tag, o_camera_id));
                end else begin
                    stalled_start++;
                end
            end

            if (o_jpeg_tvalid) begin
                check(o_sink_reset_done && sink_start == 1 && sink_beats < JPEG_BEATS, "sink DATA order/count");
                check(o_jpeg_tkeep === jpeg_keep(sink_beats), "sink DATA KEEP");
                check(o_jpeg_tlast === (sink_beats == JPEG_BEATS - 1), "sink DATA LAST");
                for (int lane = 0; lane < 16; lane++) begin
                    if (o_jpeg_tkeep[lane]) begin
                        check(o_jpeg_tdata[8 * lane +: 8] === jpeg_byte(sink_beats * 16 + lane), "sink DATA byte");
                    end
                end
                if (i_jpeg_tready) begin
                    sink_bytes += $countones(o_jpeg_tkeep);
                    trace_sink($sformatf("DATA beat=%0d keep=%04x last=%b bytes=%0d",
                                         sink_beats, o_jpeg_tkeep, o_jpeg_tlast, sink_bytes));
                    sink_beats++;
                end else if (o_jpeg_tlast) begin
                    stalled_last++;
                end
            end

            if (o_record_extension_valid) begin
                check(o_sink_reset_done && sink_beats == JPEG_BEATS && sink_extension == 0, "sink EXT order/count");
                check(o_extension_shape_valid && o_record_extension === 16384'b0, "sink EXT shape/parallel port");
                if (i_record_extension_ready) begin
                    sink_extension++;
                    trace_sink("EXTENSION");
                end else begin
                    stalled_extension++;
                end
            end

            if (o_result_valid) begin
                check(o_sink_reset_done && sink_extension == 1 && sink_result == 0, "sink RESULT order/count");
                check(sink_bytes == JPEG_BYTES, "sink RESULT after wrong actual byte count");
                check({o_result_id, o_result_epoch, o_result_length, o_result_quality} ===
                      {i_capture_id, i_mode_epoch, i_result_length, i_quality}, "sink RESULT identity/length/quality");
                check(o_result_ok === !expect_bad_length &&
                      o_result_error === (expect_bad_length ? 8'he2 : 8'h00), "sink RESULT status");
                if (i_result_ready) begin
                    sink_result++;
                    if (expect_bad_length) completed_e2++;
                    else completed_good++;
                    trace_sink($sformatf("RESULT id=%08x length=%0d ok=%b error=%02x",
                                         o_result_id, o_result_length, o_result_ok, o_result_error));
                end else begin
                    stalled_result++;
                end
            end
        end else begin
            check(sink_valid === 4'b0, "sink offered while reset asserted");
        end
        held_start = resets_released && o_start_valid && !i_start_ready;
        held_start_aux = {o_start_mask, o_start_source_type};
        held_data = resets_released && o_jpeg_tvalid && !i_jpeg_tready;
        held_jpeg_fields = {o_jpeg_tlast, o_jpeg_tkeep, o_jpeg_tdata};
        held_extension = resets_released && o_record_extension_valid && !i_record_extension_ready;
        held_result = resets_released && o_result_valid && !i_result_ready;

        #1;
        if ({o_sink_reset_done, sink_valid} !== last_sink_qual) begin
            last_sink_qual = {o_sink_reset_done, sink_valid};
            trace_sink($sformatf("QUAL_POST done=%b valid=%04b", o_sink_reset_done, sink_valid));
        end
    end

    task automatic prepare_frame(input int index, input bit bad_length);
        frame_number = scenario * 10 + index;
        expect_bad_length = bad_length;
        source_origin = source_edge;
        sink_origin = sink_edge;
        source_start = 0;
        source_beats = 0;
        source_flits = 0;
        source_extension = 0;
        source_result = 0;
        sink_start = 0;
        sink_beats = 0;
        sink_extension = 0;
        sink_result = 0;
        sink_bytes = 0;
        stalled_start = 0;
        stalled_last = 0;
        stalled_extension = 0;
        stalled_result = 0;
        held_start = 0;
        held_data = 0;
        held_extension = 0;
        held_result = 0;
        i_capture_id = 32'hf100_aa00 + frame_number;
        i_session_id = 32'hc823_9310 + 3 * frame_number;
        i_mode_epoch = 32'h9470_1000 + 5 * frame_number;
        i_write_tag = 32'h308b_4170 + 7 * frame_number;
        i_width = 16'(1920 + frame_number);
        i_height = 16'(1080 + frame_number);
        i_timestamp_ns = 64'h8374_590b_32ad_0f10 + 64'(frame_number);
        i_camera_id = frame_number[0];
        i_quality = 8'(55 + frame_number);
        i_result_id = i_capture_id;
        i_result_epoch = i_mode_epoch;
        i_result_length = 25'(JPEG_BYTES + (bad_length ? 7 : 0));
        i_result_quality = i_quality;
        i_source_fence_session = i_session_id;
        i_sink_fence_session = i_session_id;
        for (int flit = 0; flit < 16; flit++)
            i_record_extension[128 * flit +: 128] = extension_flit(flit);

        i_jpeg_tvalid = 0;
        i_result_valid = 0;
        i_record_extension_valid = 0;
        i_extension_stream_valid = 0;
        i_fence_request = 0;
        i_source_fence_idle = 0;
        i_sink_fence_quiet = 0;
        i_start_ready = 0;
        i_jpeg_tready = 0;
        i_record_extension_ready = 0;
        i_result_ready = 0;
        i_extension_read_enable = 0;
        i_start_valid = 1;
        trace_source($sformatf("OFFER_START id=%08x bad_length=%b", i_capture_id, bad_length));
    endtask

    task automatic send_source_frame;
        bit result_done, extension_done, stream_started;
        int flit;
        do @(posedge i_source_clk); while (o_start_ready !== 1'b1);
        @(negedge i_source_clk);
        i_start_valid = 0;

        for (int beat = 0; beat < JPEG_BEATS; beat++) begin
            i_jpeg_tvalid = 1;
            i_jpeg_tdata = jpeg_beat(beat);
            i_jpeg_tkeep = jpeg_keep(beat);
            i_jpeg_tlast = beat == JPEG_BEATS - 1;
            do @(posedge i_source_clk); while (o_jpeg_tready !== 1'b1);
            @(negedge i_source_clk);
        end
        i_jpeg_tvalid = 0;
        i_result_valid = 1;
        i_record_extension_valid = 1;
        result_done = 0;
        extension_done = 0;
        stream_started = 0;
        flit = 0;
        while (!result_done || !extension_done || flit < EXT_FLITS) begin
            @(posedge i_source_clk);
            if (i_result_valid && o_result_ready) result_done = 1;
            if (i_record_extension_valid && o_record_extension_ready) extension_done = 1;
            if (o_extension_stream_start) stream_started = 1;
            if (i_extension_stream_valid && o_extension_stream_ready) flit++;
            @(negedge i_source_clk);
            i_result_valid = !result_done;
            i_record_extension_valid = !extension_done;
            i_extension_stream_valid = stream_started && flit < EXT_FLITS;
            if (i_extension_stream_valid) i_extension_stream_data = extension_flit(flit);
        end
        check(source_start == 1 && source_beats == JPEG_BEATS && source_flits == EXT_FLITS &&
              source_extension == 1 && source_result == 1, "source frame accounting");
    endtask

    task automatic check_ram_word(input int index);
        check(o_extension_read_data === extension_word(index),
              $sformatf("extension RAM word %0d expected %010x got %010x",
                        index, extension_word(index), o_extension_read_data));
        ram_words++;
    endtask

    task automatic read_held_extension;
        for (int index = 0; index < EXT_WORDS; index++) begin
            @(negedge i_sink_clk);
            i_extension_read_enable = 1;
            i_extension_read_index = 9'(index);
            @(posedge i_sink_clk);
            if (index > 0) check_ram_word(index - 1);
        end
        @(negedge i_sink_clk);
        i_extension_read_enable = 0;
        @(posedge i_sink_clk);
        check_ram_word(EXT_WORDS - 1);
        trace_sink("RAM_WORDS checked=410 while_extension_held");
    endtask

    task automatic receive_to_held_extension;
        wait (o_start_valid === 1'b1);
        repeat (6) @(negedge i_sink_clk);
        i_start_ready = 1;
        do @(negedge i_sink_clk); while (sink_start == 0);
        i_start_ready = 0;
        check(o_extension_shape_valid === 1'b0, "previous extension lease survived next sink START");

        i_jpeg_tready = 1;
        do @(negedge i_sink_clk); while (sink_beats < JPEG_BEATS - 1);
        i_jpeg_tready = 0;
        wait (o_jpeg_tvalid === 1'b1 && o_jpeg_tlast === 1'b1);
        repeat (7) @(negedge i_sink_clk);
        i_jpeg_tready = 1;
        do @(negedge i_sink_clk); while (sink_beats < JPEG_BEATS);
        i_jpeg_tready = 0;

        wait (o_record_extension_valid === 1'b1);
        read_held_extension();
        check(stalled_start >= 4 && stalled_last >= 4 && stalled_extension >= EXT_WORDS &&
              sink_result == 0 && o_result_valid === 1'b0, "required START/LAST/EXT stalls or early RESULT");
    endtask

    task automatic reach_held_extension;
        fork
            send_source_frame();
            receive_to_held_extension();
        join
        @(negedge i_sink_clk);
        i_sink_fence_quiet = 1;
        @(negedge i_source_clk);
        i_source_fence_idle = 1;
        i_fence_request = 1;
        trace_source("FENCE_REQUEST while_extension_held");
        repeat (16) @(negedge i_sink_clk);
        check(o_source_fence_proven === 1'b0 && o_result_valid === 1'b0, "early fence or RESULT with EXT pending");
    endtask

    task automatic reach_held_result;
        @(negedge i_sink_clk);
        i_record_extension_ready = 1;
        do @(negedge i_sink_clk); while (sink_extension == 0);
        i_record_extension_ready = 0;
        wait (o_result_valid === 1'b1);
        repeat (16) @(negedge i_sink_clk);
        check(stalled_result >= 12 && o_source_fence_proven === 1'b0, "required RESULT stall or early fence");
    endtask

    task automatic read_after_result;
        // Identity, shape and padding, sampled after the extension and RESULT handshakes.
        int index;
        for (int selection = 0; selection < 4; selection++) begin
            case (selection)
                0: index = 2;
                1: index = 3;
                2: index = 26;
                3: index = 409;
            endcase
            @(negedge i_sink_clk);
            check(o_extension_shape_valid === 1'b1, "extension shape lost before next sink START");
            i_extension_read_enable = 1;
            i_extension_read_index = 9'(index);
            @(negedge i_sink_clk);
            i_extension_read_enable = 0;
            @(posedge i_sink_clk);
            check_ram_word(index);
        end
        trace_sink("RAM_WORDS checked=4 after_result_before_next_start");
    endtask

    task automatic finish_result_and_fence;
        @(negedge i_sink_clk);
        i_result_ready = 1;
        do @(negedge i_sink_clk); while (sink_result == 0);
        i_result_ready = 0;
        read_after_result();
        do @(negedge i_source_clk); while (o_source_fence_proven !== 1'b1);
        proofs++;
        trace_source("FENCE_PROVE after_sink_result");
        repeat (5) @(negedge i_source_clk);
        check(o_source_fence_proven === 1'b1, "fence proof did not hold with request");
        i_fence_request = 0;
        i_source_fence_idle = 0;
        do @(negedge i_source_clk); while (o_source_fence_proven !== 1'b0);
        trace_source("FENCE_CLEAR");
        repeat (12) @(negedge i_sink_clk);
        check(sink_start == 1 && sink_beats == JPEG_BEATS && sink_bytes == JPEG_BYTES &&
              sink_extension == 1 && sink_result == 1 && sink_valid === 4'b0, "sink frame accounting or drain");
    endtask

    task automatic complete_frame;
        reach_held_extension();
        reach_held_result();
        finish_result_and_fence();
    endtask

    task automatic cold_release(input bit bad_length);
        #167333;
        prepare_frame(1, bad_length);
        i_source_rst_n = 1;
        i_sink_rst_n = 1;
        trace_source("RELEASE both");
    endtask

    task automatic check_cancelled;
        check({o_source_reset_done, o_sink_reset_done, source_ready, o_extension_stream_start,
               sink_valid, o_extension_shape_valid} === 13'b0, "public qualification or offer survived reset assertion");
        trace_source($sformatf("CANCEL_QUIET clocks=%b%b done=%b%b ready=%05b sink_valid=%04b",
                               i_source_clk, i_sink_clk, o_source_reset_done, o_sink_reset_done, source_ready, sink_valid));
    endtask

    task automatic stretch_after_third_source_edge;
        int edge_before_pause;
        repeat (3) @(posedge i_source_clk);
        #100;
        source_run = 0;
        edge_before_pause = source_edge;
        trace_source($sformatf("R3_HOLD_BEGIN done=%b start_ready=%b", o_source_reset_done, o_start_ready));
        #43123;
        check(source_edge == edge_before_pause && i_source_clk === 1'b1, "fixture failed to hold R3 high phase");
        trace_source($sformatf("R3_HOLD_END done=%b start_ready=%b", o_source_reset_done, o_start_ready));
        source_run = 1;
    endtask

    task automatic release_while_source_stopped(input bit high_phase, input bit sink_reset_only);
        int edge_before_pause;
        if (high_phase) @(posedge i_source_clk);
        else @(negedge i_source_clk);
        #100;
        source_run = 0;
        edge_before_pause = source_edge;
        if (!sink_reset_only) i_source_rst_n = 0;
        i_sink_rst_n = 0;
        #600;
        check_cancelled();
        #32001;
        check_cancelled();
        prepare_frame(2, 0);
        i_source_rst_n = 1;
        i_sink_rst_n = 1;
        trace_source($sformatf("RELEASE source_clock_stopped phase=%b sink_reset_only=%b",
                               i_source_clk, sink_reset_only));
        fork
            complete_frame();
            begin
                #33173;
                check(source_edge == edge_before_pause && i_source_clk === high_phase,
                      "fixture source clock moved in stopped release window");
                check({o_source_reset_done, source_ready, o_extension_stream_start} === 7'b0,
                      "source qualified without resumed clock");
                trace_source("RESUME source_clock");
                source_run = 1;
            end
        join
    endtask

    task automatic release_while_sink_stopped;
        int edge_before_pause;
        @(negedge i_sink_clk);
        #100;
        sink_run = 0;
        edge_before_pause = sink_edge;
        i_source_rst_n = 0;
        #600;
        check_cancelled();
        #32001;
        check_cancelled();
        prepare_frame(2, 0);
        i_source_rst_n = 1;
        trace_sink("RELEASE sink_clock_stopped phase=0 source_reset_only=1");
        fork
            complete_frame();
            begin
                #33173;
                check(sink_edge == edge_before_pause && i_sink_clk === 1'b0,
                      "fixture sink clock moved in stopped release window");
                check({o_sink_reset_done, sink_valid} === 5'b0, "sink qualified without resumed clock");
                trace_sink("RESUME sink_clock");
                sink_run = 1;
            end
        join
    endtask

    initial begin
        $timeformat(-12, 0, "", 1);
        check($value$plusargs("CASE=%d", scenario), "missing +CASE");
        #293;
        i_source_rst_n = 0;
        i_sink_rst_n = 0;
        case (scenario)
            1: begin
                cold_release(0);
                complete_frame();
                check(completed_good == 1 && proofs == 1, "first frame completion/proof");
            end
            2: begin
                cold_release(0);
                fork
                    complete_frame();
                    stretch_after_third_source_edge();
                join
                release_while_source_stopped(0, 0);
                check(completed_good == 2 && proofs == 2, "stretched and stopped-low completions/proofs");
            end
            3: begin
                cold_release(0);
                reach_held_extension();
                check(sink_extension == 0 && sink_result == 0 && o_record_extension_valid,
                      "fixture missing borrowed EXT at cancellation");
                cancelled_frames++;
                release_while_source_stopped(1, 1);
                check(completed_good == 1 && cancelled_frames == 1 && proofs == 1, "EXT cancellation/recovery accounting");
            end
            4: begin
                cold_release(1);
                reach_held_extension();
                reach_held_result();
                check(sink_result == 0 && o_result_valid && o_result_error === 8'he2,
                      "fixture missing held E2 RESULT at cancellation");
                cancelled_frames++;
                release_while_sink_stopped();
                check(completed_good == 1 && completed_e2 == 0 && cancelled_frames == 1 && proofs == 1,
                      "RESULT cancellation/recovery accounting");
            end
            5: begin
                cold_release(1);
                complete_frame();
                #100;
                prepare_frame(2, 0);
                complete_frame();
                check(completed_e2 == 1 && completed_good == 1 && proofs == 2,
                      "E2 consumption followed by same-cohort recovery");
            end
            default: check(0, "unknown scenario");
        endcase
        $display("BLACKBOX_PASS case=%0d good=%0d e2=%0d cancelled=%0d proofs=%0d ram_words=%0d ps=%0t",
                 scenario, completed_good, completed_e2, cancelled_frames, proofs, ram_words, $time);
        $finish;
    end

    initial begin
        #50000000;
        check(0, "50 us simulation watchdog");
    end
endmodule
