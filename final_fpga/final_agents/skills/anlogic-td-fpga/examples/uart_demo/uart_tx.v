//-----------------------------------------------------------------------------
// Module: uart_tx
// Description: Parameterized UART transmitter, 8N1.
//   Asserts o_busy while a byte is being shifted out.
//   i_tx_start is level-sensitive while !o_busy.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 50_000_000, // Hz
    parameter integer BAUD_RATE = 115_200
) (
    input  wire       i_clk,
    input  wire       i_rst_n,
    input  wire       i_tx_start,
    input  wire [7:0] i_tx_data,
    output reg        o_tx,
    output reg        o_busy
);

    // Number of clock cycles per bit.
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    localparam integer S_IDLE  = 3'd0;
    localparam integer S_START = 3'd1;
    localparam integer S_DATA  = 3'd2;
    localparam integer S_STOP  = 3'd3;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_shreg;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state      <= S_IDLE;
            clk_cnt    <= 16'd0;
            bit_idx    <= 3'd0;
            data_shreg <= 8'd0;
            o_tx       <= 1'b1;
            o_busy     <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    o_tx   <= 1'b1;
                    o_busy <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (i_tx_start) begin
                        data_shreg <= i_tx_data;
                        o_busy     <= 1'b1;
                        state      <= S_START;
                    end
                end

                S_START: begin
                    o_tx <= 1'b0; // start bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    o_tx <= data_shreg[0]; // LSB first
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt    <= 16'd0;
                        data_shreg <= {1'b0, data_shreg[7:1]};
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    o_tx <= 1'b1; // stop bit
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        o_busy  <= 1'b0;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
