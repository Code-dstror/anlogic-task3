`timescale 1ns/1ps

module tb_fusion_uart;
    localparam integer UART_DIV = 4;
    localparam integer BIT_NS = 40 * UART_DIV;
    localparam integer OB_BYTES = 29, DJ_BYTES = 76, ROUND_BYTES = OB_BYTES + DJ_BYTES;
    localparam integer ROUNDS = 5;
    logic sys_clk = 0, pixel_clk = 0, dfi_clk = 0, user_clk = 0, pixel_clock_run = 1;
    always #20 sys_clk = ~sys_clk;
    always #4.153 pixel_clk = pixel_clock_run ? ~pixel_clk : 0;
    always #3.751 dfi_clk = ~dfi_clk;
    always #5.117 user_clk = ~user_clk;
    logic sys_rst_n = 0;
    logic [2:0] observe_reset_n = 0, business_reset_n = 0;

    logic dfi_run = 0, pixel_run = 0;
    logic [31:0] dfi_session = 32'h302ef001, dfi_epoch = 32'h10203040;
    logic job_fire = 0, job_camera = 0;
    logic [31:0] job_sequence = 0;
    logic [1:0] begin_reject = 0, pair_expire = 0, bad_finish = 0;
    logic [7:0] bank_states = 8'he4, dfi_flags = 8'hc6;
    logic [31:0] pixel_epoch = 32'h11223344, cfg_applied_epoch = 32'h11223343;
    logic [15:0] cfg_flags = 16'ha6ca, pixel_flags = 16'h30f3;
    logic [1:0] fs = 0;
    logic [3:0] capture_admit = 0;
    logic [63:0] sensor_sys = 64'h1357_0be4_2468_2d70;
    wire [223:0] dfi_page, pixel_page;
    wire [31:0] pixel_fs;
    wire tx;

    camera_field_diagnostics events (
        .dfi_clk(dfi_clk), .dfi_rst_n(business_reset_n[1]), .dfi_run(dfi_run),
        .dfi_session(dfi_session), .dfi_epoch(dfi_epoch), .job_fire(job_fire),
        .job_camera(job_camera), .job_sequence(job_sequence), .begin_reject(begin_reject),
        .pair_expire(pair_expire), .bad_finish(bad_finish), .bank_states(bank_states), .dfi_flags(dfi_flags),
        .pixel_clk(pixel_clk), .pixel_rst_n(business_reset_n[0]), .pixel_run(pixel_run),
        .pixel_epoch(pixel_epoch), .cfg_applied_epoch(cfg_applied_epoch), .cfg_flags(cfg_flags),
        .fs(fs), .capture_admit(capture_admit), .pixel_flags(pixel_flags),
        .dfi_page(dfi_page), .pixel_page(pixel_page), .pixel_fs(pixel_fs)
    );

    uart_status_observer #(
        .UART_DIV(UART_DIV), .REPORT_INTERVAL_CYCLES(256), .SNAPSHOT_TIMEOUT_CYCLES(64),
        .CFG_DIAG_ENABLE(1), .CFG_FRAME_VERSION(4), .JOB_PAGE_ENABLE(1), .JOB_SYS_CONFIG_ENABLE(1),
        .RX_DIAG_ENABLE(0), .RX_TRACE_ENABLE(0)
    ) observer (
        .i_sys_clk(sys_clk), .i_sys_rst_n(sys_rst_n), .i_pixel_clk(pixel_clk),
        .i_dfi_clk(dfi_clk), .i_user_clk(user_clk), .i_domain_observer_rst_n(observe_reset_n),
        .i_domain_reset_n(business_reset_n), .i_sys_status(16'h5a6b), .i_domain_flags(36'h103c97182),
        .i_domain_faults(12'h201), .i_domain_progress(6'h29), .i_cfg_domains({pixel_page, dfi_page}),
        .i_cfg_domain_reset_n({business_reset_n[0], business_reset_n[1]}), .i_job_sys_config(sensor_sys),
        .i_job_pixel_fs(pixel_fs), .i_rx_word_clk(1'b0), .i_rx_domains(384'b0), .i_rx_reset_n(3'b0),
        .i_trace_ack(1'b0), .i_trace_data(320'b0), .o_uart_tx(tx)
    );

    string phase = "first RUN", capture_path;
    integer received = 0, capture_file;

    task automatic dfi_event(input logic run, input logic fire, input logic camera,
        input logic [31:0] seq, input logic [1:0] reject, input logic [1:0] expiry, input logic [1:0] failed);
        @(negedge dfi_clk);
        dfi_run = run;
        dfi_flags[2] = run;
        job_fire = fire;
        job_camera = camera;
        job_sequence = seq;
        begin_reject = reject;
        pair_expire = expiry;
        bad_finish = failed;
        @(negedge dfi_clk);
        {job_fire, begin_reject, pair_expire, bad_finish} = 0;
    endtask

    task automatic pix_event(input logic run, input logic [1:0] fs_events, input logic [3:0] admit_events);
        @(negedge pixel_clk);
        pixel_run = run;
        fs = fs_events;
        capture_admit = admit_events;
        @(negedge pixel_clk);
        {fs, capture_admit} = 0;
    endtask

    task automatic dj_started(input integer round_number);
        wait(received >= (round_number - 1) * ROUND_BYTES + OB_BYTES + 1);
    endtask

    initial begin : capture_serial
        logic [7:0] octet;
        if (!$value$plusargs("CAPTURE=%s", capture_path)) capture_path = "uart_capture.bin";
        capture_file = $fopen(capture_path, "wb");
        if (capture_file == 0) $fatal(1, "FUSION_UART_SERIAL_FAIL cannot open capture");
        wait(tx === 1 && sys_rst_n === 1);
        while (received < ROUNDS * ROUND_BYTES) begin
            @(negedge tx);
            #(BIT_NS/2);
            if (tx !== 0) $fatal(1, "FUSION_UART_SERIAL_FAIL byte=%0d no start bit", received);
            for (int bit_index = 0; bit_index < 8; bit_index++) begin
                #BIT_NS;
                octet[bit_index] = tx;
            end
            #BIT_NS;
            if (tx !== 1 || $isunknown(octet))
                $fatal(1, "FUSION_UART_SERIAL_FAIL byte=%0d data=%h stop=%b", received, octet, tx);
            $fwrite(capture_file, "%c", octet);
            received++;
        end
        $fclose(capture_file);
        $display("FUSION_UART_SERIAL_PASS octets=%0d rounds=%0d", received, ROUNDS);
        $finish;
    end

    initial begin : stimulus
        repeat (8) @(negedge sys_clk);
        observe_reset_n = 3'b111;
        business_reset_n = 3'b111;
        fork
            begin
                dfi_event(1, 1, 1, 32'h90472abb, 2, 1, 2);
                dfi_event(1, 1, 0, 32'h1230ac61, 1, 2, 1);
                dfi_event(1, 1, 1, 32'hc090350d, 2, 2, 0);
            end
            begin
                pix_event(1, 1, 4'b0001);
                pix_event(1, 1, 4'b1000);
                pix_event(1, 2, 4'b0110);
                pix_event(1, 3, 4'b0011);
                pix_event(1, 1, 4'b0000);
            end
        join
        @(negedge sys_clk);
        sys_rst_n = 1;

        // Updating after the first serialized DJ byte leaves the transmitting round frozen.
        dj_started(1);
        phase = "PIX clock stopped, DFI counter wrap";
        @(negedge pixel_clk);
        pixel_clock_run = 0;
        repeat (255) dfi_event(1, 0, 0, 0, 1, 0, 0);

        dj_started(2);
        phase = "resume PIX, switch epoch under RUN";
        cfg_applied_epoch = 32'h11223344;
        pixel_epoch = 32'h11223345;
        cfg_flags = 16'hf12a;
        pixel_clock_run = 1;
        fork
            begin
                dfi_event(0, 1, 0, 32'hdeadbeef, 3, 3, 3);
                dfi_event(0, 1, 1, 32'hdeadbeef, 3, 3, 3);
            end
            begin
                pix_event(1, 2, 4'b1010);
                pix_event(1, 3, 4'b0101);
            end
        join

        dj_started(3);
        phase = "PIX RUN stopped, hold old counters";
        pix_event(0, 3, 4'b1111);
        pix_event(0, 3, 4'b1111);
        @(negedge sys_clk);
        sensor_sys = 64'h5c68_2c20_36a2_38e0;

        dj_started(4);
        phase = "second RUN includes its rising-edge events";
        fork
            begin
                @(negedge dfi_clk);
                dfi_epoch = 32'h10203041;
                dfi_session = 32'h302ef002;
                dfi_event(1, 1, 0, 0, 2, 0, 1);
            end
            pix_event(1, 2, 4'b0100);
        join
    end

    initial begin
        #2_000_000;
        $fatal(1, "FUSION_UART_SERIAL_FAIL phase=%s byte=%0d simulation watchdog", phase, received);
    end
endmodule
