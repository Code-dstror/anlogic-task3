`timescale 1ns / 1ps
// A continuously clocked supervisor plus asynchronous incident capture.
// It retains a loss even when user_clk stops and link/BME recovers before it resumes.
module c2h_link_supervisor (
    input wire i_watch_clk, input wire i_user_clk, input wire i_recovery_reset_n,
    input wire i_link_up, input wire i_bme, input wire i_perst_n,
    input wire i_pll_lock, input wire i_core_reset_n,
    output wire o_fault, output wire o_ready
);
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] link_sync=0, bme_sync=0;
    reg link_armed=0, bme_armed=0;
    reg incident=1'b1;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] fault_sync=2'b11;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] ready_sync=0;
    wire ready_reset_n;
    reset_release_sync u_ready_reset(.i_clk(i_user_clk),
        .i_async_rst_n(i_recovery_reset_n),.o_rst_n(ready_reset_n));
    wire physical_good=i_link_up&&i_perst_n&&i_pll_lock&&i_core_reset_n;
    wire incident_n=(!link_armed||physical_good)&&(!bme_armed||i_bme);
    // The raw pin/status loss may be shorter than a watch-clock period.
    // Assert immediately, but hold SET until two watch edges have observed
    // recovery so incident's async pin never releases from a remote clock.
    // Match the asynchronous SET power-up state used by implementation.
    // Explicit cold recovery drains this pipe before admission is possible.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] incident_hold_pipe=2'b11;
    wire incident_held=incident_hold_pipe[1];
    always @(posedge i_watch_clk or negedge incident_n) begin
        if(!incident_n)incident_hold_pipe<=2'b11;
        else incident_hold_pipe<={incident_hold_pipe[0],1'b0};
    end
    always @(posedge i_watch_clk) begin
        if(!i_recovery_reset_n)begin
            link_sync<=0;bme_sync<=0;link_armed<=0;bme_armed<=0;
        end else begin
            link_sync<={link_sync[0],physical_good};
            bme_sync<={bme_sync[0],i_bme};
            // Training before the host ever enables BME is not an armed DMA
            // session. Once jointly armed, either loss remains sticky even
            // when BME/link returns or the user clock is stopped.
            if(link_sync[1]&&bme_sync[1])begin link_armed<=1;bme_armed<=1;end
        end
    end
    // One asynchronous SET input, synchronous recovery clear. Recovery must be
    // held for >=4 watch-clock cycles so arm bits clear before incident clears.
    always @(posedge i_watch_clk or posedge incident_held) begin
        if(incident_held)incident<=1;
        else if(!i_recovery_reset_n)incident<=0;
    end
    // Async assertion is retained regardless of whether the user clock runs.
    // Deassertion takes two user clocks, after explicit supervisor recovery.
    always @(posedge i_user_clk or posedge incident) begin
        if(incident)fault_sync<=2'b11;
        else fault_sync<={fault_sync[0],1'b0};
    end
    // The existing independent cold-release chain requires three USER edges;
    // fault_sync needs two to drain its implementation initial value. This
    // qualification never follows runtime readiness or application enable.
    assign o_fault=ready_reset_n&&fault_sync[1];
    always @(posedge i_user_clk or negedge ready_reset_n)begin
        if(!ready_reset_n)ready_sync<=0;
        else ready_sync<={ready_sync[0],link_armed&&bme_armed};
    end
    assign o_ready=ready_sync[1]&&!fault_sync[1];
endmodule
