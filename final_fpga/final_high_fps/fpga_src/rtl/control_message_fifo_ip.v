`timescale 1ns / 1ps

// Serialize complete control messages through the official narrow async FIFO.
module control_message_fifo_ip #(
    parameter integer MESSAGE_WIDTH=147,
    parameter integer BORROW_SOURCE=0
) (
    input wire i_source_clk,
    input wire i_source_rst_n,
    input wire [MESSAGE_WIDTH-1:0] i_source_data,
    input wire i_source_valid,
    output wire o_source_ready,
    output wire o_source_reset_done,
    input wire i_sink_clk,
    input wire i_sink_rst_n,
    output wire [MESSAGE_WIDTH-1:0] o_sink_data,
    output wire o_sink_valid,
    input wire i_sink_ready,
    output wire o_sink_reset_done,
    // Optional local-clock taps. Each strobe is a real accepted 40-bit FIFO flit.
    output wire o_sink_flit_read,
    output wire [39:0] o_sink_flit_data,
    output wire [4:0] o_sink_flit_index
);
    localparam integer FLIT_COUNT=(MESSAGE_WIDTH+39)/40;
    localparam integer PADDED_WIDTH=FLIT_COUNT*40;
    localparam integer INDEX_WIDTH=FLIT_COUNT<=2 ? 1 :
        (FLIT_COUNT<=4 ? 2 : (FLIT_COUNT<=8 ? 3 : (FLIT_COUNT<=16 ? 4 : 5)));
    // The official FIFO configuration stays 40x512 for every legal message size.
    generate if (MESSAGE_WIDTH < 1 || MESSAGE_WIDTH > 1280) begin : invalid_width
        initial begin
            $display("ERROR: control_message_fifo_ip MESSAGE_WIDTH must be 1..1280");
            $finish;
        end
    end endgenerate
    wire fifo_async_reset_n;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] source_reset_release_pipe;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] sink_reset_release_pipe;
    wire source_local_rst_n = source_reset_release_pipe[2];
    wire sink_local_rst_n = sink_reset_release_pipe[2];
    (* preserve="true" *) reg source_run=1'b0;
    (* preserve="true" *) reg sink_run=1'b0;
    (* preserve="true" *) reg fifo_write_reset=1'b1;
    (* preserve="true" *) reg fifo_read_reset=1'b1;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] source_peer_release=2'b00;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] sink_peer_release=2'b00;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_valid;
    wire [39:0] fifo_read_data;
    wire [39:0] fifo_write_data;
    wire fifo_write_enable;
    wire fifo_read_enable;
    reg write_pending;
    reg [39:0] write_word;

    // One accepted message remains locked until all derived flits are written.
    wire [MESSAGE_WIDTH-1:0] source_message;
    wire source_busy;
    wire source_flit_fire = source_run && (!write_pending || fifo_write_enable) &&
        (BORROW_SOURCE!=0 ? i_source_valid : source_busy);
    reg [INDEX_WIDTH-1:0] source_flit_index;
    wire [PADDED_WIDTH-1:0] padded_source_message =
        {{(PADDED_WIDTH-MESSAGE_WIDTH){1'b0}},source_message};
    // The assembly register also holds the sole published output message.
    reg [PADDED_WIDTH-1:0] sink_message;
    reg sink_message_valid;
    reg [INDEX_WIDTH-1:0] sink_flit_index;

    assign fifo_async_reset_n = i_source_rst_n && i_sink_rst_n;
    assign o_source_reset_done = source_local_rst_n && source_run;
    assign o_sink_reset_done = sink_local_rst_n && sink_run;
    assign o_source_ready = o_source_reset_done && (BORROW_SOURCE!=0 ?
        ((!write_pending || fifo_write_enable) && source_flit_index==FLIT_COUNT-1) : !source_busy);
    assign fifo_write_enable = source_run && write_pending && !fifo_full;
    assign fifo_read_enable = sink_run && !sink_message_valid &&
                              fifo_valid && !fifo_empty;
    assign o_sink_data = sink_message[MESSAGE_WIDTH-1:0];
    assign o_sink_valid = o_sink_reset_done && sink_message_valid;
    assign o_sink_flit_read = fifo_read_enable;
    assign o_sink_flit_data = fifo_read_data;
    assign o_sink_flit_index = sink_flit_index;

    // Both domains see asynchronous assertion; release uses only local edges.
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

    // Reset assertion/release at the official RAM-facing ports is clocked.
    // Public ready/valid still close asynchronously through local_rst_n.
    // A release-chain MSB rises only after three local edges have held the
    // official port in reset. Unlike the FIFO reset pin, it stays high for the
    // entire cohort, so a stopped peer cannot miss that proof. Clear the peer
    // sample synchronously during those same local edges before using it.
    always @(posedge i_source_clk)begin
        if(!source_local_rst_n)source_peer_release<=2'b00;
        else source_peer_release<={source_peer_release[0],sink_local_rst_n};
        if(!source_local_rst_n)fifo_write_reset<=1'b1;
        else if(source_peer_release[1])fifo_write_reset<=1'b0;
    end
    always @(posedge i_sink_clk)begin
        if(!sink_local_rst_n)sink_peer_release<=2'b00;
        else sink_peer_release<={sink_peer_release[0],source_local_rst_n};
        if(!sink_local_rst_n)fifo_read_reset<=1'b1;
        else if(sink_peer_release[1])fifo_read_reset<=1'b0;
    end

    // Zero extension defines canonical padding in the final partial flit.
    assign fifo_write_data = write_word;
    always @(posedge i_source_clk) begin
        source_run <= !fifo_write_reset && fifo_write_reset_done;
        if (!source_local_rst_n || !source_run)
            write_pending <= 1'b0;
        else begin
            if (fifo_write_enable) write_pending <= 1'b0;
            if (source_flit_fire) begin
                write_pending <= 1'b1;
                write_word <= padded_source_message[source_flit_index*40 +: 40];
            end
        end
    end
    always @(posedge i_sink_clk) begin
        sink_run <= !fifo_read_reset && fifo_read_reset_done;
    end

    generate if(BORROW_SOURCE!=0) begin : g_borrow_source
        assign source_message=i_source_data;
        assign source_busy=i_source_valid || source_flit_index!=0;
        always @(posedge i_source_clk) begin
            if(!source_local_rst_n || !source_run) source_flit_index<=0;
            else if(source_flit_fire) begin
                if(source_flit_index==FLIT_COUNT-1) source_flit_index<=0;
                else source_flit_index<=source_flit_index+1'b1;
            end
        end
    end else begin : g_capture_source
    reg [MESSAGE_WIDTH-1:0] captured_message;
    reg captured_busy;
    assign source_message=captured_message;
    assign source_busy=captured_busy;
    // Functional state releases with its local chain, never a remote reset Q.
    always @(posedge i_source_clk) begin
        if (!source_local_rst_n || !source_run) begin
            captured_busy <= 1'b0;
            source_flit_index <= 0;
        end else if (i_source_valid && o_source_ready) begin
            captured_message <= i_source_data;
            captured_busy <= 1'b1;
            source_flit_index <= 0;
        end else if (source_flit_fire) begin
            if (source_flit_index == FLIT_COUNT-1) begin
                captured_busy <= 1'b0;
                source_flit_index <= 0;
            end else
                source_flit_index <= source_flit_index + 1'b1;
        end
    end
    end endgenerate

    always @(posedge i_sink_clk) begin
        if (!sink_local_rst_n || !sink_run) begin
            sink_message_valid <= 1'b0;
            sink_flit_index <= 0;
        end else if (o_sink_valid && i_sink_ready)
            sink_message_valid <= 1'b0;
        else if (fifo_read_enable) begin
            sink_message[sink_flit_index*40 +: 40] <= fifo_read_data;
            if (sink_flit_index == FLIT_COUNT-1) begin
                sink_message_valid <= 1'b1;
                sink_flit_index <= 0;
            end else sink_flit_index <= sink_flit_index + 1'b1;
        end
    end

    control_fifo_40x512 u_control_async_fifo (
        .wrst(fifo_write_reset), .rrst(fifo_read_reset),
        .clkw(i_source_clk), .clkr(i_sink_clk),
        .we(fifo_write_enable), .di(fifo_write_data),
        .re(fifo_read_enable), .dout(fifo_read_data),
        .valid(fifo_valid), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(), .rdusedw(),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done), .rd_rst_done(fifo_read_reset_done)
    );
endmodule
