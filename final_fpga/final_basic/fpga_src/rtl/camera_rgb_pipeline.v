`timescale 1ns / 1ps

// 将 RAW 像素流依次送入 ISP 和 RGB 输出打包路径
module camera_rgb_pipeline #(
    // 输出图像尺寸
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    // 裁剪起点与 Bayer 相位
    parameter integer FIRST_ROW = 20,
    parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00,
    parameter integer RUNTIME_BAYER_ENABLE = 0,
    parameter integer RUNTIME_WB_ENABLE = 0,
    // 伽马配置
    parameter integer GAMMA_BYPASS = 0,
    // RGB 输出路径选择
    parameter integer RGB_TAP = 0,
    // 0 保留原 ISP；1 将裁剪 RAW 交给外部 HDR/ISP，并接收其 RGB
    parameter integer EXTERNAL_ISP = 0,
    // S04 reuses the same ISP after a complete live frame has drained.
    parameter integer RAW_REPLAY_ENABLE = 0,
    parameter integer RAW_REPLAY_SAMPLE_BITS = 10,
    parameter integer SHARED_WIDE_ISP_ENABLE = 0,
    parameter integer JOB_CONTROL_ENABLE = 0,
    // A draining private job may run while configuration pauses future live jobs.
    parameter integer SEPARATE_REPLAY_JOB_CONTROL = 0,
    // Failed physical frames retain presented RGB until external drain completes.
    parameter integer CONTROLLED_ABORT_ENABLE = 0,
    parameter integer CONTROLLED_REPLAY_ABORT_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,
    input wire i_processing_reset_n,
    // Stable before reset release; the ISP latches phase on frame SOF.
    input wire [1:0] i_bayer_phase,
    input wire [29:0] i_wb_gains,
    input wire i_job_enable, input wire i_job_pause,
    input wire i_replay_job_enable, input wire i_replay_job_pause,
    output wire o_job_start, output wire o_job_idle, output wire o_job_replay,
    // RAW 像素流
    input wire [39:0] i_raw_data,
    input wire i_raw_valid,
    output wire o_raw_ready,
    input wire i_raw_sof,
    input wire i_raw_eol,
    input wire i_raw_abort,
    // AXIS 输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,
    // 帧异常与完成状态
    output wire o_frame_error,
    output wire o_frame_done,
    // RGB 像素流
    output wire [95:0] o_rgb_tdata,
    output wire o_rgb_tvalid,
    input wire i_rgb_tready,
    output wire o_rgb_tuser,
    output wire o_rgb_tlast,
    // 外部 HDR/ISP 接口，全部同 i_clk 域；默认模式忽略输入
    output wire [39:0] o_cropped_raw_data,
    output wire o_cropped_raw_valid,
    output wire o_cropped_raw_ready,
    input wire i_cropped_raw_ready,
    output wire o_cropped_raw_sof, o_cropped_raw_eol, o_cropped_raw_abort,
    input wire i_replay_active,
    input wire [4*RAW_REPLAY_SAMPLE_BITS-1:0] i_replay_data,
    input wire i_replay_hdr_enable,
    input wire [3:0] i_replay_tone_shift,
    input wire i_replay_valid, i_replay_sof, i_replay_eol, i_replay_abort,
    output wire o_replay_ready, o_replay_safe,
    input wire [95:0] i_external_rgb_data,
    input wire i_external_rgb_valid,
    output wire o_external_rgb_ready,
    input wire i_external_rgb_sof, i_external_rgb_eol, i_external_rgb_abort
);
    localparam [12:0] FRAME_WIDTH = WIDTH;
    localparam [12:0] FRAME_HEIGHT = HEIGHT;
    wire [39:0] cropped_data;
    wire cropped_valid, cropped_ready, cropped_sof, cropped_eol, crop_abort;
    wire [95:0] rgb_data;
    wire rgb_valid, rgb_ready, rgb_sof, rgb_eol;
    wire packer_rgb_ready;
    wire pack_error;
    wire replay_selected = RAW_REPLAY_ENABLE != 0 && i_replay_active;
    reg job_is_replay;
    // Source class is frozen at the actual ISP SOF transfer. A later selector
    // change must not give the physical cleanup helper ownership of replay.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) job_is_replay <= 1'b0;
        else if (o_job_start) job_is_replay <= replay_selected;
    end
    wire controlled_job = CONTROLLED_ABORT_ENABLE != 0 &&
        (!job_is_replay || CONTROLLED_REPLAY_ABORT_ENABLE != 0);
    reg live_frame_armed, live_work_pending;
    wire live_selected = RAW_REPLAY_ENABLE == 0 || live_frame_armed || cropped_sof;
    wire abort_replay_owner = CONTROLLED_ABORT_ENABLE != 0 ? job_is_replay : replay_selected;
    wire pipeline_abort = EXTERNAL_ISP ? i_external_rgb_abort :
        (abort_replay_owner ? i_replay_abort :
         ((RAW_REPLAY_ENABLE == 0 || live_frame_armed) && crop_abort));
    assign o_cropped_raw_data = cropped_data;
    assign o_cropped_raw_valid = cropped_valid;
    assign o_cropped_raw_ready = cropped_ready;
    assign o_cropped_raw_sof = cropped_sof;
    assign o_cropped_raw_eol = cropped_eol;
    assign o_cropped_raw_abort = crop_abort;
    assign o_rgb_tdata = rgb_data;
    assign o_rgb_tvalid = rgb_valid;
    assign o_rgb_tuser = rgb_sof;
    assign o_rgb_tlast = rgb_eol;
    wire isp_reset_n = i_rst_n && (controlled_job ?
        i_processing_reset_n : !pipeline_abort);
    wire local_abort_clear = controlled_job ?
        !i_processing_reset_n : pipeline_abort;
    generate if (CONTROLLED_ABORT_ENABLE != 0 &&
        (CONTROLLED_ABORT_ENABLE != 1 || RGB_TAP == 0 || EXTERNAL_ISP != 0 ||
         SHARED_WIDE_ISP_ENABLE == 0)) begin : bad_controlled_abort
        CAMERA_CONTROLLED_ABORT_REQUIRES_SHARED_INTERNAL_RGB_TAP invalid_configuration();
    end endgenerate
    generate if(CONTROLLED_REPLAY_ABORT_ENABLE!=0 &&
        (CONTROLLED_REPLAY_ABORT_ENABLE!=1 || CONTROLLED_ABORT_ENABLE!=1 ||
         RAW_REPLAY_ENABLE!=1 || SEPARATE_REPLAY_JOB_CONTROL!=1))begin : bad_controlled_replay_abort
        CAMERA_CONTROLLED_REPLAY_REQUIRES_PRIVATE_REPLAY_OWNER invalid_configuration();
    end endgenerate
    wire job_enabled = JOB_CONTROL_ENABLE == 0 || i_job_enable;
    generate if(RAW_REPLAY_SAMPLE_BITS!=10 &&
        (RAW_REPLAY_SAMPLE_BITS!=14 || RAW_REPLAY_ENABLE!=1 ||
         SHARED_WIDE_ISP_ENABLE!=1 || EXTERNAL_ISP!=0))begin: bad_replay_sample_width
        CAMERA_RAW14_REPLAY_REQUIRES_SHARED_INTERNAL_ISP invalid_configuration();
    end endgenerate
    wire job_pause = JOB_CONTROL_ENABLE != 0 && i_job_pause;
    wire replay_job_enabled = JOB_CONTROL_ENABLE == 0 ||
        (SEPARATE_REPLAY_JOB_CONTROL != 0 ? i_replay_job_enable : i_job_enable);
    wire replay_job_pause = JOB_CONTROL_ENABLE != 0 &&
        (SEPARATE_REPLAY_JOB_CONTROL != 0 ? i_replay_job_pause : i_job_pause);
    generate if (SEPARATE_REPLAY_JOB_CONTROL != 0 &&
        (SEPARATE_REPLAY_JOB_CONTROL != 1 || RAW_REPLAY_ENABLE == 0 ||
         JOB_CONTROL_ENABLE == 0 || EXTERNAL_ISP != 0)) begin : bad_replay_control
        CAMERA_SEPARATE_REPLAY_REQUIRES_INTERNAL_REPLAY_JOB_CONTROL invalid_configuration();
    end endgenerate
    // Admission also qualifies this boundary with a reserved JPEG slot.
    // RAW EOF alone cannot qualify it: the ISP still has buffered output.
    assign o_replay_safe = RAW_REPLAY_ENABLE != 0 && !replay_selected &&
        !live_work_pending && !cropped_valid && !rgb_valid;
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            live_frame_armed <= 1'b0;
            live_work_pending <= 1'b0;
        end else if (replay_selected) begin
            live_frame_armed <= 1'b0;
            live_work_pending <= 1'b0;
        end else begin
            if (local_abort_clear) live_frame_armed <= 1'b0;
            if (local_abort_clear || o_frame_done) live_work_pending <= 1'b0;
            if (o_job_start && !replay_selected) begin
                live_frame_armed <= 1'b1;
                live_work_pending <= 1'b1;
            end
        end
    end
    // 裁剪阶段传递有效 RAW 数据，并以帧中止清空后级流水线
    camera_raw_crop #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
        .FIRST_ROW(FIRST_ROW),.FIRST_GROUP(FIRST_GROUP)) u_crop (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_raw_data(i_raw_data),
        .i_raw_valid(i_raw_valid),.o_raw_ready(o_raw_ready),
        .i_raw_sof(i_raw_sof),.i_raw_eol(i_raw_eol),.i_raw_abort(i_raw_abort),
        .o_data(cropped_data),.o_valid(cropped_valid),.i_ready(cropped_ready),
        .o_sof(cropped_sof),.o_eol(cropped_eol),.o_abort(crop_abort)
    );
    generate if (EXTERNAL_ISP == 0) begin : g_internal_isp
    assign o_external_rgb_ready = 1'b0;
    wire isp_raw_ready;
    wire isp_job_idle;
    reg discard_live;
    wire discard_sof = !replay_selected && cropped_sof && isp_job_idle &&
                       (!job_enabled || job_pause);
    always @(posedge i_clk or negedge isp_reset_n) begin
        if(!isp_reset_n) discard_live<=0;
        else if(cropped_valid && cropped_ready && cropped_sof)
            discard_live<=discard_sof;
    end
    wire drop_live = discard_sof || (discard_live && !cropped_sof);
    wire [39:0] selected_raw = replay_selected ? i_replay_data[39:0] : cropped_data;
    wire replay_start_allowed = !i_replay_sof || (replay_job_enabled && !replay_job_pause);
    wire selected_valid = replay_selected ? (i_replay_valid && !i_replay_abort && replay_start_allowed) :
        (cropped_valid && live_selected && !crop_abort && !drop_live);
    wire selected_sof = replay_selected ? i_replay_sof : cropped_sof;
    wire selected_eol = replay_selected ? i_replay_eol : cropped_eol;
    // Live capture continues while replay uses the ISP. Partial live frames
    // are drained until their next SOF rather than spliced into replay output.
    // Serialize the two possible native SOF events for the global descriptor.
    assign cropped_ready = replay_selected ?
        !(i_replay_valid && i_replay_sof && o_replay_ready) :
        (!live_selected || drop_live ? 1'b1 : isp_raw_ready);
    assign o_replay_ready = replay_selected && !i_replay_abort && replay_start_allowed && isp_raw_ready;
    assign o_job_start = selected_valid && isp_raw_ready && selected_sof;
    assign o_job_idle = isp_job_idle;
    assign o_job_replay = replay_selected;
    if(SHARED_WIDE_ISP_ENABLE != 0) begin : wide
        wire [55:0] raw14;
        genvar lane;
        for(lane=0;lane<4;lane=lane+1) begin : extend
            if(RAW_REPLAY_SAMPLE_BITS==14)begin: full_radiance
                assign raw14[lane*14 +: 14]=replay_selected ?
                    i_replay_data[lane*14 +: 14] : {4'd0,cropped_data[lane*10 +: 10]};
            end else begin: raw10
                assign raw14[lane*14 +: 14]={4'd0,selected_raw[lane*10 +: 10]};
            end
        end
        shared_wide_isp #(.MAX_WIDTH(WIDTH),.MAX_HEIGHT(HEIGHT),.GAMMA_BYPASS(GAMMA_BYPASS),
            .HDR_BLACK_CORRECTED_ENABLE(RAW_REPLAY_SAMPLE_BITS==14)) u_isp (
            .clk(i_clk),.rst_n(isp_reset_n),.cfg_width(FRAME_WIDTH),.cfg_height(FRAME_HEIGHT),
            .cfg_bayer_phase(RUNTIME_BAYER_ENABLE ? i_bayer_phase : BAYER_PHASE),
            .cfg_hdr(RAW_REPLAY_SAMPLE_BITS==14 && replay_selected && i_replay_hdr_enable),
            .cfg_tone_shift(RAW_REPLAY_SAMPLE_BITS==14 && replay_selected ? i_replay_tone_shift : 4'd0),
            .cfg_wb_gains(RUNTIME_WB_ENABLE ? i_wb_gains : {3{10'd256}}),
            .s_data(raw14),.s_valid(selected_valid),.s_ready(isp_raw_ready),
            .s_sof(selected_sof),.s_eol(selected_eol),.m_data(rgb_data),
            .m_valid(rgb_valid),.m_ready(rgb_ready),.m_sof(rgb_sof),.m_eol(rgb_eol),
            .o_job_idle(isp_job_idle),.stat_beats(),.stat_frames(),.stat_saturated());
    end else begin : legacy
    assign isp_job_idle = !live_work_pending && !rgb_valid;
    // ISP 将四路 RAW10 转换为四路 RGB888 像素
    isp_core_top #(.C_MAX_WIDTH(3840),.C_MAX_HEIGHT(2160),
        .C_GAMMA_LINEAR_BYPASS(GAMMA_BYPASS),
        .RUNTIME_WB_ENABLE(RUNTIME_WB_ENABLE)) u_isp (
        .clk(i_clk),.rst_n(isp_reset_n),.cfg_width(FRAME_WIDTH),
        .i_wb_gains(i_wb_gains),
        .cfg_height(FRAME_HEIGHT),.cfg_bayer_phase(RUNTIME_BAYER_ENABLE ? i_bayer_phase : BAYER_PHASE),.cfg_edge_g(1'b0),
        .s_tdata(selected_raw),
        .s_tvalid(selected_valid),
        .s_tready(isp_raw_ready),
        .s_tuser(selected_sof),
        .s_tlast(selected_eol),
        .m_tdata(rgb_data),.m_tvalid(rgb_valid),.m_tready(rgb_ready),
        .m_tuser(rgb_sof),.m_tlast(rgb_eol),
        .o_stat_beat_total(),.o_stat_frame_total(),.o_stat_saturate_total()
    );
    end
    end else begin : g_external_isp
        assign o_job_start = i_external_rgb_valid && o_external_rgb_ready && i_external_rgb_sof;
        assign o_job_idle = !live_work_pending && !i_external_rgb_valid;
        assign o_job_replay = 1'b0;
        assign cropped_ready = i_cropped_raw_ready;
        assign o_replay_ready = 1'b0;
        assign rgb_data = i_external_rgb_data;
        assign rgb_valid = i_external_rgb_valid && i_rst_n && !pipeline_abort;
        assign rgb_sof = i_external_rgb_sof;
        assign rgb_eol = i_external_rgb_eol;
        assign o_external_rgb_ready = rgb_ready && i_rst_n && !pipeline_abort;
    end endgenerate
    generate if (RGB_TAP != 0) begin : g_rgb_tap
        reg [12:0] lines_seen;
        reg frame_done;
        assign rgb_ready = i_rgb_tready;
        assign o_axis_tdata = 128'd0;
        assign o_axis_tkeep = 16'd0;
        assign o_axis_tvalid = 1'b0;
        assign o_axis_tlast = 1'b0;
        assign o_frame_done = frame_done;
        assign pack_error = 1'b0;
        // 在 RGB 直出模式统计已完成的图像行
        always @(posedge i_clk or negedge i_rst_n) begin
            if (!i_rst_n) begin
                lines_seen <= 13'd0;
                frame_done <= 1'b0;
            end else begin
                frame_done <= 1'b0;
                if (local_abort_clear || (rgb_valid && rgb_ready && rgb_sof))
                    lines_seen <= 13'd0;
                if (rgb_valid && rgb_ready && rgb_eol) begin
                    if (lines_seen == FRAME_HEIGHT - 13'd1) begin
                        frame_done <= 1'b1;
                        lines_seen <= 13'd0;
                    end else
                        lines_seen <= lines_seen + 13'd1;
                end
            end
        end
    end else begin : g_packed_rgb
    assign rgb_ready = packer_rgb_ready;
    // 标准输出模式将 RGB 像素打包成 128 位 AXIS 数据
    rgb_axis_packer u_packer (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_rgb_tdata(rgb_data),
        .i_rgb_tvalid(rgb_valid),.o_rgb_tready(packer_rgb_ready),
        .i_rgb_tuser(rgb_sof),.i_rgb_tlast(rgb_eol),.i_frame_height(FRAME_HEIGHT),
        .i_abort(pipeline_abort),.o_axis_tdata(o_axis_tdata),.o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),.i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),.o_frame_error(pack_error),.o_frame_done(o_frame_done)
    );
    end endgenerate
    // 外部模式中采集下一帧的 crop_abort 不能取消已提交的 HDR 回放帧
    // pipeline_abort 是唯一对外报告的中止事件，pack_error 仅确认同一次中止
    // 因此帧错误不能重复计数
    assign o_frame_error = pipeline_abort;
endmodule
