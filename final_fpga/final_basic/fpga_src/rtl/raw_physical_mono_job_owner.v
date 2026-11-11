// Physical current-frame ownership. Unknown exposure stays unknown; this owner
// never turns a current-frame lease into temporal-history qualification.
module raw_physical_mono_job_owner #(
    parameter integer WIDTH=1920,
    parameter integer HEIGHT=1080
) (
    input wire clk,rst_n,input wire [63:0] i_now,
    input wire i_config_valid,output wire o_config_ready,
    input wire [31:0] i_session,i_epoch,input wire [1:0] i_mode,
    input wire [63:0] i_max_delta,input wire [31:0] i_max_wait,i_max_age,
    output reg o_config_done,o_config_error,o_config_busy,
    input wire i_commit_valid,output wire o_commit_ready,
    input wire [383:0] i_descriptor,input wire [63:0] i_lease,
    output reg o_commit_done,o_commit_error,o_commit_duplicate,
    output reg o_ref_valid,input wire i_ref_ready,
    output reg [1:0] o_ref_op,o_ref_mask,
    output reg [4:0] o_ref_reason,output reg o_ref_cancelled,
    output reg [383:0] o_ref_frame0,o_ref_frame1,
    output reg [63:0] o_ref_lease0,o_ref_lease1,o_ref_job_id,
    output reg o_job_valid,input wire i_job_ready,
    output reg [1:0] o_job_kind,
    output reg [63:0] o_job_id,o_pair_id,
    output reg [383:0] o_job_frame0,o_job_frame1,
    output reg [63:0] o_job_lease0,o_job_lease1,
    input wire i_retire_valid,output wire o_retire_ready,
    input wire [63:0] i_retire_job_id,input wire [31:0] i_retire_session,
    input wire i_retire_cancelled,i_read_quiescent,
    output reg o_retire_done,o_retire_error,
    output reg o_fault,output wire o_quiescent
);
    reg configured,job_owned,job_delivered;
    reg [31:0] session,epoch,max_wait,max_age;
    reg [63:0] max_delta,last_now,lease_high,job_counter;
    reg sequence_seen;
    reg [31:0] last_sequence;
    reg [63:0] last_timestamp;
    reg [3:0] generation_seen;
    reg [31:0] generation0,generation1,generation2,generation3;
    wire [1:0] slot=i_descriptor[6:5];
    wire [31:0] previous_generation=slot==0 ? generation0 : slot==1 ? generation1 :
        slot==2 ? generation2 : generation3;
    wire [31:0] sequence_delta=i_descriptor[108:77]-last_sequence;
    wire [31:0] generation_delta=i_descriptor[44:13]-previous_generation;
    wire [63:0] age=i_now-i_descriptor[204:141];
    wire retire_matches=job_owned&&job_delivered&&i_retire_job_id==o_job_id&&
        i_retire_session==o_job_frame0[76:45];
    assign o_retire_ready=!o_fault&&!o_ref_valid&&(!retire_matches||i_read_quiescent);
    wire retire_fire=i_retire_valid&&o_retire_ready;
    assign o_config_ready=!o_fault&&!o_ref_valid&&!retire_fire;
    assign o_commit_ready=!o_fault&&configured&&!o_ref_valid&&!job_owned&&
        !i_config_valid&&!retire_fire;
    assign o_quiescent=!o_ref_valid&&!job_owned;
    wire config_fire=i_config_valid&&o_config_ready;
    wire commit_fire=i_commit_valid&&o_commit_ready;
    wire config_legal=i_session!=0&&i_mode==0&&i_now>=last_now&&
        i_max_delta[63:32]==0&&i_max_wait!=0&&i_max_age!=0&&
        (!configured||(i_max_delta==max_delta&&i_max_wait==max_wait&&i_max_age==max_age));
    wire descriptor_legal=i_descriptor[383:367]==0&&i_descriptor[3]&&
        !i_descriptor[4]&&i_descriptor[2:1]==0&&i_descriptor[12:5]<4&&
        i_descriptor[44:13]!=0&&i_descriptor[76:45]==session&&
        i_descriptor[140:109]==epoch&&i_descriptor[220:205]==WIDTH&&
        i_descriptor[236:221]==HEIGHT&&i_descriptor[238:237]==1&&
        i_now>=last_now&&i_descriptor[204:141]<=i_now&&age<={32'd0,max_age}&&
        (!sequence_seen||(sequence_delta!=0&&!sequence_delta[31]&&
            i_descriptor[204:141]>=last_timestamp))&&
        (!generation_seen[slot]||(generation_delta!=0&&!generation_delta[31]));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            configured<=0;job_owned<=0;job_delivered<=0;session<=0;epoch<=0;
            max_delta<=0;max_wait<=0;max_age<=0;last_now<=0;lease_high<=0;job_counter<=0;
            sequence_seen<=0;last_sequence<=0;last_timestamp<=0;generation_seen<=0;
            generation0<=0;generation1<=0;generation2<=0;generation3<=0;
            o_config_done<=0;o_config_error<=0;o_config_busy<=0;
            o_commit_done<=0;o_commit_error<=0;o_commit_duplicate<=0;
            o_ref_valid<=0;o_ref_op<=0;o_ref_mask<=0;o_ref_reason<=0;o_ref_cancelled<=0;
            o_ref_frame0<=0;o_ref_frame1<=0;o_ref_lease0<=0;o_ref_lease1<=0;o_ref_job_id<=0;
            o_job_valid<=0;o_job_kind<=1;o_job_id<=0;o_pair_id<=0;
            o_job_frame0<=0;o_job_frame1<=0;o_job_lease0<=0;o_job_lease1<=0;
            o_retire_done<=0;o_retire_error<=0;o_fault<=0;
        end else begin
            o_config_done<=0;o_config_error<=0;o_config_busy<=0;
            o_commit_done<=0;o_commit_error<=0;o_commit_duplicate<=0;
            o_retire_done<=0;o_retire_error<=0;
            if(o_job_valid&&i_job_ready)begin o_job_valid<=0;job_delivered<=1;end
            if(!o_fault)begin
                if(config_fire)begin
                    o_config_done<=1;
                    if(job_owned)begin o_config_error<=1;o_config_busy<=1;end
                    else if(!config_legal)o_config_error<=1;
                    else begin
                        configured<=1;session<=i_session;epoch<=i_epoch;last_now<=i_now;
                        max_delta<=i_max_delta;max_wait<=i_max_wait;max_age<=i_max_age;
                        if(!configured||session!=i_session)begin
                            sequence_seen<=0;generation_seen<=0;
                        end
                    end
                end
                if(commit_fire)begin
                    if(i_lease==0)o_fault<=1;
                    else if(i_lease<=lease_high)begin o_commit_done<=1;o_commit_duplicate<=1;end
                    else if(&job_counter)o_fault<=1;
                    else begin
                        lease_high<=i_lease;
                        if(i_now>=last_now)last_now<=i_now;
                        o_ref_valid<=1;o_ref_mask<=1;o_ref_cancelled<=0;
                        o_ref_op<=descriptor_legal ? 1 : 0;
                        o_ref_reason<=descriptor_legal ? 0 : 16;
                        o_ref_frame0<=i_descriptor;o_ref_frame1<=0;
                        o_ref_lease0<=i_lease;o_ref_lease1<=0;
                        o_ref_job_id<=descriptor_legal ? job_counter+64'd1 : 0;
                        if(descriptor_legal)begin
                            sequence_seen<=1;last_sequence<=i_descriptor[108:77];
                            last_timestamp<=i_descriptor[204:141];generation_seen[slot]<=1;
                            case(slot)
                                0:generation0<=i_descriptor[44:13];
                                1:generation1<=i_descriptor[44:13];
                                2:generation2<=i_descriptor[44:13];
                                3:generation3<=i_descriptor[44:13];
                            endcase
                        end
                    end
                end
                if(retire_fire)begin
                    if(!retire_matches)begin o_retire_done<=1;o_retire_error<=1;end
                    else begin
                        o_ref_valid<=1;o_ref_op<=2;o_ref_mask<=1;o_ref_reason<=17;
                        o_ref_cancelled<=i_retire_cancelled;
                        o_ref_frame0<=o_job_frame0;o_ref_frame1<=0;
                        o_ref_lease0<=o_job_lease0;o_ref_lease1<=0;o_ref_job_id<=o_job_id;
                    end
                end
                if(o_ref_valid&&i_ref_ready)begin
                    o_ref_valid<=0;
                    case(o_ref_op)
                        0:begin o_commit_done<=1;o_commit_error<=1;end
                        1:begin
                            job_owned<=1;job_delivered<=0;job_counter<=o_ref_job_id;
                            o_job_valid<=1;o_job_id<=o_ref_job_id;o_job_kind<=1;o_pair_id<=0;
                            o_job_frame0<=o_ref_frame0;o_job_frame1<=0;
                            o_job_lease0<=o_ref_lease0;o_job_lease1<=0;o_commit_done<=1;
                        end
                        2:begin job_owned<=0;job_delivered<=0;o_retire_done<=1;end
                        default:o_fault<=1;
                    endcase
                end
            end
        end
    end
endmodule
