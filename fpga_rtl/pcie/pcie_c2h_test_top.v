`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     pcie_c2h_test_top
// Module Name:     pcie_c2h_test_top
// Description:     Board-level PCIe C2H/H2C transport verification top.
// Dependencies:    PCIe SGDMA endpoint and application transport modules
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        pcie_c2h_test_top
// 模块名称:        pcie_c2h_test_top
// 模块说明:        板级PCIe C2H/H2C传输验证顶层。
// 依赖文件:        PCIe SGDMA端点与应用传输模块

`include "pcie_protocol_v1.vh"
`include "c2h_test_fixture.vh"

module pcie_c2h_test_top (
    input  wire       sys_clk,
    input  wire       refclk_p,
    input  wire       refclk_n,
    output wire [0:0] txp,
    output wire [0:0] txn,
    input  wire [0:0] rxp,
    input  wire [0:0] rxn,
    input  wire       pcie_mperst
);

    wire user_clk;
    wire user_rst_n;
    wire user_link_up;
    wire c2h_running;
    wire [7:0] c2h_status;
    wire [7:0] h2c_status;

    wire [127:0] h2c_tdata;
    wire [15:0] h2c_tkeep;
    wire [15:0] h2c_tuser;
    wire h2c_tvalid;
    wire h2c_tready;
    wire h2c_tlast;

    wire [31:0] axil_awaddr;
    wire [2:0] axil_awprot;
    wire axil_awvalid;
    wire axil_awready;
    wire [31:0] axil_wdata;
    wire [3:0] axil_wstrb;
    wire axil_wvalid;
    wire axil_wready;
    wire [1:0] axil_bresp;
    wire axil_bvalid;
    wire axil_bready;
    wire [31:0] axil_araddr;
    wire [2:0] axil_arprot;
    wire axil_arvalid;
    wire axil_arready;
    wire [31:0] axil_rdata;
    wire [1:0] axil_rresp;
    wire axil_rvalid;
    wire axil_rready;

    wire app_enable;
    wire soft_reset;
    wire app_rst_n;
    wire [31:0] test_length;
    wire [1:0] test_pattern;
    wire test_trigger;
    wire source_busy;
    wire tx_busy;
    wire frame_accept;
    wire frame_done;
    wire frame_abort;
    wire [31:0] frame_last_error;

    wire [31:0] meta_frame_sequence;
    wire [127:0] source_tdata;
    wire [15:0] source_tkeep;
    wire source_tvalid;
    wire source_tready;
    wire source_tlast;

    reg [31:0] consumed_sequence;
    reg [31:0] dma_error_count;
    reg [31:0] drop_count;
    reg [31:0] overflow_count;
    wire [31:0] ready_mask;
    wire [31:0] sending_mask;
    wire [31:0] status_value;
    wire [31:0] h2c_byte_count;
    wire [31:0] h2c_frame_count;
    wire [31:0] h2c_error_count;
    wire [31:0] h2c_first_error;

    assign app_rst_n = user_rst_n && !soft_reset;
    assign ready_mask = {31'd0, app_enable && !source_busy};
    assign sending_mask = {31'd0, tx_busy};
    assign status_value = {
        26'd0,
        (frame_last_error != `PCIE_ERROR_NONE),
        source_busy,
        tx_busy,
        c2h_running,
        user_rst_n,
        user_link_up
    };

    always @(posedge user_clk or negedge app_rst_n) begin
        if (!app_rst_n) begin
            consumed_sequence <= 32'd0;
            dma_error_count <= 32'd0;
            drop_count <= 32'd0;
            overflow_count <= 32'd0;
        end else begin
            if (frame_done) begin
                consumed_sequence <= consumed_sequence + 1'b1;
            end
            if (frame_abort) begin
                dma_error_count <= dma_error_count + 1'b1;
                if (frame_last_error == `PCIE_ERROR_PAYLOAD_LENGTH) begin
                    overflow_count <= overflow_count + 1'b1;
                end
            end
            if (test_trigger && source_busy) begin
                drop_count <= drop_count + 1'b1;
            end
        end
    end

    pcie_video_transport u_pcie_video_transport (
        .i_sys_clk(sys_clk),
        .i_refclk_p(refclk_p),
        .i_refclk_n(refclk_n),
        .i_pcie_mperst(pcie_mperst),
        .i_pcie_rxp(rxp),
        .i_pcie_rxn(rxn),
        .o_pcie_txp(txp),
        .o_pcie_txn(txn),
        .i_app_enable(app_enable),
        .i_app_reset_n(!soft_reset),
        .i_src_tdata(source_tdata),
        .i_src_tkeep(source_tkeep),
        .i_src_tvalid(source_tvalid),
        .o_src_tready(source_tready),
        .i_src_tlast(source_tlast),
        .o_h2c_tdata(h2c_tdata),
        .o_h2c_tkeep(h2c_tkeep),
        .o_h2c_tuser(h2c_tuser),
        .o_h2c_tvalid(h2c_tvalid),
        .i_h2c_tready(h2c_tready),
        .o_h2c_tlast(h2c_tlast),
        .o_axil_awaddr(axil_awaddr),
        .o_axil_awprot(axil_awprot),
        .o_axil_awvalid(axil_awvalid),
        .i_axil_awready(axil_awready),
        .o_axil_wdata(axil_wdata),
        .o_axil_wstrb(axil_wstrb),
        .o_axil_wvalid(axil_wvalid),
        .i_axil_wready(axil_wready),
        .i_axil_bresp(axil_bresp),
        .i_axil_bvalid(axil_bvalid),
        .o_axil_bready(axil_bready),
        .o_axil_araddr(axil_araddr),
        .o_axil_arprot(axil_arprot),
        .o_axil_arvalid(axil_arvalid),
        .i_axil_arready(axil_arready),
        .i_axil_rdata(axil_rdata),
        .i_axil_rresp(axil_rresp),
        .i_axil_rvalid(axil_rvalid),
        .o_axil_rready(axil_rready),
        .o_user_clk(user_clk),
        .o_user_rst_n(user_rst_n),
        .o_user_link_up(user_link_up),
        .o_c2h_status(c2h_status),
        .o_h2c_status(h2c_status),
        .o_c2h_running(c2h_running),
        .o_tx_busy(tx_busy),
        .o_recovery_required(),
        .o_last_error(frame_last_error),
        .o_frame_accept(frame_accept),
        .o_frame_done(frame_done),
        .o_frame_abort(frame_abort)
    );

    pcie_app_regs u_pcie_app_regs (
        .i_clk(user_clk),
        .i_rst_n(user_rst_n),
        .i_axil_awaddr(axil_awaddr),
        .i_axil_awprot(axil_awprot),
        .i_axil_awvalid(axil_awvalid),
        .o_axil_awready(axil_awready),
        .i_axil_wdata(axil_wdata),
        .i_axil_wstrb(axil_wstrb),
        .i_axil_wvalid(axil_wvalid),
        .o_axil_wready(axil_wready),
        .o_axil_bresp(axil_bresp),
        .o_axil_bvalid(axil_bvalid),
        .i_axil_bready(axil_bready),
        .i_axil_araddr(axil_araddr),
        .i_axil_arprot(axil_arprot),
        .i_axil_arvalid(axil_arvalid),
        .o_axil_arready(axil_arready),
        .o_axil_rdata(axil_rdata),
        .o_axil_rresp(axil_rresp),
        .o_axil_rvalid(axil_rvalid),
        .i_axil_rready(axil_rready),
        .i_status(status_value),
        .i_ready_mask(ready_mask),
        .i_sending_mask(sending_mask),
        .i_producer_sequence(meta_frame_sequence),
        .i_consumed_sequence(consumed_sequence),
        .i_drop_count(drop_count),
        .i_overflow_count(overflow_count),
        .i_dma_error_count(dma_error_count),
        .i_last_error(frame_last_error),
        .i_h2c_byte_count(h2c_byte_count),
        .i_h2c_frame_count(h2c_frame_count),
        .i_h2c_error_count(h2c_error_count),
        .i_h2c_first_error(h2c_first_error),
        .o_app_enable(app_enable),
        .o_soft_reset(soft_reset),
        .o_test_length(test_length),
        .o_test_pattern(test_pattern),
        .o_test_trigger(test_trigger)
    );

    c2h_inband_test_source u_c2h_inband_test_source (
        .i_clk(user_clk),
        .i_rst_n(app_rst_n),
        .i_start(test_trigger && app_enable && !source_busy &&
                 ((test_pattern == `C2H_TEST_PATTERN_JPEG_FIXTURE) ||
                  ((test_length != 32'd0) &&
                   (test_length <= `PCIE_MAX_PAYLOAD))),
        .i_payload_length(test_length),
        .i_pattern_select(test_pattern),
        .o_busy(source_busy),
        .o_frame_sequence(meta_frame_sequence),
        .o_src_tdata(source_tdata),
        .o_src_tkeep(source_tkeep),
        .o_src_tvalid(source_tvalid),
        .i_src_tready(source_tready),
        .o_src_tlast(source_tlast)
    );

    h2c_stream_checker u_h2c_stream_checker (
        .i_clk(user_clk),
        .i_rst_n(app_rst_n),
        .i_axis_tdata(h2c_tdata),
        .i_axis_tkeep(h2c_tkeep),
        .i_axis_tvalid(h2c_tvalid),
        .o_axis_tready(h2c_tready),
        .i_axis_tlast(h2c_tlast),
        .o_byte_count(h2c_byte_count),
        .o_frame_count(h2c_frame_count),
        .o_error_count(h2c_error_count),
        .o_first_error_offset(h2c_first_error)
    );

    wire unused_application_status;
    assign unused_application_status = frame_accept ^ ^h2c_tuser ^
                                       ^c2h_status ^ ^h2c_status;

endmodule
