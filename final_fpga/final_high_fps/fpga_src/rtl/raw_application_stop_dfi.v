`timescale 1ns / 1ps
`default_nettype none

// Fail-closed application STOP in the cold DFI ownership domain.
// Remote application reset is used only at asynchronous control pins.
// Its release cannot reopen admission before local qualification and drain.
module raw_application_stop_dfi (
    input wire i_dfi_clk,
    input wire i_cold_rst_n,
    input wire i_pixel_rst_n,
    input wire i_dfi_rst_n,
    input wire i_quiet,
    output reg o_stop
);
    wire app_run_n = i_cold_rst_n && i_pixel_rst_n && i_dfi_rst_n;
    reg [2:0] run_release_pipe;

    // This private chain drives only the local STOP register's decision.
    // It does not drive payload, READY, owner reset, or any new grant directly.
    always @(posedge i_dfi_clk or negedge app_run_n) begin
        if (!app_run_n)
            run_release_pipe <= 3'b000;
        else
            run_release_pipe <= {run_release_pipe[1:0], 1'b1};
    end

    // Assertion immediately closes admission even if a source clock stopped.
    // Deassertion is a DFI edge after three qualifying DFI edges AND actual
    // owner/read/write/consumer quiet. A missing SAFE proof keeps STOP asserted.
    // The output FF has the same immediate assertion through the
    // asynchronous chain, and now a DFI-synchronous reset release.
    always @(posedge i_dfi_clk or negedge run_release_pipe[2]) begin
        if (!run_release_pipe[2])
            o_stop <= 1'b1;
        else if (run_release_pipe[2] && i_quiet)
            o_stop <= 1'b0;
    end
endmodule

`default_nettype wire
