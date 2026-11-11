`timescale 1ns/1ps

module tb_fusion_config #(parameter integer QUALITY_ENABLE = 1);
    // Public CFG1 registers and values from docs/pcie_protocol_v1.json.
    localparam [11:0] FEATURES = 'h208, PROFILE = 'h20c, PRESENT = 'h210,
        WIDTH = 'h214, HEIGHT = 'h218, SESSION = 'h21c,
        REQUEST_SEQUENCE = 'h220, REQUEST_SESSION = 'h224, REQUEST_MODE = 'h228,
        REQUEST_QUALITY = 'h22c, REQUEST_FLAGS = 'h230, REQUEST_MIN = 'h234,
        REQUEST_BUDGET = 'h238, REQUEST_RESTART = 'h23c, COMMAND = 'h240,
        STATUS = 'h244, RESPONSE_SEQUENCE = 'h248, ERROR_CODE = 'h24c,
        ACTIVE_MODE = 'h250, ACTIVE_QUALITY = 'h254, ACTIVE_EPOCH = 'h258,
        FIRST_SEQUENCE = 'h25c, APPLIED_CAMERA = 'h260, ACTIVE_FLAGS = 'h264,
        ACTIVE_MIN = 'h268, ACTIVE_BUDGET = 'h26c, ACTIVE_RESTART = 'h270,
        HOST_CAPABILITIES = 'h274, ACTIVE_SESSION = 'h278,
        EXT_SUPPORTED = 'h38c, EXT_SCHEMAS = 'h39c, EXT_MODES = 'h3a0,
        EXT_ENABLES = 'h3a4, SHADOW_BASE = 'he00, ACTIVE_BASE = 'he80;
    localparam [31:0] PREPARE = 1, COMMIT = 2, PREPARE_EXT = 4,
        PREPARED = 19, APPLIED = 20, INVALID = 1, UNSUPPORTED = 5;

    typedef logic [1183:0] tuple_t;
    typedef logic [1023:0] words_t;
    typedef struct packed {
        logic [1:0] mode;
        logic [6:0] quality;
        logic adaptive;
        logic [6:0] minimum;
        logic [24:0] budget;
        logic [15:0] restart;
    } scalar_t;

    logic user_clk = 0, pixel_clk = 0, dfi_clk = 0;
    always #4 user_clk = ~user_clk;
    always #5.203 pixel_clk = ~pixel_clk;
    always #3.751 dfi_clk = ~dfi_clk;
    logic user_rst_n = 0, pixel_rst_n = 0, dfi_rst_n = 0;
    logic stereo = 0, uhd = 0;
    logic write_valid = 0, read_valid = 0;
    logic [11:0] write_offset = 0, read_offset = 0;
    logic [31:0] write_data = 0;
    wire [1:0] write_response, read_response;
    wire read_response_valid;
    wire [31:0] read_data;

    logic [1:0] source_idle = 3, capture_enqueue = 0, capture_consume = 0;
    logic write_quiet = 1, pipeline_idle = 1, frame_accept = 0;
    logic [31:0] frame_sequence = 0;
    wire source_ready, pause_new_frames;
    wire job_config_valid;
    logic job_ready = 0, job_done = 0, job_busy = 0;
    tuple_t job_config, dfi_active, pixel_active, service_active;
    logic release_ack = 1, inject_valid = 0;
    wire whole_ack_valid, inject_ready;
    tuple_t inject_data = 0;
    wire fault, user_initialized, pixel_initialized;
    wire [31:0] stale_count;

    quality_config_carrier #(.QUALITY_CONTROL_ENABLE(QUALITY_ENABLE)) dut (
        .user_clk(user_clk), .user_rst_n(user_rst_n),
        .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n),
        .dfi_clk(dfi_clk), .dfi_rst_n(dfi_rst_n),
        .i_stereo_mode(stereo), .i_uhd_mode(uhd),
        .write_valid(write_valid), .write_offset(write_offset),
        .write_data(write_data), .write_strobes(4'hf), .write_response(write_response),
        .read_valid(read_valid), .read_offset(read_offset), .read_response_valid(read_response_valid),
        .read_data(read_data), .read_response(read_response),
        .i_source_idle(source_idle), .i_capture_enqueue(capture_enqueue),
        .i_capture_consume(capture_consume), .i_write_quiet(write_quiet),
        .i_pipeline_idle(pipeline_idle), .i_frame_accept(frame_accept), .i_frame_sequence(frame_sequence),
        .o_source_ready(source_ready), .o_pause_new_frames(pause_new_frames),
        .o_job_config_valid(job_config_valid), .i_job_config_ready(job_ready),
        .i_job_config_done(job_done), .i_job_config_error(1'b0), .i_job_config_busy(job_busy),
        .o_job_config(job_config), .o_dfi_active(dfi_active),
        .o_pixel_active(pixel_active), .o_service_active(service_active),
        .i_release_whole_ack(release_ack), .o_whole_ack_valid(whole_ack_valid),
        .i_inject_ack_valid(inject_valid), .i_inject_ack_ok(1'b1), .i_inject_ack_data(inject_data),
        .o_inject_ack_ready(inject_ready), .o_cfg_fault(fault), .o_stale_ack_count(stale_count),
        .o_user_initialized(user_initialized), .o_pixel_initialized(pixel_initialized)
    );

    string scenario, phase = "initialization";
    logic [31:0] session, request_number = 0, epoch = 0, first_sequence = 0;
    tuple_t active_tuple;

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1)
            $fatal(1, "FUSION_CFG_FAIL case=%s phase=%s %s", scenario, phase, message);
    endtask

    task automatic write_reg(input logic [11:0] offset, input logic [31:0] value);
        @(negedge user_clk);
        write_offset = offset;
        write_data = value;
        write_valid = 1;
        #1;
        check(write_response === 2'b00, $sformatf("write %h=%h response=%b", offset, value, write_response));
        @(negedge user_clk);
        write_valid = 0;
        repeat (2) @(negedge user_clk);
    endtask

    task automatic read_reg(input logic [11:0] offset, output logic [31:0] value);
        @(negedge user_clk);
        read_offset = offset;
        read_valid = 1;
        @(negedge user_clk);
        read_valid = 0;
        for (int cycle = 0; cycle < 30 && read_response_valid !== 1; cycle++)
            @(negedge user_clk);
        check(read_response_valid === 1 && read_response === 2'b00,
            $sformatf("read %h response=%b valid=%b", offset, read_response, read_response_valid));
        value = read_data;
    endtask

    task automatic expect_reg(input logic [11:0] offset, input logic [31:0] expected);
        logic [31:0] actual;
        read_reg(offset, actual);
        check(actual === expected, $sformatf("read %h expected=%h observed=%h", offset, expected, actual));
    endtask

    task automatic wait_status(input logic [31:0] mask, input logic [31:0] expected);
        logic [31:0] status_word;
        for (int attempt = 0; attempt < 240; attempt++) begin
            read_reg(STATUS, status_word);
            if ((status_word & mask) === expected) return;
        end
        check(0, $sformatf("status expected=%h mask=%h observed=%h", expected, mask, status_word));
    endtask

    function automatic tuple_t build_tuple(input words_t words, input scalar_t base,
        input logic [31:0] seq, input logic [31:0] target_epoch, input logic [31:0] owner_session);
        return {words, target_epoch, 6'b0, base.restart, base.budget, base.minimum,
            base.adaptive, base.quality, base.mode, owner_session, seq};
    endfunction

    function automatic words_t sdr_words(input logic [5:0] enables);
        words_t words = '0;
        words[7:0] = 2;
        words[15:10] = enables;
        return words;
    endfunction

    function automatic words_t hdr_words(input logic [13:0] motion_base);
        words_t words = sdr_words(6'd10);
        words[9:8] = 2;
        words[66:64] = 4;
        words[76:67] = 50;
        words[86:77] = 50;
        words[100:87] = motion_base;
        words[104:101] = 7;
        words[108:105] = 15;
        words[191:128] = 64'd42_345_671;
        words[223:192] = 32'd110_987_643;
        words[255:224] = 32'd915_234_567;
        words[383:352] = 1;
        return words;
    endfunction

    function automatic words_t with_quality(input words_t words, input logic [9:0] red,
        input logic [9:0] green, input logic [9:0] blue, input logic [1:0] tone, input logic fusion);
        words[63:32] = {1'b0, 1'b1, blue, green, red};
        words[415:384] = {24'b0, 4'd1, 1'b0, fusion, tone};
        return words;
    endfunction

    task automatic expect_tuple(input tuple_t actual, input tuple_t expected, input string boundary);
        check(actual[159:0] === expected[159:0], $sformatf("%s metadata expected=%h observed=%h",
            boundary, expected[159:0], actual[159:0]));
        for (int word_index = 0; word_index < 32; word_index++) begin
            check(actual[160 + 32*word_index +: 32] === expected[160 + 32*word_index +: 32],
                $sformatf("%s word %0d expected=%h observed=%h", boundary, word_index,
                    expected[160 + 32*word_index +: 32], actual[160 + 32*word_index +: 32]));
        end
    endtask

    task automatic expect_active_bar;
        expect_reg(ACTIVE_SESSION, session);
        expect_reg(ACTIVE_EPOCH, epoch);
        expect_reg(FIRST_SEQUENCE, first_sequence);
        expect_reg(APPLIED_CAMERA, 0);
        expect_reg(ACTIVE_MODE, {30'b0, active_tuple[65:64]});
        expect_reg(ACTIVE_QUALITY, {25'b0, active_tuple[72:66]});
        expect_reg(ACTIVE_FLAGS, {31'b0, active_tuple[73]});
        expect_reg(ACTIVE_MIN, {25'b0, active_tuple[80:74]});
        expect_reg(ACTIVE_BUDGET, {7'b0, active_tuple[105:81]});
        expect_reg(ACTIVE_RESTART, {16'b0, active_tuple[121:106]});
        for (int word_index = 0; word_index < 32; word_index++)
            expect_reg(ACTIVE_BASE + 12'(4*word_index), active_tuple[160 + 32*word_index +: 32]);
    endtask

    task automatic complete_dfi(output tuple_t accepted);
        @(negedge dfi_clk);
        for (int cycle = 0; cycle < 400 && job_config_valid !== 1; cycle++)
            @(negedge dfi_clk);
        check(job_config_valid === 1, "DFI CONFIG offer timed out");
        accepted = job_config;
        repeat (9) begin
            @(negedge dfi_clk);
            check(job_config_valid === 1 && job_config === accepted, "DFI offer changed while stalled");
        end
        job_ready = 1;
        @(posedge dfi_clk);
        check(job_config_valid === 1 && job_config === accepted, "wrong DFI handshake tuple");
        @(negedge dfi_clk);
        job_ready = 0;
        job_busy = 1;
        repeat (7) @(negedge dfi_clk);
        job_busy = 0;
        job_done = 1;
        @(negedge dfi_clk);
        job_done = 0;
    endtask

    task automatic boot;
        tuple_t accepted;
        scalar_t defaults = {2'd0, 7'd75, 1'b0, 7'd1, 25'd0, 16'd0};
        phase = "BOOT";
        #33 user_rst_n = 1;
        #9 pixel_rst_n = 1;
        #13 dfi_rst_n = 1;
        complete_dfi(accepted);
        // SESSION_READY must result from the automatic neutral BOOT, without a frame offer.
        wait_status(32'h19, 32'h10);
        check(user_initialized && pixel_initialized && !fault, "BOOT did not initialize both domains");
        read_reg(SESSION, session);
        check(!$isunknown(session) && session != 0, "BOOT session is zero or unknown");
        active_tuple = build_tuple('0, defaults, 0, 0, session);
        expect_tuple(accepted, active_tuple, "BOOT DFI accepted");
        expect_tuple(dfi_active, active_tuple, "BOOT DFI ACTIVE");
        expect_tuple(pixel_active, active_tuple, "BOOT PIX ACTIVE");
        expect_tuple(service_active, active_tuple, "BOOT service ACTIVE");
        expect_active_bar();
        expect_reg(FEATURES, 32'h3f | (QUALITY_ENABLE ? 32'h40 : 0));
        expect_reg(PROFILE, uhd ? 3 : (stereo ? 2 : 1));
        expect_reg(PRESENT, stereo ? 3 : 1);
        expect_reg(WIDTH, uhd ? 3840 : 1920);
        expect_reg(HEIGHT, uhd ? 2160 : 1080);
        expect_reg(EXT_SUPPORTED, (uhd || stereo) ? 0 : 4);
        expect_reg(EXT_SCHEMAS, uhd ? 4 : 6);
        expect_reg(EXT_MODES, uhd ? 1 : 5);
        expect_reg(EXT_ENABLES, uhd ? 13 : (stereo ? 15 : 63));
        write_reg(HOST_CAPABILITIES, 1);
    endtask

    task automatic request_config(input words_t words, input scalar_t base, input logic extended_config);
        request_number++;
        write_reg(REQUEST_SEQUENCE, request_number);
        write_reg(REQUEST_SESSION, session);
        write_reg(REQUEST_MODE, {30'b0, base.mode});
        write_reg(REQUEST_QUALITY, {25'b0, base.quality});
        write_reg(REQUEST_FLAGS, {31'b0, base.adaptive});
        write_reg(REQUEST_MIN, {25'b0, base.minimum});
        write_reg(REQUEST_BUDGET, {7'b0, base.budget});
        write_reg(REQUEST_RESTART, {16'b0, base.restart});
        if (extended_config) begin
            for (int word_index = 0; word_index < 32; word_index++)
                write_reg(SHADOW_BASE + 12'(4*word_index), words[32*word_index +: 32]);
        end
        write_reg(COMMAND, extended_config ? PREPARE_EXT : PREPARE);
    endtask

    task automatic reject_config(input words_t words, input scalar_t base, input logic [31:0] code);
        request_config(words, base, 1);
        wait_status(32'h1b, 32'h18);
        expect_reg(RESPONSE_SEQUENCE, request_number);
        expect_reg(ERROR_CODE, code);
        expect_active_bar();
        expect_tuple(dfi_active, active_tuple, "rejected DFI ACTIVE");
        expect_tuple(pixel_active, active_tuple, "rejected PIX ACTIVE");
        expect_tuple(service_active, active_tuple, "rejected service ACTIVE");
        check(job_config_valid === 0 && fault === 0, "rejection attempted remote CONFIG or quarantined session");
    endtask

    task automatic no_dfi_offer(input string gate_reason);
        repeat (32) begin
            @(negedge dfi_clk);
            check(job_config_valid === 0, $sformatf("CONFIG issued while %s", gate_reason));
        end
        expect_reg(ACTIVE_EPOCH, epoch);
    endtask

    task automatic consume_groups(input logic [1:0] groups);
        @(negedge dfi_clk);
        capture_consume = groups;
        @(negedge dfi_clk);
        capture_consume = 0;
    endtask

    task automatic apply_config(input words_t words, input scalar_t base, input logic extended_config,
        input logic stress_drains, input logic [31:0] new_first);
        tuple_t target, accepted;
        logic [31:0] original_stale;
        if (stress_drains) begin
            @(negedge pixel_clk);
            pipeline_idle = 0;
        end
        request_config(words, base, extended_config);
        target = build_tuple(words, base, request_number, epoch + 1, session);
        if (stress_drains) begin
            no_dfi_offer("old processing is busy during PREPARE");
            repeat (8) begin
                logic [31:0] status_word;
                read_reg(STATUS, status_word);
                check(status_word[1] === 0, "READY while old pipeline is busy");
            end
            @(negedge pixel_clk);
            pipeline_idle = 1;
        end
        wait_status('1, PREPARED);
        expect_reg(RESPONSE_SEQUENCE, request_number);
        expect_reg(ERROR_CODE, 0);
        @(negedge pixel_clk);
        release_ack = 0;
        if (stress_drains) begin
            // Both eyes owe one group. Eye 0 drains first while eye 1 is still live.
            source_idle = 0;
            capture_enqueue = 3;
            @(negedge pixel_clk);
            capture_enqueue = 0;
            consume_groups(1);
            @(negedge pixel_clk);
            source_idle = 1;
        end
        write_reg(COMMAND, COMMIT);
        if (stress_drains) begin
            no_dfi_offer("eye 1 is still live");
            @(negedge pixel_clk);
            source_idle = 3;
            no_dfi_offer("eye 1 still owes a capture group after source idle");
            @(negedge dfi_clk);
            write_quiet = 0;
            consume_groups(2);
            no_dfi_offer("the final write response is still owed");
            @(negedge dfi_clk);
            write_quiet = 1;
        end
        complete_dfi(accepted);
        expect_tuple(accepted, target, "DFI CONFIG accepted");
        expect_tuple(dfi_active, target, "DFI ACTIVE");
        @(negedge pixel_clk);
        for (int cycle = 0; cycle < 200 && whole_ack_valid !== 1; cycle++)
            @(negedge pixel_clk);
        check(whole_ack_valid === 1, "whole ACK missing");
        check(!(source_ready && !pause_new_frames), "admission before whole ACK");
        expect_active_bar();
        expect_tuple(service_active, active_tuple, "service ACTIVE before ACK");

        if (stress_drains) begin
            @(negedge pixel_clk);
            original_stale = stale_count;
            inject_data = active_tuple;
            inject_valid = 1;
            do @(posedge pixel_clk); while (inject_ready !== 1);
            @(negedge pixel_clk);
            inject_valid = 0;
            for (int cycle = 0; cycle < 200 && stale_count === original_stale; cycle++)
                @(negedge pixel_clk);
            check(stale_count === original_stale + 1, "stale ACK did not count exactly once");
            check(!(source_ready && !pause_new_frames), "stale ACK opened new admission");
            expect_active_bar();
        end

        @(negedge pixel_clk);
        if (stress_drains) pipeline_idle = 0;
        release_ack = 1;
        for (int cycle = 0; cycle < 200 && !(source_ready === 1 && pause_new_frames === 0); cycle++)
            @(negedge pixel_clk);
        check(source_ready === 1 && pause_new_frames === 0, "matched whole ACK did not open admission");
        expect_tuple(pixel_active, target, "PIX ACTIVE after matched ACK");
        expect_active_bar();
        expect_tuple(service_active, active_tuple, "service ACTIVE before real first frame");
        @(negedge pixel_clk);
        check(source_ready === 1 && pause_new_frames === 0, "first source offer is not legal");
        frame_sequence = new_first;
        frame_accept = 1;
        @(negedge pixel_clk);
        frame_accept = 0;
        wait_status('1, APPLIED);
        expect_reg(RESPONSE_SEQUENCE, request_number);
        expect_reg(ERROR_CODE, 0);
        epoch++;
        first_sequence = new_first;
        active_tuple = target;
        expect_active_bar();
        expect_tuple(service_active, target, "service ACTIVE after real first frame");
        check(fault === 0, "fault after successful APPLIED");
        @(negedge pixel_clk);
        pipeline_idle = 1;
    endtask

    initial begin : scenarios
        words_t legacy_hdr, first_hdr, bad_words;
        scalar_t base = {2'd0, 7'd87, 1'b1, 7'd23, 25'd327679, 16'd37};
        scalar_t scalar_gaussian = {2'd2, 7'd66, 1'b0, 7'd9, 25'd0, 16'd0};

        if (!$value$plusargs("CASE=%s", scenario)) scenario = "hd-dual";
        stereo = scenario == "hd-dual";
        uhd = scenario == "uhd";
        check(stereo || uhd || scenario == "hd-mono", "unknown case");
        boot();

        legacy_hdr = hdr_words(1279);
        first_hdr = with_quality(legacy_hdr, 901, 377, 702, 3, 1);
        if (uhd) begin
            phase = "UHD legacy scalar Gaussian";
            apply_config('0, scalar_gaussian, 0, 0, 32'h18b);
            phase = "UHD unsupported product and processing";
            reject_config(legacy_hdr, base, UNSUPPORTED);
            reject_config(sdr_words(2), base, UNSUPPORTED);
            reject_config(sdr_words(48), base, UNSUPPORTED);
            phase = "UHD SDR Gray+Gaussian+HE and WB";
            apply_config(with_quality(sdr_words(13), 1023, 1, 513, 0, 0), base, 1, 0, 32'h197);
        end else if (!QUALITY_ENABLE) begin
            phase = "featureless legacy HDR";
            apply_config(legacy_hdr, base, 1, 0, 32'h47);
            phase = "featureless W1/W12 rejection";
            reject_config(first_hdr, base, INVALID);
            apply_config(sdr_words(8), base, 1, 0, 32'h5b);
        end else begin
            phase = "HDR quality and late old-work drain";
            apply_config(first_hdr, base, 1, stereo, 32'h421);
            phase = "invalid manual WB channel";
            bad_words = with_quality(legacy_hdr, 0, 711, 924, 2, 0);
            reject_config(bad_words, base, INVALID);
            phase = "HDR to SDR HE";
            apply_config(with_quality(sdr_words(8), 301, 401, 801, 0, 0), base, 1, 0, 32'h435);
            phase = "invalid SDR tone";
            reject_config(with_quality(sdr_words(8), 301, 401, 801, 2, 0), base, INVALID);
            phase = "invalid version and reserved word";
            bad_words = first_hdr;
            bad_words[391:388] = 2;
            reject_config(bad_words, base, INVALID);
            bad_words = first_hdr;
            bad_words[1023] = 1;
            reject_config(bad_words, base, INVALID);
            phase = "SDR HE to HDR bright";
            apply_config(with_quality(hdr_words(245), 743, 439, 927, 2, 0), base, 1, 0, 32'h476);
            phase = "old HDR encoding accepted by new feature owner";
            apply_config(legacy_hdr, base, 1, 0, 32'h48f);
        end
        $display("FUSION_CFG_PASS case=%s quality=%0d epochs=%0d requests=%0d stale=%0d",
            scenario, QUALITY_ENABLE, epoch, request_number, stale_count);
        $finish;
    end

    initial begin
        #250000;
        $fatal(1, "FUSION_CFG_FAIL case=%s phase=%s simulation watchdog", scenario, phase);
    end
endmodule
