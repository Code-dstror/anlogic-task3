`timescale 1ns/1ps
// A processed SOURCE carries its frozen full labels and writer tag. A late
// event cannot be relabelled with the new current context's short ticket.
module raw_processing_source_ticket_gate (
    input wire clk,rst_n,i_reset_done,i_context_owned,
    input wire [383:0] i_frame,
    input wire [63:0] i_lease,i_job_id,i_pair_id,
    input wire i_member,
    input wire [31:0] i_write_tag,
    input wire s_valid,s_error,
    output wire s_ready,
    input wire [383:0] s_frame,
    input wire [63:0] s_lease,s_job_id,s_pair_id,s_write_tag,
    input wire s_member,
    output wire o_native_valid,o_native_error,
    output reg [31:0] o_stale_count
);
    wire source_matches=i_context_owned && s_frame==i_frame && s_lease==i_lease &&
        s_job_id==i_job_id && s_pair_id==i_pair_id && s_member==i_member &&
        s_write_tag=={32'd0,i_write_tag} && i_write_tag!=0;
    assign s_ready=rst_n && i_reset_done;
    assign o_native_valid=s_valid && s_ready && source_matches;
    assign o_native_error=s_error;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)o_stale_count<=0;
        else if(s_valid && s_ready && !source_matches && !(&o_stale_count))o_stale_count<=o_stale_count+1'b1;
    end
endmodule
