`timescale 1ns / 1ps

// Atomic DFI ownership around two official native RGB FIFO transports.
module temporal_nr_pixel_service4 #(
    parameter [3:0] AXI_ID=4'd2
) (
    input wire i_pixel_clk,i_pixel_rst_n,i_dfi_clk,i_dfi_rst_n,i_ddr_reset_done,
    output wire o_pixel_reset_done,o_dfi_reset_done,
    input wire [575:0] s_context,input wire s_context_valid,output wire s_context_ready,
    input wire [95:0] s_rgb,input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_last,s_valid,output wire s_ready,
    input wire [63:0] s_tag,input wire [31:0] s_index,
    input wire s_status_valid,output wire s_status_ready,
    input wire [63:0] s_status_tag,input wire s_status_ok,
    input wire [7:0] s_status_error,input wire i_pixel_source_read_quiescent,
    output wire [31:0] o_source_stale_status_count,
    output wire o_pixel_protocol_fault,o_dfi_protocol_fault,
    output wire [575:0] o_dfi_context,output wire o_dfi_context_valid,o_start_fire,
    input wire i_enable,i_history_reset,input wire [7:0] i_motion_guard,
    input wire i_motion_qualified,input wire [63:0] i_motion_current_tag,i_motion_history_tag,
    input wire [7:0] motion_confidence,input wire [3:0] motion_lane_valid,motion_keep,
    input wire motion_sof,motion_eol,motion_last,motion_valid,output wire motion_ready,
    input wire [63:0] motion_current_tag,motion_history_tag,input wire [31:0] motion_index,
    input wire i_motion_read_quiescent,i_cancel,
    output wire [575:0] m_context,output wire m_context_valid,input wire m_context_ready,
    output wire [95:0] m_rgb,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,input wire m_ready,
    output wire [63:0] m_tag,output wire [31:0] m_index,output wire m_bad,
    output wire m_status_valid,input wire m_status_ready,
    output wire [63:0] m_status_tag,output wire m_status_ok,
    output wire [7:0] m_status_error,output wire [31:0] m_status_groups,
    output wire o_pixel_read_quiescent,
    output wire o_offer_valid,o_backend_offer_valid,
    output wire [383:0] o_offer_frame,output wire [63:0] o_offer_tag,o_offer_key,
    output wire o_history_selected,o_busy,o_abort_request,o_dfi_read_quiescent,
    output wire [1:0] o_nr_history_valid,
    output wire m_result_valid,input wire m_result_ready,
    output wire [383:0] m_result_frame,output wire [63:0] m_result_tag,m_result_key,
    output wire m_result_ok,m_result_current_ok,m_result_nr_current_ok,m_result_history_commit,
    output wire [7:0] m_result_error,
    output wire [31:0] m_result_input_pixels,m_result_output_pixels,m_result_raw_pixels,
    input wire i_debug_clear,
    output wire [3:0] o_active_banks,o_pinned_banks,
    output wire [31:0] o_aw_count,o_w_count,o_b_count,o_ar_count,o_r_count,o_commit_count,
    output wire [3:0] m_axi_awid,m_axi_arid,
    output wire [27:0] m_axi_awaddr,m_axi_araddr,
    output wire [7:0] m_axi_awlen,m_axi_arlen,
    output wire [2:0] m_axi_awsize,m_axi_arsize,
    output wire [1:0] m_axi_awburst,m_axi_arburst,
    output wire m_axi_awvalid,m_axi_arvalid,input wire m_axi_awready,m_axi_arready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,m_axi_rid,input wire [1:0] m_axi_bresp,m_axi_rresp,
    input wire m_axi_bvalid,m_axi_rlast,m_axi_rvalid,output wire m_axi_bready,m_axi_rready,
    input wire [127:0] m_axi_rdata
);
    wire cohort_reset_n=i_pixel_rst_n && i_dfi_rst_n;
    reg [1:0] dfi_release;
    always @(posedge i_dfi_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) dfi_release<=2'b00;
        else dfi_release<={dfi_release[0],1'b1};
    end
    wire core_reset_n=dfi_release[1];
    wire current_source_done,current_sink_done,reverse_source_done,reverse_sink_done,service_reset_done;
    wire current_source_fault,current_sink_fault,reverse_source_fault,reverse_sink_fault;
    assign o_pixel_reset_done=current_source_done && reverse_sink_done;
    assign o_dfi_reset_done=current_sink_done && reverse_source_done && service_reset_done;
    assign o_pixel_protocol_fault=current_source_fault || reverse_sink_fault;
    assign o_dfi_protocol_fault=current_sink_fault || reverse_source_fault;

    wire [575:0] current_context;
    wire current_context_valid,current_context_ready,reverse_context_valid,reverse_context_ready;
    wire service_start_ready;
    wire nr_start_ready=service_start_ready && current_sink_done && reverse_source_done;
    wire nr_start_valid=current_context_valid && reverse_context_ready;
    assign current_context_ready=nr_start_ready && reverse_context_ready;
    assign reverse_context_valid=current_context_valid && nr_start_ready;
    assign o_start_fire=current_context_valid && current_context_ready;
    assign o_dfi_context=current_context;
    assign o_dfi_context_valid=current_context_valid;

    reg [575:0] locked_context;
    reg source_done,reverse_fence_sent;
    wire [95:0] current_rgb,filtered_rgb;
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
    wire service_source_quiet;
    wire current_status_match=current_status_tag==locked_context[447:384];
    // Only an explicit frozen failure may bypass a rejected owner's data sink.
    wire rejected_tail_discard=service_result_valid && !m_result_ok && !source_done;
    assign current_ready=rejected_tail_discard || service_source_ready;
    assign current_status_ready=!current_status_match || rejected_tail_discard || service_status_ready;
    wire current_status_fire=current_status_valid && current_status_ready && current_status_match;
    assign service_source_quiet=(source_done || (current_status_valid && current_status_match && current_quiet)) &&
        i_motion_read_quiescent;
    wire current_bad_cancel=current_valid && current_bad;

    wire reverse_status_valid,reverse_status_ready;
    assign reverse_status_valid=service_result_valid && !reverse_fence_sent;
    wire reverse_status_fire=reverse_status_valid && reverse_status_ready;
    wire publication_permitted=source_done && i_motion_read_quiescent && (reverse_fence_sent || reverse_status_fire);
    assign m_result_valid=service_result_valid && publication_permitted;
    wire service_result_ready=m_result_ready && publication_permitted;
    always @(posedge i_dfi_clk or negedge core_reset_n) begin
        if(!core_reset_n) begin locked_context<=0;source_done<=0;reverse_fence_sent<=0;end
        else begin
            if(o_start_fire) begin locked_context<=current_context;source_done<=0;reverse_fence_sent<=0;end
            if(current_status_fire && current_quiet) source_done<=1;
            if(reverse_status_fire) reverse_fence_sent<=1;
        end
    end

    native_rgb4_frame_cdc #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080)) u_current (
        .i_source_clk(i_pixel_clk),.i_source_rst_n(cohort_reset_n),
        .s_context(s_context),.s_context_valid(s_context_valid),.s_context_ready(s_context_ready),.o_source_reset_done(current_source_done),
        .s_rgb(s_rgb),.s_keep(s_keep),.s_sof(s_sof),.s_eol(s_eol),.s_last(s_last),.s_valid(s_valid),.s_ready(s_ready),.s_tag(s_tag),.s_index(s_index),
        .s_status_valid(s_status_valid),.s_status_ready(s_status_ready),.s_status_tag(s_status_tag),.s_status_ok(s_status_ok),.s_status_error(s_status_error),
        .i_source_read_quiescent(i_pixel_source_read_quiescent),.o_source_stale_status_count(o_source_stale_status_count),.o_source_protocol_fault(current_source_fault),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(cohort_reset_n),
        .m_context(current_context),.m_context_valid(current_context_valid),.m_context_ready(current_context_ready),.o_sink_reset_done(current_sink_done),
        .m_rgb(current_rgb),.m_keep(current_keep),.m_sof(current_sof),.m_eol(current_eol),.m_last(current_last),.m_valid(current_valid),.m_ready(current_ready),
        .m_tag(current_tag),.m_index(current_index),.m_bad(current_bad),
        .m_status_valid(current_status_valid),.m_status_ready(current_status_ready),.m_status_tag(current_status_tag),.m_status_ok(current_status_ok),
        .m_status_error(current_status_error),.m_status_groups(current_status_groups),.o_sink_read_quiescent(current_quiet),.o_sink_protocol_fault(current_sink_fault));

    native_rgb4_frame_cdc #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080)) u_filtered (
        .i_source_clk(i_dfi_clk),.i_source_rst_n(cohort_reset_n),
        .s_context(current_context),.s_context_valid(reverse_context_valid),.s_context_ready(reverse_context_ready),.o_source_reset_done(reverse_source_done),
        .s_rgb(filtered_rgb),.s_keep(filtered_keep),.s_sof(filtered_sof),.s_eol(filtered_eol),.s_last(filtered_last),.s_valid(filtered_valid),.s_ready(filtered_ready),
        .s_tag(filtered_tag),.s_index(filtered_index),
        .s_status_valid(reverse_status_valid),.s_status_ready(reverse_status_ready),.s_status_tag(m_result_tag),.s_status_ok(m_result_ok),.s_status_error(m_result_error),
        .i_source_read_quiescent(service_result_valid),.o_source_stale_status_count(),.o_source_protocol_fault(reverse_source_fault),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(cohort_reset_n),
        .m_context(m_context),.m_context_valid(m_context_valid),.m_context_ready(m_context_ready),.o_sink_reset_done(reverse_sink_done),
        .m_rgb(m_rgb),.m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_valid(m_valid),.m_ready(m_ready),
        .m_tag(m_tag),.m_index(m_index),.m_bad(m_bad),
        .m_status_valid(m_status_valid),.m_status_ready(m_status_ready),.m_status_tag(m_status_tag),.m_status_ok(m_status_ok),
        .m_status_error(m_status_error),.m_status_groups(m_status_groups),.o_sink_read_quiescent(o_pixel_read_quiescent),.o_sink_protocol_fault(reverse_sink_fault));

    temporal_nr_ddr_service4 #(.AXI_ID(AXI_ID)) u_service (
        .clk(i_dfi_clk),.rst_n(core_reset_n),.i_ddr_reset_done(i_ddr_reset_done),.o_reset_done(service_reset_done),
        .i_start_valid(nr_start_valid),.o_start_ready(service_start_ready),
        .i_frame(current_context[383:0]),.i_tag(current_context[447:384]),.i_pipeline_key(current_context[511:448]),
        .i_enable(i_enable),.i_history_reset(i_history_reset),.i_motion_guard(i_motion_guard),
        .i_motion_qualified(i_motion_qualified),.i_motion_current_tag(i_motion_current_tag),.i_motion_history_tag(i_motion_history_tag),
        .o_offer_valid(o_offer_valid),.o_backend_offer_valid(o_backend_offer_valid),.o_offer_frame(o_offer_frame),.o_offer_tag(o_offer_tag),.o_offer_key(o_offer_key),
        .o_history_selected(o_history_selected),.o_busy(o_busy),.o_abort_request(o_abort_request),.o_read_quiescent(o_dfi_read_quiescent),.o_nr_history_valid(o_nr_history_valid),
        .s_rgb(current_rgb),.s_keep(current_keep),.s_sof(current_sof),.s_eol(current_eol),.s_last(current_last),
        .s_valid(current_valid && !rejected_tail_discard),.s_ready(service_source_ready),.s_tag(current_tag),.s_index(current_index),
        .motion_confidence(motion_confidence),.motion_lane_valid(motion_lane_valid),.motion_keep(motion_keep),
        .motion_sof(motion_sof),.motion_eol(motion_eol),.motion_last(motion_last),.motion_valid(motion_valid),.motion_ready(motion_ready),
        .motion_current_tag(motion_current_tag),.motion_history_tag(motion_history_tag),.motion_index(motion_index),
        .m_rgb(filtered_rgb),.m_keep(filtered_keep),.m_sof(filtered_sof),.m_eol(filtered_eol),.m_last(filtered_last),
        .m_valid(filtered_valid),.m_ready(filtered_ready),.m_index(filtered_index),.m_tag(filtered_tag),
        .i_frame_status_valid(current_status_valid && current_status_match && !rejected_tail_discard),.o_frame_status_ready(service_status_ready),
        .i_frame_status_frame(locked_context[383:0]),.i_frame_status_tag(current_status_tag),.i_frame_status_key(locked_context[511:448]),
        .i_frame_status_ok(current_status_ok),.i_source_read_quiescent(service_source_quiet),.i_cancel(i_cancel || current_bad_cancel),
        .m_result_valid(service_result_valid),.m_result_ready(service_result_ready),.m_result_frame(m_result_frame),.m_result_tag(m_result_tag),.m_result_key(m_result_key),
        .m_result_ok(m_result_ok),.m_result_current_ok(m_result_current_ok),.m_result_nr_current_ok(m_result_nr_current_ok),
        .m_result_history_commit(m_result_history_commit),.m_result_error(m_result_error),
        .m_result_input_pixels(m_result_input_pixels),.m_result_output_pixels(m_result_output_pixels),.m_result_raw_pixels(m_result_raw_pixels),
        .i_debug_clear(i_debug_clear),.o_active_banks(o_active_banks),.o_pinned_banks(o_pinned_banks),
        .o_aw_count(o_aw_count),.o_w_count(o_w_count),.o_b_count(o_b_count),.o_ar_count(o_ar_count),.o_r_count(o_r_count),.o_commit_count(o_commit_count),
        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),.m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
endmodule
