//-----------------------------------------------------------------------------
// Testbench for the uart_demo design (behavioral simulation, no device libs).
//
// Deliberately shortened timings so a frame completes quickly:
//   CLK_FREQ  = 1_000_000 Hz  (1 MHz)
//   BAUD_RATE = 100_000       (10 clocks per bit)
//
// The TB does not wait for the DUT's own 2^20-cycle send trigger; it drives
// i_tx_start directly and checks the serialised 8N1 frame on o_uart_tx.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_top;

    localparam integer CLK_FREQ  = 1_000_000;
    localparam integer BAUD_RATE = 100_000;
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;   // 10
    localparam real    CLK_HALF = 500.0;                       // 1 MHz -> 500 ns half period

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'h00;
    wire       uart_tx;
    wire       uart_busy;

    // DUT: instantiate the transmitter directly so the byte sequence is
    // deterministic (the full `top` paces sends with a large counter).
    uart_tx #(
        .CLK_FREQ  (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) dut (
        .i_clk      (clk),
        .i_rst_n    (rst_n),
        .i_tx_start (tx_start),
        .i_tx_data  (tx_data),
        .o_tx       (uart_tx),
        .o_busy     (uart_busy)
    );

    always #(CLK_HALF) clk = ~clk;

    integer errors = 0;

    // Sample the line at the middle of each bit period.
    task check_bit(input expected, input [8*24-1:0] label);
        begin
            #(CLKS_PER_BIT * 1000 / 2);   // half a bit period (1 clock = 1000 ns)
            if (uart_tx !== expected) begin
                $display("FAIL %0s: expected %b got %b at t=%0t", label, expected, uart_tx, $time);
                errors = errors + 1;
            end else begin
                $display("ok   %0s = %b", label, uart_tx);
            end
            #(CLKS_PER_BIT * 1000 / 2);   // advance to the next bit boundary
        end
    endtask

    task send_and_check(input [7:0] byte);
        integer i;
        begin
            $display("--- sending 0x%02x (%b), LSB first", byte, byte);
            @(negedge clk);
            tx_data  = byte;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;

            // Start bit
            check_bit(1'b0, "start");
            // 8 data bits, LSB first
            for (i = 0; i < 8; i = i + 1) begin
                check_bit(byte[i], "data");
            end
            // Stop bit
            check_bit(1'b1, "stop");

            // Wait for busy to drop.
            wait (uart_busy == 1'b0);
            @(negedge clk);
        end
    endtask

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        // Reset
        rst_n = 1'b0;
        #(20 * 1000);
        rst_n = 1'b1;
        #(10 * 1000);

        send_and_check(8'h41);   // 'A'
        send_and_check(8'h55);   // 0101_0101 - alternating pattern
        send_and_check(8'h00);
        send_and_check(8'hFF);

        if (errors == 0) begin
            $display("RESULT: PASS - all UART frames correct");
        end else begin
            $display("RESULT: FAIL - %0d bit error(s)", errors);
        end
        $finish;
    end

    // Safety timeout
    initial begin
        #(20 * 1000 * 1000);
        $display("RESULT: FAIL - timeout");
        $finish;
    end

endmodule
