// Internal START contract only; not an interpretation of legacy wire CFG bits.
// Qualified r1 color image adapter plus actual F22 and independently enabled F23.
module stage3_filter_color_analysis4 #(
    parameter integer LANE_MONO_PRESET = 0,
    parameter integer F22_FIXED1080P_ENABLE = 0
) (
    input clk, rst_n, cancel,
    input start_valid, output start_ready,
    input [12:0] cfg_width, cfg_height,
    input cfg_gray, cfg_legacy_gaussian, cfg_color_filter, cfg_multiscale, cfg_lane,
    input [159:0] cfg_context,
    input [10:0] cfg_threshold, cfg_gx_min,
    input [1:0] cfg_ratio, cfg_sign,
    input [19:0] cfg_min_count, input [3:0] cfg_min_strips,
    input [51:0] cfg_y_begin, cfg_y_end, cfg_left, cfg_split, cfg_right,
    input source_error,
    input s_valid, output s_ready,
    input [95:0] s_rgb, input [31:0] s_y, input s_sof, s_eol,
    output m_valid, input m_ready,
    output [95:0] m_rgb, output [31:0] m_y, output m_sof, m_eol,
    output busy, frame_complete, frame_error, output [3:0] error_code,
    output [159:0] terminal_context,
    output pyramid_valid,pyramid_pending, input pyramid_ready, output [683:0] pyramid_data,
    output lane_valid, input lane_ready, output [176:0] lane_data,
    input lane_read_enable,input [8:0] lane_read_index,
    output [39:0] lane_read_data,output lane_read_valid,
    output [31:0] pyramid_drops, lane_drops, lane_started, lane_finished, lane_failed
);
    wire analysis_start, analysis_ready, analysis_cancel, selected_lane;
    wire pyramid_start_ready;
    wire [12:0] analysis_width, analysis_height;
    wire [159:0] analysis_context;
    wire a_valid, a_ready, a_sof, a_eol;
    wire [143:0] a_strip;
    wire [31:0] a_y;
    wire f22_complete, f22_error;
    wire [7:0] f22_error_code;
    wire [159:0] f22_identity;
    wire f23_terminal, f23_error;
    wire [159:0] f23_identity;
    reg lane_active, f22_done, f23_done;
    // The image adapter may stop on a bad/truncated source after admission.
    // Its cancel ends pixel work, but cannot revoke an owned sparse result.
    // Reuse F22's source-error terminal so both enabled consumers publish
    // their actual failed frame and hold it until the record JOIN takes it.
    wire results_empty = !pyramid_pending && !lane_valid;
    assign analysis_ready = pyramid_start_ready && results_empty;
    wire analysis_start_fire = analysis_start && analysis_ready;
    wire identity_error = (f22_complete || f22_error) && f22_identity != terminal_context ||
        lane_active && f23_terminal && f23_identity != terminal_context;
    // A local sparse extraction failure is a normal terminal descriptor and
    // must not reject an otherwise intact image/JPEG SOURCE.
    wire joint_error = f22_error || identity_error;
    wire joint_complete = f22_done && (!lane_active || f23_done);
    always @(posedge clk) begin
        if (!rst_n) begin lane_active<=0;f22_done<=0;f23_done<=0;end
        else if (analysis_start_fire) begin lane_active<=selected_lane;f22_done<=0;f23_done<=0;end
        else begin
            if (f22_complete) f22_done<=1;
            if (lane_active && f23_terminal) f23_done<=1;
        end
    end
    stage3_filter_color4 #(.WINDOW_STRIP_ENABLE(1)) adapter (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.start_valid(start_valid),.start_ready(start_ready),
        .cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_gray(cfg_gray),
        .cfg_legacy_gaussian(cfg_legacy_gaussian),.cfg_color_filter(cfg_color_filter),.cfg_multiscale(cfg_multiscale),.cfg_lane(cfg_lane),.cfg_context(cfg_context),
        .analysis_start_valid(analysis_start),.analysis_start_ready(analysis_ready),
        .analysis_width(analysis_width),.analysis_height(analysis_height),.analysis_context(analysis_context),
        .analysis_lane(selected_lane),.analysis_cancel(analysis_cancel),
        .analysis_complete(joint_complete),.analysis_error(joint_error),.source_error(source_error),
        .s_valid(s_valid),.s_ready(s_ready),.s_rgb(s_rgb),.s_y(s_y),.s_sof(s_sof),.s_eol(s_eol),
        .m_valid(m_valid),.m_ready(m_ready),.m_rgb(m_rgb),.m_y(m_y),.m_sof(m_sof),.m_eol(m_eol),
        .a_valid(a_valid),.a_ready(a_ready),.a_window(a_strip),.a_filtered_y(a_y),.a_sof(a_sof),.a_eol(a_eol),
        .busy(busy),.frame_complete(frame_complete),.frame_error(frame_error),.error_code(error_code),
        .terminal_context(terminal_context));
    wire low_valid;
    wire [220:0] low_metadata;
    wire [43:0] low_gx, low_gy, low_magnitude;
    wire [31:0] low_center_y;
    full_filter_multiscale4 #(.WINDOW_STRIP_ENABLE(1),.FIXED1080P_ENABLE(F22_FIXED1080P_ENABLE)) pyramid (
        .clk(clk),.rst_n(rst_n),.cancel(1'b0),
        .start_valid(analysis_start && results_empty),.start_ready(pyramid_start_ready),
        .start_width(analysis_width),.start_height(analysis_height),.start_threshold(cfg_threshold),.start_context(analysis_context),
        .s_valid(a_valid),.s_ready(a_ready),.s_window_valid(1'b1),.s_window(a_strip),
        .s_filtered_y(a_y),.s_keep(4'hf),.s_sof(a_sof),.s_eol(a_eol),.source_error(analysis_cancel),
        .record_valid(pyramid_valid),.record_pending(pyramid_pending),.record_ready(pyramid_ready),.record_data(pyramid_data),
        .frame_complete(f22_complete),.frame_error(f22_error),.frame_error_code(f22_error_code),.frame_event_context(f22_identity),
        .low_event_valid(low_valid),.low_event_metadata(low_metadata),.low_event_gx(low_gx),.low_event_gy(low_gy),.low_event_magnitude(low_magnitude),
        .low_event_filtered_y(),.low_event_center_y(low_center_y),.low_event_native_x(),.low_event_native_y(),
        .full_event_valid(),.full_event_metadata(),.full_event_filtered_y(),.full_event_gx(),.full_event_gy(),
        .full_event_magnitude(),.full_event_native_x(),.full_event_native_y(),
        .debug_poll(1'b0),.debug_clear_firstfault(1'b0),.debug_poll_count(),.record_drop_count(pyramid_drops),
        .completed_count(),.failed_count(),.native_stall_count(),.firstfault_code(),.firstfault_context(),
        .first_congestion_context(),.max_low_resident(),.max_grant_wait());
    wire selected_quarter=low_valid&&lane_active&&low_metadata[60:59]==2;
    wire [7:0] hints;
    wire hints_valid,hints_error;
    lane_mark_hint4 marks(.clk(clk),.rst_n(rst_n),.clear(1'b0),
        .start(analysis_start_fire&&selected_lane),.enable(lane_active),
        .pixel_fire(s_valid&&s_ready),.pixel_rgb(s_rgb),.pixel_eol(s_eol),
        .query(selected_quarter),.query_x(low_metadata[28:20]),.query_y(low_metadata[15:7]),
        .hint(hints),.hint_valid(hints_valid),.alignment_error(hints_error));
    reg quarter_delayed;
    reg [4:0] quarter_bad_parts;
    wire quarter_bad=|quarter_bad_parts;
    reg [8:0] quarter_x,quarter_y;
    reg [43:0] quarter_gx,quarter_gy;
    reg [31:0] quarter_center;
    always @(posedge clk)begin
        if(!rst_n||analysis_start_fire)quarter_delayed<=0;
        else begin
            quarter_delayed<=selected_quarter;
            if(selected_quarter)begin
                quarter_x<=low_metadata[28:20];quarter_y<=low_metadata[15:7];
                quarter_gx<=low_gx;quarter_gy<=low_gy;quarter_center<=low_center_y;
                // Each predicate is sampled on the same event edge as the data.
                // Split wide identity equality from shape checks; only a
                // five-input OR remains between this bank and the lane FIFO.
                quarter_bad_parts[0]<=low_metadata[100:61]!=analysis_context[39:0];
                quarter_bad_parts[1]<=low_metadata[140:101]!=analysis_context[79:40];
                quarter_bad_parts[2]<=low_metadata[180:141]!=analysis_context[119:80];
                quarter_bad_parts[3]<=low_metadata[220:181]!=analysis_context[159:120];
                quarter_bad_parts[4]<=low_metadata[58:46]!=480||
                    low_metadata[45:33]!=270||low_metadata[6:3]!=15||
                    low_metadata[32:29]!=0||low_metadata[19:16]!=0||
                    low_metadata[2]!=(low_metadata[32:20]==0&&low_metadata[19:7]==0)||
                    low_metadata[1]!=(low_metadata[32:20]==476)||
                    low_metadata[0]!=(low_metadata[32:20]==476&&low_metadata[19:7]==269);
            end
        end
    end
    lane_sparse_serial4 lane (
        .clk(clk),.rst_n(rst_n),.cancel(1'b0),
        .start(analysis_start_fire && selected_lane),.start_context(analysis_context),
        .event_valid(quarter_delayed),.event_bad(quarter_bad),.event_x(quarter_x),.event_y(quarter_y),
        .event_gx(quarter_gx),.event_gy(quarter_gy),.event_center_y(quarter_center),
        .event_hint(hints),.hint_valid(hints_valid),.hint_error(hints_error),
        .frame_complete(f22_complete && lane_active),.frame_error(f22_error && lane_active),
        .terminal_context(f22_identity),
        .record_valid(lane_valid),.record_ready(lane_ready),.record_data(lane_data),
        .read_enable(lane_read_enable),.read_index(lane_read_index),.read_data(lane_read_data),.read_valid(lane_read_valid),
        .frames_started(lane_started),.frames_finished(lane_finished),.frames_failed(lane_failed),
        .record_drop_count(lane_drops),
        .terminal_valid(f23_terminal),.terminal_error(f23_error),.terminal_identity(f23_identity));
endmodule
