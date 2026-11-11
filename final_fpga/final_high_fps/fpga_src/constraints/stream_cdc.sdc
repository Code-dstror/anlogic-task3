# SDR/HDR1080P source-level CDC constraints. No runtime audit callbacks.
# Budgets retain one-period7.0/7.5/8.0ns bounds on declared FIRST or held-bus captures.
# SECOND stages, source publication logic and ordinary data/register paths remain timed.

set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$old_pipeline_idle_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$old_pipeline_idle_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$hdr_product_quiet_dfi[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$hdr_product_quiet_dfi[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$job_idle_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$job_idle_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {armed_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {armed_pixel[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {rearm_ready_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {rearm_ready_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {record_idle_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {record_idle_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$read_quiet_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$read_quiet_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/dfi_ack_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/dfi_ack_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/dfi_quiet_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/dfi_quiet_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/rearm_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_soft_reset_fence/rearm_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/stop_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/stop_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/stop_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/stop_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {free_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {free_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {fault_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {fault_pixel[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {armed_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {armed_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$u_source_events/hard_fault_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$u_source_events/hard_fault_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {product_fault_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {product_fault_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {hdr_phase_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {hdr_phase_pixel[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/dfi_fault_meta[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/dfi_fault_meta[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/dfi_fault_meta[1]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/dfi_fault_meta[1]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/drain_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/drain_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/sink_fault_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/sink_fault_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/fault_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/fault_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_slot_credit/ack_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_slot_credit/ack_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/ack_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/ack_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {fault_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {fault_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/drain_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/drain_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_camera/quiet_cfg[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_camera/quiet_cfg[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/infra_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/infra_meta}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[1]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[1]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[2]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[2]}]
set_max_delay -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/fault_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/fault_sync[0]}]
set_max_delay -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_stream/identity_fault_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_stream/identity_fault_pixel[0]}]
set_max_delay -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_ack_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_ack_meta}]
set_max_delay -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/phy_ready_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/phy_ready_sync[0]}]
set_max_delay -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/delay_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/delay_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_mode_word[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_mode_word[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_cycle_word[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_cycle_word[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_mode_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_receiver/hdr_mode_pixel[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/done_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/done_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/error_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/error_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/enable_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/enable_sync[0]}]
set_max_delay -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/word_enable_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/word_enable_sync[0]}]
set_max_delay -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_req_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_req_meta}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {pairbank_enable_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {pairbank_enable_meta}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/pending_dfi[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/pending_dfi[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_record_format$u_format/user_done_dfi_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_record_format$u_format/user_done_dfi_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/s_peer_ready[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/s_peer_ready[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/m_fault_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/m_fault_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/return_request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/return_request_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/cancel_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/cancel_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/infra_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/infra_meta}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/enable_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/enable_meta}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[3]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/fifo_done_meta[3]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pcie/endpoint/supervisor/bme_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pcie/endpoint/supervisor/bme_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pcie/endpoint/supervisor/link_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pcie/endpoint/supervisor/link_sync[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {record_format_busy_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {record_format_busy_pixel[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/pending_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/pending_pixel[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/drain_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_soft_reset_fence/drain_pixel[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {pairbank_pause_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {pairbank_pause_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1/ready_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1/ready_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/pixel_fault_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/pixel_fault_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_slot_credit/req_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_slot_credit/req_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_hdr_source$u_native_source/g_shared_native$u_transport/sink_fault_meta}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_hdr_source$u_native_source/g_shared_native$u_transport/sink_fault_meta}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/source_fault_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/source_fault_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/drain_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/drain_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/drain_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/drain_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/quiet_cfg[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/quiet_cfg[0]}]
# Held CAM0 tag settles during SYS25 mode hold and is captured once after
# local PIX reset release. The clocks scope these three nets and replicas.
set_max_delay -from [get_clocks {sys_clk_25m}] -through [get_nets {u_camera/sdr_profile_cfg[0]* u_camera/sdr_profile_cfg[1]* u_camera/sdr_profile_cfg[2]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -through [get_nets {u_camera/sdr_profile_cfg[0]* u_camera/sdr_profile_cfg[1]* u_camera/sdr_profile_cfg[2]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_session_ctl/fifo_done_meta[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_session_ctl/fifo_done_meta[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/pause_ack_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/pause_ack_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/pixel_quiet_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/pixel_quiet_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/data_reset_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/data_reset_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/token_proof_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_soft_reset_fence/token_proof_user[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {local_dfi[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {local_dfi[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_soft_reset_fence/rearm_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_soft_reset_fence/rearm_user[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {armed_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {armed_pixel[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {armed_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {armed_user[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {rearm_ready_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {rearm_ready_user[0]}]

set_max_delay -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/route_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/active_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_epoch[*]}] -datapath_only 8.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/route_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/active_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/cfg_sample_epoch[*]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/route_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/active_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_epoch[*]}] -datapath_only 8.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/route_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/active_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_sdr g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_session[*] g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/cfg_sample_epoch[*]}]
set_max_delay -from [get_regs {g_configured_capture$u_frontend/u_time/source_gray[*]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1/gray_meta[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$u_frontend/u_time/source_gray[*]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1/gray_meta[*]}]
set_path_skew -from [get_regs {g_configured_capture$u_frontend/u_time/source_gray[*]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1/gray_meta[*]}] 7.000
set_max_delay -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/fence_count[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/fence_count[*]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/fence_count[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/fence_count[*]}]
set_max_delay -from [get_regs {u_ddr_to_pcie/return_status[0] u_ddr_to_pcie/return_status[1] u_ddr_to_pcie/return_status[2]}] -to [get_regs {u_ddr_to_pcie/s_retire_status[0] u_ddr_to_pcie/s_retire_status[1] u_ddr_to_pcie/s_retire_status[2]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_ddr_to_pcie/return_status[0] u_ddr_to_pcie/return_status[1] u_ddr_to_pcie/return_status[2]}] -to [get_regs {u_ddr_to_pcie/s_retire_status[0] u_ddr_to_pcie/s_retire_status[1] u_ddr_to_pcie/s_retire_status[2]}]

set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pixel_reset/release_pipe[*]}]
# Same-source, same-edge final-stage data reset copies. Foreign clocks reach
# only their ASR; PIX data inputs and all local functional paths remain timed.
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pixel_reset/g_data_release$data_release_n[0]* u_pixel_reset/g_data_release$data_release_n[1]* u_pixel_reset/g_data_release$data_release_n[2]* u_pixel_reset/g_data_release$data_release_n[3]* u_pixel_reset/g_data_release$data_release_n[4]* u_pixel_reset/g_data_release$data_release_n[5]* u_pixel_reset/g_data_release$data_release_n[6]*}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_user_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_transport_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_debug_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_product_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_ddr_store/u_session_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_ddr_store/g_ring_store$u_record_owner_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_soft_reset_fence/u_pixel_cold_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_soft_reset_fence/u_dfi_cold_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_soft_reset_fence/u_user_cold_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_ddr_to_pcie/s_release/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_ddr_to_pcie/m_release/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pcie/endpoint/ownership_reset_sync[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_pixel_reset/g_data_release$data_release_n[0]* u_pixel_reset/g_data_release$data_release_n[1]* u_pixel_reset/g_data_release$data_release_n[2]* u_pixel_reset/g_data_release$data_release_n[3]* u_pixel_reset/g_data_release$data_release_n[4]* u_pixel_reset/g_data_release$data_release_n[5]* u_pixel_reset/g_data_release$data_release_n[6]*}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_user_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_transport_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_live_f21_reset$u_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_config$g_source_bootstrap$u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$u_cohort_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_config$u_config_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_jpeg_control$u_service/u_user_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_live_core_reset$u_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_jpeg_control$u_service/paired_reset* g_record_format$u_format/cohort_reset_n*}] -to [get_regs {g_record_format$u_format/user_release[0]* g_record_format$u_format/user_release[1]* g_record_format$u_format/user_release[2]*}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_source_reset/release_pipe[*]}]
# Pair-drain request/ACK: remote DFI release reaches only these PIX ASR pins.
# Keep logical Q/through-net/target-bit objects across packing. Gate sr pins do
# not reliably correlate to physical asr pins. The joint-reset net reaches only
# release-chain ASR, never stage D/CE; specific remote FROM preserves local ASR.
# Request/ACK use the same joint AND; either alias may be the physical net name.
# ACK sink is the same PIX release motif; suffix copies need the same scope.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/pr/release_pipe[*]}]
# RAW FIFO joint reset: only the remote DFI release Q drives these PIX ASR
# entrances through the dedicated joint-reset net. Logical target bits survive
# packing; D shifts and local pr->source ASR stay timed. No ordinary D/CE path
# passes through this net (raw_capture_fifo_eram_safe has only two ASR ledgers).
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/pr/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_jpeg_to_ddr/u_source_reset/release_pipe[*]}]
# JPEG token FIFO: the DFI release Q uses the egress reset alias after packing.
# Only this remote Q through the joint-reset net reaches the named PIX ASR;
# suffix matching retains replicated release bits while local D/CE/ASR stay timed.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_hdr_source$u_native_source/g_shared_native$u_transport/u_sink_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pixel_reset/g_data_release$data_release_n[0]* u_pixel_reset/g_data_release$data_release_n[1]* u_pixel_reset/g_data_release$data_release_n[2]* u_pixel_reset/g_data_release$data_release_n[3]* u_pixel_reset/g_data_release$data_release_n[4]* u_pixel_reset/g_data_release$data_release_n[5]* u_pixel_reset/g_data_release$data_release_n[6]*}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_live_f21_reset$u_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_jpeg_control$u_service/u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_config$u_config/u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_live_core_reset$u_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_jpeg_control$u_service/paired_reset* g_record_format$u_format/cohort_reset_n*}] -to [get_regs {g_record_format$u_format/dfi_release[0]* g_record_format$u_format/dfi_release[1]* g_record_format$u_format/dfi_release[2]*}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_ddr_to_pcie/s_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_pairbank_run_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$u_cohort_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_config$u_config/u_user_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_source_reset/release_pipe[*]}]
# Symmetric remote PIX release Q -> DFI ASR entrances only; local dr and
# sink_release[0]->[1]->[2] D arcs retain ordinary setup/hold checks.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_stream/u_event_fifo/write_release[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_jpeg_to_ddr/u_sink_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_hdr_source$u_native_source/g_shared_native$u_transport/u_source_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/u_application_stop/run_release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_cohort_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_cohort_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_stream/u_identity_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/u_identity_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_stream/pixel_reset_sync[*]}]
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_hdr_stream/pixel_release[*]}]
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera/u_receiver/u_stream/u_event_fifo/read_release[*]}]

# Source-bound gaps found in the 2026-10-22 fast/default/high routed reports.
# These are FIRST stages of existing two-register level/toggle synchronizers.
# Their SECOND-stage paths and ordinary receiving logic remain clock timed.
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_jpeg_control$u_service/ddr_ready_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_jpeg_control$u_service/ddr_ready_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {record_source_valid_user[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {record_source_valid_user[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/m_peer_ready[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/m_peer_ready[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/s_fault_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/s_fault_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/return_ack_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_ddr_to_pcie/return_ack_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_record_format$u_format/dfi_done_user_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_record_format$u_format/dfi_done_user_sync[0]}]
# DDR physical readiness is observed by the continuously running SYS watcher.
# Only its first link_sync stage is asynchronous; link_sync[1] remains timed.
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_memory_owner_watch/link_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_memory_owner_watch/link_sync[0]}]
# Positive-slack NO_COMMON_MASTER paths also need their actual CDC contract.
# These are only the observed source-clock contributions to existing FIRST
# stages; other sources and every SECOND stage retain their existing checks.
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {local_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {local_user[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {fault_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {fault_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {source_active_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {source_active_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {fault_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {fault_user[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {product_fault_user[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {product_fault_user[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {enable_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {enable_pixel[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {recovery_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {recovery_pixel[0]}]
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {armed_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {armed_pixel[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/fault_cfg[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/fault_cfg[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_pair_cdc/request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/u_pair_cdc/request_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_pair_cdc/ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/u_pair_cdc/ack_sync[0]}]

# The event payload is frozen before request publication and held until ACK.
# Only that held bit and its explicit destination sample are relaxed.
set_max_delay -from [get_regs {u_camera/u_pair_cdc/payload}] -to [get_regs {u_camera/u_pair_cdc/m_ok}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_camera/u_pair_cdc/payload}] -to [get_regs {u_camera/u_pair_cdc/m_ok}]

# Raw asynchronous reset requests terminate ONLY on preserved release stages.
# The local release outputs, local stage-to-stage D paths, and their business
# fanout keep recovery/removal, setup and hold checks at the original clocks.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/cfg_release[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera/ref_reset[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/ref_reset[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera/pixel_reset[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_private_processing$u_processing/u_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_private_processing$u_processing/u_dfi_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/u_reset0/release_pipe[*]}]

# Local incident holders retain sub-cycle faults even with a stopped clock.
# Their sticky business latches no longer receive raw remote deassertion.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_session_ctl/abort_hold_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_session_ctl/abort_hold_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {u_pcie/endpoint/supervisor/incident_hold_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {u_memory_owner_watch/incident_hold_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pcie/endpoint/supervisor/fault_sync[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pcie/endpoint/supervisor/u_ready_reset/release_pipe[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_memory_owner_watch/fault_sync[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_memory_owner_watch/u_ready_reset/release_pipe[*]}]
# memory_fault_user is the asynchronous SET input of this two-stage DFI drain.
# Its only USER Q sources are fault_sync[1] and ready_reset_n. The dedicated
# THROUGH net never enters either stage's D/CE; the DFI shift remains timed.
set_false_path -from [get_regs {u_memory_owner_watch/fault_sync[1]* u_memory_owner_watch/ready_reset_n*}] -through [get_nets {memory_fault_user*}] -to [get_regs {memory_fault_dfi[0]*}]
set_false_path -from [get_regs {u_memory_owner_watch/fault_sync[1]* u_memory_owner_watch/ready_reset_n*}] -through [get_nets {memory_fault_user*}] -to [get_regs {memory_fault_dfi[1]*}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pcie/endpoint/supervisor/ready_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_pcie/endpoint/supervisor/ready_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_memory_owner_watch/ready_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_memory_owner_watch/ready_sync[0]}]

# Each owned FIFO waits for the peer's clocked port-reset assertion. These
# one-bit indications enter only the named FIRST stages; the local seen/run
# state, official RAM pins and all SECOND stages remain normally timed.
# Only the 17 production instances below have different source/sink clocks.
# Same-clock JPEG quantization FIFOs retain ordinary first-stage hold checks.
# USER -> PIX: g_config$u_config/u_command_fifo
set_max_delay -from [get_regs {g_config$u_config/u_command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_command_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_config$u_config/u_command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_command_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_config$u_config/u_command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_command_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_config$u_config/u_command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_command_fifo/sink_peer_release[0]*}]
# PIX -> USER: g_config$u_config/u_response_fifo
set_max_delay -from [get_regs {g_config$u_config/u_response_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_response_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_config$u_config/u_response_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_response_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_config$u_config/u_response_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_response_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_config$u_config/u_response_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_config$u_config/u_response_fifo/sink_peer_release[0]*}]
# USER -> DFI: g_jpeg_control$u_service/u_command_fifo
set_max_delay -from [get_regs {g_jpeg_control$u_service/u_command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_command_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_jpeg_control$u_service/u_command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_command_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_jpeg_control$u_service/u_command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_command_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_jpeg_control$u_service/u_command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_command_fifo/sink_peer_release[0]*}]
# DFI -> USER: g_jpeg_control$u_service/u_response_fifo
set_max_delay -from [get_regs {g_jpeg_control$u_service/u_response_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_response_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_jpeg_control$u_service/u_response_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_response_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_jpeg_control$u_service/u_response_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_response_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_jpeg_control$u_service/u_response_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_jpeg_control$u_service/u_response_fifo/sink_peer_release[0]*}]
# USER -> DFI: g_record_format$u_format/command_fifo
set_max_delay -from [get_regs {g_record_format$u_format/command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/command_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_record_format$u_format/command_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/command_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_record_format$u_format/command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/command_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_record_format$u_format/command_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/command_fifo/sink_peer_release[0]*}]
# DFI -> USER: g_record_format$u_format/ack_fifo
set_max_delay -from [get_regs {g_record_format$u_format/ack_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/ack_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_record_format$u_format/ack_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/ack_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_record_format$u_format/ack_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/ack_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_record_format$u_format/ack_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_record_format$u_format/ack_fifo/sink_peer_release[0]*}]
# PIX -> DFI: g_configured_capture$g_job_config$u_job_config/u_request
set_max_delay -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/sink_peer_release[0]*}]
# DFI -> PIX: g_configured_capture$g_job_config$u_job_config/u_ack
set_max_delay -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_ack/sink_peer_release[0]*}]
# PIX -> DFI: g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request
set_max_delay -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/sink_peer_release[0]*}]
# DFI -> PIX: g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack
set_max_delay -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/sink_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/source_reset_release_pipe[2]*}] -to [get_regs {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/sink_peer_release[0]*}]
# DFI -> PIX: g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward
set_max_delay -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/sink_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/sink_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/source_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/source_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/sink_peer_release[0]*}]
# PIX -> DFI: g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return
set_max_delay -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/sink_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/sink_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/source_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/source_reset_release_pipe[2]*}] -to [get_regs {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/sink_peer_release[0]*}]
# DFI -> PIX: g_s04$u_raw_service/u_replay_fifo
set_max_delay -from [get_regs {g_s04$u_raw_service/u_replay_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_s04$u_raw_service/u_replay_fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/u_replay_fifo/sink_reset_release_pipe[2]*}] -to [get_regs {g_s04$u_raw_service/u_replay_fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {g_s04$u_raw_service/u_replay_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_s04$u_raw_service/u_replay_fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/u_replay_fifo/source_reset_release_pipe[2]*}] -to [get_regs {g_s04$u_raw_service/u_replay_fifo/sink_peer_release[0]*}]
# PIX -> DFI: u_jpeg_to_ddr/u_token_fifo/fifo
set_max_delay -from [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/sink_reset_release_pipe[2]*}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/sink_reset_release_pipe[2]*}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/source_reset_release_pipe[2]*}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/source_reset_release_pipe[2]*}] -to [get_regs {u_jpeg_to_ddr/u_token_fifo/fifo/sink_peer_release[0]*}]
# DFI -> USER: u_ddr_to_pcie/fifo
set_max_delay -from [get_regs {u_ddr_to_pcie/fifo/sink_reset_release_pipe[2]*}] -to [get_regs {u_ddr_to_pcie/fifo/source_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_ddr_to_pcie/fifo/sink_reset_release_pipe[2]*}] -to [get_regs {u_ddr_to_pcie/fifo/source_peer_release[0]*}]
set_max_delay -from [get_regs {u_ddr_to_pcie/fifo/source_reset_release_pipe[2]*}] -to [get_regs {u_ddr_to_pcie/fifo/sink_peer_release[0]*}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_ddr_to_pcie/fifo/source_reset_release_pipe[2]*}] -to [get_regs {u_ddr_to_pcie/fifo/sink_peer_release[0]*}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_source_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_configured_capture$u_frontend/u_time/u_sink1_reset/release_pipe[*]}]

# Foreign reset assertion inputs to explicit local release bits only.
# Each destination D is constant 1 or the preceding local-stage Q; these
# foreign source registers connect only to ASR. Local D, local-reset ASR and
# all downstream business paths remain timed. See CLOCKTREE_CDC_20261023.md.
set_false_path -from [get_regs {g_private_processing$u_cohort_dfi_reset/release_pipe[2]}] -to [get_regs {g_private_processing$u_source_events/u_pixel_reset/release_pipe[0]}]
set_false_path -from [get_regs {g_private_processing$u_cohort_dfi_reset/release_pipe[2]}] -to [get_regs {g_private_processing$u_source_events/u_pixel_reset/release_pipe[1]}]
set_false_path -from [get_regs {g_private_processing$u_cohort_dfi_reset/release_pipe[2]}] -to [get_regs {g_private_processing$u_source_events/u_pixel_reset/release_pipe[2]}]
set_false_path -from [get_regs {u_camera/ref_reset[1]}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_ext_reset_sync[0]}]
set_false_path -from [get_regs {u_camera/ref_reset[1]}] -to [get_regs {u_camera/u_receiver/u_phy/u_csi_clock_watchdog/r_ext_reset_sync[1]}]

# Fixed-table status only. One PIX -> USER FIRST capture; SECOND stays timed.

# R3: FIFO joint reset Q -> dedicated reset net -> foreign capture clock.
# The three owned wrapper implementations use these nets only at release
# ASR pins (no D/CE). Pair aliases cover synthesis merging of equivalent
# request/response reset LUTs. Clock endpoints include every physical copy;
# same-clock ASR, shift D, peer FIRST budgets and business paths stay timed.
# config: exact owned reset net; USER <-> PIX ASR only.
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_config$u_config/u_command_fifo/fifo_async_reset_n* g_config$u_config/u_response_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_config$u_config/u_command_fifo/fifo_async_reset_n* g_config$u_config/u_response_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}]
# jpeg: exact owned reset net; USER <-> DFI ASR only.
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_jpeg_control$u_service/u_command_fifo/fifo_async_reset_n* g_jpeg_control$u_service/u_response_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_jpeg_control$u_service/u_command_fifo/fifo_async_reset_n* g_jpeg_control$u_service/u_response_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}]
# record: exact owned reset net; USER <-> DFI ASR only.
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_jpeg_control$u_service/paired_reset*}] -to [get_regs {g_record_format$u_format/command_fifo/sink_reset_release_pipe[0]* g_record_format$u_format/command_fifo/sink_reset_release_pipe[1]* g_record_format$u_format/command_fifo/sink_reset_release_pipe[2]* g_record_format$u_format/ack_fifo/source_reset_release_pipe[0]* g_record_format$u_format/ack_fifo/source_reset_release_pipe[1]* g_record_format$u_format/ack_fifo/source_reset_release_pipe[2]*}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_jpeg_control$u_service/paired_reset*}] -to [get_regs {g_record_format$u_format/command_fifo/source_reset_release_pipe[0]* g_record_format$u_format/command_fifo/source_reset_release_pipe[1]* g_record_format$u_format/command_fifo/source_reset_release_pipe[2]* g_record_format$u_format/ack_fifo/sink_reset_release_pipe[0]* g_record_format$u_format/ack_fifo/sink_reset_release_pipe[1]* g_record_format$u_format/ack_fifo/sink_reset_release_pipe[2]*}]
# job: exact owned reset net; PIX <-> DFI ASR only.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_configured_capture$g_job_config$u_job_config/i_dfi_rst_n*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/sink_reset_release_pipe[0]* g_configured_capture$g_job_config$u_job_config/u_request/sink_reset_release_pipe[1]* g_configured_capture$g_job_config$u_job_config/u_request/sink_reset_release_pipe[2]* g_configured_capture$g_job_config$u_job_config/u_ack/source_reset_release_pipe[0]* g_configured_capture$g_job_config$u_job_config/u_ack/source_reset_release_pipe[1]* g_configured_capture$g_job_config$u_job_config/u_ack/source_reset_release_pipe[2]*}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_configured_capture$g_job_config$u_job_config/i_dfi_rst_n*}] -to [get_regs {g_configured_capture$g_job_config$u_job_config/u_request/source_reset_release_pipe[0]* g_configured_capture$g_job_config$u_job_config/u_request/source_reset_release_pipe[1]* g_configured_capture$g_job_config$u_job_config/u_request/source_reset_release_pipe[2]* g_configured_capture$g_job_config$u_job_config/u_ack/sink_reset_release_pipe[0]* g_configured_capture$g_job_config$u_job_config/u_ack/sink_reset_release_pipe[1]* g_configured_capture$g_job_config$u_job_config/u_ack/sink_reset_release_pipe[2]*}]
# pair: exact owned reset net; PIX <-> DFI ASR only.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/fifo_async_reset_n* g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_request/fifo_async_reset_n* g_configured_capture$u_frontend/g_joint_config_owner$u_joint/u_pair_drain/u_ack/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
# ticket: exact owned reset net; DFI <-> PIX ASR only.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/fifo_async_reset_n* g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_forward/fifo_async_reset_n* g_private_processing$u_processing/u_processing_context_cdc/u_ticket/u_return/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
# raw0: exact owned reset net; PIX <-> DFI ASR only.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member0/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
# raw1: exact owned reset net; PIX <-> DFI ASR only.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_s04$u_raw_service/g_dol2_capture$u_capture/u_member1/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
# replay: exact owned reset net; DFI <-> PIX ASR only.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_s04$u_raw_service/u_replay_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_s04$u_raw_service/u_replay_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
# hdr0: exact owned reset net; WORD <-> PIX ASR only.
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -through [get_nets {u_camera/u_receiver/u_hdr_stream/g_member[0]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {u_camera/u_receiver/u_hdr_stream/g_member[0]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}]
# hdr1: exact owned reset net; WORD <-> PIX ASR only.
set_false_path -from [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -through [get_nets {u_camera/u_receiver/u_hdr_stream/g_member[1]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {u_camera/u_receiver/u_hdr_stream/g_member[1]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_camera/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}]
# jpeg_token: exact owned reset net; PIX <-> DFI ASR only.
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {u_jpeg_to_ddr/u_token_fifo/fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {u_jpeg_to_ddr/u_token_fifo/fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
# record_payload: exact owned reset net; DFI <-> USER ASR only.
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {u_ddr_to_pcie/fifo/fifo_async_reset_n*}] -to [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {u_ddr_to_pcie/fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
# CAM1 DOL2 writers use dedicated copies of the PIX/DFI capture CDC.
# Scope each exception to the same synchronizer or held mailbox as CAM0.
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/stop_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/stop_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/stop_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/stop_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/drain_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/drain_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_request_sync[0]}]
set_max_delay -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/drain_request_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/drain_request_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/drain_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/drain_ack_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/drain_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/drain_ack_sync[0]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/route_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/active_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_epoch[*]}] -datapath_only 8.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/route_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/active_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/cfg_sample_epoch[*]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/route_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/active_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_epoch[*]}] -datapath_only 8.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/route_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/active_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/active_epoch[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_sdr g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_session[*] g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/cfg_sample_epoch[*]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/fence_count[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/fence_count[*]}]
set_max_delay -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/fence_count[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/frozen_produced[*]}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/fence_count[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/pr/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/pr/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member0/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_ddr_store/u_ddr/dfi_clk}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -through [get_nets {g_s04$u_raw_service/g_cam1_hdr$u_capture/u_member1/capture_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
