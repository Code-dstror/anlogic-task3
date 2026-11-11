`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// Freeze one actual PIX admission into SOURCE metadata for the ordered record.
module frame_record_extension_builder #(
    parameter integer NEUTRAL_STATS_ENABLE = 0,
    parameter integer OBSERVATION_WIDTH = 320,
    parameter integer OBSERVATION_HEIGHT = 180,
    parameter integer SEPARATE_DATA_RESET = 0
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire s_begin_valid,
    output wire o_begin_ready,
    input wire [31:0] i_source_session,
    input wire [31:0] i_source_epoch,
    input wire [31:0] i_source_sequence,
    input wire [7:0] i_source_camera,
    input wire [7:0] i_source_kind,
    input wire [7:0] i_source_format,
    input wire [7:0] i_exposure_role,
    input wire i_exposure_valid,
    input wire [31:0] i_actual_exposure,
    input wire [31:0] i_exposure_group,
    input wire i_gain_valid,
    input wire [31:0] i_actual_gain,
    input wire i_calibration_valid,
    input wire [31:0] i_calibration_id,
    input wire [7:0] i_time_quality,
    input wire i_pair_valid,
    input wire [63:0] i_pair_id,
    input wire i_job_valid,
    input wire [63:0] i_job_id,
    input wire i_write_tag_valid,
    input wire [63:0] i_write_tag,
    input wire i_qualified,
    input wire [7:0] i_processing_member,
    input wire [7:0] i_processing_mode,
    input wire [15:0] i_record_flags,
    input wire s_stats_valid,
    output wire o_stats_ready,
    input wire [159:0] s_stats_context,
    input wire [183:0] s_statistics,
    output wire m_extension_valid,
    input wire m_extension_ready,
    output reg [1023:0] m_extension_data,
    output reg [31:0] o_stale_count,
    output reg [31:0] o_error_count,
    output wire o_input_fault,
    input wire i_data_reset_n
);
    localparam integer EXTENSION_OFFSET = 64;
    localparam integer OBSERVATION_PIXELS = OBSERVATION_WIDTH * OBSERVATION_HEIGHT;
    localparam integer MAXIMUM_SUM_Y = OBSERVATION_PIXELS * 255;
    localparam [1:0] IDLE = 2'd0, WAIT_STATS = 2'd1, PRESENT = 2'd2, FAULT = 2'd3;
    reg [1:0] state, state_next;
    reg input_fault;
    reg [1023:0] begin_extension;
    reg [1023:0] payload_data;
    reg [15:0] begin_flags;
    wire begin_fire = s_begin_valid && o_begin_ready;
    wire stats_fire = s_stats_valid && o_stats_ready;
    wire extension_fire = m_extension_valid && m_extension_ready;
    wire source_shape_valid = i_source_session != 0 && i_source_camera <= 1 &&
        i_source_kind <= `PCIE_RECORD_V2_SOURCE_PHYSICAL &&
        (i_source_format == `PCIE_RECORD_V2_FORMAT_RAW10 || i_source_format == `PCIE_RECORD_V2_FORMAT_RAW14) &&
        i_exposure_role <= `PCIE_RECORD_V2_ROLE_SHORT &&
        i_time_quality <= `PCIE_RECORD_V2_TIME_COMMON_FPGA_COUNTER_NS &&
        i_processing_member <= 1 && i_record_flags[15:3] == 0 &&
        (!i_pair_valid || i_pair_id != 0);
    wire [159:0] expected_context = {
        16'd1, 16'd0, 8'd1,
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_FORMAT-EXTENSION_OFFSET)*8 +: 8],
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_KIND-EXTENSION_OFFSET)*8 +: 8],
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_CAMERA-EXTENSION_OFFSET)*8 +: 8],
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_SEQUENCE-EXTENSION_OFFSET)*8 +: 32],
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_EPOCH-EXTENSION_OFFSET)*8 +: 32],
        payload_data[(`PCIE_RECORD_V2_OFFSET_SOURCE_SESSION-EXTENSION_OFFSET)*8 +: 32]
    };
    wire context_matches = s_stats_context == expected_context;
    wire statistics_complete =
        s_statistics[15:0] == OBSERVATION_PIXELS && s_statistics[31:16] == OBSERVATION_PIXELS &&
        s_statistics[143:128] == OBSERVATION_WIDTH && s_statistics[159:144] == OBSERVATION_HEIGHT &&
        s_statistics[167:160] == 1 && s_statistics[175:168] == 0 && s_statistics[183:176] == 1 &&
        s_statistics[103:96] <= s_statistics[111:104] &&
        s_statistics[79:64] <= OBSERVATION_PIXELS && s_statistics[95:80] <= OBSERVATION_PIXELS &&
        s_statistics[63:32] <= MAXIMUM_SUM_Y;

    generate if (NEUTRAL_STATS_ENABLE < 0 || NEUTRAL_STATS_ENABLE > 1 ||
                 OBSERVATION_WIDTH < 1 || OBSERVATION_WIDTH > 65535 ||
                 OBSERVATION_HEIGHT < 1 || OBSERVATION_HEIGHT > 65535 ||
                 OBSERVATION_PIXELS < 1 || OBSERVATION_PIXELS > 65535) begin : invalid_grid
        FRAME_RECORD_BUILDER_REQUIRES_FIXED_LEGAL_OBSERVATION_GRID invalid_configuration();
    end endgenerate
    // The rising-edge copy qualifies transfers sampled after local ASR release.
    wire data_reset_n = SEPARATE_DATA_RESET != 0 ? i_data_reset_n : i_rst_n;
    assign o_begin_ready = data_reset_n && state == IDLE;
    assign o_stats_ready = data_reset_n;
    assign m_extension_valid = data_reset_n && state == PRESENT;
    assign o_input_fault = input_fault;
    // A published STATS record has accepted a matching context. Reuse the
    // frozen SOURCE; keep the original full input equality check above.
    // Complete statistics have already proved these exact fixed fields.
    // The bounded observation grid proves every legal sum fits 24 bits.
    localparam [15:0] GRID_PIXELS=OBSERVATION_PIXELS;
    localparam [15:0] GRID_WIDTH=OBSERVATION_WIDTH,GRID_HEIGHT=OBSERVATION_HEIGHT;
    wire qualified_statistics=payload_data[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-EXTENSION_OFFSET)*8+`PCIE_RECORD_V2_FLAG_NEUTRAL_STATS];
    always @* begin
        m_extension_data=payload_data;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_CONTEXT-EXTENSION_OFFSET)*8 +: 160]=NEUTRAL_STATS_ENABLE!=0 ? expected_context : 160'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-EXTENSION_OFFSET)*8+`PCIE_RECORD_V2_FLAG_NEUTRAL_CONTEXT]=NEUTRAL_STATS_ENABLE!=0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8 +: 16]=qualified_statistics ? GRID_PIXELS : 16'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+16 +: 16]=qualified_statistics ? GRID_PIXELS : 16'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+56 +: 8]=8'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+128 +: 16]=qualified_statistics ? GRID_WIDTH : 16'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+144 +: 16]=qualified_statistics ? GRID_HEIGHT : 16'd0;
        m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+160 +: 24]=qualified_statistics ? 24'h010001 : 24'd0;
    end

    // Canonical unknown values start at zero; only explicit caller flags enable fields.
    always @(*) begin
        begin_extension = 0;
        begin_flags = 0;
        begin_flags[`PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY] = 1;
        begin_flags[`PCIE_RECORD_V2_FLAG_EXPOSURE] = i_exposure_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_GAIN] = i_gain_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_CALIBRATION] = i_calibration_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_TIME] = i_time_quality != `PCIE_RECORD_V2_TIME_UNKNOWN;
        begin_flags[`PCIE_RECORD_V2_FLAG_PAIR] = i_pair_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_JOB] = i_job_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_WRITE_TAG] = i_write_tag_valid;
        begin_flags[`PCIE_RECORD_V2_FLAG_QUALIFIED] = i_qualified;
        begin_flags[`PCIE_RECORD_V2_FLAG_HDR_PRODUCT] = i_record_flags[`PCIE_RECORD_V2_PRODUCT_HDR_MERGED];
        begin_extension[(`PCIE_RECORD_V2_OFFSET_EXTENSION_MAGIC-EXTENSION_OFFSET)*8 +: 32] = `PCIE_RECORD_V2_EXTENSION_MAGIC;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SCHEMA_VERSION-EXTENSION_OFFSET)*8 +: 16] = `PCIE_RECORD_V2_SCHEMA_VERSION;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-EXTENSION_OFFSET)*8 +: 16] = begin_flags;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_SESSION-EXTENSION_OFFSET)*8 +: 32] = i_source_session;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_EPOCH-EXTENSION_OFFSET)*8 +: 32] = i_source_epoch;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_SEQUENCE-EXTENSION_OFFSET)*8 +: 32] = i_source_sequence;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_CAMERA-EXTENSION_OFFSET)*8 +: 8] = i_source_camera;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_KIND-EXTENSION_OFFSET)*8 +: 8] = i_source_kind;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_SOURCE_FORMAT-EXTENSION_OFFSET)*8 +: 8] = i_source_format;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_EXPOSURE_ROLE-EXTENSION_OFFSET)*8 +: 8] = i_exposure_role;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_ACTUAL_EXPOSURE-EXTENSION_OFFSET)*8 +: 32] = i_exposure_valid ? i_actual_exposure : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_EXPOSURE_GROUP-EXTENSION_OFFSET)*8 +: 32] = i_exposure_valid ? i_exposure_group : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_ACTUAL_GAIN-EXTENSION_OFFSET)*8 +: 32] = i_gain_valid ? i_actual_gain : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_CALIBRATION_ID-EXTENSION_OFFSET)*8 +: 32] = i_calibration_valid ? i_calibration_id : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_PAIR_ID-EXTENSION_OFFSET)*8 +: 64] = i_pair_valid ? i_pair_id : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_JOB_ID-EXTENSION_OFFSET)*8 +: 64] = i_job_valid ? i_job_id : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_WRITE_TAG-EXTENSION_OFFSET)*8 +: 64] = i_write_tag_valid ? i_write_tag : 0;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_PROCESSING_MEMBER-EXTENSION_OFFSET)*8 +: 8] = i_processing_member;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_PROCESSING_MODE-EXTENSION_OFFSET)*8 +: 8] = i_processing_mode;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_TIME_QUALITY-EXTENSION_OFFSET)*8 +: 8] = i_time_quality;
        begin_extension[(`PCIE_RECORD_V2_OFFSET_RECORD_FLAGS-EXTENSION_OFFSET)*8 +: 16] = i_record_flags;
    end

    always @(*) begin
        state_next = state;
        case (state)
            IDLE: if (begin_fire) begin
                if (!source_shape_valid) state_next = FAULT;
                else state_next = NEUTRAL_STATS_ENABLE ? WAIT_STATS : PRESENT;
            end
            WAIT_STATS: if (stats_fire && context_matches) state_next = PRESENT;
            PRESENT: if (extension_fire) state_next = IDLE;
            FAULT: state_next = FAULT;
            default: state_next = FAULT;
        endcase
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin state <= IDLE;input_fault <= 0;end
        else begin
            state <= state_next;
            // Same transition edge as the former decoder, one stable PIX Q.
            // WAIT_STATS01 -> PRESENT10 cannot publish a transient FAULT11.
            input_fault <= state_next == FAULT;
        end
    end
    // Payload is visible only in PRESENT. Pre-sample while its owner is idle
    // or waiting, so the wide bank does not depend on reset, handshake or
    // SOURCE validation. The actual transition edge still captures the exact
    // accepted inputs, and PRESENT (including a stall) never writes the bank.
    // WAIT_STATS changes only neutral fields; expected_context therefore keeps
    // the admitted SOURCE identity even while stale statistics are sampled.
    always @(posedge i_clk) begin
        if (state == IDLE)
            payload_data <= begin_extension;
        else if (state == WAIT_STATS) begin
            payload_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+32 +: 24] <= statistics_complete ? s_statistics[55:32] : 24'd0;
            payload_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-EXTENSION_OFFSET)*8+64 +: 64] <= statistics_complete ? s_statistics[127:64] : 64'd0;
            payload_data[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-EXTENSION_OFFSET)*8+`PCIE_RECORD_V2_FLAG_NEUTRAL_STATS] <= statistics_complete;
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_stale_count <= 0;
            o_error_count <= 0;
        end else begin
            if (begin_fire) begin
                if (!source_shape_valid && !(&o_error_count))
                    o_error_count <= o_error_count + 1'b1;
            end
            if (stats_fire) begin
                if (state == WAIT_STATS && context_matches) begin
                    if (!statistics_complete) begin
                        // The true negative/incomplete result closes waiting without inventing statistics.
                        if (!(&o_error_count)) o_error_count <= o_error_count + 1'b1;
                    end
                end else if (!(&o_stale_count)) o_stale_count <= o_stale_count + 1'b1;
            end
        end
    end
endmodule
