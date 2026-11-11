`timescale 1ns/1ps
// Local mode owns the application reset and readiness. Host signals are only
// authoritative after an explicit mode switch. Endpoint reset is internal.
module fpga_debug_isolation (
    input wire i_clk, input wire i_debug_rst_n, input wire i_app_rst_n,
    input wire i_local, input wire i_run, input wire i_perst_n,
    input wire i_local_ready, input wire i_host_ready,
    input wire i_local_fault, input wire i_host_fault, input wire i_host_enable,
    input wire [3:0] i_fifo_done,
    input wire i_rearm_ready, input wire i_armed,
    output wire o_hard_rst_n, output wire o_pcie_rst_n,
    output wire o_ready, output wire o_fault, output wire o_enable,
    output wire [3:0] o_fifo_done
);
    reg local_enable;
    // The session controller's visible outputs include its asynchronous abort
    // mask, so sample them before they affect the local enable register.
    reg armed_meta, armed_sync, rearm_meta, rearm_sync;
    assign o_hard_rst_n = i_debug_rst_n && i_app_rst_n && (i_local || i_perst_n);
    assign o_pcie_rst_n = i_debug_rst_n && !i_local && i_perst_n;
    assign o_ready = i_local_ready && (i_local ? i_run : i_host_ready);
    assign o_fault = i_local_fault || (!i_local && i_host_fault);
    assign o_enable = i_local ? local_enable : i_host_enable;
    // Upper two bits belong exclusively to the unused DDR->PCIe FIFO.
    assign o_fifo_done = i_local ? {2'b11,i_fifo_done[1:0]} : i_fifo_done;
    always @(posedge i_clk or negedge o_hard_rst_n) begin
        if(!o_hard_rst_n) begin
            armed_meta<=0; armed_sync<=0;
            rearm_meta<=0; rearm_sync<=0;
            local_enable<=0;
        end else begin
            armed_meta<=i_armed; armed_sync<=armed_meta;
            rearm_meta<=i_rearm_ready; rearm_sync<=rearm_meta;
            if(!i_local || !i_run || (!armed_sync && !rearm_sync)) local_enable<=0;
            else if(rearm_sync) local_enable<=1;
        end
    end
endmodule
