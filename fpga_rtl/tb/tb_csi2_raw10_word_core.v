`timescale 1ns / 1ps

module tb_csi2_raw10_word_core;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg [31:0] word_data = 32'd0;
    reg word_valid = 1'b0;
    reg sink_ready = 1'b1;
    wire [39:0] data_out;
    wire valid_out;
    wire sof_out;
    wire eol_out;
    wire abort_out;
    wire [3:0] error_out;
    integer pixel_groups = 0;
    integer aborts = 0;
    integer eols = 0;
    reg boundary_check = 1'b0;
    integer boundary_sof_group = -1;
    integer boundary_eol_group = -1;
    reg [3:0] last_abort_code = 4'd0;
    reg [15:0] payload_crc;
    integer index;

    always #4 clk = ~clk;

    csi2_raw10_word_core dut (
        .i_clk(clk), .i_reset_n(reset_n), .i_word(word_data),
        .i_word_valid(word_valid), .i_sink_ready(sink_ready),
        .o_data(data_out), .o_valid(valid_out), .o_sof(sof_out),
        .o_eol(eol_out), .o_abort(abort_out), .o_error_code(error_out),
        .o_header_ecc_error(), .o_payload_crc_error(), .o_length_error(),
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

    task send_word;
        input [31:0] value;
        begin
            @(negedge clk); word_data = value; word_valid = 1'b1;
            @(negedge clk); word_valid = 1'b0;
        end
    endtask

    task send_crc_while_pixel_stalled;
        reg [15:0] calculated_crc;
        integer byte_no;
        reg [7:0] value;
        begin
            calculated_crc = 16'hffff;
            for (byte_no = 0; byte_no < 15; byte_no = byte_no + 1) begin
                value = byte_no[7:0] ^ 8'h5a;
                calculated_crc = crc_byte(calculated_crc, value);
            end
            send_header(8'h2b, 16'd15);
            send_word(32'h59585b5a);
            send_word(32'h5d5c5f5e);
            send_word(32'h51505352);
            sink_ready = 1'b0;
            send_word({calculated_crc[7:0] ^ 8'h01, 8'h54, 8'h57, 8'h56});
            send_word({24'd0, calculated_crc[15:8]});
        end
    endtask

    task send_good_crc_after_bubble;
        reg [15:0] calculated_crc;
        integer byte_no;
        reg [7:0] value;
        begin
            calculated_crc = 16'hffff;
            for (byte_no = 0; byte_no < 15; byte_no = byte_no + 1) begin
                value = byte_no[7:0] ^ 8'h5a;
                calculated_crc = crc_byte(calculated_crc, value);
            end
            send_header(8'h2b, 16'd15);
            send_word(32'h59585b5a);
            send_word(32'h5d5c5f5e);
            send_word(32'h51505352);
            send_word({calculated_crc[7:0], 8'h54, 8'h57, 8'h56});
            repeat (6) @(negedge clk);
            if (eols != 2 || pixel_groups != 1451) begin
                $display("[TB] RESULT: FAIL final group committed before CRC groups=%0d eols=%0d", pixel_groups, eols); $finish; end
            send_word({24'd0, calculated_crc[15:8]});
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
    task send_header_error;
        input [7:0] identifier; input [15:0] count; input [23:0] flip_mask;
        reg [23:0] header;
        begin header={count,identifier};send_word({2'b00,make_ecc(header),header^flip_mask});end
    endtask

    task send_raw_packet;
        input integer byte_count;
        input corrupt_crc;
        integer byte_no;
        integer lane;
        reg [31:0] assembled;
        reg [7:0] value;
        reg [15:0] calculated_crc;
        begin
            send_header(8'h2b, byte_count[15:0]);
            assembled = 0; lane = 0; calculated_crc = 16'hffff;
            for (byte_no = 0; byte_no < byte_count; byte_no = byte_no + 1) begin
                value = byte_no[7:0] ^ 8'h5a;
                calculated_crc = crc_byte(calculated_crc, value);
                assembled[lane*8 +: 8] = value; lane = lane + 1;
                if (lane == 4) begin send_word(assembled); assembled = 0; lane = 0; end
            end
            assembled[lane*8 +: 8] = calculated_crc[7:0] ^ {7'd0,corrupt_crc}; lane = lane + 1;
            if (lane == 4) begin send_word(assembled); assembled = 0; lane = 0; end
            assembled[lane*8 +: 8] = calculated_crc[15:8]; lane = lane + 1;
            if (lane != 0) send_word(assembled);
        end
    endtask

    always @(posedge clk) begin
        if (valid_out && sink_ready) begin
            if (abort_out) begin
                aborts = aborts + 1;
                last_abort_code = error_out;
            end else begin
                pixel_groups = pixel_groups + 1;
                if (eol_out) eols = eols + 1;
                if (boundary_check &&
                    (sof_out !== (pixel_groups == boundary_sof_group) ||
                     eol_out !== (pixel_groups == boundary_eol_group))) begin
                    $display("[TB] RESULT: FAIL boundary group=%0d SOF=%b EOL=%b expected SOF=%0d EOL=%0d",
                             pixel_groups, sof_out, eol_out,
                             boundary_sof_group, boundary_eol_group);
                    $finish;
                end
                if ((pixel_groups == 1) && !sof_out) begin
                    $display("[TB] RESULT: FAIL missing SOF"); $finish;
                end
                if (((pixel_groups == 483) || (pixel_groups == 1449)) && !eol_out) begin
                    $display("[TB] RESULT: FAIL missing EOL"); $finish; end
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        send_header_error(8'h00, 16'd0, 24'h000001);
        send_raw_packet(2415, 1'b0);
        send_raw_packet(4830, 1'b0);
        repeat (5) @(posedge clk);
        if (pixel_groups != 1449 || aborts != 0) begin
            $display("[TB] RESULT: FAIL good packet groups=%0d aborts=%0d", pixel_groups, aborts); $finish;
        end

        send_header(8'h01, 16'd0);
        send_header(8'h00, 16'd0);
        send_good_crc_after_bubble;
        repeat (3) @(posedge clk);
        if (pixel_groups != 1452 || eols != 3) begin
            $display("[TB] RESULT: FAIL delayed good CRC commit groups=%0d eols=%0d", pixel_groups, eols); $finish; end

        send_raw_packet(15, 1'b1);
        repeat (5) @(posedge clk);
        if (aborts != 1 || error_out != 0) begin
            $display("[TB] RESULT: FAIL CRC abort count=%0d", aborts); $finish;
        end
        send_header_error(8'h00, 16'd0, 24'h000003);
        repeat (4) @(posedge clk);
        if (aborts != 2) begin
            $display("[TB] RESULT: FAIL double-bit ECC not rejected"); $finish; end

        send_header(8'h00, 16'd0);
        send_crc_while_pixel_stalled;
        repeat (3) @(posedge clk);
        if (!valid_out || !abort_out || error_out != 4'd2) begin
            $display("[TB] RESULT: FAIL CRC abort not retained over pending pixel"); $finish; end
        sink_ready = 1'b1;
        repeat (2) @(posedge clk);
        if (aborts != 3 || last_abort_code != 4'd2) begin
            $display("[TB] RESULT: FAIL stalled CRC abort handshake count=%0d code=%0d", aborts, last_abort_code); $finish; end

        send_header(8'h01, 16'd0);
        send_header(8'h00, 16'd0);
        sink_ready = 1'b0;
        send_raw_packet(5, 1'b0);
        send_header_error(8'h00, 16'd0, 24'h000003);
        repeat (2) @(posedge clk);
        if (!valid_out || !abort_out || error_out != 4'd1) begin
            $display("[TB] RESULT: FAIL header abort did not replace pending pixel"); $finish; end
        sink_ready = 1'b1;
        repeat (2) @(posedge clk);
        if (aborts != 4 || last_abort_code != 4'd1) begin
            $display("[TB] RESULT: FAIL stalled header abort handshake"); $finish; end

        send_header(8'h00, 16'd0);
        sink_ready = 1'b0;
        send_raw_packet(5, 1'b0);
        send_header(8'h2b, 16'd6);
        repeat (2) @(posedge clk);
        if (!valid_out || !abort_out || error_out != 4'd4) begin
            $display("[TB] RESULT: FAIL length abort did not replace pending pixel"); $finish; end
        sink_ready = 1'b1;
        repeat (2) @(posedge clk);
        if (aborts != 5 || last_abort_code != 4'd4) begin
            $display("[TB] RESULT: FAIL stalled length abort handshake"); $finish; end

        reset_n = 1'b0;
        sink_ready = 1'b0;
        repeat (3) @(posedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);
        send_header(8'h00, 16'd0);
        send_raw_packet(10, 1'b0);
        repeat (2) @(posedge clk);
        if (!valid_out || !abort_out || error_out != 4'd3 || eol_out) begin
            $display("[TB] RESULT: FAIL same-word CRC committed over blocked output"); $finish; end
        sink_ready = 1'b1;
        repeat (2) @(posedge clk);
        if (last_abort_code != 4'd3) begin
            $display("[TB] RESULT: FAIL blocked final group did not report overflow"); $finish; end

        // The final RAW10 group and CRC occupy every byte lane across these
        // lengths. Verify the EOL group exactly, then recover after bad CRC.
        @(negedge clk);
        reset_n = 1'b0;
        sink_ready = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        reset_n = 1'b1;
        pixel_groups = 0;
        eols = 0;
        aborts = 0;
        boundary_check = 1'b1;
        send_header(8'h00, 16'd0);

        boundary_sof_group = 1; boundary_eol_group = 1;
        send_raw_packet(5, 1'b0);
        repeat (3) @(posedge clk);
        if (pixel_groups != 1 || eols != 1 || aborts != 0) begin
            $display("[TB] RESULT: FAIL 5-byte CRC boundary"); $finish; end

        boundary_sof_group = -1; boundary_eol_group = 3;
        send_raw_packet(10, 1'b0);
        repeat (3) @(posedge clk);
        if (pixel_groups != 3 || eols != 2 || aborts != 0) begin
            $display("[TB] RESULT: FAIL 10-byte CRC boundary"); $finish; end

        boundary_eol_group = 6;
        send_raw_packet(15, 1'b0);
        repeat (3) @(posedge clk);
        if (pixel_groups != 6 || eols != 3 || aborts != 0) begin
            $display("[TB] RESULT: FAIL 15-byte CRC boundary"); $finish; end

        boundary_eol_group = 10;
        send_raw_packet(20, 1'b0);
        repeat (3) @(posedge clk);
        if (pixel_groups != 10 || eols != 4 || aborts != 0) begin
            $display("[TB] RESULT: FAIL 20-byte CRC boundary"); $finish; end

        boundary_eol_group = -1;
        send_raw_packet(15, 1'b1);
        repeat (3) @(posedge clk);
        if (pixel_groups != 12 || eols != 4 ||
            aborts != 1 || last_abort_code != 4'd2) begin
            $display("[TB] RESULT: FAIL bad CRC boundary groups=%0d eols=%0d aborts=%0d code=%0d",
                     pixel_groups, eols, aborts, last_abort_code); $finish; end

        send_header(8'h00, 16'd0);
        boundary_sof_group = 13; boundary_eol_group = 16;
        send_raw_packet(20, 1'b0);
        repeat (3) @(posedge clk);
        if (pixel_groups != 16 || eols != 5 || aborts != 1) begin
            $display("[TB] RESULT: FAIL recovery after bad CRC groups=%0d eols=%0d aborts=%0d",
                     pixel_groups, eols, aborts); $finish; end
        $display("[TB] RESULT: PASS");
        $finish;
    end
endmodule
