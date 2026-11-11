`timescale 1ns/1ps
`default_nettype none

// Passive PIX transaction window, replaced only by a checked COMMIT or reset.
// The first offered physical FS and first accepted SOF after positive ACK are
// distinct observations. Each gate vector is captured on its own single edge.
module cfg_diag_pixel (
    input wire i_clk,i_observer_rst_n,i_app_rst_n,
    input wire i_commit_accepted,
    input wire [31:0] i_session,i_request_sequence,i_target_epoch,
    input wire i_remote_sent,i_positive_ack,i_negative_ack,i_unmatched_ack,
    input wire i_frame_accept,i_apply_frame,i_applied_last_sent,
    input wire [31:0] i_frame_sequence,i_live_flags,
    input wire [2:0] i_frame_gates,
    input wire i_source_fs,
    input wire [15:0] i_source_gates,
    output wire [223:0] o_data
);
    reg commit_valid;
    reg [31:0] session,sequence_id,target_epoch,first_sof_sequence,apply_sequence;
    reg [7:1] milestones;
    reg [2:0] first_sof_gates;
    reg source_fs_seen;
    reg [15:0] first_source_gates;
    reg previous_app_reset_n,reset_generation_saturated;
    reg [15:0] reset_generation;
    wire [31:0] flags=i_live_flags|
        {reset_generation_saturated,6'd0,source_fs_seen,13'd0,first_sof_gates,milestones,commit_valid};
    assign o_data={{first_source_gates,reset_generation},flags,apply_sequence,
        first_sof_sequence,target_epoch,sequence_id,session};
    always @(posedge i_clk or negedge i_observer_rst_n) begin
        if(!i_observer_rst_n)begin
            commit_valid<=0;session<=0;sequence_id<=0;target_epoch<=0;
            first_sof_sequence<=0;apply_sequence<=0;milestones<=0;first_sof_gates<=0;
            source_fs_seen<=0;first_source_gates<=0;previous_app_reset_n<=0;
            reset_generation<=0;reset_generation_saturated<=0;
        end else begin
            previous_app_reset_n<=i_app_rst_n;
            if(i_app_rst_n&&!previous_app_reset_n)begin
                if(reset_generation!=16'hffff)reset_generation<=reset_generation+1'b1;
                else reset_generation_saturated<=1;
            end
            if(!i_app_rst_n)begin
                commit_valid<=0;session<=0;sequence_id<=0;target_epoch<=0;
                first_sof_sequence<=0;apply_sequence<=0;milestones<=0;first_sof_gates<=0;
                source_fs_seen<=0;first_source_gates<=0;
            end else if(i_commit_accepted)begin
                commit_valid<=1;session<=i_session;sequence_id<=i_request_sequence;
                target_epoch<=i_target_epoch;first_sof_sequence<=0;apply_sequence<=0;
                milestones<=0;first_sof_gates<=0;source_fs_seen<=0;first_source_gates<=0;
            end else if(commit_valid)begin
                if(i_remote_sent)milestones[1]<=1;
                if(i_positive_ack)milestones[2]<=1;
                if(i_negative_ack)milestones[3]<=1;
                if(i_unmatched_ack)milestones[4]<=1;
                if((milestones[2]||i_positive_ack)&&!milestones[5]&&i_frame_accept)begin
                    milestones[5]<=1;first_sof_sequence<=i_frame_sequence;first_sof_gates<=i_frame_gates;
                end
                if(i_apply_frame&&!milestones[6])begin milestones[6]<=1;apply_sequence<=i_frame_sequence;end
                if(i_applied_last_sent)milestones[7]<=1;
                if((milestones[2]||i_positive_ack)&&!source_fs_seen&&i_source_fs)begin
                    source_fs_seen<=1;first_source_gates<=i_source_gates;
                end
            end
        end
    end
endmodule
`default_nettype wire
