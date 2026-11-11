`timescale 1ps/1ps

module tb_reset_dfi #(
    parameter integer EARLY = 1
);
    localparam [31:0] SESSION = 1, EPOCH = 7;
    reg clk = 0, run_clock = 0, async_reset_n = 1;
    wire phase_control_n, phase_data_n;
    wire gate_reset_n = EARLY ? phase_data_n : phase_control_n;
    reg start_valid = 0, ring_ready = 0, extension_valid = 0, result_valid = 0;
    reg ready_valid = 0, header_fire = 0;
    reg [31:0] seq_id = 0, writer_tag = 0, generation = 0;
    reg [1023:0] extension = 0;
    wire start_ready, ring_valid, start_reserved, extension_ready, result_ready, header_ready;
    wire [1023:0] header_extension;
    wire gate_fault;
    integer profile, accepted_starts = 0, accepted_extensions = 0, accepted_results = 0;
    integer consumed_headers = 0;
    string stage = "initial";

    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(1)) phase_release (
        .i_clk(clk), .i_async_rst_n(async_reset_n), .o_rst_n(phase_control_n), .o_data_rst_n(phase_data_n)
    );
    jpeg_record_metadata_gate #(.RECORD_EXTENSION_WIDTH(1024)) gate_dut (
        .i_clk(clk), .i_rst_n(gate_reset_n), .s_start_valid(start_valid), .o_start_ready(start_ready),
        .s_start_writer_tag(writer_tag), .s_start_sequence(seq_id), .s_start_session(SESSION),
        .s_start_epoch(EPOCH), .s_start_camera(1'b0), .i_ring_start_ready(ring_ready),
        .o_ring_start_valid(ring_valid), .o_start_reserved(start_reserved),
        .s_extension(extension), .s_extension_valid(extension_valid), .o_extension_ready(extension_ready),
        .s_extension_shape_valid(1'b1), .o_extension_read_enable(), .o_extension_read_index(),
        .i_extension_read_data(40'd0), .s_write_result_valid(result_valid), .o_write_result_ready(result_ready),
        .s_write_result_tag(writer_tag), .s_write_result_sequence(seq_id), .s_write_result_session(SESSION),
        .s_write_result_epoch(EPOCH), .s_write_result_camera(1'b0), .s_write_result_slot(16'd0),
        .s_write_result_generation(generation), .s_write_result_ok(1'b1), .s_write_result_error(8'd0),
        .i_ready_valid(ready_valid), .i_ready_slot(16'd0), .i_ready_generation(generation),
        .i_ready_session(SESSION), .i_ready_sequence(seq_id), .i_ready_epoch(EPOCH), .i_ready_camera(1'b0),
        .i_selected_version(16'd2), .o_header_ready(header_ready), .o_header_extension(header_extension),
        .i_header_fire(header_fire), .i_header_release(1'b0), .o_header_stream_data(),
        .o_header_stream_valid(), .o_header_stream_last(), .i_header_stream_ready(1'b0),
        .s_mask_req_valid(1'b0), .o_mask_req_ready(), .s_mask_req_slot(16'd0),
        .s_mask_req_generation(32'd0), .s_mask_req_session(32'd0), .s_mask_req_sequence(32'd0),
        .s_mask_req_epoch(32'd0), .s_mask_req_camera(1'b0), .o_mask_rsp_valid(), .o_mask_rsp_ok(),
        .i_mask_rsp_ready(1'b0), .o_mask_rsp_error(), .o_mask_rsp_slot(), .o_mask_rsp_generation(),
        .o_mask_rsp_session(), .o_mask_rsp_sequence(), .o_mask_rsp_epoch(), .o_mask_rsp_camera(),
        .o_mask_rsp_qualified(), .o_mask_rsp_pixels(), .o_mask_rsp_source_type(),
        .o_quiescent(), .o_fault(gate_fault), .o_stale_write_count(), .o_bad_extension_count()
    );

    always #3790 if (run_clock) clk = ~clk;

    task automatic fail(input string reason);
        $display("BLACKBOX_FAIL reset_dfi case=dfi profile=%0d phase=%s t=%0t %s", profile, stage, $time, reason);
        $fatal(1, "External contract check failed");
    endtask

    task automatic step(input string description);
        stage = description;
        $display("BLACKBOX_STEP reset_dfi case=dfi profile=%0d %s", profile, description);
    endtask

    task automatic new_descriptor(input [31:0] next_seq, input [31:0] next_generation);
        seq_id = next_seq;
        writer_tag = 32'h2c00_0000 | next_seq;
        generation = next_generation;
        extension = 0;
        extension[31:0] = 32'h32585443;
        extension[47:32] = 16'd1;
        extension[48] = 1;
        extension[95:64] = SESSION;
        extension[127:96] = EPOCH;
        extension[159:128] = next_seq;
        extension[175:168] = 8'd1;
        extension[183:176] = 8'd1;
    endtask

    function automatic [1023:0] expected_header;
        reg [1023:0] value;
        value = extension;
        value[223:192] = SESSION;
        value[255:224] = generation;
        return value;
    endfunction

    always @(posedge clk) begin
        if ((start_valid && start_ready) !== (ring_valid && ring_ready))
            fail("START producer and ring disagree about acceptance");
        if (start_valid && start_ready) accepted_starts = accepted_starts + 1;
        if (extension_valid && extension_ready) accepted_extensions = accepted_extensions + 1;
        if (result_valid && result_ready) accepted_results = accepted_results + 1;
        if (header_fire) begin
            if (ready_valid !== 1'b1 || header_ready !== 1'b1 || header_extension !== expected_header())
                fail("header fire did not transfer the exact result identity and extension");
            consumed_headers = consumed_headers + 1;
        end
    end

    task automatic check_first_reservation;
        for (integer edge_number = 1; edge_number <= 3; edge_number++) begin
            @(posedge clk);
            if ({start_ready, ring_valid, start_reserved, header_ready} !== 4'b0000)
                fail("START or header presented before R4");
            #1;
            if ({phase_control_n, phase_data_n} !== (edge_number == 3 ? 2'b01 : 2'b00))
                fail("incorrect rising release of DFI data reset");
        end
        @(negedge clk);
        if (phase_control_n !== 1'b0) fail("phased DFI control reset released before F3");
        #1;
        if ({phase_control_n, phase_data_n} !== 2'b11) fail("incorrect F3 control release");
        @(posedge clk);
        if ({start_ready, ring_valid, start_reserved, header_ready} !== 4'b0000)
            fail("ring START or header presented before the R4 reservation edge");
        #1;
        if ({ring_valid, start_reserved} !== 2'b11)
            fail($sformatf("R4 held START start_valid=%b start_ready=%b ring_valid=%b ring_ready=%b reserved=%b fault=%b",
                           start_valid, start_ready, ring_valid, ring_ready, start_reserved, gate_fault));
    endtask

    task automatic consume_start;
        @(posedge clk);
        if ({start_valid, start_ready, ring_valid, ring_ready} !== 4'b1111)
            fail("reserved START failed to transfer with a ready ring");
        @(negedge clk);
        start_valid = 0;
        ring_ready = 0;
    endtask

    task automatic publish_and_read;
        reg [1023:0] held_header;
        bit transferred;
        extension_valid = 1;
        transferred = 0;
        for (integer cycle = 0; cycle < 48; cycle++) begin
            @(posedge clk);
            if (extension_ready === 1'b1) begin
                transferred = 1;
                break;
            end
        end
        if (!transferred) fail("matching metadata extension was not accepted");
        @(negedge clk);
        extension_valid = 0;
        result_valid = 1;
        transferred = 0;
        for (integer cycle = 0; cycle < 96; cycle++) begin
            @(posedge clk);
            if (result_ready === 1'b1) begin
                transferred = 1;
                break;
            end
        end
        if (!transferred) fail("matching successful write result was not accepted");
        @(negedge clk);
        result_valid = 0;
        ready_valid = 1;
        for (integer cycle = 0; cycle < 128; cycle++) begin
            @(posedge clk);
            if (header_ready === 1'b1) begin
                held_header = header_extension;
                if (held_header !== expected_header())
                    fail($sformatf("stored extension mismatch expected=%h got=%h", expected_header(), held_header));
                repeat (5) begin
                    @(posedge clk);
                    if (header_ready !== 1'b1 || header_extension !== held_header)
                        fail("owned header changed before header fire");
                end
                @(negedge clk);
                header_fire = 1;
                @(negedge clk);
                header_fire = 0;
                ready_valid = 0;
                return;
            end
        end
        fail("matching READY tuple did not return a header within 128 rising edges");
    endtask

    task automatic require_qualified_reset;
        if ({phase_control_n, phase_data_n, ring_valid, start_ready} !== 4'b0000)
            fail("stopped-clock reset did not clear phase outputs or START qualifiers");
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        if (!$value$plusargs("profile=%d", profile) || profile != (EARLY ? 1 : 2))
            fail("profile and elaboration reset mode disagree");

        step("held START reserves at R4 and waits for ring backpressure");
        #137;
        async_reset_n = 0;
        #1;
        require_qualified_reset();
        run_clock = 1;
        @(posedge clk);
        #1;
        if ({start_reserved, header_ready} !== 2'b00) fail("synchronous status did not reset");
        @(negedge clk);
        #3;
        run_clock = 0;
        new_descriptor(32'd41, 32'd19);
        start_valid = 1;
        ring_ready = 1;
        #1423;
        async_reset_n = 1;
        #17003;
        require_qualified_reset();
        run_clock = 1;
        check_first_reservation();
        ring_ready = 0;
        repeat (5) begin
            @(posedge clk);
            if ({ring_valid, start_reserved, start_ready} !== 3'b110 || accepted_starts != 0)
                fail("reserved START did not hold while the ring was stalled");
        end
        @(negedge clk);
        ring_ready = 1;
        consume_start();

        step("publish matching metadata and hold the exact vector before consumption");
        publish_and_read();
        if (accepted_starts != 1 || accepted_extensions != 1 || accepted_results != 1 || consumed_headers != 1)
            fail("first record handshake counts do not match");

        step("reset while an unaccepted START is reserved and the DFI clock is stopped");
        new_descriptor(32'd42, 32'd20);
        start_valid = 1;
        ring_ready = 1;
        for (integer cycle = 0; cycle < 40; cycle++) begin
            @(negedge clk);
            if (ring_valid === 1'b1) break;
        end
        ring_ready = 0;
        #1;
        if ({ring_valid, start_reserved, start_ready} !== 3'b110) fail("second START did not reserve");
        #3;
        run_clock = 0;
        #137;
        async_reset_n = 0;
        #1;
        require_qualified_reset();
        #12013;
        require_qualified_reset();
        run_clock = 1;
        @(posedge clk);
        #1;
        if ({start_reserved, header_ready} !== 2'b00) fail("reserved START or header survived reset sampling");

        step("near-edge release reserves fresh START at R4 and accepts it at R5");
        @(negedge clk);
        new_descriptor(32'd43, 32'd21);
        ring_ready = 1;
        #3783;
        async_reset_n = 1;
        check_first_reservation();
        consume_start();
        publish_and_read();
        if (accepted_starts != 2 || accepted_extensions != 2 || accepted_results != 2 || consumed_headers != 2 ||
            gate_fault !== 1'b0)
            fail("recovery record count or metadata fault mismatch");

        $display("BLACKBOX_PASS reset_dfi case=dfi profile=%0d", profile);
        $finish;
    end

    initial begin
        #10000000;
        fail("10 us simulation watchdog");
    end
endmodule
