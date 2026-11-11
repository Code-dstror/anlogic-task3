`timescale 1ns / 1ps
// Isolated physical endpoint. Ownership reset is deliberately independent of
// link-up; asserting it is a coordinated recovery event, never a buffer fence.
module c2h_pcie_endpoint (
    input wire i_sys_clk, input wire i_refclk_p, input wire i_refclk_n,
    input wire i_pcie_mperst, input wire i_ownership_reset_n,
    input wire [0:0] i_pcie_rxp, input wire [0:0] i_pcie_rxn,
    output wire [0:0] o_pcie_txp, output wire [0:0] o_pcie_txn,
    output wire o_user_clk, output wire o_ownership_rst_n, output wire o_link_up,
    input wire i_record_valid, output wire o_record_ready,
    input wire [31:0] i_record_length, input wire [127:0] i_record_identity,
    input wire i_source_abort, input wire i_product_fault,
    input wire [127:0] i_axis_data, input wire [15:0] i_axis_keep,
    input wire i_axis_last, input wire i_axis_valid, output wire o_axis_ready,
    // Internal product lifecycle; not a BAR/host ABI change.
    output wire o_record_retire_valid,
    output wire [127:0] o_record_retire_identity,
    output wire [31:0] o_record_retire_status,
    output wire o_record_cancel,
    output wire o_result_pending, output wire o_quarantine, output wire o_buffer_armed,
    output wire [7:0] o_observe,
    output wire [31:0] o_axil_awaddr, output wire [2:0] o_axil_awprot,
    output wire o_axil_awvalid, input wire i_axil_awready,
    output wire [31:0] o_axil_wdata, output wire [3:0] o_axil_wstrb,
    output wire o_axil_wvalid, input wire i_axil_wready,
    input wire [1:0] i_axil_bresp, input wire i_axil_bvalid, output wire o_axil_bready,
    output wire [31:0] o_axil_araddr, output wire [2:0] o_axil_arprot,
    output wire o_axil_arvalid, input wire i_axil_arready,
    input wire [31:0] i_axil_rdata, input wire [1:0] i_axil_rresp,
    input wire i_axil_rvalid, output wire o_axil_rready, output wire o_axil_fault
);
    wire system_clock, pll_clock, aux_clock, pll_lock;
    reg [9:0] power_count=0;
    reg power_ready=0;
    reg [21:0] stable_count=0;
    reg stable=0;
    reg [1:0] ownership_reset_sync;
    wire [1:0] bme;
    wire core_reset_n, supervised_fault, supervisor_ready, physical_link_up;
    wire [127:0] rq_data, rc_data, cq_data, cc_data;
    wire [3:0] rc_keep, cq_keep, cc_keep;
    wire completion_fault,completion_incident;
    wire [2:0] native_observe_state;
    wire native_observe_submit;
    assign o_observe={native_observe_submit,native_observe_state,
        completion_fault||completion_incident,supervised_fault,supervisor_ready,bme[0]};
    wire [31:0] locked_fence_cookie;
    wire [63:0] native_address;
    wire [7:0] native_be;
    wire [12:0] native_length;
    wire [1:0] native_format;
    wire [9:0] native_tag;
    wire native_hv,native_dv,native_eot,native_halt;
    wire [74:0] rc_user;
    wire [87:0] cq_user;
    wire [32:0] cc_user;
    wire cc_ready;
    wire rc_last,rc_valid,rc_ready,cq_last,cq_valid,cq_ready,cc_last,cc_valid;
    assign system_clock=i_sys_clk;
    sys_pll_125m_25m clocks(.refclk(system_clock),.reset(!power_ready),.lock(pll_lock),.clk0_out(pll_clock),.clk1_out(aux_clock));
    always @(posedge system_clock) begin
        if(!i_pcie_mperst)begin power_count<=0;power_ready<=0;end
        else if(!power_ready)begin power_count<=power_count+1'b1;if(&power_count)power_ready<=1;end
    end
    always @(posedge pll_clock or negedge i_pcie_mperst) begin
        if(!i_pcie_mperst)begin stable_count<=0;stable<=0;end
        else if(!pll_lock)begin stable_count<=0;stable<=0;end
        else if(!stable)begin stable_count<=stable_count+1'b1;if(&stable_count)stable<=1;end
    end
    // This reset never follows bridge user_reset = !link_up.
    always @(posedge o_user_clk or negedge i_ownership_reset_n) begin
        if(!i_ownership_reset_n)ownership_reset_sync<=0;
        else ownership_reset_sync<={ownership_reset_sync[0],1'b1};
    end
    assign o_ownership_rst_n=ownership_reset_sync[1];
    c2h_link_supervisor supervisor(
        .i_watch_clk(system_clock),.i_user_clk(o_user_clk),.i_recovery_reset_n(i_ownership_reset_n),
        .i_link_up(o_link_up && physical_link_up),.i_bme(bme[0]),.i_perst_n(i_pcie_mperst),
        .i_pll_lock(pll_lock),.i_core_reset_n(core_reset_n),.o_fault(supervised_fault),.o_ready(supervisor_ready)
    );
    c2h_native_rx_transport transport(
        .i_clk(o_user_clk),.i_rst_n(o_ownership_rst_n),.i_link_up(o_link_up),.i_bme(bme[0]&&supervisor_ready),.i_external_fault(supervised_fault||completion_fault||completion_incident||i_product_fault),.o_fence_cookie(locked_fence_cookie),.i_source_abort(i_source_abort),
        .i_cq_data(cq_data),.i_cq_keep(cq_keep),.i_cq_user(cq_user),.i_cq_last(cq_last),.i_cq_valid(cq_valid),.o_cq_ready(cq_ready),
        .o_cc_data(cc_data),.o_cc_keep(cc_keep),.o_cc_user(cc_user),.o_cc_last(cc_last),.o_cc_valid(cc_valid),.i_cc_ready(cc_ready),
        .o_tlp_data(rq_data),.o_tlp_address(native_address),.o_tlp_byte_enable(native_be),
        .o_tlp_byte_length(native_length),.o_tlp_format(native_format),.o_tlp_tag(native_tag),
        .o_tlp_header_valid(native_hv),.o_tlp_data_valid(native_dv),.o_tlp_end(native_eot),.i_tlp_halt(native_halt),
        .i_rc_data(rc_data),.i_rc_keep(rc_keep),.i_rc_user(rc_user),.i_rc_last(rc_last),.i_rc_valid(rc_valid),.o_rc_ready(rc_ready),
        .i_record_valid(i_record_valid),.o_record_ready(o_record_ready),.i_record_length(i_record_length),.i_record_identity(i_record_identity),
        .i_axis_data(i_axis_data),.i_axis_keep(i_axis_keep),.i_axis_last(i_axis_last),.i_axis_valid(i_axis_valid),.o_axis_ready(o_axis_ready),
        .o_record_retire_valid(o_record_retire_valid),.o_record_retire_identity(o_record_retire_identity),
        .o_record_retire_status(o_record_retire_status),.o_record_cancel(o_record_cancel),
        .o_result_pending(o_result_pending),.o_quarantine(o_quarantine),.o_buffer_armed(o_buffer_armed),
        .o_observe_state(native_observe_state),.o_observe_submit(native_observe_submit),
        .o_axil_awaddr(o_axil_awaddr),.o_axil_awprot(o_axil_awprot),.o_axil_awvalid(o_axil_awvalid),.i_axil_awready(i_axil_awready),
        .o_axil_wdata(o_axil_wdata),.o_axil_wstrb(o_axil_wstrb),.o_axil_wvalid(o_axil_wvalid),.i_axil_wready(i_axil_wready),
        .i_axil_bresp(i_axil_bresp),.i_axil_bvalid(i_axil_bvalid),.o_axil_bready(o_axil_bready),
        .o_axil_araddr(o_axil_araddr),.o_axil_arprot(o_axil_arprot),.o_axil_arvalid(o_axil_arvalid),.i_axil_arready(i_axil_arready),
        .i_axil_rdata(i_axil_rdata),.i_axil_rresp(i_axil_rresp),.i_axil_rvalid(i_axil_rvalid),.o_axil_rready(o_axil_rready),.o_axil_fault(o_axil_fault)
    );
    camera_pcie_hard_port bridge(
        .refclk_p(i_refclk_p),.refclk_n(i_refclk_n),.rxp(i_pcie_rxp),.rxn(i_pcie_rxn),
        .txp(o_pcie_txp),.txn(o_pcie_txn),.aux_clk(aux_clock),.power_reset_n(i_pcie_mperst && stable),
        .user_clk(o_user_clk),.core_reset_n(core_reset_n),.user_link_up(o_link_up),.physical_link_up(physical_link_up),
        .bus_master_enable(bme),.ownership_reset_n(o_ownership_rst_n),.result_pending(o_result_pending),
        .fence_cookie(locked_fence_cookie),.completion_fault(completion_fault),.completion_incident(completion_incident),
        .dma_data(rq_data),.dma_addr(native_address),.dma_be(native_be),.dma_byte_length(native_length),
        .dma_fmt(native_format),.dma_tag(native_tag),.dma_hv(native_hv),.dma_dv(native_dv),.dma_eot(native_eot),.dma_halt(native_halt),
        .rc_data(rc_data),.rc_keep(rc_keep),.rc_user(rc_user),.rc_valid(rc_valid),.rc_last(rc_last),.rc_ready(rc_ready),
        .cq_data(cq_data),.cq_keep(cq_keep),.cq_user(cq_user),.cq_valid(cq_valid),.cq_last(cq_last),.cq_ready(cq_ready),
        .cc_data(cc_data),.cc_valid(cc_valid),.cc_ready(cc_ready));
endmodule
