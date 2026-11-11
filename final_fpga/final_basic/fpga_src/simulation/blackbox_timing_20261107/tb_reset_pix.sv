`timescale 1ps/1ps

module tb_reset_pix #(
    parameter integer SEPARATE = 1
);
    localparam [31:0] SESSION = 1, EPOCH = 7;

    reg clk = 0, run_clock = 0, async_reset_n = 1;
    wire phase_control_n, phase_data_n, legacy_control_n, legacy_data_n;
    wire control_n = SEPARATE ? phase_control_n : legacy_control_n;
    // A constant-low unused input verifies that legacy mode ignores it.
    wire data_n = SEPARATE ? phase_data_n : 1'b0;
    reg offer_begin = 0, terminal_valid = 0;
    reg [31:0] seq_id = 0;
    wire builder_begin_ready, join_begin_ready;
    wire begin_transfer = offer_begin && builder_begin_ready && join_begin_ready;
    wire [159:0] owner = {16'd1, 16'd0, 8'd1, 8'd1, 8'd1, 8'd0, seq_id, EPOCH, SESSION};
    wire source_valid, source_ready, joined_valid, stream_valid;
    wire [1023:0] source_data;
    wire [2047:0] joined_data;
    wire [127:0] stream_data;
    wire builder_fault, join_fault;
    reg joined_ready = 0, stream_start = 0;
    integer profile, begins = 0, sources = 0, consumed = 0;
    reg [1023:0] source_snapshot;
    reg source_held = 0;
    string stage = "initial";

    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(1)) phase_release (
        .i_clk(clk), .i_async_rst_n(async_reset_n), .o_rst_n(phase_control_n), .o_data_rst_n(phase_data_n)
    );
    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(0)) legacy_release (
        .i_clk(clk), .i_async_rst_n(async_reset_n), .o_rst_n(legacy_control_n), .o_data_rst_n(legacy_data_n)
    );
    frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(0), .SEPARATE_DATA_RESET(SEPARATE)) builder (
        .i_clk(clk), .i_rst_n(control_n), .i_data_reset_n(data_n),
        .s_begin_valid(begin_transfer), .o_begin_ready(builder_begin_ready),
        .i_source_session(SESSION), .i_source_epoch(EPOCH), .i_source_sequence(seq_id),
        .i_source_camera(8'd0), .i_source_kind(8'd1), .i_source_format(8'd1), .i_exposure_role(8'd0),
        .i_exposure_valid(1'b0), .i_actual_exposure(32'd0), .i_exposure_group(32'd0),
        .i_gain_valid(1'b0), .i_actual_gain(32'd0), .i_calibration_valid(1'b0), .i_calibration_id(32'd0),
        .i_time_quality(8'd0), .i_pair_valid(1'b0), .i_pair_id(64'd0), .i_job_valid(1'b0), .i_job_id(64'd0),
        .i_write_tag_valid(1'b0), .i_write_tag(64'd0), .i_qualified(1'b0),
        .i_processing_member(8'd0), .i_processing_mode(8'd0), .i_record_flags(16'd0),
        .s_stats_valid(1'b0), .o_stats_ready(), .s_stats_context(160'd0), .s_statistics(184'd0),
        .m_extension_valid(source_valid), .m_extension_ready(source_ready), .m_extension_data(source_data),
        .o_stale_count(), .o_error_count(), .o_input_fault(builder_fault)
    );
    frame_record_v3_join #(.SEPARATE_DATA_RESET(SEPARATE)) joiner (
        .i_clk(clk), .i_rst_n(control_n), .i_data_reset_n(data_n),
        .s_begin_valid(begin_transfer), .o_begin_ready(join_begin_ready), .s_begin_context(owner),
        .s_begin_features(4'd0), .s_terminal_valid(terminal_valid), .s_terminal_error(1'b0),
        .s_terminal_context(owner), .s_context2_extension(source_data),
        .s_context2_valid(source_valid), .o_context2_ready(source_ready),
        .s_f22_record(684'd0), .s_f22_valid(1'b0), .o_f22_ready(),
        .s_f23_record(177'd0), .s_f23_valid(1'b0), .o_f23_ready(),
        .s_f24_record(208'd0), .s_f24_valid(1'b0), .o_f24_ready(),
        .s_f25_record(265'd0), .s_f25_valid(1'b0), .o_f25_ready(),
        .m_extension(joined_data), .m_extension_valid(joined_valid), .m_extension_ready(joined_ready),
        .i_stream_start(stream_start), .m_stream_data(stream_data), .m_stream_valid(stream_valid),
        .m_stream_ready(1'b0), .o_lane_read_enable(), .o_lane_read_index(),
        .i_lane_read_data(40'd0), .i_lane_read_valid(1'b0), .o_fault(join_fault), .o_stale_count()
    );

    always #4000 if (run_clock) clk = ~clk;

    task automatic fail(input string reason);
        $display("BLACKBOX_FAIL reset_pix case=pix profile=%0d phase=%s t=%0t %s", profile, stage, $time, reason);
        $fatal(1, "External contract check failed");
    endtask

    task automatic step(input string description);
        stage = description;
        $display("BLACKBOX_STEP reset_pix case=pix profile=%0d %s", profile, description);
    endtask

    task automatic require_reset(input [3:0] expected);
        if ({phase_control_n, phase_data_n, legacy_control_n, legacy_data_n} !== expected)
            fail($sformatf("reset outputs expected=%b observed=%b", expected,
                           {phase_control_n, phase_data_n, legacy_control_n, legacy_data_n}));
        if (expected == 0 && {builder_begin_ready, join_begin_ready, source_valid, source_ready,
                              joined_valid, stream_valid} !== 6'd0)
            fail("qualified PIX READY or VALID remained high during stopped-clock reset");
    endtask

    always @(posedge clk) begin
        if (begin_transfer) begins = begins + 1;
        if (control_n && source_held && (source_valid !== 1'b1 || source_data !== source_snapshot))
            fail("builder changed a borrowed source extension before consumption");
        source_held = control_n && source_valid && !source_ready;
        if (source_valid) begin
            if (source_data[31:0] !== 32'h32585443 || source_data[47:32] !== 16'd1 ||
                source_data[159:64] !== {seq_id, EPOCH, SESSION})
                fail($sformatf("builder identity/header mismatch sequence=%h data=%h", seq_id, source_data[159:0]));
            source_snapshot = source_data;
        end
        if ((source_valid && source_ready) !== (joined_valid && joined_ready))
            fail("source and joined vector did not transfer on the same edge");
        if (source_valid && source_ready) sources = sources + 1;
        if (joined_valid && joined_ready) begin
            if (joined_data[1023:0] !== source_snapshot || joined_data[159:128] !== seq_id)
                fail("transferred joined extension does not match the admitted descriptor");
            consumed = consumed + 1;
        end
    end

    task automatic sample_first_three;
        for (integer edge_number = 1; edge_number <= 3; edge_number++) begin
            @(posedge clk);
            if (begin_transfer !== 1'b0) fail("begin accepted before R4");
            #1;
            require_reset(edge_number == 3 ? 4'b0111 : 4'b0000);
        end
    endtask

    task automatic release_and_check_r4(input bit expect_begin);
        sample_first_three();
        @(negedge clk);
        if (phase_control_n !== 1'b0) fail("phased control reset released before F3");
        #1;
        require_reset(4'b1111);
        @(posedge clk);
        if (begin_transfer !== expect_begin) fail("unexpected begin qualification on R4");
        #1;
        require_reset(4'b1111);
        @(negedge clk);
        offer_begin = 0;
    endtask

    task automatic start_descriptor(input [31:0] sequence_id);
        @(negedge clk);
        seq_id = sequence_id;
        offer_begin = 1;
        for (integer cycle = 0; cycle < 24; cycle++) begin
            @(posedge clk);
            if (begin_transfer) begin
                @(negedge clk);
                offer_begin = 0;
                return;
            end
        end
        fail("builder and join did not jointly accept descriptor");
    endtask

    task automatic terminal_then_stall;
        reg [2047:0] held_extension;
        @(negedge clk);
        terminal_valid = 1;
        @(negedge clk);
        terminal_valid = 0;
        for (integer cycle = 0; cycle < 32; cycle++) begin
            @(negedge clk);
            if (joined_valid === 1'b1) begin
                held_extension = joined_data;
                if (source_valid !== 1'b1 || source_ready !== 1'b0 || joined_data[1023:0] !== source_data ||
                    joined_data[159:128] !== seq_id)
                    fail($sformatf("borrowed source mismatch valid=%b ready=%b seq=%h joined_seq=%h",
                                   source_valid, source_ready, seq_id, joined_data[159:128]));
                repeat (5) begin
                    @(posedge clk);
                    if (joined_valid !== 1'b1 || joined_data !== held_extension)
                        fail("joined VALID or data changed under vector backpressure");
                end
                return;
            end
        end
        fail("matching terminal did not produce joined extension");
    endtask

    task automatic consume_result;
        @(negedge clk);
        joined_ready = 1;
        @(posedge clk);
        if (joined_valid !== 1'b1) fail("held vector unavailable on accepting edge");
        @(negedge clk);
        joined_ready = 0;
    endtask

    task automatic start_stalled_stream;
        reg [127:0] held_word;
        @(negedge clk);
        stream_start = 1;
        @(negedge clk);
        stream_start = 0;
        for (integer cycle = 0; cycle < 24; cycle++) begin
            @(negedge clk);
            if (stream_valid) begin
                held_word = stream_data;
                repeat (5) begin
                    @(posedge clk);
                    if (stream_valid !== 1'b1 || stream_data !== held_word)
                        fail("stream word changed while downstream was stalled");
                end
                return;
            end
        end
        fail("join did not present a stream word");
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        if (!$value$plusargs("profile=%d", profile) || profile != (SEPARATE ? 1 : 2))
            fail("profile and elaboration reset mode disagree");

        step("stopped-clock assertion and release, then cancellation between R3 and F3");
        #137;
        async_reset_n = 0;
        #1;
        require_reset(0);
        #1337;
        async_reset_n = 1;
        #17003;
        require_reset(0);
        run_clock = 1;
        sample_first_three();
        run_clock = 0;
        #13;
        async_reset_n = 0;
        #1;
        require_reset(0);
        #23011;
        require_reset(0);
        run_clock = 1;

        step("near-edge release accepts a held descriptor first at R4");
        @(negedge clk);
        seq_id = 32'd15;
        offer_begin = 1;
        #3993;
        async_reset_n = 1;
        release_and_check_r4(1);
        terminal_then_stall();
        consume_result();
        if (begins != 1 || sources != 1 || consumed != 1) fail("first descriptor count mismatch");

        step("assert reset with a stalled output stream and stopped PIX clock");
        start_descriptor(32'd16);
        terminal_then_stall();
        start_stalled_stream();
        @(negedge clk);
        #3;
        run_clock = 0;
        #137;
        async_reset_n = 0;
        #1;
        require_reset(0);
        #7733;
        async_reset_n = 1;
        #17003;
        require_reset(0);
        run_clock = 1;
        release_and_check_r4(0);
        repeat (6) begin
            @(posedge clk);
            if ({source_valid, joined_valid, stream_valid} !== 3'b000)
                fail("a pre-reset output was presented after release");
        end

        step("fresh descriptor completes after reset");
        start_descriptor(32'd17);
        terminal_then_stall();
        consume_result();
        if (begins != 3 || sources != 2 || consumed != 2 || {builder_fault, join_fault} !== 2'b00)
            fail("recovery transaction count or fault mismatch");
        $display("BLACKBOX_PASS reset_pix case=pix profile=%0d", profile);
        $finish;
    end

    initial begin
        #10000000;
        fail("10 us simulation watchdog");
    end
endmodule
