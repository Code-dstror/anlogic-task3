`timescale 1ns/1ps
// Complete records are validated/formatted once by their producer. This USER
// wrapper adds no header parser, extension buffer or second record formatter.
// i_ownership_reset_n is coordinated cold recovery only. APP reset/STOP must
// drain or retain all producers through their explicit safe-retire handshake.
module product_pcie_transport (
    input wire i_product_fault,
    input wire i_app_enable,
    input wire i_app_reset_n,
    input wire i_p0_record_valid,
    output wire o_p0_record_ready,
    input wire [31:0] i_p0_record_length,
    input wire [127:0] i_p0_record_identity,
    input wire [127:0] i_p0_axis_data,
    input wire [15:0] i_p0_axis_keep,
    input wire i_p0_axis_valid,
    input wire i_p0_axis_last,
    output wire o_p0_axis_ready,
    input wire i_p0_done_valid,
    input wire i_p0_done_ok,
    input wire i_p0_drained,
    output wire o_p0_cancel,
    output wire o_p0_retire_valid,
    input wire i_p0_retire_ready,
    output wire [127:0] o_p0_retire_identity,
    output wire [31:0] o_p0_retire_status,
    input wire i_p1_record_valid,
    output wire o_p1_record_ready,
    input wire [31:0] i_p1_record_length,
    input wire [127:0] i_p1_record_identity,
    input wire [127:0] i_p1_axis_data,
    input wire [15:0] i_p1_axis_keep,
    input wire i_p1_axis_valid,
    input wire i_p1_axis_last,
    output wire o_p1_axis_ready,
    input wire i_p1_done_valid,
    input wire i_p1_done_ok,
    input wire i_p1_drained,
    output wire o_p1_cancel,
    output wire o_p1_retire_valid,
    input wire i_p1_retire_ready,
    output wire [127:0] o_p1_retire_identity,
    output wire [31:0] o_p1_retire_status,
    output wire o_busy,
    output wire o_quarantine,
    input wire i_sys_clk,
    input wire i_refclk_p,
    input wire i_refclk_n,
    input wire i_pcie_mperst,
    input wire i_ownership_reset_n,
    input wire [0:0] i_pcie_rxp,
    input wire [0:0] i_pcie_rxn,
    output wire [0:0] o_pcie_txp,
    output wire [0:0] o_pcie_txn,
    output wire o_user_clk,
    output wire o_ownership_rst_n,
    output wire o_link_up,
    output wire [7:0] o_observe,
    output wire o_result_pending,
    output wire o_buffer_armed,
    output wire [31:0] o_axil_awaddr,
    output wire [2:0] o_axil_awprot,
    output wire o_axil_awvalid,
    input wire i_axil_awready,
    output wire [31:0] o_axil_wdata,
    output wire [3:0] o_axil_wstrb,
    output wire o_axil_wvalid,
    input wire i_axil_wready,
    input wire [1:0] i_axil_bresp,
    input wire i_axil_bvalid,
    output wire o_axil_bready,
    output wire [31:0] o_axil_araddr,
    output wire [2:0] o_axil_arprot,
    output wire o_axil_arvalid,
    input wire i_axil_arready,
    input wire [31:0] i_axil_rdata,
    input wire [1:0] i_axil_rresp,
    input wire i_axil_rvalid,
    output wire o_axil_rready,
    output wire o_axil_fault
);
    wire record_valid;
    wire record_ready;
    wire [31:0] record_length;
    wire [127:0] record_identity;
    wire [127:0] axis_data;
    wire [15:0] axis_keep;
    wire axis_valid;
    wire axis_last;
    wire axis_ready;
    wire source_abort;
    wire transport_cancel;
    wire native_quarantine;
    wire record_retire_valid;
    wire [127:0] record_retire_identity;
    wire [31:0] record_retire_status;
    jpeg_product_owner arb(
        .i_clk(o_user_clk),.i_ownership_rst_n(o_ownership_rst_n),
        .i_app_enable(i_app_enable),.i_app_reset_n(i_app_reset_n),
        .i_record_valid(i_p0_record_valid),.o_record_ready(o_p0_record_ready),
        .i_record_length(i_p0_record_length),.i_record_identity(i_p0_record_identity),
        .i_axis_data(i_p0_axis_data),.i_axis_keep(i_p0_axis_keep),
        .i_axis_valid(i_p0_axis_valid),.i_axis_last(i_p0_axis_last),.o_axis_ready(o_p0_axis_ready),
        .i_done_valid(i_p0_done_valid),.i_done_ok(i_p0_done_ok),.i_drained(i_p0_drained),
        .o_cancel(o_p0_cancel),.o_retire_valid(o_p0_retire_valid),.i_retire_ready(i_p0_retire_ready),
        .o_retire_identity(o_p0_retire_identity),.o_retire_status(o_p0_retire_status),
        .m_record_valid(record_valid),.m_record_ready(record_ready),
        .m_record_length(record_length),.m_record_identity(record_identity),
        .m_axis_data(axis_data),.m_axis_keep(axis_keep),.m_axis_valid(axis_valid),
        .m_axis_last(axis_last),.m_axis_ready(axis_ready),.o_source_abort(source_abort),
        .i_transport_cancel(transport_cancel),.i_transport_quarantine(native_quarantine),
        .i_safe_valid(record_retire_valid),.i_safe_identity(record_retire_identity),
        .i_safe_status(record_retire_status),.o_busy(o_busy),.o_quarantine(o_quarantine));
    // The legacy second port is kept only as a source-level wiring boundary.
    // This profile has one JPEG producer; no P1 storage, owner or arbitration.
    assign o_p1_record_ready=1'b0;
    assign o_p1_axis_ready=1'b0;
    assign o_p1_cancel=1'b0;
    assign o_p1_retire_valid=1'b0;
    assign o_p1_retire_identity=128'd0;
    assign o_p1_retire_status=32'd0;
    c2h_pcie_endpoint endpoint(
        .i_sys_clk(i_sys_clk),
        .i_refclk_p(i_refclk_p),
        .i_refclk_n(i_refclk_n),
        .i_pcie_mperst(i_pcie_mperst),
        .i_ownership_reset_n(i_ownership_reset_n),
        .i_pcie_rxp(i_pcie_rxp),
        .i_pcie_rxn(i_pcie_rxn),
        .o_pcie_txp(o_pcie_txp),
        .o_pcie_txn(o_pcie_txn),
        .o_user_clk(o_user_clk),
        .o_ownership_rst_n(o_ownership_rst_n),
        .o_link_up(o_link_up),
        .o_observe(o_observe),
        .i_record_valid(record_valid),
        .o_record_ready(record_ready),
        .i_record_length(record_length),
        .i_record_identity(record_identity),
        .i_source_abort(source_abort),.i_product_fault(i_product_fault),
        .i_axis_data(axis_data),
        .i_axis_keep(axis_keep),
        .i_axis_last(axis_last),
        .i_axis_valid(axis_valid),
        .o_axis_ready(axis_ready),
        .o_record_retire_valid(record_retire_valid),
        .o_record_retire_identity(record_retire_identity),
        .o_record_retire_status(record_retire_status),
        .o_record_cancel(transport_cancel),
        .o_result_pending(o_result_pending),
        .o_quarantine(native_quarantine),
        .o_buffer_armed(o_buffer_armed),
        .o_axil_awaddr(o_axil_awaddr),
        .o_axil_awprot(o_axil_awprot),
        .o_axil_awvalid(o_axil_awvalid),
        .i_axil_awready(i_axil_awready),
        .o_axil_wdata(o_axil_wdata),
        .o_axil_wstrb(o_axil_wstrb),
        .o_axil_wvalid(o_axil_wvalid),
        .i_axil_wready(i_axil_wready),
        .i_axil_bresp(i_axil_bresp),
        .i_axil_bvalid(i_axil_bvalid),
        .o_axil_bready(o_axil_bready),
        .o_axil_araddr(o_axil_araddr),
        .o_axil_arprot(o_axil_arprot),
        .o_axil_arvalid(o_axil_arvalid),
        .i_axil_arready(i_axil_arready),
        .i_axil_rdata(i_axil_rdata),
        .i_axil_rresp(i_axil_rresp),
        .i_axil_rvalid(i_axil_rvalid),
        .o_axil_rready(o_axil_rready),
        .o_axil_fault(o_axil_fault));
endmodule
