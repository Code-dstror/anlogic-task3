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
    // Test-only physical boundary. Core/PLL are omitted; the complete owned
    // transport and its configured official packet store remain real RTL.
    reg [1:0] reset_release=0;
    reg link_up=1,bme=1,hold_axis=0,external_fault=0;
    wire cq_ready,rc_ready,cc_last,cc_valid,cq_last,cq_valid,cc_ready;
    wire [127:0] cq_data,rc_data,cc_data,native_data,bypass_data;
    wire [3:0] cq_keep,rc_keep,cc_keep,bypass_dwen;
    wire [87:0] cq_user;
    wire [74:0] rc_user;
    wire [32:0] cc_user;
    wire rc_last,rc_valid;
    wire [63:0] native_address,bypass_address;
    wire [7:0] native_be;
    wire [12:0] native_length;
    wire [1:0] native_format,bypass_format;
    wire [9:0] native_tag,bypass_tag,bypass_length;
    wire native_hv,native_dv,native_eot,native_halt;
    wire bypass_hv,bypass_dv,bypass_eot,bypass_dllp,bypass_tlp,bypass_ecrc;
    wire [15:0] bypass_requester;
    reg [15:0] configured_requester_id=16'h0218;
    wire bypass_function,bypass_poison,bypass_last,requester_timeout,completion_fault;
    wire [2:0] bypass_status;
    wire [11:0] bypass_bytes;
    wire [31:0] locked_fence_cookie;
    wire completion_incident;
    wire [2:0] native_observe_state;
    wire native_observe_submit;
    // Boundary-only approximation: this model omits the actual supervisor/PLL.
    // F09 startup qualification uses the separate real-native matrix, not this bit.
    assign o_observe={native_observe_submit,native_observe_state,
        completion_fault||completion_incident,1'b0,(bme&&o_link_up),bme};
`ifdef PRODUCT_FROZEN_LISTENER_CONTROL
    assign completion_incident=0;
`endif
    wire axis_ready;
    wire reset_async_n=i_ownership_reset_n;
    always @(posedge i_sys_clk or negedge reset_async_n)
        if(!reset_async_n)reset_release<=0;
        else reset_release<={reset_release[0],1'b1};
    assign o_user_clk=i_sys_clk;
    assign o_ownership_rst_n=reset_release[1];
    assign o_link_up=link_up&&i_pcie_mperst;
    assign o_pcie_txp=0;assign o_pcie_txn=0;
    assign o_axis_ready=axis_ready&&!hold_axis;
    c2h_native_rx_transport transport(
        .i_clk(o_user_clk),.i_rst_n(o_ownership_rst_n),.i_link_up(o_link_up),.i_bme(bme),
        .i_external_fault(completion_fault||completion_incident||external_fault||i_product_fault),.o_fence_cookie(locked_fence_cookie),.i_source_abort(i_source_abort),
        .i_cq_data(cq_data),.i_cq_keep(cq_keep),.i_cq_user(cq_user),.i_cq_last(cq_last),.i_cq_valid(cq_valid),.o_cq_ready(cq_ready),
        .o_cc_data(cc_data),.o_cc_keep(cc_keep),.o_cc_user(cc_user),.o_cc_last(cc_last),.o_cc_valid(cc_valid),.i_cc_ready(cc_ready),
        .o_tlp_data(native_data),.o_tlp_address(native_address),.o_tlp_byte_enable(native_be),
        .o_tlp_byte_length(native_length),.o_tlp_format(native_format),.o_tlp_tag(native_tag),
        .o_tlp_header_valid(native_hv),.o_tlp_data_valid(native_dv),.o_tlp_end(native_eot),.i_tlp_halt(native_halt),
        .i_rc_data(rc_data),.i_rc_keep(rc_keep),.i_rc_user(rc_user),.i_rc_last(rc_last),.i_rc_valid(rc_valid),.o_rc_ready(rc_ready),
        .i_record_valid(i_record_valid),.o_record_ready(o_record_ready),.i_record_length(i_record_length),.i_record_identity(i_record_identity),
        .i_axis_data(i_axis_data),.i_axis_keep(i_axis_keep),.i_axis_last(i_axis_last),
        .i_axis_valid(i_axis_valid&&!hold_axis),.o_axis_ready(axis_ready),
        .o_record_retire_valid(o_record_retire_valid),.o_record_retire_identity(o_record_retire_identity),
        .o_record_retire_status(o_record_retire_status),.o_record_cancel(o_record_cancel),
        .o_result_pending(o_result_pending),.o_quarantine(o_quarantine),.o_buffer_armed(o_buffer_armed),
        .o_observe_state(native_observe_state),.o_observe_submit(native_observe_submit),
        .o_axil_awaddr(o_axil_awaddr),.o_axil_awprot(o_axil_awprot),.o_axil_awvalid(o_axil_awvalid),.i_axil_awready(i_axil_awready),
        .o_axil_wdata(o_axil_wdata),.o_axil_wstrb(o_axil_wstrb),.o_axil_wvalid(o_axil_wvalid),.i_axil_wready(i_axil_wready),
        .i_axil_bresp(i_axil_bresp),.i_axil_bvalid(i_axil_bvalid),.o_axil_bready(o_axil_bready),
        .o_axil_araddr(o_axil_araddr),.o_axil_arprot(o_axil_arprot),.o_axil_arvalid(o_axil_arvalid),.i_axil_arready(i_axil_arready),
        .i_axil_rdata(i_axil_rdata),.i_axil_rresp(i_axil_rresp),.i_axil_rvalid(i_axil_rvalid),.o_axil_rready(o_axil_rready),.o_axil_fault(o_axil_fault));
    c2h_native_fence_listener listener(
        .clk(o_user_clk),.rst_n(o_ownership_rst_n),.fence_start(native_hv&&!native_dv&&!native_halt),
        .fence_lower_address(native_address[6:0]),.fence_cookie(locked_fence_cookie),.fence_requester_id(configured_requester_id),
        .rx_data(bypass_data),.rx_dwen(bypass_dwen),.rx_hv(bypass_hv),.rx_dv(bypass_dv),.rx_eot(bypass_eot),
        .rx_dllp_abort(bypass_dllp),.rx_tlp_abort(bypass_tlp),.rx_ecrc_error(bypass_ecrc),
        .rx_address(bypass_address),.rx_format(bypass_format),.rx_type(5'h0a),.rx_tc(3'd0),.rx_attributes(3'd0),
        .rx_requester_id(bypass_requester),.rx_completer_id(16'h0000),.rx_tag(bypass_tag),.rx_dword_length(bypass_length),
        .rx_function(bypass_function),.rx_vf_active(1'b0),.rx_poisoned(bypass_poison),.rx_cpl_last(bypass_last),
        .rx_status(bypass_status),.rx_byte_count(bypass_bytes),.rx_at(2'd0),.rx_th(1'b0),.rx_bcm(1'b0),
        .requester_timeout(requester_timeout),.rc_data(rc_data),.rc_keep(rc_keep),.rc_user(rc_user),
        .rc_last(rc_last),.rc_valid(rc_valid),.rc_ready(rc_ready),
`ifndef PRODUCT_FROZEN_LISTENER_CONTROL
        .o_incident_now(completion_incident),
`endif
        .fault(completion_fault),.outstanding());
    tb_c2h_host_memory host(.clk(o_user_clk),.rst_n(o_ownership_rst_n),
        .cq_data(cq_data),.cq_keep(cq_keep),.cq_user(cq_user),.cq_last(cq_last),.cq_valid(cq_valid),.cq_ready(cq_ready),
        .bypass_data(bypass_data),.bypass_dwen(bypass_dwen),.bypass_hv(bypass_hv),.bypass_dv(bypass_dv),.bypass_eot(bypass_eot),
        .bypass_dllp(bypass_dllp),.bypass_tlp(bypass_tlp),.bypass_ecrc(bypass_ecrc),.bypass_address(bypass_address),
        .bypass_format(bypass_format),.bypass_tag(bypass_tag),.bypass_length(bypass_length),.bypass_requester(bypass_requester),
        .bypass_function(bypass_function),.bypass_poison(bypass_poison),.bypass_last(bypass_last),
        .bypass_status(bypass_status),.bypass_bytes(bypass_bytes),.requester_timeout(requester_timeout),
        .cc_data(cc_data),.cc_keep(cc_keep),.cc_user(cc_user),.cc_last(cc_last),.cc_valid(cc_valid),.cc_ready(cc_ready),
        .native_data(native_data),.native_address(native_address),.native_be(native_be),.native_length(native_length),
        .native_format(native_format),.native_tag(native_tag),.native_hv(native_hv),.native_dv(native_dv),.native_eot(native_eot),
        .native_halt(native_halt),.configured_requester_id(configured_requester_id),
        .record_valid(i_record_valid),.record_ready(o_record_ready),.record_length(i_record_length),.record_identity(i_record_identity),
        .result_pending(o_result_pending),.quarantine(o_quarantine),
        .axis_data(i_axis_data),.axis_keep(i_axis_keep),.axis_last(i_axis_last),
        .axis_valid(i_axis_valid&&!hold_axis),.axis_ready(axis_ready));
endmodule
