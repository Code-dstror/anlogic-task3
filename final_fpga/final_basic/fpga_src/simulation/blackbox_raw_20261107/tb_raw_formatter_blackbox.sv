`timescale 1ns/1ps

module tb_raw_formatter_blackbox;
    import raw_blackbox_support::*;

    logic clk = 0;
    always #3.75 clk = ~clk;

    logic rst_n = 0;
    logic start_valid = 0, abort_record = 0;
    wire start_ready, drained, done;
    logic [31:0] payload_bytes, seq_num, session, epoch;
    logic [15:0] width, height;
    logic camera, time_valid;
    logic [1:0] bayer;
    logic [63:0] capture_time, job_id;
    logic [127:0] in_data = 0;
    logic [15:0] in_keep = 0;
    logic in_valid = 0, in_last = 0;
    wire in_ready;
    wire [127:0] out_data;
    wire [15:0] out_keep;
    wire out_valid, out_last;
    logic out_ready = 0;

    raw_video_record_formatter formatter (
        .i_clk(clk), .i_rst_n(rst_n),
        .i_start_valid(start_valid), .o_start_ready(start_ready),
        .i_abort(abort_record), .o_drained(drained),
        .i_payload_bytes(payload_bytes), .i_width(width), .i_height(height),
        .i_sequence(seq_num), .i_session(session), .i_epoch(epoch),
        .i_camera(camera), .i_bayer_phase(bayer), .i_time_valid(time_valid),
        .i_capture_time_ns(capture_time), .i_job_id(job_id),
        .s_data(in_data), .s_keep(in_keep), .s_valid(in_valid), .s_last(in_last),
        .s_ready(in_ready), .m_data(out_data), .m_keep(out_keep),
        .m_valid(out_valid), .m_last(out_last), .m_ready(out_ready), .o_done(done)
    );

    string case_name;
    int unsigned seed = 32'h4bed8123;
    int unsigned stream_key;
    int cycle = 0;
    int bytes_seen = 0, payload_in_beats = 0, starts_seen = 0, dones_seen = 0;
    int last_cycle = -100;
    logic record_active = 0, out_held = 0;
    logic [144:0] held_beat;
    logic [511:0] expected_header;

    always @(posedge clk) begin : scoreboard
        int count;
        logic [7:0] expected_byte;

        cycle++;
        if (!rst_n) begin
            out_held = 0;
        end else begin
            if (out_held && ({out_valid, out_data, out_keep, out_last} !== {1'b1, held_beat}))
                $fatal(1, "formatter changed a stalled beat at byte %0d cycle %0d", bytes_seen, cycle);
            out_held = out_valid && !out_ready;
            held_beat = {out_data, out_keep, out_last};
            if (start_valid && start_ready)
                starts_seen++;
            if (in_valid && in_ready)
                payload_in_beats++;

            if (out_valid && !record_active)
                $fatal(1, "formatter presented output with no accepted record");
            if (out_valid && out_ready) begin
                count = bytes_seen < 64 ? 16 : 64 + int'(payload_bytes) - bytes_seen;
                if (count > 16)
                    count = 16;
                if (count < 1 || out_keep !== low_keep(count))
                    $fatal(1, "formatter KEEP at byte %0d got %h expected %h", bytes_seen, out_keep, low_keep(count));
                if (out_last !== (bytes_seen + count == 64 + payload_bytes))
                    $fatal(1, "formatter LAST at byte %0d was %b", bytes_seen, out_last);
                for (int lane = 0; lane < count; lane++) begin
                    if (bytes_seen < 64)
                        expected_byte = expected_header[8*(bytes_seen+lane) +: 8];
                    else
                        expected_byte = payload_byte(stream_key, bytes_seen + lane - 64);
                    // The wire value of an invalid timestamp is unspecified.
                    if ((time_valid || bytes_seen != 32 || lane >= 8) && out_data[8*lane +: 8] !== expected_byte)
                        $fatal(1, "formatter byte %0d got %h expected %h", bytes_seen+lane, out_data[8*lane +: 8], expected_byte);
                end
                bytes_seen += count;
                if (out_last)
                    last_cycle = cycle;
            end

            if (done) begin
                if (dones_seen != 0 || (cycle != last_cycle && cycle != last_cycle + 1))
                    $fatal(1, "formatter DONE lacked a unique last handshake, cycle=%0d last=%0d", cycle, last_cycle);
                dones_seen++;
            end
        end
    end

    task automatic step(input int count = 1);
        repeat (count) @(negedge clk);
    endtask

    task automatic reset_formatter;
        rst_n = 0;
        start_valid = 0;
        abort_record = 0;
        in_valid = 0;
        out_ready = 0;
        record_active = 0;
        step(8);
        rst_n = 1;
        step(4);
        if (drained !== 1 || start_ready !== 1 || out_valid !== 0 || done !== 0)
            $fatal(1, "formatter failed to reset to idle");
    endtask

    task automatic start_record(input int length, input int tag);
        int prior_starts;
        payload_bytes = length;
        seq_num = 32'h9152abf0 + tag;
        session = 32'h361b5d8c ^ tag;
        epoch = 32'h41750020 + tag;
        camera = tag[0];
        bayer = tag[1:0];
        time_valid = !tag[2];
        width = 16'h1120 + 4*tag;
        height = 16'h0422 + tag;
        capture_time = 64'h45dd30a51fe2b765 + 8*tag;
        job_id = 64'h80000000e170e302 ^ 3*tag;
        stream_key = 32'h7fa83c4d ^ tag ^ length;
        expected_header = araw_header(payload_bytes, width, height, seq_num, session,
                                      epoch, camera, bayer, time_valid, capture_time, job_id);
        bytes_seen = 0;
        payload_in_beats = 0;
        dones_seen = 0;
        last_cycle = -100;
        record_active = 1;
        prior_starts = starts_seen;
        start_valid = 1;
        for (int tries = 0; starts_seen == prior_starts && tries < 20; tries++)
            step();
        if (starts_seen != prior_starts + 1)
            $fatal(1, "formatter START failed tag=%0d", tag);
        start_valid = 0;
    endtask

    task automatic wait_presentation(input int offset);
        for (int tries = 0; out_valid !== 1 && tries < 20; tries++)
            step();
        if (out_valid !== 1 || bytes_seen != offset || drained !== 0)
            $fatal(1, "formatter failed to present byte %0d, saw %0d drained=%b", offset, bytes_seen, drained);
    endtask

    task automatic accept_header(input int beat, input int stall_cycles);
        wait_presentation(16*beat);
        step(stall_cycles);
        out_ready = 1;
        step();
        out_ready = 0;
        if (bytes_seen != 16*(beat+1))
            $fatal(1, "formatter did not transfer header beat %0d", beat);
    endtask

    task automatic accept_body(input int offset, input int count, input int stall_cycles);
        int previous_input_beats;
        previous_input_beats = payload_in_beats;
        in_valid = 1;
        in_last = offset + count == payload_bytes;
        in_data = payload_word(stream_key, offset);
        in_keep = low_keep(count);
        step();
        wait_presentation(64+offset);
        step(stall_cycles);
        if (dones_seen != 0 || payload_in_beats != previous_input_beats)
            $fatal(1, "formatter consumed stalled body at byte %0d", offset);
        out_ready = 1;
        step();
        out_ready = 0;
        in_valid = 0;
        if (bytes_seen != 64+offset+count || payload_in_beats != previous_input_beats+1)
            $fatal(1, "formatter did not transfer body beat at %0d", offset);
    endtask

    task automatic verify_drained(input int expected_bytes, input bit successful);
        for (int tries = 0; drained !== 1 && tries < 20; tries++)
            step();
        out_ready = 1;
        step(5);
        if (drained !== 1 || out_valid !== 0 || bytes_seen != expected_bytes || dones_seen != int'(successful))
            $fatal(1, "formatter final state drained=%b valid=%b bytes=%0d/%0d done=%0d/%0d",
                   drained, out_valid, bytes_seen, expected_bytes, dones_seen, successful);
        out_ready = 0;
        abort_record = 0;
        record_active = 0;
        step();
    endtask

    task automatic normal_record(input int length, input int tag);
        int count;
        start_record(length, tag);
        for (int beat = 0; beat < 4; beat++) begin
            seed = next_random(seed);
            accept_header(beat, 1 + int'(seed % 7));
        end
        for (int offset = 0; offset < length; offset += 16) begin
            seed = next_random(seed);
            step(int'(seed % 3));
            count = length - offset < 16 ? length - offset : 16;
            accept_body(offset, count, 1 + int'(seed % 5));
        end
        verify_drained(64+length, 1);
        if (payload_in_beats != (length+15)/16)
            $fatal(1, "formatter consumed wrong number of payload beats");
        $display("CHECK formatter length=%0d Bayer=%0d camera=%0d timestamp_valid=%0d", length, bayer, camera, time_valid);
    endtask

    task automatic abort_on_header(input int beat);
        start_record(17, 12+beat);
        for (int prefix = 0; prefix < beat; prefix++)
            accept_header(prefix, 3);
        wait_presentation(16*beat);
        step(3);
        abort_record = 1;
        step(8);
        if (drained !== 0 || out_valid !== 1 || dones_seen != 0)
            $fatal(1, "formatter drained ahead of stalled header beat %0d", beat);
        out_ready = 1;
        step();
        verify_drained(16*(beat+1), 0);
        if (payload_in_beats != 0)
            $fatal(1, "formatter consumed body on header abort");
        $display("CHECK formatter abort presented header beat=%0d", beat);
    endtask

    task automatic abort_in_body_wait;
        start_record(17, 18);
        for (int beat = 0; beat < 4; beat++)
            accept_header(beat, 1);
        accept_body(0, 16, 9);
        abort_record = 1;
        verify_drained(80, 0);
        if (payload_in_beats != 1)
            $fatal(1, "formatter lost accepted body prefix");
        $display("CHECK formatter abort following a stalled and accepted nonfinal body beat");
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name))
            $fatal(1, "missing +CASE");
        void'($value$plusargs("SEED=%d", seed));
        if (seed == 0)
            $fatal(1, "seed must be nonzero");
        $display("BEGIN case=%s seed=%0d", case_name, seed);
        step();
        reset_formatter();
        case (case_name)
            "formatter_lengths": begin
                normal_record(1, 0);
                normal_record(15, 1);
                normal_record(16, 2);
                normal_record(17, 3);
                normal_record(65, 4);
            end
            "formatter_abort": begin
                for (int beat = 0; beat < 4; beat++)
                    abort_on_header(beat);
                abort_in_body_wait();
                normal_record(17, 7);
            end
            "formatter_reset": begin
                start_record(65, 9);
                accept_header(0, 2);
                wait_presentation(16);
                step(8);
                reset_formatter();
                normal_record(1, 3);
            end
            default: $fatal(1, "unknown case %s", case_name);
        endcase
        $display("BLACKBOX_PASS %s cycles=%0d", case_name, cycle);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "formatter watchdog case=%s cycle=%0d bytes_seen=%0d", case_name, cycle, bytes_seen);
    end
endmodule
