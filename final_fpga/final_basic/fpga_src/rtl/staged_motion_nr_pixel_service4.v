`timescale 1ns / 1ps
// Two atomic native transports surround one original RGB staging backend.
module staged_motion_nr_pixel_service4 #(
    parameter integer SOURCE_WIDTH=1920, SOURCE_HEIGHT=1080,
    parameter integer PREOWNED_CONTEXT_ENABLE=0,
    parameter integer SHARED_PHASE_FIFO_ENABLE=0,NEUTRAL_STATS_ENABLE=0,
    parameter integer DEHAZE_ENABLE=0
) (
    input wire [66:0] i_f21_config,input wire [31:0] i_f21_required_lut_generation,
    input wire f21_cfg_begin_valid,output wire f21_cfg_begin_ready,input wire [31:0] f21_cfg_generation,
    input wire f21_cfg_valid,output wire f21_cfg_ready,input wire [8:0] f21_cfg_index,input wire [10:0] f21_cfg_value,
    input wire f21_cfg_commit_valid,output wire f21_cfg_commit_ready,input wire f21_cfg_abort,
    output wire f21_cfg_status_valid,input wire f21_cfg_status_ready,output wire f21_cfg_status_ok,
    output wire [7:0] f21_cfg_status_error,output wire [31:0] f21_cfg_status_generation,
    output wire o_f21_lut_valid,output wire [31:0] o_f21_lut_generation,
    output wire o_f21_start_eligible,o_f21_busy,o_f21_read_quiescent,o_f21_protocol_fault,
    output wire o_f21_fence_valid,output wire [575:0] o_f21_fence_identity,
    output wire o_f21_fence_ok,output wire [7:0] o_f21_fence_error,output wire [31:0] o_f21_fence_pixels,
    output wire o_f21_history_used,o_f21_metadata_bypass,output wire [31:0] o_f21_frame_lut_generation,
    output wire o_f21_map_commit,output wire [31:0] o_f21_map_commit_frame,
    output wire m_original_stats_valid,input wire m_original_stats_ready,
    output wire [63:0] m_original_stats_tag,
    output wire [159:0] m_original_stats_context,
    output wire [183:0] m_original_statistics,
    input wire i_pixel_clk, i_pixel_rst_n, i_dfi_clk, i_dfi_rst_n,
    output wire o_pixel_reset_done, o_dfi_reset_done,
    input wire [575:0] s_context,
    input wire s_context_valid,
    output wire s_context_ready,
    input wire [95:0] s_rgb,
    input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_last, s_valid,
    output wire s_ready,
    input wire [63:0] s_tag,
    input wire [31:0] s_index,
    input wire s_status_valid,
    output wire s_status_ready,
    input wire [575:0] s_status_context,
    input wire [63:0] s_status_tag,
    input wire s_status_ok,
    input wire [7:0] s_status_error,
    input wire i_pixel_source_read_quiescent,
    output reg [31:0] o_source_stale_status_count,
    output wire o_pixel_protocol_fault, o_dfi_protocol_fault,
    output wire [575:0] o_dfi_context,
    output wire o_dfi_context_valid, o_start_fire,
    input wire i_cancel,
    output wire [575:0] m_context,
    output wire m_context_valid,
    input wire m_context_ready,
    output wire [95:0] m_rgb,
    output wire [3:0] m_keep,
    output wire m_sof, m_eol, m_last, m_valid,
    input wire m_ready,
    output wire [63:0] m_tag,
    output wire [31:0] m_index,
    output wire m_bad,
    output wire m_status_valid,
    input wire m_status_ready,
    output wire [63:0] m_status_tag,
    output wire m_status_ok,
    output wire [7:0] m_status_error,
    output wire [31:0] m_status_groups,
    input wire [575:0] i_pixel_filtered_context,
    input wire i_pixel_filtered_read_quiescent,
    input wire i_pixel_filtered_ok,
    input wire [7:0] i_pixel_filtered_error,
    output wire o_pixel_read_quiescent,
    output reg [31:0] o_filtered_stale_proof_count,
    output reg [31:0] o_dfi_stale_ack_count,
    output wire o_reverse_fence_sent, o_source_done,
    output wire o_gray_empty,
    output wire m_result_valid,
    input wire m_result_ready,
    output wire o_dfi_read_quiescent,
    input wire  i_ddr_reset_done,
    input wire  i_matrix_fault,
    input wire  i_matrix_hard_fault,
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
    wire cohort_reset_n=i_pixel_rst_n && i_dfi_rst_n;
    reg [1:0] pixel_release, dfi_release;
    always @(posedge i_pixel_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) pixel_release<=0;
        else pixel_release<={pixel_release[0],1'b1};
    end
    always @(posedge i_dfi_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) dfi_release<=0;
        else dfi_release<={dfi_release[0],1'b1};
    end
    wire pixel_reset_n=pixel_release[1], core_reset_n=dfi_release[1];
    wire current_source_done,current_sink_done,reverse_source_done,reverse_sink_done;
    wire current_source_fault,current_sink_fault,reverse_source_fault,reverse_sink_fault;
    wire ack_source_done,ack_sink_done,service_reset_done;
    wire pixel_fault=current_source_fault || reverse_sink_fault;
    wire dfi_fault=current_sink_fault || reverse_source_fault || i_matrix_hard_fault || o_f21_protocol_fault;
    reg dfi_fault_meta,dfi_fault_sync,pixel_fault_meta,pixel_fault_sync;
    reg matrix_fault_meta,matrix_fault_sync;
    always @(posedge i_pixel_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin
            dfi_fault_meta<=0;dfi_fault_sync<=0;matrix_fault_meta<=0;matrix_fault_sync<=0;
        end else begin
            dfi_fault_meta<=dfi_fault;dfi_fault_sync<=dfi_fault_meta;
            matrix_fault_meta<=i_matrix_fault;matrix_fault_sync<=matrix_fault_meta;
        end
    end
    always @(posedge i_dfi_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin pixel_fault_meta<=0;pixel_fault_sync<=0;end
        else begin pixel_fault_meta<=pixel_fault;pixel_fault_sync<=pixel_fault_meta;end
    end
    assign o_pixel_protocol_fault=pixel_fault || dfi_fault_sync;
    assign o_dfi_protocol_fault=dfi_fault || pixel_fault_sync;
    assign o_pixel_reset_done=pixel_reset_n && current_source_done && reverse_sink_done && ack_source_done;
    assign o_dfi_reset_done=core_reset_n && current_sink_done && reverse_source_done && ack_sink_done && service_reset_done;

    reg [575:0] pixel_source_context,pixel_filtered_context,locked_context;
    reg pixel_source_active,pixel_filtered_active,dfi_active;
    wire current_context_source_ready;
    // A private RAW owner acquired this job before the processing context.
    // A trusted response error may arrive first; that accepted job still drains.
    // Hard Matrix quarantine remains part of the synchronized protocol barrier.
    wire pixel_start_allowed=o_pixel_reset_done && !o_pixel_protocol_fault &&
        (PREOWNED_CONTEXT_ENABLE!=0 || !matrix_fault_sync);
    assign s_context_ready=pixel_start_allowed && !pixel_source_active && current_context_source_ready;
    wire source_context_fire=s_context_valid && s_context_ready;
    wire source_status_exact=s_status_context==pixel_source_context &&
        s_status_tag==pixel_source_context[447:384];
    wire current_status_source_ready;
    // Old full tuples are consumed locally and cannot terminate the current FIFO owner.
    assign s_status_ready=o_pixel_reset_done && pixel_source_active &&
        (!source_status_exact || current_status_source_ready);
    wire source_status_fire=s_status_valid && s_status_ready;
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            pixel_source_context<=0;pixel_source_active<=0;o_source_stale_status_count<=0;
        end else begin
            if(source_context_fire) begin pixel_source_context<=s_context;pixel_source_active<=1;end
            if(source_status_fire) begin
                if(source_status_exact) pixel_source_active<=0;
                else if(!(&o_source_stale_status_count))
                    o_source_stale_status_count<=o_source_stale_status_count+1'b1;
            end
        end
    end

    wire [575:0] current_context;
    wire current_context_valid,current_context_ready,reverse_context_ready;
    wire service_start_ready,f21_start_ready,f21_start_valid;
    wire matrix_start_blocked=i_matrix_hard_fault ||
        (PREOWNED_CONTEXT_ENABLE==0 && i_matrix_fault);
    wire start_allowed=o_dfi_reset_done && !dfi_active && !o_dfi_protocol_fault && !matrix_start_blocked;
    // The two READY producers do not depend on VALID. All three owners acquire together.
    assign current_context_ready=start_allowed && service_start_ready && reverse_context_ready && f21_start_ready;
    wire service_start_valid=start_allowed && current_context_valid && reverse_context_ready && f21_start_ready;
    assign f21_start_valid=start_allowed && current_context_valid && reverse_context_ready && service_start_ready;
    wire reverse_context_valid=start_allowed && current_context_valid && service_start_ready;
    assign o_start_fire=current_context_valid && current_context_ready;
    assign o_dfi_context=current_context;
    assign o_dfi_context_valid=current_context_valid;

    wire [95:0] current_rgb,filtered_rgb,gray_rgb;
    wire [3:0] current_keep,filtered_keep;
    wire current_sof,current_eol,current_last,current_valid,current_ready,current_bad;
    wire filtered_sof,filtered_eol,filtered_last,filtered_valid,filtered_ready;
    wire [63:0] current_tag,filtered_tag;
    wire [31:0] current_index,filtered_index;
    wire current_status_valid,current_status_ready,current_status_ok,current_quiet;
    wire [63:0] current_status_tag;
    wire [7:0] current_status_error;
    wire [31:0] current_status_groups;
    wire service_source_ready,service_status_ready,service_result_valid;
    reg source_done,source_bad,reverse_fence_sent;
    wire reverse_status_fire;
    reg [31:0] gray_groups,gray_pixels;
    reg [2:0] side_valid;
    reg [3:0] keep0,keep1,keep2;
    reg [31:0] index0,index1,index2;
    reg [63:0] tag0,tag1,tag2;
    reg last0,last1,last2,bad0,bad1,bad2;
    wire gray_s_ready,gray_valid,gray_ready,gray_sof,gray_eol;
    wire [31:0] gray_luma;
    wire rejected_tail_discard=service_result_valid && !m_result_ok && !source_done;
    assign gray_ready=service_source_ready || rejected_tail_discard;
    assign current_ready=dfi_active && gray_s_ready;
    wire gray_input_valid=current_valid && dfi_active;
    // This is the same registered-output advance used by preprocess_gray4.
    wire gray_advance=!gray_valid || gray_ready;
    assign o_gray_empty=side_valid==0 && !gray_valid;
    wire gray_fire=gray_valid && gray_ready;
    function [2:0] keep_count;
        input [3:0] keep;
        begin keep_count={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction
    always @(posedge i_dfi_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin
            side_valid<=0;keep0<=0;keep1<=0;keep2<=0;index0<=0;index1<=0;index2<=0;
            tag0<=0;tag1<=0;tag2<=0;last0<=0;last1<=0;last2<=0;bad0<=0;bad1<=0;bad2<=0;
        end else if(gray_advance) begin
            side_valid<={side_valid[1:0],gray_input_valid};
            keep0<=current_keep;keep1<=keep0;keep2<=keep1;
            index0<=current_index;index1<=index0;index2<=index1;
            tag0<=current_tag;tag1<=tag0;tag2<=tag1;
            last0<=current_last;last1<=last0;last2<=last1;
            bad0<=current_bad;bad1<=bad0;bad2<=bad1;
        end
    end
    preprocess_gray4 #(.MAX_WIDTH(SOURCE_WIDTH),.MAX_HEIGHT(SOURCE_HEIGHT)) u_gray (
        .clk(i_dfi_clk),.rst_n(core_reset_n),.clear(1'b0),.enable(1'b0),
        .width(locked_context[217:205]),.height(locked_context[233:221]),
        .s_valid(gray_input_valid),.s_ready(gray_s_ready),.s_data(current_rgb),
        .s_sof(current_sof),.s_eol(current_eol),
        .m_valid(gray_valid),.m_ready(gray_ready),.m_data(gray_rgb),
        .m_sof(gray_sof),.m_eol(gray_eol),.m_luma(gray_luma),.m_original_data());
    wire current_status_match=current_status_tag==locked_context[447:384];
    wire source_status_present=current_status_valid && current_status_match && o_gray_empty && !source_done;
    assign current_status_ready=!current_status_match ||
        (o_gray_empty && (service_status_ready || rejected_tail_discard));
    wire current_status_fire=current_status_valid && current_status_ready && current_status_match;
    wire source_status_good=current_status_ok && !source_bad && current_status_groups==gray_groups;
    wire service_source_quiet=source_done ||
        (source_status_present && current_quiet);
    wire current_bad_cancel=dfi_active && current_valid && current_bad;
    assign o_source_done=source_done;
    assign o_reverse_fence_sent=reverse_fence_sent;
    always @(posedge i_dfi_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin
            locked_context<=0;dfi_active<=0;source_done<=0;source_bad<=0;
            reverse_fence_sent<=0;gray_groups<=0;gray_pixels<=0;
        end else begin
            if(o_start_fire) begin
                locked_context<=current_context;dfi_active<=1;source_done<=0;source_bad<=0;
                reverse_fence_sent<=0;gray_groups<=0;gray_pixels<=0;
            end
            if(current_bad_cancel || (gray_fire && bad2)) source_bad<=1;
            if(gray_fire) begin gray_groups<=gray_groups+1'b1;gray_pixels<=gray_pixels+keep_count(keep2);end
            if(current_status_fire && current_quiet && o_gray_empty) source_done<=1;
            if(reverse_status_fire) reverse_fence_sent<=1;
            if(m_result_valid && m_result_ready) dfi_active<=0;
        end
    end

    wire filtered_fence_valid,filtered_fence_ready,filtered_fence_ok;
    wire [383:0] filtered_fence_frame;
    wire [63:0] filtered_fence_tag,filtered_fence_key,filtered_fence_aux;
    wire [7:0] filtered_fence_error;
    wire [31:0] filtered_fence_pixels;
    wire reverse_status_ready;
    wire [575:0] reverse_input_context;
    wire reverse_input_context_valid;
    wire [95:0] reverse_rgb;wire [3:0] reverse_keep;
    wire reverse_sof,reverse_eol,reverse_last,reverse_valid,reverse_ready;
    wire [63:0] reverse_tag,reverse_fence_tag;
    wire [31:0] reverse_index;
    wire reverse_fence_valid,reverse_fence_ready,reverse_fence_ok,reverse_input_quiet;
    wire [7:0] reverse_fence_error;
    wire service_busy,service_quiet,service_quarantined;
    assign o_busy=service_busy || o_f21_busy;
    assign o_dfi_read_quiescent=service_quiet && o_f21_read_quiescent;
    assign o_quarantined=service_quarantined || o_f21_protocol_fault;
    // The real filtered FENCE exists before RESULT; deriving it from RESULT would deadlock ACK.
    wire reverse_status_valid=reverse_fence_valid && !reverse_fence_sent;
    assign reverse_status_fire=reverse_status_valid && reverse_status_ready;
    assign reverse_fence_ready=reverse_status_ready && !reverse_fence_sent;
    assign m_result_valid=service_result_valid && source_done;
    wire service_result_ready=m_result_ready && source_done;

    wire observer_valid,observer_ready,observer_sof,observer_eol,observer_last;
    wire [23:0] observer_rgb;wire [7:0] observer_y,observer_error;
    wire [575:0] observer_identity;wire [159:0] observer_context;
    wire observer_status_valid,observer_status_ready,observer_status_ok;
    wire [15:0] observer_pixels,observer_delivered;
    generate if(DEHAZE_ENABLE!=0)begin: g_f21
        wire adapter_start_ready;
        reg [66:0] observer_config;
        // This actual frozen-core ready proves previous map/loader/observer
        // work is idle before pinning a new map. It prevents F20 double-consumer
        // -> NR BUILD -> filtered tail -> old map pin circular waiting.
        wire low_idle=f21_cfg_begin_ready && !f21_cfg_begin_valid &&
            !f21_cfg_valid && !f21_cfg_commit_valid && !f21_cfg_abort;
        assign f21_start_ready=adapter_start_ready && low_idle;
        always @(posedge i_dfi_clk or negedge core_reset_n)begin
            if(!core_reset_n)observer_config<=0;
            else if(o_start_fire)observer_config<=i_f21_config;
        end
        wire [31:0] private_tag=current_context[447:416]==0 && current_context[415:384]!=0 ?
            current_context[415:384] : 32'd0;
        native_dehaze_pipeline4 #(.SOURCE_WIDTH(SOURCE_WIDTH),.SOURCE_HEIGHT(SOURCE_HEIGHT)) u_dehaze(
            .clk(i_dfi_clk),.rst_n(core_reset_n),.i_start_valid(f21_start_valid && low_idle),
            .o_start_ready(adapter_start_ready),.o_start_eligible(o_f21_start_eligible),
            .i_start_identity(current_context),.i_start_context({current_context[575:448],private_tag}),
            .i_start_config(i_f21_config),.i_required_lut_generation(i_f21_required_lut_generation),
            .m_context_valid(reverse_input_context_valid),.m_context_ready(reverse_context_ready),.m_context(reverse_input_context),
            .s_valid(filtered_valid),.s_ready(filtered_ready),.s_rgb(filtered_rgb),.s_keep(filtered_keep),
            .s_sof(filtered_sof),.s_eol(filtered_eol),.s_last(filtered_last),.s_tag(filtered_tag),.s_index(filtered_index),
            .s_source_valid(filtered_fence_valid),.s_source_ready(filtered_fence_ready),
            .s_source_identity({filtered_fence_aux,filtered_fence_key,filtered_fence_tag,filtered_fence_frame}),
            .s_source_ok(filtered_fence_ok),.s_source_error(filtered_fence_error),.s_source_pixels(filtered_fence_pixels),
            .i_cancel_valid(i_cancel || current_bad_cancel),.i_cancel_identity(locked_context),
            .m_valid(reverse_valid),.m_ready(reverse_ready),.m_rgb(reverse_rgb),.m_keep(reverse_keep),
            .m_sof(reverse_sof),.m_eol(reverse_eol),.m_last(reverse_last),.m_tag(reverse_tag),.m_index(reverse_index),
            .m_fence_valid(o_f21_fence_valid),.m_fence_ready(reverse_fence_ready),.m_fence_identity(o_f21_fence_identity),
            .m_fence_ok(o_f21_fence_ok),.m_fence_error(o_f21_fence_error),.m_fence_pixels(o_f21_fence_pixels),
            .o_busy(o_f21_busy),.o_read_quiescent(o_f21_read_quiescent),.o_protocol_fault(o_f21_protocol_fault),
            .o_stale_source_count(),.o_stale_cancel_count(),.o_stale_observer_count(),
            .o_history_used(o_f21_history_used),.o_metadata_bypass(o_f21_metadata_bypass),
            .o_frame_lut_generation(o_f21_frame_lut_generation),
            .s_observer_valid(observer_valid),.s_observer_ready(observer_ready),.s_observer_rgb(observer_rgb),
            .s_observer_y(observer_y),.s_observer_sof(observer_sof),.s_observer_eol(observer_eol),.s_observer_last(observer_last),
            .s_observer_identity(observer_identity),.s_observer_context(observer_context),.s_observer_config(observer_config),
            .s_observer_status_valid(observer_status_valid),.s_observer_status_ready(observer_status_ready),
            .s_observer_status_ok(observer_status_ok),.s_observer_status_error(observer_error),
            .s_observer_status_pixels(observer_pixels),.s_observer_status_delivered(observer_delivered),
            .cfg_begin_valid(f21_cfg_begin_valid),.cfg_begin_ready(f21_cfg_begin_ready),.cfg_generation(f21_cfg_generation),
            .cfg_valid(f21_cfg_valid),.cfg_ready(f21_cfg_ready),.cfg_index(f21_cfg_index),.cfg_value(f21_cfg_value),
            .cfg_commit_valid(f21_cfg_commit_valid),.cfg_commit_ready(f21_cfg_commit_ready),.cfg_abort(f21_cfg_abort),
            .cfg_status_valid(f21_cfg_status_valid),.cfg_status_ready(f21_cfg_status_ready),.cfg_status_ok(f21_cfg_status_ok),
            .cfg_status_error(f21_cfg_status_error),.cfg_status_generation(f21_cfg_status_generation),
            .lut_valid(o_f21_lut_valid),.lut_generation(o_f21_lut_generation),.map_commit(o_f21_map_commit),
            .map_commit_camera(),.map_commit_frame_id(o_f21_map_commit_frame),.map_commit_context());
        assign reverse_fence_valid=o_f21_fence_valid;
        assign reverse_fence_tag=o_f21_fence_identity[447:384];
        assign reverse_fence_ok=o_f21_fence_ok;assign reverse_fence_error=o_f21_fence_error;
        assign reverse_input_quiet=o_f21_read_quiescent;
    end else begin: g_no_f21
        assign f21_start_ready=1'b1;
        assign reverse_input_context=current_context;assign reverse_input_context_valid=reverse_context_valid;
        assign reverse_rgb=filtered_rgb;assign reverse_keep=filtered_keep;
        assign reverse_sof=filtered_sof;assign reverse_eol=filtered_eol;assign reverse_last=filtered_last;
        assign reverse_valid=filtered_valid;assign filtered_ready=reverse_ready;
        assign reverse_tag=filtered_tag;assign reverse_index=filtered_index;
        assign reverse_fence_valid=filtered_fence_valid;assign filtered_fence_ready=reverse_fence_ready;
        assign reverse_fence_tag=filtered_fence_tag;assign reverse_fence_ok=filtered_fence_ok;
        assign reverse_fence_error=filtered_fence_error;assign reverse_input_quiet=filtered_fence_valid && !filtered_valid;
        assign observer_ready=1'b1;assign observer_status_ready=1'b1;
        assign f21_cfg_begin_ready=1'b0;assign f21_cfg_ready=1'b0;assign f21_cfg_commit_ready=1'b0;
        assign f21_cfg_status_valid=1'b0;assign f21_cfg_status_ok=1'b0;assign f21_cfg_status_error=8'd0;
        assign f21_cfg_status_generation=32'd0;assign o_f21_lut_valid=1'b0;assign o_f21_lut_generation=32'd0;
        assign o_f21_start_eligible=1'b0;assign o_f21_busy=1'b0;assign o_f21_read_quiescent=1'b1;
        assign o_f21_protocol_fault=1'b0;assign o_f21_fence_valid=1'b0;assign o_f21_fence_identity=576'd0;
        assign o_f21_fence_ok=1'b0;assign o_f21_fence_error=8'd0;assign o_f21_fence_pixels=32'd0;
        assign o_f21_history_used=1'b0;assign o_f21_metadata_bypass=1'b0;assign o_f21_frame_lut_generation=32'd0;
        assign o_f21_map_commit=1'b0;assign o_f21_map_commit_frame=32'd0;
    end endgenerate

    wire reverse_context_sink_ready,reverse_context_sink_valid;
    wire [575:0] reverse_context;
    reg ack_pending;
    reg [31:0] ack_pixels,pixel_groups,pixel_pixels;
    reg [7:0] ack_error;
    reg ack_ok;
    wire ack_source_ready,ack_sink_valid,ack_sink_ready;
    wire [616:0] ack_sink_data;
    wire [616:0] ack_source_data={pixel_filtered_context[383:0],pixel_filtered_context[447:384],
        pixel_filtered_context[511:448],pixel_filtered_context[575:512],ack_pixels,ack_error,ack_ok};
    assign m_context=reverse_context;
    assign m_context_valid=reverse_context_sink_valid && !ack_pending && !pixel_filtered_active;
    assign reverse_context_sink_ready=m_context_ready && !ack_pending && !pixel_filtered_active;
    wire filtered_context_fire=m_context_valid && m_context_ready;
    wire reverse_status_sink_ready,reverse_status_sink_valid,reverse_quiet;
    assign m_status_valid=reverse_status_sink_valid;
    assign o_pixel_read_quiescent=reverse_quiet;
    wire filtered_proof_exact=i_pixel_filtered_context==pixel_filtered_context &&
        m_status_tag==pixel_filtered_context[447:384] && m_status_groups==pixel_groups;
    // External terminal READY, complete proof identity and actual consumer quiet are one responsibility.
    assign reverse_status_sink_ready=m_status_ready && filtered_proof_exact &&
        i_pixel_filtered_read_quiescent && reverse_quiet && !m_valid && !ack_pending;
    wire filtered_status_fire=m_status_valid && reverse_status_sink_ready;
    always @(posedge i_pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            pixel_filtered_context<=0;pixel_filtered_active<=0;pixel_groups<=0;pixel_pixels<=0;
            ack_pending<=0;ack_pixels<=0;ack_error<=0;ack_ok<=0;o_filtered_stale_proof_count<=0;
        end else begin
            if(filtered_context_fire) begin
                pixel_filtered_context<=m_context;pixel_filtered_active<=1;pixel_groups<=0;pixel_pixels<=0;
            end
            if(m_valid && m_ready) begin pixel_groups<=pixel_groups+1'b1;pixel_pixels<=pixel_pixels+keep_count(m_keep);end
            if(m_status_valid && m_status_ready && !filtered_proof_exact && !(&o_filtered_stale_proof_count))
                o_filtered_stale_proof_count<=o_filtered_stale_proof_count+1'b1;
            if(filtered_status_fire) begin
                ack_pending<=1;ack_pixels<=pixel_pixels;
                ack_error<=i_pixel_filtered_error!=0 ? i_pixel_filtered_error : m_status_error;
                ack_ok<=m_status_ok && i_pixel_filtered_ok;
            end
            if(ack_pending && ack_source_ready) begin ack_pending<=0;pixel_filtered_active<=0;end
        end
    end
    // ack_pending owns the complete source tuple through the actual last
    // serializer flit; READY never acknowledges a partially emitted ACK.
    control_message_fifo_ip #(.MESSAGE_WIDTH(617),.BORROW_SOURCE(1)) u_filtered_ack (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_reset_n),
        .i_source_data(ack_source_data),.i_source_valid(ack_pending),
        .o_source_ready(ack_source_ready),.o_source_reset_done(ack_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(cohort_reset_n),
        .o_sink_data(ack_sink_data),.o_sink_valid(ack_sink_valid),
        .i_sink_ready(ack_sink_ready),.o_sink_reset_done(ack_sink_done));
    wire ack_exact=ack_sink_data[616:233]==locked_context[383:0] &&
        ack_sink_data[232:169]==locked_context[447:384] &&
        ack_sink_data[168:105]==locked_context[511:448] &&
        ack_sink_data[104:41]==locked_context[575:512];
    wire service_ack_ready;
    assign ack_sink_ready=!ack_exact || service_ack_ready;
    always @(posedge i_dfi_clk or negedge core_reset_n) begin
        if(!core_reset_n) o_dfi_stale_ack_count<=0;
        else if(ack_sink_valid && ack_sink_ready && !ack_exact && !(&o_dfi_stale_ack_count))
            o_dfi_stale_ack_count<=o_dfi_stale_ack_count+1'b1;
    end

    native_rgb4_frame_cdc #(.MAX_WIDTH(SOURCE_WIDTH),.MAX_HEIGHT(SOURCE_HEIGHT)) u_current (
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_reset_n),
        .s_context(s_context),.s_context_valid(s_context_valid && pixel_start_allowed && !pixel_source_active),
        .s_context_ready(current_context_source_ready),.o_source_reset_done(current_source_done),
        .s_rgb(s_rgb),.s_keep(s_keep),.s_sof(s_sof),.s_eol(s_eol),.s_last(s_last),
        .s_valid(s_valid),.s_ready(s_ready),.s_tag(s_tag),.s_index(s_index),
        .s_status_valid(s_status_valid && source_status_exact),.s_status_ready(current_status_source_ready),
        .s_status_tag(s_status_tag),.s_status_ok(s_status_ok),.s_status_error(s_status_error),
        .i_source_read_quiescent(i_pixel_source_read_quiescent),
        .o_source_stale_status_count(),.o_source_protocol_fault(current_source_fault),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(cohort_reset_n),
        .m_context(current_context),.m_context_valid(current_context_valid),.m_context_ready(current_context_ready),
        .o_sink_reset_done(current_sink_done),
        .m_rgb(current_rgb),.m_keep(current_keep),.m_sof(current_sof),.m_eol(current_eol),
        .m_last(current_last),.m_valid(current_valid),.m_ready(current_ready),
        .m_tag(current_tag),.m_index(current_index),.m_bad(current_bad),
        .m_status_valid(current_status_valid),.m_status_ready(current_status_ready),
        .m_status_tag(current_status_tag),.m_status_ok(current_status_ok),
        .m_status_error(current_status_error),.m_status_groups(current_status_groups),
        .o_sink_read_quiescent(current_quiet),.o_sink_protocol_fault(current_sink_fault));
    native_rgb4_frame_cdc #(.MAX_WIDTH(SOURCE_WIDTH),.MAX_HEIGHT(SOURCE_HEIGHT)) u_filtered (
        .i_source_clk(i_dfi_clk),.i_source_rst_n(cohort_reset_n),
        .s_context(reverse_input_context),.s_context_valid(reverse_input_context_valid),.s_context_ready(reverse_context_ready),
        .o_source_reset_done(reverse_source_done),
        .s_rgb(reverse_rgb),.s_keep(reverse_keep),.s_sof(reverse_sof),.s_eol(reverse_eol),
        .s_last(reverse_last),.s_valid(reverse_valid),.s_ready(reverse_ready),.s_tag(reverse_tag),.s_index(reverse_index),
        .s_status_valid(reverse_status_valid),.s_status_ready(reverse_status_ready),
        .s_status_tag(reverse_fence_tag),.s_status_ok(reverse_fence_ok),.s_status_error(reverse_fence_error),
        .i_source_read_quiescent(reverse_input_quiet),
        .o_source_stale_status_count(),.o_source_protocol_fault(reverse_source_fault),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(cohort_reset_n),
        .m_context(reverse_context),.m_context_valid(reverse_context_sink_valid),
        .m_context_ready(reverse_context_sink_ready),.o_sink_reset_done(reverse_sink_done),
        .m_rgb(m_rgb),.m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_valid(m_valid),.m_ready(m_ready),
        .m_tag(m_tag),.m_index(m_index),.m_bad(m_bad),
        .m_status_valid(reverse_status_sink_valid),.m_status_ready(reverse_status_sink_ready),
        .m_status_tag(m_status_tag),.m_status_ok(m_status_ok),.m_status_error(m_status_error),
        .m_status_groups(m_status_groups),.o_sink_read_quiescent(reverse_quiet),.o_sink_protocol_fault(reverse_sink_fault));

    staged_motion_nr_service4 #(.SOURCE_WIDTH(SOURCE_WIDTH),.SOURCE_HEIGHT(SOURCE_HEIGHT),
        .SHARED_PHASE_FIFO_ENABLE(SHARED_PHASE_FIFO_ENABLE),.NEUTRAL_STATS_ENABLE(NEUTRAL_STATS_ENABLE),
        .OBSERVER_EXPORT_ENABLE(DEHAZE_ENABLE)) u_service (
        .i_observer_export_enable(DEHAZE_ENABLE!=0 && i_f21_config[66]),
        .m_observer_valid(observer_valid),.m_observer_ready(observer_ready),
        .m_observer_rgb(observer_rgb),.m_observer_luma(observer_y),.m_observer_sof(observer_sof),
        .m_observer_eol(observer_eol),.m_observer_last(observer_last),
        .m_observer_identity(observer_identity),.m_observer_context(observer_context),
        .m_observer_status_valid(observer_status_valid),.m_observer_status_ready(observer_status_ready),
        .m_observer_status_ok(observer_status_ok),.m_observer_status_error(observer_error),
        .m_observer_status_pixels(observer_pixels),.m_observer_status_delivered(observer_delivered),
        .m_original_stats_valid(m_original_stats_valid),.m_original_stats_ready(m_original_stats_ready),
        .m_original_stats_tag(m_original_stats_tag),.m_original_stats_context(m_original_stats_context),
        .m_original_statistics(m_original_statistics),

        .clk(i_dfi_clk),
        .rst_n(core_reset_n),
        .i_ddr_reset_done(i_ddr_reset_done),
        .i_matrix_fault(matrix_start_blocked),.i_matrix_hard_fault(i_matrix_hard_fault),
        .o_reset_done(service_reset_done),
        .i_start_valid(service_start_valid),
        .o_start_ready(service_start_ready),
        .i_frame(current_context[383:0]),
        .i_tag(current_context[447:384]),
        .i_key(current_context[511:448]),
        .i_aux(current_context[575:512]),
        .s_rgb(gray_rgb),
        .s_keep(keep2),
        .s_sof(gray_sof),
        .s_eol(gray_eol),
        .s_last(last2),
        .s_valid(gray_valid && !rejected_tail_discard),
        .s_ready(service_source_ready),
        .s_index(index2),
        .s_tag(tag2),
        .i_source_status_valid(source_status_present && !rejected_tail_discard),
        .o_source_status_ready(service_status_ready),
        .i_source_status_frame(locked_context[383:0]),
        .i_source_status_tag(current_status_tag),
        .i_source_status_key(locked_context[511:448]),
        .i_source_status_aux(locked_context[575:512]),
        .i_source_status_ok(source_status_good),
        .i_source_status_error(current_status_error),
        .i_source_status_pixels(gray_pixels),
        .i_source_read_quiescent(service_source_quiet),
        .m_capture_ack_valid(m_capture_ack_valid),
        .m_capture_ack_ready(m_capture_ack_ready),
        .m_capture_ack_frame(m_capture_ack_frame),
        .m_capture_ack_tag(m_capture_ack_tag),
        .m_capture_ack_key(m_capture_ack_key),
        .m_capture_ack_aux(m_capture_ack_aux),
        .m_capture_ack_ok(m_capture_ack_ok),
        .m_capture_ack_error(m_capture_ack_error),
        .m_capture_ack_pixels(m_capture_ack_pixels),
        .i_enable(i_enable),
        .i_history_reset(i_history_reset),
        .m_rgb(filtered_rgb),
        .m_keep(filtered_keep),
        .m_sof(filtered_sof),
        .m_eol(filtered_eol),
        .m_last(filtered_last),
        .m_valid(filtered_valid),
        .m_ready(filtered_ready),
        .m_index(filtered_index),
        .m_tag(filtered_tag),
        .m_filtered_fence_valid(filtered_fence_valid),
        .m_filtered_fence_ready(filtered_fence_ready),
        .m_filtered_fence_frame(filtered_fence_frame),
        .m_filtered_fence_tag(filtered_fence_tag),
        .m_filtered_fence_key(filtered_fence_key),
        .m_filtered_fence_aux(filtered_fence_aux),
        .m_filtered_fence_ok(filtered_fence_ok),
        .m_filtered_fence_error(filtered_fence_error),
        .m_filtered_fence_pixels(filtered_fence_pixels),
        .i_filtered_ack_valid(ack_sink_valid && ack_exact),
        .o_filtered_ack_ready(service_ack_ready),
        .i_filtered_ack_frame(ack_sink_data[616:233]),
        .i_filtered_ack_tag(ack_sink_data[232:169]),
        .i_filtered_ack_key(ack_sink_data[168:105]),
        .i_filtered_ack_aux(ack_sink_data[104:41]),
        .i_filtered_ack_ok(ack_sink_data[0]),
        .i_filtered_ack_error(ack_sink_data[8:1]),
        .i_filtered_ack_pixels(ack_sink_data[40:9]),
        .i_filtered_read_quiescent(ack_sink_valid && ack_exact),
        .i_cancel(i_cancel || current_bad_cancel),
        .m_result_valid(service_result_valid),
        .m_result_ready(service_result_ready),
        .m_result_frame(m_result_frame),
        .m_result_tag(m_result_tag),
        .m_result_key(m_result_key),
        .m_result_aux(m_result_aux),
        .m_result_ok(m_result_ok),
        .m_result_current_ok(m_result_current_ok),
        .m_result_capture_ok(m_result_capture_ok),
        .m_result_history_commit(m_result_history_commit),
        .m_result_error(m_result_error),
        .m_result_capture_pixels(m_result_capture_pixels),
        .m_result_input_pixels(m_result_input_pixels),
        .m_result_output_pixels(m_result_output_pixels),
        .m_result_raw_pixels(m_result_raw_pixels),
        .o_offer_valid(o_offer_valid),
        .o_backend_offer_valid(o_backend_offer_valid),
        .o_offer_frame(o_offer_frame),
        .o_offer_tag(o_offer_tag),
        .o_offer_key(o_offer_key),
        .o_offer_aux(o_offer_aux),
        .o_history_selected(o_history_selected),
        .o_busy(service_busy),
        .o_abort_request(o_abort_request),
        .o_read_quiescent(service_quiet),
        .o_quarantined(service_quarantined),
        .o_nr_history_valid(o_nr_history_valid),
        .o_rgb_active_banks(o_rgb_active_banks),
        .o_rgb_pinned_banks(o_rgb_pinned_banks),
        .o_stale_control_count(o_stale_control_count),
        .rgb_axi_awid(rgb_axi_awid),
        .rgb_axi_arid(rgb_axi_arid),
        .rgb_axi_awaddr(rgb_axi_awaddr),
        .rgb_axi_araddr(rgb_axi_araddr),
        .rgb_axi_awlen(rgb_axi_awlen),
        .rgb_axi_arlen(rgb_axi_arlen),
        .rgb_axi_awsize(rgb_axi_awsize),
        .rgb_axi_arsize(rgb_axi_arsize),
        .rgb_axi_awburst(rgb_axi_awburst),
        .rgb_axi_arburst(rgb_axi_arburst),
        .rgb_axi_awvalid(rgb_axi_awvalid),
        .rgb_axi_arvalid(rgb_axi_arvalid),
        .rgb_axi_awready(rgb_axi_awready),
        .rgb_axi_arready(rgb_axi_arready),
        .rgb_axi_wdata(rgb_axi_wdata),
        .rgb_axi_wstrb(rgb_axi_wstrb),
        .rgb_axi_wlast(rgb_axi_wlast),
        .rgb_axi_wvalid(rgb_axi_wvalid),
        .rgb_axi_wready(rgb_axi_wready),
        .rgb_axi_bid(rgb_axi_bid),
        .rgb_axi_rid(rgb_axi_rid),
        .rgb_axi_bresp(rgb_axi_bresp),
        .rgb_axi_rresp(rgb_axi_rresp),
        .rgb_axi_bvalid(rgb_axi_bvalid),
        .rgb_axi_rlast(rgb_axi_rlast),
        .rgb_axi_rvalid(rgb_axi_rvalid),
        .rgb_axi_bready(rgb_axi_bready),
        .rgb_axi_rready(rgb_axi_rready),
        .rgb_axi_rdata(rgb_axi_rdata),
        .s_luma(gray_luma),
        .i_motion_guard(i_motion_guard),
        .i_static_threshold(i_static_threshold),
        .i_weak_threshold(i_weak_threshold),
        .i_motion_threshold(i_motion_threshold),
        .o_observation_ok(o_observation_ok),
        .o_motion_success(o_motion_success),
        .o_motion_qualified(o_motion_qualified),
        .o_motion_skipped(o_motion_skipped),
        .o_map_committed(o_map_committed),
        .o_motion_backend_fault(o_motion_backend_fault),
        .o_observation_error(o_observation_error),
        .o_motion_error(o_motion_error),
        .o_projection_error(o_projection_error),
        .o_observation_pixels(o_observation_pixels),
        .o_observation_delivered(o_observation_delivered),
        .o_observation_dropped(o_observation_dropped),
        .o_y_pinned_banks(o_y_pinned_banks),
        .map_axi_awid(map_axi_awid),
        .map_axi_arid(map_axi_arid),
        .map_axi_awaddr(map_axi_awaddr),
        .map_axi_araddr(map_axi_araddr),
        .map_axi_awlen(map_axi_awlen),
        .map_axi_arlen(map_axi_arlen),
        .map_axi_awsize(map_axi_awsize),
        .map_axi_arsize(map_axi_arsize),
        .map_axi_awburst(map_axi_awburst),
        .map_axi_arburst(map_axi_arburst),
        .map_axi_awvalid(map_axi_awvalid),
        .map_axi_arvalid(map_axi_arvalid),
        .map_axi_awready(map_axi_awready),
        .map_axi_arready(map_axi_arready),
        .map_axi_wdata(map_axi_wdata),
        .map_axi_wstrb(map_axi_wstrb),
        .map_axi_wlast(map_axi_wlast),
        .map_axi_wvalid(map_axi_wvalid),
        .map_axi_wready(map_axi_wready),
        .map_axi_bid(map_axi_bid),
        .map_axi_rid(map_axi_rid),
        .map_axi_bresp(map_axi_bresp),
        .map_axi_rresp(map_axi_rresp),
        .map_axi_bvalid(map_axi_bvalid),
        .map_axi_rlast(map_axi_rlast),
        .map_axi_rvalid(map_axi_rvalid),
        .map_axi_bready(map_axi_bready),
        .map_axi_rready(map_axi_rready),
        .map_axi_rdata(map_axi_rdata)
    );
endmodule
