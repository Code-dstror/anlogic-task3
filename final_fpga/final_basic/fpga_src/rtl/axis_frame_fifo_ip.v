`timescale 1ns / 1ps

// 封装异步FIFO的有效就绪流接口
module axis_frame_fifo_ip (
    // 源时钟与复位
    input  wire i_source_clk,
    input  wire i_source_rst_n,

    // 源侧数据流
    input  wire [146:0] i_source_data,
    input  wire i_source_valid,
    output wire o_source_ready,
    output wire o_source_reset_done, // 源侧FIFO复位完成指示

    // 目的时钟与复位
    input  wire i_sink_clk,
    input  wire i_sink_rst_n,

    // 目的侧数据流
    output wire [146:0] o_sink_data,
    output wire o_sink_valid,
    input  wire i_sink_ready,
    output wire o_sink_reset_done
);

    wire fifo_async_reset_n;
    (* preserve="true" *) reg fifo_write_reset=1'b1;
    (* preserve="true" *) reg fifo_read_reset=1'b1;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] source_reset_release_pipe;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] sink_reset_release_pipe;
    wire fifo_write_enable;
    wire fifo_read_enable;
    wire fifo_valid;
    wire fifo_full;
    wire fifo_empty;
    wire fifo_almost_full;
    wire fifo_almost_empty;
    wire [9:0] fifo_write_used;
    wire [9:0] fifo_read_used;
    wire fifo_overflow;
    wire fifo_underflow;
    wire fifo_write_success;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;
    wire [146:0] fifo_read_data;
    (* preserve="true" *) reg source_run=1'b0;
    (* preserve="true" *) reg sink_run=1'b0;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] source_peer_release=2'b00;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] sink_peer_release=2'b00;
    reg source_pending=1'b0;
    reg [146:0] source_word;
    reg [146:0] read_buffer[0:1];
    reg read_head,read_tail;
    reg [1:0] read_count;
    wire source_fire=i_source_valid && o_source_ready;
    wire sink_fire=o_sink_valid && i_sink_ready;

    // Public isolation asserts asynchronously. The official FIFO reset pins
    // change only after their own clock edges, including assertion. Neither
    // port may reopen before the peer has actually sampled its local reset.
    // Its three-edge release MSB proves that reset was sampled and persists
    // until the next cohort, including when either clock subsequently stops.
    // Peer samples clear on local edges while that local release remains low.
    always @(posedge i_source_clk)begin
        if(!source_reset_release_pipe[2])source_peer_release<=2'b00;
        else source_peer_release<={source_peer_release[0],sink_reset_release_pipe[2]};
        if(!source_reset_release_pipe[2])fifo_write_reset<=1'b1;
        else if(source_peer_release[1])fifo_write_reset<=1'b0;
        source_run<=!fifo_write_reset && fifo_write_reset_done;
        if(!source_reset_release_pipe[2] || !source_run)source_pending<=1'b0;
        else begin
            if(fifo_write_enable)source_pending<=1'b0;
            if(source_fire)begin source_pending<=1'b1;source_word<=i_source_data;end
        end
    end
    always @(posedge i_sink_clk)begin
        if(!sink_reset_release_pipe[2])sink_peer_release<=2'b00;
        else sink_peer_release<={sink_peer_release[0],source_reset_release_pipe[2]};
        if(!sink_reset_release_pipe[2])fifo_read_reset<=1'b1;
        else if(sink_peer_release[1])fifo_read_reset<=1'b0;
    end

    // Prefetch into two local words independently of consumer READY. The
    // official FIFO's FWFT CE/read-pointer no longer sees the complete record
    // decoder / native-DMA permission cone. Either reset still cancels this
    // cohort through the unchanged asynchronous release pipes.
    always @(posedge i_sink_clk)begin
        sink_run<=!fifo_read_reset && fifo_read_reset_done;
        if(!sink_reset_release_pipe[2] || !sink_run)begin
            read_head<=0;read_tail<=0;read_count<=0;
        end else begin
            if(fifo_read_enable)begin
                read_buffer[read_tail]<=fifo_read_data;read_tail<=!read_tail;
            end
            if(sink_fire)read_head<=!read_head;
            // Exact modulo-four occupancy update for all four old values.
            // Carry/borrow is expressed directly so late consumer permission
            // does not pass an add/subtract result mux on the two-bit bank.
            read_count[0]<=read_count[0]^(fifo_read_enable^sink_fire);
            read_count[1]<=read_count[1]^((fifo_read_enable&&!sink_fire&&read_count[0])||
                (!fifo_read_enable&&sink_fire&&!read_count[0]));
        end
    end

    // 任一时钟域复位都会清空跨域FIFO
    assign fifo_async_reset_n = i_source_rst_n && i_sink_rst_n;
    // 完成状态由本域释放链门控；两条链仍接受同一个异步断言。
    // 不把远端复位释放Q组合送入下游本域RAM的读写使能。
    assign o_source_reset_done = source_reset_release_pipe[2] && source_run;
    assign o_sink_reset_done = sink_reset_release_pipe[2] && sink_run;
    assign o_source_ready = o_source_reset_done && (!source_pending || fifo_write_enable);
    assign fifo_write_enable = source_run && source_pending && !fifo_full;
    assign fifo_read_enable = sink_run && fifo_valid && !fifo_empty && read_count<2;
    assign o_sink_valid = o_sink_reset_done && read_count!=0;
    assign o_sink_data = read_buffer[read_head];

    // 任一外部复位都异步清零两域释放链，随后各等待三个本地时钟边沿
    // 在源时钟域同步释放FIFO复位
    always @(posedge i_source_clk or negedge fifo_async_reset_n) begin
        if (!fifo_async_reset_n)
            source_reset_release_pipe <= 3'b000;
        else
            source_reset_release_pipe <= {source_reset_release_pipe[1:0],
                                          1'b1};
    end

    // 在目的时钟域同步释放FIFO复位
    always @(posedge i_sink_clk or negedge fifo_async_reset_n) begin
        if (!fifo_async_reset_n)
            sink_reset_release_pipe <= 3'b000;
        else
            sink_reset_release_pipe <= {sink_reset_release_pipe[1:0],
                                        1'b1};
    end

    // TD 官方配置固定为147位、512深度、双时钟预读，包装层只负责流握手
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
        .afull(fifo_almost_full),
        .aempty(fifo_almost_empty),
        .wrusedw(fifo_write_used),
        .rdusedw(fifo_read_used),
        .overflow(fifo_overflow),
        .underflow(fifo_underflow),
        .wr_success(fifo_write_success),
        .wr_rst_done(fifo_write_reset_done),
        .rd_rst_done(fifo_read_reset_done)
    );

    wire unused_fifo_status;
    assign unused_fifo_status = fifo_almost_full ^ fifo_almost_empty ^
                                fifo_overflow ^ fifo_underflow ^
                                fifo_write_success ^ ^fifo_write_used ^
                                ^fifo_read_used;

endmodule
