`timescale 1ns / 1ps

// 将相机帧数、错误数和摘要通过串口发送
module camera_uart_status #(
    // 时钟与时序配置
    parameter integer CLOCK_HZ = 125000000,
    parameter integer BAUD_DIV = 1085
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,
    // 待发送状态数据
    input wire [31:0] i_frames,
    input wire [31:0] i_errors,
    input wire [31:0] i_digest,
    // 串口接口
    output wire o_tx
);
    reg [31:0] second_count;
    reg [15:0] baud_count;
    reg [127:0] payload;
    reg [9:0] serial;
    reg [3:0] bit_count;
    reg [4:0] byte_count;
    reg active;
    assign o_tx = active ? serial[0] : 1'b1;
    // 按照波特率分频依次发送状态字节
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            second_count <= 0; baud_count <= 0; payload <= 0;
            serial <= 10'h3ff; bit_count <= 0; byte_count <= 0; active <= 0;
        end else begin
            if (second_count == CLOCK_HZ-1) second_count <= 0;
            else second_count <= second_count + 1'b1;
            if (!active) begin
                baud_count <= 0;
                if (second_count == CLOCK_HZ-1) begin
                    payload <= {i_digest,i_errors,i_frames,32'h314d4143};
                    serial <= {1'b1,8'h43,1'b0};
                    bit_count <= 0; byte_count <= 0; active <= 1;
                end
            end else if (baud_count == BAUD_DIV-1) begin
                baud_count <= 0;
                if (bit_count == 9) begin
                    if (byte_count == 15) active <= 0;
                    else begin
                        payload <= {8'd0,payload[127:8]};
                        serial <= {1'b1,payload[15:8],1'b0};
                        byte_count <= byte_count + 1'b1;
                    end
                    bit_count <= 0;
                end else begin
                    serial <= {1'b1,serial[9:1]};
                    bit_count <= bit_count + 1'b1;
                end
            end else baud_count <= baud_count + 1'b1;
        end
    end
endmodule
