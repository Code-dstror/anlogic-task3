`timescale 1ns/1ps

module tb_camera_csi_rgb;

    localparam integer WIDTH = 16;
    localparam integer HEIGHT = 4;
    localparam integer FIRST_ROW = 1;
    localparam integer FIRST_GROUP = 1;
    localparam integer RAW_GROUPS = 6;
    localparam integer RAW_ROWS = 6;
    localparam integer FRAME_BYTES = WIDTH*HEIGHT*3;

    reg word_clk;
    reg pixel_clk;
    reg reset_n;
    reg [31:0] aligned_word;
    reg aligned_valid;
    wire [39:0] raw_data;
    wire raw_valid;
    wire raw_ready;
    wire raw_sof;
    wire raw_eol;
    wire frame_abort;
    wire [3:0] error_code;
    wire [31:0] crc_error_count;
    wire [127:0] axis_data;
    wire [15:0] axis_keep;
    wire axis_valid;
    reg axis_ready;
    wire axis_last;
    wire frame_error;
    wire frame_done;

    integer errors;
    integer seed;
    integer output_bytes;
    integer frame_bytes;
    integer done_count;
    integer error_count;
    integer axis_last_count;
    integer keep_index;
    reg check_bytes;
    reg crc_delay_active;
    reg early_done_seen;
    reg [15:0] ready_lfsr;
    reg [39:0] crop_test_data;
    reg crop_test_valid, crop_test_sof, crop_test_eol, crop_test_abort;
    reg crop_test_sink_ready;
    wire crop_test_ready, crop_test_valid_out, crop_test_abort_out;

    csi2_raw10_rx_stream u_receiver (
        .i_word_clk(word_clk), .i_pixel_clk(pixel_clk), .i_reset_n(reset_n),
        .i_aligned_word(aligned_word), .i_aligned_valid(aligned_valid),
        .o_raw_data(raw_data), .o_raw_valid(raw_valid), .i_raw_ready(raw_ready),
        .o_raw_sof(raw_sof), .o_raw_eol(raw_eol),
        .o_frame_abort(frame_abort), .o_error_code(error_code),
        .o_header_ecc_error_count(),
        .o_payload_crc_error_count(crc_error_count),
        .o_overflow_error_count(), .o_length_error_count(),
        .o_wait_for_sync(), .o_packet_done()
    );

    camera_rgb_pipeline #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT),
        .FIRST_ROW(FIRST_ROW), .FIRST_GROUP(FIRST_GROUP),
        .BAYER_PHASE(2'b00), .GAMMA_BYPASS(0)
    ) u_pipeline (
        .i_clk(pixel_clk), .i_rst_n(reset_n),
        .i_raw_data(raw_data), .i_raw_valid(raw_valid),
        .o_raw_ready(raw_ready), .i_raw_sof(raw_sof), .i_raw_eol(raw_eol),
        .i_raw_abort(frame_abort),
        .o_axis_tdata(axis_data), .o_axis_tkeep(axis_keep),
        .o_axis_tvalid(axis_valid), .i_axis_tready(axis_ready),
        .o_axis_tlast(axis_last), .o_frame_error(frame_error),
        .o_frame_done(frame_done)
    );

    camera_raw_crop #(
        .WIDTH(4), .HEIGHT(1), .FIRST_ROW(0), .FIRST_GROUP(0)
    ) u_crop_abort_test (
        .i_clk(pixel_clk), .i_rst_n(reset_n), .i_raw_data(crop_test_data),
        .i_raw_valid(crop_test_valid), .o_raw_ready(crop_test_ready),
        .i_raw_sof(crop_test_sof), .i_raw_eol(crop_test_eol),
        .i_raw_abort(crop_test_abort), .o_data(),
        .o_valid(crop_test_valid_out), .i_ready(crop_test_sink_ready),
        .o_sof(), .o_eol(), .o_abort(crop_test_abort_out)
    );

    always #5.555 word_clk = ~word_clk;
    always #4 pixel_clk = ~pixel_clk;

    function [5:0] make_ecc;
        input [23:0] data;
        begin
            make_ecc[0]=data[0]^data[1]^data[2]^data[4]^data[5]^data[7]^data[10]^data[11]^data[13]^data[16]^data[20]^data[21]^data[22]^data[23];
            make_ecc[1]=data[0]^data[1]^data[3]^data[4]^data[6]^data[8]^data[10]^data[12]^data[14]^data[17]^data[20]^data[21]^data[22]^data[23];
            make_ecc[2]=data[0]^data[2]^data[3]^data[5]^data[6]^data[9]^data[11]^data[12]^data[15]^data[18]^data[20]^data[21]^data[22];
            make_ecc[3]=data[1]^data[2]^data[3]^data[7]^data[8]^data[9]^data[13]^data[14]^data[15]^data[19]^data[20]^data[21]^data[23];
            make_ecc[4]=data[4]^data[5]^data[6]^data[7]^data[8]^data[9]^data[16]^data[17]^data[18]^data[19]^data[20]^data[22]^data[23];
            make_ecc[5]=data[10]^data[11]^data[12]^data[13]^data[14]^data[15]^data[16]^data[17]^data[18]^data[19]^data[21]^data[22]^data[23];
        end
    endfunction

    function [15:0] crc_byte;
        input [15:0] crc_in;
        input [7:0] byte_in;
        integer bit_no;
        reg [15:0] value;
        begin
            value = crc_in ^ byte_in;
            for (bit_no=0; bit_no<8; bit_no=bit_no+1)
                value = value[0] ? ((value >> 1)^16'h8408) : (value >> 1);
            crc_byte = value;
        end
    endfunction

    function [9:0] raw_pixel;
        input integer raw_x;
        input integer raw_y;
        integer crop_x;
        integer crop_y;
        begin
            crop_x = raw_x - FIRST_GROUP*4;
            crop_y = raw_y - FIRST_ROW;
            if (crop_x >= 0 && crop_y >= 0) begin
                if (!(crop_y & 1) && !(crop_x & 1)) raw_pixel = 10'd950;
                else if ((crop_y & 1) && (crop_x & 1)) raw_pixel = 10'd250;
                else raw_pixel = 10'd550;
            end else raw_pixel = 10'd550;
        end
    endfunction

    function [7:0] payload_byte;
        input integer raw_row;
        input integer byte_no;
        integer group_no;
        integer group_byte;
        reg [9:0] p0;
        reg [9:0] p1;
        reg [9:0] p2;
        reg [9:0] p3;
        begin
            group_no = byte_no / 5;
            group_byte = byte_no % 5;
            p0 = raw_pixel(group_no*4, raw_row);
            p1 = raw_pixel(group_no*4+1, raw_row);
            p2 = raw_pixel(group_no*4+2, raw_row);
            p3 = raw_pixel(group_no*4+3, raw_row);
            case (group_byte)
                0: payload_byte = p0[9:2];
                1: payload_byte = p1[9:2];
                2: payload_byte = p2[9:2];
                3: payload_byte = p3[9:2];
                default: payload_byte = {p3[1:0],p2[1:0],p1[1:0],p0[1:0]};
            endcase
        end
    endfunction

    function [7:0] expected_byte;
        input integer position;
        begin
            case (position % 3)
                0: expected_byte = 8'd241;
                1: expected_byte = 8'd184;
                default: expected_byte = 8'd121;
            endcase
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
            header = {count,identifier};
            send_word({2'b00,make_ecc(header),header});
        end
    endtask

    task send_raw_line;
        input integer raw_row;
        input integer corrupt_crc;
        input integer delay_crc;
        integer byte_no;
        integer lane_no;
        reg [31:0] assembled;
        reg [7:0] value;
        reg [15:0] calculated_crc;
        begin
            send_header(8'h2b, RAW_GROUPS*5);
            assembled = 0;
            lane_no = 0;
            calculated_crc = 16'hffff;
            for (byte_no=0; byte_no<RAW_GROUPS*5; byte_no=byte_no+1) begin
                value = payload_byte(raw_row,byte_no);
                calculated_crc = crc_byte(calculated_crc,value);
                assembled[lane_no*8 +: 8] = value;
                lane_no = lane_no + 1;
                if (lane_no == 4) begin
                    send_word(assembled); assembled = 0; lane_no = 0;
                end
            end
            if (delay_crc) begin
                crc_delay_active = 1'b1;
                repeat (300) @(posedge pixel_clk);
                crc_delay_active = 1'b0;
            end
            assembled[lane_no*8 +: 8] = calculated_crc[7:0] ^ corrupt_crc;
            lane_no = lane_no + 1;
            if (lane_no == 4) begin send_word(assembled); assembled=0; lane_no=0; end
            assembled[lane_no*8 +: 8] = calculated_crc[15:8];
            lane_no = lane_no + 1;
            if (lane_no != 0) send_word(assembled);
        end
    endtask

    task send_frame;
        input integer corrupt_row;
        integer raw_row;
        begin
            send_header(8'h00,16'd0);
            for (raw_row=0; raw_row<RAW_ROWS; raw_row=raw_row+1)
                send_raw_line(raw_row,raw_row==corrupt_row,raw_row==corrupt_row);
            send_header(8'h01,16'd0);
        end
    endtask

    task verify_abort_bypasses_held_output;
        begin
            crop_test_sink_ready = 1'b0;
            @(negedge pixel_clk);
            crop_test_data = 40'h123456789a;
            crop_test_sof = 1'b1;
            crop_test_eol = 1'b0;
            crop_test_abort = 1'b0;
            crop_test_valid = 1'b1;
            @(posedge pixel_clk);
            @(negedge pixel_clk);
            crop_test_sof = 1'b0;
            crop_test_eol = 1'b1;
            @(posedge pixel_clk);
            @(negedge pixel_clk);
            crop_test_valid = 1'b0;
            crop_test_eol = 1'b0;
            @(posedge pixel_clk);
            if (!crop_test_valid_out || crop_test_ready) begin
                $display("[TB] RESULT: FAIL crop held-output setup");
                errors = errors + 1;
            end
            @(negedge pixel_clk);
            crop_test_valid = 1'b1;
            crop_test_abort = 1'b1;
            #1;
            if (!crop_test_ready) begin
                $display("[TB] RESULT: FAIL abort did not bypass held backpressure");
                errors = errors + 1;
            end
            @(posedge pixel_clk);
            #1;
            if (!crop_test_abort_out || crop_test_valid_out) begin
                $display("[TB] RESULT: FAIL abort did not clear held output");
                errors = errors + 1;
            end
            @(negedge pixel_clk);
            crop_test_valid = 1'b0;
            crop_test_abort = 1'b0;
        end
    endtask

    always @(posedge pixel_clk) begin
        if (!reset_n) begin
            ready_lfsr <= 16'h1;
            axis_ready <= 1'b0;
        end else begin
            ready_lfsr <= {ready_lfsr[14:0],ready_lfsr[15]^ready_lfsr[13]^ready_lfsr[12]^ready_lfsr[10]};
            axis_ready <= ready_lfsr[0] | ready_lfsr[3];
        end
        if (axis_valid && axis_ready) begin
            for (keep_index=0; keep_index<16; keep_index=keep_index+1) begin
                if (axis_keep[keep_index]) begin
                    if (check_bytes && axis_data[keep_index*8 +: 8] !== expected_byte(frame_bytes)) begin
                        $display("[TB] RESULT: FAIL byte=%0d got=%0d expected=%0d",
                                 frame_bytes,axis_data[keep_index*8 +: 8],expected_byte(frame_bytes));
                        errors = errors + 1;
                    end
                    frame_bytes = frame_bytes + 1;
                    output_bytes = output_bytes + 1;
                end
            end
            if (axis_last) begin
                axis_last_count = axis_last_count + 1;
                if (check_bytes && frame_bytes != FRAME_BYTES) errors = errors + 1;
                frame_bytes = 0;
            end
        end
        if (frame_done) begin
            done_count = done_count + 1;
            if (crc_delay_active)
                early_done_seen = 1'b1;
        end
        if (frame_error) error_count = error_count + 1;
    end

    initial begin
        word_clk=0; pixel_clk=0; reset_n=0; aligned_word=0; aligned_valid=0;
        axis_ready=0; errors=0; seed=32'h31415926; output_bytes=0; frame_bytes=0;
        done_count=0; error_count=0; axis_last_count=0; check_bytes=1; ready_lfsr=16'h1;
        crc_delay_active=0; early_done_seen=0;
        crop_test_data=0; crop_test_valid=0; crop_test_sof=0; crop_test_eol=0;
        crop_test_abort=0; crop_test_sink_ready=0;
        repeat (15) @(posedge word_clk);
        reset_n=1;
        repeat (20) @(posedge word_clk);

        verify_abort_bypasses_held_output;

        send_frame(-1);
        wait(done_count==1);
        if (frame_bytes != 0 || output_bytes != FRAME_BYTES || axis_last_count != 1)
            errors=errors+1;

        check_bytes=0;
        frame_bytes=0;
        send_frame(4);
        wait(error_count==1);
        repeat (100) @(posedge pixel_clk);
        if (done_count != 1 || axis_last_count != 1 || crc_error_count != 1 ||
            early_done_seen) begin
            $display("[TB] RESULT: FAIL bad CRC done=%0d last=%0d crc=%0d early=%0d",
                     done_count,axis_last_count,crc_error_count,early_done_seen);
            errors=errors+1;
        end

        check_bytes=1;
        frame_bytes=0;
        output_bytes=0;
        send_frame(-1);
        wait(done_count==2);
        if (output_bytes != FRAME_BYTES || axis_last_count != 2) errors=errors+1;
        repeat (20) @(posedge pixel_clk);

        if (errors==0)
            $display("[TB] RESULT: PASS CSI FIFO to RGB AXIS, CRC abort, recovery");
        else
            $display("[TB] RESULT: FAIL errors=%0d",errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("[TB] RESULT: FAIL timeout");
        $finish;
    end

endmodule
