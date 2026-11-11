`timescale 1ns / 1ps

// DFI scheduler -> pixel member owner -> true writer completion -> DFI retire.
// Each crossing uses an existing, formally configured TD message FIFO.
module raw_pair_processing_context_ticket #(
    parameter integer NATIVE_RESULT_ENABLE=1
) (
    // Cold root only: never connect this to STOP, CFG or application resets.
    input wire i_identity_rst_n,
    input wire [31:0] i_authority_session,
    input wire i_authority_empty,i_owner_live,i_read_quiescent,i_write_quiescent,
    output wire o_owner_hold,o_recovery_required,o_ticket_exhausted,
    output wire [63:0] o_source_ticket,o_pixel_ticket,
    input wire i_dfi_clk, i_dfi_rst_n,
    input wire i_pixel_clk, i_pixel_rst_n,
    input wire s_member_valid, output wire s_member_ready,
    input wire [383:0] s_member_frame,
    input wire [63:0] s_member_lease, s_member_job_id, s_member_pair_id,
    input wire s_member_index,
    input wire s_cancel_valid, output wire s_cancel_ready,
    input wire [383:0] s_cancel_frame,
    input wire [63:0] s_cancel_lease, s_cancel_job_id, s_cancel_pair_id,
    input wire s_cancel_index,
    input wire s_write_valid, output wire s_write_ready,
    input wire [31:0] s_write_tag, s_write_sequence, s_write_session, s_write_epoch,
    input wire s_write_camera, s_write_ok,
    input wire [7:0] s_write_error,
    output wire m_processing_valid, input wire m_processing_ready,
    output wire [63:0] m_processing_job_id,
    output wire m_processing_member_index, m_processing_error,
    output wire o_dfi_reset_done, o_dfi_fault,
    // Every following context/activity signal belongs exclusively to pixel_clk.
    input wire i_pool_idle, i_admission_ready,
    input wire i_context_valid, output wire o_context_ready,
    input wire [383:0] i_context_frame,
    input wire [63:0] i_context_job_id, i_context_pair_id,
    input wire i_context_member_index, i_context_private,
    input wire i_native_job_start, i_store_start_fire, i_pipeline_error,
    input wire i_native_result_valid,i_native_result_error,
    input wire [63:0] i_native_result_job_id,
    input wire i_native_result_member_index,
    input wire [63:0] i_native_result_write_tag,
    output wire [383:0] o_frame,
    output wire [63:0] o_lease, o_job_id, o_pair_id,
    output wire o_member_index,
    output wire [31:0] o_write_tag,
    output wire o_pixel_busy, o_context_owned, o_pixel_reset_done, o_pixel_fault,
    output wire [7:0] o_first_fault_code,
    output wire [31:0] o_stale_write_count, o_completed_count, o_cancelled_count,
    output wire [31:0] o_stale_native_count,
    output wire [2:0] o_diag_ticket_state,
    output wire [3:0] o_diag_ticket_pixel
);
    wire [146:0] result;
    wire [63:0] native_ticket;
    // A legacy label is accepted only against the full current PIX context;
    // the full 64-bit ticket then authenticates the return at the DFI owner.
    wire context_labels_match=i_context_job_id==o_job_id && i_context_pair_id==o_pair_id;
    assign native_ticket=i_native_result_job_id==o_job_id &&
        i_native_result_write_tag=={32'd0,o_write_tag} ? o_pixel_ticket : 64'd0;
    assign m_processing_job_id=result[63:0];
    assign m_processing_member_index=result[64];
    assign m_processing_error=result[65];
    raw_job_ticket_context_cdc u_ticket(
        .o_diag_state(o_diag_ticket_state),
        .o_diag_ticket_pixel(o_diag_ticket_pixel),
        .i_source_clk(i_dfi_clk),.i_identity_rst_n(i_identity_rst_n),.i_source_rst_n(i_dfi_rst_n),
        .i_pixel_clk(i_pixel_clk),.i_pixel_rst_n(i_pixel_rst_n),.i_session(i_authority_session),
        .i_recovery_valid(1'b1),.i_authority_empty(i_authority_empty),
        .i_source_read_quiescent(i_read_quiescent),.i_source_write_quiescent(i_write_quiescent),
        .o_recovery_ready(),.o_recovery_required(o_recovery_required),.o_ticket_exhausted(o_ticket_exhausted),
        .o_owner_hold(o_owner_hold),
        .i_owner_member({s_member_index,s_member_pair_id,s_member_job_id,s_member_lease,s_member_frame}),
        .i_owner_live(i_owner_live),.s_job_valid(s_member_valid),.s_job_ready(s_member_ready),
        .s_cancel_member({s_cancel_index,s_cancel_pair_id,s_cancel_job_id,s_cancel_lease,s_cancel_frame}),
        .s_cancel_valid(s_cancel_valid),.s_cancel_ready(s_cancel_ready),
        .s_write_result({9'd0,s_write_error,s_write_ok,s_write_camera,s_write_epoch,s_write_session,s_write_sequence,s_write_tag}),
        .s_write_result_valid(s_write_valid),.s_write_result_ready(s_write_ready),
        .m_processing_result(result),.m_processing_result_valid(m_processing_valid),.m_processing_result_ready(m_processing_ready),
        .o_source_ticket(o_source_ticket),
        .i_pool_idle(i_pool_idle),.i_admission_ready(i_admission_ready),
        .i_context_valid(i_context_valid),.i_context_frame(i_context_frame),.i_context_ticket(o_pixel_ticket),
        .i_context_member_index(i_context_member_index),.i_context_private(i_context_private && context_labels_match),
        .o_context_ready(o_context_ready),.i_native_job_start(i_native_job_start),.i_store_start_fire(i_store_start_fire),
        .i_pipeline_error(i_pipeline_error),
        .i_native_result_valid(i_native_result_valid && NATIVE_RESULT_ENABLE!=0),.i_native_result_error(i_native_result_error),
        .i_native_result_ticket(native_ticket),.i_native_result_member_index(i_native_result_member_index),
        .o_frame(o_frame),.o_pixel_lease(o_lease),.o_pixel_job_id(o_job_id),.o_pixel_pair_id(o_pair_id),
        .o_pixel_ticket(o_pixel_ticket),.o_member_index(o_member_index),.o_write_tag(o_write_tag),
        .o_busy(o_pixel_busy),.o_context_owned(o_context_owned),
        .o_source_reset_done(o_dfi_reset_done),.o_pixel_reset_done(o_pixel_reset_done),
        .o_source_fault(o_dfi_fault),.o_pixel_fault(o_pixel_fault),.o_first_fault_code(o_first_fault_code),
        .o_completed_count(o_completed_count),.o_cancelled_count(o_cancelled_count),
        .o_stale_write_count(o_stale_write_count),.o_stale_reply_count(),.o_stale_native_count(o_stale_native_count));
endmodule
