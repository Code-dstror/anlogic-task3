`timescale 1ns / 1ps

// One pixel-domain member owner. Bulk pixels and command/result CDCs are external.
// A private write gets a non-reused tag; native sequence alone is insufficient.
module raw_pair_pixel_context #(
    parameter integer NATIVE_RESULT_ENABLE=0
) (
    input wire clk, rst_n,
    input wire i_pool_idle, i_admission_ready,
    input wire [577:0] s_command,
    input wire s_command_valid, output wire s_command_ready,
    input wire i_context_valid, output wire o_context_ready,
    input wire [383:0] i_context_frame,
    input wire [63:0] i_context_job_id, i_context_pair_id,
    input wire i_context_member_index, i_context_private,
    input wire i_native_job_start, i_store_start_fire, i_pipeline_error,
    // Optional true private replay boundary result, after its data/error FENCE.
    input wire i_native_result_valid,i_native_result_error,
    input wire [63:0] i_native_result_job_id,
    input wire i_native_result_member_index,
    // Actual final writer result: tag32/seq32/session32/epoch32/cam/ok/error8.
    input wire [146:0] s_write_result,
    input wire s_write_result_valid, output wire s_write_result_ready,
    output wire [146:0] m_processing_result,
    output wire m_processing_result_valid, input wire m_processing_result_ready,
    output wire [383:0] o_frame,
    output wire [63:0] o_lease, o_job_id, o_pair_id,
    output wire o_member_index,
    output wire [31:0] o_write_tag,
    output wire o_busy, o_context_owned,
    output wire o_protocol_fault,
    output reg [7:0] o_first_fault_code,
    output reg [31:0] o_stale_write_count, o_completed_count, o_cancelled_count,
    output reg [31:0] o_stale_native_count
);
    localparam [2:0] IDLE=0, WAIT_CONTEXT=1, ACTIVE=2, COMPLETE=3, FAULT=4;
    localparam [7:0] E_COMMAND=1, E_CONTEXT=2, E_ACTIVITY=3, E_WRITE=4,
                     E_TAG_EXHAUSTED=5, E_STATE=6, E_NATIVE_RESULT=7;
    reg [2:0] state, next_state;
    reg [576:0] member;
    reg [31:0] next_tag, member_tag;
    reg native_started, store_started, write_seen, failed, result_error;
    reg native_result_seen,native_result_failed;
    reg [7:0] fault_event;
    wire command_fire=s_command_valid && s_command_ready;
    wire is_cancel=s_command[577];
    wire same_member=s_command[576:0]==member;
    wire member_valid=s_command[511:448]!=0 && s_command[447:384]!=0 &&
        s_command[76:45]!=0 && s_command[383:367]==0 &&
        s_command[12:5]<4 && s_command[220:205]!=0 && s_command[236:221]!=0;
    wire context_match=i_context_private && i_context_frame==member[383:0] &&
        i_context_job_id==member[511:448] && i_context_pair_id==member[575:512] &&
        i_context_member_index==member[576];
    wire context_fire=i_context_valid && o_context_ready;
    wire cancel_offer=s_command_valid && is_cancel;
    wire write_fire=s_write_result_valid && s_write_result_ready;
    wire write_tag_match=s_write_result[31:0]==member_tag;
    wire write_identity_match=s_write_result[63:32]==member[108:77] &&
        s_write_result[95:64]==member[76:45] && s_write_result[127:96]==member[140:109] &&
        s_write_result[128]==member[4];
    wire write_well_formed=s_write_result[146:138]==0 &&
        (!s_write_result[129] || s_write_result[137:130]==0);
    wire accepted_write=write_fire && state==ACTIVE && write_tag_match &&
        write_identity_match && write_well_formed && (store_started || i_store_start_fire) && !write_seen;
    wire rejected_cancel=command_fire && is_cancel && state==WAIT_CONTEXT &&
        same_member && !native_started && !store_started && i_pool_idle;
    wire native_result_valid=NATIVE_RESULT_ENABLE!=0 && i_native_result_valid;
    wire native_result_owned=native_result_valid && state==ACTIVE &&
        i_native_result_job_id==member[511:448];
    wire native_result_match=native_result_owned &&
        i_native_result_member_index==member[576] && !native_result_seen;
    wire native_finished=NATIVE_RESULT_ENABLE==0 || native_result_seen || native_result_match;
    wire finished_write=state==ACTIVE && i_pool_idle && native_started && store_started &&
        (write_seen || accepted_write) && native_finished;
    // A genuine failed source FENCE may precede its first pixel: no encoder
    // or writer ever started. Pool-idle must include every pending START/tail.
    wire finished_empty=state==ACTIVE && i_pool_idle && !native_started && !store_started &&
        !i_native_job_start && !i_store_start_fire &&
        ((native_result_seen && native_result_failed) ||
         (native_result_match && i_native_result_error));
    wire finished=finished_write || finished_empty;

    assign s_command_ready=rst_n && state!=FAULT &&
        (state==IDLE ? i_pool_idle && i_admission_ready :
         state==WAIT_CONTEXT && is_cancel && i_pool_idle);
    assign o_context_ready=rst_n && state==WAIT_CONTEXT && context_match &&
        i_pool_idle && i_admission_ready && !cancel_offer;
    assign s_write_result_ready=rst_n && state!=FAULT;
    assign m_processing_result_valid=rst_n && state==COMPLETE;
    assign m_processing_result={81'd0,result_error,member[576],member[511:448]};
    assign o_frame=member[383:0];
    assign o_lease=member[447:384];
    assign o_job_id=member[511:448];
    assign o_pair_id=member[575:512];
    assign o_member_index=member[576];
    assign o_write_tag=state==ACTIVE ? member_tag : 32'd0;
    assign o_busy=state!=IDLE;
    assign o_context_owned=state==ACTIVE;
    assign o_protocol_fault=state==FAULT;

    function [31:0] sat_inc;
        input [31:0] value;
        begin sat_inc=&value ? value : value+1'b1; end
    endfunction

    // Priority: protocol fault, exact rejection cancel, context, true completion.
    always @(*) begin
        next_state=state;
        fault_event=0;
        case(state)
            IDLE: if(command_fire) begin
                if(is_cancel || !member_valid) begin next_state=FAULT;fault_event=E_COMMAND;end
                else if(next_tag==0) begin next_state=FAULT;fault_event=E_TAG_EXHAUSTED;end
                else next_state=WAIT_CONTEXT;
            end
            WAIT_CONTEXT: begin
                if(i_context_valid && !context_match) begin next_state=FAULT;fault_event=E_CONTEXT;end
                else if(i_native_job_start || i_store_start_fire) begin next_state=FAULT;fault_event=E_ACTIVITY;end
                else if(command_fire) begin
                    if(!same_member || !is_cancel) begin next_state=FAULT;fault_event=E_COMMAND;end
                    else if(rejected_cancel) next_state=COMPLETE;
                end else if(context_fire) next_state=ACTIVE;
            end
            ACTIVE: begin
                if(native_result_owned && (!native_result_match ||
                    (!i_native_result_error && !(native_started || i_native_job_start)))) begin
                    next_state=FAULT;fault_event=E_NATIVE_RESULT;
                end else if(i_native_job_start && native_started) begin next_state=FAULT;fault_event=E_ACTIVITY;end
                else if(i_store_start_fire && (store_started || !(native_started || i_native_job_start))) begin
                    next_state=FAULT;fault_event=E_ACTIVITY;
                end else if(write_fire && write_tag_match &&
                    (!write_identity_match || !write_well_formed || write_seen ||
                     !(store_started || i_store_start_fire))) begin next_state=FAULT;fault_event=E_WRITE;end
                else if(finished) next_state=COMPLETE;
            end
            COMPLETE: if(m_processing_result_ready) next_state=IDLE;
            FAULT: next_state=FAULT;
            default: begin next_state=FAULT;fault_event=E_STATE;end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state<=IDLE;
        else state<=next_state;
    end

    // Ownership never clears on a timer or on an encoder/native EOF alone.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            member<=0;next_tag<=1;member_tag<=0;
            native_started<=0;store_started<=0;write_seen<=0;failed<=0;result_error<=0;
            native_result_seen<=0;native_result_failed<=0;
            o_first_fault_code<=0;o_stale_write_count<=0;o_completed_count<=0;o_cancelled_count<=0;
            o_stale_native_count<=0;
        end else begin
            if(fault_event!=0 && o_first_fault_code==0) o_first_fault_code<=fault_event;
            if(state==IDLE && command_fire && !is_cancel && member_valid && next_tag!=0) begin
                member<=s_command[576:0];member_tag<=next_tag;
                next_tag<=next_tag+1'b1;
                native_started<=0;store_started<=0;write_seen<=0;failed<=0;result_error<=0;
                native_result_seen<=0;native_result_failed<=0;
            end
            if(state==ACTIVE) begin
                if(i_native_job_start) native_started<=1;
                if(i_store_start_fire) store_started<=1;
                if(i_pipeline_error) failed<=1;
                if(native_result_match) begin
                    native_result_seen<=1;native_result_failed<=i_native_result_error;
                    if(i_native_result_error) failed<=1;
                end
                if(accepted_write) begin write_seen<=1;if(!s_write_result[129]) failed<=1;end
            end
            if(write_fire && (!write_tag_match || state!=ACTIVE)) o_stale_write_count<=sat_inc(o_stale_write_count);
            if(native_result_valid && !native_result_owned) o_stale_native_count<=sat_inc(o_stale_native_count);
            if(next_state==COMPLETE && state!=COMPLETE) begin
                result_error<=rejected_cancel || finished_empty || failed || i_pipeline_error ||
                    (native_result_match && i_native_result_error) ||
                    (accepted_write && !s_write_result[129]);
                if(rejected_cancel) o_cancelled_count<=sat_inc(o_cancelled_count);
            end
            if(state==COMPLETE && m_processing_result_ready) o_completed_count<=sat_inc(o_completed_count);
        end
    end
endmodule
