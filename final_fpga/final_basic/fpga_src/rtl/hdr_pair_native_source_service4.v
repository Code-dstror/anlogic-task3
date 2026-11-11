`timescale 1ns/1ps
`default_nettype none
// Existing HDR reader and its one RAW14 native transport, without a second job owner.
module hdr_pair_native_source_service4 #(
    parameter integer MAX_WIDTH=1920,MAX_HEIGHT=1080,
    parameter integer CANONICAL_READ_ENABLE=0,
    parameter integer SHARED_NATIVE_ENABLE=0,
    parameter integer EXTERNAL_DECODER=0
)(
    input wire i_identity_rst_n,i_pair_bank,
    input wire i_dfi_clk,i_dfi_rst_n,i_pixel_clk,i_pixel_rst_n,
    input wire s_context_valid,output wire s_context_ready,
    input wire s_start_valid,output wire s_start_ready,
    input wire [383:0] s_long_frame,s_short_frame,
    input wire [63:0] s_long_lease,s_short_lease,s_long_tag,s_short_tag,s_job_id,s_pair_id,
    input wire [2:0] i_ratio_log2,input wire [9:0] i_black_long,i_black_short,
    input wire [13:0] i_motion_base,input wire [3:0] i_motion_shift,
    input wire [63:0] i_hdr_max_delta_ns,
    input wire i_cancel_valid,output wire o_cancel_ready,
    input wire i_result_transport_enable,
    output wire m_result_valid,m_result_ready,m_result_ok,
    output wire [7:0] o_first_error,o_reader_error,
    output wire o_reader_fault,o_source_fault,o_pixel_fault,
    output wire o_read_quiescent,o_source_reset_done,o_pixel_reset_done,
    output wire [575:0] m_context,output wire m_context_valid,input wire m_context_ready,
    output wire [95:0] m_raw_capsule,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,m_bad,input wire m_ready,
    output wire [63:0] m_tag,output wire [31:0] m_index,
    output wire m_source_valid,input wire m_source_ready,
    output wire [63:0] m_source_tag,output wire m_source_ok,
    output wire [7:0] m_source_error,output wire [31:0] m_source_groups,
    // Optional main phase reuse of the existing RAW replay FIFO and the
    // actual prepared processing command; no second context crossing.
    input wire i_shared_source_phase_owned,i_shared_pixel_phase_owned,
    input wire [575:0] i_shared_pixel_context,input wire i_shared_pixel_owner_prepared,
    output wire [146:0] m_shared_fifo_data,output wire m_shared_fifo_valid,
    input wire i_shared_fifo_ready,i_shared_fifo_source_reset_done,
    input wire [146:0] s_shared_fifo_data,input wire s_shared_fifo_valid,
    output wire m_shared_fifo_ready,input wire i_shared_fifo_sink_reset_done,
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,output wire [1:0] o_decode_abort,
    output wire o_decode_member,output wire [127:0] o_decode_data,
    output wire [15:0] o_decode_keep,output wire o_decode_valid,o_decode_last,
    input wire i_decode_ready,
    input wire i_decode_raw_member,input wire [39:0] i_decode_raw,
    input wire i_decode_raw_valid,output wire o_decode_raw_ready,
    input wire [1:0] i_decode_done,i_decode_aborted,
    output wire m_private_req_valid,input wire m_private_req_ready,
    output wire [2:0] m_private_req_op,
    output wire m_private_req_camera,output wire [1:0] m_private_req_slot,
    output wire [31:0] m_private_req_generation,m_private_req_session,m_private_req_offset,m_private_req_length,
    output wire m_private_req_private,output wire [63:0] m_private_req_lease,m_private_req_job_id,
    input wire s_private_rsp_valid,output wire s_private_rsp_ready,
    input wire [3:0] s_private_rsp_code,input wire [383:0] s_private_rsp_descriptor,
    input wire s_private_rsp_metadata_valid,
    input wire [127:0] s_private_read_data,input wire [15:0] s_private_read_keep,
    input wire s_private_read_valid,s_private_read_last,output wire s_private_read_ready,
    input wire i_private_read_complete,i_private_read_error,i_private_protocol_fault,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready
);
    wire reader_start_ready,reader_context_valid,reader_result_valid,reader_result_ready,reader_result_good;
    wire [7:0] reader_first_error;
    wire reader_fault,reader_cancel_ready;
    wire [55:0] reader_raw;wire [31:0] reader_index;wire [3:0] reader_keep;
    wire reader_valid,reader_sof,reader_eol,reader_last,reader_ready;
    wire raw_source_done,raw_sink_done,raw_source_fault,raw_sink_fault;
    wire [575:0] pixel_context;wire pixel_context_valid;
    wire [95:0] pixel_raw_capsule;
    wire pixel_status_valid,pixel_status_ok;
    wire [63:0] pixel_status_tag,pixel_tag;
    wire [7:0] pixel_status_error;wire [31:0] pixel_status_groups;
    wire pixel_transport_bad,pixel_transport_quiet;
    wire o_reader_quiescent;
    assign s_start_ready=reader_start_ready;
    assign m_result_valid=reader_result_valid;assign m_result_ready=reader_result_ready;
    assign m_result_ok=reader_result_good;assign o_first_error=reader_first_error;
    assign o_reader_fault=reader_fault;assign o_source_fault=raw_source_fault;assign o_pixel_fault=raw_sink_fault;
    assign o_read_quiescent=o_reader_quiescent;
    assign o_source_reset_done=raw_source_done;assign o_pixel_reset_done=raw_sink_done;
    assign o_cancel_ready=reader_cancel_ready;
    assign m_context=pixel_context;assign m_context_valid=pixel_context_valid;
    assign m_raw_capsule=pixel_raw_capsule;assign m_bad=pixel_transport_bad;
    assign m_source_valid=pixel_status_valid;assign m_source_tag=pixel_status_tag;
    assign m_source_ok=pixel_status_ok;assign m_source_error=pixel_status_error;assign m_source_groups=pixel_status_groups;
    assign m_tag=pixel_tag;
    hdr_pair_pixel_reader #(.WIDTH(MAX_WIDTH),.HEIGHT(MAX_HEIGHT),.EXTERNAL_DECODER(EXTERNAL_DECODER)) u_pair_reader(
        .i_clk(i_dfi_clk),.i_identity_rst_n(i_identity_rst_n),
        .i_start_valid(s_start_valid),.i_pair_bank(i_pair_bank),.i_pair_camera(s_long_frame[4]),.o_start_ready(reader_start_ready),
        .i_ratio_log2(i_ratio_log2),.i_black_long(i_black_long),.i_black_short(i_black_short),
        .i_motion_base(i_motion_base),.i_motion_shift(i_motion_shift),.i_cancel(i_cancel_valid),
        .m_raw(reader_raw),.m_motion(),.m_valid(reader_valid),.m_sof(reader_sof),.m_eol(reader_eol),
        .m_eof(reader_last),.m_index(reader_index),.m_ready(reader_ready),
        .o_result_valid(reader_result_valid),.o_result_ok(reader_result_good),.i_result_ready(reader_result_ready),
        .o_read_quiet(o_reader_quiescent),.o_protocol_fault(reader_fault),.o_long_occupancy(),.o_short_occupancy(),
        .o_decode_start_valid(o_decode_start_valid),.i_decode_start_ready(i_decode_start_ready),
        .o_decode_release(o_decode_release),.o_decode_abort(o_decode_abort),
        .o_decode_member(o_decode_member),.o_decode_data(o_decode_data),.o_decode_keep(o_decode_keep),
        .o_decode_valid(o_decode_valid),.o_decode_last(o_decode_last),.i_decode_ready(i_decode_ready),
        .i_decode_raw_member(i_decode_raw_member),.i_decode_raw(i_decode_raw),
        .i_decode_raw_valid(i_decode_raw_valid),.o_decode_raw_ready(o_decode_raw_ready),
        .i_decode_done(i_decode_done),.i_decode_aborted(i_decode_aborted),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
    assign reader_keep=4'hf;
    assign reader_cancel_ready=1'b1;
    assign reader_context_valid=1'b0;
    assign reader_first_error=reader_result_good ? 8'd0 : 8'd2;
    assign o_reader_error=reader_first_error;
    assign m_private_req_valid=0;assign m_private_req_op=0;assign m_private_req_camera=0;
    assign m_private_req_slot=0;assign m_private_req_generation=0;assign m_private_req_session=0;
    assign m_private_req_offset=0;assign m_private_req_length=0;assign m_private_req_private=0;
    assign m_private_req_lease=0;assign m_private_req_job_id=0;
    assign s_private_rsp_ready=0;assign s_private_read_ready=0;

    generate if(SHARED_NATIVE_ENABLE!=0)begin : g_shared_native
    hdr_raw14_shared_transport4 #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) u_transport(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(i_dfi_rst_n),.i_source_phase_owned(i_shared_source_phase_owned),
        .s_context({s_long_lease,s_job_id,s_long_tag,s_long_frame}),.s_context_valid(s_context_valid),
        .s_context_ready(s_context_ready),.o_source_reset_done(raw_source_done),
        .s_raw(reader_raw),.s_keep(reader_keep),.s_sof(reader_sof),.s_eol(reader_eol),.s_last(reader_last),
        .s_valid(reader_valid),.s_ready(reader_ready),.s_tag(s_long_tag),.s_index(reader_index),
        .s_status_valid(reader_result_valid&&i_result_transport_enable),.s_status_ready(reader_result_ready),
        .s_status_tag(s_long_tag),.s_status_ok(reader_result_good),.s_status_error(reader_first_error),
        .i_source_read_quiescent(o_reader_quiescent),.m_fifo_data(m_shared_fifo_data),.m_fifo_valid(m_shared_fifo_valid),
        .m_fifo_ready(i_shared_fifo_ready),.i_fifo_source_reset_done(i_shared_fifo_source_reset_done),
        .o_source_protocol_fault(raw_source_fault),.i_sink_clk(i_pixel_clk),.i_sink_rst_n(i_pixel_rst_n),
        .i_sink_phase_owned(i_shared_pixel_phase_owned),.i_prepared_context(i_shared_pixel_context),
        .i_owner_prepared(i_shared_pixel_owner_prepared),.m_context(pixel_context),.m_context_valid(pixel_context_valid),
        .m_context_ready(m_context_ready),.o_sink_reset_done(raw_sink_done),
        .s_fifo_data(s_shared_fifo_data),.s_fifo_valid(s_shared_fifo_valid),.s_fifo_ready(m_shared_fifo_ready),
        .i_fifo_sink_reset_done(i_shared_fifo_sink_reset_done),.m_raw_capsule(pixel_raw_capsule),.m_keep(m_keep),
        .m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_valid(m_valid),.m_bad(pixel_transport_bad),.m_ready(m_ready),
        .m_tag(pixel_tag),.m_index(m_index),.m_status_valid(pixel_status_valid),.m_status_ready(m_source_ready),
        .m_status_tag(pixel_status_tag),.m_status_ok(pixel_status_ok),.m_status_error(pixel_status_error),
        .m_status_groups(pixel_status_groups),.o_sink_read_quiescent(pixel_transport_quiet),.o_sink_protocol_fault(raw_sink_fault));
    end else begin : g_dedicated_native
    assign m_shared_fifo_data=0;assign m_shared_fifo_valid=0;assign m_shared_fifo_ready=0;
    // Transparent 96-bit storage carries {40'b0,RAW14x4}; it does no RGB work.
    native_rgb4_frame_cdc #(.MAX_WIDTH(MAX_WIDTH),.MAX_HEIGHT(MAX_HEIGHT)) u_radiance_cdc(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(i_dfi_rst_n),
        .s_context({s_long_lease,s_job_id,s_long_tag,s_long_frame}),.s_context_valid(s_context_valid),
        .s_context_ready(s_context_ready),.o_source_reset_done(raw_source_done),
        .s_rgb({40'd0,reader_raw}),.s_keep(reader_keep),.s_sof(reader_sof),.s_eol(reader_eol),.s_last(reader_last),
        .s_valid(reader_valid),.s_ready(reader_ready),.s_tag(s_long_tag),.s_index(reader_index),
        .s_status_valid(reader_result_valid && i_result_transport_enable),.s_status_ready(reader_result_ready),
        .s_status_tag(s_long_tag),.s_status_ok(reader_result_good),.s_status_error(reader_first_error),
        .i_source_read_quiescent(o_reader_quiescent),.o_source_stale_status_count(),.o_source_protocol_fault(raw_source_fault),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(i_pixel_rst_n),.m_context(pixel_context),.m_context_valid(pixel_context_valid),
        .m_context_ready(m_context_ready),.o_sink_reset_done(raw_sink_done),
        .m_rgb(pixel_raw_capsule),.m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_valid(m_valid),
        .m_ready(m_ready),.m_tag(pixel_tag),.m_index(m_index),.m_bad(pixel_transport_bad),
        .m_status_valid(pixel_status_valid),.m_status_ready(m_source_ready),.m_status_tag(pixel_status_tag),
        .m_status_ok(pixel_status_ok),.m_status_error(pixel_status_error),.m_status_groups(pixel_status_groups),
        .o_sink_read_quiescent(pixel_transport_quiet),.o_sink_protocol_fault(raw_sink_fault));
    end endgenerate
endmodule
`default_nettype wire
