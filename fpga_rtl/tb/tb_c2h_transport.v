`timescale 1ns / 1ps

`include "c2h_test_fixture.vh"

module tb_c2h_transport;

    reg clk;
    reg rst_n;
    reg start;
    reg [31:0] payload_length;
    reg [1:0] pattern_select;
    reg axis_tready;
    reg [15:0] ready_lfsr;
    reg case_active;
    reg [31:0] checked_payload_length;
    reg [1:0] checked_pattern;
    reg previous_stall;
    reg [127:0] stalled_data;
    reg [15:0] stalled_keep;
    reg stalled_last;
    reg previous_source_stall;
    reg [127:0] stalled_source_data;
    reg [15:0] stalled_source_keep;
    reg stalled_source_last;
    integer error_count;
    integer beat_index;
    integer payload_byte_index;
    integer lane_index;
    integer actual_byte_count;
    integer timeout_count;
    reg [15:0] expected_keep;

    wire source_busy;
    wire meta_valid;
    wire meta_ready;
    wire [31:0] meta_frame_sequence;
    wire [31:0] meta_payload_length;
    wire [15:0] meta_width;
    wire [15:0] meta_height;
    wire [7:0] meta_pixel_format;
    wire [7:0] meta_compression;
    wire [7:0] meta_quality;
    wire [63:0] meta_timestamp_ns;
    wire [31:0] meta_status;
    wire [31:0] meta_error_code;
    wire [15:0] meta_slot_id;
    wire [31:0] meta_payload_crc32;
    wire [127:0] source_tdata;
    wire [15:0] source_tkeep;
    wire source_tvalid;
    wire source_tready;
    wire source_tlast;
    wire [127:0] axis_tdata;
    wire [15:0] axis_tkeep;
    wire [15:0] axis_tuser;
    wire axis_tvalid;
    wire axis_tlast;
    wire tx_busy;
    wire transport_ready;
    wire [15:0] active_slot_id;
    wire [31:0] last_error;
    wire frame_accept;
    wire frame_done;
    wire frame_abort;

    c2h_test_source u_source (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_start(start),
        .i_payload_length(payload_length),
        .i_pattern_select(pattern_select),
        .o_busy(source_busy),
        .o_meta_valid(meta_valid),
        .i_meta_ready(meta_ready),
        .o_meta_frame_sequence(meta_frame_sequence),
        .o_meta_payload_length(meta_payload_length),
        .o_meta_width(meta_width),
        .o_meta_height(meta_height),
        .o_meta_pixel_format(meta_pixel_format),
        .o_meta_compression(meta_compression),
        .o_meta_quality(meta_quality),
        .o_meta_timestamp_ns(meta_timestamp_ns),
        .o_meta_status(meta_status),
        .o_meta_error_code(meta_error_code),
        .o_meta_slot_id(meta_slot_id),
        .o_meta_payload_crc32(meta_payload_crc32),
        .o_src_tdata(source_tdata),
        .o_src_tkeep(source_tkeep),
        .o_src_tvalid(source_tvalid),
        .i_src_tready(source_tready),
        .o_src_tlast(source_tlast)
    );

    c2h_frame_tx u_frame_tx (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_transport_enable(1'b1),
        .i_link_up(1'b1),
        .i_c2h_running(1'b1),
        .i_meta_valid(meta_valid),
        .o_meta_ready(meta_ready),
        .i_meta_frame_sequence(meta_frame_sequence),
        .i_meta_payload_length(meta_payload_length),
        .i_meta_width(meta_width),
        .i_meta_height(meta_height),
        .i_meta_pixel_format(meta_pixel_format),
        .i_meta_compression(meta_compression),
        .i_meta_quality(meta_quality),
        .i_meta_timestamp_ns(meta_timestamp_ns),
        .i_meta_status(meta_status),
        .i_meta_error_code(meta_error_code),
        .i_meta_slot_id(meta_slot_id),
        .i_meta_payload_crc32(meta_payload_crc32),
        .i_src_tdata(source_tdata),
        .i_src_tkeep(source_tkeep),
        .i_src_tvalid(source_tvalid),
        .o_src_tready(source_tready),
        .i_src_tlast(source_tlast),
        .o_axis_tdata(axis_tdata),
        .o_axis_tkeep(axis_tkeep),
        .o_axis_tuser(axis_tuser),
        .o_axis_tvalid(axis_tvalid),
        .i_axis_tready(axis_tready),
        .o_axis_tlast(axis_tlast),
        .o_tx_busy(tx_busy),
        .o_transport_ready(transport_ready),
        .o_active_slot_id(active_slot_id),
        .o_last_error(last_error),
        .o_frame_accept(frame_accept),
        .o_frame_done(frame_done),
        .o_frame_abort(frame_abort)
    );

    function [15:0] keep_mask;
        input [31:0] byte_length;
        integer valid_bytes;
        begin
            valid_bytes = byte_length % 16;
            if (byte_length > 16) begin
                keep_mask = 16'hffff;
            end else if (valid_bytes == 0) begin
                keep_mask = 16'hffff;
            end else begin
                keep_mask = (16'h0001 << valid_bytes) - 1'b1;
            end
        end
    endfunction

    function [127:0] expected_jpeg_fixture_beat;
        input [5:0] fixture_beat_index;
        begin
            // Independent verification oracle.  Each literal is a complete
            // AXI beat with lane 0 in bits [7:0], rather than a DUT-style
            // dynamic slice of the packed JPEG fixture.
            case (fixture_beat_index)
                6'd0: expected_jpeg_fixture_beat = 128'h0100000101004649464a1000e0ffd8ff;
                6'd1: expected_jpeg_fixture_beat = 128'h08050607060608004300dbff00000100;
                6'd2: expected_jpeg_fixture_beat = 128'h12190c0b0b0c0d140c0a080909070707;
                6'd3: expected_jpeg_fixture_beat = 128'h20272e24201c1c1a1d1e1f1a1d140f13;
                6'd4: expected_jpeg_fixture_beat = 128'h271f34343431302c2937281c1c232c22;
                6'd5: expected_jpeg_fixture_beat = 128'h0100080b00c0ff3234332e3c32383d39;
                6'd6: expected_jpeg_fixture_beat = 128'h0101050100001f00c4ff001101010100;
                6'd7: expected_jpeg_fixture_beat = 128'h04030201000000000000000001010101;
                6'd8: expected_jpeg_fixture_beat = 128'h0301020010b500c4ff0b0a0908070605;
                6'd9: expected_jpeg_fixture_beat = 128'h000302017d0100000404050503040203;
                6'd10: expected_jpeg_fixture_beat = 128'h32147122076151130641312112051104;
                6'd11: expected_jpeg_fixture_beat = 128'h72623324f0d15215c1b1422308a19181;
                6'd12: expected_jpeg_fixture_beat = 128'h35342a29282726251a191817160a0982;
                6'd13: expected_jpeg_fixture_beat = 128'h5554534a494847464544433a39383736;
                6'd14: expected_jpeg_fixture_beat = 128'h7574736a696867666564635a59585756;
                6'd15: expected_jpeg_fixture_beat = 128'h9493928a898887868584837a79787776;
                6'd16: expected_jpeg_fixture_beat = 128'hb2aaa9a8a7a6a5a4a3a29a9998979695;
                6'd17: expected_jpeg_fixture_beat = 128'hc9c8c7c6c5c4c3c2bab9b8b7b6b5b4b3;
                6'd18: expected_jpeg_fixture_beat = 128'he6e5e4e3e2e1dad9d8d7d6d5d4d3d2ca;
                6'd19: expected_jpeg_fixture_beat = 128'hdafffaf9f8f7f6f5f4f3f2f1eae9e8e7;
                6'd20: expected_jpeg_fixture_beat = 128'h0000000000d9ff4a003f000001010800;
                default: expected_jpeg_fixture_beat = 128'd0;
            endcase
        end
    endfunction

    task report_error;
        input [8 * 80 - 1:0] message;
        begin
            error_count = error_count + 1;
            $display("[TB] ERROR: %0s at %0t", message, $time);
        end
    endtask

    task run_length_case;
        input [31:0] case_length;
        begin
            while (!transport_ready) @(posedge clk);
            checked_payload_length = case_length;
            checked_pattern = 2'd0;
            beat_index = 0;
            actual_byte_count = 0;
            case_active = 1'b1;
            payload_length = case_length;
            pattern_select = 2'd0;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            timeout_count = 0;
            while (!frame_done && !frame_abort && (timeout_count < 4000000)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (frame_abort) report_error("unexpected frame abort");
            if (!frame_done) report_error("frame completion timeout");
            if (actual_byte_count != (case_length + 64)) begin
                report_error("actual transfer length mismatch");
            end
            case_active = 1'b0;
            @(posedge clk);
            $display("[TB] length %0d complete, beats=%0d", case_length, beat_index);
        end
    endtask

    task run_jpeg_fixture_case;
        begin
            while (!transport_ready) @(posedge clk);
            checked_payload_length = `C2H_TEST_JPEG_FIXTURE_LENGTH;
            checked_pattern = `C2H_TEST_PATTERN_JPEG_FIXTURE;
            beat_index = 0;
            actual_byte_count = 0;
            case_active = 1'b1;
            // Deliberately differs from the fixture length: mode 3 must use
            // the fixture's real length for metadata and payload generation.
            payload_length = 32'd17;
            pattern_select = `C2H_TEST_PATTERN_JPEG_FIXTURE;
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            timeout_count = 0;
            while (!frame_done && !frame_abort && (timeout_count < 4000000)) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (frame_abort) report_error("unexpected JPEG fixture frame abort");
            if (!frame_done) report_error("JPEG fixture frame completion timeout");
            if (actual_byte_count != (`C2H_TEST_JPEG_FIXTURE_LENGTH + 64)) begin
                report_error("JPEG fixture transfer length mismatch");
            end
            case_active = 1'b0;
            @(posedge clk);
            $display("[TB] JPEG fixture complete, beats=%0d", beat_index);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #4 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ready_lfsr <= 16'h1ace;
            axis_tready <= 1'b0;
        end else begin
            ready_lfsr <= {ready_lfsr[14:0],
                           ready_lfsr[15] ^ ready_lfsr[13] ^
                           ready_lfsr[12] ^ ready_lfsr[10]};
            axis_tready <= ready_lfsr[0] | ready_lfsr[3];
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            previous_stall <= 1'b0;
            stalled_data <= 128'd0;
            stalled_keep <= 16'd0;
            stalled_last <= 1'b0;
            previous_source_stall <= 1'b0;
            stalled_source_data <= 128'd0;
            stalled_source_keep <= 16'd0;
            stalled_source_last <= 1'b0;
        end else begin
            if (previous_stall) begin
                if (!axis_tvalid) report_error("TVALID dropped during backpressure");
                if (axis_tdata !== stalled_data) report_error("TDATA changed during backpressure");
                if (axis_tkeep !== stalled_keep) report_error("TKEEP changed during backpressure");
                if (axis_tlast !== stalled_last) report_error("TLAST changed during backpressure");
            end
            previous_stall <= axis_tvalid && !axis_tready;
            if (axis_tvalid && !axis_tready) begin
                stalled_data <= axis_tdata;
                stalled_keep <= axis_tkeep;
                stalled_last <= axis_tlast;
            end
            if (previous_source_stall) begin
                if (!source_tvalid) report_error("source TVALID dropped during backpressure");
                if (source_tdata !== stalled_source_data) report_error("source TDATA changed during backpressure");
                if (source_tkeep !== stalled_source_keep) report_error("source TKEEP changed during backpressure");
                if (source_tlast !== stalled_source_last) report_error("source TLAST changed during backpressure");
            end
            previous_source_stall <= source_tvalid && !source_tready;
            if (source_tvalid && !source_tready) begin
                stalled_source_data <= source_tdata;
                stalled_source_keep <= source_tkeep;
                stalled_source_last <= source_tlast;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && case_active && meta_valid && meta_ready &&
            (checked_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE)) begin
            if (meta_payload_length != `C2H_TEST_JPEG_FIXTURE_LENGTH)
                report_error("JPEG fixture metadata payload length mismatch");
            if (meta_width != `C2H_TEST_JPEG_FIXTURE_WIDTH)
                report_error("JPEG fixture metadata width mismatch");
            if (meta_height != `C2H_TEST_JPEG_FIXTURE_HEIGHT)
                report_error("JPEG fixture metadata height mismatch");
            if (meta_compression != 8'd1)
                report_error("JPEG fixture metadata compression mismatch");
        end
    end

    always @(posedge clk) begin
        if (rst_n && case_active && axis_tvalid && axis_tready) begin
            if (axis_tuser != 16'd0) report_error("TUSER must be zero");
            if (beat_index == 0) begin
                if (axis_tdata[31:0] != 32'h47504a41) report_error("frame magic mismatch");
                if (axis_tdata[47:32] != 16'd1) report_error("protocol version mismatch");
                if (axis_tdata[63:48] != 16'd64) report_error("header length mismatch");
                if (axis_tdata[127:96] != checked_payload_length) report_error("payload length field mismatch");
            end
            if (beat_index < 4) begin
                if (axis_tkeep != 16'hffff) report_error("header TKEEP mismatch");
                if (axis_tlast) report_error("TLAST asserted in header");
            end else begin
                payload_byte_index = (beat_index - 4) * 16;
                expected_keep = keep_mask(checked_payload_length - payload_byte_index);
                if (axis_tkeep != expected_keep) report_error("payload TKEEP mismatch");
                if (checked_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE) begin
                    if (axis_tdata !== expected_jpeg_fixture_beat(beat_index - 4))
                        report_error("JPEG fixture payload lane mismatch");
                end else begin
                    for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin
                        if (axis_tkeep[lane_index] &&
                            (axis_tdata[(lane_index * 8) +: 8] !=
                             ((payload_byte_index + lane_index) & 8'hff))) begin
                            report_error("payload byte mismatch");
                        end
                    end
                end
                if ((checked_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE) &&
                    ((payload_byte_index + 16) >= checked_payload_length) &&
                    (axis_tkeep != 16'h07ff)) begin
                    report_error("JPEG fixture final TKEEP mismatch");
                end
                if ((checked_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE) &&
                    ((payload_byte_index + 16) >= checked_payload_length) &&
                    (axis_tdata[127:88] !== 40'd0)) begin
                    report_error("JPEG fixture final unused lanes mismatch");
                end
                if (axis_tlast != ((payload_byte_index + 16) >= checked_payload_length)) begin
                    report_error("payload TLAST mismatch");
                end
            end
            for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin
                if (axis_tkeep[lane_index]) actual_byte_count = actual_byte_count + 1;
            end
            beat_index = beat_index + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        start = 1'b0;
        payload_length = 32'd1;
        pattern_select = 2'd0;
        axis_tready = 1'b0;
        ready_lfsr = 16'h1ace;
        case_active = 1'b0;
        checked_payload_length = 32'd0;
        checked_pattern = 2'd0;
        previous_stall = 1'b0;
        stalled_data = 128'd0;
        stalled_keep = 16'd0;
        stalled_last = 1'b0;
        previous_source_stall = 1'b0;
        stalled_source_data = 128'd0;
        stalled_source_keep = 16'd0;
        stalled_source_last = 1'b0;
        error_count = 0;
        beat_index = 0;
        payload_byte_index = 0;
        actual_byte_count = 0;
        timeout_count = 0;
        expected_keep = 16'd0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        run_length_case(32'd1);
        run_length_case(32'd15);
        run_length_case(32'd16);
        run_length_case(32'd17);
        run_length_case(32'd255);
        run_length_case(32'd4097);
        run_jpeg_fixture_case;
        if ($test$plusargs("MAX_CASES")) begin
            run_length_case(32'd16777215);
            run_length_case(32'd16777216);
        end

        if (error_count == 0) begin
            $display("[TB] RESULT: PASS - C2H header, payload, TKEEP, TLAST and backpressure");
        end else begin
            $display("[TB] RESULT: FAIL - %0d errors", error_count);
        end
        $finish;
    end

endmodule
