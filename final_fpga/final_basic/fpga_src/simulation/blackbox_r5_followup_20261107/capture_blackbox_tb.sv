`timescale 1ns/1ps

module capture_blackbox_tb;
    localparam integer EYES = 3;
    localparam integer LEFT = 0, RIGHT = 1, TINY = 2;
    localparam logic [1:0] FS = 0, FE = 1, ABORT = 2;

    logic clk = 0, running = 1, rst_n = 0;
    always #5 if (running) clk = ~clk;

    logic enable [EYES], time_valid [EYES];
    logic [31:0] session_id [EYES], epoch [EYES];
    logic [63:0] time_ns [EYES];
    logic [7:0] divisor [EYES];
    logic [39:0] raw_data [EYES];
    logic raw_valid [EYES], raw_accept [EYES], raw_sof [EYES], raw_eol [EYES];
    logic raw_abort [EYES], raw_identity [EYES];
    logic [31:0] raw_seq [EYES];
    logic event_valid [EYES], event_ok [EYES], event_identity [EYES];
    logic [1:0] event_kind [EYES];
    logic [3:0] event_error [EYES];
    logic [31:0] event_seq [EYES];
    logic receive_fault [EYES], quarantine [EYES];
    logic source_ready [EYES];

    wire event_ready [EYES];
    wire [39:0] cap_data [EYES];
    wire cap_valid [EYES], cap_accept [EYES], cap_sof [EYES], cap_eol [EYES];
    wire cap_abort [EYES], geometry_done [EYES];
    wire [31:0] cap_session [EYES], cap_epoch [EYES], cap_seq [EYES];
    wire [196:0] cap_metadata [EYES];
    wire source_valid [EYES], source_camera [EYES], source_ok [EYES];
    wire [31:0] source_session [EYES], source_epoch [EYES], source_seq [EYES];
    wire [7:0] source_error [EYES];
    wire idle [EYES], fault [EYES];

    for (genvar eye = 0; eye < EYES; eye++) begin : endpoints
        stereo_capture_source4 #(
            .CAMERA_ID(eye == RIGHT ? 1 : 0), .WIDTH(8), .HEIGHT(2),
            .TAG_WIDTH(eye == TINY ? 2 : 32),
            .SEPARATE_DATA_RESET(eye == TINY ? 1 : 0), .FS_CADENCE_ENABLE(1)
        ) dut (
            .clk(clk), .rst_n(rst_n), .i_data_reset_n(rst_n),
            .i_enable(enable[eye]), .i_session(session_id[eye]), .i_epoch(epoch[eye]),
            .i_time_ns(time_ns[eye]), .i_time_valid(time_valid[eye]),
            .i_frame_divisor(divisor[eye]), .i_data(raw_data[eye]),
            .i_valid(raw_valid[eye]), .i_accept(raw_accept[eye]),
            .i_sof(raw_sof[eye]), .i_eol(raw_eol[eye]), .i_abort(raw_abort[eye]),
            .i_sequence(raw_seq[eye]), .i_identity_valid(raw_identity[eye]),
            .i_event_valid(event_valid[eye]), .o_event_ready(event_ready[eye]),
            .i_event_kind(event_kind[eye]), .i_event_ok(event_ok[eye]),
            .i_event_error(event_error[eye]), .i_event_sequence(event_seq[eye]),
            .i_event_identity_valid(event_identity[eye]),
            .i_receive_fault(receive_fault[eye]), .i_identity_quarantine(quarantine[eye]),
            .o_capture_data(cap_data[eye]), .o_capture_valid(cap_valid[eye]),
            .o_capture_accept(cap_accept[eye]), .o_capture_sof(cap_sof[eye]),
            .o_capture_eol(cap_eol[eye]), .o_capture_abort(cap_abort[eye]),
            .o_capture_geometry_done(geometry_done[eye]),
            .o_capture_session(cap_session[eye]), .o_capture_epoch(cap_epoch[eye]),
            .o_capture_sequence(cap_seq[eye]), .o_capture_metadata(cap_metadata[eye]),
            .o_raw_source_valid(source_valid[eye]), .i_raw_source_ready(source_ready[eye]),
            .o_raw_source_session(source_session[eye]), .o_raw_source_epoch(source_epoch[eye]),
            .o_raw_source_sequence(source_seq[eye]), .o_raw_source_camera(source_camera[eye]),
            .o_raw_source_ok(source_ok[eye]), .o_raw_source_error(source_error[eye]),
            .o_idle(idle[eye]), .o_fault(fault[eye])
        );
    end

    string test_case;
    string phase [EYES];
    integer raw_prepared [EYES], raw_required [EYES], raw_seen [EYES];
    logic [41:0] raw_expected [EYES][4];
    logic [31:0] frame_session [EYES], frame_epoch [EYES], frame_seq [EYES];
    logic [63:0] frame_time [EYES];
    bit want_geometry [EYES], saw_geometry [EYES];

    bit want_source [EYES], want_good [EYES], good_fe_seen [EYES];
    bit saw_source [EYES], consumed_source [EYES], held_source [EYES];
    logic [31:0] expected_session [EYES], expected_epoch [EYES], expected_seq [EYES];
    logic [105:0] held_payload [EYES];
    integer source_count [EYES], good_count [EYES], bad_count [EYES];
    integer fs_count [EYES], raw_count [EYES];

    function automatic logic [105:0] source_payload(input int eye);
        return {source_session[eye], source_epoch[eye], source_seq[eye],
                source_camera[eye], source_ok[eye], source_error[eye]};
    endfunction

    always @(posedge clk) begin : scoreboard
        for (int eye = 0; eye < EYES; eye++) begin
            if (rst_n) begin
                if (event_ready[eye] !== 1'b1)
                    $fatal(1, "eye=%0d %s event_ready blocked out of reset", eye, phase[eye]);
                if ($isunknown({cap_valid[eye], cap_accept[eye], geometry_done[eye],
                                source_valid[eye]}))
                    $fatal(1, "eye=%0d %s unknown output qualifier", eye, phase[eye]);

                if (event_valid[eye] && event_ready[eye]) begin
                    if (event_kind[eye] == FS && event_identity[eye] &&
                        event_ok[eye] && event_error[eye] == 0)
                        fs_count[eye]++;
                    if (want_source[eye] && event_kind[eye] == FE &&
                        event_seq[eye] == expected_seq[eye] && event_identity[eye] &&
                        event_ok[eye] && event_error[eye] == 0)
                        good_fe_seen[eye] = 1;
                end

                if (cap_valid[eye] && cap_accept[eye]) begin
                    if (raw_seen[eye] >= raw_prepared[eye])
                        $fatal(1, "eye=%0d %s unexpected RAW transfer seq=%0d group=%0d",
                               eye, phase[eye], cap_seq[eye], raw_seen[eye]);
                    if ({cap_sof[eye], cap_eol[eye], cap_data[eye]} !==
                        raw_expected[eye][raw_seen[eye]] ||
                        {cap_session[eye], cap_epoch[eye], cap_seq[eye]} !==
                        {frame_session[eye], frame_epoch[eye], frame_seq[eye]} ||
                        cap_metadata[eye] !== {4'b0000, 1'b1, 128'b0, frame_time[eye]})
                        $fatal(1, "eye=%0d %s RAW identity/data/metadata mismatch seq=%0d group=%0d",
                               eye, phase[eye], cap_seq[eye], raw_seen[eye]);
                    raw_seen[eye]++;
                    raw_count[eye]++;
                end

                if (geometry_done[eye]) begin
                    if (!want_geometry[eye] || saw_geometry[eye] || raw_seen[eye] != 4)
                        $fatal(1, "eye=%0d %s unexpected geometry pulse after %0d groups",
                               eye, phase[eye], raw_seen[eye]);
                    saw_geometry[eye] = 1;
                end

                if (held_source[eye] &&
                    (source_valid[eye] !== 1'b1 || source_payload(eye) !== held_payload[eye]))
                    $fatal(1, "eye=%0d %s held SOURCE changed seq=%0d",
                           eye, phase[eye], source_seq[eye]);
                if (source_valid[eye]) begin
                    if (!want_source[eye])
                        $fatal(1, "eye=%0d %s unexpected SOURCE seq=%0d ok=%b error=%h",
                               eye, phase[eye], source_seq[eye], source_ok[eye], source_error[eye]);
                    if ({source_session[eye], source_epoch[eye], source_seq[eye]} !==
                        {expected_session[eye], expected_epoch[eye], expected_seq[eye]} ||
                        source_camera[eye] !== (eye == RIGHT))
                        $fatal(1, "eye=%0d %s SOURCE identity mismatch expected seq=%0d actual=%0d",
                               eye, phase[eye], expected_seq[eye], source_seq[eye]);
                    if (source_ok[eye] !== want_good[eye] || $isunknown(source_error[eye]) ||
                        (source_error[eye] == 0) != want_good[eye])
                        $fatal(1, "eye=%0d %s SOURCE classification seq=%0d expected ok=%b actual ok=%b error=%h",
                               eye, phase[eye], source_seq[eye], want_good[eye],
                               source_ok[eye], source_error[eye]);
                    if (!saw_source[eye] && want_good[eye] &&
                        (!good_fe_seen[eye] || !saw_geometry[eye] || raw_valid[eye] || raw_abort[eye]))
                        $fatal(1, "eye=%0d %s good SOURCE before FE/geometry/quiet seq=%0d",
                               eye, phase[eye], source_seq[eye]);
                    saw_source[eye] = 1;
                    if (source_ready[eye]) begin
                        $display("SOURCE eye=%0d seq=%0d ok=%b error=%h %s", eye,
                                 source_seq[eye], source_ok[eye], source_error[eye], phase[eye]);
                        want_source[eye] = 0;
                        consumed_source[eye] = 1;
                        source_count[eye]++;
                        if (source_ok[eye]) good_count[eye]++;
                        else bad_count[eye]++;
                    end
                end
                held_source[eye] = source_valid[eye] && !source_ready[eye];
                if (held_source[eye]) held_payload[eye] = source_payload(eye);
            end
        end
    end

    task automatic ticks(input int cycles);
        repeat (cycles) @(negedge clk);
    endtask

    task automatic drive_defaults(input int eye, input int cohort);
        enable[eye] = 1;
        session_id[eye] = 32'h5100_0000 + 16 * cohort + eye;
        epoch[eye] = 32'h8200_0000 + 16 * cohort + eye;
        time_ns[eye] = 64'hf123_0000_0000_0000 + 64'(cohort * 100 + eye);
        time_valid[eye] = 1;
        divisor[eye] = 1;
        raw_data[eye] = 0;
        raw_valid[eye] = 0;
        raw_accept[eye] = 0;
        raw_sof[eye] = 0;
        raw_eol[eye] = 0;
        raw_abort[eye] = 0;
        raw_identity[eye] = 1;
        raw_seq[eye] = 0;
        event_valid[eye] = 0;
        event_kind[eye] = FS;
        event_ok[eye] = 1;
        event_error[eye] = 0;
        event_seq[eye] = 0;
        event_identity[eye] = 1;
        receive_fault[eye] = 0;
        quarantine[eye] = 0;
        source_ready[eye] = 1;
    endtask

    task automatic clear_scoreboard(input int eye);
        phase[eye] = "after-cohort-reset";
        raw_prepared[eye] = 0;
        raw_required[eye] = 0;
        raw_seen[eye] = 0;
        want_geometry[eye] = 0;
        saw_geometry[eye] = 0;
        want_source[eye] = 0;
        want_good[eye] = 0;
        good_fe_seen[eye] = 0;
        saw_source[eye] = 0;
        consumed_source[eye] = 0;
        held_source[eye] = 0;
        source_count[eye] = 0;
        good_count[eye] = 0;
        bad_count[eye] = 0;
        fs_count[eye] = 0;
        raw_count[eye] = 0;
    endtask

    task automatic reset_cohort(input int cohort, input bit stop_clock = 0);
        if (stop_clock) begin
            running = 0;
            #12;
            if (clk !== 1'b0) $fatal(1, "clock did not stop low");
        end
        rst_n = 0;
        for (int eye = 0; eye < EYES; eye++) begin
            drive_defaults(eye, cohort);
            clear_scoreboard(eye);
        end
        #1;
        for (int eye = 0; eye < EYES; eye++)
            if (event_ready[eye] !== 1'b0)
                $fatal(1, "eye=%0d event_ready active during reset", eye);
        if (stop_clock) begin
            #17;
            if (clk !== 1'b0) $fatal(1, "clock advanced during reset");
            running = 1;
        end
        ticks(3);
        rst_n = 1;
        ticks(3);
        for (int eye = 0; eye < EYES; eye++)
            if (idle[eye] !== 1'b1 || fault[eye] !== 1'b0)
                $fatal(1, "eye=%0d failed to start a clean cohort", eye);
    endtask

    task automatic start_frame(input int eye, input logic [31:0] seq, input string label);
        phase[eye] = label;
        raw_prepared[eye] = 0;
        raw_required[eye] = 0;
        raw_seen[eye] = 0;
        want_geometry[eye] = 0;
        saw_geometry[eye] = 0;
        time_ns[eye] += 64'd137 * seq + 64'd19;
        frame_session[eye] = session_id[eye];
        frame_epoch[eye] = epoch[eye];
        frame_seq[eye] = seq;
        frame_time[eye] = time_ns[eye];
    endtask

    task automatic expect_source(input int eye, input bit good);
        if (want_source[eye]) $fatal(1, "test setup overwrote pending SOURCE");
        want_source[eye] = 1;
        want_good[eye] = good;
        good_fe_seen[eye] = 0;
        saw_source[eye] = 0;
        consumed_source[eye] = 0;
        expected_session[eye] = frame_session[eye];
        expected_epoch[eye] = frame_epoch[eye];
        expected_seq[eye] = frame_seq[eye];
    endtask

    task automatic drive_event(input int eye, input logic [1:0] kind,
                               input logic [31:0] seq, input bit identity = 1,
                               input bit ok = 1, input logic [3:0] error = 0);
        event_valid[eye] = 1;
        event_kind[eye] = kind;
        event_seq[eye] = seq;
        event_identity[eye] = identity;
        event_ok[eye] = ok;
        event_error[eye] = error;
        @(posedge clk);
        if (event_ready[eye] !== 1'b1)
            $fatal(1, "eye=%0d %s event not consumed kind=%0d seq=%0d", eye, phase[eye], kind, seq);
        @(negedge clk);
        event_valid[eye] = 0;
    endtask

    function automatic logic [39:0] group_data(input int eye, input logic [31:0] seq,
                                                input int group_index);
        logic [9:0] base;
        base = 10'(seq * 17 + group_index * 67 + eye * 149);
        return {base + 10'd271, base + 10'd193, base + 10'd61, base};
    endfunction

    task automatic drive_group(input int eye, input logic [31:0] seq,
                               input int group_index, input bit sof, input bit eol,
                               input bit identity, input bit accepted,
                               input bit compared, input bit required);
        raw_data[eye] = group_data(eye, seq, group_index);
        if (compared) begin
            if (raw_prepared[eye] == 4) $fatal(1, "test setup exceeded RAW scoreboard size");
            raw_expected[eye][raw_prepared[eye]] = {sof, eol, raw_data[eye]};
            raw_prepared[eye]++;
            if (required) raw_required[eye]++;
        end
        raw_seq[eye] = seq;
        raw_identity[eye] = identity;
        raw_valid[eye] = 1;
        raw_accept[eye] = accepted;
        raw_sof[eye] = sof;
        raw_eol[eye] = eol;
        @(negedge clk);
        raw_valid[eye] = 0;
        raw_accept[eye] = 0;
        raw_sof[eye] = 0;
        raw_eol[eye] = 0;
    endtask

    task automatic image_group(input int eye, input logic [31:0] seq,
                               input int group_index, input bit compare_transfer);
        drive_group(eye, seq, group_index, group_index == 0, group_index[0],
                    1, 1, compare_transfer, compare_transfer);
    endtask

    task automatic full_image(input int eye, input logic [31:0] seq, input bit admitted);
        for (int group_index = 0; group_index < 4; group_index++) begin
            if (group_index == 3 && admitted) want_geometry[eye] = 1;
            image_group(eye, seq, group_index, admitted);
        end
    endtask

    task automatic check_raw(input int eye);
        if (raw_seen[eye] < raw_required[eye] || raw_seen[eye] > raw_prepared[eye] ||
            saw_geometry[eye] != want_geometry[eye])
            $fatal(1, "eye=%0d %s seq=%0d saw %0d groups expected %0d..%0d geometry=%b expected=%b",
                   eye, phase[eye], frame_seq[eye], raw_seen[eye], raw_required[eye],
                   raw_prepared[eye], saw_geometry[eye], want_geometry[eye]);
    endtask

    task automatic wait_result(input int eye, input bit consumed);
        int cycles;
        cycles = 0;
        while ((consumed ? !consumed_source[eye] : !saw_source[eye]) && cycles < 32) begin
            ticks(1);
            cycles++;
        end
        if (consumed ? !consumed_source[eye] : !saw_source[eye])
            $fatal(1, "eye=%0d %s SOURCE timeout expected seq=%0d ok=%b",
                   eye, phase[eye], expected_seq[eye], want_good[eye]);
    endtask

    task automatic complete_frame(input int eye, input logic [31:0] seq,
                                  input bit admitted, input string label,
                                  input int delay_cycles = 0);
        ticks(delay_cycles);
        start_frame(eye, seq, label);
        if (admitted) expect_source(eye, 1);
        drive_event(eye, FS, seq);
        ticks(2);
        full_image(eye, seq, admitted);
        drive_event(eye, FE, seq);
        if (admitted) wait_result(eye, 1);
        ticks(4);
        check_raw(eye);
    endtask

    task automatic cadence_case;
        for (int n = 1; n <= 3; n++) begin
            reset_cohort(n);
            divisor[LEFT] = 8'(n);
            divisor[RIGHT] = 8'(n);
            for (int index = 0; index <= 3*n; index++) begin
                fork
                    complete_frame(LEFT, 100 + index, index % n == 0, "cadence");
                    complete_frame(RIGHT, 100 + index, index % n == 0, "cadence", 2 * (index % 2));
                join
            end
            for (int eye = LEFT; eye <= RIGHT; eye++) begin
                if (fs_count[eye] != 3*n+1 || source_count[eye] != 4 ||
                    raw_count[eye] != 16 || idle[eye] !== 1'b1)
                    $fatal(1, "cadence eye=%0d DIV%0d FS=%0d SOURCE=%0d RAW=%0d idle=%b",
                           eye, n, fs_count[eye], source_count[eye], raw_count[eye], idle[eye]);
                $display("CHECK cadence eye=%0d DIV%0d physical_fs=%0d SOURCE=%0d RAW=%0d",
                         eye, n, fs_count[eye], source_count[eye], raw_count[eye]);
            end
        end
    endtask

    task automatic stall_eye(input int eye, input int n);
        divisor[eye] = 8'(n);
        source_ready[eye] = 0;
        start_frame(eye, 200, "held-owner");
        expect_source(eye, 1);
        drive_event(eye, FS, 200);
        enable[eye] = 0;
        ticks(2);
        full_image(eye, 200, 1);
        drive_event(eye, FE, 200);
        wait_result(eye, 0);
        check_raw(eye);
        if (idle[eye] !== 1'b0) $fatal(1, "eye=%0d idle with stalled SOURCE", eye);
        enable[eye] = 1;
        for (int index = 1; index <= 2*n; index++)
            complete_frame(eye, 200 + index, 0, "FS-during-stall");
        source_ready[eye] = 1;
        wait_result(eye, 1);
        ticks(4);
        for (int index = 2*n+1; index <= 5*n; index++) begin
            enable[eye] = index != 4*n;
            complete_frame(eye, 200 + index, index % n == 0 && index != 4*n, "phase-after-stall");
        end
        if (source_count[eye] != 3 || fs_count[eye] != 5*n+1 || raw_count[eye] != 12)
            $fatal(1, "eye=%0d DIV%0d stall summary mismatch", eye, n);
        $display("CHECK held SOURCE eye=%0d DIV%0d crossed %0d real FS", eye, n, 2*n);
    endtask

    task automatic stall_case;
        reset_cohort(4);
        fork
            stall_eye(LEFT, 2);
            stall_eye(RIGHT, 3);
        join
    endtask

    task automatic late_good(input int eye, input logic [31:0] seq);
        start_frame(eye, seq, "first-FS-freeze-late-FE");
        expect_source(eye, 1);
        drive_event(eye, FS, seq);
        session_id[eye] ^= 32'h4000_1000;
        epoch[eye] ^= 32'h0800_0000;
        time_ns[eye] ^= 64'hf999_4321_eeee_0010;
        time_valid[eye] = 0;
        enable[eye] = 0;
        ticks(2);
        drive_group(eye, seq, 0, 1, 0, 1, 0, 0, 0);
        full_image(eye, seq, 1);
        ticks(8);
        check_raw(eye);
        if (saw_source[eye]) $fatal(1, "eye=%0d SOURCE appeared before actual FE", eye);
        drive_event(eye, FE, seq);
        wait_result(eye, 1);
        ticks(4);
        session_id[eye] = frame_session[eye];
        epoch[eye] = frame_epoch[eye];
        time_ns[eye] = frame_time[eye];
        time_valid[eye] = 1;
        enable[eye] = 1;
    endtask

    task automatic invalid_terminal(input int eye, input logic [31:0] seq, input bit abort_event);
        start_frame(eye, seq, abort_event ? "crop-external-ABORT" : "crop-external-bad-CRC");
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        full_image(eye, seq, 1);
        ticks(7);
        check_raw(eye);
        if (saw_source[eye]) $fatal(1, "eye=%0d terminal outcome before physical terminal", eye);
        drive_event(eye, abort_event ? ABORT : FE, seq, 1, 0, abort_event ? 4'd6 : 4'd2);
        wait_result(eye, 1);
        ticks(4);
    endtask

    task automatic invalid_raw(input int eye, input logic [31:0] seq, input bit wrong_seq);
        start_frame(eye, seq, wrong_seq ? "RAW-wrong-sequence" : "RAW-missing-identity");
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        image_group(eye, seq, 0, 1);
        drive_group(eye, wrong_seq ? seq-1 : seq, 1, 0, 1, wrong_seq, 1, 0, 0);
        drive_event(eye, FE, seq);
        wait_result(eye, 1);
        ticks(4);
        check_raw(eye);
    endtask

    task automatic rejected_fs(input int eye, input logic [31:0] seq, input bit identity);
        start_frame(eye, seq, identity ? "invalid-FS-status" : "FS-missing-identity");
        drive_event(eye, FS, seq, identity, !identity, identity ? 4'd2 : 4'd0);
        ticks(2);
        full_image(eye, seq, 0);
        drive_event(eye, FE, seq);
        ticks(5);
        check_raw(eye);
    endtask

    task automatic terminals_case;
        reset_cohort(5);
        fork
            late_good(LEFT, 300);
            begin ticks(3); late_good(RIGHT, 300); end
        join
        fork
            invalid_terminal(LEFT, 301, 0);
            invalid_terminal(RIGHT, 301, 1);
        join
        fork
            complete_frame(LEFT, 302, 1, "healthy-after-CRC");
            complete_frame(RIGHT, 302, 1, "healthy-after-ABORT");
        join
        fork
            invalid_raw(LEFT, 303, 1);
            invalid_raw(RIGHT, 303, 0);
        join
        fork
            complete_frame(LEFT, 304, 1, "healthy-after-wrong-RAW");
            complete_frame(RIGHT, 304, 1, "healthy-after-missing-RAW-identity");
        join
        fork
            rejected_fs(LEFT, 305, 0);
            rejected_fs(RIGHT, 305, 1);
        join
        fork
            complete_frame(LEFT, 306, 1, "healthy-after-untrusted-FS");
            complete_frame(RIGHT, 306, 1, "healthy-after-untrusted-FS");
        join
        for (int eye = LEFT; eye <= RIGHT; eye++)
            if (good_count[eye] != 4 || bad_count[eye] != 2)
                $fatal(1, "eye=%0d terminal recovery count mismatch", eye);
    endtask

    task automatic malformed_eol(input int eye, input logic [31:0] seq, input int bad_group);
        start_frame(eye, seq, $sformatf("wrong-EOL-group-%0d", bad_group));
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        for (int group_index = 0; group_index < bad_group; group_index++)
            image_group(eye, seq, group_index, 1);
        // The public contract permits masking the offending matching beat.
        drive_group(eye, seq, bad_group, bad_group == 0, !bad_group[0], 1, 1, 1, 0);
        drive_event(eye, FE, seq);
        wait_result(eye, 1);
        ticks(4);
        check_raw(eye);
    endtask

    task automatic missing_terminal(input int eye, input logic [31:0] seq);
        start_frame(eye, seq, "new-FS-with-old-terminal-missing");
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        full_image(eye, seq, 1);
        ticks(5);
        check_raw(eye);
        if (saw_source[eye]) $fatal(1, "eye=%0d negative before continuity break", eye);
        complete_frame(eye, seq+1, 0, "new-FS-breaks-continuity");
        wait_result(eye, 1);
        ticks(4);
    endtask

    task automatic short_crop(input int eye, input logic [31:0] seq);
        start_frame(eye, seq, "short-crop-abort");
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        image_group(eye, seq, 0, 1);
        image_group(eye, seq, 1, 1);
        raw_abort[eye] = 1;
        ticks(1);
        raw_abort[eye] = 0;
        drive_event(eye, FE, seq);
        wait_result(eye, 1);
        ticks(4);
        check_raw(eye);
    endtask

    task automatic geometry_case;
        reset_cohort(6);
        start_frame(LEFT, 400, "SOF-without-physical-FS");
        full_image(LEFT, 400, 0);
        ticks(6);
        check_raw(LEFT);
        if (idle[LEFT] !== 1'b1) $fatal(1, "SOF-only traffic created an owner");
        complete_frame(LEFT, 401, 1, "first-real-FS-after-SOF-only");
        for (int bad_group = 0; bad_group < 4; bad_group++) begin
            malformed_eol(LEFT, 402 + 2*bad_group, bad_group);
            complete_frame(LEFT, 403 + 2*bad_group, 1, "healthy-after-EOL-error");
        end
        short_crop(LEFT, 410);
        complete_frame(LEFT, 411, 1, "healthy-after-short-crop");
        missing_terminal(LEFT, 412);
        complete_frame(LEFT, 414, 1, "healthy-after-missing-terminal");
        if (good_count[LEFT] != 7 || bad_count[LEFT] != 6)
            $fatal(1, "geometry result counts mismatch");
    endtask

    task automatic fault_eye(input int eye, input logic [31:0] seq, input bit isolated);
        start_frame(eye, seq, isolated ? "quarantine-one-eye" : "receive-fault-one-eye");
        expect_source(eye, 0);
        drive_event(eye, FS, seq);
        ticks(2);
        image_group(eye, seq, 0, 1);
        if (isolated) quarantine[eye] = 1;
        else receive_fault[eye] = 1;
        ticks(1);
        if (isolated && (fault[eye] !== 1'b1 || fault[1-eye] !== 1'b0))
            $fatal(1, "quarantine fault did not remain local");
        if (!isolated) receive_fault[eye] = 0;
        wait_result(eye, 1);
        ticks(4);
        check_raw(eye);
        if (isolated) begin
            complete_frame(eye, seq+1, 0, "FS-during-quarantine");
            quarantine[eye] = 0;
        end
    endtask

    task automatic isolation_case;
        reset_cohort(7);
        fork
            fault_eye(LEFT, 500, 0);
            complete_frame(RIGHT, 500, 1, "healthy-right-during-left-fault");
        join
        fork
            complete_frame(LEFT, 501, 1, "left-recovered-during-right-quarantine");
            fault_eye(RIGHT, 501, 1);
        join
        fork
            complete_frame(LEFT, 503, 1, "left-after-right-quarantine");
            complete_frame(RIGHT, 503, 1, "right-recovered-after-quarantine");
        join
        for (int eye = LEFT; eye <= RIGHT; eye++)
            if (good_count[eye] != 2 || bad_count[eye] != 1)
                $fatal(1, "eye=%0d isolation result counts mismatch", eye);
    endtask

    task automatic reset_case;
        reset_cohort(8);
        start_frame(LEFT, 600, "reset-with-event-owner");
        drive_event(LEFT, FS, 600);
        start_frame(RIGHT, 600, "reset-mid-RAW");
        drive_event(RIGHT, FS, 600);
        ticks(2);
        image_group(RIGHT, 600, 0, 1);
        check_raw(RIGHT);
        reset_cohort(9);
        fork
            complete_frame(LEFT, 100, 1, "left-first-after-cohort-reset");
            complete_frame(RIGHT, 100, 1, "right-first-after-cohort-reset");
        join

        source_ready[LEFT] = 0;
        start_frame(LEFT, 101, "reset-held-SOURCE-clock-stopped");
        expect_source(LEFT, 1);
        drive_event(LEFT, FS, 101);
        ticks(2);
        full_image(LEFT, 101, 1);
        drive_event(LEFT, FE, 101);
        wait_result(LEFT, 0);
        check_raw(LEFT);
        start_frame(RIGHT, 101, "reset-with-FS-pending-on-stopped-clock");
        event_valid[RIGHT] = 1;
        event_kind[RIGHT] = FS;
        event_seq[RIGHT] = 101;
        reset_cohort(10, 1);
        fork
            complete_frame(LEFT, 100, 1, "left-first-after-stopped-reset");
            complete_frame(RIGHT, 100, 1, "right-first-after-stopped-reset");
        join
    endtask

    task automatic saturation_case;
        reset_cohort(11);
        for (int index = 0; index < 3; index++) begin
            complete_frame(TINY, 700 + index, 1, "two-bit-tag-legal");
            if (fault[TINY] !== (index == 2))
                $fatal(1, "TAG_WIDTH=2 fault did not indicate exact last legal token");
        end
        complete_frame(TINY, 703, 0, "two-bit-tag-saturated");
        complete_frame(TINY, 704, 0, "two-bit-tag-no-reuse");
        if (fault[TINY] !== 1'b1 || source_count[TINY] != 3)
            $fatal(1, "TAG_WIDTH=2 failed to retain saturation");
        reset_cohort(12);
        complete_frame(TINY, 700, 1, "two-bit-tag-new-cohort");
    endtask

    initial begin
        if (!$value$plusargs("case=%s", test_case)) $fatal(1, "missing +case");
        ticks(1);
        case (test_case)
            "cadence": cadence_case();
            "stall": stall_case();
            "terminals": terminals_case();
            "geometry": geometry_case();
            "isolation": isolation_case();
            "reset": reset_case();
            "saturation": saturation_case();
            default: $fatal(1, "unknown case %s", test_case);
        endcase
        ticks(6);
        $display("CAPTURE_BLACKBOX_PASS %s t=%0t", test_case, $time);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "CAPTURE_BLACKBOX_WATCHDOG case=%s", test_case);
    end
endmodule
