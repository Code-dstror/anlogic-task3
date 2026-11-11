`timescale 1ns / 1ps

// 管理单槽JPEG帧在DDR中的写入提交与读取
module jpeg_ddr_frame_store #(
    // 存储与时序参数
    parameter [31:0] SLOT_BASE = 32'h00000000,
    parameter [31:0] SLOT_BYTES = 32'h01000000,
    parameter integer AXI_TIMEOUT_CYCLES = 4096
) (
    // 时钟与就绪
    input wire i_clk,
    input wire i_rst_n,
    input wire i_ddr_ready,

    // 帧启动与元数据
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [31:0] i_capture_id,
    input wire [15:0] i_width,
    input wire [15:0] i_height,
    input wire [63:0] i_timestamp_ns,

    // JPEG输入流
    input wire [127:0] i_jpeg_tdata,
    input wire [15:0] i_jpeg_tkeep,
    input wire i_jpeg_tvalid,
    output wire o_jpeg_tready,
    input wire i_jpeg_tlast,

    // 编码结果
    input wire i_result_valid,
    output wire o_result_ready,
    input wire [31:0] i_result_id,
    input wire i_result_ok,
    input wire [24:0] i_result_length,

    // 待发送帧描述
    output wire o_ready_valid,
    input wire i_ready_claim,
    output wire [31:0] o_capture_id,
    output wire [24:0] o_payload_length,
    output wire [15:0] o_width,
    output wire [15:0] o_height,
    output wire [63:0] o_timestamp_ns,

    // 载荷输出流
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input wire i_payload_tready,
    output wire o_payload_tlast,

    // 错误与统计
    output reg o_drop_pulse,
    output reg o_read_done_pulse,
    output reg [7:0] o_error_code,
    output reg o_stream_recovery_required, // 读取故障后禁止继续发布帧
    output wire [3:0] o_state,
    output reg [15:0] o_wr_burst_count,
    output reg [15:0] o_rd_burst_count,
    output reg [15:0] o_berr_count,
    output reg [15:0] o_rerr_count,
    output reg [15:0] o_drop_count,
    output reg [27:0] o_last_error_addr,

    // AXI写地址
    output wire [3:0] o_axi_awid,
    output wire [27:0] o_axi_awaddr,
    output wire [7:0] o_axi_awlen,
    output wire [2:0] o_axi_awsize,
    output wire [1:0] o_axi_awburst,
    output wire o_axi_awvalid,
    input wire i_axi_awready,

    // AXI写数据
    output wire [127:0] o_axi_wdata,
    output wire [15:0] o_axi_wstrb,
    output wire o_axi_wlast,
    output wire o_axi_wvalid,
    input wire i_axi_wready,

    // AXI写响应
    input wire [3:0] i_axi_bid,
    input wire [1:0] i_axi_bresp,
    input wire i_axi_bvalid,
    output wire o_axi_bready,

    // AXI读地址
    output wire [3:0] o_axi_arid,
    output wire [27:0] o_axi_araddr,
    output wire [7:0] o_axi_arlen,
    output wire [2:0] o_axi_arsize,
    output wire [1:0] o_axi_arburst,
    output wire o_axi_arvalid,
    input wire i_axi_arready,

    // AXI读数据
    input wire [3:0] i_axi_rid,
    input wire [127:0] i_axi_rdata,
    input wire [1:0] i_axi_rresp,
    input wire i_axi_rlast,
    input wire i_axi_rvalid,
    output wire o_axi_rready
);
    localparam [3:0] S_IDLE=0, S_COLLECT=1, S_AW=2, S_W=3,
                     S_B=4, S_FINAL=5, S_READY=6, S_AR=7,
                     S_R=8, S_R_DRAIN=9, S_DISCARD=10, S_FAULT=11;
    localparam [7:0] E_NONE=0, E_INPUT=1, E_LENGTH=2,
                     E_BRESP=3, E_RRESP=4, E_RLAST=5, E_RESET=6,
                     E_BTIMEOUT=7, E_RTIMEOUT=8;
    localparam SLOT_VALID = SLOT_BYTES != 0 &&
                            SLOT_BYTES <= 32'h01000000 &&
                            SLOT_BASE[3:0] == 4'd0 &&
                            ({1'b0, SLOT_BASE} + {1'b0, SLOT_BYTES}) <=
                            33'h010000000;
    localparam TIMEOUT_EN = AXI_TIMEOUT_CYCLES > 1;
    reg [3:0] state;
    reg [31:0] wr_addr, rd_addr, capture_id;
    reg [15:0] width, height;
    reg [63:0] timestamp_ns;
    reg [24:0] input_bytes, rd_remaining;
    reg [127:0] stage_data [0:15];
    reg [15:0] stage_strb [0:15];
    reg [4:0] stage_count, beat_index, burst_count;
    reg input_last, result_seen, result_good;
    reg [24:0] result_length;
    reg [7:0] failure;
    reg [4:0] keep_bytes;
    reg keep_contiguous;
    reg [15:0] expected_keep;
    reg [4:0] collect_limit, read_limit;
    reg [31:0] wait_count;
    integer k;

    // 检查输入字节使能的连续性并统计有效字节
    always @(*) begin
        keep_bytes = 0;
        keep_contiguous = 1'b1;
        for (k=0; k<16; k=k+1) begin
            keep_bytes = keep_bytes + i_jpeg_tkeep[k];
            if (k != 0 && i_jpeg_tkeep[k] && !i_jpeg_tkeep[k-1])
                keep_contiguous = 1'b0;
        end
        expected_keep = 16'hffff;
        if (rd_remaining < 25'd16)
            expected_keep = 16'hffff >> (16 - rd_remaining[3:0]);
        collect_limit = 5'd16;
        if (wr_addr[11:4] == 8'hff)
            collect_limit = 5'd1;
        else if (wr_addr[11:4] > 8'hf0)
            collect_limit = 9'd256 - {1'b0, wr_addr[11:4]};
        read_limit = 5'd16;
        if (rd_addr[11:4] == 8'hff)
            read_limit = 5'd1;
        else if (rd_addr[11:4] > 8'hf0)
            read_limit = 9'd256 - {1'b0, rd_addr[11:4]};
        if (((rd_remaining + 25'd15) >> 4) < read_limit)
            read_limit = (rd_remaining + 25'd15) >> 4;
    end

    // 向外暴露槽位状态供系统诊断
    assign o_state = state;
    assign o_start_ready = state == S_IDLE && i_ddr_ready && i_rst_n && SLOT_VALID;
    // 丢弃模式即使 DDR 未就绪也继续排空上游帧
    // 暂存字节不写出，此时没有未完成的 AXI 事务
    assign o_jpeg_tready = (state == S_COLLECT && i_ddr_ready) ||
                           state == S_DISCARD;
    assign o_result_ready = state == S_COLLECT || state == S_AW ||
                            state == S_W || state == S_B ||
                            state == S_FINAL || state == S_DISCARD;
    assign o_ready_valid = state == S_READY;
    assign o_capture_id = capture_id;
    assign o_payload_length = input_bytes;
    assign o_width = width;
    assign o_height = height;
    assign o_timestamp_ns = timestamp_ns;

    assign o_axi_awid = 4'd0;
    assign o_axi_awaddr = wr_addr[27:0];
    assign o_axi_awlen = {3'd0, stage_count} - 8'd1;
    assign o_axi_awsize = 3'd4;
    assign o_axi_awburst = 2'b01;
    assign o_axi_awvalid = state == S_AW;
    assign o_axi_wdata = stage_data[beat_index[3:0]];
    assign o_axi_wstrb = stage_strb[beat_index[3:0]];
    assign o_axi_wlast = beat_index == stage_count - 5'd1;
    assign o_axi_wvalid = state == S_W;
    assign o_axi_bready = state == S_B;
    assign o_axi_arid = 4'd0;
    assign o_axi_araddr = rd_addr[27:0];
    assign o_axi_arlen = {3'd0, read_limit} - 8'd1;
    assign o_axi_arsize = 3'd4;
    assign o_axi_arburst = 2'b01;
    assign o_axi_arvalid = state == S_AR;
    assign o_axi_rready = (state == S_R &&
                          ((i_axi_rresp != 2'b00 || i_axi_rid != 4'd0 ||
                            i_axi_rlast != (beat_index == burst_count - 5'd1)) ||
                           i_payload_tready)) || state == S_R_DRAIN;
    assign o_payload_tdata = i_axi_rdata;
    assign o_payload_tkeep = expected_keep;
    assign o_payload_tlast = rd_remaining <= 25'd16;
    assign o_payload_tvalid = state == S_R && i_axi_rvalid &&
                              i_axi_rresp == 2'b00 && i_axi_rid == 4'd0 &&
                              i_axi_rlast == (beat_index == burst_count - 5'd1);

    wire payload_blocked = state == S_R && i_axi_rvalid && !o_axi_rready &&
                           i_axi_rresp == 2'b00 && i_axi_rid == 4'd0 &&
                           i_axi_rlast == (beat_index == burst_count - 5'd1);
    wire timeout_now = TIMEOUT_EN && !payload_blocked &&
                       wait_count >= (AXI_TIMEOUT_CYCLES - 1);
    wire slot_overflow;
    generate
        if (SLOT_BYTES[3:0] == 4'd0) begin : g_aligned_slot_limit
            // 收集阶段此前各拍均为完整的 16 字节
            // 短末拍直接进入 AW/FINAL，不再停留于 COLLECT
            // 因此对齐槽位除已满外至少剩余 16 字节
            assign slot_overflow = {7'd0, input_bytes} >= SLOT_BYTES;
        end else begin : g_unaligned_slot_limit
            assign slot_overflow = ({1'b0, input_bytes} + keep_bytes > SLOT_BYTES);
        end
    endgenerate

    // 暂存 RAM 只在合法输入握手时写入，不让会话复位直接驱动片选。
    // 复位边沿可能留下的旧 RAM 内容由状态和计数清除后失效。
    wire stage_write = state == S_COLLECT && i_ddr_ready &&
                       !(result_seen && !result_good) && i_jpeg_tvalid &&
                       keep_contiguous && keep_bytes != 0 &&
                       (i_jpeg_tlast || i_jpeg_tkeep == 16'hffff) &&
                       !slot_overflow;
    always @(posedge i_clk) begin
        if (stage_write) begin
            stage_data[stage_count[3:0]] <= i_jpeg_tdata;
            stage_strb[stage_count[3:0]] <= i_jpeg_tkeep;
        end
    end

    // W/R 服务开始前均由有效握手置零，RAM 读索引无需复位。
    // 复位窗口内 AXI 数据 valid 为低，旧索引不可被外部采纳。
    always @(posedge i_clk) begin
        case (state)
            S_AW: if (i_ddr_ready && i_axi_awready)
                beat_index <= 0;
            S_W: if (i_ddr_ready && i_axi_wready &&
                     beat_index != stage_count - 5'd1)
                beat_index <= beat_index + 5'd1;
            S_READY: if (i_ddr_ready && i_ready_claim)
                beat_index <= 0;
            S_AR: if (i_ddr_ready && i_axi_arready)
                beat_index <= 0;
            S_R: if (i_ddr_ready && i_axi_rvalid && o_axi_rready &&
                     i_axi_rresp == 2'b00 && i_axi_rid == 4'd0 &&
                     i_axi_rlast == (beat_index == burst_count - 5'd1) &&
                     rd_remaining > 25'd16 && !i_axi_rlast)
                beat_index <= beat_index + 5'd1;
            default: begin end
        endcase
    end

    // 按写响应和读取握手管理槽位生命周期
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= S_IDLE;
            wr_addr <= SLOT_BASE; rd_addr <= SLOT_BASE;
            capture_id <= 0; width <= 0; height <= 0; timestamp_ns <= 0;
            input_bytes <= 0; rd_remaining <= 0;
            stage_count <= 0; burst_count <= 0;
            input_last <= 0; result_seen <= 0; result_good <= 0;
            result_length <= 0; failure <= E_NONE;
            o_drop_pulse <= 0; o_read_done_pulse <= 0;
            o_error_code <= E_NONE;
            o_stream_recovery_required <= 0;
            wait_count <= 0;
            o_wr_burst_count <= 0; o_rd_burst_count <= 0;
            o_berr_count <= 0; o_rerr_count <= 0; o_drop_count <= 0;
            o_last_error_addr <= 0;
        end else begin
            o_drop_pulse <= 0;
            o_read_done_pulse <= 0;
            // 下游载荷反压导致有效 R 拍等待，并不视为 DDR 服务停滞
            // 数据拍及边带一直保持到下游完成接收
            if (state == S_AW || state == S_W || state == S_B ||
                state == S_AR || state == S_R_DRAIN ||
                (state == S_R && !payload_blocked))
                wait_count <= wait_count + 32'd1;
            else
                wait_count <= 0;
            if (o_drop_pulse && o_drop_count != 16'hffff)
                o_drop_count <= o_drop_count + 16'd1;
            if (i_result_valid && o_result_ready) begin
                result_seen <= 1'b1;
                result_good <= i_result_ok && i_result_id == capture_id;
                result_length <= i_result_length;
            end
            case (state)
                S_IDLE: if (i_start_valid && o_start_ready) begin
                    capture_id <= i_capture_id;
                    width <= i_width; height <= i_height;
                    timestamp_ns <= i_timestamp_ns;
                    wr_addr <= SLOT_BASE; input_bytes <= 0;
                    input_last <= 0; result_seen <= 0; result_good <= 0;
                    result_length <= 0; failure <= E_NONE;
                    stage_count <= 0;
                    state <= S_COLLECT;
                end
                S_COLLECT: if (!i_ddr_ready) begin
                    // 此时无未完成的 AXI 事务，当前帧将被丢弃
                    // JPEG 侧排空并交付结果后槽位才可复用
                    failure <= E_RESET;
                    stage_count <= 0;
                    state <= S_DISCARD;
                end else if (result_seen && !result_good) begin
                    failure <= E_INPUT;
                    stage_count <= 0;
                    state <= S_DISCARD;
                end else if (i_jpeg_tvalid && o_jpeg_tready) begin
                    if (!keep_contiguous || keep_bytes == 0 ||
                        (!i_jpeg_tlast && i_jpeg_tkeep != 16'hffff) ||
                         slot_overflow) begin
                        failure <= E_INPUT;
                        input_last <= i_jpeg_tlast;
                        stage_count <= 0;
                        state <= S_DISCARD;
                    end else begin
                        stage_count <= stage_count + 5'd1;
                        input_bytes <= input_bytes + keep_bytes;
                        if (i_jpeg_tlast) input_last <= 1'b1;
                        if (i_jpeg_tlast || stage_count + 5'd1 == collect_limit)
                            state <= S_AW;
                    end
                end
                S_AW: if (!i_ddr_ready) begin
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end else if (i_axi_awready) begin
                    wait_count <= 0;
                    state <= S_W;
                end else if (timeout_now) begin
                    o_error_code <= E_BTIMEOUT;
                    o_drop_pulse <= 1'b1;
                    if (o_berr_count != 16'hffff)
                        o_berr_count <= o_berr_count + 16'd1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end
                S_W: if (!i_ddr_ready) begin
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end else if (i_axi_wready) begin
                    wait_count <= 0;
                    if (beat_index == stage_count - 5'd1)
                        state <= S_B;
                end else if (timeout_now) begin
                    o_error_code <= E_BTIMEOUT;
                    o_drop_pulse <= 1'b1;
                    if (o_berr_count != 16'hffff)
                        o_berr_count <= o_berr_count + 16'd1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end
                S_B: if (!i_ddr_ready) begin
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end else if (i_axi_bvalid) begin
                    if (o_wr_burst_count != 16'hffff)
                        o_wr_burst_count <= o_wr_burst_count + 16'd1;
                    wr_addr <= wr_addr + {23'd0, stage_count, 4'd0};
                    stage_count <= 0;
                    if (i_axi_bresp != 2'b00 || i_axi_bid != 4'd0) begin
                        failure <= E_BRESP;
                        if (o_berr_count != 16'hffff)
                            o_berr_count <= o_berr_count + 16'd1;
                        o_last_error_addr <= wr_addr[27:0];
                        state <= S_DISCARD;
                    end else if (input_last)
                        state <= S_FINAL;
                    else
                        state <= S_COLLECT;
                end else if (timeout_now) begin
                    o_error_code <= E_BTIMEOUT;
                    o_drop_pulse <= 1'b1;
                    if (o_berr_count != 16'hffff)
                        o_berr_count <= o_berr_count + 16'd1;
                    o_last_error_addr <= wr_addr[27:0];
                    state <= S_FAULT;
                end
                S_DISCARD: begin
                    if (i_jpeg_tvalid && o_jpeg_tready && i_jpeg_tlast)
                        input_last <= 1'b1;
                    if (result_seen) begin
                        o_error_code <= failure;
                        o_drop_pulse <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                S_FINAL: if (!i_ddr_ready) begin
                    failure <= E_RESET;
                    state <= S_DISCARD;
                end else if (result_seen) begin
                    if (failure == E_NONE && result_good && input_bytes != 0 &&
                        result_length == input_bytes)
                        state <= S_READY;
                    else begin
                        o_error_code <= failure != E_NONE ? failure : E_LENGTH;
                        o_drop_pulse <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                S_READY: if (!i_ddr_ready) begin
                    // DDR 重新校准后已发布字节可能不再有效
                    // 在载荷被认领前丢弃该槽位
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    state <= S_IDLE;
                end else if (i_ready_claim) begin
                    rd_addr <= SLOT_BASE;
                    rd_remaining <= input_bytes;
                    state <= S_AR;
                end
                S_AR: if (!i_ddr_ready) begin
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    o_stream_recovery_required <= 1'b1;
                    o_last_error_addr <= rd_addr[27:0];
                    state <= S_FAULT;
                end else if (i_axi_arready) begin
                    wait_count <= 0;
                    if (o_rd_burst_count != 16'hffff)
                        o_rd_burst_count <= o_rd_burst_count + 16'd1;
                    burst_count <= read_limit;
                    state <= S_R;
                end else if (timeout_now) begin
                    o_error_code <= E_RTIMEOUT;
                    o_drop_pulse <= 1'b1;
                    o_stream_recovery_required <= 1'b1;
                    if (o_rerr_count != 16'hffff)
                        o_rerr_count <= o_rerr_count + 16'd1;
                    o_last_error_addr <= rd_addr[27:0];
                    state <= S_FAULT;
                end
                S_R: if (!i_ddr_ready) begin
                    o_error_code <= E_RESET;
                    o_drop_pulse <= 1'b1;
                    o_stream_recovery_required <= 1'b1;
                    o_last_error_addr <= rd_addr[27:0];
                    state <= S_FAULT;
                end else if (i_axi_rvalid && o_axi_rready) begin
                    wait_count <= 0;
                    if (i_axi_rresp != 2'b00 || i_axi_rid != 4'd0 ||
                        i_axi_rlast != (beat_index == burst_count - 5'd1)) begin
                        o_error_code <= (i_axi_rresp != 2'b00 || i_axi_rid != 4'd0) ?
                                        E_RRESP : E_RLAST;
                        o_stream_recovery_required <= 1'b1;
                        if (o_rerr_count != 16'hffff)
                            o_rerr_count <= o_rerr_count + 16'd1;
                        o_last_error_addr <= rd_addr[27:0];
                        if (i_axi_rlast) begin
                            o_drop_pulse <= 1'b1;
                            state <= S_FAULT;
                        end else
                            state <= S_R_DRAIN;
                    end else if (rd_remaining <= 25'd16) begin
                        o_read_done_pulse <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        rd_remaining <= rd_remaining - 25'd16;
                        if (i_axi_rlast) begin
                            rd_addr <= rd_addr + {23'd0, burst_count, 4'd0};
                            state <= S_AR;
                        end
                    end
                end else if (timeout_now) begin
                    o_error_code <= E_RTIMEOUT;
                    o_drop_pulse <= 1'b1;
                    o_stream_recovery_required <= 1'b1;
                    if (o_rerr_count != 16'hffff)
                        o_rerr_count <= o_rerr_count + 16'd1;
                    o_last_error_addr <= rd_addr[27:0];
                    state <= S_FAULT;
                end
                S_R_DRAIN: if (!i_ddr_ready) begin
                    o_drop_pulse <= 1'b1;
                    state <= S_FAULT;
                end else if (i_axi_rvalid && i_axi_rlast) begin
                    o_drop_pulse <= 1'b1;
                    state <= S_FAULT;
                end else if (timeout_now) begin
                    // 从设备已接受突发但始终未返回 RLAST
                    // 保留首个故障码，标记超时并停在故障状态
                    o_drop_pulse <= 1'b1;
                    if (o_rerr_count != 16'hffff)
                        o_rerr_count <= o_rerr_count + 16'd1;
                    state <= S_FAULT;
                end
                // S_FAULT 保持到会话复位 i_rst_n
                // 所有 AXI valid 关闭，不准入新帧，错误和恢复状态继续可观测
                // 非法状态编码同样安全地转入 S_FAULT
                S_FAULT: state <= S_FAULT;
                default: state <= S_FAULT;
            endcase
        end
    end
endmodule
