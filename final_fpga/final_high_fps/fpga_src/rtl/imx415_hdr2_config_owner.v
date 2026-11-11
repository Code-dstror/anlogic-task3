`timescale 1ns/1ps
// Fixed-preset sensor owner. All ports are in i_clk; CDC belongs to the caller.
// I2C ACK completion and post-startup frame qualification are separate states.
module imx415_hdr2_config_owner #(
    parameter integer CFG_CLK_HZ = 25000000,
    parameter integer RESET_HOLD_CYCLES = CFG_CLK_HZ/100,
    parameter integer RELEASE_WAIT_CYCLES = (CFG_CLK_HZ/1000)*30,
    parameter integer REGULATOR_WAIT_CYCLES = (CFG_CLK_HZ/1000)*24,
    parameter integer WARMUP_PAIRS = 8
) (
    input wire i_clk, input wire i_rst_n,
    input wire i_start, output wire o_start_ready,
    input wire i_clock_locked, input wire i_abort, input wire i_source_fault,
    input wire i_pair_event, input wire i_pair_ok,
    output wire o_xclr, output wire o_busy,
    output wire o_write_valid, input wire i_write_ready,
    output wire [23:0] o_write_register,
    input wire i_write_done, input wire i_write_error,
    output reg o_config_written, output wire o_stable,
    output wire o_error, output wire [7:0] o_register_index,
    output wire [31:0] o_diag_state,
    output wire [31:0] o_long_driver_lines, o_short_driver_lines,
    output wire [2:0] o_ratio_log2, output wire [31:0] o_gain_q16,
    output wire [9:0] o_black_raw10
);
    localparam [3:0] IDLE=0, RESET_HOLD=1, RELEASE_WAIT=2,
        SEND=3, WAIT_ACK=4, REGULATOR_WAIT=5, WARMUP=6, STABLE=7, FAULT=8;
    reg [3:0] state;
    reg [31:0] timer;
    reg [7:0] index;
    reg [7:0] warmup_count;
    wire wait_24ms, last;
    wire start_accept = i_start && o_start_ready;
    assign o_start_ready = state == IDLE || state == FAULT;
    assign o_xclr = i_rst_n && i_clock_locked && state != IDLE && state != RESET_HOLD && state != FAULT;
    assign o_busy = state != IDLE && state != STABLE && state != FAULT;
    assign o_write_valid = state == SEND && i_clock_locked && !i_abort && !i_source_fault;
    assign o_register_index = index;
    assign o_diag_state={warmup_count,index,state,i_clock_locked,i_abort,i_source_fault,
        i_pair_event,i_pair_ok,o_config_written,o_stable,o_error,
        o_write_valid,i_write_ready,i_write_done,i_write_error};
    assign o_stable = state == STABLE && i_clock_locked && !i_abort && !i_source_fault;
    assign o_error = state == FAULT;
    assign o_long_driver_lines = 32'd3200;
    assign o_short_driver_lines = 32'd200;
    assign o_ratio_log2 = 3'd4;
    assign o_gain_q16 = 32'd65536;
    assign o_black_raw10 = 10'd50;
    imx415_hdr2_recipe_rom u_rom(.i_index(index), .o_register(o_write_register),
        .o_wait_24ms(wait_24ms), .o_last(last));
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            state <= IDLE; timer <= 0; index <= 0; warmup_count <= 0;
            o_config_written <= 0;
        end else if (i_abort || i_source_fault || (!i_clock_locked && state != IDLE && state != FAULT)) begin
            state <= FAULT; timer <= 0; warmup_count <= 0; o_config_written <= 0;
        end else begin
            case (state)
                IDLE, FAULT: if (start_accept && i_clock_locked) begin
                    state <= RESET_HOLD; timer <= 0; index <= 0;
                    warmup_count <= 0; o_config_written <= 0;
                end
                RESET_HOLD: if (timer == RESET_HOLD_CYCLES-1) begin
                    state <= RELEASE_WAIT; timer <= 0;
                end else timer <= timer+1'b1;
                RELEASE_WAIT: if (timer == RELEASE_WAIT_CYCLES-1) begin
                    state <= SEND; timer <= 0;
                end else timer <= timer+1'b1;
                SEND: if (o_write_valid && i_write_ready) state <= WAIT_ACK;
                WAIT_ACK: if (i_write_done) begin
                    if (i_write_error) begin state <= FAULT; o_config_written <= 0; end
                    else if (last) begin
                        state <= WARMUP; warmup_count <= 0; o_config_written <= 1;
                    end else if (wait_24ms) begin state <= REGULATOR_WAIT; timer <= 0; end
                    else begin index <= index+1'b1; state <= SEND; end
                end
                REGULATOR_WAIT: if (timer == REGULATOR_WAIT_CYCLES-1) begin
                    index <= index+1'b1; state <= SEND; timer <= 0;
                end else timer <= timer+1'b1;
                WARMUP: if (i_pair_event) begin
                    if (!i_pair_ok) warmup_count <= 0;
                    else if (warmup_count == WARMUP_PAIRS-1) state <= STABLE;
                    else warmup_count <= warmup_count+1'b1;
                end
                STABLE: if (i_pair_event && !i_pair_ok) begin
                    state <= WARMUP; warmup_count <= 0;
                end
                default: begin state <= FAULT; o_config_written <= 0; end
            endcase
        end
    end
endmodule
