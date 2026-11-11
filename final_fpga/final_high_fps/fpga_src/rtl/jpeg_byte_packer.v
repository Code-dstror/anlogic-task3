`timescale 1ns / 1ps

// 将连续JPEG字节打包为128位AXI数据拍
module jpeg_byte_packer #(
    // 存储与时序参数
    parameter integer MAX_PAYLOAD_BYTES = 16777216
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // 帧控制
    input  wire i_abort,

    // 输入字节流
    input  wire [7:0] i_byte,
    input  wire i_valid,
    output wire o_ready,
    input  wire i_last,

    // AXI输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0] o_axis_tkeep,
    output wire o_axis_tvalid,
    input  wire i_axis_tready,
    output wire o_axis_tlast,

    // 错误与空闲状态
    output wire o_frame_error,
    output wire o_overflow, // 帧长度超出配置上限
    output wire o_idle
);

    reg [127:0] byte_data;
    reg [4:0]   byte_count;
    reg [24:0]  payload_count;
    reg         end_pending;
    reg         drop_frame;
    reg         drain_error;
    reg         abort_drain;
    reg         frame_error_reg;
    reg         overflow_reg;

    wire output_full;
    wire output_tail;
    wire output_valid;
    wire output_fire;
    wire input_fire;
    wire overflow_event;

    // 缓存满一拍后等待AXI输出握手
    assign output_full  = (byte_count >= 5'd16);
    assign output_tail  = end_pending && (byte_count != 5'd0);
    assign output_valid = output_full | output_tail | drain_error | abort_drain;
    assign output_fire  = output_valid && i_axis_tready;

    assign o_axis_tdata  = byte_data;
    assign o_axis_tvalid = output_valid;
    assign o_axis_tlast  = output_tail;
    assign o_axis_tkeep  = (byte_count == 5'd0)  ? 16'h0000 :
                           (byte_count == 5'd1)  ? 16'h0001 :
                           (byte_count == 5'd2)  ? 16'h0003 :
                           (byte_count == 5'd3)  ? 16'h0007 :
                           (byte_count == 5'd4)  ? 16'h000f :
                           (byte_count == 5'd5)  ? 16'h001f :
                           (byte_count == 5'd6)  ? 16'h003f :
                           (byte_count == 5'd7)  ? 16'h007f :
                           (byte_count == 5'd8)  ? 16'h00ff :
                           (byte_count == 5'd9)  ? 16'h01ff :
                           (byte_count == 5'd10) ? 16'h03ff :
                           (byte_count == 5'd11) ? 16'h07ff :
                           (byte_count == 5'd12) ? 16'h0fff :
                           (byte_count == 5'd13) ? 16'h1fff :
                           (byte_count == 5'd14) ? 16'h3fff :
                           (byte_count == 5'd15) ? 16'h7fff : 16'hffff;

    // 同一周期可接收完整输出拍并写入新字节
    // 错误排空和帧结束优先于新输入
    // drop_frame 模式持续接收至 i_last，避免超长帧生产者因等待 ready 而死锁
    // 正常模式允许新字节在同周期替换刚发送的完整输出拍
    assign o_ready = i_rst_n && !i_abort && !drain_error && !abort_drain &&
                     (drop_frame ||
                      (!end_pending && (output_full ? output_fire : 1'b1)));
    assign input_fire = i_valid && o_ready;
    assign overflow_event = input_fire &&
                            (payload_count >= MAX_PAYLOAD_BYTES);

    assign o_frame_error = frame_error_reg;
    assign o_overflow    = overflow_reg;
    assign o_idle        = i_rst_n && !i_abort && !drain_error &&
                           !abort_drain && !drop_frame && !end_pending &&
                           (byte_count == 5'd0);

    reg [127:0] next_byte_data;
    reg [4:0]   next_byte_count;
    integer     append_index;

    // 计算当前输出拍被接收后的缓存字节排列
    always @(*) begin
        next_byte_data  = byte_data;
        next_byte_count = byte_count;
        append_index    = 0;
        if (output_fire && !drain_error) begin
            if (byte_count > 5'd16) begin
                next_byte_data  = 128'd0;
                next_byte_count = byte_count - 5'd16;
            end else begin
                next_byte_data  = 128'd0;
                next_byte_count = 5'd0;
            end
        end
        if (input_fire && !drop_frame && !drain_error && !overflow_event) begin
            append_index = next_byte_count * 8;
            next_byte_data[append_index +: 8] = i_byte;
            next_byte_count = next_byte_count + 5'd1;
        end
    end

    // 维护字节缓存帧长和输出拍有效状态
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            byte_data       <= 128'd0;
            byte_count      <= 5'd0;
            payload_count   <= 25'd0;
            end_pending     <= 1'b0;
            drop_frame      <= 1'b0;
            drain_error     <= 1'b0;
            abort_drain     <= 1'b0;
            frame_error_reg <= 1'b0;
            overflow_reg    <= 1'b0;
        end else begin
            frame_error_reg <= 1'b0;
            overflow_reg    <= 1'b0;

            if (i_abort) begin
                // 中止不能撤回已呈现且受阻的输出拍
                // 完整 AXIS 载荷保持到握手完成，再丢弃其余字节并等待新帧
                if (output_valid && !output_fire) begin
                    abort_drain <= 1'b1;
                end else begin
                    byte_data    <= 128'd0;
                    byte_count   <= 5'd0;
                    end_pending  <= 1'b0;
                    drop_frame   <= 1'b0;
                    drain_error  <= 1'b0;
                    abort_drain  <= 1'b0;
                    payload_count <= 25'd0;
                end
            end else if (abort_drain) begin
                if (output_fire) begin
                    byte_data    <= 128'd0;
                    byte_count   <= 5'd0;
                    end_pending  <= 1'b0;
                    drop_frame   <= 1'b0;
                    drain_error  <= 1'b0;
                    abort_drain  <= 1'b0;
                    payload_count <= 25'd0;
                end
            end else if (drain_error) begin
                // 溢出前已呈现的输出拍必须保持稳定直至接收
                // 该拍随后作为错误帧的一部分丢弃
                if (output_fire) begin
                    if (byte_count > 5'd16) begin
                        byte_data   <= 128'd0;
                        byte_count  <= byte_count - 5'd16;
                        drain_error <= 1'b1;
                    end else begin
                        byte_data   <= 128'd0;
                        byte_count  <= 5'd0;
                        drain_error <= 1'b0;
                    end
                end
            end else if (drop_frame) begin
                // 继续接收超长帧剩余字节，但不向外输出
                if (input_fire && i_last) begin
                    drop_frame    <= 1'b0;
                    payload_count <= 25'd0;
                end
            end else if (overflow_event) begin
                frame_error_reg <= 1'b1;
                overflow_reg    <= 1'b1;
                end_pending     <= 1'b0;
                payload_count   <= 25'd0;
                // 若超限字节本身是帧终止字节，则立即结束丢弃
                // 否则持续接收直至 i_last
                drop_frame      <= !i_last;
                if (output_valid && !output_fire) begin
                    drain_error <= 1'b1;
                end else begin
                    byte_data  <= 128'd0;
                    byte_count <= 5'd0;
                end
            end else begin
                if (output_fire) begin
                    byte_data  <= next_byte_data;
                    byte_count <= next_byte_count;
                    if (output_tail) begin
                        end_pending  <= 1'b0;
                        payload_count <= 25'd0;
                    end
                end

                if (input_fire && !overflow_event) begin
                    byte_data  <= next_byte_data;
                    byte_count <= next_byte_count;
                    payload_count <= payload_count + 25'd1;
                    if (i_last) begin
                        end_pending <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
