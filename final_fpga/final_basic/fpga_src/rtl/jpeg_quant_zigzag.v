// 按固定量化表量化系数并重排为之字顺序
module jpeg_quant_zigzag (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,

    // 输入变换系数
    input wire i_block_valid,
    output wire o_block_ready,
    input wire [1023:0] i_coeffs,
    input wire [1:0] i_component,
    input wire [1:0] i_block_index,
    input wire [8:0] i_mcu_x,
    input wire [8:0] i_mcu_y,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,

    // 输出量化系数
    output reg o_block_valid,
    input wire i_block_ready,
    output reg [1023:0] o_coeffs,
    output reg [1:0] o_component,
    output reg [1:0] o_block_index,
    output reg [8:0] o_mcu_x,
    output reg [8:0] o_mcu_y,
    output reg o_frame_last,
    output reg [31:0] o_capture_id
);
    localparam [1:0] ST_IDLE = 2'd0;
    localparam [1:0] ST_RUN  = 2'd1;
    localparam [1:0] ST_OUT  = 2'd2;

    reg [1:0] state;
    reg [3:0] phase;
    reg [1023:0] source_coeffs;
    reg signed [15:0] stage_coeff [0:7];
    reg [7:0] stage_half_q [0:7];
    reg [18:0] stage_recip [0:7];
    reg [34:0] product [0:7];
    reg product_negative [0:7];
    integer lane;
    reg [5:0] scan_index;
    reg [5:0] natural_index;
    reg [15:0] magnitude;
    reg [15:0] numerator;
    reg [15:0] quotient;

    `include "jpeg_quant_tables.vh"

    // 量化器空闲时接收下一个变换块
    assign o_block_ready = i_rst_n && (state == ST_IDLE);

    // 依次量化变换系数并输出之字顺序块
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= ST_IDLE;
            phase <= 4'd0;
            o_block_valid <= 1'b0;
            o_coeffs <= 1024'd0;
            source_coeffs <= 1024'd0;
            o_component <= 2'd0;
            o_block_index <= 2'd0;
            o_mcu_x <= 9'd0;
            o_mcu_y <= 9'd0;
            o_frame_last <= 1'b0;
            o_capture_id <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (i_block_valid) begin
                        source_coeffs <= i_coeffs;
                        o_component <= i_component;
                        o_block_index <= i_block_index;
                        o_mcu_x <= i_mcu_x;
                        o_mcu_y <= i_mcu_y;
                        o_frame_last <= i_frame_last;
                        o_capture_id <= i_capture_id;
                        phase <= 4'd0;
                        state <= ST_RUN;
                    end
                end
                ST_RUN: begin
                    // 三个重叠阶段依次完成表与系数读取、精确倒数乘法和有符号之字顺序回写
                    // 在 signed16/Q75 范围无需除法修正
                    // floor(N*ceil(2^21/q)/2^21) == floor(N/q)
                    if (phase < 4'd8) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            scan_index = {phase[2:0], 3'b000} + lane;
                            natural_index = zigzag(scan_index);
                            stage_coeff[lane] <= source_coeffs[natural_index*16 +: 16];
                            stage_half_q[lane] <= (o_component == 2'd0) ?
                                (q75_luma(natural_index) >> 1) :
                                (q75_chroma(natural_index) >> 1);
                            stage_recip[lane] <= (o_component == 2'd0) ?
                                q75_recip_luma(natural_index) :
                                q75_recip_chroma(natural_index);
                        end
                    end
                    if (phase >= 4'd1 && phase <= 4'd8) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            magnitude = stage_coeff[lane][15] ?
                                (~stage_coeff[lane] + 16'd1) : stage_coeff[lane];
                            numerator = magnitude + {8'd0, stage_half_q[lane]};
                            product[lane] <= numerator * stage_recip[lane];
                            product_negative[lane] <= stage_coeff[lane][15];
                        end
                    end
                    if (phase >= 4'd2) begin
                        for (lane = 0; lane < 8; lane = lane + 1) begin
                            quotient = {2'b00, product[lane][34:21]};
                            o_coeffs[((phase-4'd2)*8+lane)*16 +: 16] <=
                                product_negative[lane] ? (~quotient + 16'd1) : quotient;
                        end
                    end
                    if (phase == 4'd9) begin
                        o_block_valid <= 1'b1;
                        state <= ST_OUT;
                    end else begin
                        phase <= phase + 4'd1;
                    end
                end
                ST_OUT: begin
                    if (i_block_ready) begin
                        o_block_valid <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                default: begin
                    o_block_valid <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
