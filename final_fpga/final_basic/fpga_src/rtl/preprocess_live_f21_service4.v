`timescale 1ns/1ps
`default_nettype none

// HD LIVE composition. SOURCE authentication remains in the single MAIN fence.
module preprocess_live_f21_service4 #(
    parameter integer HE_FIXED_CONFIG_SESSION_ENABLE = 0,
    parameter integer F21_FIXED_CONFIG_SESSION_ENABLE = 0,
    parameter integer LANE_TAP_ENABLE = 0,
    parameter integer STEREO_PASSTHROUGH_ENABLE = 0,
    parameter integer AUTO_FIXED_LUT_ENABLE = 0
) (
    input wire clk,rst_n,i_processing_rst_n,
    input wire i_stereo_passthrough,cfg_filter_dehaze,
    input wire i_dehaze_terminal_valid,i_dehaze_terminal_ok,
    input wire [96:0] i_dehaze_terminal_key,
    input wire [2:0] cfg_enable,input wire cfg_history_reset,input wire cfg_he_history_eligible,
    input wire cfg_schema2,cfg_filter_gray,cfg_filter_legacy_gaussian,cfg_filter_color,cfg_multiscale,cfg_lane,
    input wire [1023:0] cfg_filter_parameters,
    input wire i_filter_start_valid,i_filter_source_error,
    output wire o_filter_start_ready,o_filter_complete,o_filter_error,
    output wire [159:0] o_filter_terminal_context,
    output wire f22_record_valid,f22_record_pending,input wire f22_record_ready,output wire [683:0] f22_record_data,
    output wire f23_record_valid,input wire f23_record_ready,output wire [176:0] f23_record_data,
    input wire lane_read_enable,input wire [8:0] lane_read_index,
    output wire [39:0] lane_read_data,output wire lane_read_valid,
    input wire i_config_applied,
    input wire [63:0] frame_owner,input wire [31:0] frame_capture,
    input wire [208:0] frame_cohort,input wire [159:0] frame_context,
    input wire s_valid,output wire s_ready,input wire [95:0] s_rgb,
    input wire s_sof,s_eol,s_frame_done,s_frame_error,
    output wire m_valid,input wire m_ready,output wire [95:0] m_rgb,
    output wire [31:0] m_y,output wire m_sof,m_eol,m_frame_done,m_frame_error,
    output wire o_presented,o_frame_quiet,o_maintenance_quiet,o_fault,
    input wire i_window_ready,
    output wire o_window_valid,o_window_available,o_window_sof,o_window_eol,
    output wire [287:0] o_window,
    output wire [31:0] o_window_luma,
    input wire i_abort_observation,i_product_begin,i_frame_released,
    input wire i_source_frame_begin,i_authenticated_negative,
    output wire m_stats_valid,input wire m_stats_ready,
    output wire [159:0] m_stats_context,output wire [183:0] m_statistics,
    input wire [1:0] source_valid,source_cancel,
    input wire source_ok,source_camera,
    input wire [31:0] source_session,source_epoch,source_capture,
    output wire [1:0] source_ready,source_owner_match,source_skip,source_cancel_done,
    output wire [1:0] source_accepted,
    input wire cfg_begin_valid,output wire cfg_begin_ready,input wire [31:0] cfg_generation,
    input wire cfg_valid,output wire cfg_ready,input wire [8:0] cfg_index,input wire [10:0] cfg_value,
    input wire cfg_commit_valid,output wire cfg_commit_ready,input wire cfg_abort,
    output wire cfg_status_valid,input wire cfg_status_ready,output wire cfg_status_ok,
    output wire [7:0] cfg_status_error,output wire [31:0] cfg_status_generation,
    output wire lut_valid,output wire [31:0] lut_generation,
    output wire o_history_used,output wire [7:0] o_history_age,
    output wire [31:0] o_frame_lut_generation,output wire o_map_commit
);
    // Both eyes use the same atmospheric restore pipe and the existing HE.
    // Only real admitted SOURCE terminals can qualify the next estimate.
    wire pipeline_owned,pipeline_ready;
    wire stereo_active=STEREO_PASSTHROUGH_ENABLE!=0&&i_stereo_passthrough;
    // Private replay context is frozen from the camera that owns this job.
    wire history_eye=stereo_active && frame_context[96];
    wire requested_gray=cfg_schema2 ? cfg_filter_gray : cfg_enable[0]&&!cfg_enable[2];
    wire [141:0] he_context={frame_cohort[208:71],history_eye,1'b0,requested_gray,frame_cohort[67]};
    wire neutral_valid,neutral_sof,neutral_eol,neutral_last;
    wire [95:0] neutral_rgb;
    wire [31:0] neutral_y;
    wire he_decision_valid,he_decision_collect,he_cancel_done;
    wire [31:0] he_decision_capture;
    wire observer_busy,dehaze_pending;
    reg observation_discard,frame_quiet,maintenance_quiet;
    wire discard_now=observation_discard||i_abort_observation||source_cancel[0]||m_frame_error;
    wire pixels_quiet=!o_presented&&!pipeline_owned;
    wire quiet_take=i_source_frame_begin||i_product_begin||i_filter_start_valid||(s_valid&&s_ready);

    assign s_ready=rst_n&&(discard_now ? 1'b1 : pipeline_ready);
    assign o_fault=1'b0;
    assign o_frame_quiet=frame_quiet;
    assign o_maintenance_quiet=maintenance_quiet;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin frame_quiet<=0;maintenance_quiet<=0;end
        else begin
            frame_quiet<=pixels_quiet&&!quiet_take;
            maintenance_quiet<=pixels_quiet&&!quiet_take&&!observer_busy&&!dehaze_pending;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)observation_discard<=0;
        else if(i_source_frame_begin)observation_discard<=0;
        else if(i_abort_observation||source_cancel[0]||m_frame_error)observation_discard<=1;
    end
    assign source_skip[0]=he_decision_valid&&!he_decision_collect&&he_decision_capture==frame_capture;
    assign source_cancel_done[0]=he_cancel_done&&pixels_quiet;
    // The estimator observes the already authenticated final terminal directly.
    // It never takes ownership of the broadcast or backpressures that terminal.
    assign source_ready[1]=1'b1;
    assign source_owner_match[1]=1'b0;
    assign source_accepted[1]=1'b0;
    assign source_skip[1]=1'b0;
    assign source_cancel_done[1]=1'b1;
    // The old mutable table loader is absent. Schema2 selects the local
    // generation-one algorithm; per-frame usage is published separately.
    assign cfg_begin_ready=0;assign cfg_ready=0;assign cfg_commit_ready=0;
    assign cfg_status_valid=0;assign cfg_status_ok=0;assign cfg_status_error=0;assign cfg_status_generation=0;
    assign lut_valid=0;assign lut_generation=0;
    assign o_history_age=0;assign o_frame_lut_generation=o_history_used ? 32'd1 : 32'd0;
    assign o_map_commit=0;

    preprocess_live_f21_pipeline4 #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080),.CAMERA_CONTEXT_ENABLE(0),
        .DCP_ENABLE(1),.STEREO_HE_ENABLE(STEREO_PASSTHROUGH_ENABLE),.SHARED_Y_PROFILE(1),.GAUSSIAN_WINDOW_TAP_ENABLE(LANE_TAP_ENABLE),
        .GAUSSIAN_WINDOW_HANDSHAKE_ENABLE(LANE_TAP_ENABLE),.HE_SOURCE_QUALIFY_ENABLE(1),.HE_COLOR_PRESERVE(1),.NEUTRAL_TAP_ENABLE(1),
        .HE_FIXED_CONFIG_SESSION_ENABLE(HE_FIXED_CONFIG_SESSION_ENABLE),.F22_FIXED1080P_ENABLE(1)) u_pipeline(
        .o_input_owned(pipeline_owned),
        .clk(clk),.rst_n(i_processing_rst_n),.cfg_width(13'd1920),.cfg_height(13'd1080),
        .cfg_enable({cfg_enable[2],1'b0,cfg_enable[0]}),
        .cfg_dehaze_enable(cfg_schema2&&cfg_filter_dehaze),.i_dehaze_terminal_valid(i_dehaze_terminal_valid),
        .i_dehaze_terminal_ok(i_dehaze_terminal_ok),.i_dehaze_terminal_key(i_dehaze_terminal_key),
        .o_dehaze_pending(dehaze_pending),.o_dehaze_history_used(o_history_used),
        .cfg_schema2(cfg_schema2),.cfg_filter_gray(cfg_filter_gray),.cfg_filter_legacy_gaussian(cfg_filter_legacy_gaussian),
        .cfg_filter_color(cfg_filter_color),.cfg_multiscale(cfg_multiscale),.cfg_lane(cfg_lane),
        .cfg_filter_context(frame_context),.cfg_filter_parameters(cfg_filter_parameters),
        .i_filter_start_valid(i_filter_start_valid),.i_filter_source_error(i_filter_source_error),
        .o_filter_start_ready(o_filter_start_ready),.o_filter_complete(o_filter_complete),.o_filter_error(o_filter_error),
        .o_filter_terminal_context(o_filter_terminal_context),
        .f22_record_valid(f22_record_valid),.f22_record_pending(f22_record_pending),.f22_record_ready(f22_record_ready),.f22_record_data(f22_record_data),
        .f23_record_valid(f23_record_valid),.f23_record_ready(f23_record_ready),.f23_record_data(f23_record_data),
        .lane_read_enable(lane_read_enable),.lane_read_index(lane_read_index),.lane_read_data(lane_read_data),.lane_read_valid(lane_read_valid),
        .s_valid(s_valid&&!discard_now),.s_ready(pipeline_ready),.s_data(s_rgb),.s_sof(s_sof),.s_eol(s_eol),
        .s_frame_done(s_frame_done),.s_frame_error(s_frame_error||source_cancel[0]),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_rgb),.m_sof(m_sof),.m_eol(m_eol),
        .m_frame_done(m_frame_done),.m_frame_error(m_frame_error),.cfg_camera_id(1'b0),.cfg_history_reset(cfg_history_reset),
        .m_camera_id(),.m_luma(m_y),.o_presented_valid(o_presented),
        .o_neutral_valid(neutral_valid),.o_neutral_rgb(neutral_rgb),.o_neutral_luma(neutral_y),
        .o_neutral_sof(neutral_sof),.o_neutral_eol(neutral_eol),.o_neutral_eof(neutral_last),
        .i_window_ready(i_window_ready),.o_window_valid(o_window_valid),.o_window_available(o_window_available),
        .o_window(o_window),.o_window_luma(o_window_luma),.o_window_sof(o_window_sof),.o_window_eol(o_window_eol),
        .i_he_history_rst_n(rst_n),.cfg_he_context(he_context),.cfg_he_capture_sequence(frame_capture),
        .cfg_he_history_eligible(cfg_he_history_eligible),
        .i_he_source_valid(source_valid[0]),.i_he_source_camera(source_camera),.i_he_source_ok(source_ok),
        .i_he_source_session(source_session),.i_he_source_epoch(source_epoch),.i_he_source_sequence(source_capture),
        .o_he_source_ready(source_ready[0]),.o_he_history_used(),.o_he_lut_valid(),.o_he_lut_source_sequence(),
        .o_he_source_owner_match(source_owner_match[0]),.o_he_source_accepted(source_accepted[0]),
        .o_he_source_decision_valid(he_decision_valid),.o_he_source_decision_collect(he_decision_collect),
        .o_he_source_decision_capture(he_decision_capture),.o_he_source_cancel_done(he_cancel_done));

    // Neutral observation remains a passive F20 record producer. No pixel or
    // F20 status is retained for a deleted dehaze consumer or gates main READY.
    neutral_record_observer4 #(.SOURCE_WIDTH(1920),.SOURCE_HEIGHT(1080)) u_observer(
        .i_clk(clk),.i_rst_n(rst_n),.i_tap_valid(neutral_valid),.i_tap_rgb(neutral_rgb),.i_tap_luma(neutral_y),
        .i_tap_sof(neutral_sof),.i_tap_eol(neutral_eol),.i_tap_eof(neutral_last),
        .i_source_abort(i_abort_observation||source_cancel[0]||m_frame_error||s_frame_error),
        .i_context(frame_context),.i_exposure(frame_cohort[144:113]),.i_gain(frame_cohort[112:97]),
        .i_product_begin(i_product_begin),.i_frame_released(i_frame_released),
        .o_pixel_valid(),.i_pixel_ready(1'b1),.o_pixel_rgb(),.o_pixel_luma(),
        .o_pixel_sof(),.o_pixel_eol(),.o_pixel_last(),
        .m_stats_valid(m_stats_valid),.m_stats_ready(m_stats_ready),.m_stats_context(m_stats_context),.m_statistics(m_statistics),
        .i_f20_required(1'b0),.o_f20_pending(),.o_f20_owner_start(),
        .o_f20_status_valid(),.i_f20_status_ready(1'b1),.o_f20_context(),.o_f20_status_ok(),
        .o_f20_status_error(),.o_f20_sampled(),.o_f20_delivered(),
        .o_f20_width(),.o_f20_height(),.o_f20_exposure(),.o_f20_gain(),
        .o_observer_busy(observer_busy),.o_dropped_frames());
endmodule
`default_nettype wire
