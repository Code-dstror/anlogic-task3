`timescale 1ns/1ps
`default_nettype none

// Native PH1A90 Gen2 x1 endpoint. Client 0 issues pixel writes and the final
// host read fence. The target/client 1 path below only services the RK BAR.
module camera_pcie_hard_port (
    input wire refclk_p, refclk_n, rxp, rxn, aux_clk, power_reset_n,
    output wire txp, txn, user_clk, core_reset_n, user_link_up, physical_link_up,
    output wire [1:0] bus_master_enable,
    input wire ownership_reset_n, result_pending,
    input wire [31:0] fence_cookie,
    output wire completion_fault, completion_incident,
    input wire [127:0] dma_data,
    input wire [63:0] dma_addr,
    input wire [7:0] dma_be,
    input wire [12:0] dma_byte_length,
    input wire [1:0] dma_fmt,
    input wire [9:0] dma_tag,
    input wire dma_hv, dma_dv, dma_eot,
    output wire dma_halt,
    output wire [127:0] rc_data, cq_data,
    output wire [3:0] rc_keep, cq_keep,
    output wire [74:0] rc_user,
    output wire [87:0] cq_user,
    output wire rc_valid, rc_last, cq_valid, cq_last,
    input wire rc_ready, cq_ready,
    input wire [127:0] cc_data,
    input wire cc_valid,
    output wire cc_ready
);
    wire [7:0] bus_number;
    wire [4:0] device_number;
    wire [15:0] requester_id={bus_number,device_number,3'b000};
    wire [1:0] msi_enable;
    wire [63:0] msi_mask;
    wire msi_request, msi_grant, msi_masked_pending;
    wire bar_reset_n, reply_done, read_pending, requester_timeout;
    wire [9:0] read_lookup, read_tag;

    wire radm_trgt1_hv;
    wire radm_trgt1_dv;
    wire radm_trgt1_eot;
    wire radm_trgt1_tlp_abort;
    wire radm_trgt1_dllp_abort;
    wire radm_trgt1_ecrc_err;
    wire radm_trgt1_poisoned;
    wire [3:0] radm_trgt1_dwen;
    wire [1:0] radm_trgt1_fmt;
    wire [4:0] radm_trgt1_type;
    wire [2:0] radm_trgt1_attr;
    wire [2:0] radm_trgt1_tc;
    wire [15:0] radm_trgt1_reqid;
    wire [63:0] radm_trgt1_addr;
    wire [127:0] radm_trgt1_data;
    wire [9:0] radm_trgt1_tag;
    wire [9:0] radm_trgt1_dw_len;
    wire [3:0] radm_trgt1_first_be;
    wire [3:0] radm_trgt1_last_be;
    wire [2:0] radm_trgt1_in_membar_range;
    wire radm_trgt1_rom_in_range;
    wire radm_trgt1_func_num;
    wire radm_trgt1_vfunc_active;
    wire [1:0] radm_trgt1_ats;
    wire [9:0] trgt_lookup_id;
    wire trgt_lookup_empty;
    wire trgt1_radm_halt;
    wire xadm_client1_halt;
    wire [127:0] client1_tlp_data;
    wire [63:0] client1_tlp_addr;
    wire [15:0] client1_remote_req_id;
    wire [11:0] client1_cpl_byte_cnt;
    wire [2:0] client1_tlp_tc;
    wire [2:0] client1_tlp_attr;
    wire [2:0] client1_cpl_status;
    wire client1_tlp_dv;
    wire client1_tlp_eot;
    wire client1_tlp_hv;
    wire [1:0] client1_tlp_fmt;
    wire [12:0] client1_tlp_byte_len;
    wire [9:0] client1_tlp_tid;
    wire [9:0] client1_cpl_lookup_id;
    wire [127:0] radm_bypass_data;
    wire [3:0] radm_bypass_dwen;
    wire radm_bypass_hv;
    wire radm_bypass_dv;
    wire radm_bypass_eot;
    wire radm_bypass_dllp_abort;
    wire radm_bypass_tlp_abort;
    wire radm_bypass_ecrc_err;
    wire [63:0] radm_bypass_addr;
    wire [1:0] radm_bypass_fmt;
    wire [4:0] radm_bypass_type;
    wire [2:0] radm_bypass_tc;
    wire [2:0] radm_bypass_attr;
    wire [15:0] radm_bypass_reqid;
    wire [15:0] radm_bypass_cmpltr_id;
    wire [9:0] radm_bypass_tag;
    wire [9:0] radm_bypass_dw_len;
    wire radm_bypass_func_num;
    wire radm_bypass_vfunc_active;
    wire radm_bypass_poisoned;
    wire radm_bypass_cpl_last;
    wire [2:0] radm_bypass_cpl_status;
    wire [11:0] radm_bypass_byte_cnt;
    wire [1:0] radm_bypass_ats;
    wire radm_bypass_th;
    wire radm_bypass_bcm;

    // Core reset invalidates target lookup IDs. The C2H lease still belongs to
    // the ownership domain, independent of an intervening physical link reset.
    reset_release_sync u_bar_release(.i_clk(user_clk),
        .i_async_rst_n(core_reset_n && ownership_reset_n),.o_rst_n(bar_reset_n));
    camera_pcie_result_msi u_result_msi(
        .clk(user_clk),.rst_n(bar_reset_n),.link_up(user_link_up),
        .result_pending(result_pending),.enabled(msi_enable[0]),.masked(msi_mask[0]),
        .grant(msi_grant),.request(msi_request),.masked_pending(msi_masked_pending));

    camera_pcie_bar_rx u_bar_rx (
        .core_clk(user_clk),
        .core_rst_n(bar_reset_n),
        .radm_trgt1_hv(radm_trgt1_hv),
        .radm_trgt1_dv(radm_trgt1_dv),
        .radm_trgt1_eot(radm_trgt1_eot),
        .radm_trgt1_tlp_abort(radm_trgt1_tlp_abort),
        .radm_trgt1_dllp_abort(radm_trgt1_dllp_abort),
        .radm_trgt1_ecrc_err(radm_trgt1_ecrc_err),
        .radm_trgt1_poisoned(radm_trgt1_poisoned),
        .radm_trgt1_dwen(radm_trgt1_dwen),
        .radm_trgt1_fmt(radm_trgt1_fmt),
        .radm_trgt1_type(radm_trgt1_type),
        .radm_trgt1_attr(radm_trgt1_attr),
        .radm_trgt1_tc(radm_trgt1_tc),
        .radm_trgt1_reqid(radm_trgt1_reqid),
        .radm_trgt1_addr(radm_trgt1_addr),
        .radm_trgt1_data(radm_trgt1_data),
        .radm_trgt1_tag(radm_trgt1_tag),
        .radm_trgt1_dw_len(radm_trgt1_dw_len),
        .radm_trgt1_first_be(radm_trgt1_first_be),
        .radm_trgt1_last_be(radm_trgt1_last_be),
        .radm_trgt1_in_membar_range(radm_trgt1_in_membar_range),
        .radm_trgt1_rom_in_range(radm_trgt1_rom_in_range),
        .radm_trgt1_func_num(radm_trgt1_func_num),
        .radm_trgt1_vfunc_active(radm_trgt1_vfunc_active),
        .radm_trgt1_ats(radm_trgt1_ats),
        .trgt_lookup_id(trgt_lookup_id),
        .trgt_lookup_empty(trgt_lookup_empty),
        .trgt1_radm_halt(trgt1_radm_halt),
        .m_axis_cq_tdata(cq_data),
        .m_axis_cq_tkeep(cq_keep),
        .m_axis_cq_tuser(cq_user),
        .m_axis_cq_tvalid(cq_valid),
        .m_axis_cq_tready(cq_ready),
        .m_axis_cq_tlast(cq_last),
        .o_read_lookup(read_lookup),
        .o_read_tag(read_tag),
        .i_reply_done(reply_done),
        .o_read_pending(read_pending)
    );

    camera_pcie_bar_tx u_bar_tx (
        .core_clk(user_clk),
        .core_rst_n(bar_reset_n),
        .i_read_pending(read_pending),
        .i_read_lookup(read_lookup),
        .i_read_tag(read_tag),
        .o_reply_done(reply_done),
        .s_axis_cc_tdata(cc_data),
        .s_axis_cc_tvalid(cc_valid),
        .s_axis_cc_tready(cc_ready),
        .xadm_client1_halt(xadm_client1_halt),
        .client1_tlp_data(client1_tlp_data),
        .client1_tlp_addr(client1_tlp_addr),
        .client1_remote_req_id(client1_remote_req_id),
        .client1_cpl_byte_cnt(client1_cpl_byte_cnt),
        .client1_tlp_tc(client1_tlp_tc),
        .client1_tlp_attr(client1_tlp_attr),
        .client1_cpl_status(client1_cpl_status),
        .client1_tlp_dv(client1_tlp_dv),
        .client1_tlp_eot(client1_tlp_eot),
        .client1_tlp_hv(client1_tlp_hv),
        .client1_tlp_fmt(client1_tlp_fmt),
        .client1_tlp_byte_len(client1_tlp_byte_len),
        .client1_tlp_tid(client1_tlp_tid),
        .client1_cpl_lookup_id(client1_cpl_lookup_id)
    );

    c2h_native_fence_listener u_fence_listener (
        .clk(user_clk),
        .rst_n(ownership_reset_n),
        .fence_start(dma_hv && !dma_dv && !dma_halt),
        .fence_lower_address(dma_addr[6:0]),
        .fence_cookie(fence_cookie),
        .fence_requester_id(requester_id),
        .rx_data(radm_bypass_data),
        .rx_dwen(radm_bypass_dwen),
        .rx_hv(radm_bypass_hv),
        .rx_dv(radm_bypass_dv),
        .rx_eot(radm_bypass_eot),
        .rx_dllp_abort(radm_bypass_dllp_abort),
        .rx_tlp_abort(radm_bypass_tlp_abort),
        .rx_ecrc_error(radm_bypass_ecrc_err),
        .rx_address(radm_bypass_addr),
        .rx_format(radm_bypass_fmt),
        .rx_type(radm_bypass_type),
        .rx_tc(radm_bypass_tc),
        .rx_attributes(radm_bypass_attr),
        .rx_requester_id(radm_bypass_reqid),
        .rx_completer_id(radm_bypass_cmpltr_id),
        .rx_tag(radm_bypass_tag),
        .rx_dword_length(radm_bypass_dw_len),
        .rx_function(radm_bypass_func_num),
        .rx_vf_active(radm_bypass_vfunc_active),
        .rx_poisoned(radm_bypass_poisoned),
        .rx_cpl_last(radm_bypass_cpl_last),
        .rx_status(radm_bypass_cpl_status),
        .rx_byte_count(radm_bypass_byte_cnt),
        .rx_at(radm_bypass_ats),
        .rx_th(radm_bypass_th),
        .rx_bcm(radm_bypass_bcm),
        .requester_timeout(requester_timeout),
        .rc_data(rc_data),
        .rc_keep(rc_keep),
        .rc_user(rc_user),
        .rc_last(rc_last),
        .rc_valid(rc_valid),
        .rc_ready(rc_ready),
        .fault(completion_fault),
        .o_incident_now(completion_incident),
        .outstanding()
    );

    // The native IP performs its own DBI initialization from its generated ROM.
    // There is no application DBI master. All unused hard inputs have explicit levels.
    camera_pcie_ep u_controller (
        .refclk_p(refclk_p),
        .refclk_n(refclk_n),
        .txp(txp),
        .txn(txn),
        .rxp(rxp),
        .rxn(rxn),
        .client0_tlp_data(dma_data),
        .client0_tlp_addr(dma_addr),
        .client0_remote_req_id(requester_id),
        .client0_tlp_byte_en(dma_be),
        .client0_cpl_byte_cnt(12'd0),
        .client0_addr_align_en(1'd0),
        .client0_tlp_tc(3'd0),
        .client0_tlp_attr(3'd0),
        .client0_cpl_status(3'd0),
        .client0_cpl_bcm(1'd0),
        .client0_tlp_dv(dma_dv),
        .client0_tlp_eot(dma_eot),
        .client0_tlp_bad_eot(1'd0),
        .client0_tlp_hv(dma_hv),
        .client0_tlp_type(5'd0),
        .client0_tlp_fmt(dma_fmt),
        .client0_tlp_td(1'd0),
        .client0_tlp_byte_len(dma_byte_length),
        .client0_tlp_tid(dma_tag),
        .client0_tlp_ep(1'd0),
        .client0_tlp_func_num(1'd0),
        .client0_tlp_vfunc_num(2'd0),
        .client0_tlp_ats(2'd0),
        .client0_tlp_st(8'd0),
        .client0_tlp_vfunc_active(1'd0),
        .client0_tlp_nw(1'd0),
        .client0_tlp_th(1'd0),
        .client0_tlp_ph(2'd0),
        .client0_tlp_atu_bypass(1'b1),
        .client1_tlp_data(client1_tlp_data),
        .client1_tlp_addr(client1_tlp_addr),
        .client1_remote_req_id(client1_remote_req_id),
        .client1_tlp_byte_en(8'hff),
        .client1_cpl_byte_cnt(client1_cpl_byte_cnt),
        .client1_addr_align_en(1'd0),
        .client1_tlp_tc(client1_tlp_tc),
        .client1_tlp_attr(client1_tlp_attr),
        .client1_cpl_status(client1_cpl_status),
        .client1_cpl_bcm(1'd0),
        .client1_tlp_dv(client1_tlp_dv),
        .client1_tlp_eot(client1_tlp_eot),
        .client1_tlp_bad_eot(1'd0),
        .client1_tlp_hv(client1_tlp_hv),
        .client1_tlp_type(5'h0a),
        .client1_tlp_fmt(client1_tlp_fmt),
        .client1_tlp_td(1'd0),
        .client1_tlp_byte_len(client1_tlp_byte_len),
        .client1_tlp_tid(client1_tlp_tid),
        .client1_tlp_ep(1'd0),
        .client1_tlp_func_num(1'd0),
        .client1_tlp_vfunc_num(2'd0),
        .client1_tlp_ats(2'd0),
        .client1_tlp_st(8'd0),
        .client1_tlp_vfunc_active(1'd0),
        .client1_tlp_nw(1'd0),
        .client1_tlp_th(1'd0),
        .client1_tlp_ph(2'd0),
        .client1_tlp_atu_bypass(1'd0),
        .trgt1_radm_halt(trgt1_radm_halt),
        .trgt1_radm_pkt_halt(3'd0),
        .ven_msi_req(msi_request),
        .ven_msi_func_num(1'd0),
        .cfg_msi_pending({63'd0,msi_masked_pending}),
        .ven_msi_vfunc_num(2'd0),
        .ven_msi_vfunc_active(1'd0),
        .ven_msi_tc(3'd0),
        .ven_msi_vector(5'd0),
        .prs_res_failure(2'd0),
        .prs_uprgi(2'd0),
        .prs_stopped(2'd0),
        .sys_atten_button_pressed(2'd0),
        .sys_pre_det_state(2'd0),
        .sys_mrl_sensor_state(2'd0),
        .sys_pwr_fault_det(2'd0),
        .sys_mrl_sensor_chged(2'd0),
        .sys_pre_det_chged(2'd0),
        .sys_cmd_cpled_int(2'd0),
        .sys_eml_interlock_engaged(2'd0),
        .rx_lane_flip_en(1'd0),
        .tx_lane_flip_en(1'd0),
        .app_req_retry_en(1'd0),
        .app_sris_mode(1'd0),
        .app_vf_req_retry_en(4'd0),
        .app_pf_req_retry_en(2'd0),
        .app_unlock_msg(1'd0),
        .app_hdr_log(128'd0),
        .app_err_bus(13'd0),
        .app_err_advisory(1'd0),
        .app_err_func_num(1'd0),
        .app_err_vfunc_active(1'd0),
        .app_hdr_valid(1'd0),
        .app_err_vfunc_num(2'd0),
        .client0_cpl_lookup_id(10'd0),
        .client1_cpl_lookup_id(client1_cpl_lookup_id),
        .app_perst_n(1'b1),
        .app_power_up_rst_n(power_reset_n),
        .app_button_rst_n(1'b1),
        .app_auxclk(aux_clk),
        .drp_dbi_din(32'd0),
        .drp_dbi_wr(4'd0),
        .drp_dbi_addr(32'd0),
        .drp_dbi_cs(1'd0),
        .drp_dbi_cs2_exp(1'd0),
        .drp_dbi_vfunc_num(2'd0),
        .drp_dbi_vfunc_active(1'd0),
        .drp_dbi_bar_num(3'd0),
        .drp_dbi_rom_access(1'd0),
        .drp_dbi_io_access(1'd0),
        .drp_dbi_func_num(1'd0),
        .drp_app_dbi_ro_wr_disable(1'd0),
        .phy_cr_para_clk(aux_clk),
        .xadm_client0_halt(dma_halt),
        .xadm_client1_halt(xadm_client1_halt),
        .radm_bypass_data(radm_bypass_data),
        .radm_bypass_dwen(radm_bypass_dwen),
        .radm_bypass_dv(radm_bypass_dv),
        .radm_bypass_hv(radm_bypass_hv),
        .radm_bypass_eot(radm_bypass_eot),
        .radm_bypass_dllp_abort(radm_bypass_dllp_abort),
        .radm_bypass_tlp_abort(radm_bypass_tlp_abort),
        .radm_bypass_ecrc_err(radm_bypass_ecrc_err),
        .radm_bypass_addr(radm_bypass_addr),
        .radm_bypass_fmt(radm_bypass_fmt),
        .radm_bypass_tc(radm_bypass_tc),
        .radm_bypass_attr(radm_bypass_attr),
        .radm_bypass_reqid(radm_bypass_reqid),
        .radm_bypass_type(radm_bypass_type),
        .radm_bypass_tag(radm_bypass_tag),
        .radm_bypass_func_num(radm_bypass_func_num),
        .radm_bypass_vfunc_num(),
        .radm_bypass_vfunc_active(radm_bypass_vfunc_active),
        .radm_bypass_td(),
        .radm_bypass_poisoned(radm_bypass_poisoned),
        .radm_bypass_dw_len(radm_bypass_dw_len),
        .radm_bypass_rom_in_range(),
        .radm_bypass_first_be(),
        .radm_bypass_last_be(),
        .radm_bypass_io_req_in_range(),
        .radm_bypass_in_membar_range(),
        .radm_bypass_cpl_last(radm_bypass_cpl_last),
        .radm_bypass_cpl_status(radm_bypass_cpl_status),
        .radm_bypass_st(),
        .radm_bypass_cmpltr_id(radm_bypass_cmpltr_id),
        .radm_bypass_byte_cnt(radm_bypass_byte_cnt),
        .radm_bypass_ats(radm_bypass_ats),
        .radm_bypass_th(radm_bypass_th),
        .radm_bypass_ph(),
        .radm_bypass_bcm(radm_bypass_bcm),
        .radm_trgt1_dv(radm_trgt1_dv),
        .radm_trgt1_hv(radm_trgt1_hv),
        .radm_trgt1_eot(radm_trgt1_eot),
        .radm_trgt1_tlp_abort(radm_trgt1_tlp_abort),
        .radm_trgt1_dllp_abort(radm_trgt1_dllp_abort),
        .radm_trgt1_ecrc_err(radm_trgt1_ecrc_err),
        .radm_trgt1_dwen(radm_trgt1_dwen),
        .radm_trgt1_fmt(radm_trgt1_fmt),
        .radm_trgt1_attr(radm_trgt1_attr),
        .radm_trgt1_func_num(radm_trgt1_func_num),
        .radm_trgt1_type(radm_trgt1_type),
        .radm_trgt1_tc(radm_trgt1_tc),
        .radm_trgt1_reqid(radm_trgt1_reqid),
        .radm_trgt1_data(radm_trgt1_data),
        .radm_trgt1_first_be(radm_trgt1_first_be),
        .radm_trgt1_last_be(radm_trgt1_last_be),
        .radm_trgt1_addr(radm_trgt1_addr),
        .radm_trgt1_vfunc_num(),
        .radm_trgt1_vfunc_active(radm_trgt1_vfunc_active),
        .radm_trgt1_td(),
        .radm_trgt1_poisoned(radm_trgt1_poisoned),
        .radm_trgt1_hdr_uppr_bytes_valid(),
        .radm_trgt1_rom_in_range(radm_trgt1_rom_in_range),
        .radm_trgt1_io_req_in_range(),
        .radm_trgt1_hdr_uppr_bytes(),
        .radm_trgt1_in_membar_range(radm_trgt1_in_membar_range),
        .radm_trgt1_cpl_status(),
        .radm_trgt1_ats(radm_trgt1_ats),
        .radm_trgt1_tag(radm_trgt1_tag),
        .radm_trgt1_dw_len(radm_trgt1_dw_len),
        .radm_trgt1_nw(),
        .radm_trgt1_th(),
        .radm_trgt1_ph(),
        .radm_trgt1_st(),
        .radm_trgt1_byte_cnt(),
        .radm_trgt1_bcm(),
        .radm_trgt1_vc(),
        .radm_trgt1_cmpltr_id(),
        .radm_trgt1_cpl_last(),
        .radm_grant_tlp_type(),
        .radm_trgt1_atu_sloc_match(),
        .radm_trgt1_atu_cbuf_err(),
        .training_rst_n(),
        .cfg_msi_en(msi_enable),
        .cfg_msi_mask(msi_mask),
        .ven_msi_grant(msi_grant),
        .cfg_bus_master_en(bus_master_enable),
        .cfg_mem_space_en(),
        .cfg_pbus_num(bus_number),
        .cfg_pbus_dev_num(device_number),
        .smlh_ltssm_state(),
        .rdlh_link_up(physical_link_up),
        .cfg_vf_bme(),
        .radm_vendor_msg(),
        .radm_msg_payload(),
        .radm_msg_req_id(),
        .cfg_send_cor_err(),
        .cfg_send_nf_err(),
        .cfg_send_f_err(),
        .cfg_link_eq_req_int(),
        .smlh_req_rst_not(),
        .link_req_rst_not(),
        .radm_msg_unlock(),
        .radm_cpl_timeout(requester_timeout),
        .radm_timeout_func_num(),
        .radm_timeout_vfunc_num(),
        .radm_timeout_vfunc_active(),
        .radm_timeout_cpl_tc(),
        .radm_timeout_cpl_attr(),
        .radm_timeout_cpl_tag(),
        .radm_timeout_cpl_len(),
        .pm_xtlh_block_tlp(),
        .cfg_phy_control(),
        .cfg_hw_auto_sp_dis(),
        .smlh_ltssm_state_rcvry_eq(),
        .trgt_cpl_timeout(),
        .trgt_timeout_cpl_func_num(),
        .trgt_timeout_cpl_vfunc_num(),
        .trgt_timeout_cpl_vfunc_active(),
        .trgt_timeout_cpl_tc(),
        .trgt_timeout_cpl_attr(),
        .trgt_timeout_cpl_len(),
        .trgt_timeout_lookup_id(),
        .trgt_lookup_id(trgt_lookup_id),
        .trgt_lookup_empty(trgt_lookup_empty),
        .cfg_reg_serren(),
        .cfg_cor_err_rpt_en(),
        .cfg_nf_err_rpt_en(),
        .cfg_f_err_rpt_en(),
        .cfg_uncor_internal_err_sts(),
        .cfg_rcvr_overflow_err_sts(),
        .cfg_fc_protocol_err_sts(),
        .cfg_mlf_tlp_err_sts(),
        .cfg_surprise_down_er_sts(),
        .cfg_dl_protocol_err_sts(),
        .cfg_ecrc_err_sts(),
        .cfg_corrected_internal_err_sts(),
        .cfg_replay_number_rollover_err_sts(),
        .cfg_replay_timer_timeout_err_sts(),
        .cfg_bad_dllp_err_sts(),
        .cfg_bad_tlp_err_sts(),
        .cfg_rcvr_err_sts(),
        .core_rst_n(core_reset_n),
        .user_link(user_link_up),
        .drp_lbc_dbi_dout(),
        .drp_lbc_dbi_ack(),
        .core_clk(),
        .user_clk(user_clk),
        .muxd_aux_clk(),
        .muxd_aux_clk_g()
    );

endmodule
`default_nettype wire
