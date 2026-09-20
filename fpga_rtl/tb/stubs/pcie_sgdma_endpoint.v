`timescale 1ns / 1ps

// Simulation-only boundary double for pcie_video_transport.
// This model does not represent vendor PCIe or SGDMA behavior.
module pcie_sgdma_endpoint (
    input wire i_sys_clk, input wire i_refclk_p, input wire i_refclk_n,
    input wire i_pcie_mperst, input wire [0:0] i_pcie_rxp,
    input wire [0:0] i_pcie_rxn, output wire [0:0] o_pcie_txp,
    output wire [0:0] o_pcie_txn,
    input wire [127:0] i_c2h_tdata, input wire [15:0] i_c2h_tkeep,
    input wire [15:0] i_c2h_tuser, input wire i_c2h_tvalid,
    output wire o_c2h_tready, input wire i_c2h_tlast,
    output wire [127:0] o_h2c_tdata, output wire [15:0] o_h2c_tkeep,
    output wire [15:0] o_h2c_tuser, output wire o_h2c_tvalid,
    input wire i_h2c_tready, output wire o_h2c_tlast,
    output wire [31:0] o_axil_awaddr, output wire [2:0] o_axil_awprot,
    output wire o_axil_awvalid, input wire i_axil_awready,
    output wire [31:0] o_axil_wdata, output wire [3:0] o_axil_wstrb,
    output wire o_axil_wvalid, input wire i_axil_wready,
    input wire [1:0] i_axil_bresp, input wire i_axil_bvalid,
    output wire o_axil_bready, output wire [31:0] o_axil_araddr,
    output wire [2:0] o_axil_arprot, output wire o_axil_arvalid,
    input wire i_axil_arready, input wire [31:0] i_axil_rdata,
    input wire [1:0] i_axil_rresp, input wire i_axil_rvalid,
    output wire o_axil_rready, output wire o_user_clk,
    output wire o_user_rst_n, output wire o_user_link_up,
    output wire [7:0] o_c2h_status, output wire [7:0] o_h2c_status,
    output wire o_c2h_running
);
    reg c2h_ready = 1'b0;
    reg link_up = 1'b0;
    reg c2h_running = 1'b0;
    reg [127:0] h2c_data = 128'd0;
    reg [15:0] h2c_keep = 16'd0;
    reg [15:0] h2c_user = 16'd0;
    reg h2c_valid = 1'b0;
    reg h2c_last = 1'b0;
    reg [31:0] axil_awaddr = 32'd0;
    reg [2:0] axil_awprot = 3'd0;
    reg axil_awvalid = 1'b0;
    reg [31:0] axil_wdata = 32'd0;
    reg [3:0] axil_wstrb = 4'd0;
    reg axil_wvalid = 1'b0;
    reg axil_bready = 1'b0;
    reg [31:0] axil_araddr = 32'd0;
    reg [2:0] axil_arprot = 3'd0;
    reg axil_arvalid = 1'b0;
    reg axil_rready = 1'b0;

    assign o_pcie_txp = 1'b0;
    assign o_pcie_txn = 1'b0;
    assign o_user_clk = i_sys_clk;
    assign o_user_rst_n = i_pcie_mperst;
    assign o_user_link_up = link_up;
    assign o_c2h_running = c2h_running;
    assign o_c2h_status = {1'b0, c2h_running, 6'd0};
    assign o_h2c_status = 8'd0;
    assign o_c2h_tready = c2h_ready;
    assign o_h2c_tdata = h2c_data;
    assign o_h2c_tkeep = h2c_keep;
    assign o_h2c_tuser = h2c_user;
    assign o_h2c_tvalid = h2c_valid;
    assign o_h2c_tlast = h2c_last;
    assign o_axil_awaddr = axil_awaddr;
    assign o_axil_awprot = axil_awprot;
    assign o_axil_awvalid = axil_awvalid;
    assign o_axil_wdata = axil_wdata;
    assign o_axil_wstrb = axil_wstrb;
    assign o_axil_wvalid = axil_wvalid;
    assign o_axil_bready = axil_bready;
    assign o_axil_araddr = axil_araddr;
    assign o_axil_arprot = axil_arprot;
    assign o_axil_arvalid = axil_arvalid;
    assign o_axil_rready = axil_rready;

    wire unused_inputs = i_refclk_p ^ i_refclk_n ^ i_pcie_rxp[0] ^
                         i_pcie_rxn[0] ^ i_h2c_tready ^ i_axil_awready ^
                         i_axil_wready ^ ^i_axil_bresp ^ i_axil_bvalid ^
                         i_axil_arready ^ ^i_axil_rdata ^ ^i_axil_rresp ^
                         i_axil_rvalid ^ ^i_c2h_tdata ^ ^i_c2h_tkeep ^
                         ^i_c2h_tuser ^ i_c2h_tvalid ^ i_c2h_tlast;
endmodule
