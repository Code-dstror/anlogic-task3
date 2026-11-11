// Fixed schema1 four-strip composition of the existing F22 and F23 services.
// The owner starts this service before accepting native Gaussian source SOF.
module preprocess_lane_tap4 (
    input wire clk, rst_n, cancel,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width, start_height,
    input wire [159:0] start_context,
    input wire [10:0] threshold, gx_min,
    input wire [1:0] ratio_shift, direction_sign,
    input wire [19:0] min_count,
    input wire [3:0] min_paired_strips,
    input wire [51:0] strip_y_begin, strip_y_end, roi_left, roi_split, roi_right,
    input wire s_valid,
    output wire s_ready,
    input wire s_window_valid,
    input wire [287:0] s_window,
    input wire [31:0] s_filtered_y,
    input wire [3:0] s_keep,
    input wire s_sof, s_eol, source_error,
    output wire frame_complete, frame_error,
    output wire [7:0] frame_error_code,
    output wire [159:0] frame_event_context,
    output wire pyramid_valid,
    input wire pyramid_ready,
    output wire [683:0] pyramid_data,
    output wire lane_valid,
    input wire lane_ready,
    output wire [1355:0] lane_data,
    output wire [31:0] pyramid_drops, lane_drops, native_stalls,
    output wire [31:0] lane_finished, lane_failed
);
    wire low_valid;
    wire [220:0] low_metadata;
    wire [43:0] low_gx, low_gy, low_magnitude;

    preprocess_multiscale4 u_pyramid (
        .clk(clk), .rst_n(rst_n), .cancel(cancel),
        .start_valid(start_valid), .start_ready(start_ready),
        .start_width(start_width), .start_height(start_height),
        .start_threshold(threshold), .start_context(start_context),
        .s_valid(s_valid), .s_ready(s_ready), .s_window_valid(s_window_valid),
        .s_window(s_window), .s_filtered_y(s_filtered_y), .s_keep(s_keep),
        .s_sof(s_sof), .s_eol(s_eol), .source_error(source_error),
        .record_valid(pyramid_valid), .record_ready(pyramid_ready), .record_data(pyramid_data),
        .frame_complete(frame_complete), .frame_error(frame_error),
        .frame_error_code(frame_error_code), .frame_event_context(frame_event_context),
        .low_event_valid(low_valid), .low_event_metadata(low_metadata),
        .low_event_gx(low_gx), .low_event_gy(low_gy), .low_event_magnitude(low_magnitude),
        .debug_poll(1'b0), .debug_clear_firstfault(1'b0),
        .record_drop_count(pyramid_drops), .native_stall_count(native_stalls),
        .full_event_valid(), .full_event_metadata(), .full_event_filtered_y(),
        .full_event_gx(), .full_event_gy(), .full_event_magnitude(),
        .full_event_native_x(), .full_event_native_y(),
        .low_event_filtered_y(), .low_event_native_x(), .low_event_native_y(),
        .debug_poll_count(), .completed_count(), .failed_count(),
        .firstfault_code(), .firstfault_context(), .first_congestion_context(),
        .max_low_resident(), .max_grant_wait()
    );
    preprocess_lane_candidates4 #(.STRIPS(4), .MONO_PRESET(1)) u_lane (
        .clk(clk), .rst_n(rst_n), .cancel(cancel), .debug_clear(1'b0),
        .start(start_valid && start_ready), .start_context(start_context),
        .native_width(start_width), .native_height(start_height),
        .mag_threshold(threshold), .gx_min(gx_min), .ratio_shift(ratio_shift),
        .direction_sign(direction_sign), .min_count(min_count), .min_paired_strips(min_paired_strips),
        .strip_y_begin(strip_y_begin), .strip_y_end(strip_y_end),
        .roi_left(roi_left), .roi_split(roi_split), .roi_right(roi_right),
        .event_valid(low_valid), .event_metadata(low_metadata),
        .event_gx(low_gx), .event_gy(low_gy), .event_magnitude(low_magnitude),
        .frame_complete(frame_complete), .frame_error(frame_error),
        .terminal_context(frame_event_context), .source_error_code(frame_error_code),
        .record_valid(lane_valid), .record_ready(lane_ready), .record_data(lane_data),
        .record_drop_count(lane_drops), .frames_finished(lane_finished), .frames_failed(lane_failed),
        .frames_started(), .stray_terminal_count(), .first_fault_valid(),
        .first_fault_code(), .first_fault_context()
    );
endmodule
