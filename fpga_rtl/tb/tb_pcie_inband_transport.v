`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

module tb_pcie_inband_transport;
    reg clk;
    reg rst_n;
    reg [127:0] src_tdata;
    reg [15:0] src_tkeep;
    reg src_tvalid;
    wire src_tready;
    reg src_tlast;
    wire meta_valid;
    wire meta_ready;
    wire [31:0] meta_sequence;
    wire [31:0] meta_length;
    wire [15:0] meta_width;
    wire [15:0] meta_height;
    wire [7:0] meta_pixel;
    wire [7:0] meta_compression;
    wire [7:0] meta_quality;
    wire [63:0] meta_timestamp;
    wire [31:0] meta_status;
    wire [31:0] meta_error;
    wire [15:0] meta_slot;
    wire [31:0] meta_crc;
    wire [127:0] payload_tdata;
    wire [15:0] payload_tkeep;
    wire payload_tvalid;
    wire payload_tready;
    wire payload_tlast;
    wire header_error;
    wire [31:0] adapter_error;
    wire [127:0] axis_tdata;
    wire [15:0] axis_tkeep;
    wire axis_tvalid;
    reg axis_tready;
    wire axis_tlast;
    wire frame_done;
    wire frame_abort;
    integer errors;
    integer output_beat;
    integer expected_beats;
    integer seed;
    integer timeout_count;
    reg [31:0] active_length;
    reg [31:0] active_sequence;
    reg [127:0] expected_data;
    reg [15:0] expected_keep;
    reg [127:0] held_data;
    reg [15:0] held_keep;
    reg held_last;
    reg previous_stall;
    integer lane;
    integer byte_offset;
    integer remaining;
    reg header_error_seen;

    always #4 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n) begin
            axis_tready <= 1'b0;
        end else begin
            axis_tready <= (($random(seed) & 7) != 0);
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            previous_stall <= 1'b0;
            held_data <= 128'd0;
            held_keep <= 16'd0;
            held_last <= 1'b0;
        end else begin
            if (previous_stall && (!axis_tvalid || axis_tdata !== held_data ||
                                   axis_tkeep !== held_keep || axis_tlast !== held_last)) begin
                $display("[TB] ERROR output tuple changed after stalled cycle");
                errors = errors + 1;
            end
            previous_stall <= axis_tvalid && !axis_tready;
            if (axis_tvalid && !axis_tready) begin
                held_data <= axis_tdata;
                held_keep <= axis_tkeep;
                held_last <= axis_tlast;
            end
        end
    end

    always @(posedge clk) begin
        if (header_error) header_error_seen <= 1'b1;
        if (axis_tvalid && axis_tready) begin
            expected_data = 128'd0;
            expected_keep = 16'hffff;
            case (output_beat)
                0: expected_data = {active_length, active_sequence, 16'd64,
                                    `PCIE_PROTOCOL_VERSION, `PCIE_FRAME_MAGIC};
                1: expected_data = {64'h0123456789abcdef, 8'h01, 8'd91,
                                    8'd1, 8'd2, 16'd720, 16'd1280};
                2: expected_data = {32'h89abcdef, 16'd0, 16'h0023,
                                    32'h55667788, 32'h11223344};
                3: expected_data = 128'd0;
                default: begin
                    byte_offset = (output_beat - 4) * 16;
                    for (lane = 0; lane < 16; lane = lane + 1) begin
                        expected_data[(lane * 8) +: 8] = (byte_offset + lane) & 8'hff;
                    end
                    remaining = active_length - byte_offset;
                    if (remaining < 16) begin
                        expected_keep = (16'h0001 << remaining) - 1'b1;
                    end
                end
            endcase
            if ((axis_tdata !== expected_data) || (axis_tkeep !== expected_keep)) begin
                $display("[TB] ERROR beat %0d data/keep mismatch", output_beat);
                errors = errors + 1;
            end
            if (axis_tlast !== (output_beat == expected_beats - 1)) begin
                $display("[TB] ERROR beat %0d TLAST mismatch", output_beat);
                errors = errors + 1;
            end
            output_beat = output_beat + 1;
        end
    end

    task reject_then_drain;
        begin
            header_error_seen = 1'b0;
            send_beat({32'd17, 32'd99, 16'd64, `PCIE_PROTOCOL_VERSION,
                       32'hdeadbeef}, 16'hffff, 1'b0);
            send_beat(128'd0, 16'hffff, 1'b0);
            send_beat(128'd0, 16'hffff, 1'b0);
            send_beat(128'd0, 16'hffff, 1'b0);
            send_beat(128'h55, 16'h0001, 1'b1);
            repeat (3) @(posedge clk);
            if (!header_error_seen) begin
                $display("[TB] ERROR malformed header was not reported");
                errors = errors + 1;
            end
        end
    endtask

    task reset_partial_header;
        begin
            send_beat({32'd17, 32'd88, 16'd64, `PCIE_PROTOCOL_VERSION,
                       `PCIE_FRAME_MAGIC}, 16'hffff, 1'b0);
            send_beat(128'h1234, 16'hffff, 1'b0);
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_beat;
        input [127:0] data_value;
        input [15:0] keep_value;
        input last_value;
        begin
            repeat (($random(seed) & 3)) @(posedge clk);
            src_tdata <= data_value;
            src_tkeep <= keep_value;
            src_tlast <= last_value;
            src_tvalid <= 1'b1;
            @(posedge clk);
            while (!src_tready) @(posedge clk);
            src_tvalid <= 1'b0;
            src_tlast <= 1'b0;
        end
    endtask

    task send_frame;
        input [31:0] length_value;
        input [31:0] sequence_value;
        integer offset;
        integer count;
        reg [127:0] data_value;
        reg [15:0] keep_value;
        begin
            active_length = length_value;
            active_sequence = sequence_value;
            output_beat = 0;
            expected_beats = 4 + ((length_value + 15) / 16);
            send_beat({length_value, sequence_value, 16'd64,
                       `PCIE_PROTOCOL_VERSION, `PCIE_FRAME_MAGIC}, 16'hffff, 1'b0);
            send_beat({64'h0123456789abcdef, 8'h01, 8'd91, 8'd1, 8'd2,
                       16'd720, 16'd1280}, 16'hffff, 1'b0);
            send_beat({32'h89abcdef, 16'd0, 16'h0023, 32'h55667788,
                       32'h11223344}, 16'hffff, 1'b0);
            send_beat(128'd0, 16'hffff, 1'b0);
            offset = 0;
            while (offset < length_value) begin
                data_value = 128'd0;
                count = length_value - offset;
                if (count > 16) count = 16;
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    data_value[(lane * 8) +: 8] = (offset + lane) & 8'hff;
                end
                keep_value = (count == 16) ? 16'hffff : ((16'h0001 << count) - 1'b1);
                send_beat(data_value, keep_value, (offset + count) == length_value);
                offset = offset + count;
            end
            timeout_count = 0;
            while (!frame_done && timeout_count < 1000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!frame_done || output_beat != expected_beats) begin
                $display("[TB] ERROR frame length %0d did not complete", length_value);
                errors = errors + 1;
            end
        end
    endtask

    pcie_inband_header_adapter u_adapter (
        .i_clk(clk), .i_rst_n(rst_n), .i_src_tdata(src_tdata),
        .i_src_tkeep(src_tkeep), .i_src_tvalid(src_tvalid),
        .o_src_tready(src_tready), .i_src_tlast(src_tlast),
        .o_meta_valid(meta_valid), .i_meta_ready(meta_ready),
        .o_meta_frame_sequence(meta_sequence), .o_meta_payload_length(meta_length),
        .o_meta_width(meta_width), .o_meta_height(meta_height),
        .o_meta_pixel_format(meta_pixel), .o_meta_compression(meta_compression),
        .o_meta_quality(meta_quality), .o_meta_timestamp_ns(meta_timestamp),
        .o_meta_status(meta_status), .o_meta_error_code(meta_error),
        .o_meta_slot_id(meta_slot), .o_meta_payload_crc32(meta_crc),
        .o_payload_tdata(payload_tdata), .o_payload_tkeep(payload_tkeep),
        .o_payload_tvalid(payload_tvalid), .i_payload_tready(payload_tready),
        .o_payload_tlast(payload_tlast), .o_header_error(header_error),
        .o_last_error(adapter_error), .o_busy()
    );

    c2h_frame_tx u_tx (
        .i_clk(clk), .i_rst_n(rst_n), .i_transport_enable(1'b1),
        .i_link_up(1'b1), .i_c2h_running(1'b1), .i_meta_valid(meta_valid),
        .o_meta_ready(meta_ready), .i_meta_frame_sequence(meta_sequence),
        .i_meta_payload_length(meta_length), .i_meta_width(meta_width),
        .i_meta_height(meta_height), .i_meta_pixel_format(meta_pixel),
        .i_meta_compression(meta_compression), .i_meta_quality(meta_quality),
        .i_meta_timestamp_ns(meta_timestamp), .i_meta_status(meta_status),
        .i_meta_error_code(meta_error), .i_meta_slot_id(meta_slot),
        .i_meta_payload_crc32(meta_crc), .i_src_tdata(payload_tdata),
        .i_src_tkeep(payload_tkeep), .i_src_tvalid(payload_tvalid),
        .o_src_tready(payload_tready), .i_src_tlast(payload_tlast),
        .o_axis_tdata(axis_tdata), .o_axis_tkeep(axis_tkeep), .o_axis_tuser(),
        .o_axis_tvalid(axis_tvalid), .i_axis_tready(axis_tready),
        .o_axis_tlast(axis_tlast), .o_tx_busy(), .o_transport_ready(),
        .o_active_slot_id(), .o_last_error(), .o_frame_accept(),
        .o_frame_done(frame_done), .o_frame_abort(frame_abort)
    );

    initial begin
        clk = 0; rst_n = 0; src_tdata = 0; src_tkeep = 0;
        src_tvalid = 0; src_tlast = 0; axis_tready = 0; errors = 0;
        header_error_seen = 0; seed = 32'h35760001;
        repeat (5) @(posedge clk); rst_n = 1;
        send_frame(1, 1); send_frame(15, 2); send_frame(16, 3); send_frame(17, 4);
        reject_then_drain();
        send_frame(17, 7);
        reset_partial_header();
        send_frame(17, 8);
        if ($test$plusargs("MAX_CASES")) begin
            send_frame(`PCIE_MAX_PAYLOAD - 1, 5);
            send_frame(`PCIE_MAX_PAYLOAD, 6);
        end
        if (errors == 0) $display("[TB] RESULT: PASS");
        else $display("[TB] RESULT: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #300000000;
        $display("[TB] ERROR global watchdog expired");
        $fatal(1);
    end
endmodule
