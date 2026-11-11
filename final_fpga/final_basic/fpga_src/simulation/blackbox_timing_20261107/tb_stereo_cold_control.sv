`timescale 1ps/1ps

module tb_stereo_cold_control;
    localparam [9:0] DEFAULT_TUPLE = {1'b0, 1'b0, 8'd2};
    localparam [9:0] DUAL_RAW_1 = {1'b1, 1'b1, 8'd1};
    localparam [9:0] DUAL_RAW_255 = {1'b1, 1'b1, 8'd255};
    localparam [9:0] MONO_JPEG_1 = {1'b0, 1'b0, 8'd1};
    localparam [9:0] MONO_JPEG_255 = {1'b0, 1'b0, 8'd255};
    localparam [1:0] OK = 2'b00;
    localparam [1:0] REJECT = 2'b10;
    localparam [11:0] MODE = 12'hf8c, APPLY = 12'hf90, STATUS = 12'hf94, ERROR_CODE = 12'hf98;
    localparam [11:0] ACTIVE_MODE = 12'hf9c, DIVISOR = 12'hfa0, ACTIVE_DIVISOR = 12'hfa4;
    localparam [11:0] PRODUCT = 12'hfa8, ACTIVE_PRODUCT = 12'hfac;

    reg user_clk = 0, pixel_clk = 0, dfi_clk = 0;
    reg pixel_run = 1, dfi_run = 1;
    reg user_rst_n = 1, pixel_rst_n = 1, dfi_rst_n = 1;
    reg write_valid = 0, read_valid = 0;
    reg [11:0] write_offset = 0, read_offset = 0;
    reg [31:0] write_data = 0;
    reg [3:0] write_strobes = 0;
    wire [1:0] write_response, read_response;
    wire read_response_valid;
    wire [31:0] read_data;
    reg app_enable = 0, c2h_running = 0, config_idle = 1;
    reg pixel_quiet = 1, dfi_quiet = 1;
    wire user_busy, user_locked, user_start_inhibit;
    wire [9:0] user_tuple, pixel_tuple, dfi_tuple;
    wire pixel_pause, dfi_pause;

    integer profile = 0;
    integer dfi_half_period;
    string scenario;
    string phase = "initial";
    reg monitor_enabled = 0, pending = 0, isolated = 0;
    reg [9:0] committed = DEFAULT_TUPLE, proposed = DEFAULT_TUPLE;
    time last_user_edge, last_pixel_edge, last_dfi_edge;

    stereo_cold_control #(.FRAME_DIVISOR(2), .RAW_EXPORT_ENABLE(1)) dut (
        .user_clk(user_clk), .user_rst_n(user_rst_n),
        .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n),
        .dfi_clk(dfi_clk), .dfi_rst_n(dfi_rst_n),
        .write_valid(write_valid), .write_offset(write_offset), .write_data(write_data),
        .write_strobes(write_strobes), .write_response(write_response),
        .read_valid(read_valid), .read_offset(read_offset),
        .read_response_valid(read_response_valid), .read_data(read_data),
        .read_response(read_response), .i_app_enable(app_enable), .i_c2h_running(c2h_running),
        .i_user_config_idle(config_idle), .i_pixel_quiet(pixel_quiet), .i_dfi_quiet(dfi_quiet),
        .o_user_busy(user_busy), .o_user_locked(user_locked), .o_user_mode(user_tuple[9]),
        .o_user_start_inhibit(user_start_inhibit), .o_pixel_mode(pixel_tuple[9]),
        .o_dfi_mode(dfi_tuple[9]), .o_user_raw(user_tuple[8]), .o_pixel_raw(pixel_tuple[8]),
        .o_dfi_raw(dfi_tuple[8]), .o_user_frame_divisor(user_tuple[7:0]),
        .o_pixel_frame_divisor(pixel_tuple[7:0]), .o_dfi_frame_divisor(dfi_tuple[7:0]),
        .o_pixel_pause(pixel_pause), .o_dfi_pause(dfi_pause)
    );

    always #4000 user_clk = ~user_clk;

    initial begin
        wait (profile != 0);
        if (profile == 1) #1310;
        else #2930;
        forever begin
            #4000;
            if (pixel_run) pixel_clk = ~pixel_clk;
        end
    end

    initial begin
        wait (profile != 0);
        if (profile == 1) begin
            dfi_half_period = 3750;
            #620;
        end else begin
            dfi_half_period = 3790;
            #2326;
        end
        forever begin
            #(dfi_half_period);
            if (dfi_run) dfi_clk = ~dfi_clk;
        end
    end

    always @(posedge user_clk) last_user_edge = $time;
    always @(posedge pixel_clk) last_pixel_edge = $time;
    always @(posedge dfi_clk) last_dfi_edge = $time;

    task automatic fail(input string reason);
        $display("BLACKBOX_FAIL stereo_cold_control case=%s profile=%0d phase=%s t=%0t %s",
                 scenario, profile, phase, $time, reason);
        $fatal(1, "External contract check failed");
    endtask

    task automatic step(input string description);
        phase = description;
        $display("BLACKBOX_STEP stereo_cold_control case=%s profile=%0d %s",
                 scenario, profile, description);
    endtask

    // Let all bits settle together after a single clock edge before comparing the tuple.
    always @(pixel_tuple) begin
        #1;
        if (monitor_enabled) begin
            if (last_pixel_edge != $time - 1) fail("PIX tuple changed without a PIX edge");
            if (pixel_tuple !== committed && (!pending || pixel_tuple !== proposed))
                fail($sformatf("PIX tuple=%03h expected %03h or %03h", pixel_tuple,
                               committed, proposed));
            if (pixel_tuple === proposed && pixel_tuple !== committed && pixel_quiet !== 1'b1)
                fail("PIX adopted the proposed tuple while nonquiet");
        end
    end

    always @(dfi_tuple) begin
        #1;
        if (monitor_enabled) begin
            if (last_dfi_edge != $time - 1) fail("DFI tuple changed without a DFI edge");
            if (dfi_tuple !== committed && (!pending || dfi_tuple !== proposed))
                fail($sformatf("DFI tuple=%03h expected %03h or %03h", dfi_tuple,
                               committed, proposed));
            if (dfi_tuple === proposed && dfi_tuple !== committed && dfi_quiet !== 1'b1)
                fail("DFI adopted the proposed tuple while nonquiet");
        end
    end

    always @(user_tuple) begin
        #1;
        if (monitor_enabled) begin
            if (last_user_edge != $time - 1) fail("USER tuple changed without a USER edge");
            if (user_tuple !== committed && (!pending || isolated || user_tuple !== proposed))
                fail($sformatf("USER tuple=%03h committed=%03h proposed=%03h pending=%b isolated=%b",
                               user_tuple, committed, proposed, pending, isolated));
            if (user_tuple !== committed && (pixel_tuple !== user_tuple || dfi_tuple !== user_tuple))
                fail("USER published before both local tuples were adopted");
        end
    end

    always @(user_tuple or pixel_tuple or dfi_tuple or pixel_pause or dfi_pause) begin
        #1;
        if (monitor_enabled && pending) begin
            if (pixel_tuple !== user_tuple && pixel_pause !== 1'b1)
                fail("PIX released pause before USER publication");
            if (dfi_tuple !== user_tuple && dfi_pause !== 1'b1)
                fail("DFI released pause before USER publication");
        end
    end

    task automatic require_tuples(input [9:0] expected);
        if (user_tuple !== expected || pixel_tuple !== expected || dfi_tuple !== expected)
            fail($sformatf("tuple expected=%03h user=%03h pix=%03h dfi=%03h",
                           expected, user_tuple, pixel_tuple, dfi_tuple));
    endtask

    task automatic reset_cohort(input integer domain);
        monitor_enabled = 0;
        pending = 0;
        isolated = 0;
        committed = DEFAULT_TUPLE;
        proposed = DEFAULT_TUPLE;
        @(negedge user_clk);
        #137;
        if (domain == 0 || domain == 3) user_rst_n = 0;
        if (domain == 1 || domain == 3) pixel_rst_n = 0;
        if (domain == 2 || domain == 3) dfi_rst_n = 0;
        repeat (6) @(negedge user_clk);
        require_tuples(DEFAULT_TUPLE);
        #137;
        user_rst_n = 1;
        pixel_rst_n = 1;
        dfi_rst_n = 1;
        monitor_enabled = 1;
        repeat (20) @(negedge user_clk);
        require_tuples(DEFAULT_TUPLE);
    endtask

    task automatic write_reg(input [11:0] address, input [31:0] value,
                             input [3:0] strobes, input [1:0] expected_response);
        @(negedge user_clk);
        write_valid = 1;
        write_offset = address;
        write_data = value;
        write_strobes = strobes;
        @(posedge user_clk);
        if (write_response !== expected_response)
            fail($sformatf("write %03h data=%08h strobes=%h expected response=%b got=%b",
                           address, value, strobes, expected_response, write_response));
        @(negedge user_clk);
        write_valid = 0;
    endtask

    task automatic read_reg(input [11:0] address, input [1:0] expected_response,
                            output [31:0] result);
        @(negedge user_clk);
        read_valid = 1;
        read_offset = address;
        @(posedge user_clk);
        #1;
        if (read_response_valid !== 1'b1 || read_response !== expected_response)
            fail($sformatf("read %03h expected response=%b got valid=%b response=%b",
                           address, expected_response, read_response_valid, read_response));
        result = read_data;
        @(negedge user_clk);
        read_valid = 0;
        @(posedge user_clk);
        #1;
        if (read_response_valid !== 1'b0) fail("read response exceeded one USER cycle");
    endtask

    task automatic expect_reg(input [11:0] address, input [31:0] expected);
        reg [31:0] actual;
        read_reg(address, OK, actual);
        if (actual !== expected)
            fail($sformatf("read %03h expected=%08h got=%08h", address, expected, actual));
    endtask

    task automatic expect_requested(input [9:0] expected);
        expect_reg(MODE, {31'b0, expected[9]});
        expect_reg(PRODUCT, {31'b0, expected[8]});
        expect_reg(DIVISOR, {24'b0, expected[7:0]});
    endtask

    task automatic expect_active(input [9:0] expected);
        expect_reg(ACTIVE_MODE, {31'b0, expected[9]});
        expect_reg(ACTIVE_PRODUCT, {31'b0, expected[8]});
        expect_reg(ACTIVE_DIVISOR, {24'b0, expected[7:0]});
    endtask

    task automatic expect_status(input bit busy, input bit done, input bit locked,
                                 input bit mode, input bit check_done);
        reg [31:0] status_word;
        read_reg(STATUS, OK, status_word);
        if (status_word[4:2] !== {1'b0, mode, locked} || status_word[0] !== busy ||
            (check_done && status_word[1] !== done))
            fail($sformatf("status=%08h expected busy=%b done=%b (check=%b) locked=%b mode=%b",
                           status_word, busy, done, check_done, locked, mode));
    endtask

    task automatic stage_tuple(input [9:0] desired);
        write_reg(MODE, {31'b0, desired[9]}, 4'hf, OK);
        expect_reg(DIVISOR, 32'd2);
        write_reg(PRODUCT, {31'b0, desired[8]}, 4'hf, OK);
        write_reg(DIVISOR, {24'b0, desired[7:0]}, 4'hf, OK);
        expect_requested(desired);
        expect_active(committed);
        require_tuples(committed);
    endtask

    task automatic start_apply(input [9:0] desired);
        proposed = desired;
        pending = 1;
        write_reg(APPLY, 32'd1, 4'hf, OK);
    endtask

    task automatic wait_completed;
        for (integer cycle = 0; cycle < 120; cycle++) begin
            @(negedge user_clk);
            if (user_busy === 1'b0 && user_locked === 1'b0 && user_start_inhibit === 1'b0 &&
                pixel_pause === 1'b0 && dfi_pause === 1'b0 && user_tuple === proposed) begin
                require_tuples(proposed);
                committed = proposed;
                pending = 0;
                expect_status(0, 1, 0, committed[9], 1);
                expect_active(committed);
                return;
            end
        end
        fail($sformatf("APPLY completion timeout busy=%b locked=%b inhibit=%b pause=%b/%b tuple=%03h/%03h/%03h",
                       user_busy, user_locked, user_start_inhibit, pixel_pause, dfi_pause,
                       user_tuple, pixel_tuple, dfi_tuple));
    endtask

    task automatic require_pending(input bit first_pixel);
        if (user_tuple !== committed || user_busy !== 1'b1 || user_start_inhibit !== 1'b1)
            fail("USER did not preserve its active tuple and inhibit start while waiting");
        if (first_pixel) begin
            if (pixel_tuple !== proposed || pixel_pause !== 1'b1 || dfi_tuple !== committed)
                fail("DFI wait did not preserve the split, paused local tuples");
        end else if (dfi_tuple !== proposed || dfi_pause !== 1'b1 || pixel_tuple !== committed) begin
            fail("PIX wait did not preserve the split, paused local tuples");
        end
    endtask

    task automatic wait_first_accept(input bit first_pixel);
        for (integer cycle = 0; cycle < 80; cycle++) begin
            @(negedge user_clk);
            if ((first_pixel ? pixel_tuple : dfi_tuple) === proposed) begin
                require_pending(first_pixel);
                return;
            end
        end
        fail("quiet receiver did not adopt while its peer was blocked");
    endtask

    task automatic stop_receiver(input bit stop_pixel);
        if (stop_pixel) begin
            @(negedge pixel_clk);
            #1;
            pixel_run = 0;
        end else begin
            @(negedge dfi_clk);
            #1;
            dfi_run = 0;
        end
    endtask

    task automatic pulse_start(input bit use_dma);
        @(negedge user_clk);
        if (use_dma) c2h_running = 1;
        else app_enable = 1;
        @(negedge user_clk);
        c2h_running = 0;
        app_enable = 0;
    endtask

    task automatic registers_case;
        reg [31:0] caps, unused_read;
        step("register map, request staging, and invalid writes");
        expect_reg(12'hf80, 32'd827479123);
        expect_reg(12'hf84, 32'd2);
        read_reg(12'hf88, OK, caps);
        if ($isunknown(caps)) fail("capability read contains unknown bits");
        read_reg(APPLY, REJECT, unused_read);
        read_reg(12'hffc, REJECT, unused_read);
        expect_requested(DEFAULT_TUPLE);
        expect_active(DEFAULT_TUPLE);
        expect_status(0, 0, 0, 0, 1);
        expect_reg(ERROR_CODE, 32'd0);

        write_reg(DIVISOR, 32'd255, 4'hf, OK);
        write_reg(MODE, 32'd1, 4'hf, OK);
        expect_reg(DIVISOR, 32'd2);
        stage_tuple(DUAL_RAW_1);
        write_reg(MODE, 32'd2, 4'hf, REJECT);
        expect_reg(ERROR_CODE, 32'd3);
        write_reg(DIVISOR, 32'd0, 4'hf, REJECT);
        write_reg(DIVISOR, 32'd256, 4'hf, REJECT);
        write_reg(PRODUCT, 32'd2, 4'hf, REJECT);
        write_reg(DIVISOR, 32'd37, 4'h7, REJECT);
        write_reg(APPLY, 32'd2, 4'hf, REJECT);
        write_reg(12'hffc, 32'd1, 4'hf, REJECT);
        config_idle = 0;
        write_reg(PRODUCT, 32'd0, 4'hf, REJECT);
        write_reg(APPLY, 32'd1, 4'hf, REJECT);
        config_idle = 1;
        expect_requested(DUAL_RAW_1);
        expect_active(DEFAULT_TUPLE);
        require_tuples(DEFAULT_TUPLE);
        expect_reg(12'hf88, caps);

        step("idle APP start locks writes until cohort reset");
        pulse_start(0);
        write_reg(APPLY, 32'd1, 4'hf, REJECT);
        expect_reg(ERROR_CODE, 32'd2);
        expect_status(0, 0, 1, 0, 1);
        expect_requested(DUAL_RAW_1);
        reset_cohort(0);
        expect_requested(DEFAULT_TUPLE);
        expect_status(0, 0, 0, 0, 1);
    endtask

    task automatic commit_case;
        bit first_pixel;
        first_pixel = (profile == 1);
        step("DUAL RAW DIV1 applies in each domain only at local quiet");
        stage_tuple(DUAL_RAW_1);
        pixel_quiet = first_pixel;
        dfi_quiet = !first_pixel;
        start_apply(DUAL_RAW_1);
        wait_first_accept(first_pixel);
        expect_status(1, 0, 0, 0, 1);
        write_reg(MODE, 32'd0, 4'hf, REJECT);
        expect_reg(ERROR_CODE, 32'd1);
        write_reg(DIVISOR, 32'd255, 4'hf, REJECT);
        write_reg(PRODUCT, 32'd0, 4'hf, REJECT);
        write_reg(APPLY, 32'd1, 4'hf, REJECT);
        expect_requested(DUAL_RAW_1);
        expect_active(DEFAULT_TUPLE);
        require_pending(first_pixel);
        pixel_quiet = 1;
        dfi_quiet = 1;
        wait_completed();

        step("MONO JPEG DIV255 waits for stopped peer and completes when resumed");
        stage_tuple(MONO_JPEG_255);
        stop_receiver(!first_pixel);
        start_apply(MONO_JPEG_255);
        wait_first_accept(first_pixel);
        repeat (22) begin
            @(negedge user_clk);
            require_pending(first_pixel);
        end
        pixel_run = 1;
        dfi_run = 1;
        wait_completed();
    endtask

    task automatic lock_case(input bit use_dma);
        bit first_pixel;
        first_pixel = !use_dma;
        step("one receiver adopted while the other is nonquiet");
        stage_tuple(DUAL_RAW_255);
        pixel_quiet = first_pixel;
        dfi_quiet = !first_pixel;
        start_apply(DUAL_RAW_255);
        wait_first_accept(first_pixel);

        step(use_dma ? "DMA pulse isolates the busy transaction" :
                       "APP pulse isolates the busy transaction");
        isolated = 1;
        pulse_start(use_dma);
        pixel_quiet = 1;
        dfi_quiet = 1;
        repeat (30) begin
            @(negedge user_clk);
            if (user_tuple !== DEFAULT_TUPLE || user_locked !== 1'b1)
                fail("USER publication or unlock after startup pulse during APPLY");
            if ((pixel_tuple !== user_tuple || dfi_tuple !== user_tuple) &&
                user_start_inhibit !== 1'b1)
                fail("partially applied transaction no longer inhibits start");
        end
        write_reg(MODE, 32'd0, 4'hf, REJECT);
        write_reg(APPLY, 32'd1, 4'hf, REJECT);
        expect_active(DEFAULT_TUPLE);
        expect_requested(DUAL_RAW_255);

        step("a single-domain reset clears isolation and permits a fresh APPLY");
        reset_cohort(use_dma ? 2 : 0);
        expect_status(0, 0, 0, 0, 1);
        expect_requested(DEFAULT_TUPLE);
        stage_tuple(DUAL_RAW_1);
        start_apply(DUAL_RAW_1);
        wait_completed();
    endtask

    task automatic reset_wait_case;
        step("commit a nondefault tuple before testing interrupted APPLY");
        stage_tuple(DUAL_RAW_255);
        start_apply(DUAL_RAW_255);
        wait_completed();

        step("PIX reset aborts APPLY while DFI is stopped awaiting acceptance");
        stage_tuple(MONO_JPEG_1);
        stop_receiver(0);
        start_apply(MONO_JPEG_1);
        wait_first_accept(1);
        reset_cohort(1);
        dfi_run = 1;
        repeat (20) @(negedge user_clk);
        require_tuples(DEFAULT_TUPLE);
        expect_status(0, 0, 0, 0, 1);
        expect_requested(DEFAULT_TUPLE);

        step("first post-reset APPLY completes without a stale acknowledgment");
        stage_tuple(DUAL_RAW_1);
        start_apply(DUAL_RAW_1);
        wait_completed();
    endtask

    initial begin
        $timeformat(-9, 3, " ns", 12);
        if (!$value$plusargs("profile=%d", profile) || (profile != 1 && profile != 2))
            fail("missing or invalid clock profile");
        if (!$value$plusargs("case=%s", scenario)) fail("missing case");
        reset_cohort(3);
        case (scenario)
            "registers": registers_case();
            "commit": commit_case();
            "app_lock": lock_case(0);
            "dma_lock": lock_case(1);
            "reset_wait": reset_wait_case();
            default: fail("unknown case");
        endcase
        $display("BLACKBOX_PASS stereo_cold_control case=%s profile=%0d", scenario, profile);
        $finish;
    end

    initial begin
        #10000000;
        fail("10 us simulation watchdog");
    end
endmodule
