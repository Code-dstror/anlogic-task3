`timescale 1ns/1ps

module raw_ingress_case #(parameter integer PROFILE = 0)(output bit done = 0);
    localparam integer ROLE = PROFILE == 1 || PROFILE == 2 ? PROFILE : 0;
    localparam integer WIDTH = PROFILE == 3 ? 40 : 32;
    localparam integer HEIGHT = 2;
    localparam integer UHD_WIDTH = PROFILE == 0 ? 64 : 0;
    localparam integer UHD_HEIGHT = PROFILE == 0 ? 2 : 0;
    localparam bit COMPACT = ROLE == 0;

    bit i_clk = 0;
    always #5 i_clk = !i_clk;

    bit i_rst_n = 0;
    bit i_enable, i_valid, i_accept, i_sof, i_eol, i_abort, i_camera;
    bit [39:0] i_data;
    bit [31:0] i_epoch, i_external_sequence, i_session_id;
    bit i_sdr_profile, i_bayer_valid, i_time_valid;
    bit [1:0] i_bayer_pattern;
    bit i_metadata_valid;
    bit [63:0] i_timestamp;
    bit [31:0] i_actual_exposure, i_gain, i_calibration_id;
    bit i_source_kind;
    bit [1:0] i_exposure_role;
    bit [31:0] i_exposure_group;
    bit i_source_qualified, i_source_valid;
    bit [31:0] i_source_session, i_source_epoch, i_source_sequence;
    bit i_source_camera, i_source_ok;
    bit [7:0] i_source_error;
    bit i_axis_tready, i_uhd;
    wire o_source_ready, o_axis_tvalid, o_axis_tlast, o_capture_idle, o_frame_accept;
    wire [31:0] o_source_stale_count, o_drop_count, o_error_count;
    wire [127:0] o_axis_tdata;
    wire [15:0] o_axis_tkeep;
    wire [1:0] o_axis_tuser;

    shared_raw10_frame_ingress #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .UHD_WIDTH(UHD_WIDTH), .UHD_HEIGHT(UHD_HEIGHT),
        .CONTEXT_ENABLE(1), .EXTERNAL_SEQUENCE_ENABLE(1), .PAIR_METADATA_ENABLE(1),
        .SOURCE_TERMINAL_ENABLE(1), .COMPACT_CAPTURE_HEADER(COMPACT), .FIXED_HDR_ROLE(ROLE)
    ) dut (.*);

    typedef struct packed {
        logic [1:0] user_id;
        logic last;
        logic [15:0] keep;
        logic [127:0] data;
    } token_t;

    token_t tokens[$];
    token_t expected_end, held_token;
    bit held, frame_live, fault, accept_expected, terminal, good_source;
    bit [31:0] epoch, sequence_id, session_id;
    bit camera;
    integer groups_per_row, groups_per_frame, token_index;
    integer cycle = 0, trace_file, pass_frames = 0, fail_frames = 0, fault_count, stale_count;
    integer stall_cycles = 0, tail_stall_cycles = 0;
    string scenario = "reset";

    function automatic token_t token(input logic [1:0] user_id, input logic last,
                                     input logic [15:0] keep, input logic [127:0] data);
        token = {user_id, last, keep, data};
    endfunction

    function automatic bit [39:0] raw_group(input integer group_id, input bit [31:0] seq);
        for (int lane = 0; lane < 4; lane++)
            raw_group[10*lane +: 10] = (197*group_id + 271*lane + seq[9:0]) ^
                                      (group_id << (lane+1)) ^ (group_id >> 2);
    endfunction

    task automatic fail(input string reason);
        $fatal(1, "RAW_FAIL profile=%0d case=%s seq=%08x cycle=%0d token=%0d %s",
               PROFILE, scenario, sequence_id, cycle, token_index, reason);
    endtask

    always @(posedge i_clk or negedge i_rst_n) begin : observe
        token_t offered;
        token_t wanted;
        if (!i_rst_n) begin
            held = 0;
        end else if (!done) begin
            cycle++;
            offered = token(o_axis_tuser, o_axis_tlast, o_axis_tkeep, o_axis_tdata);
            if (held && (o_axis_tvalid !== 1'b1 || offered !== held_token))
                fail($sformatf("stall changed offer from %037h to %037h", held_token, offered));
            held = o_axis_tvalid && !i_axis_tready;
            if (held) begin
                held_token = offered;
                stall_cycles++;
                if (offered.user_id == 0 && offered.last)
                    tail_stall_cycles++;
            end
            if (o_frame_accept !== accept_expected)
                fail($sformatf("frame accept got %b expected %b", o_frame_accept, accept_expected));
            if (o_source_ready !== 1'b1)
                fail("SOURCE ready deasserted out of reset");
            if (i_source_valid && i_source_ok && i_source_error == 0 && frame_live && !terminal &&
                {i_source_camera, i_source_session, i_source_epoch, i_source_sequence} ==
                {camera, session_id, epoch, sequence_id})
                good_source = 1;

            $fwrite(trace_file, "%0d,%b,%b,%b,%08x,%08x,%08x,%b,%b",
                    cycle, o_frame_accept, o_source_ready, o_capture_idle, o_drop_count,
                    o_error_count, o_source_stale_count, o_axis_tvalid, i_axis_tready);
            if (o_axis_tvalid)
                $fwrite(trace_file, ",%037h", offered);
            $fwrite(trace_file, "\n");

            if (o_axis_tvalid && i_axis_tready) begin
                if (!frame_live || terminal)
                    fail("output without live frame");
                case (offered.user_id)
                    0, 1: begin
                        if (token_index >= tokens.size())
                            fail("extra DATA or header token");
                        wanted = tokens[token_index];
                        if (offered !== wanted)
                            fail($sformatf("offer=%037h expected=%037h", offered, wanted));
                        token_index++;
                    end
                    2: begin
                        if (fault || !good_source || token_index != tokens.size())
                            fail("END before complete data and matching successful SOURCE");
                        if (offered !== expected_end)
                            fail($sformatf("END=%037h expected=%037h", offered, expected_end));
                        terminal = 1;
                        pass_frames++;
                    end
                    3: begin
                        if (!fault || offered !== token(3, 0, 16'hffff, 128'd0))
                            fail($sformatf("unexpected ABORT=%037h", offered));
                        terminal = 1;
                        fail_frames++;
                    end
                    default: fail("unknown TUSER");
                endcase
            end
        end
    end

    // Stimulus changes at falling edges. The monitor samples the rising-edge transfer.
    task automatic step;
        @(negedge i_clk);
    endtask

    task automatic reset_link;
        #2 i_rst_n = 0;
        frame_live = 0;
        terminal = 0;
        accept_expected = 0;
        i_enable = 0;
        i_valid = 0;
        i_source_valid = 0;
        i_abort = 0;
        i_axis_tready = 0;
        step();
        step();
        i_rst_n = 1;
        i_enable = 1;
        i_axis_tready = 1;
        fault_count = 0;
        stale_count = 0;
        step();
        if ({o_capture_idle, o_axis_tvalid, o_drop_count, o_error_count, o_source_stale_count} !==
            {1'b1, 1'b0, 96'd0})
            fail("reset did not clear public ownership and counters");
    endtask

    task automatic setup_header(input bit uhd, input bit [31:0] seq, input bit time_valid);
        i_uhd = uhd;
        i_external_sequence = seq;
        i_session_id = 32'hd81ac251 ^ (seq << 8);
        i_epoch = 32'h51bf60f3 ^ (seq >> 3);
        i_exposure_group = 32'h97604287 + seq;
        i_camera = ROLE != 0;
        i_sdr_profile = ROLE == 0;
        i_bayer_pattern = seq[1:0];
        i_bayer_valid = ROLE == 0;
        i_time_valid = time_valid;
        i_metadata_valid = 1;
        i_timestamp = 64'h9081a6c44d290ee9 ^ {seq, seq};
        i_actual_exposure = ROLE == 1 ? 3200 : ROLE == 2 ? 200 : 2197;
        i_gain = ROLE == 0 ? 32'h000001ab : 256;
        i_calibration_id = 32'h56a3d02f;
        i_source_kind = 1;
        i_exposure_role = ROLE;
        i_source_qualified = 1;
    endtask

    task automatic model_frame(input string label);
        byte unsigned packed_bytes[$];
        bit [39:0] group_bits;
        bit [127:0] beat;
        bit [15:0] keep;
        bit [23:0] flags;
        bit [63:0] timestamp;
        int unsigned byte_count, samples;

        scenario = label;
        groups_per_row = (i_uhd ? UHD_WIDTH : WIDTH)/4;
        groups_per_frame = groups_per_row*(i_uhd ? UHD_HEIGHT : HEIGHT);
        session_id = i_session_id;
        epoch = i_epoch;
        camera = i_camera;
        sequence_id = i_external_sequence;
        tokens.delete();
        token_index = 0;
        terminal = 0;
        good_source = 0;
        fault = 0;
        frame_live = 1;
        tokens.push_back(token(1, 0, COMPACT ? 16'hc030 : 16'hffff,
                              {i_exposure_group, epoch, session_id, sequence_id}));
        if (COMPACT) begin
            timestamp = i_time_valid ? i_timestamp : 0;
            flags = 0;
            flags[3:0] = 3;
            flags[4] = i_source_kind;
            flags[6:5] = i_exposure_role;
            flags[7] = i_source_qualified;
            flags[8] = i_metadata_valid;
            flags[10:9] = i_bayer_pattern;
            flags[11] = i_bayer_valid;
            flags[12] = i_time_valid;
            tokens.push_back(token(1, 1, 16'hffff, {i_gain, i_actual_exposure, timestamp}));
            tokens.push_back(token(1, 1, 16'hffff,
                                  {epoch, sequence_id, i_calibration_id, 6'd0, i_uhd, camera, flags}));
        end else begin
            tokens.push_back(token(1, 1, ROLE == 1 ? 16'hca17 : 16'hca1b,
                                  {epoch, sequence_id, i_timestamp}));
        end
        for (int group_id = 0; group_id < groups_per_frame; group_id++) begin
            group_bits = raw_group(group_id, sequence_id);
            for (int lane_byte = 0; lane_byte < 5; lane_byte++)
                packed_bytes.push_back(group_bits[8*lane_byte +: 8]);
        end
        byte_count = packed_bytes.size();
        samples = 4*groups_per_frame;
        while (packed_bytes.size() != 0) begin
            beat = 0;
            keep = 0;
            for (int lane_byte = 0; lane_byte < 16 && packed_bytes.size() != 0; lane_byte++) begin
                beat[8*lane_byte +: 8] = packed_bytes.pop_front();
                keep[lane_byte] = 1;
            end
            tokens.push_back(token(0, packed_bytes.size() == 0, keep, beat));
        end
        expected_end = token(2, 0, 16'hffff, {63'd0, 1'b1, samples, byte_count});
    endtask

    task automatic drive_group(input integer group_id, input bit sof, input bit eol,
                               input bit [31:0] seq);
        i_data = raw_group(group_id, seq);
        i_sof = sof;
        i_eol = eol;
        i_valid = 1;
        i_accept = 1;
    endtask

    task automatic start_frame(input string label, input bit uhd, input bit [31:0] seq,
                               input bit time_valid);
        setup_header(uhd, seq, time_valid);
        model_frame(label);
        drive_group(0, 1, 0, seq);
        accept_expected = 1;
        step();
        accept_expected = 0;
        i_valid = 0;
    endtask

    task automatic await_offer(input bit [1:0] user_id, input bit last);
        int age;
        age = 0;
        while (!(o_axis_tvalid === 1'b1 && o_axis_tuser === user_id && o_axis_tlast === last)) begin
            if (age++ >= 50)
                fail($sformatf("waiting for offer user=%0d last=%b", user_id, last));
            step();
        end
    endtask

    task automatic finish_groups(input bit hold_tail, input bit poison_meta);
        int age;
        for (int group_id = 1; group_id < groups_per_frame; group_id++) begin
            if (group_id == groups_per_row) begin
                i_valid = 0;
                step();
                if (PROFILE == 0) begin
                    // An offered but unaccepted group cannot consume bytes or a frame boundary.
                    drive_group(127, 1, 1, ~sequence_id);
                    i_accept = 0;
                    step();
                end
            end
            if (poison_meta && group_id == 4) begin
                i_uhd = !i_uhd;
                i_external_sequence = ~sequence_id;
                i_session_id = ~session_id;
                i_epoch = ~epoch;
                i_timestamp = ~i_timestamp;
                i_bayer_pattern = ~i_bayer_pattern;
                i_gain = ~i_gain;
            end
            if (hold_tail && group_id == groups_per_frame-1) begin
                i_valid = 0;
                repeat (4) step();
                i_axis_tready = 0;
            end
            drive_group(group_id, 0, group_id % groups_per_row == groups_per_row-1, sequence_id);
            step();
        end
        i_valid = 0;
        if (hold_tail) begin
            // A non-aligned final group can produce a full beat before the partial tail.
            // Inspect the next public offer before deciding which beat to pause.
            age = 0;
            while (!(o_axis_tvalid === 1'b1 && o_axis_tuser === 2'd0 && o_axis_tlast === 1'b1)) begin
                if (age++ >= 50)
                    fail("waiting for final DATA offer");
                i_axis_tready = 1;
                step();
            end
            i_axis_tready = 0;
        end
    endtask

    task automatic source(input bit [3:0] stale_fields, input bit ok, input bit [7:0] error_code);
        bit expect_stale;
        expect_stale = stale_fields != 0 || !frame_live || terminal || good_source;
        i_source_camera = camera ^ stale_fields[3];
        i_source_session = session_id ^ {31'd0, stale_fields[2]};
        i_source_epoch = epoch ^ {31'd0, stale_fields[1]};
        i_source_sequence = sequence_id ^ {31'd0, stale_fields[0]};
        i_source_ok = ok;
        i_source_error = error_code;
        i_source_valid = 1;
        step();
        i_source_valid = 0;
        if (expect_stale)
            stale_count++;
        if (o_source_stale_count !== stale_count)
            fail($sformatf("SOURCE stale count got %0d expected %0d", o_source_stale_count, stale_count));
    endtask

    task automatic retire;
        int age;
        age = 0;
        while (!terminal || o_capture_idle !== 1'b1) begin
            if (age++ >= 100)
                fail("no terminal and idle within 100 PIX clocks");
            step();
        end
        if (fault)
            fault_count++;
        if (o_drop_count !== fault_count || o_error_count !== fault_count)
            fail($sformatf("drop/error got %0d/%0d expected %0d",
                           o_drop_count, o_error_count, fault_count));
        frame_live = 0;
        repeat (3) step();
    endtask

    task automatic legal_frame(input string label, input bit uhd, input bit [31:0] seq,
                               input bit time_valid);
        start_frame(label, uhd, seq, time_valid);
        finish_groups(0, 0);
        // Pixel EOF alone may drain DATA but cannot commit success.
        repeat (4) step();
        source(0, 1, 0);
        retire();
    endtask

    task automatic geometry_fault(input bit duplicate_sof, input bit [31:0] seq);
        start_frame(duplicate_sof ? "mid-frame SOF" : "early EOL", 0, seq, 1);
        for (int group_id = 1; group_id < 5; group_id++) begin
            drive_group(group_id, 0, 0, sequence_id);
            step();
        end
        fault = 1;
        drive_group(5, duplicate_sof, !duplicate_sof, sequence_id);
        step();
        i_valid = 0;
        retire();
    endtask

    initial begin : exercise
        int tail_before;
        trace_file = $fopen($sformatf("trace_%0d.csv", PROFILE), "w");
        if (!trace_file)
            fail("could not open public-interface trace");
        step();
        reset_link();
        legal_frame("first legal frame", 0, 32'hfffffffe, ROLE != 0);

        if (PROFILE == 0) begin
            start_frame("UHD tail, stale SOURCE then success", 1, 32'hffffffff, 1);
            tail_before = tail_stall_cycles;
            finish_groups(1, 1);
            source(4'b0001, 1, 0);
            source(4'b0010, 1, 0);
            source(4'b0100, 1, 0);
            source(4'b1000, 1, 0);
            source(0, 1, 0);
            repeat (5) step();
            if (tail_stall_cycles - tail_before < 9)
                fail("fixture failed to hold the final DATA beat");
            i_axis_tready = 1;
            // A following HD SOF is allowed on the same edge as the preceding END.
            await_offer(2, 0);
            setup_header(0, 32'd0, 0);
            drive_group(0, 1, 0, 32'd0);
            accept_expected = 1;
            step();
            if (!terminal)
                fail("previous END did not transfer on the next SOF edge");
            accept_expected = 0;
            i_valid = 0;
            model_frame("HD SOF concurrent with UHD retirement");
            finish_groups(0, 1);
            source(0, 1, 0);
            retire();
            source(0, 1, 0); // Duplicate from the retired frame.

            start_frame("bad SOURCE with stalled UHD tail", 1, 32'd1, 0);
            finish_groups(1, 1);
            fault = 1;
            source(0, 1, 8'h04);
            repeat (8) step();
            i_axis_tready = 1;
            retire();
            if (token_index != tokens.size())
                fail("bad SOURCE discarded a promised tail");
            legal_frame("recovery after bad SOURCE", 0, 32'd2, 1);

            geometry_fault(0, 32'd3);
            legal_frame("recovery after early EOL", 1, 32'd4, 0);
            geometry_fault(1, 32'd5);
            legal_frame("recovery after mid-frame SOF", 0, 32'd6, 1);

            start_frame("capture overrun on downstream stall", 1, 32'd7, 1);
            for (int group_id = 1; group_id < 5; group_id++) begin
                drive_group(group_id, 0, 0, sequence_id);
                step();
            end
            fault = 1;
            i_axis_tready = 0;
            for (int group_id = 5; group_id < groups_per_frame-1; group_id++) begin
                drive_group(group_id, 0, group_id % groups_per_row == groups_per_row-1, sequence_id);
                step();
            end
            i_valid = 0;
            repeat (8) step();
            i_axis_tready = 1;
            retire();
            legal_frame("recovery after capture overrun", 0, 32'd8, 1);

            start_frame("mid-frame disable", 0, 32'd9, 1);
            i_valid = 0;
            repeat (4) step();
            fault = 1;
            i_enable = 0;
            step();
            retire();
            i_enable = 1;
            legal_frame("recovery after disable", 0, 32'd10, 1);

            start_frame("reset with promised DATA tail", 0, 32'd11, 1);
            finish_groups(1, 0);
            repeat (3) step();
            reset_link();
            source(0, 1, 0); // Old ownership may not commit after reset.
            legal_frame("recovery after reset", 1, 32'd12, 0);
        end else if (ROLE != 0) begin
            start_frame("fixed-role cancellation", 0, 32'hffffffff, 1);
            repeat (4) step();
            fault = 1;
            i_abort = 1;
            step();
            i_abort = 0;
            retire();
            legal_frame("fixed-role recovery", 0, 32'd0, 1);
        end else begin
            start_frame("four-byte padded DATA tail", 0, 32'hffffffff, 1);
            finish_groups(1, 0);
            repeat (6) step();
            i_axis_tready = 1;
            source(0, 1, 0);
            retire();
        end

        $display("RAW_PROFILE_PASS profile=%0d good=%0d aborted=%0d stall=%0d tail_stall=%0d",
                 PROFILE, pass_frames, fail_frames, stall_cycles, tail_stall_cycles);
        done = 1;
        $fclose(trace_file);
    end
endmodule

module tb_raw_ingress;
    wire [3:0] done;
    for (genvar profile = 0; profile < 4; profile++) begin : profiles
        raw_ingress_case #(.PROFILE(profile)) test_case (.done(done[profile]));
    end

    initial begin
        wait (&done);
        $display("RAW_INGRESS_PASS profiles=4");
        $finish;
    end

    initial begin
        #40000;
        $fatal(1, "RAW_FAIL simulation watchdog 4000 PIX clocks");
    end
endmodule
