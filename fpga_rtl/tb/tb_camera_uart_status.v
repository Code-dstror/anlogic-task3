`timescale 1ns/1ps

module tb_camera_uart_status;

    localparam integer CLOCK_HZ = 800;
    localparam integer BAUD_DIV = 4;

    reg i_clk;
    reg i_rst_n;
    reg [31:0] i_frames;
    reg [31:0] i_errors;
    reg [31:0] i_digest;
    wire o_tx;

    integer errors;
    integer cycle_count;
    integer first_start_cycle;
    integer second_start_cycle;
    integer byte_index;
    reg [7:0] first_packet [0:15];
    reg [7:0] second_packet [0:15];

    camera_uart_status #(
        .CLOCK_HZ(CLOCK_HZ),
        .BAUD_DIV(BAUD_DIV)
    ) dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_frames(i_frames),
        .i_errors(i_errors),
        .i_digest(i_digest),
        .o_tx(o_tx)
    );

    always #4 i_clk = ~i_clk;

    always @(posedge i_clk)
        cycle_count = cycle_count + 1;

    task receive_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge o_tx);
            repeat (BAUD_DIV/2) @(posedge i_clk);
            if (o_tx !== 1'b0) begin
                $display("[TB] ERROR: missing UART start bit");
                errors = errors + 1;
            end
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (BAUD_DIV) @(posedge i_clk);
                value[bit_index] = o_tx;
            end
            repeat (BAUD_DIV) @(posedge i_clk);
            if (o_tx !== 1'b1) begin
                $display("[TB] ERROR: missing UART stop bit");
                errors = errors + 1;
            end
            repeat (BAUD_DIV/2) @(posedge i_clk);
        end
    endtask

    task check_byte;
        input [7:0] actual;
        input [7:0] expected;
        input integer packet_number;
        input integer position;
        begin
            if (actual !== expected) begin
                $display("[TB] ERROR: packet %0d byte %0d got=%02x expected=%02x",
                         packet_number, position, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst_n = 1'b0;
        i_frames = 32'h11223344;
        i_errors = 32'h55667788;
        i_digest = 32'h99aabbcc;
        errors = 0;
        cycle_count = 0;
        first_start_cycle = -1;
        second_start_cycle = -1;

        repeat (5) @(posedge i_clk);
        i_rst_n = 1'b1;

        for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
            receive_byte(first_packet[byte_index]);
            if (byte_index == 3) begin
                i_frames = 32'hdeadbeef;
                i_errors = 32'h01020304;
                i_digest = 32'h76543210;
            end
            if (byte_index == 0)
                first_start_cycle = cycle_count - (BAUD_DIV*10);
        end

        for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
            receive_byte(second_packet[byte_index]);
            if (byte_index == 0)
                second_start_cycle = cycle_count - (BAUD_DIV*10);
        end

        check_byte(first_packet[0], 8'h43, 1, 0);
        check_byte(first_packet[1], 8'h41, 1, 1);
        check_byte(first_packet[2], 8'h4d, 1, 2);
        check_byte(first_packet[3], 8'h31, 1, 3);
        check_byte(first_packet[4], 8'h44, 1, 4);
        check_byte(first_packet[5], 8'h33, 1, 5);
        check_byte(first_packet[6], 8'h22, 1, 6);
        check_byte(first_packet[7], 8'h11, 1, 7);
        check_byte(first_packet[8], 8'h88, 1, 8);
        check_byte(first_packet[9], 8'h77, 1, 9);
        check_byte(first_packet[10], 8'h66, 1, 10);
        check_byte(first_packet[11], 8'h55, 1, 11);
        check_byte(first_packet[12], 8'hcc, 1, 12);
        check_byte(first_packet[13], 8'hbb, 1, 13);
        check_byte(first_packet[14], 8'haa, 1, 14);
        check_byte(first_packet[15], 8'h99, 1, 15);

        check_byte(second_packet[0], 8'h43, 2, 0);
        check_byte(second_packet[1], 8'h41, 2, 1);
        check_byte(second_packet[2], 8'h4d, 2, 2);
        check_byte(second_packet[3], 8'h31, 2, 3);
        check_byte(second_packet[4], 8'hef, 2, 4);
        check_byte(second_packet[5], 8'hbe, 2, 5);
        check_byte(second_packet[6], 8'had, 2, 6);
        check_byte(second_packet[7], 8'hde, 2, 7);
        check_byte(second_packet[8], 8'h04, 2, 8);
        check_byte(second_packet[9], 8'h03, 2, 9);
        check_byte(second_packet[10], 8'h02, 2, 10);
        check_byte(second_packet[11], 8'h01, 2, 11);
        check_byte(second_packet[12], 8'h10, 2, 12);
        check_byte(second_packet[13], 8'h32, 2, 13);
        check_byte(second_packet[14], 8'h54, 2, 14);
        check_byte(second_packet[15], 8'h76, 2, 15);

        if (second_start_cycle - first_start_cycle != CLOCK_HZ) begin
            $display("[TB] ERROR: packet cadence %0d expected %0d",
                     second_start_cycle-first_start_cycle, CLOCK_HZ);
            errors = errors + 1;
        end
        if (o_tx !== 1'b1) begin
            $display("[TB] ERROR: UART not idle high after packet");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #1000000;
        $display("[TB] ERROR: timeout");
        $finish;
    end

endmodule
