`timescale 1ns / 1ps

// DFI-only queue ownership changes after real backend promises have drained.
module nr_dfi_phase_fifo_pair4 (
    input wire clk,rst_n,i_ddr_reset_done,i_matrix_hard_fault,
    input wire [575:0] s_begin_context,s_process_context,s_release_context,
    input wire s_begin_valid,s_process_valid,s_release_valid,
    output wire s_begin_ready,s_process_ready,s_release_ready,
    input wire i_rgb_write_quiescent,i_motion_write_quiescent,i_old_y_read_quiescent,
    input wire i_original_source_quiescent,
    input wire i_rgb_read_quiescent,i_projection_quiescent,i_filtered_source_quiescent,
    output wire o_reset_done,o_build_active,o_process_active,o_idle,o_fault,o_queues_empty,
    output wire [31:0] o_stale_control_count,
    input wire [146:0] s_cw_data,s_mw_data,s_cr_data,s_hr_data,
    input wire s_cw_valid,s_mw_valid,s_cr_valid,s_hr_valid,
    output wire s_cw_ready,s_mw_ready,s_cr_ready,s_hr_ready,
    output wire [146:0] m_cw_data,m_mw_data,m_cr_data,m_hr_data,
    output wire m_cw_valid,m_mw_valid,m_cr_valid,m_hr_valid,
    input wire m_cw_ready,m_mw_ready,m_cr_ready,m_hr_ready,
    output wire [9:0] o_cw_available,o_mw_available,o_cr_available,o_hr_available
);
    localparam [1:0] IDLE=0,BUILD=1,PROCESS=2;
    reg [1:0] state,state_next;
    reg [575:0] context_locked;
    reg quarantined;
    reg [31:0] stale_control_count,pushed_first,popped_first,pushed_second,popped_second;
    wire first_source_ready,second_source_ready,first_sink_valid,second_sink_valid;
    wire first_source_done,first_sink_done,second_source_done,second_sink_done;
    wire [146:0] first_sink_data,second_sink_data;
    wire [9:0] first_available,second_available;
    wire build=state==BUILD,process=state==PROCESS;
    wire first_source_valid=(build && s_cw_valid) || (process && s_cr_valid);
    wire second_source_valid=(build && s_mw_valid) || (process && s_hr_valid);
    wire first_sink_ready=(build && m_cw_ready) || (process && m_cr_ready);
    wire second_sink_ready=(build && m_mw_ready) || (process && m_hr_ready);
    wire first_push=first_source_valid && first_source_ready;
    wire second_push=second_source_valid && second_source_ready;
    wire first_pop=first_sink_valid && first_sink_ready;
    wire second_pop=second_sink_valid && second_sink_ready;
    assign o_queues_empty=pushed_first==popped_first && pushed_second==popped_second &&
        !first_sink_valid && !second_sink_valid && first_available==0 && second_available==0;
    wire build_quiet=i_rgb_write_quiescent && i_motion_write_quiescent &&
        i_old_y_read_quiescent && i_original_source_quiescent;
    wire process_quiet=i_rgb_read_quiescent && i_projection_quiescent && i_filtered_source_quiescent;
    wire process_match=s_process_context==context_locked;
    wire release_match=s_release_context==context_locked;
    assign o_reset_done=rst_n && i_ddr_reset_done && first_source_done && first_sink_done &&
        second_source_done && second_sink_done;
    assign o_fault=quarantined || i_matrix_hard_fault;
    assign o_build_active=rst_n && build;
    assign o_process_active=rst_n && process;
    assign o_idle=rst_n && state==IDLE && o_queues_empty && !o_fault;
    assign s_begin_ready=o_reset_done && o_idle;
    assign s_process_ready=o_reset_done && build && !o_fault &&
        (!process_match || (o_queues_empty && !s_cw_valid && !s_mw_valid && build_quiet));
    assign s_release_ready=o_reset_done && process && !o_fault &&
        (!release_match || (o_queues_empty && !s_cr_valid && !s_hr_valid && process_quiet));
    assign o_stale_control_count=stale_control_count;
    assign s_cw_ready=build && first_source_ready;assign s_mw_ready=build && second_source_ready;
    assign s_cr_ready=process && first_source_ready;assign s_hr_ready=process && second_source_ready;
    assign m_cw_data=first_sink_data;assign m_cr_data=first_sink_data;
    assign m_mw_data=second_sink_data;assign m_hr_data=second_sink_data;
    assign m_cw_valid=build && first_sink_valid;assign m_mw_valid=build && second_sink_valid;
    assign m_cr_valid=process && first_sink_valid;assign m_hr_valid=process && second_sink_valid;
    assign o_cw_available=build ? first_available : 10'd0;
    assign o_mw_available=build ? second_available : 10'd0;
    assign o_cr_available=process ? first_available : 10'd0;
    assign o_hr_available=process ? second_available : 10'd0;
    raw_capture_fifo_ip u_first(
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data(build ? s_cw_data : s_cr_data),
        .i_source_valid(first_source_valid),.o_source_ready(first_source_ready),.o_source_reset_done(first_source_done),
        .i_sink_clk(clk),.i_sink_rst_n(rst_n),.o_sink_data(first_sink_data),.o_sink_valid(first_sink_valid),
        .i_sink_ready(first_sink_ready),.o_available_count(first_available),.o_sink_reset_done(first_sink_done));
    raw_capture_fifo_ip u_second(
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data(build ? s_mw_data : s_hr_data),
        .i_source_valid(second_source_valid),.o_source_ready(second_source_ready),.o_source_reset_done(second_source_done),
        .i_sink_clk(clk),.i_sink_rst_n(rst_n),.o_sink_data(second_sink_data),.o_sink_valid(second_sink_valid),
        .i_sink_ready(second_sink_ready),.o_available_count(second_available),.o_sink_reset_done(second_sink_done));
    always @(*)begin
        state_next=state;
        case(state)
            IDLE: if(s_begin_valid && s_begin_ready && s_begin_context[447:384]!=0)state_next=BUILD;
            BUILD: if(s_process_valid && s_process_ready && process_match)state_next=PROCESS;
            PROCESS: if(s_release_valid && s_release_ready && release_match)state_next=IDLE;
            default: state_next=state;
        endcase
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)state<=IDLE;
        else state<=state_next;
    end
    // No reset or pointer clear occurs at BEGIN/PROCESS/RELEASE.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            context_locked<=0;quarantined<=0;stale_control_count<=0;
            pushed_first<=0;popped_first<=0;pushed_second<=0;popped_second<=0;
        end else begin
            if(i_matrix_hard_fault || state==3)quarantined<=1;
            if(first_push)pushed_first<=pushed_first+1'b1;
            if(first_pop)popped_first<=popped_first+1'b1;
            if(second_push)pushed_second<=pushed_second+1'b1;
            if(second_pop)popped_second<=popped_second+1'b1;
            if(s_begin_valid && s_begin_ready)begin
                if(s_begin_context[447:384]==0)quarantined<=1;
                else context_locked<=s_begin_context;
            end
            if((s_process_valid && s_process_ready && !process_match) ||
               (s_release_valid && s_release_ready && !release_match))
                if(!(&stale_control_count))stale_control_count<=stale_control_count+1'b1;
        end
    end
endmodule
