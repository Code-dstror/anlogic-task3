`timescale 1ns / 1ps

// ISP RGB888/4PPC -> grayscale -> Gaussian -> temporal histogram EQ -> JPEG
// admission. All interfaces use clk. This is a cancellable camera epoch:
// m_frame_error explicitly invalidates/cancels any stalled pixels of that frame.
module preprocess_pipeline4 #(
    parameter integer MAX_WIDTH = 3840,
    parameter integer MAX_HEIGHT = 2160,
    parameter integer CAMERA_CONTEXT_ENABLE = 0,
    parameter integer SHARED_Y_PROFILE = 0,
    parameter integer HISTORY_RESET_ENABLE = (CAMERA_CONTEXT_ENABLE != 0) || (SHARED_Y_PROFILE != 0),
    parameter integer GAUSSIAN_WINDOW_TAP_ENABLE = 0,
    parameter integer NEUTRAL_TAP_ENABLE = 0,
    parameter integer GAUSSIAN_WINDOW_HANDSHAKE_ENABLE = 0,
    // Compile-time stage-one profile: shared Y/Gray without Gaussian/HE storage.
    parameter integer GRAY_ONLY_ENABLE = 0,
    parameter integer HE_SOURCE_QUALIFY_ENABLE = 0,
    parameter integer HE_FIXED_CONFIG_SESSION_ENABLE = 0,
    parameter integer HE_COLOR_PRESERVE = 0
) (
    input wire clk, rst_n,
    input wire [12:0] cfg_width, cfg_height,
    input wire [2:0] cfg_enable,
    input wire s_valid,
    output wire s_ready,
    input wire [95:0] s_data,
    input wire s_sof, s_eol,
    input wire s_frame_done, s_frame_error,
    output wire m_valid,
    input wire m_ready,
    output wire [95:0] m_data,
    output wire m_sof, m_eol,
    output reg m_frame_done, m_frame_error,
    input wire cfg_camera_id, cfg_history_reset,
    output wire m_camera_id,
    output wire [31:0] m_luma,
    // Includes internal held tokens even when final m_valid is not presented.
    output wire o_presented_valid,
    // Passive accepted pre-enhancement tap; it never controls main ready.
    output wire o_neutral_valid,
    output wire [95:0] o_neutral_rgb,
    output wire [31:0] o_neutral_luma,
    output wire o_neutral_sof, o_neutral_eol, o_neutral_eof,
    // Optional common-transfer fork of the existing monochrome window.
    input wire i_window_ready,
    output wire o_window_valid,
    output wire o_window_available,
    output wire [287:0] o_window,
    output wire [31:0] o_window_luma,
    output wire o_window_sof, o_window_eol,
    // Qualified mono profile only. All inputs are synchronous to clk.
    input wire i_he_history_rst_n,
    input wire [141:0] cfg_he_context,
    input wire cfg_he_history_eligible,
    input wire [31:0] cfg_he_capture_sequence,
    input wire i_he_source_valid, i_he_source_camera, i_he_source_ok,
    input wire [31:0] i_he_source_session, i_he_source_epoch, i_he_source_sequence,
    output wire o_he_source_ready, o_he_history_used, o_he_lut_valid,
    output wire o_he_source_owner_match, o_he_source_accepted,
    output wire o_he_source_decision_valid, o_he_source_decision_collect,
    output wire [31:0] o_he_source_decision_capture,
    output wire o_he_source_cancel_done,
    output wire [31:0] o_he_lut_source_sequence
);
    wire pipeline_rst_n = rst_n && (!HE_SOURCE_QUALIFY_ENABLE || i_he_history_rst_n);
    wire history_rst_n = HE_SOURCE_QUALIFY_ENABLE ? i_he_history_rst_n : rst_n;
    reg [141:0] frame_he_context;
    reg frame_he_history_eligible;
    reg [31:0] frame_he_capture;
    reg he_started;
    wire he_start, he_source_ready;
    wire [1:0] context_presented;
    wire requested_gray = (cfg_enable[0] && !(HE_COLOR_PRESERVE && cfg_enable[2] && !cfg_enable[1])) ||
                          (!GRAY_ONLY_ENABLE && SHARED_Y_PROFILE && cfg_enable[1]);
    reg [1:0] previous_input_mode;
    reg previous_input_mode_valid;
    reg active, input_complete, source_complete, output_complete;
    reg [12:0] frame_width, frame_height;
    reg [2:0] frame_enable;
    reg frame_camera, frame_history_reset;
    reg [2:0] previous_enable0, previous_enable1;
    reg [1:0] previous_enable_valid;
    wire requested_camera = CAMERA_CONTEXT_ENABLE ? cfg_camera_id : 1'b0;
    wire selected_camera = active ? frame_camera : requested_camera;
    reg [10:0] input_x;
    reg [12:0] input_y, output_y;
    wire [12:0] width = active ? frame_width : cfg_width;
    wire [12:0] height = active ? frame_height : cfg_height;
    wire [2:0] enables = active ? frame_enable : cfg_enable;
    wire cfg_ok = cfg_width >= 4 && cfg_width <= MAX_WIDTH &&
                  cfg_width[1:0] == 0 && cfg_height != 0 &&
                  cfg_height <= MAX_HEIGHT;
    wire expected_eol = input_x == (width[12:2] - 1'b1);
    wire input_last = expected_eol && input_y == height - 1'b1;
    wire bad_start = !active && s_valid && s_sof &&
                     (!cfg_ok || s_eol != (cfg_width == 4));
    wire bad_body = active && !input_complete && s_valid &&
                    (s_sof || s_eol != expected_eol);
    wire malformed = bad_start || bad_body;
    wire g_ready;
    wire input_fire = s_valid && s_ready && !malformed &&
                      (active || s_sof) && !s_frame_error;
    // Check the latched status one cycle later: this permits status and last
    // input transfer on the same edge without a ready -> clear -> ready loop.
    wire premature_done = active && source_complete && !input_complete;
    wire histogram_error;
    wire cancel = s_frame_error || malformed || premature_done || histogram_error;
    // This small domain discriminator survives an ordinary frame reset.
    always @(posedge clk or negedge history_rst_n) begin
        if (!history_rst_n) begin previous_input_mode <= 0; previous_input_mode_valid <= 0; end
        else if (pipeline_rst_n && input_fire && !active) begin
            previous_input_mode <= {cfg_enable[1],requested_gray};
            previous_input_mode_valid <= 1;
        end
    end
    always @(posedge clk or negedge pipeline_rst_n) begin
        if (!pipeline_rst_n) begin frame_he_context <= 0; frame_he_capture <= 0; he_started <= 0; frame_he_history_eligible <= 0; end
        else if (cancel) he_started <= 0;
        else begin
            if (input_fire && !active) begin
                frame_he_context <= cfg_he_context;
                frame_he_history_eligible <= HE_FIXED_CONFIG_SESSION_ENABLE && cfg_he_history_eligible;
                frame_he_capture <= cfg_he_capture_sequence;
                he_started <= 0;
            end else if (he_start) he_started <= 1;
        end
    end
    // Idle/canceled frames never hold an old authentic event hostage. During
    // a live frame, wait until the histogram owner exists before forwarding.
    assign o_he_source_ready = HE_SOURCE_QUALIFY_ENABLE && pipeline_rst_n && !cancel &&
                               he_source_ready && (active ? he_started : !(s_valid && s_sof));
    generate if (HE_SOURCE_QUALIFY_ENABLE && (CAMERA_CONTEXT_ENABLE || !SHARED_Y_PROFILE || GRAY_ONLY_ENABLE)) begin : g_invalid_he_profile
        INVALID_QUALIFIED_HE_PROFILE unsupported_profile();
    end endgenerate
    assign s_ready = pipeline_rst_n && !s_frame_error &&
                     (malformed ? 1'b1 :
                     (active ? (!input_complete && g_ready) :
                     (!s_sof || g_ready)));
    wire g_valid, g_sof, g_eol, g_down_ready;
    wire [95:0] g_data;
    wire [95:0] g_original;
    reg [12:0] neutral_row;
    wire [31:0] g_luma,a_luma,b_luma,c_luma,h_luma,o_luma;
    wire a_valid, a_ready, a_sof, a_eol;
    wire [95:0] a_data;
    wire b_valid, b_ready, b_sof, b_eol, b_queue_ready;
    wire native_window_valid;
    wire tap_ready = GAUSSIAN_WINDOW_HANDSHAKE_ENABLE ? i_window_ready : 1'b1;
    assign b_ready = b_queue_ready && tap_ready;
    assign o_window_valid = GAUSSIAN_WINDOW_HANDSHAKE_ENABLE && b_valid && b_queue_ready;
    assign o_window_available = native_window_valid;
    assign o_window_luma = b_luma;
    assign o_window_sof = b_sof;
    assign o_window_eol = b_eol;
    wire [95:0] b_data;
    wire c_valid, c_ready, c_sof, c_eol;
    wire [95:0] c_data;
    wire h_valid, h_ready, h_sof, h_eol;
    wire [95:0] h_data;
    wire [1:0] context_valid,context_ready,context_sof,context_eol,context_error;
    wire [95:0] context_data0,context_data1;
    wire [31:0] context_luma0,context_luma1;
    wire o_valid, o_sof, o_eol;
    wire [95:0] o_data;
    assign m_valid = o_valid && active && !cancel;
    assign m_data = o_data;
    assign m_sof = o_sof;
    assign m_eol = o_eol;
    assign m_camera_id = frame_camera;
    assign m_luma = o_luma;
    wire output_fire = m_valid && m_ready;
    wire output_last = output_fire && m_eol && output_y == frame_height - 1'b1;

    assign o_neutral_valid = NEUTRAL_TAP_ENABLE && g_valid && g_down_ready && !cancel;
    assign o_neutral_rgb = g_original;
    assign o_neutral_luma = NEUTRAL_TAP_ENABLE ? g_luma : 32'd0;
    assign o_neutral_sof = NEUTRAL_TAP_ENABLE && g_sof;
    assign o_neutral_eol = NEUTRAL_TAP_ENABLE && g_eol;
    assign o_neutral_eof = NEUTRAL_TAP_ENABLE && g_eol && neutral_row == height - 1'b1;
    always @(posedge clk or negedge pipeline_rst_n) begin
        if (!pipeline_rst_n) neutral_row <= 0;
        else if (cancel) neutral_row <= 0;
        else if (o_neutral_valid && g_eol)
            neutral_row <= o_neutral_eof ? 13'd0 : neutral_row + 1'b1;
    end

    preprocess_gray4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .NEUTRAL_TAP_ENABLE(NEUTRAL_TAP_ENABLE)) u_gray (
        .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel),
        .enable((enables[0] && !(HE_COLOR_PRESERVE && enables[2] && !enables[1])) ||
                (!GRAY_ONLY_ENABLE && SHARED_Y_PROFILE && enables[1])),
        .width(width),.height(height),.s_valid(s_valid && (active || s_sof) &&
        !input_complete && !malformed && !premature_done),.s_ready(g_ready),
        .s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.m_valid(g_valid),
        .m_ready(g_down_ready),.m_data(g_data),.m_sof(g_sof),.m_eol(g_eol),.m_luma(g_luma),
        .m_original_data(g_original)
    );
    preprocess_stream_fifo2 #(.LUMA_SIDEBAND_ENABLE(1)) u_gray_queue (
        .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel),.s_valid(g_valid),.s_ready(g_down_ready),
        .s_data(g_data),.s_sof(g_sof),.s_eol(g_eol),.m_valid(a_valid),.m_ready(a_ready),
        .m_data(a_data),.m_sof(a_sof),.m_eol(a_eol),.s_luma(g_luma),.m_luma(a_luma)
    );
    assign o_presented_valid = g_valid || a_valid || b_valid || c_valid ||
        (|context_valid) || (|context_presented) || o_valid;
    generate if (GRAY_ONLY_ENABLE != 0) begin : g_gray_only
        // Keep the shared-Y arithmetic, neutral tap and epoch completion owner.
        // Absent enhancement stages cannot create a window token or backpressure.
        assign a_ready = h_ready;
        assign h_valid = a_valid;
        assign h_data = a_data;
        assign h_luma = a_luma;
        assign h_sof = a_sof;
        assign h_eol = a_eol;
        assign histogram_error = 1'b0;
        assign b_valid = 1'b0; assign b_data = 96'd0; assign b_luma = 32'd0;
        assign b_sof = 1'b0; assign b_eol = 1'b0; assign b_queue_ready = 1'b0;
        assign native_window_valid = 1'b0; assign o_window = 288'd0;
        assign c_valid = 1'b0; assign c_data = 96'd0; assign c_luma = 32'd0;
        assign c_sof = 1'b0; assign c_eol = 1'b0; assign c_ready = 1'b0;
        assign context_valid = 2'd0; assign context_ready = 2'd0;
        assign context_sof = 2'd0; assign context_eol = 2'd0; assign context_error = 2'd0;
        assign context_data0 = 96'd0; assign context_data1 = 96'd0;
        assign context_luma0 = 32'd0; assign context_luma1 = 32'd0;
        assign context_presented = 2'd0;
        assign he_start = 1'b0; assign he_source_ready = 1'b0;
        assign o_he_history_used = 1'b0; assign o_he_lut_valid = 1'b0;
        assign o_he_lut_source_sequence = 32'd0;
        assign o_he_source_owner_match=0;assign o_he_source_accepted=0;
        assign o_he_source_decision_valid=0;assign o_he_source_decision_collect=0;
        assign o_he_source_decision_capture=0;assign o_he_source_cancel_done=1;
    end else begin : g_full_preprocess
    preprocess_gaussian4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .MONOCHROME_STORAGE(SHARED_Y_PROFILE),.WINDOW_TAP_ENABLE(GAUSSIAN_WINDOW_TAP_ENABLE)) u_gauss (
        .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel),.enable(enables[1]),
        .width(width),.height(height),.s_valid(a_valid),.s_ready(a_ready),
        .s_data(a_data),.s_sof(a_sof),.s_eol(a_eol),.m_valid(b_valid),
        .m_ready(b_ready),.m_data(b_data),.m_sof(b_sof),.m_eol(b_eol),.s_luma(a_luma),.m_luma(b_luma),
        .m_window_valid(native_window_valid),.m_window(o_window)
    );
    preprocess_stream_fifo2 #(.LUMA_SIDEBAND_ENABLE(1)) u_gauss_queue (
        .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel),.s_valid(b_valid && tap_ready),.s_ready(b_queue_ready),
        .s_data(b_data),.s_sof(b_sof),.s_eol(b_eol),.m_valid(c_valid),.m_ready(c_ready),
        .m_data(c_data),.m_sof(c_sof),.m_eol(c_eol),.s_luma(b_luma),.m_luma(c_luma)
    );
    assign c_ready = selected_camera ? context_ready[1] : context_ready[0];
    assign h_valid = selected_camera ? context_valid[1] : context_valid[0];
    assign h_data = selected_camera ? context_data1 : context_data0;
    assign h_luma = selected_camera ? context_luma1 : context_luma0;
    assign h_sof = selected_camera ? context_sof[1] : context_sof[0];
    assign h_eol = selected_camera ? context_eol[1] : context_eol[0];
    assign histogram_error = selected_camera ? context_error[1] : context_error[0];
    preprocess_hist_eq4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .EXTERNAL_LUMA_ENABLE(SHARED_Y_PROFILE),.HISTORY_RESET_ENABLE(HISTORY_RESET_ENABLE),
        .SOURCE_QUALIFY_ENABLE(HE_SOURCE_QUALIFY_ENABLE),.HE_COLOR_PRESERVE(HE_COLOR_PRESERVE),
        .FIXED_CONFIG_SESSION_ENABLE(HE_FIXED_CONFIG_SESSION_ENABLE)) u_hist (
        .clk(clk),.rst_n(history_rst_n),
        .clear((cancel || (HE_SOURCE_QUALIFY_ENABLE && !rst_n)) && !selected_camera),.enable(enables[2]),
        .width(width),.height(height),.s_valid(c_valid && !selected_camera),.s_ready(context_ready[0]),
        .s_data(c_data),.s_sof(c_sof),.s_eol(c_eol),.m_valid(context_valid[0]),
        .m_ready(h_ready && !selected_camera),.m_data(context_data0),
        .m_sof(context_sof[0]),.m_eol(context_eol[0]),.s_luma(c_luma),.m_luma(context_luma0),
        .history_reset(frame_history_reset),.statistics_error(context_error[0]),
        .lut_valid(o_he_lut_valid),.lut_epoch(o_he_lut_source_sequence),.stats_skipped_frames(),.stats_overflow_count(),
        .s_history_context(frame_he_context),.s_capture_sequence(frame_he_capture),
        .s_history_eligible(frame_he_history_eligible),
        .source_valid(i_he_source_valid && o_he_source_ready),.source_camera(i_he_source_camera),
        .source_ok(i_he_source_ok),.source_session(i_he_source_session),.source_epoch(i_he_source_epoch),
        .source_capture_sequence(i_he_source_sequence),.o_frame_history_used(o_he_history_used),
        .o_presented_valid(context_presented[0]),.o_frame_started(he_start),.o_source_ready(he_source_ready),
        .o_source_owner_match(o_he_source_owner_match),.o_source_accepted(o_he_source_accepted),
        .o_source_decision_valid(o_he_source_decision_valid),.o_source_decision_collect(o_he_source_decision_collect),
        .o_source_decision_capture(o_he_source_decision_capture),.o_source_cancel_done(o_he_source_cancel_done),
        .o_divider_ready(),.stats_unqualified_frames(),.stats_source_rejects(),.stats_canceled_jobs()
    );
    if (CAMERA_CONTEXT_ENABLE) begin : g_camera1
        preprocess_hist_eq4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
            .EXTERNAL_LUMA_ENABLE(SHARED_Y_PROFILE),.HISTORY_RESET_ENABLE(HISTORY_RESET_ENABLE)) u_hist (
            .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel && selected_camera),.enable(enables[2]),
            .width(width),.height(height),.s_valid(c_valid && selected_camera),.s_ready(context_ready[1]),
            .s_data(c_data),.s_sof(c_sof),.s_eol(c_eol),.m_valid(context_valid[1]),
            .m_ready(h_ready && selected_camera),.m_data(context_data1),
            .m_sof(context_sof[1]),.m_eol(context_eol[1]),.s_luma(c_luma),.m_luma(context_luma1),
            .history_reset(frame_history_reset),.statistics_error(context_error[1]),
            .lut_valid(),.lut_epoch(),.stats_skipped_frames(),.stats_overflow_count(),
            .o_presented_valid(context_presented[1]),.s_history_context(142'd0),.s_capture_sequence(32'd0),
            .s_history_eligible(1'b0),
            .source_valid(1'b0),.source_camera(1'b0),.source_ok(1'b0),.source_session(32'd0),
            .source_epoch(32'd0),.source_capture_sequence(32'd0),.o_frame_history_used(),
            .o_frame_started(),.o_source_ready(),.o_divider_ready(),.stats_unqualified_frames(),
            .stats_source_rejects(),.stats_canceled_jobs());
    end else begin : g_single_camera
        assign context_ready[1] = 1'b0; assign context_valid[1] = 1'b0;
        assign context_sof[1] = 1'b0; assign context_eol[1] = 1'b0;
        assign context_error[1] = 1'b0; assign context_data1 = 96'd0;
        assign context_luma1 = 32'd0;
        assign context_presented[1] = 1'b0;
    end
    end endgenerate
    preprocess_stream_fifo2 #(.LUMA_SIDEBAND_ENABLE(1)) u_output_queue (
        .clk(clk),.rst_n(pipeline_rst_n),.clear(cancel),.s_valid(h_valid),.s_ready(h_ready),
        .s_data(h_data),.s_sof(h_sof),.s_eol(h_eol),.m_valid(o_valid),
        .m_ready(m_ready && active),.m_data(o_data),.m_sof(o_sof),.m_eol(o_eol),
        .s_luma(h_luma),.m_luma(o_luma)
    );

    always @(posedge clk or negedge pipeline_rst_n) begin
        if (!pipeline_rst_n) begin
            active <= 0; input_complete <= 0; source_complete <= 0; output_complete <= 0;
            frame_width <= 0; frame_height <= 0; frame_enable <= 0;
            frame_camera <= 0; frame_history_reset <= 0;
            previous_enable0 <= 0; previous_enable1 <= 0; previous_enable_valid <= 0;
            input_x <= 0; input_y <= 0; output_y <= 0;
            m_frame_done <= 0; m_frame_error <= 0;
        end else begin
            m_frame_done <= 0;
            m_frame_error <= 0;
            if (cancel) begin
                active <= 0; input_complete <= 0; source_complete <= 0; output_complete <= 0;
                input_x <= 0; input_y <= 0; output_y <= 0;
                m_frame_error <= 1;
            end else begin
                if (input_fire) begin
                    if (!active) begin
                        active <= 1;
                        frame_width <= cfg_width;
                        frame_height <= cfg_height;
                        frame_enable <= cfg_enable;
                        frame_camera <= requested_camera;
                        frame_history_reset <= HE_SOURCE_QUALIFY_ENABLE ? (cfg_history_reset ||
                            (previous_input_mode_valid && previous_input_mode != {cfg_enable[1],requested_gray})) :
                            (HISTORY_RESET_ENABLE && (cfg_history_reset ||
                            (previous_enable_valid[requested_camera] && cfg_enable !=
                            (requested_camera ? previous_enable1 : previous_enable0))));
                        previous_enable_valid[requested_camera] <= 1'b1;
                        if (requested_camera) previous_enable1 <= cfg_enable;
                        else previous_enable0 <= cfg_enable;
                        source_complete <= s_frame_done;
                        output_complete <= 0;
                        output_y <= 0;
                    end
                    if (s_eol) begin
                        input_x <= 0;
                        input_y <= input_y + 1'b1;
                    end else input_x <= input_x + 1'b1;
                    if (input_last) input_complete <= 1;
                end
                if (s_frame_done && active) source_complete <= 1;
                if (output_fire && m_eol) output_y <= output_y + 1'b1;
                if (output_last) output_complete <= 1;
                if (active && (source_complete || s_frame_done) &&
                    (output_complete || output_last)) begin
                    // Registered pulse follows the final output transfer;
                    // admission deasserts ready while done is asserted.
                    m_frame_done <= 1;
                    active <= 0; input_complete <= 0; source_complete <= 0; output_complete <= 0;
                    input_x <= 0; input_y <= 0; output_y <= 0;
                end
            end
        end
    end
endmodule
