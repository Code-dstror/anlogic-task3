`timescale 1ns / 1ps

// Pixel-domain identity for each accepted whole-frame native job. No payload copy.
module native_frame_descriptor (
    input wire i_clk, i_rst_n,
    input wire i_native_valid, i_native_ready, i_native_sof,
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id,
    input wire [7:0] i_format,
    input wire [15:0] i_width, i_height,
    input wire [31:0] i_sample_count,
    input wire [63:0] i_timestamp_ns,
    output wire [31:0] o_next_sequence,
    output reg [31:0] o_frame_sequence,
    output reg o_descriptor_valid,
    output reg [31:0] o_session_id, o_mode_epoch,
    output reg o_camera_id,
    output reg [7:0] o_format,
    output reg [15:0] o_width, o_height,
    output reg [31:0] o_sample_count,
    output reg [63:0] o_timestamp_ns, o_job_handle
);
    reg [31:0] sequence_counter;
    wire [31:0] geometry = i_width * i_height;
    assign o_next_sequence = sequence_counter + 32'd1;
    // Even an invalid descriptor consumes a sequence: dropped captures stay visible.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            sequence_counter <= 0; o_frame_sequence <= 0; o_descriptor_valid <= 0;
            o_session_id <= 0; o_mode_epoch <= 0; o_camera_id <= 0; o_format <= 0;
            o_width <= 0; o_height <= 0; o_sample_count <= 0;
            o_timestamp_ns <= 0; o_job_handle <= 0;
        end else if (i_native_valid && i_native_ready && i_native_sof) begin
            sequence_counter <= o_next_sequence; o_frame_sequence <= o_next_sequence;
            o_session_id <= i_session_id; o_mode_epoch <= i_mode_epoch;
            o_camera_id <= i_camera_id; o_format <= i_format;
            o_width <= i_width; o_height <= i_height; o_sample_count <= i_sample_count;
            o_timestamp_ns <= i_timestamp_ns; o_job_handle <= {i_session_id,o_next_sequence};
            o_descriptor_valid <= i_width != 0 && i_height != 0 &&
                                  i_sample_count == geometry && (i_format == 1 || i_format == 2);
        end
    end
endmodule
