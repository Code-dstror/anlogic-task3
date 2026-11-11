`timescale 1ns / 1ps

// RAW token CDC; all payload storage and pointer crossing stay in official IP.
module raw_capture_fifo_eram_safe (
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
    // Dedicated asynchronous-assert/local-release chains. Keep all stages
    // identifiable so scoped remote-reset ASR constraints remain auditable.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] source_reset_release_pipe;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] sink_reset_release_pipe;
    reg source_run;
    reg sink_run;
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
    reg source_pending;
    reg [146:0] source_word;
    reg [146:0] read_buffer[0:1];
    reg read_head,read_tail;
    reg [1:0] read_count;
    wire [146:0] fifo_read_data;
    wire source_fire=i_source_valid&&o_source_ready;
    wire sink_fire=o_sink_valid&&i_sink_ready;
    wire [9:0] fifo_available;
    // Synchronous elastic boundaries isolate user ASYNC state and READY.
    always @(posedge i_source_clk)begin
        source_run<=source_reset_release_pipe[2]&&fifo_write_reset_done;
        if(!source_reset_release_pipe[2]||!source_run)source_pending<=0;
        else begin
            if(fifo_write_enable)source_pending<=0;
            if(source_fire)begin source_pending<=1;source_word<=i_source_data;end
        end
    end
    always @(posedge i_sink_clk)begin
        sink_run<=sink_reset_release_pipe[2]&&fifo_read_reset_done;
        if(!sink_reset_release_pipe[2]||!sink_run)begin
            read_head<=0;read_tail<=0;read_count<=0;read_handshake_delayed<=0;
        end else begin
            read_handshake_delayed<=fifo_read_enable;
            if(fifo_read_enable)begin read_buffer[read_tail]<=fifo_read_data;read_tail<=!read_tail;end
            if(sink_fire)read_head<=!read_head;
            case({fifo_read_enable,sink_fire})
                2'b10:read_count<=read_count+1'b1;
                2'b01:read_count<=read_count-1'b1;
                default:begin end
            endcase
        end
    end
    wire [9:0] corrected_read_used;

    assign fifo_async_reset_n = i_source_rst_n && i_sink_rst_n;
    // Keep the public three-posedge reset evidence unchanged. Release the
    // vendor ASR pins on each port's own falling edge, with asynchronous
    // assertion inherited from that same local pipe. No remote reset feeds
    // these new endpoints and no local recovery/removal path is cut.
    (* preserve="true" *) reg source_ip_release=1'b0;
    (* preserve="true" *) reg sink_ip_release=1'b0;
    always @(negedge i_source_clk or negedge source_reset_release_pipe[2])begin
        if(!source_reset_release_pipe[2])source_ip_release<=1'b0;
        else source_ip_release<=1'b1;
    end
    always @(negedge i_sink_clk or negedge sink_reset_release_pipe[2])begin
        if(!sink_reset_release_pipe[2])sink_ip_release<=1'b0;
        else sink_ip_release<=1'b1;
    end
    assign fifo_write_reset = !source_ip_release;
    assign fifo_read_reset = !sink_ip_release;
    assign o_source_reset_done = source_reset_release_pipe[2] &&
                                 source_run;
    assign o_sink_reset_done = sink_reset_release_pipe[2] &&
                               sink_run;
    assign o_source_ready = o_source_reset_done && (!source_pending||fifo_write_enable);
    assign o_sink_valid = o_sink_reset_done && read_count!=0;
    assign o_sink_data=read_buffer[read_head];
    assign fifo_write_enable = source_pending && source_run && !fifo_full;
    assign fifo_read_enable = sink_run && fifo_valid && !fifo_empty && read_count<2;
    // Official rdusedw contains the FWFT head but reflects a read one cycle
    // late. Remove that already-consumed token; a valid prefetched head can
    // appear one cycle before rdusedw catches up and independently proves one.
    assign corrected_read_used =
        (fifo_read_used > {9'd0, read_handshake_delayed}) ?
        fifo_read_used - {9'd0, read_handshake_delayed} : 10'd0;
    assign fifo_available = !fifo_valid||fifo_empty ? 10'd0 :
        (corrected_read_used==0 ? 10'd1 : corrected_read_used);
    assign o_available_count = !o_sink_valid ? 10'd0 : fifo_available+{8'd0,read_count};

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

    camera_packet_fifo_147x512 u_pcie_axis_async_fifo (
        .wrst(fifo_write_reset),
        .rrst(fifo_read_reset),
        .clkw(i_source_clk),
        .clkr(i_sink_clk),
        .we(fifo_write_enable),
        .di(source_word),
        .re(fifo_read_enable),
        .dout(fifo_read_data),
        .valid(fifo_valid),
        .full_flag(fifo_full),
        .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(), .rdusedw(fifo_read_used),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done),
        .rd_rst_done(fifo_read_reset_done)
    );

endmodule
