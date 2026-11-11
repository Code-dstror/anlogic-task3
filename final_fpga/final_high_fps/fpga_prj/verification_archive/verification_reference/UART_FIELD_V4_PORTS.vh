module camera_field_diagnostics (
    input wire dfi_clk,dfi_rst_n,dfi_run,
    input wire [31:0] dfi_session,dfi_epoch,
    input wire job_fire,job_camera,input wire [31:0] job_sequence,
    input wire [1:0] begin_reject,pair_expire,bad_finish,
    input wire [7:0] bank_states,dfi_flags,
    input wire pixel_clk,pixel_rst_n,pixel_run,
    input wire [31:0] pixel_epoch,
    input wire [31:0] cfg_applied_epoch,
    input wire [15:0] cfg_flags,
    input wire [1:0] fs,
    input wire [3:0] capture_admit,
    input wire [15:0] pixel_flags,
    output wire [223:0] dfi_page,pixel_page,
    output wire [31:0] pixel_fs
);

module uart_status_observer #(
    parameter integer UART_DIV=217,
    parameter integer REPORT_INTERVAL_CYCLES=25000000,
    parameter integer SNAPSHOT_TIMEOUT_CYCLES=25000,
    parameter integer CFG_DIAG_ENABLE=0,
    parameter integer CFG_FRAME_VERSION=1,
    parameter integer JOB_PAGE_ENABLE=0,
    parameter integer JOB_SYS_CONFIG_ENABLE=0,
    parameter integer RX_DIAG_ENABLE=0,
    parameter integer RX_TRACE_ENABLE=0
) (
    input wire i_sys_clk,
    input wire i_sys_rst_n,
    input wire i_pixel_clk,
    input wire i_dfi_clk,
    input wire i_user_clk,
    input wire [2:0] i_domain_observer_rst_n,
    input wire [2:0] i_domain_reset_n,
    input wire [15:0] i_sys_status,
    input wire [35:0] i_domain_flags,
    input wire [11:0] i_domain_faults,
    input wire [5:0] i_domain_progress,
    input wire [447:0] i_cfg_domains,
    input wire [1:0] i_cfg_domain_reset_n,
    input wire [63:0] i_job_sys_config,
    input wire [31:0] i_job_pixel_fs,
    input wire i_rx_word_clk,
    input wire [383:0] i_rx_domains,
    input wire [2:0] i_rx_reset_n,
    // SYS-domain four-phase endpoint. The leaf owns ACK synchronization and
    // holds this entire bank until request returns low; it has no business ACK.
    output reg o_trace_request,
    output reg [5:0] o_trace_index,
    input wire i_trace_ack,
    input wire [319:0] i_trace_data,
    output wire o_uart_tx
);
