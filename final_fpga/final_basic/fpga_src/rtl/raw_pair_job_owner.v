// Metadata ownership only. Store ref-ready acknowledges an applied atomic change.
module raw_pair_job_owner #(
    parameter integer ALLOW_POLICY_UPDATE = 0
) (
    input wire clk, input wire rst_n, input wire [63:0] i_now,
    input wire i_config_valid, output wire o_config_ready,
    input wire [31:0] i_session, i_epoch, input wire [1:0] i_mode,
    input wire [63:0] i_max_delta, input wire [31:0] i_max_wait, i_max_age,
    output reg o_config_done, o_config_error, o_config_busy,
    input wire i_commit_valid, output wire o_commit_ready,
    input wire [383:0] i_descriptor, input wire [63:0] i_lease,
    output reg o_commit_done, o_commit_error, o_commit_duplicate,
    output reg o_ref_valid, input wire i_ref_ready,
    output reg [1:0] o_ref_op, o_ref_mask,
    output reg [4:0] o_ref_reason, output reg o_ref_cancelled,
    output reg [383:0] o_ref_frame0, o_ref_frame1,
    output reg [63:0] o_ref_lease0, o_ref_lease1, o_ref_job_id,
    output reg o_job_valid, input wire i_job_ready,
    output wire [1:0] o_job_kind, output reg [63:0] o_job_id, output wire [63:0] o_pair_id,
    output wire [383:0] o_job_frame0, o_job_frame1,
    output wire [63:0] o_job_lease0, o_job_lease1,
    input wire i_retire_valid, output wire o_retire_ready,
    input wire [63:0] i_retire_job_id, input wire [31:0] i_retire_session,
    input wire i_retire_cancelled, i_read_quiescent,
    output reg o_retire_done, o_retire_error,
    output reg o_fault, output wire o_quiescent
);
    localparam [1:0] REF_EVENT=0, REF_BAD=1, REF_RETIRE=2;
    reg command_busy, command_config, configured;
    reg [1:0] mode, command_mode;
    reg pending_valid, pending_handled;
    reg [383:0] pending_frame;
    reg [63:0] pending_lease, lease_high, job_counter;
    reg [1:0] resident_valid;
    reg [72:0] resident_handle0, resident_handle1;
    reg [63:0] resident_lease0, resident_lease1;
    reg job_held, job_delivered;
    reg [1:0] job_mask, ref_source;
    reg [1:0] ref_remove;
    reg ref_pending_used;
    reg [1:0] ref_kind;
    reg [63:0] ref_pair;

    // PIN's applied REF tuple is the sole JOB payload storage. While
    // job_held, COMMIT cannot enter and CONFIG is rejected. The manager's
    // JOB-producing event always returns to FINISH; RETIRE changes only REF
    // operation/reason/mask. Keep these words immutable until applied RETIRE.
    // JOB payload is qualified by o_job_valid / the delivered owner lifetime.
    assign o_job_frame0=o_ref_frame0;assign o_job_frame1=o_ref_frame1;
    assign o_job_lease0=o_ref_lease0;assign o_job_lease1=o_ref_lease1;
    assign o_job_kind=ref_kind;assign o_pair_id=ref_pair;

    function [72:0] handle;
        input [383:0] frame;
        begin handle={frame[76:13],frame[12:4]}; end
    endfunction
    wire [72:0] input_handle=handle(i_descriptor);
    wire duplicate_live_bad =
        (resident_valid[0] && i_lease==resident_lease0 && input_handle!=resident_handle0) ||
        (resident_valid[1] && i_lease==resident_lease1 && input_handle!=resident_handle1) ||
        (job_held && i_lease==o_job_lease0 && input_handle!=handle(o_job_frame0)) ||
        (job_held && job_mask[1] && i_lease==o_job_lease1 && input_handle!=handle(o_job_frame1));
    wire mgr_ready, mgr_done, mgr_error, mgr_event_valid;
    wire [1:0] mgr_kind; wire [3:0] mgr_reason;
    wire [383:0] mgr_frame0, mgr_frame1; wire [63:0] mgr_pair;
    wire retire_matches=job_held && job_delivered &&
        i_retire_job_id==o_job_id && i_retire_session==o_job_frame0[76:45];
    assign o_retire_ready=!o_fault && !o_ref_valid && !mgr_event_valid &&
        (!retire_matches || i_read_quiescent);
    wire retire_fire=i_retire_valid && o_retire_ready;
    assign o_config_ready=!o_fault && !command_busy && !o_ref_valid &&
        mgr_ready && !retire_fire;
    assign o_commit_ready=!o_fault && !command_busy && !o_ref_valid &&
        mgr_ready && configured && !job_held && !i_config_valid && !retire_fire;
    wire config_fire=i_config_valid && o_config_ready;
    wire commit_fire=i_commit_valid && o_commit_ready;
    wire new_commit=commit_fire && i_lease!=0 && i_lease>lease_high;
    wire mgr_valid=(config_fire && !job_held) || new_commit;
    wire mgr_event_ready=o_ref_valid && i_ref_ready && ref_source==REF_EVENT && !o_fault;
    assign o_quiescent=!command_busy && !o_ref_valid && !pending_valid &&
        resident_valid==0 && !job_held && !mgr_event_valid;
    frame_pair_manager #(.SLOTS_PER_CAMERA(4),.ALLOW_POLICY_UPDATE(ALLOW_POLICY_UPDATE)) u_manager (
        .clk(clk),.rst_n(rst_n),.i_valid(mgr_valid),.o_ready(mgr_ready),
        .i_command(config_fire ? 2'd2 : 2'd0),.i_now(i_now),.i_descriptor(i_descriptor),
        .i_session(i_session),.i_epoch(i_epoch),.i_mode(i_mode),
        .i_max_delta(i_max_delta),.i_max_wait(i_max_wait),.i_max_age(i_max_age),
        .o_done(mgr_done),.o_error(mgr_error),.o_event_valid(mgr_event_valid),
        .i_event_ready(mgr_event_ready),.o_event_kind(mgr_kind),.o_event_reason(mgr_reason),
        .o_frame0(mgr_frame0),.o_frame1(mgr_frame1),.o_pair_id(mgr_pair)
    );

    // Match references independently of sequence/exposure/qualification decisions.
    reg [63:0] event_lease0, event_lease1;
    reg [1:0] event_remove;
    reg event_pending, event_found0, event_found1;
    always @* begin
        event_lease0=0; event_lease1=0; event_remove=0;
        event_pending=0; event_found0=0; event_found1=mgr_kind!=0;
        if(mgr_kind==3) begin
            if(pending_valid && handle(mgr_frame0)==handle(pending_frame)) begin
                event_lease0=pending_lease; event_pending=1; event_found0=1;
            end
        end else begin
            if(resident_valid[0] && handle(mgr_frame0)==resident_handle0) begin
                event_lease0=resident_lease0; event_remove[0]=1; event_found0=1;
            end else if(resident_valid[1] && handle(mgr_frame0)==resident_handle1) begin
                event_lease0=resident_lease1; event_remove[1]=1; event_found0=1;
            end else if(pending_valid && !pending_handled && handle(mgr_frame0)==handle(pending_frame)) begin
                event_lease0=pending_lease; event_pending=1; event_found0=1;
            end
            if(mgr_kind==0) begin
                if(resident_valid[0] && handle(mgr_frame1)==resident_handle0) begin
                    event_lease1=resident_lease0; event_remove[0]=1; event_found1=1;
                end else if(resident_valid[1] && handle(mgr_frame1)==resident_handle1) begin
                    event_lease1=resident_lease1; event_remove[1]=1; event_found1=1;
                end else if(pending_valid && !pending_handled && handle(mgr_frame1)==handle(pending_frame)) begin
                    event_lease1=pending_lease; event_pending=1; event_found1=1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            command_busy<=0; command_config<=0; configured<=0; mode<=0; command_mode<=0;
            pending_valid<=0; pending_handled<=0; pending_frame<=0; pending_lease<=0;
            lease_high<=0; job_counter<=0; resident_valid<=0;
            resident_handle0<=0; resident_handle1<=0; resident_lease0<=0; resident_lease1<=0;
            job_held<=0; job_delivered<=0; job_mask<=0; ref_source<=0; ref_remove<=0;
            ref_pending_used<=0; ref_kind<=0; ref_pair<=0;
            o_config_done<=0; o_config_error<=0; o_config_busy<=0;
            o_commit_done<=0; o_commit_error<=0; o_commit_duplicate<=0;
            o_retire_done<=0; o_retire_error<=0; o_fault<=0;
            o_ref_valid<=0; o_ref_op<=0; o_ref_mask<=0; o_ref_reason<=0; o_ref_cancelled<=0;
            o_ref_frame0<=0; o_ref_frame1<=0; o_ref_lease0<=0; o_ref_lease1<=0; o_ref_job_id<=0;
            o_job_valid<=0; o_job_id<=0;
        end else begin
            o_config_done<=0; o_config_error<=0; o_config_busy<=0;
            o_commit_done<=0; o_commit_error<=0; o_commit_duplicate<=0;
            o_retire_done<=0; o_retire_error<=0;
            if(o_job_valid && i_job_ready) begin o_job_valid<=0; job_delivered<=1; end
            if(!o_fault) begin
                if(config_fire) begin
                    if(job_held) begin o_config_done<=1; o_config_error<=1; o_config_busy<=1; end
                    else begin command_busy<=1; command_config<=1; command_mode<=i_mode; end
                end
                if(commit_fire) begin
                    if(i_lease==0 || duplicate_live_bad) begin
                        o_commit_done<=1; o_commit_error<=1; o_fault<=1;
                    end else if(i_lease<=lease_high) begin
                        o_commit_done<=1; o_commit_duplicate<=1;
                    end else begin
                        lease_high<=i_lease; pending_valid<=1; pending_handled<=0;
                        pending_frame<=i_descriptor; pending_lease<=i_lease;
                        command_busy<=1; command_config<=0;
                    end
                end
                if(mgr_done && command_busy) begin
                    if(command_config) begin
                        command_busy<=0; o_config_done<=1; o_config_error<=mgr_error;
                        if(!mgr_error) begin mode<=command_mode; configured<=1; end
                    end else if(mgr_error) begin
                        // Bad descriptors/time can produce done/error with no event.
                        o_ref_valid<=1; ref_source<=REF_BAD; o_ref_op<=0; o_ref_mask<=1;
                        o_ref_reason<=16; o_ref_cancelled<=0;
                        o_ref_frame0<=pending_frame; o_ref_frame1<=0;
                        o_ref_lease0<=pending_lease; o_ref_lease1<=0; o_ref_job_id<=0;
                    end else begin
                        command_busy<=0; pending_valid<=0; o_commit_done<=1;
                        if(!pending_handled) begin
                            if(mode==2 ? pending_frame[2:1]==2 : pending_frame[4]) begin
                                resident_valid[1]<=1; resident_handle1<=handle(pending_frame); resident_lease1<=pending_lease;
                            end else begin
                                resident_valid[0]<=1; resident_handle0<=handle(pending_frame); resident_lease0<=pending_lease;
                            end
                        end
                    end
                end
                if(mgr_event_valid && !o_ref_valid) begin
                    if(!event_found0 || !event_found1 || ((mgr_kind==0 || mgr_kind==1) && job_held)) o_fault<=1;
                    else begin
                        o_ref_valid<=1; ref_source<=REF_EVENT;
                        o_ref_op<=mgr_kind==0 || mgr_kind==1 ? 1 : 0;
                        o_ref_mask<=mgr_kind==0 ? 3 : 1; o_ref_reason<={1'b0,mgr_reason};
                        o_ref_cancelled<=0; o_ref_frame0<=mgr_frame0; o_ref_frame1<=mgr_frame1;
                        o_ref_lease0<=event_lease0; o_ref_lease1<=event_lease1;
                        o_ref_job_id<=mgr_kind==0 || mgr_kind==1 ? job_counter+1'b1 : 0;
                        ref_remove<=event_remove; ref_pending_used<=event_pending;
                        ref_kind<=mgr_kind; ref_pair<=mgr_pair;
                    end
                end
                if(retire_fire) begin
                    if(!retire_matches) begin o_retire_done<=1; o_retire_error<=1; end
                    else begin
                        o_ref_valid<=1; ref_source<=REF_RETIRE; o_ref_op<=2; o_ref_mask<=job_mask;
                        o_ref_reason<=17; o_ref_cancelled<=i_retire_cancelled;
                        o_ref_job_id<=o_job_id;
                    end
                end
                if(o_ref_valid && i_ref_ready) begin
                    o_ref_valid<=0;
                    case(ref_source)
                        REF_EVENT: begin
                            resident_valid<=resident_valid & ~ref_remove;
                            if(ref_pending_used) pending_handled<=1;
                            if(o_ref_op==1) begin
                                job_held<=1; job_delivered<=0; job_mask<=o_ref_mask;
                                job_counter<=o_ref_job_id; o_job_valid<=1;
                                o_job_id<=o_ref_job_id;
                            end
                        end
                        REF_BAD: begin
                            pending_valid<=0; pending_handled<=1; command_busy<=0;
                            o_commit_done<=1; o_commit_error<=1;
                        end
                        REF_RETIRE: begin job_held<=0; job_delivered<=0; o_retire_done<=1; end
                        default: o_fault<=1;
                    endcase
                end
            end
        end
    end
endmodule
