//-----------------------------------------------------------------------------
// Module: top
// Description: Demo top level for Anlogic PH1A60GEG324 (TD 6.2.1).
//   - Free running counter on the LED output
//   - UART transmitter streaming an incrementing byte pattern
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module top (
    input  wire i_clk,      // 50 MHz board clock
    input  wire i_rst_n,    // active low reset
    output wire o_uart_tx,  // UART TX line
    output wire o_led,      // heartbeat LED
    output wire o_uart_busy
);

    // ---------------------------------------------------------------
    // Heartbeat: toggle LED every 2^24 clocks (~0.34 s @50 MHz)
    // ---------------------------------------------------------------
    reg [23:0] led_cnt;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            led_cnt <= 24'd0;
        end else begin
            led_cnt <= led_cnt + 24'd1;
        end
    end

    assign o_led = led_cnt[23];

    // ---------------------------------------------------------------
    // Byte sequencer: send a byte every 2^20 clocks (~21 ms @50 MHz)
    // ---------------------------------------------------------------
    reg [19:0] send_cnt;
    reg        send_req;
    reg [7:0]  send_data;
    wire       tx_busy;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            send_cnt  <= 20'd0;
            send_req  <= 1'b0;
            send_data <= 8'h41; // 'A'
        end else begin
            if (send_cnt == 20'hF_FFFF) begin
                send_cnt <= 20'd0;
                if (!tx_busy) begin
                    send_req  <= 1'b1;
                    send_data <= send_data + 8'd1;
                end else begin
                    send_req <= 1'b0;
                end
            end else begin
                send_cnt <= send_cnt + 20'd1;
                send_req <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------
    // UART transmitter
    // ---------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ  (50_000_000),
        .BAUD_RATE (115_200)
    ) u_uart_tx (
        .i_clk      (i_clk),
        .i_rst_n    (i_rst_n),
        .i_tx_start (send_req),
        .i_tx_data  (send_data),
        .o_tx       (o_uart_tx),
        .o_busy     (tx_busy)
    );

    assign o_uart_busy = tx_busy;

endmodule
