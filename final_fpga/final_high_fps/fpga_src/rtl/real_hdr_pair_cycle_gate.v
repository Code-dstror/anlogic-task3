`timescale 1ns/1ps
`default_nettype none
`include "pcie_protocol_v1.vh"

// Two PIX-domain DOL2 contexts retain SHORT(n) while LONG(n+1) starts.
// A member SOURCE proves its own true FE/CRC/full-sensor geometry only.
// The existing DFI bank publishes a pair after BOTH real writers succeed.
module real_hdr_pair_cycle_gate #(
    parameter integer TIMEOUT_CYCLES=12500000,
    parameter [31:0] RECIPE_CALIBRATION_ID=32'h56a3d02f,
    parameter [31:0] LONG_LINE_TICKS=3200, SHORT_LINE_TICKS=200,
    parameter [31:0] GAIN_Q8_8=256,
    parameter integer EXTERNAL_PHASE_ENABLE=0
) (
    input wire i_clk,i_reset_n,i_fault,i_stable,i_admit_enable,
    input wire [31:0] i_session,i_epoch,
    input wire [63:0] i_time,
    input wire i_time_valid,
    input wire i_capture0_idle,i_capture1_idle,
    input wire [146:0] s0_data,s1_data,
    input wire s0_valid,s1_valid,
    output wire s0_ready,s1_ready,
    output reg [39:0] m0_data,m1_data,
    output reg m0_valid,m1_valid,m0_sof,m1_sof,m0_eol,m1_eol,m0_abort,m1_abort,
    output reg [31:0] o_sequence0,o_sequence1,o_session,o_epoch,
    output reg [196:0] o_metadata0,o_metadata1,
    output reg o_source0_valid,o_source1_valid,
    input wire i_source0_ready,i_source1_ready,
    // Legacy shared names now name LONG only. SHORT has its own held bundle.
    output reg [31:0] o_source_session,o_source_epoch,o_source0_sequence,o_source1_sequence,
    output reg o_source_ok,
    output reg [7:0] o_source_error,
    output reg [31:0] o_source1_session,o_source1_epoch,
    output reg o_source1_ok,
    output reg [7:0] o_source1_error,
    output reg o_pair_event,o_pair_ok,
    output wire [31:0] o_diag_pair,
    output wire [47:0] o_diag_counts,
    output reg [31:0] o_good_pairs,o_bad_pairs,o_not_admitted_pairs,
    output wire o_quiet,
    input wire [31:0] i_timeout_phase
);
    localparam [0:0] SOURCE_PHYSICAL=`PCIE_RECORD_V2_SOURCE_PHYSICAL;
    function integer timer_bits;
        input integer value;
        integer remaining;
        begin
            remaining=value>1?value-1:1;timer_bits=0;
            while(remaining>0)begin timer_bits=timer_bits+1;remaining=remaining>>1;end
        end
    endfunction
    localparam integer TIMER_BITS=timer_bits(TIMEOUT_CYCLES);
    // One modulo-T phase for both contexts. A newly allocated context stores
    // the current phase and expires when that phase next returns T clocks later.
    wire [TIMER_BITS-1:0] timeout_phase;
    generate if(EXTERNAL_PHASE_ENABLE!=0)begin:g_external_phase
        assign timeout_phase=i_timeout_phase[TIMER_BITS-1:0];
    end else begin:g_local_phase
        reg [TIMER_BITS-1:0] phase;
        always @(posedge i_clk or negedge i_reset_n)begin
            if(!i_reset_n)phase<=0;
            else if(phase==TIMEOUT_CYCLES-1)phase<=0;
            else phase<=phase+1'b1;
        end
        assign timeout_phase=phase;
    end endgenerate

    function [15:0] sat_add;
        input [15:0] value;
        input [1:0] increment;
        reg [16:0] sum;
        begin sum={1'b0,value}+increment;sat_add=sum[16]?16'hffff:sum[15:0];end
    endfunction
    reg [1:0] active,admitted,bad;
    reg stable_blocked,skip_valid;
    reg [31:0] skip_group;
    reg [3:0] watermark_pending_requests;
    reg [31:0] watermark_pending_id[0:1];
    wire watermark_pending=|watermark_pending_requests;
    function serial_after;
        input [31:0] a,b;
        begin serial_after=(a[30:0]!=b[30:0])&&
            ((a[30:0]>b[30:0])^a[31]^b[31]);end
    endfunction
    reg [31:0] cycle_group[0:1];
    // Each slot records the free-running phase of its accepted LONG FS.
    reg [TIMER_BITS-1:0] timer[0:1];
    reg [1:0] seen[0:1],done[0:1],started[0:1],terminal_sent[0:1];
    wire [146:0] token[0:1];
    assign token[0]=s0_data;assign token[1]=s1_data;
    wire [1:0] fs={2{!watermark_pending}}&
        {s1_valid&&!s1_data[42]&&s1_data[46:43]==7,
         s0_valid&&!s0_data[42]&&s0_data[46:43]==7};
    wire [1:0] match0={active[1]&&cycle_group[1]==s0_data[78:47],
                         active[0]&&cycle_group[0]==s0_data[78:47]};
    wire [1:0] match1={active[1]&&cycle_group[1]==s1_data[78:47],
                         active[0]&&cycle_group[0]==s1_data[78:47]};
    wire [4:0] newer_than[0:4];
    wire skipped0=!(|match0)&&skip_valid&&s0_data[78:47]!=0&&
        (s0_data[78:47]==skip_group||serial_after(skip_group,s0_data[78:47]));
    wire skipped1=!(|match1)&&skip_valid&&s1_data[78:47]!=0&&
        (s1_data[78:47]==skip_group||serial_after(skip_group,s1_data[78:47]));
    wire [1:0] unfinished0={active[1]&&seen[1][0]&&!done[1][0],
                              active[0]&&seen[0][0]&&!done[0][0]};
    wire [1:0] unfinished1={active[1]&&seen[1][1]&&!done[1][1],
                              active[0]&&seen[0][1]&&!done[0][1]};
    wire reentry0=fs[0]&&!skipped0&&(|unfinished0);
    wire reentry1=fs[1]&&!skipped1&&(|unfinished1);
    wire allow_new_group=i_admit_enable&&!i_fault;
    wire need_new0=fs[0]&&!skipped0&&!(|match0)&&allow_new_group;
    wire member0_busy=active==3||o_source0_valid||(i_stable&&!stable_blocked&&!i_capture0_idle);
    wire wait_member0=need_new0&&member0_busy;
    assign s0_ready=!watermark_pending&&!reentry0&&!wait_member0;
    wire same_group=s0_data[78:47]==s1_data[78:47];
    wire simultaneous_start=fs[0]&&s0_ready&&!skipped0&&allow_new_group&&same_group;
    wire matching1_admitted=(match1[0]&&admitted[0])||(match1[1]&&admitted[1])||
        (simultaneous_start&&i_stable&&!stable_blocked);
    wire member1_busy=o_source1_valid||!i_capture1_idle;
    wire wait_member1=fs[1]&&!skipped1&&matching1_admitted&&member1_busy;
    // Receiver publication can begin with a SHORT that has no LONG cycle.
    // It must drain because no future LONG can match that unqualified FS.
    wire trusted_short_group=s1_data[111]&&s1_data[112]&&s1_data[78:47]!=0;
    wire future_short=fs[1]&&trusted_short_group&&!skipped1&&!(|match1)&&
        !simultaneous_start&&allow_new_group;
    assign s1_ready=!watermark_pending&&!reentry1&&!wait_member1&&!future_short;
    wire [1:0] fire={s1_valid&&s1_ready,s0_valid&&s0_ready};
    // CFG borrows this quiet level through the old-cohort drain. Rejected
    // sensor traffic can still advance the skip watermark without owning RAW
    // or SOURCE. Keep that filtering on the token path only.
    assign o_quiet=active==0&&!o_source0_valid&&!o_source1_valid;

    wire new_long=need_new0&&!reentry0&&!member0_busy;
    wire [1:0] allocate={new_long&&active[0],new_long&&!active[0]};
    wire join_new_short=new_long&&same_group&&fire[1];
    wire new_bad=!s0_data[111]||!s0_data[112]||s0_data[78:47]==0||!i_time_valid;
    wire new_admitted=i_stable&&!stable_blocked&&!new_bad&&i_capture0_idle&&!o_source0_valid;

    // A registered match needs no new-group permission. A simultaneous LONG
    // FS can additionally stall a matched SHORT FS at the interface, but in
    // that case it duplicates the slot's LONG FS and cancels before SHORT.
    wire [1:0] take_old0=match0&{2{s0_valid&&!watermark_pending&&!reentry0}};
    wire [1:0] take_old1=match1&{2{s1_valid&&!watermark_pending&&!reentry1}}&
        (~admitted|{2{!fs[1]||!member1_busy}});
    wire [1:0] take_old[0:1];
    assign take_old[0]=take_old0;assign take_old[1]=take_old1;

    reg [1:0] next_active,next_admitted,next_bad;
    wire next_skip_valid;
    wire [31:0] next_skip_group;
    reg [3:0] watermark_request;
    reg [31:0] next_group[0:1];
    reg [TIMER_BITS-1:0] next_timer[0:1];
    reg [1:0] next_seen[0:1],next_done[0:1],next_started[0:1],next_terminal_sent[0:1];
    reg [1:0] cancel,finish,raw_valid,raw_sof,raw_eol,raw_abort;
    reg [7:0] cancel_error[0:1];
    reg [39:0] raw_data[0:1];
    reg [1:0] source_enqueue,source_ok;
    reg [7:0] source_error[0:1];
    reg short_fs_accept,short_fs_admitted;
    reg [1:0] good_events,bad_events,not_admitted_events;
    reg [7:0] first_event_error,last_event_error;
    integer c,member;
    always @*begin
        next_active=active;next_admitted=admitted;next_bad=bad;
        watermark_request=0;
        watermark_request[0]=fire[0]&&(skipped0||(!(|match0)&&!allow_new_group))&&s0_data[78:47]!=0;
        watermark_request[1]=fire[1]&&(skipped1||(!(|match1)&&!allow_new_group))&&s1_data[78:47]!=0;
        cancel=0;finish=0;raw_valid=0;raw_sof=0;raw_eol=0;raw_abort=0;
        short_fs_accept=0;short_fs_admitted=0;source_enqueue=0;source_ok=0;
        good_events=0;bad_events=0;not_admitted_events=0;
        first_event_error=0;last_event_error=0;
        raw_data[0]=0;raw_data[1]=0;
        source_error[0]=0;source_error[1]=0;
        for(c=0;c<2;c=c+1)begin
            next_group[c]=cycle_group[c];
            next_timer[c]=timer[c];
            next_seen[c]=seen[c];next_done[c]=done[c];next_started[c]=started[c];
            next_terminal_sent[c]=terminal_sent[c];
            cancel[c]=active[c]&&(i_fault||(admitted[c]&&!i_stable)||
                i_session!=o_session||i_epoch!=o_epoch||
                (reentry0&&unfinished0[c])||(reentry1&&unfinished1[c])||
                (TIMEOUT_CYCLES>0&&timer[c]==timeout_phase));
            cancel_error[c]=(i_fault||(admitted[c]&&!i_stable)||
                i_session!=o_session||i_epoch!=o_epoch)?8'd9:
                ((reentry0&&unfinished0[c])||(reentry1&&unfinished1[c]))?8'd5:8'd11;
            // Process the members of this registered slot in LONG then SHORT
            // order. A new group on the other slot cannot affect these results.
            for(member=0;member<2;member=member+1)begin
                if(take_old[member][c]&&!cancel[c])begin
                    if(fs[member])begin
                        // Every registered group already has a LONG FS.
                        if(member==0||seen[c][member]||!token[member][111]||!token[member][112])begin
                            cancel[c]=1;cancel_error[c]=5;
                        end else begin
                            next_seen[c][member]=1;
                            short_fs_accept=1;short_fs_admitted=admitted[c];
                        end
                    end else if(token[member][42]||token[member][46:43]==8||
                        !token[member][111]||!token[member][112])begin
                        cancel[c]=1;cancel_error[c]={4'd0,token[member][46:43]};
                    end else if(token[member][46:43]==6)begin
                        if(!seen[c][member]||done[c][member])begin
                            cancel[c]=1;cancel_error[c]=5;
                        end else next_done[c][member]=1;
                    end else if(token[member][46:43]==0&&seen[c][member]&&
                        !done[c][member]&&admitted[c]&&!bad[c])begin
                        raw_valid[member]=1;raw_data[member]=token[member][39:0];
                        raw_sof[member]=token[member][40];raw_eol[member]=token[member][41];
                        if(token[member][40])next_started[c][member]=1;
                    end
                end
            end
        end
        for(c=0;c<2;c=c+1)begin
            // A late peer fault cannot retract an already issued member
            // terminal, or abort the next group which now owns that lane.
            for(member=0;member<2;member=member+1)begin
                if(active[c]&&next_started[c][member]&&!terminal_sent[c][member]&&
                    (cancel[c]||next_done[c][member]))begin
                    source_enqueue[member]=1;
                    // All retained contexts have one cohort at each registered
                    // edge. A mismatch cancels every OLD context before RAW.
                    // New FS cannot emit RAW/SOURCE on that same edge, so these
                    // OLD globals are copied into the independent held terminal
                    // even when a new cohort's FS updates capture identity.
                    // There is only one unfinished member per physical lane.
                    // Its next FS is blocked until FE/negative terminal and
                    // ingress retirement; completed peer contexts never reuse it.
                    source_ok[member]=!cancel[c]&&!bad[c];
                    source_error[member]=cancel[c]?cancel_error[c]:bad[c]?8'd10:8'd0;
                    raw_abort[member]=cancel[c];
                    if(cancel[c])raw_valid[member]=0;
                    next_terminal_sent[c][member]=1;
                end
            end
            if(allocate[c])begin
                next_active[c]=1;next_group[c]=s0_data[78:47];next_timer[c]=timeout_phase;
                next_seen[c]=1;next_done[c]=0;next_started[c]=0;next_terminal_sent[c]=0;
                next_bad[c]=new_bad;next_admitted[c]=new_admitted;
                // A same-edge SHORT can join or reject a new LONG, but no
                // member of the newly allocated slot can emit RAW or SOURCE.
                if(join_new_short)begin
                    if(s1_data[42]||s1_data[46:43]==8||!s1_data[111]||!s1_data[112])begin
                        cancel[c]=1;cancel_error[c]=fs[1]?8'd5:{4'd0,s1_data[46:43]};
                    end else if(s1_data[46:43]==6)begin
                        cancel[c]=1;cancel_error[c]=5;
                    end else if(fs[1])begin
                        next_seen[c][1]=1;
                        short_fs_accept=1;short_fs_admitted=new_admitted;
                    end
                end
            end
            finish[c]=next_active[c]&&next_done[c]==3&&!cancel[c];
            if(cancel[c]||finish[c])begin
                if(finish[c]&&!next_bad[c]&&next_seen[c]==3)good_events=good_events+1'b1;
                else begin
                    bad_events=bad_events+1'b1;
                    last_event_error=cancel[c]?cancel_error[c]:8'd10;
                    if(first_event_error==0)first_event_error=last_event_error;
                    watermark_request[c+2]=next_group[c]!=0;
                end
                if(!next_admitted[c])not_admitted_events=not_admitted_events+1'b1;
                next_active[c]=0;next_admitted[c]=0;
            end
        end
    end
    // A 32-bit serial-number relation is NOT transitive for arbitrary
    // malformed tokens. Preserve the original ordered four-way fold. Compare
    // immutable candidate IDs in parallel and select only their one-hot index.
    wire [31:0] watermark_id[0:4];
    assign watermark_id[0]=skip_group;
    assign watermark_id[1]=watermark_pending_id[0];
    assign watermark_id[2]=watermark_pending_id[1];
    // Context group registers receive next_group on the request edge and do
    // not change while token admission is closed. Reuse them as the two late
    // candidates instead of duplicating another64bits of payload storage.
    assign watermark_id[3]=cycle_group[0];
    assign watermark_id[4]=cycle_group[1];
    genvar a,b;
    generate for(a=0;a<5;a=a+1)begin:g_order
        assign newer_than[a][a]=1'b0;
        for(b=a+1;b<5;b=b+1)begin:g_pair
            wire [30:0] x=watermark_id[a][30:0],y=watermark_id[b][30:0];
            wire greater=x>y;
            wire unequal=x!=y;
            wire order_bit=greater^watermark_id[a][31]^watermark_id[b][31];
            assign newer_than[a][b]=unequal&&order_bit;
            assign newer_than[b][a]=unequal&&!order_bit;
        end
    end endgenerate
    wire [2:0] request_index[0:3];
    assign request_index[0]=1;assign request_index[1]=2;
    assign request_index[2]=3;
    assign request_index[3]=4;
    // Compose two ordered two-event selector maps. The priorities are the
    // same as the serial fold even for arbitrary, non-transitive group IDs.
    wire take0=watermark_pending_requests[0]&&(!skip_valid||newer_than[1][0]);
    wire take10=watermark_pending_requests[1]&&(!skip_valid||newer_than[2][0]);
    wire take11=watermark_pending_requests[1]&&newer_than[2][1];
    wire [2:0] early;
    assign early[0]=!take0&&!take10;
    assign early[1]=take0&&!take11;
    assign early[2]=(take0&&take11)||(!take0&&take10);
    wire [4:0] order2=request_index[2]==1?newer_than[1]:newer_than[3];
    wire [4:0] order3=request_index[3]==1?newer_than[1]:newer_than[4];
    wire late_dominates=watermark_pending_requests[3]&&(request_index[2]==1?order3[1]:order3[3]);
    wire [2:0] eligible_origin={2'b00,!skip_valid};
    wire [2:0] take2={3{watermark_pending_requests[2]}}&(order2[2:0]|eligible_origin);
    wire [2:0] take3={3{watermark_pending_requests[3]}}&(order3[2:0]|eligible_origin);
    wire [2:0] keep=early&~take2&~take3;
    wire use2=(|(early&take2))&&!late_dominates;
    wire use3=|(early&((take2&{3{late_dominates}})|(~take2&take3)));
    wire use_token0=keep[1]||(use2&&request_index[2]==1)||(use3&&request_index[3]==1);
    assign next_skip_valid=skip_valid||watermark_pending;
    assign next_skip_group=({32{use_token0}}&watermark_id[1])|
        ({32{keep[2]}}&watermark_id[2])|({32{use2&&request_index[2]==3}}&watermark_id[3])|
        ({32{use3&&request_index[3]==4}}&watermark_id[4]);
    reg [7:0] first_bad_reason,last_bad_reason;
    reg [15:0] diag_good,diag_bad,diag_not_admitted;
    wire diag_context=active[0]?1'b0:1'b1;
    assign o_diag_counts={diag_not_admitted,diag_bad,diag_good};
    assign o_diag_pair={first_bad_reason,last_bad_reason,seen[diag_context],done[diag_context],started[diag_context],
        (|active),(|admitted),(|bad),stable_blocked,s0_valid,s1_valid,i_stable,i_fault,i_admit_enable,i_time_valid};
    integer r;
    // Record only rejected/failed group IDs, then perform the ordered serial
    // fold on register outputs. The one-cycle negative-path bubble prevents a
    // following token from bypassing a pending watermark. Healthy groups have
    // no extra data latency. Fault/timeout terminals still progress in the gap.
    always @(posedge i_clk)begin
        if(watermark_request[0])watermark_pending_id[0]<=s0_data[78:47];
        if(watermark_request[1])watermark_pending_id[1]<=s1_data[78:47];
    end
    always @(posedge i_clk or negedge i_reset_n)begin
        if(!i_reset_n)begin
            active<=0;admitted<=0;bad<=0;stable_blocked<=0;skip_group<=0;skip_valid<=0;
            watermark_pending_requests<=0;
            for(r=0;r<2;r=r+1)begin
                cycle_group[r]<=0;
                timer[r]<=0;seen[r]<=0;done[r]<=0;started[r]<=0;terminal_sent[r]<=0;
            end
            m0_valid<=0;m1_valid<=0;m0_data<=0;m1_data<=0;m0_sof<=0;m1_sof<=0;
            m0_eol<=0;m1_eol<=0;m0_abort<=0;m1_abort<=0;
            o_sequence0<=0;o_sequence1<=0;o_session<=0;o_epoch<=0;o_metadata0<=0;o_metadata1<=0;
            o_source0_valid<=0;o_source1_valid<=0;o_source_session<=0;o_source_epoch<=0;
            o_source0_sequence<=0;o_source1_sequence<=0;o_source_ok<=0;o_source_error<=0;
            o_source1_session<=0;o_source1_epoch<=0;o_source1_ok<=0;o_source1_error<=0;
            o_pair_event<=0;o_pair_ok<=0;o_good_pairs<=0;o_bad_pairs<=0;o_not_admitted_pairs<=0;
            first_bad_reason<=0;last_bad_reason<=0;diag_good<=0;diag_bad<=0;diag_not_admitted<=0;
        end else begin
            active<=next_active;admitted<=next_admitted;bad<=next_bad;
            // Retain the watermark through the clock enable, so a late reject
            // decision does not feed a 32-bit old/new feedback mux.
            watermark_pending_requests<=watermark_request;
            if(watermark_pending&&!keep[0])skip_group<=next_skip_group;
            skip_valid<=next_skip_valid;
            for(r=0;r<2;r=r+1)begin
                cycle_group[r]<=next_group[r];timer[r]<=next_timer[r];
                seen[r]<=next_seen[r];done[r]<=next_done[r];started[r]<=next_started[r];terminal_sent[r]<=next_terminal_sent[r];
            end
            m0_valid<=raw_valid[0];m1_valid<=raw_valid[1];m0_data<=raw_data[0];m1_data<=raw_data[1];
            m0_sof<=raw_sof[0];m1_sof<=raw_sof[1];m0_eol<=raw_eol[0];m1_eol<=raw_eol[1];
            m0_abort<=raw_abort[0];m1_abort<=raw_abort[1];
            o_pair_event<=0;
            if(!i_stable)stable_blocked<=0;
            if(o_source0_valid&&i_source0_ready)o_source0_valid<=0;
            if(o_source1_valid&&i_source1_ready)o_source1_valid<=0;
            if(new_long)begin
                o_sequence0<=s0_data[110:79];o_session<=i_session;o_epoch<=i_epoch;
                o_metadata0<={1'b1,new_admitted,2'd1,SOURCE_PHYSICAL,s0_data[78:47],
                    RECIPE_CALIBRATION_ID,GAIN_Q8_8,LONG_LINE_TICKS,i_time};
            end
            if(short_fs_accept)begin
                o_sequence1<=s1_data[110:79];
                o_metadata1<={1'b1,short_fs_admitted,2'd2,SOURCE_PHYSICAL,s1_data[78:47],
                    RECIPE_CALIBRATION_ID,GAIN_Q8_8,SHORT_LINE_TICKS,i_time};
            end
            if(source_enqueue[0])begin
                o_source0_valid<=1;o_source_session<=o_session;o_source_epoch<=o_epoch;
                o_source0_sequence<=o_sequence0;o_source_ok<=source_ok[0];o_source_error<=source_error[0];
            end
            if(source_enqueue[1])begin
                o_source1_valid<=1;o_source1_session<=o_session;o_source1_epoch<=o_epoch;
                o_source1_sequence<=o_sequence1;o_source1_ok<=source_ok[1];o_source1_error<=source_error[1];
            end
            if(good_events!=0||bad_events!=0)begin
                o_pair_event<=1;o_pair_ok<=bad_events==0;
                o_good_pairs<=o_good_pairs+good_events;o_bad_pairs<=o_bad_pairs+bad_events;
                o_not_admitted_pairs<=o_not_admitted_pairs+not_admitted_events;
                diag_good<=sat_add(diag_good,good_events);diag_bad<=sat_add(diag_bad,bad_events);
                diag_not_admitted<=sat_add(diag_not_admitted,not_admitted_events);
                if(bad_events!=0)begin
                    stable_blocked<=1;
                    if(first_bad_reason==0)first_bad_reason<=first_event_error;
                    last_bad_reason<=last_event_error;
                end
            end
        end
    end
endmodule
`default_nettype wire
