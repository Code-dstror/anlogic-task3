// 通过跨时钟请求应答检测 CSI 字节时钟是否持续运行
module csi_clock_watchdog #(
    // 时钟检测与复位释放配置
    parameter TIMEOUT_REF_CYCLES = 1024,
    parameter GOOD_ACKS          = 3,
    parameter RELEASE_STAGES     = 3,
    parameter CNT_WIDTH          = 16
)(
    // 时钟与复位
    input  wire I_ref_clk,
    input  wire I_ext_clk,
    input  wire I_arst_n,

    // 监测使能
    input  wire I_enable,

    // 时钟健康状态
    output reg  O_healthy_ref,
    output reg  O_clock_lost_pulse_ref,

    // 外部时钟域复位
    output wire O_ext_rst_n
);
    localparam [CNT_WIDTH-1:0] TIMEOUT_MAX = TIMEOUT_REF_CYCLES;
    localparam [2:0] ACKS_MAX = GOOD_ACKS;

    // 参考时钟域的请求、应答与超时状态
    reg r_req_toggle;
    reg r_waiting;
    reg r_ack_ref;
    reg [CNT_WIDTH-1:0] r_timeout_count;
    reg [2:0] r_good_count;
    reg r_ack_meta;
    reg r_ack_sync;
    reg r_enable_meta;
    reg r_enable_sync;

    // 外部字节时钟域的请求同步与复位释放状态
    reg r_req_meta;
    reg r_req_sync;
    reg r_ack_toggle;
    reg [1:0] r_ext_reset_sync;
    reg [RELEASE_STAGES-1:0] r_release_pipe;

    wire w_round_done  = r_waiting && (r_ack_sync != r_ack_ref);
    wire w_timeout     = r_waiting && !w_round_done &&
                         (r_timeout_count >= TIMEOUT_MAX);
    wire w_healthy_next = (r_good_count == ACKS_MAX) && r_enable_sync;

    wire w_ext_reset_n = r_ext_reset_sync[1];

    assign O_ext_rst_n = r_release_pipe[RELEASE_STAGES-1];

    // 在参考时钟域发起应答检测并更新超时状态
    always @(posedge I_ref_clk or negedge I_arst_n) begin
        if (!I_arst_n) begin
            r_req_toggle   <= 1'b0;
            r_waiting      <= 1'b0;
            r_ack_ref      <= 1'b0;
            r_timeout_count <= {CNT_WIDTH{1'b0}};
            r_good_count   <= 3'd0;
            r_ack_meta     <= 1'b0;
            r_ack_sync     <= 1'b0;
            r_enable_meta  <= 1'b0;
            r_enable_sync  <= 1'b0;
            O_healthy_ref  <= 1'b0;
            O_clock_lost_pulse_ref <= 1'b0;
        end else begin
            r_ack_meta <= r_ack_toggle;
            r_ack_sync <= r_ack_meta;
            r_enable_meta <= I_enable;
            r_enable_sync <= r_enable_meta;
            O_healthy_ref <= w_healthy_next;
            O_clock_lost_pulse_ref <= O_healthy_ref && !w_healthy_next;

            if (!r_waiting) begin
                // 一次只发起一轮应答检测
                r_req_toggle    <= ~r_req_toggle;
                r_waiting       <= 1'b1;
                r_ack_ref       <= r_ack_sync;
                r_timeout_count <= {CNT_WIDTH{1'b0}};
            end else if (w_round_done) begin
                r_waiting <= 1'b0;
                if (r_good_count != ACKS_MAX)
                    r_good_count <= r_good_count + 3'd1;
            end else if (w_timeout) begin
                // 外部时钟边沿不足时撤销健康状态，下一参考时钟周期重新发起检测
                r_waiting    <= 1'b0;
                r_good_count <= 3'd0;
            end else begin
                r_timeout_count <= r_timeout_count + 1'b1;
            end
        end
    end

    // 独立复位是本地释放链唯一的异步输入，其余字节域状态使用同步后的末级
    // 在外部时钟域同步复位释放
    always @(posedge I_ext_clk or negedge I_arst_n) begin
        if (!I_arst_n)
            r_ext_reset_sync <= 2'b00;
        else
            r_ext_reset_sync <= {r_ext_reset_sync[0], 1'b1};
    end

    // 在外部时钟域采样请求并返回应答翻转
    always @(posedge I_ext_clk or negedge w_ext_reset_n) begin
        if (!w_ext_reset_n) begin
            r_req_meta   <= 1'b0;
            r_req_sync   <= 1'b0;
            r_ack_toggle <= 1'b0;
        end else begin
            r_req_meta   <= r_req_toggle;
            r_req_sync   <= r_req_meta;
            r_ack_toggle <= r_req_sync;
        end
    end

    // 健康状态丢失时各级异步清零，停钟期间也保持复位
    // 只有实际字节时钟沿才能逐级释放，避免使能恢复时暴露旧状态
    // 仅在时钟恢复后逐级释放外部复位
    always @(posedge I_ext_clk or negedge O_healthy_ref) begin
        if (!O_healthy_ref)
            r_release_pipe <= {RELEASE_STAGES{1'b0}};
        else
            r_release_pipe <= {r_release_pipe[RELEASE_STAGES-2:0], 1'b1};
    end

endmodule
