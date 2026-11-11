`timescale 1ns/1ps
`default_nettype none

module quality_hdr_reader_carrier #(
    parameter integer WIDTH=68, HEIGHT=63
) (
    input wire i_clk,i_identity_rst_n,
    input wire i_start_valid,i_pair_bank,i_pair_camera,output wire o_start_ready,
    input wire [2:0] i_ratio_log2,
    input wire [9:0] i_black_long,i_black_short,
    input wire [13:0] i_motion_base,input wire [3:0] i_motion_shift,
    input wire [1:0] i_fusion_preset,
    input wire i_cancel,
    output wire [55:0] m_raw,output wire [3:0] m_motion,
    output wire m_valid,m_sof,m_eol,m_eof,output wire [31:0] m_index,
    input wire m_ready,
    output wire o_result_valid,o_result_ok,input wire i_result_ready,
    output wire o_read_quiet,o_protocol_fault,
    output wire [9:0] o_long_occupancy,o_short_occupancy,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    wire decode_start,decode_start_ready,decode_release;
    wire [1:0] decode_abort,decode_done,decode_aborted;
    wire decode_member,decode_valid,decode_last,decode_ready;
    wire [127:0] decode_data;
    wire [15:0] decode_keep;
    wire raw_member,raw_valid,raw_ready;
    wire [39:0] raw_data;

    shared_raw10_decode_service #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) decoder (
        .clk(i_clk),.rst_n(i_identity_rst_n),
        .hdr_start_valid(decode_start),.hdr_start_ready(decode_start_ready),
        .hdr_release(decode_release),.hdr_abort(decode_abort),
        .hdr_member(decode_member),.hdr_data(decode_data),.hdr_keep(decode_keep),
        .hdr_valid(decode_valid),.hdr_last(decode_last),.hdr_ready(decode_ready),
        .hdr_raw_member(raw_member),.hdr_raw(raw_data),
        .hdr_raw_valid(raw_valid),.hdr_raw_ready(raw_ready),
        .hdr_done(decode_done),.hdr_aborted(decode_aborted),
        .stereo_start_valid(1'b0),.stereo_start_ready(),.stereo_release(1'b0),
        .stereo_cancel(1'b0),.stereo_run(1'b0),.stereo_data(128'd0),
        .stereo_keep(16'd0),.stereo_valid(1'b0),.stereo_last(1'b0),.stereo_ready(),
        .stereo_raw(),.stereo_raw_valid(),.stereo_raw_ready(1'b0),
        .stereo_sof(),.stereo_eol(),.stereo_done(),.stereo_aborted(),
        .stereo_quiet(),.stereo_active(),.quiet());

    hdr_pair_pixel_reader #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.EXTERNAL_DECODER(1)) reader (
        .i_clk(i_clk),.i_identity_rst_n(i_identity_rst_n),
        .i_start_valid(i_start_valid),.i_pair_bank(i_pair_bank),.i_pair_camera(i_pair_camera),
        .o_start_ready(o_start_ready),.i_ratio_log2(i_ratio_log2),
        .i_black_long(i_black_long),.i_black_short(i_black_short),
        .i_motion_base(i_motion_base),.i_motion_shift(i_motion_shift),.i_fusion_preset(i_fusion_preset),.i_cancel(i_cancel),
        .m_raw(m_raw),.m_motion(m_motion),.m_valid(m_valid),.m_sof(m_sof),.m_eol(m_eol),
        .m_eof(m_eof),.m_index(m_index),.m_ready(m_ready),
        .o_result_valid(o_result_valid),.o_result_ok(o_result_ok),.i_result_ready(i_result_ready),
        .o_read_quiet(o_read_quiet),.o_protocol_fault(o_protocol_fault),
        .o_long_occupancy(o_long_occupancy),.o_short_occupancy(o_short_occupancy),
        .o_decode_start_valid(decode_start),.i_decode_start_ready(decode_start_ready),
        .o_decode_release(decode_release),.o_decode_abort(decode_abort),
        .o_decode_member(decode_member),.o_decode_data(decode_data),.o_decode_keep(decode_keep),
        .o_decode_valid(decode_valid),.o_decode_last(decode_last),.i_decode_ready(decode_ready),
        .i_decode_raw_member(raw_member),.i_decode_raw(raw_data),.i_decode_raw_valid(raw_valid),
        .o_decode_raw_ready(raw_ready),.i_decode_done(decode_done),.i_decode_aborted(decode_aborted),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),.m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready));
endmodule

`default_nettype wire
