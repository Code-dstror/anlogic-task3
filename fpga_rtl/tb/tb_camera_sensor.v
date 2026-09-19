`timescale 1ns/1ps

module tb_camera_sensor;

    localparam integer WAIT_CYCLES = 8;
    localparam integer HALF_PERIOD = 4;

    reg i_clk;
    reg i_rst_n;
    wire o_xclr;
    wire o_scl;
    tri io_sda;
    wire o_done;
    wire o_error;

    reg slave_sda_low;
    assign io_sda = slave_sda_low ? 1'b0 : 1'bz;
    pullup(io_sda);

    integer errors;
    integer start_count;
    integer stop_count;
    integer transaction_count;
    integer byte_count;
    integer bit_count;
    integer nack_transaction;
    integer nack_byte;
    integer cycle_count;
    integer xclr_release_cycle;
    integer first_start_cycle;
    integer standby_stop_cycle;
    integer xmsta_start_cycle;
    integer done_cycle;
    integer reset_release_cycle;
    integer last_stop_byte_count;
    integer index;
    reg [7:0] current_byte;
    reg [7:0] received [0:811];
    reg active_transfer;
    reg release_ack;
    reg monitor_enable;

    reg [8:0] reference_index;
    wire [31:0] reference_data;
    wire [7:0] reference_size;

    imx415_config #(
        .MODE_4K(0),
        .WAIT_CYCLES(WAIT_CYCLES),
        .I2C_HALF_PERIOD(HALF_PERIOD)
    ) dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .o_xclr(o_xclr),
        .o_scl(o_scl),
        .io_sda(io_sda),
        .o_done(o_done),
        .o_error(o_error)
    );

    ui_imx415reg reference_table (
        .MODE(2'd0),
        .REG_INDEX(reference_index),
        .REG_DATA(reference_data),
        .REG_SIZE(reference_size)
    );

    always #20.833 i_clk = ~i_clk;

    always @(posedge i_clk) begin
        cycle_count = cycle_count + 1;
        if (o_done && done_cycle < 0)
            done_cycle = cycle_count;
    end

    always @(posedge o_xclr) begin
        if (monitor_enable)
            xclr_release_cycle = cycle_count;
    end

    always @(negedge io_sda) begin
        if (monitor_enable && i_rst_n && o_scl === 1'b1 && !slave_sda_low) begin
            active_transfer = 1'b1;
            release_ack = 1'b0;
            bit_count = 0;
            byte_count = 0;
            current_byte = 8'd0;
            start_count = start_count + 1;
            if (first_start_cycle < 0)
                first_start_cycle = cycle_count;
            if (transaction_count == 202)
                xmsta_start_cycle = cycle_count;
        end
    end

    always @(posedge io_sda) begin
        if (monitor_enable && i_rst_n && o_scl === 1'b1 && active_transfer &&
            !slave_sda_low) begin
            active_transfer = 1'b0;
            stop_count = stop_count + 1;
            if (transaction_count == 201)
                standby_stop_cycle = cycle_count;
            last_stop_byte_count = byte_count;
            transaction_count = transaction_count + 1;
        end
    end

    always @(posedge o_scl) begin
        if (monitor_enable && i_rst_n && active_transfer) begin
            if (bit_count < 8) begin
                current_byte = {current_byte[6:0], io_sda};
                bit_count = bit_count + 1;
            end else begin
                if (transaction_count < 203 && byte_count < 4)
                    received[transaction_count*4 + byte_count] = current_byte;
                byte_count = byte_count + 1;
                bit_count = 0;
                current_byte = 8'd0;
            end
        end
    end

    always @(negedge o_scl) begin
        if (!i_rst_n || !monitor_enable || !active_transfer) begin
            slave_sda_low = 1'b0;
            release_ack = 1'b0;
        end else if (release_ack) begin
            slave_sda_low = 1'b0;
            release_ack = 1'b0;
        end else if (bit_count == 8) begin
            if (transaction_count == nack_transaction && byte_count == nack_byte)
                slave_sda_low = 1'b0;
            else
                slave_sda_low = 1'b1;
            release_ack = 1'b1;
        end
    end

    function [7:0] expected_override;
        input [15:0] address;
        input [7:0] baseline_value;
        begin
            case (address)
                16'h3008: expected_override = 8'h54;
                16'h300A: expected_override = 8'h3B;
                16'h300B: expected_override = 8'h00;
                16'h3024: expected_override = 8'hCA;
                16'h3025: expected_override = 8'h08;
                16'h3028: expected_override = 8'h15;
                16'h3029: expected_override = 8'h02;
                16'h3033: expected_override = 8'h09;
                16'h3118: expected_override = 8'hB4;
                16'h311A: expected_override = 8'hFC;
                16'h4004: expected_override = 8'h00;
                16'h400C: expected_override = 8'h00;
                16'h4018: expected_override = 8'h6F;
                16'h401A: expected_override = 8'h2F;
                16'h401C: expected_override = 8'h2F;
                16'h401E: expected_override = 8'hBF;
                16'h401F: expected_override = 8'h00;
                16'h4020: expected_override = 8'h2F;
                16'h4022: expected_override = 8'h57;
                16'h4024: expected_override = 8'h2F;
                16'h4026: expected_override = 8'h4F;
                16'h4028: expected_override = 8'h27;
                16'h4074: expected_override = 8'h01;
                default: expected_override = baseline_value;
            endcase
        end
    endfunction

    task clear_monitor;
        integer clear_index;
        begin
            slave_sda_low = 1'b0;
            active_transfer = 1'b0;
            release_ack = 1'b0;
            start_count = 0;
            stop_count = 0;
            transaction_count = 0;
            byte_count = 0;
            bit_count = 0;
            current_byte = 8'd0;
            xclr_release_cycle = -1;
            first_start_cycle = -1;
            standby_stop_cycle = -1;
            xmsta_start_cycle = -1;
            done_cycle = -1;
            reset_release_cycle = -1;
            last_stop_byte_count = 0;
            for (clear_index = 0; clear_index < 812; clear_index = clear_index + 1)
                received[clear_index] = 8'hxx;
        end
    endtask

    task apply_reset;
        begin
            monitor_enable = 1'b0;
            i_rst_n = 1'b0;
            repeat (3) @(posedge i_clk);
            clear_monitor;
            @(negedge i_clk);
            monitor_enable = 1'b1;
            i_rst_n = 1'b1;
            reset_release_cycle = cycle_count;
        end
    endtask

    task wait_terminal;
        integer timeout;
        begin
            timeout = 0;
            while (!o_done && !o_error && timeout < 200000) begin
                @(posedge i_clk);
                timeout = timeout + 1;
            end
            if (timeout == 200000) begin
                $display("[TB] ERROR: configuration timeout");
                errors = errors + 1;
            end
            repeat (3) @(posedge i_clk);
        end
    endtask

    task verify_success;
        reg [23:0] expected_register;
        begin
            if (!o_done || o_error) begin
                $display("[TB] ERROR: successful run did not finish READY");
                errors = errors + 1;
            end
            if (transaction_count != 203 || start_count != 203 || stop_count != 203) begin
                $display("[TB] ERROR: transaction counts tx=%0d start=%0d stop=%0d",
                         transaction_count, start_count, stop_count);
                errors = errors + 1;
            end
            if (first_start_cycle - xclr_release_cycle < WAIT_CYCLES) begin
                $display("[TB] ERROR: XCLR release stabilization was too short");
                errors = errors + 1;
            end
            if (xclr_release_cycle - reset_release_cycle < WAIT_CYCLES) begin
                $display("[TB] ERROR: XCLR low hold was too short");
                errors = errors + 1;
            end
            if (xmsta_start_cycle - standby_stop_cycle < WAIT_CYCLES) begin
                $display("[TB] ERROR: reduced 10 ms wake wait was too short");
                errors = errors + 1;
            end
            if (done_cycle <= xmsta_start_cycle) begin
                $display("[TB] ERROR: done asserted before XMSTA transaction");
                errors = errors + 1;
            end
            if (reference_size !== 8'd201) begin
                $display("[TB] ERROR: vendor table size is not 201");
                errors = errors + 1;
            end
            if (o_scl !== 1'b1 || io_sda !== 1'b1) begin
                $display("[TB] ERROR: I2C bus not idle-high after completion");
                errors = errors + 1;
            end
            for (index = 0; index < 201; index = index + 1) begin
                reference_index = index;
                #1;
                expected_register = {
                    reference_data[23:8],
                    expected_override(reference_data[23:8], reference_data[7:0])
                };
                if (received[index*4] !== 8'h34 ||
                    received[index*4+1] !== expected_register[23:16] ||
                    received[index*4+2] !== expected_register[15:8] ||
                    received[index*4+3] !== expected_register[7:0]) begin
                    $display("[TB] ERROR: transaction %0d got %02x %02x %02x %02x expected 34 %06x",
                             index, received[index*4], received[index*4+1],
                             received[index*4+2], received[index*4+3], expected_register);
                    errors = errors + 1;
                end
            end
            if (received[804] !== 8'h34 || received[805] !== 8'h30 ||
                received[806] !== 8'h00 || received[807] !== 8'h00)
                errors = errors + 1;
            if (received[808] !== 8'h34 || received[809] !== 8'h30 ||
                received[810] !== 8'h02 || received[811] !== 8'h00)
                errors = errors + 1;
        end
    endtask

    task test_nack_position;
        input integer selected_byte;
        begin
            nack_transaction = 0;
            nack_byte = selected_byte;
            apply_reset;
            wait_terminal;
            if (!o_error || o_done) begin
                $display("[TB] ERROR: byte-%0d NACK did not fail closed", selected_byte);
                errors = errors + 1;
            end
            if (transaction_count != 1 || start_count != 1 || stop_count != 1) begin
                $display("[TB] ERROR: byte-%0d NACK continued configuration", selected_byte);
                errors = errors + 1;
            end
            if (last_stop_byte_count != selected_byte + 1) begin
                $display("[TB] ERROR: byte-%0d NACK stopped after %0d ACK slots",
                         selected_byte, last_stop_byte_count);
                errors = errors + 1;
            end
            repeat (20) @(posedge i_clk);
            if (transaction_count != 1) begin
                $display("[TB] ERROR: FAILED state issued another transfer");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst_n = 1'b0;
        slave_sda_low = 1'b0;
        monitor_enable = 1'b0;
        errors = 0;
        cycle_count = 0;
        reference_index = 9'd0;
        nack_transaction = -1;
        nack_byte = -1;
        clear_monitor;

        nack_transaction = -1;
        nack_byte = -1;
        apply_reset;
        while (start_count == 0) @(posedge i_clk);
        repeat (10) @(posedge i_clk);
        i_rst_n = 1'b0;
        monitor_enable = 1'b0;
        repeat (3) @(posedge i_clk);
        if (o_xclr !== 1'b0 || o_done || o_error) begin
            $display("[TB] ERROR: reset during transaction did not clear outputs");
            errors = errors + 1;
        end

        nack_transaction = -1;
        nack_byte = -1;
        apply_reset;
        wait_terminal;
        verify_success;

        test_nack_position(0);
        test_nack_position(1);
        test_nack_position(2);
        test_nack_position(3);

        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #500000000;
        $display("[TB] ERROR: global timeout");
        $finish;
    end

endmodule
