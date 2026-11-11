`timescale 1ns/1ps
`default_nettype none

// Passive USER-domain CFG milestones. No output is a business control input.
// Business reset is sampled as data; the only async reset is observer cold reset.
module cfg_diag_user (
    input wire i_clk,i_observer_rst_n,i_app_rst_n,
    input wire i_prepare_start,i_commit_accepted,i_commit_last_sent,
    input wire i_applied_present,i_copy_started,i_copy_complete,
    input wire i_applied_taken,i_published,i_reply_mismatch,
    input wire [31:0] i_session,i_request_sequence,i_target_epoch,
    input wire [31:0] i_published_epoch,i_published_first_sequence,i_live_flags,
    output wire [223:0] o_data
);
    reg request_valid;
    reg [31:0] session,sequence_id,target_epoch;
    reg [7:1] milestones;
    reg reply_mismatch;
    reg previous_app_reset_n,reset_generation_saturated;
    reg [15:0] reset_generation;
    wire [31:0] flags=i_live_flags|
        {reset_generation_saturated,17'd0,reply_mismatch,5'd0,milestones,request_valid};
    assign o_data={{16'd0,reset_generation},flags,i_published_first_sequence,
        i_published_epoch,target_epoch,sequence_id,session};
    always @(posedge i_clk or negedge i_observer_rst_n) begin
        if(!i_observer_rst_n)begin
            request_valid<=0;session<=0;sequence_id<=0;target_epoch<=0;
            milestones<=0;reply_mismatch<=0;previous_app_reset_n<=0;
            reset_generation<=0;reset_generation_saturated<=0;
        end else begin
            previous_app_reset_n<=i_app_rst_n;
            if(i_app_rst_n&&!previous_app_reset_n)begin
                if(reset_generation!=16'hffff)reset_generation<=reset_generation+1'b1;
                else reset_generation_saturated<=1;
            end
            if(!i_app_rst_n)begin
                request_valid<=0;session<=0;sequence_id<=0;target_epoch<=0;
                milestones<=0;reply_mismatch<=0;
            end else if(i_prepare_start)begin
                request_valid<=1;session<=i_session;sequence_id<=i_request_sequence;
                target_epoch<=i_target_epoch;milestones<=0;reply_mismatch<=0;
            end else if(request_valid)begin
                if(i_commit_accepted)milestones[1]<=1;
                if(i_commit_last_sent)milestones[2]<=1;
                if(i_applied_present)milestones[3]<=1;
                if(i_copy_started)milestones[4]<=1;
                if(i_copy_complete)milestones[5]<=1;
                if(i_applied_taken)milestones[6]<=1;
                if(i_published)milestones[7]<=1;
                if(i_reply_mismatch)reply_mismatch<=1;
            end
        end
    end
endmodule
`default_nettype wire
