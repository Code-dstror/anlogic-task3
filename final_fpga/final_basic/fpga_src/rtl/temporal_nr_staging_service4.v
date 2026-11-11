`timescale 1ns / 1ps

// One physical original-RGB backend; F39 raw output is a checked completion sink.
module temporal_nr_staging_service4 #(
    parameter integer EXTERNAL_FIFO_ENABLE=0,
    parameter integer BORROW_JOB_CONTEXT=0
) (
    input wire i_external_fifo_reset_done,
    output wire [146:0] q_cw_source_data,output wire q_cw_source_valid,input wire q_cw_source_ready,
    input wire [146:0] q_cw_sink_data,input wire q_cw_sink_valid,output wire q_cw_sink_ready,
    input wire [9:0] q_cw_available,
    output wire [146:0] q_cr_source_data,output wire q_cr_source_valid,input wire q_cr_source_ready,
    input wire [146:0] q_cr_sink_data,input wire q_cr_sink_valid,output wire q_cr_sink_ready,
    input wire [9:0] q_cr_available,
    output wire [146:0] q_hr_source_data,output wire q_hr_source_valid,input wire q_hr_source_ready,
    input wire [146:0] q_hr_sink_data,input wire q_hr_sink_valid,output wire q_hr_sink_ready,
    input wire [9:0] q_hr_available,
    output wire o_write_quiescent,
    input wire clk,rst_n,i_ddr_reset_done,output wire o_reset_done,
    input wire i_capture_valid,output wire o_capture_ready,
    input wire [383:0] i_capture_frame,input wire [63:0] i_capture_tag,i_capture_key,i_capture_aux,
    // Optional same-domain parent owner: {aux,key,tag,frame}, resident for the
    // complete CAPTURE -> RESULT/FAULT lifetime, including all held outputs.
    input wire [575:0] i_job_context,
    input wire [95:0] s_rgb,input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_last,s_valid,output wire s_ready,
    input wire [31:0] s_index,input wire [63:0] s_tag,
    input wire i_source_status_valid,output wire o_source_status_ready,
    input wire [383:0] i_source_status_frame,
    input wire [63:0] i_source_status_tag,i_source_status_key,i_source_status_aux,
    input wire i_source_status_ok,input wire [7:0] i_source_status_error,
    input wire [31:0] i_source_status_pixels,input wire i_source_read_quiescent,
    output wire m_capture_ack_valid,input wire m_capture_ack_ready,
    output wire [383:0] m_capture_ack_frame,
    output wire [63:0] m_capture_ack_tag,m_capture_ack_key,m_capture_ack_aux,
    output wire m_capture_ack_ok,output wire [7:0] m_capture_ack_error,
    output wire [31:0] m_capture_ack_pixels,
    input wire i_process_valid,output wire o_process_ready,
    input wire [383:0] i_process_frame,input wire [63:0] i_process_tag,i_process_key,i_process_aux,
    input wire i_enable,i_history_reset,input wire [7:0] i_motion_guard,
    input wire i_motion_qualified,input wire [63:0] i_motion_current_tag,i_motion_history_tag,
    input wire [7:0] motion_confidence,input wire [3:0] motion_lane_valid,motion_keep,
    input wire motion_sof,motion_eol,motion_last,motion_valid,output wire motion_ready,
    input wire [63:0] motion_current_tag,motion_history_tag,input wire [31:0] motion_index,
    input wire i_motion_read_quiescent,
    output wire [95:0] m_rgb,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,input wire m_ready,
    output wire [31:0] m_index,output wire [63:0] m_tag,
    output wire m_filtered_fence_valid,input wire m_filtered_fence_ready,
    output wire [383:0] m_filtered_fence_frame,
    output wire [63:0] m_filtered_fence_tag,m_filtered_fence_key,m_filtered_fence_aux,
    output reg m_filtered_fence_ok,output reg [7:0] m_filtered_fence_error,
    output reg [31:0] m_filtered_fence_pixels,
    input wire i_filtered_ack_valid,output wire o_filtered_ack_ready,
    input wire [383:0] i_filtered_ack_frame,
    input wire [63:0] i_filtered_ack_tag,i_filtered_ack_key,i_filtered_ack_aux,
    input wire i_filtered_ack_ok,input wire [7:0] i_filtered_ack_error,
    input wire [31:0] i_filtered_ack_pixels,input wire i_filtered_read_quiescent,
    input wire i_cancel,
    output wire m_result_valid,input wire m_result_ready,
    output wire [383:0] m_result_frame,output wire [63:0] m_result_tag,m_result_key,m_result_aux,
    output wire m_result_ok,m_result_current_ok,m_result_capture_ok,m_result_history_commit,
    output wire [7:0] m_result_error,
    output wire [31:0] m_result_capture_pixels,m_result_input_pixels,m_result_output_pixels,m_result_raw_pixels,
    output wire o_offer_valid,o_backend_offer_valid,
    output wire [383:0] o_offer_frame,output wire [63:0] o_offer_tag,o_offer_key,o_offer_aux,
    output wire o_history_selected,o_busy,o_abort_request,o_read_quiescent,o_quarantined,
    output wire [1:0] o_nr_history_valid,output wire [3:0] o_active_banks,o_pinned_banks,
    output reg [31:0] o_stale_control_count,
    output wire [31:0] o_aw_count,o_w_count,o_b_count,o_ar_count,o_r_count,o_commit_count,
    output wire [3:0] m_axi_awid,m_axi_arid,
    output wire [27:0] m_axi_awaddr,m_axi_araddr,output wire [7:0] m_axi_awlen,m_axi_arlen,
    output wire [2:0] m_axi_awsize,m_axi_arsize,output wire [1:0] m_axi_awburst,m_axi_arburst,
    output wire m_axi_awvalid,m_axi_arvalid,input wire m_axi_awready,m_axi_arready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,m_axi_rid,input wire [1:0] m_axi_bresp,m_axi_rresp,
    input wire m_axi_bvalid,m_axi_rlast,m_axi_rvalid,output wire m_axi_bready,m_axi_rready,
    input wire [127:0] m_axi_rdata
);
    localparam [2:0] IDLE=0,CAPTURE=1,WAIT_PROCESS=2,PROCESS=3,RESULT=4,FAULT=5;
    localparam [7:0] E_OBLIGATION=32,E_FILTERED=33;
    reg [2:0] state;
    reg [383:0] frame_snapshot,old_frame,published_frame0,published_frame1;
    reg [63:0] tag_snapshot,key_snapshot,aux_snapshot,old_tag,old_key;
    wire [383:0] frame=BORROW_JOB_CONTEXT!=0 ? i_job_context[383:0] : frame_snapshot;
    wire [63:0] tag=BORROW_JOB_CONTEXT!=0 ? i_job_context[447:384] : tag_snapshot;
    wire [63:0] pipeline_key=BORROW_JOB_CONTEXT!=0 ? i_job_context[511:448] : key_snapshot;
    wire [63:0] aux=BORROW_JOB_CONTEXT!=0 ? i_job_context[575:512] : aux_snapshot;
    reg [63:0] published_tag0,published_tag1,published_key0,published_key1,published_aux0,published_aux1;
    reg capture_saved,capture_ok,aborted,planned,stage_started,identity_lost,local_bad;
    reg [7:0] capture_error,local_error;
    reg backend_error_seen;reg [7:0] backend_error;
    reg [31:0] capture_pixels,input_pixels,output_pixels,raw_pixels,input_groups,raw_groups;
    reg [15:0] raw_x,raw_y;
    reg c_seen,h_seen,c_ok,h_ok;
    reg fence_pending,fence_sent,filtered_ack_seen,filtered_ack_ok,filtered_quiet;
    reg [7:0] filtered_ack_error;
    reg nr_ack_valid,nr_ack_sent,nr_ack_ok;
    reg [7:0] nr_ack_error;

    wire stage_capture_ready,stage_process_ready,stage_publish_ready,stage_busy,stage_fault,stage_quarantined;
    wire [7:0] stage_error;
    wire nr_start_ready,nr_busy,nr_plan_valid,nr_result_valid,nr_result_ok,nr_result_current_ok,nr_result_commit;
    wire [7:0] nr_result_error;
    wire nr_s_ready,nr_h_ready,nr_motion_ready,nr_frame_status_ready,nr_history_status_ready,nr_ack_ready;
    wire stage_quiet,c_quiet,h_quiet;
    wire backend_offer_valid;wire [383:0] backend_offer_frame;
    wire [63:0] backend_offer_tag,backend_offer_key;
    wire offer_camera=state==IDLE ? i_capture_frame[4] : frame[4];
    wire mirror_match=offer_camera ?
        (backend_offer_frame==published_frame1 && backend_offer_tag==published_tag1 && backend_offer_key==published_key1) :
        (backend_offer_frame==published_frame0 && backend_offer_tag==published_tag0 && backend_offer_key==published_key0);
    assign o_offer_valid=backend_offer_valid && mirror_match && o_nr_history_valid[offer_camera];
    assign o_backend_offer_valid=backend_offer_valid;
    assign o_offer_frame=backend_offer_frame;assign o_offer_tag=backend_offer_tag;assign o_offer_key=backend_offer_key;
    assign o_offer_aux=offer_camera ? published_aux1 : published_aux0;
    assign o_capture_ready=rst_n && state==IDLE && stage_capture_ready && nr_start_ready && !i_cancel;
    wire capture_fire=i_capture_valid && o_capture_ready;
    wire process_match=i_process_frame==frame && i_process_tag==tag && i_process_key==pipeline_key && i_process_aux==aux;
    assign o_process_ready=rst_n && state==WAIT_PROCESS && nr_start_ready && !o_quarantined;
    wire process_control_fire=i_process_valid && o_process_ready;
    wire process_fire=process_control_fire && process_match;
    assign o_busy=state!=IDLE || stage_busy || nr_busy;
    assign o_quarantined=stage_quarantined || identity_lost || state==FAULT;

    wire source_match=i_source_status_frame==frame && i_source_status_tag==tag &&
        i_source_status_key==pipeline_key && i_source_status_aux==aux;
    wire stage_fence_ready,stage_ack_valid,stage_ack_ready,stage_ack_ok;
    wire [383:0] stage_ack_frame;wire [63:0] stage_ack_tag,stage_ack_key;
    wire [7:0] stage_ack_error;wire [31:0] stage_ack_pixels;
    assign o_source_status_ready=rst_n && state==CAPTURE && (!source_match || stage_fence_ready);
    assign m_capture_ack_valid=stage_ack_valid && state==CAPTURE;
    assign stage_ack_ready=m_capture_ack_ready && state==CAPTURE;
    assign m_capture_ack_frame=stage_ack_frame;assign m_capture_ack_tag=stage_ack_tag;assign m_capture_ack_key=stage_ack_key;
    assign m_capture_ack_aux=aux;assign m_capture_ack_ok=stage_ack_ok;
    assign m_capture_ack_error=stage_ack_error;assign m_capture_ack_pixels=stage_ack_pixels;
    wire capture_ack_fire=m_capture_ack_valid && m_capture_ack_ready;
    wire capture_ack_match=stage_ack_frame==frame && stage_ack_tag==tag && stage_ack_key==pipeline_key;

    wire [95:0] c_rgb,h_rgb,raw_rgb;
    wire [3:0] c_keep,h_keep;wire c_sof,c_eol,c_last,c_valid,c_ready,h_sof,h_eol,h_last,h_valid,h_ready;
    wire [31:0] c_index,h_index;wire [63:0] c_tag,h_tag;
    wire c_status_valid,h_status_valid,c_status_ready,h_status_ready,c_status_ok,h_status_ok,h_skipped;
    wire [383:0] c_status_frame,h_status_frame;
    wire [63:0] c_status_tag,h_status_tag,c_status_key,h_status_key;
    wire [7:0] c_status_error,h_status_error;wire [31:0] c_status_groups,h_status_groups;
    wire c_status_match=c_status_frame==frame && c_status_tag==tag && c_status_key==pipeline_key;
    wire h_status_match=h_status_frame==old_frame && h_status_tag==old_tag && h_status_key==old_key;
    wire c_status_good=c_status_ok && c_status_error==0 && c_status_groups==input_groups && input_pixels==capture_pixels;
    wire h_status_good=h_status_ok && h_status_error==0 &&
        (h_skipped ? h_status_groups==0 : h_status_groups==input_groups);
    assign c_status_ready=rst_n && stage_started && !c_seen &&
        (!c_status_match || nr_frame_status_ready || (nr_result_valid && !planned));
    assign h_status_ready=rst_n && stage_started && !h_seen &&
        (!h_status_match || !o_history_selected || nr_history_status_ready || (nr_result_valid && !planned));
    wire c_status_fire=c_status_valid && c_status_ready;
    wire h_status_fire=h_status_valid && h_status_ready;
    wire raw_valid;wire raw_ready=rst_n && state==PROCESS;
    wire raw_fire=raw_valid && raw_ready;
    wire raw_row_last={1'b0,raw_x}+17'd4>={1'b0,frame[220:205]};
    wire raw_frame_last=raw_row_last && raw_y==frame[236:221]-16'd1;
    wire [16:0] raw_remaining={1'b0,frame[220:205]}-{1'b0,raw_x};
    wire [3:0] raw_expected_keep=!raw_row_last || raw_remaining>=4 ? 4'hf :
        raw_remaining==3 ? 4'h7 : raw_remaining==2 ? 4'h3 : 4'h1;
    wire raw_good=m_tag==tag && m_index==raw_groups && m_keep==raw_expected_keep &&
        m_sof==(raw_groups==0) && m_eol==raw_row_last && m_last==raw_frame_last;
    wire [2:0] current_lanes={2'd0,c_keep[0]}+{2'd0,c_keep[1]}+{2'd0,c_keep[2]}+{2'd0,c_keep[3]};
    wire [2:0] output_lanes={2'd0,m_keep[0]}+{2'd0,m_keep[1]}+{2'd0,m_keep[2]}+{2'd0,m_keep[3]};
    wire nr_fence_valid,nr_fence_ok;wire [7:0] nr_fence_error;
    wire [383:0] nr_fence_frame;wire [63:0] nr_fence_tag,nr_fence_key;wire [31:0] nr_fence_pixels;
    wire nr_fence_ready=!fence_pending && !fence_sent && state==PROCESS;
    wire nr_fence_fire=nr_fence_valid && nr_fence_ready;
    wire write_obligation_good=capture_saved && capture_ok && nr_fence_frame==frame &&
        nr_fence_tag==tag && nr_fence_key==pipeline_key && nr_fence_pixels==capture_pixels &&
        input_pixels==capture_pixels && raw_pixels==capture_pixels && output_pixels==capture_pixels && !local_bad;
    wire filtered_source_good=write_obligation_good && c_seen && c_ok && h_seen &&
        (!o_history_selected || h_ok) && !aborted && !i_cancel &&
        (nr_fence_ok || nr_fence_error==8'd10);
    assign m_filtered_fence_valid=rst_n && fence_pending;
    assign m_filtered_fence_frame=frame;assign m_filtered_fence_tag=tag;
    assign m_filtered_fence_key=pipeline_key;assign m_filtered_fence_aux=aux;
    wire filtered_fence_fire=m_filtered_fence_valid && m_filtered_fence_ready;
    wire filtered_ack_match=i_filtered_ack_frame==frame && i_filtered_ack_tag==tag &&
        i_filtered_ack_key==pipeline_key && i_filtered_ack_aux==aux;
    assign o_filtered_ack_ready=rst_n && state==PROCESS &&
        (!filtered_ack_match || filtered_ack_seen || (fence_sent && i_filtered_read_quiescent));
    wire filtered_ack_fire=i_filtered_ack_valid && o_filtered_ack_ready;
    wire filtered_ack_good=i_filtered_ack_pixels==m_filtered_fence_pixels &&
        i_filtered_ack_ok && i_filtered_ack_error==0 && m_filtered_fence_ok;
    wire filtered_failure=filtered_ack_fire && filtered_ack_match && !filtered_ack_seen && !filtered_ack_good;
    wire count_failure=(raw_fire && !raw_good) || (nr_fence_fire && !write_obligation_good && capture_ok && !aborted);
    wire abort_event=state!=IDLE && !nr_result_valid &&
        (i_cancel || stage_fault || local_bad || (capture_saved && !capture_ok) || filtered_failure || count_failure);
    wire abort_active=!nr_result_valid && (aborted || abort_event);
    assign o_abort_request=state!=IDLE && (aborted || abort_event);
    assign c_ready=abort_active || (nr_result_valid && !planned) || nr_s_ready;
    assign h_ready=abort_active || (nr_result_valid && !planned) || nr_h_ready;
    assign motion_ready=rst_n && state==PROCESS && !nr_result_valid && (abort_active || nr_motion_ready);
    assign o_read_quiescent=stage_quiet && i_motion_read_quiescent;
    wire no_plan_cleanup=nr_result_valid && !stage_started;
    wire stage_process_valid=nr_plan_valid || no_plan_cleanup;
    wire stage_process_fire=stage_process_valid && stage_process_ready;
    wire plan_fire=nr_plan_valid && stage_process_ready;
    wire backend_cancel=!nr_result_valid && (aborted || abort_event);
    wire stage_publish_fire;
    assign m_result_valid=rst_n && state==RESULT && nr_result_valid && stage_publish_ready;
    wire result_fire=m_result_valid && m_result_ready;
    assign m_result_ok=nr_result_ok;assign m_result_current_ok=nr_result_current_ok;
    assign m_result_capture_ok=capture_ok;assign m_result_history_commit=nr_result_commit;
    assign m_result_error=backend_error_seen ? backend_error :
        filtered_ack_seen && !filtered_ack_ok ? filtered_ack_error : nr_result_error;
    assign m_result_aux=aux;
    assign m_result_capture_pixels=capture_pixels;assign m_result_input_pixels=input_pixels;
    assign m_result_output_pixels=output_pixels;assign m_result_raw_pixels=raw_pixels;
    wire stale_control=(i_source_status_valid && o_source_status_ready && !source_match) ||
        (process_control_fire && !process_match) || (filtered_ack_fire && (!filtered_ack_match || filtered_ack_seen));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;frame_snapshot<=0;tag_snapshot<=0;key_snapshot<=0;aux_snapshot<=0;
            old_frame<=0;old_tag<=0;old_key<=0;
            capture_saved<=0;capture_ok<=0;capture_error<=0;capture_pixels<=0;backend_error_seen<=0;backend_error<=0;
            aborted<=0;planned<=0;stage_started<=0;identity_lost<=0;local_bad<=0;local_error<=0;
            input_pixels<=0;output_pixels<=0;raw_pixels<=0;input_groups<=0;raw_groups<=0;raw_x<=0;raw_y<=0;
            c_seen<=0;h_seen<=0;c_ok<=0;h_ok<=0;fence_pending<=0;fence_sent<=0;
            filtered_ack_seen<=0;filtered_ack_ok<=0;filtered_ack_error<=0;filtered_quiet<=0;
            nr_ack_valid<=0;nr_ack_sent<=0;nr_ack_ok<=0;nr_ack_error<=0;
            m_filtered_fence_ok<=0;m_filtered_fence_error<=0;m_filtered_fence_pixels<=0;
            published_frame0<=0;published_frame1<=0;published_tag0<=0;published_tag1<=0;
            published_key0<=0;published_key1<=0;published_aux0<=0;published_aux1<=0;o_stale_control_count<=0;
        end else begin
            if(stale_control && !(&o_stale_control_count)) o_stale_control_count<=o_stale_control_count+1'b1;
            if(abort_event)aborted<=1;
            if(abort_event && stage_fault && !backend_error_seen)begin backend_error_seen<=1;backend_error<=stage_error;end
            if(count_failure)begin local_bad<=1;local_error<=E_OBLIGATION;end
            if(c_status_fire)begin
                c_seen<=1;c_ok<=c_status_match && c_status_good;
                if(!c_status_match)identity_lost<=1;
            end
            if(h_status_fire)begin
                h_seen<=1;h_ok<=h_status_match && h_status_good;
                if(!h_status_match)identity_lost<=1;
            end
            if(stage_process_fire)stage_started<=1;
            if(plan_fire)planned<=1;
            if(c_valid && c_ready)begin input_pixels<=input_pixels+current_lanes;input_groups<=input_groups+32'd1;end
            if(m_valid && m_ready)output_pixels<=output_pixels+output_lanes;
            if(raw_fire)begin
                raw_pixels<=raw_pixels+output_lanes;raw_groups<=raw_groups+32'd1;
                if(raw_row_last)begin raw_x<=0;raw_y<=raw_y+16'd1;end else raw_x<=raw_x+16'd4;
            end
            if(nr_fence_fire)begin
                fence_pending<=1;m_filtered_fence_pixels<=output_pixels;
                m_filtered_fence_ok<=filtered_source_good;
                m_filtered_fence_error<=filtered_source_good ? 8'd0 :
                    !capture_ok ? capture_error : local_bad ? local_error : nr_fence_error!=0 ? nr_fence_error : E_FILTERED;
            end
            if(nr_result_valid && !planned && stage_started && c_seen && h_seen && stage_quiet && !fence_pending && !fence_sent)begin
                fence_pending<=1;m_filtered_fence_ok<=0;m_filtered_fence_error<=nr_result_error;
                m_filtered_fence_pixels<=output_pixels;
            end
            if(filtered_fence_fire)begin fence_pending<=0;fence_sent<=1;end
            if(filtered_ack_fire && filtered_ack_match && !filtered_ack_seen)begin
                filtered_ack_seen<=1;filtered_ack_ok<=filtered_ack_good;filtered_quiet<=i_filtered_read_quiescent;
                filtered_ack_error<=filtered_ack_good ? 8'd0 : i_filtered_ack_error!=0 ? i_filtered_ack_error : E_FILTERED;
            end
            if(planned && fence_sent && filtered_ack_seen && filtered_quiet && c_seen && h_seen &&
                stage_quiet && i_motion_read_quiescent && !nr_ack_valid && !nr_ack_sent)begin
                nr_ack_valid<=1;nr_ack_ok<=capture_ok && filtered_ack_ok && !aborted && !local_bad;
                nr_ack_error<=!capture_ok ? capture_error : local_bad ? local_error : !filtered_ack_ok ? filtered_ack_error : 8'd0;
            end
            if(nr_ack_valid && nr_ack_ready)begin nr_ack_valid<=0;nr_ack_sent<=1;end
            case(state)
                IDLE: if(capture_fire)begin
                    if(BORROW_JOB_CONTEXT==0)begin
                        frame_snapshot<=i_capture_frame;tag_snapshot<=i_capture_tag;
                        key_snapshot<=i_capture_key;aux_snapshot<=i_capture_aux;
                    end
                    old_frame<=backend_offer_frame;old_tag<=backend_offer_tag;old_key<=backend_offer_key;
                    capture_saved<=0;capture_ok<=0;capture_error<=0;capture_pixels<=0;backend_error_seen<=0;backend_error<=0;
                    aborted<=0;planned<=0;stage_started<=0;local_bad<=0;local_error<=0;
                    input_pixels<=0;output_pixels<=0;raw_pixels<=0;input_groups<=0;raw_groups<=0;raw_x<=0;raw_y<=0;
                    c_seen<=0;h_seen<=0;c_ok<=0;h_ok<=0;fence_pending<=0;fence_sent<=0;
                    filtered_ack_seen<=0;filtered_ack_ok<=0;filtered_ack_error<=0;filtered_quiet<=0;
                    nr_ack_valid<=0;nr_ack_sent<=0;nr_ack_ok<=0;nr_ack_error<=0;state<=CAPTURE;
                end
                CAPTURE: if(capture_ack_fire)begin
                    capture_saved<=1;capture_ok<=stage_ack_ok && capture_ack_match;
                    capture_error<=stage_ack_error;capture_pixels<=stage_ack_pixels;
                    if(!capture_ack_match)identity_lost<=1;
                    state<=WAIT_PROCESS;
                end
                WAIT_PROCESS: if(process_fire)state<=PROCESS;
                PROCESS: if(nr_result_valid && stage_publish_ready && c_seen && h_seen &&
                    filtered_ack_seen && filtered_quiet && i_motion_read_quiescent && !o_quarantined)state<=RESULT;
                RESULT: if(result_fire)begin
                    if(nr_result_commit)begin
                        if(frame[4])begin published_frame1<=frame;published_tag1<=tag;published_key1<=pipeline_key;published_aux1<=aux;end
                        else begin published_frame0<=frame;published_tag0<=tag;published_key0<=pipeline_key;published_aux0<=aux;end
                    end
                    state<=IDLE;
                end
                FAULT: begin end
                default:begin state<=FAULT;identity_lost<=1;end
            endcase
        end
    end

    preprocess_temporal_nr4 #(.MAX_WIDTH(1920),.MAX_HEIGHT(1080)) u_nr(
        .clk(clk),.rst_n(rst_n),.i_start_valid(process_fire),.o_start_ready(nr_start_ready),
        .i_frame(frame),.i_tag(tag),.i_pipeline_key(pipeline_key),.i_enable(i_enable),.i_motion_guard(i_motion_guard),
        .i_history_reset(i_history_reset),.i_third_enable(1'b0),
        .i_history_available(o_offer_valid && backend_offer_key==pipeline_key),.i_history_frame(old_frame),.i_history_tag(old_tag),
        .i_motion_qualified(i_motion_qualified),.i_motion_current_tag(i_motion_current_tag),.i_motion_history_tag(i_motion_history_tag),
        .m_plan_valid(nr_plan_valid),.m_plan_ready(stage_process_ready),.o_frame(),.o_tag(),.o_pipeline_key(),
        .o_history_tag(),.o_history_selected(o_history_selected),
        .s_rgb(c_rgb),.s_keep(c_keep),.s_sof(c_sof),.s_eol(c_eol),.s_last(c_last),.s_valid(c_valid && !abort_active),
        .s_ready(nr_s_ready),.s_tag(c_tag),.s_index(c_index),
        .h_rgb(h_rgb),.h_keep(h_keep),.h_sof(h_sof),.h_eol(h_eol),.h_last(h_last),.h_valid(h_valid && !abort_active),
        .h_ready(nr_h_ready),.h_tag(h_tag),.h_index(h_index),
        .motion_confidence(motion_confidence),.motion_lane_valid(motion_lane_valid),.motion_keep(motion_keep),
        .motion_sof(motion_sof),.motion_eol(motion_eol),.motion_last(motion_last),.motion_valid(motion_valid && !abort_active),
        .motion_ready(nr_motion_ready),.motion_current_tag(motion_current_tag),.motion_history_tag(motion_history_tag),.motion_index(motion_index),
        .h2_rgb(96'd0),.h2_keep(4'd0),.h2_sof(1'b0),.h2_eol(1'b0),.h2_last(1'b0),.h2_valid(1'b0),.h2_ready(),.h2_tag(64'd0),.h2_index(32'd0),
        .m_rgb(m_rgb),.m_valid(m_valid),.m_ready(m_ready),.m_history_raw(raw_rgb),.m_history_filtered(),.m_history_valid(raw_valid),.m_history_ready(raw_ready),
        .m_keep(m_keep),.m_sof(m_sof),.m_eol(m_eol),.m_last(m_last),.m_index(m_index),.m_tag(m_tag),
        .i_frame_status_valid(c_status_valid && c_status_match && !c_seen),.o_frame_status_ready(nr_frame_status_ready),
        .i_frame_status_tag(c_status_tag),.i_frame_status_ok(c_status_good),
        .i_history_status_valid(h_status_valid && h_status_match && !h_seen && o_history_selected),.o_history_status_ready(nr_history_status_ready),
        .i_history_status_tag(h_status_tag),.i_history_status_ok(h_status_good),.i_abort(abort_active),.i_read_quiescent(o_read_quiescent && filtered_quiet),
        .m_write_status_valid(nr_fence_valid),.m_write_status_ready(nr_fence_ready),.m_write_status_tag(nr_fence_tag),.m_write_status_key(nr_fence_key),
        .m_write_status_frame(nr_fence_frame),.m_write_status_ok(nr_fence_ok),.m_write_status_error(nr_fence_error),.m_write_status_pixels(nr_fence_pixels),
        .i_write_ack_valid(nr_ack_valid),.o_write_ack_ready(nr_ack_ready),.i_write_ack_tag(tag),.i_write_ack_key(pipeline_key),
        .i_write_ack_frame(frame),.i_write_ack_ok(nr_ack_ok),.i_write_ack_error(nr_ack_error),
        .m_result_valid(nr_result_valid),.m_result_ready(result_fire),.m_result_tag(m_result_tag),.m_result_key(m_result_key),.m_result_frame(m_result_frame),
        .m_result_ok(nr_result_ok),.m_result_current_ok(nr_result_current_ok),.m_result_history_commit(nr_result_commit),.m_result_error(nr_result_error),
        .o_busy(nr_busy),.o_history_valid(o_nr_history_valid),.i_debug_enable(1'b0),.i_debug_snapshot(1'b0),
        .o_debug_frames(),.o_debug_history_used(),.o_debug_fallback_lanes(),.o_debug_stale_tokens(),
        .o_first_fault_valid(),.o_first_fault_code(),.o_first_fault_tag(),.o_first_fault_index());

    temporal_rgb_staging_store4 #(.EXTERNAL_FIFO_ENABLE(EXTERNAL_FIFO_ENABLE)) u_store(
        .i_external_fifo_reset_done(i_external_fifo_reset_done),
        .q_cw_source_data(q_cw_source_data),.q_cw_source_valid(q_cw_source_valid),.q_cw_source_ready(q_cw_source_ready),
        .q_cw_sink_data(q_cw_sink_data),.q_cw_sink_valid(q_cw_sink_valid),.q_cw_sink_ready(q_cw_sink_ready),.q_cw_available(q_cw_available),
        .q_cr_source_data(q_cr_source_data),.q_cr_source_valid(q_cr_source_valid),.q_cr_source_ready(q_cr_source_ready),
        .q_cr_sink_data(q_cr_sink_data),.q_cr_sink_valid(q_cr_sink_valid),.q_cr_sink_ready(q_cr_sink_ready),.q_cr_available(q_cr_available),
        .q_hr_source_data(q_hr_source_data),.q_hr_source_valid(q_hr_source_valid),.q_hr_source_ready(q_hr_source_ready),
        .q_hr_sink_data(q_hr_sink_data),.q_hr_sink_valid(q_hr_sink_valid),.q_hr_sink_ready(q_hr_sink_ready),.q_hr_available(q_hr_available),
        .o_write_quiescent(o_write_quiescent),
        .i_clk(clk),.i_rst_n(rst_n),.i_ddr_reset_done(i_ddr_reset_done),.o_reset_done(o_reset_done),
        .i_offer_camera(offer_camera),.o_offer_valid(backend_offer_valid),.o_offer_frame(backend_offer_frame),.o_offer_tag(backend_offer_tag),.o_offer_key(backend_offer_key),
        .i_capture_valid(capture_fire),.o_capture_ready(stage_capture_ready),.i_capture_frame(i_capture_frame),.i_capture_tag(i_capture_tag),.i_capture_key(i_capture_key),
        .s_rgb(s_rgb),.s_keep(s_keep),.s_sof(s_sof),.s_eol(s_eol),.s_last(s_last),.s_valid(s_valid),.s_ready(s_ready),.s_index(s_index),.s_tag(s_tag),
        .i_fence_valid(i_source_status_valid && source_match && state==CAPTURE),.o_fence_ready(stage_fence_ready),
        .i_fence_frame(i_source_status_frame),.i_fence_tag(i_source_status_tag),.i_fence_key(i_source_status_key),
        .i_fence_ok(i_source_status_ok),.i_fence_error(i_source_status_error),.i_fence_pixels(i_source_status_pixels),.i_source_read_quiescent(i_source_read_quiescent),
        .m_capture_ack_valid(stage_ack_valid),.m_capture_ack_ready(stage_ack_ready),.m_capture_ack_frame(stage_ack_frame),
        .m_capture_ack_tag(stage_ack_tag),.m_capture_ack_key(stage_ack_key),.m_capture_ack_ok(stage_ack_ok),.m_capture_ack_error(stage_ack_error),.m_capture_ack_pixels(stage_ack_pixels),
        .i_process_valid(stage_process_valid),.o_process_ready(stage_process_ready),.i_process_frame(frame),.i_process_tag(tag),.i_process_key(pipeline_key),
        .i_process_history_selected(nr_plan_valid && o_history_selected),.i_process_history_frame(old_frame),.i_process_history_tag(old_tag),.i_process_history_key(old_key),
        .c_rgb(c_rgb),.c_keep(c_keep),.c_sof(c_sof),.c_eol(c_eol),.c_last(c_last),.c_valid(c_valid),.c_ready(c_ready),.c_index(c_index),.c_tag(c_tag),
        .h_rgb(h_rgb),.h_keep(h_keep),.h_sof(h_sof),.h_eol(h_eol),.h_last(h_last),.h_valid(h_valid),.h_ready(h_ready),.h_index(h_index),.h_tag(h_tag),
        .m_current_status_valid(c_status_valid),.m_current_status_ready(c_status_ready),.m_current_status_frame(c_status_frame),.m_current_status_tag(c_status_tag),.m_current_status_key(c_status_key),
        .m_current_status_ok(c_status_ok),.m_current_status_error(c_status_error),.m_current_status_groups(c_status_groups),
        .m_history_status_valid(h_status_valid),.m_history_status_ready(h_status_ready),.m_history_status_frame(h_status_frame),.m_history_status_tag(h_status_tag),.m_history_status_key(h_status_key),
        .m_history_status_ok(h_status_ok),.m_history_status_skipped(h_skipped),.m_history_status_error(h_status_error),.m_history_status_groups(h_status_groups),
        .o_current_read_quiescent(c_quiet),.o_history_read_quiescent(h_quiet),.o_read_quiescent(stage_quiet),
        .i_publish_valid(result_fire),.o_publish_ready(stage_publish_ready),.i_publish_frame(m_result_frame),.i_publish_tag(m_result_tag),.i_publish_key(m_result_key),
        .i_publish_ok(nr_result_ok),.i_publish_commit(nr_result_commit),.i_cancel(backend_cancel || no_plan_cleanup),
        .o_publish_fire(stage_publish_fire),.o_publish_committed(),.o_busy(stage_busy),.o_fault(stage_fault),.o_quarantined(stage_quarantined),.o_error(stage_error),
        .o_active_banks(o_active_banks),.o_pinned_banks(o_pinned_banks),.o_candidate_bank(),.o_read_owned(),.o_stale_control_count(),
        .o_aw_count(o_aw_count),.o_w_count(o_w_count),.o_b_count(o_b_count),.o_ar_count(o_ar_count),.o_r_count(o_r_count),.o_commit_count(o_commit_count),
        .m_axi_awid(m_axi_awid),.m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
endmodule
