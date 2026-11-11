`timescale 1ns/1ps

module tb_fusion_cold;
    // RATE_CONTROL_CONTRACT.md and GEOMETRY_CONTROL_PUBLIC.md application offsets.
    localparam [11:0] APP_CONTROL = 'h018, STEREO_MAGIC = 'hf80, STEREO_ABI = 'hf84,
        REQUEST_MODE = 'hf8c, APPLY = 'hf90, STATUS = 'hf94, ERROR_CODE = 'hf98,
        ACTIVE_MODE = 'hf9c, REQUEST_DIV = 'hfa0, ACTIVE_DIV = 'hfa4,
        REQUEST_PRODUCT = 'hfa8, ACTIVE_PRODUCT = 'hfac, RATE_CAPS = 'hfb0,
        REQUEST_RATE = 'hfb4, ACTIVE_RATE = 'hfb8, REQUEST_GEOMETRY = 'hfbc,
        ACTIVE_GEOMETRY = 'hfc0, GEOMETRY_CAPS = 'hfc4;
    localparam [1:0] OKAY = 0, SLVERR = 2;

    logic user_clk = 0, pixel_clk = 0, dfi_clk = 0, cfg_clk = 0, cfg_run = 1;
    always #4 user_clk = ~user_clk;
    initial begin
        #1.173;
        forever #4 pixel_clk = ~pixel_clk;
    end
    always #3.751 dfi_clk = ~dfi_clk;
    always #20 cfg_clk = cfg_run ? ~cfg_clk : 0;
    logic user_rst_n = 0, pixel_rst_n = 0, dfi_rst_n = 0;

    logic [31:0] awaddr = 0, wdata = 0, araddr = 0;
    logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    logic [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;

    wire write_valid, read_valid, read_response_valid;
    wire [11:0] write_offset, read_offset;
    wire [31:0] write_data, read_data;
    wire [3:0] write_strobes;
    wire [1:0] write_response, read_response;
    logic c2h_running = 0, config_idle = 1, pixel_quiet = 1, dfi_quiet = 1;
    wire app_enable, busy, locked, inhibit, user_mode, pixel_mode, dfi_mode;
    wire user_raw, pixel_raw, dfi_raw, user_uhd, pixel_uhd, dfi_uhd;
    wire [7:0] user_divisor, pixel_divisor, dfi_divisor;
    wire [2:0] pixel_profile, cfg_profile;
    wire pixel_pause, dfi_pause;

    mono_pcie_app_regs_v2 #(.STEREO_ENABLE(1)) bar_regs (
        .i_clk(user_clk), .i_rst_n(user_rst_n),
        .i_axil_awaddr(awaddr), .i_axil_awprot(3'b0), .i_axil_awvalid(awvalid), .o_axil_awready(awready),
        .i_axil_wdata(wdata), .i_axil_wstrb(wstrb), .i_axil_wvalid(wvalid), .o_axil_wready(wready),
        .o_axil_bresp(bresp), .o_axil_bvalid(bvalid), .i_axil_bready(bready),
        .i_axil_araddr(araddr), .i_axil_arprot(3'b0), .i_axil_arvalid(arvalid), .o_axil_arready(arready),
        .o_axil_rdata(rdata), .o_axil_rresp(rresp), .o_axil_rvalid(rvalid), .i_axil_rready(rready),
        .i_status(32'b0), .i_ready_mask(32'b0), .i_sending_mask(32'b0),
        .i_producer_sequence(32'b0), .i_consumed_sequence(32'b0), .i_drop_count(32'b0),
        .i_overflow_count(32'b0), .i_dma_error_count(32'b0), .i_last_error(32'b0),
        .i_h2c_byte_count(32'b0), .i_h2c_frame_count(32'b0), .i_h2c_error_count(32'b0), .i_h2c_first_error(32'b0),
        .i_raw_write_response(2'b10), .i_raw_read_response_valid(1'b0), .i_raw_read_data(32'b0), .i_raw_read_response(2'b10),
        .i_cfg_write_response(2'b10), .i_cfg_read_response_valid(1'b0), .i_cfg_read_data(32'b0), .i_cfg_read_response(2'b10),
        .i_jpeg_write_response(2'b10), .i_jpeg_read_response_valid(1'b0), .i_jpeg_read_data(32'b0), .i_jpeg_read_response(2'b10),
        .i_record_write_response(2'b10), .i_record_read_response_valid(1'b0), .i_record_read_data(32'b0), .i_record_read_response(2'b10),
        .i_algo_write_response(2'b10), .i_algo_read_response_valid(1'b0), .i_algo_read_data(32'b0), .i_algo_read_response(2'b10),
        .i_stereo_start_inhibit(inhibit), .o_app_enable(app_enable),
        .o_stereo_write_valid(write_valid), .o_stereo_write_offset(write_offset),
        .o_stereo_write_data(write_data), .o_stereo_write_strobes(write_strobes), .i_stereo_write_response(write_response),
        .o_stereo_read_valid(read_valid), .o_stereo_read_offset(read_offset),
        .i_stereo_read_response_valid(read_response_valid), .i_stereo_read_data(read_data), .i_stereo_read_response(read_response)
    );

    stereo_cold_control #(.FRAME_DIVISOR(2), .RAW_EXPORT_ENABLE(1), .UHD_ENABLE(1)) dut (
        .user_clk(user_clk), .user_rst_n(user_rst_n), .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n),
        .dfi_clk(dfi_clk), .dfi_rst_n(dfi_rst_n), .cfg_clk(cfg_clk),
        .write_valid(write_valid), .write_offset(write_offset), .write_data(write_data),
        .write_strobes(write_strobes), .write_response(write_response), .read_valid(read_valid),
        .read_offset(read_offset), .read_response_valid(read_response_valid), .read_data(read_data), .read_response(read_response),
        .i_app_enable(app_enable), .i_c2h_running(c2h_running), .i_user_config_idle(config_idle),
        .i_pixel_quiet(pixel_quiet), .i_dfi_quiet(dfi_quiet),
        .o_user_busy(busy), .o_user_locked(locked), .o_user_mode(user_mode), .o_user_start_inhibit(inhibit),
        .o_pixel_mode(pixel_mode), .o_dfi_mode(dfi_mode), .o_user_raw(user_raw), .o_pixel_raw(pixel_raw), .o_dfi_raw(dfi_raw),
        .o_user_frame_divisor(user_divisor), .o_pixel_frame_divisor(pixel_divisor), .o_dfi_frame_divisor(dfi_divisor),
        .o_pixel_sdr_profile(pixel_profile), .o_cfg_sdr_profile(cfg_profile), .o_pixel_pause(pixel_pause), .o_dfi_pause(dfi_pause),
        .o_user_uhd(user_uhd), .o_pixel_uhd(pixel_uhd), .o_dfi_uhd(dfi_uhd)
    );

    string phase = "reset";
    integer applied_profiles = 0;

    task automatic check(input logic condition, input string message);
        if (condition !== 1'b1)
            $fatal(1, "FUSION_COLD_FAIL phase=%s %s", phase, message);
    endtask

    task automatic bar_write(input logic [11:0] offset, input logic [31:0] value,
        input logic [1:0] expected = OKAY, input logic [3:0] strobes = 4'hf);
        // Stagger AW and W, exercising each order without relying on a same-edge handshake.
        fork
            begin
                repeat (offset[2] ? 3 : 1) @(negedge user_clk);
                awaddr = 32'h80000 + {20'b0, offset};
                awvalid = 1;
                do @(posedge user_clk); while (awready !== 1);
                @(negedge user_clk);
                awvalid = 0;
            end
            begin
                repeat (offset[2] ? 1 : 3) @(negedge user_clk);
                wdata = value;
                wstrb = strobes;
                wvalid = 1;
                do @(posedge user_clk); while (wready !== 1);
                @(negedge user_clk);
                wvalid = 0;
            end
        join
        while (bvalid !== 1) @(negedge user_clk);
        repeat (2) begin
            check(bvalid === 1 && bresp === expected,
                $sformatf("write %h=%h expected response=%b observed=%b", offset, value, expected, bresp));
            @(negedge user_clk);
        end
        bready = 1;
        @(negedge user_clk);
        bready = 0;
    endtask

    task automatic bar_read(input logic [11:0] offset, output logic [31:0] value);
        @(negedge user_clk);
        araddr = 32'h80000 + {20'b0, offset};
        arvalid = 1;
        do @(posedge user_clk); while (arready !== 1);
        @(negedge user_clk);
        arvalid = 0;
        while (rvalid !== 1) @(negedge user_clk);
        value = rdata;
        repeat (2) begin
            check(rvalid === 1 && rresp === OKAY && rdata === value,
                $sformatf("read %h response/data changed under stall, response=%b", offset, rresp));
            @(negedge user_clk);
        end
        rready = 1;
        @(negedge user_clk);
        rready = 0;
    endtask

    task automatic expect_reg(input logic [11:0] offset, input logic [31:0] expected);
        logic [31:0] value;
        bar_read(offset, value);
        check(value === expected, $sformatf("read %h expected=%h observed=%h", offset, expected, value));
    endtask

    task automatic release_reset;
        #19 user_rst_n = 1;
        #15 pixel_rst_n = 1;
        #19 dfi_rst_n = 1;
        repeat (14) @(negedge user_clk);
        check(inhibit === 0 && locked === 0 && busy === 0 && app_enable === 0, "cold BOOT did not open staging");
    endtask

    task automatic expect_active(input logic topology, input logic product, input logic [31:0] geometry,
        input logic [31:0] rate, input logic [7:0] request_divisor, input logic [2:0] profile);
        logic is_uhd;
        is_uhd = geometry != 0;
        expect_reg(ACTIVE_MODE, {31'b0, topology});
        expect_reg(ACTIVE_PRODUCT, {31'b0, product});
        expect_reg(ACTIVE_GEOMETRY, geometry);
        expect_reg(ACTIVE_RATE, rate);
        expect_reg(ACTIVE_DIV, {24'b0, request_divisor});
        check({user_mode, pixel_mode, dfi_mode} === {3{topology}}, "topology domain skew");
        check({user_raw, pixel_raw, dfi_raw} === {3{product}}, "product domain skew");
        check({user_uhd, pixel_uhd, dfi_uhd} === {3{is_uhd}}, "geometry domain skew");
        // All cold-controller outputs publish the negotiated divisor. The capture consumer
        // resolves its physical cadence using the selected sensor profile.
        check({user_divisor, pixel_divisor, dfi_divisor} === {3{request_divisor}},
            $sformatf("negotiated divisor expected=%0d observed user=%0d pixel=%0d dfi=%0d",
                request_divisor, user_divisor, pixel_divisor, dfi_divisor));
        check(pixel_profile === profile && cfg_profile === profile,
            $sformatf("sensor profile expected=%0d observed pixel=%0d SYS25=%0d", profile, pixel_profile, cfg_profile));
        check(pixel_pause === 0 && dfi_pause === 0, "local consumer remained paused after APPLY");
    endtask

    task automatic wait_done(input logic topology);
        logic [31:0] value;
        for (int attempt = 0; attempt < 50; attempt++) begin
            bar_read(STATUS, value);
            if (value[1:0] === 2'b10) begin
                check(value[4:2] === {1'b0, topology, 1'b0} && inhibit === 0, "wrong DONE or START inhibition");
                expect_reg(ERROR_CODE, 0);
                applied_profiles++;
                return;
            end
        end
        check(0, $sformatf("APPLY timed out status=%h", value));
    endtask

    initial begin
        release_reset();
        expect_reg(STEREO_MAGIC, 32'h31525453);
        expect_reg(STEREO_ABI, 2);
        expect_reg(RATE_CAPS, 32'h10f);
        expect_reg(GEOMETRY_CAPS, 32'h107);
        expect_active(0, 0, 0, 0, 2, 0);

        phase = "HD mono60";
        bar_write(REQUEST_RATE, 1, SLVERR);
        expect_reg(ERROR_CODE, 3);
        bar_write(REQUEST_DIV, 1);
        bar_write(APPLY, 1);
        wait_done(0);
        expect_active(0, 0, 0, 0, 1, 0);

        phase = "HD dual30";
        bar_write(REQUEST_MODE, 1);
        expect_reg(REQUEST_DIV, 2);
        bar_write(REQUEST_GEOMETRY, 2, SLVERR);
        expect_reg(REQUEST_GEOMETRY, 0);
        expect_reg(ERROR_CODE, 3);
        bar_write(APPLY, 1);
        wait_done(1);
        expect_active(1, 0, 0, 0, 2, 4);

        for (int rate = 1; rate <= 3; rate++) begin
            phase = $sformatf("HD dual explicit rate code %0d", rate);
            bar_write(REQUEST_RATE, rate);
            bar_write(REQUEST_GEOMETRY, 0);
            expect_reg(REQUEST_RATE, rate);
            bar_write(REQUEST_PRODUCT, {31'b0, rate[0]});
            bar_write(APPLY, 1);
            wait_done(1);
            expect_active(1, rate[0], 0, rate, 2, rate[2:0]);
        end

        phase = "UHD15 JPEG";
        @(negedge user_clk);
        config_idle = 0;
        bar_write(REQUEST_MODE, 0, SLVERR);
        expect_reg(ERROR_CODE, 1);
        expect_reg(ACTIVE_RATE, 3);
        @(negedge user_clk);
        config_idle = 1;
        bar_write(REQUEST_MODE, 0);
        expect_reg(REQUEST_RATE, 0);
        expect_reg(REQUEST_GEOMETRY, 0);
        bar_write(REQUEST_DIV, 1);
        bar_write(REQUEST_PRODUCT, 0);
        bar_write(REQUEST_GEOMETRY, 3, SLVERR);
        bar_write(REQUEST_GEOMETRY, 1, SLVERR, 4'h7);
        expect_reg(REQUEST_GEOMETRY, 0);
        bar_write(REQUEST_GEOMETRY, 1);
        bar_write(APPLY, 1);
        wait_done(0);
        expect_active(0, 0, 1, 0, 1, 5);

        phase = "UHD20 RAW with skewed clocks and late SYS25";
        @(negedge pixel_clk);
        pixel_quiet = 0;
        @(negedge dfi_clk);
        dfi_quiet = 0;
        @(negedge cfg_clk);
        cfg_run = 0;
        bar_write(REQUEST_GEOMETRY, 2);
        bar_write(REQUEST_RATE, 0);
        expect_reg(REQUEST_GEOMETRY, 2);
        bar_write(REQUEST_PRODUCT, 1);
        bar_write(APPLY, 1);
        repeat (20) @(negedge user_clk);
        check(busy === 1 && inhibit === 1, "APPLY issued without START inhibition");
        expect_reg(STATUS, 1);
        expect_reg(ACTIVE_GEOMETRY, 1);
        expect_reg(ACTIVE_PRODUCT, 0);
        bar_write(APP_CONTROL, 1, SLVERR);
        check(app_enable === 0, "APP enabled during incomplete APPLY");
        @(negedge pixel_clk);
        pixel_quiet = 1;
        repeat (20) @(negedge user_clk);
        expect_reg(ACTIVE_GEOMETRY, 1);
        @(negedge dfi_clk);
        dfi_quiet = 1;
        repeat (60) @(negedge user_clk);
        expect_reg(STATUS, 1);
        expect_reg(ACTIVE_GEOMETRY, 1);
        expect_reg(ACTIVE_PRODUCT, 0);
        check(cfg_profile === 5 && app_enable === 0, "USER moved while SYS25 still held old profile");
        @(negedge user_clk);
        cfg_run = 1;
        wait_done(0);
        expect_active(0, 1, 2, 0, 1, 6);

        phase = "APP start locks cold controls";
        bar_write(APP_CONTROL, 1);
        repeat (8) @(negedge user_clk);
        check(app_enable === 1 && locked === 1, "APP start failed to lock cold writes");
        bar_write(REQUEST_GEOMETRY, 0, SLVERR);
        bar_write(REQUEST_PRODUCT, 0, SLVERR);
        expect_reg(ERROR_CODE, 2);
        expect_active(0, 1, 2, 0, 1, 6);

        phase = "C2H-only lock survives stop and clears on cohort reset";
        @(negedge user_clk);
        {user_rst_n, pixel_rst_n, dfi_rst_n} = 0;
        repeat (6) @(negedge user_clk);
        release_reset();
        @(negedge user_clk);
        c2h_running = 1;
        repeat (6) @(negedge user_clk);
        check(app_enable === 0 && locked === 1, "C2H-only start did not lock cold writes");
        @(negedge user_clk);
        c2h_running = 0;
        bar_write(REQUEST_GEOMETRY, 2, SLVERR);
        expect_reg(ERROR_CODE, 2);
        expect_reg(ACTIVE_GEOMETRY, 0);
        @(negedge dfi_clk);
        dfi_rst_n = 0;
        repeat (6) @(negedge user_clk);
        dfi_rst_n = 1;
        repeat (14) @(negedge user_clk);
        check(locked === 0, "cohort reset did not clear C2H lock");
        bar_write(REQUEST_DIV, 1);
        bar_write(APPLY, 1);
        wait_done(0);
        expect_active(0, 0, 0, 0, 1, 0);

        $display("FUSION_COLD_PASS completed_applies=%0d", applied_profiles);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "FUSION_COLD_FAIL phase=%s simulation watchdog", phase);
    end
endmodule
