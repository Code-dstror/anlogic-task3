`timescale 1ns / 1ps

module csi2_raw10_rx_stream (
    input  wire        i_word_clk,
    input  wire        i_pixel_clk,
    input  wire        i_reset_n,
    input  wire [31:0] i_aligned_word,
    input  wire        i_aligned_valid,
    output wire [39:0] o_raw_data,
    output wire        o_raw_valid,
    input  wire        i_raw_ready,
    output wire        o_raw_sof,
    output wire        o_raw_eol,
    output wire        o_frame_abort,
    output wire [3:0]  o_error_code,
    output reg  [31:0] o_header_ecc_error_count,
    output reg  [31:0] o_payload_crc_error_count,
    output reg  [31:0] o_overflow_error_count,
    output reg  [31:0] o_length_error_count
    ,output wire       o_wait_for_sync
    ,output wire       o_packet_done
);
    wire [39:0] source_data;
    wire source_valid;
    wire source_sof;
    wire source_eol;
    wire source_abort;
    wire [3:0] source_error;
    wire fifo_source_ready;
    wire unused_ecc_error;
    wire unused_crc_error;
    wire unused_length_error;
    wire [46:0] fifo_read_data;
    wire fifo_read_valid;
    reg drain_frame;
    reg [1:0] word_reset_sync;
    reg [1:0] pixel_reset_sync;
    wire word_reset_n = word_reset_sync[1];
    wire pixel_reset_n = pixel_reset_sync[1];

    // One asynchronous source reset feeds two unrelated clocks. Each domain
    // asserts immediately and releases only after two local clock edges.
    always @(posedge i_word_clk or negedge i_reset_n) begin
        if (!i_reset_n)
            word_reset_sync <= 2'b00;
        else
            word_reset_sync <= {word_reset_sync[0], 1'b1};
    end

    always @(posedge i_pixel_clk or negedge i_reset_n) begin
        if (!i_reset_n)
            pixel_reset_sync <= 2'b00;
        else
            pixel_reset_sync <= {pixel_reset_sync[0], 1'b1};
    end

    csi2_raw10_word_core u_word_core (
        .i_clk(i_word_clk), .i_reset_n(word_reset_n),
        .i_word(i_aligned_word), .i_word_valid(i_aligned_valid),
        .i_sink_ready(fifo_source_ready),
        .o_data(source_data), .o_valid(source_valid), .o_sof(source_sof),
        .o_eol(source_eol), .o_abort(source_abort),
        .o_error_code(source_error),
        .o_header_ecc_error(unused_ecc_error),
        .o_payload_crc_error(unused_crc_error),
        .o_length_error(unused_length_error),
        .o_wait_for_sync(o_wait_for_sync),
        .o_packet_done(o_packet_done)
    );

    csi2_async_event_fifo u_event_fifo (
        .i_write_clk(i_word_clk), .i_reset_n(i_reset_n),
        .i_write_data({source_error, source_abort, source_eol, source_sof, source_data}),
        .i_write_valid(source_valid), .o_write_ready(fifo_source_ready),
        .i_read_clk(i_pixel_clk),
        .o_read_data(fifo_read_data), .o_read_valid(fifo_read_valid),
        .i_read_ready(i_raw_ready ||
                      (drain_frame && !fifo_read_data[42] && !fifo_read_data[40]))
    );

    assign o_raw_data = fifo_read_data[39:0];
    assign o_raw_sof = fifo_read_data[40];
    assign o_raw_eol = fifo_read_data[41];
    assign o_frame_abort = fifo_read_data[42];
    assign o_error_code = fifo_read_data[46:43];
    assign o_raw_valid = fifo_read_valid &&
                         (!drain_frame || fifo_read_data[40] || fifo_read_data[42]);

    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if (!pixel_reset_n) begin
            drain_frame <= 1'b0;
            o_header_ecc_error_count <= 32'd0;
            o_payload_crc_error_count <= 32'd0;
            o_overflow_error_count <= 32'd0;
            o_length_error_count <= 32'd0;
        end else if (o_raw_valid && i_raw_ready) begin
            if (o_frame_abort) begin
                drain_frame <= 1'b1;
                case (o_error_code)
                    4'd1: o_header_ecc_error_count <= o_header_ecc_error_count + 1'b1;
                    4'd2: o_payload_crc_error_count <= o_payload_crc_error_count + 1'b1;
                    4'd3: o_overflow_error_count <= o_overflow_error_count + 1'b1;
                    4'd4: o_length_error_count <= o_length_error_count + 1'b1;
                    default: o_length_error_count <= o_length_error_count + 1'b1;
                endcase
            end else if (o_raw_sof) begin
                drain_frame <= 1'b0;
            end
        end
    end
endmodule
