`timescale 1ns/1ps
// LOCAL stopping uses actual admissions and disjoint successful/failed terminals.
// All resets are independent debug resets; an application abort cannot erase debt.
module fpga_debug_local_stop (
    input wire i_sys_clk,
    input wire i_sys_rst_n,
    input wire i_request,
    output wire o_ready,
    output wire o_done,
    input wire i_pixel_clk,
    input wire i_pixel_rst_n,
    input wire i_pixel_active,
    input wire i_pixel_quiet,
    input wire i_start_fire,
    output wire o_pause_new_frames,
    input wire i_dfi_clk,
    input wire i_dfi_rst_n,
    input wire i_dfi_active,
    input wire i_dfi_quiet,
    input wire i_retire_fire,
    input wire i_failed_write_fire
);
    reg [1:0] request_pixel;
    reg [31:0] admitted_count, frozen_count;
    reg admission_overflow, pixel_ack;
    reg [2:0] pixel_ack_dfi;
    reg [31:0] frozen_meta, frozen_sync, settled_count;
    reg settlement_overflow, dfi_done;
    reg [1:0] done_sys;

    assign o_pause_new_frames=request_pixel[1];
    assign o_ready=!i_request && !done_sys[1];
    assign o_done=i_request && done_sys[1];

    // The count is frozen before ACK crosses. Two data registers followed by
    // the third ACK register provide a bundled-data settling cycle in DFI.
    always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
        if(!i_pixel_rst_n) begin
            request_pixel<=0; admitted_count<=0; frozen_count<=0;
            admission_overflow<=0; pixel_ack<=0;
        end else begin
            request_pixel<={request_pixel[0],i_request};
            if(i_start_fire) begin
                if(&admitted_count) admission_overflow<=1;
                else admitted_count<=admitted_count+1'b1;
            end
            if(!request_pixel[1]) pixel_ack<=0;
            else if(!i_pixel_active || !i_pixel_quiet || i_start_fire || admission_overflow)
                pixel_ack<=0;
            else if(!pixel_ack) begin
                frozen_count<=admitted_count;
                pixel_ack<=1;
            end
        end
    end

    // A missing DDR B, a stalled record tail, or an unretired source admission
    // keeps either real quiescence or this equality false. Failed admissions
    // settle only on the real drained writer ACK, never on quiet alone.
    // RETIRE and failed ACK may belong to different slots on the same edge.
    always @(posedge i_dfi_clk or negedge i_dfi_rst_n) begin
        if(!i_dfi_rst_n) begin
            pixel_ack_dfi<=0; frozen_meta<=0; frozen_sync<=0;
            settled_count<=0; settlement_overflow<=0; dfi_done<=0;
        end else begin
            pixel_ack_dfi<={pixel_ack_dfi[1:0],pixel_ack};
            frozen_meta<=frozen_count; frozen_sync<=frozen_meta;
            if(i_retire_fire && i_failed_write_fire) begin
                if(settled_count>=32'hfffffffe) settlement_overflow<=1;
                else settled_count<=settled_count+32'd2;
            end else if(i_retire_fire || i_failed_write_fire) begin
                if(&settled_count) settlement_overflow<=1;
                else settled_count<=settled_count+1'b1;
            end
            dfi_done<=pixel_ack_dfi[2] && i_dfi_active && i_dfi_quiet &&
                !i_retire_fire && !i_failed_write_fire && !settlement_overflow && frozen_sync==settled_count;
        end
    end

    always @(posedge i_sys_clk or negedge i_sys_rst_n) begin
        if(!i_sys_rst_n) done_sys<=0;
        else done_sys<={done_sys[0],dfi_done};
    end
endmodule
