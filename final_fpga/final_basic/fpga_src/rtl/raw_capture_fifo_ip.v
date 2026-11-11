`timescale 1ns / 1ps

// RAW token CDC; all payload storage and pointer crossing stay in official IP.
module raw_capture_fifo_ip (
    input  wire         i_source_clk,
    input  wire         i_source_rst_n,
    input  wire [146:0] i_source_data,
    input  wire         i_source_valid,
    output wire         o_source_ready,
    output wire         o_source_reset_done,
    input  wire         i_sink_clk,
    input  wire         i_sink_rst_n,
    output wire [146:0] o_sink_data,
    output wire         o_sink_valid,
    input  wire         i_sink_ready,
    output wire [9:0]   o_available_count,
    output wire         o_sink_reset_done
);

    wire fifo_async_reset_n;
    reg [2:0] source_reset_release_pipe;
    reg [2:0] sink_reset_release_pipe;
    wire fifo_write_reset;
    wire fifo_read_reset;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;
    wire fifo_valid;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire [9:0] fifo_read_used;
    reg read_handshake_delayed;
    wire [9:0] corrected_read_used;

    assign fifo_async_reset_n = i_source_rst_n && i_sink_rst_n;
    assign fifo_write_reset = !source_reset_release_pipe[2];
    assign fifo_read_reset = !sink_reset_release_pipe[2];
    assign o_source_reset_done = source_reset_release_pipe[2] &&
                                 fifo_write_reset_done;
    assign o_sink_reset_done = sink_reset_release_pipe[2] &&
                               fifo_read_reset_done;
    assign o_source_ready = o_source_reset_done && !fifo_full;
    assign o_sink_valid = o_sink_reset_done && fifo_valid && !fifo_empty;
    assign fifo_write_enable = i_source_valid && o_source_ready;
    assign fifo_read_enable = o_sink_valid && i_sink_ready;
    // Official rdusedw contains the FWFT head but reflects a read one cycle
    // late. Remove that already-consumed token; a valid prefetched head can
    // appear one cycle before rdusedw catches up and independently proves one.
    assign corrected_read_used =
        (fifo_read_used > {9'd0, read_handshake_delayed}) ?
        fifo_read_used - {9'd0, read_handshake_delayed} : 10'd0;
    assign o_available_count = !o_sink_valid ? 10'd0 :
                               (corrected_read_used == 10'd0 ? 10'd1 :
                                corrected_read_used);

    // The reset assertion is shared; release never depends on a remote clock.
    always @(posedge i_source_clk or negedge fifo_async_reset_n) begin
        if (!fifo_async_reset_n)
            source_reset_release_pipe <= 3'b000;
        else
            source_reset_release_pipe <= {source_reset_release_pipe[1:0], 1'b1};
    end

    always @(posedge i_sink_clk or negedge fifo_async_reset_n) begin
        if (!fifo_async_reset_n)
            sink_reset_release_pipe <= 3'b000;
        else
            sink_reset_release_pipe <= {sink_reset_release_pipe[1:0], 1'b1};
    end

    always @(posedge i_sink_clk or negedge fifo_async_reset_n) begin
        if (!fifo_async_reset_n)
            read_handshake_delayed <= 1'b0;
        else if (!o_sink_reset_done)
            read_handshake_delayed <= 1'b0;
        else
            read_handshake_delayed <= fifo_read_enable;
    end

    camera_packet_fifo_147x512 u_pcie_axis_async_fifo (
        .wrst(fifo_write_reset),
        .rrst(fifo_read_reset),
        .clkw(i_source_clk),
        .clkr(i_sink_clk),
        .we(fifo_write_enable),
        .di(i_source_data),
        .re(fifo_read_enable),
        .dout(o_sink_data),
        .valid(fifo_valid),
        .full_flag(fifo_full),
        .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(), .rdusedw(fifo_read_used),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done),
        .rd_rst_done(fifo_read_reset_done)
    );

endmodule
