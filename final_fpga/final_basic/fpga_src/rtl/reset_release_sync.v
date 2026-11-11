`timescale 1ns / 1ps

// 在本地时钟域同步释放异步复位
module reset_release_sync #(
    parameter integer FALLING_RELEASE=0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_async_rst_n,
    output wire o_rst_n
);
    // Keep the release stages as an identifiable CDC boundary. Equivalent
    // reset chains must not merge into ordinary state registers: the SDC
    // exceptions name only this chain, while its local fanout stays timed.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] release_pipe;

    // 异步置位复位流水线并在本地时钟逐级释放
    always @(posedge i_clk or negedge i_async_rst_n) begin
        if (!i_async_rst_n)
            release_pipe <= 3'b000;
        else
            release_pipe <= {release_pipe[1:0], 1'b1};
    end

    // 复位流水线末级控制本地逻辑释放
    generate if(FALLING_RELEASE!=0)begin:g_falling_release
        // The existing local pipe still owns asynchronous assertion. Its
        // positive-edge release reaches this negative-edge stage half a
        // cycle before sampling. Both local recovery/removal legs stay timed.
        (* preserve="true" *) reg released_n=1'b0;
        always @(negedge i_clk or negedge release_pipe[2])begin
            if(!release_pipe[2])released_n<=1'b0;
            else released_n<=1'b1;
        end
        assign o_rst_n=released_n;
    end else begin:g_original_release
        assign o_rst_n=release_pipe[2];
    end endgenerate
endmodule
