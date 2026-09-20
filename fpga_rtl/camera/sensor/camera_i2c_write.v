`timescale 1ns / 1ps
// Single-clock IMX415 register writer. SCL is an output, never an RTL clock.
// Four bytes per request: 0x34, address high, address low, register value.
module camera_i2c_write #(
    parameter integer HALF_PERIOD = 120
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire i_start,
    input wire [23:0] i_register,
    output wire o_busy,
    output wire o_done,
    output wire o_error,
    output wire o_scl,
    inout wire io_sda
);
    localparam [3:0] IDLE=0, START=1, BIT_LOW=2, BIT_HIGH=3,
        ACK_LOW=4, ACK_HIGH=5, STOP_LOW=6, STOP_HIGH=7,
        STOP_RELEASE=8, DONE=9;
    reg [3:0] state, next_state;
    reg [15:0] divider;
    reg [31:0] shift_data;
    reg [2:0] bit_index;
    reg [1:0] byte_index;
    reg error_o;
    reg scl_o, sda_release;
    reg sda_meta, sda_sync;
    wire tick = divider == HALF_PERIOD-1;
    assign o_busy = state != IDLE;
    assign o_done = state == DONE;
    assign o_error = error_o;
    assign o_scl = scl_o;
    assign io_sda = sda_release ? 1'bz : 1'b0;

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= IDLE;
            divider <= 0;
            sda_meta <= 1;
            sda_sync <= 1;
        end else begin
            state <= next_state;
            sda_meta <= io_sda;
            sda_sync <= sda_meta;
            if (state == IDLE || tick) divider <= 0;
            else divider <= divider + 1'b1;
        end
    end
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: if (i_start) next_state = START;
            START: if (tick) next_state = BIT_LOW;
            BIT_LOW: if (tick) next_state = BIT_HIGH;
            BIT_HIGH: if (tick) begin
                if (bit_index == 7) next_state = ACK_LOW;
                else next_state = BIT_LOW;
            end
            ACK_LOW: if (tick) next_state = ACK_HIGH;
            ACK_HIGH: if (tick) begin
                if (sda_sync || byte_index == 3) next_state = STOP_LOW;
                else next_state = BIT_LOW;
            end
            STOP_LOW: if (tick) next_state = STOP_HIGH;
            STOP_HIGH: if (tick) next_state = STOP_RELEASE;
            STOP_RELEASE: if (tick) next_state = DONE;
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end
    always @(*) begin
        scl_o = 1;
        sda_release = 1;
        case (state)
            START: sda_release = 0;
            BIT_LOW: begin scl_o = 0; sda_release = shift_data[31]; end
            BIT_HIGH: sda_release = shift_data[31];
            ACK_LOW: scl_o = 0;
            STOP_LOW: begin scl_o = 0; sda_release = 0; end
            STOP_HIGH: sda_release = 0;
            default: begin scl_o = 1; sda_release = 1; end
        endcase
    end
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            shift_data <= 0;
            bit_index <= 0;
            byte_index <= 0;
            error_o <= 0;
        end else if (state == IDLE && i_start) begin
            shift_data <= {8'h34, i_register};
            bit_index <= 0;
            byte_index <= 0;
            error_o <= 0;
        end else if (tick) begin
            if (state == BIT_HIGH) begin
                shift_data <= {shift_data[30:0],1'b1};
                bit_index <= bit_index + 1'b1;
            end
            if (state == ACK_HIGH) begin
                byte_index <= byte_index + 1'b1;
                if (sda_sync) error_o <= 1;
            end
        end
    end
endmodule
