`timescale 1ns/1ps

module tb_dehaze_transition;
    localparam integer WIDTH = 256;
    localparam integer HEIGHT = 128;
    localparam integer GROUPS_PER_LINE = WIDTH / 4;
    localparam integer GROUPS_PER_FRAME = GROUPS_PER_LINE * HEIGHT;
    localparam integer TAIL_LIMIT = 256;

    typedef struct packed {
        logic camera;
        logic [31:0] session;
        logic [31:0] epoch;
        logic [31:0] sequence_id;
    } key_t;

    logic clk = 0;
    logic clock_running = 1;
    logic rst_n = 0;
    logic clear = 0;
    logic i_history_reset = 0;
    logic i_enable = 0;
    key_t owner = '0;
    logic s_valid = 0;
    logic s_sof = 0;
    logic s_eol = 0;
    wire s_ready;
    logic [95:0] s_rgb = '0;
    logic [31:0] s_luma = '0;
    logic terminal_standalone = 0;
    logic terminal_on_accept = 0;
    logic terminal_ok = 0;
    key_t terminal_owner = '0;
    wire terminal_valid = terminal_standalone ||
                          (terminal_on_accept && s_valid && s_ready);
    wire m_valid, m_sof, m_eol;
    wire [95:0] m_rgb;
    wire [31:0] m_luma;
    wire o_history_used, o_pending, o_pixel_pending;

    logic sink_accepting = 1;
    logic finite_stalls = 0;
    integer clock_count = 0;
    wire m_ready = sink_accepting && (!finite_stalls || clock_count % 43 >= 7);

    string scenario = "initial reset";
    logic frame_open = 0;
    logic expect_history = 0;
    logic stalled_offer = 0;
    logic [129:0] stalled_fields;
    integer pattern_salt = 0;
    integer groups_in = 0;
    integer groups_out = 0;
    integer stall_cycles = 0;
    integer full_frames = 0;
    integer aborted_frames = 0;

    dehaze_dcp_restore4 #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .EXTERNAL_DARK_ENABLE(0)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear(clear), .i_history_reset(i_history_reset),
        .i_enable(i_enable), .i_camera(owner.camera), .i_session(owner.session),
        .i_epoch(owner.epoch), .i_sequence(owner.sequence_id),
        .s_valid(s_valid), .s_ready(s_ready), .s_sof(s_sof), .s_eol(s_eol),
        .s_rgb(s_rgb), .s_luma(s_luma), .s_dark_statistics(16'd0),
        .i_terminal_valid(terminal_valid), .i_terminal_ok(terminal_ok),
        .i_terminal_camera(terminal_owner.camera), .i_terminal_session(terminal_owner.session),
        .i_terminal_epoch(terminal_owner.epoch), .i_terminal_sequence(terminal_owner.sequence_id),
        .m_valid(m_valid), .m_ready(m_ready), .m_sof(m_sof), .m_eol(m_eol),
        .m_rgb(m_rgb), .m_luma(m_luma), .o_history_used(o_history_used),
        .o_pending(o_pending), .o_pixel_pending(o_pixel_pending)
    );

    always #5 if (clock_running) clk = ~clk;
    always @(posedge clk) clock_count <= clock_count + 1;

    function automatic key_t make_key(
        input logic camera, input logic [31:0] session, epoch, sequence_id
    );
        return {camera, session, epoch, sequence_id};
    endfunction

    function automatic logic [127:0] raster_group(input integer beat, salt);
        logic [95:0] rgb;
        logic [31:0] luma;
        integer red, green, blue;
        integer row, column;
        row = beat / GROUPS_PER_LINE;
        column = (beat % GROUPS_PER_LINE) * 4;
        for (integer lane = 0; lane < 4; lane++) begin
            red = 32 + (3 * (column + lane) + 5 * row + 13 * salt) % 192;
            green = 40 + (7 * (column + lane) + 2 * row + 17 * salt) % 184;
            blue = 24 + (11 * (column + lane) + 3 * row + 19 * salt) % 200;
            rgb[lane * 24 +: 24] = {red[7:0], green[7:0], blue[7:0]};
            luma[lane * 8 +: 8] = (77 * red + 150 * green + 29 * blue + 128) >> 8;
        end
        return {luma, rgb};
    endfunction

    task automatic fail(input string reason);
        $fatal(1, "FAIL_DEHAZE_TRANSITION %s t=%0t in=%0d out=%0d pending=%b pixel_pending=%b %s",
               scenario, $time, groups_in, groups_out, o_pending, o_pixel_pending, reason);
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            stalled_offer = 0;
        end else begin
            if (stalled_offer && (m_valid !== 1'b1 ||
                                 {m_sof, m_eol, m_luma, m_rgb} !== stalled_fields))
                fail("output changed while stalled");
            stalled_offer = m_valid && !m_ready;
            if (stalled_offer) begin
                stalled_fields = {m_sof, m_eol, m_luma, m_rgb};
                stall_cycles = stall_cycles + 1;
            end

            if (s_valid && s_ready) begin
                if (!frame_open || groups_in >= GROUPS_PER_FRAME)
                    fail("unexpected input handshake");
                groups_in = groups_in + 1;
            end
            if (m_valid && m_ready) begin
                if (!frame_open || groups_out >= groups_in)
                    fail("unexpected output handshake");
                if (m_sof !== (groups_out == 0) ||
                    m_eol !== (groups_out % GROUPS_PER_LINE == GROUPS_PER_LINE - 1))
                    fail("output SOF/EOL mismatch");
                if (!expect_history && {m_luma, m_rgb} !== raster_group(groups_out, pattern_salt))
                    fail("identity RGB/luma mismatch");
                if ((^{m_luma, m_rgb}) === 1'bx)
                    fail("unknown output pixels");
                groups_out = groups_out + 1;
            end
        end
    end

    task automatic require_quiet;
        integer elapsed;
        elapsed = 0;
        while ({o_pending, o_pixel_pending, m_valid} !== 3'b000) begin
            if (elapsed == TAIL_LIMIT)
                fail("pending/output did not clear");
            @(negedge clk);
            elapsed++;
        end
        repeat (3) begin
            @(negedge clk);
            if ({o_pending, o_pixel_pending, m_valid} !== 3'b000)
                fail("output or pending returned without an input");
        end
    endtask

    task automatic begin_frame(
        input string name, input key_t key, input logic enabled, reset_history,
        input logic history, stall_output
    );
        scenario = name;
        $display("CASE_DEHAZE_TRANSITION %s", scenario);
        require_quiet();
        owner = key;
        i_enable = enabled;
        i_history_reset = reset_history;
        expect_history = history;
        finite_stalls = stall_output;
        pattern_salt++;
        groups_in = 0;
        groups_out = 0;
        stall_cycles = 0;
        frame_open = 1;
    endtask

    task automatic offer_group(input integer beat);
        s_valid = 1;
        s_sof = beat == 0;
        s_eol = beat % GROUPS_PER_LINE == GROUPS_PER_LINE - 1;
        {s_luma, s_rgb} = raster_group(beat, pattern_salt);
    endtask

    task automatic send_groups(input integer count, input integer source_beat);
        logic accepted;
        integer elapsed;
        for (integer beat = 0; beat < count; beat++) begin
            offer_group(beat);
            terminal_on_accept = beat == source_beat;
            terminal_owner = owner;
            terminal_ok = 1;
            elapsed = 0;
            do begin
                @(posedge clk);
                accepted = s_ready === 1'b1;
                @(negedge clk);
                elapsed++;
                if (!accepted && elapsed == TAIL_LIMIT)
                    fail("input group remained stalled");
            end while (!accepted);
            if (o_history_used !== expect_history)
                fail($sformatf("frame history flag expected %b, got %b", expect_history, o_history_used));
            i_history_reset = 0;
        end
        s_valid = 0;
        terminal_on_accept = 0;
        finite_stalls = 0;
    endtask

    task automatic finish_pixels;
        integer elapsed;
        elapsed = 0;
        while (groups_out != GROUPS_PER_FRAME || o_pixel_pending !== 1'b0) begin
            if (elapsed == TAIL_LIMIT)
                fail("full input raster did not drain to a complete output raster");
            @(negedge clk);
            elapsed++;
        end
        if (groups_in != GROUPS_PER_FRAME)
            fail("incorrect number of accepted inputs");
    endtask

    task automatic pulse_terminal(input key_t key, input logic ok);
        logic input_accepted;
        terminal_owner = key;
        terminal_ok = ok;
        terminal_standalone = 1;
        @(posedge clk);
        input_accepted = s_valid && s_ready;
        @(negedge clk);
        terminal_standalone = 0;
        if (input_accepted)
            s_valid = 0;
    endtask

    task automatic reject_terminal(input key_t key, input string field_name);
        pulse_terminal(key, 1);
        repeat (TAIL_LIMIT) begin
            @(negedge clk);
            if ({o_pending, o_pixel_pending, m_valid} !== 3'b100)
                fail($sformatf("terminal with mismatched %s released the history obligation", field_name));
        end
    endtask

    task automatic finish_frame(input logic require_stalls);
        require_quiet();
        if (require_stalls && stall_cycles == 0)
            fail("the sink never held an output offer under backpressure");
        $display("DONE_DEHAZE_TRANSITION %s in=%0d out=%0d stalls=%0d history=%b",
                 scenario, groups_in, groups_out, stall_cycles, expect_history);
        frame_open = 0;
        full_frames++;
    endtask

    task automatic hold_partial_output;
        logic input_accepted, output_held;
        send_groups(GROUPS_PER_LINE + GROUPS_PER_LINE / 2, -1);
        sink_accepting = 0;
        offer_group(groups_in);
        for (integer elapsed = 0; elapsed < TAIL_LIMIT; elapsed++) begin
            @(posedge clk);
            input_accepted = s_valid && s_ready;
            output_held = m_valid && !m_ready;
            @(negedge clk);
            if (input_accepted)
                s_valid = 0;
            if (output_held)
                return;
        end
        fail("unable to hold an output offer on the partial raster");
    endtask

    task automatic record_abort;
        $display("ABORT_DEHAZE_TRANSITION %s in=%0d out=%0d stalls=%0d",
                 scenario, groups_in, groups_out, stall_cycles);
        frame_open = 0;
        aborted_frames++;
    endtask

    initial begin : exercise_public_contract
        key_t wrong_key;
        repeat (4) @(negedge clk);
        rst_n = 1;

        begin_frame("disabled identity", make_key(0, 23, 40, 100), 0, 0, 0, 1);
        send_groups(GROUPS_PER_FRAME, -1);
        finish_pixels();
        finish_frame(1);

        begin_frame("first enabled eye zero with SOURCE at SOF", make_key(0, 23, 40, 101), 1, 1, 0, 0);
        send_groups(GROUPS_PER_FRAME, 0);
        finish_pixels();
        finish_frame(0);

        begin_frame("first enabled eye one with late SOURCE", make_key(1, 23, 40, 102), 1, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, -1);
        finish_pixels();
        if (o_pending !== 1'b1)
            fail("history obligation disappeared before SOURCE");
        wrong_key = owner;
        wrong_key.camera = 0;
        reject_terminal(wrong_key, "camera");
        wrong_key = owner;
        wrong_key.session = 24;
        reject_terminal(wrong_key, "session");
        wrong_key = owner;
        wrong_key.epoch = 41;
        reject_terminal(wrong_key, "epoch");
        wrong_key = owner;
        wrong_key.sequence_id = 103;
        reject_terminal(wrong_key, "sequence");
        pulse_terminal(owner, 1);
        finish_frame(0);

        begin_frame("disabled again with existing history", make_key(0, 23, 40, 103), 0, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, -1);
        finish_pixels();
        finish_frame(0);

        begin_frame("re-enabled eye zero with distance four", make_key(0, 23, 40, 105), 1, 0, 1, 1);
        send_groups(GROUPS_PER_FRAME, GROUPS_PER_FRAME / 2);
        finish_pixels();
        finish_frame(1);

        begin_frame("eye one with new epoch", make_key(1, 23, 41, 103), 1, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, 0);
        finish_pixels();
        finish_frame(0);

        begin_frame("eye one with new session", make_key(1, 24, 41, 104), 1, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, 0);
        finish_pixels();
        finish_frame(0);

        begin_frame("warm history reset and negative SOURCE with clear", make_key(1, 24, 41, 105), 1, 1, 0, 0);
        hold_partial_output();
        pulse_terminal(owner, 0);
        clear = 1;
        s_valid = 0;
        @(negedge clk);
        clear = 0;
        record_abort();
        require_quiet();
        sink_accepting = 1;

        begin_frame("complete first owner after clear", make_key(1, 24, 41, 106), 1, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, 0);
        finish_pixels();
        finish_frame(0);

        begin_frame("asynchronous reset on stopped clock", make_key(1, 24, 41, 107), 1, 0, 1, 0);
        hold_partial_output();
        clock_running = 0;
        #2;
        if (clk !== 1'b0 || m_valid !== 1'b1)
            fail("reset stimulus did not stop a clock with an output offer held");
        rst_n = 0;
        #2;
        if (clk !== 1'b0 || m_valid !== 1'b0)
            fail("reset did not clear held output without a clock edge");
        s_valid = 0;
        #28;
        if (clk !== 1'b0 || m_valid !== 1'b0)
            fail("output returned while clock and reset remained stopped");
        record_abort();
        clock_running = 1;
        repeat (2) @(negedge clk);
        rst_n = 1;
        sink_accepting = 1;

        begin_frame("complete first owner after reset", make_key(1, 24, 41, 108), 1, 0, 0, 0);
        send_groups(GROUPS_PER_FRAME, 0);
        finish_pixels();
        finish_frame(0);

        $display("PASS_DEHAZE_TRANSITION full_frames=%0d aborted_frames=%0d groups_per_frame=%0d",
                 full_frames, aborted_frames, GROUPS_PER_FRAME);
        $finish;
    end

    initial begin
        #2_000_000;
        fail("2 ms simulation watchdog");
    end
endmodule
