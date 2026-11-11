`timescale 1ns / 1ps

// 将 RGB 像素流封装为带长度边界的 AXIS 数据
module rgb_axis_packer (
    // 时钟与复位
    input  wire         i_clk,
    input  wire         i_rst_n,
    // RGB 像素流
    input  wire [95:0]  i_rgb_tdata,
    input  wire         i_rgb_tvalid,
    output wire         o_rgb_tready,
    input  wire         i_rgb_tuser,
    input  wire         i_rgb_tlast,
    // 帧长与中止控制
    input  wire [12:0]  i_frame_height,
    input  wire         i_abort,
    // AXIS 输出流
    output wire [127:0] o_axis_tdata,
    output wire [15:0]  o_axis_tkeep,
    output wire         o_axis_tvalid,
    input  wire         i_axis_tready,
    output wire         o_axis_tlast,
    // 帧异常与完成状态
    output wire         o_frame_error,
    output wire         o_frame_done
);

    reg [255:0] pack_data;
    reg [5:0]   pack_count;
    reg [12:0]  line_count;
    reg [12:0]  frame_height;
    reg         frame_active;
    reg         frame_end_pending;
    reg         abort_drain;
    reg         frame_error_o;
    reg         frame_done_o;

    wire [95:0] ordered_rgb;
    wire        output_fire;
    wire        input_fire;
    wire        output_is_tail;
    wire [5:0]  bytes_after_pop;

    assign ordered_rgb = {
        i_rgb_tdata[79:72], i_rgb_tdata[87:80], i_rgb_tdata[95:88],
        i_rgb_tdata[55:48], i_rgb_tdata[63:56], i_rgb_tdata[71:64],
        i_rgb_tdata[31:24], i_rgb_tdata[39:32], i_rgb_tdata[47:40],
        i_rgb_tdata[7:0],   i_rgb_tdata[15:8],  i_rgb_tdata[23:16]
    };

    assign o_axis_tdata  = pack_data[127:0];
    assign o_axis_tvalid = (pack_count >= 6'd16) |
                           (frame_end_pending & (pack_count != 6'd0));
    assign output_is_tail = frame_end_pending & (pack_count <= 6'd16);
    assign o_axis_tlast = output_is_tail;
    assign o_axis_tkeep = (pack_count >= 6'd16) ? 16'hffff :
                          (16'hffff >> (6'd16 - pack_count));
    assign output_fire = o_axis_tvalid & i_axis_tready;
    assign bytes_after_pop = (pack_count > 6'd16) ?
                             (pack_count - 6'd16) : 6'd0;

    assign o_rgb_tready = !i_abort && !abort_drain && !frame_end_pending &&
                          (!frame_active ? i_rgb_tuser : 1'b1) &&
                          ((pack_count <= 6'd20) || output_fire);
    assign input_fire = i_rgb_tvalid & o_rgb_tready;
    assign o_frame_error = frame_error_o;
    assign o_frame_done = frame_done_o;

    integer append_bit;
    reg [255:0] next_pack_data;
    reg [5:0]   next_pack_count;

    // 根据本拍 RGB 像素数量计算待追加的数据位
    always @(*) begin
        append_bit = 0;
        next_pack_data = pack_data;
        next_pack_count = pack_count;
        if (output_fire) begin
            next_pack_data = pack_data >> 128;
            next_pack_count = bytes_after_pop;
        end
        if (input_fire) begin
            append_bit = next_pack_count * 8;
            next_pack_data[append_bit +: 96] = ordered_rgb;
            next_pack_count = next_pack_count + 6'd12;
        end
    end

    // 按输入输出握手更新 AXIS 打包缓冲和帧状态
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            pack_data        <= 256'd0;
            pack_count       <= 6'd0;
            line_count       <= 13'd0;
            frame_height     <= 13'd0;
            frame_active     <= 1'b0;
            frame_end_pending <= 1'b0;
            abort_drain      <= 1'b0;
            frame_error_o    <= 1'b0;
            frame_done_o     <= 1'b0;
        end else begin
            frame_error_o <= 1'b0;
            frame_done_o  <= 1'b0;

            if (i_abort) begin
                frame_error_o <= frame_active | frame_end_pending |
                                 (pack_count != 6'd0);
                frame_active <= 1'b0;
                line_count <= 13'd0;
                if (o_axis_tvalid && !output_fire) begin
                    abort_drain <= 1'b1;
                end else begin
                    abort_drain <= 1'b0;
                    frame_end_pending <= 1'b0;
                    pack_data <= 256'd0;
                    pack_count <= 6'd0;
                end
            end else if (abort_drain) begin
                if (output_fire) begin
                    abort_drain <= 1'b0;
                    frame_end_pending <= 1'b0;
                    pack_data <= 256'd0;
                    pack_count <= 6'd0;
                end
            end else begin
                pack_data <= next_pack_data;
                pack_count <= next_pack_count;

                if (input_fire) begin
                    if (!frame_active) begin
                        frame_active <= 1'b1;
                        frame_height <= i_frame_height;
                        line_count <= 13'd0;
                    end
                    if (i_rgb_tlast) begin
                        if ((!frame_active && (i_frame_height <= 13'd1)) ||
                            (frame_active &&
                             (line_count + 13'd1 >= frame_height))) begin
                            frame_active <= 1'b0;
                            frame_end_pending <= 1'b1;
                        end else begin
                            line_count <= line_count + 13'd1;
                        end
                    end
                end

                if (output_fire && output_is_tail) begin
                    frame_end_pending <= 1'b0;
                    frame_done_o <= 1'b1;
                end
            end
        end
    end

endmodule
