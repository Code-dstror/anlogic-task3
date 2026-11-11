`timescale 1ns / 1ps

// 按模式寄存器表配置 IMX415 传感器
module imx415_config #(
    // 传感器采集模式
    parameter integer MODE_4K = 0,
    // 时钟与时序配置
    parameter integer WAIT_CYCLES = 240000,
    // STANDBY cancel to XMSTA: 25 ms at the production 24 MHz SDR clock.
    // Separate from reset hold/release so short reset waits cannot shorten wake.
    parameter integer SDR_WAKE_CYCLES = 600000,
    parameter integer I2C_HALF_PERIOD = 120,
    parameter integer RUNTIME_EXPOSURE_ENABLE = 0,
    // Reset-applied gain selection; no live gain I2C transactions.
    parameter integer RUNTIME_GAIN_ENABLE = 0
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,
    // 传感器控制与 I2C 总线
    output wire o_xclr,
    output wire o_scl,
    inout wire io_sda,
    // 配置结果
    output wire o_done,
    output wire o_error,
    // Optional linear-mode exposure command, in this same clock domain.
    input wire i_exposure_valid,
    output wire o_exposure_ready,
    input wire [19:0] i_exposure_lines,
    output reg o_exposure_done,
    output wire o_exposure_error,
    // Sensor-clock domain, stable from reset through boot configuration.
    input wire [7:0] i_gain_code
);
    localparam [3:0] HOLD=0, RELEASE=1, SEND=2, WAIT_WRITE=3,
        CHECK=4, WAKE_WAIT=5, READY=6, FAILED=7,
        EXP_SEND=8, EXP_WAIT=9, EXP_CHECK=10, EXP_FAILED=11;
    // imx415_mode_table fixes both supported modes to this VMAX.
    localparam [19:0] VMAX_LINES = 20'd2250;
    reg [3:0] state, next_state;
    reg [31:0] wait_count;
    reg [7:0] index;
    wire [23:0] table_register;
    reg [23:0] write_register;
    reg boot_done;
    reg [19:0] exposure_shr0;
    reg [2:0] exposure_step;
    reg exposure_failed;
    reg exposure_error;
    wire busy, done, error;
    wire wait_end = wait_count == WAIT_CYCLES-1;
    wire wake_end = wait_count == SDR_WAKE_CYCLES-1;
    wire exposure_in_range = i_exposure_lines >= 20'd4 &&
        i_exposure_lines <= VMAX_LINES - 20'd8;
    wire exposure_accept = i_exposure_valid && o_exposure_ready;
    assign o_xclr = i_rst_n && state != HOLD;
    assign o_done = boot_done;
    assign o_error = state == FAILED;
    assign o_exposure_ready = RUNTIME_EXPOSURE_ENABLE != 0 &&
        state == READY && !exposure_error;
    assign o_exposure_error = exposure_error;
    imx415_mode_table #(.MODE_4K(MODE_4K)) u_table (
        .i_index(index), .o_register(table_register)
    );
    // 在配置启动和复位时更新寄存器写入字
    always @(*) begin
        write_register = table_register;
        if (RUNTIME_GAIN_ENABLE != 0 && index < 201) begin
            case (table_register[23:8])
                16'h3090: write_register = {16'h3090, i_gain_code};
                16'h3091: write_register = 24'h309100;
                default: write_register = table_register;
            endcase
        end
        if (index == 201) write_register = 24'h300000;
        if (index == 202) write_register = 24'h300200;
        if (state == EXP_SEND || state == EXP_WAIT || state == EXP_CHECK) begin
            case (exposure_step)
                0: write_register = 24'h300101;
                1: write_register = {16'h3050, exposure_shr0[7:0]};
                2: write_register = {16'h3051, exposure_shr0[15:8]};
                3: write_register = {16'h3052, 4'd0, exposure_shr0[19:16]};
                default: write_register = 24'h300100;
            endcase
        end
    end
    camera_i2c_write #(.HALF_PERIOD(I2C_HALF_PERIOD)) u_i2c (
        .i_clk(i_clk), .i_rst_n(i_rst_n),
        .i_start(state == SEND || state == EXP_SEND),
        .i_register(write_register), .o_busy(busy), .o_done(done),
        .o_error(error), .o_scl(o_scl), .io_sda(io_sda)
    );
    // 按等待及写入结果推进配置状态
    always @(posedge i_clk) begin
        if (!i_rst_n) state <= HOLD;
        else state <= next_state;
    end
    // 根据写入完成与错误事件选择后继状态
    always @(*) begin
        next_state = state;
        case (state)
            HOLD: if (wait_end) next_state = RELEASE;
            RELEASE: if (wait_end) next_state = SEND;
            SEND: next_state = WAIT_WRITE;
            WAIT_WRITE: if (done) next_state = CHECK;
            CHECK: begin
                if (error) next_state = FAILED;
                else if (index == 202) next_state = READY;
                else if (index == 201) next_state = WAKE_WAIT;
                else next_state = SEND;
            end
            WAKE_WAIT: if (wake_end) next_state = SEND;
            READY: begin
                if (exposure_accept)
                    next_state = exposure_in_range ? EXP_SEND : EXP_FAILED;
            end
            FAILED: next_state = FAILED;
            EXP_SEND: next_state = EXP_WAIT;
            EXP_WAIT: if (done) next_state = EXP_CHECK;
            EXP_CHECK: begin
                if (exposure_step == 4)
                    next_state = (error || exposure_failed) ? EXP_FAILED : READY;
                else next_state = EXP_SEND;
            end
            EXP_FAILED: next_state = EXP_FAILED;
            default: next_state = FAILED;
        endcase
    end
    // 累计等待周期并推进寄存器表索引
    always @(posedge i_clk) begin
        if (!i_rst_n) begin wait_count <= 0; index <= 0; end
        else begin
            if (state != next_state) wait_count <= 0;
            else if (state == HOLD || state == RELEASE || state == WAKE_WAIT)
                wait_count <= wait_count + 1'b1;
            if (state == CHECK && !error && index != 202) index <= index + 1'b1;
        end
    end
    // An ACK acknowledges register writes, never an applied CSI frame.
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            boot_done <= 1'b0;
            exposure_shr0 <= 0;
            exposure_step <= 0;
            exposure_failed <= 1'b0;
            exposure_error <= 1'b0;
            o_exposure_done <= 1'b0;
        end else begin
            o_exposure_done <= 1'b0;
            if (state == CHECK && !error && index == 202)
                boot_done <= 1'b1;
            if (exposure_accept) begin
                exposure_shr0 <= VMAX_LINES - i_exposure_lines;
                exposure_step <= 0;
                exposure_failed <= 1'b0;
                if (!exposure_in_range) exposure_error <= 1'b1;
            end
            if (state == EXP_CHECK) begin
                if (error) begin
                    exposure_failed <= 1'b1;
                    exposure_error <= 1'b1;
                end
                if (exposure_step != 4) begin
                    // Even after a NACK, attempt REGHOLD release. A partial
                    // command is untrusted until full reset and reinitialization.
                    exposure_step <= error ? 3'd4 : exposure_step + 1'b1;
                end else if (!error && !exposure_failed)
                    o_exposure_done <= 1'b1;
            end
        end
    end
endmodule
