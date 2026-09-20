`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/15
// Design Name:     pcie_video_transport
// Module Name:     pcie_video_transport
// Description:     Reusable PCIe video stream and AXI4-Lite transport boundary.
// Dependencies:    PCIe endpoint, in-band adapter, C2H frame transmitter
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月15日
// 设计名称:        pcie_video_transport
// 模块名称:        pcie_video_transport
// 模块说明:        可复用PCIe视频流与AXI4-Lite传输边界。
// 依赖文件:        PCIe端点、带内帧头适配器、C2H帧发送器

`include "pcie_protocol_v1.vh"

module pcie_video_transport (
    input  wire         i_sys_clk,
    input  wire         i_refclk_p,
    input  wire         i_refclk_n,
    input  wire         i_pcie_mperst,
    input  wire [0:0]   i_pcie_rxp,
    input  wire [0:0]   i_pcie_rxn,
    output wire [0:0]   o_pcie_txp,
    output wire [0:0]   o_pcie_txn,
    input  wire         i_app_enable,
    input  wire         i_app_reset_n,
    input  wire [127:0] i_src_tdata,
    input  wire [15:0]  i_src_tkeep,
    input  wire         i_src_tvalid,
    output wire         o_src_tready,
    input  wire         i_src_tlast,
    output wire [127:0] o_h2c_tdata,
    output wire [15:0]  o_h2c_tkeep,
    output wire [15:0]  o_h2c_tuser,
    output wire         o_h2c_tvalid,
    input  wire         i_h2c_tready,
    output wire         o_h2c_tlast,
    output wire [31:0]  o_axil_awaddr,
    output wire [2:0]   o_axil_awprot,
    output wire         o_axil_awvalid,
    input  wire         i_axil_awready,
    output wire [31:0]  o_axil_wdata,
    output wire [3:0]   o_axil_wstrb,
    output wire         o_axil_wvalid,
    input  wire         i_axil_wready,
    input  wire [1:0]   i_axil_bresp,
    input  wire         i_axil_bvalid,
    output wire         o_axil_bready,
    output wire [31:0]  o_axil_araddr,
    output wire [2:0]   o_axil_arprot,
    output wire         o_axil_arvalid,
    input  wire         i_axil_arready,
    input  wire [31:0]  i_axil_rdata,
    input  wire [1:0]   i_axil_rresp,
    input  wire         i_axil_rvalid,
    output wire         o_axil_rready,
    output wire         o_user_clk,
    output wire         o_user_rst_n,
    output wire         o_user_link_up,
    output wire [7:0]   o_c2h_status,
    output wire [7:0]   o_h2c_status,
    output wire         o_c2h_running,
    output wire         o_tx_busy,
    output wire         o_recovery_required,
    output wire [31:0]  o_last_error,
    output wire         o_frame_accept,
    output wire         o_frame_done,
    output wire         o_frame_abort
);

    wire transport_rst_n;
    wire [127:0] c2h_tdata;
    wire [15:0] c2h_tkeep;
    wire [15:0] c2h_tuser;
    wire c2h_tvalid;
    wire c2h_tready;
    wire c2h_tlast;
    wire meta_valid;
    wire meta_ready;
    wire [31:0] meta_frame_sequence;
    wire [31:0] meta_payload_length;
    wire [15:0] meta_width;
    wire [15:0] meta_height;
    wire [7:0] meta_pixel_format;
    wire [7:0] meta_compression;
    wire [7:0] meta_quality;
    wire [63:0] meta_timestamp_ns;
    wire [31:0] meta_status;
    wire [31:0] meta_error_code;
    wire [15:0] meta_slot_id;
    wire [31:0] meta_payload_crc32;
    wire [127:0] payload_tdata;
    wire [15:0] payload_tkeep;
    wire payload_tvalid;
    wire payload_tready;
    wire payload_tlast;
    wire header_error;
    wire [31:0] header_last_error;
    wire adapter_busy;
    wire frame_tx_abort;
    wire [31:0] frame_tx_last_error;
    wire [15:0] active_slot_id;
    wire transport_ready;
    reg recovery_required;
    reg [31:0] sticky_last_error;
    reg metadata_accepted;
    wire payload_source_ready;
    wire frame_tx_busy;
    wire source_admit;

    assign transport_rst_n = o_user_rst_n && i_app_reset_n;
    assign source_admit = !recovery_required && i_app_enable && !frame_tx_abort &&
                          !(metadata_accepted && (!o_user_link_up || !o_c2h_running));
    assign o_src_tready = source_admit ? payload_source_ready : 1'b0;
    assign o_recovery_required = recovery_required;
    assign o_last_error = recovery_required ? sticky_last_error :
                          ((header_last_error != `PCIE_ERROR_NONE) ?
                           header_last_error : frame_tx_last_error);
    assign o_frame_abort = frame_tx_abort || header_error;
    assign o_tx_busy = frame_tx_busy || adapter_busy || recovery_required;

    always @(posedge o_user_clk or negedge transport_rst_n) begin
        if (!transport_rst_n) begin
            recovery_required <= 1'b0;
            sticky_last_error <= `PCIE_ERROR_NONE;
            metadata_accepted <= 1'b0;
        end else begin
            if (o_frame_done) begin
                metadata_accepted <= 1'b0;
            end
            if (meta_valid && meta_ready) begin
                metadata_accepted <= 1'b1;
            end
            if (metadata_accepted && !o_frame_done &&
                (frame_tx_abort || !i_app_enable || !o_user_link_up || !o_c2h_running)) begin
                recovery_required <= 1'b1;
                metadata_accepted <= 1'b0;
                if (frame_tx_last_error != `PCIE_ERROR_NONE) begin
                    sticky_last_error <= frame_tx_last_error;
                end else begin
                    sticky_last_error <= `PCIE_ERROR_RECOVERY_REQUIRED;
                end
            end
        end
    end

    pcie_inband_header_adapter u_pcie_inband_header_adapter (
        .i_clk(o_user_clk), .i_rst_n(transport_rst_n),
        .i_src_tdata(i_src_tdata), .i_src_tkeep(i_src_tkeep),
        .i_src_tvalid(i_src_tvalid && source_admit),
        .o_src_tready(payload_source_ready),
        .i_src_tlast(i_src_tlast), .o_meta_valid(meta_valid),
        .i_meta_ready(meta_ready), .o_meta_frame_sequence(meta_frame_sequence),
        .o_meta_payload_length(meta_payload_length), .o_meta_width(meta_width),
        .o_meta_height(meta_height), .o_meta_pixel_format(meta_pixel_format),
        .o_meta_compression(meta_compression), .o_meta_quality(meta_quality),
        .o_meta_timestamp_ns(meta_timestamp_ns), .o_meta_status(meta_status),
        .o_meta_error_code(meta_error_code), .o_meta_slot_id(meta_slot_id),
        .o_meta_payload_crc32(meta_payload_crc32), .o_payload_tdata(payload_tdata),
        .o_payload_tkeep(payload_tkeep), .o_payload_tvalid(payload_tvalid),
        .i_payload_tready(payload_tready), .o_payload_tlast(payload_tlast),
        .o_header_error(header_error), .o_last_error(header_last_error),
        .o_busy(adapter_busy)
    );

    c2h_frame_tx u_c2h_frame_tx (
        .i_clk(o_user_clk), .i_rst_n(transport_rst_n),
        .i_transport_enable(i_app_enable && !recovery_required),
        .i_link_up(o_user_link_up), .i_c2h_running(o_c2h_running),
        .i_meta_valid(meta_valid), .o_meta_ready(meta_ready),
        .i_meta_frame_sequence(meta_frame_sequence),
        .i_meta_payload_length(meta_payload_length), .i_meta_width(meta_width),
        .i_meta_height(meta_height), .i_meta_pixel_format(meta_pixel_format),
        .i_meta_compression(meta_compression), .i_meta_quality(meta_quality),
        .i_meta_timestamp_ns(meta_timestamp_ns), .i_meta_status(meta_status),
        .i_meta_error_code(meta_error_code), .i_meta_slot_id(meta_slot_id),
        .i_meta_payload_crc32(meta_payload_crc32), .i_src_tdata(payload_tdata),
        .i_src_tkeep(payload_tkeep), .i_src_tvalid(payload_tvalid),
        .o_src_tready(payload_tready), .i_src_tlast(payload_tlast),
        .o_axis_tdata(c2h_tdata), .o_axis_tkeep(c2h_tkeep),
        .o_axis_tuser(c2h_tuser), .o_axis_tvalid(c2h_tvalid),
        .i_axis_tready(c2h_tready), .o_axis_tlast(c2h_tlast),
        .o_tx_busy(frame_tx_busy), .o_transport_ready(transport_ready),
        .o_active_slot_id(active_slot_id), .o_last_error(frame_tx_last_error),
        .o_frame_accept(o_frame_accept), .o_frame_done(o_frame_done),
        .o_frame_abort(frame_tx_abort)
    );

    pcie_sgdma_endpoint u_pcie_sgdma_endpoint (
        .i_sys_clk(i_sys_clk), .i_refclk_p(i_refclk_p), .i_refclk_n(i_refclk_n),
        .i_pcie_mperst(i_pcie_mperst), .i_pcie_rxp(i_pcie_rxp),
        .i_pcie_rxn(i_pcie_rxn), .o_pcie_txp(o_pcie_txp), .o_pcie_txn(o_pcie_txn),
        .i_c2h_tdata(c2h_tdata), .i_c2h_tkeep(c2h_tkeep),
        .i_c2h_tuser(c2h_tuser), .i_c2h_tvalid(c2h_tvalid),
        .o_c2h_tready(c2h_tready), .i_c2h_tlast(c2h_tlast),
        .o_h2c_tdata(o_h2c_tdata), .o_h2c_tkeep(o_h2c_tkeep),
        .o_h2c_tuser(o_h2c_tuser), .o_h2c_tvalid(o_h2c_tvalid),
        .i_h2c_tready(i_h2c_tready), .o_h2c_tlast(o_h2c_tlast),
        .o_axil_awaddr(o_axil_awaddr), .o_axil_awprot(o_axil_awprot),
        .o_axil_awvalid(o_axil_awvalid), .i_axil_awready(i_axil_awready),
        .o_axil_wdata(o_axil_wdata), .o_axil_wstrb(o_axil_wstrb),
        .o_axil_wvalid(o_axil_wvalid), .i_axil_wready(i_axil_wready),
        .i_axil_bresp(i_axil_bresp), .i_axil_bvalid(i_axil_bvalid),
        .o_axil_bready(o_axil_bready), .o_axil_araddr(o_axil_araddr),
        .o_axil_arprot(o_axil_arprot), .o_axil_arvalid(o_axil_arvalid),
        .i_axil_arready(i_axil_arready), .i_axil_rdata(i_axil_rdata),
        .i_axil_rresp(i_axil_rresp), .i_axil_rvalid(i_axil_rvalid),
        .o_axil_rready(o_axil_rready), .o_user_clk(o_user_clk),
        .o_user_rst_n(o_user_rst_n), .o_user_link_up(o_user_link_up),
        .o_c2h_status(o_c2h_status), .o_h2c_status(o_h2c_status),
        .o_c2h_running(o_c2h_running)
    );

    wire unused_transport_status;
    assign unused_transport_status = transport_ready ^ ^active_slot_id;

endmodule
