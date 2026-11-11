// Single DFI metadata owner/scheduler composition; all payload lives elsewhere.
module raw_pair_job_service #(
    parameter integer PHYSICAL_MONO_CURRENT_ENABLE=0,
    parameter integer HDR_PROCESSING_ENABLE=0,
    parameter integer WIDTH=1920,
    parameter integer HEIGHT=1080,
    parameter integer STEREO_ENABLE=0
) (
    input wire i_stereo_mode,i_stereo_job_valid,i_stereo_empty,
    input wire [383:0] i_stereo_job_frame,
    input wire [63:0] i_stereo_job_lease,i_stereo_job_id,
    output wire o_stereo_job_ready,o_stereo_retire_valid,
    output wire [63:0] o_stereo_retire_job_id,
    input wire i_stereo_retire_ready,i_stereo_retire_done,i_stereo_retire_error,
    input wire i_identity_rst_n,
    input wire i_pair_valid,i_pair_bank,i_pair_empty,i_pair_fault,
    input wire [63:0] i_pair_id,output wire o_pair_ready,
    input wire i_pair_config_ready,i_pair_config_error,output wire o_pair_config_valid,
    output wire o_pair_release_valid,o_pair_release_bank,
    output wire [63:0] o_pair_release_id,input wire i_pair_release_ready,
    output wire o_pair_directory_valid,output wire [1:0] o_pair_directory_slot,
    input wire i_pair_directory_ready,
    input wire [31:0] s_pair_directory_data,input wire [3:0] s_pair_directory_word,
    input wire s_pair_directory_valid,s_pair_directory_last,output wire s_pair_directory_ready,
    input wire i_retire_inhibit,
    input wire clk, input wire rst_n,
    input wire [63:0] i_now,
    input wire i_config_valid, output wire o_config_ready,
    input wire [31:0] i_session, i_epoch, input wire [1:0] i_mode,
    input wire i_mono_enable,
    input wire [63:0] i_max_delta, input wire [31:0] i_max_wait, i_max_age,
    output wire o_config_done, o_config_error, o_config_busy,
    input wire i_commit_valid, output wire o_commit_ready,
    input wire [383:0] i_descriptor, input wire [63:0] i_lease,
    output wire o_commit_done, o_commit_error, o_commit_duplicate,
    output wire o_ref_valid, input wire i_ref_ready,
    output wire [1:0] o_ref_op, o_ref_mask,
    output wire [4:0] o_ref_reason, output wire o_ref_cancelled,
    output wire [383:0] o_ref_frame0, o_ref_frame1,
    output wire [63:0] o_ref_lease0, o_ref_lease1, o_ref_job_id,
    output wire m_member_valid, input wire m_member_ready,
    output wire [383:0] m_member_frame,
    output wire [63:0] m_member_lease, m_member_job_id, m_member_pair_id,
    output wire m_member_index,
    output wire o_req_valid, input wire i_req_ready,
    output wire o_req_private, output wire [2:0] o_req_op,
    output wire o_req_camera, output wire [1:0] o_req_slot,
    output wire [31:0] o_req_generation, o_req_session, o_req_offset, o_req_length,
    output wire [63:0] o_req_lease, o_req_job_id,
    input wire i_rsp_valid, output wire o_rsp_ready,
    input wire [3:0] i_rsp_code, input wire i_rsp_camera,
    input wire [1:0] i_rsp_slot,
    input wire [31:0] i_rsp_generation, i_rsp_session, i_rsp_sequence, i_rsp_epoch,
    input wire i_native_done, i_native_error,
    input wire [63:0] i_native_job_id, input wire i_native_member_index,
    input wire i_processing_done, i_processing_error,
    input wire [63:0] i_processing_job_id, input wire i_processing_member_index,
    input wire i_cancel, i_read_quiescent,
    output wire o_processing_cancel_valid, input wire i_processing_cancel_ready,
    output wire [383:0] o_processing_cancel_frame,
    output wire [63:0] o_processing_cancel_lease, o_processing_cancel_job_id, o_processing_cancel_pair_id,
    output wire o_processing_cancel_member_index,
    // Readonly observation of internal dispatch and retirement handshakes.
    output wire o_job_valid, o_job_ready, output wire [1:0] o_job_kind,
    output wire [63:0] o_job_id, o_pair_id, o_job_lease0, o_job_lease1,
    output wire [383:0] o_job_frame0, o_job_frame1,
    output wire o_retire_valid, o_retire_ready,
    output wire [31:0] o_retire_session, output wire [63:0] o_retire_job_id,
    output wire o_retire_cancelled, o_retire_read_quiescent, o_retire_done, o_retire_error,
    output wire o_owner_quiescent, o_owner_fault,
    output wire o_scheduler_busy, o_scheduler_fault,
    output wire [3:0] o_error_code, output wire o_stale_completion,
    output wire o_busy, o_fault, o_quiescent,
    // Optional HDR controls use the same held F42 owner and member CDC.
    input wire i_public_read_quiescent,i_product_quiescent,i_hdr_reset_done,
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
    localparam [2:0] D_IDLE=0,D_BEGIN=1,D_REQUEST=2,D_ASSEMBLE=3,D_JOB=4,D_ACTIVE=5;
    reg [2:0] dispatch_state;
    reg retired_pulse,config_done_pulse,dispatch_fault;
    reg owned_bank,release_pending,release_bank;
    reg [63:0] owned_pair_id,release_id;
    wire cache_begin_ready,cache_valid,cache_fault;
    wire [383:0] cache_frame;
    wire [63:0] cache_lease;
    wire release_fire=o_pair_release_valid && i_pair_release_ready;
    wire stereo_mode=STEREO_ENABLE!=0&&i_stereo_mode;
    assign o_stereo_job_ready=stereo_mode&&o_job_ready;
    assign o_stereo_retire_valid=stereo_mode&&o_retire_valid;
    assign o_stereo_retire_job_id=o_retire_job_id;
    assign o_pair_ready=!stereo_mode&&dispatch_state==D_IDLE && !cache_valid && !o_scheduler_busy &&
        !i_retire_inhibit && i_hdr_reset_done && i_read_quiescent &&
        i_public_read_quiescent && i_product_quiescent && !o_fault && !i_config_valid;
    assign o_pair_directory_valid=dispatch_state==D_REQUEST;
    assign o_pair_directory_slot={owned_bank,1'b0};
    hdr_pair_context_cache u_context_cache(
        .i_clk(clk),.i_identity_rst_n(i_identity_rst_n),
        .i_begin(dispatch_state==D_BEGIN),.i_expected_slot({owned_bank,1'b0}),
        .o_begin_ready(cache_begin_ready),.s_data(s_pair_directory_data),
        .s_word(s_pair_directory_word),.s_last(s_pair_directory_last),
        .s_valid(s_pair_directory_valid),.s_ready(s_pair_directory_ready),
        .o_frame(cache_frame),.o_lease(cache_lease),.o_valid(cache_valid),
        .i_clear(retired_pulse),.o_fault(cache_fault));
    assign o_job_valid=stereo_mode?i_stereo_job_valid:(dispatch_state==D_JOB && cache_valid && !o_fault);
    assign o_job_kind=stereo_mode?2'd1:2'd0;
    assign o_job_frame0=stereo_mode?i_stereo_job_frame:cache_frame;assign o_job_frame1=384'd0;
    assign o_job_lease0=stereo_mode?i_stereo_job_lease:cache_lease;
    // The owner atomically reserves consecutive complete 64-bit leases for
    // this immutable pair; LONG can never be the last counter value.
    assign o_job_lease1=stereo_mode?64'd0:cache_lease+64'd1;
    // Distinct semantic labels share one full-width, non-reused allocator in
    // this profile; neither field is truncated or reconstructed from a tag.
    assign o_job_id=stereo_mode?i_stereo_job_id:owned_pair_id;assign o_pair_id=stereo_mode?64'd0:owned_pair_id;
    assign o_pair_release_valid=release_pending;
    assign o_pair_release_bank=release_bank;assign o_pair_release_id=release_id;
    assign o_retire_ready=stereo_mode?(i_stereo_retire_ready&&!i_retire_inhibit):(release_pending && i_pair_release_ready);
    assign o_retire_done=stereo_mode?i_stereo_retire_done:retired_pulse;
    assign o_retire_error=stereo_mode&&i_stereo_retire_error;
    assign o_owner_quiescent=(stereo_mode?i_stereo_empty:i_pair_empty) && dispatch_state==D_IDLE && !cache_valid;
    assign o_owner_fault=i_pair_fault || cache_fault || dispatch_fault;
    assign o_busy=!o_owner_quiescent || o_scheduler_busy;
    assign o_fault=o_owner_fault || o_scheduler_fault;
    assign o_quiescent=o_owner_quiescent && !o_scheduler_busy && i_read_quiescent && !o_fault;
    assign o_pair_config_valid=i_config_valid;
    assign o_config_ready=i_pair_config_ready;
    assign o_config_done=config_done_pulse;
    assign o_config_error=i_pair_config_error;
    assign o_config_busy=i_config_valid && !i_pair_config_ready;
    assign o_commit_ready=1'b1;
    assign o_commit_done=i_commit_valid;assign o_commit_error=0;assign o_commit_duplicate=0;
    assign o_ref_valid=0;assign o_ref_op=0;assign o_ref_mask=0;assign o_ref_reason=0;
    assign o_ref_cancelled=0;assign o_ref_frame0=0;assign o_ref_frame1=0;
    assign o_ref_lease0=0;assign o_ref_lease1=0;assign o_ref_job_id=0;
    always @(posedge clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin
            dispatch_state<=D_IDLE;retired_pulse<=0;config_done_pulse<=0;dispatch_fault<=0;
            owned_bank<=0;owned_pair_id<=0;release_pending<=0;release_bank<=0;release_id<=0;
        end
        else begin
            retired_pulse<=release_fire;
            if(release_fire)release_pending<=0;
            if(!release_pending && dispatch_state==D_ACTIVE && o_retire_valid &&
                o_retire_read_quiescent && i_read_quiescent && i_public_read_quiescent &&
                i_product_quiescent && i_hdr_read_quiescent && !i_retire_inhibit &&
                rst_n && !o_fault && !i_hard_fault && !i_hdr_fault)begin
                release_pending<=1;release_bank<=owned_bank;release_id<=owned_pair_id;
            end
            config_done_pulse<=i_config_valid && i_pair_config_ready;
            // Losing application context cannot silently restart an acquired
            // pair. The external identity reset is required for recovery.
            if(!rst_n && dispatch_state!=D_IDLE)dispatch_fault<=1;
            case(dispatch_state)
                D_IDLE:if(i_pair_valid && o_pair_ready)begin
                    owned_bank<=i_pair_bank;owned_pair_id<=i_pair_id;dispatch_state<=D_BEGIN;
                end
                D_BEGIN:if(cache_begin_ready)dispatch_state<=D_REQUEST;
                D_REQUEST:if(i_pair_directory_ready)dispatch_state<=D_ASSEMBLE;
                D_ASSEMBLE:if(cache_valid)dispatch_state<=D_JOB;
                D_JOB:if(o_job_valid && o_job_ready)dispatch_state<=D_ACTIVE;
                D_ACTIVE:if(release_fire)dispatch_state<=D_IDLE;
                default:dispatch_fault<=1;
            endcase
        end
    end

    raw_hdr_phase_scheduler4 #(.NORMAL_REPLAY_ENABLE(STEREO_ENABLE),.NORMAL_SINGLE_MEMBER(1)) u_scheduler (
        .o_diag_scheduler_state(o_diag_scheduler_state),
        .i_hdr_mode(!stereo_mode),.i_public_read_quiescent(i_public_read_quiescent),
        .i_product_quiescent(i_product_quiescent),.i_hdr_reset_done(i_hdr_reset_done),
        .i_read_quiescent(i_read_quiescent),.i_hard_fault(i_hard_fault || o_owner_fault),
        .i_hdr_fault(i_hdr_fault),.i_hdr_read_quiescent(i_hdr_read_quiescent),
        .o_hdr_phase_request(o_hdr_phase_request),.o_hdr_phase_owned(o_hdr_phase_owned),
        .o_hdr_context_valid(o_hdr_context_valid),.i_hdr_context_ready(i_hdr_context_ready),
        .o_hdr_start_valid(o_hdr_start_valid),.i_hdr_start_ready(i_hdr_start_ready),
        .o_hdr_cancel_valid(o_hdr_cancel_valid),.i_hdr_cancel_ready(i_hdr_cancel_ready),
        .o_hdr_result_transport_enable(o_hdr_result_transport_enable),
        .i_hdr_result_valid(i_hdr_result_valid),.i_hdr_result_ready(i_hdr_result_ready),
        .i_hdr_result_ok(i_hdr_result_ok),.i_hdr_result_error(i_hdr_result_error),
        .o_hdr_long_tag(o_hdr_long_tag),.o_hdr_short_tag(o_hdr_short_tag),
        .clk(clk),.rst_n(i_identity_rst_n),.i_job_valid(o_job_valid),.o_job_ready(o_job_ready),.i_job_kind(o_job_kind),
        .i_job_id(o_job_id),.i_pair_id(o_pair_id),.i_job_frame0(o_job_frame0),.i_job_frame1(o_job_frame1),.i_job_lease0(o_job_lease0),.i_job_lease1(o_job_lease1),
        .m_member_valid(m_member_valid),.m_member_ready(m_member_ready),.m_member_frame(m_member_frame),.m_member_lease(m_member_lease),
        .m_member_job_id(m_member_job_id),.m_member_pair_id(m_member_pair_id),.m_member_index(m_member_index),
        .o_req_valid(o_req_valid),.i_req_ready(i_req_ready),.o_req_private(o_req_private),.o_req_op(o_req_op),
        .o_req_camera(o_req_camera),.o_req_slot(o_req_slot),.o_req_generation(o_req_generation),.o_req_session(o_req_session),
        .o_req_offset(o_req_offset),.o_req_length(o_req_length),.o_req_lease(o_req_lease),.o_req_job_id(o_req_job_id),
        .i_rsp_valid(i_rsp_valid),.o_rsp_ready(o_rsp_ready),.i_rsp_code(i_rsp_code),.i_rsp_camera(i_rsp_camera),.i_rsp_slot(i_rsp_slot),
        .i_rsp_generation(i_rsp_generation),.i_rsp_session(i_rsp_session),.i_rsp_sequence(i_rsp_sequence),.i_rsp_epoch(i_rsp_epoch),
        .i_native_done(i_native_done),.i_native_error(i_native_error),.i_native_job_id(i_native_job_id),.i_native_member_index(i_native_member_index),
        .i_processing_done(i_processing_done),.i_processing_error(i_processing_error),.i_processing_job_id(i_processing_job_id),.i_processing_member_index(i_processing_member_index),
        .i_cancel(i_cancel),.o_processing_cancel_valid(o_processing_cancel_valid),.i_processing_cancel_ready(i_processing_cancel_ready),
        .o_processing_cancel_frame(o_processing_cancel_frame),.o_processing_cancel_lease(o_processing_cancel_lease),
        .o_processing_cancel_job_id(o_processing_cancel_job_id),.o_processing_cancel_pair_id(o_processing_cancel_pair_id),.o_processing_cancel_member_index(o_processing_cancel_member_index),
        .o_retire_valid(o_retire_valid),.i_retire_ready(o_retire_ready),.o_retire_session(o_retire_session),.o_retire_job_id(o_retire_job_id),
        .o_retire_cancelled(o_retire_cancelled),.o_retire_read_quiescent(o_retire_read_quiescent),.i_retire_done(o_retire_done),.i_retire_error(o_retire_error),
        .o_busy(o_scheduler_busy),.o_fault(o_scheduler_fault),.o_error_code(o_error_code),.o_stale_completion(o_stale_completion));

endmodule
