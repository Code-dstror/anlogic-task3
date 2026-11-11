`timescale 1ns / 1ps
`default_nettype none
`include "pcie_protocol_v1.vh"
`ifndef ANLOGIC_COMPILED_PROFILE
`define ANLOGIC_COMPILED_PROFILE 1
`endif
`ifndef ANLOGIC_SOURCE_SELECT
`define ANLOGIC_SOURCE_SELECT 0
`endif
// Independent refactor: SDR/HDR + all image algorithms + JPEG; no LZ hardware.
module anlogic2026 #(
    // Separate compile-time images. Production has no UART parser/probes.
    parameter integer DEBUG_UART_ENABLE = 0,
    // Passive production telemetry. It has no RX/control path into the app.
    parameter integer READONLY_UART_ENABLE = 1,
    parameter integer READONLY_UART_REPORT_CYCLES = 25000000,
    parameter integer DUAL_CAMERA_ENABLE = 1,
    parameter integer STEREO_CAPTURE_DIVISOR = 2,
    parameter [9:0] COLOR_CONFIG_DEFAULT = 10'h083,
    parameter [29:0] COLOR_WB_DEFAULT = {10'd832,10'd410,10'd909},
    parameter integer COMPILED_PROFILE = `ANLOGIC_COMPILED_PROFILE,
    parameter integer FRAME_WIDTH = COMPILED_PROFILE==3 ? 3840 : 1920,
    parameter integer FRAME_HEIGHT = COMPILED_PROFILE==3 ? 2160 : 1080,
    // Cold build selection: physical camera0, virtual mono, virtual stereo.
    // It changes no board port or online CFG ABI field.
    parameter integer SOURCE_SELECT = `ANLOGIC_SOURCE_SELECT,
    // Cold single-camera JPEG descriptor count; absent camera1 never aliases
    // camera0. A future dual-camera source requires its own qualified profile.
    parameter integer JPEG_CAMERA_COUNT = DUAL_CAMERA_ENABLE!=0 ? 2 : (SOURCE_SELECT==2 ? 2 : 1),
    parameter integer S3_HDR_ENABLE = 1, // FULL_HDR_APPLICATION_PROFILE
    // Stage2 control width is independent of the retained R8 resource cuts.
    parameter integer R8_FULL_CONFIG_EXTENSION_ENABLE = 1,
`ifdef R8_STAGE2_COMPACT_TRANSPORT
    parameter integer R8_STAGE2_COMPACT_TRANSPORT_ENABLE = 1,
`else
    parameter integer R8_STAGE2_COMPACT_TRANSPORT_ENABLE = 0,
`endif
`ifdef R8_F21_FIXED_CONFIG_SESSION
    parameter integer R8_F21_FIXED_CONFIG_SESSION_ENABLE = 1,
`else
    parameter integer R8_F21_FIXED_CONFIG_SESSION_ENABLE = 0,
`endif
`ifdef R8_HE_FIXED_CONFIG_SESSION
    parameter integer R8_HE_FIXED_CONFIG_SESSION_ENABLE = 1,
`else
    parameter integer R8_HE_FIXED_CONFIG_SESSION_ENABLE = 0,
`endif
    parameter integer F24_MASK_ENABLE = 0,
    parameter integer VIRTUAL0_PHASE = 0, VIRTUAL1_PHASE = 7,
    parameter integer VIRTUAL0_PERIOD = 2083333, VIRTUAL1_PERIOD = 2083333
) (
    // 板级时钟与相机串行接口
    input wire sys_clk,
    input wire board_ref_clk_100m,
    input wire mipi_clk_hs_rx_p,
    input wire [3:0] mipi_data_hs_p,
    output wire cam_scl,
    inout wire cam_sda,
    output wire cam_mclk,
    output wire cam_xclr,
    input wire mipi1_clk_hs_rx_p,input wire [3:0] mipi1_data_hs_p,
    output wire cam1_scl,inout wire cam1_sda,output wire cam1_mclk,cam1_xclr,

    // 相机状态串口
    output wire uart_tx,
    input wire uart_rx,

    // DDR 时钟、命令与双向数据
    output wire [0:0] ddr_ck_p,
    output wire [0:0] ddr_ck_n,
    output wire ddr_reset_n,
    output wire [0:0] ddr_cke,
    output wire [0:0] ddr_odt,
    output wire [0:0] ddr_cs_n,
    output wire ddr_ras_n,
    output wire ddr_cas_n,
    output wire ddr_we_n,
    output wire [2:0] ddr_ba,
    output wire [13:0] ddr_addr,
    inout wire [1:0] ddr_dqs_p,
    inout wire [1:0] ddr_dqs_n,
    inout wire [15:0] ddr_dq,
    inout wire [1:0] ddr_dm,

    // PCIe 参考时钟、复位与串行通道
    input wire refclk_p,
    input wire refclk_n,
    input wire pcie_mperst,
    input wire [0:0] rxp,
    input wire [0:0] rxn,
    output wire [0:0] txp,
    output wire [0:0] txn
);
    `include "analysis_config_transport.vh"
    // The shared estimator owns its coefficients; the legacy host LUT is unused.
    localparam integer F21_AUTO_FIXED_LUT_ENABLE = 0;
    generate if(SOURCE_SELECT!=0 || COMPILED_PROFILE!=1)begin:g_production_physical_profile
        REAL_HDR_REQUIRES_PHYSICAL_MONO_1080P invalid_production_profile();
    end endgenerate
    generate if(S3_HDR_ENABLE!=1)begin:g_requires_hdr_backend
        APPLICATION_PROFILE_REQUIRES_HDR_BACKEND invalid_hdr_profile();
    end endgenerate
`ifdef R8_STAGE1
    localparam integer R8_STAGE1_ENABLE = 1;
`else
    localparam integer R8_STAGE1_ENABLE = 0;
`endif
`ifdef R8_BASIC_PREPROCESS
    // Independent basic algorithms; all R8 cold resource cuts remain active.
    localparam integer R8_BASIC_PREPROCESS_ENABLE = R8_STAGE1_ENABLE;
`else
    localparam integer R8_BASIC_PREPROCESS_ENABLE = 0;
`endif
    // Stage2 releases only JPEG policy; all R8 cold storage/transport cuts stay.
    localparam integer R8_FIXED_JPEG_ENABLE = R8_STAGE1_ENABLE && !R8_BASIC_PREPROCESS_ENABLE;
    localparam integer R8_FULL_CONFIG_ENABLE = R8_BASIC_PREPROCESS_ENABLE && R8_FULL_CONFIG_EXTENSION_ENABLE;
    localparam integer R8_COMPACT_CONFIG_ENABLE = R8_STAGE1_ENABLE && !R8_FULL_CONFIG_ENABLE;
`ifdef S04_RAW_FRAME_STORE
    localparam integer S04_ENABLE = 1;
`else
    localparam integer S04_ENABLE = 0;
`endif
    // LIVE services do not require a full RAW frame store.
    localparam integer VIDEO_SERVICE_ENABLE = S04_ENABLE || R8_STAGE1_ENABLE;
`ifdef S08_CONFIGURED_CAPTURE
    localparam integer CONFIGURED_CAPTURE_ENABLE = VIDEO_SERVICE_ENABLE;
`else
    localparam integer CONFIGURED_CAPTURE_ENABLE = 0;
`endif
    // Compile physical private capability only for the supported NR raster.
    // Actual CFG selects stored current frames; BOOT keeps physical live SDR.
    localparam integer PRIVATE_PROCESSING_ENABLE =
        S04_ENABLE != 0 && CONFIGURED_CAPTURE_ENABLE != 0 && (SOURCE_SELECT != 0 ||
        (FRAME_WIDTH>=6 && FRAME_WIDTH<=1920 && FRAME_HEIGHT>=6 && FRAME_HEIGHT<=1080 &&
         FRAME_WIDTH%6==0 && FRAME_HEIGHT%6==0));
    localparam integer PHYSICAL_FRAME_FENCE_ENABLE =
        CONFIGURED_CAPTURE_ENABLE != 0 && (SOURCE_SELECT == 0 || SOURCE_SELECT == 3);
    generate if(R8_BASIC_PREPROCESS_ENABLE && (!S04_ENABLE || SOURCE_SELECT==2)) begin : g_invalid_basic_profile
        R8_BASIC_REQUIRES_COLD_PHYSICAL_LIVE invalid_profile();
    end endgenerate
`ifdef R8_LIVE_F21
    localparam integer LIVE_F21_ENABLE=R8_FULL_CONFIG_ENABLE;
`else
    localparam integer LIVE_F21_ENABLE=0;
`endif
    generate if(LIVE_F21_ENABLE && (FRAME_WIDTH!=1920 || FRAME_HEIGHT!=1080))begin:g_invalid_live_f21_geometry
        LIVE_F21_REQUIRES_GENERATED_HD_COORDINATES unsupported_geometry();
    end endgenerate
    // Use generated mode identifiers: SDR=0, SDR_LZ=1, HDR=2.
    localparam [2:0] REFACTOR_PRODUCT_MODES =
        (3'b001 << `PCIE_CFG_V2_MODES_MONO_SDR) | (3'b001 << `PCIE_CFG_V2_MODES_MONO_HDR);
    localparam integer RECORD_METADATA_ENABLE = CONFIGURED_CAPTURE_ENABLE;
    localparam integer CONFIG_EXT_WIDTH = 1024;
    localparam integer S07_PROCESSING_ENABLE = !R8_STAGE1_ENABLE && RECORD_METADATA_ENABLE &&
        FRAME_WIDTH>=4 && FRAME_WIDTH<=3840 && FRAME_WIDTH%4==0 &&
        FRAME_HEIGHT>=1 && FRAME_HEIGHT<=2160;
    localparam integer MASK_ENABLE = F24_MASK_ENABLE!=0 && S04_ENABLE && S07_PROCESSING_ENABLE;
    localparam [7:0] S07_CONFIG_SUPPORTED = S07_PROCESSING_ENABLE ?
        (MASK_ENABLE ? 8'hf0 : 8'hb0) : (LIVE_F21_ENABLE ? 8'h30 : 8'h00);
    localparam integer LIVE_LANE_ENABLE = LIVE_F21_ENABLE;
    localparam integer RECORD_V3_ENABLE = S07_PROCESSING_ENABLE || LIVE_LANE_ENABLE;
    localparam integer RECORD_EXTENSION_WIDTH = RECORD_V3_ENABLE ? 16384 : 1024;
    // This specialization contains the real four-client NR path only for
    // its supported raster. Physical live SDR keeps its existing specialization.
    localparam integer NR_PROCESSING_ENABLE = 0;
    // Digital exposure fixtures can qualify real LONG/SHORT slots. Physical
    // metadata remains unknown and its explicit current owner remains MONO.
    localparam integer HDR_PROCESSING_ENABLE = S3_HDR_ENABLE && PRIVATE_PROCESSING_ENABLE &&
        FRAME_WIDTH>=4 && FRAME_WIDTH<=1920 && FRAME_WIDTH%4==0 &&
        FRAME_HEIGHT>=1 && FRAME_HEIGHT<=1080;
    localparam integer PRIVATE_RAW_SAMPLE_BITS = HDR_PROCESSING_ENABLE ? 14 : 10;
    localparam [31:0] CONFIG_EXT_COMBINATIONS = HDR_PROCESSING_ENABLE && NR_PROCESSING_ENABLE ? 32'd1 : 32'd0;
    // The legacy LUT upload protocol is separate from schema2 built-in dehaze.
    localparam integer HOST_DEHAZE_LUT_ENABLE = 0;
    localparam [7:0] LEGACY_DEHAZE_SUPPORTED = 8'h00;
    localparam [5:0] SHARED_PROCESSING_ENABLES = LIVE_F21_ENABLE ? 6'h3f : 6'h3d;
    localparam [7:0] CONFIG_EXT_SUPPORTED = CONFIGURED_CAPTURE_ENABLE ?
        ( (HDR_PROCESSING_ENABLE ? 8'h04 : 8'h00) | LEGACY_DEHAZE_SUPPORTED | S07_CONFIG_SUPPORTED) : 8'h00;
    generate if(R8_STAGE2_COMPACT_TRANSPORT_ENABLE!=0 &&
        (!LIVE_F21_ENABLE || CONFIG_EXT_SUPPORTED!=8'h34 || CONFIG_EXT_COMBINATIONS!=0))begin:g_invalid_f21_transport
        F21_COMPACT_REQUIRES_EXACT_LIVE_CAPABILITY invalid_transport();
    end endgenerate
    localparam integer NEUTRAL_STATS_ENABLE = RECORD_METADATA_ENABLE &&
        FRAME_WIDTH % 6 == 0 && FRAME_HEIGHT % 6 == 0 &&
        (FRAME_WIDTH/6)*(FRAME_HEIGHT/6) <= 65535;
    localparam [7:0] RECORD_SOURCE_PHYSICAL = `PCIE_RECORD_V2_SOURCE_PHYSICAL;
    localparam [7:0] RECORD_TIME_COMMON = `PCIE_RECORD_V2_TIME_COMMON_FPGA_COUNTER_NS;
    localparam [7:0] RECORD_TIME_UNKNOWN = `PCIE_RECORD_V2_TIME_UNKNOWN;
    // The MCU row RAM pitch is in whole 16-pixel groups. The descriptor and
    // encoded SOF retain the actual width, including a partial final MCU.
    localparam integer JPEG_STORAGE_WIDTH = ((FRAME_WIDTH+15)/16)*16;
    localparam [7:0] NATIVE_FORMAT = `PCIE_RAW_FORMAT_RAW10;

    wire [63:0] physical_product_tag;
    wire [31:0] physical_event_sequence,cropped_raw_sequence;
    wire physical_event_identity_valid,cropped_raw_identity_valid;
    wire camera_source_identity_fault,physical_identity_quarantine;
    wire mono_source_recovery_quiet,physical_recovery_history_reset;
    reg source_recovery_history_pending;
    wire [1:0] physical_live_source_valid,physical_live_source_cancel;
    wire physical_live_source_frame_begin,physical_live_observation_abort,physical_live_authenticated_negative;
    wire physical_lane_owner_begin,physical_lane_source_fire,physical_lane_source_ok;
    wire [1:0] hdr_live_source_valid,hdr_live_source_cancel;
    wire hdr_frame_begin,hdr_notice_ready,hdr_product_done,hdr_product_failed;
    wire [575:0] hdr_product_context,hdr_notice_context;
    wire hdr_notice_exact=hdr_notice_context==hdr_product_context;
    wire pixel_clk, pixel_pll_lock, camera_pll_lock;
    wire stereo_mode_user,stereo_mode_pixel,stereo_mode_dfi;
    wire raw_mode_user,raw_mode_pixel,raw_mode_dfi;
    wire raw_record_valid,raw_record_ready,raw_payload_valid,raw_payload_last,raw_payload_ready;
    wire [31:0] raw_record_length;
    wire [127:0] raw_record_identity,raw_payload_data;
    wire [15:0] raw_payload_keep;
    wire raw_record_done,raw_record_ok,raw_record_drained,raw_record_cancel,raw_retire_valid,raw_retire_ready;
    wire [127:0] raw_retire_identity;
    wire raw_format_start_ready,raw_format_drained,raw_format_valid,raw_format_last,raw_format_ready;
    wire [127:0] raw_format_data;
    wire [15:0] raw_format_keep;
    wire record_cdc_ready,record_cdc_axis_ready,record_cdc_cancel,record_cdc_retire_valid;
    wire [127:0] record_cdc_retire_identity;
    wire [31:0] record_cdc_retire_status;
    wire stereo_busy_user,stereo_locked_user,stereo_start_inhibit,stereo_pause_pixel,stereo_pause_dfi;
    wire stereo_bar_write_valid,stereo_bar_read_valid,stereo_bar_read_response_valid;
    wire [11:0] stereo_bar_write_offset,stereo_bar_read_offset;
    wire [31:0] stereo_bar_write_data,stereo_bar_read_data;
    wire [3:0] stereo_bar_write_strobes;
    wire [1:0] stereo_bar_write_response,stereo_bar_read_response,cfg_service_write_response;
    wire cfg_user_transaction_idle,cfg_user_stereo_compatible;
    wire stereo_source0_idle,stereo_source1_idle,stereo_source0_fault,stereo_source1_fault;
    wire [39:0] stereo_capture0_data,stereo_capture1_data;
    wire stereo_capture0_valid,stereo_capture0_accept,stereo_capture0_sof,stereo_capture0_eol,stereo_capture0_abort,stereo_capture0_done;
    wire stereo_capture1_valid,stereo_capture1_accept,stereo_capture1_sof,stereo_capture1_eol,stereo_capture1_abort,stereo_capture1_done;
    wire [31:0] stereo_capture0_session,stereo_capture0_epoch,stereo_capture0_sequence;
    wire [31:0] stereo_capture1_session,stereo_capture1_epoch,stereo_capture1_sequence;
    wire [196:0] stereo_capture0_metadata,stereo_capture1_metadata;
    wire stereo_source0_valid,stereo_source0_ready,stereo_source0_ok,stereo_source0_camera;
    wire stereo_source1_valid,stereo_source1_ready,stereo_source1_ok,stereo_source1_camera;
    wire [31:0] stereo_source0_session,stereo_source0_epoch,stereo_source0_sequence;
    wire [31:0] stereo_source1_session,stereo_source1_epoch,stereo_source1_sequence;
    wire [7:0] stereo_source0_error,stereo_source1_error;
    wire stereo_event0_ready;
    wire stereo_job_valid,stereo_job_ready,stereo_retire_valid,stereo_retire_ready,stereo_retire_done,stereo_retire_error,stereo_empty;
    wire [383:0] stereo_job_frame;wire [63:0] stereo_job_lease,stereo_job_id,stereo_retire_id;
    wire [1:0] stereo_job_bayer;wire stereo_job_time_valid;

    // Stable product/cadence values, published by the existing cold mailbox.
    wire [7:0] stereo_divisor_user,stereo_divisor_pixel,stereo_divisor_dfi;
    wire stereo_jpeg_job_ready;
    assign stereo_job_ready=stereo_jpeg_job_ready;

    wire stereo_processing_selected;
    wire shared_processing_selected;
    wire cold_config_observe,cold_config_sof;
    wire stereo_processing_result_valid,stereo_processing_result_error;
    wire [63:0] stereo_processing_result_job;

    // Deterministic pair-bank authority; all ports below belong to DFI.
    wire pairbank_valid,pairbank_ready,pairbank_bank;
    wire [63:0] pairbank_id;
    wire pairbank_cfg_valid,pairbank_cfg_ready,pairbank_cfg_error;
    wire pairbank_release_valid,pairbank_release_ready,pairbank_release_bank;
    wire [63:0] pairbank_release_id;
    wire pairbank_directory_valid,pairbank_directory_ready;
    wire [1:0] pairbank_directory_slot;
    wire [31:0] pairbank_directory_data;
    wire [3:0] pairbank_directory_word;
    wire pairbank_directory_output_valid,pairbank_directory_last,pairbank_directory_output_ready;
    reg pairbank_enable_meta,pairbank_enable_sync;
    reg pairbank_pause_meta,pairbank_pause_sync;
    wire pairbank_stop;

    wire product_dfi_reset_n,product_dfi_data_reset_n;
    // Copy only this cold-DFI reset driver in placement; keep its release edge.
    (* max_fanout=512 *) wire hdr_identity_reset_n;
    wire product_cold_reset_n;
    wire hdr_writer_quiescent,hdr_owner_empty,hdr_scheduler_busy;
    wire hdr_ticket_hold,hdr_ticket_recovery,hdr_ticket_exhausted;
    wire [3:0] diag_scheduler_state,diag_scheduler_error;
    wire [2:0] diag_ticket_state;
    wire [3:0] diag_ticket_pixel;
    wire [7:0] diag_ticket_error;
    wire diag_member_valid,diag_member_ready;
    wire diag_job_valid,diag_job_ready;
    wire diag_retire_valid,diag_retire_ready,diag_retire_done;
    wire [2:0] diag_admission_state;
    wire camera_ref_clk, sensor_clk, sensor_hdr_clk, unused_pixel_aux;
    // Explicit global route across the board-ref PAD/DDR PLL half-chip boundary.
    // Existing DDR IP and PLL feedback bytes are preserved.
    wire board_ref_clk_100m_gclk;
    PH1_LOGIC_BUFG u_board_ref_bufg (.i(board_ref_clk_100m),
        .o(board_ref_clk_100m_gclk));
    wire dfi_clk, ddr_phy_rst_n, ddr_cal_done, ddr_app_ready;
    assign hdr_identity_reset_n=product_dfi_reset_n;
    wire user_clk, user_rst_n, user_link_up, c2h_running;
    wire [7:0] c2h_status, h2c_status;
    // The main PIX reset uses fabric routing after the reset BUFG removal.
    (* max_fanout=512 *) wire pixel_rst_n;
    wire pixel_reset_local_n, dfi_rst_n, user_session_rst_n;
    wire [6:0] pixel_data_reset_n;
    wire [7:0] transport_observe;
    wire live_f21_fault,live_lease_fault,cfg_pixel_initialized,native_pipeline_idle,physical_source_idle,physical_sdr_source_idle;
    reg source_local_pixel;
    wire admission_take;
    wire session_ddr_reset_n, session_data_reset_n, session_transport_reset_n;
    wire transport_user_reset_n, session_armed, session_rearm_required;
    wire session_rearm_ready;
    wire token_src_reset_done, token_sink_reset_done;
    wire record_src_reset_done, record_sink_reset_done;
    wire credit_request_pixel, credit_grant_pixel, credit_ack_pixel;
    wire credit_reserved_dfi, credit_fault;
    reg [1:0] armed_pixel, armed_user, rearm_ready_user, local_pixel;
    wire soft_reset, app_enable, transport_recovery;
    wire memory_fault_user,memory_owner_ready;
    reg [1:0] memory_fault_dfi=2'b11;
    // The USER and DFI clocks may start in either order. The retained fault
    // pipeline powers up asserted. Qualify it from the rising-edge cold
    // release so the ring and other DFI consumers have a full setup cycle.
    // Runtime readiness and memory incidents leave that release asserted.
    wire memory_fault_dfi_active=product_dfi_data_reset_n&&memory_fault_dfi[1];
    reg [1:0] product_fault_user;
    wire reset_pending_user,reset_pause_pixel,reset_execute_user,reset_marker_request;
    wire reset_source_proven,reset_source_fault,reset_sink_fault;
    wire [63:0] reset_raw_enqueued,reset_raw_consumed;
    wire jpeg_cdc_source_busy,jpeg_cdc_user_busy,jpeg_cdc_source_fault,jpeg_cdc_user_fault;
    wire product_transport_busy,product_buffer_armed,product_result_pending,product_axil_fault;
    wire jpeg_user_record_valid,jpeg_user_record_ready,jpeg_user_axis_valid,jpeg_user_axis_ready,jpeg_user_axis_last;
    wire [31:0] jpeg_user_record_length,jpeg_user_retire_status;
    wire [127:0] jpeg_user_record_identity,jpeg_user_axis_data,jpeg_user_retire_identity;
    wire [15:0] jpeg_user_axis_keep;
    wire jpeg_user_done_valid,jpeg_user_done_ok,jpeg_user_drained,jpeg_user_cancel;
    wire jpeg_user_retire_valid,jpeg_user_retire_ready;
    wire retire_user_fault;
    reg [63:0] pixel_ticks;
    wire [24:0] jpeg_result_length;
    wire [127:0] record_data;
    wire [15:0] record_keep;
    wire record_valid, record_ready, record_last, record_meta_ready;
    wire tx_busy, frame_accept, frame_done, frame_abort;
    wire bridge_fault, store_recovery;
    wire record_source_fault;
    wire f21_protocol_fault,f21_lut_fault;
    reg [1:0] enable_pixel;
    wire admission_protocol_fault;
    wire debug_rst_n, debug_app_rst_n, debug_local, debug_run, debug_clear;
    // Independent configuration startup authority. PERST, link, APP enable
    // and soft reset never clear DDR/native/product ownership.
    assign product_cold_reset_n=debug_rst_n&&debug_app_rst_n;
    wire debug_pixel_rst_n, debug_dfi_rst_n, debug_user_rst_n;
    wire local_stop_request,local_stop_ready,local_stop_done,local_stop_pause;
    wire local_stop_authorized;
    reset_release_sync u_debug_pixel_reset (.i_clk(pixel_clk),
        .i_async_rst_n(debug_rst_n), .o_rst_n(debug_pixel_rst_n));
    reset_release_sync u_debug_dfi_reset (.i_clk(dfi_clk),
        .i_async_rst_n(debug_rst_n), .o_rst_n(debug_dfi_rst_n));
    reset_release_sync u_debug_user_reset (.i_clk(user_clk),
        .i_async_rst_n(debug_rst_n), .o_rst_n(debug_user_rst_n));
    wire app_hard_rst_n, endpoint_rst_n, session_ready, session_fault;
    wire effective_app_enable;
    // Configuration changes only in LOCAL_IDLE while the application is reset.
    // Both clocks run independently of app reset; two destination stages settle
    // long before the 1023-cycle (25 MHz) reset hold ends. No per-frame CDC.
    // Retain the measured 2026-10-05 GBRG/gain32 and R/G/B 909/410/832 settings.
    // Runtime UART adjustment is diagnostic-image-only; CCM is not calibrated.
    wire [29:0] debug_color_wb;
    reg [29:0] color_wb_meta, color_wb_pixel;
    wire [9:0] debug_color_config;
    reg [1:0] color_phase_meta, color_phase_pixel;
    always @(posedge pixel_clk) begin
        color_phase_meta <= debug_color_config[1:0];
        color_phase_pixel <= color_phase_meta;
        color_wb_meta <= debug_color_wb;
        color_wb_pixel <= color_wb_meta;
    end
    // Sensor configuration now shares the SYS25 domain with debug_control.
    // SET_COLOR still holds the application in reset; the sequencer latches
    // gain at START, so no SENSOR24 gain crossing is needed.
    wire [7:0] color_gain_cfg=debug_color_config[9:2];

    wire [3:0] effective_fifo_done;
    wire [2:0] debug_request, debug_ack;
    wire [119:0] debug_command, debug_response;
    wire [31:0] debug_rx_errors, debug_timeouts;
    reg [1:0] local_dfi, local_user;
    fpga_debug_isolation u_debug_isolation (
        .i_clk(sys_clk), .i_debug_rst_n(debug_rst_n), .i_app_rst_n(debug_app_rst_n),
        .i_local(debug_local), .i_run(debug_run), .i_perst_n(pcie_mperst),
        .i_local_ready(pixel_pll_lock && camera_pll_lock && ddr_phy_rst_n && ddr_app_ready && memory_owner_ready),
        .i_host_ready(user_rst_n),
        .i_local_fault(1'b0),
        .i_host_fault(reset_execute_user),
        .i_host_enable(app_enable&&!reset_pending_user&&!transport_recovery),
        .i_fifo_done({record_sink_reset_done,record_src_reset_done,token_sink_reset_done,token_src_reset_done}),
        .i_rearm_ready(session_rearm_ready), .i_armed(session_armed),
        .o_hard_rst_n(app_hard_rst_n), .o_pcie_rst_n(endpoint_rst_n),
        .o_ready(session_ready), .o_fault(session_fault), .o_enable(effective_app_enable),
        .o_fifo_done(effective_fifo_done));
    always @(posedge dfi_clk or negedge debug_dfi_rst_n)
        if(!debug_dfi_rst_n) local_dfi<=2'b11;
        else local_dfi<={local_dfi[0],debug_local};
    // 汇总基础设施就绪和故障，统一控制单帧会话的复位与重新准入
    frame_session_controller u_session_ctl (
        .i_clk(sys_clk), .i_hard_reset_n(app_hard_rst_n),
        .i_infra_ready_async(session_ready),
        .i_fatal_async(session_fault),
        .i_app_enable_async(effective_app_enable),
        .i_fifo_reset_done_async(effective_fifo_done),
        .o_ddr_reset_n(session_ddr_reset_n), .o_data_reset_n(session_data_reset_n),
        .o_transport_reset_n(session_transport_reset_n),
        .o_session_armed(session_armed), .o_rearm_required(session_rearm_required),
        .o_rearm_ready(session_rearm_ready)
    );
    // 像素域与相机参考时钟分别由现有 PLL 配置产生
    sys_pll_125m_25m u_pixel_pll (.refclk(sys_clk), .reset(1'b0),
        .lock(pixel_pll_lock), .clk0_out(pixel_clk), .clk1_out(unused_pixel_aux));
    wire camera_pll_refclk;
`ifdef PH1
    // The camera PLL is outside the reference PAD's local routing sector.
    PH1_LOGIC_BUFG u_camera_ref_global (.i(sys_clk),.o(camera_pll_refclk));
`else
    assign camera_pll_refclk=sys_clk;
`endif
    imx415_sensor_pll_25m u_camera_pll (.refclk(camera_pll_refclk), .reset(1'b0),
        .lock(camera_pll_lock), .clk0_out(camera_ref_clk),
        .clk1_out(sensor_clk),.clk2_out(sensor_hdr_clk));
    // 每个时钟域独立同步释放复位，避免跨域直接解除复位
    reset_release_sync_data #(.DATA_RESET_COPIES(7)) u_pixel_reset (.i_clk(pixel_clk),
        .i_async_rst_n(session_data_reset_n && pixel_pll_lock && camera_pll_lock),
        .o_rst_n(pixel_reset_local_n),.o_data_rst_n(pixel_data_reset_n));
    // PIXEL_RESET_DISTRIBUTION_BEGIN
    // Positive-edge final copies preserve the original three-edge release.
    // Each nearby falling-edge stage releases its positive-edge consumers
    // with half a cycle of recovery/removal margin. No reset uses a BUFG.
    wire [3:0] pixel_branch_reset_n;
    wire pixel_posedge_reset_n=pixel_data_reset_n[3];
    genvar pixel_reset_branch;
    generate for(pixel_reset_branch=0;pixel_reset_branch<4;pixel_reset_branch=pixel_reset_branch+1)begin:g_pixel_reset_branch
        (* preserve="true" *) reg release_n;
        always @(negedge pixel_clk or negedge pixel_data_reset_n[pixel_reset_branch+3])begin
            if(!pixel_data_reset_n[pixel_reset_branch+3])release_n<=1'b0;
            else release_n<=1'b1;
        end
        assign pixel_branch_reset_n[pixel_reset_branch]=release_n;
    end endgenerate
    assign pixel_rst_n=pixel_branch_reset_n[0];
    // PIXEL_RESET_DISTRIBUTION_END
    reset_release_sync u_dfi_reset (.i_clk(dfi_clk),
        .i_async_rst_n(session_data_reset_n && ddr_phy_rst_n),
        .o_rst_n(dfi_rst_n));
    reset_release_sync u_user_reset (.i_clk(user_clk),
        .i_async_rst_n(session_data_reset_n && user_rst_n),
        .o_rst_n(user_session_rst_n));
    reset_release_sync u_transport_reset (.i_clk(user_clk),
        .i_async_rst_n(session_transport_reset_n && user_rst_n),
        .o_rst_n(transport_user_reset_n));
    // 将会话准入状态同步到像素域
    always @(posedge pixel_clk or negedge pixel_rst_n)
        if (!pixel_rst_n) begin armed_pixel <= 0; local_pixel <= 2'b11; end
        else begin
            armed_pixel <= {armed_pixel[0],session_armed};
            local_pixel <= {local_pixel[0],debug_local};
        end
    // 将会话和恢复状态同步到 PCIe 用户域
    always @(posedge user_clk or negedge user_session_rst_n)
        if (!user_session_rst_n) begin
            armed_user <= 0;
            rearm_ready_user <= 0;
            local_user <= 2'b11;
        end else begin
            armed_user <= {armed_user[0],session_armed};
            rearm_ready_user <= {rearm_ready_user[0],session_rearm_ready};
            local_user <= {local_user[0],debug_local};
        end


    // S04 RAW occupies a disjoint 128 MiB arena behind the existing DDR IP.
    wire [3:0] raw_axi_awid;
    wire [27:0] raw_axi_awaddr;
    wire [7:0] raw_axi_awlen;
    wire [2:0] raw_axi_awsize;
    wire [1:0] raw_axi_awburst;
    wire raw_axi_awvalid;
    wire raw_axi_awready;
    wire [127:0] raw_axi_wdata;
    wire [15:0] raw_axi_wstrb;
    wire raw_axi_wlast;
    wire raw_axi_wvalid;
    wire raw_axi_wready;
    wire [3:0] raw_axi_bid;
    wire [1:0] raw_axi_bresp;
    wire raw_axi_bvalid;
    wire raw_axi_bready;
    wire [3:0] raw_axi_arid;
    wire [27:0] raw_axi_araddr;
    wire [7:0] raw_axi_arlen;
    wire [2:0] raw_axi_arsize;
    wire [1:0] raw_axi_arburst;
    wire raw_axi_arvalid;
    wire raw_axi_arready;
    wire [3:0] raw_axi_rid;
    wire [127:0] raw_axi_rdata;
    wire [1:0] raw_axi_rresp;
    wire raw_axi_rlast;
    wire raw_axi_rvalid;
    wire raw_axi_rready;
    wire [3:0] capture_axi_awid;
    wire [27:0] capture_axi_awaddr;
    wire [7:0] capture_axi_awlen;
    wire [2:0] capture_axi_awsize;
    wire [1:0] capture_axi_awburst;
    wire capture_axi_awvalid;
    wire capture_axi_awready;
    wire [127:0] capture_axi_wdata;
    wire [15:0] capture_axi_wstrb;
    wire capture_axi_wlast;
    wire capture_axi_wvalid;
    wire capture_axi_wready;
    wire [3:0] capture_axi_bid;
    wire [1:0] capture_axi_bresp;
    wire capture_axi_bvalid;
    wire capture_axi_bready;
    wire [3:0] capture_axi_arid;
    wire [27:0] capture_axi_araddr;
    wire [7:0] capture_axi_arlen;
    wire [2:0] capture_axi_arsize;
    wire [1:0] capture_axi_arburst;
    wire capture_axi_arvalid;
    wire capture_axi_arready;
    wire [3:0] capture_axi_rid;
    wire [127:0] capture_axi_rdata;
    wire [1:0] capture_axi_rresp;
    wire capture_axi_rlast;
    wire capture_axi_rvalid;
    wire capture_axi_rready;
    wire [3:0] hdr_reader_axi_arid;
    wire [27:0] hdr_reader_axi_araddr;
    wire [7:0] hdr_reader_axi_arlen;
    wire [2:0] hdr_reader_axi_arsize;
    wire [1:0] hdr_reader_axi_arburst;
    wire hdr_reader_axi_arvalid;
    wire hdr_reader_axi_arready;
    wire [3:0] hdr_reader_axi_rid;
    wire [127:0] hdr_reader_axi_rdata;
    wire [1:0] hdr_reader_axi_rresp;
    wire hdr_reader_axi_rlast;
    wire hdr_reader_axi_rvalid;
    wire hdr_reader_axi_rready;
    // Both readers run on DFI. Only the existing post-merge RAW14 transport
    // crosses to PIX; the one RAW10 decoder needs no new CDC or descriptor RAM.
    wire hdr_decode_start,hdr_decode_start_ready,hdr_decode_release;
    wire [1:0] hdr_decode_abort,hdr_decode_done,hdr_decode_aborted;
    wire hdr_decode_member,hdr_decode_valid,hdr_decode_last,hdr_decode_ready;
    wire [127:0] hdr_decode_data;wire [15:0] hdr_decode_keep;
    wire [39:0] hdr_decode_raw;
    wire hdr_decode_raw_member,hdr_decode_raw_valid,hdr_decode_raw_ready;
    wire stereo_decode_start,stereo_decode_start_ready,stereo_decode_release;
    wire stereo_decode_cancel,stereo_decode_run,stereo_decode_valid,stereo_decode_last,stereo_decode_ready;
    wire [127:0] stereo_decode_data;wire [15:0] stereo_decode_keep;
    wire [39:0] stereo_decode_raw;
    wire stereo_decode_raw_valid,stereo_decode_raw_ready,stereo_decode_sof,stereo_decode_eol;
    wire stereo_decode_done,stereo_decode_aborted,stereo_decode_quiet,stereo_decode_active;
    wire raw_route_sdr,raw_mode_busy,raw_mode_applied,raw_policy_admit,raw_region_quiet;
    reg jpeg_native_bound;
    wire raw_bayer_valid;

    wire raw_bar_write_valid, raw_bar_read_valid, raw_bar_read_response_valid;
    wire [11:0] raw_bar_write_offset, raw_bar_read_offset;
    wire [31:0] raw_bar_write_data, raw_bar_read_data;
    wire [3:0] raw_bar_write_strobes;
    wire [1:0] raw_bar_write_response, raw_bar_read_response;
    wire [39:0] cropped_raw_data, replay_raw_data;
    wire cropped_raw_valid, cropped_raw_ready, cropped_raw_sof, cropped_raw_eol, cropped_raw_abort;
    wire replay_active, replay_raw_valid, replay_raw_ready, replay_raw_sof, replay_raw_eol, replay_raw_abort;
    wire replay_pipeline_safe, replay_admission_ready;
    // Source-domain enqueue/admission and DFI consume/write fences stay distinct.
    wire raw_capture0_enqueue_fire,raw_capture1_enqueue_fire;
    wire raw_capture0_consume_fire,raw_capture1_consume_fire;
    wire raw_capture0_idle,raw_capture1_idle;
    wire raw_capture0_frame_accept,raw_capture1_frame_accept;
    wire raw_capture_write_quiescent;
    wire raw_private_ownership_quiescent;
    wire [39:0] capture0_data,capture1_data;
    wire capture0_valid,capture0_accept,capture0_sof,capture0_eol,capture0_abort;
    wire capture1_valid,capture1_accept,capture1_sof,capture1_eol,capture1_abort;
    wire [31:0] capture0_session,capture0_sequence,capture0_epoch;
    wire [31:0] capture1_session,capture1_sequence,capture1_epoch;
    wire [196:0] capture0_metadata,capture1_metadata;
    wire camera_hdr_mode,camera_mode_running,camera_hdr_stable,hdr_cycle_quiet;
    wire rx_diag_word_clk;
    wire [1:0] field_hdr_reject,field_hdr_expire,field_sdr_reject,field_sdr_bad,field_cam1_admit;
    wire [3:0] field_hdr_bad;wire [7:0] field_hdr_banks;
    wire [127:0] rx_diag_word,rx_diag_cfg,rx_diag_cfg1;
    wire [31:0] rx_diag_good,rx_diag_bad,rx_diag_not_admitted,rx_diag_pair;
    wire [47:0] rx_diag_counts;
    assign rx_diag_good={16'd0,rx_diag_counts[15:0]};
    assign rx_diag_bad={16'd0,rx_diag_counts[31:16]};
    assign rx_diag_not_admitted={16'd0,rx_diag_counts[47:32]};
    wire [383:0] rx_diag_domains={rx_diag_pair,rx_diag_not_admitted,rx_diag_bad,rx_diag_good,rx_diag_cfg,rx_diag_word};
    wire [159+CONFIG_EXT_WIDTH:0] capture0_active_config;
    // PIX and DFI each use their locally committed copy of the same configuration.
    wire physical_hdr_requested=analysis_hdr_enabled(capture0_active_config[1183:160]);
    wire stereo_hdr_pixel=stereo_mode_pixel && physical_hdr_requested;
    wire stereo_sdr_pixel=stereo_mode_pixel && !physical_hdr_requested;
    wire stored_sdr_pixel=(stereo_mode_pixel||raw_mode_pixel)&&!physical_hdr_requested;
    // Each physical eye has its own CSI lifecycle. Member 0 is LONG and member 1
    // is SHORT. Only this eye's clean member completions can qualify its pair.
    wire cam1_hdr_mode,cam1_hdr_mode_running,cam1_hdr_stable,cam1_hdr_cycle_quiet;
    wire cam1_hdr_pair_event,cam1_hdr_pair_ok;
    wire [146:0] cam1_hdr_token0,cam1_hdr_token1;
    wire [1:0] cam1_hdr_token_valid,cam1_hdr_token_ready;
    wire [79:0] cam1_hdr_data;
    wire [1:0] cam1_hdr_valid,cam1_hdr_sof,cam1_hdr_eol,cam1_hdr_abort;
    wire [63:0] cam1_hdr_sequence;
    wire [31:0] cam1_hdr_session,cam1_hdr_epoch;
    wire [393:0] cam1_hdr_metadata;
    wire [1:0] cam1_hdr_source_valid,cam1_hdr_source_ok;
    wire [63:0] cam1_hdr_source_session,cam1_hdr_source_epoch,cam1_hdr_source_sequence;
    wire [15:0] cam1_hdr_source_error;
    wire [1:0] cam1_hdr_source_ready,cam1_hdr_idle;
    wire [146:0] hdr_token0,hdr_token1;
    wire hdr_token0_valid,hdr_token1_valid,hdr_token0_ready,hdr_token1_ready,hdr_pair_event,hdr_pair_ok;
    wire [39:0] hdr_capture0_data,hdr_capture1_data,sdr_capture0_data;
    wire hdr_capture0_valid,hdr_capture1_valid,hdr_capture0_sof,hdr_capture1_sof,hdr_capture0_eol,hdr_capture1_eol,hdr_capture0_abort,hdr_capture1_abort;
    wire sdr_capture0_valid,sdr_capture0_accept,sdr_capture0_sof,sdr_capture0_eol,sdr_capture0_eof,sdr_capture0_abort;
    wire [31:0] hdr_capture0_sequence,hdr_capture1_sequence,hdr_capture_session,hdr_capture_epoch,sdr_capture0_session,sdr_capture0_epoch,sdr_capture0_sequence;
    wire [196:0] hdr_capture0_metadata,hdr_capture1_metadata,sdr_capture0_metadata;
    wire hdr_source0_valid,hdr_source1_valid,hdr_source0_ready,hdr_source1_ready,hdr_source_ok;
    wire [31:0] hdr_source_session,hdr_source_epoch,hdr_source0_sequence,hdr_source1_sequence;
    wire [7:0] hdr_source_error,hdr_source1_error;
    wire [31:0] hdr_source1_session,hdr_source1_epoch;
    wire hdr_source1_ok;

    wire [1023:0] capture0_algorithm_extension=analysis_algorithm_extension(capture0_active_config[1183:160]);
    wire capture0_schema2=capture0_active_config[167:160]==`PCIE_CFG_V2_SCHEMA;
    wire capture0_filter_gray=capture0_schema2 ? capture0_active_config[170] :
        capture0_active_config[65:64]==1||capture0_active_config[65:64]==2;
    wire capture0_filter_legacy=!capture0_schema2&&capture0_active_config[65:64]==2;
    wire [159+CONFIG_EXT_WIDTH:0] capture_config_data,whole_config_ack_data;
    wire capture_config_valid,capture_config_ready;
    wire whole_config_ack_valid,whole_config_ack_ready,whole_config_ack_ok;
    wire [159+CONFIG_EXT_WIDTH:0] frontend_config_ack_data;
    wire frontend_config_ack_valid,frontend_config_ack_ready,frontend_config_ack_ok;
    wire [159+CONFIG_EXT_WIDTH:0] online_config_data,online_config_ack_data;
    wire [159+CONFIG_EXT_WIDTH:0] dfi_active_config,dfi_pending_config;
    wire dfi_active_hdr;
    wire [1023:0] dfi_algorithm_extension=analysis_algorithm_extension(dfi_active_config[1183:160]);
    wire stereo_hdr_dfi=stereo_mode_dfi && dfi_active_hdr;
    wire stereo_sdr_dfi=stereo_mode_dfi && !stereo_hdr_dfi;
    wire stored_sdr_dfi=stereo_sdr_dfi||raw_mode_dfi;
    wire [1023:0] dfi_pending_algorithm_extension=analysis_algorithm_extension(dfi_pending_config[1183:160]);
    wire cfs_protocol_fault;
    wire online_config_valid,online_config_ready;
    wire online_config_ack_valid,online_config_ack_ready,online_config_ack_ok;
    wire configured_source_ready,configured_source_pause;
    wire [63:0] common_pixel_time_ns,common_dfi_time_ns;
    wire common_pixel_time_valid,common_dfi_time_valid;
    wire capture_frontend_fault,source_bootstrap_fault;
    wire capture_config_reset_done;
    wire raw_job_config_valid,raw_job_config_ready,raw_job_config_done;
    wire raw_job_config_error,raw_job_config_busy,raw_job_config_fault;
    wire raw_job_source_config_fault;
    wire [31:0] record_source_active_session,record_source_active_epoch;
    wire record_source_active_valid;
    wire record_pixel_quiescent_dfi;
    wire record_dfi_data_quiescent,record_dfi_select_quiescent;
    wire [31:0] raw_job_config_session,raw_job_config_epoch;
    wire [1:0] raw_job_config_mode;
    wire raw_job_config_mono;
    wire [63:0] raw_job_config_max_delta;
    wire [31:0] raw_job_config_max_wait,raw_job_config_max_age;
    wire raw_processing_quiescent,raw_processing_fault;
    wire raw_processing_idle_pixel;
    wire raw_commit_valid,raw_commit_ready,raw_ref_valid,raw_ref_ready,raw_reference_fault;
    wire [1:0] raw_ref_op,raw_ref_mask;
    wire raw_ref_store_ready,ddr_arbiter_fault;
    // The store applies candidate->job only at its atomic F_APPLY handshake.
    // Gate both endpoints there; existing candidate/job RELEASE still drains.
    wire raw_ref_acquire_allowed=raw_ref_op!=2'd1 || !ddr_arbiter_fault;
    assign raw_ref_ready=raw_ref_store_ready && raw_ref_acquire_allowed;
    wire nr_writer_ack_valid,nr_writer_ack_ready,nr_writer_start_permitted,nr_start_fire;
    wire nr_private_writer_start_permitted;
    wire private_writer_required=PRIVATE_PROCESSING_ENABLE!=0 && (stereo_mode_dfi || SOURCE_SELECT!=0 || dfi_active_hdr);
    wire nr_writer_required=NR_PROCESSING_ENABLE!=0 && private_writer_required;
    assign nr_writer_start_permitted=!nr_writer_required||nr_private_writer_start_permitted;
    wire nr_result_valid,nr_result_ok,nr_result_current_ok,nr_result_capture_ok,nr_result_history_commit;
    wire [383:0] nr_result_frame;
    wire [63:0] nr_result_tag,nr_result_key,nr_result_aux;
    wire [7:0] nr_result_error;
    wire [31:0] nr_result_input_pixels,nr_result_output_pixels;
    wire nr_history_selected,nr_observation_ok,nr_motion_qualified,nr_read_quiescent;
    wire f21_cfg_begin_valid,f21_cfg_begin_ready,f21_cfg_valid,f21_cfg_ready;
    wire f21_cfg_commit_valid,f21_cfg_commit_ready,f21_cfg_abort;
    wire f21_cfg_status_valid,f21_cfg_status_ready,f21_cfg_status_ok;
    wire [31:0] f21_cfg_generation,f21_cfg_status_generation;
    wire [8:0] f21_cfg_index;
    wire [10:0] f21_cfg_value;
    wire [7:0] f21_cfg_status_error;
    wire f21_lut_valid,f21_owned_lut_valid,f21_lut_update_busy,f21_lut_update_inhibit;
    wire [31:0] f21_lut_generation,f21_owned_lut_generation;
    wire f21_busy,f21_read_quiescent;
    wire f21_start_eligible,f21_fence_valid,f21_fence_ok;
    wire [575:0] f21_fence_identity;
    wire [7:0] f21_fence_error;
    wire [31:0] f21_fence_pixels;
    wire f21_history_used,f21_metadata_bypass,f21_map_commit;
    wire [31:0] f21_frame_lut_generation,f21_map_commit_frame;
    wire f21_core_reset_n,f21_core_async_reset_n;
    // cfg_begin_ready additionally closes the independent observer map scan.
    // The existing RAW/job owners close NR publication. Its per-frame SOURCE
    // read-quiet is false before the first owner, so it cannot gate BOOT.
    wire f21_pipeline_quiet=HOST_DEHAZE_LUT_ENABLE==0 ||
        (!f21_busy && f21_read_quiescent &&
         f21_cfg_begin_ready && !f21_protocol_fault && !f21_lut_fault);
    wire live_f21_rst_n,live_f21_frame_quiet,live_f21_maintenance_quiet;
    wire live_lease_inhibit,live_lease_busy;
    wire [1:0] live_source_valid,live_source_ready,live_source_match,live_source_skip;
    wire [1:0] live_source_cancel,live_source_cancel_done,live_source_accepted;
    wire live_observation_abort,live_source_frame_begin,live_authenticated_negative;
    wire live_source_block=LIVE_F21_ENABLE &&
        (!f21_core_async_reset_n || !f21_core_reset_n || f21_lut_update_busy || live_lease_busy || live_lease_fault || live_f21_fault || f21_lut_fault);
    generate if(LIVE_F21_ENABLE)begin:g_live_f21_reset
        reset_release_sync u_reset(.i_clk(pixel_clk),
            .i_async_rst_n(pixel_rst_n&&dfi_rst_n&&(source_local_pixel||user_session_rst_n)),.o_rst_n(live_f21_rst_n));
    end else begin:g_no_live_f21_reset
        assign live_f21_rst_n=pixel_rst_n;assign live_f21_frame_quiet=1;assign live_f21_maintenance_quiet=1;
        assign live_f21_fault=0;assign live_lease_inhibit=0;assign live_lease_busy=0;assign live_lease_fault=0;
        assign live_source_ready=0;assign live_source_match=0;assign live_source_skip=0;
        assign live_source_cancel_done=0;assign live_source_accepted=0;
    end endgenerate
    wire f21_load_permitted;
    wire f21_load_available=LIVE_F21_ENABLE ?
        (cfg_pixel_initialized&&!source_local_pixel&&live_f21_maintenance_quiet&&native_pipeline_idle&&
         physical_source_idle&&!live_lease_inhibit&&!live_lease_fault&&!live_f21_fault) :
        record_dfi_data_quiescent && record_source_active_valid &&
        !raw_job_config_valid && !raw_job_config_done && !raw_job_config_busy &&
        !f21_lut_update_inhibit;
    wire algo_bar_write_valid,algo_bar_read_valid,algo_bar_read_response_valid;
    wire [11:0] algo_bar_write_offset,algo_bar_read_offset;
    wire [31:0] algo_bar_write_data,algo_bar_read_data;
    wire [3:0] algo_bar_write_strobes;
    wire [1:0] algo_bar_write_response,algo_bar_read_response;
    wire [1:0] nr_history_valid;
    wire [383:0] raw_commit_frame,raw_ref_frame0,raw_ref_frame1,raw_member_frame;
    wire [63:0] raw_commit_lease,raw_ref_lease0,raw_ref_lease1,raw_ref_job_id;
    wire [3:0] nr_rgb_axi_awid,nr_rgb_axi_arid,nr_rgb_axi_bid,nr_rgb_axi_rid;
    wire [27:0] nr_rgb_axi_awaddr,nr_rgb_axi_araddr;
    wire [7:0] nr_rgb_axi_awlen,nr_rgb_axi_arlen;
    wire [2:0] nr_rgb_axi_awsize,nr_rgb_axi_arsize;
    wire [1:0] nr_rgb_axi_awburst,nr_rgb_axi_arburst,nr_rgb_axi_bresp,nr_rgb_axi_rresp;
    wire nr_rgb_axi_awvalid,nr_rgb_axi_awready,nr_rgb_axi_wvalid,nr_rgb_axi_wready;
    wire nr_rgb_axi_wlast,nr_rgb_axi_bvalid,nr_rgb_axi_bready;
    wire nr_rgb_axi_arvalid,nr_rgb_axi_arready,nr_rgb_axi_rvalid,nr_rgb_axi_rready,nr_rgb_axi_rlast;
    wire [127:0] nr_rgb_axi_wdata,nr_rgb_axi_rdata;
    wire [15:0] nr_rgb_axi_wstrb;
    wire [3:0] nr_map_axi_awid,nr_map_axi_arid,nr_map_axi_bid,nr_map_axi_rid;
    wire [27:0] nr_map_axi_awaddr,nr_map_axi_araddr;
    wire [7:0] nr_map_axi_awlen,nr_map_axi_arlen;
    wire [2:0] nr_map_axi_awsize,nr_map_axi_arsize;
    wire [1:0] nr_map_axi_awburst,nr_map_axi_arburst,nr_map_axi_bresp,nr_map_axi_rresp;
    wire nr_map_axi_awvalid,nr_map_axi_awready,nr_map_axi_wvalid,nr_map_axi_wready;
    wire nr_map_axi_wlast,nr_map_axi_bvalid,nr_map_axi_bready;
    wire nr_map_axi_arvalid,nr_map_axi_arready,nr_map_axi_rvalid,nr_map_axi_rready,nr_map_axi_rlast;
    wire [127:0] nr_map_axi_wdata,nr_map_axi_rdata;
    wire [15:0] nr_map_axi_wstrb;
    wire raw_private_req_valid,raw_private_req_ready,raw_private_req_camera;
    wire [2:0] raw_private_req_op;
    wire [1:0] raw_private_req_slot;
    wire [31:0] raw_private_req_generation,raw_private_req_session;
    wire [63:0] raw_private_req_lease,raw_private_req_job_id,raw_member_pair_id;
    wire raw_member_index,raw_read_quiescent;
    wire raw_private_rsp_valid,raw_private_rsp_ready,raw_private_rsp_camera;
    wire [3:0] raw_private_rsp_code;
    wire [1:0] raw_private_rsp_slot;
    wire [31:0] raw_private_rsp_generation,raw_private_rsp_session,raw_private_rsp_sequence,raw_private_rsp_epoch;
    wire raw_private_native_done,raw_private_native_error,raw_private_native_member;
    wire [63:0] raw_private_native_job;
    wire raw_replay_context_valid,raw_replay_context_ready,raw_replay_context_private,raw_replay_context_member;
    wire [383:0] raw_replay_context_frame;
    wire [63:0] raw_replay_context_job,raw_replay_context_pair;
    wire raw_replay_protocol_fault,raw_replay_native_done,raw_replay_native_error;
    wire processing_context_ready,processing_context_owned,processing_pixel_reset_done,processing_pixel_fault;
    wire processing_pixel_busy;
    wire processing_event_fault;
    wire processing_pool_idle,processing_replay_payload_enable,processing_context_available;
    wire private_context_fire,physical_fs_take,pixel_context_request;
    wire processing_sof_fire,processing_writer_start_fire;
    wire processing_source_valid,processing_source_ready,processing_source_error;
    wire [383:0] processing_frame,processing_source_frame;
    wire [63:0] processing_lease,processing_job_id,processing_pair_id;
    wire [63:0] processing_source_lease,processing_source_job,processing_source_pair,processing_source_tag;
    wire processing_member,processing_source_member;
    wire [31:0] processing_write_tag;
    wire writer_ack_valid,writer_ack_ready,writer_ack_ok,writer_ack_camera;
    wire [7:0] writer_ack_error;
    wire [31:0] writer_ack_tag,writer_ack_sequence,writer_ack_session,writer_ack_epoch;
    wire [15:0] writer_ack_slot;
    wire [31:0] writer_ack_generation;
    wire [24:0] debug_writer_ack_length;
    wire [15:0] debug_writer_allocation_slot;
    wire [31:0] debug_writer_allocation_generation;
    wire private_writer_ack_valid,private_writer_ack_ready;
    // The private job reuses the existing camera ISP. Its native SOURCE and
    // processed SOURCE remain separate, complete ownership boundaries.
    wire [4*PRIVATE_RAW_SAMPLE_BITS-1:0] private_isp_raw;
    wire private_isp_raw_valid,private_isp_raw_sof,private_isp_raw_eol,private_isp_raw_ready;
    wire private_isp_reset_n,private_isp_hdr_enable;
    wire [3:0] private_isp_tone_shift;
    wire hdr_phase_request,hdr_phase_owned,hdr_processing_selected;
    reg [1:0] hdr_phase_pixel;
    wire [146:0] hdr_fifo_source,hdr_fifo_sink;
    wire hdr_fifo_source_valid,hdr_fifo_source_ready,hdr_fifo_sink_valid,hdr_fifo_sink_ready;
    wire hdr_fifo_source_reset_done,hdr_fifo_sink_reset_done;
    wire raw_public_read_quiescent;
    wire [383:0] raw_private_rsp_descriptor;
    wire raw_private_rsp_metadata_valid;
    wire [127:0] raw_private_read_data;
    wire [15:0] raw_private_read_keep;
    wire raw_private_read_valid,raw_private_read_last,raw_private_read_ready;
    wire raw_private_read_complete,raw_private_read_error,raw_private_read_fault;
    wire normal_private_req_valid,normal_private_req_ready,normal_private_req_camera;
    wire [2:0] normal_private_req_op;
    wire [1:0] normal_private_req_slot;
    wire [31:0] normal_private_req_generation,normal_private_req_session;
    wire [63:0] normal_private_req_lease,normal_private_req_job_id;
    wire normal_private_rsp_ready;
    wire hdr_private_req_valid,hdr_private_req_ready,hdr_private_req_camera;
    wire [2:0] hdr_private_req_op;
    wire [1:0] hdr_private_req_slot;
    wire [31:0] hdr_private_req_generation,hdr_private_req_session,hdr_private_req_offset,hdr_private_req_length;
    wire [63:0] hdr_private_req_lease,hdr_private_req_job_id;
    wire hdr_private_rsp_ready;
    wire [383:0] hdr_job_frame0,hdr_job_frame1;
    wire [63:0] hdr_job_id,hdr_pair_id,hdr_job_lease0,hdr_job_lease1;
    wire hdr_context_valid,hdr_context_ready,hdr_start_valid,hdr_start_ready,hdr_cancel_valid,hdr_cancel_ready;
    wire hdr_transport_enable,hdr_result_valid,hdr_result_ready,hdr_result_ok;
    wire [7:0] hdr_result_error;
    wire [63:0] hdr_long_tag,hdr_short_tag;
    wire hdr_reader_fault,hdr_source_fault,hdr_pixel_fault,hdr_reader_quiet,hdr_source_reset_done;
    wire [575:0] hdr_pixel_context;
    wire hdr_pixel_context_valid,hdr_pixel_context_ready;
    wire [95:0] hdr_raw_capsule;
    wire hdr_raw_valid,hdr_raw_ready,hdr_raw_sof,hdr_raw_eol;
    wire hdr_raw_source_valid,hdr_raw_source_ready,hdr_raw_source_ok;
    wire [63:0] hdr_raw_source_tag;
    wire [7:0] hdr_raw_source_error;
    wire [55:0] replay_raw14;
    genvar raw_lane;
    generate for(raw_lane=0;raw_lane<4;raw_lane=raw_lane+1)begin:g_replay_raw14
        assign replay_raw14[14*raw_lane+:14]={4'd0,replay_raw_data[10*raw_lane+:10]};
    end endgenerate
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)hdr_phase_pixel<=0;
        else hdr_phase_pixel<={hdr_phase_pixel[0],hdr_phase_owned};
    end
    assign hdr_processing_selected=HDR_PROCESSING_ENABLE!=0 && hdr_phase_pixel[1];
    assign shared_processing_selected=hdr_processing_selected||stereo_processing_selected;
    assign stereo_processing_selected=stereo_sdr_pixel&&!raw_mode_pixel&&processing_pixel_busy;
    assign raw_private_req_valid=hdr_phase_owned ? hdr_private_req_valid : normal_private_req_valid;
    assign raw_private_req_op=hdr_phase_owned ? hdr_private_req_op : normal_private_req_op;
    assign raw_private_req_camera=hdr_phase_owned ? hdr_private_req_camera : normal_private_req_camera;
    assign raw_private_req_slot=hdr_phase_owned ? hdr_private_req_slot : normal_private_req_slot;
    assign raw_private_req_generation=hdr_phase_owned ? hdr_private_req_generation : normal_private_req_generation;
    assign raw_private_req_session=hdr_phase_owned ? hdr_private_req_session : normal_private_req_session;
    assign raw_private_req_lease=hdr_phase_owned ? hdr_private_req_lease : normal_private_req_lease;
    assign raw_private_req_job_id=hdr_phase_owned ? hdr_private_req_job_id : normal_private_req_job_id;
    assign raw_private_rsp_ready=hdr_phase_owned ? hdr_private_rsp_ready : normal_private_rsp_ready;
    assign normal_private_req_ready=!hdr_phase_owned && raw_private_req_ready;
    assign hdr_private_req_ready=hdr_phase_owned && raw_private_req_ready;
    wire [95:0] private_rgb;
    wire private_rgb_valid,private_rgb_ready,private_rgb_sof,private_rgb_eol;
    wire private_notice_valid,private_notice_ok,private_isp_cleanup;
    wire [7:0] private_notice_error;
    wire private_pp_reset_n,private_pp_error;
    wire private_jpeg_source_done,private_jpeg_source_error;
    wire private_no_work_complete;
    wire advanced_abort_request,advanced_abort_fire;
    wire physical_advanced_abort_request,physical_advanced_abort_fire;
    wire [95:0] preprocess_input_rgb;
    wire preprocess_input_valid,preprocess_input_sof,preprocess_input_eol;
    wire preprocess_input_ready;
    wire record_writer_ack_valid,record_writer_ack_ready;
    wire record_metadata_fault,record_metadata_quiescent;
    wire record_ordered_source_fault,record_builder_fault;
    wire record_ordered_fault;
    reg record_replay_binding_fault;
    wire record_builder_ready;
    wire [2047:0] record_source_extension;
    wire [RECORD_EXTENSION_WIDTH-1:0] record_dfi_extension,record_header_extension;
    wire [127:0] record_extension_stream_data;
    wire record_extension_stream_valid,record_extension_stream_ready,record_extension_stream_start;
    wire lane_read_enable,lane_read_valid;
    wire [8:0] lane_read_index;
    wire [39:0] lane_read_data;
    wire preprocess_records_quiet,advanced_cfg_ready,advanced_join_ready;
    wire lane_capacity_ready,lane_quiet,lane_fault,lane_owner_begin,lane_source_fire,lane_source_ok;
    wire lane_tap_ready,lane_tap_valid,lane_tap_available,lane_tap_sof,lane_tap_eol;
    wire [287:0] lane_tap_window;
    wire [31:0] lane_tap_luma;
    wire live_history_used,live_lane_product_owned;
    wire live_filter_start,live_filter_start_ready,live_filter_source_error;
    wire live_filter_complete,live_filter_error;
    wire [159:0] live_filter_terminal_context;
    wire live_filter_f22_ready,live_filter_f23_ready;
    wire advanced_terminal_valid,advanced_terminal_error;
    wire [159:0] advanced_terminal_context;
    wire advanced_f22_valid,advanced_f23_valid,advanced_f24_valid,advanced_f25_valid;
    wire advanced_f22_pending;
    wire advanced_f22_ready,advanced_f23_ready,advanced_f24_ready,advanced_f25_ready;
    wire [683:0] advanced_f22_record;
    wire [176:0] advanced_f23_record;
    wire [207:0] advanced_f24_record;
    wire [264:0] advanced_f25_record;
    wire [3:0] advanced_job_features;
    wire advanced_f24_join_valid,advanced_f24_join_ready;
    wire mask_morph_valid,mask_morph_ready,mask_morph_sof,mask_morph_eol,mask_morph_eof;
    wire [3:0] mask_morph,mask_morph_keep;
    wire [12:0] mask_morph_x,mask_morph_y,mask_morph_width,mask_morph_height;
    wire [159:0] mask_morph_context;
    wire mask_begin_ready,mask_source_quiet,mask_writer_quiet,mask_export_quiet,mask_export_fault;
    wire mask_allocation_valid,mask_allocation_ready,mask_result_valid,mask_result_ready,mask_result_ok;
    wire [15:0] mask_allocation_slot,mask_result_slot;
    wire [31:0] mask_allocation_generation,mask_result_tag,mask_result_generation;
    wire [27:0] mask_allocation_base;
    wire [24:0] mask_allocation_bytes;
    wire [159:0] mask_result_context;
    wire [7:0] mask_result_error;
    wire [12:0] mask_result_width,mask_result_height;
    wire [16:0] mask_result_written_bytes;
    wire [207:0] mask_result_terminal;
    wire [133:0] mask_command;
    wire mask_command_valid,mask_command_ready,mask_response_valid,mask_response_ready;
    wire mask_block_valid,mask_block_ready,mask_cache_retire,mask_owner_complete;
    wire [146:0] mask_response,mask_block;
    wire mask_ring_req_valid,mask_ring_req_ready,mask_ring_req_target,mask_ring_req_lock,mask_ring_req_camera;
    wire [1:0] mask_ring_req_op;
    wire [15:0] mask_ring_req_slot;
    wire [31:0] mask_ring_req_generation,mask_ring_req_session;
    wire mask_ring_rsp_valid,mask_ring_rsp_ready,mask_ring_read_release,mask_ring_read_active;
    wire mask_metadata_req_valid,mask_metadata_req_ready,mask_metadata_req_camera;
    wire [15:0] mask_metadata_req_slot;
    wire [31:0] mask_metadata_req_generation,mask_metadata_req_session,mask_metadata_req_epoch,mask_metadata_req_sequence;
    wire mask_metadata_rsp_valid,mask_metadata_rsp_ready,mask_metadata_rsp_ok,mask_metadata_rsp_camera,mask_metadata_rsp_qualified;
    wire [7:0] mask_metadata_rsp_error;
    wire [15:0] mask_metadata_rsp_slot;
    wire [31:0] mask_metadata_rsp_generation,mask_metadata_rsp_session,mask_metadata_rsp_epoch,mask_metadata_rsp_sequence;
    wire [23:0] mask_metadata_rsp_pixels;
    wire [2:0] mask_metadata_rsp_type;
    wire ddr_start_mask;
    wire [2:0] ddr_start_source_type;
    reg admitted_mask;
    reg [2:0] admitted_source_type;
    wire [159:0] mask_allocation_context;
    wire [3:0] mask_axi_awid,mask_axi_bid,mask_axi_arid,mask_axi_rid;
    wire [27:0] mask_axi_awaddr,mask_axi_araddr;
    wire [7:0] mask_axi_awlen,mask_axi_arlen;
    wire [2:0] mask_axi_awsize,mask_axi_arsize;
    wire [1:0] mask_axi_awburst,mask_axi_arburst,mask_axi_bresp,mask_axi_rresp;
    wire mask_axi_awvalid,mask_axi_awready,mask_axi_wlast,mask_axi_wvalid,mask_axi_wready;
    wire mask_axi_bvalid,mask_axi_bready,mask_axi_arvalid,mask_axi_arready,mask_axi_rlast,mask_axi_rvalid,mask_axi_rready;
    wire [127:0] mask_axi_wdata,mask_axi_rdata;
    wire [15:0] mask_axi_wstrb;
    wire mask_axi_quiet,mask_axi_fault,ring_control_quiet;
    // Disabled optional consumers must never hold the common LIVE owner.
    generate if(MASK_ENABLE==0) begin : g_no_mask
        assign mask_begin_ready=1'b1;
        assign mask_source_quiet=1'b1;
        assign mask_morph_ready=1'b1;
        assign advanced_f24_join_valid=advanced_f24_valid;
        assign advanced_f24_ready=advanced_f24_join_ready;
        assign mask_command_ready=1'b0;
        assign mask_response_valid=1'b0;
        assign mask_response=147'd0;
        assign mask_block_valid=1'b0;
        assign mask_block=147'd0;
        assign mask_owner_complete=1'b0;
    end endgenerate
    wire record_source_extension_valid,record_source_extension_ready;
    wire record_dfi_extension_valid,record_dfi_extension_ready;
    wire record_extension_shape_valid,record_extension_read_enable;
    wire [8:0] record_extension_read_index;
    wire [39:0] record_extension_read_data;
    wire record_header_ready,record_start_reserved,record_formatter_abort;
    wire ring_start_valid,ring_start_ready,ring_request_ready;
    wire record_ring_quiescent,record_formatter_busy;
    wire [15:0] record_selected_version_user,record_selected_version_dfi;
    wire record_format_busy,record_format_user_ready,record_format_dfi_ready;
    wire record_bar_write_valid,record_bar_read_valid,record_bar_read_response_valid;
    wire [11:0] record_bar_write_offset,record_bar_read_offset;
    wire [31:0] record_bar_write_data,record_bar_read_data;
    wire [3:0] record_bar_write_strobes;
    wire [1:0] record_bar_write_response,record_bar_read_response;
    reg [1:0] record_format_busy_pixel,record_idle_user,record_source_valid_user;
    reg [63:0] record_product_next_tag,record_admitted_write_tag;
    reg [31:0] record_writer_next_tag,record_admitted_writer_tag;
    reg record_product_advance_pending,record_writer_advance_pending;
    reg record_product_tag_exhausted,record_writer_tag_exhausted;
    wire record_product_available=RECORD_METADATA_ENABLE==0 ||
        (record_builder_ready&&(lane_capacity_ready||!lane_quiet)&&!record_product_tag_exhausted&&
         (PRIVATE_PROCESSING_ENABLE!=0 || !record_writer_tag_exhausted));
    wire host_replay_context_valid,host_replay_context_ready,host_replay_metadata_valid;
    wire [383:0] host_replay_context_frame;
    reg host_replay_context_owned,host_replay_saved_metadata_valid;
    reg [383:0] host_replay_saved_frame;
    // MODE is a cold strap. These two registers run throughout application
    // reset, so the source bootstrap sees its settled choice on release.
    reg source_local_meta;
    always @(posedge pixel_clk) begin
        source_local_meta<=debug_local;
        source_local_pixel<=source_local_meta;
    end
`ifdef R8_LIVE_F21_SIM_METADATA
    // Explicit bench provider enters the actual SOF metadata owner, never a status.
    reg simulation_f21_known=0;
    reg [31:0] simulation_f21_exposure=1000,simulation_f21_gain=256;
    wire [196:0] physical_metadata_input=simulation_f21_known ?
        {1'b1,1'b1,2'd0,1'b1,32'd0,32'd1,simulation_f21_gain,simulation_f21_exposure,common_pixel_time_ns} :
        {133'd0,common_pixel_time_ns};
`else
    wire [196:0] physical_metadata_input={133'd0,common_pixel_time_ns};
`endif
    wire native_job_start,native_job_idle,native_job_replay;
    wire cfg_source_ready,cfg_pause,cfg_user_initialized,capture_config_apply_fault;
    wire [1:0] cfg_mode;
    wire [7:0] cfg_quality,cfg_min_quality,selected_quality;
    wire cfg_adaptive;
    wire [24:0] cfg_budget;
    wire [15:0] cfg_restart;
    wire [31:0] cfg_session,cfg_epoch,cfg_user_session;
    wire he_history_reset_n;
    wire cfg_pipeline_idle;
    wire [11:0] cfg_apply_diagnostics;
    wire physical_admit_enable,physical_frame_enable;
    wire capture0_geometry_done;
    wire physical_raw_source_valid,physical_raw_source_ready,physical_raw_source_ok,physical_raw_source_camera;
    wire [31:0] physical_raw_source_session,physical_raw_source_epoch,physical_raw_source_sequence;
    wire [7:0] physical_raw_source_error;
    wire physical_native_source_valid,physical_native_source_ready,physical_native_source_ok;
    wire [575:0] physical_native_source_context;
    wire [63:0] physical_native_source_tag;
    wire [7:0] physical_native_source_error;
    wire physical_event_valid,mono_physical_event_ready,physical_event_ok;
    wire [1:0] physical_event_kind;
    wire [3:0] physical_event_error;
    wire physical_processing_rst_n,physical_processing_data_rst_n;
    wire private_pp_data_rst_n;
    wire [31:0] native_next_sequence;
    wire native_identity_event=(cropped_raw_valid && cropped_raw_ready && cropped_raw_sof) ||
        (CONFIGURED_CAPTURE_ENABLE==0 && native_job_start && native_job_replay);
    native_frame_descriptor u_native_descriptor (
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_native_valid(native_identity_event),
        .i_native_ready(1'b1),.i_native_sof(1'b1),.i_session_id(cfg_session),
        .i_mode_epoch(cfg_epoch),.i_camera_id(1'b0),.i_format(NATIVE_FORMAT),
        .i_width(FRAME_WIDTH[15:0]),.i_height(FRAME_HEIGHT[15:0]),.i_sample_count(FRAME_WIDTH*FRAME_HEIGHT),
        .i_timestamp_ns(pixel_ticks),.o_next_sequence(native_next_sequence),
        .o_frame_sequence(),.o_descriptor_valid(),.o_session_id(),.o_mode_epoch(),.o_camera_id(),
        .o_format(),.o_width(),.o_height(),.o_sample_count(),.o_timestamp_ns(),.o_job_handle());
    wire cfg_bar_write_valid,cfg_bar_read_valid,cfg_bar_read_response_valid;
    wire [11:0] cfg_bar_write_offset,cfg_bar_read_offset;
    wire [31:0] cfg_bar_write_data,cfg_bar_read_data;
    wire [3:0] cfg_bar_write_strobes;
    wire [1:0] cfg_bar_write_response,cfg_bar_read_response;
    // Diagnostic-only CFG facts. These nets terminate exclusively at UART.
    wire [447:0] cfg_diag_domains,cfg_diag_core_domains;
    wire [4:0] cfg_diag_admission_faults;
    // CG/V2 adds five live PIX causes in formerly reserved flag bits. These
    // loads terminate at the existing held snapshot bank; no business feedback.
    assign cfg_diag_domains={cfg_diag_core_domains[447:415],
        cfg_diag_admission_faults,cfg_diag_core_domains[409:0]};
    wire [1:0] cfg_diag_domain_reset_n;
    wire cfg_diag_source_fs;
    wire [15:0] cfg_diag_source_gates;
    generate if(VIDEO_SERVICE_ENABLE!=0) begin : g_config
        wire online_ready,online_pause,online_adaptive,online_initialized,local_initialized;
        wire config_pixel_reset_n;
        reset_release_sync u_config_pixel_reset(.i_clk(pixel_clk),
            .i_async_rst_n(pixel_rst_n&&(!R8_FULL_CONFIG_ENABLE||dfi_rst_n)&&(!LIVE_F21_ENABLE||f21_core_async_reset_n)),
            .o_rst_n(config_pixel_reset_n));
        wire [1:0] online_mode;
        wire [7:0] online_quality,online_minimum;
        wire [24:0] online_budget;
        wire [15:0] online_restart;
        wire [31:0] online_session,online_epoch;
        // LOCAL can diagnose pixel/DDR with the endpoint held in reset.
        // A cold MODE change resets jobs before selecting the online BOOT tuple.
        assign cfg_source_ready=CONFIGURED_CAPTURE_ENABLE!=0 ?
            configured_source_ready&&!raw_job_source_config_fault :
            local_pixel[1] || online_ready;
        assign cfg_pause=CONFIGURED_CAPTURE_ENABLE!=0 ?
            configured_source_pause||raw_job_source_config_fault :
            !local_pixel[1] && online_pause;
        assign cfg_mode=local_pixel[1] ? 2'd0 : online_mode;
        assign cfg_quality=local_pixel[1] ? 8'd75 : online_quality;
        assign cfg_adaptive=!local_pixel[1] && online_adaptive;
        assign cfg_min_quality=local_pixel[1] ? 8'd1 : online_minimum;
        assign cfg_budget=local_pixel[1] ? 25'd0 : online_budget;
        assign cfg_restart=local_pixel[1] ? 16'd0 : online_restart;
        assign cfg_session=local_pixel[1] ? 32'd1 : online_session;
        assign cfg_epoch=local_pixel[1] ? 32'd0 : online_epoch;
        // These are actual local owner facts, not DFI active or source READY.
        assign cfg_pixel_initialized=CONFIGURED_CAPTURE_ENABLE!=0 ?
            (source_local_pixel ? local_initialized : online_initialized) :
            (!local_pixel[1] && online_initialized);
        // A physical SDR frame uses the cropped stream's real acceptance.
        // The optional RAW store is disabled for that path. Stored SDR and
        // physical HDR use the actual primary RAW ingress admission instead
        // of a sensor offer; new shared processing need not be idle at this edge.
        wire configured_frame_accept=PHYSICAL_FRAME_FENCE_ENABLE!=0&&
            !physical_hdr_requested&&!stored_sdr_pixel ?
            capture0_valid&&capture0_accept&&capture0_sof :
            raw_capture0_frame_accept&&(physical_hdr_requested ?
                camera_hdr_mode&&hdr_capture0_metadata[196]&&hdr_capture0_metadata[195]&&hdr_capture0_metadata[194:193]==1 :
                !camera_hdr_mode);
        assign cfg_bar_write_response=(stereo_busy_user||raw_mode_user)?2'b10:cfg_service_write_response;
        mono_config_service_v2 #(.STEREO_CAPABLE(DUAL_CAMERA_ENABLE),.CFG_DIAG_ENABLE(0),
            .APPLY_SOURCE_FAULT_ENABLE(CONFIGURED_CAPTURE_ENABLE!=0&&SOURCE_SELECT==0),
            .V2_SUPPORTED_MODES(REFACTOR_PRODUCT_MODES),.V2_SUPPORTED_ENABLES(SHARED_PROCESSING_ENABLES),.LANE_GAUSSIAN_ONLY(1),.PROFILE(COMPILED_PROFILE),.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
            .LIVE_GRAY_FIXED_ENABLE(R8_FIXED_JPEG_ENABLE),
            .LIVE_BASIC_MODES_ENABLE(R8_BASIC_PREPROCESS_ENABLE),
            .COMPACT_EMPTY_EXTENSION_ENABLE(R8_COMPACT_CONFIG_ENABLE),
            .COMPACT_STAGE2_EXTENSION_ENABLE(R8_STAGE2_COMPACT_TRANSPORT_ENABLE),
            .REMOTE_CONFIG_ENABLE(CONFIGURED_CAPTURE_ENABLE),.EXT_WIDTH(CONFIG_EXT_WIDTH),
            .EXT_COMBINATIONS(CONFIG_EXT_COMBINATIONS),.EXT_SUPPORTED(CONFIG_EXT_SUPPORTED)) u_config (
            .user_clk(user_clk),.user_rst_n(user_rst_n),.pixel_clk(pixel_clk),
            .pixel_rst_n(config_pixel_reset_n),
            .i_stereo_mode(stereo_mode_user),.o_user_transaction_idle(cfg_user_transaction_idle),.o_user_stereo_compatible(cfg_user_stereo_compatible),
            .write_valid(cfg_bar_write_valid&&!stereo_busy_user&&!raw_mode_user),.write_offset(cfg_bar_write_offset),.write_data(cfg_bar_write_data),
            .write_strobes(cfg_bar_write_strobes),.write_response(cfg_service_write_response),
            .read_valid(cfg_bar_read_valid),.read_offset(cfg_bar_read_offset),.read_response_valid(cfg_bar_read_response_valid),
            .read_data(cfg_bar_read_data),.read_response(cfg_bar_read_response),
            // Whole drain remains strict. The new admitted SOF is also the
            // engine's one actual APPLIED boundary, before native work begins.
            .pipeline_idle(cfg_pipeline_idle || (PHYSICAL_FRAME_FENCE_ENABLE!=0 &&
                configured_frame_accept&&native_pipeline_idle&&!replay_active&&
                 (physical_hdr_requested ?
                    (camera_hdr_mode&&hdr_capture0_metadata[196]&&hdr_capture0_metadata[195]&&hdr_capture0_metadata[194:193]==1) :
                    (!camera_hdr_mode&&(stored_sdr_pixel||physical_frame_enable))))),
            .frame_accept(CONFIGURED_CAPTURE_ENABLE!=0 ? configured_frame_accept||cold_config_sof : native_job_start),
            .i_apply_source_fault(capture_config_apply_fault),
            .frame_sequence(CONFIGURED_CAPTURE_ENABLE!=0 ? (cold_config_observe ? cropped_raw_sequence : capture0_sequence) : native_next_sequence),
            .source_ready(online_ready),.pause_new_jobs(online_pause),.active_mode(online_mode),
            .active_quality(online_quality),.adaptive_quality(online_adaptive),.minimum_quality(online_minimum),
            .frame_budget(online_budget),.restart_mcus(online_restart),.source_session(online_session),
            .mode_epoch(online_epoch),.active_config(),.active_schema2(),.active_legacy_gaussian(),.active_product_mode(),.active_processing_enables(),.user_session(cfg_user_session),.user_initialized(cfg_user_initialized),
            .pixel_initialized(online_initialized),
            .m_config_data(online_config_data),.m_config_valid(online_config_valid),.m_config_ready(online_config_ready),
            .s_config_ack_data(online_config_ack_data),.s_config_ack_valid(online_config_ack_valid),.s_config_ack_ok(online_config_ack_ok),
            .s_config_ack_ready(online_config_ack_ready),.config_fault(),.config_stale_ack_count(),
            .diag_observer_rst_n({debug_pixel_rst_n,debug_user_rst_n}),
            .diag_source_fs(cfg_diag_source_fs),.diag_source_gates(cfg_diag_source_gates),
            .diag_domains(cfg_diag_core_domains),.diag_domain_reset_n(cfg_diag_domain_reset_n),
            .o_apply_diagnostics(cfg_apply_diagnostics));
        if(CONFIGURED_CAPTURE_ENABLE!=0) begin : g_source_bootstrap
            wire local_fault,mode_fault;
            wire bootstrap_pixel_rst_n;
            // The DFI reset asserts this cohort asynchronously, but release
            // must use pixel edges before it participates in source READY.
            reset_release_sync u_pixel_reset(.i_clk(pixel_clk),
                .i_async_rst_n(pixel_rst_n&&dfi_rst_n),.o_rst_n(bootstrap_pixel_rst_n));
            assign he_history_reset_n=bootstrap_pixel_rst_n;
            frame_source_config_bootstrap #(.EXT_WIDTH(CONFIG_EXT_WIDTH)) u_bootstrap(
                .clk(pixel_clk),.rst_n(bootstrap_pixel_rst_n),.i_local(source_local_pixel),
                .i_transport_reset_done(capture_config_reset_done),
                .s_online_config_data(online_config_data),.s_online_config_valid(online_config_valid),
                .s_online_config_ready(online_config_ready),
                .m_online_ack_data(online_config_ack_data),.m_online_ack_valid(online_config_ack_valid),
                .m_online_ack_ok(online_config_ack_ok),.m_online_ack_ready(online_config_ack_ready),
                .i_online_source_ready(online_ready),.i_online_pause_new_frames(online_pause),
                .m_source_config_data(capture_config_data),.m_source_config_valid(capture_config_valid),
                .m_source_config_ready(capture_config_ready),
                .s_whole_ack_data(whole_config_ack_data),.s_whole_ack_valid(whole_config_ack_valid),
                .s_whole_ack_ok(whole_config_ack_ok),.s_whole_ack_ready(whole_config_ack_ready),
                .o_source_ready(configured_source_ready),.o_pause_new_frames(configured_source_pause),
                .o_local_initialized(local_initialized),.o_local_fault(local_fault),.o_mode_fault(mode_fault),
                .o_stale_ack_count(),.o_local_config());
            assign source_bootstrap_fault=local_fault||mode_fault;
        end else begin : g_legacy_source_config
            assign he_history_reset_n=pixel_rst_n;
            assign local_initialized=0;
            assign online_config_ready=0;assign online_config_ack_data=0;
            assign online_config_ack_valid=0;assign online_config_ack_ok=0;
            assign capture_config_data=0;assign capture_config_valid=0;
            assign whole_config_ack_ready=0;assign configured_source_ready=0;
            assign configured_source_pause=1;assign source_bootstrap_fault=0;
        end
    end else begin : g_legacy_config
        assign cfg_user_transaction_idle=0;assign cfg_user_stereo_compatible=0;assign cfg_service_write_response=2'b10;
        assign cfg_diag_core_domains=448'd0;assign cfg_diag_domain_reset_n=2'd0;
        assign cfg_apply_diagnostics=12'd0;
        assign he_history_reset_n=pixel_rst_n;
        assign cfg_pixel_initialized=0;
        assign cfg_source_ready=1;assign cfg_pause=0;assign cfg_mode=0;
        assign cfg_quality=75;assign cfg_adaptive=0;assign cfg_min_quality=1;assign cfg_budget=0;assign cfg_restart=0;
        assign cfg_session=1;assign cfg_epoch=1;assign cfg_user_session=1;assign cfg_user_initialized=1;
        assign cfg_bar_write_response=2'b10;assign cfg_bar_read_response=2'b10;
        assign cfg_bar_read_response_valid=0;assign cfg_bar_read_data=0;
        assign online_config_data=0;assign online_config_valid=0;assign online_config_ready=0;
        assign online_config_ack_data=0;assign online_config_ack_valid=0;
        assign online_config_ack_ok=0;assign online_config_ack_ready=0;
        assign capture_config_data=0;assign capture_config_valid=0;
        assign whole_config_ack_ready=0;assign configured_source_ready=0;
        assign configured_source_pause=1;assign source_bootstrap_fault=0;
    end endgenerate
    wire capture_terminal_ready;
    assign physical_raw_source_ready=camera_hdr_mode?1'b1:capture_terminal_ready;
    assign stereo_source0_ready=stored_sdr_pixel&&capture_terminal_ready;
    assign stereo_source1_ready=stored_sdr_pixel&&hdr_source1_ready;
    assign hdr_source0_ready=camera_hdr_mode?capture_terminal_ready:1'b1;
    generate if(CONFIGURED_CAPTURE_ENABLE!=0) begin : g_configured_capture
        wire [1:0] source_fault,dfi_fault;
        reg old_pipeline_idle_meta,old_pipeline_idle_sync;
        assign record_pixel_quiescent_dfi=old_pipeline_idle_sync;
        // PREPARE/COMMIT keeps future SOFs paused while this stable drain
        // level crosses. Private jobs additionally use the actual DFI owners.
        always @(posedge dfi_clk or negedge dfi_rst_n) begin
            if(!dfi_rst_n) begin old_pipeline_idle_meta<=0;old_pipeline_idle_sync<=0;end
            else begin old_pipeline_idle_meta<=cfg_pipeline_idle;old_pipeline_idle_sync<=old_pipeline_idle_meta;end
        end
        physical_configured_capture_frontend #(.SOURCE_SELECT(SOURCE_SELECT),
            .PRESET_MONO_ENABLE(1),
            .JOINT_CONFIG_OWNER_ENABLE(1),
            .TRUSTED_INPUT(1),
            .DEST0_SAME_CLOCK(R8_STAGE1_ENABLE),.DEST1_SAME_CLOCK(R8_STAGE1_ENABLE),
            .EXT_WIDTH(CONFIG_EXT_WIDTH),.EXT_COMBINATIONS(CONFIG_EXT_COMBINATIONS),.EXT_SUPPORTED(CONFIG_EXT_SUPPORTED),
            .PHYSICAL_FRAME_FENCE_ENABLE(PHYSICAL_FRAME_FENCE_ENABLE),
            .WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),
            .VIRTUAL0_PHASE(VIRTUAL0_PHASE),.VIRTUAL1_PHASE(VIRTUAL1_PHASE),
            .VIRTUAL0_PERIOD(VIRTUAL0_PERIOD),.VIRTUAL1_PERIOD(VIRTUAL1_PERIOD)) u_frontend(
            .i_pixel_clk(pixel_clk),.i_pixel_rst_n(pixel_rst_n),
            // The absent physical camera1 still has a running digital CFG owner.
            .i_capture1_clk(pixel_clk),.i_capture1_rst_n(pixel_rst_n),
            .i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n),
            .s_config_data(capture_config_data),.s_config_valid(capture_config_valid),.s_config_ready(capture_config_ready),
            .m_config_ack_data(frontend_config_ack_data),.m_config_ack_valid(frontend_config_ack_valid),
            .m_config_ack_ok(frontend_config_ack_ok),.m_config_ack_ready(frontend_config_ack_ready),
            .i_source_ready(cfg_source_ready),.i_pause_new_frames(cfg_pause || local_stop_pause || reset_pause_pixel || stereo_pause_pixel),
            .i_physical_data(cropped_raw_data),.i_physical_valid(cropped_raw_valid&&!stereo_mode_pixel&&!raw_mode_pixel),
            .i_physical_accept(cropped_raw_ready),.i_physical_sof(cropped_raw_sof),
            .i_physical_eol(cropped_raw_eol),.i_physical_abort(cropped_raw_abort),
            // SOF time is observed; physical exposure/gain/calibration and
            // exposure qualification remain explicitly unknown here.
            .i_physical_metadata(physical_metadata_input),
            .i_physical_sequence(cropped_raw_sequence),.i_physical_identity_valid(cropped_raw_identity_valid),
            .i_physical_frame_enable(physical_frame_enable),.i_physical_source_idle(physical_source_idle),
            .o_physical_admit_enable(physical_admit_enable),
            .i_capture0_enqueue_fire(raw_capture0_enqueue_fire),.i_capture1_enqueue_fire(raw_capture1_enqueue_fire),
            .i_capture0_consume_fire(raw_capture0_consume_fire),.i_capture1_consume_fire(raw_capture1_consume_fire),
            .i_capture0_idle(raw_capture0_idle),.i_capture1_idle(raw_capture1_idle),
            .i_capture0_frame_accept(raw_capture0_frame_accept),.i_capture1_frame_accept(raw_capture1_frame_accept),
            .i_capture_write_quiescent(raw_capture_write_quiescent),
            .i_old_processing_quiescent(PRIVATE_PROCESSING_ENABLE!=0 ?
                raw_private_ownership_quiescent&&raw_processing_quiescent&&f21_pipeline_quiet : old_pipeline_idle_sync),
            .i_virtual0_enable(1'd0),
            .i_virtual0_abort_now(1'd0),
            .i_virtual0_drop_frame(1'd0),
            .i_virtual0_bad_eol(1'd0),
            .i_virtual0_abort_frame(1'd0),
            .i_virtual0_pattern(2'd0),
            .i_virtual0_exposure_role(2'd0),
            .i_virtual0_seed(16'd0),
            .i_virtual0_bad_line(16'd0),
            .i_virtual0_abort_after_groups(32'd0),
            .i_virtual0_actual_exposure(32'd0),
            .i_virtual0_gain(32'd0),
            .i_virtual0_calibration_id(32'd0),
            .i_virtual0_exposure_group(32'd0),
            .i_virtual0_metadata_valid(1'd0),
            .i_virtual0_source_qualified(1'd0),
            .o_capture0_data(sdr_capture0_data),.o_capture0_valid(sdr_capture0_valid),.o_capture0_accept(sdr_capture0_accept),
            .o_capture0_sof(sdr_capture0_sof),.o_capture0_eol(sdr_capture0_eol),
            .o_capture0_eof(sdr_capture0_eof),.o_capture0_abort(sdr_capture0_abort),
            .o_capture0_session(sdr_capture0_session),.o_capture0_sequence(sdr_capture0_sequence),.o_capture0_epoch(sdr_capture0_epoch),
            .o_capture0_metadata(sdr_capture0_metadata),.o_capture0_frame_accept(),.o_capture0_source_idle(),
            .o_active_config0(capture0_active_config),.o_enqueued_count0(reset_raw_enqueued),.o_consumed_count0(reset_raw_consumed),
            .i_virtual1_enable(1'd0),
            .i_virtual1_abort_now(1'd0),
            .i_virtual1_drop_frame(1'd0),
            .i_virtual1_bad_eol(1'd0),
            .i_virtual1_abort_frame(1'd0),
            .i_virtual1_pattern(2'd0),
            .i_virtual1_exposure_role(2'd0),
            .i_virtual1_seed(16'd0),
            .i_virtual1_bad_line(16'd0),
            .i_virtual1_abort_after_groups(32'd0),
            .i_virtual1_actual_exposure(32'd0),
            .i_virtual1_gain(32'd0),
            .i_virtual1_calibration_id(32'd0),
            .i_virtual1_exposure_group(32'd0),
            .i_virtual1_metadata_valid(1'd0),
            .i_virtual1_source_qualified(1'd0),
            .o_capture1_data(),.o_capture1_valid(),.o_capture1_accept(),
            .o_capture1_sof(),.o_capture1_eol(),.o_capture1_eof(),.o_capture1_abort(),
            .o_capture1_session(),.o_capture1_sequence(),.o_capture1_epoch(),
            .o_capture1_metadata(),.o_capture1_frame_accept(),.o_capture1_source_idle(),
            .o_active_config1(),.o_enqueued_count1(),.o_consumed_count1(),
            .o_pixel_time_ns(common_pixel_time_ns),.o_pixel_time_valid(common_pixel_time_valid),
            .o_capture1_time_ns(),.o_capture1_time_valid(),.o_dfi_time_ns(common_dfi_time_ns),.o_dfi_time_valid(common_dfi_time_valid),
            .o_initialized(),.o_source_fault(source_fault),.o_dfi_fault(dfi_fault),.o_local_reset_done(),
            .o_config_reset_done(capture_config_reset_done),.o_config_busy(),.o_stale_ack_count());
        assign capture0_data=stored_sdr_pixel?stereo_capture0_data:camera_hdr_mode?hdr_capture0_data:sdr_capture0_data;
        assign capture0_valid=stored_sdr_pixel?stereo_capture0_valid:camera_hdr_mode?hdr_capture0_valid:sdr_capture0_valid;
        assign capture0_sof=stored_sdr_pixel?stereo_capture0_sof:camera_hdr_mode?hdr_capture0_sof:sdr_capture0_sof;
        assign capture0_eol=stored_sdr_pixel?stereo_capture0_eol:camera_hdr_mode?hdr_capture0_eol:sdr_capture0_eol;
        assign capture0_abort=stored_sdr_pixel?stereo_capture0_abort:camera_hdr_mode?hdr_capture0_abort:sdr_capture0_abort;
        assign capture0_session=stored_sdr_pixel?stereo_capture0_session:camera_hdr_mode?hdr_capture_session:sdr_capture0_session;
        assign capture0_epoch=stored_sdr_pixel?stereo_capture0_epoch:camera_hdr_mode?hdr_capture_epoch:sdr_capture0_epoch;
        assign capture0_sequence=stored_sdr_pixel?stereo_capture0_sequence:camera_hdr_mode?hdr_capture0_sequence:sdr_capture0_sequence;
        assign capture0_metadata=stored_sdr_pixel?stereo_capture0_metadata:camera_hdr_mode?hdr_capture0_metadata:sdr_capture0_metadata;
        assign capture0_accept=stored_sdr_pixel?stereo_capture0_accept:camera_hdr_mode?1'b1:sdr_capture0_accept;assign capture0_geometry_done=stored_sdr_pixel?stereo_capture0_done:camera_hdr_mode?1'b0:sdr_capture0_eof;
        assign capture1_data=stored_sdr_pixel?stereo_capture1_data:hdr_capture1_data;
        assign capture1_valid=stored_sdr_pixel?stereo_capture1_valid:camera_hdr_mode&&hdr_capture1_valid;
        assign capture1_sof=stored_sdr_pixel?stereo_capture1_sof:hdr_capture1_sof;
        assign capture1_eol=stored_sdr_pixel?stereo_capture1_eol:hdr_capture1_eol;
        assign capture1_abort=stored_sdr_pixel?stereo_capture1_abort:hdr_capture1_abort;
        assign capture1_session=stored_sdr_pixel?stereo_capture1_session:hdr_capture_session;
        assign capture1_epoch=stored_sdr_pixel?stereo_capture1_epoch:hdr_capture_epoch;
        assign capture1_sequence=stored_sdr_pixel?stereo_capture1_sequence:hdr_capture1_sequence;
        assign capture1_metadata=stored_sdr_pixel?stereo_capture1_metadata:hdr_capture1_metadata;
        assign capture1_accept=stored_sdr_pixel?stereo_capture1_accept:1'b1;

        // Each drain already synchronizes its sticky DFI fault and latches
        // source_fault locally. Both MAIN receiver clocks are pixel_clk.
        // Raw DFI flags must not drive pixel admission or the CSI RAM CSB.
        assign capture_frontend_fault=(|source_fault);
        if(PRIVATE_PROCESSING_ENABLE!=0 || RECORD_METADATA_ENABLE!=0) begin : g_job_config
            wire source_fault,dfi_fault;
            localparam integer JOB_EXT_WIDTH=R8_STAGE2_COMPACT_TRANSPORT_ENABLE ? MONO_EXTENSION_BITS :
                (R8_COMPACT_CONFIG_ENABLE ? 1 : CONFIG_EXT_WIDTH);
            wire [159+JOB_EXT_WIDTH:0] compact_frontend_ack;
            wire [159+JOB_EXT_WIDTH:0] compact_whole_ack,compact_active,compact_pending;
            // Only the cold compact specialization reconstructs the empty
            // extension; the full profile preserves all1184 tuple bits.
            wire job_front_valid,job_front_ready,job_front_ok,job_ack_valid,job_ack_ready,job_ack_ok;
            if(LIVE_F21_ENABLE)begin:g_pixel_lut_lease
                wire [1183:0] lease_front_data,lease_request_data,lease_return_data,lease_ack_data;
                wire lease_front_valid,lease_front_ok,lease_front_ready;
                wire lease_ack_valid,lease_ack_ok,lease_ack_ready;
                if(R8_STAGE2_COMPACT_TRANSPORT_ENABLE)begin:g_narrow_boundary
                    mono_config_narrow_gate_v2 #(.TRUSTED_INPUT(1),.LEGACY_SUPPORTED(CONFIG_EXT_SUPPORTED),.V2_SUPPORTED_MODES(REFACTOR_PRODUCT_MODES),.V2_SUPPORTED_ENABLES(SHARED_PROCESSING_ENABLES),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),.LANE_GAUSSIAN_ONLY(1)) u_gate(
                        .s_frontend_data(frontend_config_ack_data),.s_frontend_valid(frontend_config_ack_valid),
                        .s_frontend_ok(frontend_config_ack_ok),.s_frontend_ready(frontend_config_ack_ready),
                        .m_lease_data(lease_front_data),.m_lease_valid(lease_front_valid),.m_lease_ok(lease_front_ok),
                        .m_lease_ready(lease_front_ready),.i_lease_busy(live_lease_busy),
                        .s_lease_ack_data(lease_ack_data),.s_lease_ack_valid(lease_ack_valid),.s_lease_ack_ok(lease_ack_ok),
                        .s_lease_ack_ready(lease_ack_ready),.m_ack_data(whole_config_ack_data),
                        .m_ack_valid(whole_config_ack_valid),.m_ack_ok(whole_config_ack_ok),.m_ack_ready(whole_config_ack_ready),
                        .m_schema2(),.m_legacy_gaussian(),.m_product_mode(),.m_processing_enables(),.m_algorithm_parameters());
                    assign compact_frontend_ack=mono_pack_tuple(lease_request_data);
                    assign lease_return_data=mono_unpack_tuple(compact_whole_ack);
                end else begin:g_full_boundary
                    assign lease_front_data=frontend_config_ack_data;
                    assign lease_front_valid=frontend_config_ack_valid;assign lease_front_ok=frontend_config_ack_ok;
                    assign frontend_config_ack_ready=lease_front_ready;
                    assign compact_frontend_ack=lease_request_data;assign lease_return_data=compact_whole_ack;
                    assign whole_config_ack_data=lease_ack_data;assign whole_config_ack_valid=lease_ack_valid;
                    assign whole_config_ack_ok=lease_ack_ok;assign lease_ack_ready=whole_config_ack_ready;
                end
                // No LUT owner exists in this image. Keep the existing
                // compact whole-config request/ACK boundary as direct wires.
                assign lease_request_data=lease_front_data;
                assign job_front_valid=lease_front_valid;assign job_front_ok=lease_front_ok;
                assign lease_front_ready=job_front_ready;
                assign lease_ack_data=lease_return_data;assign lease_ack_valid=job_ack_valid;
                assign lease_ack_ok=job_ack_ok;assign job_ack_ready=lease_ack_ready;
                assign live_lease_inhibit=0;assign live_lease_busy=0;assign live_lease_fault=0;
            end else begin:g_no_pixel_lut_lease
                assign compact_frontend_ack=frontend_config_ack_data[159+JOB_EXT_WIDTH:0];
                assign job_front_valid=frontend_config_ack_valid;assign job_front_ok=frontend_config_ack_ok;
                assign frontend_config_ack_ready=job_front_ready;
                assign whole_config_ack_data=compact_whole_ack;assign whole_config_ack_valid=job_ack_valid;
                assign whole_config_ack_ok=job_ack_ok;assign job_ack_ready=whole_config_ack_ready;
            end
            if(R8_STAGE2_COMPACT_TRANSPORT_ENABLE)begin:g_expand_dfi_policy
                assign dfi_active_config=mono_unpack_tuple(compact_active);
                assign dfi_pending_config=mono_unpack_tuple(compact_pending);
            end else begin:g_original_dfi_policy
                assign dfi_active_config=compact_active;
                assign dfi_pending_config=compact_pending;
            end
            frame_job_config_cdc #(.EXT_WIDTH(JOB_EXT_WIDTH),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),
                .TRUSTED_INPUT(1),
                .COMPACT_EMPTY_EXTENSION_ENABLE(R8_COMPACT_CONFIG_ENABLE),
            .COMPACT_STAGE2_EXTENSION_ENABLE(R8_STAGE2_COMPACT_TRANSPORT_ENABLE),
                .DEHAZE_LUT_GUARD_ENABLE(HOST_DEHAZE_LUT_ENABLE),
                .EXT_COMBINATIONS(CONFIG_EXT_COMBINATIONS),.EXT_SUPPORTED(CONFIG_EXT_SUPPORTED)) u_job_config(
                .i_dehaze_lut_valid(f21_owned_lut_valid),.i_dehaze_lut_generation(f21_owned_lut_generation),
                .i_dehaze_update_busy(f21_lut_update_busy),.o_dehaze_lut_update_inhibit(f21_lut_update_inhibit),
                .i_pixel_clk(pixel_clk),.i_pixel_rst_n(LIVE_F21_ENABLE ? f21_core_async_reset_n : pixel_rst_n),
                .i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n&&(!LIVE_F21_ENABLE||f21_core_async_reset_n)),
                .s_frontend_applied_data(compact_frontend_ack),.s_frontend_applied_valid(job_front_valid),
                .s_frontend_applied_ok(job_front_ok),.s_frontend_applied_ready(job_front_ready),
                .m_whole_ack_data(compact_whole_ack),.m_whole_ack_valid(job_ack_valid),
                .m_whole_ack_ok(job_ack_ok),.m_whole_ack_ready(job_ack_ready),
                .i_pair_mode(SOURCE_SELECT==2 ? 2'd1 : 2'd0),.i_mono_enable(SOURCE_SELECT!=2),
                .i_max_delta_ns(64'd1000000),.i_max_wait_ns(32'd50000000),.i_max_age_ns(32'd100000000),
                .o_job_config_valid(raw_job_config_valid),.i_job_config_ready(raw_job_config_ready),
                .o_job_session(raw_job_config_session),.o_job_epoch(raw_job_config_epoch),
                .o_job_mode(raw_job_config_mode),.o_job_mono_enable(raw_job_config_mono),
                .o_job_max_delta_ns(raw_job_config_max_delta),.o_job_max_wait_ns(raw_job_config_max_wait),
                .o_job_max_age_ns(raw_job_config_max_age),
                .i_job_config_done(raw_job_config_done),.i_job_config_error(raw_job_config_error),.i_job_config_busy(raw_job_config_busy),
                .o_source_reset_done(),.o_dfi_reset_done(),.o_source_busy(),.o_dfi_busy(),
                .o_active_session(record_source_active_session),.o_active_epoch(record_source_active_epoch),
                .o_active_valid(record_source_active_valid),.o_active_config(compact_active),
                .o_active_hdr(dfi_active_hdr),
                .o_job_config_snapshot(compact_pending),
                .o_source_fault(source_fault),.o_dfi_fault(dfi_fault),.o_stale_ack_count(),.o_stale_job_done_count());
            assign raw_job_config_fault=source_fault||dfi_fault||live_lease_fault;
            // This PIX-domain flag already synchronizes the DFI sticky fault.
            // Pause future SOFs while every accepted old body drains normally.
            assign raw_job_source_config_fault=source_fault||live_lease_fault;
        end else begin : g_capture_only_config
            assign f21_lut_update_inhibit=0;
            assign dfi_active_config=0;assign dfi_pending_config=0;assign dfi_active_hdr=0;
            assign record_source_active_session=0;assign record_source_active_epoch=0;
            assign record_source_active_valid=0;
            assign whole_config_ack_data=frontend_config_ack_data;
            assign whole_config_ack_valid=frontend_config_ack_valid;
            assign whole_config_ack_ok=frontend_config_ack_ok;
            assign frontend_config_ack_ready=whole_config_ack_ready;
            assign raw_job_config_valid=0;assign raw_job_config_session=0;assign raw_job_config_epoch=0;
            assign raw_job_config_mode=0;assign raw_job_config_mono=0;assign raw_job_config_max_delta=0;
            assign raw_job_config_max_wait=0;assign raw_job_config_max_age=0;assign raw_job_config_fault=0;
            assign raw_job_source_config_fault=0;
        end
    end else begin : g_unconfigured_capture
        assign f21_lut_update_inhibit=0;
        assign dfi_active_config=0;assign dfi_pending_config=0;assign dfi_active_hdr=0;
        assign record_pixel_quiescent_dfi=0;
        assign record_source_active_session=0;assign record_source_active_epoch=0;
        assign record_source_active_valid=0;
        assign physical_admit_enable=0;assign capture0_geometry_done=0;
        assign capture0_active_config=0;
        assign capture0_data=cropped_raw_data;assign capture0_valid=cropped_raw_valid;
        assign capture0_accept=cropped_raw_ready;assign capture0_sof=cropped_raw_sof;
        assign capture0_eol=cropped_raw_eol;assign capture0_abort=cropped_raw_abort;
        assign capture0_session=cfg_session;assign capture0_sequence=native_next_sequence;assign capture0_epoch=cfg_epoch;
        assign capture0_metadata=0;assign capture1_data=0;assign capture1_valid=0;assign capture1_accept=0;
        assign capture1_sof=0;assign capture1_eol=0;assign capture1_abort=0;
        assign capture1_session=0;assign capture1_sequence=0;assign capture1_epoch=0;assign capture1_metadata=0;
        assign capture_config_ready=0;assign capture_config_reset_done=0;
        assign frontend_config_ack_data=0;assign frontend_config_ack_valid=0;assign frontend_config_ack_ok=0;
        assign frontend_config_ack_ready=0;assign whole_config_ack_data=0;assign whole_config_ack_valid=0;assign whole_config_ack_ok=0;
        assign common_pixel_time_ns=pixel_ticks;assign common_dfi_time_ns=0;
        assign common_pixel_time_valid=0;assign common_dfi_time_valid=0;assign capture_frontend_fault=0;
        assign raw_job_config_valid=0;assign raw_job_config_session=0;assign raw_job_config_epoch=0;
        assign raw_job_config_mode=0;assign raw_job_config_mono=0;assign raw_job_config_max_delta=0;
        assign raw_job_config_max_wait=0;assign raw_job_config_max_age=0;assign raw_job_config_fault=0;
        assign raw_job_source_config_fault=0;
    end endgenerate
    generate if (S04_ENABLE != 0) begin : g_s04
        wire [1:0] raw_service_write_response;
        // Digital private jobs exclusively own the shared replay processing
        // pool. A host request must fail at admission rather than wedge it
        // with a non-private context. QUERY/PIN/FETCH/RELEASE remain available.
        wire denied_host_replay=PRIVATE_PROCESSING_ENABLE!=0 && raw_bar_write_valid &&
            raw_bar_write_offset==`PCIE_REG_RAW_COMMAND &&
            raw_bar_write_strobes==4'hf && raw_bar_write_data==`PCIE_RAW_COMMAND_REPLAY;
        assign raw_bar_write_response=denied_host_replay ? 2'b10 : raw_service_write_response;
        full_raw_store #(.STEREO_ENABLE(DUAL_CAMERA_ENABLE),.STEREO_CAPTURE_DIVISOR(STEREO_CAPTURE_DIVISOR),.STEREO_RUNTIME_CADENCE(1),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),.DESCRIPTOR_ENABLE(1),
            .SHARED_DECODE_ENABLE(HDR_PROCESSING_ENABLE),.RAW_EXPORT_ENABLE(HDR_PROCESSING_ENABLE),
            .CAMERA_COUNT(1),
            .CANONICAL_PRIVATE_FETCH_ENABLE(HDR_PROCESSING_ENABLE),.SHARED_REPLAY_FIFO_ENABLE(HDR_PROCESSING_ENABLE),
            .DUAL_CAPTURE_ENABLE(1),.SECOND_HDR_CAMERA(DUAL_CAMERA_ENABLE),.SEPARATE_DFI_DATA_RESET(1),
            // Preserve physical source/time provenance as well as virtual
            // metadata. Unknown fields stay zero; only explicit stored-current
            // policy may obtain a physical MONO lease after complete SOURCE/B.
            .PAIR_METADATA_ENABLE(CONFIGURED_CAPTURE_ENABLE),.PHYSICAL_MONO_CURRENT_ENABLE(PHYSICAL_FRAME_FENCE_ENABLE && NR_PROCESSING_ENABLE),.PRIVATE_REPLAY_ENABLE(PRIVATE_PROCESSING_ENABLE),
            .HOST_REPLAY_CONTEXT_ENABLE(0),
            .CFS_ENABLE(0),.OFFICIAL_CRC_QUALIFIED(1),
            .SOURCE_TERMINAL_ENABLE(PHYSICAL_FRAME_FENCE_ENABLE),.MASK_EXPORT_ENABLE(0)) u_raw_service (
            .o_hdr_begin_reject(field_hdr_reject),.o_hdr_pair_expire(field_hdr_expire),
            .o_hdr_bad_finish(field_hdr_bad),.o_hdr_bank_states(field_hdr_banks),
            .o_sdr_begin_reject(field_sdr_reject),.o_sdr_bad_finish(field_sdr_bad),.o_cam1_hdr_admit(field_cam1_admit),
            .i_cam1_hdr_enable(stereo_hdr_pixel),
            .i_cam1_hdr_data(cam1_hdr_data),.i_cam1_hdr_valid(cam1_hdr_valid),
            .i_cam1_hdr_sof(cam1_hdr_sof),.i_cam1_hdr_eol(cam1_hdr_eol),.i_cam1_hdr_abort(cam1_hdr_abort),
            .i_cam1_hdr_sequence(cam1_hdr_sequence),.i_cam1_hdr_metadata(cam1_hdr_metadata),
            .i_cam1_hdr_source_valid(cam1_hdr_source_valid),.o_cam1_hdr_source_ready(cam1_hdr_source_ready),
            .i_cam1_hdr_source_session(cam1_hdr_source_session),.i_cam1_hdr_source_epoch(cam1_hdr_source_epoch),
            .i_cam1_hdr_source_sequence(cam1_hdr_source_sequence),.i_cam1_hdr_source_ok(cam1_hdr_source_ok),
            .i_cam1_hdr_source_error(cam1_hdr_source_error),.o_cam1_hdr_idle(cam1_hdr_idle),
            .i_stereo_mode(stored_sdr_dfi),.i_stereo_mode_pixel(stored_sdr_pixel),
            .i_raw_export(raw_mode_dfi),.i_raw_cancel(raw_record_cancel),
            .o_raw_record_valid(raw_record_valid),.i_raw_record_ready(raw_record_ready),
            .o_raw_record_length(raw_record_length),.o_raw_record_identity(raw_record_identity),
            .o_raw_data(raw_payload_data),.o_raw_keep(raw_payload_keep),.o_raw_valid(raw_payload_valid),.o_raw_last(raw_payload_last),.i_raw_ready(raw_payload_ready),
            .o_raw_done_valid(raw_record_done),.o_raw_done_ok(raw_record_ok),.o_raw_drained(raw_record_drained),
            .i_raw_retire_valid(raw_retire_valid),.o_raw_retire_ready(raw_retire_ready),.i_raw_retire_identity(raw_retire_identity),
            .i_stereo_frame_divisor_pixel(8'd1), // Stereo cadence was decided at the authenticated sensor FS.

            .o_stereo_job_valid(stereo_job_valid),.i_stereo_job_ready(stereo_job_ready),.o_stereo_job_frame(stereo_job_frame),
            .o_stereo_job_lease(stereo_job_lease),.o_stereo_job_id(stereo_job_id),.o_stereo_job_bayer(stereo_job_bayer),.o_stereo_job_time_valid(stereo_job_time_valid),
            .i_stereo_retire_valid(stereo_retire_valid),.i_stereo_retire_job_id(stereo_retire_id),.o_stereo_retire_ready(stereo_retire_ready),
            .o_stereo_retire_done(stereo_retire_done),.o_stereo_retire_error(stereo_retire_error),.o_stereo_empty(stereo_empty),
            .i_stereo_processing_done(stereo_processing_result_valid),.i_stereo_processing_error(stereo_processing_result_error),.i_stereo_processing_job_id(stereo_processing_result_job),
            .o_decode_start_valid(stereo_decode_start),.i_decode_start_ready(stereo_decode_start_ready),
            .o_decode_release(stereo_decode_release),.o_decode_cancel(stereo_decode_cancel),.o_decode_run(stereo_decode_run),
            .o_decode_data(stereo_decode_data),.o_decode_keep(stereo_decode_keep),
            .o_decode_valid(stereo_decode_valid),.o_decode_last(stereo_decode_last),.i_decode_ready(stereo_decode_ready),
            .i_decode_raw(stereo_decode_raw),.i_decode_raw_valid(stereo_decode_raw_valid),.o_decode_raw_ready(stereo_decode_raw_ready),
            .i_decode_sof(stereo_decode_sof),.i_decode_eol(stereo_decode_eol),
            .i_decode_done(stereo_decode_done),.i_decode_aborted(stereo_decode_aborted),.i_decode_quiet(stereo_decode_quiet),.i_decode_active(stereo_decode_active),
            // Two capture paths are HDR members or physical SDR eyes, never both.
            .i_sdr_lz_enable(1'b0),.i_lz_fault(1'b0),.i_lz_region_quiet(1'b1),
            .i_capture_time_valid(common_pixel_time_valid),.i_bayer_valid(raw_bayer_valid),.i_isp_bayer_phase(color_phase_pixel),
            .o_raw_route_sdr(raw_route_sdr),.o_raw_mode_busy(raw_mode_busy),.o_raw_mode_applied(raw_mode_applied),
            .o_raw_policy_admit(raw_policy_admit),.o_raw_region_quiet(raw_region_quiet),
            .o_lz_region_grant(),.o_lz_stop(),.o_sdr_offer_valid(),.o_sdr_frame_context(),
            .i_sdr_read_request_valid(1'b0),.i_sdr_read_request_context(448'd0),.o_sdr_read_request_ready(),
            .o_sdr_read_data(),.o_sdr_read_keep(),.o_sdr_read_valid(),.o_sdr_read_last(),
            .i_sdr_read_ready(1'b0),.o_sdr_read_owned(),.o_sdr_read_done_valid(),.o_sdr_read_done_ok(),
            .i_sdr_reader_cancel(1'b0),.i_sdr_release_valid(1'b0),.i_sdr_release_context(448'd0),
            .i_sdr_consumer_quiet(1'b1),.o_sdr_release_ready(),
            .s_hdr_axi_arid(hdr_reader_axi_arid),
            .s_hdr_axi_araddr(hdr_reader_axi_araddr),
            .s_hdr_axi_arlen(hdr_reader_axi_arlen),
            .s_hdr_axi_arsize(hdr_reader_axi_arsize),
            .s_hdr_axi_arburst(hdr_reader_axi_arburst),
            .s_hdr_axi_arvalid(hdr_reader_axi_arvalid),
            .s_hdr_axi_arready(hdr_reader_axi_arready),
            .s_hdr_axi_rid(hdr_reader_axi_rid),
            .s_hdr_axi_rdata(hdr_reader_axi_rdata),
            .s_hdr_axi_rresp(hdr_reader_axi_rresp),
            .s_hdr_axi_rlast(hdr_reader_axi_rlast),
            .s_hdr_axi_rvalid(hdr_reader_axi_rvalid),
            .s_hdr_axi_rready(hdr_reader_axi_rready),

            .i_identity_rst_n(hdr_identity_reset_n),.i_identity_data_rst_n(product_dfi_data_reset_n),
            .i_pair_stop(pairbank_stop||stereo_pause_dfi),
            .i_pair_fault(hdr_reader_fault||hdr_source_fault||store_recovery),
            .i_pair_now(common_dfi_time_ns),
            .i_pair_config_valid(pairbank_cfg_valid),.o_pair_config_ready(pairbank_cfg_ready),.o_pair_config_error(pairbank_cfg_error),
            .i_pair_session(raw_job_config_session),.i_pair_epoch(raw_job_config_epoch),
            .i_pair_max_delta(raw_job_config_max_delta),.i_pair_max_wait(raw_job_config_max_wait),.i_pair_max_age(raw_job_config_max_age),
            .i_pair_ratio(3'd4),.i_pair_hdr_enable(raw_job_config_mode==2),
            .o_pair_valid(pairbank_valid),.o_pair_bank(pairbank_bank),.o_pair_id(pairbank_id),.i_pair_ready(pairbank_ready),
            .i_pair_release_valid(pairbank_release_valid),.o_pair_release_ready(pairbank_release_ready),
            .i_pair_release_bank(pairbank_release_bank),.i_pair_release_id(pairbank_release_id),
            .i_pair_read_quiet(hdr_reader_quiet),.i_pair_product_quiet(hdr_writer_quiescent),.i_pair_ticket_released(!hdr_ticket_hold),
            .i_pair_directory_valid(pairbank_directory_valid),.i_pair_directory_slot(pairbank_directory_slot),.o_pair_directory_ready(pairbank_directory_ready),
            .m_pair_directory_data(pairbank_directory_data),.m_pair_directory_word(pairbank_directory_word),
            .m_pair_directory_valid(pairbank_directory_output_valid),.m_pair_directory_last(pairbank_directory_last),.m_pair_directory_ready(pairbank_directory_output_ready),
            .i_capture_enable(stored_sdr_pixel || (capture0_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR] &&
                camera_hdr_mode)),
            .i_pixel_clk(pixel_clk), .i_pixel_rst_n(pixel_rst_n),
            .i_dfi_clk(dfi_clk), .i_dfi_rst_n(dfi_rst_n), .i_ddr_ready(ddr_app_ready),
            .i_cfs_enable(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_CFS]),
            .i_physical_mono_current_enable(1'b0),
            .o_cfs_compressed_count(),.o_cfs_no_benefit_count(),
            .o_cfs_overflow_count(),.o_cfs_busy_count(),.o_cfs_protocol_fault(cfs_protocol_fault),
            .i_user_clk(user_clk), .i_user_rst_n(user_rst_n),
            .i_capture_data(capture0_data), .i_capture_valid(capture0_valid),
            .i_capture_accept(capture0_accept),
            .i_capture_sof(capture0_sof), .i_capture_eol(capture0_eol),
            .i_capture_abort(capture0_abort), .i_capture_epoch(capture0_epoch),
            .i_session_id(capture0_session),.i_frame_sequence(capture0_sequence),.i_mode_epoch(capture0_epoch),
            .i_capture_metadata(capture0_metadata),
            .i_capture_source_valid(stored_sdr_pixel ? stereo_source0_valid : camera_hdr_mode ? hdr_source0_valid : physical_raw_source_valid),.o_capture_source_ready(capture_terminal_ready),
            .i_capture_source_session(stored_sdr_pixel ? stereo_source0_session : camera_hdr_mode ? hdr_source_session : physical_raw_source_session),
            .i_capture_source_epoch(stored_sdr_pixel ? stereo_source0_epoch : camera_hdr_mode ? hdr_source_epoch : physical_raw_source_epoch),
            .i_capture_source_sequence(stored_sdr_pixel ? stereo_source0_sequence : camera_hdr_mode ? hdr_source0_sequence : physical_raw_source_sequence),.i_capture_source_camera(stored_sdr_pixel?stereo_source0_camera:1'b0),
            .i_capture_source_ok(stored_sdr_pixel ? stereo_source0_ok : camera_hdr_mode ? hdr_source_ok : physical_raw_source_ok),
            .i_capture_source_error(stored_sdr_pixel ? stereo_source0_error : camera_hdr_mode ? hdr_source_error : physical_raw_source_error),
            .o_capture_source_stale_count(),
            // The released board profile keeps the proven single IMX415 pinout.
            // The independent second capture domain is qualified in S08 simulation.
            .i_capture1_clk(pixel_clk),.i_capture1_rst_n(pixel_rst_n),.i_capture1_data(capture1_data),
            .i_capture1_valid(capture1_valid),.i_capture1_accept(capture1_accept),
            .i_capture1_sof(capture1_sof),.i_capture1_eol(capture1_eol),.i_capture1_abort(capture1_abort),
            .i_capture1_session(capture1_session),.i_capture1_sequence(capture1_sequence),.i_capture1_epoch(capture1_epoch),
            .i_capture1_metadata(capture1_metadata),
            .i_capture1_source_valid(stored_sdr_pixel?stereo_source1_valid:camera_hdr_mode&&hdr_source1_valid),.o_capture1_source_ready(hdr_source1_ready),
            .i_capture1_source_session(stored_sdr_pixel?stereo_source1_session:hdr_source1_session),.i_capture1_source_epoch(stored_sdr_pixel?stereo_source1_epoch:hdr_source1_epoch),.i_capture1_source_sequence(stored_sdr_pixel?stereo_source1_sequence:hdr_source1_sequence),
            .i_capture1_source_camera(stored_sdr_pixel?stereo_source1_camera:1'b0),.i_capture1_source_ok(stored_sdr_pixel?stereo_source1_ok:hdr_source1_ok),.i_capture1_source_error(stored_sdr_pixel?stereo_source1_error:hdr_source1_error),
            .o_capture1_source_stale_count(),
            .o_capture0_enqueue_fire(raw_capture0_enqueue_fire),.o_capture1_enqueue_fire(raw_capture1_enqueue_fire),
            .o_capture0_consume_fire(raw_capture0_consume_fire),.o_capture1_consume_fire(raw_capture1_consume_fire),
            .o_capture0_idle(raw_capture0_idle),.o_capture1_idle(raw_capture1_idle),
            .o_capture0_frame_accept(raw_capture0_frame_accept),.o_capture1_frame_accept(raw_capture1_frame_accept),
            .o_capture_write_quiescent(raw_capture_write_quiescent),
            .o_private_ownership_quiescent(raw_private_ownership_quiescent),
            .o_commit_valid(raw_commit_valid),.o_commit_frame(raw_commit_frame),.o_commit_lease(raw_commit_lease),.i_commit_ready(raw_commit_ready),
            .i_ref_valid(raw_ref_valid&&raw_ref_acquire_allowed),.o_ref_ready(raw_ref_store_ready),.i_ref_op(raw_ref_op),.i_ref_mask(raw_ref_mask),
            .i_ref_frame0(raw_ref_frame0),.i_ref_frame1(raw_ref_frame1),
            .i_ref_lease0(raw_ref_lease0),.i_ref_lease1(raw_ref_lease1),.i_ref_job_id(raw_ref_job_id),.o_reference_fault(raw_reference_fault),
            .o_read_quiescent(raw_read_quiescent),
            .i_shared_replay_source_select(hdr_phase_owned),.i_shared_replay_sink_select(shared_processing_selected),
            .s_shared_replay_data(hdr_fifo_source),.s_shared_replay_valid(hdr_fifo_source_valid),
            .s_shared_replay_ready(hdr_fifo_source_ready),.o_shared_replay_source_reset_done(hdr_fifo_source_reset_done),
            .m_shared_replay_data(hdr_fifo_sink),.m_shared_replay_valid(hdr_fifo_sink_valid),
            .m_shared_replay_ready(hdr_fifo_sink_ready),.o_shared_replay_sink_reset_done(hdr_fifo_sink_reset_done),
            .i_private_req_offset(hdr_phase_owned ? hdr_private_req_offset : 32'd0),
            .i_private_req_length(hdr_phase_owned ? hdr_private_req_length : 32'd0),
            .i_public_read_admission_enable(!hdr_phase_request),.o_public_read_quiescent(raw_public_read_quiescent),
            .o_mask_command_data(mask_command),.o_mask_command_valid(mask_command_valid),.i_mask_command_ready(mask_command_ready),
            .i_mask_response_data(mask_response),.i_mask_response_valid(mask_response_valid),.o_mask_response_ready(mask_response_ready),
            .i_mask_block_data(mask_block),.i_mask_block_valid(mask_block_valid),.o_mask_block_ready(mask_block_ready),
            .o_mask_cache_retire(mask_cache_retire),.i_mask_owner_complete(mask_owner_complete),
            .o_private_rsp_descriptor(raw_private_rsp_descriptor),.o_private_rsp_metadata_valid(raw_private_rsp_metadata_valid),
            .o_private_read_data(raw_private_read_data),.o_private_read_keep(raw_private_read_keep),
            .o_private_read_valid(raw_private_read_valid),.o_private_read_last(raw_private_read_last),
            .i_private_read_ready(raw_private_read_ready),.o_private_read_complete(raw_private_read_complete),
            .o_private_read_error(raw_private_read_error),.o_private_read_protocol_fault(raw_private_read_fault),
            .i_private_req_valid(raw_private_req_valid),.o_private_req_ready(raw_private_req_ready),.i_private_req_op(raw_private_req_op),
            .i_private_req_camera(raw_private_req_camera),.i_private_req_slot(raw_private_req_slot),
            .i_private_req_generation(raw_private_req_generation),.i_private_req_session(raw_private_req_session),
            .i_private_req_lease(raw_private_req_lease),.i_private_req_job_id(raw_private_req_job_id),
            .i_private_descriptor(raw_member_frame),.i_private_pair_id(raw_member_pair_id),.i_private_member_index(raw_member_index),
            .o_private_rsp_valid(raw_private_rsp_valid),.i_private_rsp_ready(raw_private_rsp_ready),.o_private_rsp_code(raw_private_rsp_code),
            .o_private_rsp_camera(raw_private_rsp_camera),.o_private_rsp_slot(raw_private_rsp_slot),
            .o_private_rsp_generation(raw_private_rsp_generation),.o_private_rsp_session(raw_private_rsp_session),
            .o_private_rsp_sequence(raw_private_rsp_sequence),.o_private_rsp_epoch(raw_private_rsp_epoch),
            .o_private_native_done(raw_private_native_done),.o_private_native_error(raw_private_native_error),
            .o_private_native_job_id(raw_private_native_job),.o_private_native_member_index(raw_private_native_member),
            .o_replay_context_valid(raw_replay_context_valid),.i_replay_context_ready(raw_replay_context_ready),.o_replay_descriptor(raw_replay_context_frame),
            .o_replay_job_id(raw_replay_context_job),.o_replay_pair_id(raw_replay_context_pair),
            .o_replay_member_index(raw_replay_context_member),.o_replay_private(raw_replay_context_private),.o_replay_protocol_fault(raw_replay_protocol_fault),
            .o_host_replay_context_valid(host_replay_context_valid),.i_host_replay_context_ready(host_replay_context_ready),
            .o_host_replay_descriptor(host_replay_context_frame),.o_host_replay_metadata_valid(host_replay_metadata_valid),
            .o_replay_native_done(raw_replay_native_done),.o_replay_native_error(raw_replay_native_error),
            .i_replay_safe(replay_pipeline_safe && replay_admission_ready &&
                record_product_available&&!record_format_busy_pixel[1]&&
                (PHYSICAL_FRAME_FENCE_ENABLE==0 || physical_source_idle)),
            .o_replay_active(replay_active), .o_replay_data(replay_raw_data),
            .o_replay_valid(replay_raw_valid), .i_replay_ready(replay_raw_ready),
            .o_replay_sof(replay_raw_sof), .o_replay_eol(replay_raw_eol), .o_replay_abort(replay_raw_abort),
            .i_bar_write_valid(raw_bar_write_valid&&!denied_host_replay), .i_bar_write_offset(raw_bar_write_offset),
            .i_bar_write_data(raw_bar_write_data), .i_bar_write_strobes(raw_bar_write_strobes),
            .o_bar_write_response(raw_service_write_response),
            .i_bar_read_valid(raw_bar_read_valid), .i_bar_read_offset(raw_bar_read_offset),
            .o_bar_read_response_valid(raw_bar_read_response_valid),
            .o_bar_read_data(raw_bar_read_data), .o_bar_read_response(raw_bar_read_response),
            .m_axi_awid(capture_axi_awid),
            .m_axi_awaddr(capture_axi_awaddr),
            .m_axi_awlen(capture_axi_awlen),
            .m_axi_awsize(capture_axi_awsize),
            .m_axi_awburst(capture_axi_awburst),
            .m_axi_awvalid(capture_axi_awvalid),
            .m_axi_awready(capture_axi_awready),
            .m_axi_wdata(capture_axi_wdata),
            .m_axi_wstrb(capture_axi_wstrb),
            .m_axi_wlast(capture_axi_wlast),
            .m_axi_wvalid(capture_axi_wvalid),
            .m_axi_wready(capture_axi_wready),
            .m_axi_bid(capture_axi_bid),
            .m_axi_bresp(capture_axi_bresp),
            .m_axi_bvalid(capture_axi_bvalid),
            .m_axi_bready(capture_axi_bready),
            .m_axi_arid(capture_axi_arid),
            .m_axi_araddr(capture_axi_araddr),
            .m_axi_arlen(capture_axi_arlen),
            .m_axi_arsize(capture_axi_arsize),
            .m_axi_arburst(capture_axi_arburst),
            .m_axi_arvalid(capture_axi_arvalid),
            .m_axi_arready(capture_axi_arready),
            .m_axi_rid(capture_axi_rid),
            .m_axi_rdata(capture_axi_rdata),
            .m_axi_rresp(capture_axi_rresp),
            .m_axi_rlast(capture_axi_rlast),
            .m_axi_rvalid(capture_axi_rvalid),
            .m_axi_rready(capture_axi_rready)
        );
    end else begin : g_no_s04
        assign stereo_decode_start=0;assign stereo_decode_release=0;assign stereo_decode_cancel=0;assign stereo_decode_run=0;
        assign stereo_decode_data=0;assign stereo_decode_keep=0;assign stereo_decode_valid=0;assign stereo_decode_last=0;
        assign stereo_decode_raw_ready=0;
        assign cfs_protocol_fault=0;
        assign host_replay_context_valid=0;assign host_replay_context_frame=0;
        assign host_replay_metadata_valid=0;
        // With no RAW writer, consume its SOURCE notification without claiming
        // a DDR operation. The native JPEG owner still checks its own terminal.
        assign physical_raw_source_ready=R8_STAGE1_ENABLE;
        assign raw_capture0_enqueue_fire=1'b0;assign raw_capture1_enqueue_fire=1'b0;
        assign raw_capture0_consume_fire=1'b0;assign raw_capture1_consume_fire=1'b0;
        assign raw_capture0_idle=1'b1;assign raw_capture1_idle=1'b1;
        assign raw_capture0_frame_accept=R8_STAGE1_ENABLE && capture0_valid && capture0_accept && capture0_sof;
        assign raw_capture1_frame_accept=1'b0;
        assign raw_capture_write_quiescent=R8_STAGE1_ENABLE;
        assign raw_private_ownership_quiescent=R8_STAGE1_ENABLE;
        assign raw_commit_valid=0;assign raw_commit_frame=0;assign raw_commit_lease=0;
        assign raw_ref_store_ready=0;assign raw_reference_fault=0;assign raw_read_quiescent=1;
        assign raw_private_req_ready=0;assign raw_private_rsp_valid=0;assign raw_private_rsp_code=0;
        assign raw_private_rsp_camera=0;assign raw_private_rsp_slot=0;assign raw_private_rsp_generation=0;
        assign raw_private_rsp_session=0;assign raw_private_rsp_sequence=0;assign raw_private_rsp_epoch=0;
        assign raw_private_native_done=0;assign raw_private_native_error=0;assign raw_private_native_job=0;assign raw_private_native_member=0;
        assign raw_replay_context_valid=0;assign raw_replay_context_frame=0;assign raw_replay_context_job=0;
        assign raw_replay_context_pair=0;assign raw_replay_context_member=0;assign raw_replay_context_private=0;
        assign raw_replay_protocol_fault=0;assign raw_replay_native_done=0;assign raw_replay_native_error=0;
        assign raw_axi_awid = 4'd0;
        assign raw_axi_awaddr = 28'd0;
        assign raw_axi_awlen = 8'd0;
        assign raw_axi_awsize = 3'd0;
        assign raw_axi_awburst = 2'd0;
        assign raw_axi_awvalid = 1'd0;
        assign raw_axi_wdata = 128'd0;
        assign raw_axi_wstrb = 16'd0;
        assign raw_axi_wlast = 1'd0;
        assign raw_axi_wvalid = 1'd0;
        assign raw_axi_bready = 1'd0;
        assign raw_axi_arid = 4'd0;
        assign raw_axi_araddr = 28'd0;
        assign raw_axi_arlen = 8'd0;
        assign raw_axi_arsize = 3'd0;
        assign raw_axi_arburst = 2'd0;
        assign raw_axi_arvalid = 1'd0;
        assign raw_axi_rready = 1'd0;

        assign raw_bar_write_response = 2'd0;
        assign raw_bar_read_response_valid = 1'b0;
        assign raw_bar_read_data = 32'd0;
        assign raw_bar_read_response = 2'd0;
        assign replay_active = 1'b0;
        assign replay_raw_data = 40'd0;
        assign replay_raw_valid = 1'b0;
        assign replay_raw_sof = 1'b0;
        assign replay_raw_eol = 1'b0;
        assign replay_raw_abort = 1'b0;
    end endgenerate

    wire camera_raw_valid, camera_raw_ready, camera_raw_sof, camera_raw_eol;
    wire camera_raw_abort, camera_receive_fault;
    wire [511:0] camera_geometry_status;
    wire [95:0] camera_rgb;
    wire camera_rgb_valid, camera_rgb_ready, camera_sof, camera_eol;
    // CFG PREPARE/COMMIT drains both real owners before this policy changes.
    // Its actual capture START also freezes a per-slot copy in RAWstore.
    wire physical_stored_policy=stereo_mode_pixel || raw_mode_pixel || (PHYSICAL_FRAME_FENCE_ENABLE!=0 && HDR_PROCESSING_ENABLE!=0 &&
        capture0_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_HDR]);
    reg physical_capture_private;
    wire private_processing_selected=PRIVATE_PROCESSING_ENABLE!=0 &&
        (hdr_processing_selected || processing_context_owned);
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)physical_capture_private<=0;
        else if(capture0_valid&&capture0_accept&&capture0_sof)
            physical_capture_private<=physical_stored_policy;
        else if(physical_source_idle&&native_pipeline_idle&&raw_processing_idle_pixel&&!replay_active)
            physical_capture_private<=0;
    end
    assign live_source_valid=private_processing_selected ? hdr_live_source_valid : physical_live_source_valid;
    assign live_source_cancel=private_processing_selected ? hdr_live_source_cancel : physical_live_source_cancel;
    assign live_source_frame_begin=private_processing_selected ? hdr_frame_begin : physical_live_source_frame_begin;
    assign live_observation_abort=private_processing_selected ?
        (private_notice_valid&&hdr_notice_exact&&!private_notice_ok)||private_pp_error : physical_live_observation_abort;
    assign live_authenticated_negative=private_processing_selected ?
        private_notice_valid&&hdr_notice_exact&&!private_notice_ok : physical_live_authenticated_negative;
    assign lane_owner_begin=private_processing_selected ? hdr_frame_begin : physical_lane_owner_begin;
    assign lane_source_fire=private_processing_selected ? hdr_product_done||hdr_product_failed : physical_lane_source_fire;
    assign lane_source_ok=private_processing_selected ? hdr_product_done : physical_lane_source_ok;
    wire hdr_notice_ready_core,hdr_product_done_core,hdr_product_failed_core;
    assign hdr_notice_ready=f21_core_async_reset_n&&hdr_notice_ready_core;
    assign hdr_product_done=f21_core_async_reset_n&&hdr_product_done_core;
    assign hdr_product_failed=f21_core_async_reset_n&&hdr_product_failed_core;
    source_terminal_broadcast u_hdr_source_broadcast(
        .clk(pixel_clk),.rst_n(f21_core_reset_n),.frame_begin(hdr_frame_begin),
        .frame_owned(processing_context_owned),.cancel(private_pp_error||live_f21_fault),
        .frame_required(2'b01),
        .owner_context(hdr_product_context),.owner_tag(hdr_product_context[447:384]),
        .source_context(hdr_notice_context),.source_tag(hdr_notice_context[447:384]),
        .source_valid(private_notice_valid&&private_processing_selected),.source_ok(private_notice_ok),
        .source_ready(hdr_notice_ready_core),.consumer_owner_match(live_source_match),
        .consumer_ready(live_source_ready),.consumer_skip(live_source_skip),.consumer_cancel_done(live_source_cancel_done),
        .consumer_valid(hdr_live_source_valid),.consumer_cancel(hdr_live_source_cancel),
        .native_done(hdr_product_done_core),.native_failed(hdr_product_failed_core),.rejected(),.done_mask());
    wire [159:0] live_neutral_stats_context;
    wire [183:0] live_neutral_statistics;
    wire live_neutral_stats_valid,live_neutral_stats_ready;
    wire private_isp_rgb_ready;
    wire private_replay_raw_ready;
    wire [4*PRIVATE_RAW_SAMPLE_BITS-1:0] camera_replay_raw;
    generate if(HDR_PROCESSING_ENABLE!=0)begin: g_camera_replay_raw14
        assign camera_replay_raw=replay_raw14;
    end else begin: g_camera_replay_raw10
        assign camera_replay_raw=replay_raw_data;
    end endgenerate
    assign preprocess_input_rgb=private_processing_selected ? private_rgb : camera_rgb;
    assign preprocess_input_valid=private_processing_selected ? private_rgb_valid : camera_rgb_valid;
    assign preprocess_input_sof=private_processing_selected ? private_rgb_sof : camera_sof;
    assign preprocess_input_eol=private_processing_selected ? private_rgb_eol : camera_eol;
    wire camera_error, camera_done, camera_config_done, camera_config_error;
    wire stereo_sensor_30_pixel=COMPILED_PROFILE!=3&&stereo_mode_pixel&&stereo_divisor_pixel==8'd2;
    wire [7:0] stereo_capture_divisor_pixel=(stereo_sensor_30_pixel||raw_mode_pixel&&!stereo_mode_pixel)?8'd1:stereo_divisor_pixel;
    wire camera_sdr_30_mode,cam1_sdr_30_mode;
    wire camera_sdr_profile_matches=camera_sdr_30_mode==stereo_sensor_30_pixel;
    wire cam1_sdr_profile_matches=cam1_sdr_30_mode==stereo_sensor_30_pixel;
    // Before the first APP/DMA start there is no product admission. A real
    // sensor SOF may still acknowledge the fully applied, drained CFG tuple.
    // This observes a boundary only: no RAW slot or image job is manufactured.
    assign cold_config_observe=DUAL_CAMERA_ENABLE!=0&&SOURCE_SELECT==0&&
        CONFIGURED_CAPTURE_ENABLE!=0&&PHYSICAL_FRAME_FENCE_ENABLE!=0&&
        !stereo_mode_pixel&&!enable_pixel[1]&&!armed_pixel[1]&&!local_pixel[1]&&
        !physical_hdr_requested&&!camera_hdr_mode&&camera_mode_running&&
        camera_config_done&&camera_sdr_profile_matches&&!camera_config_error&&!camera_receive_fault&&
        !camera_source_identity_fault&&cfg_pipeline_idle&&
        !private_processing_selected&&!replay_active;
    assign cold_config_sof=cold_config_observe&&cropped_raw_identity_valid&&
        cropped_raw_valid&&cropped_raw_ready&&cropped_raw_sof;
    // The fixed single-camera profile establishes Bayer phase before capture.
    // capture0_geometry_done is EOF and is not configuration validity.
    assign raw_bayer_valid=camera_config_done&&!camera_config_error&&PHYSICAL_FRAME_FENCE_ENABLE&&
        FRAME_WIDTH==1920&&FRAME_HEIGHT==1080;
    wire camera_delay_ready;
    wire camera_phy_ready, camera_delay_status_valid;
    wire [7:0] camera_delay_debug;
    wire [5:0] camera_delay_window;
    wire [31:0] camera_ecc, camera_crc, camera_overflow, camera_format;
    // 接收 RAW 数据并输出每拍四像素的 RGB 流，行尾由 RGB TLAST 标记
    // This timebase follows the common PIX reset. Per-eye mode resets
    // clear that eye's contexts and leave the other eye's deadlines intact.
    localparam integer SHARED_HDR_TIMEOUT_CYCLES=12500000;
    localparam [23:0] SHARED_HDR_TIMEOUT_LAST=SHARED_HDR_TIMEOUT_CYCLES-1;
    reg [23:0] shared_hdr_timeout_phase;
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)shared_hdr_timeout_phase<=24'd0;
        else if(shared_hdr_timeout_phase==SHARED_HDR_TIMEOUT_LAST)shared_hdr_timeout_phase<=24'd0;
        else shared_hdr_timeout_phase<=shared_hdr_timeout_phase+1'b1;
    end
    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(SHARED_HDR_TIMEOUT_CYCLES),
        .EXTERNAL_PHASE_ENABLE(1)) u_real_hdr_cycle(
        .i_timeout_phase({8'd0,shared_hdr_timeout_phase}),
        .i_clk(pixel_clk),.i_reset_n(pixel_branch_reset_n[1]&&camera_mode_running&&camera_hdr_mode),
        .i_fault(camera_source_identity_fault||camera_receive_fault),.i_stable(camera_hdr_stable&&(!stereo_hdr_pixel||cam1_hdr_stable)),
        .i_admit_enable(physical_hdr_requested&&cfg_source_ready&&!cfg_pause&&!local_stop_pause&&!reset_pause_pixel&&enable_pixel[1]&&armed_pixel[1]&&!record_format_busy_pixel[1]),
        .i_session(capture0_active_config[63:32]),.i_epoch(capture0_active_config[159:128]),
        .i_time(common_pixel_time_ns),.i_time_valid(common_pixel_time_valid),.i_capture0_idle(raw_capture0_idle),.i_capture1_idle(raw_capture1_idle),
        .s0_data(hdr_token0),.s1_data(hdr_token1),.s0_valid(hdr_token0_valid),.s1_valid(hdr_token1_valid),.s0_ready(hdr_token0_ready),.s1_ready(hdr_token1_ready),
        .m0_data(hdr_capture0_data),.m1_data(hdr_capture1_data),.m0_valid(hdr_capture0_valid),.m1_valid(hdr_capture1_valid),
        .m0_sof(hdr_capture0_sof),.m1_sof(hdr_capture1_sof),.m0_eol(hdr_capture0_eol),.m1_eol(hdr_capture1_eol),.m0_abort(hdr_capture0_abort),.m1_abort(hdr_capture1_abort),
        .o_sequence0(hdr_capture0_sequence),.o_sequence1(hdr_capture1_sequence),.o_session(hdr_capture_session),.o_epoch(hdr_capture_epoch),
        .o_metadata0(hdr_capture0_metadata),.o_metadata1(hdr_capture1_metadata),
        .o_source0_valid(hdr_source0_valid),.o_source1_valid(hdr_source1_valid),.i_source0_ready(hdr_source0_ready),.i_source1_ready(hdr_source1_ready),
        .o_source_session(hdr_source_session),.o_source_epoch(hdr_source_epoch),.o_source0_sequence(hdr_source0_sequence),.o_source1_sequence(hdr_source1_sequence),
        .o_source1_session(hdr_source1_session),.o_source1_epoch(hdr_source1_epoch),
        .o_source1_ok(hdr_source1_ok),.o_source1_error(hdr_source1_error),
        .o_source_ok(hdr_source_ok),.o_source_error(hdr_source_error),.o_pair_event(hdr_pair_event),.o_pair_ok(hdr_pair_ok),
        .o_good_pairs(),.o_bad_pairs(),.o_not_admitted_pairs(),.o_diag_pair(rx_diag_pair),.o_diag_counts(rx_diag_counts),.o_quiet(hdr_cycle_quiet));
    real_hdr_camera_observe_axis #(.RX_DIAG_ENABLE(0),.MODE_4K(COMPILED_PROFILE==3),.SDR_RATE_CONTROL_ENABLE(1),.RGB_TAP(1), .FIRST_ROW(16),
        .FRAME_EVENTS_ENABLE(PHYSICAL_FRAME_FENCE_ENABLE),
        .CONTROLLED_ABORT_ENABLE(PHYSICAL_FRAME_FENCE_ENABLE || PRIVATE_PROCESSING_ENABLE),
        .CONTROLLED_REPLAY_ABORT_ENABLE(PRIVATE_PROCESSING_ENABLE),
        .COLOR_CONFIG_ENABLE(1), .RAW_REPLAY_ENABLE(VIDEO_SERVICE_ENABLE),
        .SHARED_WIDE_ISP_ENABLE(VIDEO_SERVICE_ENABLE),.JOB_CONTROL_ENABLE(VIDEO_SERVICE_ENABLE),
        .RAW_REPLAY_SAMPLE_BITS(PRIVATE_RAW_SAMPLE_BITS),.SEPARATE_REPLAY_JOB_CONTROL(PRIVATE_PROCESSING_ENABLE)) u_camera (
        .i_bayer_phase(color_phase_pixel), .i_gain_code(color_gain_cfg),
        .i_wb_gains(color_wb_pixel),
        .i_job_enable(private_processing_selected||stereo_mode_pixel||raw_mode_pixel ? 1'b0 :
            (PHYSICAL_FRAME_FENCE_ENABLE!=0 ?
                (physical_frame_enable || (replay_active && cfg_source_ready && !cfg_pause)) : cfg_source_ready)),
        .i_job_pause(PHYSICAL_FRAME_FENCE_ENABLE!=0 ?
            (!native_pipeline_idle || (replay_active && (cfg_pause || !physical_source_idle))) :
            (local_stop_pause || cfg_pause || (VIDEO_SERVICE_ENABLE!=0 && !cfg_pipeline_idle))),
        .i_processing_reset_n(private_processing_selected ? private_isp_reset_n : physical_processing_rst_n),
        .i_replay_job_enable(private_processing_selected ? processing_replay_payload_enable&&processing_context_owned : cfg_source_ready),
        .i_replay_job_pause(!private_processing_selected&&cfg_pause),
        .o_job_start(native_job_start),.o_job_idle(native_job_idle),.o_job_replay(native_job_replay),
        .i_pixel_clk(pixel_clk), .i_sensor_clk(sensor_clk),
        .i_cfg_clk(sys_clk),.i_hdr_mclk(sensor_hdr_clk),.i_clock_locked(camera_pll_lock),
        .i_hdr_request(physical_hdr_requested),
        .i_sdr_30_request(stereo_sensor_30_pixel),.o_sdr_30_mode(camera_sdr_30_mode),
        .i_mode_quiet(cfg_pipeline_idle&&raw_private_ownership_quiescent&&raw_capture0_idle&&raw_capture1_idle&&(&cam1_hdr_idle)&&!replay_active),
        .i_hdr_pair_event(hdr_pair_event),.i_hdr_pair_ok(hdr_pair_ok),
        .o_hdr_mode(camera_hdr_mode),.o_mode_running(camera_mode_running),.o_hdr_stable(camera_hdr_stable),
        .o_rx_diag_word_clk(rx_diag_word_clk),.o_rx_diag_word(rx_diag_word),.o_rx_diag_cfg(rx_diag_cfg),
        .o_rx_trace_sample(),.o_rx_trace_trigger(),
        .o_rx_trace_cohort_n(),.o_rx_trace_enable(),
        .m_hdr0_data(hdr_token0),.m_hdr1_data(hdr_token1),.m_hdr0_valid(hdr_token0_valid),.m_hdr1_valid(hdr_token1_valid),
        .m_hdr0_ready(hdr_token0_ready),.m_hdr1_ready(hdr_token1_ready),
        .i_ref_clk(camera_ref_clk), .i_reset_n(pixel_branch_reset_n[1]),
        .mipi_clk_hs_rx_p(mipi_clk_hs_rx_p), .mipi_data_hs_p(mipi_data_hs_p),
        .cam_scl(cam_scl), .cam_sda(cam_sda),
        .cam_mclk(cam_mclk), .cam_xclr(cam_xclr),
        .o_axis_tdata(), .o_axis_tkeep(), .o_axis_tvalid(),
        .i_axis_tready(1'b1), .o_axis_tlast(),
        .o_frame_error(camera_error), .o_frame_done(camera_done),
        .o_config_done(camera_config_done), .o_config_error(camera_config_error),
        .o_ecc_errors(camera_ecc), .o_crc_errors(camera_crc),
        .o_overflows(camera_overflow), .o_format_errors(camera_format),
        .m_frame_event_valid(physical_event_valid),.m_frame_event_ready((stereo_mode_pixel||raw_mode_pixel)?stereo_event0_ready:mono_physical_event_ready),
        .m_frame_event_kind(physical_event_kind),.m_frame_event_ok(physical_event_ok),
        .m_frame_event_error(physical_event_error),
        .m_frame_event_sequence(physical_event_sequence),.m_frame_event_identity_valid(physical_event_identity_valid),
        .o_source_identity_fault(camera_source_identity_fault),
        .o_delay_ready(camera_delay_ready),
        .o_phy_ready(camera_phy_ready), .o_delay_status_valid(camera_delay_status_valid),
        .o_delay_debug(camera_delay_debug), .o_delay_window(camera_delay_window),
        .o_observe_raw_valid(camera_raw_valid), .o_observe_raw_ready(camera_raw_ready),
        .o_observe_raw_sof(camera_raw_sof), .o_observe_raw_eol(camera_raw_eol),
        .o_observe_raw_abort(camera_raw_abort), .o_observe_receive_fault(camera_receive_fault),
        .o_rgb_tdata(camera_rgb), .o_rgb_tvalid(camera_rgb_valid),
        .i_rgb_tready(camera_rgb_ready), .o_rgb_tuser(camera_sof),
        .o_rgb_tlast(camera_eol),
        .o_cropped_raw_data(cropped_raw_data), .o_cropped_raw_valid(cropped_raw_valid),
        .o_cropped_raw_ready(cropped_raw_ready), .o_cropped_raw_sof(cropped_raw_sof),
        .o_cropped_raw_eol(cropped_raw_eol), .o_cropped_raw_abort(cropped_raw_abort),
        .o_cropped_raw_sequence(cropped_raw_sequence),.o_cropped_raw_identity_valid(cropped_raw_identity_valid),
        .i_replay_active(replay_active||hdr_processing_selected||stereo_processing_selected),
        .i_replay_hdr_enable(private_isp_hdr_enable),.i_replay_tone_shift(private_isp_tone_shift),
        .i_replay_data(private_processing_selected ? private_isp_raw :
            camera_replay_raw),
        .i_replay_valid(private_processing_selected ? private_isp_raw_valid : replay_raw_valid),
        .i_replay_sof(private_processing_selected ? private_isp_raw_sof : replay_raw_sof),
        .i_replay_eol(private_processing_selected ? private_isp_raw_eol : replay_raw_eol),
        .i_replay_abort(private_processing_selected ? 1'b0 : replay_raw_abort),
        .o_replay_ready(private_isp_raw_ready), .o_replay_safe(replay_pipeline_safe)
    );
    // Physical eye1 has its own receiver only. Both eyes use the original ISP after DDR replay.
    wire [39:0] camera1_raw;
    wire camera1_valid,camera1_sof,camera1_eol,camera1_abort,camera1_identity_valid;
    wire [31:0] camera1_sequence;
    wire camera1_event_valid,camera1_event_ready,camera1_event_ok,camera1_event_identity_valid;
    wire [1:0] camera1_event_kind;wire [3:0] camera1_event_error;wire [31:0] camera1_event_sequence;
    wire camera1_receive_fault,camera1_identity_fault,camera1_quarantine,camera1_config_done,camera1_config_error,camera1_phy_ready;
    wire [31:0] camera1_ecc,camera1_crc,camera1_overflow,camera1_format;
    // Use only terminal errors of the required eyes in the requested sensor
    // profile. An old profile's error can be cleared by the drained mode hold.
    assign capture_config_apply_fault=
        (camera_config_error&&camera_mode_running&&camera_hdr_mode==physical_hdr_requested&&
            (physical_hdr_requested||camera_sdr_profile_matches))||
        (stereo_mode_pixel&&camera1_config_error&&cam1_hdr_mode_running&&cam1_hdr_mode==stereo_hdr_pixel&&
            (stereo_hdr_pixel||cam1_sdr_profile_matches));
    real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(SHARED_HDR_TIMEOUT_CYCLES),
        .EXTERNAL_PHASE_ENABLE(1)) u_cam1_hdr_cycle(
        .i_timeout_phase({8'd0,shared_hdr_timeout_phase}),
        .i_clk(pixel_clk),.i_reset_n(pixel_branch_reset_n[2]&&cam1_hdr_mode_running&&cam1_hdr_mode),
        .i_fault(camera1_identity_fault||camera1_receive_fault),.i_stable(cam1_hdr_stable&&camera_hdr_stable),
        .i_admit_enable(stereo_hdr_pixel&&cfg_source_ready&&!cfg_pause&&!stereo_pause_pixel&&
            !local_stop_pause&&!reset_pause_pixel&&enable_pixel[1]&&armed_pixel[1]&&!record_format_busy_pixel[1]),
        .i_session(capture0_active_config[63:32]),.i_epoch(capture0_active_config[159:128]),
        .i_time(common_pixel_time_ns),.i_time_valid(common_pixel_time_valid),
        .i_capture0_idle(cam1_hdr_idle[0]),.i_capture1_idle(cam1_hdr_idle[1]),
        .s0_data(cam1_hdr_token0),.s1_data(cam1_hdr_token1),
        .s0_valid(cam1_hdr_token_valid[0]),.s1_valid(cam1_hdr_token_valid[1]),
        .s0_ready(cam1_hdr_token_ready[0]),.s1_ready(cam1_hdr_token_ready[1]),
        .m0_data(cam1_hdr_data[39:0]),.m1_data(cam1_hdr_data[79:40]),
        .m0_valid(cam1_hdr_valid[0]),.m1_valid(cam1_hdr_valid[1]),
        .m0_sof(cam1_hdr_sof[0]),.m1_sof(cam1_hdr_sof[1]),
        .m0_eol(cam1_hdr_eol[0]),.m1_eol(cam1_hdr_eol[1]),
        .m0_abort(cam1_hdr_abort[0]),.m1_abort(cam1_hdr_abort[1]),
        .o_sequence0(cam1_hdr_sequence[31:0]),.o_sequence1(cam1_hdr_sequence[63:32]),
        .o_session(cam1_hdr_session),.o_epoch(cam1_hdr_epoch),
        .o_metadata0(cam1_hdr_metadata[196:0]),.o_metadata1(cam1_hdr_metadata[393:197]),
        .o_source0_valid(cam1_hdr_source_valid[0]),.o_source1_valid(cam1_hdr_source_valid[1]),
        .i_source0_ready(cam1_hdr_source_ready[0]),.i_source1_ready(cam1_hdr_source_ready[1]),
        .o_source_session(cam1_hdr_source_session[31:0]),.o_source1_session(cam1_hdr_source_session[63:32]),
        .o_source_epoch(cam1_hdr_source_epoch[31:0]),.o_source1_epoch(cam1_hdr_source_epoch[63:32]),
        .o_source0_sequence(cam1_hdr_source_sequence[31:0]),.o_source1_sequence(cam1_hdr_source_sequence[63:32]),
        .o_source_ok(cam1_hdr_source_ok[0]),.o_source1_ok(cam1_hdr_source_ok[1]),
        .o_source_error(cam1_hdr_source_error[7:0]),.o_source1_error(cam1_hdr_source_error[15:8]),
        .o_pair_event(cam1_hdr_pair_event),.o_pair_ok(cam1_hdr_pair_ok),
        .o_good_pairs(),.o_bad_pairs(),.o_not_admitted_pairs(),.o_diag_pair(),.o_diag_counts(),
        .o_quiet(cam1_hdr_cycle_quiet));
    sdr_camera_raw_frontend #(.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),.SDR_RATE_CONTROL_ENABLE(1),.FIRST_ROW(16),.FIRST_GROUP(1),
        .EVENT_FIFO_DEPTH(512)) u_camera1(
        .i_cfg_clk(sys_clk),.i_hdr_mclk(sensor_hdr_clk),.i_clock_locked(camera_pll_lock),
        .i_hdr_request(stereo_hdr_pixel),
        .i_sdr_30_request(stereo_sensor_30_pixel),.o_sdr_30_mode(cam1_sdr_30_mode),
        .i_mode_quiet(cfg_pipeline_idle&&stereo_source1_idle&&(&cam1_hdr_idle)&&cam1_hdr_cycle_quiet&&!replay_active),
        .i_hdr_pair_event(cam1_hdr_pair_event),.i_hdr_pair_ok(cam1_hdr_pair_ok),
        .o_hdr_mode(cam1_hdr_mode),.o_mode_running(cam1_hdr_mode_running),.o_hdr_stable(cam1_hdr_stable),
        .m_hdr0_data(cam1_hdr_token0),.m_hdr1_data(cam1_hdr_token1),
        .m_hdr0_valid(cam1_hdr_token_valid[0]),.m_hdr1_valid(cam1_hdr_token_valid[1]),
        .m_hdr0_ready(cam1_hdr_token_ready[0]),.m_hdr1_ready(cam1_hdr_token_ready[1]),
        .i_pixel_clk(pixel_clk),.i_sensor_clk(sensor_clk),.i_ref_clk(camera_ref_clk),
        .i_reset_n(pixel_branch_reset_n[2]&&stereo_mode_pixel&&!stereo_pause_pixel),.i_gain_code(color_gain_cfg),
        .mipi_clk_hs_rx_p(mipi1_clk_hs_rx_p),.mipi_data_hs_p(mipi1_data_hs_p),
        .cam_scl(cam1_scl),.cam_sda(cam1_sda),.cam_mclk(cam1_mclk),.cam_xclr(cam1_xclr),
        .o_cropped_raw_data(camera1_raw),.o_cropped_raw_valid(camera1_valid),.i_cropped_raw_ready(1'b1),
        .o_cropped_raw_sof(camera1_sof),.o_cropped_raw_eol(camera1_eol),.o_cropped_raw_abort(camera1_abort),
        .o_cropped_raw_sequence(camera1_sequence),.o_cropped_raw_identity_valid(camera1_identity_valid),
        .m_frame_event_valid(camera1_event_valid),.m_frame_event_ready(camera1_event_ready),.m_frame_event_kind(camera1_event_kind),
        .m_frame_event_ok(camera1_event_ok),.m_frame_event_error(camera1_event_error),.m_frame_event_sequence(camera1_event_sequence),.m_frame_event_identity_valid(camera1_event_identity_valid),
        .o_config_done(camera1_config_done),.o_config_error(camera1_config_error),.o_phy_ready(camera1_phy_ready),
        .o_rx_diag_cfg(rx_diag_cfg1),
        .o_delay_ready(),.o_delay_debug(),.o_delay_window(),.o_delay_status_valid(),
        .o_ecc_errors(camera1_ecc),.o_crc_errors(camera1_crc),.o_overflows(camera1_overflow),.o_format_errors(camera1_format),
        .o_source_identity_fault(camera1_identity_fault),.o_receive_fault(camera1_receive_fault),
        .o_observe_raw_valid(),.o_observe_raw_ready(),.o_observe_raw_sof(),.o_observe_raw_eol(),.o_observe_raw_abort());
    production_source_identity_guard u_source1_identity_guard(
        .clk(pixel_clk),.rst_n(pixel_rst_n&&stereo_mode_pixel&&!stereo_pause_pixel),.phy_ready(camera1_phy_ready),
        .receive_fault(camera1_receive_fault),.parser_identity_fault(camera1_identity_fault),
        .i_recovery_quiet(stereo_source1_idle&&raw_capture1_idle&&camera1_event_ready),
        .event_valid(camera1_event_valid),.event_kind(camera1_event_kind),.event_identity_valid(camera1_event_identity_valid),.quarantine(camera1_quarantine));
    wire stereo_capture_enable;
    stereo_capture_source4 #(.CAMERA_ID(0),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),.SEPARATE_DATA_RESET(1),
        .FS_CADENCE_ENABLE(1)) u_stereo_capture0(
        .i_frame_divisor(stereo_capture_divisor_pixel),
        .clk(pixel_clk),.rst_n(pixel_rst_n&&(stereo_mode_pixel||raw_mode_pixel)),.i_enable(stereo_capture_enable&&camera_config_done),
        .i_data_reset_n(pixel_data_reset_n[1]&&(stereo_mode_pixel||raw_mode_pixel)),
        .i_session(capture0_active_config[63:32]),.i_epoch(capture0_active_config[159:128]),.i_time_ns(common_pixel_time_ns),.i_time_valid(common_pixel_time_valid),
        .i_data(cropped_raw_data),.i_valid(cropped_raw_valid),.i_accept(cropped_raw_ready),.i_sof(cropped_raw_sof),.i_eol(cropped_raw_eol),.i_abort(cropped_raw_abort),
        .i_sequence(cropped_raw_sequence),.i_identity_valid(cropped_raw_identity_valid),
        .i_event_valid(physical_event_valid),.o_event_ready(stereo_event0_ready),.i_event_kind(physical_event_kind),
        .i_event_ok(physical_event_ok),.i_event_error(physical_event_error),.i_event_sequence(physical_event_sequence),.i_event_identity_valid(physical_event_identity_valid),
        .i_receive_fault(camera_receive_fault),.i_identity_quarantine(physical_identity_quarantine),
        .o_capture_data(stereo_capture0_data),.o_capture_valid(stereo_capture0_valid),.o_capture_accept(stereo_capture0_accept),
        .o_capture_sof(stereo_capture0_sof),.o_capture_eol(stereo_capture0_eol),.o_capture_abort(stereo_capture0_abort),.o_capture_geometry_done(stereo_capture0_done),
        .o_capture_session(stereo_capture0_session),.o_capture_epoch(stereo_capture0_epoch),.o_capture_sequence(stereo_capture0_sequence),.o_capture_metadata(stereo_capture0_metadata),
        .o_raw_source_valid(stereo_source0_valid),.i_raw_source_ready(stereo_source0_ready),
        .o_raw_source_session(stereo_source0_session),.o_raw_source_epoch(stereo_source0_epoch),.o_raw_source_sequence(stereo_source0_sequence),
        .o_raw_source_camera(stereo_source0_camera),.o_raw_source_ok(stereo_source0_ok),.o_raw_source_error(stereo_source0_error),
        .o_idle(stereo_source0_idle),.o_fault(stereo_source0_fault));
    stereo_capture_source4 #(.CAMERA_ID(1),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT),.SEPARATE_DATA_RESET(1),
        .FS_CADENCE_ENABLE(1)) u_stereo_capture1(
        .i_frame_divisor(stereo_capture_divisor_pixel),
        .clk(pixel_clk),.rst_n(pixel_rst_n&&stereo_mode_pixel),.i_enable(stereo_capture_enable&&stereo_sdr_pixel&&cam1_hdr_mode_running&&!cam1_hdr_mode&&camera1_config_done),
        .i_data_reset_n(pixel_data_reset_n[2]&&stereo_mode_pixel),
        .i_session(capture0_active_config[63:32]),.i_epoch(capture0_active_config[159:128]),.i_time_ns(common_pixel_time_ns),.i_time_valid(common_pixel_time_valid),
        .i_data(camera1_raw),.i_valid(camera1_valid),.i_accept(1'b1),.i_sof(camera1_sof),.i_eol(camera1_eol),.i_abort(camera1_abort),
        .i_sequence(camera1_sequence),.i_identity_valid(camera1_identity_valid),
        .i_event_valid(camera1_event_valid),.o_event_ready(camera1_event_ready),.i_event_kind(camera1_event_kind),
        .i_event_ok(camera1_event_ok),.i_event_error(camera1_event_error),.i_event_sequence(camera1_event_sequence),.i_event_identity_valid(camera1_event_identity_valid),
        .i_receive_fault(camera1_receive_fault),.i_identity_quarantine(camera1_quarantine),
        .o_capture_data(stereo_capture1_data),.o_capture_valid(stereo_capture1_valid),.o_capture_accept(stereo_capture1_accept),
        .o_capture_sof(stereo_capture1_sof),.o_capture_eol(stereo_capture1_eol),.o_capture_abort(stereo_capture1_abort),.o_capture_geometry_done(stereo_capture1_done),
        .o_capture_session(stereo_capture1_session),.o_capture_epoch(stereo_capture1_epoch),.o_capture_sequence(stereo_capture1_sequence),.o_capture_metadata(stereo_capture1_metadata),
        .o_raw_source_valid(stereo_source1_valid),.i_raw_source_ready(stereo_source1_ready),
        .o_raw_source_session(stereo_source1_session),.o_raw_source_epoch(stereo_source1_epoch),.o_raw_source_sequence(stereo_source1_sequence),
        .o_raw_source_camera(stereo_source1_camera),.o_raw_source_ok(stereo_source1_ok),.o_raw_source_error(stereo_source1_error),
        .o_idle(stereo_source1_idle),.o_fault(stereo_source1_fault));
    production_source_identity_guard u_source_identity_guard(
        .clk(pixel_clk),.rst_n(pixel_rst_n&&camera_mode_running&&!camera_hdr_mode),.phy_ready(camera_phy_ready),
        .receive_fault(camera_receive_fault),.parser_identity_fault(camera_source_identity_fault),
        .i_recovery_quiet(((stereo_mode_pixel||raw_mode_pixel) ? stereo_event0_ready : mono_physical_event_ready)&&((stereo_mode_pixel||raw_mode_pixel) ? stereo_source0_idle&&raw_capture0_idle : mono_source_recovery_quiet)),
        .event_valid(physical_event_valid),.event_kind(physical_event_kind),
        .event_identity_valid(physical_event_identity_valid),
        .quarantine(physical_identity_quarantine));
    // 统计相机帧与错误，仅在 RGB 握手时更新诊断摘要
    reg [31:0] camera_frames, camera_errors, camera_digest;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            camera_frames <= 0; camera_errors <= 0; camera_digest <= 0;
        end else begin
            if (camera_done) camera_frames <= camera_frames + 1'b1;
            if (camera_error) camera_errors <= camera_errors + 1'b1;
            if (camera_rgb_valid && camera_rgb_ready)
                camera_digest <= camera_digest ^ camera_rgb[31:0] ^
                                 camera_rgb[63:32] ^ camera_rgb[95:64];
        end
    end

    // 应用使能与故障按电平同步，槽位所有权通过独立四相握手传递
    wire store_start_ready;
    reg [1:0] fault_pixel;
    reg [1:0] recovery_pixel;
    assign stereo_capture_enable=stored_sdr_pixel&&camera_mode_running&&!camera_hdr_mode&&camera_config_done&&camera_sdr_profile_matches&&(!stereo_mode_pixel||(cam1_hdr_mode_running&&!cam1_hdr_mode&&camera1_config_done&&cam1_sdr_profile_matches))&&!stereo_pause_pixel&&cfg_source_ready&&!cfg_pause&&
        !local_stop_pause&&!reset_pause_pixel&&enable_pixel[1]&&armed_pixel[1]&&!recovery_pixel[1]&&!fault_pixel[1];
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            enable_pixel <= 0;
            fault_pixel <= 0; recovery_pixel <= 0;
        end else begin
            enable_pixel <= {enable_pixel[0], effective_app_enable};
            fault_pixel <= {fault_pixel[0], bridge_fault || store_recovery || cfs_protocol_fault};
            recovery_pixel <= {recovery_pixel[0], !debug_local && transport_recovery};
        end
    end
    // 按当前 125 MHz 像素时钟累计纳秒时间戳
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) pixel_ticks <= 0;
        else pixel_ticks <= pixel_ticks + 64'd8;
    end
    wire [95:0] jpeg_rgb;
    wire [31:0] jpeg_luma;
    wire jpeg_rgb_valid, jpeg_rgb_ready, jpeg_sof, jpeg_eol;
    wire start_valid, start_ready, status_valid, status_ready, status_ok;
    wire jpeg_result_valid, jpeg_result_ready, jpeg_result_ok;
    wire [31:0] capture_id, status_id;
    wire [63:0] capture_time;
    wire frame_active_pixel;
    wire [31:0] jpeg_result_id;
    wire [7:0] jpeg_actual_quality;
    wire [31:0] jpeg_actual_epoch;
    wire jpeg_idle;
    reg [31:0] job_sequence,job_session,job_epoch;
    reg [63:0] job_timestamp;
    reg [383:0] job_source_frame;
    reg job_source_metadata_valid;
    reg [1:0] job_mode;
    reg [7:0] job_processing_mode;
    wire job_schema2=job_processing_mode[7];
    wire [5:0] job_processing_enables=job_processing_mode[5:0];
    reg job_is_replay;
    reg [7:0] job_quality;
    reg [15:0] job_restart;
    reg [7:0] job_requested_quality,job_minimum_quality;
    reg job_adaptive;
    reg [24:0] job_budget;
    reg job_pending;
    wire [95:0] processed_rgb;
    wire [31:0] processed_luma;
    wire processed_valid,processed_ready,processed_sof,processed_eol,processed_done,processed_error;
    wire preprocess_presented,admission_rgb_buffered,admission_state_idle;
    wire neutral_tap_valid,neutral_tap_sof,neutral_tap_eol,neutral_tap_eof;
    wire [95:0] neutral_tap_rgb;
    wire [31:0] neutral_tap_luma;
    wire neutral_stats_valid,neutral_stats_ready;
    wire [159:0] neutral_stats_context;
    wire [183:0] neutral_statistics;
    wire record_stored_source=private_processing_selected || job_is_replay;
    // HDR sparse ownership starts at authenticated context admission, before
    // the first replay RAW SOF updates legacy job_* registers. Borrow the
    // already-published ticket context for that entire product lifetime.
    wire [159:0] neutral_record_context=private_processing_selected ?
        {16'd1,16'd0,8'd1,{6'd0,processing_frame[238:237]},
         {7'd0,processing_frame[3]},{7'd0,processing_frame[4]},
         processing_frame[108:77],processing_frame[140:109],processing_frame[76:45]} :
        {16'd1,16'd0,8'd1,
        record_stored_source ? {6'd0,job_source_frame[238:237]} : NATIVE_FORMAT,
        record_stored_source ? {7'd0,job_source_frame[3]} : RECORD_SOURCE_PHYSICAL,
        record_stored_source ? {7'd0,job_source_frame[4]} : 8'd0,
        job_sequence,job_epoch,job_session};
    wire physical_source_done,physical_source_failed;
    wire physical_cleanup_pulse;
    wire he_source_valid,he_source_ready;
    wire he_source_ok,he_source_camera;
    wire [31:0] he_source_session,he_source_epoch,he_source_sequence;
    // Actual LIVE exposure is not yet supplied by a qualified sensor owner.
    // The capture/session identity is real; numeric zero never means known.
    wire [141:0] he_history_context={job_session,job_epoch,32'd0,16'd0,
        FRAME_WIDTH[12:0],FRAME_HEIGHT[12:0],3'd0,1'b0};
    // Eligibility describes the fixed sensor/ISP session, never known exposure.
    // Every online CONFIG changes the real epoch after drain; UART color writes
    // require cold LOCAL maintenance and assert application/session reset.
    wire he_history_eligible=R8_BASIC_PREPROCESS_ENABLE && cfg_pixel_initialized &&
        ((!private_processing_selected && !job_is_replay && (SOURCE_SELECT==0||SOURCE_SELECT==3)) ||
         (shared_processing_selected && processing_context_owned));
    reg [31:0] previous_preprocess_epoch;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            job_sequence<=0;job_session<=0;job_epoch<=0;job_mode<=0;job_processing_mode<=0;job_quality<=75;job_restart<=0;
            job_pending<=0;previous_preprocess_epoch<=0;job_timestamp<=0;job_is_replay<=0;
            job_requested_quality<=75;job_minimum_quality<=1;job_adaptive<=0;job_budget<=0;
            job_source_frame<=0;job_source_metadata_valid<=0;
        end else begin
            if(native_job_start) begin
                job_sequence<=private_processing_selected ? processing_frame[108:77] :
                    (RECORD_METADATA_ENABLE!=0 && native_job_replay ? host_replay_saved_frame[108:77] :
                     (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_sequence : native_next_sequence));
                job_session<=private_processing_selected ? processing_frame[76:45] :
                    (RECORD_METADATA_ENABLE!=0 && native_job_replay ? host_replay_saved_frame[76:45] :
                     (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_session : cfg_session));
                job_epoch<=private_processing_selected ? processing_frame[140:109] :
                    (RECORD_METADATA_ENABLE!=0 && native_job_replay ? host_replay_saved_frame[140:109] :
                     (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_epoch : cfg_epoch));
                job_timestamp<=private_processing_selected ? processing_frame[204:141] :
                    (RECORD_METADATA_ENABLE!=0 && native_job_replay ?
                        (host_replay_saved_metadata_valid ? host_replay_saved_frame[204:141] : 64'd0) :
                     (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_metadata[63:0] : pixel_ticks));
                job_source_frame<=private_processing_selected ? processing_frame :
                    (native_job_replay ? host_replay_saved_frame : 384'd0);
                job_source_metadata_valid<=private_processing_selected ? processing_frame[0] :
                    (native_job_replay&&host_replay_saved_metadata_valid);
                job_is_replay<=native_job_replay;
                // The frontend has already applied this atomic tuple. The
                // USER engine can still be updating APPLIED on this same SOF.
                job_mode<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ? capture0_active_config[65:64] : cfg_mode;
                // Legacy DUAL COLOR records carry the schema2 tag even after
                // a quality-only CFG transaction has advanced the epoch.
                job_processing_mode<=stereo_mode_pixel && !capture0_schema2 && capture0_active_config[65:64]==0 ?
                    `PCIE_RECORD_V2_MODE_SCHEMA2_TAG : capture0_schema2 ?
                    (`PCIE_RECORD_V2_MODE_SCHEMA2_TAG|{2'd0,capture0_active_config[175:170]}) :
                    {6'd0,(PHYSICAL_FRAME_FENCE_ENABLE!=0&&!native_job_replay?capture0_active_config[65:64]:cfg_mode)};
                job_quality<=selected_quality;
                job_restart<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ? capture0_active_config[121:106] : cfg_restart;
                job_requested_quality<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ?
                    {1'b0,capture0_active_config[72:66]} : cfg_quality;
                job_minimum_quality<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ?
                    {1'b0,capture0_active_config[80:74]} : cfg_min_quality;
                job_adaptive<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ? capture0_active_config[73] : cfg_adaptive;
                job_budget<=PHYSICAL_FRAME_FENCE_ENABLE!=0 && !native_job_replay ? capture0_active_config[105:81] : cfg_budget;
                job_pending<=1;
            end
            if(processed_done || processed_error || physical_cleanup_pulse || private_no_work_complete) job_pending<=0;
            if(camera_rgb_valid && camera_rgb_ready && camera_sof) previous_preprocess_epoch<=job_epoch;
        end
    end
    // Unknown input loss invalidates history, but never interrupts the failed
    // old frame's SOURCE/record drain. Keep the request through the recovered
    // frame's descriptor and input-SOF sampling; output SOF is safely later.
    assign physical_recovery_history_reset=source_recovery_history_pending&&
        !stereo_mode_pixel&&!camera_hdr_mode&&!job_is_replay&&!private_processing_selected;
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)source_recovery_history_pending<=0;
        else if(!stereo_mode_pixel&&!camera_hdr_mode&&physical_identity_quarantine&&mono_source_recovery_quiet)
            source_recovery_history_pending<=1;
        else if(physical_recovery_history_reset&&processed_valid&&processed_ready&&processed_sof)
            source_recovery_history_pending<=0;
    end
    wire native_pipeline_idle_now=native_job_idle && !job_pending && !frame_active_pixel && jpeg_idle &&
        raw_processing_idle_pixel && preprocess_records_quiet && mask_source_quiet && live_f21_frame_quiet;
    wire private_context_request=PRIVATE_PROCESSING_ENABLE!=0&&
        (shared_processing_selected ? hdr_pixel_context_valid : raw_replay_context_valid);
    assign pixel_context_request=host_replay_context_valid||private_context_request;
    wire pixel_context_take=private_context_fire||(host_replay_context_valid&&host_replay_context_ready);
    wire pixel_pipeline_take=native_job_start||admission_take||pixel_context_take;
    frame_admission_qualification u_native_idle_publish(
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_available(native_pipeline_idle_now),
        .i_take(pixel_pipeline_take),.i_inhibit(1'b0),.o_available(native_pipeline_idle));
    // Each mode owns a different source fence. The inactive SDR fence is in
    // reset during HDR, so its reset-low idle cannot represent physical HDR
    // drain. Select only the actual clock/sensor mode, never the requested
    // tuple; global reset and clock hold remain fail-closed. Native/RAW/record
    // obligations remain independent terms in cfg_pipeline_idle below.
    // Data qualification uses the same local release before its reset-only
    // global distribution. All sequential ASR consumers retain pixel_rst_n.
    assign physical_source_idle=pixel_reset_local_n && camera_mode_running &&
        (stereo_mode_pixel ? stereo_source0_idle&&stereo_source1_idle&&hdr_cycle_quiet&&cam1_hdr_cycle_quiet :
             camera_hdr_mode ? hdr_cycle_quiet : raw_mode_pixel ? stereo_source0_idle&&hdr_cycle_quiet : physical_sdr_source_idle);
    frame_admission_qualification u_config_idle_publish(
        .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),
        .i_available(native_pipeline_idle&&live_f21_maintenance_quiet&&hdr_cycle_quiet&&
            (PHYSICAL_FRAME_FENCE_ENABLE==0||physical_source_idle)),
        .i_take(pixel_pipeline_take||physical_fs_take||
                (!stereo_mode_pixel&&!raw_mode_pixel&&native_identity_event)||raw_capture0_frame_accept),
        .i_inhibit(host_replay_context_owned||processing_context_owned||replay_active||physical_frame_enable),
        .o_available(cfg_pipeline_idle));
    generate if(VIDEO_SERVICE_ENABLE!=0) begin : g_preprocess
        wire [2:0] enables=job_schema2 ? {job_processing_enables[3],1'b0,job_processing_enables[0]} :
            job_mode==0 ? 3'b000 : job_mode==1 ? 3'b001 : job_mode==2 ? 3'b011 : 3'b101;
        if(S07_PROCESSING_ENABLE!=0) begin : g_advanced
        wire [1023:0] extension=capture0_algorithm_extension;
        wire [3:0] requested_features=stereo_mode_pixel ? 4'd0 : extension[`PCIE_CFG_EXT_OFFSET_ENABLE+4+:4];
        wire advanced_reset_n=private_processing_selected ? private_pp_reset_n : physical_processing_rst_n;
        reg private_error_fire,physical_error_fire;
        wire presented_pixels_clear=!preprocess_input_valid&&!preprocess_presented&&
            !processed_valid&&!jpeg_rgb_valid&&!admission_rgb_buffered;
        assign advanced_abort_fire=private_error_fire;
        assign physical_advanced_abort_fire=physical_error_fire;
        // Select the error at the opposite edge after every presented pixel
        // has really drained. Records remain owned until their normal READY.
        // Do not wait for JOIN quiet here: JOIN needs this actual terminal.
        always @(negedge pixel_clk or negedge pixel_posedge_reset_n) begin
            if(!pixel_posedge_reset_n) begin private_error_fire<=0;physical_error_fire<=0;end
            else begin
                private_error_fire<=advanced_abort_request&&private_processing_selected&&presented_pixels_clear;
                physical_error_fire<=physical_advanced_abort_request&&!private_processing_selected&&
                    presented_pixels_clear&&!camera_rgb_valid&&!cropped_raw_valid;
            end
        end
        // The actual input SOF is held while one frozen config starts every
        // shared numerical consumer. A job without input never reserves JOIN.
        wire cfg_start=job_pending&&preprocess_input_valid&&preprocess_input_sof&&
            advanced_join_ready&&record_builder_ready&&mask_begin_ready;
        wire cfg_rejected;
        reg [3:0] job_features;
        assign advanced_job_features=job_features;
        always @(posedge pixel_clk or negedge pixel_rst_n) begin
            if(!pixel_rst_n) job_features<=0;
            else if(cfg_start&&advanced_cfg_ready) job_features<=requested_features;
        end
        preprocess_advanced_pipeline4 #(.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
            .STRIPS(4),.CAMERA_CONTEXT_ENABLE(1)) u_preprocess (
            .clk(pixel_clk),.rst_n(advanced_reset_n),.cancel(1'b0),
            .cfg_valid(cfg_start),.cfg_ready(advanced_cfg_ready),.cfg_schema(8'd1),
            .cfg_context(neutral_record_context),.cfg_width(FRAME_WIDTH[12:0]),.cfg_height(FRAME_HEIGHT[12:0]),
            .cfg_pp_enable(requested_features[0] ? extension[`PCIE_CFG_EXT_OFFSET_PP_ENABLE+:3] : enables),
            .cfg_camera_id(private_processing_selected ? processing_frame[4] : 1'b0),
            .cfg_history_reset(physical_recovery_history_reset||((job_epoch!=previous_preprocess_epoch)&&
                (!requested_features[0]||extension[`PCIE_CFG_EXT_OFFSET_PP_HISTORY_RESET]))),
            .cfg_features(requested_features),
            .cfg_threshold(extension[`PCIE_CFG_EXT_OFFSET_THRESHOLD+:11]),
            .cfg_gx_min(extension[`PCIE_CFG_EXT_OFFSET_GX_MIN+:11]),
            .cfg_ratio_shift(extension[`PCIE_CFG_EXT_OFFSET_RATIO_SHIFT+:2]),
            .cfg_direction_sign(extension[`PCIE_CFG_EXT_OFFSET_DIRECTION_SIGN+:2]),
            .cfg_min_count(extension[`PCIE_CFG_EXT_OFFSET_MIN_COUNT+:20]),
            .cfg_min_paired_strips(extension[`PCIE_CFG_EXT_OFFSET_MIN_PAIRED_STRIPS+:4]),
            .cfg_strip_y_begin(extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_BEGIN+:52]),
            .cfg_strip_y_end(extension[`PCIE_CFG_EXT_OFFSET_STRIP_Y_END+:52]),
            .cfg_roi_left(extension[`PCIE_CFG_EXT_OFFSET_ROI_LEFT+:52]),
            .cfg_roi_split(extension[`PCIE_CFG_EXT_OFFSET_ROI_SPLIT+:52]),
            .cfg_roi_right(extension[`PCIE_CFG_EXT_OFFSET_ROI_RIGHT+:52]),
            .cfg_morph_mode(extension[`PCIE_CFG_EXT_OFFSET_MORPH_MODE+:3]),
            .cfg_min_curvature(extension[`PCIE_CFG_EXT_OFFSET_MIN_CURVATURE+:13]),
            .cfg_rejected(cfg_rejected),.cfg_error_code(),
            .s_valid(preprocess_input_valid),.s_ready(preprocess_input_ready),.s_data(preprocess_input_rgb),
            .s_sof(preprocess_input_sof),.s_eol(preprocess_input_eol),
            .s_frame_done(private_processing_selected ? private_notice_valid&&private_notice_ok : camera_done),
            .s_frame_error(advanced_abort_fire||physical_advanced_abort_fire||
                (private_processing_selected ? private_pp_error :
                (PHYSICAL_FRAME_FENCE_ENABLE!=0 && !job_is_replay ? 1'b0 : camera_error))),
            .m_valid(processed_valid),.m_ready(processed_ready),.m_data(processed_rgb),
            .m_luma(processed_luma),.m_sof(processed_sof),.m_eol(processed_eol),.m_camera_id(),
            .frame_done(),.frame_error(),.frame_context(),
            .computation_terminal_valid(advanced_terminal_valid),
            .computation_terminal_error(advanced_terminal_error),
            .computation_terminal_context(advanced_terminal_context),
            .o_presented_valid(preprocess_presented),
            .o_neutral_valid(neutral_tap_valid),.o_neutral_rgb(neutral_tap_rgb),
            .o_neutral_luma(neutral_tap_luma),.o_neutral_sof(neutral_tap_sof),
            .o_neutral_eol(neutral_tap_eol),.o_neutral_eof(neutral_tap_eof),
            .f22_record_valid(advanced_f22_valid),.f22_record_ready(advanced_f22_ready),.f22_record_data(advanced_f22_record),
            .f23_record_valid(advanced_f23_valid),.f23_record_ready(advanced_f23_ready),.f23_record_data(advanced_f23_record),
            .morph_valid(mask_morph_valid),.morph_ready(mask_morph_ready),.morph_mask(mask_morph),.morph_keep(mask_morph_keep),
            .morph_sof(mask_morph_sof),.morph_eol(mask_morph_eol),.morph_eof(mask_morph_eof),.morph_x(mask_morph_x),.morph_y(mask_morph_y),
            .morph_width(mask_morph_width),.morph_height(mask_morph_height),.morph_context(mask_morph_context),
            .f24_record_valid(advanced_f24_valid),.f24_record_ready(advanced_f24_ready),.f24_record_data(advanced_f24_record),
            .f25_record_valid(advanced_f25_valid),.f25_record_ready(advanced_f25_ready),.f25_record_data(advanced_f25_record),
            .f22_record_drops(),.f23_record_drops(),.f22_completed_count(),.f22_failed_count(),
            .f22_native_stall_count(),.f22_firstfault_code(),.f22_firstfault_context(),
            .f22_first_congestion_context(),.f22_max_low_resident(),.f22_max_grant_wait(),
            .f23_frames_started(),.f23_frames_finished(),.f23_frames_failed(),.f23_stray_terminals(),
            .f23_firstfault_valid(),.f23_firstfault_code(),.f23_firstfault_context(),
            .f24_record_drops(),.f24_overflow_frames(),.f24_max_queued(),.f24_first_overflow_context());
        assign processed_done=advanced_terminal_valid&&!advanced_terminal_error;
        assign processed_error=(advanced_terminal_valid&&advanced_terminal_error)||cfg_rejected;
        end else if(LIVE_F21_ENABLE)begin:g_live_f21
        assign advanced_abort_fire=1'b0;assign physical_advanced_abort_fire=1'b0;
        assign neutral_tap_valid=0;assign neutral_tap_rgb=0;assign neutral_tap_luma=0;
        assign neutral_tap_sof=0;assign neutral_tap_eol=0;assign neutral_tap_eof=0;
        assign he_source_ready=live_source_ready[0];
        // All measurement fields are from the real admitted frontend capsule.
        wire metadata_known=private_processing_selected ? processing_frame[0]&&processing_frame[334:319]==0 :
            capture0_metadata[196]&&capture0_metadata[195]&&capture0_metadata[127:112]==0;
        wire [31:0] product_exposure=private_processing_selected ? processing_frame[302:271] : capture0_metadata[95:64];
        wire [15:0] product_gain=private_processing_selected ? processing_frame[318:303] : capture0_metadata[111:96];
        wire [141:0] observation_context={job_session,job_epoch,product_exposure,product_gain,
            13'd1920,13'd1080,3'd0,metadata_known};
        wire [208:0] observation_cohort={observation_context,67'd0};
        (* preserve="true" *) reg processing_run=0;
        wire processing_async_n=private_processing_selected ? private_pp_reset_n : physical_processing_rst_n;
        always @(posedge pixel_clk)processing_run<=f21_core_reset_n&&processing_async_n;
        wire input_pending,output_pending,input_valid,input_ready,output_valid,output_ready;
        wire [97:0] input_word;
        wire [129:0] output_word;
        wire [95:0] core_rgb;
        wire [31:0] core_luma;
        wire core_sof,core_eol,core_done,core_error,core_presented,core_frame_quiet,core_maintenance_quiet;
        // Same logical PIX reset, before its reset-only global route.
        // This boundary has only synchronous ledger clear and external masks;
        // every original asynchronous storage reset retains its global copy.
        wire processing_data_async_n=private_processing_selected ? private_pp_data_rst_n : physical_processing_data_rst_n;
        wire boundary_async_n=f21_core_async_reset_n&&processing_data_async_n;
        stream_reset_boundary2 #(.WIDTH(98),.EXTERNAL_SOURCE(1)) u_input_boundary(
            .clk(pixel_clk),.run_n(processing_run),.async_n(boundary_async_n),
            .s_data({preprocess_input_sof,preprocess_input_eol,preprocess_input_rgb}),
            .s_valid(preprocess_input_valid),.s_ready(preprocess_input_ready),
            .m_data(input_word),.m_valid(input_valid),.m_ready(input_ready),.pending(input_pending));
        stream_reset_boundary2 #(.WIDTH(130),.EXTERNAL_SOURCE(0)) u_output_boundary(
            .clk(pixel_clk),.run_n(processing_run),.async_n(boundary_async_n),
            .s_data({core_sof,core_eol,core_luma,core_rgb}),.s_valid(output_valid),.s_ready(output_ready),
            .m_data(output_word),.m_valid(processed_valid),.m_ready(processed_ready),.pending(output_pending));
        assign {processed_sof,processed_eol,processed_luma,processed_rgb}=output_word;
        reg input_done_pending=0,input_done_seen=0,output_done_pending=0,output_error_pending=0;
        reg source_frame_begin_q=0,observation_abort_q=0,product_begin_q=0,frame_released_q=0,negative_q=0;
        reg filter_start_q=0,filter_error_q=0,config_applied_q=0;
        wire input_source_done=private_processing_selected ? private_notice_valid&&private_notice_ok : camera_done;
        wire input_frame_done=input_done_pending&&!input_pending;
        // Geometry termination follows the last stored pixel, not acceptance
        // into either boundary's queue. Reset discards the entire old frame.
        always @(posedge pixel_clk)begin
            if(!f21_core_reset_n||!processing_run||!boundary_async_n)begin
                input_done_pending<=0;input_done_seen<=0;output_done_pending<=0;output_error_pending<=0;
                source_frame_begin_q<=0;observation_abort_q<=0;product_begin_q<=0;frame_released_q<=0;negative_q<=0;
                filter_start_q<=0;filter_error_q<=0;config_applied_q<=0;
            end else begin
                source_frame_begin_q<=live_source_frame_begin;observation_abort_q<=live_observation_abort;
                product_begin_q<=admission_take;frame_released_q<=native_pipeline_idle;
                negative_q<=live_authenticated_negative;
                filter_start_q<=live_filter_start;filter_error_q<=live_filter_source_error;
                config_applied_q<=whole_config_ack_valid&&whole_config_ack_ready&&whole_config_ack_ok;
                if(input_frame_done)input_done_pending<=0;
                if(input_source_done&&!input_done_seen)begin input_done_pending<=1;input_done_seen<=1;end
                if(preprocess_input_valid&&preprocess_input_ready&&preprocess_input_sof)input_done_seen<=0;
                if(!output_pending)begin output_done_pending<=0;output_error_pending<=0;end
                if(core_done)output_done_pending<=1;
                if(core_error)output_error_pending<=1;
            end
        end
        assign processed_done=boundary_async_n&&output_done_pending&&!output_pending;
        assign processed_error=boundary_async_n&&output_error_pending&&!output_pending;
        assign preprocess_presented=core_presented||input_pending||output_pending;
        assign live_f21_frame_quiet=boundary_async_n&&core_frame_quiet&&!input_pending&&!output_pending&&
            !input_done_pending&&!output_done_pending&&!output_error_pending;
        assign live_f21_maintenance_quiet=boundary_async_n&&core_maintenance_quiet&&!input_pending&&!output_pending&&
            !input_done_pending&&!output_done_pending&&!output_error_pending;
        wire [1:0] source_valid_core,source_cancel_core,source_ready_core;
        wire [1:0] source_match_core,source_skip_core,source_cancel_done_core,source_accepted_core;
        wire filter_ready_core,filter_complete_core,filter_error_core;
        // A real kernel take removes its current owner-match immediately.
        // Keep that witness through the boundary's delayed ACK; READY here
        // comes only from its registered record of the genuine inner take.
        assign live_source_match={2{f21_core_async_reset_n}}&(source_match_core|live_source_ready);
        assign live_source_skip={2{f21_core_async_reset_n}}&source_skip_core;
        assign live_source_cancel_done={2{f21_core_async_reset_n}}&source_cancel_done_core;
        assign live_source_accepted={2{f21_core_async_reset_n}}&source_accepted_core;
        assign live_filter_start_ready=f21_core_async_reset_n&&filter_ready_core;
        assign live_filter_complete=f21_core_async_reset_n&&filter_complete_core;
        assign live_filter_error=f21_core_async_reset_n&&filter_error_core;
        wire [97:0] source_key_core;
        wire [96:0] source_key=private_processing_selected ?
            {processing_frame[4],processing_frame[76:45],processing_frame[140:109],processing_frame[108:77]} :
            {physical_native_source_context[282],physical_native_source_context[378:347],
             physical_native_source_context[346:315],physical_native_source_context[314:283]};
        source_terminal_sync_boundary u_source_boundary(
            .clk(pixel_clk),.run_n(f21_core_reset_n),.async_n(f21_core_async_reset_n),.frame_begin(live_source_frame_begin),
            .s_valid(live_source_valid),.s_cancel(live_source_cancel),.s_ready(live_source_ready),
            .s_key({private_processing_selected ? private_notice_ok : physical_native_source_ok,source_key}),
            .m_valid(source_valid_core),.m_cancel(source_cancel_core),.m_ready(source_ready_core),.m_key(source_key_core));
        wire f22_valid_core,f23_valid_core,stats_valid_core;
        reg [2:0] record_taken=0;
        wire [2:0] record_valid={stats_valid_core,f23_valid_core,f22_valid_core};
        wire [2:0] record_publish={3{f21_core_async_reset_n}}&record_valid&~record_taken;
        // Borrow held record data, but return each external take one clock
        // later. Asynchronous publication and consumer READY stop at this Q.
        always @(posedge pixel_clk)begin
            if(!f21_core_reset_n||!f21_core_async_reset_n)record_taken<=0;
            else record_taken<=record_publish&{live_neutral_stats_ready,live_filter_f23_ready,live_filter_f22_ready};
        end
        assign {live_neutral_stats_valid,advanced_f23_valid,advanced_f22_valid}=record_publish;
        preprocess_live_f21_service4 #(.STEREO_PASSTHROUGH_ENABLE(DUAL_CAMERA_ENABLE),.HE_FIXED_CONFIG_SESSION_ENABLE(R8_HE_FIXED_CONFIG_SESSION_ENABLE),
            .F21_FIXED_CONFIG_SESSION_ENABLE(R8_F21_FIXED_CONFIG_SESSION_ENABLE),.AUTO_FIXED_LUT_ENABLE(F21_AUTO_FIXED_LUT_ENABLE),.LANE_TAP_ENABLE(LIVE_LANE_ENABLE)) u_live(
            .clk(pixel_clk),.rst_n(f21_core_reset_n),.i_processing_rst_n(processing_run),
            .i_stereo_passthrough(stereo_mode_pixel),
            .cfg_filter_dehaze(capture0_schema2&&capture0_active_config[171]),
            .i_dehaze_terminal_valid(lane_source_fire),.i_dehaze_terminal_ok(lane_source_ok),
            .i_dehaze_terminal_key(source_key),
            .cfg_enable(enables),.cfg_history_reset(physical_recovery_history_reset||job_epoch!=previous_preprocess_epoch),
            .cfg_schema2(capture0_schema2),.cfg_filter_gray(capture0_filter_gray),.cfg_filter_legacy_gaussian(capture0_filter_legacy),
            .cfg_filter_color(capture0_schema2&&capture0_active_config[172]),
            .cfg_multiscale(!stereo_mode_pixel&&capture0_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F22]),
            .cfg_lane(!stereo_mode_pixel&&capture0_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_F23]),
            .cfg_filter_parameters(capture0_algorithm_extension),
            .i_filter_start_valid(filter_start_q),.i_filter_source_error(filter_error_q),
            .o_filter_start_ready(filter_ready_core),.o_filter_complete(filter_complete_core),.o_filter_error(filter_error_core),
            .o_filter_terminal_context(live_filter_terminal_context),
            .f22_record_valid(f22_valid_core),.f22_record_pending(advanced_f22_pending),.f22_record_ready(record_taken[0]),.f22_record_data(advanced_f22_record),
            .f23_record_valid(f23_valid_core),.f23_record_ready(record_taken[1]),.f23_record_data(advanced_f23_record),
            .lane_read_enable(lane_read_enable),.lane_read_index(lane_read_index),.lane_read_data(lane_read_data),.lane_read_valid(lane_read_valid),
            .cfg_he_history_eligible(he_history_eligible),
            .i_config_applied(config_applied_q),
            .frame_owner(private_processing_selected ? {32'd0,processing_write_tag} : physical_product_tag),.frame_capture(job_sequence),
            .frame_cohort(observation_cohort),.frame_context(neutral_record_context),
            .s_valid(input_valid),.s_ready(input_ready),.s_rgb(input_word[95:0]),
            .s_sof(input_word[97]),.s_eol(input_word[96]),.s_frame_done(input_frame_done),.s_frame_error(1'b0),
            .m_valid(output_valid),.m_ready(output_ready),.m_rgb(core_rgb),.m_y(core_luma),
            .m_sof(core_sof),.m_eol(core_eol),.m_frame_done(core_done),.m_frame_error(core_error),
            .o_presented(core_presented),.o_frame_quiet(core_frame_quiet),
             .o_maintenance_quiet(core_maintenance_quiet),.o_fault(live_f21_fault),
            .i_window_ready(lane_tap_ready),.o_window_valid(lane_tap_valid),.o_window_available(lane_tap_available),
            .o_window(lane_tap_window),.o_window_luma(lane_tap_luma),
            .o_window_sof(lane_tap_sof),.o_window_eol(lane_tap_eol),
            .i_abort_observation(observation_abort_q),.i_product_begin(product_begin_q),.i_frame_released(frame_released_q),
            .i_source_frame_begin(source_frame_begin_q),.i_authenticated_negative(negative_q),
            .m_stats_valid(stats_valid_core),.m_stats_ready(record_taken[2]),
            .m_stats_context(live_neutral_stats_context),.m_statistics(live_neutral_statistics),
            .source_valid(source_valid_core),.source_cancel(source_cancel_core),
             .source_ok(source_key_core[97]),.source_camera(source_key_core[96]),
            .source_session(source_key_core[95:64]),.source_epoch(source_key_core[63:32]),.source_capture(source_key_core[31:0]),
            .source_ready(source_ready_core),.source_owner_match(source_match_core),.source_skip(source_skip_core),
            .source_cancel_done(source_cancel_done_core),.source_accepted(source_accepted_core),
            .cfg_begin_valid(f21_cfg_begin_valid),.cfg_begin_ready(f21_cfg_begin_ready),.cfg_generation(f21_cfg_generation),
            .cfg_valid(f21_cfg_valid),.cfg_ready(f21_cfg_ready),.cfg_index(f21_cfg_index),.cfg_value(f21_cfg_value),
            .cfg_commit_valid(f21_cfg_commit_valid),.cfg_commit_ready(f21_cfg_commit_ready),.cfg_abort(f21_cfg_abort),
            .cfg_status_valid(f21_cfg_status_valid),.cfg_status_ready(f21_cfg_status_ready),.cfg_status_ok(f21_cfg_status_ok),
            .cfg_status_error(f21_cfg_status_error),.cfg_status_generation(f21_cfg_status_generation),
            .lut_valid(f21_lut_valid),.lut_generation(f21_lut_generation),
            .o_history_used(live_history_used),.o_history_age(),.o_frame_lut_generation(),.o_map_commit());
        end else begin : g_regular
        assign advanced_abort_fire=1'b0;
        assign physical_advanced_abort_fire=1'b0;
        preprocess_pipeline4 #(.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
            .GRAY_ONLY_ENABLE(R8_STAGE1_ENABLE && !R8_BASIC_PREPROCESS_ENABLE),
            .CAMERA_CONTEXT_ENABLE(!R8_BASIC_PREPROCESS_ENABLE),.SHARED_Y_PROFILE(1),
            .HE_SOURCE_QUALIFY_ENABLE(R8_BASIC_PREPROCESS_ENABLE),
            .HE_FIXED_CONFIG_SESSION_ENABLE(R8_HE_FIXED_CONFIG_SESSION_ENABLE),
            .HE_COLOR_PRESERVE(R8_BASIC_PREPROCESS_ENABLE),
            .NEUTRAL_TAP_ENABLE(NEUTRAL_STATS_ENABLE && (!NR_PROCESSING_ENABLE || SOURCE_SELECT==0))) u_preprocess (
            .clk(pixel_clk),.rst_n(private_processing_selected ? private_pp_reset_n : physical_processing_rst_n),
            .cfg_width(FRAME_WIDTH[12:0]),.cfg_height(FRAME_HEIGHT[12:0]),
            .cfg_enable(enables),.cfg_camera_id(private_processing_selected ? processing_frame[4] : 1'b0),
            .cfg_history_reset(physical_recovery_history_reset||job_epoch!=previous_preprocess_epoch),
            .s_valid(preprocess_input_valid),.s_ready(preprocess_input_ready),.s_data(preprocess_input_rgb),
            .s_sof(preprocess_input_sof),.s_eol(preprocess_input_eol),
            .s_frame_done(private_processing_selected ? private_notice_valid&&private_notice_ok : camera_done),
            .s_frame_error(private_processing_selected ? private_pp_error :
                (PHYSICAL_FRAME_FENCE_ENABLE!=0 && !job_is_replay ? 1'b0 : camera_error)),
            .m_valid(processed_valid),.m_ready(processed_ready),
            .m_data(processed_rgb),.m_sof(processed_sof),.m_eol(processed_eol),.m_frame_done(processed_done),
            .m_frame_error(processed_error),.m_camera_id(),.m_luma(processed_luma),
            .o_presented_valid(preprocess_presented),
            .o_neutral_valid(neutral_tap_valid),.o_neutral_rgb(neutral_tap_rgb),
            .o_neutral_luma(neutral_tap_luma),.o_neutral_sof(neutral_tap_sof),
            .o_neutral_eol(neutral_tap_eol),.o_neutral_eof(neutral_tap_eof),
            .i_window_ready(1'b1),.o_window_valid(),.o_window_available(),
            .o_window(),.o_window_luma(),.o_window_sof(),.o_window_eol(),
            .i_he_history_rst_n(R8_HE_FIXED_CONFIG_SESSION_ENABLE ? he_history_reset_n : pixel_rst_n),
            .cfg_he_context(he_history_context),.cfg_he_history_eligible(he_history_eligible),
            .cfg_he_capture_sequence(job_sequence),.i_he_source_valid(he_source_valid),
            .o_he_source_ready(he_source_ready),.i_he_source_camera(he_source_camera),
            .i_he_source_ok(he_source_ok),.i_he_source_session(he_source_session),
            .i_he_source_epoch(he_source_epoch),.i_he_source_sequence(he_source_sequence),
            .o_he_history_used(),.o_he_lut_valid(),.o_he_lut_source_sequence());
        end
    end else begin : g_legacy_preprocess
        assign advanced_abort_fire=1'b0;
        assign physical_advanced_abort_fire=1'b0;
        assign preprocess_input_ready=processed_ready;assign processed_rgb=preprocess_input_rgb;
        assign processed_valid=preprocess_input_valid;assign processed_sof=preprocess_input_sof;assign processed_eol=preprocess_input_eol;
        assign processed_done=camera_done;assign processed_error=camera_error;assign processed_luma=0;
        assign preprocess_presented=0;
        assign neutral_tap_valid=0;assign neutral_tap_rgb=0;assign neutral_tap_luma=0;
        assign neutral_tap_sof=0;assign neutral_tap_eol=0;assign neutral_tap_eof=0;
    end endgenerate
    generate if(S07_PROCESSING_ENABLE==0 && !LIVE_LANE_ENABLE) begin : g_no_advanced_records
        assign advanced_cfg_ready=1;assign advanced_terminal_valid=0;assign advanced_terminal_error=0;
        assign advanced_terminal_context=0;
        assign advanced_f22_valid=0;assign advanced_f23_valid=0;assign advanced_f24_valid=0;assign advanced_f25_valid=0;
        assign advanced_f22_record=0;assign advanced_f23_record=0;assign advanced_f24_record=0;assign advanced_f25_record=0;
        assign advanced_job_features=0;
    end endgenerate
    generate if(LIVE_LANE_ENABLE)begin:g_live_lane
        wire [1023:0] extension=capture0_algorithm_extension;
        wire [1:0] requested_features=stereo_mode_pixel ? 2'b0 : extension[`PCIE_CFG_EXT_OFFSET_ENABLE+4+:2];
        wire start_valid,start_ready,observe,source_error,discard_records,product_owned;
        wire complete,error,algorithm_ready;
        wire [7:0] error_code;
        wire [159:0] terminal_context;
        wire config_compatible=capture0_schema2||!requested_features[0] ||
            (capture0_active_config[65:64]==2 && extension[`PCIE_CFG_EXT_OFFSET_PP_ENABLE+:3]==3);
        wire owner_begin_ready;
        assign lane_capacity_ready=owner_begin_ready&&config_compatible;
        assign advanced_cfg_ready=lane_quiet;
        assign live_lane_product_owned=product_owned;
        assign advanced_terminal_context=neutral_record_context;
        assign lane_tap_ready=1'b1;
        assign live_filter_start=lane_owner_begin&&owner_begin_ready;
        assign live_filter_source_error=source_error;
        assign start_ready=live_filter_start_ready;
        assign complete=live_filter_complete;
        assign error=live_filter_error;
        assign terminal_context=live_filter_terminal_context;
        assign live_filter_f22_ready=product_owned?advanced_f22_ready:discard_records;
        assign live_filter_f23_ready=product_owned?advanced_f23_ready:discard_records;
        assign advanced_f24_valid=0;assign advanced_f24_record=0;
        assign advanced_f25_valid=0;assign advanced_f25_record=0;
        preprocess_live_lane_owner u_owner(
            .clk(pixel_clk),.rst_n(f21_core_reset_n),.begin_valid(lane_owner_begin),.begin_ready(owner_begin_ready),
            .frame_context(neutral_record_context),.begin_features(requested_features),
            .lane_start_ready(start_ready),.pyramid_valid(advanced_f22_valid),.lane_valid(advanced_f23_valid),
            .join_begin_ready(advanced_join_ready),.lane_start_valid(start_valid),.frame_features(advanced_job_features),
            .product_begin(admission_take),.extension_fire(record_source_extension_valid&&record_source_extension_ready),
            .source_fire(lane_source_fire),.source_ok(lane_source_ok),
            .foreground_done(processed_done),.foreground_error(processed_error),.foreground_quiet(live_f21_frame_quiet),
            .abort_frame(live_observation_abort),.lane_complete(complete),.lane_error(error),.lane_event_context(terminal_context),
            .lane_source_error(source_error),.tap_observe(observe),.discard_records(discard_records),
            .product_owned(product_owned),.terminal_valid(advanced_terminal_valid),.terminal_error(advanced_terminal_error),
            .o_quiet(lane_quiet),.o_fault(lane_fault));
        // F22/F23 arithmetic is now inside the shared post-F21 filter.
    end else begin:g_no_live_lane
        assign lane_capacity_ready=1;assign lane_quiet=1;assign lane_fault=0;assign lane_tap_ready=1;
        assign live_history_used=0;
        assign live_lane_product_owned=0;
        assign live_filter_start=0;assign live_filter_source_error=0;assign live_filter_f22_ready=0;assign live_filter_f23_ready=0;
    end endgenerate

    // The LIVE F22 queue may suppress VALID immediately on cancel. Quiet
    // waits for its accepted record to be retired or synchronously cleared.
    generate if(!(VIDEO_SERVICE_ENABLE!=0 && S07_PROCESSING_ENABLE==0 && LIVE_F21_ENABLE)) begin:g_no_live_f22_pending
        assign advanced_f22_pending=advanced_f22_valid;
    end endgenerate
    assign preprocess_records_quiet=lane_quiet&&advanced_cfg_ready&&advanced_join_ready&&
        !advanced_f22_pending&&!advanced_f23_valid&&!advanced_f24_valid&&!advanced_f25_valid;
    generate if(PRIVATE_PROCESSING_ENABLE!=0)begin : g_private_input_ready
        assign private_rgb_ready=private_processing_selected&&preprocess_input_ready;
        assign camera_rgb_ready=private_processing_selected ? private_isp_rgb_ready : preprocess_input_ready;
        assign replay_raw_ready=private_processing_selected ? private_replay_raw_ready : private_isp_raw_ready;
    end else begin : g_direct_input_ready
        assign camera_rgb_ready=preprocess_input_ready;
        assign replay_raw_ready=private_isp_raw_ready;
        assign private_rgb_ready=0;
        assign private_isp_raw=0;assign private_isp_raw_valid=0;
        assign private_isp_raw_sof=0;assign private_isp_raw_eol=0;
        assign private_isp_reset_n=pixel_rst_n;
        assign private_pp_reset_n=pixel_rst_n;assign private_pp_data_rst_n=pixel_reset_local_n;assign private_pp_error=0;
        assign private_rgb=0;assign private_rgb_valid=0;assign private_rgb_sof=0;assign private_rgb_eol=0;
        assign private_notice_valid=0;assign private_notice_ok=0;assign private_notice_error=0;assign private_isp_cleanup=0;
    end endgenerate
    generate if(!LIVE_F21_ENABLE && NEUTRAL_STATS_ENABLE!=0 && (NR_PROCESSING_ENABLE==0 || SOURCE_SELECT==0)) begin : g_neutral_stats
        wire stored_source=private_processing_selected || job_is_replay;
        wire [159:0] source_context={16'd1,16'd0,8'd1,
            stored_source ? {6'd0,job_source_frame[238:237]} : NATIVE_FORMAT,
            stored_source ? {7'd0,job_source_frame[3]} : RECORD_SOURCE_PHYSICAL,
            stored_source ? {7'd0,job_source_frame[4]} : 8'd0,
            job_sequence,job_epoch,job_session};
        neutral_record_observer4 #(.SOURCE_WIDTH(FRAME_WIDTH),.SOURCE_HEIGHT(FRAME_HEIGHT)) u_neutral (
            .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_tap_valid(neutral_tap_valid&&!private_processing_selected),
            .i_tap_rgb(neutral_tap_rgb),.i_tap_luma(neutral_tap_luma),
            .i_tap_sof(neutral_tap_sof),.i_tap_eol(neutral_tap_eol),.i_tap_eof(neutral_tap_eof),
            .i_source_abort(camera_error||processed_error||physical_source_failed),
            .i_context(source_context),.i_exposure(32'd0),.i_gain(16'd0),.i_product_begin(admission_take&&!private_processing_selected),.i_frame_released(native_pipeline_idle),
            // This statistics consumer drains the side pixels. DDR image export
            // is a separate consumer and is not advertised by this connection.
            .o_pixel_valid(),.i_pixel_ready(1'b1),.o_pixel_rgb(),.o_pixel_luma(),
            .o_pixel_sof(),.o_pixel_eol(),.o_pixel_last(),
            .m_stats_valid(live_neutral_stats_valid),.m_stats_ready(live_neutral_stats_ready),
            .m_stats_context(live_neutral_stats_context),.m_statistics(live_neutral_statistics),
            .i_f20_required(1'b0),.o_f20_pending(),.o_f20_owner_start(),.o_f20_status_valid(),.i_f20_status_ready(1'b1),
            .o_f20_context(),.o_f20_status_ok(),.o_f20_status_error(),.o_f20_sampled(),.o_f20_delivered(),
            .o_f20_width(),.o_f20_height(),.o_f20_exposure(),.o_f20_gain(),.o_observer_busy(),.o_dropped_frames());
    end else if(!LIVE_F21_ENABLE)begin : g_no_neutral_stats
        assign live_neutral_stats_valid=0;assign live_neutral_stats_context=0;assign live_neutral_statistics=0;
    end endgenerate
    generate if(NR_PROCESSING_ENABLE==0)begin : g_live_statistics_select
        assign neutral_stats_valid=live_neutral_stats_valid;
        assign neutral_stats_context=live_neutral_stats_context;
        assign neutral_statistics=live_neutral_statistics;
        assign live_neutral_stats_ready=neutral_stats_ready;
    end else begin : g_private_statistics_select
        assign live_neutral_stats_ready=!private_processing_selected&&neutral_stats_ready;
    end endgenerate
    assign record_source_fault=record_ordered_source_fault || record_builder_fault || record_replay_binding_fault;
    assign host_replay_context_ready=RECORD_METADATA_ENABLE!=0 && !private_processing_selected &&
        !host_replay_context_owned&&native_pipeline_idle&&physical_source_idle&&
        record_product_available&&!record_format_busy_pixel[1]&&!f21_lut_update_busy;
    // Actual admission allocates separate PRODUCT64 and writer32 namespaces.
    // Neither counter may wrap inside a cohort; the last tag remains usable.
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            record_product_next_tag<=1;record_admitted_write_tag<=0;
            record_writer_next_tag<=1;record_admitted_writer_tag<=0;
            record_product_advance_pending<=0;record_writer_advance_pending<=0;
            record_product_tag_exhausted<=0;record_writer_tag_exhausted<=0;
            record_format_busy_pixel<=0;host_replay_context_owned<=0;
            host_replay_saved_frame<=0;host_replay_saved_metadata_valid<=0;
            record_replay_binding_fault<=0;
        end else begin
            // Admission consumes the current namespaces on its original edge.
            // The real admission FSM leaves IDLE after take, so update the
            // unowned next values one edge later using local, narrow enables.
            // MAX/exhaustion remains authoritative on the admission edge.
            record_product_advance_pending<=admission_take&&RECORD_METADATA_ENABLE!=0&&
                !(&record_product_next_tag);
            record_writer_advance_pending<=admission_take&&RECORD_METADATA_ENABLE!=0&&
                !private_processing_selected&&!(&record_writer_next_tag);
            if(record_product_advance_pending)
                record_product_next_tag<=record_product_next_tag+64'd1;
            if(record_writer_advance_pending)
                record_writer_next_tag<=record_writer_next_tag+32'd1;
            record_format_busy_pixel<={record_format_busy_pixel[0],record_format_busy};
            if(host_replay_context_valid&&host_replay_context_ready) begin
                host_replay_context_owned<=1;host_replay_saved_frame<=host_replay_context_frame;
                host_replay_saved_metadata_valid<=host_replay_metadata_valid;
            end
            if(native_job_start&&native_job_replay&&!private_processing_selected&&RECORD_METADATA_ENABLE!=0) begin
                if(!host_replay_context_owned)record_replay_binding_fault<=1;
                host_replay_context_owned<=0;
            end
            if(!private_processing_selected&&host_replay_context_owned&&
                (raw_replay_native_done||raw_replay_native_error))host_replay_context_owned<=0;
            if(admission_take&&RECORD_METADATA_ENABLE!=0) begin
                record_admitted_write_tag<=record_product_next_tag;
                record_admitted_writer_tag<=private_processing_selected ? processing_write_tag : record_writer_next_tag;
                if(&record_product_next_tag)record_product_tag_exhausted<=1;
                if(!private_processing_selected) begin
                    if(&record_writer_next_tag)record_writer_tag_exhausted<=1;
                end
                if(!record_product_available)record_replay_binding_fault<=1;
            end
        end
    end
    reg [31:0] admitted_session,admitted_epoch;
    reg admitted_camera;
    reg [7:0] admitted_quality;
    reg [15:0] admitted_restart;
    reg [7:0] admitted_requested,admitted_minimum;
    reg admitted_adaptive;
    reg [24:0] admitted_budget;
    wire [31:0] quality_over_budget_count;
    wire [7:0] quality_degradation_reason;
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if(!pixel_rst_n) begin
            admitted_session<=0;admitted_epoch<=0;admitted_camera<=0;admitted_quality<=75;
            admitted_requested<=75;admitted_minimum<=1;admitted_adaptive<=0;admitted_budget<=0;
            admitted_mask<=0;admitted_source_type<=0;
        end
        else if(admission_take) begin
            admitted_session<=job_session;admitted_epoch<=job_epoch;admitted_quality<=job_quality;
            admitted_camera<=private_processing_selected ? processing_frame[4] :
                (RECORD_METADATA_ENABLE!=0 && job_is_replay ? job_source_frame[4] : 1'b0);
            admitted_requested<=job_requested_quality;admitted_minimum<=job_minimum_quality;
            admitted_adaptive<=job_adaptive;admitted_budget<=job_budget;
            admitted_mask<=MASK_ENABLE!=0&&advanced_job_features[2];
            admitted_source_type<={neutral_record_context[104],neutral_record_context[113:112]};
        end
    end
    // Only the encoder consumes restart_mcus, after admission has reserved its
    // first group and left IDLE. Pre-sample the unowned value on that same
    // admission edge; hold it through START/RUN/result/credit retirement.
    // This keeps the late admission/reset cone off the 16-bit payload CE.
    always @(posedge pixel_clk) begin
        if(admission_state_idle) admitted_restart<=job_restart;
    end
    jpeg_quality_controller u_quality_control (
        .clk(pixel_clk),.rst_n(pixel_rst_n),
        .adaptive_enable(R8_FIXED_JPEG_ENABLE ? 1'b0 : (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_active_config[73] : cfg_adaptive)),
        .requested_quality(R8_FIXED_JPEG_ENABLE ? 8'd75 : (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? {1'b0,capture0_active_config[72:66]} : cfg_quality)),
        .minimum_quality(R8_FIXED_JPEG_ENABLE ? 8'd75 : (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? {1'b0,capture0_active_config[80:74]} : cfg_min_quality)),
        .frame_budget(R8_FIXED_JPEG_ENABLE ? 25'd0 : (PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_active_config[105:81] : cfg_budget)),
        .mode_epoch(PHYSICAL_FRAME_FENCE_ENABLE!=0 ? capture0_active_config[159:128] : cfg_epoch),
        .frame_begin(admission_take),.frame_complete(jpeg_result_valid && jpeg_result_ready),
        .frame_ok(jpeg_result_ok),.completed_length(jpeg_result_length),.selected_quality(selected_quality),
        .over_budget_count(quality_over_budget_count),.degradation_reason(quality_degradation_reason));
    // 取得空闲槽位信用后才接收完整图像帧，并关联编码结果
    jpeg_frame_admission #(.EXTERNAL_SEQUENCE_ENABLE(VIDEO_SERVICE_ENABLE),.SHARED_LUMA_ENABLE(VIDEO_SERVICE_ENABLE)) u_admission (
        .i_clk(pixel_clk), .i_rst_n(pixel_rst_n),
        .i_credit_grant(credit_grant_pixel), .i_credit_ack(credit_ack_pixel),
        .i_session_armed(armed_pixel[1]), .i_app_enable(enable_pixel[1]),
        .o_replay_ready_boundary(replay_admission_ready),
        .o_credit_request(credit_request_pixel), .o_credit_take(admission_take),
        .i_fault(fault_pixel[1] || recovery_pixel[1]),
        .i_rgb_data(processed_rgb), .i_rgb_valid(processed_valid),.i_luma(processed_luma),.i_frame_sequence(job_sequence),
        .o_rgb_ready(processed_ready), .i_rgb_sof(processed_sof),
        .i_rgb_eol(processed_eol),
        .i_camera_done(private_processing_selected ? private_jpeg_source_done :
            (PHYSICAL_FRAME_FENCE_ENABLE!=0 && !job_is_replay ? physical_source_done : processed_done)),
        .i_camera_error(private_processing_selected ? private_jpeg_source_error :
            (PHYSICAL_FRAME_FENCE_ENABLE!=0 && !job_is_replay ? physical_source_failed : processed_error)),
        .o_jpeg_rgb(jpeg_rgb),.o_jpeg_luma(jpeg_luma),
        .o_jpeg_valid(jpeg_rgb_valid), .i_jpeg_ready(jpeg_rgb_ready),
        .o_jpeg_sof(jpeg_sof), .o_jpeg_eol(jpeg_eol),
        .o_start_valid(start_valid), .i_start_ready(start_ready),
        .i_time_ns(RECORD_METADATA_ENABLE!=0 ? job_timestamp :
            (private_processing_selected ? processing_frame[204:141] : pixel_ticks)),
        .o_timestamp_ns(capture_time),
        .o_capture_id(capture_id), .o_status_valid(status_valid),
        .i_status_ready(status_ready), .o_status_id(status_id),
        .o_status_ok(status_ok), .i_result_valid(jpeg_result_valid),
        .i_result_ready(jpeg_result_ready), .i_result_id(jpeg_result_id),
        .o_diag_state(diag_admission_state),.o_protocol_fault(admission_protocol_fault), .o_active(frame_active_pixel),
        .o_rgb_buffered(admission_rgb_buffered),.o_state_idle(admission_state_idle)
    );
    // True FS/FE owns the physical frame beyond the cropped geometry.
    // This capsule is SOURCE data, not a fabricated RAW slot descriptor.
    generate if(PHYSICAL_FRAME_FENCE_ENABLE!=0) begin : g_physical_source
        reg [63:0] source_tag_counter,source_tag;
        assign physical_product_tag=source_tag;
        reg [575:0] source_capsule_q;
        reg native_owned,crop_geometry_seen,rgb_geometry_seen,camera_geometry_seen;
        reg raw_terminal_taken,early_failure,cleanup_notified,native_tail_closed;
        reg binding_fault;
        reg he_pp_sof_seen;
        // Exhaustion requires a new cohort; never reuse an old SOURCE tag.
        wire [63:0] next_tag=(&source_tag_counter) ? 64'hffffffffffffffff : source_tag_counter+64'd1;
        wire [575:0] source_capsule={capture0_metadata,capture0_session,capture0_epoch,
            capture0_sequence,1'b0,282'd0};
        wire context_ready;
        wire context_fire=!camera_hdr_mode&&capture0_valid&&capture0_accept&&capture0_sof&&context_ready;
        // Register the true owner handshake alongside the frozen capsule/tag.
        // Both consumers and the terminal broker start from the same local Q.
        reg context_begin_q;
        always @(posedge pixel_clk or negedge f21_core_async_reset_n)begin
            if(!f21_core_async_reset_n)context_begin_q<=0;
            else context_begin_q<=context_fire;
        end
        wire crop_quiet=!cropped_raw_valid;
        wire raw_fire=physical_raw_source_valid&&physical_raw_source_ready;
        // The frontend selects its incoming SOF capsule from raw_fire. Terminal
        // authentication must use the admitted capsule, independent of READY.
        wire raw_exact=physical_raw_source_session==source_capsule_q[378:347]&&
            physical_raw_source_epoch==source_capsule_q[346:315]&&physical_raw_source_sequence==source_capsule_q[314:283]&&
            !physical_raw_source_camera;
        wire source_exact=physical_native_source_context==source_capsule_q&&
            physical_native_source_tag==source_tag&&source_tag!=0;
        wire source_fire=physical_native_source_valid&&physical_native_source_ready;
        wire scoped_pipeline_error=native_owned&&!rgb_geometry_seen&&(camera_error||processed_error);
        wire all_presented_clear=!camera_rgb_valid&&!preprocess_presented&&!processed_valid&&
            !admission_rgb_buffered&&!jpeg_rgb_valid;
        wire cleanup_complete,cleanup_pending,cleanup_fault;
        wire early_negative=raw_fire&&raw_exact&&
            (!physical_raw_source_ok||early_failure||scoped_pipeline_error);
        // A later processing failure can follow a held positive RAW terminal.
        // It still belongs to the same frozen tag and needs local tail cleanup.
        wire late_negative=native_owned&&early_failure&&raw_terminal_taken&&
            crop_quiet&&!cleanup_notified;
        // The first negative RAW handshake arms cleanup before the fence can
        // publish native SOURCE, including an error after complete geometry.
        wire cleanup_required=cleanup_notified||early_negative||late_negative||early_failure;
        wire rgb_quiet=!native_owned || (all_presented_clear&&
            (cleanup_required ? cleanup_complete :
                (camera_geometry_seen&&rgb_geometry_seen&&native_job_idle)));
        // The fence owns and holds the authentic capsule until both existing
        // native retirement and HE consume this one terminal. Early positive
        // SOURCE cannot be discarded while PP has not established its owner.
        assign physical_live_observation_abort=LIVE_F21_ENABLE&&(early_negative||late_negative||scoped_pipeline_error);
        assign physical_live_source_frame_begin=LIVE_F21_ENABLE&&context_begin_q;
        assign physical_lane_owner_begin=LIVE_LANE_ENABLE&&context_begin_q&&native_owned;
        assign physical_lane_source_fire=LIVE_LANE_ENABLE&&source_fire&&source_exact&&native_owned;
        assign physical_lane_source_ok=physical_native_source_ok;
        assign physical_live_authenticated_negative=LIVE_F21_ENABLE&&physical_native_source_valid&&source_exact&&native_owned&&!physical_native_source_ok;
        if(LIVE_F21_ENABLE)begin:g_source_broadcast
            wire rejected;
            wire source_ready_core,source_done_core,source_failed_core;
            assign physical_native_source_ready=f21_core_async_reset_n&&source_ready_core;
            assign physical_source_done=f21_core_async_reset_n&&source_done_core;
            assign physical_source_failed=f21_core_async_reset_n&&source_failed_core;
            source_terminal_broadcast u_broadcast(
                .clk(pixel_clk),.rst_n(f21_core_reset_n),.frame_begin(context_begin_q),.frame_owned(native_owned),
                .cancel(early_failure||live_f21_fault),
                .frame_required(2'b01),
                .owner_context(source_capsule_q),.owner_tag(source_tag),.source_context(physical_native_source_context),.source_tag(physical_native_source_tag),
                .source_valid(physical_native_source_valid),.source_ok(physical_native_source_ok),.source_ready(source_ready_core),
                .consumer_owner_match(live_source_match),.consumer_ready(live_source_ready),.consumer_skip(live_source_skip),
                .consumer_cancel_done(live_source_cancel_done),.consumer_valid(physical_live_source_valid),.consumer_cancel(physical_live_source_cancel),
                .native_done(source_done_core),.native_failed(source_failed_core),.rejected(rejected),.done_mask());
            assign he_source_valid=physical_live_source_valid[0];
            assign he_source_ok=physical_native_source_ok;assign he_source_camera=physical_native_source_context[282];
            assign he_source_session=physical_native_source_context[378:347];assign he_source_epoch=physical_native_source_context[346:315];
            assign he_source_sequence=physical_native_source_context[314:283];
        end else begin:g_single_he_source
            assign physical_live_source_valid=0;assign physical_live_source_cancel=0;
        assign he_source_valid=R8_BASIC_PREPROCESS_ENABLE && physical_native_source_valid &&
            source_exact && native_owned && (!physical_native_source_ok || he_pp_sof_seen);
        assign he_source_ok=physical_native_source_ok;
        assign he_source_camera=physical_native_source_context[282];
        assign he_source_session=physical_native_source_context[378:347];
        assign he_source_epoch=physical_native_source_context[346:315];
        assign he_source_sequence=physical_native_source_context[314:283];
        assign physical_native_source_ready=!R8_BASIC_PREPROCESS_ENABLE || !source_exact || !native_owned ||
            ((!physical_native_source_ok || he_pp_sof_seen) && he_source_ready);
        assign physical_source_done=source_fire&&source_exact&&native_owned&&physical_native_source_ok;
        assign physical_source_failed=source_fire&&source_exact&&native_owned&&!physical_native_source_ok;
        end
        always @(posedge pixel_clk or negedge pixel_rst_n) begin
            if(!pixel_rst_n) begin
                source_tag_counter<=0;source_tag<=0;source_capsule_q<=0;native_owned<=0;
                crop_geometry_seen<=0;rgb_geometry_seen<=0;camera_geometry_seen<=0;
                raw_terminal_taken<=0;early_failure<=0;cleanup_notified<=0;native_tail_closed<=0;binding_fault<=0;
                he_pp_sof_seen<=0;
            end else begin
                if(capture0_geometry_done)crop_geometry_seen<=1;
                if(native_owned&&camera_done)camera_geometry_seen<=1;
                if(native_owned&&processed_done)rgb_geometry_seen<=1;
                if(preprocess_input_valid&&preprocess_input_ready&&preprocess_input_sof&&native_owned&&
                   job_session==source_capsule_q[378:347]&&job_epoch==source_capsule_q[346:315]&&
                   job_sequence==source_capsule_q[314:283]&&!job_is_replay)
                    he_pp_sof_seen<=1;
                if(scoped_pipeline_error || capture0_abort)early_failure<=1;
                if(raw_fire)begin
                    if(raw_exact)begin
                        raw_terminal_taken<=1;
                        if(!physical_raw_source_ok)early_failure<=1;
                    end else binding_fault<=1;
                end
                if(early_negative||late_negative)cleanup_notified<=1;
                // Ordered FE/ABORT precedes the authenticated RAW terminal;
                // crop quiet drains its only held output and OWNED blocks FS.
                // This is a per-context terminal proof, not a delayed VALID.
                if((early_negative||late_negative)&&crop_quiet)native_tail_closed<=1;
                if(source_fire)begin
                    if(!source_exact)binding_fault<=1;
                    if(source_exact)begin native_owned<=0;he_pp_sof_seen<=0;end
                end
                if(context_fire) begin
                    if(&source_tag_counter)binding_fault<=1;
                    source_tag_counter<=next_tag;source_tag<=next_tag;
                    source_capsule_q<=source_capsule;
                    native_owned<=!physical_stored_policy&&native_job_start&&!native_job_replay;
                    crop_geometry_seen<=capture0_geometry_done;rgb_geometry_seen<=0;camera_geometry_seen<=0;
                    raw_terminal_taken<=0;early_failure<=0;cleanup_notified<=0;native_tail_closed<=0;
                    he_pp_sof_seen<=0;
                end else if(native_job_start&&!native_job_replay&&physical_frame_enable&&!physical_capture_private)
                    native_owned<=1;
            end
        end
        if(S07_PROCESSING_ENABLE!=0)begin : g_advanced_cleanup
            localparam [2:0] CLEAN_IDLE=0,CLEAN_REQUEST=1,CLEAN_TERMINAL=2,
                CLEAN_RECORDS=3,CLEAN_ARM=4,CLEAN_CLEAR=5;
            reg [2:0] cleanup_state;
            reg [1:0] clear_cycles;
            reg pp_admitted,terminal_seen,clear_active,source_closed,local_fault;
            reg cleanup_pulse;
            wire tail_quiet=preprocess_records_quiet && all_presented_clear && crop_quiet &&
                jpeg_idle && !frame_active_pixel && !start_valid && !status_valid &&
                !jpeg_result_valid && !record_source_extension_valid;
            wire terminal_fire=advanced_terminal_valid&&advanced_terminal_context==neutral_record_context;
            assign physical_advanced_abort_request=cleanup_state==CLEAN_REQUEST&&!terminal_seen&&!terminal_fire;
            assign cleanup_pending=cleanup_state!=CLEAN_IDLE;
            assign cleanup_complete=source_closed;
            assign cleanup_fault=local_fault;
            assign physical_processing_rst_n=pixel_rst_n && !clear_active;
            assign physical_processing_data_rst_n=pixel_reset_local_n && !clear_active;
            assign physical_cleanup_pulse=cleanup_pulse;
            always @(negedge pixel_clk or negedge pixel_posedge_reset_n)begin
                if(!pixel_posedge_reset_n)clear_active<=0;
                else if(cleanup_state==CLEAN_ARM && tail_quiet && !native_owned)clear_active<=1;
                else if(cleanup_state==CLEAN_IDLE)clear_active<=0;
            end
            always @(posedge pixel_clk or negedge pixel_rst_n)begin
                if(!pixel_rst_n)begin
                    cleanup_state<=CLEAN_IDLE;clear_cycles<=0;pp_admitted<=0;terminal_seen<=0;
                    source_closed<=0;local_fault<=0;cleanup_pulse<=0;
                end else begin
                    cleanup_pulse<=0;
                    if(context_fire)begin
                        pp_admitted<=0;terminal_seen<=0;source_closed<=0;
                        if(cleanup_state!=CLEAN_IDLE)local_fault<=1;
                    end
                    if(!private_processing_selected && !job_is_replay &&
                        preprocess_input_valid&&preprocess_input_ready&&preprocess_input_sof)
                        pp_admitted<=1;
                    if(native_owned&&terminal_fire)
                        terminal_seen<=1;
                    case(cleanup_state)
                        CLEAN_IDLE:if((early_negative||late_negative)&&native_owned)
                            cleanup_state<=pp_admitted&&!terminal_seen&&!terminal_fire ? CLEAN_REQUEST : CLEAN_TERMINAL;
                        CLEAN_REQUEST:if(physical_advanced_abort_fire||terminal_seen||terminal_fire)cleanup_state<=CLEAN_TERMINAL;
                        // SOURCE closes before JOIN retirement: that SOURCE is
                        // itself required by the neutral statistics/record path.
                        CLEAN_TERMINAL:if((!pp_admitted||terminal_seen||terminal_fire)&&all_presented_clear&&crop_quiet)begin
                            source_closed<=1;cleanup_state<=CLEAN_RECORDS;
                        end
                        CLEAN_RECORDS:if(tail_quiet&&!native_owned)cleanup_state<=CLEAN_ARM;
                        CLEAN_ARM:if(clear_active)begin
                            cleanup_state<=CLEAN_CLEAR;clear_cycles<=2;cleanup_pulse<=1;
                        end else if(!tail_quiet)cleanup_state<=CLEAN_RECORDS;
                        CLEAN_CLEAR:if(clear_cycles!=0)clear_cycles<=clear_cycles-1'b1;
                            else cleanup_state<=CLEAN_IDLE;
                        default:local_fault<=1;
                    endcase
                end
            end
        end else begin : g_regular_cleanup
        assign physical_advanced_abort_request=1'b0;
        wire local_cleanup_pending,local_cleanup_complete,cleanup_source_fire;
        wire cleanup_status_ready;
        if(LIVE_F21_ENABLE)begin:g_live_record_drain
            reg failed_pending,source_closed,source_retired,clear_started;
            reg previous_pixels_quiet;
            // Cancel already stops unpublished LIVE pixels. Its real failed
            // F22/F23 records outlive those pixels and still belong to JOIN.
            // Close SOURCE before waiting for the records that need SOURCE;
            // clear ISP/preprocess only after their actual extension/result.
            wire pixels_quiet=native_tail_closed&&crop_quiet&&all_presented_clear;
            wire record_tail_quiet=preprocess_records_quiet&&all_presented_clear&&crop_quiet&&
                jpeg_idle&&!frame_active_pixel&&!start_valid&&!status_valid&&
                !jpeg_result_valid&&!record_source_extension_valid;
            assign cleanup_complete=source_closed;
            assign cleanup_pending=failed_pending||local_cleanup_pending;
            assign cleanup_source_fire=failed_pending&&source_retired&&!clear_started&&record_tail_quiet;
            // The original local-clear helper's STATUS acknowledges the SOURCE
            // already consumed by this exact context, never a new completion.
            assign cleanup_status_ready=source_retired;
            always @(posedge pixel_clk or negedge pixel_rst_n)begin
                if(!pixel_rst_n)begin
                    failed_pending<=0;source_closed<=0;source_retired<=0;clear_started<=0;
                    previous_pixels_quiet<=0;
                end else begin
                    previous_pixels_quiet<=pixels_quiet;
                    if((early_negative||late_negative)&&native_owned)failed_pending<=1;
                    if(failed_pending&&pixels_quiet&&previous_pixels_quiet)source_closed<=1;
                    if(physical_source_failed)source_retired<=1;
                    if(cleanup_source_fire)clear_started<=1;
                    if(local_cleanup_complete&&source_retired)failed_pending<=0;
                    if(context_fire)begin
                        failed_pending<=0;source_closed<=0;source_retired<=0;clear_started<=0;
                        previous_pixels_quiet<=0;
                    end
                end
            end
        end else begin:g_direct_clear
            assign cleanup_complete=local_cleanup_complete;
            assign cleanup_pending=local_cleanup_pending;
            assign cleanup_source_fire=early_negative||late_negative;
            assign cleanup_status_ready=source_fire&&source_exact&&!physical_native_source_ok;
        end
        hdr_pair_product_abort_drain4 #(.SYNC_CLEAR_ENABLE(1),.SEPARATE_DATA_RESET(1),.FALLING_INPUT_RESET(1)) u_cleanup(
            .clk(pixel_clk),.rst_n(pixel_rst_n),.i_context_fire(context_fire),.i_context_tag(next_tag),
            .i_source_fire(cleanup_source_fire),.i_source_tag(source_tag),
            .i_source_ok(1'b0),.i_source_read_quiescent(crop_quiet),
            .i_native_job_start(native_job_start&&!native_job_replay&&physical_frame_enable&&!physical_capture_private),
            .i_native_valid(!native_tail_closed),.i_isp_valid(camera_rgb_valid),
            .i_preprocess_valid(preprocess_presented||processed_valid),
            .i_admission_valid(admission_rgb_buffered||jpeg_rgb_valid),
            .o_local_rst_n(physical_processing_rst_n),
            .i_data_reset_n(pixel_reset_local_n),.o_local_data_rst_n(physical_processing_data_rst_n),
            .o_drain_pending(local_cleanup_pending),
            .o_failed_status_valid(local_cleanup_complete),
            .i_failed_status_ready(cleanup_status_ready),
            .o_protocol_fault(cleanup_fault),.o_stale_source_count(),.o_cleanup_pulse(physical_cleanup_pulse));
        end
        // Keep an already queued next FS while the previous LIVE JPEG retires.
        // FE/ABORT always pass; disabled, paused or faulted sessions still drain.
        wire fence_event_ready;
        reg deferred_fs,fs_qualification_seen;
        wire physical_admission_credit;
        assign mono_source_recovery_quiet=physical_sdr_source_idle&&native_pipeline_idle&&
            native_pipeline_idle_now&&raw_capture0_idle&&raw_capture1_idle&&
            crop_quiet&&all_presented_clear&&!cleanup_pending&&!cleanup_fault&&
            !binding_fault&&!capture_frontend_fault&&!host_replay_context_owned&&!processing_context_owned;
        wire physical_admission_inhibit=stereo_mode_pixel||raw_mode_pixel||stereo_pause_pixel||physical_hdr_requested||!cfg_source_ready||cfg_pause||capture_config_valid||
            local_stop_pause||reset_pause_pixel||live_source_block||!enable_pixel[1]||!armed_pixel[1]||
            recovery_pixel[1]||fault_pixel[1]||replay_active||pixel_context_request||
            host_replay_context_owned||processing_context_owned||camera_receive_fault||physical_identity_quarantine||
            capture_frontend_fault||binding_fault||cleanup_fault||cleanup_pending||!camera_mode_running||!camera_sdr_profile_matches;
        // First offered physical FS after positive CFG ACK is observed even
        // when admission cannot accept it. Never feed these taps into READY.
        assign cfg_diag_source_fs=physical_event_valid&&physical_event_kind==2'd0;
        assign cfg_diag_admission_faults={cleanup_fault,binding_fault,capture_frontend_fault,
            camera_source_identity_fault,physical_identity_quarantine};
        assign cfg_diag_source_gates={physical_admission_inhibit,camera_receive_fault,
            camera_mode_running,record_format_busy_pixel[1],record_product_available,
            physical_sdr_source_idle,physical_admit_enable,native_pipeline_idle,
            live_source_block,local_stop_pause,reset_pause_pixel,capture_config_valid,
            cfg_pause,cfg_source_ready,armed_pixel[1],enable_pixel[1]};
        frame_admission_qualification u_admission_credit(
            .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),
            .i_available(physical_admit_enable&&native_pipeline_idle_now&&raw_capture0_idle&&
                physical_sdr_source_idle&&record_product_available&&!record_format_busy_pixel[1]&&!(&source_tag_counter)),
            .i_take(physical_fs_take),.i_inhibit(physical_admission_inhibit),.o_available(physical_admission_credit));
        assign physical_fs_take=physical_event_valid&&mono_physical_event_ready&&physical_event_kind==2'd0;
        wire defer_permitted=!stereo_mode_pixel&&!raw_mode_pixel&&!stereo_pause_pixel&&R8_STAGE1_ENABLE && physical_admit_enable &&
            enable_pixel[1] && armed_pixel[1] &&
            !replay_active && !camera_receive_fault && !physical_identity_quarantine && !capture_frontend_fault &&
            !binding_fault && !cleanup_fault && !cleanup_pending &&
            !fault_pixel[1] && !recovery_pixel[1];
        wire defer_next_fs=defer_permitted && physical_event_kind==2'd0 &&
            (!fs_qualification_seen || !native_pipeline_idle || live_source_block || pixel_context_request||
                host_replay_context_owned||processing_context_owned||(deferred_fs &&
                (!replay_admission_ready || !record_product_available)));
        assign mono_physical_event_ready=fence_event_ready && !defer_next_fs;
        // Once held across retirement, keep the same FS until the real writer
        // credit and metadata owner are ready. An unrelated FS arriving with
        // no prior work still follows the normal no-credit discard policy.
        always @(posedge pixel_clk or negedge pixel_rst_n) begin
            if(!pixel_rst_n)begin deferred_fs<=0;fs_qualification_seen<=0;end
            else begin
                if(!defer_permitted || !physical_event_valid ||
                    physical_event_kind!=2'd0 || mono_physical_event_ready)begin
                    deferred_fs<=0;fs_qualification_seen<=0;
                end else begin
                    fs_qualification_seen<=1;
                    if(!native_pipeline_idle)deferred_fs<=1;
                end
            end
        end
        physical_identity_source_fence #(.SEPARATE_DATA_RESET(1)) u_fence(
            .i_clk(pixel_clk),.i_rst_n(pixel_rst_n&&camera_mode_running&&!camera_hdr_mode&&!stereo_mode_pixel&&!raw_mode_pixel),
            .i_data_reset_n(pixel_reset_local_n&&camera_mode_running&&!camera_hdr_mode&&!stereo_mode_pixel&&!raw_mode_pixel),
            .i_admit_enable(physical_admission_credit),
            .i_event_valid(physical_event_valid&&!defer_next_fs),.o_event_ready(fence_event_ready),
            .i_event_kind(physical_event_kind),.i_event_ok(physical_event_ok),.i_event_error({4'd0,physical_event_error}),
            .i_event_sequence(physical_event_sequence),.i_event_identity_valid(physical_event_identity_valid),
            .i_continuity_fault(physical_identity_quarantine),
            .i_context_valid(capture0_valid&&capture0_accept&&capture0_sof),.o_context_ready(context_ready),
            .i_context(source_capsule),.i_context_tag(next_tag),.i_context_session(capture0_session),
            .i_context_epoch(capture0_epoch),.i_context_sequence(capture0_sequence),.i_context_camera(1'b0),
            .i_crop_geometry_done(capture0_geometry_done),.i_crop_input_quiet(crop_quiet),
            .i_rgb_geometry_done(physical_capture_private ? capture0_geometry_done : processed_done&&native_owned),.i_rgb_output_quiet(physical_capture_private ? crop_quiet : rgb_quiet),
            .i_source_fault(capture0_abort||scoped_pipeline_error),.i_source_error(8'd1),
            .o_capture_frame_enable(physical_frame_enable),.o_source_idle(physical_sdr_source_idle),
            .o_raw_source_valid(physical_raw_source_valid),.i_raw_source_ready(physical_raw_source_ready),
            .o_raw_source_session(physical_raw_source_session),.o_raw_source_epoch(physical_raw_source_epoch),
            .o_raw_source_sequence(physical_raw_source_sequence),.o_raw_source_camera(physical_raw_source_camera),
            .o_raw_source_ok(physical_raw_source_ok),.o_raw_source_error(physical_raw_source_error),
            .o_native_source_valid(physical_native_source_valid),.i_native_source_ready(physical_native_source_ready),
            .o_native_source_context(physical_native_source_context),.o_native_source_tag(physical_native_source_tag),
            .o_native_source_ok(physical_native_source_ok),.o_native_source_error(physical_native_source_error),
            .o_drop_count(),.o_stale_event_count());
        wire unused_geometry=crop_geometry_seen^admission_state_idle;
    end else begin : g_geometry_source
        assign mono_source_recovery_quiet=1'b0;
        assign cfg_diag_source_fs=1'b0;assign cfg_diag_source_gates=16'd0;
        assign cfg_diag_admission_faults=5'd0;
        assign physical_fs_take=0;
        assign physical_product_tag=0;
        assign physical_live_source_valid=0;assign physical_live_source_cancel=0;
        assign physical_live_source_frame_begin=0;assign physical_live_observation_abort=0;
        assign physical_live_authenticated_negative=0;assign physical_lane_owner_begin=0;
        assign physical_lane_source_fire=0;assign physical_lane_source_ok=0;
        assign he_source_valid=0;assign he_source_ok=0;assign he_source_camera=0;
        assign he_source_session=0;assign he_source_epoch=0;assign he_source_sequence=0;
        assign physical_advanced_abort_request=1'b0;
        assign physical_processing_rst_n=pixel_rst_n;assign physical_processing_data_rst_n=pixel_reset_local_n;assign physical_cleanup_pulse=0;
        assign mono_physical_event_ready=1;assign physical_frame_enable=0;assign physical_sdr_source_idle=1;
        assign physical_raw_source_valid=0;assign physical_raw_source_session=0;
        assign physical_raw_source_epoch=0;assign physical_raw_source_sequence=0;
        assign physical_raw_source_camera=0;assign physical_raw_source_ok=0;assign physical_raw_source_error=0;
        assign physical_native_source_valid=0;assign physical_native_source_ready=0;
        assign physical_native_source_context=0;assign physical_native_source_tag=0;
        assign physical_native_source_ok=0;assign physical_native_source_error=0;
        assign physical_source_done=0;assign physical_source_failed=0;
    end endgenerate
    wire [127:0] jpeg_data;
    wire [15:0] jpeg_keep;
    wire jpeg_valid, jpeg_ready, jpeg_last;
    wire [7:0] jpeg_result_error;
    // 编码器输出 JPEG 字节流，结束结果另行携带实际长度与错误
    jpeg_encoder_top #(.MAX_WIDTH(JPEG_STORAGE_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
        // Keep one four-pixel encoder. Use the native synchronous ERAM banks
        // for the DCT and quantizer scratch rather than replicated LUT RAM.
        .SHARED_STREAM_ENABLE(VIDEO_SERVICE_ENABLE),.TINY_DISTRIBUTED_RAM_ENABLE(0),
        .COEFF_BANKED_STORAGE_ENABLE(R8_STAGE1_ENABLE),.MCU_ROW_STREAM_ENABLE(R8_STAGE1_ENABLE),
        .FIXED_GEOMETRY_ENABLE(R8_STAGE1_ENABLE && FRAME_WIDTH%240==0 && FRAME_HEIGHT%8==0)) u_jpeg (
        .i_clk(pixel_clk), .i_rst_n(pixel_data_reset_n[0]),
        .i_rgb(jpeg_rgb), .i_rgb_valid(jpeg_rgb_valid),
        .i_luma(jpeg_luma),.i_quality(R8_FIXED_JPEG_ENABLE ? 8'd75 : admitted_quality),.i_session_id(admitted_session),
        .i_mode_epoch(admitted_epoch),.i_camera_id(admitted_camera),.i_restart_mcus(R8_FIXED_JPEG_ENABLE ? 16'd0 : admitted_restart),
        .o_rgb_ready(jpeg_rgb_ready), .i_sof(jpeg_sof), .i_eol(jpeg_eol),
        .i_capture_id(capture_id), .i_width(FRAME_WIDTH[12:0]), .i_height(FRAME_HEIGHT[12:0]),
        .i_frame_status_valid(status_valid), .o_frame_status_ready(status_ready),
        .i_frame_status_id(status_id), .i_frame_ok(status_ok),
        .o_axis_tdata(jpeg_data), .o_axis_tkeep(jpeg_keep),
        .o_axis_tvalid(jpeg_valid), .i_axis_tready(jpeg_ready),
        .o_axis_tlast(jpeg_last), .o_result_valid(jpeg_result_valid),
        .i_result_ready(jpeg_result_ready), .o_result_id(jpeg_result_id),
        .o_result_ok(jpeg_result_ok), .o_payload_length(jpeg_result_length),
        .o_error_code(jpeg_result_error),.o_result_quality(jpeg_actual_quality),.o_result_epoch(jpeg_actual_epoch),.o_idle(jpeg_idle)
    );

    wire ddr_start_valid, ddr_jpeg_valid, ddr_jpeg_last;
    wire ddr_start_ready, ddr_jpeg_ready;
    wire ddr_result_valid, ddr_result_ready, ddr_result_ok;
    wire [31:0] ddr_capture_id, ddr_result_id;
    wire [15:0] ddr_width, ddr_height, ddr_jpeg_keep;
    wire [63:0] ddr_timestamp;
    wire [127:0] ddr_jpeg_data;
    wire [24:0] ddr_result_length;
    wire [7:0] ddr_result_error;
    wire [31:0] ddr_session,ddr_epoch,ddr_actual_epoch;
    wire ddr_camera;
    wire [7:0] ddr_quality,ddr_actual_quality;
    wire [31:0] ddr_write_tag;
    assign mask_allocation_context={16'd1,16'd0,8'd1,{6'd0,ddr_start_source_type[1:0]},
        {7'd0,ddr_start_source_type[2]},{7'd0,ddr_camera},ddr_capture_id,ddr_epoch,ddr_session};
    assign bridge_fault=record_ordered_fault || record_metadata_fault;
    generate if(RECORD_METADATA_ENABLE!=0) begin : g_record_builder
        wire stored_source=private_processing_selected || job_is_replay;
        wire measured_source=stored_source&&job_source_metadata_valid;
        wire [1023:0] context2_extension;
        wire context2_valid,context2_ready,context2_begin_ready,context2_fault;
        wire join_fault;
        assign record_builder_ready=context2_begin_ready&&advanced_join_ready&&mask_begin_ready;
        assign record_builder_fault=context2_fault||join_fault||lane_fault;
        // Physical SOF time is independently observed. An old HOST slot with
        // unknown measurement metadata publishes UNKNOWN time, never NOW.
        frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(NEUTRAL_STATS_ENABLE),
            .OBSERVATION_WIDTH(NEUTRAL_STATS_ENABLE ? FRAME_WIDTH/6 : 320),
            .OBSERVATION_HEIGHT(NEUTRAL_STATS_ENABLE ? FRAME_HEIGHT/6 : 180),.SEPARATE_DATA_RESET(1)) u_builder(
            .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),.i_data_reset_n(pixel_posedge_reset_n),
            .s_begin_valid(admission_take),.o_begin_ready(context2_begin_ready),
            .i_source_session(job_session),.i_source_epoch(job_epoch),.i_source_sequence(job_sequence),
            .i_source_camera(stored_source ? {7'd0,job_source_frame[4]} : 8'd0),
            .i_source_kind(stored_source ? {7'd0,job_source_frame[3]} : RECORD_SOURCE_PHYSICAL),
            .i_source_format(stored_source ? {6'd0,job_source_frame[238:237]} : NATIVE_FORMAT),
            .i_exposure_role(measured_source ? {6'd0,job_source_frame[2:1]} : 8'd0),
            .i_exposure_valid(measured_source),.i_actual_exposure(job_source_frame[302:271]),
            .i_exposure_group(job_source_frame[366:335]),
            .i_gain_valid(measured_source),.i_actual_gain(job_source_frame[334:303]),
            .i_calibration_valid(measured_source),.i_calibration_id(job_source_frame[270:239]),
            .i_time_quality(!stored_source || measured_source || (private_processing_selected&&job_source_frame[3]) ? RECORD_TIME_COMMON : RECORD_TIME_UNKNOWN),
            .i_pair_valid(private_processing_selected && processing_pair_id!=0),.i_pair_id(processing_pair_id),
            .i_job_valid(private_processing_selected),.i_job_id(processing_job_id),
            .i_write_tag_valid(1'b1),.i_write_tag(record_product_next_tag),
            .i_qualified(measured_source&&job_source_frame[0]),
            .i_processing_member(private_processing_selected ? {7'd0,processing_member} : 8'd0),
            .i_processing_mode(job_processing_mode),.i_record_flags({13'd0,live_history_used,1'b0,hdr_processing_selected}),
            .s_stats_valid(neutral_stats_valid),.o_stats_ready(neutral_stats_ready),
            .s_stats_context(neutral_stats_context),.s_statistics(neutral_statistics),
            .m_extension_valid(context2_valid),.m_extension_ready(context2_ready),
            .m_extension_data(context2_extension),.o_stale_count(),.o_error_count(),.o_input_fault(context2_fault));
        if(RECORD_V3_ENABLE!=0) begin : g_v3
            frame_record_v3_join #(.SEPARATE_DATA_RESET(1)) u_join(
                .i_clk(pixel_clk),.i_rst_n(pixel_branch_reset_n[3]),.i_data_reset_n(pixel_data_reset_n[6]),
                .s_begin_valid(admission_take),.o_begin_ready(advanced_join_ready),
                .s_begin_context(neutral_record_context),.s_begin_features(advanced_job_features),
                .s_terminal_valid(advanced_terminal_valid),.s_terminal_error(advanced_terminal_error),
                .s_terminal_context(advanced_terminal_context),
                .s_context2_extension(context2_extension),.s_context2_valid(context2_valid),.o_context2_ready(context2_ready),
                .s_f22_record(advanced_f22_record),.s_f22_valid(advanced_f22_valid&&(!LIVE_LANE_ENABLE||live_lane_product_owned)),.o_f22_ready(advanced_f22_ready),
                .s_f23_record(advanced_f23_record),.s_f23_valid(advanced_f23_valid&&(!LIVE_LANE_ENABLE||live_lane_product_owned)),.o_f23_ready(advanced_f23_ready),
                .s_f24_record(advanced_f24_record),.s_f24_valid(advanced_f24_join_valid),.o_f24_ready(advanced_f24_join_ready),
                .s_f25_record(advanced_f25_record),.s_f25_valid(advanced_f25_valid),.o_f25_ready(advanced_f25_ready),
                .m_extension(record_source_extension),.m_extension_valid(record_source_extension_valid),
                .m_extension_ready(record_source_extension_ready),
                .i_stream_start(record_extension_stream_start),.m_stream_data(record_extension_stream_data),
                .m_stream_valid(record_extension_stream_valid),.m_stream_ready(record_extension_stream_ready),
                .o_lane_read_enable(lane_read_enable),.o_lane_read_index(lane_read_index),
                .i_lane_read_data(lane_read_data),.i_lane_read_valid(lane_read_valid),.o_fault(join_fault),.o_stale_count());
        end else begin : g_v2
            assign advanced_join_ready=1;assign join_fault=0;
            assign advanced_f22_ready=1;assign advanced_f23_ready=1;assign advanced_f24_join_ready=1;assign advanced_f25_ready=1;
            assign record_source_extension=context2_extension;assign record_source_extension_valid=context2_valid;
            assign context2_ready=record_source_extension_ready;
        end
    end else begin : g_legacy_record_builder
        assign record_builder_ready=1;assign record_builder_fault=0;
        assign neutral_stats_ready=1;
        assign record_source_extension=0;assign record_source_extension_valid=0;
        assign advanced_join_ready=1;
        assign advanced_f22_ready=1;assign advanced_f23_ready=1;assign advanced_f24_join_ready=1;assign advanced_f25_ready=1;
    end endgenerate
    // 将开始、JPEG 数据和结束结果按顺序跨入 DDR 域
    ordered_frame_cdc #(.CONTEXT_ENABLE(VIDEO_SERVICE_ENABLE),.WRITE_TAG_ENABLE(PRIVATE_PROCESSING_ENABLE || RECORD_METADATA_ENABLE),
        .RECORD_EXTENSION_ENABLE(RECORD_METADATA_ENABLE),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),
        .BORROW_EXTENSION(1),.STREAM_EXTENSION(1),.MASK_CONTEXT_ENABLE(MASK_ENABLE),.EXTENSION_RAM_ENABLE(RECORD_METADATA_ENABLE)) u_jpeg_to_ddr (
        .i_source_clk(pixel_clk), .i_source_rst_n(pixel_branch_reset_n[3]),
        .i_start_valid(start_valid), .o_start_ready(start_ready),
        .i_capture_id(capture_id), .i_width(FRAME_WIDTH[15:0]),
        .i_height(FRAME_HEIGHT[15:0]), .i_timestamp_ns(capture_time),
        .i_session_id(admitted_session),.i_mode_epoch(admitted_epoch),.i_camera_id(admitted_camera),
        .i_write_tag(RECORD_METADATA_ENABLE!=0 ? record_admitted_writer_tag : processing_write_tag),
        .i_start_mask(admitted_mask),.i_start_source_type(admitted_source_type),.o_start_mask(ddr_start_mask),.o_start_source_type(ddr_start_source_type),
        .i_quality(admitted_quality),.i_format(8'd1),.i_result_quality(jpeg_actual_quality),.i_result_epoch(jpeg_actual_epoch),
        .i_jpeg_tdata(jpeg_data), .i_jpeg_tkeep(jpeg_keep),
        .i_jpeg_tlast(jpeg_last), .i_jpeg_tvalid(jpeg_valid),
        .o_jpeg_tready(jpeg_ready), .i_result_valid(jpeg_result_valid),
        .o_result_ready(jpeg_result_ready), .i_result_id(jpeg_result_id),
        .i_result_ok(jpeg_result_ok), .i_result_length(jpeg_result_length),
        .i_result_error(jpeg_result_error),
        .i_record_extension(record_source_extension),.i_record_extension_valid(record_source_extension_valid),
        .i_extension_stream_data(record_extension_stream_data),.i_extension_stream_valid(record_extension_stream_valid),
        .o_extension_stream_ready(record_extension_stream_ready),.o_extension_stream_start(record_extension_stream_start),
        .o_record_extension_ready(record_source_extension_ready),.o_source_protocol_fault(record_ordered_source_fault),
        .o_record_extension(record_dfi_extension),.o_record_extension_valid(record_dfi_extension_valid),
        .i_record_extension_ready(record_dfi_extension_ready),
        .o_extension_shape_valid(record_extension_shape_valid),
        .i_extension_read_enable(record_extension_read_enable),.i_extension_read_index(record_extension_read_index),
        .o_extension_read_data(record_extension_read_data),
        .i_sink_clk(dfi_clk), .i_sink_rst_n(dfi_rst_n),
        .o_start_valid(ddr_start_valid), .i_start_ready(ddr_start_ready),
        .o_capture_id(ddr_capture_id), .o_width(ddr_width),
        .o_height(ddr_height), .o_timestamp_ns(ddr_timestamp),
        .o_session_id(ddr_session),.o_mode_epoch(ddr_epoch),.o_camera_id(ddr_camera),.o_quality(ddr_quality),.o_format(),.o_write_tag(ddr_write_tag),
        .o_result_quality(ddr_actual_quality),.o_result_epoch(ddr_actual_epoch),
        .o_jpeg_tdata(ddr_jpeg_data), .o_jpeg_tkeep(ddr_jpeg_keep),
        .o_jpeg_tlast(ddr_jpeg_last), .o_jpeg_tvalid(ddr_jpeg_valid),
        .i_jpeg_tready(ddr_jpeg_ready), .o_result_valid(ddr_result_valid),
        .i_result_ready(ddr_result_ready), .o_result_id(ddr_result_id),
        .o_result_ok(ddr_result_ok), .o_result_length(ddr_result_length),
        .o_result_error(ddr_result_error), .o_protocol_fault(record_ordered_fault),
        .i_fence_request(reset_marker_request),.i_source_fence_idle(cfg_pipeline_idle),
        .i_source_fence_session(cfg_session),.i_sink_fence_session(dfi_active_config[63:32]),
        .i_raw_enqueued(reset_raw_enqueued),.i_raw_consumed(reset_raw_consumed),
        .i_raw_consume_fire(raw_capture0_consume_fire),.i_sink_fence_quiet(record_dfi_data_quiescent),
        .o_source_fence_proven(reset_source_proven),.o_source_fence_fault(reset_source_fault),.o_sink_fence_fault(reset_sink_fault),
        .o_source_reset_done(token_src_reset_done),
        .o_sink_reset_done(token_sink_reset_done)
    );
    // C21_POLICY_PUBLISH_BEGIN
    // The complete policy is captured in its owning domain before CDC. These
    // are ordinary local timing paths, never additional asynchronous FIRSTs.
    // The final publication adds one PIX/USER edge to DFI policy observation.
    // APP reset asserts PIX pause immediately; USER ownership reset clears
    // enable. Neither publication FF resets any accepted owner or slot.
    reg cfg_pause_publish,host_enable_publish;
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)cfg_pause_publish<=1'b1;
        else cfg_pause_publish<=cfg_pause;
    end
    always @(posedge user_clk or negedge user_rst_n)begin
        if(!user_rst_n)host_enable_publish<=1'b0;
        else host_enable_publish<=app_enable&&!reset_pending_user&&!transport_recovery;
    end
    // The frozen production image has DEBUG_UART_ENABLE=0. Its SYS boot mux
    // only hands over while APP reset is held; no live SYS policy enters this
    // USER publisher. UART LOCAL retains its original explicit debug branch
    // and requires a separate source/CDC qualification if selected later.
    wire pairbank_enable_published=DEBUG_UART_ENABLE!=0 ? effective_app_enable : host_enable_publish;
    // C21_POLICY_PUBLISH_END
    // Only single-bit admission requests cross here. Pair authority/counters
    // stay on the cold identity reset and cannot disappear with application reset.
    always @(posedge dfi_clk or negedge hdr_identity_reset_n)begin
        if(!hdr_identity_reset_n)begin
            pairbank_enable_meta<=0;pairbank_enable_sync<=0;
            pairbank_pause_meta<=0;pairbank_pause_sync<=0;
        end else begin
            pairbank_enable_meta<=pairbank_enable_published;pairbank_enable_sync<=pairbank_enable_meta;
            pairbank_pause_meta<=cfg_pause_publish;pairbank_pause_sync<=pairbank_pause_meta;
        end
    end
    wire pairbank_run_dfi_n;
    // Preserve immediate STOP assertion; qualify reset release only in DFI.
    // Ownership, epoch and real drain/retirement remain on their cold cohort.
    reset_release_sync u_pairbank_run_dfi_reset(.i_clk(dfi_clk),
        .i_async_rst_n(pixel_rst_n && dfi_rst_n && f21_core_async_reset_n),
        .o_rst_n(pairbank_run_dfi_n));
    assign pairbank_stop=!pairbank_enable_sync || pairbank_pause_sync ||
        hdr_ticket_recovery || !pairbank_run_dfi_n || store_recovery;
    generate if(HDR_PROCESSING_ENABLE!=0)begin : g_hdr_source
        shared_raw10_decode_service #(.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)) u_decode_service(
            .clk(dfi_clk),.rst_n(hdr_identity_reset_n),
            .hdr_start_valid(hdr_decode_start),.hdr_start_ready(hdr_decode_start_ready),
            .hdr_release(hdr_decode_release),.hdr_abort(hdr_decode_abort),
            .hdr_member(hdr_decode_member),.hdr_data(hdr_decode_data),.hdr_keep(hdr_decode_keep),
            .hdr_valid(hdr_decode_valid),.hdr_last(hdr_decode_last),.hdr_ready(hdr_decode_ready),
            .hdr_raw_member(hdr_decode_raw_member),.hdr_raw(hdr_decode_raw),
            .hdr_raw_valid(hdr_decode_raw_valid),.hdr_raw_ready(hdr_decode_raw_ready),
            .hdr_done(hdr_decode_done),.hdr_aborted(hdr_decode_aborted),
            .stereo_start_valid(stereo_decode_start),.stereo_start_ready(stereo_decode_start_ready),
            .stereo_release(stereo_decode_release),.stereo_cancel(stereo_decode_cancel),.stereo_run(stereo_decode_run),
            .stereo_data(stereo_decode_data),.stereo_keep(stereo_decode_keep),
            .stereo_valid(stereo_decode_valid),.stereo_last(stereo_decode_last),.stereo_ready(stereo_decode_ready),
            .stereo_raw(stereo_decode_raw),.stereo_raw_valid(stereo_decode_raw_valid),.stereo_raw_ready(stereo_decode_raw_ready),
            .stereo_sof(stereo_decode_sof),.stereo_eol(stereo_decode_eol),
            .stereo_done(stereo_decode_done),.stereo_aborted(stereo_decode_aborted),.stereo_quiet(stereo_decode_quiet),.stereo_active(stereo_decode_active),.quiet());
        // Canonical FETCH/RETIRE uses the original RAW store/cache and AXI
        // client. Both full-capacity reader FIFOs feed the existing replay
        // FIFO, never a duplicate ISP/post/context transport.
        hdr_pair_native_source_service4 #(.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
            .CANONICAL_READ_ENABLE(1),.SHARED_NATIVE_ENABLE(1),.EXTERNAL_DECODER(1)) u_native_source(
            .i_identity_rst_n(hdr_identity_reset_n),.i_pair_bank(pairbank_bank),
            .i_dfi_clk(dfi_clk),.i_pixel_clk(pixel_clk),
            .i_dfi_rst_n(pixel_rst_n&&dfi_rst_n&&f21_core_async_reset_n),
            .i_pixel_rst_n(pixel_rst_n&&dfi_rst_n&&f21_core_async_reset_n),
            .s_context_valid(hdr_context_valid),.s_context_ready(hdr_context_ready),
            .s_start_valid(hdr_start_valid),.s_start_ready(hdr_start_ready),
            .s_long_frame(hdr_job_frame0),.s_short_frame(hdr_job_frame1),
            .s_long_lease(hdr_job_lease0),.s_short_lease(hdr_job_lease1),
            .s_long_tag(hdr_long_tag),.s_short_tag(hdr_short_tag),.s_job_id(hdr_job_id),.s_pair_id(hdr_pair_id),
            .i_ratio_log2(3'd4),
            .i_black_long(10'd50),
            .i_black_short(10'd50),
            .i_motion_base(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_HDR_MOTION_BASE+:14]),
            .i_motion_shift(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_HDR_MOTION_SHIFT+:4]),
            .i_hdr_max_delta_ns(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_HDR_MAX_DELTA_NS+:64]),
            .i_cancel_valid(hdr_cancel_valid),.o_cancel_ready(hdr_cancel_ready),
            .i_result_transport_enable(hdr_transport_enable),.m_result_valid(hdr_result_valid),
            .m_result_ready(hdr_result_ready),.m_result_ok(hdr_result_ok),.o_first_error(hdr_result_error),
            .o_reader_error(),.o_reader_fault(hdr_reader_fault),.o_source_fault(hdr_source_fault),
            .o_pixel_fault(hdr_pixel_fault),.o_read_quiescent(hdr_reader_quiet),
            .o_source_reset_done(hdr_source_reset_done),.o_pixel_reset_done(),
            .o_decode_start_valid(hdr_decode_start),.i_decode_start_ready(hdr_decode_start_ready),
            .o_decode_release(hdr_decode_release),.o_decode_abort(hdr_decode_abort),
            .o_decode_member(hdr_decode_member),.o_decode_data(hdr_decode_data),.o_decode_keep(hdr_decode_keep),
            .o_decode_valid(hdr_decode_valid),.o_decode_last(hdr_decode_last),.i_decode_ready(hdr_decode_ready),
            .i_decode_raw_member(hdr_decode_raw_member),.i_decode_raw(hdr_decode_raw),
            .i_decode_raw_valid(hdr_decode_raw_valid),.o_decode_raw_ready(hdr_decode_raw_ready),
            .i_decode_done(hdr_decode_done),.i_decode_aborted(hdr_decode_aborted),
            .m_context(hdr_pixel_context),.m_context_valid(hdr_pixel_context_valid),.m_context_ready(hdr_pixel_context_ready),
            .m_raw_capsule(hdr_raw_capsule),.m_keep(),.m_sof(hdr_raw_sof),.m_eol(hdr_raw_eol),
            .m_last(),.m_valid(hdr_raw_valid),.m_bad(),.m_ready(hdr_raw_ready),.m_tag(),.m_index(),
            .m_source_valid(hdr_raw_source_valid),.m_source_ready(hdr_raw_source_ready),
            .m_source_tag(hdr_raw_source_tag),.m_source_ok(hdr_raw_source_ok),
            .m_source_error(hdr_raw_source_error),.m_source_groups(),
            .i_shared_source_phase_owned(hdr_phase_owned),.i_shared_pixel_phase_owned(shared_processing_selected),
            .i_shared_pixel_context({processing_lease,processing_job_id,processing_job_id,processing_frame}),
            .i_shared_pixel_owner_prepared(processing_pixel_busy&&!processing_context_owned),
            .m_shared_fifo_data(hdr_fifo_source),.m_shared_fifo_valid(hdr_fifo_source_valid),
            .i_shared_fifo_ready(hdr_fifo_source_ready),.i_shared_fifo_source_reset_done(hdr_fifo_source_reset_done),
            .s_shared_fifo_data(hdr_fifo_sink),.s_shared_fifo_valid(hdr_fifo_sink_valid),
            .m_shared_fifo_ready(hdr_fifo_sink_ready),.i_shared_fifo_sink_reset_done(hdr_fifo_sink_reset_done),
            .m_private_req_valid(hdr_private_req_valid),.m_private_req_ready(hdr_private_req_ready),
            .m_private_req_op(hdr_private_req_op),.m_private_req_camera(hdr_private_req_camera),.m_private_req_slot(hdr_private_req_slot),
            .m_private_req_generation(hdr_private_req_generation),.m_private_req_session(hdr_private_req_session),
            .m_private_req_offset(hdr_private_req_offset),.m_private_req_length(hdr_private_req_length),
            .m_private_req_private(),.m_private_req_lease(hdr_private_req_lease),.m_private_req_job_id(hdr_private_req_job_id),
            .s_private_rsp_valid(raw_private_rsp_valid&&hdr_phase_owned),.s_private_rsp_ready(hdr_private_rsp_ready),
            .s_private_rsp_code(raw_private_rsp_code),.s_private_rsp_descriptor(raw_private_rsp_descriptor),
            .s_private_rsp_metadata_valid(raw_private_rsp_metadata_valid),
            .s_private_read_data(raw_private_read_data),.s_private_read_keep(raw_private_read_keep),
            .s_private_read_valid(raw_private_read_valid),.s_private_read_last(raw_private_read_last),
            .s_private_read_ready(raw_private_read_ready),.i_private_read_complete(raw_private_read_complete),
            .i_private_read_error(raw_private_read_error),.i_private_protocol_fault(raw_private_read_fault||store_recovery),
            .m_axi_arid(hdr_reader_axi_arid),.m_axi_araddr(hdr_reader_axi_araddr),.m_axi_arlen(hdr_reader_axi_arlen),.m_axi_arsize(hdr_reader_axi_arsize),.m_axi_arburst(hdr_reader_axi_arburst),.m_axi_arvalid(hdr_reader_axi_arvalid),
            .m_axi_arready(hdr_reader_axi_arready),.m_axi_rid(hdr_reader_axi_rid),.m_axi_rdata(hdr_reader_axi_rdata),.m_axi_rresp(hdr_reader_axi_rresp),
            .m_axi_rlast(hdr_reader_axi_rlast),.m_axi_rvalid(hdr_reader_axi_rvalid),.m_axi_rready(hdr_reader_axi_rready));
    end else begin : g_no_hdr_source
        assign hdr_decode_start=0;assign hdr_decode_release=0;assign hdr_decode_abort=0;assign hdr_decode_member=0;
        assign hdr_decode_data=0;assign hdr_decode_keep=0;assign hdr_decode_valid=0;assign hdr_decode_last=0;
        assign hdr_decode_raw_ready=0;
        assign hdr_decode_start_ready=0;assign hdr_decode_ready=0;assign hdr_decode_raw_member=0;
        assign hdr_decode_raw=0;assign hdr_decode_raw_valid=0;assign hdr_decode_done=0;assign hdr_decode_aborted=0;
        assign stereo_decode_start_ready=0;assign stereo_decode_ready=0;assign stereo_decode_raw=0;assign stereo_decode_raw_valid=0;
        assign stereo_decode_sof=0;assign stereo_decode_eol=0;assign stereo_decode_done=0;assign stereo_decode_aborted=0;assign stereo_decode_quiet=1;assign stereo_decode_active=0;
        assign hdr_context_ready=0;assign hdr_start_ready=0;assign hdr_cancel_ready=0;
        assign hdr_result_valid=0;assign hdr_result_ready=0;assign hdr_result_ok=0;assign hdr_result_error=0;
        assign hdr_reader_fault=0;assign hdr_source_fault=0;assign hdr_pixel_fault=0;assign hdr_reader_quiet=1;
        assign hdr_source_reset_done=1;assign hdr_pixel_context=0;assign hdr_pixel_context_valid=0;
        assign hdr_raw_capsule=0;assign hdr_raw_valid=0;assign hdr_raw_sof=0;assign hdr_raw_eol=0;
        assign hdr_raw_source_valid=0;assign hdr_raw_source_ok=0;assign hdr_raw_source_tag=0;assign hdr_raw_source_error=0;
        assign hdr_fifo_source=0;assign hdr_fifo_source_valid=0;assign hdr_fifo_sink_ready=0;
        assign hdr_private_req_valid=0;assign hdr_private_req_op=0;assign hdr_private_req_camera=0;assign hdr_private_req_slot=0;
        assign hdr_private_req_generation=0;assign hdr_private_req_session=0;assign hdr_private_req_offset=0;assign hdr_private_req_length=0;
        assign hdr_private_req_lease=0;assign hdr_private_req_job_id=0;assign hdr_private_rsp_ready=0;assign raw_private_read_ready=1;
    end endgenerate
    generate if(PRIVATE_PROCESSING_ENABLE!=0) begin : g_private_processing
        wire cohort_pixel_reset_n,cohort_dfi_reset_n;
        wire cohort_async_reset_n=pixel_rst_n&&dfi_rst_n&&f21_core_async_reset_n;
        reset_release_sync u_cohort_pixel_reset(.i_clk(pixel_clk),
            .i_async_rst_n(cohort_async_reset_n),.o_rst_n(cohort_pixel_reset_n));
        reset_release_sync u_cohort_dfi_reset(.i_clk(dfi_clk),
            .i_async_rst_n(cohort_async_reset_n),.o_rst_n(cohort_dfi_reset_n));
        wire input_context_valid=shared_processing_selected ? hdr_pixel_context_valid : raw_replay_context_valid;
        wire [383:0] input_context_frame=shared_processing_selected ? hdr_pixel_context[383:0] : raw_replay_context_frame;
        wire [63:0] input_context_job=shared_processing_selected ? hdr_pixel_context[511:448] : raw_replay_context_job;
        wire [63:0] input_context_pair=shared_processing_selected ? processing_pair_id : raw_replay_context_pair;
        wire input_context_member=shared_processing_selected ? 1'b0 : raw_replay_context_member;
        wire input_context_private=shared_processing_selected ? 1'b1 : raw_replay_context_private;
        wire context_permitted=processing_context_available&&record_product_available&&!record_format_busy_pixel[1]&&
            !host_replay_context_valid&&!host_replay_context_owned&&!replay_active&&!f21_lut_update_busy&&
            (PHYSICAL_FRAME_FENCE_ENABLE==0||stereo_mode_pixel||camera_hdr_mode||physical_sdr_source_idle);
        wire input_context_ready=processing_context_ready&&context_permitted;
        wire context_fire=input_context_valid&&input_context_ready;
        assign private_context_fire=context_fire;
        reg [1:0] hdr_product_quiet_dfi;
        always @(posedge dfi_clk or negedge dfi_rst_n)begin
            if(!dfi_rst_n)hdr_product_quiet_dfi<=0;
            else hdr_product_quiet_dfi<={hdr_product_quiet_dfi[0],processing_pool_idle};
        end
        reg job_idle_meta,job_idle_sync;
        always @(posedge pixel_clk or negedge pixel_rst_n) begin
            if(!pixel_rst_n) begin job_idle_meta<=0;job_idle_sync<=0;end
            else begin job_idle_meta<=raw_processing_quiescent&&f21_pipeline_quiet;job_idle_sync<=job_idle_meta;end
        end
        assign raw_processing_idle_pixel=job_idle_sync;
        assign raw_replay_context_ready=!shared_processing_selected&&input_context_ready;
        assign hdr_pixel_context_ready=shared_processing_selected&&input_context_ready;
        raw_pair_processing_service #(.STEREO_ENABLE(DUAL_CAMERA_ENABLE),.PHYSICAL_MONO_CURRENT_ENABLE(0),.HDR_PROCESSING_ENABLE(HDR_PROCESSING_ENABLE),.WIDTH(FRAME_WIDTH),.HEIGHT(FRAME_HEIGHT)) u_processing(
            .i_stereo_mode(stereo_sdr_dfi&&!raw_mode_dfi),.i_stereo_job_valid(stereo_job_valid&&!raw_mode_dfi),.i_stereo_empty(stereo_empty),
            .i_stereo_job_frame(stereo_job_frame),.i_stereo_job_lease(stereo_job_lease),.i_stereo_job_id(stereo_job_id),
            .o_stereo_job_ready(stereo_jpeg_job_ready),.o_stereo_retire_valid(stereo_retire_valid),.o_stereo_retire_job_id(stereo_retire_id),
            .i_stereo_retire_ready(stereo_retire_ready),.i_stereo_retire_done(stereo_retire_done),.i_stereo_retire_error(stereo_retire_error),
            .i_pair_valid(pairbank_valid),.i_pair_bank(pairbank_bank),.i_pair_id(pairbank_id),.o_pair_ready(pairbank_ready),
            .i_pair_empty(raw_private_ownership_quiescent),.i_pair_fault(raw_reference_fault),
            .o_pair_config_valid(pairbank_cfg_valid),.i_pair_config_ready(pairbank_cfg_ready),.i_pair_config_error(pairbank_cfg_error),
            .o_pair_release_valid(pairbank_release_valid),.i_pair_release_ready(pairbank_release_ready),
            .o_pair_release_bank(pairbank_release_bank),.o_pair_release_id(pairbank_release_id),
            .o_pair_directory_valid(pairbank_directory_valid),.o_pair_directory_slot(pairbank_directory_slot),.i_pair_directory_ready(pairbank_directory_ready),
            .s_pair_directory_data(pairbank_directory_data),.s_pair_directory_word(pairbank_directory_word),
            .s_pair_directory_valid(pairbank_directory_output_valid),.s_pair_directory_last(pairbank_directory_last),.s_pair_directory_ready(pairbank_directory_output_ready),
            .i_identity_rst_n(hdr_identity_reset_n),
            .i_authority_empty(raw_private_ownership_quiescent&&hdr_owner_empty&&!hdr_scheduler_busy),
            .i_write_quiescent(hdr_writer_quiescent&&!ddr_start_valid&&!ddr_jpeg_valid&&!ddr_result_valid),
            .o_ticket_owner_hold(hdr_ticket_hold),.o_ticket_recovery_required(hdr_ticket_recovery),.o_ticket_exhausted(hdr_ticket_exhausted),
            .i_dfi_clk(dfi_clk),.i_dfi_rst_n(cohort_dfi_reset_n),.i_pixel_clk(pixel_clk),.i_pixel_rst_n(cohort_pixel_reset_n),
            .i_now(common_dfi_time_ns),
            .i_config_valid(raw_job_config_valid),.o_config_ready(raw_job_config_ready),
            .i_session(raw_job_config_session),.i_epoch(raw_job_config_epoch),.i_mode(raw_job_config_mode),
            .i_mono_enable(raw_job_config_mono),.i_max_delta(raw_job_config_max_delta),
            .i_max_wait(raw_job_config_max_wait),.i_max_age(raw_job_config_max_age),
            .o_config_done(raw_job_config_done),.o_config_error(raw_job_config_error),.o_config_busy(raw_job_config_busy),
            .i_commit_valid(raw_commit_valid),.o_commit_ready(raw_commit_ready),.i_descriptor(raw_commit_frame),.i_lease(raw_commit_lease),
            .o_commit_done(),.o_commit_error(),.o_commit_duplicate(),
            .o_ref_valid(raw_ref_valid),.i_ref_ready(raw_ref_ready),.o_ref_op(raw_ref_op),.o_ref_mask(raw_ref_mask),
            .o_ref_reason(),.o_ref_cancelled(),.o_ref_frame0(raw_ref_frame0),.o_ref_frame1(raw_ref_frame1),
            .o_ref_lease0(raw_ref_lease0),.o_ref_lease1(raw_ref_lease1),.o_ref_job_id(raw_ref_job_id),
            .m_member_valid(diag_member_valid),.m_member_ready(diag_member_ready),.m_member_frame(raw_member_frame),.m_member_lease(),.m_member_job_id(),
            .m_member_pair_id(raw_member_pair_id),.m_member_index(raw_member_index),
            .o_req_valid(normal_private_req_valid),.i_req_ready(normal_private_req_ready),.o_req_private(),.o_req_op(normal_private_req_op),
            .o_req_camera(normal_private_req_camera),.o_req_slot(normal_private_req_slot),
            .o_req_generation(normal_private_req_generation),.o_req_session(normal_private_req_session),.o_req_offset(),.o_req_length(),
            .o_req_lease(normal_private_req_lease),.o_req_job_id(normal_private_req_job_id),
            .i_rsp_valid(raw_private_rsp_valid&&!hdr_phase_owned),.o_rsp_ready(normal_private_rsp_ready),.i_rsp_code(raw_private_rsp_code),
            .i_rsp_camera(raw_private_rsp_camera),.i_rsp_slot(raw_private_rsp_slot),
            .i_rsp_generation(raw_private_rsp_generation),.i_rsp_session(raw_private_rsp_session),
            .i_rsp_sequence(raw_private_rsp_sequence),.i_rsp_epoch(raw_private_rsp_epoch),
            .i_native_done(raw_private_native_done),.i_native_error(raw_private_native_error),
            .i_native_job_id(raw_private_native_job),.i_native_member_index(raw_private_native_member),
            .i_cancel(1'b0),.i_read_quiescent(raw_read_quiescent),
            .o_processing_cancel_valid(),.o_processing_cancel_ready(),.o_processing_cancel_frame(),
            .o_processing_cancel_lease(),.o_processing_cancel_job_id(),.o_processing_cancel_pair_id(),.o_processing_cancel_member_index(),
            .o_job_valid(diag_job_valid),.o_job_ready(diag_job_ready),.o_job_kind(),.o_job_id(hdr_job_id),.o_pair_id(hdr_pair_id),.o_job_lease0(hdr_job_lease0),.o_job_lease1(hdr_job_lease1),
            .o_job_frame0(hdr_job_frame0),.o_job_frame1(hdr_job_frame1),.o_retire_valid(diag_retire_valid),.o_retire_ready(diag_retire_ready),.o_retire_session(),.o_retire_job_id(),
            .o_retire_cancelled(),.o_retire_read_quiescent(),.o_retire_done(diag_retire_done),.o_retire_error(),
            .o_owner_quiescent(hdr_owner_empty),.o_owner_fault(),.o_scheduler_busy(hdr_scheduler_busy),.o_scheduler_fault(),
            .o_diag_scheduler_state(diag_scheduler_state),.o_diag_ticket_state(diag_ticket_state),.o_diag_ticket_pixel(diag_ticket_pixel),
            .o_error_code(diag_scheduler_error),.o_stale_completion(),.o_busy(),.o_fault(raw_processing_fault),.o_quiescent(raw_processing_quiescent),
            .s_write_valid(private_writer_ack_valid),.s_write_ready(private_writer_ack_ready),.s_write_tag(writer_ack_tag),
            .s_write_sequence(writer_ack_sequence),.s_write_session(writer_ack_session),.s_write_epoch(writer_ack_epoch),
            .s_write_camera(writer_ack_camera),.s_write_ok(writer_ack_ok),.s_write_error(writer_ack_error),
            .o_processing_valid(stereo_processing_result_valid),.o_processing_job_id(stereo_processing_result_job),.o_processing_member_index(),.o_processing_error(stereo_processing_result_error),
            .o_dfi_reset_done(),.o_dfi_context_fault(),
            .i_pool_idle(processing_pool_idle),.i_admission_ready(replay_admission_ready&&
                record_product_available&&!record_format_busy_pixel[1]),
            .i_context_valid(input_context_valid&&context_permitted),.o_context_ready(processing_context_ready),
            .i_context_frame(input_context_frame),.i_context_job_id(input_context_job),.i_context_pair_id(input_context_pair),
            .i_context_member_index(input_context_member),.i_context_private(input_context_private),
            .i_processed_sof(processing_sof_fire),.i_writer_start_fire(processing_writer_start_fire),
            .i_pixel_cancel(1'b0),.i_pipeline_error(processing_context_owned&&(camera_error||processed_error||processing_event_fault)),
            .i_processed_source_valid(processing_source_valid),.i_processed_source_error(processing_source_error),
            .o_processed_source_ready(processing_source_ready),.i_processed_source_frame(processing_source_frame),
            .i_processed_source_lease(processing_source_lease),.i_processed_source_pair_id(processing_source_pair),
            .i_processed_source_write_tag(processing_source_tag),.i_processed_source_job_id(processing_source_job),
            .i_processed_source_member_index(processing_source_member),
            .o_frame(processing_frame),.o_lease(processing_lease),.o_pixel_job_id(processing_job_id),.o_pixel_pair_id(processing_pair_id),
            .o_member_index(processing_member),.o_write_tag(processing_write_tag),.o_pixel_busy(processing_pixel_busy),
            .o_context_owned(processing_context_owned),.o_pixel_reset_done(processing_pixel_reset_done),
            .o_pixel_fault(processing_pixel_fault),.o_first_fault_code(diag_ticket_error),.o_stale_write_count(),
            .o_completed_count(),.o_cancelled_count(),.o_stale_source_count(),
            .i_public_read_quiescent(raw_public_read_quiescent),.i_product_quiescent(hdr_product_quiet_dfi[1]),
            .i_hdr_reset_done(hdr_source_reset_done),.i_hard_fault(store_recovery),
            .i_hdr_fault(hdr_reader_fault||hdr_source_fault),.i_hdr_read_quiescent(hdr_reader_quiet),
            .o_hdr_phase_request(hdr_phase_request),.o_hdr_phase_owned(hdr_phase_owned),
            .o_hdr_context_valid(hdr_context_valid),.i_hdr_context_ready(hdr_context_ready),
            .o_hdr_start_valid(hdr_start_valid),.i_hdr_start_ready(hdr_start_ready),
            .o_hdr_cancel_valid(hdr_cancel_valid),.i_hdr_cancel_ready(hdr_cancel_ready),
            .o_hdr_result_transport_enable(hdr_transport_enable),.i_hdr_result_valid(hdr_result_valid),
            .i_hdr_result_ready(hdr_result_ready),.i_hdr_result_ok(hdr_result_ok),.i_hdr_result_error(hdr_result_error),
            .o_hdr_long_tag(hdr_long_tag),.o_hdr_short_tag(hdr_short_tag));
        reg [63:0] next_native_tag,native_tag;
        reg source_pending,source_ok,source_member,source_overlap_fault;
        reg [383:0] source_frame;
        reg [63:0] source_job,source_pair,source_lease,source_tag;
        reg read_quiet_meta,read_quiet_sync;
        reg pipeline_failed;
        wire source_ready;
        wire [575:0] processed_context;
        wire [575:0] source_notice_context;
        assign hdr_product_context=processed_context;assign hdr_notice_context=source_notice_context;
        wire processed_context_valid,private_dfi_fault;
        wire processed_context_ready;
        assign hdr_frame_begin=processed_context_valid&&processed_context_ready;
        wire pp_cleanup_pending,pp_cleanup_status,pp_cleanup_fault;
        reg pp_started;
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)pp_started<=0;
            else begin
                if(processed_context_valid&&processed_context_ready)pp_started<=0;
                if(private_rgb_valid&&private_rgb_ready&&private_rgb_sof)pp_started<=1;
            end
        end
        // An admitted advanced frame owns records until the real negative
        // computation terminal and JOIN tail have been consumed.
        if(S07_PROCESSING_ENABLE!=0)begin : g_advanced_cleanup
            localparam [2:0] CLEAN_IDLE=0,CLEAN_REQUEST=1,CLEAN_RECORDS=2,
                CLEAN_ARM=3,CLEAN_CLEAR=4;
            reg [2:0] cleanup_state;
            reg [1:0] clear_cycles;
            reg clear_active,cleanup_fault;
            reg pp_terminal_seen,pp_terminal_ok,original_source_seen,original_source_ok,jpeg_source_sent;
            reg jpeg_source_done,jpeg_source_error;
            wire terminal_fire=advanced_terminal_valid&&advanced_terminal_context==neutral_record_context;
            wire jpeg_source_safe=!private_rgb_valid&&!preprocess_presented&&!processed_valid&&
                !admission_rgb_buffered&&!jpeg_rgb_valid;
            wire cleanup_tail_quiet=preprocess_records_quiet && jpeg_idle &&
                !frame_active_pixel && !preprocess_presented && !processed_valid &&
                !private_rgb_valid && !admission_rgb_buffered && !jpeg_rgb_valid &&
                !start_valid && !status_valid && !jpeg_result_valid && !record_source_extension_valid;
            assign advanced_abort_request=cleanup_state==CLEAN_REQUEST&&!pp_terminal_seen&&!terminal_fire;
            assign private_jpeg_source_done=jpeg_source_done;
            assign private_jpeg_source_error=jpeg_source_error;
            // A genuine negative native FENCE may contain no output at all.
            // No PP config/SOF, JOIN or JPEG owner exists in this case; cancel
            // only pending START bookkeeping, then consume the original FENCE.
            assign private_no_work_complete=private_notice_valid&&!private_notice_ok&&!pp_started&&
                source_notice_context==processed_context&&preprocess_records_quiet&&jpeg_source_safe&&
                jpeg_idle&&!frame_active_pixel&&!start_valid&&!status_valid&&!jpeg_result_valid;
            assign private_pp_reset_n=pixel_rst_n && !clear_active;
            assign private_pp_data_rst_n=pixel_reset_local_n && !clear_active;
            assign pp_cleanup_pending=cleanup_state!=CLEAN_IDLE;
            assign pp_cleanup_status=1'b0;
            assign pp_cleanup_fault=cleanup_fault;
            // The opposite edge sees settled VALID outputs; reset may not
            // withdraw a newly presented pixel or a held record.
            always @(negedge pixel_clk or negedge pixel_posedge_reset_n)begin
                if(!pixel_posedge_reset_n)clear_active<=0;
                else if(cleanup_state==CLEAN_ARM && cleanup_tail_quiet)clear_active<=1;
                else if(cleanup_state==CLEAN_IDLE)clear_active<=0;
            end
            always @(posedge pixel_clk or negedge pixel_rst_n)begin
                if(!pixel_rst_n)begin
                    cleanup_state<=CLEAN_IDLE;clear_cycles<=0;cleanup_fault<=0;
                    pp_terminal_seen<=0;pp_terminal_ok<=0;original_source_seen<=0;original_source_ok<=0;
                end
                else begin
                    if(processed_context_valid&&processed_context_ready)begin
                        pp_terminal_seen<=0;pp_terminal_ok<=0;original_source_seen<=0;original_source_ok<=0;
                    end
                    if(terminal_fire)begin pp_terminal_seen<=1;pp_terminal_ok<=!advanced_terminal_error;end
                    if(private_notice_valid&&source_notice_context==processed_context)begin
                        original_source_seen<=1;original_source_ok<=private_notice_ok;
                    end
                    if(processed_context_valid&&processed_context_ready&&cleanup_state!=CLEAN_IDLE)
                        cleanup_fault<=1;
                    case(cleanup_state)
                        CLEAN_IDLE:if(private_notice_valid&&!private_notice_ok&&pp_started)begin
                            if(source_notice_context!=processed_context)cleanup_fault<=1;
                            else cleanup_state<=pp_terminal_seen||terminal_fire ? CLEAN_RECORDS : CLEAN_REQUEST;
                        end
                        CLEAN_REQUEST:if(advanced_abort_fire||pp_terminal_seen||terminal_fire)cleanup_state<=CLEAN_RECORDS;
                        CLEAN_RECORDS:if(cleanup_tail_quiet)cleanup_state<=CLEAN_ARM;
                        CLEAN_ARM:if(clear_active)begin cleanup_state<=CLEAN_CLEAR;clear_cycles<=2;end
                            else if(!cleanup_tail_quiet)cleanup_state<=CLEAN_RECORDS;
                        CLEAN_CLEAR:if(clear_cycles!=0)clear_cycles<=clear_cycles-1'b1;
                            else cleanup_state<=CLEAN_IDLE;
                        default:cleanup_fault<=1;
                    endcase
                end
            end
            // Numerical EOF alone cannot publish a positive JPEG END. Join it
            // with the actual same-frame original SOURCE; late failure closes
            // JPEG at a safe boundary without rewriting held PP records.
            always @(negedge pixel_clk or negedge pixel_posedge_reset_n)begin
                if(!pixel_posedge_reset_n)begin jpeg_source_sent<=0;jpeg_source_done<=0;jpeg_source_error<=0;end
                else begin
                    jpeg_source_done<=0;jpeg_source_error<=0;
                    if(!pp_started)jpeg_source_sent<=0;
                    else if(!jpeg_source_sent&&pp_started&&jpeg_source_safe&&
                        ((pp_terminal_seen&&!pp_terminal_ok)||(original_source_seen&&!original_source_ok)||
                         (pp_terminal_seen&&original_source_seen)))begin
                        jpeg_source_sent<=1;
                        jpeg_source_done<=pp_terminal_seen&&pp_terminal_ok&&original_source_seen&&original_source_ok;
                        jpeg_source_error<=!pp_terminal_ok||!original_source_ok;
                    end
                end
            end
        end else begin : g_regular_cleanup
        assign advanced_abort_request=1'b0;
        wire jpeg_source_data_quiet=!private_rgb_valid&&!preprocess_presented&&!processed_valid&&
            !admission_rgb_buffered&&!jpeg_rgb_valid;
        wire joined_terminal_busy,joined_terminal_fault;
        wire drain_terminal_fault;
        reg cleanup_notice_seen;
        wire cleanup_notice=private_notice_valid&&!cleanup_notice_seen;
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)cleanup_notice_seen<=0;
            else if(hdr_frame_begin)cleanup_notice_seen<=0;
            else if(cleanup_notice)cleanup_notice_seen<=1;
        end
        assign pp_cleanup_fault=drain_terminal_fault||joined_terminal_fault;
        hdr_product_terminal_join u_terminal_join(
            .clk(pixel_clk),.rst_n(pixel_rst_n),.begin_frame(hdr_frame_begin),
            .source_done(hdr_product_done),.source_failed(hdr_product_failed),
            .foreground_done(processed_done),.foreground_failed(processed_error),
            .data_quiet(jpeg_source_data_quiet),
            .error_drain_quiet(!pp_cleanup_pending&&jpeg_source_data_quiet),
            .done(private_jpeg_source_done),.failed(private_jpeg_source_error),
            .busy(joined_terminal_busy),.fault(joined_terminal_fault));
        assign private_no_work_complete=1'b0;
        // Default PP cleanup retains its qualified controlled-reset contract.
        // The retained native STATUS owner blocks a new private PP source
        // through this direct caller's ARM gap; clear commits on PIX posedge.
        hdr_pair_product_abort_drain4 #(.SYNC_CLEAR_ENABLE(1),.SEPARATE_DATA_RESET(1),.FALLING_INPUT_RESET(1)) u_pp_cleanup(
            .clk(pixel_clk),.rst_n(pixel_rst_n),
            .i_context_fire(processed_context_valid&&processed_context_ready),
            .i_context_tag(processed_context[447:384]),.i_source_fire(cleanup_notice),
            .i_source_tag(source_notice_context[447:384]),.i_source_ok(private_notice_ok),
            .i_source_read_quiescent(private_notice_valid),
            .i_native_job_start(private_rgb_valid&&private_rgb_ready&&private_rgb_sof),
            .i_native_valid(private_rgb_valid),.i_isp_valid(preprocess_presented),
            .i_preprocess_valid(processed_valid),.i_admission_valid(jpeg_rgb_valid),
            .o_local_rst_n(private_pp_reset_n),
            .i_data_reset_n(pixel_reset_local_n),.o_local_data_rst_n(private_pp_data_rst_n),
            .o_drain_pending(pp_cleanup_pending),
            .o_failed_status_valid(pp_cleanup_status),.i_failed_status_ready(1'b1),
            .o_protocol_fault(drain_terminal_fault),.o_stale_source_count(),.o_cleanup_pulse());
        end
        assign private_pp_error=pp_cleanup_status ||
            (private_notice_valid&&!private_notice_ok&&!pp_started);
        wire private_pipeline_quiet=preprocess_records_quiet && !job_pending && !preprocess_presented && !processed_valid &&
            jpeg_idle && !frame_active_pixel && !admission_rgb_buffered && !jpeg_rgb_valid &&
            !start_valid && !status_valid && !jpeg_result_valid && !record_source_extension_valid &&
            !pp_cleanup_pending;
        // A new context clears the old cancellation ledger. Publishing READY
        // directly from processed_valid closes a loop through frame_begin,
        // source_cancel and the pipeline's output-valid mask. Grant only a
        // previously observed empty boundary and consume it on the true take.
        frame_admission_qualification u_processed_context_credit(
            .i_clk(pixel_clk),.i_rst_n(pixel_rst_n),
            .i_available(preprocess_records_quiet && jpeg_idle && !frame_active_pixel && !preprocess_presented &&
                !processed_valid && !start_valid && !status_valid && !jpeg_result_valid),
            .i_take(hdr_frame_begin),.i_inhibit(1'b0),.o_available(processed_context_ready));
        assign processing_sof_fire=private_processing_selected&&processed_valid&&processed_ready&&processed_sof&&admission_take;
        assign processing_writer_start_fire=private_processing_selected&&start_valid&&start_ready;
        always @(posedge pixel_clk or negedge pixel_rst_n)begin
            if(!pixel_rst_n)begin
                next_native_tag<=1;native_tag<=0;source_pending<=0;source_ok<=0;source_member<=0;
                source_overlap_fault<=0;source_frame<=0;source_job<=0;source_pair<=0;
                source_lease<=0;source_tag<=0;read_quiet_meta<=0;read_quiet_sync<=0;pipeline_failed<=0;
            end else begin
                read_quiet_meta<=raw_read_quiescent&&(!hdr_phase_owned||hdr_reader_quiet);read_quiet_sync<=read_quiet_meta;
                if(context_fire)begin
                    native_tag<=shared_processing_selected ? hdr_pixel_context[447:384] : next_native_tag;
                    if(!shared_processing_selected)begin
                        if(next_native_tag==0)source_overlap_fault<=1;
                        else next_native_tag<=next_native_tag+1'b1;
                    end
                    pipeline_failed<=0;
                end
                if(processed_error || (jpeg_result_valid&&jpeg_result_ready&&!jpeg_result_ok))pipeline_failed<=1;
                if(source_pending&&source_ready&&read_quiet_sync)source_pending<=0;
                if(processing_context_owned && raw_replay_context_private && (raw_replay_native_done || raw_replay_native_error))begin
                    if(source_pending)source_overlap_fault<=1;
                    else begin
                        source_pending<=1;source_ok<=!raw_replay_native_error;
                        source_frame<=raw_replay_context_frame;source_job<=raw_replay_context_job;
                        source_pair<=raw_replay_context_pair;source_member<=raw_replay_context_member;
                        source_lease<=processing_lease;source_tag<=native_tag;
                    end
                end
            end
        end
        wire private_pixel_fault;
        assign processing_event_fault=private_pixel_fault||source_overlap_fault||pp_cleanup_fault||hdr_pixel_fault;
        reg nr_history_epoch_valid;
        reg [31:0] nr_history_epoch_seen,nr_history_session_seen;
        wire nr_history_reset=dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_NR_HISTORY_RESET] &&
            (!nr_history_epoch_valid || nr_history_epoch_seen!=dfi_active_config[159:128] ||
             nr_history_session_seen!=dfi_active_config[63:32]);
        always @(posedge dfi_clk or negedge dfi_rst_n)begin
            if(!dfi_rst_n)begin
                nr_history_epoch_valid<=0;nr_history_epoch_seen<=0;nr_history_session_seen<=0;
            end else if(nr_start_fire)begin
                nr_history_epoch_valid<=1;nr_history_epoch_seen<=dfi_active_config[159:128];
                nr_history_session_seen<=dfi_active_config[63:32];
            end
        end
        // One original ISP pass. The NR specialization owns real DDR history
        // and publication; applied DFI CFG freezes its policy on true START.
        wire nr_neutral_stats_valid;
        wire [159:0] nr_neutral_stats_context;
        wire [183:0] nr_neutral_statistics;
        if(NR_PROCESSING_ENABLE!=0)begin : g_original_stats
            assign neutral_stats_valid=private_processing_selected ? nr_neutral_stats_valid : live_neutral_stats_valid;
            assign neutral_stats_context=private_processing_selected ? nr_neutral_stats_context : live_neutral_stats_context;
            assign neutral_statistics=private_processing_selected ? nr_neutral_statistics : live_neutral_statistics;
        end
        wire private_original_cohort_reset_n=cohort_pixel_reset_n;
        wire [383:0] private_original_frame;
        wire [63:0] private_original_job,private_original_pair,private_original_lease,private_original_native_tag;
        wire [31:0] private_original_writer_tag;
        wire private_original_member,private_original_owner_run;
        wire [575:0] private_original_original_context,private_original_native_context;
        wire private_original_original_context_valid,private_original_adapter_source_ready;
        wire [95:0] private_original_original_rgb;
        wire [3:0] private_original_original_keep;
        wire private_original_original_sof,private_original_original_eol,private_original_original_last,private_original_original_valid,private_original_original_ready;
        wire [63:0] private_original_original_tag,private_original_original_status_tag;
        wire [31:0] private_original_original_index,private_original_original_status_groups;
        wire private_original_original_status_valid,private_original_original_status_ready,private_original_original_status_ok,private_original_original_quiet;
        wire [7:0] private_original_original_status_error;
        wire private_original_post_pool_idle,private_original_post_pixel_fault;
        assign hdr_raw_ready=shared_processing_selected&&private_replay_raw_ready;
        assign hdr_raw_source_ready=shared_processing_selected&&source_ready&&read_quiet_sync;
        wire [4*PRIVATE_RAW_SAMPLE_BITS-1:0] private_source_raw;
        if(HDR_PROCESSING_ENABLE!=0)begin: g_private_source_raw14
            assign private_source_raw=shared_processing_selected ? hdr_raw_capsule[55:0] : replay_raw14;
        end else begin: g_private_source_raw10
            assign private_source_raw=replay_raw_data;
        end
        private_raw_isp_borrow4 #(.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),
            .RAW_SAMPLE_BITS(PRIVATE_RAW_SAMPLE_BITS),.EXTERNAL_ISP_ENABLE(1),
            .ORIGINAL_SYNC_CLEAR_ENABLE(1)) u_original_source(
            .i_pixel_clk(pixel_clk),.i_pixel_rst_n(private_original_cohort_reset_n),
            .i_owner_published(processing_pixel_busy),
            .i_context_fire(context_fire),.i_context_private(input_context_private),.i_context_frame(input_context_frame),
            .i_context_job(input_context_job),.i_context_pair(input_context_pair),.i_context_key({input_context_frame[76:45],31'd0,input_context_frame[4]}),
            .i_context_aux(input_context_job),.i_context_member(input_context_member),
            .o_context_available(processing_context_available),.o_payload_enable(processing_replay_payload_enable),.o_pool_idle(processing_pool_idle),
            .i_owner_valid(processing_context_owned),.i_owner_frame(processing_frame),.i_owner_lease(processing_lease),
            .i_owner_job(processing_job_id),.i_owner_pair(processing_pair_id),.i_owner_native_tag(native_tag),
            .i_owner_writer_tag(processing_write_tag),.i_owner_member(processing_member),
            .i_bayer_phase(color_phase_pixel),.i_wb_gains(color_wb_pixel),.i_hdr_enable(hdr_processing_selected),.i_tone_shift(hdr_processing_selected ? 4'd4 : 4'd0),
            .o_isp_raw_data(private_isp_raw),.o_isp_raw_valid(private_isp_raw_valid),.o_isp_raw_sof(private_isp_raw_sof),.o_isp_raw_eol(private_isp_raw_eol),
            .i_isp_raw_ready(private_isp_raw_ready),.i_isp_rgb(camera_rgb),.i_isp_rgb_valid(camera_rgb_valid&&private_processing_selected),
            .i_isp_rgb_sof(camera_sof),.i_isp_rgb_eol(camera_eol),.i_isp_idle(native_job_idle),
            .o_isp_rgb_ready(private_isp_rgb_ready),.o_isp_reset_n(private_isp_reset_n),.o_isp_bayer_phase(),
            .o_isp_wb_gains(),.o_isp_hdr_enable(private_isp_hdr_enable),.o_isp_tone_shift(private_isp_tone_shift),
            .s_raw_data(private_source_raw),
            .s_raw_valid(shared_processing_selected ? hdr_raw_valid : replay_raw_valid),
            .s_raw_sof(shared_processing_selected ? hdr_raw_sof : replay_raw_sof),
            .s_raw_eol(shared_processing_selected ? hdr_raw_eol : replay_raw_eol),.s_raw_ready(private_replay_raw_ready),
            .s_raw_source_valid(shared_processing_selected ? hdr_raw_source_valid&&read_quiet_sync : source_pending&&read_quiet_sync),.s_raw_source_ready(source_ready),
             .s_raw_source_frame(shared_processing_selected ? hdr_pixel_context[383:0] : source_frame),
            .s_raw_source_lease(shared_processing_selected ? processing_lease : source_lease),
            .s_raw_source_job(shared_processing_selected ? processing_job_id : source_job),
             .s_raw_source_pair(shared_processing_selected ? processing_pair_id : source_pair),
            .s_raw_source_tag(shared_processing_selected ? hdr_raw_source_tag : source_tag),
            .s_raw_source_member(shared_processing_selected ? 1'b0 : source_member),
             .s_raw_source_ok(shared_processing_selected ? hdr_raw_source_ok : source_ok),
            .s_raw_source_error(shared_processing_selected ? hdr_raw_source_error : source_ok ? 8'd0 : 8'd2),
            .i_raw_source_read_quiescent(read_quiet_sync),.i_pixel_cancel(1'd0),
            .i_pipeline_quiescent(private_pipeline_quiet),.i_post_pool_idle(private_original_post_pool_idle),.i_post_pixel_fault(private_original_post_pixel_fault),
            .i_processed_source_fire(processing_source_valid&&processing_source_ready),
            .m_context(private_original_original_context),.m_context_valid(private_original_original_context_valid),.m_context_ready(private_original_adapter_source_ready),
            .m_rgb(private_original_original_rgb),.m_keep(private_original_original_keep),.m_sof(private_original_original_sof),.m_eol(private_original_original_eol),.m_last(private_original_original_last),
            .m_valid(private_original_original_valid),.m_ready(private_original_original_ready),.m_tag(private_original_original_tag),.m_index(private_original_original_index),
            .m_status_valid(private_original_original_status_valid),.m_status_ready(private_original_original_status_ready),.m_status_context(private_original_native_context),
            .m_status_tag(private_original_original_status_tag),.m_status_ok(private_original_original_status_ok),.m_status_error(private_original_original_status_error),
            .m_status_groups(private_original_original_status_groups),.o_original_read_quiescent(private_original_original_quiet),
            .o_locked_owner_valid(private_original_owner_run),.o_locked_frame(private_original_frame),.o_locked_lease(private_original_lease),.o_locked_job(private_original_job),
            .o_locked_pair(private_original_pair),.o_locked_native_tag(private_original_native_tag),.o_locked_writer_tag(private_original_writer_tag),.o_locked_member(private_original_member),
            .o_pixel_fault(private_pixel_fault),.o_isp_idle(),.o_isp_cleanup(private_isp_cleanup),
            .o_stale_raw_source_count());
        private_rgb_source_borrow4 #(.MAX_WIDTH(FRAME_WIDTH),.MAX_HEIGHT(FRAME_HEIGHT),.NR_ENABLE(0),.NEUTRAL_STATS_ENABLE(0),.DEHAZE_ENABLE(0)) u_source_events(
                .i_borrow_live(processing_pixel_busy),
                .i_f21_config(67'd0),
                .i_f21_required_lut_generation(32'd0),
                .f21_cfg_begin_valid(f21_cfg_begin_valid),
                .f21_cfg_begin_ready(),
                .f21_cfg_generation(f21_cfg_generation),
                .f21_cfg_valid(f21_cfg_valid),
                .f21_cfg_ready(),
                .f21_cfg_index(f21_cfg_index),
                .f21_cfg_value(f21_cfg_value),
                .f21_cfg_commit_valid(f21_cfg_commit_valid),
                .f21_cfg_commit_ready(),
                .f21_cfg_abort(f21_cfg_abort),
                .f21_cfg_status_valid(),
                .f21_cfg_status_ready(f21_cfg_status_ready),
                .f21_cfg_status_ok(),
                .f21_cfg_status_error(),
                .f21_cfg_status_generation(),
                .o_f21_lut_valid(),
                .o_f21_lut_generation(),
                .o_f21_start_eligible(f21_start_eligible),
                .o_f21_busy(f21_busy),
                .o_f21_read_quiescent(f21_read_quiescent),
                .o_f21_protocol_fault(f21_protocol_fault),
                .o_f21_fence_valid(f21_fence_valid),
                .o_f21_fence_identity(f21_fence_identity),
                .o_f21_fence_ok(f21_fence_ok),
                .o_f21_fence_error(f21_fence_error),
                .o_f21_fence_pixels(f21_fence_pixels),
                .o_f21_history_used(f21_history_used),
                .o_f21_metadata_bypass(f21_metadata_bypass),
                .o_f21_frame_lut_generation(f21_frame_lut_generation),
                .o_f21_map_commit(f21_map_commit),
                .o_f21_map_commit_frame(f21_map_commit_frame),
            .i_neutral_stats_request(NEUTRAL_STATS_ENABLE!=0),.i_neutral_record_begin(admission_take&&private_processing_selected),
            .i_neutral_record_context(neutral_record_context),.m_neutral_stats_valid(nr_neutral_stats_valid),
            .m_neutral_stats_ready(NR_PROCESSING_ENABLE ? private_processing_selected&&neutral_stats_ready : 1'b1),.m_neutral_stats_context(nr_neutral_stats_context),
            .m_neutral_statistics(nr_neutral_statistics),.o_neutral_stats_stale_count(),

            .i_pixel_clk(pixel_clk),.i_pixel_rst_n(private_original_cohort_reset_n),.i_dfi_clk(dfi_clk),.i_dfi_rst_n(cohort_dfi_reset_n),
            .s_context(private_original_original_context),.s_context_valid(private_original_original_context_valid),.s_context_ready(private_original_adapter_source_ready),
            .i_owner_valid(private_original_owner_run),.i_owner_frame(private_original_frame),.i_owner_lease(private_original_lease),.i_owner_job(private_original_job),.i_owner_pair(private_original_pair),
            .i_owner_native_tag(private_original_native_tag),.i_owner_writer_tag(private_original_writer_tag),.i_owner_member(private_original_member),
            .s_rgb(private_original_original_rgb),.s_keep(private_original_original_keep),.s_sof(private_original_original_sof),.s_eol(private_original_original_eol),.s_last(private_original_original_last),
            .s_valid(private_original_original_valid),.s_ready(private_original_original_ready),.s_tag(private_original_original_tag),.s_index(private_original_original_index),
            .s_status_valid(private_original_original_status_valid),.s_status_ready(private_original_original_status_ready),.s_status_context(private_original_native_context),
            .s_status_tag(private_original_original_status_tag),.s_status_ok(private_original_original_status_ok),.s_status_error(private_original_original_status_error),
            .s_status_groups(private_original_original_status_groups),.i_original_read_quiescent(private_original_original_quiet),
            .m_context(processed_context),.m_context_valid(processed_context_valid),.m_context_ready(processed_context_ready),.m_rgb(private_rgb),
            .m_keep(),.m_sof(private_rgb_sof),.m_eol(private_rgb_eol),.m_last(),
            .m_valid(private_rgb_valid),.m_ready(private_rgb_ready),.m_tag(),.m_index(),
            .m_source_notice_valid(private_notice_valid),.m_source_notice_ready(hdr_notice_ready),.m_source_notice_context(source_notice_context),.m_source_notice_ok(private_notice_ok),
            .m_source_notice_error(private_notice_error),.i_processed_sof_fire(processing_sof_fire),.i_writer_source_start_fire(processing_writer_start_fire),.i_pipeline_quiescent(private_pipeline_quiet),
            .i_pipeline_ok(!pipeline_failed&&!processed_error),.i_pipeline_error(pipeline_failed||processed_error ? 8'd3 : 8'd0),.m_processed_source_valid(processing_source_valid),.m_processed_source_ready(processing_source_ready),
            .m_processed_source_frame(processing_source_frame),.m_processed_source_lease(processing_source_lease),.m_processed_source_job(processing_source_job),.m_processed_source_pair(processing_source_pair),
            .m_processed_source_write_tag(processing_source_tag),.m_processed_source_member(processing_source_member),.m_processed_source_error(processing_source_error),.o_pixel_fault(private_original_post_pixel_fault),
            .o_dfi_fault(private_dfi_fault),.o_context_available(),.o_pool_idle(private_original_post_pool_idle),.o_stale_original_status_count(),
            .o_writer_start_permitted(nr_private_writer_start_permitted),.o_nr_start_fire(nr_start_fire),.i_writer_start_fire(ring_start_valid&&ring_start_ready&&!bridge_fault&&nr_writer_start_permitted),.s_write_valid(nr_writer_ack_valid),.s_write_ready(nr_writer_ack_ready),
            .s_write_tag(writer_ack_tag),.s_write_sequence(writer_ack_sequence),.s_write_session(writer_ack_session),.s_write_epoch(writer_ack_epoch),
            .s_write_camera(writer_ack_camera),.s_write_ok(writer_ack_ok),.s_write_error(writer_ack_error),.i_ddr_reset_done(ddr_app_ready),
            .i_matrix_fault(ddr_arbiter_fault),.i_matrix_hard_fault(store_recovery),.i_dfi_cancel(1'd0),.i_nr_enable(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_ENABLE+`PCIE_CFG_EXT_FEATURE_NR]),
            .i_history_reset(nr_history_reset),.i_motion_guard(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_NR_MOTION_GUARD+:8]),.i_static_threshold(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_NR_STATIC_THRESHOLD+:8]),.i_weak_threshold(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_NR_WEAK_THRESHOLD+:8]),
            .i_motion_threshold(dfi_algorithm_extension[`PCIE_CFG_EXT_OFFSET_NR_MOTION_THRESHOLD+:8]),.m_nr_result_valid(nr_result_valid),.m_nr_result_ready(1'b1),.m_nr_result_frame(nr_result_frame),
            .m_nr_result_tag(nr_result_tag),.m_nr_result_key(nr_result_key),.m_nr_result_aux(nr_result_aux),.m_nr_result_ok(nr_result_ok),
            .m_nr_result_current_ok(nr_result_current_ok),.m_nr_result_capture_ok(nr_result_capture_ok),.m_nr_result_history_commit(nr_result_history_commit),.m_nr_result_error(nr_result_error),
            .m_nr_result_input_pixels(nr_result_input_pixels),.m_nr_result_output_pixels(nr_result_output_pixels),.o_history_selected(nr_history_selected),.o_observation_ok(nr_observation_ok),
            .o_motion_qualified(nr_motion_qualified),.o_nr_history_valid(nr_history_valid),.o_dfi_read_quiescent(nr_read_quiescent),.rgb_axi_awid(nr_rgb_axi_awid),
            .rgb_axi_arid(nr_rgb_axi_arid),.rgb_axi_awaddr(nr_rgb_axi_awaddr),.rgb_axi_araddr(nr_rgb_axi_araddr),.rgb_axi_awlen(nr_rgb_axi_awlen),
            .rgb_axi_arlen(nr_rgb_axi_arlen),.rgb_axi_awsize(nr_rgb_axi_awsize),.rgb_axi_arsize(nr_rgb_axi_arsize),.rgb_axi_awburst(nr_rgb_axi_awburst),
            .rgb_axi_arburst(nr_rgb_axi_arburst),.rgb_axi_awvalid(nr_rgb_axi_awvalid),.rgb_axi_arvalid(nr_rgb_axi_arvalid),.rgb_axi_awready(nr_rgb_axi_awready),
            .rgb_axi_arready(nr_rgb_axi_arready),.rgb_axi_wdata(nr_rgb_axi_wdata),.rgb_axi_wstrb(nr_rgb_axi_wstrb),.rgb_axi_wlast(nr_rgb_axi_wlast),
            .rgb_axi_wvalid(nr_rgb_axi_wvalid),.rgb_axi_wready(nr_rgb_axi_wready),.rgb_axi_bid(nr_rgb_axi_bid),.rgb_axi_rid(nr_rgb_axi_rid),
            .rgb_axi_bresp(nr_rgb_axi_bresp),.rgb_axi_rresp(nr_rgb_axi_rresp),.rgb_axi_bvalid(nr_rgb_axi_bvalid),.rgb_axi_rlast(nr_rgb_axi_rlast),
            .rgb_axi_rvalid(nr_rgb_axi_rvalid),.rgb_axi_bready(nr_rgb_axi_bready),.rgb_axi_rready(nr_rgb_axi_rready),.rgb_axi_rdata(nr_rgb_axi_rdata),
            .map_axi_awid(nr_map_axi_awid),.map_axi_arid(nr_map_axi_arid),.map_axi_awaddr(nr_map_axi_awaddr),.map_axi_araddr(nr_map_axi_araddr),
            .map_axi_awlen(nr_map_axi_awlen),.map_axi_arlen(nr_map_axi_arlen),.map_axi_awsize(nr_map_axi_awsize),.map_axi_arsize(nr_map_axi_arsize),
            .map_axi_awburst(nr_map_axi_awburst),.map_axi_arburst(nr_map_axi_arburst),.map_axi_awvalid(nr_map_axi_awvalid),.map_axi_arvalid(nr_map_axi_arvalid),
            .map_axi_awready(nr_map_axi_awready),.map_axi_arready(nr_map_axi_arready),.map_axi_wdata(nr_map_axi_wdata),.map_axi_wstrb(nr_map_axi_wstrb),
            .map_axi_wlast(nr_map_axi_wlast),.map_axi_wvalid(nr_map_axi_wvalid),.map_axi_wready(nr_map_axi_wready),.map_axi_bid(nr_map_axi_bid),
            .map_axi_rid(nr_map_axi_rid),.map_axi_bresp(nr_map_axi_bresp),.map_axi_rresp(nr_map_axi_rresp),.map_axi_bvalid(nr_map_axi_bvalid),
            .map_axi_rlast(nr_map_axi_rlast),.map_axi_rvalid(nr_map_axi_rvalid),.map_axi_bready(nr_map_axi_bready),.map_axi_rready(nr_map_axi_rready),
            .map_axi_rdata(nr_map_axi_rdata));
    end else begin : g_no_private_processing
        assign diag_scheduler_state=0;assign diag_ticket_state=0;assign diag_scheduler_error=0;
        assign diag_ticket_error=0;assign diag_ticket_pixel=0;assign diag_member_valid=0;assign diag_member_ready=0;
        assign diag_job_valid=0;assign diag_job_ready=0;
        assign diag_retire_valid=0;assign diag_retire_ready=0;assign diag_retire_done=0;
        assign private_context_fire=0;
        assign processing_pixel_busy=1'b0;
        assign hdr_phase_request=0;assign hdr_phase_owned=0;
        assign hdr_job_frame0=0;assign hdr_job_frame1=0;assign hdr_job_id=0;assign hdr_pair_id=0;
        assign hdr_job_lease0=0;assign hdr_job_lease1=0;assign hdr_context_valid=0;assign hdr_start_valid=0;
        assign hdr_cancel_valid=0;assign hdr_transport_enable=0;assign hdr_long_tag=0;assign hdr_short_tag=0;
        assign hdr_pixel_context_ready=0;assign hdr_raw_ready=0;assign hdr_raw_source_ready=0;
        assign private_isp_hdr_enable=0;assign private_isp_tone_shift=0;
        assign advanced_abort_request=1'b0;
        assign private_jpeg_source_done=1'b0;assign private_jpeg_source_error=1'b0;
        assign private_no_work_complete=1'b0;
        if(!LIVE_F21_ENABLE)begin:g_no_live_f21_control
        assign f21_cfg_begin_ready=0;assign f21_cfg_ready=0;assign f21_cfg_commit_ready=0;
        assign f21_cfg_status_valid=0;assign f21_cfg_status_ok=0;
        assign f21_cfg_status_error=0;assign f21_cfg_status_generation=0;
        assign f21_lut_valid=0;assign f21_lut_generation=0;
        end
        assign f21_start_eligible=0;
        assign f21_busy=0;assign f21_read_quiescent=1;assign f21_protocol_fault=0;
        assign f21_fence_valid=0;assign f21_fence_identity=0;assign f21_fence_ok=0;
        assign f21_fence_error=0;assign f21_fence_pixels=0;
        assign f21_history_used=0;assign f21_metadata_bypass=0;assign f21_frame_lut_generation=0;
        assign f21_map_commit=0;assign f21_map_commit_frame=0;
        assign nr_private_writer_start_permitted=1;assign nr_start_fire=0;assign nr_writer_ack_ready=1;
        assign nr_result_valid=0;assign nr_result_ok=0;assign nr_result_current_ok=0;
        assign nr_result_capture_ok=0;assign nr_result_history_commit=0;
        assign nr_result_frame=0;assign nr_result_tag=0;assign nr_result_key=0;assign nr_result_aux=0;
        assign nr_result_error=0;assign nr_result_input_pixels=0;assign nr_result_output_pixels=0;
        assign nr_history_selected=0;assign nr_observation_ok=0;assign nr_motion_qualified=0;
        assign nr_history_valid=0;assign nr_read_quiescent=1;
        assign nr_rgb_axi_awid=0;
        assign nr_rgb_axi_arid=0;
        assign nr_rgb_axi_awaddr=0;
        assign nr_rgb_axi_araddr=0;
        assign nr_rgb_axi_awlen=0;
        assign nr_rgb_axi_arlen=0;
        assign nr_rgb_axi_awsize=0;
        assign nr_rgb_axi_arsize=0;
        assign nr_rgb_axi_awburst=0;
        assign nr_rgb_axi_arburst=0;
        assign nr_rgb_axi_awvalid=0;
        assign nr_rgb_axi_arvalid=0;
        assign nr_rgb_axi_wdata=0;
        assign nr_rgb_axi_wstrb=0;
        assign nr_rgb_axi_wlast=0;
        assign nr_rgb_axi_wvalid=0;
        assign nr_rgb_axi_bready=0;
        assign nr_rgb_axi_rready=0;
        assign nr_map_axi_awid=0;
        assign nr_map_axi_arid=0;
        assign nr_map_axi_awaddr=0;
        assign nr_map_axi_araddr=0;
        assign nr_map_axi_awlen=0;
        assign nr_map_axi_arlen=0;
        assign nr_map_axi_awsize=0;
        assign nr_map_axi_arsize=0;
        assign nr_map_axi_awburst=0;
        assign nr_map_axi_arburst=0;
        assign nr_map_axi_awvalid=0;
        assign nr_map_axi_arvalid=0;
        assign nr_map_axi_wdata=0;
        assign nr_map_axi_wstrb=0;
        assign nr_map_axi_wlast=0;
        assign nr_map_axi_wvalid=0;
        assign nr_map_axi_bready=0;
        assign nr_map_axi_rready=0;
        assign raw_commit_ready=1;assign raw_ref_valid=0;assign raw_ref_op=0;assign raw_ref_mask=0;
        assign raw_ref_frame0=0;assign raw_ref_frame1=0;assign raw_ref_lease0=0;assign raw_ref_lease1=0;assign raw_ref_job_id=0;
        assign normal_private_req_valid=0;assign normal_private_req_op=0;assign normal_private_req_camera=0;assign normal_private_req_slot=0;
        assign normal_private_req_generation=0;assign normal_private_req_session=0;assign normal_private_req_lease=0;assign normal_private_req_job_id=0;
        assign raw_member_frame=0;assign raw_member_pair_id=0;assign raw_member_index=0;assign normal_private_rsp_ready=1;
        assign raw_replay_context_ready=0;assign raw_processing_quiescent=1;assign raw_processing_fault=0;
        assign raw_processing_idle_pixel=1;
        if(RECORD_METADATA_ENABLE!=0) begin : g_capture_config_apply
            reg apply_done;
            // Capture has applied the whole PIX tuple already. DFI acknowledges
            // it only after actual old data owners are empty, without waiting
            // for the unused pre-granted JPEG credit or for its own CONFIG.
            assign raw_job_config_ready=record_dfi_data_quiescent&&!apply_done;
            assign raw_job_config_done=apply_done;
            assign raw_job_config_error=0;assign raw_job_config_busy=0;
            always @(posedge dfi_clk or negedge dfi_rst_n) begin
                if(!dfi_rst_n)apply_done<=0;
                else apply_done<=raw_job_config_valid&&raw_job_config_ready;
            end
        end else begin : g_no_capture_config_apply
            assign raw_job_config_ready=0;assign raw_job_config_done=0;
            assign raw_job_config_error=0;assign raw_job_config_busy=0;
        end
        assign processing_context_ready=0;assign processing_context_owned=0;assign processing_pixel_reset_done=0;assign processing_pixel_fault=0;
        assign processing_pool_idle=0;assign processing_replay_payload_enable=0;assign processing_context_available=0;
        assign processing_sof_fire=0;assign processing_writer_start_fire=0;assign processing_event_fault=0;
        assign processing_source_valid=0;assign processing_source_ready=0;assign processing_source_error=0;
        assign processing_frame=0;assign processing_lease=0;assign processing_job_id=0;assign processing_pair_id=0;
        assign processing_source_frame=0;assign processing_source_lease=0;assign processing_source_job=0;
        assign processing_source_pair=0;assign processing_source_tag=0;assign processing_member=0;assign processing_source_member=0;
        assign processing_write_tag=0;assign private_writer_ack_ready=1;
    end endgenerate
    wire store_ready_valid, store_ready_claim;
    wire [31:0] store_id;
    wire [24:0] store_length;
    wire [15:0] store_width, store_height, store_payload_keep;
    wire [63:0] store_time;
    wire [127:0] store_payload_data;
    wire store_payload_valid, store_payload_ready, store_payload_last;
    wire [127:0] record_header_stream_data;
    wire record_header_stream_valid,record_header_stream_last,record_header_stream_ready;
    wire store_drop, store_read_done;
    wire [7:0] store_error;
    wire [15:0] store_slot;
    wire [31:0] store_session,store_generation,store_epoch;
    wire [7:0] store_quality;
    wire store_camera;
    wire retire_valid,retire_ready,retire_error,retire_meta_ready,retire_user_armed;
    wire jpeg_source_record_ready,jpeg_source_cancel,jpeg_source_retire_valid;
    wire [127:0] jpeg_source_retire_identity;
    wire [31:0] jpeg_source_retire_status;
    wire store_reader_complete,store_reader_error,record_formatter_done;
    reg jpeg_record_owned,jpeg_record_done,jpeg_record_ok,jpeg_cancel_seen;
    wire [127:0] jpeg_record_identity={16'h4a50,store_session,store_generation,store_slot,store_id};
    wire [31:0] jpeg_record_length={7'd0,store_length}+
        (record_selected_version_dfi==4?32'd2112:record_selected_version_dfi==2?32'd192:32'd64);
    wire [31:0] retire_session,retire_generation;
    wire [15:0] retire_slot;
    reg local_retire_pending;
    reg [31:0] local_read_session,local_read_generation;
    reg [15:0] local_read_slot;
    wire ring_retire_ready;
    wire jpeg_bar_write_valid,jpeg_bar_read_valid,jpeg_bar_read_response_valid;
    wire [11:0] jpeg_bar_write_offset,jpeg_bar_read_offset;
    wire [31:0] jpeg_bar_write_data,jpeg_bar_read_data;
    wire [3:0] jpeg_bar_write_strobes;
    wire [1:0] jpeg_bar_write_response,jpeg_bar_read_response;
    wire ring_req_valid,ring_req_ready,ring_req_camera,ring_rsp_valid,ring_rsp_ready,ring_rsp_camera,ring_rsp_pinned;
    wire [1:0] ring_req_op;
    wire [15:0] ring_req_slot,ring_rsp_slot,ring_rsp_width,ring_rsp_height;
    wire [31:0] ring_req_generation,ring_req_session,ring_rsp_generation,ring_rsp_session,ring_rsp_epoch,ring_rsp_id;
    wire [3:0] ring_rsp_code;
    wire [2:0] ring_rsp_state;
    wire [7:0] ring_rsp_quality;
    wire [24:0] ring_rsp_length;
    wire actual_c2h_valid,actual_c2h_ready,actual_c2h_last;
    generate if(VIDEO_SERVICE_ENABLE!=0) begin : g_jpeg_control
        jpeg_frame_service u_service (
            .i_user_clk(user_clk),.i_user_rst_n(user_rst_n),.i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n),
            .i_user_session_id(cfg_user_session),.i_user_initialized(cfg_user_initialized),.i_ddr_ready(ddr_app_ready),
            .i_bar_write_valid(jpeg_bar_write_valid),.i_bar_write_offset(jpeg_bar_write_offset),
            .i_bar_write_data(jpeg_bar_write_data),.i_bar_write_strobes(jpeg_bar_write_strobes),.o_bar_write_response(jpeg_bar_write_response),
            .i_bar_read_valid(jpeg_bar_read_valid),.i_bar_read_offset(jpeg_bar_read_offset),
            .o_bar_read_response_valid(jpeg_bar_read_response_valid),.o_bar_read_data(jpeg_bar_read_data),.o_bar_read_response(jpeg_bar_read_response),
            .o_req_valid(ring_req_valid),.i_req_ready(ring_req_ready),.o_req_op(ring_req_op),.o_req_camera(ring_req_camera),
            .o_req_slot(ring_req_slot),.o_req_generation(ring_req_generation),.o_req_session(ring_req_session),
            .i_rsp_valid(ring_rsp_valid),.o_rsp_ready(ring_rsp_ready),.i_rsp_code(ring_rsp_code),
            .i_rsp_slot(ring_rsp_slot),.i_rsp_generation(ring_rsp_generation),.i_rsp_session(ring_rsp_session),
            .i_rsp_epoch(ring_rsp_epoch),.i_rsp_capture_id(ring_rsp_id),.i_rsp_camera(ring_rsp_camera),.i_rsp_quality(ring_rsp_quality),
            .i_rsp_width(ring_rsp_width),.i_rsp_height(ring_rsp_height),.i_rsp_payload_length(ring_rsp_length),
            .i_rsp_pinned(ring_rsp_pinned),.i_rsp_state(ring_rsp_state),.o_user_ready(),.o_dfi_ready());
    end else begin : g_legacy_jpeg_control
        assign ring_req_valid=0;assign ring_req_op=0;assign ring_req_camera=0;assign ring_req_slot=0;
        assign ring_req_generation=0;assign ring_req_session=0;assign ring_rsp_ready=1;
        assign jpeg_bar_write_response=2'b10;assign jpeg_bar_read_response=2'b10;
        assign jpeg_bar_read_response_valid=0;assign jpeg_bar_read_data=0;
    end endgenerate
    assign retire_ready=ring_retire_ready && !local_dfi[1];
    assign retire_meta_ready=jpeg_source_record_ready;
    assign retire_user_armed=c2h_running;
    assign retire_valid=jpeg_source_retire_valid;
    assign retire_session=jpeg_source_retire_identity[111:80];
    assign retire_generation=jpeg_source_retire_identity[79:48];
    assign retire_slot=jpeg_source_retire_identity[47:32];
    assign retire_error=jpeg_source_retire_status!=0;
    always @(posedge dfi_clk or negedge dfi_rst_n) begin
        if(!dfi_rst_n) begin
            local_retire_pending<=0;local_read_session<=0;local_read_slot<=0;local_read_generation<=0;
        end else begin
            if(store_ready_claim && local_dfi[1]) begin
                local_read_session<=store_session;local_read_slot<=store_slot;local_read_generation<=store_generation;
            end
            if(local_dfi[1] && record_valid && record_ready && record_last) local_retire_pending<=1;
            if(local_retire_pending && ring_retire_ready) local_retire_pending<=0;
        end
    end
    assign ring_req_ready=ring_request_ready&&!record_start_reserved;
    assign store_start_ready=ring_start_ready;
    generate if(RECORD_METADATA_ENABLE!=0) begin : g_record_metadata
        reg private_ack_seen,metadata_ack_seen,nr_ack_seen;
        assign private_writer_ack_valid=private_writer_required&&writer_ack_valid&&!private_ack_seen;
        assign record_writer_ack_valid=writer_ack_valid&&!metadata_ack_seen;
        assign nr_writer_ack_valid=nr_writer_required&&writer_ack_valid&&!nr_ack_seen;
        assign writer_ack_ready=(!private_writer_required || private_ack_seen || private_writer_ack_ready)&&
            (metadata_ack_seen || record_writer_ack_ready)&&
            (!nr_writer_required || nr_ack_seen || nr_writer_ack_ready);
        always @(posedge dfi_clk or negedge dfi_rst_n) begin
            if(!dfi_rst_n)begin private_ack_seen<=0;metadata_ack_seen<=0;nr_ack_seen<=0;end
            else begin
                if(private_writer_ack_valid&&private_writer_ack_ready)private_ack_seen<=1;
                if(record_writer_ack_valid&&record_writer_ack_ready)metadata_ack_seen<=1;
                if(nr_writer_ack_valid&&nr_writer_ack_ready)nr_ack_seen<=1;
                // A true source result retirement starts the next fanout owner.
                if(writer_ack_valid&&writer_ack_ready)begin private_ack_seen<=0;metadata_ack_seen<=0;nr_ack_seen<=0;end
            end
        end
        // The gate, store and their RAM controls sample reset on rising DFI.
        jpeg_record_metadata_gate #(.BORROW_PENDING_EXTENSION(1),.STAGING_EXTENSION_ENABLE(1),.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),.BORROW_HEADER(1),.STREAM_READ(1)) u_gate(
            .i_clk(dfi_clk),.i_rst_n(product_dfi_data_reset_n),
            .s_start_valid(ddr_start_valid&&!bridge_fault),.o_start_ready(ddr_start_ready),
            .s_start_writer_tag(ddr_write_tag),.s_start_sequence(ddr_capture_id),
            .s_start_session(ddr_session),.s_start_epoch(ddr_epoch),.s_start_camera(ddr_camera),
            .i_ring_start_ready(ring_start_ready&&!bridge_fault&&nr_writer_start_permitted),.o_ring_start_valid(ring_start_valid),
            .o_start_reserved(record_start_reserved),
            .s_extension(record_dfi_extension),.s_extension_valid(record_dfi_extension_valid),
            .o_extension_ready(record_dfi_extension_ready),
            .s_extension_shape_valid(record_extension_shape_valid),
            .o_extension_read_enable(record_extension_read_enable),.o_extension_read_index(record_extension_read_index),
            .i_extension_read_data(record_extension_read_data),
            .s_write_result_valid(record_writer_ack_valid),.o_write_result_ready(record_writer_ack_ready),
            .s_write_result_tag(writer_ack_tag),.s_write_result_sequence(writer_ack_sequence),
            .s_write_result_session(writer_ack_session),.s_write_result_epoch(writer_ack_epoch),
            .s_write_result_camera(writer_ack_camera),.s_write_result_slot(writer_ack_slot),
            .s_write_result_generation(writer_ack_generation),.s_write_result_ok(writer_ack_ok),
            .s_write_result_error(writer_ack_error),
            .i_ready_valid(store_ready_valid),.i_ready_slot(store_slot),.i_ready_generation(store_generation),
            .i_ready_session(store_session),.i_ready_sequence(store_id),.i_ready_epoch(store_epoch),
            .i_ready_camera(store_camera),.i_selected_version(record_selected_version_dfi),
            .o_header_ready(record_header_ready),.o_header_extension(record_header_extension),
            .i_header_fire(store_ready_claim),
            .i_header_release(store_payload_ready || record_formatter_abort),
            .o_header_stream_data(record_header_stream_data),.o_header_stream_valid(record_header_stream_valid),
            .o_header_stream_last(record_header_stream_last),.i_header_stream_ready(record_header_stream_ready),
            .s_mask_req_valid(1'b0),.o_mask_req_ready(),.s_mask_req_slot(16'd0),
            .s_mask_req_generation(32'd0),.s_mask_req_session(32'd0),.s_mask_req_sequence(32'd0),
            .s_mask_req_epoch(32'd0),.s_mask_req_camera(1'b0),.o_mask_rsp_valid(),.o_mask_rsp_ok(),
            .i_mask_rsp_ready(1'b0),.o_mask_rsp_error(),.o_mask_rsp_slot(),.o_mask_rsp_generation(),
            .o_mask_rsp_session(),.o_mask_rsp_sequence(),.o_mask_rsp_epoch(),.o_mask_rsp_camera(),
            .o_mask_rsp_qualified(),.o_mask_rsp_pixels(),.o_mask_rsp_source_type(),
            .o_quiescent(record_metadata_quiescent),
            .o_fault(record_metadata_fault),.o_stale_write_count(),.o_bad_extension_count());
    end else begin : g_legacy_record_metadata
        assign private_writer_ack_valid=writer_ack_valid;assign writer_ack_ready=private_writer_ack_ready;
        assign nr_writer_ack_valid=0;
        assign record_writer_ack_valid=0;assign record_writer_ack_ready=1;
        assign ring_start_valid=ddr_start_valid;assign ddr_start_ready=ring_start_ready;
        assign record_start_reserved=0;assign record_dfi_extension_ready=1;
        assign record_extension_read_enable=0;assign record_extension_read_index=0;
        assign record_header_ready=1;assign record_header_extension=0;
        assign record_header_stream_data=0;assign record_header_stream_valid=0;assign record_header_stream_last=0;
        assign record_metadata_quiescent=1;assign record_metadata_fault=0;
    end endgenerate
    // 四相信用握手保证同一 DDR 槽位不会被重复准入
    single_slot_credit_cdc #(.MULTI_SLOT_ENABLE(VIDEO_SERVICE_ENABLE)) u_slot_credit (
        .i_source_clk(pixel_clk), .i_source_rst_n(pixel_rst_n),
        .i_source_request(credit_request_pixel), .o_source_grant(credit_grant_pixel),
        .o_source_ack(credit_ack_pixel),
        .i_sink_clk(dfi_clk), .i_sink_rst_n(dfi_rst_n),
        .i_sink_slot_available(store_start_ready),
        .i_sink_claim(ring_start_valid && !bridge_fault && nr_writer_start_permitted && ring_start_ready),
        .o_sink_reserved(credit_reserved_dfi), .o_protocol_fault(credit_fault)
    );
    // 完整且无错误的数据写入后发布 READY，读出末拍握手前保持槽位占用
    ddr3_jpeg_store #(.HDR_PORT_ENABLE(S04_ENABLE),.JPEG_RING_ENABLE(VIDEO_SERVICE_ENABLE),
        .JPEG_CAMERA_COUNT(JPEG_CAMERA_COUNT),
        .FOUR_CLIENT_ENABLE(NR_PROCESSING_ENABLE),
        .WRITE_RESULT_ENABLE(PRIVATE_PROCESSING_ENABLE || RECORD_METADATA_ENABLE),
        .WRITE_TAG_ENABLE(PRIVATE_PROCESSING_ENABLE || RECORD_METADATA_ENABLE)) u_ddr_store (
        .i_sys_clk_100m(board_ref_clk_100m_gclk),
        .i_sys_rst_n(product_cold_reset_n),
        .i_session_rst_n(product_cold_reset_n),
        .i_record_ownership_rst_n(product_cold_reset_n),.i_memory_fault(memory_fault_dfi_active),
        .o_ddr_ck_p(ddr_ck_p), .o_ddr_ck_n(ddr_ck_n),
        .o_ddr_reset_n(ddr_reset_n), .o_ddr_cke(ddr_cke),
        .o_ddr_odt(ddr_odt), .o_ddr_cs_n(ddr_cs_n),
        .o_ddr_ras_n(ddr_ras_n), .o_ddr_cas_n(ddr_cas_n),
        .o_ddr_we_n(ddr_we_n), .o_ddr_ba(ddr_ba), .o_ddr_addr(ddr_addr),
        .io_ddr_dqs_p(ddr_dqs_p), .io_ddr_dqs_n(ddr_dqs_n),
        .io_ddr_dq(ddr_dq), .io_ddr_dm(ddr_dm),
        .o_dfi_clk(dfi_clk), .o_ddrphy_rst_n(ddr_phy_rst_n),
        .o_ddr_init_cal_done(ddr_cal_done), .o_app_ready(ddr_app_ready),
        .o_pll_locked(),.o_ddr_init_cal_err(),.o_ddr_init_cal_step(),.o_store_state(),
        .o_wr_burst_count(),.o_rd_burst_count(),.o_berr_count(),.o_rerr_count(),
        .o_drop_count(),.o_last_error_addr(),.o_hdr_arbiter_fault(ddr_arbiter_fault),
        .i_start_valid(ring_start_valid && !bridge_fault && nr_writer_start_permitted),
        .o_start_ready(ring_start_ready),
        .i_capture_id(ddr_capture_id), .i_width(ddr_width),
        .i_height(ddr_height), .i_timestamp_ns(ddr_timestamp),.i_write_tag(ddr_write_tag),
        .i_session_id(ddr_session),.i_mode_epoch(ddr_epoch),.i_camera_id(ddr_camera),.i_quality(ddr_quality),
        .i_result_quality(ddr_actual_quality),.i_result_epoch(ddr_actual_epoch),
        .o_slot_id(store_slot),.o_generation(store_generation),.o_session_id(store_session),.o_mode_epoch(store_epoch),
        .o_camera_id(store_camera),.o_quality(store_quality),
        .i_retire_valid(local_dfi[1] ? local_retire_pending : retire_valid),.o_retire_ready(ring_retire_ready),
        .i_retire_session(local_dfi[1] ? local_read_session : retire_session),
        .i_retire_slot(local_dfi[1] ? local_read_slot : retire_slot),
        .i_retire_generation(local_dfi[1] ? local_read_generation : retire_generation),.i_retire_error(!local_dfi[1] && retire_error),
        .o_retire_rsp_valid(),.i_retire_rsp_ready(1'b1),.o_retire_rsp_code(),.o_read_complete(store_reader_complete),.o_read_error(store_reader_error),
        .i_req_valid(ring_req_valid&&!record_start_reserved),.o_req_ready(ring_request_ready),
        .i_req_op(ring_req_op),.i_req_camera(ring_req_camera),
        .i_req_slot(ring_req_slot),.i_req_generation(ring_req_generation),.i_req_session(ring_req_session),
        .o_rsp_valid(ring_rsp_valid),.i_rsp_ready(ring_rsp_ready),.o_rsp_code(ring_rsp_code),.o_rsp_slot(ring_rsp_slot),
        .o_rsp_generation(ring_rsp_generation),.o_rsp_session(ring_rsp_session),.o_rsp_epoch(ring_rsp_epoch),.o_rsp_capture_id(ring_rsp_id),
        .o_rsp_camera(ring_rsp_camera),.o_rsp_quality(ring_rsp_quality),.o_rsp_width(ring_rsp_width),.o_rsp_height(ring_rsp_height),
        .o_rsp_payload_length(ring_rsp_length),.o_rsp_pinned(ring_rsp_pinned),.o_rsp_state(ring_rsp_state),
        .i_start_mask(1'b0),.i_mask_allocation_ready(1'b0),
        .i_start_source_type(3'd0),
        .o_mask_allocation_valid(),.o_mask_allocation_slot(debug_writer_allocation_slot),
        .o_mask_allocation_generation(debug_writer_allocation_generation),
        .o_mask_allocation_base(),.o_mask_allocation_bytes(),
        .i_mask_result_valid(1'b0),.o_mask_result_ready(),.i_mask_result_context(160'd0),
        .i_mask_result_tag(32'd0),.i_mask_result_generation(32'd0),.i_mask_result_slot(16'd0),
        .i_mask_result_ok(1'b0),.i_mask_result_error(8'd0),
        .i_mask_result_width(13'd0),.i_mask_result_height(13'd0),
        .i_mask_result_written_bytes(17'd0),.i_mask_result_terminal_body(48'd0),
        .i_req_mask(1'b0),.i_req_read_lock(1'b0),.i_mask_read_lease_release(1'b0),
        .o_mask_read_lease_active(),.o_rsp_read_authorized(),
        .o_rsp_mask_present(),.o_rsp_mask_pinned(),.o_rsp_mask_tail_base(),
        .i_mask_axi_awid(4'd0),.i_mask_axi_awaddr(28'd0),.i_mask_axi_awlen(8'd0),
        .i_mask_axi_awsize(3'd0),.i_mask_axi_awburst(2'd0),.i_mask_axi_awvalid(1'b0),.o_mask_axi_awready(),
        .i_mask_axi_wdata(128'd0),.i_mask_axi_wstrb(16'd0),.i_mask_axi_wlast(1'b0),
        .i_mask_axi_wvalid(1'b0),.o_mask_axi_wready(),.o_mask_axi_bid(),.o_mask_axi_bresp(),
        .o_mask_axi_bvalid(),.i_mask_axi_bready(1'b0),
        .i_mask_axi_arid(4'd0),.i_mask_axi_araddr(28'd0),.i_mask_axi_arlen(8'd0),
        .i_mask_axi_arsize(3'd0),.i_mask_axi_arburst(2'd0),.i_mask_axi_arvalid(1'b0),.o_mask_axi_arready(),
        .o_mask_axi_rid(),.o_mask_axi_rdata(),.o_mask_axi_rresp(),.o_mask_axi_rlast(),
        .o_mask_axi_rvalid(),.i_mask_axi_rready(1'b0),.o_mask_axi_quiescent(),.o_mask_axi_fault(),
        .i_jpeg_tdata(ddr_jpeg_data), .i_jpeg_tkeep(ddr_jpeg_keep),
        .i_jpeg_tvalid(ddr_jpeg_valid), .o_jpeg_tready(ddr_jpeg_ready),
        .i_jpeg_tlast(ddr_jpeg_last), .i_result_valid(ddr_result_valid),
        .o_result_ready(ddr_result_ready), .i_result_id(ddr_result_id),
        .i_result_ok(ddr_result_ok), .i_result_length(ddr_result_length),
        .i_write_result_ready(writer_ack_ready),
        .o_write_result_valid(writer_ack_valid),.o_write_result_ok(writer_ack_ok),.o_write_result_error(writer_ack_error),
        .o_write_result_capture_id(writer_ack_sequence),.o_write_result_session(writer_ack_session),.o_write_result_epoch(writer_ack_epoch),
        .o_write_result_camera(writer_ack_camera),.o_write_result_slot(writer_ack_slot),
        .o_write_result_generation(writer_ack_generation),
        .o_write_result_payload_length(debug_writer_ack_length),.o_write_result_tag(writer_ack_tag),
        .o_ready_valid(store_ready_valid), .i_ready_claim(store_ready_claim),
        .o_capture_id(store_id), .o_payload_length(store_length),
        .o_width(store_width), .o_height(store_height),
        .o_timestamp_ns(store_time), .o_payload_tdata(store_payload_data),
        .o_payload_tkeep(store_payload_keep),
        .o_payload_tvalid(store_payload_valid),
        .i_payload_tready(store_payload_ready),
        .o_payload_tlast(store_payload_last), .o_drop_pulse(store_drop),
        .o_read_done_pulse(store_read_done), .o_error_code(store_error),
        .o_stream_recovery_required(store_recovery),
        .i_hdr_axi_awid(raw_axi_awid),
        .i_hdr_axi_awaddr(raw_axi_awaddr),
        .i_hdr_axi_awlen(raw_axi_awlen),
        .i_hdr_axi_awsize(raw_axi_awsize),
        .i_hdr_axi_awburst(raw_axi_awburst),
        .i_hdr_axi_awvalid(raw_axi_awvalid),
        .o_hdr_axi_awready(raw_axi_awready),
        .i_hdr_axi_wdata(raw_axi_wdata),
        .i_hdr_axi_wstrb(raw_axi_wstrb),
        .i_hdr_axi_wlast(raw_axi_wlast),
        .i_hdr_axi_wvalid(raw_axi_wvalid),
        .o_hdr_axi_wready(raw_axi_wready),
        .o_hdr_axi_bid(raw_axi_bid),
        .o_hdr_axi_bresp(raw_axi_bresp),
        .o_hdr_axi_bvalid(raw_axi_bvalid),
        .i_hdr_axi_bready(raw_axi_bready),
        .i_hdr_axi_arid(raw_axi_arid),
        .i_hdr_axi_araddr(raw_axi_araddr),
        .i_hdr_axi_arlen(raw_axi_arlen),
        .i_hdr_axi_arsize(raw_axi_arsize),
        .i_hdr_axi_arburst(raw_axi_arburst),
        .i_hdr_axi_arvalid(raw_axi_arvalid),
        .o_hdr_axi_arready(raw_axi_arready),
        .o_hdr_axi_rid(raw_axi_rid),
        .o_hdr_axi_rdata(raw_axi_rdata),
        .o_hdr_axi_rresp(raw_axi_rresp),
        .o_hdr_axi_rlast(raw_axi_rlast),
        .o_hdr_axi_rvalid(raw_axi_rvalid),
        .i_hdr_axi_rready(raw_axi_rready),
        // Real RGB staging and Y/map clients share the authentic Matrix4.
        .i_rgb_axi_awid(nr_rgb_axi_awid),
        .i_rgb_axi_arid(nr_rgb_axi_arid),
        .i_rgb_axi_awaddr(nr_rgb_axi_awaddr),
        .i_rgb_axi_araddr(nr_rgb_axi_araddr),
        .i_rgb_axi_awlen(nr_rgb_axi_awlen),
        .i_rgb_axi_arlen(nr_rgb_axi_arlen),
        .i_rgb_axi_awsize(nr_rgb_axi_awsize),
        .i_rgb_axi_arsize(nr_rgb_axi_arsize),
        .i_rgb_axi_awburst(nr_rgb_axi_awburst),
        .i_rgb_axi_arburst(nr_rgb_axi_arburst),
        .i_rgb_axi_awvalid(nr_rgb_axi_awvalid),
        .i_rgb_axi_arvalid(nr_rgb_axi_arvalid),
        .o_rgb_axi_awready(nr_rgb_axi_awready),
        .o_rgb_axi_arready(nr_rgb_axi_arready),
        .i_rgb_axi_wdata(nr_rgb_axi_wdata),
        .i_rgb_axi_wstrb(nr_rgb_axi_wstrb),
        .i_rgb_axi_wlast(nr_rgb_axi_wlast),
        .i_rgb_axi_wvalid(nr_rgb_axi_wvalid),
        .o_rgb_axi_wready(nr_rgb_axi_wready),
        .o_rgb_axi_bid(nr_rgb_axi_bid),
        .o_rgb_axi_rid(nr_rgb_axi_rid),
        .o_rgb_axi_bresp(nr_rgb_axi_bresp),
        .o_rgb_axi_rresp(nr_rgb_axi_rresp),
        .o_rgb_axi_bvalid(nr_rgb_axi_bvalid),
        .o_rgb_axi_rlast(nr_rgb_axi_rlast),
        .o_rgb_axi_rvalid(nr_rgb_axi_rvalid),
        .i_rgb_axi_bready(nr_rgb_axi_bready),
        .i_rgb_axi_rready(nr_rgb_axi_rready),
        .o_rgb_axi_rdata(nr_rgb_axi_rdata),
        .i_map_axi_awid(nr_map_axi_awid),
        .i_map_axi_arid(nr_map_axi_arid),
        .i_map_axi_awaddr(nr_map_axi_awaddr),
        .i_map_axi_araddr(nr_map_axi_araddr),
        .i_map_axi_awlen(nr_map_axi_awlen),
        .i_map_axi_arlen(nr_map_axi_arlen),
        .i_map_axi_awsize(nr_map_axi_awsize),
        .i_map_axi_arsize(nr_map_axi_arsize),
        .i_map_axi_awburst(nr_map_axi_awburst),
        .i_map_axi_arburst(nr_map_axi_arburst),
        .i_map_axi_awvalid(nr_map_axi_awvalid),
        .i_map_axi_arvalid(nr_map_axi_arvalid),
        .o_map_axi_awready(nr_map_axi_awready),
        .o_map_axi_arready(nr_map_axi_arready),
        .i_map_axi_wdata(nr_map_axi_wdata),
        .i_map_axi_wstrb(nr_map_axi_wstrb),
        .i_map_axi_wlast(nr_map_axi_wlast),
        .i_map_axi_wvalid(nr_map_axi_wvalid),
        .o_map_axi_wready(nr_map_axi_wready),
        .o_map_axi_bid(nr_map_axi_bid),
        .o_map_axi_rid(nr_map_axi_rid),
        .o_map_axi_bresp(nr_map_axi_bresp),
        .o_map_axi_rresp(nr_map_axi_rresp),
        .o_map_axi_bvalid(nr_map_axi_bvalid),
        .o_map_axi_rlast(nr_map_axi_rlast),
        .o_map_axi_rvalid(nr_map_axi_rvalid),
        .i_map_axi_bready(nr_map_axi_bready),
        .i_map_axi_rready(nr_map_axi_rready),
        .o_map_axi_rdata(nr_map_axi_rdata),
        .o_record_quiescent(record_ring_quiescent),.o_write_quiescent(hdr_writer_quiescent)
    );

    // 先在 DDR 域封装完整协议记录，元数据握手时认领槽位
    // 格式化器接收最后一个 DDR 数据拍后才允许释放槽位
    wire pcie_record_ready;
    wire formatter_payload_ready,formatter_extension_ready;
    wire jpeg_drop_remaining=jpeg_record_owned&&jpeg_record_done&&!jpeg_record_ok;
    assign store_payload_ready=formatter_payload_ready||jpeg_drop_remaining;
    assign record_header_stream_ready=formatter_extension_ready||jpeg_drop_remaining;
    assign record_ready = local_dfi[1] ? dfi_rst_n : pcie_record_ready;
    c2h_frame_tx #(.RECORD_V2_ENABLE(RECORD_METADATA_ENABLE),.RECORD_V3_ENABLE(0),.RECORD_V4_ENABLE(RECORD_V3_ENABLE),
        .RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),.BORROW_EXTENSION(1),.STREAM_EXTENSION(RECORD_METADATA_ENABLE)) u_ddr_record (
        .i_clk(dfi_clk), .i_rst_n(product_dfi_reset_n),
        .i_transport_enable(1'b1), .i_link_up(1'b1),
        .i_c2h_running(1'b1),
        .i_meta_valid(store_ready_valid && record_header_ready && (local_dfi[1] || retire_meta_ready) &&
            !bridge_fault && !store_recovery),
        .o_meta_ready(record_meta_ready),
        .i_meta_frame_sequence(store_id),
        .i_meta_payload_length({7'd0,store_length}),
        .i_meta_width(store_width), .i_meta_height(store_height),
        .i_meta_pixel_format(8'd1), .i_meta_compression(8'd1),
        .i_meta_quality(VIDEO_SERVICE_ENABLE!=0 ? store_quality : 8'd75), .i_meta_timestamp_ns(store_time),
        .i_meta_status(32'd0), .i_meta_error_code(32'd0),
        .i_meta_slot_id(record_selected_version_dfi!=16'd1 ? store_slot : 16'd0), .i_meta_payload_crc32(32'd0),
        .i_meta_record_version(record_selected_version_dfi),.i_meta_record_extension(record_header_extension),
        .i_extension_tdata(record_header_stream_data),.i_extension_tvalid(record_header_stream_valid),
        .i_extension_tlast(record_header_stream_last),.o_extension_tready(formatter_extension_ready),
        .i_src_tdata(store_payload_data), .i_src_tkeep(store_payload_keep),
        .i_src_tvalid(store_payload_valid),
        .o_src_tready(formatter_payload_ready),
        .i_src_tlast(store_payload_last), .o_axis_tdata(record_data),
        .o_axis_tkeep(record_keep), .o_axis_tuser(),
        .o_axis_tvalid(record_valid), .i_axis_tready(record_ready),
        .o_axis_tlast(record_last), .o_tx_busy(record_formatter_busy), .o_transport_ready(),
        .o_active_slot_id(), .o_last_error(), .o_frame_accept(),
        .o_frame_done(record_formatter_done), .o_frame_abort(record_formatter_abort)
    );
    assign store_ready_claim = store_ready_valid && record_header_ready && record_meta_ready &&
                               (local_dfi[1] || retire_meta_ready) &&
                               !bridge_fault && !store_recovery;
    reset_release_sync_data #(.DATA_RESET_COPIES(0),.FALLING_RELEASE(1)) u_product_dfi_reset(.i_clk(dfi_clk),
        .i_async_rst_n(product_cold_reset_n),.o_rst_n(product_dfi_reset_n),
        .o_data_rst_n(product_dfi_data_reset_n));
    wire jpeg_offer=store_ready_valid&&record_header_ready&&record_meta_ready&&
        !local_dfi[1]&&!bridge_fault&&!store_recovery;
    always @(posedge dfi_clk or negedge product_dfi_reset_n)begin
        if(!product_dfi_reset_n)begin
            jpeg_record_owned<=0;jpeg_record_done<=0;jpeg_record_ok<=0;jpeg_cancel_seen<=0;
        end else begin
            if(jpeg_offer&&jpeg_source_record_ready)begin
                jpeg_record_owned<=1;jpeg_record_done<=0;jpeg_record_ok<=0;jpeg_cancel_seen<=0;
            end
            if(jpeg_record_owned&&jpeg_source_cancel&&!jpeg_record_done)jpeg_cancel_seen<=1;
            if(jpeg_record_owned&&!jpeg_record_done&&(record_formatter_done||record_formatter_abort))begin
                jpeg_record_done<=1;
                jpeg_record_ok<=record_formatter_done&&!record_formatter_abort&&!store_reader_error&&
                    !jpeg_cancel_seen&&!jpeg_source_cancel;
            end
            if(jpeg_source_retire_valid&&retire_ready)begin
                jpeg_record_owned<=0;jpeg_record_done<=0;
            end
        end
    end
    // Ring ready_* is frozen while its reader owns SENDING/R_HOLD. Borrow it
    // until the actual returned native SAFE event handshakes at that same ring.
    // Cold product selection reuses the sole opaque CDC and native DMA owner.
    // The RAW directory owns the borrowed header until returned SAFE/ACK.
    assign raw_record_ready=raw_mode_dfi&&raw_format_start_ready&&record_cdc_ready;
    assign jpeg_source_record_ready=!raw_mode_dfi&&record_cdc_ready;
    assign pcie_record_ready=!raw_mode_dfi&&record_cdc_axis_ready;
    assign raw_format_ready=raw_mode_dfi&&record_cdc_axis_ready;
    assign raw_record_cancel=raw_mode_dfi&&record_cdc_cancel;
    assign jpeg_source_cancel=!raw_mode_dfi&&record_cdc_cancel;
    assign raw_retire_valid=raw_mode_dfi&&record_cdc_retire_valid;
    assign raw_retire_identity=record_cdc_retire_identity;
    assign jpeg_source_retire_valid=!raw_mode_dfi&&record_cdc_retire_valid;
    assign jpeg_source_retire_identity=record_cdc_retire_identity;
    assign jpeg_source_retire_status=record_cdc_retire_status;
    raw_video_record_formatter #(.SEPARATE_DATA_RESET(1)) u_raw_formatter(
        .i_clk(dfi_clk),.i_rst_n(product_dfi_reset_n),.i_data_reset_n(product_dfi_data_reset_n),
        .i_start_valid(raw_mode_dfi&&raw_record_valid&&record_cdc_ready),.o_start_ready(raw_format_start_ready),
        .i_abort(raw_record_done&&!raw_record_ok),.o_drained(raw_format_drained),
        .i_payload_bytes(FRAME_WIDTH*FRAME_HEIGHT/4*5),.i_width(FRAME_WIDTH[15:0]),.i_height(FRAME_HEIGHT[15:0]),
        .i_sequence(stereo_job_frame[108:77]),.i_session(stereo_job_frame[76:45]),.i_epoch(stereo_job_frame[140:109]),
        .i_camera(stereo_job_frame[4]),.i_bayer_phase(stereo_job_bayer),.i_time_valid(stereo_job_time_valid),
        .i_capture_time_ns(stereo_job_frame[204:141]),.i_job_id(stereo_job_id),
        .s_data(raw_payload_data),.s_keep(raw_payload_keep),.s_valid(raw_payload_valid),.s_last(raw_payload_last),.s_ready(raw_payload_ready),
        .m_data(raw_format_data),.m_keep(raw_format_keep),.m_valid(raw_format_valid),.m_last(raw_format_last),.m_ready(raw_format_ready),.o_done());
    product_record_cdc u_ddr_to_pcie(
        .s_clk(dfi_clk),.m_clk(user_clk),.s_cold_rst_n(product_cold_reset_n),.m_cold_rst_n(user_rst_n),
        .s_record_valid(raw_mode_dfi?raw_record_valid&&raw_format_start_ready:jpeg_offer),.s_record_ready(record_cdc_ready),
        .s_record_length(raw_mode_dfi?raw_record_length:jpeg_record_length),.s_record_identity(raw_mode_dfi?raw_record_identity:jpeg_record_identity),
        .s_axis_data(raw_mode_dfi?raw_format_data:record_data),.s_axis_keep(raw_mode_dfi?raw_format_keep:record_keep),.s_axis_valid(raw_mode_dfi?raw_format_valid:record_valid&&!local_dfi[1]),
        .s_axis_last(raw_mode_dfi?raw_format_last:record_last),.s_axis_ready(record_cdc_axis_ready),
        .s_done_valid(raw_mode_dfi?raw_record_done:jpeg_record_owned&&jpeg_record_done),.s_done_ok(raw_mode_dfi?raw_record_ok:jpeg_record_ok),
        .s_drained(raw_mode_dfi?(raw_record_drained&&raw_format_drained):(jpeg_record_owned&&jpeg_record_done&&store_reader_complete&&!record_formatter_busy&&
            !record_valid&&!store_payload_valid&&!record_header_stream_valid)),.s_cancel(record_cdc_cancel),
        .s_retire_valid(record_cdc_retire_valid),.s_retire_ready(raw_mode_dfi?raw_retire_ready:retire_ready),
        .s_retire_identity(record_cdc_retire_identity),.s_retire_status(record_cdc_retire_status),
        .m_record_valid(jpeg_user_record_valid),.m_record_ready(jpeg_user_record_ready),
        .m_record_length(jpeg_user_record_length),.m_record_identity(jpeg_user_record_identity),
        .m_axis_data(jpeg_user_axis_data),.m_axis_keep(jpeg_user_axis_keep),.m_axis_valid(jpeg_user_axis_valid),
        .m_axis_last(jpeg_user_axis_last),.m_axis_ready(jpeg_user_axis_ready),
        .m_done_valid(jpeg_user_done_valid),.m_done_ok(jpeg_user_done_ok),.m_drained(jpeg_user_drained),
        .m_cancel(jpeg_user_cancel),.m_retire_valid(jpeg_user_retire_valid),.m_retire_ready(jpeg_user_retire_ready),
        .m_retire_identity(jpeg_user_retire_identity),.m_retire_status(jpeg_user_retire_status),
        .s_busy(jpeg_cdc_source_busy),.m_busy(jpeg_cdc_user_busy),.s_fault(jpeg_cdc_source_fault),.m_fault(jpeg_cdc_user_fault),
        .s_reset_done(record_src_reset_done),.m_reset_done(record_sink_reset_done));

    // Only the HDR RAW client remains; no inner RAW/LZ arbitration or queues.
    assign raw_axi_awid=capture_axi_awid;
    assign raw_axi_awaddr=capture_axi_awaddr;
    assign raw_axi_awlen=capture_axi_awlen;
    assign raw_axi_awsize=capture_axi_awsize;
    assign raw_axi_awburst=capture_axi_awburst;
    assign raw_axi_awvalid=capture_axi_awvalid;
    assign raw_axi_wdata=capture_axi_wdata;
    assign raw_axi_wstrb=capture_axi_wstrb;
    assign raw_axi_wlast=capture_axi_wlast;
    assign raw_axi_wvalid=capture_axi_wvalid;
    assign raw_axi_bready=capture_axi_bready;
    assign raw_axi_arid=capture_axi_arid;
    assign raw_axi_araddr=capture_axi_araddr;
    assign raw_axi_arlen=capture_axi_arlen;
    assign raw_axi_arsize=capture_axi_arsize;
    assign raw_axi_arburst=capture_axi_arburst;
    assign raw_axi_arvalid=capture_axi_arvalid;
    assign raw_axi_rready=capture_axi_rready;
    assign capture_axi_awready=raw_axi_awready;
    assign capture_axi_wready=raw_axi_wready;
    assign capture_axi_bid=raw_axi_bid;
    assign capture_axi_bresp=raw_axi_bresp;
    assign capture_axi_bvalid=raw_axi_bvalid;
    assign capture_axi_arready=raw_axi_arready;
    assign capture_axi_rid=raw_axi_rid;
    assign capture_axi_rdata=raw_axi_rdata;
    assign capture_axi_rresp=raw_axi_rresp;
    assign capture_axi_rlast=raw_axi_rlast;
    assign capture_axi_rvalid=raw_axi_rvalid;

    production_soft_reset_fence u_soft_reset_fence(
        .user_clk(user_clk),.pixel_clk(pixel_clk),.dfi_clk(dfi_clk),.cold_reset_n(product_cold_reset_n),
        .soft_reset_request(soft_reset),.pixel_quiet(cfg_pipeline_idle),
        .dfi_quiet(record_dfi_data_quiescent&&!store_ready_valid&&!record_valid&&!jpeg_cdc_source_busy),
        .user_quiet(!tx_busy&&!product_result_pending&&!product_buffer_armed&&!transport_recovery&&!jpeg_cdc_user_fault),
        .token_drain_proven_pixel(reset_source_proven),.pixel_data_reset_n(pixel_rst_n),
        .user_initialized(cfg_user_initialized),.user_session(cfg_user_session),.rearm_ready_async(session_rearm_ready),
        .pause_pixel(reset_pause_pixel),.pending_user(reset_pending_user),.execute_reset_user(reset_execute_user),
        .marker_request_pixel(reset_marker_request));

    wire [127:0] h2c_data;
    wire [15:0] h2c_keep, h2c_user;
    wire h2c_valid, h2c_ready, h2c_last;
    wire [31:0] axil_awaddr, axil_wdata, axil_araddr, axil_rdata;
    wire [2:0] axil_awprot, axil_arprot;
    wire [3:0] axil_wstrb;
    wire axil_awvalid, axil_awready, axil_wvalid, axil_wready;
    wire axil_bvalid, axil_bready, axil_arvalid, axil_arready;
    wire axil_rvalid, axil_rready;
    wire [1:0] axil_bresp, axil_rresp;
    wire [15:0] pcie_diag_flags, pcie_diag_keep;
    wire [31:0] pcie_diag_sequence, pcie_diag_payload_length;
    wire [31:0] transport_error;
    // The complete DFI record is not parsed or formatted again in USER.
    product_pcie_transport u_pcie (
        .i_sys_clk(sys_clk), .i_refclk_p(refclk_p), .i_refclk_n(refclk_n),
        .i_pcie_mperst(endpoint_rst_n), .i_pcie_rxp(rxp), .i_pcie_rxn(rxn),
        .i_ownership_reset_n(product_cold_reset_n),
        .o_pcie_txp(txp), .o_pcie_txn(txn),
        .i_app_enable(app_enable && armed_user[1] && !local_user[1]),
        .i_app_reset_n(transport_user_reset_n),
        .i_product_fault(jpeg_cdc_user_fault||product_fault_user[1]||memory_fault_user),
        .i_p0_record_valid(jpeg_user_record_valid),.o_p0_record_ready(jpeg_user_record_ready),
        .i_p0_record_length(jpeg_user_record_length),.i_p0_record_identity(jpeg_user_record_identity),
        .i_p0_axis_data(jpeg_user_axis_data),.i_p0_axis_keep(jpeg_user_axis_keep),
        .i_p0_axis_valid(jpeg_user_axis_valid),.i_p0_axis_last(jpeg_user_axis_last),.o_p0_axis_ready(jpeg_user_axis_ready),
        .i_p0_done_valid(jpeg_user_done_valid),.i_p0_done_ok(jpeg_user_done_ok),.i_p0_drained(jpeg_user_drained),
        .o_p0_cancel(jpeg_user_cancel),.o_p0_retire_valid(jpeg_user_retire_valid),.i_p0_retire_ready(jpeg_user_retire_ready),
        .o_p0_retire_identity(jpeg_user_retire_identity),.o_p0_retire_status(jpeg_user_retire_status),
        // The second legacy endpoint port has no producer in this image.
        .i_p1_record_valid(1'b0),.o_p1_record_ready(),.i_p1_record_length(32'd0),.i_p1_record_identity(128'd0),
        .i_p1_axis_data(128'd0),.i_p1_axis_keep(16'd0),.i_p1_axis_valid(1'b0),.i_p1_axis_last(1'b0),.o_p1_axis_ready(),
        .i_p1_done_valid(1'b0),.i_p1_done_ok(1'b0),.i_p1_drained(1'b1),.o_p1_cancel(),
        .o_p1_retire_valid(),.i_p1_retire_ready(1'b1),.o_p1_retire_identity(),.o_p1_retire_status(),
        .o_axil_awaddr(axil_awaddr), .o_axil_awprot(axil_awprot),
        .o_axil_awvalid(axil_awvalid), .i_axil_awready(axil_awready),
        .o_axil_wdata(axil_wdata), .o_axil_wstrb(axil_wstrb),
        .o_axil_wvalid(axil_wvalid), .i_axil_wready(axil_wready),
        .i_axil_bresp(axil_bresp), .i_axil_bvalid(axil_bvalid),
        .o_axil_bready(axil_bready), .o_axil_araddr(axil_araddr),
        .o_axil_arprot(axil_arprot), .o_axil_arvalid(axil_arvalid),
        .i_axil_arready(axil_arready), .i_axil_rdata(axil_rdata),
        .i_axil_rresp(axil_rresp), .i_axil_rvalid(axil_rvalid),
        .o_axil_rready(axil_rready),.o_axil_fault(product_axil_fault),.o_user_clk(user_clk),
        .o_ownership_rst_n(user_rst_n),.o_link_up(user_link_up),.o_observe(transport_observe),
        .o_busy(product_transport_busy),.o_quarantine(transport_recovery),
        .o_buffer_armed(product_buffer_armed),.o_result_pending(product_result_pending)
    );
    // Reuse the qualified incident-capture structure for memory continuity.
    // The watch clock runs even when a data clock stops. Neither PERST nor
    // ordinary session reset can clear this product recovery quarantine.
    c2h_link_supervisor u_memory_owner_watch(
        .i_watch_clk(sys_clk),.i_user_clk(user_clk),.i_recovery_reset_n(product_cold_reset_n),
        .i_link_up(ddr_app_ready),.i_bme(1'b1),.i_perst_n(1'b1),
        .i_pll_lock(ddr_phy_rst_n),.i_core_reset_n(1'b1),
        .o_fault(memory_fault_user),.o_ready(memory_owner_ready));
    always @(posedge dfi_clk or posedge memory_fault_user)begin
        if(memory_fault_user)memory_fault_dfi<=2'b11;
        else memory_fault_dfi<={memory_fault_dfi[0],1'b0};
    end
    always @(posedge user_clk or negedge user_rst_n)begin
        if(!user_rst_n)product_fault_user<=0;
        else product_fault_user<={product_fault_user[0],reset_source_fault||reset_sink_fault||jpeg_cdc_source_fault||
            bridge_fault||store_recovery||record_ordered_fault||record_metadata_fault||record_source_fault};
    end
    assign retire_user_fault=jpeg_cdc_user_fault||product_fault_user[1]||memory_fault_user;

    always @(posedge user_clk or negedge user_rst_n)begin
        if(!user_rst_n)begin jpeg_native_bound<=0;end
        else begin
            if(jpeg_user_record_valid&&jpeg_user_record_ready)jpeg_native_bound<=1;
            if(jpeg_user_retire_valid&&jpeg_user_retire_ready)jpeg_native_bound<=0;
        end
    end
    assign c2h_running=product_buffer_armed||jpeg_native_bound;
    assign tx_busy=product_transport_busy||jpeg_cdc_user_busy;
    assign frame_accept=jpeg_user_record_valid&&jpeg_user_record_ready;
    assign frame_done=jpeg_user_retire_valid&&jpeg_user_retire_ready&&jpeg_user_retire_status==0;
    assign frame_abort=jpeg_user_retire_valid&&jpeg_user_retire_ready&&jpeg_user_retire_status!=0;
    assign actual_c2h_valid=jpeg_user_axis_valid;assign actual_c2h_ready=jpeg_user_axis_ready;assign actual_c2h_last=jpeg_user_axis_last;
    assign transport_error=transport_recovery?`PCIE_ERROR_RECOVERY_REQUIRED:`PCIE_ERROR_NONE;
    assign h2c_data=0;assign h2c_keep=0;assign h2c_user=0;assign h2c_valid=0;assign h2c_last=0;
    assign c2h_status=0;assign h2c_status=0;assign pcie_diag_flags=0;assign pcie_diag_keep=0;
    assign pcie_diag_sequence=0;assign pcie_diag_payload_length=0;
    wire [31:0] h2c_bytes, h2c_frames, h2c_errors, h2c_first_error;
    // 接收并检查主机下行数据，统计结果映射到应用寄存器
    h2c_stream_checker u_h2c_checker (
        .i_clk(user_clk), .i_rst_n(user_session_rst_n),
        .i_axis_tdata(h2c_data), .i_axis_tkeep(h2c_keep),
        .i_axis_tvalid(h2c_valid), .o_axis_tready(h2c_ready),
        .i_axis_tlast(h2c_last), .o_byte_count(h2c_bytes),
        .o_frame_count(h2c_frames), .o_error_count(h2c_errors),
        .o_first_error_offset(h2c_first_error)
    );
    // 跨域采样诊断状态，并在用户域统计记录接受、完成与中止事件
    reg [1:0] free_user, source_active_user, fault_user;
    reg [31:0] producer_count, consumed_count, dma_errors;
    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            free_user <= 0; source_active_user <= 0; fault_user <= 0;
            producer_count <= 0; consumed_count <= 0; dma_errors <= 0;
        end else begin
            free_user <= {free_user[0], store_ready_valid};
            source_active_user <= {source_active_user[0], frame_active_pixel};
            fault_user <= {fault_user[0], bridge_fault || store_recovery ||
                           admission_protocol_fault || credit_fault || retire_user_fault || session_rearm_required};
            if (frame_accept) producer_count <= producer_count + 32'd1;
            if (frame_done) consumed_count <= consumed_count + 32'd1;
            if (frame_abort) dma_errors <= dma_errors + 32'd1;
        end
    end
    wire [31:0] app_status = {24'd0,armed_user[1],rearm_ready_user[1],
        transport_recovery || fault_user[1],source_active_user[1],
        tx_busy,c2h_running,user_rst_n,user_link_up};
    // Ring and RAW proofs include their accepted FIFO traffic and retained
    // owners. CONFIG may retire an unused credit; format SELECT may not.
    assign record_dfi_data_quiescent=dfi_rst_n&&record_ring_quiescent&&
        raw_capture_write_quiescent&&raw_read_quiescent&&record_pixel_quiescent_dfi&&
        raw_region_quiet&&
        (PRIVATE_PROCESSING_ENABLE==0 || (raw_private_ownership_quiescent&&raw_processing_quiescent))&&
        f21_pipeline_quiet&&
        record_metadata_quiescent&&!ddr_start_valid&&!ddr_jpeg_valid&&!ddr_result_valid&&
        !record_dfi_extension_valid&&!writer_ack_valid&&!record_formatter_busy&&
        !local_retire_pending&&!retire_valid&&!jpeg_cdc_source_busy&&!bridge_fault&&!store_recovery;
    assign record_dfi_select_quiescent=record_dfi_data_quiescent&&!credit_reserved_dfi&&
        !raw_job_config_valid&&!raw_job_config_done&&!raw_job_config_busy&&record_source_active_valid;
    always @(posedge user_clk or negedge user_rst_n) begin
        if(!user_rst_n)begin record_idle_user<=0;record_source_valid_user<=0;end
        else begin
            record_idle_user<={record_idle_user[0],record_dfi_select_quiescent};
            record_source_valid_user<={record_source_valid_user[0],record_source_active_valid&&record_format_dfi_ready};
        end
    end
    generate if(RECORD_METADATA_ENABLE!=0) begin : g_record_format
        record_format_service #(.NEUTRAL_STATS_ENABLE(NEUTRAL_STATS_ENABLE),.RECORD_V3_ENABLE(RECORD_V3_ENABLE)) u_format(
            .i_user_clk(user_clk),.i_user_rst_n(user_rst_n),
            .write_valid(record_bar_write_valid),.write_offset(record_bar_write_offset),
            .write_data(record_bar_write_data),.write_strobes(record_bar_write_strobes),.write_response(record_bar_write_response),
            .read_valid(record_bar_read_valid),.read_offset(record_bar_read_offset),
            .read_response_valid(record_bar_read_response_valid),.read_data(record_bar_read_data),.read_response(record_bar_read_response),
            .i_user_source_session(cfg_user_session),.i_user_source_session_ready(cfg_user_initialized&&record_source_valid_user[1]),
            .i_app_enable(app_enable),.i_c2h_running(c2h_running),.i_tx_busy(tx_busy),
            .i_source_functional_quiescent(record_idle_user[1]),.i_session_armed(armed_user[1]),.i_rearm_ready(rearm_ready_user[1]),
            .o_user_busy(record_format_busy),.o_user_selected_version(record_selected_version_user),
            .o_user_selected_header_length(),.o_user_selection_epoch(),.o_user_reset_done(record_format_user_ready),.o_stale_ack_count(),
            .i_dfi_clk(dfi_clk),.i_dfi_rst_n(dfi_rst_n),
            .i_dfi_source_session(record_source_active_session),.i_dfi_quiescent(record_dfi_select_quiescent),
            .o_dfi_selected_version(record_selected_version_dfi),.o_dfi_selection_epoch(),.o_dfi_reset_done(record_format_dfi_ready));
    end else begin : g_legacy_record_format
        assign record_selected_version_user=16'd1;assign record_selected_version_dfi=16'd1;
        assign record_format_busy=0;assign record_format_user_ready=0;assign record_format_dfi_ready=0;
        assign record_bar_write_response=2'b10;assign record_bar_read_response_valid=0;
        assign record_bar_read_data=0;assign record_bar_read_response=2'b10;
    end endgenerate
    // The processing chain still needs locally released reset. No algorithm
    // BAR endpoint, reciprocal table, LUT status CDC or loading owner remains.
    generate begin:g_live_core_reset
        wire core_cohort_n=live_f21_rst_n &&
            (source_local_pixel ? pixel_rst_n&&dfi_rst_n : user_session_rst_n);
        reset_release_sync u_reset(.i_clk(pixel_clk),.i_async_rst_n(core_cohort_n),
            .o_rst_n(f21_core_async_reset_n));
        (* preserve="true" *) reg core_run=1'b0;
        always @(posedge pixel_clk)core_run<=f21_core_async_reset_n;
        assign f21_core_reset_n=core_run;
    end endgenerate
    assign f21_load_permitted=0;
    assign f21_cfg_begin_valid=0;assign f21_cfg_generation=0;
    assign f21_cfg_valid=0;assign f21_cfg_index=0;assign f21_cfg_value=0;
    assign f21_cfg_commit_valid=0;assign f21_cfg_abort=0;assign f21_cfg_status_ready=1;
    assign f21_owned_lut_valid=0;assign f21_owned_lut_generation=0;
    assign f21_lut_update_busy=0;assign f21_lut_fault=0;
    assign algo_bar_write_response=2'b10;assign algo_bar_read_response_valid=0;
    assign algo_bar_read_data=0;assign algo_bar_read_response=2'b10;
    generate if(DUAL_CAMERA_ENABLE!=0)begin:g_stereo_control
        stereo_cold_control #(.FRAME_DIVISOR(STEREO_CAPTURE_DIVISOR),.RAW_EXPORT_ENABLE(1)) u_stereo_control(
            .user_clk(user_clk),.user_rst_n(user_rst_n),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.dfi_clk(dfi_clk),.dfi_rst_n(dfi_rst_n),
            .write_valid(stereo_bar_write_valid),.write_offset(stereo_bar_write_offset),.write_data(stereo_bar_write_data),.write_strobes(stereo_bar_write_strobes),.write_response(stereo_bar_write_response),
            .read_valid(stereo_bar_read_valid),.read_offset(stereo_bar_read_offset),.read_response_valid(stereo_bar_read_response_valid),.read_data(stereo_bar_read_data),.read_response(stereo_bar_read_response),
            .i_app_enable(app_enable),.i_c2h_running(c2h_running),.i_user_config_idle(cfg_user_transaction_idle&&cfg_user_stereo_compatible),
            .i_pixel_quiet(cfg_pipeline_idle&&(!(stereo_mode_pixel||raw_mode_pixel)||stereo_source0_idle)&&(!stereo_mode_pixel||stereo_source1_idle)),
            .i_dfi_quiet(record_dfi_data_quiescent&&!raw_job_config_busy&&!raw_job_config_valid),
            .o_user_busy(stereo_busy_user),.o_user_locked(stereo_locked_user),.o_user_mode(stereo_mode_user),.o_user_start_inhibit(stereo_start_inhibit),
            .o_user_frame_divisor(stereo_divisor_user),.o_pixel_frame_divisor(stereo_divisor_pixel),.o_dfi_frame_divisor(stereo_divisor_dfi),
            .o_pixel_mode(stereo_mode_pixel),.o_dfi_mode(stereo_mode_dfi),.o_pixel_pause(stereo_pause_pixel),.o_dfi_pause(stereo_pause_dfi),
            .o_user_raw(raw_mode_user),.o_pixel_raw(raw_mode_pixel),.o_dfi_raw(raw_mode_dfi));
    end else begin:g_mono_cold_control
        assign stereo_mode_user=0;assign stereo_mode_pixel=0;assign stereo_mode_dfi=0;
        assign raw_mode_user=0;assign raw_mode_pixel=0;assign raw_mode_dfi=0;
        assign stereo_divisor_user=STEREO_CAPTURE_DIVISOR;assign stereo_divisor_pixel=STEREO_CAPTURE_DIVISOR;assign stereo_divisor_dfi=STEREO_CAPTURE_DIVISOR;
        assign stereo_busy_user=0;assign stereo_locked_user=0;assign stereo_start_inhibit=0;
        assign stereo_pause_pixel=0;assign stereo_pause_dfi=0;
        assign stereo_bar_write_response=2'b10;assign stereo_bar_read_response_valid=0;assign stereo_bar_read_data=0;assign stereo_bar_read_response=2'b10;
    end endgenerate
    // AXI-Lite 寄存器提供应用控制与链路诊断
    mono_pcie_app_regs_v2 #(.STEREO_ENABLE(DUAL_CAMERA_ENABLE),.MONO_SCHEMA2_ENABLE(1),.RAW_ENABLE(0),.CONFIG_ENABLE(VIDEO_SERVICE_ENABLE),.JPEG_RING_ENABLE(VIDEO_SERVICE_ENABLE),
        .RECORD_ENABLE(RECORD_METADATA_ENABLE),.CONFIG_EXT_ENABLE(CONFIGURED_CAPTURE_ENABLE),.ALGO_ENABLE(0)) u_app_regs (
        .i_clk(user_clk), .i_rst_n(user_rst_n),
        .i_stereo_start_inhibit(stereo_start_inhibit||(!raw_mode_user&&stereo_mode_user&&
            record_selected_version_user!=`PCIE_RECORD_V2_VERSION&&record_selected_version_user!=`PCIE_RECORD_V4_VERSION)),
        .o_stereo_write_valid(stereo_bar_write_valid),.o_stereo_write_offset(stereo_bar_write_offset),.o_stereo_write_data(stereo_bar_write_data),.o_stereo_write_strobes(stereo_bar_write_strobes),.i_stereo_write_response(stereo_bar_write_response),
        .o_stereo_read_valid(stereo_bar_read_valid),.o_stereo_read_offset(stereo_bar_read_offset),.i_stereo_read_response_valid(stereo_bar_read_response_valid),.i_stereo_read_data(stereo_bar_read_data),.i_stereo_read_response(stereo_bar_read_response),
        .i_axil_awaddr(axil_awaddr), .i_axil_awprot(axil_awprot),
        .i_axil_awvalid(axil_awvalid), .o_axil_awready(axil_awready),
        .i_axil_wdata(axil_wdata), .i_axil_wstrb(axil_wstrb),
        .i_axil_wvalid(axil_wvalid), .o_axil_wready(axil_wready),
        .o_axil_bresp(axil_bresp), .o_axil_bvalid(axil_bvalid),
        .i_axil_bready(axil_bready), .i_axil_araddr(axil_araddr),
        .i_axil_arprot(axil_arprot), .i_axil_arvalid(axil_arvalid),
        .o_axil_arready(axil_arready), .o_axil_rdata(axil_rdata),
        .o_axil_rresp(axil_rresp), .o_axil_rvalid(axil_rvalid),
        .i_axil_rready(axil_rready), .i_status(app_status),
        .i_ready_mask({31'd0,free_user[1]}),
        .i_sending_mask({31'd0,tx_busy}),
        .i_producer_sequence(producer_count),
        .i_consumed_sequence(consumed_count),
        .i_drop_count(32'd0), .i_overflow_count(32'd0),
        .i_dma_error_count(dma_errors), .i_last_error(transport_error),
        .i_h2c_byte_count(h2c_bytes), .i_h2c_frame_count(h2c_frames),
        .i_h2c_error_count(h2c_errors),
        .i_h2c_first_error(h2c_first_error),
        .o_app_enable(app_enable), .o_soft_reset(soft_reset),
        .o_test_length(), .o_test_pattern(), .o_test_trigger(),
        .o_raw_write_valid(raw_bar_write_valid), .o_raw_write_offset(raw_bar_write_offset),
        .o_raw_write_data(raw_bar_write_data), .o_raw_write_strobes(raw_bar_write_strobes),
        .i_raw_write_response(raw_bar_write_response),
        .o_raw_read_valid(raw_bar_read_valid), .o_raw_read_offset(raw_bar_read_offset),
        .i_raw_read_response_valid(raw_bar_read_response_valid),
        .i_raw_read_data(raw_bar_read_data), .i_raw_read_response(raw_bar_read_response),
        .o_cfg_write_valid(cfg_bar_write_valid),.o_cfg_write_offset(cfg_bar_write_offset),
        .o_cfg_write_data(cfg_bar_write_data),.o_cfg_write_strobes(cfg_bar_write_strobes),.i_cfg_write_response(cfg_bar_write_response),
        .o_algo_write_valid(algo_bar_write_valid),.o_algo_write_offset(algo_bar_write_offset),
        .o_algo_write_data(algo_bar_write_data),.o_algo_write_strobes(algo_bar_write_strobes),
        .i_algo_write_response(algo_bar_write_response),.o_algo_read_valid(algo_bar_read_valid),.o_algo_read_offset(algo_bar_read_offset),
        .i_algo_read_response_valid(algo_bar_read_response_valid),.i_algo_read_data(algo_bar_read_data),.i_algo_read_response(algo_bar_read_response),
        .o_cfg_read_valid(cfg_bar_read_valid),.o_cfg_read_offset(cfg_bar_read_offset),
        .i_cfg_read_response_valid(cfg_bar_read_response_valid),.i_cfg_read_data(cfg_bar_read_data),.i_cfg_read_response(cfg_bar_read_response),
        .o_jpeg_write_valid(jpeg_bar_write_valid),.o_jpeg_write_offset(jpeg_bar_write_offset),
        .o_jpeg_write_data(jpeg_bar_write_data),.o_jpeg_write_strobes(jpeg_bar_write_strobes),.i_jpeg_write_response(jpeg_bar_write_response),
        .o_jpeg_read_valid(jpeg_bar_read_valid),.o_jpeg_read_offset(jpeg_bar_read_offset),
        .i_jpeg_read_response_valid(jpeg_bar_read_response_valid),.i_jpeg_read_data(jpeg_bar_read_data),
        .i_jpeg_read_response(jpeg_bar_read_response),
        .o_record_write_valid(record_bar_write_valid),.o_record_write_offset(record_bar_write_offset),
        .o_record_write_data(record_bar_write_data),.o_record_write_strobes(record_bar_write_strobes),
        .i_record_write_response(record_bar_write_response),.o_record_read_valid(record_bar_read_valid),
        .o_record_read_offset(record_bar_read_offset),.i_record_read_response_valid(record_bar_read_response_valid),
        .i_record_read_data(record_bar_read_data),.i_record_read_response(record_bar_read_response)
    );
    // Debug is deliberately outside the application and PCIe reset domains.
    wire [511:0] debug_sys_status, debug_pixel_status, debug_dfi_status;
    wire debug_dfi_frame, debug_dfi_error;
    wire [5:0] debug_alive;
    reg [16:0] debug_flags_meta, debug_flags_sync;
    reg [24:0] debug_second_count;
    reg [31:0] debug_seconds;
    reg debug_sticky_fault, debug_clear_seen;
    reg dma_exposed_ever;
    reg [1:0] maintenance_running_sync,maintenance_exposed_sync;
    always @(posedge user_clk or negedge debug_user_rst_n) begin
        if(!debug_user_rst_n) dma_exposed_ever<=0;
        else if(app_enable || c2h_running || frame_accept) dma_exposed_ever<=1;
    end
    always @(posedge sys_clk or negedge debug_rst_n) begin
        if(!debug_rst_n) begin maintenance_running_sync<=0;maintenance_exposed_sync<=0;end
        else begin
            maintenance_running_sync<={maintenance_running_sync[0],debug_run || session_armed};
            maintenance_exposed_sync<={maintenance_exposed_sync[0],dma_exposed_ever};
        end
    end
    // The endpoint remains reset throughout cold LOCAL ownership. STOP only
    // blocks new frames; accepted JPEG/DDR/record owners continue to retire.
    assign local_stop_authorized=debug_local && !maintenance_exposed_sync[1];
    fpga_debug_local_stop u_local_stop (
        .i_sys_clk(sys_clk),.i_sys_rst_n(debug_rst_n),.i_request(local_stop_request),
        .o_ready(local_stop_ready),.o_done(local_stop_done),
        .i_pixel_clk(pixel_clk),.i_pixel_rst_n(debug_pixel_rst_n),
        .i_pixel_active(pixel_rst_n),.i_pixel_quiet(cfg_pipeline_idle &&
            !start_valid && !record_source_extension_valid && record_builder_ready),
        .i_start_fire(start_valid && start_ready),.o_pause_new_frames(local_stop_pause),
        .i_dfi_clk(dfi_clk),.i_dfi_rst_n(debug_dfi_rst_n),.i_dfi_active(dfi_rst_n),
        .i_dfi_quiet(record_dfi_data_quiescent && !store_ready_valid && !record_valid),
        .i_retire_fire(local_dfi[1] && local_retire_pending && ring_retire_ready),
        // A failed writer ACK proves the owned slot is ABORTED and AXI drained.
        // This settles a failed admission; it never fabricates a record RETIRE.
        .i_failed_write_fire(local_dfi[1] && writer_ack_valid && writer_ack_ready && !writer_ack_ok));
    // Only the cold, unexposed LOCAL_IDLE state proves no DMA ownership exists.
    // Online recovery requires a host broker; BUSY=0 supplies no such proof.
    wire cold_local_idle=debug_local && !debug_run && !maintenance_running_sync[1] && !maintenance_exposed_sync[1];
    wire [2:0] maintenance_state=cold_local_idle ? 3'd1 :
        maintenance_running_sync[1] ? 3'd2 : 3'd4;
    generate if (DEBUG_UART_ENABLE != 0) begin : g_debug_uart
    fpga_debug_clocks u_debug_clocks (
        .i_clk(sys_clk), .i_rst_n(debug_rst_n),
        .i_clocks({user_clk,dfi_clk,board_ref_clk_100m_gclk,camera_ref_clk,sensor_clk,pixel_clk}),
        .o_alive(debug_alive));
    always @(posedge sys_clk) begin
        if(!debug_rst_n) begin
            debug_flags_meta<=0;debug_flags_sync<=0;debug_second_count<=0;
            debug_seconds<=0;debug_sticky_fault<=0;debug_clear_seen<=0;
        end else begin
            debug_flags_meta<={endpoint_rst_n,user_link_up,user_rst_n,dfi_rst_n,pixel_rst_n,
                session_rearm_required,session_rearm_ready,session_armed,ddr_phy_rst_n,
                ddr_app_ready,ddr_cal_done,camera_pll_lock,pixel_pll_lock,pcie_mperst,
                debug_app_rst_n,debug_run,debug_local};
            debug_flags_sync<=debug_flags_meta;
            if(debug_second_count==24999999) begin debug_second_count<=0;debug_seconds<=debug_seconds+1'b1;end
            else debug_second_count<=debug_second_count+1'b1;
            if(debug_clear_seen!=debug_clear) begin debug_sticky_fault<=0;debug_clear_seen<=debug_clear;end
            // The session controller stretches even a sub-cycle fatal event
            // into this system-clock flag; raw faults can clear on app reset.
            else if(session_rearm_required) debug_sticky_fault<=1;
        end
    end
    assign debug_sys_status={32'd2,(VIDEO_SERVICE_ENABLE != 0 ? 32'h0000003f : 32'h0000000f),
        (R8_STAGE1_ENABLE ? 32'h20261011 : (S04_ENABLE != 0 ? 32'h20261006 : 32'h20261005)),
        (R8_STAGE1_ENABLE ? 32'h52385332 : (S04_ENABLE != 0 ? 32'h52415734 : 32'h46444936)),32'd64,32'd256,32'd25000000,32'd57600,
        31'd0,debug_sticky_fault,debug_timeouts,debug_rx_errors,debug_seconds,
        26'd0,debug_alive,15'd0,debug_flags_sync,32'd1,32'h44424731};
    // Stage2 keeps source snapshots, first faults and maintenance control;
    // only the optional trace capture/read service is absent in this profile.
    fpga_debug_control #(.DOMAIN_COUNT(3), .COLOR_CONFIG_ENABLE(1),
        .COLOR_CONFIG_DEFAULT(COLOR_CONFIG_DEFAULT),
        .COLOR_WB_DEFAULT(COLOR_WB_DEFAULT),.DEBUG_PROFILE(R8_STAGE1_ENABLE ? 2 : (S04_ENABLE ? 1 : 0)),
        .DEBUG_EXT_ENABLE(VIDEO_SERVICE_ENABLE),.MAINTENANCE_INTERLOCK(VIDEO_SERVICE_ENABLE),
        .COOPERATIVE_LOCAL_STOP_ENABLE(VIDEO_SERVICE_ENABLE),
        .TRACE_BANK_MASK(R8_BASIC_PREPROCESS_ENABLE ? 3'b000 :
            (R8_STAGE1_ENABLE ? 3'b001 : (S04_ENABLE ? 3'b000 : 3'b111)))) u_debug_control (
        .i_clk(sys_clk), .i_rx(uart_rx), .o_tx(uart_tx), .i_sys_status(debug_sys_status),
        .o_debug_rst_n(debug_rst_n), .o_app_rst_n(debug_app_rst_n),
        .o_local(debug_local), .o_run(debug_run), .o_clear(debug_clear),
        .o_request(debug_request), .o_command(debug_command),
        .i_ack(debug_ack), .i_response(debug_response),
        .o_rx_errors(debug_rx_errors), .o_timeouts(debug_timeouts),
        .o_color_config(debug_color_config), .o_color_wb(debug_color_wb),
        .o_image_config(),
        .i_maintenance_authorized(cold_local_idle),.i_maintenance_state(maintenance_state),.o_maintenance_denied(),
        .i_local_stop_authorized(local_stop_authorized),.i_local_stop_ready(local_stop_ready),
        .i_local_stop_done(local_stop_done),.o_local_stop_request(local_stop_request));

    reg [1:0] debug_clear_pixel;
    reg debug_clear_pixel_seen;
    reg [31:0] debug_jpeg_id,debug_jpeg_length,debug_jpeg_error;
    reg [31:0] debug_jpeg_results,debug_jpeg_success,debug_pixel_fault;
    reg [31:0] debug_rgb_beats,debug_jpeg_beats;
    reg [31:0] debug_pixel_cycles;
    wire pixel_clear_event,dfi_clear_event,pcie_clear_event;
    wire [31:0] dfi_fault_causes,pcie_fault_causes;
    wire [255:0] dfi_fault_context,pcie_fault_context;
    reg [255:0] debug_job_status;
    reg debug_job_pending,debug_job_ok;
    reg [7:0] debug_job_quality;
    reg [31:0] debug_job_session,debug_job_epoch,debug_job_sequence;
    reg [31:0] debug_job_config,debug_job_budget,debug_job_length;
    // Result and the feedback controller update on one edge. Capture feedback
    // one edge later so the entire diagnostic tuple describes that result.
    always @(posedge pixel_clk or negedge debug_pixel_rst_n) begin
        if(!debug_pixel_rst_n) begin
            debug_job_status<=0;debug_job_pending<=0;debug_job_ok<=0;debug_job_quality<=0;
            debug_job_session<=0;debug_job_epoch<=0;debug_job_sequence<=0;
            debug_job_config<=0;debug_job_budget<=0;debug_job_length<=0;
        end else if(pixel_clear_event || debug_clear_pixel[1]!=debug_clear_pixel_seen) begin
            debug_job_status<=0;debug_job_pending<=0;
        end else begin
            debug_job_pending<=pixel_rst_n && jpeg_result_valid && jpeg_result_ready;
            if(debug_job_pending) debug_job_status<={quality_over_budget_count,
                debug_job_length,debug_job_budget,debug_job_config,
                16'd0,quality_degradation_reason,debug_job_ok,debug_job_quality[6:0],
                debug_job_sequence,debug_job_epoch,debug_job_session};
            if(pixel_rst_n && jpeg_result_valid && jpeg_result_ready) begin
                debug_job_session<=admitted_session;debug_job_epoch<=jpeg_actual_epoch;
                debug_job_sequence<=jpeg_result_id;debug_job_quality<=jpeg_actual_quality;debug_job_ok<=jpeg_result_ok;
                debug_job_config<={15'd0,admitted_adaptive,1'b0,admitted_minimum[6:0],1'b0,admitted_requested[6:0]};
                debug_job_budget<={7'd0,admitted_budget};debug_job_length<={7'd0,jpeg_result_length};
            end
        end
    end
    // The session controller retains a fatal event after application reset.
    // Synchronize it into each independent debug domain and trigger once.
    reg [1:0] debug_abort_pixel;
    reg debug_abort_pixel_seen;
    wire debug_abort_pixel_event = debug_abort_pixel[1] && !debug_abort_pixel_seen;
    always @(posedge pixel_clk or negedge debug_pixel_rst_n) begin
        if(!debug_pixel_rst_n) begin
            debug_clear_pixel<=0;debug_clear_pixel_seen<=0;debug_jpeg_id<=0;
            debug_jpeg_length<=0;debug_jpeg_error<=0;debug_jpeg_results<=0;
            debug_jpeg_success<=0;debug_pixel_fault<=0;debug_rgb_beats<=0;
            debug_jpeg_beats<=0;debug_pixel_cycles<=0;
            debug_abort_pixel<=0;debug_abort_pixel_seen<=0;
        end else begin
            debug_abort_pixel<={debug_abort_pixel[0],session_rearm_required};
            debug_abort_pixel_seen<=debug_abort_pixel[1];
            debug_clear_pixel<={debug_clear_pixel[0],debug_clear};
            debug_pixel_cycles<=debug_pixel_cycles+1'b1;
            if(pixel_clear_event || debug_clear_pixel[1]!=debug_clear_pixel_seen) begin
                debug_clear_pixel_seen<=debug_clear_pixel[1];debug_pixel_fault<=0;
                debug_jpeg_results<=0;debug_jpeg_success<=0;debug_rgb_beats<=0;debug_jpeg_beats<=0;
            end else if(pixel_rst_n) begin
                if(camera_rgb_valid && camera_rgb_ready) debug_rgb_beats<=debug_rgb_beats+1'b1;
                if(jpeg_valid && jpeg_ready) debug_jpeg_beats<=debug_jpeg_beats+1'b1;
                if(jpeg_result_valid && jpeg_result_ready) begin
                    debug_jpeg_id<=jpeg_result_id;debug_jpeg_length<={7'd0,jpeg_result_length};
                    debug_jpeg_error<={24'd0,jpeg_result_error};debug_jpeg_results<=debug_jpeg_results+1'b1;
                    if(jpeg_result_ok) debug_jpeg_success<=debug_jpeg_success+1'b1;
                end
                if(debug_pixel_fault==0 && (camera_error || camera_config_error ||
                    (jpeg_result_valid && jpeg_result_ready && !jpeg_result_ok)))
                    debug_pixel_fault<={29'd0,(jpeg_result_valid && jpeg_result_ready && !jpeg_result_ok),
                        camera_config_error,camera_error};
            end
        end
    end
    // Passive monitor is in the pixel domain and cannot drive camera/ISP flow.
    f_camera_geometry_monitor #(.EXPECT_RGB_LINES(FRAME_HEIGHT)) u_camera_geometry_monitor (
        .i_clk(pixel_clk), .i_debug_rst_n(debug_pixel_rst_n), .i_app_rst_n(pixel_rst_n),
        .i_clear(pixel_clear_event || debug_clear_pixel[1] != debug_clear_pixel_seen),
        .i_raw_valid(camera_raw_valid), .i_raw_ready(camera_raw_ready),
        .i_raw_sof(camera_raw_sof), .i_raw_eol(camera_raw_eol), .i_raw_abort(camera_raw_abort),
        .i_receive_fault(camera_receive_fault), .i_crop_error(camera_error),
        .i_rgb_valid(camera_rgb_valid), .i_rgb_ready(camera_rgb_ready),
        .i_rgb_sof(camera_sof), .i_rgb_eol(camera_eol),
        .i_frame_done(camera_done), .i_frame_error(camera_error),
        .o_status(camera_geometry_status));
    assign debug_pixel_status={debug_jpeg_beats,debug_rgb_beats,debug_pixel_fault,
        debug_jpeg_success,debug_jpeg_results,debug_jpeg_error,debug_jpeg_length,
        debug_jpeg_id,camera_digest,camera_format,camera_overflow,camera_crc,camera_ecc,
        camera_errors,camera_frames,11'd0,camera_delay_window,camera_delay_debug,
        camera_delay_status_valid,camera_phy_ready,frame_active_pixel,camera_delay_ready,
        camera_config_error,camera_config_done,pixel_rst_n};
    fpga_debug_probe #(.DEBUG_PROFILE(R8_STAGE1_ENABLE ? 2 : (S04_ENABLE ? 1 : 0)),.DEBUG_EXT_ENABLE(VIDEO_SERVICE_ENABLE),
        .TRACE_ENABLE(!R8_BASIC_PREPROCESS_ENABLE && (R8_STAGE1_ENABLE || !S04_ENABLE)),
        .GEOMETRY_ENABLE(0),.JOB_STATUS_ENABLE(VIDEO_SERVICE_ENABLE)) u_debug_pixel_probe (
        .i_clk(pixel_clk), .i_debug_rst_n(debug_pixel_rst_n), .i_request(debug_request[0]),
        .i_command(debug_command[39:0]), .o_ack(debug_ack[0]), .o_response(debug_response[39:0]),
        .i_status(debug_pixel_status), .i_geometry_status(camera_geometry_status),.i_job_status(debug_job_status),.i_clear(debug_clear),
        .o_clear_event(pixel_clear_event),
        .i_fault_causes({27'd0,admission_protocol_fault,processed_error,
            (jpeg_result_valid && jpeg_result_ready && !jpeg_result_ok),camera_config_error,camera_error}),
        .i_fault_context({job_session,job_epoch,job_sequence,{24'd0,admitted_quality},
            {24'd0,jpeg_result_error},{7'd0,jpeg_result_length},camera_overflow,camera_format}),
        .i_sample({debug_pixel_cycles,jpeg_data[31:0],jpeg_keep,4'd0,debug_abort_pixel_event,pixel_rst_n,
            camera_config_done,camera_delay_ready,camera_error,camera_sof,camera_eol,
            camera_rgb_valid,camera_rgb_ready,jpeg_valid,jpeg_ready,jpeg_last}),
        .i_frame_event(camera_done), .i_error_event(debug_abort_pixel_event || camera_error || camera_config_error ||
            (jpeg_result_valid && jpeg_result_ready && !jpeg_result_ok)));
    wire [15:0] debug_record_header_length = record_selected_version_dfi == `PCIE_RECORD_V4_VERSION ?
        `PCIE_RECORD_V4_HEADER_LENGTH : (record_selected_version_dfi == `PCIE_RECORD_V2_VERSION ?
        `PCIE_RECORD_V2_HEADER_LENGTH : `PCIE_HEADER_LENGTH);
    fpga_debug_stream_monitor #(.LOCAL_CLEAR_ENABLE(VIDEO_SERVICE_ENABLE),.FAULT_EVENT_PIPELINE_ENABLE(1),
        .SLOT_PROOF_ENABLE(VIDEO_SERVICE_ENABLE)) u_debug_stream_monitor (
        .i_clk(dfi_clk), .i_debug_rst_n(debug_dfi_rst_n), .i_app_rst_n(dfi_rst_n), .i_clear(debug_clear),
        .i_clear_local(dfi_clear_event),.o_fault_causes(dfi_fault_causes),.o_fault_context(dfi_fault_context),
        .i_write_start(ring_start_valid && ring_start_ready && !bridge_fault && nr_writer_start_permitted),
        .i_write_slot(debug_writer_allocation_slot),.i_write_generation(debug_writer_allocation_generation),
        .i_write_sequence(ddr_capture_id),.i_write_session(ddr_session),.i_write_epoch(ddr_epoch),.i_write_tag(ddr_write_tag),
        .i_commit_valid(writer_ack_valid),.i_commit_ok(writer_ack_ok),
        .i_commit_slot(writer_ack_slot),.i_commit_generation(writer_ack_generation),
        .i_commit_sequence(writer_ack_sequence),.i_commit_session(writer_ack_session),
        .i_commit_epoch(writer_ack_epoch),.i_commit_tag(writer_ack_tag),.i_commit_length(debug_writer_ack_length),
        .i_read_slot(store_slot),.i_read_generation(store_generation),.i_read_sequence(store_id),
        .i_read_session(store_session),.i_read_epoch(store_epoch),.i_record_header_length(debug_record_header_length),
        .i_write_valid(ddr_jpeg_valid), .i_write_ready(ddr_jpeg_ready),
        .i_write_data(ddr_jpeg_data), .i_write_keep(ddr_jpeg_keep), .i_write_last(ddr_jpeg_last),
        .i_write_result(ddr_result_valid && ddr_result_ready), .i_write_ok(ddr_result_ok),
        .i_write_length(ddr_result_length), .i_read_start(store_ready_claim),
        .i_read_valid(store_payload_valid), .i_read_ready(store_payload_ready),
        .i_read_data(store_payload_data), .i_read_keep(store_payload_keep), .i_read_last(store_payload_last),
        .i_record_start(store_ready_claim), .i_record_length(store_length),
        .i_record_valid(record_valid), .i_record_ready(record_ready), .i_record_data(record_data),
        .i_record_keep(record_keep), .i_record_last(record_last),
        .o_status(debug_dfi_status), .o_frame_event(debug_dfi_frame), .o_error_event(debug_dfi_error));
    reg [31:0] debug_dfi_cycles;
    reg [1:0] debug_abort_dfi;
    reg debug_abort_dfi_seen;
    wire debug_abort_dfi_event = debug_abort_dfi[1] && !debug_abort_dfi_seen;
    always @(posedge dfi_clk or negedge debug_dfi_rst_n) begin
        if(!debug_dfi_rst_n) begin
            debug_dfi_cycles<=0;debug_abort_dfi<=0;debug_abort_dfi_seen<=0;
        end else begin
            debug_dfi_cycles<=debug_dfi_cycles+1'b1;
            debug_abort_dfi<={debug_abort_dfi[0],session_rearm_required};
            debug_abort_dfi_seen<=debug_abort_dfi[1];
        end
    end
    fpga_debug_probe #(.DEBUG_PROFILE(R8_STAGE1_ENABLE ? 2 : (S04_ENABLE ? 1 : 0)),.DEBUG_EXT_ENABLE(VIDEO_SERVICE_ENABLE),
        .TRACE_ENABLE(VIDEO_SERVICE_ENABLE ? 0 : 1)) u_debug_dfi_probe (
        .i_clk(dfi_clk), .i_debug_rst_n(debug_dfi_rst_n), .i_request(debug_request[1]),
        .i_command(debug_command[79:40]), .o_ack(debug_ack[1]), .o_response(debug_response[79:40]),
        .i_status(debug_dfi_status), .i_clear(debug_clear),
        .i_geometry_status(512'd0),.i_job_status(256'd0),.o_clear_event(dfi_clear_event),
        .i_fault_causes(dfi_fault_causes | {30'd0,store_recovery,bridge_fault}),.i_fault_context(dfi_fault_context),
        .i_sample({debug_dfi_cycles,record_data[31:0],record_keep,3'd0,debug_abort_dfi_event,dfi_rst_n,
            store_ready_valid,store_ready_claim,store_payload_valid,store_payload_ready,
            store_payload_last,ddr_jpeg_valid,ddr_jpeg_ready,ddr_jpeg_last,record_valid,record_ready,record_last}),
        .i_frame_event(debug_dfi_frame), .i_error_event(debug_dfi_error || debug_abort_dfi_event));
    // Capture PCIe edges in their original clock domain, before session recovery.
    // Debug reset is independent of application/user reset so evidence survives.
    wire [511:0] debug_pcie_status;
    wire [95:0] debug_pcie_sample;
    wire debug_pcie_error;
    pcie_stream_monitor #(.LOCAL_CLEAR_ENABLE(VIDEO_SERVICE_ENABLE)) u_pcie_stream_monitor (
        .i_clk(user_clk), .i_debug_rst_n(debug_user_rst_n), .i_clear(debug_clear),
        .i_clear_local(pcie_clear_event),.o_fault_causes(pcie_fault_causes),.o_fault_context(pcie_fault_context),
        .i_flags(pcie_diag_flags), .i_keep(pcie_diag_keep), .i_c2h_status(c2h_status),
        .i_sequence(pcie_diag_sequence), .i_payload_length(pcie_diag_payload_length),
        .o_status(debug_pcie_status), .o_sample(debug_pcie_sample),
        .o_error_event(debug_pcie_error)
    );
    fpga_debug_probe #(.DEBUG_PROFILE(R8_STAGE1_ENABLE ? 2 : (S04_ENABLE ? 1 : 0)),.DEBUG_EXT_ENABLE(VIDEO_SERVICE_ENABLE),
        .TRACE_ENABLE(VIDEO_SERVICE_ENABLE ? 0 : 1)) u_debug_pcie_probe (
        .i_clk(user_clk), .i_debug_rst_n(debug_user_rst_n), .i_request(debug_request[2]),
        .i_command(debug_command[119:80]), .o_ack(debug_ack[2]),
        .o_response(debug_response[119:80]), .i_status(debug_pcie_status),
        .i_geometry_status(512'd0),.i_job_status(256'd0),.o_clear_event(pcie_clear_event),
        .i_fault_causes(pcie_fault_causes | {31'd0,retire_user_fault}),.i_fault_context(pcie_fault_context),
        .i_sample(debug_pcie_sample), .i_frame_event(frame_accept),
        .i_error_event(debug_pcie_error), .i_clear(debug_clear)
    );
    end else begin : g_production
        stage3_production_boot u_boot (
            .i_clk(sys_clk), .o_debug_rst_n(debug_rst_n),
            .o_app_rst_n(debug_app_rst_n), .o_local(debug_local), .o_run(debug_run));
        if (READONLY_UART_ENABLE != 0) begin:g_status_uart
            // OB/RX retain their wire layout. DJ replaces the historical CFG trace.
            // The SDR-only RT history ring is retired from this production top.
            // Independent observational registers add one input load per tap.
            // Every destination below belongs to telemetry; no output returns
            // to an application enable, reset, READY, configuration or owner.
            (* ASYNC_REG="TRUE" *) reg [15:0] sys_flags_meta,sys_flags;
            (* ASYNC_REG="TRUE" *) reg [11:0] pixel_flags_meta,pixel_flags;
            (* ASYNC_REG="TRUE" *) reg [11:0] dfi_flags_meta,dfi_flags;
            (* ASYNC_REG="TRUE" *) reg [11:0] user_flags_meta,user_flags;
            reg [3:0] pixel_faults,dfi_faults,user_faults;
            reg [1:0] pixel_progress,dfi_progress,user_progress;
            reg [2:0] user_first_fault_phase;
            wire [3:0] user_causes={product_fault_user[1]||product_axil_fault||
                (transport_recovery&&transport_observe[6:4]==3'd7&&
                !transport_observe[2]&&!transport_observe[3]&&!memory_fault_user),
                memory_fault_user,transport_observe[3],transport_observe[2]};
            wire [11:0] user_observe_flags={user_flags[11:9],
                (|user_faults ? user_first_fault_phase : transport_observe[6:4]),user_flags[5:0]};
            always @(posedge sys_clk or negedge debug_rst_n) begin
                if(!debug_rst_n) begin sys_flags_meta<=0;sys_flags<=0;end
                else begin
                    sys_flags_meta<={effective_app_enable,memory_owner_ready,session_rearm_required,
                        session_armed,session_ready,endpoint_rst_n,user_rst_n,user_link_up,
                        ddr_phy_rst_n,ddr_app_ready,ddr_cal_done,camera_pll_lock,pixel_pll_lock,
                        pcie_mperst,debug_app_rst_n,debug_rst_n};
                    sys_flags<=sys_flags_meta;
                end
            end
            always @(posedge pixel_clk or negedge debug_pixel_rst_n) begin
                if(!debug_pixel_rst_n) begin
                    pixel_flags_meta<=0;pixel_flags<=0;pixel_faults<=0;pixel_progress<=0;
                end else begin
                    // Dual mode reuses the held PIX status bundle for CAM1.
                    // Mono status and the reset flag retain their R6 layout.
                    pixel_flags_meta<=stereo_mode_pixel ?
                        {camera1_config_error,native_pipeline_idle,raw_processing_idle_pixel,
                        jpeg_idle,frame_active_pixel,camera1_phy_ready,camera1_config_done,camera_config_error,
                        camera_phy_ready,camera_config_done,cfg_pixel_initialized,pixel_rst_n} :
                        {camera_config_error,native_pipeline_idle,raw_processing_idle_pixel,
                        jpeg_idle,frame_active_pixel,camera_hdr_stable,camera_hdr_mode,camera_delay_ready,
                        camera_phy_ready,camera_config_done,cfg_pixel_initialized,pixel_rst_n};
                    pixel_flags<=pixel_flags_meta;
                    pixel_faults<={admission_protocol_fault||live_f21_fault||live_lease_fault||processed_error||record_source_fault,
                        jpeg_result_valid&&jpeg_result_ready&&!jpeg_result_ok,
                        camera_error||camera_receive_fault||camera_source_identity_fault||
                        (stereo_mode_pixel&&(camera1_receive_fault||camera1_identity_fault||camera1_quarantine||
                        stereo_source0_fault||stereo_source1_fault)),
                        camera_config_error||(stereo_mode_pixel&&camera1_config_error)};
                    pixel_progress<={jpeg_result_valid&&jpeg_result_ready,admission_take};
                end
            end
            always @(posedge dfi_clk or negedge debug_dfi_rst_n) begin
                if(!debug_dfi_rst_n) begin
                    dfi_flags_meta<=0;dfi_flags<=0;dfi_faults<=0;dfi_progress<=0;
                end else begin
                    dfi_flags_meta<={hdr_scheduler_busy,hdr_owner_empty,hdr_writer_quiescent,
                        credit_reserved_dfi,store_ready_valid,writer_ack_valid,store_recovery,bridge_fault,
                        ddr_phy_rst_n,ddr_app_ready,ddr_cal_done,dfi_rst_n};
                    dfi_flags<=dfi_flags_meta;
                    dfi_faults<={writer_ack_valid&&writer_ack_ready&&!writer_ack_ok,
                        ddr_arbiter_fault||hdr_ticket_recovery||hdr_ticket_exhausted,store_recovery,bridge_fault};
                    dfi_progress<={store_ready_claim,writer_ack_valid&&writer_ack_ready};
                end
            end
            always @(posedge user_clk or negedge debug_user_rst_n) begin
                if(!debug_user_rst_n) begin
                    user_flags_meta<=0;user_flags<=0;user_faults<=0;user_progress<=0;user_first_fault_phase<=0;
                end else begin
                    user_flags_meta<={reset_pending_user,memory_owner_ready,transport_recovery,
                        transport_observe[6:4],product_buffer_armed,transport_observe[1],transport_observe[0],
                        cfg_user_initialized,user_link_up,user_rst_n};
                    user_flags<=user_flags_meta;
                    if(user_faults==0&&|user_causes)begin
                        user_faults<=user_causes;user_first_fault_phase<=transport_observe[6:4];
                    end
                    user_progress<={jpeg_user_retire_valid&&jpeg_user_retire_ready,
                        transport_observe[7]};
                end
            end
            // DJ/v3 replaces redundant physical-FS counters with the CFG
            // publication epoch and quiet/transaction gates, using the same
            // two held snapshot pages. No diagnostic feeds business logic.
            // DJ/v2 replaced the frozen first-job watch with current fault-local
            // samples. The leaf has only UART page outputs and cannot stall work.
            wire field_job_fire=(diag_job_valid&&diag_job_ready)||(raw_record_valid&&raw_record_ready);
            wire [383:0] field_job_frame=raw_mode_dfi?stereo_job_frame:hdr_job_frame0;
            wire [223:0] job_page_dfi,job_page_pix;
            camera_field_diagnostics u_field_diagnostics(
                .dfi_clk(dfi_clk),.dfi_rst_n(debug_dfi_rst_n),.dfi_run(pairbank_enable_sync),
                .dfi_session(dfi_active_config[63:32]),.dfi_epoch(dfi_active_config[159:128]),
                .job_fire(field_job_fire),.job_camera(field_job_frame[4]),.job_sequence(field_job_frame[108:77]),
                .begin_reject(stored_sdr_dfi?field_sdr_reject:field_hdr_reject),
                .pair_expire(stored_sdr_dfi?2'd0:field_hdr_expire),
                .bad_finish(stored_sdr_dfi?field_sdr_bad:{|field_hdr_bad[3:2],|field_hdr_bad[1:0]}),
                .bank_states(stored_sdr_dfi?8'd0:field_hdr_banks),
                .dfi_flags({hdr_owner_empty,raw_read_quiescent,bridge_fault,raw_processing_fault,
                    hdr_ticket_recovery,pairbank_enable_sync,dfi_active_hdr,raw_mode_dfi}),
                .pixel_clk(pixel_clk),.pixel_rst_n(debug_pixel_rst_n),.pixel_run(enable_pixel[1]),
                .pixel_epoch(capture0_active_config[159:128]),
                .cfg_applied_epoch(cfg_epoch),
                .cfg_flags({native_pipeline_idle,live_f21_maintenance_quiet,
                    physical_source_idle,cfg_pipeline_idle,cfg_apply_diagnostics}),
                .capture_admit({field_cam1_admit,raw_capture1_frame_accept,raw_capture0_frame_accept}),
                .pixel_flags({camera1_receive_fault,camera_receive_fault,camera1_identity_fault,camera_source_identity_fault,
                    camera1_config_error,camera_config_error,camera1_config_done,camera_config_done,
                    cam1_hdr_stable,camera_hdr_stable,cam1_hdr_mode_running,camera_mode_running,
                    cfg_pause,raw_mode_pixel,stereo_mode_pixel,physical_hdr_requested}),
                .dfi_page(job_page_dfi),.pixel_page(job_page_pix));

            uart_status_observer #(.RX_TRACE_ENABLE(0),.RX_DIAG_ENABLE(0),.UART_DIV(217),.CFG_DIAG_ENABLE(1),.JOB_PAGE_ENABLE(1),.CFG_FRAME_VERSION(3),.JOB_SYS_CONFIG_ENABLE(1),
                .REPORT_INTERVAL_CYCLES(READONLY_UART_REPORT_CYCLES)) u_observer (
                .i_sys_clk(sys_clk),.i_sys_rst_n(debug_rst_n),
                .i_pixel_clk(pixel_clk),.i_dfi_clk(dfi_clk),.i_user_clk(user_clk),
                .i_domain_observer_rst_n({debug_user_rst_n,debug_dfi_rst_n,debug_pixel_rst_n}),
                .i_domain_reset_n({user_rst_n,dfi_rst_n,pixel_rst_n}),
                .i_sys_status(sys_flags),.i_domain_flags({user_observe_flags,dfi_flags,pixel_flags}),
                .i_domain_faults({user_faults,dfi_faults,pixel_faults}),
                .i_domain_progress({user_progress,dfi_progress,pixel_progress}),
                .i_cfg_domains({job_page_pix,job_page_dfi}),.i_cfg_domain_reset_n({pixel_rst_n,dfi_rst_n}),
                .i_job_sys_config({rx_diag_cfg1[31:0],rx_diag_cfg[31:0]}),
                .i_rx_word_clk(rx_diag_word_clk),.i_rx_domains(rx_diag_domains),
                .o_trace_request(),.o_trace_index(),
                .i_trace_ack(1'b0),.i_trace_data(320'd0),
                .i_rx_reset_n({pixel_rst_n&&camera_mode_running,debug_rst_n,pixel_rst_n}),.o_uart_tx(uart_tx));
        end else begin:g_no_status_uart
            assign uart_tx=1'b1;
        end
        assign debug_clear = 1'b0;
        assign debug_request = 3'd0;
        assign debug_command = 120'd0;
        assign debug_rx_errors = 32'd0;
        assign debug_timeouts = 32'd0;
        assign debug_color_config = COLOR_CONFIG_DEFAULT;
        assign debug_color_wb = COLOR_WB_DEFAULT;
        assign local_stop_request = 1'b0;
    end endgenerate
    wire unused_debug = ddr_cal_done ^ ddr_app_ready ^
        camera_config_done ^ camera_config_error ^ camera_delay_ready ^
        store_drop ^ store_read_done ^ ^store_error ^ ^ddr_result_error ^
        ^camera_ecc ^ ^camera_crc ^ ^camera_overflow ^ ^camera_format ^
        ^c2h_status ^ ^h2c_status ^ ^h2c_user;
endmodule
`default_nettype wire
