# New camera1 and cold stereo control only. Flat native TD SDC commands.
# Load real_hdr_clocks, this file, stream_cdc, then observer_cdc in native TD.
# Source-level constraints: mapped-object coverage and physical STA are NOT_RUN.
# No clock groups, blanket hierarchy cuts, second-stage exceptions or IP edits.

# Camera1 supports SDR and DOL2; time the fastest physical HDR lane clock (450 MHz).
create_clock -name mipi1_hs_clk -period 2.222222 [get_ports {mipi1_clk_hs_rx_p}]
# Derive the newly clocked camera1 LCLK/SCLK network, preserving related phases.
derive_clocks

# REF -> WORD first stages: enable and watchdog request.
set_max_delay -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/word_enable_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/word_enable_sync[0]}]
set_max_delay -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/r_align_enable_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/r_align_enable_sync[0]}]
set_max_delay -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_req_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_req_meta}]

# WORD -> PIX/REF first stages: identity fault, ready, calibration, watchdog ACK.
set_max_delay -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_stream/identity_fault_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_stream/identity_fault_pixel[0]}]
set_max_delay -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/phy_ready_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/phy_ready_sync[0]}]
set_max_delay -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/delay_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/delay_sync[0]}]
set_max_delay -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_ack_meta}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_ack_meta}]

# Camera1 selects the unchanged 47x512 official FIFO. Only its g_depth512 IP
# root is selected. B native 47x512 synthesis confirms the exact generated
# instance below and nine Gray / FIRST-stage bits in each direction. No second
# stage or other FIFO is selected; production matching remains a separate check.
# 7.5ns is below min(PIX 8ns, HDR WORD 8.888888ns); all SECOND paths stay timed.
set_max_delay -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_w[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_w[*]}] -datapath_only 7.500
set_false_path -hold -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_w[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_w[*]}]
set_path_skew -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_w[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_w[*]}] 7.500
set_max_delay -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_r[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_r[*]}] -datapath_only 7.500
set_false_path -hold -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_r[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_r[*]}]
set_path_skew -from [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/primary_addr_gray_reg_r[*]}] -to [get_regs -hier {u_camera1/u_receiver/u_stream/u_event_fifo/g_depth512$u_event_fifo/soft_fifo_Inst/soft_fifo_core_inst/cdc$cross_inst/sync_r1_r[*]}] 7.500

# Cold mode USER request/release/quarantine -> PIX/DFI FIRST only.
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/request_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/request_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_request_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/request_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/request_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_request_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/release_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_release_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/release_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_release_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/release_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_release_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/release_toggle}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_release_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/quarantined}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_quarantine_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/quarantined}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_quarantine_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/quarantined}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_quarantine_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/quarantined}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_quarantine_sync[0]}]

# Recipient ACK publication -> USER FIRST; original ACK/SECOND/local logic timed.
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/pixel_ack}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/pixel_ack}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_ack_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/dfi_ack}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/dfi_ack}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_ack_sync[0]}]

# PIX quiet receipt requests the SYS25 profile capture. Return receipt to USER.
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/pixel_ack}] -to [get_regs {g_stereo_control$u_stereo_control/cfg_request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/pixel_ack}] -to [get_regs {g_stereo_control$u_stereo_control/cfg_request_sync[0]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/cfg_ack}] -to [get_regs {g_stereo_control$u_stereo_control/cfg_ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/cfg_ack}] -to [get_regs {g_stereo_control$u_stereo_control/cfg_ack_sync[0]}]

# Held mode/cadence fields: stable throughout the request and every receipt.
# Destination captures only after two-stage request synchronization and local quiet.
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/held_profile[*]}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_mode[*] g_stereo_control$u_stereo_control/o_pixel_frame_divisor[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/held_profile[*]}] -to [get_regs {g_stereo_control$u_stereo_control/pixel_mode[*] g_stereo_control$u_stereo_control/o_pixel_frame_divisor[*]}]
set_max_delay -from [get_regs {g_stereo_control$u_stereo_control/held_profile[*]}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_mode[*] g_stereo_control$u_stereo_control/o_dfi_frame_divisor[*]}] -datapath_only 7.000
set_false_path -hold -from [get_regs {g_stereo_control$u_stereo_control/held_profile[*]}] -to [get_regs {g_stereo_control$u_stereo_control/dfi_mode[*] g_stereo_control$u_stereo_control/o_dfi_frame_divisor[*]}]

# RAW shares the synchronized request and acknowledgements. Select its held data net
# and replicas between USER and the two recipient clocks because packing can
# rename the physical launch and capture cells.
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[10]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] u_ddr_store/u_ddr/dfi_clk}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[10]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] u_ddr_store/u_ddr/dfi_clk}]

# Rate bundle bits 11..13 feed only the PIX admission selector and the SYS25
# sensor request. Both recipients sample held data after a synchronized token.
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[11]* g_stereo_control$u_stereo_control/held_profile[12]* g_stereo_control$u_stereo_control/held_profile[13]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] sys_clk_25m}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[11]* g_stereo_control$u_stereo_control/held_profile[12]* g_stereo_control$u_stereo_control/held_profile[13]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] sys_clk_25m}]

