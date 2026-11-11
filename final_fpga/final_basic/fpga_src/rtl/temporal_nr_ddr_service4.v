`timescale 1ns / 1ps

// Same-DFI-clock composition: actual raw DDR ownership and NR publication are
// one transaction. Cross-domain pixel transport belongs to the external owner.
module temporal_nr_ddr_service4 #(
    parameter [3:0] AXI_ID=4'd2
) (
    input wire clk,rst_n,i_ddr_reset_done,
    output wire o_reset_done,
    input wire i_start_valid, output wire o_start_ready,
    input wire [383:0] i_frame, input wire [63:0] i_tag,i_pipeline_key,
    input wire i_enable,i_history_reset, input wire [7:0] i_motion_guard,
    input wire i_motion_qualified, input wire [63:0] i_motion_current_tag,i_motion_history_tag,
    output wire o_offer_valid,o_backend_offer_valid,
    output wire [383:0] o_offer_frame, output wire [63:0] o_offer_tag,o_offer_key,
    output wire o_history_selected,o_busy,o_abort_request,o_read_quiescent,
    output wire [1:0] o_nr_history_valid,
    input wire [95:0] s_rgb, input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_last,s_valid, output wire s_ready,
    input wire [63:0] s_tag, input wire [31:0] s_index,
    input wire [7:0] motion_confidence, input wire [3:0] motion_lane_valid,motion_keep,
    input wire motion_sof,motion_eol,motion_last,motion_valid, output wire motion_ready,
    input wire [63:0] motion_current_tag,motion_history_tag, input wire [31:0] motion_index,
    output wire [95:0] m_rgb, output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid, input wire m_ready,
    output wire [31:0] m_index, output wire [63:0] m_tag,
    input wire i_frame_status_valid, output wire o_frame_status_ready,
    input wire [383:0] i_frame_status_frame,
    input wire [63:0] i_frame_status_tag,i_frame_status_key,
    input wire i_frame_status_ok,i_source_read_quiescent,i_cancel,
    output wire m_result_valid, input wire m_result_ready,
    output wire [383:0] m_result_frame, output wire [63:0] m_result_tag,m_result_key,
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
    output wire m_axi_awvalid,m_axi_arvalid, input wire m_axi_awready,m_axi_arready,
    output wire [127:0] m_axi_wdata, output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid, input wire m_axi_wready,
    input wire [3:0] m_axi_bid,m_axi_rid, input wire [1:0] m_axi_bresp,m_axi_rresp,
    input wire m_axi_bvalid,m_axi_rlast,m_axi_rvalid, output wire m_axi_bready,m_axi_rready,
    input wire [127:0] m_axi_rdata
);
    wire nr_start_ready,nr_busy,nr_plan_valid,backend_plan_ready,backend_busy;
    wire [383:0] frame;
    wire [63:0] tag,key,history_tag;
    wire backend_offer_valid;
    wire [383:0] backend_offer_frame;
    wire [63:0] backend_offer_tag,backend_offer_key;
    // Published identity mirrors compare the full backend offer to the exact
    // NR cache entry established by the same positive RESULT handshake.
    reg [383:0] published_frame0,published_frame1;
    reg [63:0] published_tag0,published_tag1,published_key0,published_key1;
    wire offer_camera=nr_busy ? frame[4] : i_frame[4];
    wire mirror_match=offer_camera ?
        (backend_offer_frame==published_frame1 && backend_offer_tag==published_tag1 && backend_offer_key==published_key1) :
        (backend_offer_frame==published_frame0 && backend_offer_tag==published_tag0 && backend_offer_key==published_key0);
    assign o_offer_valid=backend_offer_valid && mirror_match && o_nr_history_valid[offer_camera];
    assign o_backend_offer_valid=backend_offer_valid;
    assign o_offer_frame=backend_offer_frame;assign o_offer_tag=backend_offer_tag;assign o_offer_key=backend_offer_key;
    assign o_start_ready=rst_n && o_reset_done && nr_start_ready && backend_plan_ready && !i_cancel;
    wire start_fire=i_start_valid && o_start_ready;
    wire plan_fire=nr_plan_valid && backend_plan_ready;
    reg planned,aborted,user_canceled,backend_aborted;
    reg [7:0] backend_error;
    wire backend_fault;
    wire [7:0] backend_fault_code;
    wire nr_result_valid,backend_publish_ready;
    wire source_failure_event;
    wire abort_event=nr_busy && !nr_result_valid && (i_cancel || backend_fault || source_failure_event);
    wire abort_active=!nr_result_valid && (aborted || abort_event);
    assign o_busy=nr_busy || backend_busy;
    assign o_abort_request=aborted || abort_event;

    wire [95:0] raw_rgb,h_rgb;
    wire raw_valid,raw_ready,h_valid,nr_h_ready;
    wire [3:0] h_keep;
    wire h_sof,h_eol,h_last;
    wire [31:0] h_index;
    wire [63:0] h_tag;
    wire backend_read_quiet,nr_source_ready,nr_motion_ready;
    // These independent discard sinks are armed by the actual cancel/fault
    // event. Every presented item is still retired by its own handshake.
    assign s_ready=rst_n && nr_busy && !nr_result_valid && (abort_active || nr_source_ready);
    assign motion_ready=rst_n && nr_busy && !nr_result_valid && (abort_active || nr_motion_ready);
    wire h_ready=abort_active || nr_h_ready;
    assign o_read_quiescent=backend_read_quiet && i_source_read_quiescent;

    wire history_status_valid,history_status_ready,history_status_ok;
    wire [383:0] history_status_frame,read_frame;
    wire [63:0] history_status_tag,history_status_key,read_tag,read_key;
    wire [7:0] history_status_error;
    wire history_status_match=history_status_frame==read_frame && history_status_tag==history_tag && history_status_key==key;
    wire nr_history_status_ready;
    assign history_status_ready=history_status_match ? nr_history_status_ready : 1'b1;
    wire fence_valid,fence_ready,fence_ok;
    wire [383:0] fence_frame;
    wire [63:0] fence_tag,fence_key;
    wire [7:0] fence_error;
    wire [31:0] fence_pixels;
    wire ack_valid,ack_ready,ack_ok;
    wire [383:0] ack_frame;
    wire [63:0] ack_tag,ack_key;
    wire [7:0] ack_error;
    wire [31:0] ack_pixels;
    wire nr_frame_status_ready;
    wire source_status_match=i_frame_status_frame==frame && i_frame_status_tag==tag && i_frame_status_key==key;
    assign o_frame_status_ready=rst_n && nr_busy && !nr_result_valid &&
        (!source_status_match || nr_frame_status_ready);
    // A real failed source terminal can close a prefix without another LAST.
    // Unmatched terminal identity is consumed as stale and cannot abort it.
    assign source_failure_event=i_frame_status_valid && o_frame_status_ready &&
        source_status_match && !i_frame_status_ok;
    wire nr_result_ok,nr_result_current_ok,nr_result_commit;
    wire [7:0] nr_result_error;
    reg original_result_sealed,original_current_ok;
    // Only this rendezvous can consume either final owner. In particular, the
    // backend cannot switch banks while external RESULT is held.
    assign m_result_valid=nr_result_valid && original_result_sealed && (!planned || backend_publish_ready);
    wire result_fire=m_result_valid && m_result_ready;
    wire nr_result_ready=m_result_ready && original_result_sealed && (!planned || backend_publish_ready);
    wire backend_publish_valid=planned && result_fire;
    assign m_result_ok=nr_result_ok;
    assign m_result_nr_current_ok=nr_result_current_ok;
    assign m_result_history_commit=nr_result_commit;
    assign m_result_error=backend_aborted && !user_canceled ? backend_error : nr_result_error;

    reg [15:0] source_x,source_y;
    reg [31:0] source_groups,source_pixels,output_pixels,raw_pixels;
    reg source_bad,source_complete,source_status_seen,source_status_ok;
    wire source_fire=s_valid && s_ready;
    wire source_row_last={1'b0,source_x}+17'd4>={1'b0,frame[220:205]};
    wire source_frame_last=source_row_last && source_y==frame[236:221]-16'd1;
    wire [16:0] source_remaining={1'b0,frame[220:205]}-{1'b0,source_x};
    wire [3:0] expected_keep=!source_row_last || source_remaining>=4 ? 4'hf :
        source_remaining==3 ? 4'h7 : source_remaining==2 ? 4'h3 : 4'h1;
    wire source_good=s_tag==tag && s_index==source_groups && s_keep==expected_keep &&
        s_sof==(source_groups==0) && s_eol==source_row_last && s_last==source_frame_last && !source_complete;
    wire [2:0] source_lanes={2'd0,s_keep[0]}+{2'd0,s_keep[1]}+{2'd0,s_keep[2]}+{2'd0,s_keep[3]};
    wire [2:0] output_lanes={2'd0,m_keep[0]}+{2'd0,m_keep[1]}+{2'd0,m_keep[2]}+{2'd0,m_keep[3]};
    // Original source qualification is deliberately separate from the frozen
    // NR product/current diagnostics. Fault-discard still validates every item.
    wire original_source_good=source_status_seen && source_status_ok && source_complete &&
        !source_bad && !user_canceled && i_source_read_quiescent;
    assign m_result_current_ok=original_current_ok;
    assign m_result_input_pixels=source_pixels;
    assign m_result_output_pixels=output_pixels;
    assign m_result_raw_pixels=raw_pixels;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            planned<=0;aborted<=0;user_canceled<=0;backend_aborted<=0;backend_error<=0;
            source_x<=0;source_y<=0;source_groups<=0;source_pixels<=0;output_pixels<=0;raw_pixels<=0;
            source_bad<=0;source_complete<=0;source_status_seen<=0;source_status_ok<=0;
            original_result_sealed<=0;original_current_ok<=0;
            published_frame0<=0;published_frame1<=0;published_tag0<=0;published_tag1<=0;published_key0<=0;published_key1<=0;
        end else begin
            if(start_fire)begin
                planned<=0;aborted<=0;user_canceled<=0;backend_aborted<=0;backend_error<=0;
                source_x<=0;source_y<=0;source_groups<=0;source_pixels<=0;output_pixels<=0;raw_pixels<=0;
                source_bad<=0;source_complete<=0;source_status_seen<=0;source_status_ok<=0;
                original_result_sealed<=0;original_current_ok<=0;
            end
            if(nr_result_valid && !original_result_sealed)begin
                original_result_sealed<=1;original_current_ok<=original_source_good;
            end
            if(plan_fire)planned<=1;
            if(abort_event)begin
                aborted<=1;if(i_cancel)user_canceled<=1;
                if(backend_fault && !backend_aborted)begin backend_aborted<=1;backend_error<=backend_fault_code;end
            end
            if(source_fire)begin
                source_groups<=source_groups+32'd1;source_pixels<=source_pixels+source_lanes;
                if(!source_good)source_bad<=1;
                if(source_row_last)begin source_x<=0;source_y<=source_y+16'd1;end else source_x<=source_x+16'd4;
                if(source_frame_last && source_good)source_complete<=1;
            end
            if(i_frame_status_valid && o_frame_status_ready && source_status_match)begin
                source_status_seen<=1;source_status_ok<=i_frame_status_ok;
                if(!i_frame_status_ok)source_bad<=1;
            end
            if(m_valid && m_ready)output_pixels<=output_pixels+output_lanes;
            if(raw_valid && raw_ready)raw_pixels<=raw_pixels+output_lanes;
            if(result_fire)begin
                planned<=0;aborted<=0;original_result_sealed<=0;
                if(nr_result_commit)begin
                    if(m_result_frame[4])begin published_frame1<=m_result_frame;published_tag1<=m_result_tag;published_key1<=m_result_key;end
                    else begin published_frame0<=m_result_frame;published_tag0<=m_result_tag;published_key0<=m_result_key;end
                end
            end
        end
    end

    preprocess_temporal_nr4 #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080)) u_nr (
        .clk(clk),.rst_n(rst_n),.i_start_valid(i_start_valid && o_start_ready),.o_start_ready(nr_start_ready),
        .i_frame(i_frame),.i_tag(i_tag),.i_pipeline_key(i_pipeline_key),.i_enable(i_enable),.i_motion_guard(i_motion_guard),
        .i_history_reset(i_history_reset),.i_third_enable(1'b0),
        .i_history_available(o_offer_valid && backend_offer_key==i_pipeline_key),
        .i_history_frame(backend_offer_frame),.i_history_tag(backend_offer_tag),
        .i_motion_qualified(i_motion_qualified),.i_motion_current_tag(i_motion_current_tag),.i_motion_history_tag(i_motion_history_tag),
        .m_plan_valid(nr_plan_valid),.m_plan_ready(backend_plan_ready),.o_frame(frame),.o_tag(tag),.o_pipeline_key(key),
        .o_history_tag(history_tag),.o_history_selected(o_history_selected),
        .s_rgb(s_rgb),.s_keep(s_keep),.s_sof(s_sof),.s_eol(s_eol),.s_last(s_last),.s_valid(s_valid && !abort_active),
        .s_ready(nr_source_ready),.s_tag(s_tag),.s_index(s_index),
        .h_rgb(h_rgb),.h_keep(h_keep),.h_sof(h_sof),.h_eol(h_eol),.h_last(h_last),.h_valid(h_valid && !abort_active),
        .h_ready(nr_h_ready),.h_tag(h_tag),.h_index(h_index),
        .motion_confidence(motion_confidence),.motion_lane_valid(motion_lane_valid),.motion_keep(motion_keep),
        .motion_sof(motion_sof),.motion_eol(motion_eol),.motion_last(motion_last),.motion_valid(motion_valid && !abort_active),
        .motion_ready(nr_motion_ready),.motion_current_tag(motion_current_tag),.motion_history_tag(motion_history_tag),.motion_index(motion_index),
        .h2_rgb(96'd0),.h2_keep(4'd0),.h2_sof(1'b0),.h2_eol(1'b0),.h2_last(1'b0),.h2_valid(1'b0),.h2_ready(),.h2_tag(64'd0),.h2_index(32'd0),
        .m_rgb(m_rgb),.m_valid(m_valid),.m_ready(m_ready),.m_history_raw(raw_rgb),.m_history_filtered(),.m_history_valid(raw_valid),.m_history_ready(raw_ready),
        .m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_index(m_index),.m_tag(m_tag),
        .i_frame_status_valid(i_frame_status_valid && source_status_match),.o_frame_status_ready(nr_frame_status_ready),
        .i_frame_status_tag(i_frame_status_tag),.i_frame_status_ok(i_frame_status_ok),
        .i_history_status_valid(history_status_valid && history_status_match),.o_history_status_ready(nr_history_status_ready),
        .i_history_status_tag(history_status_tag),.i_history_status_ok(history_status_ok),.i_abort(abort_active),.i_read_quiescent(o_read_quiescent),
        .m_write_status_valid(fence_valid),.m_write_status_ready(fence_ready),.m_write_status_tag(fence_tag),.m_write_status_key(fence_key),
        .m_write_status_frame(fence_frame),.m_write_status_ok(fence_ok),.m_write_status_error(fence_error),.m_write_status_pixels(fence_pixels),
        .i_write_ack_valid(ack_valid),.o_write_ack_ready(ack_ready),.i_write_ack_tag(ack_tag),.i_write_ack_key(ack_key),
        .i_write_ack_frame(ack_frame),.i_write_ack_ok(ack_ok),.i_write_ack_error(ack_error),
        .m_result_valid(nr_result_valid),.m_result_ready(nr_result_ready),.m_result_tag(m_result_tag),.m_result_key(m_result_key),
        .m_result_frame(m_result_frame),.m_result_ok(nr_result_ok),.m_result_current_ok(nr_result_current_ok),
        .m_result_history_commit(nr_result_commit),.m_result_error(nr_result_error),.o_busy(nr_busy),.o_history_valid(o_nr_history_valid),
        .i_debug_enable(1'b0),.i_debug_snapshot(1'b0),.o_debug_frames(),.o_debug_history_used(),.o_debug_fallback_lanes(),.o_debug_stale_tokens(),
        .o_first_fault_valid(),.o_first_fault_code(),.o_first_fault_tag(),.o_first_fault_index());

    temporal_history_store4 #(.AXI_ID(AXI_ID)) u_store (
        .i_clk(clk),.i_rst_n(rst_n),.i_ddr_reset_done(i_ddr_reset_done),.o_reset_done(o_reset_done),
        .i_offer_camera(offer_camera),.o_offer_valid(backend_offer_valid),.o_offer_frame(backend_offer_frame),.o_offer_tag(backend_offer_tag),.o_offer_key(backend_offer_key),
        .i_plan_valid(nr_plan_valid),.o_plan_ready(backend_plan_ready),.i_plan_frame(frame),.i_plan_tag(tag),.i_plan_key(key),
        .i_plan_history_selected(o_history_selected),.i_plan_history_tag(history_tag),
        .s_rgb(raw_rgb),.s_keep(m_keep),.s_sof(m_sof),.s_eol(m_eol),.s_last(m_last),.s_valid(raw_valid),.s_index(m_index),.s_tag(m_tag),.s_ready(raw_ready),
        .h_rgb(h_rgb),.h_keep(h_keep),.h_sof(h_sof),.h_eol(h_eol),.h_last(h_last),.h_valid(h_valid),.h_index(h_index),.h_tag(h_tag),.h_ready(h_ready),
        .o_read_frame(read_frame),.o_read_tag(read_tag),.o_read_key(read_key),.o_read_quiescent(backend_read_quiet),
        .m_history_status_valid(history_status_valid),.m_history_status_ready(history_status_ready),.m_history_status_frame(history_status_frame),
        .m_history_status_tag(history_status_tag),.m_history_status_key(history_status_key),.m_history_status_ok(history_status_ok),.m_history_status_error(history_status_error),
        .i_fence_valid(fence_valid),.o_fence_ready(fence_ready),.i_fence_frame(fence_frame),.i_fence_tag(fence_tag),.i_fence_key(fence_key),
        .i_fence_ok(fence_ok),.i_fence_error(fence_error),.i_fence_pixels(fence_pixels),
        .m_ack_valid(ack_valid),.m_ack_ready(ack_ready),.m_ack_frame(ack_frame),.m_ack_tag(ack_tag),.m_ack_key(ack_key),.m_ack_ok(ack_ok),.m_ack_error(ack_error),.m_ack_pixels(ack_pixels),
        .i_publish_valid(backend_publish_valid),.o_publish_ready(backend_publish_ready),.i_publish_frame(m_result_frame),.i_publish_tag(m_result_tag),.i_publish_key(m_result_key),
        .i_publish_ok(nr_result_ok),.i_publish_commit(nr_result_commit),.i_cancel(abort_active),
        .o_busy(backend_busy),.o_fault(backend_fault),.o_error(backend_fault_code),.o_active_banks(o_active_banks),.o_pinned_banks(o_pinned_banks),.o_candidate_bank(),
        .i_debug_clear(i_debug_clear),.o_aw_count(o_aw_count),.o_w_count(o_w_count),.o_b_count(o_b_count),.o_ar_count(o_ar_count),.o_r_count(o_r_count),.o_commit_count(o_commit_count),.o_fault_count(),
        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),.m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
endmodule
