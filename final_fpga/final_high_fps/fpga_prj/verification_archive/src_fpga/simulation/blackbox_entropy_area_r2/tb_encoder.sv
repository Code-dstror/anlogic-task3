`timescale 1ns/1ps
module tb_encoder;
    localparam integer FRAMES = 4;
    localparam integer MAX_WIDTH = 3840;
    localparam integer MAX_HEIGHT = 32;
    localparam integer MAX_GROUPS = MAX_WIDTH * MAX_HEIGHT / 4;
    localparam integer WATCHDOG = 2200000;

    reg clk = 0;
    reg rst_n = 0;
    always #4 clk = ~clk;

    reg [95:0] rgb = 0;
    reg [31:0] luma = 0;
    reg [31:0] session_id = 0, epoch = 0, capture_id = 0;
    reg camera_id = 0, sof = 0, eol = 0, rgb_valid = 0;
    reg [15:0] restart_mcus = 0;
    reg [12:0] width = 0, height = 0;
    wire rgb_ready;
    reg status_valid = 0, frame_ok = 0;
    wire status_ready;
    wire [127:0] axis_data;
    wire [15:0] axis_keep;
    wire axis_valid, axis_last;
    reg axis_ready = 1;
    wire result_valid, result_ok, idle;
    wire [31:0] result_id, result_epoch;
    wire [24:0] result_length;
    wire [7:0] result_error, result_quality;
    reg result_ready = 0;

    jpeg_encoder_top #(
        .MAX_WIDTH(MAX_WIDTH), .MAX_HEIGHT(MAX_HEIGHT), .SHARED_STREAM_ENABLE(1),
        .ROM_INIT_ROOT("./rom_init"), .ROM_INIT_SUFFIX(".mif.dath"),
        .TINY_DISTRIBUTED_RAM_ENABLE(0), .COEFF_BANKED_STORAGE_ENABLE(1),
        .MCU_ROW_STREAM_ENABLE(1), .FIXED_GEOMETRY_ENABLE(0), .DUAL_GEOMETRY_ENABLE(1)
    ) dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_rgb(rgb), .i_luma(luma), .i_quality(8'd75),
        .i_session_id(session_id), .i_mode_epoch(epoch), .i_camera_id(camera_id),
        .i_restart_mcus(restart_mcus), .i_rgb_valid(rgb_valid), .o_rgb_ready(rgb_ready),
        .i_sof(sof), .i_eol(eol), .i_capture_id(capture_id), .i_width(width), .i_height(height),
        .i_frame_status_valid(status_valid), .o_frame_status_ready(status_ready),
        .i_frame_status_id(capture_id), .i_frame_ok(frame_ok),
        .o_axis_tdata(axis_data), .o_axis_tkeep(axis_keep), .o_axis_tvalid(axis_valid),
        .i_axis_tready(axis_ready), .o_axis_tlast(axis_last),
        .o_result_valid(result_valid), .i_result_ready(result_ready),
        .o_result_id(result_id), .o_result_ok(result_ok), .o_payload_length(result_length),
        .o_error_code(result_error), .o_result_quality(result_quality),
        .o_result_epoch(result_epoch), .o_idle(idle)
    );

    integer cycle = 0, frame = -1;
    integer log_fd, config_fd, fields;
    integer width_cfg, height_cfg, restart_cfg, camera_cfg, ok_cfg;
    integer group_count, groups_per_line, rgb_count = 0, axis_count = 0;
    integer accepted_length = 0, tail_cycle = -1, source_cycle = -1;
    integer first_result = -1, result_cycle = -1;
    integer pause_left = 0, last_regular_pause = -1;
    integer first_frame = 0, end_frame = FRAMES;
    string trace_path = "encoder.trace";
    reg [127:0] pixels [0:MAX_GROUPS-1];
    reg active = 0;
    reg stalled_axis = 0, stalled_result = 0;
    reg negative_hold = 0, release_negative = 0, paused_tail = 0;
    reg [144:0] held_axis;
    wire [105:0] result = {result_id, result_ok, result_length, result_error,
                           result_quality, result_epoch};
    reg [105:0] held_result;

    always @(negedge clk) begin
        #1;
        axis_ready = 1;
        if (active && rst_n) begin
            if (frame == 2 && rgb_count == group_count && !release_negative &&
                (axis_valid || negative_hold)) begin
                negative_hold = 1;
                axis_ready = 0;
            end else if (pause_left > 0) begin
                pause_left = pause_left - 1;
                axis_ready = 0;
            end else if (axis_valid && frame == 1 && axis_last && !paused_tail) begin
                paused_tail = 1;
                pause_left = 9;
                axis_ready = 0;
            end else if (axis_valid && frame == 1 && axis_count % 113 == 2 &&
                         axis_count != last_regular_pause) begin
                last_regular_pause = axis_count;
                pause_left = 4;
                axis_ready = 0;
            end
        end
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle > WATCHDOG)
            $fatal(1, "encoder watchdog frame=%0d RGB=%0d AXIS=%0d SOURCE=%0d RESULT=%0d idle=%b",
                   frame, rgb_count, axis_count, source_cycle, result_cycle, idle);
        if (!rst_n) begin
            stalled_axis = 0;
            stalled_result = 0;
        end else if (!active) begin
            if (axis_valid || result_valid)
                $fatal(1, "unexpected JPEG output outside a frame cycle=%0d", cycle);
        end else begin
            if (stalled_axis && (axis_valid !== 1'b1 || {axis_data, axis_keep, axis_last} !== held_axis))
                $fatal(1, "AXIS offer changed under stall frame=%0d beat=%0d cycle=%0d", frame, axis_count, cycle);
            if (stalled_result && (result_valid !== 1'b1 || result !== held_result))
                $fatal(1, "RESULT offer changed under stall frame=%0d cycle=%0d", frame, cycle);
            stalled_axis = axis_valid && !axis_ready;
            stalled_result = result_valid && !result_ready;
            held_axis = {axis_data, axis_keep, axis_last};
            held_result = result;
            if (axis_valid && (tail_cycle >= 0 || first_result >= 0))
                $fatal(1, "AXIS after LAST or RESULT frame=%0d cycle=%0d", frame, cycle);
            if (stalled_axis)
                $fwrite(log_fd, "H %0d %0d %0d %0d\n", frame, cycle, axis_count, axis_last);

            if (result_valid) begin
                if (source_cycle < 0 || axis_valid || (frame_ok && tail_cycle < 0) || result_cycle >= 0)
                    $fatal(1, "RESULT before prerequisites or repeated frame=%0d cycle=%0d", frame, cycle);
                if (result_id !== capture_id || result_epoch !== epoch || result_quality !== 8'd75 ||
                    result_ok !== frame_ok || result_error !== (frame_ok ? 8'd0 : 8'd1) ||
                    result_length !== (frame_ok ? accepted_length[24:0] : 25'd0))
                    $fatal(1, "RESULT mismatch frame=%0d id=%08x epoch=%08x quality=%0d ok=%b error=%02x length=%0d",
                           frame, result_id, result_epoch, result_quality, result_ok, result_error, result_length);
                if (first_result < 0) begin
                    first_result = cycle;
                    $fwrite(log_fd, "P %0d %0d\n", frame, cycle);
                end
                if (result_ready) begin
                    result_cycle = cycle;
                    $fwrite(log_fd, "R %0d %0d %08x %0d %02x %0d %0d %08x\n", frame, cycle,
                            result_id, result_ok, result_error, result_length, result_quality, result_epoch);
                end
            end
            if (axis_valid && axis_ready) begin
                if (axis_keep == 0 || (axis_keep & (axis_keep + 16'd1)) != 0 ||
                    (!axis_last && axis_keep != 16'hffff))
                    $fatal(1, "bad AXIS KEEP frame=%0d beat=%0d keep=%04x", frame, axis_count, axis_keep);
                $fwrite(log_fd, "B %0d %0d %04x %0d %032x\n", frame, cycle, axis_keep, axis_last, axis_data);
                accepted_length = accepted_length + $countones(axis_keep);
                axis_count = axis_count + 1;
                if (axis_last)
                    tail_cycle = cycle;
            end
            if (status_valid && status_ready) begin
                if (rgb_count != group_count || source_cycle >= 0)
                    $fatal(1, "SOURCE accepted at incorrect frame boundary frame=%0d", frame);
                source_cycle = cycle;
                $fwrite(log_fd, "S %0d %0d %08x %0d\n", frame, cycle, capture_id, frame_ok);
            end
            if (rgb_valid && rgb_ready) begin
                $fwrite(log_fd, "I %0d %0d %0d\n", frame, cycle, rgb_count);
                rgb_count = rgb_count + 1;
            end
        end
    end

    task read_config;
        begin
            fields = $fscanf(config_fd, "%h %h %h %d %d %d %d %d", capture_id, epoch,
                             session_id, camera_cfg, width_cfg, height_cfg, restart_cfg, ok_cfg);
            if (fields != 8)
                $fatal(1, "bad encoder config frame=%0d", frame);
        end
    endtask

    initial begin
        fields = $value$plusargs("first_frame=%d", first_frame);
        fields = $value$plusargs("end_frame=%d", end_frame);
        fields = $value$plusargs("trace_path=%s", trace_path);
        if (first_frame < 0 || end_frame > FRAMES || first_frame >= end_frame)
            $fatal(1, "invalid encoder fixture range [%0d,%0d)", first_frame, end_frame);
        log_fd = $fopen(trace_path, "w");
        config_fd = $fopen("encoder.config", "r");
        if (!log_fd || !config_fd)
            $fatal(1, "cannot open encoder trace or fixture");
        repeat (12) @(negedge clk);
        rst_n = 1;
        repeat (6) @(negedge clk);

        for (frame = 0; frame < first_frame; frame = frame + 1)
            read_config();
        for (frame = first_frame; frame < end_frame; frame = frame + 1) begin
            while (idle !== 1'b1) @(negedge clk);
            read_config();
            group_count = width_cfg * height_cfg / 4;
            groups_per_line = width_cfg / 4;
            if (group_count > MAX_GROUPS || groups_per_line < 1)
                $fatal(1, "bad encoder config frame=%0d", frame);
            $readmemh($sformatf("encoder_%0d.pixels", frame), pixels, 0, group_count - 1);
            width = width_cfg[12:0];
            height = height_cfg[12:0];
            camera_id = camera_cfg[0];
            restart_mcus = restart_cfg[15:0];
            frame_ok = ok_cfg[0];
            rgb_count = 0;
            axis_count = 0;
            accepted_length = 0;
            tail_cycle = -1;
            source_cycle = -1;
            first_result = -1;
            result_cycle = -1;
            pause_left = 0;
            last_regular_pause = -1;
            negative_hold = 0;
            release_negative = 0;
            paused_tail = 0;
            active = 1;
            $fwrite(log_fd, "F %0d %0d\n", frame, cycle);
            while (rgb_count < group_count) begin
                {luma, rgb} = pixels[rgb_count];
                sof = rgb_count == 0;
                eol = rgb_count % groups_per_line == groups_per_line - 1;
                rgb_valid = 1;
                @(negedge clk);
            end
            rgb_valid = 0;
            if (frame == 0) begin
                while (tail_cycle < 0) @(negedge clk);
                repeat (7) @(negedge clk);
            end else if (frame == 2) begin
                while (!negative_hold) @(negedge clk);
            end
            status_valid = 1;
            while (source_cycle < 0) @(negedge clk);
            status_valid = 0;
            if (frame == 2) begin
                repeat (6) @(negedge clk);
                release_negative = 1;
            end
            while (first_result < 0) @(negedge clk);
            repeat (8) @(negedge clk);
            result_ready = 1;
            while (result_cycle < 0) @(negedge clk);
            result_ready = 0;
            while (idle !== 1'b1) @(negedge clk);
            $fwrite(log_fd, "N %0d %0d\n", frame, cycle);
            active = 0;
            repeat (8) @(negedge clk);
        end
        $fclose(config_fd);
        $fclose(log_fd);
        $display("PASS encoder_area_r2 frames=%0d cycles=%0d", end_frame - first_frame, cycle);
        $finish;
    end
endmodule