# Foreign-origin reset REQUEST -> explicit local release banks only.
# Each target D-chain shifts locally; local release -> functional reset consumers
# and related WORD/x2/x4 PHY recovery/removal paths remain timed.
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_cohort_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_cohort_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_ext_reset_sync[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_stream/u_identity_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_stream/pixel_reset_sync[*]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_stream/u_event_fifo/read_release[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_stream/u_event_fifo/write_release[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_stereo_control$u_stereo_control/u_user_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_stereo_control$u_stereo_control/u_user_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_stereo_control$u_stereo_control/u_pixel_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_stereo_control$u_stereo_control/u_pixel_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -to [get_regs {g_stereo_control$u_stereo_control/u_dfi_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {g_stereo_control$u_stereo_control/u_dfi_release/release_pipe[*]}]
set_false_path -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk u_pixel_pll/pll_inst.clkc[0] u_ddr_store/u_ddr/dfi_clk}] -to [get_regs {g_stereo_control$u_stereo_control/u_cfg_release/release_pipe[*]}]

# u_stereo_capture0/1 are entirely in PIX; they receive no CDC exceptions.
# Cold geometry is held alongside the original mode/product tuple through
# the same PIX/DFI receipt handshake. It is never changed in an active stream.
set_max_delay -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[14]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] u_ddr_store/u_ddr/dfi_clk}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pcie/endpoint/bridge/u_controller/pcie_user_clk}] -through [get_nets {g_stereo_control$u_stereo_control/held_profile[14]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0] u_ddr_store/u_ddr/dfi_clk}]
# Unconnected eye-scan debug output registers may be pruned; no blanket cut is
# added for them. If debug outputs become live, add a held-status bundle budget.
# Port input/output delay values need measured board/sensor timing; none invented.

# CAM1 uses the same reset, event mailbox and SDR/DOL2 receive structures as CAM0.
set_max_delay -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/fault_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/fault_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_mode_word[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_mode_word[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_cycle_word[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_cycle_word[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_mode_pixel[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_receiver/hdr_mode_pixel[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/done_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/done_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/error_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/error_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/enable_sync[0]}] -datapath_only 7.500
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/enable_sync[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/quiet_cfg[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/quiet_cfg[0]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/u_identity_word_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/u_identity_pixel_reset/release_pipe[*]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -to [get_regs {u_camera1/u_receiver/u_hdr_stream/pixel_release[*]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/fault_cfg[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/fault_cfg[0]}]
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_pair_cdc/request_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/u_pair_cdc/request_sync[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_pair_cdc/ack_sync[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/u_pair_cdc/ack_sync[0]}]
set_max_delay -from [get_regs {u_camera1/u_pair_cdc/payload}] -to [get_regs {u_camera1/u_pair_cdc/m_ok}] -datapath_only 7.000
set_false_path -hold -from [get_regs {u_camera1/u_pair_cdc/payload}] -to [get_regs {u_camera1/u_pair_cdc/m_ok}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/cfg_release[*]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/ref_reset[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/ref_reset[*]}]
set_false_path -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/pixel_reset[*]}]
set_false_path -from [get_regs {u_camera1/ref_reset[1]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_ext_reset_sync[0]}]
set_false_path -from [get_regs {u_camera1/ref_reset[1]}] -to [get_regs {u_camera1/u_receiver/u_phy/u_csi_clock_watchdog/r_ext_reset_sync[1]}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -through [get_nets {u_camera1/u_receiver/u_hdr_stream/g_member[0]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {u_camera1/u_receiver/u_hdr_stream/g_member[0]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}]
set_false_path -from [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}] -through [get_nets {u_camera1/u_receiver/u_hdr_stream/g_member[1]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]
set_false_path -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -through [get_nets {u_camera1/u_receiver/u_hdr_stream/g_member[1]$u_fifo/fifo_async_reset_n*}] -to [get_clocks {u_camera1/u_receiver/u_phy/u_rx_clk_gen/U_io_clk_div_1.clkdivout}]

# Held CAM1 tag settles during SYS25 mode hold and is captured once after
# local PIX reset release. The clocks scope these three nets and replicas.
set_max_delay -from [get_clocks {sys_clk_25m}] -through [get_nets {u_camera1/sdr_profile_cfg[0]* u_camera1/sdr_profile_cfg[1]* u_camera1/sdr_profile_cfg[2]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -through [get_nets {u_camera1/sdr_profile_cfg[0]* u_camera1/sdr_profile_cfg[1]* u_camera1/sdr_profile_cfg[2]*}] -to [get_clocks {u_pixel_pll/pll_inst.clkc[0]}]

# Explicit mode request / return levels: FIRST only, later stages remain timed.
set_max_delay -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/request_cfg[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {u_pixel_pll/pll_inst.clkc[0]}] -to [get_regs {u_camera1/request_cfg[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/mode_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/mode_pixel[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/hold_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/hold_pixel[0]}]
set_max_delay -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/stable_pixel[0]}] -datapath_only 7.000
set_false_path -hold -from [get_clocks {sys_clk_25m}] -to [get_regs {u_camera1/stable_pixel[0]}]
