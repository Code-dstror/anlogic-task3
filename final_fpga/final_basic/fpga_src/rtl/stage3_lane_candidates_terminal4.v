// Explicit compact-stat bitstream profile; ordinary defaults remain unchanged.
`ifndef C15_F23_FULLHEIGHT_PROFILE
`define C15_F23_FULLHEIGHT_PROFILE 0
`endif
// F23 passive quarter-scale evidence. All four lanes merge into small strip
// control accumulators; no video-ready or reset feedback reaches F22.
module stage3_lane_candidates_terminal4 #(
    parameter integer STRIPS = 4,
    parameter integer MONO_PRESET = 0,
    parameter integer FULLHEIGHT_ROI_ENABLE = (`C15_F23_FULLHEIGHT_PROFILE && MONO_PRESET)
) (
    input wire clk,
    input wire rst_n,
    input wire cancel,
    input wire debug_clear,
    input wire start,
    input wire [159:0] start_context,
    input wire [12:0] native_width,
    input wire [12:0] native_height,
    input wire [10:0] mag_threshold,
    input wire [10:0] gx_min,
    input wire [1:0] ratio_shift,
    input wire [1:0] direction_sign,
    input wire [19:0] min_count,
    input wire [3:0] min_paired_strips,
    input wire [STRIPS*13-1:0] strip_y_begin,
    input wire [STRIPS*13-1:0] strip_y_end,
    input wire [STRIPS*13-1:0] roi_left,
    input wire [STRIPS*13-1:0] roi_split,
    input wire [STRIPS*13-1:0] roi_right,
    input wire event_valid,
    input wire [220:0] event_metadata,
    input wire [43:0] event_gx,
    input wire [43:0] event_gy,
    input wire [43:0] event_magnitude,
    input wire frame_complete,
    input wire frame_error,
    input wire [159:0] terminal_context,
    input wire [7:0] source_error_code,
    output reg record_valid,
    input wire record_ready,
    output reg [292+266*STRIPS-1:0] record_data,
    output reg [31:0] frames_started,
    output reg [31:0] frames_finished,
    output reg [31:0] frames_failed,
    output reg [31:0] record_drop_count,
    output reg [31:0] stray_terminal_count,
    output reg first_fault_valid,
    output reg [7:0] first_fault_code,
    output reg [159:0] first_fault_context,
    output reg terminal_valid, terminal_error,
    output wire [159:0] terminal_identity
);
    localparam integer ACTIVE_STRIPS = FULLHEIGHT_ROI_ENABLE ? 1 : STRIPS;
    localparam integer SIDES = 2 * ACTIVE_STRIPS;
    localparam integer COUNT_BITS = FULLHEIGHT_ROI_ENABLE ? 16 : MONO_PRESET ? 14 : 20;
    localparam integer XSUM_BITS = FULLHEIGHT_ROI_ENABLE ? 27 : MONO_PRESET ? 26 : 32;
    localparam integer STRENGTH_BITS = FULLHEIGHT_ROI_ENABLE ? 27 : MONO_PRESET ? 25 : 30;
    reg active, eof_seen;
    reg [7:0] current_error;
    reg [159:0] locked_context;
    reg [12:0] locked_native_width, locked_native_height, low_width, low_height;
    reg [10:0] locked_threshold, locked_gx_min;
    reg [1:0] locked_ratio, locked_sign;
    reg [19:0] locked_min_count, pixels_seen;
    reg [3:0] locked_min_strips;
    reg [STRIPS*13-1:0] locked_y_begin, locked_y_end;
    reg [STRIPS*13-1:0] locked_left, locked_split, locked_right;
    reg [12:0] expected_x, expected_y;
    reg [COUNT_BITS-1:0] point_count [0:SIDES-1];
    reg [XSUM_BITS-1:0] sum_native_x [0:SIDES-1];
    reg [STRENGTH_BITS-1:0] strength_sum [0:SIDES-1];
    reg [10:0] peak_strength [0:SIDES-1];
    reg [12:0] peak_x [0:SIDES-1];
    reg [12:0] peak_y [0:SIDES-1];
    reg [COUNT_BITS-1:0] next_count [0:SIDES-1];
    reg [XSUM_BITS-1:0] next_sum_x [0:SIDES-1];
    reg [STRENGTH_BITS-1:0] next_strength_sum [0:SIDES-1];
    reg [10:0] next_peak [0:SIDES-1];
    reg [12:0] next_peak_x [0:SIDES-1];
    reg [12:0] next_peak_y [0:SIDES-1];
    wire selected_event = event_valid && event_metadata[60:59] == 2;
    wire [12:0] event_x = event_metadata[32:20];
    wire [12:0] event_y = event_metadata[19:7];
    wire [3:0] event_keep = event_metadata[6:3];
    wire [12:0] start_low_width = (native_width + 13'd3) >> 2;
    wire [12:0] start_low_height = (native_height + 13'd3) >> 2;
    wire terminal_match = active && terminal_context == locked_context;
    wire finish = active && (start || ((frame_complete || frame_error) && terminal_match));
    wire slot_free = !record_valid || record_ready;
    reg config_bad;
    reg [7:0] event_error;
    reg [7:0] finish_error;
    reg [7:0] diagnostic_error;
    reg [159:0] diagnostic_context;
    reg [2:0] lane_count;
    reg [3:0] required_keep;
    reg bad_gradient;
    reg [292+266*STRIPS-1:0] completed_record;
    reg [119:0] left_stats, right_stats;
    reg [3:0] paired_strips;
    reg frame_has_evidence;
    reg [12:0] native_y_end;
    integer cfg_index, numeric_lane, record_index, reset_index;

    function [10:0] absolute_gradient;
        input [10:0] value;
        begin absolute_gradient = value[10] ? (~value + 11'd1) : value; end
    endfunction

    always @* begin
        config_bad = STRIPS < 1 || STRIPS > 8 || native_width < 4 || native_width > 3840
            || native_width[1:0] != 0 || native_height < 1 || native_height > 2160
            || mag_threshold > 2040 || gx_min > 1020 || direction_sign == 3
            || min_count == 0 || min_paired_strips == 0 || min_paired_strips > STRIPS;
        // A rejected profile never updates the narrowed evidence registers.
        // Serialized shape remains four slots. Three explicitly empty
        // slots own no accumulators and never claim independent measurements.
        if (FULLHEIGHT_ROI_ENABLE && (STRIPS != 4 || MONO_PRESET != 1 ||
            native_width != 1920 || native_height != 1080 ||
            strip_y_begin != 52'd0 || strip_y_end != {39'd0,13'd270} ||
            roi_left != 52'd0 || roi_split != {39'd0,13'd240} ||
            roi_right != {39'd0,13'd480})) config_bad = 1;
        if (MONO_PRESET && !FULLHEIGHT_ROI_ENABLE && (STRIPS != 4 || native_width != 1920 || native_height != 1080
            || strip_y_begin != {13'd202,13'd135,13'd67,13'd0}
            || strip_y_end != {13'd270,13'd202,13'd135,13'd67}
            || roi_left != 0 || roi_split != {4{13'd240}} || roi_right != {4{13'd480}}))
            config_bad = 1;
        for (cfg_index = 0; cfg_index < ACTIVE_STRIPS; cfg_index = cfg_index + 1) begin
            if (strip_y_begin[cfg_index*13 +: 13] >= strip_y_end[cfg_index*13 +: 13]
                || strip_y_end[cfg_index*13 +: 13] > start_low_height
                || roi_left[cfg_index*13 +: 13] >= roi_split[cfg_index*13 +: 13]
                || roi_split[cfg_index*13 +: 13] >= roi_right[cfg_index*13 +: 13]
                || roi_right[cfg_index*13 +: 13] > start_low_width)
                config_bad = 1;
            if (cfg_index > 0) begin
                if (strip_y_begin[cfg_index*13 +: 13] != strip_y_end[(cfg_index-1)*13 +: 13]
                    || roi_left[cfg_index*13 +: 13] > roi_left[(cfg_index-1)*13 +: 13]
                    || roi_right[cfg_index*13 +: 13] < roi_right[(cfg_index-1)*13 +: 13])
                    config_bad = 1;
            end
        end
    end

    // Validate one complete vector before accepting any lane, so malformed
    // geometry/gradients cannot leave partial evidence in a strip.
    always @* begin
        case (event_keep)
            4'h1: lane_count = 1;
            4'h3: lane_count = 2;
            4'h7: lane_count = 3;
            4'hf: lane_count = 4;
            default: lane_count = 0;
        endcase
        if (low_width - expected_x >= 4) required_keep = 4'hf;
        else case (low_width - expected_x)
            1: required_keep = 4'h1;
            2: required_keep = 4'h3;
            3: required_keep = 4'h7;
            default: required_keep = 0;
        endcase
        bad_gradient = 0;
        for (numeric_lane = 0; numeric_lane < 4; numeric_lane = numeric_lane + 1) begin
            if (event_keep[numeric_lane]) begin
                if (absolute_gradient(event_gx[numeric_lane*11 +: 11]) > 1020
                    || absolute_gradient(event_gy[numeric_lane*11 +: 11]) > 1020
                    || event_magnitude[numeric_lane*11 +: 11] !=
                        absolute_gradient(event_gx[numeric_lane*11 +: 11])
                        + absolute_gradient(event_gy[numeric_lane*11 +: 11]))
                    bad_gradient = 1;
            end
        end
        event_error = 0;
        if (eof_seen) event_error = 5;
        else if (event_metadata[220:61] != locked_context
            || event_metadata[58:46] != low_width || event_metadata[45:33] != low_height)
            event_error = 3;
        else if (event_x != expected_x || event_y != expected_y) event_error = 6;
        else if (event_keep != required_keep || lane_count == 0) event_error = 4;
        else if (event_metadata[2] != (expected_x == 0 && expected_y == 0)
            || event_metadata[1] != (expected_x + lane_count == low_width)
            || event_metadata[0] != (expected_x + lane_count == low_width && expected_y == low_height-1))
            event_error = 5;
        else if (bad_gradient) event_error = 2;
    end

    // Legal strip rows are disjoint. Select one history pair and perform
    // only two vector reductions, independent of STRIPS. No rate conversion.
    reg strip_selected;
    reg [2:0] selected_strip;
    reg [12:0] selected_left, selected_split, selected_right;
    integer select_index;
    always @* begin
        strip_selected = 0;
        selected_strip = 0;
        selected_left = 0; selected_split = 0; selected_right = 0;
        for (select_index=0; select_index<ACTIVE_STRIPS; select_index=select_index+1) begin
            if (event_y >= locked_y_begin[select_index*13 +:13] &&
                event_y < locked_y_end[select_index*13 +:13]) begin
                strip_selected = 1;
                selected_strip = select_index;
                selected_left = locked_left[select_index*13 +:13];
                selected_split = locked_split[select_index*13 +:13];
                selected_right = locked_right[select_index*13 +:13];
            end
        end
    end
    reg [COUNT_BITS-1:0] shared_count [0:1];
    reg [XSUM_BITS-1:0] shared_sum_x [0:1];
    reg [STRENGTH_BITS-1:0] shared_strength [0:1];
    reg [10:0] shared_peak [0:1];
    reg [12:0] shared_peak_x [0:1], shared_peak_y [0:1];
    // Reduce the current vector before looking at history. In particular the
    // peak feedback traverses one comparator, rather than four chained lane
    // comparators and their coordinate muxes. Equal magnitudes select the
    // earliest lane locally, then preserve an existing history peak.
    wire [10:0] lane_abs_x [0:3], lane_abs_y [0:3];
    wire [13:0] lane_direction_bound [0:3];
    wire [12:0] lane_pixel_x [0:3];
    wire [3:0] lane_numeric_accepted;
    genvar numeric;
    generate for (numeric=0; numeric<4; numeric=numeric+1) begin : g_numeric
        assign lane_abs_x[numeric] = absolute_gradient(event_gx[numeric*11 +:11]);
        assign lane_abs_y[numeric] = absolute_gradient(event_gy[numeric*11 +:11]);
        assign lane_direction_bound[numeric] = {3'd0,lane_abs_x[numeric]} << locked_ratio;
        assign lane_pixel_x[numeric] = event_x + numeric;
        assign lane_numeric_accepted[numeric] = strip_selected && event_keep[numeric]
            && lane_pixel_x[numeric] >= selected_left && lane_pixel_x[numeric] < selected_right
            && event_magnitude[numeric*11 +:11] >= locked_threshold
            && lane_abs_x[numeric] != 0 && lane_abs_x[numeric] >= locked_gx_min
            && {3'd0,lane_abs_y[numeric]} <= lane_direction_bound[numeric]
            && (locked_sign == 0 || (locked_sign == 1 && !event_gx[numeric*11+10])
                || (locked_sign == 2 && event_gx[numeric*11+10]));
    end endgenerate
    genvar direction;
    generate for (direction=0; direction<2; direction=direction+1) begin : g_shared
        wire [3:0] history_index = {selected_strip,1'b0} + direction;
        wire [3:0] accepted;
        wire [3:0] exceeds_history;
        wire [16:0] x_term [0:3];
        wire [12:0] strength_term [0:3];
        genvar item;
        for (item=0; item<4; item=item+1) begin : g_item
            assign accepted[item] = lane_numeric_accepted[item] &&
                (direction != 0 ? lane_pixel_x[item] >= selected_split :
                                  lane_pixel_x[item] < selected_split);
            assign exceeds_history[item] = accepted[item] &&
                event_magnitude[item*11 +:11] > peak_strength[history_index];
            assign x_term[item] = accepted[item] ? {2'd0,lane_pixel_x[item],2'b00} : 17'd0;
            assign strength_term[item] = accepted[item] ?
                {2'd0,event_magnitude[item*11 +:11]} : 13'd0;
        end
        wire [1:0] count_low = {1'b0,accepted[0]} + {1'b0,accepted[1]};
        wire [1:0] count_high = {1'b0,accepted[2]} + {1'b0,accepted[3]};
        wire [2:0] vector_count = {1'b0,count_low} + {1'b0,count_high};
        wire [16:0] x_low = x_term[0] + x_term[1];
        wire [16:0] x_high = x_term[2] + x_term[3];
        wire [16:0] vector_x_sum = x_low + x_high;
        wire [12:0] strength_low = strength_term[0] + strength_term[1];
        wire [12:0] strength_high = strength_term[2] + strength_term[3];
        wire [12:0] vector_strength_sum = strength_low + strength_high;
        wire low_first = accepted[0] && (!accepted[1] ||
            event_magnitude[0 +:11] >= event_magnitude[11 +:11]);
        wire high_first = accepted[2] && (!accepted[3] ||
            event_magnitude[22 +:11] >= event_magnitude[33 +:11]);
        wire low_valid = |accepted[1:0];
        wire high_valid = |accepted[3:2];
        wire [10:0] low_peak = low_first ? event_magnitude[0 +:11] : event_magnitude[11 +:11];
        wire [10:0] high_peak = high_first ? event_magnitude[22 +:11] : event_magnitude[33 +:11];
        wire choose_low = low_valid && (!high_valid || low_peak >= high_peak);
        wire [10:0] vector_peak = choose_low ? low_peak : high_peak;
        wire [1:0] vector_lane = choose_low ? {1'b0,!low_first} : {1'b1,!high_first};
        wire [12:0] vector_peak_pixel_x = event_x + {11'd0,vector_lane};
        // Preserve first-candidate behavior, including count wrap and a zero
        // candidate. Winner/tie data remain the original independent tree.
        wire update_peak = (point_count[history_index] == 0 && (|accepted)) ||
            (|exceeds_history);
        always @* begin
            shared_peak[direction] = peak_strength[history_index];
            shared_peak_x[direction] = peak_x[history_index];
            shared_peak_y[direction] = peak_y[history_index];
            if (update_peak) begin
                shared_peak[direction] = vector_peak;
                shared_peak_x[direction] = vector_peak_pixel_x << 2;
                shared_peak_y[direction] = event_y << 2;
            end
            shared_count[direction] = point_count[history_index] + vector_count;
            shared_sum_x[direction] = sum_native_x[history_index] + vector_x_sum;
            shared_strength[direction] = strength_sum[history_index] + vector_strength_sum;
        end
    end endgenerate
    genvar side;
    generate for (side=0; side<SIDES; side=side+1) begin : g_history
        always @* begin
            next_count[side] = point_count[side];
            next_sum_x[side] = sum_native_x[side];
            next_strength_sum[side] = strength_sum[side];
            next_peak[side] = peak_strength[side];
            next_peak_x[side] = peak_x[side];
            next_peak_y[side] = peak_y[side];
            if (strip_selected && selected_strip == side/2) begin
                next_count[side] = shared_count[side%2];
                next_sum_x[side] = shared_sum_x[side%2];
                next_strength_sum[side] = shared_strength[side%2];
                next_peak[side] = shared_peak[side%2];
                next_peak_x[side] = shared_peak_x[side%2];
                next_peak_y[side] = shared_peak_y[side%2];
            end
        end
    end endgenerate
    always @* begin
        finish_error = current_error;
        if (finish_error == 0) begin
            if (frame_error && terminal_match) finish_error = {1'b1,source_error_code[6:0]};
            else if (start && !(frame_complete && terminal_match)) finish_error = 9;
            else if (!eof_seen) finish_error = 7;
        end
        paired_strips = 0;
        for (record_index = 0; record_index < ACTIVE_STRIPS; record_index = record_index + 1)
            if (point_count[2*record_index] >= locked_min_count
                && point_count[2*record_index+1] >= locked_min_count)
                paired_strips = paired_strips + 1;
        frame_has_evidence = finish_error == 0 && paired_strips >= locked_min_strips;
        completed_record = 0;
        left_stats = 0; right_stats = 0; native_y_end = 0;
        for (record_index = 0; record_index < ACTIVE_STRIPS; record_index = record_index + 1) begin
            left_stats = 0; right_stats = 0;
            if (finish_error == 0) begin
                left_stats = {{{(20-COUNT_BITS){1'b0}},point_count[2*record_index]},{{(32-XSUM_BITS){1'b0}},sum_native_x[2*record_index]},
                    {{(30-STRENGTH_BITS){1'b0}},strength_sum[2*record_index]},peak_strength[2*record_index],
                    peak_x[2*record_index],peak_y[2*record_index],
                    (point_count[2*record_index] >= locked_min_count)};
                right_stats = {{{(20-COUNT_BITS){1'b0}},point_count[2*record_index+1]},{{(32-XSUM_BITS){1'b0}},sum_native_x[2*record_index+1]},
                    {{(30-STRENGTH_BITS){1'b0}},strength_sum[2*record_index+1]},peak_strength[2*record_index+1],
                    peak_x[2*record_index+1],peak_y[2*record_index+1],
                    (point_count[2*record_index+1] >= locked_min_count)};
            end
            native_y_end = locked_y_end[record_index*13 +: 13] << 2;
            if (native_y_end > locked_native_height) native_y_end = locked_native_height;
            completed_record[record_index*266 +: 266] =
                {(locked_y_begin[record_index*13 +: 13] << 2),native_y_end,left_stats,right_stats};
        end
        completed_record[STRIPS*266 +: 292] = {locked_context,(finish_error == 0),finish_error,
            frame_has_evidence,locked_native_width,locked_native_height,low_width,low_height,
            locked_threshold,locked_gx_min,locked_ratio,locked_sign,locked_min_count,
            locked_min_strips,(finish_error == 0 ? pixels_seen : 20'd0)};
        diagnostic_error = 0;
        diagnostic_context = locked_context;
        if (finish && finish_error != 0) diagnostic_error = finish_error;
        else if (selected_event && active && current_error == 0 && event_error != 0)
            diagnostic_error = event_error;
        else if (start && config_bad) begin diagnostic_error = 1; diagnostic_context = start_context; end
        else if (finish && !slot_free) diagnostic_error = 10;
    end

    always @(posedge clk) begin
        if (!rst_n || cancel) begin
            active <= 0; eof_seen <= 0; current_error <= 0; locked_context <= 0;
            locked_native_width <= 0; locked_native_height <= 0; low_width <= 0; low_height <= 0;
            locked_threshold <= 0; locked_gx_min <= 0; locked_ratio <= 0; locked_sign <= 0;
            locked_min_count <= 0; locked_min_strips <= 0; pixels_seen <= 0;
            locked_y_begin <= 0; locked_y_end <= 0; locked_left <= 0; locked_split <= 0; locked_right <= 0;
            expected_x <= 0; expected_y <= 0; record_valid <= 0; record_data <= 0;
            for (reset_index = 0; reset_index < SIDES; reset_index = reset_index + 1) begin
                point_count[reset_index] <= 0; sum_native_x[reset_index] <= 0;
                strength_sum[reset_index] <= 0; peak_strength[reset_index] <= 0;
                peak_x[reset_index] <= 0; peak_y[reset_index] <= 0;
            end
        end else begin
            if (record_valid && record_ready) record_valid <= 0;
            if (finish) begin
                active <= 0;
                if (slot_free) begin record_valid <= 1; record_data <= completed_record; end
            end
            if (start) begin
                active <= 1; eof_seen <= 0; current_error <= config_bad ? 8'd1 : 8'd0;
                locked_context <= start_context; locked_native_width <= native_width;
                locked_native_height <= native_height; low_width <= start_low_width; low_height <= start_low_height;
                locked_threshold <= mag_threshold; locked_gx_min <= gx_min;
                locked_ratio <= ratio_shift; locked_sign <= direction_sign;
                locked_min_count <= min_count; locked_min_strips <= min_paired_strips;
                locked_y_begin <= strip_y_begin; locked_y_end <= strip_y_end;
                locked_left <= roi_left; locked_split <= roi_split; locked_right <= roi_right;
                expected_x <= 0; expected_y <= 0; pixels_seen <= 0;
            end else if (!finish && selected_event && active && current_error == 0) begin
                if (event_error != 0) begin current_error <= event_error; eof_seen <= 0; pixels_seen <= 0; end
                else begin
                    pixels_seen <= pixels_seen + lane_count;
                    if (event_metadata[1]) begin expected_x <= 0; expected_y <= expected_y + 13'd1; end
                    else expected_x <= expected_x + lane_count;
                    if (event_metadata[0]) eof_seen <= 1;
                end
            end
            for (reset_index = 0; reset_index < SIDES; reset_index = reset_index + 1) begin
                if (start || finish || (selected_event && active && current_error == 0 && event_error != 0)) begin
                    point_count[reset_index] <= 0; sum_native_x[reset_index] <= 0;
                    strength_sum[reset_index] <= 0; peak_strength[reset_index] <= 0;
                    peak_x[reset_index] <= 0; peak_y[reset_index] <= 0;
                end else if (selected_event && active && current_error == 0 && event_error == 0) begin
                    point_count[reset_index] <= next_count[reset_index];
                    sum_native_x[reset_index] <= next_sum_x[reset_index];
                    strength_sum[reset_index] <= next_strength_sum[reset_index];
                    peak_strength[reset_index] <= next_peak[reset_index];
                    peak_x[reset_index] <= next_peak_x[reset_index]; peak_y[reset_index] <= next_peak_y[reset_index];
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n || cancel || debug_clear) begin
            frames_started <= 0; frames_finished <= 0; frames_failed <= 0;
            record_drop_count <= 0; stray_terminal_count <= 0; first_fault_valid <= 0;
            first_fault_code <= 0; first_fault_context <= 0;
        end else begin
            if (start) frames_started <= frames_started + 32'd1;
            if (finish) begin
                frames_finished <= frames_finished + 32'd1;
                if (finish_error != 0) frames_failed <= frames_failed + 32'd1;
                if (!slot_free && record_drop_count != 32'hffffffff)
                    record_drop_count <= record_drop_count + 32'd1;
            end
            if ((frame_complete || frame_error) && !terminal_match)
                stray_terminal_count <= stray_terminal_count + 32'd1;
            if (!first_fault_valid && diagnostic_error != 0) begin
                first_fault_valid <= 1; first_fault_code <= diagnostic_error;
                first_fault_context <= diagnostic_context;
            end
        end
    end
    // Functional completion is independent of sparse-record capacity and debug.
    // Existing finish/error arithmetic is reused without alteration. Identity
    // borrows the owning locked context: it is stable throughout this pulse.
    assign terminal_identity = locked_context;
    always @(posedge clk) begin
        if (!rst_n || cancel) begin
            terminal_valid <= 0; terminal_error <= 0;
        end else begin
            terminal_valid <= finish;
            if (finish) begin
                terminal_error <= finish_error != 0;
            end
        end
    end
endmodule
