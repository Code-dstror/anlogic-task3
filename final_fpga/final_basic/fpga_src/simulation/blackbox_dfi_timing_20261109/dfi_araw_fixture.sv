`timescale 1ns/1ps

package dfi_araw_oracle;
    `include "araw_oracle_fields.svh"

    localparam logic [15:0] WIDTH = 16'd8, HEIGHT = 16'd2;
    localparam logic [31:0] PAYLOAD_BYTES = 32'd20;
    localparam logic [31:0] RECORD_BYTES = ARAW_HEADER_BYTES + PAYLOAD_BYTES;
    localparam int HEADER_BEATS = ARAW_HEADER_BYTES / 16;
    localparam int RECORD_BEATS = HEADER_BEATS + 2;

    typedef struct packed {
        logic [31:0] seq_no, session_no, epoch;
        logic camera;
        logic [1:0] bayer;
        logic time_valid;
        logic [63:0] capture_ns, job_id;
    } descriptor_t;

    typedef logic [159:0] payload_t;

    typedef struct packed {
        logic [127:0] data;
        logic [15:0] keep;
        logic last;
    } axis_t;

    function automatic descriptor_t descriptor(input logic [31:0] seq_no, input bit camera);
        descriptor_t value;
        value.seq_no = seq_no;
        value.session_no = 32'habc1_682f;
        value.epoch = 32'h0000_013d;
        value.camera = camera;
        value.bayer = camera ? 2'd2 : 2'd3;
        value.time_valid = 1;
        value.capture_ns = {32'h129a_574b, seq_no};
        value.job_id = {32'h582c_f36e, seq_no};
        return value;
    endfunction

    function automatic axis_t payload_beat(input payload_t payload, input int index);
        axis_t beat;
        if (index == 0) beat = '{payload[127:0], 16'hffff, 1'b0};
        else beat = '{{96'ha0b9_8263_6445_2607_8675_3423, payload[159:128]}, 16'h000f, 1'b1};
        return beat;
    endfunction

    function automatic axis_t record_beat(input descriptor_t desc, input payload_t payload, input int index);
        logic [ARAW_HEADER_BYTES*8-1:0] header;
        axis_t beat;
        if (index >= HEADER_BEATS) return payload_beat(payload, index - HEADER_BEATS);

        header = '0;
        header[ARAW_MAGIC_LO+:ARAW_MAGIC_BITS] = ARAW_MAGIC;
        header[ARAW_VERSION_LO+:ARAW_VERSION_BITS] = ARAW_VERSION;
        header[ARAW_HEADER_BYTES_LO+:ARAW_HEADER_BYTES_BITS] = ARAW_HEADER_BYTES;
        header[ARAW_PAYLOAD_BYTES_LO+:ARAW_PAYLOAD_BYTES_BITS] = PAYLOAD_BYTES;
        header[ARAW_WIDTH_LO+:ARAW_WIDTH_BITS] = WIDTH;
        header[ARAW_HEIGHT_LO+:ARAW_HEIGHT_BITS] = HEIGHT;
        header[ARAW_SOURCE_SEQUENCE_LO+:ARAW_SOURCE_SEQUENCE_BITS] = desc.seq_no;
        header[ARAW_SOURCE_SESSION_LO+:ARAW_SOURCE_SESSION_BITS] = desc.session_no;
        header[ARAW_MODE_EPOCH_LO+:ARAW_MODE_EPOCH_BITS] = desc.epoch;
        header[ARAW_CAMERA_LO+:ARAW_CAMERA_BITS] = desc.camera;
        header[ARAW_FORMAT_LO+:ARAW_FORMAT_BITS] = ARAW_FORMAT_RAW10;
        header[ARAW_BAYER_PHASE_LO+:ARAW_BAYER_PHASE_BITS] = desc.bayer;
        header[ARAW_FLAGS_LO+:ARAW_FLAGS_BITS] = desc.time_valid ? ARAW_TIMESTAMP_FLAG : 0;
        header[ARAW_CAPTURE_TIME_NS_LO+:ARAW_CAPTURE_TIME_NS_BITS] = desc.capture_ns;
        header[ARAW_JOB_ID_LO+:ARAW_JOB_ID_BITS] = desc.job_id;
        beat = '{header[index*128+:128], 16'hffff, 1'b0};
        return beat;
    endfunction

    function automatic bit axis_matches(input axis_t actual, expected);
        if ({actual.keep, actual.last} !== {expected.keep, expected.last}) return 0;
        for (int lane = 0; lane < 16; lane++)
            if (expected.keep[lane] && actual.data[lane*8+:8] !== expected.data[lane*8+:8]) return 0;
        return 1;
    endfunction
endpackage

module dfi_araw_ports import dfi_araw_oracle::*; (
    input wire clk, cold_n,
    output wire state_n, data_n,
    input wire descriptor_t desc,
    input wire start_valid,
    output wire start_ready,
    input wire axis_t payload,
    input wire payload_valid,
    output wire payload_ready,
    output axis_t record_data,
    output wire record_valid,
    input wire record_ready,
    output wire done, drained
);
    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(1)) reset_dut (
        .i_clk(clk), .i_async_rst_n(cold_n), .o_rst_n(state_n), .o_data_rst_n(data_n)
    );

    raw_video_record_formatter #(.SEPARATE_DATA_RESET(1)) formatter (
        .i_clk(clk), .i_rst_n(state_n), .i_data_reset_n(data_n),
        .i_start_valid(start_valid), .o_start_ready(start_ready), .i_abort(1'b0), .o_drained(drained),
        .i_payload_bytes(PAYLOAD_BYTES), .i_width(WIDTH), .i_height(HEIGHT),
        .i_sequence(desc.seq_no), .i_session(desc.session_no), .i_epoch(desc.epoch),
        .i_camera(desc.camera), .i_bayer_phase(desc.bayer), .i_time_valid(desc.time_valid),
        .i_capture_time_ns(desc.capture_ns), .i_job_id(desc.job_id),
        .s_data(payload.data), .s_keep(payload.keep), .s_valid(payload_valid), .s_last(payload.last), .s_ready(payload_ready),
        .m_data(record_data.data), .m_keep(record_data.keep), .m_valid(record_valid),
        .m_last(record_data.last), .m_ready(record_ready), .o_done(done)
    );
endmodule
