//-----------------------------------------------------------------------------
// postroute_tb.v - testbench for the TD post-route (routed + SDF) netlist
//   DUT  : top  (post_route.v, PH1 physical primitives)
//   Requires the PH1 global-reset primitive at TB level (SWUG107 fig.4-5):
//        PH1_PHY_GSR PH1_PHY_GSR();
//   UART sampling is clock counted (434 clk/bit) -> exact bit centres.
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps

module postroute_tb;

    localparam integer HALF_CLK     = 10;    // 20 ns period = 50 MHz
    localparam integer CLKS_PER_BIT = 434;   // 50_000_000 / 115_200

    reg  i_clk   = 1'b0;
    reg  i_rst_n = 1'b0;
    wire o_uart_tx;
    wire o_led;
    wire o_uart_busy;

    integer frame_cnt   = 0;
    integer bit_errors  = 0;
    integer byte_errors = 0;
    reg [7:0] rx_byte;
    reg [7:0] last_byte;
    integer   k;
    real      t_clk1, t_clk2;

    // Anlogic PH1 global reset primitive - mandatory for PH1 device libraries
    PH1_PHY_GSR PH1_PHY_GSR();

    top dut (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .o_uart_tx   (o_uart_tx),
        .o_led       (o_led),
        .o_uart_busy (o_uart_busy)
    );

    always #HALF_CLK i_clk = ~i_clk;

    initial begin
        $timeformat(-9, 3, " ns", 15);   // print %t in ns on every module
        $printtimescale;
        $display("[TB] ==== POST-ROUTE simulation of TD demo top ====");
        $display("[TB] UART = 115200 8N1, CLKS_PER_BIT = %0d (=434*20ns = 8680 ns)", CLKS_PER_BIT);
        @(posedge i_clk); t_clk1 = $realtime;
        @(posedge i_clk); t_clk2 = $realtime;
        $display("[TB] measured clock period = %0.3f time units", t_clk2 - t_clk1);
        repeat (18) @(posedge i_clk);
        i_rst_n = 1'b1;
        $display("[TB] t=%t : reset released (i_rst_n=1)", $time);
    end

    task automatic decode_frame;
        begin
            @(negedge o_uart_tx);
            $display("[TB] t=%t : START bit (line low)", $time);
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge i_clk);
            for (k = 0; k < 8; k = k + 1) begin
                rx_byte[k] = o_uart_tx;
                $display("[TB]          data[%0d] = %b   (t=%t)", k, o_uart_tx, $time);
                repeat (CLKS_PER_BIT) @(posedge i_clk);
            end
            if (o_uart_tx !== 1'b1) begin
                $display("[TB]          ERROR: STOP bit is %b, expected 1 (t=%t)", o_uart_tx, $time);
                bit_errors = bit_errors + 1;
            end else begin
                $display("[TB]          STOP bit = 1  (t=%t)", $time);
            end
            frame_cnt = frame_cnt + 1;
            $display("[TB] FRAME %0d : o_uart_tx = 0x%02h = '%c'   [start=0 d0..d7=%b%b%b%b%b%b%b%b stop=1]",
                     frame_cnt, rx_byte, rx_byte,
                     rx_byte[0], rx_byte[1], rx_byte[2], rx_byte[3],
                     rx_byte[4], rx_byte[5], rx_byte[6], rx_byte[7]);
            if (frame_cnt > 1) begin
                if (rx_byte !== (last_byte + 8'd1)) begin
                    $display("[TB]          NOTE: byte is 0x%02h, previous+1 would be 0x%02h", rx_byte, last_byte + 8'd1);
                    byte_errors = byte_errors + 1;
                end else begin
                    $display("[TB]          byte sequence check OK (0x%02h -> 0x%02h)", last_byte, rx_byte);
                end
            end
            last_byte = rx_byte;
            repeat (CLKS_PER_BIT/2) @(posedge i_clk);
        end
    endtask

    initial begin : main
        wait (i_rst_n === 1'b1);
        decode_frame;
        decode_frame;
        $display("[TB] SUMMARY: frames=%0d framing_errors=%0d sequence_mismatches=%0d",
                 frame_cnt, bit_errors, byte_errors);
        if (bit_errors == 0)
            $display("[TB] RESULT: PASS - %0d UART 8N1 frames on o_uart_tx are well framed (post-route netlist)", frame_cnt);
        else
            $display("[TB] RESULT: FAIL - %0d framing errors", bit_errors);
        $display("[TB] simulation finished at t=%t", $time);
        $finish;
    end

    initial begin
        #60_000_000;
        $display("[TB] RESULT: FAIL - timeout at t=%t", $time);
        $finish;
    end

endmodule
