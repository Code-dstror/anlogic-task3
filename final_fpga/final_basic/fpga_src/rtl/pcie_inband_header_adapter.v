`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// 校验带内帧头并分离元数据与载荷
module pcie_inband_header_adapter #(
    parameter integer RECORD_V2_ENABLE = 0,
    parameter integer RECORD_V3_ENABLE = 0,
    parameter integer RECORD_EXTENSION_WIDTH = RECORD_V3_ENABLE ? 3072 : 1024,
    parameter integer HEADER_EXTENSION_RAM_ENABLE=0
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 带内输入流
    input  wire [127:0] i_src_tdata,
    input  wire [15:0] i_src_tkeep,
    input  wire i_src_tvalid,
    output wire o_src_tready,
    input  wire i_src_tlast,
    // The owner selects the format while all record domains are quiescent.
    // A header never changes this selection by carrying its own version.
    input  wire [15:0] i_selected_version,

    // 帧元数据输出
    output wire o_meta_valid,
    input  wire i_meta_ready,
    output wire [31:0] o_meta_frame_sequence,
    output wire [31:0] o_meta_payload_length,
    output wire [15:0] o_meta_width,
    output wire [15:0] o_meta_height,
    output wire [7:0] o_meta_pixel_format,
    output wire [7:0] o_meta_compression,
    output wire [7:0] o_meta_quality,
    output wire [63:0] o_meta_timestamp_ns,
    output wire [31:0] o_meta_status,
    output wire [31:0] o_meta_error_code,
    output wire [15:0] o_meta_slot_id,
    output wire [31:0] o_meta_payload_crc32,
    output wire [15:0] o_meta_record_version,
    output wire [RECORD_EXTENSION_WIDTH-1:0] o_meta_record_extension,

    // 载荷输出流
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input  wire i_payload_tready,
    output wire o_payload_tlast,

    // 错误与活动状态
    output wire o_header_error, // 带内帧头校验失败
    output wire [31:0] o_last_error,
    output wire o_busy,
    output wire [127:0] o_extension_tdata,
    output wire o_extension_tvalid,o_extension_tlast,
    input wire i_extension_tready
);
    generate if(HEADER_EXTENSION_RAM_ENABLE==0)begin:g_legacy
        pcie_inband_header_adapter_legacy #(.RECORD_V2_ENABLE(RECORD_V2_ENABLE),.RECORD_V3_ENABLE(RECORD_V3_ENABLE),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH)) u_legacy(.i_clk(i_clk),.i_rst_n(i_rst_n),.i_src_tdata(i_src_tdata),.i_src_tkeep(i_src_tkeep),.i_src_tvalid(i_src_tvalid),.o_src_tready(o_src_tready),.i_src_tlast(i_src_tlast),.i_selected_version(i_selected_version),.o_meta_valid(o_meta_valid),.i_meta_ready(i_meta_ready),.o_meta_frame_sequence(o_meta_frame_sequence),.o_meta_payload_length(o_meta_payload_length),.o_meta_width(o_meta_width),.o_meta_height(o_meta_height),.o_meta_pixel_format(o_meta_pixel_format),.o_meta_compression(o_meta_compression),.o_meta_quality(o_meta_quality),.o_meta_timestamp_ns(o_meta_timestamp_ns),.o_meta_status(o_meta_status),.o_meta_error_code(o_meta_error_code),.o_meta_slot_id(o_meta_slot_id),.o_meta_payload_crc32(o_meta_payload_crc32),.o_meta_record_version(o_meta_record_version),.o_meta_record_extension(o_meta_record_extension),.o_payload_tdata(o_payload_tdata),.o_payload_tkeep(o_payload_tkeep),.o_payload_tvalid(o_payload_tvalid),.i_payload_tready(i_payload_tready),.o_payload_tlast(o_payload_tlast),.o_header_error(o_header_error),.o_last_error(o_last_error),.o_busy(o_busy));
        assign o_extension_tdata=0;assign o_extension_tvalid=0;assign o_extension_tlast=0;
    end else begin:g_ram
        pcie_header_extension_ram #(.RECORD_V2_ENABLE(RECORD_V2_ENABLE),.RECORD_V3_ENABLE(RECORD_V3_ENABLE),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH)) u_ram(.i_clk(i_clk),.i_rst_n(i_rst_n),.i_src_tdata(i_src_tdata),.i_src_tkeep(i_src_tkeep),.i_src_tvalid(i_src_tvalid),.o_src_tready(o_src_tready),.i_src_tlast(i_src_tlast),.i_selected_version(i_selected_version),.o_meta_valid(o_meta_valid),.i_meta_ready(i_meta_ready),.o_meta_frame_sequence(o_meta_frame_sequence),.o_meta_payload_length(o_meta_payload_length),.o_meta_width(o_meta_width),.o_meta_height(o_meta_height),.o_meta_pixel_format(o_meta_pixel_format),.o_meta_compression(o_meta_compression),.o_meta_quality(o_meta_quality),.o_meta_timestamp_ns(o_meta_timestamp_ns),.o_meta_status(o_meta_status),.o_meta_error_code(o_meta_error_code),.o_meta_slot_id(o_meta_slot_id),.o_meta_payload_crc32(o_meta_payload_crc32),.o_meta_record_version(o_meta_record_version),.o_meta_record_extension(o_meta_record_extension),.o_payload_tdata(o_payload_tdata),.o_payload_tkeep(o_payload_tkeep),.o_payload_tvalid(o_payload_tvalid),.i_payload_tready(i_payload_tready),.o_payload_tlast(o_payload_tlast),.o_header_error(o_header_error),.o_last_error(o_last_error),.o_busy(o_busy),.o_extension_tdata(o_extension_tdata),.o_extension_tvalid(o_extension_tvalid),.o_extension_tlast(o_extension_tlast),.i_extension_tready(i_extension_tready));
    end endgenerate
endmodule
