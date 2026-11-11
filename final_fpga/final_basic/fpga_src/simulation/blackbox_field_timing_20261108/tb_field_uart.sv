`timescale 1ns/1ps

module tb_field_uart;
    localparam integer UART_BIT_NS = 20;
    localparam [63:0] SYS0 = 64'hb6_4d_5832_17_a2_b917;
    localparam [63:0] SYS1 = 64'h32_18_b164_81_2c_269b;
    localparam [63:0] SYS2 = 64'h9e_01_2ce0_24_d3_7294;
    reg dfi_clk = 0, pix_clk = 0, sys_clk = 0, user_clk = 0, pix_clock_on = 1;
    reg rst_n = 0, uart_rst_n = 0, dfi_run = 0, pix_run = 0;
    reg [31:0] dfi_session = 32'h4213765a, dfi_epoch = 32'h77008932, pix_epoch = 32'h6f804e79;
    reg job_fire = 0, job_camera = 0;
    reg [31:0] job_sequence = 0;
    reg [1:0] reject = 0, expire = 0, bad_finish = 0, fs = 0;
    reg [3:0] admit = 0;
    reg [7:0] banks = 8'b11_10_01_00, dfi_flags_without_run = 8'hb1;
    reg [15:0] pix_flags = 16'h6aa7;
    reg [63:0] sys_config = SYS0;
    wire [7:0] dfi_flags = (dfi_flags_without_run & 8'hfb) | {5'd0, dfi_run, 2'd0};
    wire [223:0] dfi_page, pix_page;
    wire uart_tx;

    always #5 sys_clk = ~sys_clk;
    always #3.75 dfi_clk = ~dfi_clk;
    always #4 if (pix_clock_on) pix_clk = ~pix_clk;
    always #6 user_clk = ~user_clk;

    camera_field_diagnostics diagnostics (
        .dfi_clk(dfi_clk), .dfi_rst_n(rst_n), .dfi_run(dfi_run),
        .dfi_session(dfi_session), .dfi_epoch(dfi_epoch), .job_fire(job_fire),
        .job_camera(job_camera), .job_sequence(job_sequence), .begin_reject(reject),
        .pair_expire(expire), .bad_finish(bad_finish), .bank_states(banks), .dfi_flags(dfi_flags),
        .pixel_clk(pix_clk), .pixel_rst_n(rst_n), .pixel_run(pix_run), .pixel_epoch(pix_epoch),
        .fs(fs), .capture_admit(admit), .pixel_flags(pix_flags), .dfi_page(dfi_page), .pixel_page(pix_page)
    );

    uart_status_observer #(.UART_DIV(2), .REPORT_INTERVAL_CYCLES(5000),
                           .SNAPSHOT_TIMEOUT_CYCLES(256), .CFG_DIAG_ENABLE(1), .CFG_FRAME_VERSION(2),
                           .JOB_PAGE_ENABLE(1), .JOB_SYS_CONFIG_ENABLE(1),
                           .RX_DIAG_ENABLE(0), .RX_TRACE_ENABLE(0)) observer (
        .i_sys_clk(sys_clk), .i_sys_rst_n(uart_rst_n), .i_pixel_clk(pix_clk),
        .i_dfi_clk(dfi_clk), .i_user_clk(user_clk), .i_domain_observer_rst_n({3{rst_n}}),
        .i_domain_reset_n({3{rst_n}}), .i_sys_status(16'h1234), .i_domain_flags(36'h123456789),
        .i_domain_faults(12'h243), .i_domain_progress(6'h24), .i_cfg_domains({pix_page, dfi_page}),
        .i_cfg_domain_reset_n({2{rst_n}}), .i_job_sys_config(sys_config), .i_rx_word_clk(1'b0),
        .i_rx_domains(384'b0), .i_rx_reset_n(3'b0), .i_trace_ack(1'b0), .i_trace_data(320'b0),
        .o_uart_tx(uart_tx)
    );

    integer seq_model [0:1];
    reg [15:0] jobs_model [0:1], fs_model [0:1], admits_model [0:3];
    reg [7:0] reject_model [0:1], expire_model [0:1], bad_model [0:1];
    reg previous_dfi_run = 0, previous_pix_run = 0;
    reg [223:0] dfi_expected, pix_expected;
    integer dfi_checks = 0, pix_checks = 0;

    always @(posedge dfi_clk) begin : dfi_oracle
        integer eye;
        if (!rst_n || (dfi_run && !previous_dfi_run)) begin
            for (eye = 0; eye < 2; eye = eye+1) begin
                seq_model[eye] = 0;
                jobs_model[eye] = 0;
                reject_model[eye] = 0;
                expire_model[eye] = 0;
                bad_model[eye] = 0;
            end
        end
        if (rst_n && dfi_run) begin
            if (job_fire) begin
                seq_model[job_camera] = job_sequence;
                jobs_model[job_camera] = jobs_model[job_camera]+1;
            end
            for (eye = 0; eye < 2; eye = eye+1) begin
                if (reject[eye]) reject_model[eye] = reject_model[eye]+1;
                if (expire[eye]) expire_model[eye] = expire_model[eye]+1;
                if (bad_finish[eye]) bad_model[eye] = bad_model[eye]+1;
            end
        end
        previous_dfi_run = rst_n && dfi_run;
        #0.001;
        dfi_expected = {dfi_flags, banks, bad_model[1], bad_model[0], expire_model[1], expire_model[0],
                        reject_model[1], reject_model[0], jobs_model[1], jobs_model[0], dfi_session,
                        dfi_epoch, seq_model[1], seq_model[0]};
        if (rst_n && dfi_page !== dfi_expected)
            $fatal(1, "DFI diagnostic page mismatch got=%h expected=%h", dfi_page, dfi_expected);
        if (rst_n) dfi_checks = dfi_checks+1;
    end

    always @(posedge pix_clk) begin : pix_oracle
        integer channel;
        if (!rst_n || (pix_run && !previous_pix_run)) begin
            for (channel = 0; channel < 2; channel = channel+1) fs_model[channel] = 0;
            for (channel = 0; channel < 4; channel = channel+1) admits_model[channel] = 0;
        end
        if (rst_n && pix_run) begin
            for (channel = 0; channel < 2; channel = channel+1)
                if (fs[channel]) fs_model[channel] = fs_model[channel]+1;
            for (channel = 0; channel < 4; channel = channel+1)
                if (admit[channel]) admits_model[channel] = admits_model[channel]+1;
        end
        previous_pix_run = rst_n && pix_run;
        #0.001;
        pix_expected = {16'd0, pix_epoch, pix_flags, 64'd0, admits_model[3], admits_model[2],
                        admits_model[1], admits_model[0], fs_model[1], fs_model[0]};
        if (rst_n && pix_page !== pix_expected)
            $fatal(1, "PIX diagnostic page mismatch got=%h expected=%h", pix_page, pix_expected);
        if (rst_n) pix_checks = pix_checks+1;
    end

    task automatic exercise_dfi;
        integer n;
        @(negedge dfi_clk);
        dfi_run = 1;
        job_fire = 1;
        job_camera = 1;
        job_sequence = 32'hc204ad81;
        reject = 2'b11;
        expire = 2'b10;
        bad_finish = 2'b01;
        for (n = 0; n < 258; n = n+1) begin
            @(negedge dfi_clk);
            job_fire = n % 3 == 0;
            job_camera = n % 2;
            job_sequence = 32'h3800ace1 + 23*n;
            reject = {n % 3 == 0, 1'b1};
            expire = {n % 5 == 0, 1'b1};
            bad_finish = {1'b1, n % 7 == 0};
            if (n == 37) dfi_epoch = dfi_epoch+1; // A mode window change is not a RUN boundary.
        end
        @(negedge dfi_clk);
        if (reject_model[0] != 8'd3 || expire_model[0] != 8'd2 || bad_model[1] != 8'd2)
            $fatal(1, "coverage: expected 8-bit modulo wrap");
        dfi_run = 0;
        repeat (4) @(negedge dfi_clk); // Pulses with RUN low must leave counters unchanged.
        dfi_run = 1;
        job_fire = 1;
        job_camera = 0;
        job_sequence = 32'h77654321;
        reject = 2'b01;
        expire = 2'b10;
        bad_finish = 2'b11;
        @(negedge dfi_clk);
        if (jobs_model[0] != 1 || jobs_model[1] != 0 || seq_model[1] != 0)
            $fatal(1, "coverage: resume must include first edge's job");
        job_fire = 1;
        job_camera = 1;
        job_sequence = 32'hab123458;
        reject = 2'b10;
        expire = 2'b01;
        bad_finish = 2'b10;
        @(negedge dfi_clk);
        job_fire = 0;
        reject = 0;
        expire = 0;
        bad_finish = 0;
    endtask

    task automatic exercise_pix;
        integer n;
        @(negedge pix_clk);
        pix_run = 1;
        fs = 2'b11;
        admit = 4'b1011;
        for (n = 0; n < 19; n = n+1) begin
            @(negedge pix_clk);
            fs = {n % 2 == 0, 1'b1};
            admit = {n % 3 == 0, n % 4 == 0, n % 5 == 0, n % 6 == 0};
            if (n == 10) pix_epoch = pix_epoch+1;
        end
        @(negedge pix_clk);
        pix_run = 0;
        fs = 2'b11;
        admit = 4'b1111;
        repeat (4) @(negedge pix_clk);
        pix_run = 1;
        fs = 2'b10;
        admit = 4'b0101;
        @(negedge pix_clk);
        fs = 2'b11;
        admit = 4'b1011;
        @(negedge pix_clk);
        fs = 0;
        admit = 0;
    endtask

    task automatic receive_byte(output reg [7:0] data);
        integer n;
        @(negedge uart_tx);
        #(UART_BIT_NS/2);
        if (uart_tx !== 1'b0) $fatal(1, "bad UART start bit");
        for (n = 0; n < 8; n = n+1) begin
            #UART_BIT_NS;
            data[n] = uart_tx;
        end
        #UART_BIT_NS;
        if (uart_tx !== 1'b1) $fatal(1, "bad UART stop bit");
    endtask

    task automatic receive_dj(output reg [543:0] packet, input bit perturb);
        reg [7:0] prev, current;
        integer n;
        prev = 0;
        receive_byte(current);
        n = 1;
        while (!(prev == 8'h44 && current == 8'h4a)) begin
            if (n >= 160) $fatal(1, "UART stream contained no DJ header");
            prev = current;
            receive_byte(current);
            n = n+1;
        end
        packet[15:0] = 16'h4a44;
        for (n = 2; n < 68; n = n+1) begin
            receive_byte(current);
            packet[n*8 +: 8] = current;
            if (perturb && n == 20) begin
                // All three changes happen before their on-wire bytes or later fields.
                // SYS is updated before the overlay's byte 50 starts transmitting.
                #1;
                sys_config = SYS1;
                dfi_epoch = 32'hb4c3ae27;
                banks = 8'b00_01_10_11;
                pix_epoch = 32'ha0208cd6;
                pix_flags = 16'h9043;
            end
        end
    endtask

    function automatic [15:0] dj_crc(input [543:0] packet);
        integer index, k;
        reg [15:0] crc;
        crc = 16'hffff;
        for (index = 0; index < 66; index = index+1) begin
            crc = crc ^ {packet[index*8 +: 8], 8'b0};
            for (k = 0; k < 8; k = k+1) crc = (crc << 1) ^ (crc[15] ? 16'h1021 : 16'b0);
        end
        dj_crc = crc;
    endfunction

    task automatic check_dj(input [543:0] packet, input bit pix_fresh,
                            input [223:0] dfi_wanted, input [223:0] pix_wanted,
                            input [63:0] config_wanted);
        reg [223:0] overlaid;
        if (packet[47:0] !== 48'h0044_0102_4a44 || packet[543:528] !== dj_crc(packet))
            $fatal(1, "DJ v2 wire header or CRC mismatch");
        if (packet[65:64] !== {pix_fresh, 1'b1} || packet[72] !== 1'b1 ||
            (pix_fresh && packet[73] !== 1'b1))
            $fatal(1, "DJ snapshot mask mismatch fresh=%h reset=%h pix_fresh=%b",
                   packet[71:64], packet[79:72], pix_fresh);
        if (packet[80 +: 224] !== dfi_wanted) $fatal(1, "DFI snapshot changed or mapped incorrectly");
        overlaid = pix_wanted;
        overlaid[96 +: 64] = config_wanted;
        if (pix_fresh && packet[304 +: 224] !== overlaid)
            $fatal(1, "PIX/SYS snapshot changed or mapped incorrectly got=%h expected=%h", packet[304 +: 224], overlaid);
        $display("DJ_WIRE seq=%0d pix_fresh=%b fresh=%h reset=%h crc=%h", packet[63:48], pix_fresh,
                 packet[71:64], packet[79:72], packet[543:528]);
    endtask

    initial begin : test
        reg [223:0] dfi_frozen, pix_frozen;
        reg [543:0] packet;
        reg [15:0] prior_sequence;
        repeat (6) @(negedge sys_clk);
        #1 rst_n = 1;
        fork
            exercise_dfi();
            exercise_pix();
        join
        repeat (4) @(negedge sys_clk);
        dfi_frozen = dfi_expected;
        pix_frozen = pix_expected;
        uart_rst_n = 1; // Listen before the first report; SYS may transmit immediately.
        receive_dj(packet, 1);
        check_dj(packet, 1, dfi_frozen, pix_frozen, SYS0);
        prior_sequence = packet[63:48];

        @(negedge pix_clk);
        pix_clock_on = 0;
        @(negedge dfi_clk);
        dfi_session = 32'ha5c36908;
        job_fire = 1;
        job_camera = 1;
        job_sequence = 32'h1020e481;
        @(negedge dfi_clk);
        job_fire = 0;
        dfi_frozen = dfi_expected;
        receive_dj(packet, 0);
        check_dj(packet, 0, dfi_frozen, '0, SYS1);
        if (packet[63:48] !== prior_sequence + 16'd1) $fatal(1, "DJ sequence lost during PIX clock stop");
        prior_sequence = packet[63:48];

        sys_config = SYS2;
        pix_clock_on = 1;
        @(negedge pix_clk);
        fs = 2'b01;
        admit = 4'b1001;
        @(negedge pix_clk);
        fs = 0;
        admit = 0;
        pix_frozen = pix_expected;
        receive_dj(packet, 0);
        check_dj(packet, 1, dfi_frozen, pix_frozen, SYS2);
        if (packet[63:48] !== prior_sequence + 16'd1) $fatal(1, "DJ sequence lost after PIX clock restart");
        if (dfi_checks < 258 || pix_checks < 20) $fatal(1, "coverage: helper exercise incomplete");
        $display("PASS_FIELD_UART packets=3 dfi_checks=%0d pix_checks=%0d sim_ns=%0d", dfi_checks, pix_checks, $time);
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "UART watchdog expired");
    end
endmodule
