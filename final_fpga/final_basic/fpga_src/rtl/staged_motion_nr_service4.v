`timescale 1ns / 1ps

// Accepted original native RGB feeds one writer and a passive F20 observation.
module staged_motion_nr_service4 #(
    parameter integer SOURCE_WIDTH=1920,SOURCE_HEIGHT=1080,
    parameter integer SHARED_PHASE_FIFO_ENABLE=0,NEUTRAL_STATS_ENABLE=0,
    parameter integer OBSERVER_EXPORT_ENABLE=0
) (
    // Optional second consumer of the one original F20 observation, in clk.
    input wire i_observer_export_enable,
    output wire m_observer_valid,input wire m_observer_ready,
    output wire [23:0] m_observer_rgb,output wire [7:0] m_observer_luma,
    output wire m_observer_sof,m_observer_eol,m_observer_last,
    output wire [575:0] m_observer_identity,
    output wire [159:0] m_observer_context,
    output wire m_observer_status_valid,input wire m_observer_status_ready,
    output wire m_observer_status_ok,output wire [7:0] m_observer_status_error,
    output wire [15:0] m_observer_status_pixels,m_observer_status_delivered,
    output wire m_original_stats_valid,input wire m_original_stats_ready,
    output wire [63:0] m_original_stats_tag,
    output wire [159:0] m_original_stats_context,
    output wire [183:0] m_original_statistics,
    input wire  clk,
    input wire  rst_n,
    input wire  i_ddr_reset_done,
    input wire  i_matrix_fault,
    input wire  i_matrix_hard_fault,
    output wire  o_reset_done,
    input wire  i_start_valid,
    output wire  o_start_ready,
    input wire [383:0] i_frame,
    input wire [63:0] i_tag,
    input wire [63:0] i_key,
    input wire [63:0] i_aux,
    input wire [95:0] s_rgb,
    input wire [3:0] s_keep,
    input wire  s_sof,
    input wire  s_eol,
    input wire  s_last,
    input wire  s_valid,
    output wire  s_ready,
    input wire [31:0] s_index,
    input wire [63:0] s_tag,
    input wire  i_source_status_valid,
    output wire  o_source_status_ready,
    input wire [383:0] i_source_status_frame,
    input wire [63:0] i_source_status_tag,
    input wire [63:0] i_source_status_key,
    input wire [63:0] i_source_status_aux,
    input wire  i_source_status_ok,
    input wire [7:0] i_source_status_error,
    input wire [31:0] i_source_status_pixels,
    input wire  i_source_read_quiescent,
    output wire  m_capture_ack_valid,
    input wire  m_capture_ack_ready,
    output wire [383:0] m_capture_ack_frame,
    output wire [63:0] m_capture_ack_tag,
    output wire [63:0] m_capture_ack_key,
    output wire [63:0] m_capture_ack_aux,
    output wire  m_capture_ack_ok,
    output wire [7:0] m_capture_ack_error,
    output wire [31:0] m_capture_ack_pixels,
    input wire  i_enable,
    input wire  i_history_reset,
    output wire [95:0] m_rgb,
    output wire [3:0] m_keep,
    output wire  m_sof,
    output wire  m_eol,
    output wire  m_last,
    output wire  m_valid,
    input wire  m_ready,
    output wire [31:0] m_index,
    output wire [63:0] m_tag,
    output wire  m_filtered_fence_valid,
    input wire  m_filtered_fence_ready,
    output wire [383:0] m_filtered_fence_frame,
    output wire [63:0] m_filtered_fence_tag,
    output wire [63:0] m_filtered_fence_key,
    output wire [63:0] m_filtered_fence_aux,
    output wire  m_filtered_fence_ok,
    output wire [7:0] m_filtered_fence_error,
    output wire [31:0] m_filtered_fence_pixels,
    input wire  i_filtered_ack_valid,
    output wire  o_filtered_ack_ready,
    input wire [383:0] i_filtered_ack_frame,
    input wire [63:0] i_filtered_ack_tag,
    input wire [63:0] i_filtered_ack_key,
    input wire [63:0] i_filtered_ack_aux,
    input wire  i_filtered_ack_ok,
    input wire [7:0] i_filtered_ack_error,
    input wire [31:0] i_filtered_ack_pixels,
    input wire  i_filtered_read_quiescent,
    input wire  i_cancel,
    output wire  m_result_valid,
    input wire  m_result_ready,
    output wire [383:0] m_result_frame,
    output wire [63:0] m_result_tag,
    output wire [63:0] m_result_key,
    output wire [63:0] m_result_aux,
    output wire  m_result_ok,
    output wire  m_result_current_ok,
    output wire  m_result_capture_ok,
    output wire  m_result_history_commit,
    output wire [7:0] m_result_error,
    output wire [31:0] m_result_capture_pixels,
    output wire [31:0] m_result_input_pixels,
    output wire [31:0] m_result_output_pixels,
    output wire [31:0] m_result_raw_pixels,
    output wire  o_offer_valid,
    output wire  o_backend_offer_valid,
    output wire [383:0] o_offer_frame,
    output wire [63:0] o_offer_tag,
    output wire [63:0] o_offer_key,
    output wire [63:0] o_offer_aux,
    output wire  o_history_selected,
    output wire  o_busy,
    output wire  o_abort_request,
    output wire  o_read_quiescent,
    output wire  o_quarantined,
    output wire [1:0] o_nr_history_valid,
    output wire [3:0] o_rgb_active_banks,
    output wire [3:0] o_rgb_pinned_banks,
    output wire [31:0] o_stale_control_count,
    output wire [3:0] rgb_axi_awid,
    output wire [3:0] rgb_axi_arid,
    output wire [27:0] rgb_axi_awaddr,
    output wire [27:0] rgb_axi_araddr,
    output wire [7:0] rgb_axi_awlen,
    output wire [7:0] rgb_axi_arlen,
    output wire [2:0] rgb_axi_awsize,
    output wire [2:0] rgb_axi_arsize,
    output wire [1:0] rgb_axi_awburst,
    output wire [1:0] rgb_axi_arburst,
    output wire  rgb_axi_awvalid,
    output wire  rgb_axi_arvalid,
    input wire  rgb_axi_awready,
    input wire  rgb_axi_arready,
    output wire [127:0] rgb_axi_wdata,
    output wire [15:0] rgb_axi_wstrb,
    output wire  rgb_axi_wlast,
    output wire  rgb_axi_wvalid,
    input wire  rgb_axi_wready,
    input wire [3:0] rgb_axi_bid,
    input wire [3:0] rgb_axi_rid,
    input wire [1:0] rgb_axi_bresp,
    input wire [1:0] rgb_axi_rresp,
    input wire  rgb_axi_bvalid,
    input wire  rgb_axi_rlast,
    input wire  rgb_axi_rvalid,
    output wire  rgb_axi_bready,
    output wire  rgb_axi_rready,
    input wire [127:0] rgb_axi_rdata,
    input wire [31:0] s_luma,
    input wire [7:0] i_motion_guard,
    input wire [7:0] i_static_threshold,
    input wire [7:0] i_weak_threshold,
    input wire [7:0] i_motion_threshold,
    output wire  o_observation_ok,
    output wire  o_motion_success,
    output wire  o_motion_qualified,
    output wire  o_motion_skipped,
    output wire  o_map_committed,
    output wire  o_motion_backend_fault,
    output wire [7:0] o_observation_error,
    output wire [7:0] o_motion_error,
    output wire [7:0] o_projection_error,
    output wire [15:0] o_observation_pixels,
    output wire [15:0] o_observation_delivered,
    output wire [31:0] o_observation_dropped,
    output wire [3:0] o_y_pinned_banks,
    output wire [3:0] map_axi_awid,
    output wire [3:0] map_axi_arid,
    output wire [27:0] map_axi_awaddr,
    output wire [27:0] map_axi_araddr,
    output wire [7:0] map_axi_awlen,
    output wire [7:0] map_axi_arlen,
    output wire [2:0] map_axi_awsize,
    output wire [2:0] map_axi_arsize,
    output wire [1:0] map_axi_awburst,
    output wire [1:0] map_axi_arburst,
    output wire  map_axi_awvalid,
    output wire  map_axi_arvalid,
    input wire  map_axi_awready,
    input wire  map_axi_arready,
    output wire [127:0] map_axi_wdata,
    output wire [15:0] map_axi_wstrb,
    output wire  map_axi_wlast,
    output wire  map_axi_wvalid,
    input wire  map_axi_wready,
    input wire [3:0] map_axi_bid,
    input wire [3:0] map_axi_rid,
    input wire [1:0] map_axi_bresp,
    input wire [1:0] map_axi_rresp,
    input wire  map_axi_bvalid,
    input wire  map_axi_rlast,
    input wire  map_axi_rvalid,
    output wire  map_axi_bready,
    output wire  map_axi_rready,
    input wire [127:0] map_axi_rdata
);
    localparam [8:0] OBS_WIDTH=SOURCE_WIDTH/6;
    localparam [7:0] OBS_HEIGHT=SOURCE_HEIGHT/6;
    wire  nr_o_reset_done;
    wire  nr_o_capture_ready;
    wire  nr_s_ready;
    wire  nr_o_source_status_ready;
    wire  nr_m_capture_ack_valid;
    wire [383:0] nr_m_capture_ack_frame;
    wire [63:0] nr_m_capture_ack_tag;
    wire [63:0] nr_m_capture_ack_key;
    wire [63:0] nr_m_capture_ack_aux;
    wire  nr_m_capture_ack_ok;
    wire [7:0] nr_m_capture_ack_error;
    wire [31:0] nr_m_capture_ack_pixels;
    wire  nr_o_process_ready;
    wire  nr_motion_ready;
    wire [95:0] nr_m_rgb;
    wire [3:0] nr_m_keep;
    wire  nr_m_sof;
    wire  nr_m_eol;
    wire  nr_m_last;
    wire  nr_m_valid;
    wire [31:0] nr_m_index;
    wire [63:0] nr_m_tag;
    wire  nr_m_filtered_fence_valid;
    wire [383:0] nr_m_filtered_fence_frame;
    wire [63:0] nr_m_filtered_fence_tag;
    wire [63:0] nr_m_filtered_fence_key;
    wire [63:0] nr_m_filtered_fence_aux;
    wire  nr_m_filtered_fence_ok;
    wire [7:0] nr_m_filtered_fence_error;
    wire [31:0] nr_m_filtered_fence_pixels;
    wire  nr_o_filtered_ack_ready;
    wire  nr_m_result_valid;
    wire [383:0] nr_m_result_frame;
    wire [63:0] nr_m_result_tag;
    wire [63:0] nr_m_result_key;
    wire [63:0] nr_m_result_aux;
    wire  nr_m_result_ok;
    wire  nr_m_result_current_ok;
    wire  nr_m_result_capture_ok;
    wire  nr_m_result_history_commit;
    wire [7:0] nr_m_result_error;
    wire [31:0] nr_m_result_capture_pixels;
    wire [31:0] nr_m_result_input_pixels;
    wire [31:0] nr_m_result_output_pixels;
    wire [31:0] nr_m_result_raw_pixels;
    wire  nr_o_offer_valid;
    wire  nr_o_backend_offer_valid;
    wire [383:0] nr_o_offer_frame;
    wire [63:0] nr_o_offer_tag;
    wire [63:0] nr_o_offer_key;
    wire [63:0] nr_o_offer_aux;
    wire  nr_o_history_selected;
    wire  nr_o_busy;
    wire  nr_o_abort_request;
    wire  nr_o_read_quiescent;
    wire  nr_o_quarantined;
    wire [1:0] nr_o_nr_history_valid;
    wire [3:0] nr_o_active_banks;
    wire [3:0] nr_o_pinned_banks;
    wire [31:0] nr_o_stale_control_count;
    wire [31:0] nr_o_aw_count;
    wire [31:0] nr_o_w_count;
    wire [31:0] nr_o_b_count;
    wire [31:0] nr_o_ar_count;
    wire [31:0] nr_o_r_count;
    wire [31:0] nr_o_commit_count;
    wire [3:0] nr_m_axi_awid;
    wire [3:0] nr_m_axi_arid;
    wire [27:0] nr_m_axi_awaddr;
    wire [27:0] nr_m_axi_araddr;
    wire [7:0] nr_m_axi_awlen;
    wire [7:0] nr_m_axi_arlen;
    wire [2:0] nr_m_axi_awsize;
    wire [2:0] nr_m_axi_arsize;
    wire [1:0] nr_m_axi_awburst;
    wire [1:0] nr_m_axi_arburst;
    wire  nr_m_axi_awvalid;
    wire  nr_m_axi_arvalid;
    wire [127:0] nr_m_axi_wdata;
    wire [15:0] nr_m_axi_wstrb;
    wire  nr_m_axi_wlast;
    wire  nr_m_axi_wvalid;
    wire  nr_m_axi_bready;
    wire  nr_m_axi_rready;
    wire  mo_o_reset_done;
    wire  mo_o_start_ready;
    wire  mo_o_offer_valid;
    wire  mo_o_backend_offer_valid;
    wire [383:0] mo_o_offer_frame;
    wire [63:0] mo_o_offer_key;
    wire [159:0] mo_o_offer_context;
    wire [31:0] mo_o_offer_tag;
    wire  mo_o_history_used;
    wire [7:0] mo_o_history_reason;
    wire  mo_s_ready;
    wire  mo_o_source_ready;
    wire  mo_o_abort_request;
    wire  mo_o_busy;
    wire  mo_o_read_quiescent;
    wire  mo_o_job_done;
    wire  mo_m_result_valid;
    wire [1:0] mo_m_result_kind;
    wire [383:0] mo_m_result_frame;
    wire [383:0] mo_m_result_history_frame;
    wire [63:0] mo_m_result_key;
    wire [159:0] mo_m_result_context;
    wire [31:0] mo_m_result_tag;
    wire [31:0] mo_m_result_history_tag;
    wire  mo_m_result_success;
    wire  mo_m_result_source_ok;
    wire  mo_m_result_history_publish;
    wire  mo_m_result_map_commit;
    wire [7:0] mo_m_result_error;
    wire [7:0] mo_m_result_backend_error;
    wire  mo_m_result_temporal_trust;
    wire  mo_m_result_global_change;
    wire  mo_m_result_brightness_change;
    wire [15:0] mo_m_result_pixels;
    wire [15:0] mo_m_result_foreground;
    wire [15:0] mo_m_result_confidence0;
    wire [15:0] mo_m_result_confidence1;
    wire [15:0] mo_m_result_confidence2;
    wire [15:0] mo_m_result_confidence3;
    wire [23:0] mo_m_result_sum_abs;
    wire [23:0] mo_m_result_sum_y;
    wire signed [24:0] mo_m_result_sum_diff;
    wire  mo_m_motion_valid;
    wire [7:0] mo_m_motion_confidence;
    wire [3:0] mo_m_motion_lane_valid;
    wire [3:0] mo_m_motion_keep;
    wire  mo_m_motion_sof;
    wire  mo_m_motion_eol;
    wire  mo_m_motion_last;
    wire [31:0] mo_m_motion_index;
    wire [383:0] mo_m_motion_frame;
    wire [383:0] mo_m_motion_history_frame;
    wire [63:0] mo_m_motion_key;
    wire [63:0] mo_m_motion_tag;
    wire [63:0] mo_m_motion_history_tag;
    wire [159:0] mo_m_motion_context;
    wire  mo_m_projection_valid;
    wire [1:0] mo_m_projection_kind;
    wire [7:0] mo_m_projection_error;
    wire [7:0] mo_m_projection_reason;
    wire  mo_m_projection_qualified;
    wire [31:0] mo_m_projection_map_groups;
    wire [31:0] mo_m_projection_output_groups;
    wire [31:0] mo_m_projection_output_pixels;
    wire  mo_o_map_committed;
    wire  mo_o_backend_fault;
    wire [7:0] mo_o_backend_error;
    wire [3:0] mo_o_active_banks;
    wire [3:0] mo_o_pinned_banks;
    wire [31:0] mo_o_stale_sources;
    wire [31:0] mo_o_late_cancels;
    wire [31:0] mo_o_completed_jobs;
    wire [31:0] mo_o_aw_count;
    wire [31:0] mo_o_w_count;
    wire [31:0] mo_o_b_count;
    wire [31:0] mo_o_ar_count;
    wire [31:0] mo_o_r_count;
    wire [3:0] mo_m_axi_awid;
    wire [27:0] mo_m_axi_awaddr;
    wire [7:0] mo_m_axi_awlen;
    wire [2:0] mo_m_axi_awsize;
    wire [1:0] mo_m_axi_awburst;
    wire  mo_m_axi_awvalid;
    wire [127:0] mo_m_axi_wdata;
    wire [15:0] mo_m_axi_wstrb;
    wire  mo_m_axi_wlast;
    wire  mo_m_axi_wvalid;
    wire  mo_m_axi_bready;
    wire [3:0] mo_m_axi_arid;
    wire [27:0] mo_m_axi_araddr;
    wire [7:0] mo_m_axi_arlen;
    wire [2:0] mo_m_axi_arsize;
    wire [1:0] mo_m_axi_arburst;
    wire  mo_m_axi_arvalid;
    wire  mo_m_axi_rready;
    wire  ob_o_pixel_valid;
    wire [23:0] ob_o_pixel_rgb;
    wire [7:0] ob_o_pixel_luma;
    wire  ob_o_pixel_sof;
    wire  ob_o_pixel_eol;
    wire  ob_o_pixel_last;
    wire [159:0] ob_o_context;
    wire [31:0] ob_o_exposure;
    wire [15:0] ob_o_gain;
    wire [12:0] ob_o_source_width;
    wire [12:0] ob_o_source_height;
    wire [12:0] ob_o_observation_width;
    wire [12:0] ob_o_observation_height;
    wire  ob_o_status_valid;
    wire  ob_o_status_ok;
    wire [7:0] ob_o_status_error;
    wire [15:0] ob_o_status_pixels;
    wire [15:0] ob_o_status_delivered;
    wire [31:0] ob_o_status_sum_y;
    wire [7:0] ob_o_status_min_y;
    wire [7:0] ob_o_status_max_y;
    wire [15:0] ob_o_status_dark;
    wire [15:0] ob_o_status_bright;
    wire  ob_o_busy;
    wire  ob_o_reset_done;
    wire [31:0] ob_o_dropped_frames;

    assign s_ready=nr_s_ready;
    assign m_capture_ack_valid=nr_m_capture_ack_valid;
    assign m_capture_ack_frame=nr_m_capture_ack_frame;
    assign m_capture_ack_tag=nr_m_capture_ack_tag;
    assign m_capture_ack_key=nr_m_capture_ack_key;
    assign m_capture_ack_aux=nr_m_capture_ack_aux;
    assign m_capture_ack_ok=nr_m_capture_ack_ok;
    assign m_capture_ack_error=nr_m_capture_ack_error;
    assign m_capture_ack_pixels=nr_m_capture_ack_pixels;
    assign m_rgb=nr_m_rgb;
    assign m_keep=nr_m_keep;
    assign m_sof=nr_m_sof;
    assign m_eol=nr_m_eol;
    assign m_last=nr_m_last;
    assign m_valid=nr_m_valid;
    assign m_index=nr_m_index;
    assign m_tag=nr_m_tag;
    assign m_filtered_fence_valid=nr_m_filtered_fence_valid;
    assign m_filtered_fence_frame=nr_m_filtered_fence_frame;
    assign m_filtered_fence_tag=nr_m_filtered_fence_tag;
    assign m_filtered_fence_key=nr_m_filtered_fence_key;
    assign m_filtered_fence_aux=nr_m_filtered_fence_aux;
    assign m_filtered_fence_ok=nr_m_filtered_fence_ok;
    assign m_filtered_fence_error=nr_m_filtered_fence_error;
    assign m_filtered_fence_pixels=nr_m_filtered_fence_pixels;
    assign o_filtered_ack_ready=nr_o_filtered_ack_ready;
    assign m_result_frame=nr_m_result_frame;
    assign m_result_tag=nr_m_result_tag;
    assign m_result_key=nr_m_result_key;
    assign m_result_aux=nr_m_result_aux;
    assign m_result_ok=nr_m_result_ok;
    assign m_result_current_ok=nr_m_result_current_ok;
    assign m_result_capture_ok=nr_m_result_capture_ok;
    assign m_result_history_commit=nr_m_result_history_commit;
    assign m_result_error=nr_m_result_error;
    assign m_result_capture_pixels=nr_m_result_capture_pixels;
    assign m_result_input_pixels=nr_m_result_input_pixels;
    assign m_result_output_pixels=nr_m_result_output_pixels;
    assign m_result_raw_pixels=nr_m_result_raw_pixels;
    assign o_offer_valid=nr_o_offer_valid;
    assign o_backend_offer_valid=nr_o_backend_offer_valid;
    assign o_offer_frame=nr_o_offer_frame;
    assign o_offer_tag=nr_o_offer_tag;
    assign o_offer_key=nr_o_offer_key;
    assign o_offer_aux=nr_o_offer_aux;
    assign o_history_selected=nr_o_history_selected;
    assign o_nr_history_valid=nr_o_nr_history_valid;
    assign o_rgb_active_banks=nr_o_active_banks;
    assign o_rgb_pinned_banks=nr_o_pinned_banks;
    assign rgb_axi_awid=nr_m_axi_awid;
    assign rgb_axi_arid=nr_m_axi_arid;
    assign rgb_axi_awaddr=nr_m_axi_awaddr;
    assign rgb_axi_araddr=nr_m_axi_araddr;
    assign rgb_axi_awlen=nr_m_axi_awlen;
    assign rgb_axi_arlen=nr_m_axi_arlen;
    assign rgb_axi_awsize=nr_m_axi_awsize;
    assign rgb_axi_arsize=nr_m_axi_arsize;
    assign rgb_axi_awburst=nr_m_axi_awburst;
    assign rgb_axi_arburst=nr_m_axi_arburst;
    assign rgb_axi_awvalid=nr_m_axi_awvalid;
    assign rgb_axi_arvalid=nr_m_axi_arvalid;
    assign rgb_axi_wdata=nr_m_axi_wdata;
    assign rgb_axi_wstrb=nr_m_axi_wstrb;
    assign rgb_axi_wlast=nr_m_axi_wlast;
    assign rgb_axi_wvalid=nr_m_axi_wvalid;
    assign rgb_axi_bready=nr_m_axi_bready;
    assign rgb_axi_rready=nr_m_axi_rready;
    assign map_axi_awid=mo_m_axi_awid;
    assign map_axi_awaddr=mo_m_axi_awaddr;
    assign map_axi_awlen=mo_m_axi_awlen;
    assign map_axi_awsize=mo_m_axi_awsize;
    assign map_axi_awburst=mo_m_axi_awburst;
    assign map_axi_awvalid=mo_m_axi_awvalid;
    assign map_axi_wdata=mo_m_axi_wdata;
    assign map_axi_wstrb=mo_m_axi_wstrb;
    assign map_axi_wlast=mo_m_axi_wlast;
    assign map_axi_wvalid=mo_m_axi_wvalid;
    assign map_axi_bready=mo_m_axi_bready;
    assign map_axi_arid=mo_m_axi_arid;
    assign map_axi_araddr=mo_m_axi_araddr;
    assign map_axi_arlen=mo_m_axi_arlen;
    assign map_axi_arsize=mo_m_axi_arsize;
    assign map_axi_arburst=mo_m_axi_arburst;
    assign map_axi_arvalid=mo_m_axi_arvalid;
    assign map_axi_rready=mo_m_axi_rready;
    localparam [2:0] IDLE=0,CAPTURE_BUILD=1,WAIT_PROJECTION=2,NR_PROCESS=3,RESULT=4,FAULT=5;
    localparam [15:0] OBS_PIXELS=(SOURCE_WIDTH/6)*(SOURCE_HEIGHT/6);
    reg [2:0] state;
    reg [383:0] frame_locked,old_frame_locked;
    reg [63:0] tag_locked,key_locked,aux_locked,old_tag_locked;
    reg [159:0] context_locked;
    reg [31:0] write_tag_locked,main_groups,main_pixels,received_pixels,packed_pixels;
    reg enable_locked,history_reset_locked,canceled,source_seen,source_ok,source_quiet;
    reg [7:0] guard_locked;
    reg observer_started,ob_status_seen,ob_status_ok,tap_bad,identity_lost;
    reg [7:0] observation_error;
    reg [15:0] observation_pixels,observation_delivered;
    reg capture_saved,capture_ok,mo_source_sent,mo_result_seen,mo_skip,mo_success;
    reg motion_build_drained;
    reg [7:0] motion_error;
    reg motion_selected,nr_started,nr_failure_seen,projection_failure_seen;
    reg [31:0] stale_sources;
    // Only one partial assembly and one native output register; no FIFO.
    reg [31:0] partial_y,packed_y;
    reg [2:0] partial_count;
    reg partial_sof,packed_valid,packed_sof,packed_eol,packed_last;
    reg [3:0] packed_keep;
    wire start_tag_eligible=i_tag[63:32]==0 && i_tag[31:0]!=0;
    wire [31:0] start_write_tag=start_tag_eligible ? i_tag[31:0] : 32'd0;
    wire [159:0] start_context={i_aux,i_key,start_write_tag};
    wire joint_history=i_enable && !i_history_reset && start_tag_eligible && i_frame[0] &&
        i_frame[302:271]!=0 && nr_o_offer_valid && mo_o_offer_valid &&
        nr_o_offer_key==i_key && nr_o_offer_tag[63:32]==0 && nr_o_offer_tag[31:0]!=0 &&
        mo_o_offer_frame==nr_o_offer_frame && mo_o_offer_key==nr_o_offer_key &&
        mo_o_offer_tag==nr_o_offer_tag[31:0] &&
        mo_o_offer_context=={nr_o_offer_aux,nr_o_offer_key,nr_o_offer_tag[31:0]};
    // The old-Y reader can immediately become the projection reader at F26
    // RESULT. Preserve its actual BUILD drain proof at that owner boundary.
    wire nr_write_quiescent,mo_build_quiescent,stats_start_ready;
    wire phase_reset_done,phase_begin_ready,phase_process_ready,phase_release_ready;
    wire phase_process_active,phase_fault,phase_idle;
    wire [31:0] phase_stale_controls;
    wire [146:0] q_cw_source_data,q_cw_sink_data;
    wire q_cw_source_valid,q_cw_source_ready,q_cw_sink_valid,q_cw_sink_ready;
    wire [9:0] q_cw_available;
    wire [146:0] q_mw_source_data,q_mw_sink_data;
    wire q_mw_source_valid,q_mw_source_ready,q_mw_sink_valid,q_mw_sink_ready;
    wire [9:0] q_mw_available;
    wire [146:0] q_cr_source_data,q_cr_sink_data;
    wire q_cr_source_valid,q_cr_source_ready,q_cr_sink_valid,q_cr_sink_ready;
    wire [9:0] q_cr_available;
    wire [146:0] q_hr_source_data,q_hr_sink_data;
    wire q_hr_source_valid,q_hr_source_ready,q_hr_sink_valid,q_hr_sink_ready;
    wire [9:0] q_hr_available;
    assign o_reset_done=nr_o_reset_done && mo_o_reset_done && ob_o_reset_done && phase_reset_done;
    assign o_start_ready=rst_n && state==IDLE && !i_matrix_fault && o_reset_done && nr_o_capture_ready &&
        mo_o_start_ready && !ob_o_busy && !i_cancel && phase_begin_ready && stats_start_ready;
    wire start_fire=i_start_valid && o_start_ready;
    wire main_fire=s_valid && nr_s_ready;
    wire [2:0] main_lanes={2'd0,s_keep[0]}+{2'd0,s_keep[1]}+{2'd0,s_keep[2]}+{2'd0,s_keep[3]};
    wire tap_good=s_tag==tag_locked && s_index==main_groups && s_sof==(main_groups==0);
    wire source_match=i_source_status_frame==frame_locked && i_source_status_tag==tag_locked &&
        i_source_status_key==key_locked && i_source_status_aux==aux_locked;
    assign o_source_status_ready=rst_n && state!=IDLE &&
        (!source_match || source_seen || nr_o_source_status_ready);
    wire source_fire=i_source_status_valid && o_source_status_ready;
    wire matching_source_fire=source_fire && source_match && !source_seen;
    wire negative_source=matching_source_fire && !i_source_status_ok;
    wire observer_cancel=state!=IDLE &&
        (canceled || (i_cancel && !nr_m_result_valid) || negative_source ||
        (source_seen && !source_ok) || tap_bad || (main_fire && !tap_good));
    // After its real STATUS, no later malformed SOF can create a second F20 owner.
    wire observer_tap=main_fire && !ob_status_seen;
    wire pixel_ready=!packed_valid || mo_s_ready;
    wire observer_fifo_ready;
    wire pixel_fire;
    wire observer_export_done;
    wire packed_fire=packed_valid && mo_s_ready;
    wire observer_identity=ob_o_context==context_locked &&
        ob_o_source_width==frame_locked[217:205] && ob_o_source_height==frame_locked[233:221] &&
        ob_o_exposure==frame_locked[302:271] && ob_o_gain==frame_locked[318:303];
    wire observer_status_fire=ob_o_status_valid && !ob_status_seen;
    wire no_observer=source_seen && !observer_started && (main_groups==0 || tap_bad);
    wire pack_quiet=!packed_valid && partial_count==0 && received_pixels==packed_pixels;
    wire y_source_quiet=source_seen && source_quiet && pack_quiet &&
        (ob_status_seen || no_observer) && (!ob_status_seen || received_pixels=={16'd0,observation_delivered});
    wire y_source_ok=source_ok && !canceled && !tap_bad && ob_status_seen && ob_status_ok &&
        observation_pixels==OBS_PIXELS && observation_delivered==OBS_PIXELS &&
        frame_locked[220:205]==SOURCE_WIDTH && frame_locked[236:221]==SOURCE_HEIGHT;
    wire y_source_valid=state!=IDLE && y_source_quiet && !mo_source_sent;
    wire branch_cancel=state!=IDLE &&
        (canceled || (i_cancel && !nr_m_result_valid) || tap_bad ||
        (source_seen && !source_ok) || (ob_status_seen && !ob_status_ok));
    wire mo_result_ready=state==CAPTURE_BUILD && capture_saved && !identity_lost;
    wire mo_result_fire=mo_m_result_valid && mo_result_ready;
    wire mo_result_match=mo_m_result_frame==frame_locked && mo_m_result_key==key_locked &&
        mo_m_result_context==context_locked && mo_m_result_tag==write_tag_locked;
    wire projection_cancel=state!=IDLE && !nr_m_result_valid &&
        (canceled || i_cancel || nr_o_abort_request || (capture_saved && !capture_ok));
    wire motion_pair_match=mo_m_motion_frame==frame_locked && mo_m_motion_history_frame==old_frame_locked &&
        mo_m_motion_key==key_locked && mo_m_motion_context==context_locked &&
        mo_m_motion_tag==tag_locked && mo_m_motion_history_tag==old_tag_locked;
    wire motion_terminal=mo_skip && mo_result_seen;
    wire projection_terminal=mo_m_projection_valid && mo_o_read_quiescent;
    // RESULT releases the held projection terminal. Its VALID is no longer a
    // quiet proof in IDLE; use the real motion backend drain and ownership.
    wire motion_idle_quiet=state==IDLE && !mo_o_busy && mo_o_read_quiescent;
    wire motion_tail_quiet=motion_terminal || projection_terminal || motion_idle_quiet;
    wire selected_projection_failure=nr_started && motion_selected &&
        (mo_o_backend_fault || (mo_m_projection_valid && mo_m_projection_kind==2));
    // Both directions of failure propagation cross a register. Motion's
    // terminal VALID includes its real drain proof, which itself reacts to
    // projection_cancel; feeding it directly into NR cancel creates feedback.
    wire nr_cancel=state!=IDLE && !nr_m_result_valid &&
        (canceled || i_cancel || (projection_failure_seen && !nr_failure_seen));
    wire motion_discard=!nr_m_result_valid && (nr_o_abort_request || nr_cancel || identity_lost);
    wire nr_process_valid=state==NR_PROCESS && !nr_started && !identity_lost && phase_process_active;
    wire result_rendezvous=nr_m_result_valid && motion_tail_quiet && !identity_lost && phase_release_ready && observer_export_done;
    assign m_result_valid=rst_n && (state==NR_PROCESS || state==RESULT) && result_rendezvous;
    wire result_fire=m_result_valid && m_result_ready;
    assign o_busy=state!=IDLE || nr_o_busy || mo_o_busy || ob_o_busy || !phase_idle;
    assign o_abort_request=state!=IDLE && (nr_o_abort_request || nr_cancel);
    assign o_read_quiescent=nr_o_read_quiescent && motion_tail_quiet;
    assign o_quarantined=identity_lost || nr_o_quarantined || state==FAULT || phase_fault;
    assign o_stale_control_count=stale_sources+nr_o_stale_control_count+phase_stale_controls;
    assign o_observation_ok=ob_status_seen && ob_status_ok;
    assign o_observation_error=ob_status_seen ? observation_error : no_observer ? 8'd40 : 8'd0;
    assign o_observation_pixels=observation_pixels;assign o_observation_delivered=observation_delivered;
    assign o_observation_dropped=ob_o_dropped_frames;
    assign o_motion_success=mo_success;assign o_motion_qualified=motion_selected;assign o_motion_skipped=mo_skip;
    assign o_motion_error=motion_error;assign o_projection_error=mo_skip ? 8'd0 : mo_m_projection_error;
    assign o_map_committed=mo_o_map_committed;assign o_motion_backend_fault=mo_o_backend_fault;
    assign o_y_pinned_banks=mo_o_pinned_banks;
    generate if(OBSERVER_EXPORT_ENABLE!=0)begin: g_observer_export
        reg enabled,local_seen,export_seen,terminal_pending,terminal_sent;
        reg terminal_ok;
        reg [7:0] terminal_error,source_error;
        reg [15:0] terminal_pixels,terminal_delivered;
        wire local_fire=ob_o_pixel_valid && !local_seen && pixel_ready;
        wire export_fire=m_observer_valid && m_observer_ready;
        wire fifo_fire=ob_o_pixel_valid && observer_fifo_ready;
        // Each consumer takes the held official FIFO head exactly once.
        // Only the low-rate observation can stall; original RGB READY is intact.
        assign pixel_fire=local_fire;
        assign observer_fifo_ready=(local_seen || pixel_ready) &&
            (!enabled || export_seen || m_observer_ready);
        assign m_observer_valid=rst_n && enabled && ob_o_pixel_valid && !export_seen;
        assign m_observer_rgb=ob_o_pixel_rgb;
        assign m_observer_luma=ob_o_pixel_luma;
        assign m_observer_sof=ob_o_pixel_sof;
        assign m_observer_eol=ob_o_pixel_eol;
        assign m_observer_last=ob_o_pixel_last;
        assign m_observer_identity={aux_locked,key_locked,tag_locked,frame_locked};
        assign m_observer_context=context_locked;
        assign m_observer_status_valid=rst_n && terminal_pending;
        assign m_observer_status_ok=terminal_ok;
        assign m_observer_status_error=terminal_error;
        assign m_observer_status_pixels=terminal_pixels;
        assign m_observer_status_delivered=terminal_delivered;
        assign observer_export_done=!enabled || terminal_sent;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)begin
                enabled<=0;local_seen<=0;export_seen<=0;terminal_pending<=0;terminal_sent<=0;
                terminal_ok<=0;terminal_error<=0;source_error<=0;terminal_pixels<=0;terminal_delivered<=0;
            end else begin
                if(fifo_fire)begin local_seen<=0;export_seen<=0;end
                else begin
                    if(local_fire)local_seen<=1;
                    if(export_fire)export_seen<=1;
                end
                if(start_fire)begin
                    enabled<=i_observer_export_enable;
                    terminal_pending<=0;terminal_sent<=0;source_error<=0;
                end
                if(matching_source_fire)source_error<=i_source_status_error;
                // F20 EOF alone is not original SOURCE success. Freeze a single
                // result only after real SOURCE and all accepted samples drain.
                if(enabled && state!=IDLE && y_source_quiet && capture_saved && !terminal_pending && !terminal_sent)begin
                    terminal_pending<=1;
                    terminal_ok<=y_source_ok && capture_ok && frame_locked[0] && frame_locked[302:271]!=0;
                    terminal_error<=!source_ok ? (source_error!=0 ? source_error : 8'd42) :
                        no_observer ? 8'd40 : observation_error!=0 ? observation_error :
                        !y_source_ok ? 8'd42 : !capture_ok ? 8'd44 :
                        !frame_locked[0] || frame_locked[302:271]==0 ? 8'd43 : 8'd0;
                    terminal_pixels<=ob_status_seen ? observation_pixels : 16'd0;
                    terminal_delivered<=ob_status_seen ? observation_delivered : 16'd0;
                end
                if(m_observer_status_valid && m_observer_status_ready)begin
                    terminal_pending<=0;terminal_sent<=1;
                end
            end
        end
    end else begin: g_no_observer_export
        assign observer_fifo_ready=pixel_ready;
        assign pixel_fire=ob_o_pixel_valid && pixel_ready;
        assign observer_export_done=1'b1;
        assign m_observer_valid=1'b0;assign m_observer_rgb=24'd0;assign m_observer_luma=8'd0;
        assign m_observer_sof=1'b0;assign m_observer_eol=1'b0;assign m_observer_last=1'b0;
        assign m_observer_identity=576'd0;assign m_observer_context=160'd0;
        assign m_observer_status_valid=1'b0;assign m_observer_status_ok=1'b0;
        assign m_observer_status_error=8'd0;assign m_observer_status_pixels=16'd0;
        assign m_observer_status_delivered=16'd0;
    end endgenerate
    generate if(NEUTRAL_STATS_ENABLE!=0)begin: g_original_stats
        nr_original_stats_source4 #(.SOURCE_WIDTH(SOURCE_WIDTH),.SOURCE_HEIGHT(SOURCE_HEIGHT)) u_stats(
            .clk(clk),.rst_n(rst_n),.i_start(start_fire),.o_start_ready(stats_start_ready),
            .i_frame(i_frame),.i_tag(i_tag),.i_observer_expected_context(start_context),
            .i_observation_valid(observer_status_fire),.i_observation_metadata_match(observer_identity),
            .i_observation_context(ob_o_context),
            .i_observation_statistics({8'd1,ob_o_status_error,{7'd0,ob_o_status_ok},
                3'd0,ob_o_observation_height,3'd0,ob_o_observation_width,8'd224,8'd32,
                ob_o_status_max_y,ob_o_status_min_y,ob_o_status_bright,ob_o_status_dark,
                ob_o_status_sum_y,ob_o_status_delivered,ob_o_status_pixels}),
            .i_source_valid(matching_source_fire),.i_source_ok(i_source_status_ok),
            .i_source_error(i_source_status_error),.i_source_pixels(i_source_status_pixels),
            .i_accepted_pixels(main_pixels),.i_source_quiescent(y_source_quiet),.i_no_observer(no_observer),
            .m_valid(m_original_stats_valid),.m_ready(m_original_stats_ready),.m_tag(m_original_stats_tag),
            .m_context(m_original_stats_context),.m_statistics(m_original_statistics));
    end else begin: g_no_original_stats
        assign stats_start_ready=1'b1;
        assign m_original_stats_valid=1'b0;assign m_original_stats_tag=64'd0;
        assign m_original_stats_context=160'd0;assign m_original_statistics=184'd0;
    end endgenerate
    generate if(SHARED_PHASE_FIFO_ENABLE!=0)begin: g_shared_phase
        nr_dfi_phase_fifo_pair4 u_pair(
            .clk(clk),.rst_n(rst_n),.i_ddr_reset_done(i_ddr_reset_done),.i_matrix_hard_fault(i_matrix_hard_fault),
            .s_begin_context({i_aux,i_key,i_tag,i_frame}),.s_begin_valid(start_fire),.s_begin_ready(phase_begin_ready),
            .s_process_context({aux_locked,key_locked,tag_locked,frame_locked}),
            .s_process_valid(state==NR_PROCESS && !nr_started && !identity_lost),.s_process_ready(phase_process_ready),
            .s_release_context({aux_locked,key_locked,tag_locked,frame_locked}),
            .s_release_valid(result_fire),.s_release_ready(phase_release_ready),
            .i_rgb_write_quiescent(nr_write_quiescent),.i_motion_write_quiescent(motion_build_drained),
            .i_old_y_read_quiescent(motion_build_drained),.i_original_source_quiescent(y_source_quiet),
            .i_rgb_read_quiescent(nr_o_read_quiescent),.i_projection_quiescent(motion_tail_quiet),
            .i_filtered_source_quiescent(nr_m_result_valid),
            .o_reset_done(phase_reset_done),.o_build_active(),.o_process_active(phase_process_active),
            .o_idle(phase_idle),.o_fault(phase_fault),.o_queues_empty(),.o_stale_control_count(phase_stale_controls),
            .s_cw_data(q_cw_source_data),.s_cw_valid(q_cw_source_valid),.s_cw_ready(q_cw_source_ready),
            .m_cw_data(q_cw_sink_data),.m_cw_valid(q_cw_sink_valid),.m_cw_ready(q_cw_sink_ready),.o_cw_available(q_cw_available),
            .s_mw_data(q_mw_source_data),.s_mw_valid(q_mw_source_valid),.s_mw_ready(q_mw_source_ready),
            .m_mw_data(q_mw_sink_data),.m_mw_valid(q_mw_sink_valid),.m_mw_ready(q_mw_sink_ready),.o_mw_available(q_mw_available),
            .s_cr_data(q_cr_source_data),.s_cr_valid(q_cr_source_valid),.s_cr_ready(q_cr_source_ready),
            .m_cr_data(q_cr_sink_data),.m_cr_valid(q_cr_sink_valid),.m_cr_ready(q_cr_sink_ready),.o_cr_available(q_cr_available),
            .s_hr_data(q_hr_source_data),.s_hr_valid(q_hr_source_valid),.s_hr_ready(q_hr_source_ready),
            .m_hr_data(q_hr_sink_data),.m_hr_valid(q_hr_sink_valid),.m_hr_ready(q_hr_sink_ready),.o_hr_available(q_hr_available)
        );
    end else begin: g_internal_phase
        assign phase_reset_done=1'b1;
        assign phase_begin_ready=1'b1;assign phase_process_ready=1'b1;assign phase_release_ready=1'b1;
        assign phase_process_active=1'b1;assign phase_fault=1'b0;assign phase_idle=1'b1;
        assign phase_stale_controls=32'd0;
        assign q_cw_source_ready=1'b0;assign q_cw_sink_data=147'd0;assign q_cw_sink_valid=1'b0;assign q_cw_available=10'd0;
        assign q_mw_source_ready=1'b0;assign q_mw_sink_data=147'd0;assign q_mw_sink_valid=1'b0;assign q_mw_available=10'd0;
        assign q_cr_source_ready=1'b0;assign q_cr_sink_data=147'd0;assign q_cr_sink_valid=1'b0;assign q_cr_available=10'd0;
        assign q_hr_source_ready=1'b0;assign q_hr_sink_data=147'd0;assign q_hr_sink_valid=1'b0;assign q_hr_available=10'd0;
    end endgenerate
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;frame_locked<=0;tag_locked<=0;key_locked<=0;aux_locked<=0;
            old_frame_locked<=0;old_tag_locked<=0;context_locked<=0;write_tag_locked<=0;
            enable_locked<=0;history_reset_locked<=0;guard_locked<=0;canceled<=0;
            source_seen<=0;source_ok<=0;source_quiet<=0;main_groups<=0;main_pixels<=0;
            observer_started<=0;ob_status_seen<=0;ob_status_ok<=0;observation_error<=0;
            observation_pixels<=0;observation_delivered<=0;tap_bad<=0;identity_lost<=0;
            capture_saved<=0;capture_ok<=0;motion_build_drained<=0;mo_source_sent<=0;mo_result_seen<=0;mo_skip<=0;mo_success<=0;motion_error<=0;
            motion_selected<=0;nr_started<=0;nr_failure_seen<=0;projection_failure_seen<=0;stale_sources<=0;
            partial_y<=0;partial_count<=0;partial_sof<=0;packed_y<=0;packed_valid<=0;
            packed_keep<=0;packed_sof<=0;packed_eol<=0;packed_last<=0;received_pixels<=0;packed_pixels<=0;
        end else begin
            if(i_cancel && state!=IDLE && !nr_m_result_valid)canceled<=1;
            if(state!=IDLE && nr_o_abort_request)nr_failure_seen<=1;
            if(selected_projection_failure)projection_failure_seen<=1;
            if(main_fire)begin
                main_groups<=main_groups+32'd1;main_pixels<=main_pixels+main_lanes;
                if(!tap_good)tap_bad<=1;
                if(s_sof && !ob_status_seen)observer_started<=1;
            end
            if(source_fire && (!source_match || source_seen) && !(&stale_sources))stale_sources<=stale_sources+32'd1;
            if(matching_source_fire)begin
                source_seen<=1;source_ok<=i_source_status_ok;source_quiet<=i_source_read_quiescent;
                if(i_source_status_pixels!=main_pixels)tap_bad<=1;
            end
            if(observer_status_fire)begin
                ob_status_seen<=1;ob_status_ok<=ob_o_status_ok && observer_identity;
                observation_error<=observer_identity ? ob_o_status_error : 8'd41;
                observation_pixels<=ob_o_status_pixels;observation_delivered<=ob_o_status_delivered;
                if(!observer_identity)identity_lost<=1;
            end
            if(nr_m_capture_ack_valid && m_capture_ack_ready)begin capture_saved<=1;capture_ok<=nr_m_capture_ack_ok;end
            if(y_source_valid && mo_o_source_ready)mo_source_sent<=1;
            if(packed_fire)begin packed_valid<=0;packed_pixels<=packed_pixels+
                {31'd0,packed_keep[0]}+{31'd0,packed_keep[1]}+{31'd0,packed_keep[2]}+{31'd0,packed_keep[3]};end
            if(pixel_fire)begin
                received_pixels<=received_pixels+32'd1;
                if(partial_count==0)partial_sof<=ob_o_pixel_sof;
                if(partial_count==3 || ob_o_pixel_eol || ob_o_pixel_last)begin
                    packed_valid<=1;packed_y<=partial_y | ({24'd0,ob_o_pixel_luma}<<(partial_count*8));
                    packed_keep<=4'hf>>(3-partial_count);packed_sof<=partial_count==0 ? ob_o_pixel_sof : partial_sof;
                    packed_eol<=ob_o_pixel_eol;packed_last<=ob_o_pixel_last;partial_y<=0;partial_count<=0;
                end else begin
                    partial_y<=partial_y | ({24'd0,ob_o_pixel_luma}<<(partial_count*8));
                    partial_count<=partial_count+3'd1;
                end
            end else if(ob_status_seen && partial_count!=0 && !packed_valid)begin
                packed_valid<=1;packed_y<=partial_y;packed_keep<=4'hf>>(4-partial_count);
                packed_sof<=partial_sof;packed_eol<=0;packed_last<=0;partial_y<=0;partial_count<=0;
            end
            case(state)
                IDLE:if(start_fire)begin
                    frame_locked<=i_frame;tag_locked<=i_tag;key_locked<=i_key;aux_locked<=i_aux;
                    old_frame_locked<=nr_o_offer_frame;old_tag_locked<=nr_o_offer_tag;
                    context_locked<=start_context;write_tag_locked<=start_write_tag;
                    enable_locked<=i_enable;history_reset_locked<=i_history_reset;guard_locked<=i_motion_guard;canceled<=0;
                    source_seen<=0;source_ok<=0;source_quiet<=0;main_groups<=0;main_pixels<=0;
                    observer_started<=0;ob_status_seen<=0;ob_status_ok<=0;observation_error<=0;observation_pixels<=0;observation_delivered<=0;tap_bad<=0;
                    capture_saved<=0;capture_ok<=0;motion_build_drained<=0;mo_source_sent<=0;mo_result_seen<=0;mo_skip<=0;mo_success<=0;motion_error<=0;
                    motion_selected<=0;nr_started<=0;nr_failure_seen<=0;projection_failure_seen<=0;partial_y<=0;partial_count<=0;partial_sof<=0;packed_valid<=0;received_pixels<=0;packed_pixels<=0;
                    state<=CAPTURE_BUILD;
                end
                CAPTURE_BUILD:if(mo_result_fire)begin
                    mo_result_seen<=1;mo_skip<=mo_m_result_kind==0;mo_success<=mo_m_result_success;
                    motion_error<=mo_m_result_backend_error!=0 ? mo_m_result_backend_error : mo_m_result_error;
                    if(!mo_result_match || !mo_build_quiescent)begin identity_lost<=1;state<=FAULT;end
                    else begin motion_build_drained<=1;state<=WAIT_PROJECTION;end
                end
                WAIT_PROJECTION:begin
                    if(motion_terminal || mo_m_projection_valid)begin motion_selected<=0;state<=NR_PROCESS;end
                    else if(mo_m_motion_valid)begin
                        if(motion_pair_match && capture_ok && !canceled)begin motion_selected<=1;state<=NR_PROCESS;end
                        else begin identity_lost<=1;state<=FAULT;end
                    end
                end
                NR_PROCESS:begin
                    if(nr_process_valid && nr_o_process_ready)nr_started<=1;
                    if(result_rendezvous)state<=RESULT;
                    if(result_fire)state<=IDLE;
                end
                RESULT:if(result_fire)state<=IDLE;
                FAULT:begin end
                default:begin state<=FAULT;identity_lost<=1;end
            endcase
        end
    end


    temporal_nr_staging_service4 #(.EXTERNAL_FIFO_ENABLE(SHARED_PHASE_FIFO_ENABLE),.BORROW_JOB_CONTEXT(1)) u_nr(
        .i_job_context({aux_locked,key_locked,tag_locked,frame_locked}),
        .i_external_fifo_reset_done(phase_reset_done),
        .q_cw_source_data(q_cw_source_data),.q_cw_source_valid(q_cw_source_valid),.q_cw_source_ready(q_cw_source_ready),
        .q_cw_sink_data(q_cw_sink_data),.q_cw_sink_valid(q_cw_sink_valid),.q_cw_sink_ready(q_cw_sink_ready),.q_cw_available(q_cw_available),
        .q_cr_source_data(q_cr_source_data),.q_cr_source_valid(q_cr_source_valid),.q_cr_source_ready(q_cr_source_ready),
        .q_cr_sink_data(q_cr_sink_data),.q_cr_sink_valid(q_cr_sink_valid),.q_cr_sink_ready(q_cr_sink_ready),.q_cr_available(q_cr_available),
        .q_hr_source_data(q_hr_source_data),.q_hr_source_valid(q_hr_source_valid),.q_hr_source_ready(q_hr_source_ready),
        .q_hr_sink_data(q_hr_sink_data),.q_hr_sink_valid(q_hr_sink_valid),.q_hr_sink_ready(q_hr_sink_ready),.q_hr_available(q_hr_available),
        .o_write_quiescent(nr_write_quiescent),
        .clk(clk),
        .rst_n(rst_n),
        .i_ddr_reset_done(i_ddr_reset_done),
        .o_reset_done(nr_o_reset_done),
        .i_capture_valid(start_fire),
        .o_capture_ready(nr_o_capture_ready),
        .i_capture_frame(i_frame),
        .i_capture_tag(i_tag),
        .i_capture_key(i_key),
        .i_capture_aux(i_aux),
        .s_rgb(s_rgb),
        .s_keep(s_keep),
        .s_sof(s_sof),
        .s_eol(s_eol),
        .s_last(s_last),
        .s_valid(s_valid),
        .s_ready(nr_s_ready),
        .s_index(s_index),
        .s_tag(s_tag),
        .i_source_status_valid(i_source_status_valid && source_match && !source_seen),
        .o_source_status_ready(nr_o_source_status_ready),
        .i_source_status_frame(i_source_status_frame),
        .i_source_status_tag(i_source_status_tag),
        .i_source_status_key(i_source_status_key),
        .i_source_status_aux(i_source_status_aux),
        .i_source_status_ok(i_source_status_ok),
        .i_source_status_error(i_source_status_error),
        .i_source_status_pixels(i_source_status_pixels),
        .i_source_read_quiescent(i_source_read_quiescent),
        .m_capture_ack_valid(nr_m_capture_ack_valid),
        .m_capture_ack_ready(m_capture_ack_ready),
        .m_capture_ack_frame(nr_m_capture_ack_frame),
        .m_capture_ack_tag(nr_m_capture_ack_tag),
        .m_capture_ack_key(nr_m_capture_ack_key),
        .m_capture_ack_aux(nr_m_capture_ack_aux),
        .m_capture_ack_ok(nr_m_capture_ack_ok),
        .m_capture_ack_error(nr_m_capture_ack_error),
        .m_capture_ack_pixels(nr_m_capture_ack_pixels),
        .i_process_valid(nr_process_valid),
        .o_process_ready(nr_o_process_ready),
        .i_process_frame(frame_locked),
        .i_process_tag(tag_locked),
        .i_process_key(key_locked),
        .i_process_aux(aux_locked),
        .i_enable(enable_locked),
        .i_history_reset(history_reset_locked),
        .i_motion_guard(guard_locked),
        .i_motion_qualified(motion_selected),
        .i_motion_current_tag(tag_locked),
        .i_motion_history_tag(old_tag_locked),
        .motion_confidence(mo_m_motion_confidence),
        .motion_lane_valid(mo_m_motion_lane_valid),
        .motion_keep(mo_m_motion_keep),
        .motion_sof(mo_m_motion_sof),
        .motion_eol(mo_m_motion_eol),
        .motion_last(mo_m_motion_last),
        .motion_valid(mo_m_motion_valid),
        .motion_ready(nr_motion_ready),
        .motion_current_tag(mo_m_motion_tag),
        .motion_history_tag(mo_m_motion_history_tag),
        .motion_index(mo_m_motion_index),
        .i_motion_read_quiescent(motion_tail_quiet),
        .m_rgb(nr_m_rgb),
        .m_keep(nr_m_keep),
        .m_sof(nr_m_sof),
        .m_eol(nr_m_eol),
        .m_last(nr_m_last),
        .m_valid(nr_m_valid),
        .m_ready(m_ready),
        .m_index(nr_m_index),
        .m_tag(nr_m_tag),
        .m_filtered_fence_valid(nr_m_filtered_fence_valid),
        .m_filtered_fence_ready(m_filtered_fence_ready),
        .m_filtered_fence_frame(nr_m_filtered_fence_frame),
        .m_filtered_fence_tag(nr_m_filtered_fence_tag),
        .m_filtered_fence_key(nr_m_filtered_fence_key),
        .m_filtered_fence_aux(nr_m_filtered_fence_aux),
        .m_filtered_fence_ok(nr_m_filtered_fence_ok),
        .m_filtered_fence_error(nr_m_filtered_fence_error),
        .m_filtered_fence_pixels(nr_m_filtered_fence_pixels),
        .i_filtered_ack_valid(i_filtered_ack_valid),
        .o_filtered_ack_ready(nr_o_filtered_ack_ready),
        .i_filtered_ack_frame(i_filtered_ack_frame),
        .i_filtered_ack_tag(i_filtered_ack_tag),
        .i_filtered_ack_key(i_filtered_ack_key),
        .i_filtered_ack_aux(i_filtered_ack_aux),
        .i_filtered_ack_ok(i_filtered_ack_ok),
        .i_filtered_ack_error(i_filtered_ack_error),
        .i_filtered_ack_pixels(i_filtered_ack_pixels),
        .i_filtered_read_quiescent(i_filtered_read_quiescent),
        .i_cancel(nr_cancel),
        .m_result_valid(nr_m_result_valid),
        .m_result_ready(result_fire),
        .m_result_frame(nr_m_result_frame),
        .m_result_tag(nr_m_result_tag),
        .m_result_key(nr_m_result_key),
        .m_result_aux(nr_m_result_aux),
        .m_result_ok(nr_m_result_ok),
        .m_result_current_ok(nr_m_result_current_ok),
        .m_result_capture_ok(nr_m_result_capture_ok),
        .m_result_history_commit(nr_m_result_history_commit),
        .m_result_error(nr_m_result_error),
        .m_result_capture_pixels(nr_m_result_capture_pixels),
        .m_result_input_pixels(nr_m_result_input_pixels),
        .m_result_output_pixels(nr_m_result_output_pixels),
        .m_result_raw_pixels(nr_m_result_raw_pixels),
        .o_offer_valid(nr_o_offer_valid),
        .o_backend_offer_valid(nr_o_backend_offer_valid),
        .o_offer_frame(nr_o_offer_frame),
        .o_offer_tag(nr_o_offer_tag),
        .o_offer_key(nr_o_offer_key),
        .o_offer_aux(nr_o_offer_aux),
        .o_history_selected(nr_o_history_selected),
        .o_busy(nr_o_busy),
        .o_abort_request(nr_o_abort_request),
        .o_read_quiescent(nr_o_read_quiescent),
        .o_quarantined(nr_o_quarantined),
        .o_nr_history_valid(nr_o_nr_history_valid),
        .o_active_banks(nr_o_active_banks),
        .o_pinned_banks(nr_o_pinned_banks),
        .o_stale_control_count(nr_o_stale_control_count),
        .o_aw_count(nr_o_aw_count),
        .o_w_count(nr_o_w_count),
        .o_b_count(nr_o_b_count),
        .o_ar_count(nr_o_ar_count),
        .o_r_count(nr_o_r_count),
        .o_commit_count(nr_o_commit_count),
        .m_axi_awid(nr_m_axi_awid),
        .m_axi_arid(nr_m_axi_arid),
        .m_axi_awaddr(nr_m_axi_awaddr),
        .m_axi_araddr(nr_m_axi_araddr),
        .m_axi_awlen(nr_m_axi_awlen),
        .m_axi_arlen(nr_m_axi_arlen),
        .m_axi_awsize(nr_m_axi_awsize),
        .m_axi_arsize(nr_m_axi_arsize),
        .m_axi_awburst(nr_m_axi_awburst),
        .m_axi_arburst(nr_m_axi_arburst),
        .m_axi_awvalid(nr_m_axi_awvalid),
        .m_axi_arvalid(nr_m_axi_arvalid),
        .m_axi_awready(rgb_axi_awready),
        .m_axi_arready(rgb_axi_arready),
        .m_axi_wdata(nr_m_axi_wdata),
        .m_axi_wstrb(nr_m_axi_wstrb),
        .m_axi_wlast(nr_m_axi_wlast),
        .m_axi_wvalid(nr_m_axi_wvalid),
        .m_axi_wready(rgb_axi_wready),
        .m_axi_bid(rgb_axi_bid),
        .m_axi_rid(rgb_axi_rid),
        .m_axi_bresp(rgb_axi_bresp),
        .m_axi_rresp(rgb_axi_rresp),
        .m_axi_bvalid(rgb_axi_bvalid),
        .m_axi_rlast(rgb_axi_rlast),
        .m_axi_rvalid(rgb_axi_rvalid),
        .m_axi_bready(nr_m_axi_bready),
        .m_axi_rready(nr_m_axi_rready),
        .m_axi_rdata(rgb_axi_rdata));

    motion_ddr_service4 #(.AXI_ID(4'd2),.EXTERNAL_FIFO_ENABLE(SHARED_PHASE_FIFO_ENABLE)) u_mo(
        .i_external_fifo_reset_done(phase_reset_done),
        .q_mw_source_data(q_mw_source_data),.q_mw_source_valid(q_mw_source_valid),.q_mw_source_ready(q_mw_source_ready),
        .q_mw_sink_data(q_mw_sink_data),.q_mw_sink_valid(q_mw_sink_valid),.q_mw_sink_ready(q_mw_sink_ready),.q_mw_available(q_mw_available),
        .o_build_quiescent(mo_build_quiescent),
        .clk(clk),
        .rst_n(rst_n),
        .i_ddr_reset_done(i_ddr_reset_done),
        .i_source_reset_done(ob_o_reset_done),
        .o_reset_done(mo_o_reset_done),
        .i_start_valid(start_fire),
        .o_start_ready(mo_o_start_ready),
        .i_frame(i_frame),
        .i_history_frame(nr_o_offer_frame),
        .i_key(i_key),
        .i_context(start_context),
        .i_tag(start_write_tag),
        .i_history_tag(nr_o_offer_tag[31:0]),
        .i_width(OBS_WIDTH),
        .i_height(OBS_HEIGHT),
        .i_history_available(joint_history),
        .i_static_threshold(i_static_threshold),
        .i_weak_threshold(i_weak_threshold),
        .i_motion_threshold(i_motion_threshold),
        .i_rgb_available(joint_history),
        .i_rgb_frame(i_frame),
        .i_rgb_history_frame(nr_o_offer_frame),
        .i_rgb_key(i_key),
        .i_rgb_tag(i_tag),
        .i_rgb_history_tag(nr_o_offer_tag),
        .o_offer_valid(mo_o_offer_valid),
        .o_backend_offer_valid(mo_o_backend_offer_valid),
        .o_offer_frame(mo_o_offer_frame),
        .o_offer_key(mo_o_offer_key),
        .o_offer_context(mo_o_offer_context),
        .o_offer_tag(mo_o_offer_tag),
        .o_history_used(mo_o_history_used),
        .o_history_reason(mo_o_history_reason),
        .s_valid(packed_valid),
        .s_ready(mo_s_ready),
        .s_y(packed_y),
        .s_keep(packed_keep),
        .s_sof(packed_sof),
        .s_eol(packed_eol),
        .s_last(packed_last),
        .s_tag(write_tag_locked),
        .i_source_valid(y_source_valid),
        .o_source_ready(mo_o_source_ready),
        .i_source_frame(frame_locked),
        .i_source_key(key_locked),
        .i_source_context(context_locked),
        .i_source_tag(write_tag_locked),
        .i_source_ok(y_source_ok),
        .i_source_read_quiescent(y_source_quiet),
        .i_cancel(branch_cancel),
        .o_abort_request(mo_o_abort_request),
        .o_busy(mo_o_busy),
        .o_read_quiescent(mo_o_read_quiescent),
        .o_job_done(mo_o_job_done),
        .m_result_valid(mo_m_result_valid),
        .m_result_ready(mo_result_ready),
        .m_result_kind(mo_m_result_kind),
        .m_result_frame(mo_m_result_frame),
        .m_result_history_frame(mo_m_result_history_frame),
        .m_result_key(mo_m_result_key),
        .m_result_context(mo_m_result_context),
        .m_result_tag(mo_m_result_tag),
        .m_result_history_tag(mo_m_result_history_tag),
        .m_result_success(mo_m_result_success),
        .m_result_source_ok(mo_m_result_source_ok),
        .m_result_history_publish(mo_m_result_history_publish),
        .m_result_map_commit(mo_m_result_map_commit),
        .m_result_error(mo_m_result_error),
        .m_result_backend_error(mo_m_result_backend_error),
        .m_result_temporal_trust(mo_m_result_temporal_trust),
        .m_result_global_change(mo_m_result_global_change),
        .m_result_brightness_change(mo_m_result_brightness_change),
        .m_result_pixels(mo_m_result_pixels),
        .m_result_foreground(mo_m_result_foreground),
        .m_result_confidence0(mo_m_result_confidence0),
        .m_result_confidence1(mo_m_result_confidence1),
        .m_result_confidence2(mo_m_result_confidence2),
        .m_result_confidence3(mo_m_result_confidence3),
        .m_result_sum_abs(mo_m_result_sum_abs),
        .m_result_sum_y(mo_m_result_sum_y),
        .m_result_sum_diff(mo_m_result_sum_diff),
        .i_projection_cancel(projection_cancel),
        .i_motion_discard(motion_discard),
        .m_motion_valid(mo_m_motion_valid),
        .m_motion_ready(nr_motion_ready),
        .m_motion_confidence(mo_m_motion_confidence),
        .m_motion_lane_valid(mo_m_motion_lane_valid),
        .m_motion_keep(mo_m_motion_keep),
        .m_motion_sof(mo_m_motion_sof),
        .m_motion_eol(mo_m_motion_eol),
        .m_motion_last(mo_m_motion_last),
        .m_motion_index(mo_m_motion_index),
        .m_motion_frame(mo_m_motion_frame),
        .m_motion_history_frame(mo_m_motion_history_frame),
        .m_motion_key(mo_m_motion_key),
        .m_motion_tag(mo_m_motion_tag),
        .m_motion_history_tag(mo_m_motion_history_tag),
        .m_motion_context(mo_m_motion_context),
        .m_projection_valid(mo_m_projection_valid),
        .m_projection_ready(result_fire),
        .m_projection_kind(mo_m_projection_kind),
        .m_projection_error(mo_m_projection_error),
        .m_projection_reason(mo_m_projection_reason),
        .m_projection_qualified(mo_m_projection_qualified),
        .m_projection_map_groups(mo_m_projection_map_groups),
        .m_projection_output_groups(mo_m_projection_output_groups),
        .m_projection_output_pixels(mo_m_projection_output_pixels),
        .o_map_committed(mo_o_map_committed),
        .o_backend_fault(mo_o_backend_fault),
        .o_backend_error(mo_o_backend_error),
        .o_active_banks(mo_o_active_banks),
        .o_pinned_banks(mo_o_pinned_banks),
        .i_debug_clear(1'b0),
        .o_stale_sources(mo_o_stale_sources),
        .o_late_cancels(mo_o_late_cancels),
        .o_completed_jobs(mo_o_completed_jobs),
        .o_aw_count(mo_o_aw_count),
        .o_w_count(mo_o_w_count),
        .o_b_count(mo_o_b_count),
        .o_ar_count(mo_o_ar_count),
        .o_r_count(mo_o_r_count),
        .m_axi_awid(mo_m_axi_awid),
        .m_axi_awaddr(mo_m_axi_awaddr),
        .m_axi_awlen(mo_m_axi_awlen),
        .m_axi_awsize(mo_m_axi_awsize),
        .m_axi_awburst(mo_m_axi_awburst),
        .m_axi_awvalid(mo_m_axi_awvalid),
        .m_axi_awready(map_axi_awready),
        .m_axi_wdata(mo_m_axi_wdata),
        .m_axi_wstrb(mo_m_axi_wstrb),
        .m_axi_wlast(mo_m_axi_wlast),
        .m_axi_wvalid(mo_m_axi_wvalid),
        .m_axi_wready(map_axi_wready),
        .m_axi_bid(map_axi_bid),
        .m_axi_bresp(map_axi_bresp),
        .m_axi_bvalid(map_axi_bvalid),
        .m_axi_bready(mo_m_axi_bready),
        .m_axi_arid(mo_m_axi_arid),
        .m_axi_araddr(mo_m_axi_araddr),
        .m_axi_arlen(mo_m_axi_arlen),
        .m_axi_arsize(mo_m_axi_arsize),
        .m_axi_arburst(mo_m_axi_arburst),
        .m_axi_arvalid(mo_m_axi_arvalid),
        .m_axi_arready(map_axi_arready),
        .m_axi_rid(map_axi_rid),
        .m_axi_rdata(map_axi_rdata),
        .m_axi_rresp(map_axi_rresp),
        .m_axi_rlast(map_axi_rlast),
        .m_axi_rvalid(map_axi_rvalid),
        .m_axi_rready(mo_m_axi_rready));

    neutral_observer #(.SOURCE_WIDTH(SOURCE_WIDTH),.SOURCE_HEIGHT(SOURCE_HEIGHT)) u_ob(
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_tap_valid(observer_tap),
        .i_tap_rgb(s_rgb),
        .i_tap_luma(s_luma),
        .i_tap_keep(s_keep),
        .i_tap_sof(s_sof),
        .i_tap_eol(s_eol),
        .i_tap_eof(s_last),
        .i_source_abort(observer_cancel),
        .i_context(context_locked),
        .i_exposure(frame_locked[302:271]),
        .i_gain(frame_locked[318:303]),
        .i_width(frame_locked[217:205]),
        .i_height(frame_locked[233:221]),
        .o_pixel_valid(ob_o_pixel_valid),
        .i_pixel_ready(observer_fifo_ready),
        .o_pixel_rgb(ob_o_pixel_rgb),
        .o_pixel_luma(ob_o_pixel_luma),
        .o_pixel_sof(ob_o_pixel_sof),
        .o_pixel_eol(ob_o_pixel_eol),
        .o_pixel_last(ob_o_pixel_last),
        .o_context(ob_o_context),
        .o_exposure(ob_o_exposure),
        .o_gain(ob_o_gain),
        .o_source_width(ob_o_source_width),
        .o_source_height(ob_o_source_height),
        .o_observation_width(ob_o_observation_width),
        .o_observation_height(ob_o_observation_height),
        .o_status_valid(ob_o_status_valid),
        .i_status_ready(!ob_status_seen),
        .o_status_ok(ob_o_status_ok),
        .o_status_error(ob_o_status_error),
        .o_status_pixels(ob_o_status_pixels),
        .o_status_delivered(ob_o_status_delivered),
        .o_status_sum_y(ob_o_status_sum_y),
        .o_status_min_y(ob_o_status_min_y),
        .o_status_max_y(ob_o_status_max_y),
        .o_status_dark(ob_o_status_dark),
        .o_status_bright(ob_o_status_bright),
        .o_busy(ob_o_busy),
        .o_reset_done(ob_o_reset_done),
        .o_dropped_frames(ob_o_dropped_frames));
endmodule
