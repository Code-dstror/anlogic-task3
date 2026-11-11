`timescale 1ns/1ps
// PIX-domain continuity quarantine. A healthy, identity-bearing FS establishes
// continuity; PHY training before that point has no published SOURCE to protect.
// After a fault, a consumed healthy FS may rearm only when the actual old
// source/product owners are quiet. The caller supplies consumed FS events.
module production_source_identity_guard (
    input wire clk,rst_n,
    input wire phy_ready,receive_fault,parser_identity_fault,
    input wire i_recovery_quiet,
    input wire event_valid,input wire [1:0] event_kind,input wire event_identity_valid,
    output reg quarantine
);
    reg cohort_started;
    wire fs_present=event_valid && event_kind==0;
    wire healthy_fs=fs_present && event_identity_valid && phy_ready &&
        !receive_fault && !parser_identity_fault;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin cohort_started<=0;quarantine<=0;end
        else begin
            if(healthy_fs)cohort_started<=1;
            // A fault coincident with the first FS is not startup noise.
            // Invalid identities never establish a recoverable new cohort.
            if(parser_identity_fault || (fs_present&&!event_identity_valid) ||
               ((cohort_started||fs_present)&&(!phy_ready||receive_fault)))quarantine<=1;
            else if(i_recovery_quiet && healthy_fs)quarantine<=0;
        end
    end
endmodule
