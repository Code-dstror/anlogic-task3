// One shared native Y/window producer and independently bounded sparse services.
module preprocess_advanced_pipeline4 #(
    parameter integer MAX_WIDTH=1920,
    parameter integer MAX_HEIGHT=1080,
    parameter integer STRIPS=4,
    parameter integer CAMERA_CONTEXT_ENABLE=0
) (
    input wire clk,rst_n,cancel,
    input wire cfg_valid,
    output wire cfg_ready,
    input wire [7:0] cfg_schema,
    input wire [159:0] cfg_context,
    input wire [12:0] cfg_width,cfg_height,
    input wire [2:0] cfg_pp_enable,
    input wire cfg_camera_id,cfg_history_reset,
    input wire [3:0] cfg_features,
    input wire [10:0] cfg_threshold,cfg_gx_min,
    input wire [1:0] cfg_ratio_shift,cfg_direction_sign,
    input wire [19:0] cfg_min_count,
    input wire [3:0] cfg_min_paired_strips,
    input wire [STRIPS*13-1:0] cfg_strip_y_begin,cfg_strip_y_end,
    input wire [STRIPS*13-1:0] cfg_roi_left,cfg_roi_split,cfg_roi_right,
    input wire [2:0] cfg_morph_mode,
    input wire [12:0] cfg_min_curvature,
    output reg cfg_rejected,
    output reg [7:0] cfg_error_code,
    input wire s_valid,
    output wire s_ready,
    input wire [95:0] s_data,
    input wire s_sof,s_eol,s_frame_done,s_frame_error,
    output wire m_valid,
    input wire m_ready,
    output wire [95:0] m_data,
    output wire [31:0] m_luma,
    output wire m_sof,m_eol,m_camera_id,
    output reg frame_done,frame_error,
    output wire [159:0] frame_context,
    // Actual numerical tails complete independently of held-record consumption.
    output reg computation_terminal_valid,computation_terminal_error,
    output wire [159:0] computation_terminal_context,
    output wire o_presented_valid,
    output wire o_neutral_valid,
    output wire [95:0] o_neutral_rgb,
    output wire [31:0] o_neutral_luma,
    output wire o_neutral_sof,o_neutral_eol,o_neutral_eof,
    output wire f22_record_valid,
    input wire f22_record_ready,
    output wire [683:0] f22_record_data,
    output wire f23_record_valid,
    input wire f23_record_ready,
    output wire [292+266*STRIPS-1:0] f23_record_data,
    output wire morph_valid,
    input wire morph_ready,
    output wire [3:0] morph_mask,morph_keep,
    output wire morph_sof,morph_eol,morph_eof,
    output wire [12:0] morph_x,morph_y,morph_width,morph_height,
    output wire [159:0] morph_context,
    output reg f24_record_valid,
    input wire f24_record_ready,
    output reg [207:0] f24_record_data,
    output wire f25_record_valid,
    input wire f25_record_ready,
    output wire [264:0] f25_record_data,
    output wire [31:0] f22_record_drops,f23_record_drops,
    output wire [31:0] f22_completed_count,f22_failed_count,f22_native_stall_count,
    output wire [7:0] f22_firstfault_code,
    output wire [159:0] f22_firstfault_context,f22_first_congestion_context,
    output wire [2:0] f22_max_low_resident,
    output wire [1:0] f22_max_grant_wait,
    output wire [31:0] f23_frames_started,f23_frames_finished,f23_frames_failed,f23_stray_terminals,
    output wire f23_firstfault_valid,
    output wire [7:0] f23_firstfault_code,
    output wire [159:0] f23_firstfault_context,
    output reg [31:0] f24_record_drops,f24_overflow_frames,
    output reg [9:0] f24_max_queued,
    output reg [159:0] f24_first_overflow_context
);
    reg armed,source_started,pp_finished,pyramid_finished,morph_finished,refine_finished;
    reg failed;
    reg computation_refine_finished,computation_reported;
    reg [3:0] features;
    reg [159:0] identity;
    reg [12:0] width,height,min_curvature;
    reg [2:0] pp_enable,morph_mode;
    reg camera,history_reset;
    reg [10:0] threshold;
    assign frame_context=identity;
    assign computation_terminal_context=identity;
    wire run=rst_n&&!cancel;
    wire f22_start_ready,f24_start_ready,refine_ready;
    wire fifo_write_done,fifo_read_done;
    assign cfg_ready=run&&!armed&&f22_start_ready&&f24_start_ready&&refine_ready
        &&fifo_write_done&&fifo_read_done;
    wire cfg_fire=cfg_valid&&cfg_ready;
    reg roi_bad;
    integer strip_check;
    wire [12:0] cfg_quarter_width=(cfg_width+13'd3)>>2;
    wire [12:0] cfg_quarter_height=(cfg_height+13'd3)>>2;
    always @* begin
        roi_bad=cfg_gx_min>1020||cfg_direction_sign==3||cfg_min_count==0
            ||cfg_min_paired_strips==0||cfg_min_paired_strips>STRIPS;
        for(strip_check=0;strip_check<STRIPS;strip_check=strip_check+1) begin
            if(cfg_strip_y_begin[strip_check*13+:13]>=cfg_strip_y_end[strip_check*13+:13]
                ||cfg_strip_y_end[strip_check*13+:13]>cfg_quarter_height
                ||cfg_roi_left[strip_check*13+:13]>=cfg_roi_split[strip_check*13+:13]
                ||cfg_roi_split[strip_check*13+:13]>=cfg_roi_right[strip_check*13+:13]
                ||cfg_roi_right[strip_check*13+:13]>cfg_quarter_width) roi_bad=1;
            if(strip_check>0) begin
                if(cfg_strip_y_begin[strip_check*13+:13]!=cfg_strip_y_end[(strip_check-1)*13+:13]
                    ||cfg_roi_left[strip_check*13+:13]>cfg_roi_left[(strip_check-1)*13+:13]
                    ||cfg_roi_right[strip_check*13+:13]<cfg_roi_right[(strip_check-1)*13+:13]) roi_bad=1;
            end
        end
    end
    wire bad_config=cfg_schema!=1 || cfg_width<4 || cfg_width>MAX_WIDTH || cfg_width[1:0]!=0
        ||cfg_height==0||cfg_height>MAX_HEIGHT||cfg_threshold>2040
        ||((|cfg_features[3:1])&&!cfg_features[0])
        ||(cfg_features[0]&&!cfg_pp_enable[1])
        ||(cfg_features[1]&&roi_bad)
        ||(cfg_features[2]&&cfg_morph_mode>4)
        ||(cfg_features[3]&&(cfg_min_curvature==0||cfg_min_curvature>4080));
    wire start=cfg_fire&&!bad_config;
    wire pp_ready,pp_done,pp_error,window_valid,window_available,window_ready;
    wire [287:0] window_data;
    wire [31:0] window_luma;
    wire window_sof,window_eol;
    wire pyramid_done,pyramid_error;
    wire [7:0] pyramid_error_code;
    wire [159:0] pyramid_context;
    assign s_ready=run&&armed&&!pp_finished&&pp_ready;
    wire input_fire=s_valid&&s_ready;
    preprocess_pipeline4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT),
        .CAMERA_CONTEXT_ENABLE(CAMERA_CONTEXT_ENABLE),.SHARED_Y_PROFILE(1),
        .NEUTRAL_TAP_ENABLE(1),.GAUSSIAN_WINDOW_TAP_ENABLE(1),
        .GAUSSIAN_WINDOW_HANDSHAKE_ENABLE(1)) pp (
        .clk(clk),.rst_n(rst_n),.cfg_width(width),.cfg_height(height),.cfg_enable(pp_enable),
        .cfg_camera_id(camera),.cfg_history_reset(history_reset),
        .s_valid(s_valid&&armed&&!pp_finished&&run),.s_ready(pp_ready),.s_data(s_data),
        .s_sof(s_sof),.s_eol(s_eol),.s_frame_done(s_frame_done&&armed),
        .s_frame_error(cancel||s_frame_error||pyramid_error),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_luma(m_luma),
        .m_sof(m_sof),.m_eol(m_eol),.m_camera_id(m_camera_id),
        .m_frame_done(pp_done),.m_frame_error(pp_error),.o_presented_valid(o_presented_valid),
        .o_neutral_valid(o_neutral_valid),.o_neutral_rgb(o_neutral_rgb),
        .o_neutral_luma(o_neutral_luma),.o_neutral_sof(o_neutral_sof),
        .o_neutral_eol(o_neutral_eol),.o_neutral_eof(o_neutral_eof),
        .i_window_ready(!features[0]||window_ready),.o_window_valid(window_valid),
        .o_window_available(window_available),.o_window(window_data),
        .o_window_luma(window_luma),.o_window_sof(window_sof),.o_window_eol(window_eol));
    wire low_valid;
    wire [220:0] low_metadata;
    wire [43:0] low_gx,low_gy,low_magnitude;
    wire quarter_event=low_valid&&low_metadata[60:59]==2;
    preprocess_multiscale4 pyramid (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),
        .start_valid(start&&cfg_features[0]),.start_ready(f22_start_ready),
        .start_width(cfg_width),.start_height(cfg_height),.start_threshold(cfg_threshold),
        .start_context(cfg_context),.s_valid(window_valid&&features[0]),.s_ready(window_ready),
        .s_window_valid(window_available),.s_window(window_data),.s_filtered_y(window_luma),
        .s_keep(4'hf),.s_sof(window_sof),.s_eol(window_eol),
        .source_error((s_frame_error||pp_error)&&armed),
        .record_valid(f22_record_valid),.record_ready(f22_record_ready),.record_data(f22_record_data),
        .frame_complete(pyramid_done),.frame_error(pyramid_error),
        .frame_error_code(pyramid_error_code),.frame_event_context(pyramid_context),
        .low_event_valid(low_valid),.low_event_metadata(low_metadata),
        .low_event_gx(low_gx),.low_event_gy(low_gy),.low_event_magnitude(low_magnitude),
        .full_event_valid(),.full_event_metadata(),.full_event_filtered_y(),
        .full_event_gx(),.full_event_gy(),.full_event_magnitude(),
        .full_event_native_x(),.full_event_native_y(),.low_event_filtered_y(),
        .low_event_native_x(),.low_event_native_y(),
        .debug_poll(1'b0),.debug_clear_firstfault(1'b0),.debug_poll_count(),
        .record_drop_count(f22_record_drops),.completed_count(f22_completed_count),
        .failed_count(f22_failed_count),.native_stall_count(f22_native_stall_count),
        .firstfault_code(f22_firstfault_code),.firstfault_context(f22_firstfault_context),
        .first_congestion_context(f22_first_congestion_context),
        .max_low_resident(f22_max_low_resident),.max_grant_wait(f22_max_grant_wait));
    preprocess_lane_candidates4 #(.STRIPS(STRIPS)) candidates (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.debug_clear(1'b0),
        .start(start&&cfg_features[1]),.start_context(cfg_context),
        .native_width(cfg_width),.native_height(cfg_height),.mag_threshold(cfg_threshold),
        .gx_min(cfg_gx_min),.ratio_shift(cfg_ratio_shift),.direction_sign(cfg_direction_sign),
        .min_count(cfg_min_count),.min_paired_strips(cfg_min_paired_strips),
        .strip_y_begin(cfg_strip_y_begin),.strip_y_end(cfg_strip_y_end),
        .roi_left(cfg_roi_left),.roi_split(cfg_roi_split),.roi_right(cfg_roi_right),
        .event_valid(low_valid&&features[1]),.event_metadata(low_metadata),
        .event_gx(low_gx),.event_gy(low_gy),.event_magnitude(low_magnitude),
        .frame_complete(pyramid_done),.frame_error(pyramid_error),
        .terminal_context(pyramid_context),.source_error_code(pyramid_error_code),
        .record_valid(f23_record_valid),.record_ready(f23_record_ready),
        .record_data(f23_record_data),.record_drop_count(f23_record_drops),
        .frames_started(f23_frames_started),.frames_finished(f23_frames_finished),
        .frames_failed(f23_frames_failed),.stray_terminal_count(f23_stray_terminals),
        .first_fault_valid(f23_firstfault_valid),.first_fault_code(f23_firstfault_code),
        .first_fault_context(f23_firstfault_context));

    // Threshold before the bounded FIFO is exactly the morphology's predicate.
    // A one-bit sample becomes magnitude0/1 with locked threshold1 downstream.
    wire [3:0] event_mask;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_threshold
        assign event_mask[lane]=low_metadata[3+lane]&&low_magnitude[11*lane+:11]!=0
            &&low_magnitude[11*lane+:11]>=threshold;
    end endgenerate
    reg morph_poison,morph_overflow;
    wire fifo_full,fifo_empty,fifo_valid;
    wire [39:0] fifo_data;
    wire [9:0] fifo_used;
    wire event_to_morph=quarter_event&&features[2]&&!morph_poison;
    wire overflow=event_to_morph&&fifo_full;
    wire fifo_write=event_to_morph&&!fifo_full;
    wire morph_input_ready;
    wire fifo_read=fifo_valid&&!fifo_empty&&(morph_poison||morph_input_ready);
    reg [2:0] fifo_reset_release;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) fifo_reset_release<=0;
        else if(cancel) fifo_reset_release<=0;
        else fifo_reset_release<={fifo_reset_release[1:0],1'b1};
    end
    control_fifo_40x512 admission (
        .clkw(clk),.clkr(clk),.wrst(!fifo_reset_release[2]),.rrst(!fifo_reset_release[2]),
        .we(fifo_write),.di({29'd0,event_mask,low_metadata[6:0]}),
        .re(fifo_read),.dout(fifo_data),.full_flag(fifo_full),.empty_flag(fifo_empty),
        .valid(fifo_valid),.wrusedw(fifo_used),.wr_rst_done(fifo_write_done),.rd_rst_done(fifo_read_done),
        .afull(),.aempty(),.rdusedw(),.overflow(),.underflow(),.wr_success());
    wire [43:0] binary_magnitude;
    generate for(lane=0;lane<4;lane=lane+1) begin:g_binary
        assign binary_magnitude[11*lane+:11]={10'd0,fifo_data[7+lane]};
    end endgenerate
    wire morph_done,morph_error;
    wire [7:0] morph_error_code;
    wire [159:0] morph_status_context;
    wire upstream_error=pyramid_error||(pp_error&&features[0])||s_frame_error;
    preprocess_morphology4 morphology (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),
        .source_error(morph_poison||overflow||upstream_error),.debug_clear(1'b0),
        .start_valid(start&&cfg_features[2]),.start_ready(f24_start_ready),
        .start_width((cfg_width+13'd3)>>2),.start_height((cfg_height+13'd3)>>2),
        .start_context(cfg_context),.start_threshold(11'd1),.start_mode(cfg_morph_mode),
        .s_valid(fifo_valid&&!fifo_empty&&!morph_poison&&!overflow),.s_ready(morph_input_ready),
        .s_magnitude(binary_magnitude),.s_keep(fifo_data[6:3]),
        .s_sof(fifo_data[2]),.s_eol(fifo_data[1]),.s_eof(fifo_data[0]),
        .m_valid(morph_valid),.m_ready(morph_ready),.m_mask(morph_mask),.m_keep(morph_keep),
        .m_sof(morph_sof),.m_eol(morph_eol),.m_eof(morph_eof),
        .m_x(morph_x),.m_y(morph_y),.m_width(morph_width),.m_height(morph_height),
        .m_context(morph_context),.done(morph_done),.error(morph_error),
        .error_code(morph_error_code),.status_context(morph_status_context),
        .frames_started(),.frames_completed(),.frames_failed(),.first_fault_valid(),
        .first_fault_code(),.first_fault_context());
    reg [23:0] morph_pixels;
    reg [2:0] mask_count;
    integer count_lane;
    always @* begin
        mask_count=0;
        for(count_lane=0;count_lane<4;count_lane=count_lane+1)
            mask_count=mask_count+morph_keep[count_lane];
    end
    function [31:0] increment;
        input [31:0] value;
        begin increment=value==32'hffffffff ? value : value+1'b1;end
    endfunction
    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            morph_poison<=0;morph_overflow<=0;morph_pixels<=0;f24_record_valid<=0;f24_record_data<=0;
            f24_record_drops<=0;f24_overflow_frames<=0;f24_max_queued<=0;
            f24_first_overflow_context<=0;
        end else begin
            if(f24_record_valid&&f24_record_ready) f24_record_valid<=0;
            if(start) begin morph_poison<=0;morph_overflow<=0;morph_pixels<=0;end
            if(armed&&features[2]&&(overflow||upstream_error)) morph_poison<=1;
            if(overflow) begin
                morph_overflow<=1;
                f24_overflow_frames<=increment(f24_overflow_frames);
                if(f24_overflow_frames==0) f24_first_overflow_context<=identity;
            end
            if(fifo_used>f24_max_queued) f24_max_queued<=fifo_used;
            if(morph_valid&&morph_ready) morph_pixels<=morph_pixels+mask_count;
            if(morph_done) begin
                if(!f24_record_valid||f24_record_ready) begin
                    f24_record_valid<=1;
                    f24_record_data<={morph_status_context,!(morph_error||morph_poison),
                        morph_overflow ? 8'h81 : morph_error_code,threshold,morph_mode,
                        morph_pixels,morph_overflow};
                end else f24_record_drops<=increment(f24_record_drops);
            end
        end
    end

    // Raster scan retains actual adjacent samples, including across group edges.
    // It selects one strongest local peak; equal centers retain earliest y/x.
    reg [10:0] previous_left,previous_center,peak_left,peak_center,peak_right;
    reg [1:0] previous_count;
    reg peak_valid;
    reg [12:0] peak_x,peak_y;
    reg [10:0] scan_left,scan_center,scan_peak_left,scan_peak_center,scan_peak_right;
    reg [1:0] scan_count;
    reg scan_peak_valid;
    reg [12:0] scan_peak_x,scan_peak_y,scan_x;
    reg [10:0] scan_right;
    integer sample_lane;
    always @* begin
        scan_left=previous_left;scan_center=previous_center;scan_count=previous_count;
        scan_peak_left=peak_left;scan_peak_center=peak_center;scan_peak_right=peak_right;
        scan_peak_valid=peak_valid;scan_peak_x=peak_x;scan_peak_y=peak_y;
        scan_x=0;scan_right=0;
        if(low_metadata[32:20]==0) scan_count=0;
        for(sample_lane=0;sample_lane<4;sample_lane=sample_lane+1) begin
            scan_right=low_magnitude[sample_lane*11+:11];
            scan_x=low_metadata[32:20]+sample_lane;
            if(low_metadata[3+sample_lane]) begin
                if(scan_count==2&&scan_center>=scan_left&&scan_center>=scan_right
                    &&(scan_center>scan_left||scan_center>scan_right)
                    &&(!scan_peak_valid||scan_center>scan_peak_center)) begin
                    scan_peak_valid=1;scan_peak_left=scan_left;scan_peak_center=scan_center;
                    scan_peak_right=scan_right;scan_peak_x=(scan_x-1'b1)<<2;
                    scan_peak_y=low_metadata[19:7]<<2;
                end
                scan_left=scan_center;scan_center=scan_right;
                if(scan_count!=2) scan_count=scan_count+1'b1;
            end
        end
        if(low_metadata[1]) scan_count=0;
    end
    reg refine_pending,no_peak_valid;
    reg [7:0] no_peak_code;
    wire refine_valid,refine_ok;
    wire [7:0] refine_error;
    wire [21:0] refine_x;
    wire [11:0] refine_delta;
    wire [12:0] refine_y;
    wire [2:0] refine_spacing;
    wire [13:0] refine_curvature;
    wire [159:0] refine_context;
    wire [31:0] refine_tag;
    assign f25_record_valid=refine_valid||no_peak_valid;
    assign f25_record_data=no_peak_valid ? {identity,32'd0,1'b0,no_peak_code,22'd0,12'd0,13'd0,3'd4,14'd0} :
        {refine_context,refine_tag,refine_ok,refine_error,refine_x,refine_delta,
         refine_y,refine_spacing,refine_curvature};
    preprocess_subpixel3 refinement (
        .clk(clk),.rst_n(rst_n),.cancel(cancel),.debug_clear(1'b0),
        .s_valid(refine_pending),.s_ready(refine_ready),
        .s_left(peak_left),.s_center(peak_center),.s_right(peak_right),
        .s_peak_x(peak_x),.s_y(peak_y),.s_native_width(width),.s_spacing(3'd4),
        .s_neighbors(2'b11),.s_min_curvature(min_curvature),.s_context(identity),
        .s_tag({6'd0,peak_y,peak_x}),.m_valid(refine_valid),.m_ready(f25_record_ready),
        .m_ok(refine_ok),.m_error_code(refine_error),.m_x_q8(refine_x),.m_delta_q8(refine_delta),
        .m_y(refine_y),.m_spacing(refine_spacing),.m_curvature(refine_curvature),
        .m_context(refine_context),.m_tag(refine_tag),.requests_accepted(),.results_completed(),
        .requests_rejected(),.first_fault_valid(),.first_fault_code(),.first_fault_context(),.first_fault_tag());
    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            previous_left<=0;previous_center<=0;previous_count<=0;
            peak_valid<=0;peak_left<=0;peak_center<=0;peak_right<=0;peak_x<=0;peak_y<=0;
            refine_pending<=0;no_peak_valid<=0;no_peak_code<=0;
        end else begin
            if(start) begin peak_valid<=0;previous_count<=0;end
            if(quarter_event&&features[3]) begin
                previous_left<=scan_left;previous_center<=scan_center;previous_count<=scan_count;
                peak_valid<=scan_peak_valid;peak_left<=scan_peak_left;peak_center<=scan_peak_center;
                peak_right<=scan_peak_right;peak_x<=scan_peak_x;peak_y<=scan_peak_y;
            end
            if(pyramid_done&&features[3]) begin
                if(peak_valid) refine_pending<=1;
                else begin no_peak_valid<=1;no_peak_code<=8'h80;end
            end
            if(pyramid_error&&features[3]) begin no_peak_valid<=1;no_peak_code<=8'h81;end
            if(refine_pending&&refine_ready) refine_pending<=0;
            if(no_peak_valid&&f25_record_ready) no_peak_valid<=0;
        end
    end
    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            armed<=0;source_started<=0;pp_finished<=0;pyramid_finished<=0;
            morph_finished<=0;refine_finished<=0;failed<=0;
            features<=0;identity<=0;width<=0;height<=0;pp_enable<=0;
            camera<=0;history_reset<=0;threshold<=0;morph_mode<=0;min_curvature<=1;
            cfg_rejected<=0;cfg_error_code<=0;frame_done<=0;frame_error<=0;
            computation_refine_finished<=0;computation_reported<=0;
            computation_terminal_valid<=0;computation_terminal_error<=0;
        end else begin
            cfg_rejected<=0;frame_done<=0;frame_error<=0;
            computation_terminal_valid<=0;
            if(cfg_fire&&bad_config) begin cfg_rejected<=1;cfg_error_code<=1;end
            if(start) begin
                armed<=1;source_started<=0;failed<=0;
                pp_finished<=0;pyramid_finished<=!cfg_features[0];
                morph_finished<=!cfg_features[2];refine_finished<=!cfg_features[3];
                features<=cfg_features;identity<=cfg_context;width<=cfg_width;height<=cfg_height;
                computation_refine_finished<=!cfg_features[3];computation_reported<=0;
                pp_enable<=cfg_pp_enable;camera<=cfg_camera_id;history_reset<=cfg_history_reset;
                threshold<=cfg_threshold;morph_mode<=cfg_morph_mode;min_curvature<=cfg_min_curvature;
            end
            if(input_fire&&s_sof) source_started<=1;
            if(armed&&(pp_done||pp_error)) pp_finished<=1;
            if(armed&&(pyramid_done||pyramid_error)) pyramid_finished<=1;
            if(armed&&morph_done) morph_finished<=1;
            if(armed&&f25_record_valid&&f25_record_ready) refine_finished<=1;
            if(armed&&f25_record_valid&&f25_record_data[264:105]==identity)
                computation_refine_finished<=1;
            if(armed&&(pp_error||pyramid_error||morph_error||overflow||s_frame_error)) failed<=1;
            if(armed&&source_started&&pp_finished&&pyramid_finished&&morph_finished
                &&computation_refine_finished&&fifo_empty&&!fifo_valid&&!computation_reported) begin
                computation_reported<=1;computation_terminal_valid<=1;
                computation_terminal_error<=failed;
            end
            if(armed&&source_started&&pp_finished&&pyramid_finished&&morph_finished
                &&refine_finished&&fifo_empty&&!fifo_valid) begin
                armed<=0;frame_done<=!failed;frame_error<=failed;
            end
        end
    end
endmodule
