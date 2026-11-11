`timescale 1ns/1ps
// Slow toggles cross to sys_clk; activity means edges observed in a 10 ms window.
module fpga_debug_clocks #(
    parameter integer WINDOW_CYCLES=250000
)(input wire i_clk, input wire i_rst_n, input wire [5:0] i_clocks,
  output reg [5:0] o_alive);
    wire [5:0] toggles;
    genvar g;
    generate for(g=0;g<6;g=g+1) begin: clock_counter
        reg [10:0] count;
        wire local_rst_n;
        reset_release_sync u_reset (.i_clk(i_clocks[g]),
            .i_async_rst_n(i_rst_n), .o_rst_n(local_rst_n));
        always @(posedge i_clocks[g] or negedge local_rst_n)
            if(!local_rst_n) count<=0; else count<=count+1'b1;
        assign toggles[g]=count[10];
    end endgenerate
    reg [5:0] meta, sync, previous, seen;
    reg [17:0] window_count;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            meta<=0;sync<=0;previous<=0;seen<=0;window_count<=0;o_alive<=0;
        end else begin
            meta<=toggles;sync<=meta;previous<=sync;
            if(window_count==WINDOW_CYCLES-1) begin
                o_alive<=seen | (sync^previous);seen<=0;window_count<=0;
            end else begin seen<=seen | (sync^previous);window_count<=window_count+1'b1;end
        end
    end
endmodule
