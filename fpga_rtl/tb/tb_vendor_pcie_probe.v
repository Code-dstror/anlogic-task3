`timescale 1ns / 1ps

// Bounded smoke probe for the real Anlogic PCIe/SGDMA simulation models.
// This is intentionally not a Root Complex model and therefore cannot prove
// link training or DMA traffic.  It only proves compilation/elaboration and
// observes reset/clock/link-facing status with every DUT input defined.
module tb_vendor_pcie_probe;

    reg i_sys_clk = 1'b0;
    reg i_refclk_p = 1'b0;
    wire i_refclk_n = ~i_refclk_p;
    reg i_pcie_mperst = 1'b0;
    reg [0:0] i_pcie_rxp = 1'b0;
    reg [0:0] i_pcie_rxn = 1'b1;

    wire [0:0] o_pcie_txp;
    wire [0:0] o_pcie_txn;
    wire o_src_tready;
    wire [127:0] o_h2c_tdata;
    wire [15:0] o_h2c_tkeep;
    wire [15:0] o_h2c_tuser;
    wire o_h2c_tvalid;
    wire o_h2c_tlast;
    wire [31:0] o_axil_awaddr;
    wire [2:0] o_axil_awprot;
    wire o_axil_awvalid;
    wire [31:0] o_axil_wdata;
    wire [3:0] o_axil_wstrb;
    wire o_axil_wvalid;
    wire o_axil_bready;
    wire [31:0] o_axil_araddr;
    wire [2:0] o_axil_arprot;
    wire o_axil_arvalid;
    wire o_axil_rready;
    wire o_user_clk;
    wire o_user_rst_n;
    wire o_user_link_up;
    wire [7:0] o_c2h_status;
    wire [7:0] o_h2c_status;
    wire o_c2h_running;
    wire o_tx_busy;
    wire o_recovery_required;
    wire [31:0] o_last_error;
    wire o_frame_accept;
    wire o_frame_done;
    wire o_frame_abort;

    always #20 i_sys_clk = ~i_sys_clk;
    always #5 i_refclk_p = ~i_refclk_p;

    // PH1 primitive models use this exact top-level hierarchical instance name.
    PH1_PHY_GSR PH1_PHY_GSR ();

    pcie_video_transport dut (
        .i_sys_clk(i_sys_clk), .i_refclk_p(i_refclk_p),
        .i_refclk_n(i_refclk_n), .i_pcie_mperst(i_pcie_mperst),
        .i_pcie_rxp(i_pcie_rxp), .i_pcie_rxn(i_pcie_rxn),
        .o_pcie_txp(o_pcie_txp), .o_pcie_txn(o_pcie_txn),
        .i_app_enable(1'b0), .i_app_reset_n(1'b1),
        .i_src_tdata(128'd0), .i_src_tkeep(16'd0),
        .i_src_tvalid(1'b0), .o_src_tready(o_src_tready),
        .i_src_tlast(1'b0), .o_h2c_tdata(o_h2c_tdata),
        .o_h2c_tkeep(o_h2c_tkeep), .o_h2c_tuser(o_h2c_tuser),
        .o_h2c_tvalid(o_h2c_tvalid), .i_h2c_tready(1'b1),
        .o_h2c_tlast(o_h2c_tlast), .o_axil_awaddr(o_axil_awaddr),
        .o_axil_awprot(o_axil_awprot), .o_axil_awvalid(o_axil_awvalid),
        .i_axil_awready(1'b1), .o_axil_wdata(o_axil_wdata),
        .o_axil_wstrb(o_axil_wstrb), .o_axil_wvalid(o_axil_wvalid),
        .i_axil_wready(1'b1), .i_axil_bresp(2'b00),
        .i_axil_bvalid(1'b0), .o_axil_bready(o_axil_bready),
        .o_axil_araddr(o_axil_araddr), .o_axil_arprot(o_axil_arprot),
        .o_axil_arvalid(o_axil_arvalid), .i_axil_arready(1'b1),
        .i_axil_rdata(32'd0), .i_axil_rresp(2'b00),
        .i_axil_rvalid(1'b0), .o_axil_rready(o_axil_rready),
        .o_user_clk(o_user_clk), .o_user_rst_n(o_user_rst_n),
        .o_user_link_up(o_user_link_up), .o_c2h_status(o_c2h_status),
        .o_h2c_status(o_h2c_status), .o_c2h_running(o_c2h_running),
        .o_tx_busy(o_tx_busy), .o_recovery_required(o_recovery_required),
        .o_last_error(o_last_error), .o_frame_accept(o_frame_accept),
        .o_frame_done(o_frame_done), .o_frame_abort(o_frame_abort)
    );

    initial begin
        $display("[TB] vendor PCIe/SGDMA model elaborated");
        #1000 i_pcie_mperst = 1'b1;
        #99000;
        $display("[TB] t=%0t user_clk=%b user_rst_n=%b link_up=%b c2h=%02h h2c=%02h tx=%b/%b",
                 $time, o_user_clk, o_user_rst_n, o_user_link_up,
                 o_c2h_status, o_h2c_status, o_pcie_txp, o_pcie_txn);
        $display("[TB] RESULT: DIAGNOSTIC_NONPASS - no Root Complex/BFM; link and DMA were not demonstrated");
        $finish;
    end

endmodule
