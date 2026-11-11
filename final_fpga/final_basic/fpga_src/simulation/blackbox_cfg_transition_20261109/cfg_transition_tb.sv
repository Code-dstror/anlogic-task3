`timescale 1ns/1ps

module cfg_transition_tb;
    `include "cfg_protocol.svh"

    localparam integer EXT_WIDTH = 1024;
    localparam integer WAIT_POLLS = 240;
    localparam integer WAIT_PIXELS = 1200;
    localparam integer HOLD_POLLS = 12;
    localparam [31:0] HOST_READY_CAPABILITY = 32'd1;

    reg user_clk = 0;
    reg pixel_clk = 0;
    reg user_clock_running = 1;
    reg user_rst_n = 0;
    reg pixel_rst_n = 0;
    reg stereo_mode = 1;
    reg write_valid = 0;
    reg [11:0] write_offset = 0;
    reg [31:0] write_data = 0;
    wire [1:0] write_response;
    reg read_valid = 0;
    reg [11:0] read_offset = 0;
    wire read_response_valid;
    wire [31:0] read_data;
    wire [1:0] read_response;
    reg pipeline_idle = 1;
    reg frame_accept = 0;
    reg [31:0] frame_sequence = 0;
    reg apply_source_fault = 0;
    wire source_ready, pause_new_jobs;
    wire [31:0] source_session, mode_epoch;
    wire [1183:0] config_data;
    wire config_valid;
    reg config_ready = 0;
    reg [1183:0] ack_data = 0;
    reg ack_valid = 0;
    reg ack_ok = 0;
    wire ack_ready;
    wire [31:0] stale_ack_count;
    integer config_handshakes = 0;
    reg [31:0] session_id;
    reg [31:0] epoch = 0;
    reg [6:0] current_quality = 75;
    reg [1023:0] current_extension = 0;
    string test_case;

    always #4 if (user_clock_running) user_clk = ~user_clk;
    initial begin
        #1.3;
        forever #5 pixel_clk = ~pixel_clk;
    end

    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n)
            config_handshakes <= 0;
        else if (config_valid && config_ready)
            config_handshakes <= config_handshakes + 1;
    end

    mono_config_service_v2 #(
        .PROFILE(1), .MAX_WIDTH(1920), .MAX_HEIGHT(1080),
        .REMOTE_CONFIG_ENABLE(1), .EXT_WIDTH(EXT_WIDTH), .EXT_STRIPS(4),
        .EXT_COMBINATIONS(0), .EXT_SUPPORTED(8'h3c),
        .V2_SUPPORTED_MODES(3'b101), .V2_SUPPORTED_ENABLES(6'h3f),
        .LIVE_GRAY_FIXED_ENABLE(0), .LIVE_BASIC_MODES_ENABLE(1),
        .COMPACT_EMPTY_EXTENSION_ENABLE(0), .COMPACT_STAGE2_EXTENSION_ENABLE(1),
        .LANE_GAUSSIAN_ONLY(1), .CFG_DIAG_ENABLE(0), .STEREO_CAPABLE(1),
        .APPLY_SOURCE_FAULT_ENABLE(1)
    ) dut (
        .user_clk(user_clk), .user_rst_n(user_rst_n),
        .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n), .i_stereo_mode(stereo_mode),
        .write_valid(write_valid), .write_offset(write_offset), .write_data(write_data),
        .write_strobes(4'hf), .write_response(write_response),
        .read_valid(read_valid), .read_offset(read_offset),
        .read_response_valid(read_response_valid), .read_data(read_data),
        .read_response(read_response), .pipeline_idle(pipeline_idle),
        .frame_accept(frame_accept), .frame_sequence(frame_sequence),
        .source_ready(source_ready), .pause_new_jobs(pause_new_jobs),
        .source_session(source_session), .mode_epoch(mode_epoch),
        .m_config_data(config_data), .m_config_valid(config_valid), .m_config_ready(config_ready),
        .s_config_ack_data(ack_data), .s_config_ack_valid(ack_valid),
        .s_config_ack_ok(ack_ok), .s_config_ack_ready(ack_ready),
        .config_stale_ack_count(stale_ack_count),
        .diag_observer_rst_n(2'b11), .diag_source_fs(1'b0), .diag_source_gates(16'b0),
        .i_apply_source_fault(apply_source_fault)
    );

    initial begin
        #1500000;
        $fatal(1, "CFG_EVIDENCE FAIL WATCHDOG case=%s", test_case);
    end

    function automatic [1023:0] extension(input [1:0] product, input [5:0] enables);
        reg [1023:0] result;
        begin
            result = 0;
            result[SCHEMA_LSB +: SCHEMA_WIDTH] = SCHEMA_2;
            result[PRODUCT_MODE_LSB +: PRODUCT_MODE_WIDTH] = product;
            result[PROCESSING_ENABLES_LSB +: PROCESSING_ENABLES_WIDTH] = enables;
            if (product == MONO_HDR) begin
                result[HDR_RATIO_LSB +: HDR_RATIO_WIDTH] = 4;
                result[HDR_BLACK_LONG_LSB +: HDR_BLACK_LONG_WIDTH] = 50;
                result[HDR_BLACK_SHORT_LSB +: HDR_BLACK_SHORT_WIDTH] = 50;
                result[HDR_MOTION_BASE_LSB +: HDR_MOTION_BASE_WIDTH] = 64;
                result[HDR_MOTION_SHIFT_LSB +: HDR_MOTION_SHIFT_WIDTH] = 3;
                result[HDR_QUALIFICATION_LSB +: HDR_QUALIFICATION_WIDTH] = HDR_QUALIFICATION_REQUIRED;
                result[HDR_MAX_DELTA_NS_LSB +: HDR_MAX_DELTA_NS_WIDTH] = 64'd50000000;
                result[HDR_MAX_WAIT_NS_LSB +: HDR_MAX_WAIT_NS_WIDTH] = 32'd100000000;
                result[HDR_MAX_AGE_NS_LSB +: HDR_MAX_AGE_NS_WIDTH] = 32'd1000000000;
            end
            extension = result;
        end
    endfunction

    function automatic [1183:0] request_tuple(
        input [31:0] seq, input [6:0] quality, input [1023:0] ext_bits
    );
        request_tuple = {ext_bits, epoch + 32'd1, 6'b0, 16'b0, 25'b0,
                         7'd1, 1'b0, quality, COLOR, session_id, seq};
    endfunction

    task automatic bar_write(input [11:0] address, input [31:0] value);
        @(negedge user_clk);
        write_offset = address;
        write_data = value;
        write_valid = 1;
        @(posedge user_clk);
        if (write_response !== 2'b00)
            $fatal(1, "CFG_EVIDENCE FAIL BAR_WRITE address=%h value=%h response=%h", address, value, write_response);
        @(negedge user_clk);
        write_valid = 0;
    endtask

    task automatic bar_read(input [11:0] address, output [31:0] value);
        integer cycles;
        begin
            @(negedge user_clk);
            read_offset = address;
            read_valid = 1;
            @(posedge user_clk);
            #1;
            cycles = 0;
            if (read_response_valid !== 1'b1) begin
                @(negedge user_clk);
                read_valid = 0;
            end
            while (read_response_valid !== 1'b1 && cycles < 80) begin
                @(posedge user_clk);
                #1;
                cycles = cycles + 1;
            end
            if (read_response_valid !== 1'b1 || read_response !== 2'b00)
                $fatal(1, "CFG_EVIDENCE FAIL BAR_READ address=%h valid=%b response=%h", address, read_response_valid, read_response);
            value = read_data;
            if (read_valid) begin
                @(negedge user_clk);
                read_valid = 0;
            end
        end
    endtask

    task automatic expect_register(input [11:0] address, input [31:0] expected);
        reg [31:0] value;
        begin
            bar_read(address, value);
            if (value !== expected)
                $fatal(1, "CFG_EVIDENCE FAIL BAR_VALUE address=%h expected=%h got=%h", address, expected, value);
        end
    endtask

    task automatic expect_active(input integer full_extension);
        integer word_index;
        begin
            expect_register(CFG_SESSION, session_id);
            expect_register(CFG_ACTIVE_SESSION, session_id);
            expect_register(CFG_MODE_EPOCH, epoch);
            expect_register(CFG_ACTIVE_MODE, {30'd0, COLOR});
            expect_register(CFG_ACTIVE_QUALITY, {25'd0, current_quality});
            if (full_extension != 0) begin
                expect_register(CFG_ACTIVE_FLAGS, 0);
                expect_register(CFG_ACTIVE_MIN_QUALITY, 1);
                expect_register(CFG_ACTIVE_FRAME_BUDGET, 0);
                expect_register(CFG_ACTIVE_RESTART_MCUS, 0);
                for (word_index = 0; word_index < EXT_WORD_COUNT; word_index = word_index + 1)
                    expect_register(CFG_EXT_ACTIVE_BASE + 12'(4 * word_index),
                                    current_extension[32*word_index +: 32]);
            end
        end
    endtask

    task automatic wait_status(
        input [31:0] mask, input [31:0] expected_seq, input bit check_seq, input string failure_stage
    );
        reg [31:0] status, response_seq, error_code;
        integer poll;
        begin : wait_for_publication
            response_seq = 0;
            for (poll = 0; poll < WAIT_POLLS; poll = poll + 1) begin
                bar_read(CFG_STATUS, status);
                if (check_seq)
                    bar_read(CFG_RESPONSE_SEQUENCE, response_seq);
                if (!check_seq || response_seq == expected_seq) begin
                    if ((status & mask) === mask)
                        disable wait_for_publication;
                    if ((status & STATUS_ERROR) != 0) begin
                        bar_read(CFG_ERROR, error_code);
                        $fatal(1, "CFG_EVIDENCE FAIL UNEXPECTED_ERROR stage=%s seq=%h status=%h error=%h",
                               failure_stage, response_seq, status, error_code);
                    end
                end
            end
            bar_read(CFG_MODE_EPOCH, error_code);
            $fatal(1, "CFG_EVIDENCE FAIL %s req=%h status=%h response=%h active_epoch=%0d source_ready=%b old_idle=%b",
                   failure_stage, expected_seq, status, response_seq, error_code, source_ready, pipeline_idle);
        end
    endtask

    task automatic expect_pending(
        input [31:0] seq, input [31:0] forbidden, input bit forbid_request, input bit require_no_source
    );
        reg [31:0] status, response_seq;
        integer poll;
        begin
            for (poll = 0; poll < HOLD_POLLS; poll = poll + 1) begin
                bar_read(CFG_STATUS, status);
                bar_read(CFG_RESPONSE_SEQUENCE, response_seq);
                if (response_seq == seq && (status & forbidden) != 0)
                    $fatal(1, "CFG_EVIDENCE FAIL EARLY_STATUS seq=%h status=%h forbidden=%h", seq, status, forbidden);
                if (forbid_request && config_valid !== 1'b0)
                    $fatal(1, "CFG_EVIDENCE FAIL EARLY_REMOTE_REQUEST seq=%h", seq);
                if (require_no_source && source_ready !== 1'b0)
                    $fatal(1, "CFG_EVIDENCE FAIL EARLY_SOURCE seq=%h", seq);
            end
            expect_active(0);
        end
    endtask

    task automatic take_remote(output [1183:0] tuple);
        integer cycles;
        begin
            @(negedge pixel_clk);
            cycles = 0;
            while (config_valid !== 1'b1 && cycles < WAIT_PIXELS) begin
                @(negedge pixel_clk);
                cycles = cycles + 1;
            end
            if (config_valid !== 1'b1)
                $fatal(1, "CFG_EVIDENCE FAIL REMOTE_REQUEST_TIMEOUT");
            tuple = config_data;
            repeat (12) begin
                @(posedge pixel_clk);
                if (config_valid !== 1'b1 || config_data !== tuple)
                    $fatal(1, "CFG_EVIDENCE FAIL REMOTE_OFFER_CHANGED_UNDER_STALL");
            end
            @(negedge pixel_clk);
            config_ready = 1;
            @(posedge pixel_clk);
            if (config_valid !== 1'b1 || config_data !== tuple)
                $fatal(1, "CFG_EVIDENCE FAIL REMOTE_HANDSHAKE_CHANGED_TUPLE");
            @(negedge pixel_clk);
            config_ready = 0;
        end
    endtask

    task automatic return_ack(input [1183:0] tuple, input bit okay);
        integer cycles;
        begin
            // This delay models the external owner draining and accepting the tuple.
            repeat (18) @(negedge pixel_clk);
            ack_data = tuple;
            ack_ok = okay;
            ack_valid = 1;
            @(posedge pixel_clk);
            cycles = 0;
            while (ack_ready !== 1'b1 && cycles < WAIT_PIXELS) begin
                @(posedge pixel_clk);
                cycles = cycles + 1;
            end
            if (ack_ready !== 1'b1)
                $fatal(1, "CFG_EVIDENCE FAIL REMOTE_ACK_TIMEOUT");
            @(negedge pixel_clk);
            ack_valid = 0;
            ack_ok = 0;
        end
    endtask

    task automatic release_reset;
        repeat (16) @(negedge pixel_clk);
        @(negedge user_clk);
        user_rst_n = 1;
        @(negedge pixel_clk);
        pixel_rst_n = 1;
    endtask

    task automatic boot;
        reg [1183:0] tuple;
        reg [31:0] status;
        begin
            epoch = 0;
            current_quality = 75;
            current_extension = 0;
            take_remote(tuple);
            if (tuple[159:128] !== 32'd0 || tuple[72:66] !== 7'd75 || tuple[65:64] !== COLOR)
                $fatal(1, "CFG_EVIDENCE FAIL BOOT_TUPLE epoch=%h mode=%h quality=%h",
                       tuple[159:128], tuple[65:64], tuple[72:66]);
            return_ack(tuple, 1);
            wait_status(STATUS_SESSION_READY, 0, 0, "BOOT_SESSION_READY");
            bar_read(CFG_SESSION, session_id);
            if (session_id !== tuple[63:32] || session_id !== source_session)
                $fatal(1, "CFG_EVIDENCE FAIL BOOT_SESSION_ID bar=%h remote=%h pixel=%h", session_id, tuple[63:32], source_session);
            bar_read(CFG_STATUS, status);
            if ((status & (STATUS_APPLIED | STATUS_ERROR | STATUS_BUSY | STATUS_READY)) !== 0 || config_handshakes != 1)
                $fatal(1, "CFG_EVIDENCE FAIL BOOT_TERMINAL status=%h config_count=%0d", status, config_handshakes);
            expect_active(0);
            $display("CFG_EVIDENCE BOOT session=%h epoch=0 quality=75 time=%0t", session_id, $time);
        end
    endtask

    task automatic prepare_commit(
        input [31:0] seq, input [6:0] quality, input [1023:0] ext_bits, output [1183:0] tuple
    );
        integer word_index;
        integer cycles;
        integer prior_count;
        reg [1183:0] expected;
        reg [31:0] status, response_seq, error_code;
        begin
            prior_count = config_handshakes;
            expected = request_tuple(seq, quality, ext_bits);
            @(negedge pixel_clk);
            pipeline_idle = 0;
            bar_write(CFG_HOST_CAPABILITIES, HOST_READY_CAPABILITY);
            bar_write(CFG_REQUEST_SEQUENCE, seq);
            bar_write(CFG_REQUEST_SESSION, session_id);
            bar_write(CFG_REQUEST_MODE, {30'd0, COLOR});
            bar_write(CFG_REQUEST_QUALITY, {25'd0, quality});
            bar_write(CFG_REQUEST_FLAGS, 0);
            bar_write(CFG_REQUEST_MIN_QUALITY, 1);
            bar_write(CFG_REQUEST_FRAME_BUDGET, 0);
            bar_write(CFG_REQUEST_RESTART_MCUS, 0);
            for (word_index = 0; word_index < EXT_WORD_COUNT; word_index = word_index + 1)
                bar_write(CFG_EXT_SHADOW_BASE + 12'(4 * word_index), ext_bits[32*word_index +: 32]);
            expect_register(CFG_REQUEST_SEQUENCE, seq);
            expect_register(CFG_REQUEST_SESSION, session_id);
            expect_register(CFG_REQUEST_MODE, {30'd0, COLOR});
            expect_register(CFG_REQUEST_QUALITY, {25'd0, quality});
            expect_register(CFG_REQUEST_FLAGS, 0);
            expect_register(CFG_REQUEST_MIN_QUALITY, 1);
            expect_register(CFG_REQUEST_FRAME_BUDGET, 0);
            expect_register(CFG_REQUEST_RESTART_MCUS, 0);
            for (word_index = 0; word_index < EXT_WORD_COUNT; word_index = word_index + 1)
                expect_register(CFG_EXT_SHADOW_BASE + 12'(4 * word_index), ext_bits[32*word_index +: 32]);
            bar_write(CFG_COMMAND, COMMAND_PREPARE_EXT);
            cycles = 0;
            while (pause_new_jobs !== 1'b1 && cycles < WAIT_PIXELS) begin
                @(negedge pixel_clk);
                cycles = cycles + 1;
            end
            if (pause_new_jobs !== 1'b1) begin
                bar_read(CFG_STATUS, status);
                bar_read(CFG_RESPONSE_SEQUENCE, response_seq);
                bar_read(CFG_ERROR, error_code);
                $fatal(1, "CFG_EVIDENCE FAIL PREPARE_PAUSE seq=%h status=%h response=%h error=%h", seq,
                       status, response_seq, error_code);
            end
            expect_pending(seq, STATUS_READY | STATUS_APPLIED | STATUS_ERROR, 1, 0);
            if (pause_new_jobs !== 1'b1)
                $fatal(1, "CFG_EVIDENCE FAIL OLD_DRAIN_PAUSE_RELEASE seq=%h", seq);
            @(negedge pixel_clk);
            pipeline_idle = 1;
            wait_status(STATUS_READY, seq, 1, "PREPARE_READY");
            expect_pending(seq, STATUS_APPLIED | STATUS_ERROR, 1, 0);
            bar_write(CFG_COMMAND, COMMAND_COMMIT);
            take_remote(tuple);
            if (tuple !== expected) begin
                for (word_index = 0; word_index < 37; word_index = word_index + 1)
                    if (tuple[32*word_index +: 32] !== expected[32*word_index +: 32])
                        $display("CFG_EVIDENCE TUPLE_DIFF seq=%h word=%0d expected=%h got=%h", seq,
                                 word_index, expected[32*word_index +: 32], tuple[32*word_index +: 32]);
                $fatal(1, "CFG_EVIDENCE FAIL REMOTE_TUPLE seq=%h", seq);
            end
            if (config_handshakes != prior_count + 1)
                $fatal(1, "CFG_EVIDENCE FAIL REMOTE_REQUEST_COUNT seq=%h before=%0d after=%0d", seq, prior_count, config_handshakes);
            expect_pending(seq, STATUS_APPLIED | STATUS_ERROR, 1, 1);
            $display("CFG_EVIDENCE READY_AND_REMOTE seq=%h old_epoch=%0d new_epoch=%0d quality=%0d schema_word=%h time=%0t",
                     seq, epoch, epoch + 1, quality, ext_bits[31:0], $time);
        end
    endtask

    task automatic wait_frame_ready;
        integer cycles;
        begin
            cycles = 0;
            while ((source_ready !== 1'b1 || pause_new_jobs !== 1'b0) && cycles < WAIT_PIXELS) begin
                @(negedge pixel_clk);
                cycles = cycles + 1;
            end
            if (source_ready !== 1'b1 || pause_new_jobs !== 1'b0)
                $fatal(1, "CFG_EVIDENCE FAIL ACK_DID_NOT_RELEASE_CAPTURE epoch=%0d", epoch);
        end
    endtask

    task automatic send_frame(input [31:0] seq, input bit fault);
        @(negedge pixel_clk);
        if (source_ready !== 1'b1 || pause_new_jobs !== 1'b0)
            $fatal(1, "CFG_EVIDENCE FAIL CAPTURE_NOT_READY seq=%h", seq);
        frame_sequence = seq;
        frame_accept = 1;
        apply_source_fault = fault;
        @(posedge pixel_clk);
        $display("CFG_EVIDENCE ACCEPT_CAM0 seq=%h pipeline_idle=%b source_fault=%b time=%0t",
                 seq, pipeline_idle, fault, $time);
        @(negedge pixel_clk);
        frame_accept = 0;
        apply_source_fault = 0;
    endtask

    task automatic expect_applied(
        input [31:0] seq, input [31:0] first_seq, input [6:0] quality,
        input [1023:0] ext_bits, input string failure_stage
    );
        begin
            wait_status(STATUS_APPLIED, seq, 1, failure_stage);
            expect_register(CFG_ERROR, 0);
            expect_register(CFG_APPLIED_FIRST_SEQUENCE, first_seq);
            expect_register(CFG_APPLIED_CAMERA, 0);
            epoch = epoch + 1;
            current_quality = quality;
            current_extension = ext_bits;
            if (mode_epoch !== epoch || source_session !== session_id)
                $fatal(1, "CFG_EVIDENCE FAIL PIX_IDENTITY seq=%h pixel_epoch=%0d expected=%0d", seq, mode_epoch, epoch);
            expect_active(1);
            $display("CFG_EVIDENCE APPLIED seq=%h epoch=%0d first_cam0_seq=%h quality=%0d schema_word=%h time=%0t",
                     seq, epoch, first_seq, quality, ext_bits[31:0], $time);
        end
    endtask

    task automatic apply_profile(
        input [31:0] seq, input [6:0] quality, input [1023:0] ext_bits,
        input [31:0] first_seq, input bit keep_busy, input string failure_stage
    );
        reg [1183:0] tuple;
        integer frame_index;
        begin
            prepare_commit(seq, quality, ext_bits, tuple);
            return_ack(tuple, 1);
            wait_frame_ready();
            expect_pending(seq, STATUS_APPLIED | STATUS_ERROR, 1, 0);
            @(negedge pixel_clk);
            pipeline_idle = !keep_busy;
            send_frame(first_seq, 0);
            if (keep_busy) begin
                for (frame_index = 1; frame_index <= 3; frame_index = frame_index + 1) begin
                    repeat (14) @(negedge pixel_clk);
                    send_frame(first_seq + frame_index, 0);
                end
            end
            expect_applied(seq, first_seq, quality, ext_bits, failure_stage);
        end
    endtask

    task automatic expect_reset_error(input [31:0] seq);
        reg [31:0] status;
        begin
            wait_status(STATUS_ERROR, seq, 1, "ERROR_RESET_TERMINAL");
            bar_read(CFG_STATUS, status);
            if ((status & (STATUS_APPLIED | STATUS_BUSY)) !== 0)
                $fatal(1, "CFG_EVIDENCE FAIL ERROR_DID_NOT_TERMINATE seq=%h status=%h", seq, status);
            expect_register(CFG_ERROR, ERROR_RESET);
            expect_active(1);
            $display("CFG_EVIDENCE ERROR_RESET seq=%h old_epoch=%0d time=%0t", seq, epoch, $time);
        end
    endtask

    task automatic run_liveness;
        apply_profile(32'h101, 7'd78, extension(MONO_SDR, ENABLE_HISTOGRAM), 32'h341, 0, "HE_APPLIED");
        apply_profile(32'h102, 7'd80, extension(MONO_SDR, ENABLE_DEHAZE), 32'h480, 1, "LIVENESS");
    endtask

    task automatic run_profiles;
        run_liveness();
        apply_profile(32'h103, 7'd74, extension(MONO_SDR, 0), 32'h510, 1, "SDR_APPLIED");
        apply_profile(32'h104, 7'd78, extension(MONO_SDR, ENABLE_HISTOGRAM), 32'h570, 1, "HE_APPLIED_AGAIN");
        apply_profile(32'h105, 7'd80, extension(MONO_SDR, ENABLE_DEHAZE), 32'h601, 1, "DEHAZE_APPLIED_AGAIN");
        apply_profile(32'h106, 7'd74, extension(MONO_SDR, 0), 32'h680, 1, "SDR_APPLIED_AGAIN");
        apply_profile(32'h107, 7'd75, extension(MONO_HDR, 0), 32'h710, 1, "HDR_APPLIED");
        apply_profile(32'h108, 7'd80, extension(MONO_SDR, ENABLE_DEHAZE), 32'h800, 1, "HDR_TO_DEHAZE_APPLIED");
    endtask

    task automatic run_ack_fault(input bit fault_at_sof);
        reg [1183:0] tuple;
        reg [1183:0] wrong_tuple;
        reg [1023:0] dehaze_ext;
        reg [31:0] stale_before;
        begin
            apply_profile(32'h210, 7'd78, extension(MONO_SDR, ENABLE_HISTOGRAM), 32'hA30, 0, "HE_APPLIED");
            dehaze_ext = extension(MONO_SDR, ENABLE_DEHAZE);
            prepare_commit(32'h211, 7'd80, dehaze_ext, tuple);
            stale_before = stale_ack_count;
            wrong_tuple = tuple;
            wrong_tuple[128] = ~tuple[128];
            return_ack(wrong_tuple, 1);
            expect_pending(32'h211, STATUS_APPLIED | STATUS_ERROR, 1, 1);
            if (stale_ack_count !== stale_before + 32'd1)
                $fatal(1, "CFG_EVIDENCE FAIL STALE_ACK_COUNT before=%h after=%h", stale_before, stale_ack_count);
            $display("CFG_EVIDENCE WRONG_EPOCH_ACK_REJECTED seq=00000211 time=%0t", $time);
            if (fault_at_sof) begin
                return_ack(tuple, 1);
                wait_frame_ready();
                expect_pending(32'h211, STATUS_APPLIED | STATUS_ERROR, 1, 0);
                @(negedge pixel_clk);
                pipeline_idle = 0;
                send_frame(32'hA80, 1);
            end else begin
                return_ack(tuple, 0);
            end
            expect_reset_error(32'h211);
            @(negedge pixel_clk);
            user_rst_n = 0;
            pixel_rst_n = 0;
            pipeline_idle = 1;
            release_reset();
            boot();
            apply_profile(32'h212, 7'd80, dehaze_ext, 32'hAA0, 1, "POST_ERROR_RECOVERY");
        end
    endtask

    task automatic run_stopped_reset;
        reg [1183:0] tuple;
        reg [31:0] response_seq;
        begin
            prepare_commit(32'h310, 7'd78, extension(MONO_SDR, ENABLE_HISTOGRAM), tuple);
            return_ack(tuple, 1);
            wait_frame_ready();
            @(negedge user_clk);
            user_clock_running = 0;
            @(negedge pixel_clk);
            pipeline_idle = 0;
            send_frame(32'hB80, 0);
            repeat (80) @(negedge pixel_clk);
            // Assert both resets off either sampling edge while USER is stopped.
            #2;
            user_rst_n = 0;
            pixel_rst_n = 0;
            repeat (15) @(negedge pixel_clk);
            if (user_clk !== 1'b0 || source_ready !== 1'b0 || config_valid !== 1'b0 || mode_epoch !== 0)
                $fatal(1, "CFG_EVIDENCE FAIL RESET_WHILE_USER_STOPPED clk=%b ready=%b valid=%b pixel_epoch=%0d",
                       user_clk, source_ready, config_valid, mode_epoch);
            $display("CFG_EVIDENCE CLOCK_STOP_RESET_INVALIDATED_PENDING_APPLY time=%0t", $time);
            stereo_mode = 0;
            pipeline_idle = 1;
            user_clock_running = 1;
            release_reset();
            boot();
            bar_read(CFG_RESPONSE_SEQUENCE, response_seq);
            if (response_seq === 32'h310)
                $fatal(1, "CFG_EVIDENCE FAIL STALE_RESPONSE_AFTER_RESET response=%h", response_seq);
            apply_profile(32'h311, 7'd80, extension(MONO_SDR, ENABLE_DEHAZE), 32'hBA0, 0, "POST_STOP_MONO_APPLIED");
        end
    endtask

    initial begin
        if (!$value$plusargs("case=%s", test_case))
            $fatal(1, "CFG_EVIDENCE FAIL MISSING_CASE");
        release_reset();
        boot();
        case (test_case)
            "liveness": run_liveness();
            "profiles": run_profiles();
            "negative_ack": run_ack_fault(0);
            "fault_at_sof": run_ack_fault(1);
            "stopped_reset": run_stopped_reset();
            default: $fatal(1, "CFG_EVIDENCE FAIL UNKNOWN_CASE %s", test_case);
        endcase
        $display("CFG_EVIDENCE PASS case=%s final_epoch=%0d time=%0t", test_case, epoch, $time);
        $finish;
    end
endmodule
