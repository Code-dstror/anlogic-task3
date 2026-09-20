`timescale 1ns/1ps

module tb_camera_rgb_pipeline #(
    parameter integer WIDTH = 16,
    parameter integer HEIGHT = 4,
    parameter integer FULL_RUN = 0,
    parameter integer GAMMA_BYPASS = 1
);

    localparam integer FIRST_ROW = 1;
    localparam integer FIRST_GROUP = 1;
    localparam integer RAW_GROUPS = FIRST_GROUP + WIDTH/4 + 1;
    localparam integer RAW_ROWS = FIRST_ROW + HEIGHT + 1;
    localparam integer FRAME_BYTES = WIDTH * HEIGHT * 3;

    reg i_clk;
    reg i_rst_n;
    reg [39:0] i_raw_data;
    reg i_raw_valid;
    wire o_raw_ready;
    reg i_raw_sof;
    reg i_raw_eol;
    reg i_raw_abort;
    wire [127:0] o_axis_tdata;
    wire [15:0] o_axis_tkeep;
    wire o_axis_tvalid;
    reg i_axis_tready;
    wire o_axis_tlast;
    wire o_frame_error;
    wire o_frame_done;

    integer errors;
    integer seed;
    integer ready_random;
    integer checking;
    integer output_byte_count;
    integer frame_byte_count;
    integer frame_done_count;
    integer frame_error_count;
    integer cycle_count;
    integer frame_start_cycle;
    integer frame_end_cycle;
    integer lane;
    reg [127:0] stalled_data;
    reg [15:0] stalled_keep;
    reg stalled_last;
    reg was_stalled;

    camera_rgb_pipeline #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .FIRST_ROW(FIRST_ROW),
        .FIRST_GROUP(FIRST_GROUP),
        .BAYER_PHASE(2'b00),
        .GAMMA_BYPASS(GAMMA_BYPASS)
    ) dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_raw_data(i_raw_data),
        .i_raw_valid(i_raw_valid),
        .o_raw_ready(o_raw_ready),
        .i_raw_sof(i_raw_sof),
        .i_raw_eol(i_raw_eol),
        .i_raw_abort(i_raw_abort),
        .o_axis_tdata(o_axis_tdata),
        .o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),
        .i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),
        .o_frame_error(o_frame_error),
        .o_frame_done(o_frame_done)
    );

    always #4 i_clk = ~i_clk;

    function [9:0] raw_pixel;
        input integer raw_x;
        input integer raw_y;
        integer crop_x;
        integer crop_y;
        begin
            crop_x = raw_x - FIRST_GROUP*4;
            crop_y = raw_y - FIRST_ROW;
            if (crop_x >= 0 && crop_y >= 0) begin
                if ((crop_y & 1) == 0 && (crop_x & 1) == 0)
                    raw_pixel = 10'd950;
                else if ((crop_y & 1) == 1 && (crop_x & 1) == 1)
                    raw_pixel = 10'd250;
                else
                    raw_pixel = 10'd550;
            end else begin
                raw_pixel = 10'd550;
            end
        end
    endfunction

    function [7:0] expected_byte;
        input integer byte_position;
        integer linear_value;
        real normalized;
        real encoded;
        begin
            case (byte_position % 3)
                0: linear_value = 900;
                1: linear_value = 500;
                default: linear_value = 200;
            endcase
            if (GAMMA_BYPASS) begin
                expected_byte = linear_value >> 2;
            end else begin
                normalized = linear_value / 1023.0;
                encoded = 255.0 * $pow(normalized, 1.0/2.2);
                expected_byte = $rtoi(encoded + 0.5);
            end
        end
    endfunction

    always @(negedge i_clk) begin
        if (!i_rst_n)
            i_axis_tready <= 1'b0;
        else if (ready_random)
            i_axis_tready <= (($random(seed) & 7) != 0);
        else
            i_axis_tready <= 1'b1;
    end

    always @(posedge i_clk) begin
        cycle_count = cycle_count + 1;
        if (!i_rst_n) begin
            was_stalled <= 1'b0;
        end else begin
            if (was_stalled && (!o_axis_tvalid || o_axis_tdata !== stalled_data ||
                o_axis_tkeep !== stalled_keep || o_axis_tlast !== stalled_last)) begin
                $display("[TB] ERROR: AXIS output changed while stalled");
                errors = errors + 1;
            end
            was_stalled <= o_axis_tvalid && !i_axis_tready;
            if (o_axis_tvalid && !i_axis_tready) begin
                stalled_data <= o_axis_tdata;
                stalled_keep <= o_axis_tkeep;
                stalled_last <= o_axis_tlast;
            end

            if (o_axis_tvalid && i_axis_tready) begin
                for (lane = 0; lane < 16; lane = lane + 1) begin
                    if (o_axis_tkeep[lane]) begin
                        if (checking && o_axis_tdata[lane*8 +: 8] !==
                            expected_byte(frame_byte_count)) begin
                            $display("[TB] ERROR: byte %0d got=%0d expected=%0d",
                                     frame_byte_count, o_axis_tdata[lane*8 +: 8],
                                     expected_byte(frame_byte_count));
                            errors = errors + 1;
                        end
                        frame_byte_count = frame_byte_count + 1;
                        output_byte_count = output_byte_count + 1;
                    end
                end
                if (o_axis_tlast) begin
                    if (checking && frame_byte_count != FRAME_BYTES) begin
                        $display("[TB] ERROR: frame length %0d expected %0d",
                                 frame_byte_count, FRAME_BYTES);
                        errors = errors + 1;
                    end
                    frame_byte_count = 0;
                    frame_end_cycle = cycle_count;
                end
            end
            if (o_frame_done)
                frame_done_count = frame_done_count + 1;
            if (o_frame_error)
                frame_error_count = frame_error_count + 1;
        end
    end

    task drive_raw_beat;
        input integer raw_row;
        input integer raw_group;
        input integer sof_value;
        input integer eol_value;
        input integer abort_value;
        input integer allow_gap;
        integer gap_count;
        integer pixel_lane;
        begin
            if (allow_gap) begin
                gap_count = $random(seed) & 3;
                repeat (gap_count) @(posedge i_clk);
            end
            @(negedge i_clk);
            for (pixel_lane = 0; pixel_lane < 4; pixel_lane = pixel_lane + 1)
                i_raw_data[pixel_lane*10 +: 10] =
                    raw_pixel(raw_group*4 + pixel_lane, raw_row);
            i_raw_sof = sof_value;
            i_raw_eol = eol_value;
            i_raw_abort = abort_value;
            i_raw_valid = 1'b1;
            @(posedge i_clk);
            while (!o_raw_ready) @(posedge i_clk);
            @(negedge i_clk);
            i_raw_valid = 1'b0;
            i_raw_sof = 1'b0;
            i_raw_eol = 1'b0;
            i_raw_abort = 1'b0;
        end
    endtask

    task send_complete_frame;
        input integer allow_gap;
        integer raw_row;
        integer raw_group;
        begin
            for (raw_row = 0; raw_row < RAW_ROWS; raw_row = raw_row + 1) begin
                for (raw_group = 0; raw_group < RAW_GROUPS; raw_group = raw_group + 1) begin
                    drive_raw_beat(raw_row, raw_group,
                                   raw_row == 0 && raw_group == 0,
                                   raw_group == RAW_GROUPS-1, 0, allow_gap);
                end
            end
        end
    endtask

    task send_partial_then_abort;
        integer raw_row;
        integer raw_group;
        integer output_before;
        begin
            output_before = output_byte_count;
            for (raw_row = 0; raw_row < FIRST_ROW + 3; raw_row = raw_row + 1) begin
                for (raw_group = 0; raw_group < RAW_GROUPS; raw_group = raw_group + 1) begin
                    drive_raw_beat(raw_row, raw_group,
                                   raw_row == 0 && raw_group == 0,
                                   raw_group == RAW_GROUPS-1, 0, 0);
                end
            end
            while (output_byte_count == output_before) @(posedge i_clk);
            drive_raw_beat(FIRST_ROW + 3, 0, 0, 0, 1, 0);
        end
    endtask

    task send_malformed_short_line;
        integer raw_group;
        begin
            for (raw_group = 0; raw_group < RAW_GROUPS; raw_group = raw_group + 1)
                drive_raw_beat(0, raw_group, raw_group == 0,
                               raw_group == RAW_GROUPS-1, 0, 0);
            drive_raw_beat(1, 0, 0, 0, 0, 0);
            drive_raw_beat(1, 1, 0, 1, 0, 0);
        end
    endtask

    task wait_done_count;
        input integer target;
        integer timeout;
        begin
            timeout = 0;
            while (frame_done_count < target && timeout < 50000000) begin
                @(posedge i_clk);
                timeout = timeout + 1;
            end
            if (timeout == 50000000) begin
                $display("[TB] ERROR: frame completion timeout target=%0d got=%0d",
                         target, frame_done_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst_n = 1'b0;
        i_raw_data = 40'd0;
        i_raw_valid = 1'b0;
        i_raw_sof = 1'b0;
        i_raw_eol = 1'b0;
        i_raw_abort = 1'b0;
        i_axis_tready = 1'b0;
        errors = 0;
        seed = 32'h51c39a27;
        ready_random = 0;
        checking = 1;
        output_byte_count = 0;
        frame_byte_count = 0;
        frame_done_count = 0;
        frame_error_count = 0;
        cycle_count = 0;
        frame_start_cycle = 0;
        frame_end_cycle = 0;
        was_stalled = 1'b0;

        repeat (8) @(posedge i_clk);
        i_rst_n = 1'b1;
        repeat (4) @(posedge i_clk);
        frame_start_cycle = cycle_count;

        if (FULL_RUN) begin
            ready_random = 0;
            send_complete_frame(0);
            wait_done_count(1);
            if (output_byte_count != FRAME_BYTES) begin
                $display("[TB] ERROR: full frame byte total %0d expected %0d",
                         output_byte_count, FRAME_BYTES);
                errors = errors + 1;
            end
            $display("[TB] RATE width=%0d height=%0d bytes=%0d cycles=%0d",
                     WIDTH, HEIGHT, output_byte_count,
                     frame_end_cycle-frame_start_cycle);
        end else begin
            ready_random = 1;
            send_complete_frame(1);
            send_complete_frame(1);
            wait_done_count(2);

            checking = 0;
            frame_byte_count = 0;
            send_partial_then_abort;
            while (frame_error_count < 1) @(posedge i_clk);
            repeat (20) @(posedge i_clk);

            frame_byte_count = 0;
            send_malformed_short_line;
            while (frame_error_count < 2) @(posedge i_clk);
            repeat (20) @(posedge i_clk);

            checking = 1;
            frame_byte_count = 0;
            send_complete_frame(1);
            wait_done_count(3);
        end

        repeat (10) @(posedge i_clk);
        if (errors == 0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #2000000000;
        $display("[TB] ERROR: global timeout");
        $finish;
    end

endmodule
