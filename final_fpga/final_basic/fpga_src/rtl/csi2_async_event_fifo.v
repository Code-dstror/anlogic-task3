`timescale 1ns / 1ps

// 在 CSI 字时钟和像素时钟之间缓存接收事件
module csi2_async_event_fifo #(
    // Zero preserves the existing compile-profile depth. Only a dedicated
    // continuously drained SDR receiver opts into the frozen 512-word IP.
    parameter integer FIFO_DEPTH = 0
) (
    // 写入时钟与复位
    input  wire        i_write_clk,
    input  wire        i_write_reset_n,
    // 写入接口
    input  wire [46:0] i_write_data,
    input  wire        i_write_valid,
    output wire        o_write_ready,
    // 读出时钟与复位
    input  wire        i_read_clk,
    input  wire        i_read_reset_n,
    // 读出接口
    output wire [46:0] o_read_data,
    output wire        o_read_valid,
    input  wire        i_read_ready
);
    // 两域复位均异步断言并在各自时钟域释放，FIFO 分别接收写域与读域复位
    // 读写端仅在本域复位完成后开放握手，避免跨域释放边沿直接传播
    wire cohort_reset_n=i_write_reset_n&&i_read_reset_n;
    reg [2:0] write_release,read_release;
    reg write_run,read_run;
    always @(posedge i_write_clk or negedge cohort_reset_n)begin
        if(!cohort_reset_n)write_release<=0;else write_release<={write_release[1:0],1'b1};
    end
    always @(posedge i_read_clk or negedge cohort_reset_n)begin
        if(!cohort_reset_n)read_release<=0;else read_release<={read_release[1:0],1'b1};
    end
    wire fifo_write_reset = !write_release[2];
    wire fifo_read_reset = !read_release[2];
    wire fifo_full;
    wire fifo_empty;
    wire fifo_valid;
    wire fifo_write_reset_done;
    wire fifo_read_reset_done;
`ifdef R8_STAGE1
    localparam integer PROFILE_DEPTH = 8192;
`else
    localparam integer PROFILE_DEPTH = 512;
`endif
    localparam integer SELECTED_DEPTH = FIFO_DEPTH == 0 ? PROFILE_DEPTH : FIFO_DEPTH;
    localparam integer FIFO_USED_WIDTH = SELECTED_DEPTH == 8192 ? 14 : 10;
    localparam [FIFO_USED_WIDTH-1:0] FIFO_WRITE_LIMIT = SELECTED_DEPTH - 8;
    generate if (SELECTED_DEPTH != 512 && SELECTED_DEPTH != 8192) begin : g_bad_depth
        CSI_EVENT_FIFO_REQUIRES_FROZEN_DEPTH_512_OR_8192 invalid_configuration();
    end endgenerate
    wire [FIFO_USED_WIDTH-1:0] fifo_write_used;
    wire [FIFO_USED_WIDTH-1:0] fifo_read_used;
    wire [46:0] fifo_read_data;
    wire fifo_read_enable;
    wire unused_status;
    reg write_pending;
    reg [46:0] write_word;
    wire fifo_write_ready=write_run&&!fifo_full&&(fifo_write_used<FIFO_WRITE_LIMIT);
    wire fifo_write_enable=write_pending&&fifo_write_ready;
    always @(posedge i_write_clk)begin
        write_run<=write_release[2]&&fifo_write_reset_done;
        if(!write_release[2]||!write_run)write_pending<=0;
        else begin
            if(fifo_write_enable)write_pending<=0;
            if(i_write_valid&&o_write_ready)begin write_pending<=1;write_word<=i_write_data;end
        end
    end

    assign o_write_ready = write_release[2]&&write_run&&(!write_pending||fifo_write_enable);
    // 两项本地缓冲把下游 READY 与 ERAM 读使能隔开，保留每周期一项的读取能力
    // 满时先消费已有头部，下一拍同时补入和消费；读指针始终只按实际握手推进
    reg [46:0] read_buffer [0:1];
    reg read_head;
    reg read_tail;
    reg [1:0] read_count;
    wire read_fire = o_read_valid && i_read_ready;

    assign fifo_read_enable = read_run && fifo_valid && !fifo_empty &&
                              (read_count < 2'd2);
    assign o_read_valid = read_release[2]&&read_run && (read_count != 2'd0);
    assign o_read_data = read_buffer[read_head];

    // 有效性由计数保护，数据寄存器不需要复位；只在官方预读头实际出队时保存
    always @(posedge i_read_clk) begin
        read_run <= read_release[2] && fifo_read_reset_done;
        if (fifo_read_enable)
            read_buffer[read_tail] <= fifo_read_data;
    end

    always @(posedge i_read_clk) begin
        if (!read_release[2]) begin
            read_head <= 1'b0;
            read_tail <= 1'b0;
            read_count <= 2'd0;
        end else if (!read_run) begin
            read_head <= 1'b0;
            read_tail <= 1'b0;
            read_count <= 2'd0;
        end else begin
            if (fifo_read_enable)
                read_tail <= !read_tail;
            if (read_fire)
                read_head <= !read_head;
            // Exact modulo-four inc/dec, including the unused 2'b11 state.
            // A simultaneous prefetch/pop holds both bits. Express carry and
            // borrow directly so late downstream READY does not traverse an
            // add/subtract result mux before the two occupancy registers.
            read_count[0] <= read_count[0] ^ fifo_read_enable ^ read_fire;
            read_count[1] <= read_count[1] ^
                ((fifo_read_enable ^ read_fire) && (read_count[0] ^ read_fire));
        end
    end

    // 两个深度均使用独立生成的 TD 官方双时钟预读 IP，保留八项近满裕量
    generate if (SELECTED_DEPTH == 8192) begin : g_depth8192
    camera_event_fifo_47x8192 u_event_fifo (
        .wrst(fifo_write_reset), .rrst(fifo_read_reset),
        .clkw(i_write_clk), .clkr(i_read_clk),
        .we(fifo_write_enable), .di(write_word),
        .re(fifo_read_enable), .dout(fifo_read_data),
        .valid(fifo_valid), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(fifo_write_used), .rdusedw(fifo_read_used),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done), .rd_rst_done(fifo_read_reset_done)
    );
    end else begin : g_depth512
    camera_event_fifo_47x512 u_event_fifo (
        .wrst(fifo_write_reset), .rrst(fifo_read_reset),
        .clkw(i_write_clk), .clkr(i_read_clk),
        .we(fifo_write_enable), .di(write_word),
        .re(fifo_read_enable), .dout(fifo_read_data),
        .valid(fifo_valid), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .afull(), .aempty(), .wrusedw(fifo_write_used), .rdusedw(fifo_read_used),
        .overflow(), .underflow(), .wr_success(),
        .wr_rst_done(fifo_write_reset_done), .rd_rst_done(fifo_read_reset_done)
    );
    end endgenerate

    assign unused_status = ^fifo_read_used;
endmodule
