`timescale 1ns / 1ps

// Bind private RAW context to its real ACTIVE tag before admitting payload.
// SOURCE owns this frozen tuple through its handshake and physical tail drain.
module raw_private_jpeg_event_bridge (
    input wire clk, rst_n,
    input wire i_context_fire, i_context_private,
    input wire [383:0] i_context_frame,
    input wire [63:0] i_context_lease, i_context_job_id, i_context_pair_id,
    input wire i_context_member_index,
    output wire o_context_available, o_replay_payload_enable,
    input wire i_active_tuple_valid,
    input wire [383:0] i_active_frame,
    input wire [63:0] i_active_lease, i_active_job_id, i_active_pair_id,
    input wire i_active_member_index,
    input wire [63:0] i_active_write_tag,
    input wire i_processed_sof_fire, i_admission_take,
    input wire i_start_valid, i_start_ready, i_encoder_sof_fire,
    input wire i_status_valid, i_status_ready,
    input wire [31:0] i_status_id, input wire i_status_ok,
    input wire i_result_valid, i_result_ready,
    input wire [31:0] i_result_id, input wire i_result_ok,
    input wire i_raw_done, i_raw_error, i_raw_private,
    input wire [383:0] i_raw_frame,
    input wire [63:0] i_raw_job_id, i_raw_pair_id,
    input wire i_raw_member_index,
    input wire i_cancel, i_pipeline_error,
    input wire i_isp_idle, i_preprocess_idle, i_jpeg_idle,
    input wire i_isp_output_valid, i_preprocess_output_valid,
    input wire i_admission_active, i_admission_rgb_valid,
    output wire o_processing_sof, o_writer_start_fire, o_pool_idle,
    output wire o_writer_expected, o_processed_seen,
    output wire m_source_valid, input wire m_source_ready,
    output wire [383:0] m_source_frame,
    output wire [63:0] m_source_lease, m_source_job_id, m_source_pair_id,
    output wire m_source_member_index,
    output wire [63:0] m_source_write_tag,
    output wire m_source_error, o_source_no_writer,
    output wire o_busy, o_protocol_fault,
    output reg [7:0] o_first_fault_code,
    output reg [31:0] o_stale_raw_count, o_stale_status_count
);
    localparam [2:0] IDLE=0, WAIT_ACTIVE=1, OWNED=2,
        SOURCE_HELD=3, DRAIN=4, FAULT=5;
    localparam [7:0] E_CONTEXT=1, E_ACTIVE=2, E_ACTIVITY=3, E_RESULT=4, E_STATE=5;
    reg [2:0] state, next_state;
    reg [383:0] frame;
    reg [63:0] lease, job_id, pair_id, write_tag;
    reg member_index;
    reg processed_seen, admitted, start_offered, writer_started, encoder_started;
    reg raw_seen, failed, negative_result_seen, status_seen;
    reg source_error, source_no_writer;
    reg [7:0] fault_event;
    wire local_tail_quiet=i_isp_idle && i_preprocess_idle && i_jpeg_idle &&
        !i_isp_output_valid && !i_preprocess_output_valid &&
        !i_admission_active && !i_admission_rgb_valid && !i_start_valid &&
        !i_status_valid && !i_result_valid;
    wire active_match=i_active_frame==frame && i_active_lease==lease &&
        i_active_job_id==job_id && i_active_pair_id==pair_id &&
        i_active_member_index==member_index && i_active_write_tag!=0;
    wire raw_match=i_raw_private && i_raw_frame==frame && i_raw_job_id==job_id &&
        i_raw_pair_id==pair_id && i_raw_member_index==member_index;
    wire raw_owned=i_raw_done && (state==WAIT_ACTIVE || state==OWNED || state==SOURCE_HELD || state==DRAIN) && raw_match;
    wire start_fire=i_start_valid && i_start_ready;
    wire status_fire=i_status_valid && i_status_ready;
    wire result_fire=i_result_valid && i_result_ready;
    wire admission_now=admitted || (i_processed_sof_fire && i_admission_take);
    wire writer_now=writer_started || start_fire;
    wire encoder_now=encoder_started || i_encoder_sof_fire;
    wire status_match=state==OWNED && status_fire && i_status_id==frame[108:77] &&
        admission_now && writer_now && encoder_now && !status_seen;
    wire result_match=result_fire && (state==OWNED || state==SOURCE_HELD || state==DRAIN) &&
        i_result_id==frame[108:77] && writer_now && encoder_now;
    wire bad_now=failed || i_cancel || i_pipeline_error ||
        (raw_owned && i_raw_error) || (result_match && !i_result_ok);
    wire raw_finished=raw_seen || raw_owned;
    wire no_writer_now=!admission_now && !start_offered && !i_start_valid &&
        !writer_now && !encoder_now;
    wire empty_failure=state==OWNED && raw_finished && bad_now &&
        no_writer_now && local_tail_quiet;
    wire cancelled_status_failure=state==OWNED && raw_finished && bad_now &&
        (negative_result_seen || (result_match && !i_result_ok)) && local_tail_quiet;

    assign o_context_available=rst_n && state==IDLE && local_tail_quiet;
    assign o_replay_payload_enable=rst_n && state==OWNED;
    assign o_processing_sof=rst_n && state==OWNED && i_processed_sof_fire && i_admission_take;
    assign o_writer_start_fire=rst_n && state==OWNED && start_fire;
    assign o_pool_idle=rst_n && local_tail_quiet && !m_source_valid;
    assign o_writer_expected=admitted || start_offered || writer_started;
    assign o_processed_seen=processed_seen;
    assign m_source_valid=rst_n && state==SOURCE_HELD;
    assign m_source_frame=frame;
    assign m_source_lease=lease;
    assign m_source_job_id=job_id;
    assign m_source_pair_id=pair_id;
    assign m_source_member_index=member_index;
    assign m_source_write_tag=write_tag;
    assign m_source_error=source_error;
    assign o_source_no_writer=source_no_writer;
    assign o_busy=state!=IDLE;
    assign o_protocol_fault=state==FAULT;

    // A presented START remains external owned work even before its handshake.
    // The bridge observes those obligations; it never retracts its producer.
    always @(*) begin
        next_state=state;
        fault_event=0;
        if(i_context_fire && state!=IDLE) begin
            next_state=FAULT;fault_event=E_CONTEXT;
        end else case(state)
            IDLE: if(i_context_fire) begin
                if(!i_context_private || i_context_lease==0 || i_context_job_id==0 || !local_tail_quiet) begin
                    next_state=FAULT;fault_event=E_CONTEXT;
                end else next_state=WAIT_ACTIVE;
            end
            WAIT_ACTIVE: begin
                if(i_processed_sof_fire || i_admission_take || start_fire || i_encoder_sof_fire) begin
                    next_state=FAULT;fault_event=E_ACTIVITY;
                end else if(i_active_tuple_valid) begin
                    if(!active_match) begin next_state=FAULT;fault_event=E_ACTIVE;end
                    else next_state=OWNED;
                end
            end
            OWNED: begin
                if((i_admission_take && (!i_processed_sof_fire || admitted)) ||
                    (i_start_valid && !admission_now) || (start_fire && writer_started) ||
                    (i_encoder_sof_fire && (!writer_now || encoder_started))) begin
                    next_state=FAULT;fault_event=E_ACTIVITY;
                end else if(result_match && i_result_ok && !status_seen && !status_match) begin
                    next_state=FAULT;fault_event=E_RESULT;
                end else if(status_match || empty_failure || cancelled_status_failure)
                    next_state=SOURCE_HELD;
            end
            SOURCE_HELD: if(m_source_ready) next_state=DRAIN;
            DRAIN: if(local_tail_quiet && (raw_seen || raw_owned)) next_state=IDLE;
            FAULT: next_state=FAULT;
            default: begin next_state=FAULT;fault_event=E_STATE;end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state<=IDLE;
        else state<=next_state;
    end

    // Context/tag and SOURCE are scalar ownership records, not payload memory.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame<=0;lease<=0;job_id<=0;pair_id<=0;write_tag<=0;member_index<=0;
            processed_seen<=0;admitted<=0;start_offered<=0;writer_started<=0;encoder_started<=0;
            raw_seen<=0;failed<=0;negative_result_seen<=0;status_seen<=0;
            source_error<=0;source_no_writer<=0;
            o_first_fault_code<=0;o_stale_raw_count<=0;o_stale_status_count<=0;
        end else begin
            if(fault_event!=0 && o_first_fault_code==0) o_first_fault_code<=fault_event;
            if(state==IDLE && i_context_fire) begin
                frame<=i_context_frame;lease<=i_context_lease;job_id<=i_context_job_id;
                pair_id<=i_context_pair_id;member_index<=i_context_member_index;write_tag<=0;
                processed_seen<=0;admitted<=0;start_offered<=0;writer_started<=0;encoder_started<=0;
                raw_seen<=0;failed<=i_cancel || i_pipeline_error;
                negative_result_seen<=0;status_seen<=0;source_error<=0;source_no_writer<=0;
            end
            if(state==WAIT_ACTIVE && i_active_tuple_valid && active_match)
                write_tag<=i_active_write_tag;
            if(state==WAIT_ACTIVE || state==OWNED) begin
                if(i_cancel || i_pipeline_error) failed<=1;
            end
            if(raw_owned && !raw_seen) begin
                raw_seen<=1;
                if((state==WAIT_ACTIVE || state==OWNED) && i_raw_error) failed<=1;
            end
            if(i_raw_done && (!raw_owned || raw_seen) && !(&o_stale_raw_count))
                o_stale_raw_count<=o_stale_raw_count+1'b1;
            if(status_fire && !status_match && !(&o_stale_status_count))
                o_stale_status_count<=o_stale_status_count+1'b1;
            if(state==OWNED) begin
                if(i_processed_sof_fire) processed_seen<=1;
                if(i_admission_take) admitted<=1;
                if(i_start_valid) start_offered<=1;
                if(start_fire) writer_started<=1;
                if(i_encoder_sof_fire) encoder_started<=1;
                if(result_match && !i_result_ok) begin negative_result_seen<=1;failed<=1;end
                if(status_match) status_seen<=1;
                if(next_state==SOURCE_HELD) begin
                    source_error<=status_match ? (bad_now || !i_status_ok) : 1'b1;
                    source_no_writer<=no_writer_now;
                end
            end
        end
    end
endmodule
