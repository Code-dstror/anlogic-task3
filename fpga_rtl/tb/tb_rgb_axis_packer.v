`timescale 1ns/1ps

module tb_rgb_axis_packer;

    reg          i_clk;
    reg          i_rst_n;
    reg [95:0]   i_rgb_tdata;
    reg          i_rgb_tvalid;
    wire         o_rgb_tready;
    reg          i_rgb_tuser;
    reg          i_rgb_tlast;
    reg [12:0]   i_frame_height;
    reg          i_abort;
    wire [127:0] o_axis_tdata;
    wire [15:0]  o_axis_tkeep;
    wire         o_axis_tvalid;
    reg          i_axis_tready;
    wire         o_axis_tlast;
    wire         o_frame_error;
    wire         o_frame_done;

    reg [7:0] expected_bytes [0:8191];
    integer expected_length;
    integer expected_index;
    integer errors;
    integer done_count;
    integer error_count;
    integer seed;
    integer stall_cycles;
    integer ready_mode;
    integer byte_index;
    reg [127:0] held_data;
    reg [15:0] held_keep;
    reg held_last;
    reg was_stalled;

    rgb_axis_packer dut (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_rgb_tdata(i_rgb_tdata),
        .i_rgb_tvalid(i_rgb_tvalid),
        .o_rgb_tready(o_rgb_tready),
        .i_rgb_tuser(i_rgb_tuser),
        .i_rgb_tlast(i_rgb_tlast),
        .i_frame_height(i_frame_height),
        .i_abort(i_abort),
        .o_axis_tdata(o_axis_tdata),
        .o_axis_tkeep(o_axis_tkeep),
        .o_axis_tvalid(o_axis_tvalid),
        .i_axis_tready(i_axis_tready),
        .o_axis_tlast(o_axis_tlast),
        .o_frame_error(o_frame_error),
        .o_frame_done(o_frame_done)
    );

    always #4 i_clk = ~i_clk;

    always @(negedge i_clk) begin
        if (!i_rst_n) begin
            i_axis_tready <= 1'b0;
        end else if (ready_mode == 0) begin
            i_axis_tready <= (($random(seed) & 7) != 0);
        end else if (ready_mode == 1) begin
            i_axis_tready <= 1'b0;
        end else begin
            i_axis_tready <= 1'b1;
        end
    end

    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            expected_index <= 0;
            done_count <= 0;
            error_count <= 0;
            was_stalled <= 1'b0;
        end else begin
            if (was_stalled) begin
                if (!o_axis_tvalid || o_axis_tdata !== held_data ||
                    o_axis_tkeep !== held_keep || o_axis_tlast !== held_last) begin
                    $display("[TB] ERROR: AXIS changed while stalled");
                    errors = errors + 1;
                end
            end
            was_stalled <= o_axis_tvalid && !i_axis_tready;
            if (o_axis_tvalid && !i_axis_tready) begin
                held_data <= o_axis_tdata;
                held_keep <= o_axis_tkeep;
                held_last <= o_axis_tlast;
            end

            if (o_axis_tvalid && i_axis_tready) begin
                for (byte_index = 0; byte_index < 16; byte_index = byte_index + 1) begin
                    if (o_axis_tkeep[byte_index]) begin
                        if (expected_index >= expected_length) begin
                            $display("[TB] ERROR: unexpected byte %02x", o_axis_tdata[byte_index*8 +: 8]);
                            errors = errors + 1;
                        end else if (o_axis_tdata[byte_index*8 +: 8] !==
                                     expected_bytes[expected_index]) begin
                            $display("[TB] ERROR: byte %0d got=%02x expected=%02x",
                                     expected_index,
                                     o_axis_tdata[byte_index*8 +: 8],
                                     expected_bytes[expected_index]);
                            errors = errors + 1;
                        end
                        expected_index = expected_index + 1;
                    end
                end
                if (o_axis_tlast && (expected_index != expected_length)) begin
                    $display("[TB] ERROR: TLAST at byte %0d expected %0d",
                             expected_index, expected_length);
                    errors = errors + 1;
                end
            end
            if (o_frame_done) done_count <= done_count + 1;
            if (o_frame_error) error_count <= error_count + 1;
        end
    end

    task append_pixel;
        input integer pixel_id;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            red = pixel_id[7:0];
            green = (pixel_id + 8'h41) & 8'hff;
            blue = (pixel_id ^ 8'ha5) & 8'hff;
            expected_bytes[expected_length] = red;
            expected_bytes[expected_length + 1] = green;
            expected_bytes[expected_length + 2] = blue;
            expected_length = expected_length + 3;
        end
    endtask

    task drive_group;
        input integer first_pixel;
        input integer is_sof;
        input integer is_eol;
        integer lane;
        integer gap;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            for (lane = 0; lane < 4; lane = lane + 1) begin
                red = (first_pixel + lane) & 8'hff;
                green = (first_pixel + lane + 8'h41) & 8'hff;
                blue = (first_pixel + lane) ^ 8'ha5;
                i_rgb_tdata[lane*24 +: 24] = {red, green, blue};
                append_pixel(first_pixel + lane);
            end
            gap = $random(seed) & 3;
            repeat (gap) @(posedge i_clk);
            @(negedge i_clk);
            i_rgb_tuser = is_sof;
            i_rgb_tlast = is_eol;
            i_rgb_tvalid = 1'b1;
            @(posedge i_clk);
            while (!o_rgb_tready) @(posedge i_clk);
            @(negedge i_clk);
            i_rgb_tvalid = 1'b0;
            i_rgb_tuser = 1'b0;
            i_rgb_tlast = 1'b0;
        end
    endtask

    task send_frame;
        input integer width;
        input integer height;
        input integer base_pixel;
        integer x;
        integer y;
        integer done_before;
        begin
            expected_length = 0;
            expected_index = 0;
            i_frame_height = height;
            done_before = done_count;
            for (y = 0; y < height; y = y + 1) begin
                for (x = 0; x < width; x = x + 4) begin
                    drive_group(base_pixel + y*width + x,
                                (x == 0) && (y == 0),
                                (x + 4 == width));
                end
            end
            while (done_count == done_before) @(posedge i_clk);
            if (expected_index != expected_length) begin
                $display("[TB] ERROR: frame ended with %0d/%0d bytes",
                         expected_index, expected_length);
                errors = errors + 1;
            end
        end
    endtask

    task abort_stalled_frame;
        integer prior_errors;
        integer lane;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        begin
            expected_length = 0;
            expected_index = 0;
            i_frame_height = 13'd3;
            ready_mode = 1;
            drive_group(1000, 1, 0);
            drive_group(1004, 0, 1);
            while (!o_axis_tvalid) @(posedge i_clk);
            prior_errors = error_count;
            @(negedge i_clk);
            i_abort = 1'b1;
            @(negedge i_clk);
            i_abort = 1'b0;
            repeat (4) @(posedge i_clk);
            ready_mode = 2;
            while (o_axis_tvalid) @(posedge i_clk);
            repeat (2) @(posedge i_clk);
            if (error_count != prior_errors + 1) begin
                $display("[TB] ERROR: abort error pulse count mismatch");
                errors = errors + 1;
            end
            expected_length = 0;
            expected_index = 0;
            ready_mode = 0;
        end
    endtask

    task abort_stalled_tail;
        integer prior_errors;
        begin
            expected_length = 0;
            expected_index = 0;
            i_frame_height = 13'd1;
            ready_mode = 1;
            drive_group(1100, 1, 1);
            while (!o_axis_tvalid || !o_axis_tlast) @(posedge i_clk);
            prior_errors = error_count;
            @(negedge i_clk);
            i_abort = 1'b1;
            @(negedge i_clk);
            i_abort = 1'b0;
            repeat (4) @(posedge i_clk);
            if (!o_axis_tvalid || !o_axis_tlast || o_axis_tkeep !== 16'h0fff) begin
                $display("[TB] ERROR: abort changed a stalled tail beat");
                errors = errors + 1;
            end
            ready_mode = 2;
            while (o_axis_tvalid) @(posedge i_clk);
            repeat (2) @(posedge i_clk);
            if (error_count != prior_errors + 1) begin
                $display("[TB] ERROR: tail abort error pulse count mismatch");
                errors = errors + 1;
            end
            expected_length = 0;
            expected_index = 0;
            ready_mode = 0;
        end
    endtask

    task block_next_sof_until_tail_drains;
        integer wait_cycles;
        integer done_before;
        begin
            expected_length = 0;
            expected_index = 0;
            i_frame_height = 13'd1;
            ready_mode = 1;
            done_before = done_count;
            drive_group(1150, 1, 1);
            while (!o_axis_tvalid || !o_axis_tlast) @(posedge i_clk);
            @(negedge i_clk);
            i_rgb_tdata = 96'd0;
            i_rgb_tuser = 1'b1;
            i_rgb_tlast = 1'b1;
            i_rgb_tvalid = 1'b1;
            wait_cycles = 0;
            repeat (4) begin
                @(posedge i_clk);
                if (o_rgb_tready) begin
                    $display("[TB] ERROR: accepted next SOF before prior tail drained");
                    errors = errors + 1;
                end
                wait_cycles = wait_cycles + 1;
            end
            ready_mode = 2;
            while (!o_rgb_tready) @(posedge i_clk);
            #1;
            for (wait_cycles = 0; wait_cycles < 12; wait_cycles = wait_cycles + 1)
                expected_bytes[expected_length + wait_cycles] = 8'h00;
            expected_length = expected_length + 12;
            @(negedge i_clk);
            i_rgb_tvalid = 1'b0;
            i_rgb_tuser = 1'b0;
            i_rgb_tlast = 1'b0;
            ready_mode = 0;
            while (done_count < done_before + 2) @(posedge i_clk);
            expected_length = 0;
            expected_index = 0;
        end
    endtask

    initial begin
        i_clk = 1'b0;
        i_rst_n = 1'b0;
        i_rgb_tdata = 96'd0;
        i_rgb_tvalid = 1'b0;
        i_rgb_tuser = 1'b0;
        i_rgb_tlast = 1'b0;
        i_frame_height = 13'd0;
        i_abort = 1'b0;
        i_axis_tready = 1'b0;
        expected_length = 0;
        expected_index = 0;
        errors = 0;
        done_count = 0;
        error_count = 0;
        seed = 32'h19a3c75d;
        ready_mode = 0;
        was_stalled = 1'b0;

        repeat (5) @(posedge i_clk);
        i_rst_n = 1'b1;
        repeat (3) @(posedge i_clk);

        send_frame(4, 1, 0);
        send_frame(8, 1, 32);
        send_frame(12, 1, 96);
        send_frame(16, 1, 192);
        send_frame(4, 3, 320);
        send_frame(8, 2, 400);
        send_frame(12, 3, 500);
        send_frame(16, 2, 700);

        abort_stalled_frame;
        abort_stalled_tail;
        block_next_sof_until_tail_drains;
        send_frame(16, 2, 1200);

        @(negedge i_clk);
        i_rst_n = 1'b0;
        repeat (2) @(posedge i_clk);
        i_rst_n = 1'b1;
        repeat (3) @(posedge i_clk);
        send_frame(4, 1, 1500);

        if (errors == 0) begin
            $display("RESULT: PASS");
        end else begin
            $display("RESULT: FAIL errors=%0d", errors);
        end
        $finish;
    end

    initial begin
        #2000000;
        $display("[TB] ERROR: timeout");
        $finish;
    end

endmodule
