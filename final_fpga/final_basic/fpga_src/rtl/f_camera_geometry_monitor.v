`timescale 1ns / 1ps

// Passive pixel-domain frame geometry; no stream signal is driven by this block.
module f_camera_geometry_monitor #(
    parameter integer EXPECT_RGB_LINES = 1080
) (
    input wire i_clk,
    input wire i_debug_rst_n,
    input wire i_app_rst_n,
    input wire i_clear,
    input wire i_raw_valid,
    input wire i_raw_ready,
    input wire i_raw_sof,
    input wire i_raw_eol,
    input wire i_raw_abort,
    input wire i_receive_fault,
    input wire i_crop_error,
    input wire i_rgb_valid,
    input wire i_rgb_ready,
    input wire i_rgb_sof,
    input wire i_rgb_eol,
    input wire i_frame_done,
    input wire i_frame_error,
    output wire [511:0] o_status
);
    reg raw_active, raw_history_valid, raw_previous_partial, raw_previous_fault;
    reg rgb_active, rgb_history_valid, rgb_previous_complete, rgb_previous_failed;
    reg reset_discarded, app_previous;
    reg [9:0] saturation_sources;
    wire saturated = |saturation_sources;
    reg abort_previous, receive_previous, crop_previous, done_previous, error_previous;
    reg [31:0] raw_id, raw_previous_id, rgb_id, rgb_previous_id;
    reg [15:0] raw_rows, raw_groups, raw_first, raw_last, raw_min, raw_max;
    reg [15:0] previous_rows, previous_tail, previous_first, previous_last;
    reg [15:0] previous_min, previous_max;
    reg [15:0] abort_count, receive_count, crop_count;
    reg [15:0] previous_aborts, previous_receives, previous_crops;
    reg [15:0] total_aborts, total_receives, total_crops;
    reg [15:0] accepted_row, accepted_group;
    reg [31:0] accepted_id;
    // Modular successor of the saturating RAW counter. Zero represents the
    // exhausted FFFFFFFF counter and remains zero until debug reset/CLEAR.
    reg [31:0] raw_id_successor;
    wire [31:0] accepted_next_id = raw_id_successor == 0 ?
                                  32'hffffffff : raw_id_successor;
    reg [15:0] candidate_row, candidate_group;
    reg [22:0] candidate_id;
    reg [7:0] candidate_reasons;
    reg [63:0] fault_history;
    wire [63:0] fault_scene = (|candidate_reasons) ?
        {candidate_id, 1'b1, candidate_reasons, candidate_group, candidate_row} : fault_history;
    reg [15:0] rgb_lines, previous_rgb_lines;
    reg [31:0] rgb_successes, rgb_failures;

    wire raw_transfer = i_raw_valid && i_raw_ready;
    wire raw_start = raw_transfer && i_raw_sof;
    wire rgb_transfer = i_rgb_valid && i_rgb_ready;
    wire rgb_start = rgb_transfer && i_rgb_sof;
    wire abort_event = i_raw_abort && !abort_previous;
    wire receive_event = i_receive_fault && !receive_previous;
    wire crop_event = i_crop_error && !crop_previous;
    wire done_event = i_frame_done && !done_previous;
    wire error_event = i_frame_error && !error_previous;
    wire reset_event = app_previous && !i_app_rst_n;
    // Precompute geometry before the late READY handshake selects a clock edge.
    wire [15:0] groups_after = increment_short(raw_groups);
    wire raw_count_enable = raw_transfer && (raw_active || i_raw_sof);
    wire [15:0] raw_rows_next = i_raw_sof ? (i_raw_eol ? 16'd1 : 16'd0) :
                              (i_raw_eol ? increment_short(raw_rows) : raw_rows);
    wire [15:0] raw_groups_next = i_raw_sof ? (i_raw_eol ? 16'd0 : 16'd1) :
                                (i_raw_eol ? 16'd0 : groups_after);
    wire [15:0] raw_first_next = i_raw_sof ? (i_raw_eol ? 16'd1 : 16'd0) :
                               (i_raw_eol && raw_rows == 0 ? groups_after : raw_first);
    wire [15:0] raw_last_next = i_raw_sof ? (i_raw_eol ? 16'd1 : 16'd0) :
                              (i_raw_eol ? groups_after : raw_last);
    wire [15:0] raw_min_next = i_raw_sof ? (i_raw_eol ? 16'd1 : 16'd0) :
                             (i_raw_eol && (raw_rows == 0 || groups_after < raw_min) ?
                              groups_after : raw_min);
    wire [15:0] raw_max_next = i_raw_sof ? (i_raw_eol ? 16'd1 : 16'd0) :
                             (i_raw_eol && groups_after > raw_max ? groups_after : raw_max);
    wire [15:0] lines_after = rgb_transfer && i_rgb_eol ?
                              increment_short(rgb_lines) : rgb_lines;
    // Compare both possible counts before the late RGB READY/EOL selection.
    wire current_lines_bad = rgb_lines != EXPECT_RGB_LINES;
    wire incremented_lines_bad = increment_short(rgb_lines) != EXPECT_RGB_LINES;
    wire completion_lines_bad = rgb_transfer && i_rgb_eol ?
                                incremented_lines_bad : current_lines_bad;
    wire bad_completion = done_event && (!rgb_active || completion_lines_bad);
    wire rgb_replaced = rgb_start && rgb_active && !done_event && !error_event;
    wire raw_partial_boundary = raw_start && raw_active && raw_groups != 0;
    wire [7:0] reasons_now = {raw_partial_boundary, rgb_replaced, bad_completion,
                             error_event, reset_event, crop_event, receive_event, abort_event};

    // Saturation retains useful geometry and explicitly marks exhausted counters.
    function [15:0] increment_short;
        input [15:0] value;
        begin increment_short = value == 16'hffff ? value : value + 16'd1; end
    endfunction
    function [31:0] increment_total;
        input [31:0] value;
        begin increment_total = value == 32'hffffffff ? value : value + 32'd1; end
    endfunction

    wire [31:0] flags = {21'd0, !raw_active, saturated, reset_discarded,
                         rgb_previous_failed, rgb_previous_complete, rgb_active,
                         rgb_history_valid, raw_previous_fault, raw_previous_partial,
                         raw_active, raw_history_valid};
    assign o_status = {
        rgb_failures, rgb_successes, rgb_lines, previous_rgb_lines,
        rgb_previous_id, fault_scene, total_crops, previous_crops,
        total_receives, previous_receives, total_aborts, previous_aborts,
        raw_groups, raw_rows, previous_max, previous_min,
        previous_last, previous_first, previous_tail, previous_rows,
        raw_previous_id, flags, 32'h46474d31
    };

    // A candidate and the previous visible scene are registered every edge.
    // Selection uses registered reasons, so the late event union never enables
    // the wide scene registers. The complete tuple is visible on the event edge;
    // an idle edge copies that tuple into history without adding output latency.
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            candidate_row <= 0; candidate_group <= 0; candidate_id <= 0;
            candidate_reasons <= 0; fault_history <= 0;
        end else if (i_clear) begin
            candidate_row <= 0; candidate_group <= 0; candidate_id <= 0;
            candidate_reasons <= 0; fault_history <= 0;
        end else begin
            fault_history <= fault_scene;
            candidate_reasons <= i_app_rst_n ? reasons_now :
                                 (reset_event && (raw_active || rgb_active) ? 8'h08 : 8'h00);
            if (!i_app_rst_n) begin
                candidate_row <= raw_rows; candidate_group <= raw_groups; candidate_id <= raw_id[22:0];
            end else if (crop_event) begin
                candidate_row <= accepted_row; candidate_group <= accepted_group;
                candidate_id <= accepted_id[22:0];
            end else if (raw_partial_boundary && !abort_event && !receive_event) begin
                candidate_row <= raw_rows; candidate_group <= raw_groups; candidate_id <= raw_id[22:0];
            end else begin
                candidate_row <= raw_start ? 16'd0 : raw_rows;
                candidate_group <= raw_start ? 16'd0 : raw_groups;
                candidate_id <= raw_start ? raw_id_successor[22:0] : raw_id[22:0];
            end
        end
    end

    // The late transfer controls only selection/enable in the scene and
    // accepted-ID banks; their D cones no longer contain a wide increment.
    // Update the predictor with exactly the RAW counter's admission condition.
    // Application reset preserves RAW history and this predictor together.
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) raw_id_successor <= 32'd1;
        else if (i_clear) raw_id_successor <= 32'd1;
        else if (i_app_rst_n && raw_start && raw_id_successor != 0)
            raw_id_successor <= raw_id_successor + 32'd1;
    end

    // Keep each sticky source local; only registered flags feed the page OR.
    // Reaching a maximum alone does not set a flag: these are attempted counts.
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) saturation_sources <= 0;
        else if (i_clear) saturation_sources <= 0;
        else if (!i_app_rst_n) begin
            if (reset_event && rgb_active && rgb_failures == 32'hffffffff)
                saturation_sources[9] <= 1;
        end else begin
            if (abort_event && total_aborts == 16'hffff) saturation_sources[0] <= 1;
            if (receive_event && total_receives == 16'hffff) saturation_sources[1] <= 1;
            if (crop_event && total_crops == 16'hffff) saturation_sources[2] <= 1;
            if (raw_transfer && raw_active && (raw_rows == 16'hffff || raw_groups == 16'hffff))
                saturation_sources[3] <= 1;
            if (rgb_transfer && rgb_active && rgb_lines == 16'hffff) saturation_sources[4] <= 1;
            if (raw_start && raw_id == 32'hffffffff) saturation_sources[5] <= 1;
            if (rgb_start && rgb_id == 32'hffffffff) saturation_sources[6] <= 1;
            if (done_event && !error_event && !bad_completion && rgb_successes == 32'hffffffff)
                saturation_sources[7] <= 1;
            if ((error_event || bad_completion || rgb_replaced) && rgb_failures == 32'hffffffff)
                saturation_sources[8] <= 1;
        end
    end

    // Debug reset/CLEAR erase history and wait for a fresh accepted SOF.
    // Application reset retains history, cancels live frames and records the discard.
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            raw_active <= 0; raw_history_valid <= 0; raw_previous_partial <= 0;
            raw_previous_fault <= 0; rgb_active <= 0; rgb_history_valid <= 0;
            rgb_previous_complete <= 0; rgb_previous_failed <= 0;
            reset_discarded <= 0; app_previous <= 0;
            abort_previous <= 0; receive_previous <= 0; crop_previous <= 0;
            done_previous <= 0; error_previous <= 0;
            raw_id <= 0; raw_previous_id <= 0; rgb_id <= 0; rgb_previous_id <= 0;
            raw_rows <= 0; raw_groups <= 0; raw_first <= 0; raw_last <= 0;
            raw_min <= 0; raw_max <= 0; previous_rows <= 0; previous_tail <= 0;
            previous_first <= 0; previous_last <= 0; previous_min <= 0; previous_max <= 0;
            abort_count <= 0; receive_count <= 0; crop_count <= 0;
            previous_aborts <= 0; previous_receives <= 0; previous_crops <= 0;
            total_aborts <= 0; total_receives <= 0; total_crops <= 0;
            accepted_row <= 0; accepted_group <= 0; accepted_id <= 0;
            rgb_lines <= 0; previous_rgb_lines <= 0; rgb_successes <= 0; rgb_failures <= 0;
        end else if (i_clear) begin
            raw_active <= 0; raw_history_valid <= 0; raw_previous_partial <= 0;
            raw_previous_fault <= 0; rgb_active <= 0; rgb_history_valid <= 0;
            rgb_previous_complete <= 0; rgb_previous_failed <= 0;
            reset_discarded <= 0; app_previous <= i_app_rst_n;
            abort_previous <= i_raw_abort; receive_previous <= i_receive_fault;
            crop_previous <= i_crop_error; done_previous <= i_frame_done;
            error_previous <= i_frame_error;
            raw_id <= 0; raw_previous_id <= 0; rgb_id <= 0; rgb_previous_id <= 0;
            raw_rows <= 0; raw_groups <= 0; raw_first <= 0; raw_last <= 0;
            raw_min <= 0; raw_max <= 0; previous_rows <= 0; previous_tail <= 0;
            previous_first <= 0; previous_last <= 0; previous_min <= 0; previous_max <= 0;
            abort_count <= 0; receive_count <= 0; crop_count <= 0;
            previous_aborts <= 0; previous_receives <= 0; previous_crops <= 0;
            total_aborts <= 0; total_receives <= 0; total_crops <= 0;
            accepted_row <= 0; accepted_group <= 0; accepted_id <= 0;
            rgb_lines <= 0; previous_rgb_lines <= 0; rgb_successes <= 0; rgb_failures <= 0;
        end else begin
            app_previous <= i_app_rst_n;
            abort_previous <= i_raw_abort; receive_previous <= i_receive_fault;
            crop_previous <= i_crop_error; done_previous <= i_frame_done;
            error_previous <= i_frame_error;
            if (!i_app_rst_n) begin
                raw_active <= 0; raw_rows <= 0; raw_groups <= 0;
                raw_first <= 0; raw_last <= 0; raw_min <= 0; raw_max <= 0;
                abort_count <= 0; receive_count <= 0; crop_count <= 0;
                rgb_active <= 0; rgb_lines <= 0;
                if (reset_event && (raw_active || rgb_active)) begin
                    reset_discarded <= 1;
                    if (rgb_active) begin
                        rgb_history_valid <= 1; rgb_previous_complete <= 0; rgb_previous_failed <= 1;
                        rgb_previous_id <= rgb_id; previous_rgb_lines <= rgb_lines;
                        rgb_failures <= increment_total(rgb_failures);
                    end
                end
            end else begin
                if (abort_event) total_aborts <= increment_short(total_aborts);
                if (receive_event) total_receives <= increment_short(total_receives);
                if (crop_event) total_crops <= increment_short(total_crops);
                if (raw_count_enable) begin
                    raw_rows <= raw_rows_next; raw_groups <= raw_groups_next;
                    raw_first <= raw_first_next; raw_last <= raw_last_next;
                    raw_min <= raw_min_next; raw_max <= raw_max_next;
                end
                if (raw_start) begin
                    if (raw_active) begin
                        raw_history_valid <= 1; raw_previous_id <= raw_id;
                        previous_rows <= raw_rows; previous_tail <= raw_groups;
                        previous_first <= raw_first; previous_last <= raw_last;
                        previous_min <= raw_min; previous_max <= raw_max;
                        previous_aborts <= abort_count; previous_receives <= receive_count;
                        previous_crops <= crop_event ? increment_short(crop_count) : crop_count;
                        raw_previous_partial <= raw_groups != 0;
                        raw_previous_fault <= (abort_count != 0 || receive_count != 0 ||
                                               crop_count != 0 || crop_event);
                    end
                    raw_active <= 1; raw_id <= increment_total(raw_id);
                    abort_count <= abort_event ? 16'd1 : 16'd0;
                    receive_count <= receive_event ? 16'd1 : 16'd0;
                    crop_count <= 0;
                    accepted_row <= 0; accepted_group <= 0; accepted_id <= accepted_next_id;
                end else if (raw_active) begin
                    if (abort_event) abort_count <= increment_short(abort_count);
                    if (receive_event) receive_count <= increment_short(receive_count);
                    if (crop_event) crop_count <= increment_short(crop_count);
                    if (raw_transfer) begin
                        accepted_row <= raw_rows; accepted_group <= raw_groups; accepted_id <= raw_id;
                    end
                end
                // Error wins over completion; invalid completion is a failed diagnostic frame.
                if (error_event || done_event) begin
                    rgb_history_valid <= 1; rgb_previous_id <= rgb_id;
                    previous_rgb_lines <= rgb_active ? lines_after : 16'd0;
                    rgb_previous_complete <= !error_event && !bad_completion;
                    rgb_previous_failed <= error_event || bad_completion;
                    rgb_active <= 0; rgb_lines <= 0;
                    if (error_event || bad_completion) rgb_failures <= increment_total(rgb_failures);
                    else rgb_successes <= increment_total(rgb_successes);
                end else if (rgb_start) begin
                    if (rgb_active) begin
                        rgb_history_valid <= 1; rgb_previous_id <= rgb_id;
                        previous_rgb_lines <= rgb_lines;
                        rgb_previous_complete <= 0; rgb_previous_failed <= 1;
                        rgb_failures <= increment_total(rgb_failures);
                    end
                    rgb_id <= increment_total(rgb_id); rgb_active <= 1;
                    rgb_lines <= i_rgb_eol ? 16'd1 : 16'd0;
                end else if (rgb_active && rgb_transfer && i_rgb_eol) rgb_lines <= lines_after;
            end
        end
    end
endmodule
