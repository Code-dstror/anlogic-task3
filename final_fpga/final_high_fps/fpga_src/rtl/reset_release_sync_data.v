`timescale 1ns / 1ps

// 在本地时钟域同步释放异步复位
module reset_release_sync_data #(
    parameter integer DATA_RESET_COPIES = 3,
    parameter integer FALLING_RELEASE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_async_rst_n,
    output wire o_rst_n,
    output wire [(DATA_RESET_COPIES > 0 ? DATA_RESET_COPIES : 1)-1:0] o_data_rst_n
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

    generate if (FALLING_RELEASE != 0) begin : g_falling_release
        // Keep ASR on the falling edge while the data output gets a full
        // cycle to settle before the same first active rising sample.
        (* preserve="true" *) reg released_n = 1'b0;
        always @(negedge i_clk or negedge release_pipe[2]) begin
            if (!release_pipe[2])
                released_n <= 1'b0;
            else
                released_n <= 1'b1;
        end
        assign o_rst_n = released_n;
    end else begin : g_original_release
        assign o_rst_n = release_pipe[2];
    end endgenerate

    // Same-edge final-stage copies keep synchronous data qualification off
    // the global ASR tree. Each copy samples the original second stage, so
    // assertion and third-edge release match release_pipe[2].
    // These local distribution registers use preserve, rather than a new
    // ASYNC_REG bank that would force all copies next to the synchronizer.
    generate if (DATA_RESET_COPIES > 0) begin : g_data_release
        (* preserve="true" *) reg [DATA_RESET_COPIES-1:0] data_release_n;
        always @(posedge i_clk or negedge i_async_rst_n) begin
            if (!i_async_rst_n)
                data_release_n <= {DATA_RESET_COPIES{1'b0}};
            else
                data_release_n <= {DATA_RESET_COPIES{release_pipe[1]}};
        end
        assign o_data_rst_n = data_release_n;
    end else begin : g_no_data_release
        assign o_data_rst_n = release_pipe[2];
    end endgenerate
endmodule
