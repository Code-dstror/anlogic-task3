`timescale 1ns/1ps
module tb_entropy;
    localparam integer FRAMES = 11;
    localparam integer MAX_TOKENS = 756;
    localparam integer WATCHDOG = 280000;

    reg clk = 0;
    reg rst_n = 0;
    reg abort_frame = 0;
    always #4 clk = ~clk;

    reg token_valid = 0;
    reg [130:0] token = 0;
    reg [15:0] restart_mcus = 0;
    wire token_ready;
    wire byte_valid, byte_last, done, error_valid, idle;
    wire [7:0] octet, error_code;
    wire [31:0] error_id;
    reg byte_ready = 1;

    jpeg_entropy #(
        .STREAM_INPUT_ENABLE(1), .RESTART_ENABLE(1),
        .COEFF_BANKED_STORAGE_ENABLE(1),
        .ROM_INIT_ROOT("./rom_init"), .ROM_INIT_SUFFIX(".mif.dath")
    ) dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_abort(abort_frame),
        .i_block_valid(1'b0), .o_block_ready(), .i_coeffs(1024'b0),
        .i_component(2'b0), .i_block_index(2'b0), .i_mcu_x(9'b0), .i_mcu_y(9'b0),
        .i_frame_last(1'b0), .i_capture_id(32'b0),
        .i_token_valid(token_valid), .o_token_ready(token_ready), .i_token_data(token[127:0]),
        .i_token_keep(16'hffff), .i_token_last(token[128]), .i_token_user(token[130:129]),
        .i_restart_mcus(restart_mcus),
        .o_byte_valid(byte_valid), .i_byte_ready(byte_ready), .o_byte(octet), .o_byte_last(byte_last),
        .o_entropy_done(done), .o_error_valid(error_valid),
        .o_error_capture_id(error_id), .o_error_code(error_code), .o_idle(idle)
    );

    integer cycle = 0;
    integer log_fd, config_fd, scan_fields;
    integer frame = -1, interval, n_tokens, control, restart_ordinal, last_ordinal;
    integer accepted_tokens = 0, accepted_bytes = 0;
    integer held_streak = 0, pause_left = 0;
    integer done_count = 0, error_count = 0, tail_cycle = -1;
    reg [31:0] capture_id;
    reg [130:0] tokens [0:MAX_TOKENS-1];
    reg [8:0] held_byte;
    reg held = 0, active = 0, release_cancel = 0, control_fired = 0;
    reg paused_first = 0, paused_restart = 0, paused_last = 0;

    always @(negedge clk) begin
        #1;
        byte_ready = 1;
        if (active && rst_n) begin
            if ((control == 8 || control == 9) && accepted_bytes == 3 && !release_cancel) begin
                byte_ready = 0;
            end else if (pause_left > 0) begin
                pause_left = pause_left - 1;
                byte_ready = 0;
            end else if (byte_valid) begin
                if (accepted_bytes == 0 && !paused_first) begin
                    paused_first = 1;
                    pause_left = 6;
                    byte_ready = 0;
                end else if (accepted_bytes == restart_ordinal && !paused_restart) begin
                    paused_restart = 1;
                    pause_left = 6;
                    byte_ready = 0;
                end else if (accepted_bytes == last_ordinal && !paused_last) begin
                    paused_last = 1;
                    pause_left = 6;
                    byte_ready = 0;
                end
            end
        end
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle > WATCHDOG)
            $fatal(1, "entropy watchdog frame=%0d tokens=%0d bytes=%0d idle=%b",
                   frame, accepted_tokens, accepted_bytes, idle);
        if (!rst_n) begin
            held = 0;
            held_streak = 0;
        end else if (!active) begin
            if (byte_valid || done || error_valid)
                $fatal(1, "stray entropy offer or terminal, frame=%0d cycle=%0d", frame, cycle);
        end else begin
            if (held && (byte_valid !== 1'b1 || {byte_last, octet} !== held_byte))
                $fatal(1, "entropy byte changed under stall frame=%0d ordinal=%0d cycle=%0d",
                       frame, accepted_bytes, cycle);
            held = byte_valid && !byte_ready;
            held_byte = {byte_last, octet};
            if (held) begin
                held_streak = held_streak + 1;
                $fwrite(log_fd, "H %0d %0d %0d\n", frame, cycle, accepted_bytes);
            end else begin
                held_streak = 0;
            end
            if (token_valid && token_ready) begin
                $fwrite(log_fd, "I %0d %0d %0d\n", frame, cycle, accepted_tokens);
                accepted_tokens = accepted_tokens + 1;
            end
            if (byte_valid && byte_ready) begin
                if (tail_cycle >= 0 || done_count != 0 || (control == 9 && control_fired))
                    $fatal(1, "unexpected byte after entropy retirement frame=%0d cycle=%0d", frame, cycle);
                $fwrite(log_fd, "B %0d %0d %02x %0d\n", frame, cycle, octet, byte_last);
                accepted_bytes = accepted_bytes + 1;
            end
            if (done) begin
                if (control != 0 || tail_cycle < 0 || done_count != 0)
                    $fatal(1, "unexpected entropy DONE frame=%0d tail=%0d cycle=%0d", frame, tail_cycle, cycle);
                done_count = done_count + 1;
                $fwrite(log_fd, "D %0d %0d\n", frame, cycle);
            end
            if (byte_valid && byte_ready && byte_last)
                tail_cycle = cycle;
            if (error_valid) begin
                if ((control != 2 && control != 4) || error_count != 0 ||
                    error_id !== capture_id || error_code !== control[7:0])
                    $fatal(1, "unexpected entropy error frame=%0d code=%0d id=%08x cycle=%0d",
                           frame, error_code, error_id, cycle);
                error_count = error_count + 1;
                $fwrite(log_fd, "E %0d %0d %02x %08x\n", frame, cycle, error_code, error_id);
            end
        end
    end

    initial begin
        log_fd = $fopen("entropy.trace", "w");
        config_fd = $fopen("entropy.config", "r");
        if (!log_fd || !config_fd)
            $fatal(1, "cannot open entropy trace or fixture");
        repeat (12) @(negedge clk);
        rst_n = 1;
        repeat (6) @(negedge clk);

        for (frame = 0; frame < FRAMES; frame = frame + 1) begin
            while (idle !== 1'b1) @(negedge clk);
            scan_fields = $fscanf(config_fd, "%h %d %d %d %d %d",
                                  capture_id, interval, n_tokens, control, restart_ordinal, last_ordinal);
            if (scan_fields != 6 || n_tokens < 1 || n_tokens > MAX_TOKENS)
                $fatal(1, "bad entropy config frame=%0d", frame);
            $readmemh($sformatf("entropy_%0d.tokens", frame), tokens, 0, n_tokens - 1);
            restart_mcus = interval[15:0];
            accepted_tokens = 0;
            accepted_bytes = 0;
            done_count = 0;
            error_count = 0;
            tail_cycle = -1;
            pause_left = 0;
            paused_first = 0;
            paused_restart = 0;
            paused_last = 0;
            release_cancel = 0;
            control_fired = 0;
            active = 1;
            $fwrite(log_fd, "F %0d %0d\n", frame, cycle);
            while (accepted_tokens < n_tokens) begin
                token = tokens[accepted_tokens];
                token_valid = 1;
                @(negedge clk);
            end
            token_valid = 0;

            if (control == 8 || control == 9) begin
                while (held_streak < 5 || accepted_bytes != 3) @(negedge clk);
                control_fired = 1;
                $fwrite(log_fd, "C %0d %0d %0d\n", frame, cycle, control);
                if (control == 8) begin
                    abort_frame = 1;
                    repeat (4) @(negedge clk);
                    release_cancel = 1;
                    while (accepted_bytes != 4) @(negedge clk);
                    abort_frame = 0;
                end else begin
                    rst_n = 0;
                    repeat (12) @(negedge clk);
                    rst_n = 1;
                    repeat (6) @(negedge clk);
                end
            end
            while (idle !== 1'b1 || (control == 0 && done_count != 1) ||
                   ((control == 2 || control == 4) && error_count != 1)) @(negedge clk);
            $fwrite(log_fd, "N %0d %0d\n", frame, cycle);
            active = 0;
            repeat (8) @(negedge clk);
        end

        $fclose(config_fd);
        $fclose(log_fd);
        $display("PASS entropy_area_r2 frames=%0d cycles=%0d", FRAMES, cycle);
        $finish;
    end
endmodule
