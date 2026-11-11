`timescale 1ns / 1ps

// Passive pre-enhancement native4 tap. Side traffic never controls main ready.
module neutral_observer #(
    parameter integer SOURCE_WIDTH = 1920,
    parameter integer SOURCE_HEIGHT = 1080,
    parameter [7:0] DARK_THRESHOLD = 8'd32,
    parameter [7:0] BRIGHT_THRESHOLD = 8'd224
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire i_tap_valid,
    input wire [95:0] i_tap_rgb,
    input wire [31:0] i_tap_luma,
    input wire [3:0] i_tap_keep,
    input wire i_tap_sof,
    input wire i_tap_eol,
    input wire i_tap_eof,
    input wire i_source_abort,
    input wire [159:0] i_context,
    input wire [31:0] i_exposure,
    input wire [15:0] i_gain,
    input wire [12:0] i_width,
    input wire [12:0] i_height,
    output wire o_pixel_valid,
    input wire i_pixel_ready,
    output wire [23:0] o_pixel_rgb,
    output wire [7:0] o_pixel_luma,
    output wire o_pixel_sof,
    output wire o_pixel_eol,
    output wire o_pixel_last,
    output wire [159:0] o_context,
    output wire [31:0] o_exposure,
    output wire [15:0] o_gain,
    output wire [12:0] o_source_width,
    output wire [12:0] o_source_height,
    output wire [12:0] o_observation_width,
    output wire [12:0] o_observation_height,
    output wire o_status_valid,
    input wire i_status_ready,
    output wire o_status_ok,
    output wire [7:0] o_status_error,
    output wire [15:0] o_status_pixels,
    output wire [15:0] o_status_delivered,
    output wire [31:0] o_status_sum_y,
    output wire [7:0] o_status_min_y,
    output wire [7:0] o_status_max_y,
    output wire [15:0] o_status_dark,
    output wire [15:0] o_status_bright,
    output wire o_busy,
    output wire o_reset_done,
    output wire [31:0] o_dropped_frames
);
    localparam integer OBS_WIDTH = SOURCE_WIDTH / 6;
    localparam integer OBS_HEIGHT = SOURCE_HEIGHT / 6;
    localparam integer OBS_PIXELS = OBS_WIDTH * OBS_HEIGHT;
    localparam integer PARAMETER_FAULT = SOURCE_WIDTH < 6 || SOURCE_HEIGHT < 6 ||
        SOURCE_WIDTH > 8190 || SOURCE_HEIGHT > 8190 || SOURCE_WIDTH % 6 != 0 ||
        SOURCE_HEIGHT % 6 != 0 || OBS_PIXELS > 65535;
    localparam [2:0] IDLE = 3'd0, CAPTURE = 3'd1, DRAIN = 3'd2, STATUS = 3'd3;
    reg [2:0] state, state_next;
    reg [2:0] reset_release;
    reg [12:0] source_x, source_y, observation_x;
    reg [2:0] phase_x, phase_y;
    reg source_complete;
    reg [9:0] queued_pixels;
    reg [15:0] sampled_pixels, delivered_pixels, dark_pixels, bright_pixels;
    reg [31:0] sum_y, dropped_frames;
    reg [7:0] min_y, max_y, error_code;
    reg [159:0] context_locked;
    reg [31:0] exposure_locked;
    reg [15:0] gain_locked;
    reg [12:0] width_locked, height_locked;

    wire fifo_full, fifo_empty, fifo_valid, fifo_write_done, fifo_read_done;
    wire fifo_overflow;
    wire [39:0] fifo_data;
    wire fifo_reset = !reset_release[2];
    wire fifo_ready = reset_release[2] && fifo_write_done && fifo_read_done;
    wire admitted_start = state == IDLE && i_tap_valid && i_tap_sof && fifo_ready;
    wire observed_beat = i_tap_valid && (state == CAPTURE || admitted_start);
    reg [2:0] tap_samples;
    reg [3:0] expected_keep, body_expected_keep;
    reg [1:0] sample_lane;
    reg lane_selected;
    reg [7:0] current_fault;
    wire [13:0] advanced_x = {1'b0, source_x} + tap_samples;
    wire body_row_final = advanced_x == SOURCE_WIDTH;
    wire body_frame_final = body_row_final && source_y == SOURCE_HEIGHT - 1;
    wire row_final = admitted_start ? tap_samples == SOURCE_WIDTH : body_row_final;
    wire frame_final = admitted_start ? tap_samples == SOURCE_WIDTH && SOURCE_HEIGHT == 1 : body_frame_final;
    wire metadata_fault = admitted_start && (PARAMETER_FAULT || i_width != SOURCE_WIDTH || i_height != SOURCE_HEIGHT);
    wire boundary_fault = observed_beat && (i_tap_keep != expected_keep || i_tap_eol != row_final || i_tap_eof != frame_final);
    wire new_sof_fault = state == CAPTURE && i_tap_valid && i_tap_sof;
    wire abort_fault = i_source_abort && (state == CAPTURE || state == DRAIN || admitted_start);
    wire selected_point = observed_beat && !admitted_start && phase_y == 3 && lane_selected && sample_lane < tap_samples;
    wire queue_fault = selected_point && fifo_full;
    wire overflow_fault = fifo_overflow && (state == CAPTURE || state == DRAIN);
    wire capture_fault = abort_fault || metadata_fault || new_sof_fault ||
                         boundary_fault || queue_fault || overflow_fault;
    // CAPTURE cannot admit another SOF. Its body geometry and queue decision
    // therefore need no IDLE/admitted_start mux or general fault priority cone.
    wire body_selected_point = phase_y == 3 && lane_selected && sample_lane < tap_samples;
    wire body_boundary_fault = i_tap_keep != body_expected_keep ||
        i_tap_eol != body_row_final || i_tap_eof != body_frame_final;
    wire body_end = i_source_abort || fifo_overflow || (i_tap_valid &&
        (i_tap_sof || body_boundary_fault || body_frame_final || (body_selected_point && fifo_full)));
    wire fifo_write_enable = state == CAPTURE && i_tap_valid && body_selected_point &&
        fifo_ready && !fifo_full && !i_source_abort && !i_tap_sof &&
        !body_boundary_fault && !fifo_overflow;
    wire fifo_read_enable = o_pixel_valid && i_pixel_ready;
    wire [7:0] selected_y = i_tap_luma[sample_lane * 8 +: 8];
    wire [23:0] selected_rgb = i_tap_rgb[sample_lane * 24 +: 24];
    wire selected_sof = sampled_pixels == 0;
    wire selected_eol = observation_x == OBS_WIDTH - 1;
    wire selected_last = sampled_pixels == OBS_PIXELS - 1;
    wire [39:0] fifo_write_data = {5'd0, selected_y, selected_last, selected_eol, selected_sof, selected_rgb};
    wire [3:0] next_phase_x = phase_x + tap_samples;
    wire [8:0] sum_low = {1'b0, sum_y[7:0]} + {1'b0, selected_y};
    wire sum_carry16 = sum_low[8] && (&sum_y[15:8]);
    wire sum_carry24 = sum_carry16 && (&sum_y[23:16]);
    wire status_fire = o_status_valid && i_status_ready;

    assign o_pixel_valid = fifo_ready && fifo_valid && !fifo_empty;
    assign o_pixel_rgb = fifo_data[23:0];
    assign o_pixel_sof = fifo_data[24];
    assign o_pixel_eol = fifo_data[25];
    assign o_pixel_last = fifo_data[26];
    assign o_pixel_luma = fifo_data[34:27];
    assign o_context = context_locked;
    assign o_exposure = exposure_locked;
    assign o_gain = gain_locked;
    assign o_source_width = width_locked;
    assign o_source_height = height_locked;
    assign o_observation_width = OBS_WIDTH;
    assign o_observation_height = OBS_HEIGHT;
    assign o_status_valid = state == STATUS;
    assign o_status_ok = error_code == 0;
    assign o_status_error = error_code;
    assign o_status_pixels = sampled_pixels;
    assign o_status_delivered = delivered_pixels;
    assign o_status_sum_y = sum_y;
    assign o_status_min_y = min_y;
    assign o_status_max_y = max_y;
    assign o_status_dark = dark_pixels;
    assign o_status_bright = bright_pixels;
    assign o_busy = state != IDLE;
    assign o_reset_done = fifo_ready;
    assign o_dropped_frames = dropped_frames;

    // Same local clock on both official async ports; only coordinated reset.
    control_fifo_40x512 u_observation_fifo (
        .di(fifo_write_data), .clkw(i_clk), .clkr(i_clk), .wrst(fifo_reset), .rrst(fifo_reset),
        .we(fifo_write_enable), .re(fifo_read_enable), .dout(fifo_data), .full_flag(fifo_full),
        .empty_flag(fifo_empty), .valid(fifo_valid), .wr_rst_done(fifo_write_done), .rd_rst_done(fifo_read_done),
        .overflow(fifo_overflow), .underflow(), .wr_success(), .afull(), .aempty(), .wrusedw(), .rdusedw());

    // Low-contiguous native4 keep and fixed center-lane selection.
    always @(*) begin
        case (i_tap_keep)
            4'h1: tap_samples = 1;
            4'h3: tap_samples = 2;
            4'h7: tap_samples = 3;
            4'hf: tap_samples = 4;
            default: tap_samples = 0;
        endcase
        // Constant body comparisons are also used directly by CAPTURE control.
        body_expected_keep = 4'hf;
        if (source_x == SOURCE_WIDTH-1) body_expected_keep = 4'h1;
        else if (source_x == SOURCE_WIDTH-2) body_expected_keep = 4'h3;
        else if (source_x == SOURCE_WIDTH-3) body_expected_keep = 4'h7;
        else if (source_x == SOURCE_WIDTH) body_expected_keep = 0;
        expected_keep = admitted_start ? 4'hf : body_expected_keep;
        sample_lane = 0;
        lane_selected = 1;
        case (phase_x)
            3'd0: sample_lane = 3;
            3'd1: sample_lane = 2;
            3'd2: sample_lane = 1;
            3'd3: sample_lane = 0;
            default: lane_selected = 0;
        endcase
    end

    // The first fault is retained. It affects only branch admission/capture.
    always @(*) begin
        current_fault = 0;
        if (abort_fault) current_fault = 3;
        else if (metadata_fault) current_fault = 1;
        else if (new_sof_fault) current_fault = 4;
        else if (boundary_fault) current_fault = 5;
        else if (queue_fault) current_fault = 2;
        else if (overflow_fault) current_fault = 6;
    end

    always @(*) begin
        state_next = state;
        case (state)
            IDLE: if (admitted_start) state_next = capture_fault ? DRAIN : CAPTURE;
            CAPTURE: if (body_end) state_next = DRAIN;
            DRAIN: if (queued_pixels == 0) state_next = STATUS;
            STATUS: if (status_fire) state_next = IDLE;
            default: state_next = DRAIN;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin state <= IDLE; reset_release <= 0; end
        else begin state <= state_next; reset_release <= {reset_release[1:0], 1'b1}; end
    end

    // The metadata bundle is meaningful only with a published pixel/status.
    // Its owner state and FIFO release still assert asynchronously; clearing
    // these payload flops on a local edge keeps their ASR load off that tree.
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            context_locked <= 0; exposure_locked <= 0; gain_locked <= 0;
            width_locked <= 0; height_locked <= 0;
        end else if (admitted_start) begin
            context_locked <= i_context; exposure_locked <= i_exposure; gain_locked <= i_gain;
            width_locked <= i_width; height_locked <= i_height;
        end
    end

    // Scalar metadata/statistics are owned until status acceptance. No source
    // event except global reset can clear queued or already presented pixels.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            source_x <= 0; source_y <= 0; observation_x <= 0; phase_x <= 0; phase_y <= 0;
            source_complete <= 0; queued_pixels <= 0; sampled_pixels <= 0; delivered_pixels <= 0;
            dark_pixels <= 0; bright_pixels <= 0; sum_y <= 0; dropped_frames <= 0;
            min_y <= 255; max_y <= 0; error_code <= 0;
        end else begin
            if (i_tap_valid && i_tap_sof && !admitted_start && dropped_frames != 32'hffffffff)
                dropped_frames <= dropped_frames + 1'b1;
            if (admitted_start) begin
                source_x <= 0; source_y <= 0; observation_x <= 0; phase_x <= 0; phase_y <= 0;
                source_complete <= 0; queued_pixels <= 0; sampled_pixels <= 0; delivered_pixels <= 0;
                dark_pixels <= 0; bright_pixels <= 0; sum_y <= 0; min_y <= 255; max_y <= 0;
                error_code <= current_fault;
            end else begin
                case ({fifo_write_enable, fifo_read_enable})
                    2'b10: queued_pixels <= queued_pixels + 1'b1;
                    2'b01: queued_pixels <= queued_pixels - 1'b1;
                    default: queued_pixels <= queued_pixels;
                endcase
                if (fifo_read_enable) delivered_pixels <= delivered_pixels + 1'b1;
                if (capture_fault && error_code == 0) error_code <= current_fault;
                if (state > STATUS && error_code == 0) error_code <= 8;
                if (state == DRAIN && state_next == STATUS && error_code == 0 && !capture_fault &&
                    (!source_complete || sampled_pixels != OBS_PIXELS || delivered_pixels != OBS_PIXELS))
                    error_code <= 7;
            end
            // source_x is private geometry, never a published statistic. A bad
            // observed beat enters DRAIN on this edge and cannot admit pixels;
            // the next admitted SOF starts its coordinate anew. Keep the late
            // fault decision out of this coordinate register's clock enable.
            if (observed_beat)
                source_x <= row_final ? 13'd0 :
                            (admitted_start ? {10'd0, tap_samples} : advanced_x[12:0]);
            if (observed_beat && !capture_fault) begin
                if (row_final) begin
                    phase_x <= 0;
                    source_y[7:0] <= admitted_start ? 8'd1 : source_y[7:0] + 1'b1;
                    source_y[12:8] <= admitted_start ? 5'd0 : source_y[12:8] + (&source_y[7:0]);
                    phase_y <= admitted_start ? 3'd1 : (phase_y == 5 ? 3'd0 : phase_y + 1'b1);
                end else begin
                    phase_x <= admitted_start ? tap_samples : (next_phase_x >= 6 ? next_phase_x - 6 : next_phase_x);
                end
                if (frame_final) source_complete <= 1;
            end
            if (fifo_write_enable) begin
                sampled_pixels <= sampled_pixels + 1'b1;
                // Parallel byte carries bound the late tap/abort enable path
                // without delaying any accepted-pixel statistic.
                sum_y[7:0] <= sum_low[7:0];
                sum_y[15:8] <= sum_y[15:8] + sum_low[8];
                sum_y[23:16] <= sum_y[23:16] + sum_carry16;
                sum_y[31:24] <= sum_y[31:24] + sum_carry24;
                if (selected_y < min_y) min_y <= selected_y;
                if (selected_y > max_y) max_y <= selected_y;
                if (selected_y < DARK_THRESHOLD) dark_pixels <= dark_pixels + 1'b1;
                if (selected_y >= BRIGHT_THRESHOLD) bright_pixels <= bright_pixels + 1'b1;
                observation_x <= selected_eol ? 13'd0 : observation_x + 1'b1;
            end
        end
    end
endmodule
