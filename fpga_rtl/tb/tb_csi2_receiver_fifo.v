`timescale 1ns / 1ps

module tb_csi2_receiver_fifo;
    reg word_clk = 1'b0;
    reg pixel_clk = 1'b0;
    reg reset_n = 1'b0;
    reg [31:0] aligned_word = 32'd0;
    reg aligned_valid = 1'b0;
    reg raw_ready = 1'b0;
    reg random_ready_enable = 1'b0;
    reg [15:0] ready_lfsr = 16'h1;

    wire [39:0] raw_data;
    wire raw_valid;
    wire raw_sof;
    wire raw_eol;
    wire frame_abort;
    wire [3:0] error_code;
    wire [31:0] overflow_count;

    integer abort_count = 0;
    integer accepted_groups = 0;
    integer expected_group = 0;
    integer expected_groups = 0;
    integer stable_cycles = 0;
    reg check_pixels = 1'b0;
    reg wait_stalled_sof = 1'b0;
    reg [46:0] stalled_value;
    reg stalled_value_seen = 1'b0;

    always #5.555 word_clk = ~word_clk;
    always #4 pixel_clk = ~pixel_clk;

    csi2_raw10_rx_stream dut (
        .i_word_clk(word_clk), .i_pixel_clk(pixel_clk), .i_reset_n(reset_n),
        .i_aligned_word(aligned_word), .i_aligned_valid(aligned_valid),
        .o_raw_data(raw_data), .o_raw_valid(raw_valid), .i_raw_ready(raw_ready),
        .o_raw_sof(raw_sof), .o_raw_eol(raw_eol),
        .o_frame_abort(frame_abort), .o_error_code(error_code),
        .o_header_ecc_error_count(), .o_payload_crc_error_count(),
        .o_overflow_error_count(overflow_count), .o_length_error_count(),
        .o_wait_for_sync(), .o_packet_done()
    );

    function [5:0] make_ecc;
        input [23:0] data;
        begin
            make_ecc[0] = data[0]^data[1]^data[2]^data[4]^data[5]^data[7]^data[10]^data[11]^data[13]^data[16]^data[20]^data[21]^data[22]^data[23];
            make_ecc[1] = data[0]^data[1]^data[3]^data[4]^data[6]^data[8]^data[10]^data[12]^data[14]^data[17]^data[20]^data[21]^data[22]^data[23];
            make_ecc[2] = data[0]^data[2]^data[3]^data[5]^data[6]^data[9]^data[11]^data[12]^data[15]^data[18]^data[20]^data[21]^data[22];
            make_ecc[3] = data[1]^data[2]^data[3]^data[7]^data[8]^data[9]^data[13]^data[14]^data[15]^data[19]^data[20]^data[21]^data[23];
            make_ecc[4] = data[4]^data[5]^data[6]^data[7]^data[8]^data[9]^data[16]^data[17]^data[18]^data[19]^data[20]^data[22]^data[23];
            make_ecc[5] = data[10]^data[11]^data[12]^data[13]^data[14]^data[15]^data[16]^data[17]^data[18]^data[19]^data[21]^data[22]^data[23];
        end
    endfunction

    function [15:0] crc_byte;
        input [15:0] crc_in;
        input [7:0] byte_in;
        integer bit_no;
        reg [15:0] value;
        begin
            value = crc_in ^ byte_in;
            for (bit_no = 0; bit_no < 8; bit_no = bit_no + 1)
                value = value[0] ? ((value >> 1) ^ 16'h8408) : (value >> 1);
            crc_byte = value;
        end
    endfunction

    function [7:0] payload_byte;
        input integer byte_no;
        begin payload_byte = byte_no[7:0] ^ 8'h5a; end
    endfunction

    function [39:0] expected_raw_group;
        input integer group_no;
        reg [39:0] packed;
        begin
            packed = {payload_byte(group_no*5+4), payload_byte(group_no*5+3),
                      payload_byte(group_no*5+2), payload_byte(group_no*5+1),
                      payload_byte(group_no*5)};
            expected_raw_group[9:0] = {packed[7:0], packed[33:32]};
            expected_raw_group[19:10] = {packed[15:8], packed[35:34]};
            expected_raw_group[29:20] = {packed[23:16], packed[37:36]};
            expected_raw_group[39:30] = {packed[31:24], packed[39:38]};
        end
    endfunction

    task send_word;
        input [31:0] value;
        begin
            @(negedge word_clk);
            aligned_word = value;
            aligned_valid = 1'b1;
            @(negedge word_clk);
            aligned_valid = 1'b0;
        end
    endtask

    task send_header;
        input [7:0] identifier;
        input [15:0] count;
        reg [23:0] header;
        begin
            header = {count, identifier};
            send_word({2'b00, make_ecc(header), header});
        end
    endtask

    task send_raw_packet;
        input integer group_count;
        integer byte_count;
        integer byte_no;
        integer lane;
        reg [31:0] assembled;
        reg [7:0] value;
        reg [15:0] calculated_crc;
        begin
            byte_count = group_count * 5;
            send_header(8'h2b, byte_count[15:0]);
            assembled = 0;
            lane = 0;
            calculated_crc = 16'hffff;
            for (byte_no = 0; byte_no < byte_count; byte_no = byte_no + 1) begin
                value = payload_byte(byte_no);
                calculated_crc = crc_byte(calculated_crc, value);
                assembled[lane*8 +: 8] = value;
                lane = lane + 1;
                if (lane == 4) begin
                    send_word(assembled);
                    assembled = 0;
                    lane = 0;
                end
            end
            assembled[lane*8 +: 8] = calculated_crc[7:0];
            lane = lane + 1;
            if (lane == 4) begin send_word(assembled); assembled = 0; lane = 0; end
            assembled[lane*8 +: 8] = calculated_crc[15:8];
            lane = lane + 1;
            if (lane != 0) send_word(assembled);
        end
    endtask

    always @(posedge pixel_clk) begin
        if (!reset_n) begin
            ready_lfsr <= 16'h1;
        end else if (random_ready_enable) begin
            ready_lfsr <= {ready_lfsr[14:0], ready_lfsr[15] ^ ready_lfsr[13] ^ ready_lfsr[12] ^ ready_lfsr[10]};
            raw_ready <= ready_lfsr[0] | ready_lfsr[3];
        end

        if (reset_n && wait_stalled_sof && raw_valid && raw_sof && !raw_ready) begin
            if (!stalled_value_seen) begin
                stalled_value <= {error_code, frame_abort, raw_eol, raw_sof, raw_data};
                stalled_value_seen <= 1'b1;
            end else if ({error_code, frame_abort, raw_eol, raw_sof, raw_data} !== stalled_value) begin
                $display("[TB] RESULT: FAIL stalled SOF changed");
                $finish;
            end
            stable_cycles <= stable_cycles + 1;
        end

        if (reset_n && raw_valid && raw_ready) begin
            if (frame_abort) begin
                if (error_code != 4'd3) begin
                    $display("[TB] RESULT: FAIL unexpected abort code=%0d", error_code);
                    $finish;
                end
                abort_count <= abort_count + 1;
            end else if (check_pixels) begin
                if (raw_data !== expected_raw_group(expected_group)) begin
                    $display("[TB] RESULT: FAIL pixel group=%0d got=%h expected=%h",
                             expected_group, raw_data, expected_raw_group(expected_group));
                    $finish;
                end
                if ((expected_group == 0) != raw_sof) begin
                    $display("[TB] RESULT: FAIL SOF group=%0d value=%b", expected_group, raw_sof);
                    $finish;
                end
                if ((expected_group == expected_groups-1) != raw_eol) begin
                    $display("[TB] RESULT: FAIL EOL group=%0d value=%b", expected_group, raw_eol);
                    $finish;
                end
                expected_group <= expected_group + 1;
                accepted_groups <= accepted_groups + 1;
            end
        end
    end

    initial begin
        repeat (12) @(posedge word_clk);
        reset_n = 1'b1;
        repeat (20) @(posedge word_clk);

        send_header(8'h00, 16'd0);
        send_raw_packet(650);
        repeat (10) @(posedge word_clk);
        raw_ready = 1'b1;
        wait (abort_count == 1);
        repeat (20) @(posedge pixel_clk);
        if (overflow_count != 1) begin
            $display("[TB] RESULT: FAIL overflow count=%0d", overflow_count);
            $finish;
        end

        send_header(8'h01, 16'd0);
        send_header(8'h00, 16'd0);
        raw_ready = 1'b0;
        check_pixels = 1'b1;
        expected_group = 0;
        expected_groups = 4;
        wait_stalled_sof = 1'b1;
        send_raw_packet(4);
        wait (stalled_value_seen == 1'b1);
        repeat (6) @(posedge pixel_clk);
        if (stable_cycles < 4) begin
            $display("[TB] RESULT: FAIL SOF was not held under backpressure");
            $finish;
        end
        raw_ready = 1'b1;
        wait (expected_group == 4);
        wait_stalled_sof = 1'b0;
        check_pixels = 1'b0;
        send_header(8'h01, 16'd0);

        send_header(8'h00, 16'd0);
        expected_group = 0;
        expected_groups = 483;
        accepted_groups = 0;
        check_pixels = 1'b1;
        random_ready_enable = 1'b1;
        send_raw_packet(483);
        wait (accepted_groups == 483);
        random_ready_enable = 1'b0;
        raw_ready = 1'b1;
        check_pixels = 1'b0;
        send_header(8'h01, 16'd0);
        repeat (30) @(posedge pixel_clk);

        if (abort_count != 1 || overflow_count != 1) begin
            $display("[TB] RESULT: FAIL final aborts=%0d overflow=%0d", abort_count, overflow_count);
            $finish;
        end
        $display("[TB] RESULT: PASS overflow recovery, stalled SOF, and 1932-pixel line");
        $finish;
    end

    initial begin
        #2000000;
        $display("[TB] RESULT: FAIL timeout");
        $finish;
    end
endmodule
