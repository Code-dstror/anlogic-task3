`timescale 1ns / 1ps
// Reset and ordered I2C startup. Any NACK fails closed until a new reset.
module imx415_config #(
    parameter integer MODE_4K = 0,
    parameter integer WAIT_CYCLES = 240000,
    parameter integer I2C_HALF_PERIOD = 120
) (
    input wire i_clk,
    input wire i_rst_n,
    output wire o_xclr,
    output wire o_scl,
    inout wire io_sda,
    output wire o_done,
    output wire o_error
);
    localparam [3:0] HOLD=0, RELEASE=1, SEND=2, WAIT_WRITE=3,
        CHECK=4, WAKE_WAIT=5, READY=6, FAILED=7;
    reg [3:0] state, next_state;
    reg [31:0] wait_count;
    reg [7:0] index;
    wire [23:0] table_register;
    reg [23:0] write_register;
    wire busy, done, error;
    wire wait_end = wait_count == WAIT_CYCLES-1;
    assign o_xclr = i_rst_n && state != HOLD;
    assign o_done = state == READY;
    assign o_error = state == FAILED;
    imx415_mode_table #(.MODE_4K(MODE_4K)) u_table (
        .i_index(index), .o_register(table_register)
    );
    always @(*) begin
        write_register = table_register;
        if (index == 201) write_register = 24'h300000;
        if (index == 202) write_register = 24'h300200;
    end
    camera_i2c_write #(.HALF_PERIOD(I2C_HALF_PERIOD)) u_i2c (
        .i_clk(i_clk), .i_rst_n(i_rst_n), .i_start(state == SEND),
        .i_register(write_register), .o_busy(busy), .o_done(done),
        .o_error(error), .o_scl(o_scl), .io_sda(io_sda)
    );
    always @(posedge i_clk) begin
        if (!i_rst_n) state <= HOLD;
        else state <= next_state;
    end
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
            WAKE_WAIT: if (wait_end) next_state = SEND;
            READY: next_state = READY;
            FAILED: next_state = FAILED;
            default: next_state = FAILED;
        endcase
    end
    always @(posedge i_clk) begin
        if (!i_rst_n) begin wait_count <= 0; index <= 0; end
        else begin
            if (state != next_state) wait_count <= 0;
            else if (state == HOLD || state == RELEASE || state == WAKE_WAIT)
                wait_count <= wait_count + 1'b1;
            if (state == CHECK && !error && index != 202) index <= index + 1'b1;
        end
    end
endmodule
