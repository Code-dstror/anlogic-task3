`timescale 1ns/1ps
// Reserve existing sparse producers before the first native Gaussian transfer.
// frame_context is borrowed from the caller until o_quiet; no identity copy.
module preprocess_live_lane_owner (
    input wire clk, rst_n,
    input wire begin_valid,
    output wire begin_ready,
    input wire [159:0] frame_context,
    input wire [1:0] begin_features,
    input wire lane_start_ready, pyramid_valid, lane_valid, join_begin_ready,
    output wire lane_start_valid,
    output wire [3:0] frame_features,
    input wire product_begin, extension_fire,
    input wire source_fire, source_ok,
    input wire foreground_done, foreground_error, foreground_quiet,
    input wire abort_frame,
    input wire lane_complete, lane_error,
    input wire [159:0] lane_event_context,
    output wire lane_source_error,
    output wire tap_observe,
    output wire discard_records,
    output wire product_owned,
    output wire terminal_valid, terminal_error,
    output wire o_quiet,
    output reg o_fault
);
    reg owned, product_seen, terminal_sent;
    reg source_seen, source_failed, foreground_seen, foreground_failed;
    reg lane_seen, lane_failed, abort_seen;
    reg [1:0] features;
    wire begin_fire = begin_valid && begin_ready;
    wire lane_event = (lane_complete || lane_error) && lane_event_context == frame_context;
    wire finished = source_seen && foreground_seen && lane_seen;
    wire no_product_done = owned && !product_seen && !product_begin && finished;
    wire release_owner = (product_seen && extension_fire) || no_product_done;

    assign begin_ready = rst_n && !owned && !o_fault && lane_start_ready &&
                         !pyramid_valid && !lane_valid && join_begin_ready;
    assign lane_start_valid = begin_fire && begin_features[0];
    assign frame_features = {2'd0, features};
    assign lane_source_error = owned && features[0] && !lane_seen &&
                               (abort_frame || abort_seen || foreground_error || source_failed ||
                                (source_fire && !source_ok));
    assign tap_observe = owned && features[0] && !lane_seen && !lane_source_error;
    assign product_owned = product_seen;
    assign discard_records = no_product_done;
    assign terminal_valid = owned && product_seen && finished && !terminal_sent;
    assign terminal_error = source_failed || foreground_failed || lane_failed || abort_seen;
    assign o_quiet = !owned;

    always @(posedge clk) begin
        if (!rst_n) begin
            owned <= 0; product_seen <= 0; terminal_sent <= 0;
            source_seen <= 0; source_failed <= 0;
            foreground_seen <= 0; foreground_failed <= 0;
            lane_seen <= 0; lane_failed <= 0; abort_seen <= 0;
            features <= 0; o_fault <= 0;
        end else begin
            if (owned) begin
                if (source_fire) begin source_seen <= 1; source_failed <= !source_ok; end
                if (foreground_done || ((abort_seen || abort_frame || foreground_failed ||
                                         foreground_error || source_failed) && foreground_quiet))
                    foreground_seen <= 1;
                if (foreground_error) foreground_failed <= 1;
                if (abort_frame) abort_seen <= 1;
                if (lane_event) begin lane_seen <= 1; lane_failed <= lane_error; end
                if (product_begin) product_seen <= 1;
                if (terminal_valid) terminal_sent <= 1;
                if ((lane_complete || lane_error) && lane_event_context != frame_context) o_fault <= 1;
            end
            if (product_begin && !owned) o_fault <= 1;
            if (release_owner) begin owned <= 0; product_seen <= 0; end
            if (begin_fire) begin
                owned <= 1; product_seen <= 0; terminal_sent <= 0;
                source_seen <= 0; source_failed <= 0;
                foreground_seen <= 0; foreground_failed <= 0;
                lane_seen <= !begin_features[0]; lane_failed <= 0; abort_seen <= 0;
                features <= begin_features;
                if (begin_features[1] && !begin_features[0]) o_fault <= 1;
            end
        end
    end
endmodule
