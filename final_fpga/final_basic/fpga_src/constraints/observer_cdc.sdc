# Read-only UART observation CDC. No application/control-domain paths are cut.
# All source snapshots are held until a four-phase ACK completes. Two SYS
# ACK stages plus ACK_SETTLE precede the 48-bit capture (SYS period=40ns).
# Bound data/control propagation to 32ns; waive only async FIRST-stage hold.
# Every stage-2 and ordinary business setup/hold/recovery/removal remains timed.

set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/request_level[0]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/request_sync[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/request_level[0]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/request_sync[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[0]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}]

set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/request_level[1]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/request_sync[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/request_level[1]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/request_sync[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[1]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[1]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[1]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}]

set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/request_level[2]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/request_sync[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/request_level[2]}] -to [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/request_sync[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[2]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/ack_meta[2]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_domain[2]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_domains[*]}]

# Independently synchronized observation levels; FIRST stages only.
set_max_delay -to [get_regs {g_production$g_status_uart$u_observer/reset_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$u_observer/reset_meta[*]}]
set_max_delay -to [get_regs {g_production$g_status_uart$sys_flags_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$sys_flags_meta[*]}]
set_max_delay -to [get_regs {g_production$g_status_uart$pixel_flags_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$pixel_flags_meta[*]}]
set_max_delay -to [get_regs {g_production$g_status_uart$dfi_flags_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$dfi_flags_meta[*]}]
set_max_delay -to [get_regs {g_production$g_status_uart$user_flags_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$user_flags_meta[*]}]

# DJ reuses the existing two four-phase mailboxes; both inputs are local to their source clocks.
# DFI=0, PIX=1. The matched held-bank, first synchronizer and settle boundaries are unchanged.
# Only async FIRST-stage hold is waived; stage-2 and business paths stay timed.
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/cfg_request_level[0]}] -to [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/request_sync[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/cfg_request_level[0]}] -to [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/request_sync[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/cfg_ack_meta[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/cfg_ack_meta[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_cfg_domains[*]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[0]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_cfg_domains[*]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/cfg_request_level[1]}] -to [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/request_sync[0]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/cfg_request_level[1]}] -to [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/request_sync[0]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/cfg_ack_meta[1]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/o_ack}] -to [get_regs {g_production$g_status_uart$u_observer/cfg_ack_meta[1]}]
set_max_delay -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_cfg_domains[*]}] -datapath_only 32.000
set_false_path -hold -from [get_regs {g_production$g_status_uart$u_observer/g_cfg_diag$g_domain[1]$u_snapshot/o_snapshot[*]}] -to [get_regs {g_production$g_status_uart$u_observer/report_cfg_domains[*]}]
set_max_delay -to [get_regs {g_production$g_status_uart$u_observer/cfg_reset_meta[*]}] -datapath_only 32.000
set_false_path -hold -to [get_regs {g_production$g_status_uart$u_observer/cfg_reset_meta[*]}]

# RX detailed banks and RT history are disabled in camera_raw_r1.
# OB and DJ snapshots above remain observational; no retired endpoint is constrained.
