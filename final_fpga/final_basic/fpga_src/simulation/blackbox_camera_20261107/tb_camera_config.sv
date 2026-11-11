`timescale 1ns/1ns

module camera_config_eye #(parameter bit DEFAULT_TIMING = 0) (input logic clk);
    localparam int CLK_NS = 40;
    localparam int HALF = DEFAULT_TIMING ? 125 : 4;
    localparam int SDR_HOLD = DEFAULT_TIMING ? 250000 : 19;
    localparam int SDR_RELEASE = DEFAULT_TIMING ? 250000 : 23;
    localparam int SDR_WAKE = DEFAULT_TIMING ? 625000 : 211;
    localparam int HDR_HOLD = DEFAULT_TIMING ? 250000 : 29;
    localparam int HDR_RELEASE = DEFAULT_TIMING ? 750000 : 37;
    localparam int HDR_WAKE = DEFAULT_TIMING ? 600000 : 257;
    localparam int SDR_WRITES = 203;
    localparam int HDR_WRITES = 139;

    logic rst_n = 0, start = 0, locked = 1, abort = 0, source_fault = 0;
    logic hdr = 0, sdr30 = 0, pair_event = 0, pair_ok = 0;
    logic [7:0] gain = 0;
    wire ready, xclr, scl, written, stable, error;
    wire [7:0] register_index;
    wire [127:0] rx_diag_cfg;
    tri sda;
    bit ack_low = 0;

    pullup (sda);
    assign sda = ack_low ? 1'b0 : 1'bz;

    generate if (DEFAULT_TIMING) begin : production_parameters
        imx415_sensor_config dut (
            .i_clk(clk), .i_rst_n(rst_n), .i_start(start), .o_start_ready(ready),
            .i_clock_locked(locked), .i_abort(abort), .i_source_fault(source_fault),
            .i_hdr(hdr), .i_sdr_30(sdr30), .i_gain_code(gain),
            .i_pair_event(pair_event), .i_pair_ok(pair_ok),
            .o_xclr(xclr), .o_scl(scl), .io_sda(sda),
            .o_config_written(written), .o_stable(stable), .o_error(error),
            .o_register_index(register_index), .o_rx_diag_cfg(rx_diag_cfg)
        );
    end else begin : short_parameters
        imx415_sensor_config #(
            .I2C_HALF_PERIOD(HALF), .SDR_RESET_HOLD_CYCLES(SDR_HOLD),
            .SDR_RELEASE_WAIT_CYCLES(SDR_RELEASE), .SDR_WAKE_CYCLES(SDR_WAKE),
            .HDR_RESET_HOLD_CYCLES(HDR_HOLD), .HDR_RELEASE_WAIT_CYCLES(HDR_RELEASE),
            .HDR_REGULATOR_WAIT_CYCLES(HDR_WAKE)
        ) dut (
            .i_clk(clk), .i_rst_n(rst_n), .i_start(start), .o_start_ready(ready),
            .i_clock_locked(locked), .i_abort(abort), .i_source_fault(source_fault),
            .i_hdr(hdr), .i_sdr_30(sdr30), .i_gain_code(gain),
            .i_pair_event(pair_event), .i_pair_ok(pair_ok),
            .o_xclr(xclr), .o_scl(scl), .io_sda(sda),
            .o_config_written(written), .o_stable(stable), .o_error(error),
            .o_register_index(register_index), .o_rx_diag_cfg(rx_diag_cfg)
        );
    end endgenerate

    string label = "idle";
    int failures = 0;
    int trace_file = 0;
    bit capture = 0, watch_quiet = 0, in_transfer = 0, transfer_nacked = 0;
    bit requested_hdr = 0, requested_sdr30 = 0;
    logic [7:0] requested_gain = 0;
    int expected_writes, starts, stops, writes, slots, stop_clocks;
    int nack_transfer, nack_byte, nack_count, quiet_edges;
    time accepted_at, low_at, release_at, transfer_at, previous_stop;
    time final_ack_rise, final_ack_end, first_written_at, wake_gap;
    time data_rise, data_fall, min_scl_high, min_scl_low;
    bit saw_error, early_written_reported;
    logic [31:0] shifted;
    logic [23:0] recipe [1:SDR_WRITES];
    logic [23:0] saved_recipe [0:1][1:SDR_WRITES];
    int saved_length [0:1];

    task automatic check(input logic condition, input string detail);
        if (condition !== 1'b1) begin
            failures++;
            $display("ASSERT_FAIL %m [%s] t=%0d ns %s", label, $time, detail);
        end
    endtask

    always @(negedge xclr) if (capture) low_at = $time;
    always @(posedge xclr) if (capture) release_at = $time;

    always @(negedge sda) begin
        if (watch_quiet && scl === 1'b1)
            quiet_edges++;
        if (capture && scl === 1'b1) begin
            check(!in_transfer, "new START before previous STOP");
            starts++;
            check(starts <= expected_writes && nack_count == 0,
                  $sformatf("unexpected I2C START number %0d", starts));
            if (starts == 1) begin
                check(low_at != 0 && release_at >= low_at + CLK_NS * (requested_hdr ? HDR_HOLD : SDR_HOLD),
                      $sformatf("XCLR low time low=%0d release=%0d", low_at, release_at));
                check(xclr === 1'b1 && release_at != 0 &&
                      $time >= release_at + CLK_NS * (requested_hdr ? HDR_RELEASE : SDR_RELEASE),
                      $sformatf("first START before XCLR release wait, release=%0d", release_at));
            end
            if (starts == expected_writes) begin
                wake_gap = $time - previous_stop;
                check(previous_stop != 0 && wake_gap >= CLK_NS * (requested_hdr ? HDR_WAKE : SDR_WAKE),
                      $sformatf("standby STOP to XMSTA START only %0d ns", wake_gap));
            end
            in_transfer = 1;
            transfer_nacked = 0;
            transfer_at = $time;
            slots = 0;
            stop_clocks = 0;
            shifted = 0;
            data_rise = 0;
            data_fall = 0;
        end
    end

    always @(posedge scl) begin
        if (watch_quiet) quiet_edges++;
        if (capture && in_transfer && scl === 1'b1) begin
            if (slots < 36 && !transfer_nacked) begin
                data_rise = $time;
                if (data_fall != 0 && $time - data_fall < min_scl_low)
                    min_scl_low = $time - data_fall;
                if (slots % 9 == 8) begin
                    if (starts == nack_transfer && slots / 9 == nack_byte) begin
                        check(sda === 1'b1, "injected NACK did not resolve to a high ninth bit");
                        transfer_nacked = 1;
                        nack_count++;
                    end else begin
                        check(sda === 1'b0, "slave ACK did not resolve to a low ninth bit");
                        if (slots == 35 && starts == expected_writes)
                            final_ack_rise = $time;
                    end
                end else begin
                    check(sda === 1'b0 || sda === 1'b1, "SDA contention or unknown data bit");
                    shifted = {shifted[30:0], sda};
                    if (slots == 7)
                        check(shifted[7:0] === 8'h34, $sformatf("address byte %02h", shifted[7:0]));
                end
                slots++;
            end else begin
                stop_clocks++;
                check(stop_clocks <= 1, "extra SCL pulses after the final ACK or an injected NACK");
            end
        end
    end

    always @(negedge scl) begin
        if (watch_quiet) quiet_edges++;
        if (capture && in_transfer) begin
            if (data_rise != 0) begin
                if ($time - data_rise < min_scl_high)
                    min_scl_high = $time - data_rise;
                data_fall = $time;
                data_rise = 0;
            end
            if (final_ack_rise != 0 && final_ack_end == 0)
                final_ack_end = $time;
            ack_low = slots < 36 && !transfer_nacked && slots % 9 == 8 &&
                      !(starts == nack_transfer && slots / 9 == nack_byte);
        end else begin
            ack_low = 0;
        end
    end

    always @(posedge sda) begin
        if (capture && in_transfer && sda === 1'b1 && scl === 1'b1) begin
            check(transfer_nacked || slots == 36,
                  $sformatf("STOP after %0d of 36 SCL bits", slots));
            if (!transfer_nacked && slots == 36) begin
                writes++;
                if (writes <= SDR_WRITES)
                    recipe[writes] = shifted[23:0];
            end
            stops++;
            $fdisplay(trace_file, "%m,%s,%0d,%0d,%0d,%0d,%08h,%0d",
                      label, starts, transfer_at, $time, slots, shifted, transfer_nacked);
            previous_stop = $time;
            in_transfer = 0;
        end
    end

    always @(negedge clk) begin
        if (capture && $time > accepted_at) begin
            if (error === 1'b1) saw_error = 1;
            if ((written === 1'b1 || stable === 1'b1) &&
                final_ack_end == 0 && !early_written_reported) begin
                check(0, $sformatf("success before final ACK completed, STARTs=%0d STOPs=%0d", starts, stops));
                early_written_reported = 1;
            end
            if (written === 1'b1 && first_written_at == 0)
                first_written_at = $time;
        end
    end

    task automatic boot(input int trace_fd);
        trace_file = trace_fd;
        repeat (6) @(negedge clk);
        rst_n = 1;
        repeat (6) @(negedge clk);
    endtask

    task automatic launch(input string name, input bit new_hdr, input bit new_sdr30,
                          input logic [7:0] new_gain, input int fail_transfer = 0,
                          input int fail_byte = -1);
        label = name;
        fork : ready_deadline
            begin wait (ready === 1'b1); end
            begin #100000; end
        join_any
        disable ready_deadline;
        @(negedge clk);
        check(ready === 1'b1 && locked, "START unavailable within 100 us");
        check(scl === 1'b1 && sda === 1'b1, "I2C bus is not idle before START request");
        requested_hdr = new_hdr;
        requested_sdr30 = new_sdr30;
        requested_gain = new_gain;
        hdr = new_hdr;
        sdr30 = new_sdr30;
        gain = new_gain;
        expected_writes = new_hdr ? HDR_WRITES : SDR_WRITES;
        starts = 0;
        stops = 0;
        writes = 0;
        in_transfer = 0;
        transfer_nacked = 0;
        nack_transfer = fail_transfer;
        nack_byte = fail_byte;
        nack_count = 0;
        final_ack_rise = 0;
        final_ack_end = 0;
        first_written_at = 0;
        previous_stop = 0;
        wake_gap = 0;
        min_scl_high = '1;
        min_scl_low = '1;
        accepted_at = $time + CLK_NS / 2;
        low_at = xclr === 1'b0 ? accepted_at : 0;
        release_at = 0;
        saw_error = 0;
        early_written_reported = 0;
        capture = 1;
        start = 1;
        $display("LAUNCH %m [%s] accepted=%0d ns hdr=%0d sdr30=%0d gain=%02h nack=%0d/%0d",
                 label, accepted_at, hdr, sdr30, gain, nack_transfer, nack_byte);
        @(negedge clk);
        start = 0;
    endtask

    task automatic mutate_busy(input int after_start);
        wait (starts >= after_start);
        @(negedge clk);
        check(ready === 1'b0, "START ready was high while configuration was busy");
        hdr = !requested_hdr;
        sdr30 = !requested_sdr30;
        gain = requested_gain ^ 8'hff;
        start = 1;
        @(negedge clk);
        start = 0;
    endtask

    task automatic require_register(input logic [15:0] address, input logic [7:0] expected);
        logic [7:0] last_value;
        bit found;
        found = 0;
        for (int i = 1; i <= writes && i <= SDR_WRITES; i++) begin
            if (recipe[i][23:8] === address) begin
                found = 1;
                last_value = recipe[i][7:0];
            end
        end
        check(found && last_value === expected,
              $sformatf("reg %04h found=%0d expected=%02h observed=%02h", address, found, expected, last_value));
    endtask

    task automatic success;
        fork : config_deadline
            begin wait ((written === 1'b1 && stops >= expected_writes) || saw_error); end
            begin #(DEFAULT_TIMING ? 220_000_000 : 12_000_000); end
        join_any
        disable config_deadline;
        repeat (12) @(negedge clk);
        check(written === 1'b1 && error === 1'b0 && !saw_error, "configuration did not complete successfully");
        check(starts == expected_writes && writes == expected_writes && stops == expected_writes,
              $sformatf("expected %0d writes, observed START=%0d ACKed=%0d STOP=%0d", expected_writes, starts, writes, stops));
        check(final_ack_rise != 0 && final_ack_end > final_ack_rise && first_written_at >= final_ack_end,
              $sformatf("last ACK rising=%0d falling=%0d first config_written=%0d", final_ack_rise, final_ack_end, first_written_at));
        check(recipe[expected_writes - 1] === 24'h300000 && recipe[expected_writes] === 24'h300200,
              $sformatf("last writes are %06h and %06h", recipe[expected_writes - 1], recipe[expected_writes]));
        check(stable === !requested_hdr, "stable did not match post-configuration mode qualification");
        if (!requested_hdr) begin
            require_register(16'h3024, 8'hca);
            require_register(16'h3025, 8'h08);
            require_register(16'h3026, 8'h00);
            require_register(16'h3028, requested_sdr30 ? 8'h2a : 8'h15);
            require_register(16'h3029, requested_sdr30 ? 8'h04 : 8'h02);
            require_register(16'h3050, requested_sdr30 ? 8'h69 : 8'h08);
            require_register(16'h3051, requested_sdr30 ? 8'h04 : 8'h00);
            require_register(16'h3052, 8'h00);
            require_register(16'h3090, requested_gain);
            require_register(16'h3091, 8'h00);
        end
        if (DEFAULT_TIMING) begin
            check(min_scl_high == HALF * CLK_NS && min_scl_low >= HALF * CLK_NS,
                  $sformatf("125-cycle half-period expected, high min=%0d low min=%0d ns", min_scl_high, min_scl_low));
        end
        $display("CONFIG %m [%s] starts=%0d writes=%0d stops=%0d xclr_low=%0d ns wake=%0d ns high_min=%0d ns low_min=%0d ns ack_rise=%0d ns ack_end=%0d ns done_sample=%0d ns",
                 label, starts, writes, stops, release_at-low_at, wake_gap, min_scl_high,
                 min_scl_low, final_ack_rise, final_ack_end, first_written_at);
    endtask

    task automatic require_nack;
        fork : nack_deadline
            begin wait (nack_count != 0 && stops >= nack_transfer && (saw_error || ready)); end
            begin #12_000_000; end
        join_any
        disable nack_deadline;
        repeat (400) @(negedge clk);
        check(nack_count == 1 && writes == nack_transfer - 1 && starts == nack_transfer && stops == nack_transfer,
              $sformatf("NACK ordinal=%0d byte=%0d got START=%0d ACKed=%0d STOP=%0d nack_count=%0d",
                        nack_transfer, nack_byte, starts, writes, stops, nack_count));
        check(saw_error && written === 1'b0 && stable === 1'b0, "NACK failed to report an error without success");
        $display("NACK %m [%s] ordinal=%0d byte=%0d error=%0d ready=%b", label, nack_transfer, nack_byte, saw_error, ready);
    endtask

    task automatic snapshot(input int bank);
        saved_length[bank] = writes;
        for (int i = 1; i <= writes && i <= SDR_WRITES; i++)
            saved_recipe[bank][i] = recipe[i];
    endtask

    task automatic compare_snapshot(input int bank);
        check(writes == saved_length[bank], "recipe length changed across equivalent requests");
        for (int i = 1; i <= writes && i <= saved_length[bank] && i <= SDR_WRITES; i++)
            check(recipe[i] === saved_recipe[bank][i],
                  $sformatf("recipe changed at write %0d from %06h to %06h", i, saved_recipe[bank][i], recipe[i]));
    endtask

    task automatic cut(input string reason);
        @(negedge clk);
        $display("CUT %m [%s] %s t=%0d ns START=%0d STOP=%0d slot=%0d",
                 label, reason, $time, starts, stops, slots);
        capture = 0;
        ack_low = 0;
        case (reason)
            "reset": rst_n = 0;
            "lock": locked = 0;
            "abort": abort = 1;
            "source_fault": source_fault = 1;
            default: $fatal(1, "unknown cut reason %s", reason);
        endcase
        repeat (8) @(negedge clk);
        check(written === 1'b0 && stable === 1'b0, "interruption retained configuration success");
        rst_n = 1;
        locked = 1;
        abort = 0;
        source_fault = 0;
        repeat (8) @(negedge clk);
        quiet_edges = 0;
        watch_quiet = 1;
        repeat (400) @(negedge clk);
        watch_quiet = 0;
        check(quiet_edges == 0 && scl === 1'b1 && sda === 1'b1,
              $sformatf("I2C did not stay idle after interruption, edges=%0d", quiet_edges));
        check(written === 1'b0 && stable === 1'b0, "configuration became valid without another START");
    endtask

    task automatic start_unlocked;
        label = "unlocked_start";
        @(negedge clk);
        locked = 0;
        repeat (4) @(negedge clk);
        quiet_edges = 0;
        watch_quiet = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        repeat (100) @(negedge clk);
        locked = 1;
        repeat (400) @(negedge clk);
        watch_quiet = 0;
        check(quiet_edges == 0 && written === 1'b0 && stable === 1'b0,
              "START asserted without lock was accepted or replayed");
    endtask

    task automatic pair(input bit good, input bit expected_stable);
        @(negedge clk);
        pair_ok = good;
        pair_event = 1;
        @(negedge clk);
        pair_event = 0;
        repeat (3) @(negedge clk);
        check(stable === expected_stable,
              $sformatf("pair good=%0d expected stable=%0d observed=%b", good, expected_stable, stable));
    endtask

    task automatic warmup;
        repeat (7) pair(1, 0);
        pair(1, 1);
    endtask
endmodule

module tb_camera_config #(parameter bit DEFAULT_TIMING = 0);
    logic clk = 0;
    always #20 clk = !clk;

    camera_config_eye #(DEFAULT_TIMING) left(clk);
    camera_config_eye right(clk);

    string scenario, trace_path;
    int trace_file, nack_transfer, nack_byte;
    initial begin
        #(DEFAULT_TIMING ? 240_000_000 : 45_000_000);
        $display("CASE_RESULT FAIL watchdog %s", scenario);
        $fatal(1, "bounded simulation time exceeded");
    end

    initial begin
        if (!$value$plusargs("CASE=%s", scenario) || !$value$plusargs("TRACE=%s", trace_path))
            $fatal(1, "CASE and TRACE plusargs are required");
        trace_file = $fopen(trace_path, "w");
        if (trace_file == 0) $fatal(1, "could not open bus trace");
        $fdisplay(trace_file, "eye,launch,ordinal,start_ns,stop_ns,scl_slots,wire_hex,nacked");
        fork
            left.boot(trace_file);
            right.boot(trace_file);
        join

        case (scenario)
            "dual_same", "dual_stagger", "dual_nack", "dual_lock": begin
                fork
                    begin
                        left.launch("left_sdr60", 0, 0, 8'h24, scenario == "dual_nack" ? 47 : 0, 2);
                        left.mutate_busy(8);
                        if (scenario == "dual_nack") begin
                            left.require_nack();
                            left.launch("left_nack_retry", 0, 0, 8'h32);
                        end else if (scenario == "dual_lock") begin
                            wait (left.starts == 11 && left.slots == 5);
                            left.cut("lock");
                            left.launch("left_lock_retry", 0, 0, 8'h32);
                        end
                        left.success();
                    end
                    begin
                        if (scenario != "dual_same") repeat (137) @(negedge clk);
                        right.launch("right_sdr30", 0, 1, 8'h61);
                        right.mutate_busy(23);
                        right.success();
                    end
                join
                right.check(right.stable === 1'b1 && right.writes == 203,
                            "peer did not remain configured through left recovery");
            end
            "sdr_roundtrip": begin
                left.start_unlocked();
                for (int round = 0; round < 4; round++) begin
                    left.launch($sformatf("sdr_round_%0d", round), 0, round % 2, round % 2 ? 8'h61 : 8'h24);
                    if (round < 2) left.mutate_busy(10);
                    left.success();
                    if (round < 2) left.snapshot(round % 2);
                    else left.compare_snapshot(round % 2);
                    left.cut(round == 3 ? "lock" : "abort");
                end
            end
            "nack": begin
                if (!$value$plusargs("NACK_TRANSFER=%d", nack_transfer) ||
                    !$value$plusargs("NACK_BYTE=%d", nack_byte))
                    $fatal(1, "NACK_TRANSFER and NACK_BYTE plusargs are required");
                left.launch("nack_probe", 0, 0, 8'h24, nack_transfer, nack_byte);
                left.require_nack();
                left.launch("nack_retry", 0, 1, 8'h61);
                left.success();
            end
            "wake_abort", "wake_reset", "bit_reset", "bit_lock": begin
                left.launch("interrupt_probe", 0, 0, 8'h24);
                if (scenario == "wake_abort" || scenario == "wake_reset") begin
                    wait (left.stops == 202);
                    repeat (20) @(negedge clk);
                    left.check(left.starts == 202 && left.written === 1'b0, "XMSTA or done arrived inside the wake interval");
                    left.cut(scenario == "wake_abort" ? "abort" : "reset");
                end else begin
                    wait (left.starts == 7 && left.slots == 5);
                    left.cut(scenario == "bit_lock" ? "lock" : "reset");
                end
                left.launch("interrupt_retry", 0, 1, 8'h61);
                left.success();
            end
            "hdr_recipe": begin
                left.launch("hdr_baseline", 1, 0, 8'h24);
                left.success();
                left.snapshot(0);
                repeat (7) left.pair(1, 0);
                repeat (13) @(negedge clk);
                left.check(left.stable === 1'b0, "pair_ok without pair_event qualified HDR");
                left.pair(0, 0);
                left.warmup();
                left.cut("abort");
                left.launch("hdr_sdr30_and_gain", 1, 1, 8'h61);
                left.mutate_busy(8);
                left.success();
                left.compare_snapshot(0);
                left.warmup();
            end
            "hdr_abort", "hdr_fault": begin
                left.launch("hdr_interruption", 1, 0, 8'h24);
                left.success();
                repeat (4) left.pair(1, 0);
                left.cut(scenario == "hdr_abort" ? "abort" : "source_fault");
                repeat (8) left.pair(1, 0);
                left.launch("hdr_retry", 1, 1, 8'h61);
                left.success();
                left.warmup();
                if (scenario == "hdr_fault") left.cut("source_fault");
            end
            "production_defaults": begin
                if (!DEFAULT_TIMING) $fatal(1, "production_defaults requires DEFAULT_TIMING=1");
                left.launch("default_sdr60", 0, 0, 8'h24);
                left.success();
            end
            default: $fatal(1, "unknown scenario %s", scenario);
        endcase

        $fclose(trace_file);
        if (left.failures + right.failures == 0) begin
            $display("CASE_RESULT PASS %s", scenario);
            $finish;
        end else begin
            $display("CASE_RESULT FAIL %s assertions=%0d", scenario, left.failures + right.failures);
            $fatal(1, "camera configuration contract failed");
        end
    end
endmodule
