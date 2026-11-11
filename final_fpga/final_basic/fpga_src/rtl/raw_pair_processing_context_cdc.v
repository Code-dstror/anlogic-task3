`timescale 1ns / 1ps

// DFI scheduler -> pixel member owner -> true writer completion -> DFI retire.
// Each crossing uses an existing, formally configured TD message FIFO.
module raw_pair_processing_context_cdc #(
    parameter integer NATIVE_RESULT_ENABLE=0
) (
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
    output wire [383:0] o_frame,
    output wire [63:0] o_lease, o_job_id, o_pair_id,
    output wire o_member_index,
    output wire [31:0] o_write_tag,
    output wire o_pixel_busy, o_context_owned, o_pixel_reset_done, o_pixel_fault,
    output wire [7:0] o_first_fault_code,
    output wire [31:0] o_stale_write_count, o_completed_count, o_cancelled_count,
    output wire [31:0] o_stale_native_count
);
    wire async_rst_n=i_dfi_rst_n && i_pixel_rst_n;
    wire dfi_local_rst_n,pixel_local_rst_n;
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(async_rst_n),.o_rst_n(dfi_local_rst_n));
    reset_release_sync u_pixel_reset(.i_clk(i_pixel_clk),.i_async_rst_n(async_rst_n),.o_rst_n(pixel_local_rst_n));
    wire [577:0] command_source=s_cancel_valid ?
        {1'b1,s_cancel_index,s_cancel_pair_id,s_cancel_job_id,s_cancel_lease,s_cancel_frame} :
        {1'b0,s_member_index,s_member_pair_id,s_member_job_id,s_member_lease,s_member_frame};
    wire [577:0] command_sink;
    wire command_source_ready,command_sink_valid,command_sink_ready;
    wire command_dfi_done,command_pixel_done,command_pixel_fault,command_dfi_fault;
    wire pixel_context_fault;
    reg context_fault_meta,context_fault_sync;
    always @(posedge i_dfi_clk or negedge dfi_local_rst_n) begin
        if(!dfi_local_rst_n) begin context_fault_meta<=0;context_fault_sync<=0;end
        else begin context_fault_meta<=pixel_context_fault;context_fault_sync<=context_fault_meta;end
    end
    assign o_dfi_fault=command_dfi_fault || context_fault_sync;
    assign o_pixel_fault=command_pixel_fault || pixel_context_fault;
    assign s_member_ready=command_source_ready && !s_cancel_valid && !o_dfi_fault;
    assign s_cancel_ready=command_source_ready && !o_dfi_fault;
    raw_pair_command_cdc u_command_cdc(
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_local_rst_n),
        .s_command(command_source),.s_command_valid((s_member_valid || s_cancel_valid) && !o_dfi_fault),
        .s_command_ready(command_source_ready),.o_source_reset_done(command_dfi_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(pixel_local_rst_n),.m_command(command_sink),
        .m_command_valid(command_sink_valid),.m_command_ready(command_sink_ready),
        .o_sink_reset_done(command_pixel_done),.o_protocol_fault(command_pixel_fault),.o_source_protocol_fault(command_dfi_fault));
    wire [146:0] write_source={9'd0,s_write_error,s_write_ok,s_write_camera,
                              s_write_epoch,s_write_session,s_write_sequence,s_write_tag};
    wire [146:0] write_sink,processing_source,processing_sink;
    wire write_sink_valid,write_sink_ready,write_dfi_done,write_pixel_done;
    wire processing_source_valid,processing_source_ready,processing_pixel_done,processing_dfi_done;
    control_message_fifo_ip u_write_result_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_local_rst_n),.i_source_data(write_source),
        .i_source_valid(s_write_valid),.o_source_ready(s_write_ready),.o_source_reset_done(write_dfi_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(pixel_local_rst_n),.o_sink_data(write_sink),
        .o_sink_valid(write_sink_valid),.i_sink_ready(write_sink_ready),.o_sink_reset_done(write_pixel_done));
    raw_pair_pixel_context #(.NATIVE_RESULT_ENABLE(NATIVE_RESULT_ENABLE)) u_pixel_context(
        .clk(i_pixel_clk),.rst_n(pixel_local_rst_n),
        .i_pool_idle(i_pool_idle),.i_admission_ready(i_admission_ready && o_pixel_reset_done),
        .s_command(command_sink),.s_command_valid(command_sink_valid),.s_command_ready(command_sink_ready),
        .i_context_valid(i_context_valid),.o_context_ready(o_context_ready),.i_context_frame(i_context_frame),
        .i_context_job_id(i_context_job_id),.i_context_pair_id(i_context_pair_id),
        .i_context_member_index(i_context_member_index),.i_context_private(i_context_private),
        .i_native_job_start(i_native_job_start),.i_store_start_fire(i_store_start_fire),.i_pipeline_error(i_pipeline_error),
        .i_native_result_valid(i_native_result_valid),.i_native_result_error(i_native_result_error),
        .i_native_result_job_id(i_native_result_job_id),.i_native_result_member_index(i_native_result_member_index),
        .s_write_result(write_sink),.s_write_result_valid(write_sink_valid),.s_write_result_ready(write_sink_ready),
        .m_processing_result(processing_source),.m_processing_result_valid(processing_source_valid),.m_processing_result_ready(processing_source_ready),
        .o_frame(o_frame),.o_lease(o_lease),.o_job_id(o_job_id),.o_pair_id(o_pair_id),.o_member_index(o_member_index),
        .o_write_tag(o_write_tag),.o_busy(o_pixel_busy),.o_context_owned(o_context_owned),.o_protocol_fault(pixel_context_fault),
        .o_first_fault_code(o_first_fault_code),.o_stale_write_count(o_stale_write_count),
        .o_completed_count(o_completed_count),.o_cancelled_count(o_cancelled_count),.o_stale_native_count(o_stale_native_count));
    control_message_fifo_ip u_processing_result_fifo(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_pixel_clk),.i_source_rst_n(pixel_local_rst_n),.i_source_data(processing_source),
        .i_source_valid(processing_source_valid),.o_source_ready(processing_source_ready),.o_source_reset_done(processing_pixel_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(dfi_local_rst_n),.o_sink_data(processing_sink),
        .o_sink_valid(m_processing_valid),.i_sink_ready(m_processing_ready),.o_sink_reset_done(processing_dfi_done));
    assign m_processing_job_id=processing_sink[63:0];
    assign m_processing_member_index=processing_sink[64];
    assign m_processing_error=processing_sink[65];
    assign o_dfi_reset_done=command_dfi_done && write_dfi_done && processing_dfi_done;
    assign o_pixel_reset_done=command_pixel_done && write_pixel_done && processing_pixel_done;
endmodule
