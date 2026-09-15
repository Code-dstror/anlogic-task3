`timescale 1ns / 1ps

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
    reg previous_stall;
    reg [127:0] stalled_data;
    reg [15:0] stalled_keep;
    reg stalled_last;
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
                for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1) begin
                    if (axis_tkeep[lane_index] &&
                        (axis_tdata[(lane_index * 8) +: 8] !=
                         ((payload_byte_index + lane_index) & 8'hff))) begin
                        report_error("payload byte mismatch");
                    end
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
        previous_stall = 1'b0;
        stalled_data = 128'd0;
        stalled_keep = 16'd0;
        stalled_last = 1'b0;
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
