`timescale 1ns/1ps

module tb_r2_egress_cdc;
    import egress_vectors::*;
    logic source_clk = 0, sink_clk = 0;
    logic source_rst_n = 1, sink_rst_n = 1;
    bit sink_running = 1;
    always #4 source_clk = ~source_clk;
    always #7 if (sink_running) sink_clk = ~sink_clk;
    `include "egress_sink_checks.svh"

    frame_t source_frame;
    logic i_start_valid = 0, o_start_ready;
    logic [127:0] i_jpeg_tdata = 0;
    logic [15:0] i_jpeg_tkeep = 0;
    logic i_jpeg_tlast = 0, i_jpeg_tvalid = 0, o_jpeg_tready;
    logic i_result_valid = 0, o_result_ready;
    logic [31:0] i_result_id = 0, i_result_epoch = 0;
    logic [24:0] i_result_length = 0;
    logic [7:0] i_result_quality = 0;
    logic [2047:0] source_extension = 0;
    logic source_extension_valid = 0, source_extension_ready;
    logic [127:0] i_extension_stream_data = 0;
    logic i_extension_stream_valid = 0, o_extension_stream_ready, o_extension_stream_start;
    logic o_source_protocol_fault;
    logic i_fence_request = 0, i_source_fence_idle = 0, i_sink_fence_quiet = 0;
    logic o_source_fence_proven, o_source_fence_fault, o_sink_fence_fault;
    logic o_source_reset_done, o_sink_reset_done;
    bit expect_malformed = 0;

    ordered_frame_cdc #(
        .CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1), .RECORD_EXTENSION_ENABLE(1),
        .RECORD_EXTENSION_WIDTH(16384), .BORROW_EXTENSION(1), .MASK_CONTEXT_ENABLE(0),
        .EXTENSION_RAM_ENABLE(1), .STREAM_EXTENSION(1)
    ) dut (
        .i_source_clk(source_clk), .i_source_rst_n(source_rst_n),
        .i_sink_clk(sink_clk), .i_sink_rst_n(sink_rst_n),
        .i_capture_id(source_frame.capture_id), .i_session_id(source_frame.session),
        .i_mode_epoch(source_frame.epoch), .i_write_tag(source_frame.tag),
        .i_width(source_frame.width), .i_height(source_frame.height),
        .i_timestamp_ns(source_frame.timestamp_ns), .i_camera_id(source_frame.camera),
        .i_quality(source_frame.quality), .i_format(8'd1),
        .i_start_mask(1'b0), .i_start_source_type(3'd0),
        .i_record_extension(source_extension), .i_record_extension_valid(source_extension_valid),
        .o_record_extension_ready(source_extension_ready),
        .i_result_ok(1'b1), .i_result_error(8'd0),
        .i_source_fence_session(32'h28df_301b), .i_sink_fence_session(32'h28df_301b),
        .i_raw_enqueued(64'h0000_0010_0000_00a7), .i_raw_consumed(64'h0000_0010_0000_00a7),
        .i_raw_consume_fire(1'b0),
        .*
    );

    always @(posedge source_clk)
        if (o_source_reset_done && !expect_malformed &&
            {o_source_protocol_fault, o_source_fence_fault} !== 2'b0)
            $fatal(1, "legal CDC source/fence raised fault");

    always @(posedge sink_clk)
        if (o_sink_reset_done && !expect_malformed &&
            {o_protocol_fault, o_sink_fence_fault} !== 2'b0)
            $fatal(1, "legal CDC sink/fence raised fault");

    task automatic wait_release;
        do @(posedge sink_clk); while ({o_source_reset_done, o_sink_reset_done} !== 2'b11);
        check_quiet(4);
    endtask

    task automatic produce(input frame_t frame, input integer beats, input frame_t stream_owner);
        extension_t header, stream;
        integer index;
        bit stream_started, header_done, result_done, last;
        header = extension_for(frame);
        stream = extension_for(stream_owner);
        @(negedge source_clk);
        source_frame = frame;
        i_start_valid = 1;
        do @(posedge source_clk); while (o_start_ready !== 1'b1);
        @(negedge source_clk);
        i_start_valid = 0;
        // The producer may immediately reuse its START descriptor.
        source_frame = ~frame;
        for (integer beat = 0; beat < beats; beat++) begin
            last = beat == beats - 1;
            i_jpeg_tvalid = 1;
            i_jpeg_tdata = jpeg_bytes(frame, beat, last);
            i_jpeg_tkeep = jpeg_keep(last);
            i_jpeg_tlast = last;
            do @(posedge source_clk); while (o_jpeg_tready !== 1'b1);
            @(negedge source_clk);
        end
        i_jpeg_tvalid = 0;
        i_result_id = frame.capture_id;
        i_result_epoch = frame.epoch;
        i_result_quality = frame.quality;
        i_result_length = jpeg_length(beats, 1);
        i_result_valid = 1;
        source_extension = header[2047:0];
        source_extension_valid = 1;
        index = 0;
        stream_started = 0;
        header_done = 0;
        result_done = 0;
        do begin
            @(posedge source_clk);
            if (o_extension_stream_start === 1'b1)
                stream_started = 1;
            if (i_extension_stream_valid && o_extension_stream_ready === 1'b1)
                index++;
            if (source_extension_valid && source_extension_ready === 1'b1)
                header_done = 1;
            if (i_result_valid && o_result_ready === 1'b1) begin
                if (index != 128)
                    $fatal(1, "source RESULT acknowledged before all flits transferred, index=%0d",
                           index);
                result_done = 1;
            end
            @(negedge source_clk);
            source_extension_valid = !header_done;
            if (header_done)
                source_extension = ~header[2047:0];
            i_result_valid = !result_done;
            i_extension_stream_valid = stream_started && index < 128;
            if (i_extension_stream_valid)
                i_extension_stream_data = stream[128*index +: 128];
        end while (!result_done || !header_done || index != 128);
        $display("CDC source capture=%h result and borrowed header accepted, stream flits=%0d",
                 frame.capture_id, index);
    endtask

    task automatic no_fence_proof(input integer cycles);
        repeat (cycles) begin
            @(posedge source_clk);
            if (o_source_fence_proven !== 1'b0)
                $fatal(1, "fence proven before sink truly drained");
        end
    endtask

    task automatic paired_frames(input frame_t first, input frame_t next_frame);
        fork
            begin
                produce(first, 24, first);
                produce(next_frame, 7, next_frame);
                @(negedge source_clk);
                i_source_fence_idle = 1;
                i_fence_request = 1;
            end
            begin
                hold_start(first, 7);
                take_start(first);
                take_jpeg(first, 24, 1, 4, 6, 0);
                hold_extension(7);
                read_words(extension_for(first), 0, 409, 1);
                take_extension();
                hold_result(first, jpeg_length(24, 1), 1, 0, 7, 1);
                take_result();

                hold_start(next_frame, 5);
                read_words(extension_for(first), 0, 8, 0);
                read_words(extension_for(first), 409, 409, 0);
                take_start(next_frame);
                @(posedge sink_clk);
                if (o_extension_shape_valid !== 1'b0)
                    $fatal(1, "old extension remained valid after next START transferred");
                take_jpeg(next_frame, 7, 1, 4, 0, 0);
                hold_extension(5);
                wait (i_fence_request);
                @(negedge sink_clk); i_sink_fence_quiet = 1;
                no_fence_proof(40);
                read_words(extension_for(next_frame), 0, 8, 1);
                take_extension();
                hold_result(next_frame, jpeg_length(7, 1), 1, 0, 4, 1);
                no_fence_proof(40);
                hold_result(next_frame, jpeg_length(7, 1), 1, 0, 2, 1);
                take_result();
                i_sink_fence_quiet = 0;
                no_fence_proof(20);
                @(negedge sink_clk); i_sink_fence_quiet = 1;
                do @(posedge source_clk); while (o_source_fence_proven !== 1'b1);
                repeat (5) begin
                    @(posedge source_clk);
                    if (o_source_fence_proven !== 1'b1)
                        $fatal(1, "fence proof failed to hold until request withdrawn");
                end
                @(negedge source_clk);
                i_fence_request = 0;
                i_source_fence_idle = 0;
                do @(posedge source_clk); while (o_source_fence_proven !== 1'b0);
                @(negedge sink_clk); i_sink_fence_quiet = 0;
                check_quiet(12);
            end
        join
        $display("CDC paired terminals and drain proof transferred");
    endtask

    task automatic receive_to_result(input frame_t frame, input integer beats);
        hold_start(frame, 2);
        take_start(frame);
        take_jpeg(frame, beats, 1, 2, 0, 0);
        hold_extension(4);
        read_words(extension_for(frame), 0, 8, 1);
        take_extension();
        hold_result(frame, jpeg_length(beats, 1), 1, 0, 6, 1);
    endtask

    task automatic cancel_stalled_result(input frame_t frame);
        fork
            produce(frame, 3, frame);
            receive_to_result(frame, 3);
        join
        @(negedge sink_clk);
        if (o_result_valid !== 1'b1 || i_result_ready !== 1'b0)
            $fatal(1, "cancellation fixture did not hold a terminal");
        sink_running = 0;
        #3 source_rst_n = 0;
        #4;
        if ({o_sink_reset_done, o_result_valid} !== 2'b0)
            $fatal(1, "source reset failed to cancel result with sink clock stopped");
        repeat (4) @(negedge source_clk);
        source_rst_n = 1;
        repeat (4) @(negedge source_clk);
        if ({o_sink_reset_done, o_result_valid} !== 2'b0)
            $fatal(1, "cancelled result returned before the sink clock restarted");
        sink_running = 1;
        wait_release();
        $display("CDC stopped-sink reset cancelled an unaccepted RESULT");
    endtask

    task automatic reject_stale_stream(input frame_t frame, input frame_t stale);
        bit fault_seen, checked;
        expect_malformed = 1;
        fault_seen = 0;
        checked = 0;
        fork : stale_stream_case
            produce(frame, 2, stale);
            begin
                hold_start(frame, 2);
                take_start(frame);
                take_jpeg(frame, 2, 1, 2, 0, 0);
                repeat (500) begin
                    @(posedge sink_clk);
                    if (o_protocol_fault === 1'b1 || o_source_protocol_fault === 1'b1)
                        fault_seen = 1;
                    if (o_record_extension_valid !== 1'b0 ||
                        (o_result_valid === 1'b1 && o_result_ok !== 1'b0))
                        $fatal(1, "stale stream identity escaped as a valid extension or RESULT");
                end
                if (!fault_seen)
                    $fatal(1, "stale borrowed stream identity raised no protocol fault");
                checked = 1;
            end
        join_none
        wait (checked);
        disable stale_stream_case;
        $display("CDC stale borrowed stream identity quarantined");
    endtask

    initial begin
        #2 source_rst_n = 0;
        sink_rst_n = 0;
        #45 source_rst_n = 1;
        #6 sink_rst_n = 1;
        wait_release();
        paired_frames(fixture(32'hffff_ffff, 1), fixture(32'd0, 2));
        cancel_stalled_result(fixture(32'd1, 3));
        fork
            produce(fixture(32'd2, 4), 9, fixture(32'd2, 4));
            receive_to_result(fixture(32'd2, 4), 9);
        join
        take_result();
        check_quiet(9);
        reject_stale_stream(fixture(32'd3, 5), fixture(32'd2, 4));
        $display("R2_EGRESS_CDC PASS");
        $finish;
    end

    initial #220000 $fatal(1, "CDC suite simulation watchdog");
endmodule
