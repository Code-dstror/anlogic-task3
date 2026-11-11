`timescale 1ns/1ps

module tb_uart_cfg_v3;
    localparam integer SYS_CLOCK_NS = 10;
    localparam integer UART_DIV = 4;
    localparam integer BIT_NS = SYS_CLOCK_NS * UART_DIV;
    localparam logic [15:0] SYS_STATUS = 16'h56e1;

    logic sys_clk = 0, dfi_clk = 0, pixel_clk = 0, user_clk = 0;
    logic pixel_clock_running = 1;
    logic sys_rst_n = 0, dfi_rst_n = 0, pixel_rst_n = 0, user_rst_n = 0;
    logic [2:0] observer_rst_n = 0;
    logic dfi_run = 0, pixel_run = 0;
    logic [31:0] dfi_session = 32'h13724a09, dfi_epoch = 17, pixel_epoch = 17;
    logic [31:0] cfg_applied_epoch = 16;
    logic [15:0] cfg_flags = 16'ha76a, pixel_flags = 16'h03f3;
    logic job_fire = 0, job_camera = 0;
    logic [31:0] job_sequence = 0;
    logic [1:0] begin_reject = 0, pair_expire = 0, bad_finish = 0;
    logic [7:0] bank_states = 8'he4, dfi_flags = 8'ha2;
    logic [3:0] capture_admit = 0;
    logic [63:0] job_sys_config = 64'h5ac36b31_691aa442;
    wire [223:0] dfi_page, pixel_page;
    wire uart_tx;

    logic [223:0] expected_dfi, expected_pixel;
    logic [223:0] serial_dfi, serial_pixel;
    logic [1:0] serial_fresh, serial_reset_n;
    logic [15:0] serial_sequence;
    integer packet_pairs = 0;
    integer passed_phases = 0;
    event packet_pair_received;
    logic [7:0] ob [0:28];
    logic [7:0] dj [0:67];
    string phase = "startup";

    always #(SYS_CLOCK_NS / 2) sys_clk = ~sys_clk;
    always #7 dfi_clk = ~dfi_clk;
    always #11 if (pixel_clock_running) pixel_clk = ~pixel_clk;
    always #9 user_clk = ~user_clk;

    camera_field_diagnostics field_pages (
        .dfi_clk(dfi_clk), .dfi_rst_n(dfi_rst_n), .dfi_run(dfi_run),
        .dfi_session(dfi_session), .dfi_epoch(dfi_epoch),
        .job_fire(job_fire), .job_camera(job_camera), .job_sequence(job_sequence),
        .begin_reject(begin_reject), .pair_expire(pair_expire), .bad_finish(bad_finish),
        .bank_states(bank_states), .dfi_flags(dfi_flags),
        .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n), .pixel_run(pixel_run),
        .pixel_epoch(pixel_epoch), .cfg_applied_epoch(cfg_applied_epoch), .cfg_flags(cfg_flags),
        .capture_admit(capture_admit), .pixel_flags(pixel_flags),
        .dfi_page(dfi_page), .pixel_page(pixel_page)
    );

    uart_status_observer #(
        .UART_DIV(UART_DIV), .REPORT_INTERVAL_CYCLES(64), .SNAPSHOT_TIMEOUT_CYCLES(128),
        .CFG_DIAG_ENABLE(1), .CFG_FRAME_VERSION(3), .JOB_PAGE_ENABLE(1),
        .JOB_SYS_CONFIG_ENABLE(1), .RX_DIAG_ENABLE(0), .RX_TRACE_ENABLE(0)
    ) observer (
        .i_sys_clk(sys_clk), .i_sys_rst_n(sys_rst_n),
        .i_pixel_clk(pixel_clk), .i_dfi_clk(dfi_clk), .i_user_clk(user_clk),
        .i_domain_observer_rst_n(observer_rst_n),
        .i_domain_reset_n({user_rst_n, dfi_rst_n, pixel_rst_n}),
        .i_sys_status(SYS_STATUS), .i_domain_flags({12'h307, 12'h2a5, 12'h19c}),
        .i_domain_faults(12'h0), .i_domain_progress(6'h0),
        .i_cfg_domains({pixel_page, dfi_page}),
        .i_cfg_domain_reset_n({pixel_rst_n, dfi_rst_n}), .i_job_sys_config(job_sys_config),
        .i_rx_word_clk(sys_clk), .i_rx_domains(384'h0), .i_rx_reset_n(3'h0),
        .o_trace_request(), .o_trace_index(), .i_trace_ack(1'b0), .i_trace_data(320'h0),
        .o_uart_tx(uart_tx)
    );

    task automatic fail(input string reason);
        $fatal(1, "FAIL_UART_CFG_V3 %s t=%0t report_pairs=%0d %s", phase, $time, packet_pairs, reason);
    endtask

    task automatic receive_byte(output logic [7:0] value);
        @(negedge uart_tx);
        #(BIT_NS / 2);
        if (uart_tx !== 1'b0)
            fail("invalid 8N1 start bit");
        for (integer bit_number = 0; bit_number < 8; bit_number++) begin
            #BIT_NS;
            if (uart_tx !== 1'b0 && uart_tx !== 1'b1)
                fail("unknown TX data bit");
            value[bit_number] = uart_tx;
        end
        #BIT_NS;
        if (uart_tx !== 1'b1)
            fail("invalid 8N1 stop bit");
    endtask

    function automatic logic [7:0] ob_crc8;
        logic [7:0] crc;
        crc = 0;
        for (integer index = 0; index < 28; index++) begin
            crc = crc ^ ob[index];
            repeat (8)
                crc = (crc << 1) ^ (crc[7] ? 8'h07 : 8'h00);
        end
        return crc;
    endfunction

    function automatic logic [15:0] dj_crc16;
        logic [15:0] crc;
        crc = 16'hffff;
        for (integer index = 0; index < 66; index++) begin
            crc = crc ^ {dj[index], 8'h00};
            repeat (8)
                crc = (crc << 1) ^ (crc[15] ? 16'h1021 : 16'h0000);
        end
        return crc;
    endfunction

    initial begin : uart_receiver
        @(posedge sys_rst_n);
        #1;
        if (uart_tx !== 1'b1)
            fail("UART did not start in the idle-high state");
        forever begin
            for (integer index = 0; index < 29; index++)
                receive_byte(ob[index]);
            if ({ob[0], ob[1], ob[2], ob[3]} !== 32'h4f42_021d || ob[28] !== ob_crc8())
                fail("OB/v2 header or CRC8 mismatch");
            if ({ob[9], ob[8]} !== SYS_STATUS || ob[6][7:3] !== 0 || ob[7][7:3] !== 0)
                fail("OB/v2 SYS status or mask encoding mismatch");
            if (ob[6][0] && ob[7][0] && {ob[15], ob[14], ob[13], ob[12], ob[11], ob[10]} !== 48'h0000_0000_019c)
                fail("OB/v2 PIX payload mismatch");
            if (ob[6][1] && ob[7][1] && {ob[21], ob[20], ob[19], ob[18], ob[17], ob[16]} !== 48'h0000_0000_02a5)
                fail("OB/v2 DFI payload mismatch");
            if (ob[6][2] && ob[7][2] && {ob[27], ob[26], ob[25], ob[24], ob[23], ob[22]} !== 48'h0000_0000_0307)
                fail("OB/v2 USER payload mismatch");

            for (integer index = 0; index < 68; index++)
                receive_byte(dj[index]);
            if ({dj[0], dj[1], dj[2], dj[3], dj[4], dj[5]} !== 48'h444a_0301_4400)
                fail("DJ/v3 header mismatch");
            if ({dj[67], dj[66]} !== dj_crc16())
                fail("DJ/v3 CRC16 mismatch");
            if (dj[8][7:2] !== 0 || dj[9][7:2] !== 0)
                fail("DJ/v3 mask has bits outside the two domains");
            for (integer index = 0; index < 28; index++) begin
                serial_dfi[index * 8 +: 8] = dj[10 + index];
                serial_pixel[index * 8 +: 8] = dj[38 + index];
            end
            serial_fresh = dj[8][1:0];
            serial_reset_n = dj[9][1:0];
            serial_sequence = {dj[7], dj[6]};
            packet_pairs++;
            -> packet_pair_received;
        end
    end

    task automatic drive_dfi(
        input logic run, camera, input logic [31:0] sequence_id,
        input logic [1:0] reject_bits, expire_bits, finish_bits
    );
        @(negedge dfi_clk);
        dfi_run = run;
        dfi_flags[2] = run;
        job_fire = 1;
        job_camera = camera;
        job_sequence = sequence_id;
        begin_reject = reject_bits;
        pair_expire = expire_bits;
        bad_finish = finish_bits;
        @(negedge dfi_clk);
        job_fire = 0;
        begin_reject = 0;
        pair_expire = 0;
        bad_finish = 0;
    endtask

    task automatic drive_pixel(input logic run, input logic [3:0] admitted);
        @(negedge pixel_clk);
        pixel_run = run;
        capture_admit = admitted;
        @(negedge pixel_clk);
        capture_admit = 0;
    endtask

    task automatic check_live_pages;
        #1;
        if (dfi_page !== expected_dfi)
            fail($sformatf("DFI page expected %056h got %056h", expected_dfi, dfi_page));
        // SYS configuration belongs to the transmitted page's freeze edge.
        if ({pixel_page[223:160], pixel_page[95:0]} !==
            {expected_pixel[223:160], expected_pixel[95:0]})
            fail($sformatf("PIX page expected %056h got %056h", expected_pixel, pixel_page));
    endtask

    task automatic await_report(
        input string name, input logic [1:0] fresh_mask, fresh_bits, reset_bits, input integer attempts
    );
        logic [223:0] expected_serial_pixel;
        phase = name;
        expected_serial_pixel = expected_pixel;
        expected_serial_pixel[159:96] = job_sys_config;
        for (integer attempt = 0; attempt < attempts; attempt++) begin
            @(packet_pair_received);
            if ((serial_fresh & fresh_mask) !== fresh_bits || serial_reset_n !== reset_bits)
                continue;
            if (serial_fresh[0] && serial_reset_n[0] && serial_dfi !== expected_dfi)
                continue;
            if (serial_fresh[1] && serial_reset_n[1] && serial_pixel !== expected_serial_pixel)
                continue;
            $display("DONE_UART_CFG_V3 %s sequence=%0d fresh=%b reset_n=%b",
                     phase, serial_sequence, serial_fresh, serial_reset_n);
            passed_phases++;
            return;
        end
        fail($sformatf("expected fresh %b mask %b reset_n %b DFI %056h PIX %056h; last fresh %b reset_n %b DFI %056h PIX %056h",
                       fresh_bits, fresh_mask, reset_bits, expected_dfi, expected_serial_pixel,
                       serial_fresh, serial_reset_n, serial_dfi, serial_pixel));
    endtask

    initial begin : public_event_stimulus
        repeat (5) @(negedge sys_clk);
        sys_rst_n = 1;
        pixel_rst_n = 1;
        dfi_rst_n = 1;
        user_rst_n = 1;
        observer_rst_n = 3'b111;
        expected_dfi = {dfi_flags, bank_states, 80'h0, dfi_session, dfi_epoch, 64'h0};
        expected_pixel = {cfg_flags, pixel_epoch, pixel_flags, 128'h0, cfg_applied_epoch};
        check_live_pages();

        phase = "first RUN rise and events";
        fork
            begin
                drive_dfi(1, 0, 32'h31415927, 2'b11, 2'b10, 2'b01);
                drive_dfi(1, 1, 32'h89abcdef, 2'b01, 2'b11, 2'b10);
                drive_dfi(1, 1, 32'h10203040, 2'b00, 2'b10, 2'b11);
            end
            begin
                drive_pixel(1, 4'b0101);
                drive_pixel(1, 4'b1010);
                drive_pixel(1, 4'b0110);
                drive_pixel(1, 4'b1000);
                drive_pixel(1, 4'b0100);
                drive_pixel(1, 4'b1000);
                drive_pixel(1, 4'b1000);
            end
        join
        expected_dfi[223:216] = dfi_flags;
        expected_dfi[207:128] = {8'd2, 8'd2, 8'd3, 8'd1, 8'd1, 8'd2, 16'd2, 16'd1};
        expected_dfi[63:0] = 64'h10203040_31415927;
        expected_pixel[95:32] = {16'd4, 16'd3, 16'd2, 16'd1};
        check_live_pages();
        await_report("RUN events and SYS override", 2'b11, 2'b11, 2'b11, 4);

        phase = "mode change preserves running counts";
        @(negedge dfi_clk);
        dfi_flags[0] = 1;
        @(negedge pixel_clk);
        pixel_flags[2] = 1;
        expected_dfi[223:216] = dfi_flags;
        expected_pixel[175:160] = pixel_flags;
        check_live_pages();

        phase = "RUN falling and held counters";
        fork
            begin
                drive_dfi(0, 0, 32'hbbbbcccc, 2'b11, 2'b11, 2'b11);
                drive_dfi(0, 1, 32'hddddffff, 2'b11, 2'b11, 2'b11);
            end
            begin
                drive_pixel(0, 4'b0101);
                drive_pixel(0, 4'b1010);
            end
        join
        expected_dfi[223:216] = dfi_flags;
        check_live_pages();
        await_report("RUN down leaves counters held", 2'b11, 2'b11, 2'b11, 4);

        phase = "second RUN rise";
        fork
            drive_dfi(1, 1, 32'haabb0042, 2'b10, 2'b01, 2'b11);
            drive_pixel(1, 4'b1001);
        join
        expected_dfi[223:216] = dfi_flags;
        expected_dfi[207:128] = {8'd1, 8'd1, 8'd0, 8'd1, 8'd1, 8'd0, 16'd1, 16'd0};
        expected_dfi[63:0] = 64'haabb0042_00000000;
        expected_pixel[95:32] = {16'd1, 16'd0, 16'd0, 16'd1};
        check_live_pages();
        await_report("next RUN clears and includes its first event", 2'b11, 2'b11, 2'b11, 4);

        @(negedge pixel_clk);
        pixel_clock_running = 0;
        await_report("PIX stopped invalidates only PIX freshness", 2'b11, 2'b01, 2'b11, 4);
        await_report("PIX stays stale with its clock stopped", 2'b11, 2'b01, 2'b11, 1);

        @(negedge sys_clk);
        pixel_epoch = 18;
        cfg_applied_epoch = 17;
        cfg_flags = 16'hf42a;
        job_sys_config = 64'ha49f021b_06354e24;
        pixel_clock_running = 1;
        drive_pixel(1, 4'b0010);
        expected_pixel[223:208] = cfg_flags;
        expected_pixel[207:176] = pixel_epoch;
        expected_pixel[63:48] = 1;
        expected_pixel[31:0] = cfg_applied_epoch;
        check_live_pages();
        await_report("PIX recovered with new CFG and SYS values", 2'b11, 2'b11, 2'b11, 4);

        @(negedge pixel_clk);
        pixel_rst_n = 0;
        pixel_run = 0;
        expected_pixel[95:32] = 0;
        await_report("PIX business reset invalidates the page", 2'b01, 2'b01, 2'b01, 4);

        @(negedge pixel_clk);
        pixel_rst_n = 1;
        check_live_pages();
        drive_pixel(1, 4'b0100);
        expected_pixel[79:64] = 1;
        check_live_pages();
        await_report("PIX reset released with fresh counts", 2'b11, 2'b11, 2'b11, 4);

        $display("PASS_UART_CFG_V3 phases=%0d packet_pairs=%0d", passed_phases, packet_pairs);
        $finish;
    end

    initial begin
        #2_000_000;
        fail("2 ms simulation watchdog");
    end
endmodule
