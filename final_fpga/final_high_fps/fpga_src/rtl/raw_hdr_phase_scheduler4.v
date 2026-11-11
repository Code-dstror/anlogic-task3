`timescale 1ns/1ps
`default_nettype none
// One F42 owner and one processing CDC serve RAW10 or derived HDR RAW14.
module raw_hdr_phase_scheduler4 #(parameter integer NORMAL_REPLAY_ENABLE=0, parameter integer NORMAL_SINGLE_MEMBER=0) (
    input wire clk, input wire rst_n,
    input wire i_job_valid, output wire o_job_ready,
    input wire [1:0] i_job_kind,
    input wire [63:0] i_job_id,i_pair_id,i_job_lease0,i_job_lease1,
    input wire [383:0] i_job_frame0,i_job_frame1,
    output wire m_member_valid, input wire m_member_ready,
    output wire [383:0] m_member_frame,
    output wire [63:0] m_member_lease,m_member_job_id,m_member_pair_id,
    output wire m_member_index,
    output wire o_req_valid, input wire i_req_ready,
    output wire o_req_private, output wire [2:0] o_req_op,
    output wire o_req_camera, output wire [1:0] o_req_slot,
    output wire [31:0] o_req_generation,o_req_session,o_req_offset,o_req_length,
    output wire [63:0] o_req_lease,o_req_job_id,
    input wire i_rsp_valid, output wire o_rsp_ready,
    input wire [3:0] i_rsp_code, input wire i_rsp_camera,
    input wire [1:0] i_rsp_slot,
    input wire [31:0] i_rsp_generation,i_rsp_session,i_rsp_sequence,i_rsp_epoch,
    input wire i_native_done,i_native_error,
    input wire [63:0] i_native_job_id, input wire i_native_member_index,
    input wire i_processing_done,i_processing_error,
    input wire [63:0] i_processing_job_id, input wire i_processing_member_index,
    input wire i_cancel,
    output wire o_processing_cancel_valid, input wire i_processing_cancel_ready,
    output wire [383:0] o_processing_cancel_frame,
    output wire [63:0] o_processing_cancel_lease,o_processing_cancel_job_id,o_processing_cancel_pair_id,
    output wire o_processing_cancel_member_index,
    output wire o_retire_valid, input wire i_retire_ready,
    output wire [31:0] o_retire_session, output wire [63:0] o_retire_job_id,
    output wire o_retire_cancelled, output wire o_retire_read_quiescent,
    input wire i_retire_done,i_retire_error,
    output wire o_busy, output wire o_fault, output wire [3:0] o_error_code,
    output wire o_stale_completion,
    // HDR mode is the accepted owner CONFIG, held through true job retirement.
    input wire i_hdr_mode,i_public_read_quiescent,i_product_quiescent,i_hdr_reset_done,i_read_quiescent,
    input wire i_hard_fault,i_hdr_fault,i_hdr_read_quiescent,
    output wire o_hdr_phase_request,o_hdr_phase_owned,
    output wire o_hdr_context_valid,input wire i_hdr_context_ready,
    output wire o_hdr_start_valid,input wire i_hdr_start_ready,
    output wire o_hdr_cancel_valid,input wire i_hdr_cancel_ready,
    output wire o_hdr_result_transport_enable,
    input wire i_hdr_result_valid,i_hdr_result_ready,i_hdr_result_ok,
    input wire [7:0] i_hdr_result_error,
    output wire [63:0] o_hdr_long_tag,o_hdr_short_tag,
    output wire [3:0] o_diag_scheduler_state
);
    wire  normal_o_job_ready;
    wire  normal_m_member_valid;
    wire [383:0] normal_m_member_frame;
    wire [63:0] normal_m_member_lease;
    wire [63:0] normal_m_member_job_id;
    wire [63:0] normal_m_member_pair_id;
    wire  normal_m_member_index;
    wire  normal_o_req_valid;
    wire  normal_o_req_private;
    wire [2:0] normal_o_req_op;
    wire  normal_o_req_camera;
    wire [1:0] normal_o_req_slot;
    wire [31:0] normal_o_req_generation;
    wire [31:0] normal_o_req_session;
    wire [31:0] normal_o_req_offset;
    wire [31:0] normal_o_req_length;
    wire [63:0] normal_o_req_lease;
    wire [63:0] normal_o_req_job_id;
    wire  normal_o_rsp_ready;
    wire  normal_o_processing_cancel_valid;
    wire [383:0] normal_o_processing_cancel_frame;
    wire [63:0] normal_o_processing_cancel_lease;
    wire [63:0] normal_o_processing_cancel_job_id;
    wire [63:0] normal_o_processing_cancel_pair_id;
    wire  normal_o_processing_cancel_member_index;
    wire  normal_o_retire_valid;
    wire [31:0] normal_o_retire_session;
    wire [63:0] normal_o_retire_job_id;
    wire  normal_o_retire_cancelled;
    wire  normal_o_retire_read_quiescent;
    wire  normal_o_busy;
    wire  normal_o_fault;
    wire [3:0] normal_o_error_code;
    wire  normal_o_stale_completion;

    localparam [3:0] IDLE=0,COMMAND=1,CONTEXT=2,START=3,RUN=4,
        WAIT_PRODUCT=5,OWNER_REQUEST=6,OWNER_RESPONSE=7,FAULT=8;
    reg [3:0] state;
    reg hdr_owned,hdr_fault,context_accepted,processing_seen,processing_failed;
    reg reader_seen,reader_good,failed,cancel_pending,retire_cancelled,stale;
    wire tag_available=i_job_id!=0;
    wire whole_quiet=i_hdr_read_quiescent && i_read_quiescent &&
        i_public_read_quiescent && i_product_quiescent;
    wire processing_match=hdr_owned && context_accepted &&
        i_processing_job_id==i_job_id && !i_processing_member_index;
    wire result_fire=state==RUN && i_hdr_result_valid && i_hdr_result_ready;
    wire processing_fire=i_processing_done && processing_match;
    wire sealed=state==OWNER_REQUEST || state==OWNER_RESPONSE || state==FAULT;
    // Descriptors/leases/job are borrowed from the actual F42 owner. That
    // owner cannot replace them before its successful RELEASE_JOB response.
    assign o_hdr_long_tag=i_job_id;
    assign o_hdr_short_tag=i_job_id;
    assign o_hdr_phase_request=i_hdr_mode && (i_job_valid || hdr_owned);
    assign o_hdr_phase_owned=hdr_owned;
    assign o_hdr_context_valid=hdr_owned && state==CONTEXT;
    assign o_hdr_start_valid=hdr_owned && state==START;
    assign o_hdr_cancel_valid=hdr_owned && state==RUN && cancel_pending;
    assign o_hdr_result_transport_enable=hdr_owned && state==RUN;
    assign o_job_ready=state==IDLE && !hdr_fault && !normal_o_busy &&
        (i_hdr_mode ? i_hdr_reset_done && !i_hdr_fault && !i_hard_fault && tag_available &&
            i_public_read_quiescent && i_product_quiescent && i_read_quiescent : normal_o_job_ready);
    assign m_member_valid=hdr_owned ? state==COMMAND : normal_m_member_valid;
    assign m_member_frame=hdr_owned ? i_job_frame0 : normal_m_member_frame;
    assign m_member_lease=hdr_owned ? i_job_lease0 : normal_m_member_lease;
    assign m_member_job_id=hdr_owned ? i_job_id : normal_m_member_job_id;
    assign m_member_pair_id=hdr_owned ? i_pair_id : normal_m_member_pair_id;
    assign m_member_index=hdr_owned ? 1'b0 : normal_m_member_index;
    assign o_req_valid=!hdr_owned && normal_o_req_valid;
    assign o_req_private=normal_o_req_private;assign o_req_op=normal_o_req_op;
    assign o_req_camera=normal_o_req_camera;assign o_req_slot=normal_o_req_slot;
    assign o_req_generation=normal_o_req_generation;assign o_req_session=normal_o_req_session;
    assign o_req_offset=normal_o_req_offset;assign o_req_length=normal_o_req_length;
    assign o_req_lease=normal_o_req_lease;assign o_req_job_id=normal_o_req_job_id;
    assign o_rsp_ready=!hdr_owned && normal_o_rsp_ready;
    assign o_processing_cancel_valid=!hdr_owned && normal_o_processing_cancel_valid;
    assign o_processing_cancel_frame=normal_o_processing_cancel_frame;
    assign o_processing_cancel_lease=normal_o_processing_cancel_lease;
    assign o_processing_cancel_job_id=normal_o_processing_cancel_job_id;
    assign o_processing_cancel_pair_id=normal_o_processing_cancel_pair_id;
    assign o_processing_cancel_member_index=normal_o_processing_cancel_member_index;
    assign o_retire_valid=hdr_owned ? state==OWNER_REQUEST : normal_o_retire_valid;
    assign o_retire_session=hdr_owned ? i_job_frame0[76:45] : normal_o_retire_session;
    assign o_retire_job_id=hdr_owned ? i_job_id : normal_o_retire_job_id;
    assign o_retire_cancelled=hdr_owned ? retire_cancelled : normal_o_retire_cancelled;
    assign o_retire_read_quiescent=hdr_owned ?
        (state==OWNER_REQUEST || state==OWNER_RESPONSE) && whole_quiet : normal_o_retire_read_quiescent;
    assign o_busy=hdr_owned || hdr_fault || state==FAULT || normal_o_busy;
    assign o_fault=hdr_fault || normal_o_fault;
    assign o_error_code=hdr_fault ? 4'hf : hdr_owned ? i_hdr_result_error[3:0] : normal_o_error_code;
    assign o_stale_completion=stale || normal_o_stale_completion;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;hdr_owned<=0;hdr_fault<=0;context_accepted<=0;
            processing_seen<=0;processing_failed<=0;reader_seen<=0;reader_good<=0;
            failed<=0;cancel_pending<=0;retire_cancelled<=0;stale<=0;
        end else begin
            stale<=0;
            if(hdr_owned && !sealed)begin
                if(i_cancel)begin cancel_pending<=1;failed<=1;end
                if(o_hdr_cancel_valid && i_hdr_cancel_ready)cancel_pending<=0;
                if(i_processing_done || i_processing_error)begin
                    if(!processing_match)stale<=1;
                    else if(i_processing_error)begin processing_failed<=1;failed<=1;end
                    if(processing_fire)processing_seen<=1;
                end
                if(i_native_done || i_native_error)stale<=1;
                if(result_fire)begin
                    reader_seen<=1;reader_good<=i_hdr_result_ok;
                    if(!i_hdr_result_ok)failed<=1;
                end
            end
            // A hard fault quarantines the real refs. It never synthesizes a
            // SOURCE, RETIRE, processing completion or timeout-based release.
            if((hdr_owned || (i_hdr_mode && i_job_valid)) && (i_hard_fault || i_hdr_fault))
                hdr_fault<=1;
            // Held command/context/START promises still drain to the existing
            // fault-aware consumer. The same hard fault must reach the reader
            // so it cannot start a new FETCH. Quarantine blocks ref retirement.
            case(state)
                IDLE:if(i_hdr_mode && i_job_valid && o_job_ready)begin
                    hdr_owned<=1;context_accepted<=0;processing_seen<=0;processing_failed<=0;
                    reader_seen<=0;reader_good<=0;failed<=i_cancel;cancel_pending<=i_cancel;
                    retire_cancelled<=i_cancel;
                    if(i_job_kind!=0 || i_job_lease0==0 || i_job_lease1==0 ||
                        i_job_lease0==i_job_lease1)begin hdr_fault<=1;state<=FAULT;end
                    else state<=i_cancel ? OWNER_REQUEST : COMMAND;
                end
                COMMAND:if(m_member_ready)begin context_accepted<=1;state<=CONTEXT;end
                CONTEXT:if(i_hdr_context_ready)state<=START;
                START:if(i_hdr_start_ready)state<=RUN;
                RUN:if(result_fire)state<=WAIT_PRODUCT;
                WAIT_PRODUCT:if(!hdr_fault && !i_hard_fault && !i_hdr_fault &&
                    reader_seen && (processing_seen || processing_fire) && whole_quiet)begin
                    retire_cancelled<=failed || !reader_good || processing_failed ||
                        (processing_fire && i_processing_error) || i_cancel;
                    state<=OWNER_REQUEST;
                end
                OWNER_REQUEST:if(i_retire_ready)state<=OWNER_RESPONSE;
                OWNER_RESPONSE:if(i_retire_done)begin
                    if(i_retire_error)begin hdr_fault<=1;state<=FAULT;end
                    else begin hdr_owned<=0;context_accepted<=0;state<=IDLE;end
                end
                FAULT:state<=FAULT;
                default:begin hdr_fault<=1;state<=FAULT;end
            endcase
        end
    end

    generate if(NORMAL_REPLAY_ENABLE!=0)begin:g_normal_replay
    // stereo_raw_owner holds its job descriptor until our real owner-retire
    // response completes; reuse it as the HDR path already reuses its owner.
    raw_pair_replay_scheduler #(.BORROW_CONTEXT(1)) u_normal(
        .o_diag_state(o_diag_scheduler_state),
        .clk(clk),
        .rst_n(rst_n),
        .i_job_valid(i_job_valid && !i_hdr_mode && !hdr_owned && state==IDLE && !hdr_fault),
        .o_job_ready(normal_o_job_ready),
        .i_job_kind(NORMAL_SINGLE_MEMBER!=0 ? 2'd1 : i_job_kind),
        .i_job_id(i_job_id),
        .i_pair_id(i_pair_id),
        .i_job_lease0(i_job_lease0),
        .i_job_lease1(i_job_lease1),
        .i_job_frame0(i_job_frame0),
        .i_job_frame1(i_job_frame1),
        .m_member_valid(normal_m_member_valid),
        .m_member_ready(m_member_ready),
        .m_member_frame(normal_m_member_frame),
        .m_member_lease(normal_m_member_lease),
        .m_member_job_id(normal_m_member_job_id),
        .m_member_pair_id(normal_m_member_pair_id),
        .m_member_index(normal_m_member_index),
        .o_req_valid(normal_o_req_valid),
        .i_req_ready(i_req_ready),
        .o_req_private(normal_o_req_private),
        .o_req_op(normal_o_req_op),
        .o_req_camera(normal_o_req_camera),
        .o_req_slot(normal_o_req_slot),
        .o_req_generation(normal_o_req_generation),
        .o_req_session(normal_o_req_session),
        .o_req_offset(normal_o_req_offset),
        .o_req_length(normal_o_req_length),
        .o_req_lease(normal_o_req_lease),
        .o_req_job_id(normal_o_req_job_id),
        .i_rsp_valid(i_rsp_valid),
        .o_rsp_ready(normal_o_rsp_ready),
        .i_rsp_code(i_rsp_code),
        .i_rsp_camera(i_rsp_camera),
        .i_rsp_slot(i_rsp_slot),
        .i_rsp_generation(i_rsp_generation),
        .i_rsp_session(i_rsp_session),
        .i_rsp_sequence(i_rsp_sequence),
        .i_rsp_epoch(i_rsp_epoch),
        .i_native_done(i_native_done && !hdr_owned),
        .i_native_error(i_native_error && !hdr_owned),
        .i_native_job_id(i_native_job_id),
        .i_native_member_index(i_native_member_index),
        .i_processing_done(i_processing_done && !hdr_owned),
        .i_processing_error(i_processing_error && !hdr_owned),
        .i_processing_job_id(i_processing_job_id),
        .i_processing_member_index(i_processing_member_index),
        .i_cancel(i_cancel && !hdr_owned),
        .o_processing_cancel_valid(normal_o_processing_cancel_valid),
        .i_processing_cancel_ready(i_processing_cancel_ready),
        .o_processing_cancel_frame(normal_o_processing_cancel_frame),
        .o_processing_cancel_lease(normal_o_processing_cancel_lease),
        .o_processing_cancel_job_id(normal_o_processing_cancel_job_id),
        .o_processing_cancel_pair_id(normal_o_processing_cancel_pair_id),
        .o_processing_cancel_member_index(normal_o_processing_cancel_member_index),
        .o_retire_valid(normal_o_retire_valid),
        .i_retire_ready(i_retire_ready),
        .o_retire_session(normal_o_retire_session),
        .o_retire_job_id(normal_o_retire_job_id),
        .o_retire_cancelled(normal_o_retire_cancelled),
        .o_retire_read_quiescent(normal_o_retire_read_quiescent),
        .i_retire_done(i_retire_done),
        .i_retire_error(i_retire_error),
        .o_busy(normal_o_busy),
        .o_fault(normal_o_fault),
        .o_error_code(normal_o_error_code),
        .o_stale_completion(normal_o_stale_completion)
    );
    end else begin:g_no_normal_replay
    assign o_diag_scheduler_state=4'd0;
    // This application profile stores only qualified HDR exposures. Ordinary
    // SDR remains live; there is no public or stored-MONO RAW read owner.
    assign normal_o_job_ready=0;
    assign normal_m_member_valid=0;
    assign normal_m_member_frame=0;
    assign normal_m_member_lease=0;
    assign normal_m_member_job_id=0;
    assign normal_m_member_pair_id=0;
    assign normal_m_member_index=0;
    assign normal_o_req_valid=0;
    assign normal_o_req_private=0;
    assign normal_o_req_op=0;
    assign normal_o_req_camera=0;
    assign normal_o_req_slot=0;
    assign normal_o_req_generation=0;
    assign normal_o_req_session=0;
    assign normal_o_req_offset=0;
    assign normal_o_req_length=0;
    assign normal_o_req_lease=0;
    assign normal_o_req_job_id=0;
    assign normal_o_rsp_ready=0;
    assign normal_o_processing_cancel_valid=0;
    assign normal_o_processing_cancel_frame=0;
    assign normal_o_processing_cancel_lease=0;
    assign normal_o_processing_cancel_job_id=0;
    assign normal_o_processing_cancel_pair_id=0;
    assign normal_o_processing_cancel_member_index=0;
    assign normal_o_retire_valid=0;
    assign normal_o_retire_session=0;
    assign normal_o_retire_job_id=0;
    assign normal_o_retire_cancelled=0;
    assign normal_o_retire_read_quiescent=0;
    assign normal_o_busy=0;
    assign normal_o_fault=0;
    assign normal_o_error_code=0;
    assign normal_o_stale_completion=0;

    end endgenerate

endmodule
`default_nettype wire
