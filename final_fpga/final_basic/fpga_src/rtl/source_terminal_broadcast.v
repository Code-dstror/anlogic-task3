`timescale 1ns/1ps
// Borrow the existing fence capsule and existing admitted capsule; store no payload.
module source_terminal_broadcast (
    input wire clk,rst_n,frame_begin,frame_owned,cancel,
    input wire [1:0] frame_required,
    input wire [575:0] owner_context,source_context,
    input wire [63:0] owner_tag,source_tag,
    input wire source_valid,source_ok,output wire source_ready,
    input wire [1:0] consumer_owner_match,consumer_ready,consumer_skip,
    input wire [1:0] consumer_cancel_done,
    output wire [1:0] consumer_valid,consumer_cancel,
    output wire native_done,native_failed,rejected,
    output wire [1:0] done_mask
);
    reg [1:0] required,done,cancel_sent;
    reg canceled;
    reg source_checked,source_exact;
    // Both heads are already held by their real owners. Check that borrowed
    // identity once, then use only the registered decision in READY/cancel.
    // Do not let a 640-bit comparison join the downstream pixel READY chain.
    wire authenticated=source_valid&&source_checked&&source_exact;
    wire cancel_mode=cancel||canceled||(authenticated&&!source_ok);
    wire [1:0] fires=consumer_valid&consumer_ready;
    wire [1:0] canceled_ack=cancel_sent&consumer_cancel_done;
    wire [1:0] progress=cancel_mode ? canceled_ack : (done|fires|consumer_skip);
    // Consumer witnesses can depend on downstream pixel READY. Only the
    // registered ledger may retire SOURCE and feed admission's terminal input.
    // On first cancellation, old positive bits are not cancellation witnesses.
    wire terminal_complete=((done&required)==required)&&(!cancel_mode||canceled);
    wire source_fire=source_valid&&source_ready;
    assign consumer_valid={2{rst_n&&!frame_begin&&authenticated&&!cancel_mode}}&required&~done&consumer_owner_match;
    // Cancel every required consumer, including one that already saw positive.
    assign consumer_cancel={2{rst_n&&!frame_begin&&frame_owned&&cancel_mode}}&required&~cancel_sent;
    assign source_ready=rst_n&&!frame_begin&&source_checked&&(!source_exact||terminal_complete);
    assign native_done=source_fire&&source_exact&&source_ok&&!cancel_mode;
    assign native_failed=source_fire&&source_exact&&cancel_mode;
    assign rejected=source_fire&&!source_exact;
    assign done_mask=done;
    always @(posedge clk)begin
        if(!rst_n)begin
            required<=0;done<=0;cancel_sent<=0;canceled<=0;
            source_checked<=0;source_exact<=0;
        end
        else begin
            if(frame_begin||source_fire||!source_valid)source_checked<=0;
            else if(!source_checked)begin
                source_checked<=1;
                source_exact<=frame_owned&&owner_tag!=0&&source_tag==owner_tag&&source_context==owner_context;
            end
            done<=progress&required;
            cancel_sent<=cancel_sent|consumer_cancel;
            if(frame_owned&&cancel_mode)canceled<=1;
            // A foreign terminal is diagnosed/consumed, but owns none of these
            // obligations. Only this frame's exact terminal may retire them.
            if(source_fire&&source_exact)begin required<=0;done<=0;cancel_sent<=0;canceled<=0;end
            if(frame_begin)begin required<=frame_required;done<=0;cancel_sent<=0;canceled<=0;end
        end
    end
endmodule
