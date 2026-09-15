`timescale 1ns / 1ps
module c2h_inband_test_source (
    input wire i_clk, input wire i_rst_n, input wire i_start,
    input wire [31:0] i_payload_length, input wire [1:0] i_pattern_select,
    output wire o_busy, output wire [31:0] o_frame_sequence,
    output wire [127:0] o_src_tdata, output wire [15:0] o_src_tkeep,
    output wire o_src_tvalid, input wire i_src_tready, output wire o_src_tlast
);
    wire source_busy, meta_valid, meta_ready, payload_tvalid, payload_tready, payload_tlast;
    wire [31:0] meta_payload_length, meta_status, meta_error_code, meta_payload_crc32;
    wire [15:0] meta_width, meta_height, meta_slot_id, payload_tkeep;
    wire [7:0] meta_pixel_format, meta_compression, meta_quality;
    wire [63:0] meta_timestamp_ns;
    wire [127:0] payload_tdata;
    wire formatter_busy;
    assign o_busy = source_busy || formatter_busy;
    c2h_test_source u_c2h_test_source (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_start(i_start),
        .i_payload_length(i_payload_length), .i_pattern_select(i_pattern_select),
        .o_busy(source_busy), .o_meta_valid(meta_valid), .i_meta_ready(meta_ready),
        .o_meta_frame_sequence(o_frame_sequence), .o_meta_payload_length(meta_payload_length),
        .o_meta_width(meta_width), .o_meta_height(meta_height),
        .o_meta_pixel_format(meta_pixel_format), .o_meta_compression(meta_compression),
        .o_meta_quality(meta_quality), .o_meta_timestamp_ns(meta_timestamp_ns),
        .o_meta_status(meta_status), .o_meta_error_code(meta_error_code),
        .o_meta_slot_id(meta_slot_id), .o_meta_payload_crc32(meta_payload_crc32),
        .o_src_tdata(payload_tdata), .o_src_tkeep(payload_tkeep),
        .o_src_tvalid(payload_tvalid), .i_src_tready(payload_tready),
        .o_src_tlast(payload_tlast)
    );
    c2h_frame_tx u_record_formatter (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_transport_enable(1'b1),
        .i_link_up(1'b1), .i_c2h_running(1'b1), .i_meta_valid(meta_valid),
        .o_meta_ready(meta_ready), .i_meta_frame_sequence(o_frame_sequence),
        .i_meta_payload_length(meta_payload_length), .i_meta_width(meta_width),
        .i_meta_height(meta_height), .i_meta_pixel_format(meta_pixel_format),
        .i_meta_compression(meta_compression), .i_meta_quality(meta_quality),
        .i_meta_timestamp_ns(meta_timestamp_ns), .i_meta_status(meta_status),
        .i_meta_error_code(meta_error_code), .i_meta_slot_id(meta_slot_id),
        .i_meta_payload_crc32(meta_payload_crc32), .i_src_tdata(payload_tdata),
        .i_src_tkeep(payload_tkeep), .i_src_tvalid(payload_tvalid),
        .o_src_tready(payload_tready), .i_src_tlast(payload_tlast),
        .o_axis_tdata(o_src_tdata), .o_axis_tkeep(o_src_tkeep), .o_axis_tuser(),
        .o_axis_tvalid(o_src_tvalid), .i_axis_tready(i_src_tready),
        .o_axis_tlast(o_src_tlast), .o_tx_busy(formatter_busy),
        .o_transport_ready(), .o_active_slot_id(), .o_last_error(),
        .o_frame_accept(), .o_frame_done(), .o_frame_abort()
    );
endmodule
