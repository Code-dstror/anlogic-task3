`timescale 1ns / 1ps

module tb_csi2_async_event_fifo_reset;
    reg write_clk = 1'b0;
    reg read_clk = 1'b0;
    reg run_write_clk = 1'b1;
    reg run_read_clk = 1'b1;
    reg reset_n = 1'b0;
    reg [46:0] write_data = 47'd0;
    reg write_valid = 1'b0;
    reg read_ready = 1'b0;
    wire write_ready;
    wire [46:0] read_data;
    wire read_valid;

    always #5 write_clk = run_write_clk ? !write_clk : 1'b0;
    always #4 read_clk = run_read_clk ? !read_clk : 1'b0;

    csi2_async_event_fifo dut (
        .i_write_clk(write_clk), .i_reset_n(reset_n),
        .i_write_data(write_data), .i_write_valid(write_valid),
        .o_write_ready(write_ready), .i_read_clk(read_clk),
        .o_read_data(read_data), .o_read_valid(read_valid),
        .i_read_ready(read_ready)
    );

    task send_word;
        input [46:0] value;
        begin
            wait (write_ready);
            @(negedge write_clk);
            write_data = value;
            write_valid = 1'b1;
            @(negedge write_clk);
            write_valid = 1'b0;
        end
    endtask

    task expect_word;
        input [46:0] value;
        begin
            wait (read_valid);
            if (read_data !== value) begin
                $display("[TB] RESULT: FAIL expected %h, got %h", value, read_data);
                $finish;
            end
            @(negedge read_clk);
            read_ready = 1'b1;
            @(negedge read_clk);
            read_ready = 1'b0;
        end
    endtask

    initial begin
        repeat (8) @(posedge write_clk);
        #2 reset_n = 1'b1;
        wait (write_ready);
        send_word(47'h0123456789ab);
        expect_word(47'h0123456789ab);

        // The read clock can start later than the write clock. The vendor
        // reset-done outputs gate each side independently after release.
        @(negedge read_clk);
        run_read_clk = 1'b0;
        #2 reset_n = 1'b0;
        repeat (6) @(posedge write_clk);
        if (write_ready || read_valid) begin
            $display("[TB] RESULT: FAIL active while reset asserted");
            $finish;
        end
        #2 reset_n = 1'b1;
        wait (write_ready);
        send_word(47'h0223456789ab);
        repeat (8) @(posedge write_clk);
        if (read_valid) begin
            $display("[TB] RESULT: FAIL read side released without a clock");
            $finish;
        end
        run_read_clk = 1'b1;
        expect_word(47'h0223456789ab);

        // A new asynchronous assertion flushes unread data. No old item may
        // appear after both clocks have completed their local reset release.
        send_word(47'h0323456789ab);
        #2 reset_n = 1'b0;
        repeat (8) @(posedge write_clk);
        #2 reset_n = 1'b1;
        repeat (20) @(posedge read_clk);
        if (read_valid) begin
            $display("[TB] RESULT: FAIL stale item after reset");
            $finish;
        end
        send_word(47'h0423456789ab);
        expect_word(47'h0423456789ab);
        $display("[TB] RESULT: PASS async assert, staggered clocks, reset flush");
        $finish;
    end

    initial begin
        #100000;
        $display("[TB] RESULT: FAIL timeout");
        $finish;
    end
endmodule
