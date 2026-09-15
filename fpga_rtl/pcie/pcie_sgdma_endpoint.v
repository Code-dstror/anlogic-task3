`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     pcie_sgdma_endpoint
// Module Name:     pcie_sgdma_endpoint
// Description:     PH1A PCIe Gen2 x1 and SGDMA integration boundary.
// Dependencies:    sgdma_pll, sgdma_subsys, PH1 logic primitives
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        pcie_sgdma_endpoint
// 模块名称:        pcie_sgdma_endpoint
// 模块说明:        PH1A PCIe Gen2 x1与SGDMA集成边界。
// 依赖文件:        sgdma_pll、sgdma_subsys、PH1逻辑原语

`include "pcie_feature_defines.vh"

module pcie_sgdma_endpoint (
    input  wire         i_sys_clk,
    input  wire         i_refclk_p,
    input  wire         i_refclk_n,
    input  wire         i_pcie_mperst,
    input  wire [0:0]   i_pcie_rxp,
    input  wire [0:0]   i_pcie_rxn,
    output wire [0:0]   o_pcie_txp,
    output wire [0:0]   o_pcie_txn,

    input  wire [127:0] i_c2h_tdata,
    input  wire [15:0]  i_c2h_tkeep,
    input  wire [15:0]  i_c2h_tuser,
    input  wire         i_c2h_tvalid,
    output wire         o_c2h_tready,
    input  wire         i_c2h_tlast,

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
    output wire         o_c2h_running
);

    reg [9:0] power_on_count = 10'd0;
    reg power_on_done = 1'b0;
    reg [21:0] pll_stable_count = 22'd0;
    reg pll_lock_stable = 1'b0;

    wire sys_clk_global;
    wire core_clk;
    wire auxiliary_clk;
    wire pll_lock;
    wire tl_power_on_rst_n;
    wire [7:0] c2h_status_one;
    wire [7:0] h2c_status_one;
    wire [7:0] c2h_status_two;
    wire [7:0] h2c_status_two;
    wire [7:0] c2h_status_three;
    wire [7:0] h2c_status_three;
    wire [15:0] user_irq_ack;
    wire msi_enable;
    wire [2:0] msi_vector_width;

    PH1_LOGIC_BUFG u_system_clock_buffer (
        .i(i_sys_clk),
        .o(sys_clk_global)
    );

    always @(posedge sys_clk_global) begin
        if (!i_pcie_mperst) begin
            power_on_count <= 10'd0;
            power_on_done <= 1'b0;
        end else if (!power_on_done) begin
            power_on_count <= power_on_count + 1'b1;
            if (&power_on_count) begin
                power_on_done <= 1'b1;
            end
        end
    end

    sgdma_pll u_sgdma_pll (
        .refclk(sys_clk_global),
        .reset(!power_on_done),
        .lock(pll_lock),
        .clk0_out(core_clk),
        .clk1_out(auxiliary_clk)
    );

    always @(posedge core_clk or negedge i_pcie_mperst) begin
        if (!i_pcie_mperst) begin
            pll_stable_count <= 22'd0;
            pll_lock_stable <= 1'b0;
        end else if (!pll_lock) begin
            pll_stable_count <= 22'd0;
            pll_lock_stable <= 1'b0;
        end else if (!pll_lock_stable) begin
            pll_stable_count <= pll_stable_count + 1'b1;
            if (&pll_stable_count) begin
                pll_lock_stable <= 1'b1;
            end
        end
    end

    assign tl_power_on_rst_n = i_pcie_mperst && pll_lock_stable;
    assign o_c2h_running = o_c2h_status[6];

    sgdma_subsys #(
        .SIM_MODE(0),
        .DEVICE_FAMILY("PH1A"),
        .USER_CLK_FREQ(125),
        .LINK_WIDTH(1),
        .DATA_WIDTH(128),
        .AXI4MM_BUS_EN(0),
        .AXI4ST_BUS_EN(1),
        .DMA_BYPA_EN(0),
        .CFG_MGMT_EN(0),
        .AXI4L_MBUS_EN(1),
        .AXI4L_SBUS_EN(0),
        .USR_IRQ_NUM(16),
        .LGCY_EN(0),
        .MSI_EN(1),
        .MSIX_EN(0),
        .H2C_CHNL_NUM(1),
        .C2H_CHNL_NUM(1),
        .H2C_DSC_BYP_MAP(0),
        .C2H_DSC_BYP_MAP(0),
        .H2C_ID_NUM(32),
        .C2H_ID_NUM(16)
    ) u_sgdma_subsystem (
        .app_auxclk(auxiliary_clk),
        .tl_power_on_rstn(tl_power_on_rst_n),
        .tl_clk_user(core_clk),
        .pll_lock(pll_lock),
        .ref_pad_clk_p(i_refclk_p),
        .ref_pad_clk_n(i_refclk_n),
        .pcie_tx_p(o_pcie_txp),
        .pcie_tx_n(o_pcie_txn),
        .pcie_rx_p(i_pcie_rxp),
        .pcie_rx_n(i_pcie_rxn),
        .c2h_sts_0(o_c2h_status),
        .h2c_sts_0(o_h2c_status),
        .c2h_sts_1(c2h_status_one),
        .h2c_sts_1(h2c_status_one),
        .c2h_sts_2(c2h_status_two),
        .h2c_sts_2(h2c_status_two),
        .c2h_sts_3(c2h_status_three),
        .h2c_sts_3(h2c_status_three),
        .s0_axis_c2h_tready(o_c2h_tready),
        .s0_axis_c2h_tdata(i_c2h_tdata),
        .s0_axis_c2h_tkeep(i_c2h_tkeep),
        .s0_axis_c2h_tuser(i_c2h_tuser),
        .s0_axis_c2h_tlast(i_c2h_tlast),
        .s0_axis_c2h_tvalid(i_c2h_tvalid),
        .m0_axis_h2c_tready(i_h2c_tready),
        .m0_axis_h2c_tdata(o_h2c_tdata),
        .m0_axis_h2c_tkeep(o_h2c_tkeep),
        .m0_axis_h2c_tuser(o_h2c_tuser),
        .m0_axis_h2c_tlast(o_h2c_tlast),
        .m0_axis_h2c_tvalid(o_h2c_tvalid),
        .usr_irq_req(16'd0),
        .usr_irq_ack(user_irq_ack),
        .msi_enable(msi_enable),
        .msi_vector_width(msi_vector_width),
        .m_axil_awaddr(o_axil_awaddr),
        .m_axil_awprot(o_axil_awprot),
        .m_axil_awvalid(o_axil_awvalid),
        .m_axil_awready(i_axil_awready),
        .m_axil_wdata(o_axil_wdata),
        .m_axil_wstrb(o_axil_wstrb),
        .m_axil_wvalid(o_axil_wvalid),
        .m_axil_wready(i_axil_wready),
        .m_axil_bvalid(i_axil_bvalid),
        .m_axil_bresp(i_axil_bresp),
        .m_axil_bready(o_axil_bready),
        .m_axil_araddr(o_axil_araddr),
        .m_axil_arprot(o_axil_arprot),
        .m_axil_arvalid(o_axil_arvalid),
        .m_axil_arready(i_axil_arready),
        .m_axil_rdata(i_axil_rdata),
        .m_axil_rresp(i_axil_rresp),
        .m_axil_rvalid(i_axil_rvalid),
        .m_axil_rready(o_axil_rready),
        .user_link_up(o_user_link_up),
        .user_clk(o_user_clk),
        .user_rst_n(o_user_rst_n)
    );

    wire unused_status;
    assign unused_status = ^c2h_status_one ^ ^h2c_status_one ^
                           ^c2h_status_two ^ ^h2c_status_two ^
                           ^c2h_status_three ^ ^h2c_status_three ^
                           ^user_irq_ack ^ msi_enable ^ ^msi_vector_width;

endmodule
