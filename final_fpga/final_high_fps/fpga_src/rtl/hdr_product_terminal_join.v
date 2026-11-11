`timescale 1ns/1ps
// The admitted JPEG consumer treats SOURCE as an immediate end-of-input. Join
// authentic upstream SOURCE with the actual shared-foreground terminal, then
// wait for every presented downstream pixel to drain before emitting it.
module hdr_product_terminal_join(
    input wire clk,rst_n,begin_frame,
    input wire source_done,source_failed,
    input wire foreground_done,foreground_failed,
    input wire data_quiet,error_drain_quiet,
    output reg done,failed,output wire busy,output reg fault
);
    reg owned,source_seen,foreground_seen,error_seen;
    wire source_now=source_seen||source_done||source_failed;
    wire foreground_now=foreground_seen||foreground_done||foreground_failed||
        ((error_seen||source_failed)&&error_drain_quiet);
    assign busy=owned;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin owned<=0;source_seen<=0;foreground_seen<=0;error_seen<=0;done<=0;failed<=0;fault<=0;end
        else begin
            done<=0;failed<=0;
            if(begin_frame)begin
                if(owned)fault<=1;
                else begin owned<=1;source_seen<=0;foreground_seen<=0;error_seen<=0;end
            end
            if(owned&&!fault)begin
                if(source_done||source_failed)source_seen<=1;
                if(foreground_done||foreground_failed)foreground_seen<=1;
                if(source_failed||foreground_failed)error_seen<=1;
                if(source_now&&foreground_now&&data_quiet&&!begin_frame)begin
                    owned<=0;
                    if(error_seen||source_failed||foreground_failed)failed<=1;else done<=1;
                end
            end
        end
    end
endmodule
