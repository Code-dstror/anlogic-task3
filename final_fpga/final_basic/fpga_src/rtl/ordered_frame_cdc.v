`timescale 1ns / 1ps

// 通过异步FIFO传送有序帧令牌
module ordered_frame_cdc #(
    parameter integer CONTEXT_ENABLE = 0,
    parameter integer WRITE_TAG_ENABLE = 0,
    parameter integer RECORD_EXTENSION_ENABLE = 0,
    parameter integer RECORD_EXTENSION_WIDTH = 1024,
    parameter integer BORROW_EXTENSION = 0,
    parameter integer MASK_CONTEXT_ENABLE = 0,
    parameter integer EXTENSION_RAM_ENABLE = 0,
    parameter integer STREAM_EXTENSION = 0
) (
    // 源时钟与复位
    input wire i_source_clk,
    input wire i_source_rst_n,

    // 源侧帧起始
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [31:0] i_capture_id,
    input wire [15:0] i_width,
    input wire [15:0] i_height,
    input wire [63:0] i_timestamp_ns,
    input wire [31:0] i_session_id, i_mode_epoch,
    input wire i_camera_id, input wire [7:0] i_quality, i_format,
    input wire [31:0] i_write_tag,
    input wire i_start_mask,
    input wire [2:0] i_start_source_type,

    // 源侧JPEG数据
    input wire [127:0] i_jpeg_tdata,
    input wire [15:0] i_jpeg_tkeep,
    input wire i_jpeg_tlast,
    input wire i_jpeg_tvalid,
    output wire o_jpeg_tready,

    // 源侧帧结果
    input wire i_result_valid,
    output wire o_result_ready,
    input wire [31:0] i_result_id,
    input wire i_result_ok,
    input wire [24:0] i_result_length,
    input wire [7:0] i_result_error,
    input wire [7:0] i_result_quality, input wire [31:0] i_result_epoch,

    // Source extension is frozen with the waiting actual RESULT.
    input wire [(STREAM_EXTENSION!=0 ? 2048 : RECORD_EXTENSION_WIDTH)-1:0] i_record_extension,
    input wire i_record_extension_valid,
    output wire o_record_extension_ready,
    input wire [127:0] i_extension_stream_data,
    input wire i_extension_stream_valid,
    output wire o_extension_stream_ready,
    output wire o_extension_stream_start,
    output wire o_source_protocol_fault,

    // 目的时钟与复位
    input wire i_sink_clk,
    input wire i_sink_rst_n,

    // 目的侧帧起始
    output wire o_start_valid,
    input wire i_start_ready,
    output wire [31:0] o_capture_id,
    output wire [15:0] o_width,
    output wire [15:0] o_height,
    output wire [63:0] o_timestamp_ns,
    output wire [31:0] o_session_id, o_mode_epoch,
    output wire o_camera_id, output wire [7:0] o_quality, o_format,
    output wire [31:0] o_write_tag,
    output wire o_start_mask,
    output wire [2:0] o_start_source_type,

    // 目的侧JPEG数据
    output wire [127:0] o_jpeg_tdata,
    output wire [15:0] o_jpeg_tkeep,
    output wire o_jpeg_tlast,
    output wire o_jpeg_tvalid,
    input wire i_jpeg_tready,

    // 目的侧帧结果
    output wire o_result_valid,
    input wire i_result_ready,
    output wire [31:0] o_result_id,
    output wire o_result_ok,
    output wire [24:0] o_result_length,
    output wire [7:0] o_result_error,
    output wire [7:0] o_result_quality, output wire [31:0] o_result_epoch,

    output wire [RECORD_EXTENSION_WIDTH-1:0] o_record_extension,
    output wire o_record_extension_valid,
    input wire i_record_extension_ready,

    // Complete staging lease is retained until the next real START.
    output wire o_extension_shape_valid,
    input wire i_extension_read_enable,
    input wire [8:0] i_extension_read_index,
    output wire [39:0] o_extension_read_data,

    // 协议与复位状态
    output wire o_protocol_fault, // 令牌顺序或内容不符合帧协议
    input wire i_fence_request,i_source_fence_idle,
    input wire [31:0] i_source_fence_session,i_sink_fence_session,
    input wire [63:0] i_raw_enqueued,i_raw_consumed,
    input wire i_raw_consume_fire,i_sink_fence_quiet,
    output wire o_source_fence_proven,o_source_fence_fault,o_sink_fence_fault,
    output wire o_source_reset_done,
    output wire o_sink_reset_done
);
    generate if(RECORD_EXTENSION_WIDTH!=1024 && RECORD_EXTENSION_WIDTH!=3072 && RECORD_EXTENSION_WIDTH!=16384) begin : invalid_record_width
        RECORD_EXTENSION_REQUIRES_1024_3072_OR_16384 u_invalid_record_width();
    end endgenerate
    generate if(WRITE_TAG_ENABLE!=0 && CONTEXT_ENABLE==0) begin : invalid_tag_profile
        TD_ORDERED_WRITE_TAG_REQUIRES_CONTEXT u_invalid_configuration();
    end endgenerate
    generate if(RECORD_EXTENSION_ENABLE!=0 && (CONTEXT_ENABLE==0 || WRITE_TAG_ENABLE==0)) begin : invalid_extension_profile
        TD_ORDERED_RECORD_EXTENSION_REQUIRES_CONTEXT_AND_WRITE_TAG u_invalid_configuration();
    end endgenerate
    generate if(MASK_CONTEXT_ENABLE!=0 && (CONTEXT_ENABLE==0 || WRITE_TAG_ENABLE==0)) begin : invalid_mask_profile
        TD_ORDERED_MASK_REQUIRES_CONTEXT_AND_WRITE_TAG u_invalid_configuration();
    end endgenerate
    wire [146:0] write_token, read_token;
    wire write_valid, write_ready, read_valid, read_ready,egress_pending;
    wire session_async_rst_n = i_source_rst_n && i_sink_rst_n;
    wire source_local_rst_n, ingress_rst_n, sink_local_rst_n;

    // 源侧编码令牌经异步FIFO送入目的侧解码器
    // 源侧数据资格和 FIFO 仍在第三个上升沿释放。入口状态的异步复位在
    // 随后的下降沿释放，两者允许的首个上升沿采样相同。
    reset_release_sync_data #(.DATA_RESET_COPIES(0), .FALLING_RELEASE(1)) u_source_reset (
        .i_clk(i_source_clk), .i_async_rst_n(session_async_rst_n),
        .o_rst_n(ingress_rst_n), .o_data_rst_n(source_local_rst_n)
    );
    reset_release_sync u_sink_reset (
        .i_clk(i_sink_clk), .i_async_rst_n(session_async_rst_n),
        .o_rst_n(sink_local_rst_n)
    );

    ordered_frame_ingress #(.CONTEXT_ENABLE(CONTEXT_ENABLE),.WRITE_TAG_ENABLE(WRITE_TAG_ENABLE),.RECORD_EXTENSION_ENABLE(RECORD_EXTENSION_ENABLE),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),.BORROW_EXTENSION(BORROW_EXTENSION),.MASK_CONTEXT_ENABLE(MASK_CONTEXT_ENABLE),.STREAM_EXTENSION(STREAM_EXTENSION),
        .SEPARATE_DATA_RESET(1)) u_ingress (
        .i_clk(i_source_clk), .i_rst_n(ingress_rst_n), .i_data_rst_n(source_local_rst_n),
        .i_start_valid(i_start_valid), .o_start_ready(o_start_ready),
        .i_capture_id(i_capture_id), .i_width(i_width),
        .i_height(i_height), .i_timestamp_ns(i_timestamp_ns),
        .i_session_id(i_session_id),.i_mode_epoch(i_mode_epoch),.i_camera_id(i_camera_id),
        .i_quality(i_quality),.i_format(i_format),.i_write_tag(i_write_tag),
        .i_start_mask(i_start_mask),.i_start_source_type(i_start_source_type),
        .i_jpeg_tdata(i_jpeg_tdata), .i_jpeg_tkeep(i_jpeg_tkeep),
        .i_jpeg_tlast(i_jpeg_tlast), .i_jpeg_tvalid(i_jpeg_tvalid),
        .o_jpeg_tready(o_jpeg_tready),
        .i_result_valid(i_result_valid), .o_result_ready(o_result_ready),
        .i_result_id(i_result_id), .i_result_ok(i_result_ok),
        .i_result_length(i_result_length), .i_result_error(i_result_error),
        .i_result_quality(i_result_quality),.i_result_epoch(i_result_epoch),
        .i_record_extension(i_record_extension),.i_record_extension_valid(i_record_extension_valid),
        .i_extension_stream_data(i_extension_stream_data),.i_extension_stream_valid(i_extension_stream_valid),
        .o_extension_stream_ready(o_extension_stream_ready),.o_extension_stream_start(o_extension_stream_start),
        .o_record_extension_ready(o_record_extension_ready),.o_protocol_fault(o_source_protocol_fault),
        .o_token_data(write_token), .o_token_valid(write_valid),
        .i_token_ready(write_ready)
    );

    ordered_frame_fifo_fence u_token_fifo (
        .i_source_clk(i_source_clk), .i_source_rst_n(source_local_rst_n),
        .i_source_data(write_token), .i_source_valid(write_valid),
        .o_source_ready(write_ready),
        .o_source_reset_done(o_source_reset_done),
        .i_sink_clk(i_sink_clk), .i_sink_rst_n(sink_local_rst_n),
        .o_sink_data(read_token), .o_sink_valid(read_valid),
        .i_sink_ready(read_ready), .o_sink_reset_done(o_sink_reset_done),
        .i_fence_request(i_fence_request),.i_source_idle(i_source_fence_idle),
        .i_source_session(i_source_fence_session),.i_raw_enqueued(i_raw_enqueued),
        .i_sink_quiet(i_sink_fence_quiet && !egress_pending),.i_sink_session(i_sink_fence_session),
        .i_raw_consumed(i_raw_consumed),.i_raw_consume_fire(i_raw_consume_fire),
        .o_source_proven(o_source_fence_proven),.o_source_fault(o_source_fence_fault),.o_sink_fault(o_sink_fence_fault)
    );

    ordered_frame_egress #(.CONTEXT_ENABLE(CONTEXT_ENABLE),.WRITE_TAG_ENABLE(WRITE_TAG_ENABLE),.RECORD_EXTENSION_ENABLE(RECORD_EXTENSION_ENABLE),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),.MASK_CONTEXT_ENABLE(MASK_CONTEXT_ENABLE),.EXTENSION_RAM_ENABLE(EXTENSION_RAM_ENABLE)) u_egress (
        .i_clk(i_sink_clk), .i_rst_n(sink_local_rst_n),
        .i_token_data(read_token), .i_token_valid(read_valid),
        .o_token_ready(read_ready),.o_token_pending(egress_pending),
        .o_start_valid(o_start_valid), .i_start_ready(i_start_ready),
        .o_capture_id(o_capture_id), .o_width(o_width),
        .o_height(o_height), .o_timestamp_ns(o_timestamp_ns),
        .o_session_id(o_session_id),.o_mode_epoch(o_mode_epoch),.o_camera_id(o_camera_id),
        .o_quality(o_quality),.o_format(o_format),.o_write_tag(o_write_tag),
        .o_start_mask(o_start_mask),.o_start_source_type(o_start_source_type),
        .o_jpeg_tdata(o_jpeg_tdata), .o_jpeg_tkeep(o_jpeg_tkeep),
        .o_jpeg_tlast(o_jpeg_tlast), .o_jpeg_tvalid(o_jpeg_tvalid),
        .i_jpeg_tready(i_jpeg_tready),
        .o_result_valid(o_result_valid), .i_result_ready(i_result_ready),
        .o_result_id(o_result_id), .o_result_ok(o_result_ok),
        .o_result_length(o_result_length), .o_result_error(o_result_error),
        .o_result_quality(o_result_quality),.o_result_epoch(o_result_epoch),
        .o_record_extension(o_record_extension),.o_record_extension_valid(o_record_extension_valid),
        .i_record_extension_ready(i_record_extension_ready),
        .o_extension_shape_valid(o_extension_shape_valid),
        .i_extension_read_enable(i_extension_read_enable),.i_extension_read_index(i_extension_read_index),
        .o_extension_read_data(o_extension_read_data),
        .o_protocol_fault(o_protocol_fault)
    );
endmodule
