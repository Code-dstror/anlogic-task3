`timescale 1ns / 1ps
// Reusable pixel-domain pipeline; raw abort items bypass output backpressure.
module camera_rgb_pipeline #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    parameter integer FIRST_ROW = 20,
    parameter integer FIRST_GROUP = 1,
    parameter [1:0] BAYER_PHASE = 2'b00,
    parameter integer GAMMA_BYPASS = 0
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire [39:0] i_raw_data,
    input wire i_raw_valid,
    output wire o_raw_ready,
    input wire i_raw_sof,
    input wire i_raw_eol,
    input wire i_raw_abort,
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input wire i_axis_tready,
    output wire o_axis_tlast,
    output wire o_frame_error,
    output wire o_frame_done
);
    localparam [12:0] FRAME_WIDTH = WIDTH;
    localparam [12:0] FRAME_HEIGHT = HEIGHT;
    wire [39:0] cropped_data;
    wire cropped_valid, cropped_ready, cropped_sof, cropped_eol, crop_abort;
    wire [95:0] rgb_data;
    wire rgb_valid, rgb_ready, rgb_sof, rgb_eol;
    wire pack_error;
    wire isp_reset_n = i_rst_n && !crop_abort;
    camera_raw_crop #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),
        .FIRST_ROW(FIRST_ROW),.FIRST_GROUP(FIRST_GROUP)) u_crop (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_raw_data(i_raw_data),
        .i_raw_valid(i_raw_valid),.o_raw_ready(o_raw_ready),
        .i_raw_sof(i_raw_sof),.i_raw_eol(i_raw_eol),.i_raw_abort(i_raw_abort),
        .o_data(cropped_data),.o_valid(cropped_valid),.i_ready(cropped_ready),
        .o_sof(cropped_sof),.o_eol(cropped_eol),.o_abort(crop_abort)
    );
    isp_core_top #(.C_MAX_WIDTH(3840),.C_MAX_HEIGHT(2160),
        .C_GAMMA_LINEAR_BYPASS(GAMMA_BYPASS)) u_isp (
        .clk(i_clk),.rst_n(isp_reset_n),.cfg_width(FRAME_WIDTH),
        .cfg_height(FRAME_HEIGHT),.cfg_bayer_phase(BAYER_PHASE),.cfg_edge_g(1'b0),
        .s_tdata(cropped_data),.s_tvalid(cropped_valid && !crop_abort),
        .s_tready(cropped_ready),.s_tuser(cropped_sof),.s_tlast(cropped_eol),
        .m_tdata(rgb_data),.m_tvalid(rgb_valid),.m_tready(rgb_ready),
        .m_tuser(rgb_sof),.m_tlast(rgb_eol),
        .o_stat_beat_total(),.o_stat_frame_total(),.o_stat_saturate_total()
    );
    rgb_axis_packer u_packer (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_rgb_tdata(rgb_data),
        .i_rgb_tvalid(rgb_valid),.o_rgb_tready(rgb_ready),
        .i_rgb_tuser(rgb_sof),.i_rgb_tlast(rgb_eol),.i_frame_height(FRAME_HEIGHT),
        .i_abort(crop_abort),.o_axis_tdata(o_axis_tdata),.o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),.i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),.o_frame_error(pack_error),.o_frame_done(o_frame_done)
    );
    // crop_abort is the single public event; pack_error acknowledges that same
    // abort one cycle later and must not double-count it.
    assign o_frame_error = crop_abort;
endmodule
