`timescale 1ns/1ps

module tb_dcp_clear;
    localparam integer WIDTH = 256, HEIGHT = 128, ROW = WIDTH/4, GROUPS = ROW*HEIGHT;
    localparam [31:0] SESSION = 32'h155a5a01, EPOCH = 32'h12345678;
    reg clk = 0, rst_n = 0, clear = 0, history_reset = 0, enable = 0, camera = 0;
    reg [31:0] seq = 0;
    reg source_valid = 0, source_sof = 0, source_eol = 0;
    reg [95:0] source_rgb = 0;
    reg [31:0] source_luma = 0;
    wire source_ready;
    reg terminal_valid = 0, terminal_ok = 0, terminal_camera = 0;
    reg [31:0] terminal_seq = 0;
    wire sink_valid, sink_sof, sink_eol, history_used, pending, pixel_pending;
    wire [95:0] sink_rgb;
    wire [31:0] sink_luma;
    reg sink_open = 1, hold_tail = 0, live = 0, uniform_frame = 0, expect_history = 0;
    integer received = 0, sent = 0, full_frames = 0, cancelled = 0, held_cycles = 0;
    integer cycle = 0;
    reg add_finite_stall = 0;
    wire sink_ready = sink_open && !(hold_tail && received == GROUPS-1) &&
                      !(add_finite_stall && cycle % 13 == 4);
    string scenario;

    dehaze_dcp_restore4 #(.WIDTH(WIDTH), .HEIGHT(HEIGHT), .EXTERNAL_DARK_ENABLE(0)) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .i_history_reset(history_reset), .i_enable(enable),
        .i_camera(camera), .i_session(SESSION), .i_epoch(EPOCH), .i_sequence(seq),
        .s_valid(source_valid), .s_sof(source_sof), .s_eol(source_eol), .s_ready(source_ready),
        .s_rgb(source_rgb), .s_luma(source_luma), .s_dark_statistics(16'b0),
        .i_terminal_valid(terminal_valid), .i_terminal_ok(terminal_ok), .i_terminal_camera(terminal_camera),
        .i_terminal_session(SESSION), .i_terminal_epoch(EPOCH), .i_terminal_sequence(terminal_seq),
        .m_valid(sink_valid), .m_sof(sink_sof), .m_eol(sink_eol), .m_ready(sink_ready),
        .m_rgb(sink_rgb), .m_luma(sink_luma), .o_history_used(history_used),
        .o_pending(pending), .o_pixel_pending(pixel_pending)
    );

    function automatic [127:0] raster_group(input integer eye, input integer sequence_id,
                                             input integer group_index, input bit uniform);
        integer k, p;
        for (k = 0; k < 4; k = k + 1) begin
            p = 4*group_index+k;
            if (uniform) begin
                raster_group[k*24 +: 24] = 24'hc0c0c0;
                raster_group[96+k*8 +: 8] = 8'hc0;
            end else begin
                raster_group[k*24+16 +: 8] = (p + 11*sequence_id + 3*eye) % 256;
                raster_group[k*24+8 +: 8] = (3*p + group_index/ROW + 19*sequence_id + 7*eye) % 256;
                raster_group[k*24 +: 8] = (5*p + 13*k + 31*sequence_id + 11*eye) % 256;
                raster_group[96+k*8 +: 8] = (7*p + 29*k + 23*sequence_id + 17*eye) % 256;
            end
        end
    endfunction

    reg held = 0;
    reg [129:0] held_fields;
    wire [129:0] output_fields = {sink_luma, sink_rgb, sink_sof, sink_eol};
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            if (rst_n && clear && source_ready !== 1'b0) $fatal(1, "READY open during clear");
            sent <= 0;
            received <= 0;
            held <= 0;
        end else begin
            cycle <= cycle + 1;
            if (source_valid && source_ready) begin
                if (!live || sent >= GROUPS || source_sof !== (sent == 0) ||
                    source_eol !== (sent % ROW == ROW-1)) $fatal(1, "fixture: source geometry/order");
                sent <= sent + 1;
            end
            if (held && (!sink_valid || output_fields !== held_fields))
                $fatal(1, "DCP offered output changed under stall");
            if (held) held_cycles <= held_cycles + 1;
            held <= sink_valid && !sink_ready;
            held_fields <= output_fields;
            if (sink_valid) begin
                if (!live || received >= GROUPS || received >= sent + (source_valid && source_ready))
                    $fatal(1, "output outside current frame: sent=%0d received=%0d live=%b", sent, received, live);
                if ({sink_luma, sink_rgb} !== raster_group(int'(camera), int'(seq), received, uniform_frame) ||
                    sink_sof !== (received == 0) || sink_eol !== (received % ROW == ROW-1))
                    $fatal(1, "RGB/Y or SOF/EOL mismatch eye=%0d seq=%0d group=%0d", camera, seq, received);
                if (history_used !== expect_history)
                    $fatal(1, "history choice mismatch eye=%0d seq=%0d got=%b expected=%b", camera, seq, history_used, expect_history);
                if (sink_ready) received <= received + 1;
            end
        end
    end

    always #4 clk = ~clk;

    task automatic begin_frame(input bit eye, input integer sequence_id, input bit uniform,
                               input bit use_history, input bit wanted_history);
        if (live || pending || pixel_pending || sink_valid) $fatal(1, "fixture: prior frame still pending");
        sent = 0;
        received = 0;
        camera = eye;
        seq = sequence_id;
        uniform_frame = uniform;
        enable = use_history;
        expect_history = wanted_history;
        live = 1;
    endtask

    task automatic groups_until(input integer limit);
        reg [127:0] group_data;
        integer i;
        for (i = sent; i < limit; i = i + 1) begin
            source_valid = 1;
            source_sof = i == 0;
            source_eol = i % ROW == ROW-1;
            group_data = raster_group(int'(camera), int'(seq), i, uniform_frame);
            {source_luma, source_rgb} = group_data;
            while (sent <= i) @(negedge clk);
        end
        source_valid = 0;
    endtask

    task automatic source_terminal(input bit eye, input integer sequence_id, input bit ok);
        terminal_valid = 1;
        terminal_ok = ok;
        terminal_camera = eye;
        terminal_seq = sequence_id;
        @(negedge clk);
        terminal_valid = 0;
    endtask

    task automatic wait_frame;
        while (received < GROUPS || pending || pixel_pending) @(negedge clk);
        if (sent != GROUPS || received != GROUPS || sink_valid) $fatal(1, "full DCP frame incomplete");
        $display("DCP_FRAME eye=%b seq=%0d groups=%0d used_history=%b", camera, seq, received, expect_history);
        full_frames = full_frames + 1;
        live = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic flush(input integer clocks, input integer terminal_status);
        $display("DCP_CLEAR eye=%b seq=%0d sent=%0d consumed=%0d held_valid=%b terminal=%0d",
                 camera, seq, sent, received, sink_valid && !sink_ready, terminal_status);
        if (live) cancelled = cancelled + 1;
        live = 0;
        clear = 1;
        if (terminal_status >= 0) begin
            terminal_valid = 1;
            terminal_ok = terminal_status != 0;
            terminal_camera = camera;
            terminal_seq = seq;
        end
        repeat (clocks) begin
            @(negedge clk);
            terminal_valid = 0;
        end
        clear = 0;
        sink_open = 1;
        hold_tail = 0;
        repeat (3) @(negedge clk);
        while (pending || pixel_pending) @(negedge clk);
        if (history_used !== 1'b0 || sink_valid || sent != 0 || received != 0)
            $fatal(1, "stale validity after clear");
    endtask

    task automatic clear_case;
        begin_frame(0, 1, 0, 0, 0);
        add_finite_stall = 1;
        groups_until(GROUPS-3);
        source_terminal(0, 1, 1); // Matching terminal before the final three groups.
        groups_until(GROUPS);
        wait_frame();
        add_finite_stall = 0;

        sink_open = 0;
        begin_frame(1, 2, 0, 0, 0);
        groups_until(1);
        while (!sink_valid) @(negedge clk);
        repeat (4) @(negedge clk);
        if (!sink_sof || received != 0) $fatal(1, "coverage: no held first beat");
        flush(1, 1);  // Positive terminal on the same edge as clear.
        flush(2, -1); // Second clear with no old data.

        begin_frame(0, 3, 0, 0, 0);
        groups_until(177);
        source_terminal(0, 3, 0);
        if (received == 0 || received >= GROUPS) $fatal(1, "coverage: no consumed body prefix");
        flush(2, -1);

        begin_frame(1, 4, 0, 0, 0);
        hold_tail = 1;
        groups_until(GROUPS);
        while (!(sink_valid && received == GROUPS-1)) @(negedge clk);
        repeat (4) @(negedge clk);
        if (!sink_eol || sink_ready) $fatal(1, "coverage: final group was not held");
        flush(1, -1);

        begin_frame(1, 5, 0, 0, 0);
        groups_until(3);
        source_terminal(1, 4, 1); // Old positive after clear must not replace new identity.
        groups_until(GROUPS);
        source_terminal(1, 5, 1);
        wait_frame();
        if (cancelled != 3 || full_frames != 2 || held_cycles < 8) $fatal(1, "incomplete clear coverage");
    endtask

    task automatic uniform_transaction(input bit eye, input integer sequence_id,
                                       input bit want_history, input bit ok);
        begin_frame(eye, sequence_id, 1, 1, want_history);
        groups_until(GROUPS);
        while (received != GROUPS) @(negedge clk);
        source_terminal(eye, sequence_id, ok);
        wait_frame();
    endtask

    task automatic history_reset_case;
        uniform_transaction(0, 1, 0, 0); // Complete geometry and negative SOURCE: no history.
        uniform_transaction(0, 2, 0, 1); // First actual success for eye 0.
        uniform_transaction(1, 1, 0, 1); // Eye 0's successful frame must not leak into eye 1.
        begin_frame(0, 3, 1, 1, 1); // Same eye and forward sequence use committed history.
        groups_until(9);
        while (received == 0) @(negedge clk);
        flush(1, 1); // A positive terminal with partial geometry and clear cannot publish.
        sink_open = 0;
        begin_frame(1, 2, 1, 1, 1); // Clear preserved earlier successful history.
        groups_until(1);
        while (!sink_valid) @(negedge clk);
        repeat (4) @(negedge clk);
        if (!sink_sof || received != 0) $fatal(1, "coverage: no held frame at reset");
        #1 rst_n = 0;
        live = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        sink_open = 1;
        repeat (4) @(negedge clk);
        if (pending || pixel_pending || sink_valid || history_used !== 1'b0)
            $fatal(1, "cold reset retained stale data or history validity");
        begin_frame(0, 4, 0, 1, 0);
        groups_until(GROUPS);
        source_terminal(0, 4, 1);
        wait_frame();
        if (full_frames != 4 || held_cycles < 3) $fatal(1, "incomplete history/reset coverage");
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", scenario)) $fatal(1, "fixture: specify CASE");
        repeat (6) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);
        case (scenario)
            "clear": clear_case();
            "history_reset": history_reset_case();
            default: $fatal(1, "fixture: unknown CASE");
        endcase
        $display("PASS_FIELD_DCP case=%s full_frames=%0d cancelled=%0d held_cycles=%0d sim_ns=%0d",
                 scenario, full_frames, cancelled, held_cycles, $time);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "watchdog case=%s eye=%0d seq=%0d sent=%0d received=%0d pending=%b/%b READY=%b VALID=%b",
                 scenario, camera, seq, sent, received, pending, pixel_pending, source_ready, sink_valid);
    end
endmodule
