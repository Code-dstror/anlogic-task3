`timescale 1ns / 1ps

// 协调基础设施复位和帧会话重新使能
module frame_session_controller #(
    // 存储与时序参数
    parameter integer DDR_RESET_CYCLES = 8
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_hard_reset_n,

    // 异步运行条件
    input wire i_infra_ready_async,
    input wire i_fatal_async,
    input wire i_app_enable_async,
    input wire [3:0] i_fifo_reset_done_async,

    // 分级复位与会话状态
    output wire o_ddr_reset_n,
    output wire o_data_reset_n,
    output wire o_transport_reset_n,
    output wire o_session_armed,
    output wire o_rearm_required, // 故障恢复后等待主机重新使能
    output wire o_rearm_ready
);
    localparam [2:0] RESET_ASSERT=0, WAIT_INFRA=1, RELEASE_DATA=2,
                     WAIT_FIFOS=3, WAIT_HOST_LO=4, WAIT_HOST_HI=5, RUN=6;
    reg [2:0] state, state_next;
    reg data_released, ddr_released, armed_owner;
    reg [15:0] reset_count;
    reg infra_meta, infra_sync, enable_meta, enable_sync;
    reg [3:0] fifo_done_meta, fifo_done_sync;
    reg abort_pending, abort_meta, abort_sync, rearm_required;
    wire abort_event = !i_hard_reset_n || i_fatal_async ||
                       (data_released && !i_infra_ready_async);
    // Stretch any asynchronous incident through two local edges. Only these
    // stages receive the raw event; the retained fault below releases its
    // asynchronous SET on the controller clock rather than on a remote edge.
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] abort_hold_pipe=2'b11;
    wire abort_held=abort_hold_pipe[1];
    always @(posedge i_clk or posedge abort_event) begin
        if(abort_event) abort_hold_pipe<=2'b11;
        else abort_hold_pipe<={abort_hold_pipe[0],1'b0};
    end
    // 按基础设施状态分级释放DDR复位
    assign o_ddr_reset_n = i_hard_reset_n && ddr_released;
    assign o_data_reset_n = data_released && !abort_event && !abort_pending;
    assign o_session_armed = armed_owner && !abort_event && !abort_pending;
    assign o_transport_reset_n = o_data_reset_n && o_session_armed;
    assign o_rearm_required = rearm_required;
    assign o_rearm_ready = state==WAIT_HOST_HI && infra_sync &&
                           &fifo_done_sync && !abort_event && !abort_pending;

    // 单次异步置位可捕获短于 sys_clk 周期的故障，时钟停止时也有效
    // 协调器观察到故障前，不得通过复位源侧故障寄存器清除锁存状态
    // 异步捕获基础设施中止事件
    always @(posedge i_clk or posedge abort_held) begin
        if (abort_held) abort_pending <= 1'b1;
        else if (state==RESET_ASSERT || state==WAIT_INFRA)
            abort_pending <= 1'b0;
    end
    // 将异步就绪使能和故障状态同步到系统时钟
    always @(posedge i_clk or negedge i_hard_reset_n) begin
        if (!i_hard_reset_n) begin
            infra_meta<=0; infra_sync<=0; enable_meta<=0; enable_sync<=0;
            fifo_done_meta<=0; fifo_done_sync<=0;
            abort_meta<=1; abort_sync<=1;
        end else begin
            // 故障锁存可在时钟沿之间置位
            // 仅第二级采样结果驱动同步会话状态机
            abort_meta<=abort_pending; abort_sync<=abort_meta;
            infra_meta<=i_infra_ready_async; infra_sync<=infra_meta;
            enable_meta<=i_app_enable_async; enable_sync<=enable_meta;
            if (!data_released) begin fifo_done_meta<=0; fifo_done_sync<=0; end
            else begin
                fifo_done_meta<=i_fifo_reset_done_async;
                fifo_done_sync<=fifo_done_meta;
            end
        end
    end
    // State decisions feed register D inputs, never asynchronous reset outputs.
    always @(*) begin
        state_next = state;
        if (state!=RESET_ASSERT && state!=WAIT_INFRA && abort_sync)
            state_next = RESET_ASSERT;
        else case (state)
            RESET_ASSERT: if (reset_count==DDR_RESET_CYCLES-1)
                state_next = WAIT_INFRA;
            WAIT_INFRA: if (infra_sync && !abort_sync) state_next = RELEASE_DATA;
            RELEASE_DATA: state_next = WAIT_FIFOS;
            WAIT_FIFOS: if (&fifo_done_sync) state_next = WAIT_HOST_LO;
            WAIT_HOST_LO: if (!enable_sync) state_next = WAIT_HOST_HI;
            WAIT_HOST_HI: if (enable_sync) state_next = RUN;
            RUN: state_next = RUN;
            default: state_next = RESET_ASSERT;
        endcase
    end

    // Ownership changes on the original transition edge. Keep the data owner
    // asserted until the FSM handles abort so infra-loss capture cannot self-clear.
    always @(posedge i_clk or negedge i_hard_reset_n) begin
        if (!i_hard_reset_n) begin
            state <= RESET_ASSERT;
            ddr_released <= 1'b0;
            data_released <= 1'b0;
            armed_owner <= 1'b0;
        end else begin
            state <= state_next;
            ddr_released <= state_next != RESET_ASSERT;
            data_released <= state_next==RELEASE_DATA || state_next==WAIT_FIFOS ||
                             state_next==WAIT_HOST_LO || state_next==WAIT_HOST_HI || state_next==RUN;
            armed_owner <= state_next == RUN;
        end
    end

    // Counter and rearm status preserve original event priority and cycle counts.
    always @(posedge i_clk or negedge i_hard_reset_n) begin
        if (!i_hard_reset_n) begin
            reset_count <= 0;
            rearm_required <= 0;
        end else if (state!=RESET_ASSERT && state!=WAIT_INFRA && abort_sync) begin
            reset_count <= 0;
            rearm_required <= 1;
        end else case (state)
            RESET_ASSERT: begin
                if (reset_count==DDR_RESET_CYCLES-1) reset_count <= 0;
                else reset_count <= reset_count + 1'b1;
            end
            WAIT_HOST_HI: if (enable_sync) rearm_required <= 0;
            WAIT_INFRA, RELEASE_DATA, WAIT_FIFOS, WAIT_HOST_LO, RUN: begin end
            default: begin reset_count <= 0; rearm_required <= 1; end
        endcase
    end
endmodule
