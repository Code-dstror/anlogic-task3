`timescale 1ns/1ps

interface sensor_config_pins(input wire clk);
    bit rst_n=0, start=0, clock_locked=0, abort_config=0, source_fault=0;
    bit hdr=0, sdr_30=0, pair_event=0, pair_ok=0;
    bit [7:0] gain=0;
    wire ready, xclr, scl, written, stable, error;
    tri1 sda;
endinterface

// The test slave observes only the pins. It recognizes START, each ninth
// clock, and STOP, and drives an open-drain ACK while the master releases SDA.
module sensor_config_probe #(
    parameter int EYE=0, HALF_PERIOD=4,
    parameter int SDR_HOLD=5, SDR_RELEASE=7, SDR_WAKE=41,
    parameter int HDR_HOLD=9, HDR_RELEASE=11, HDR_WAKE=43
)(sensor_config_pins pins);
    int cycle=0, accepted_cycle=0, release_cycle=0, scl_edge_cycle=0;
    int standby_stop=0, wake_gap=0, starts=0, stops=0, writes=0;
    int bits_seen=0, bytes_seen=0, nacks=0, nack_write=-1, nack_byte=0;
    int recipe_length=203, hold_cycles=0, release_cycles=0, wake_cycles=0;
    bit active=0, ack_drive=0, saw_nack=0, stop_clock=0;
    bit previous_scl=1, previous_sda=1, previous_xclr=0;
    bit expected_hdr=0, expected_sdr_30=0;
    bit [7:0] expected_gain=0;
    reg [31:0] packet=0;
    wire [7:0] oracle_index = 8'(stops);
    wire [23:0] legacy_sdr, legacy_hdr;

    frozen_imx415_mode_table legacy_sdr_table(.i_index(oracle_index), .o_register(legacy_sdr));
    frozen_imx415_hdr2_recipe_rom legacy_hdr_table(.i_index(oracle_index), .o_register(legacy_hdr),
        .o_wait_24ms(), .o_last());
    assign pins.sda = ack_drive ? 1'b0 : 1'bz;

    function automatic [31:0] expected_packet();
        reg [23:0] word;
        word = legacy_sdr;
        // Reset-applied gain and two trailing commands from old imx415_config.
        case (stops)
            51: word[7:0] = expected_gain;
            52: word[7:0] = 8'h00;
            201: word = 24'h300000;
            202: word = 24'h300200;
            default: begin end
        endcase
        if (expected_sdr_30) begin
            // HMAX 533 -> 1066. VMAX stays 2250, so half the old integration
            // lines preserves the integration time at twice the line period.
            case (stops)
                17: word[7:0] = 8'h2a;
                18: word[7:0] = 8'h04;
                33: word[7:0] = 8'h69;
                34: word[7:0] = 8'h04;
                35: word[7:0] = 8'h00;
                default: begin end
            endcase
        end
        expected_packet = {8'h34, expected_hdr ? legacy_hdr : word};
    endfunction

    task automatic check(input bit ok, input string message);
        if (!ok)
            $fatal(1, "eye=%0d cycle=%0d write=%0d %s", EYE, cycle, stops, message);
    endtask

    task automatic begin_packet();
        check(!active && starts==stops && starts<recipe_length, "unexpected I2C START");
        check(pins.written===1'b0 && pins.stable===1'b0, "ready before last ACK");
        if (starts==0)
            check(cycle-release_cycle>=release_cycles && cycle-release_cycle<=release_cycles+2,
                "XCLR release wait differs from the selected mode");
        if (starts==recipe_length-1) begin
            check(standby_stop!=0, "no ACKed STANDBY cancel before XMSTA");
            wake_gap = cycle-standby_stop;
            check(wake_gap>=wake_cycles && wake_gap<=wake_cycles+2*HALF_PERIOD+4,
                $sformatf("STANDBY STOP to XMSTA START gap %0d, expected at least %0d",
                    wake_gap, wake_cycles));
        end
        active=1;
        scl_edge_cycle=cycle;
        starts++;
        bits_seen=0;
        bytes_seen=0;
        packet=0;
        saw_nack=0;
        stop_clock=0;
    endtask

    task automatic end_packet();
        reg [31:0] expected;
        check(active && stop_clock && bits_seen==0, "malformed I2C STOP");
        check(cycle-scl_edge_cycle==HALF_PERIOD, "wrong I2C STOP hold");
        check(saw_nack==(stops==nack_write), "unexpected write ACK status");
        check(bytes_seen==(saw_nack ? nack_byte : 4), "incorrect number of I2C bytes");
        expected=expected_packet() >> (8*(4-bytes_seen));
        check(packet===expected, $sformatf("I2C packet %08h expected %08h", packet, expected));
        if (saw_nack) nacks++;
        else begin
            writes++;
            if (stops==recipe_length-2) standby_stop=cycle;
        end
        stops++;
        active=0;
    endtask

    // Sample at system-clock edges, after the previous edge's pin transitions
    // have settled. A complete SCL low interval remains for slave ACK setup.
    always @(posedge pins.clk) begin
        cycle++;
        if (pins.start && pins.ready && pins.clock_locked && !pins.abort_config)
            accepted_cycle=cycle;
        if (pins.rst_n && (pins.written || pins.stable))
            check(writes==recipe_length && starts==stops && nacks==0,
                "configuration published before all physical writes completed");
        if (!pins.rst_n || !pins.xclr) begin
            active=0;
            ack_drive=0;
            previous_xclr=0;
            previous_scl=1;
            previous_sda=1;
        end else begin
            check(!$isunknown({pins.scl,pins.sda}), "I2C line is unknown");
            if (!previous_xclr) begin
                release_cycle=cycle;
                check(cycle-accepted_cycle-1==hold_cycles, "XCLR reset hold differs from the selected mode");
            end
            if (previous_scl && pins.scl && previous_sda!=pins.sda) begin
                if (pins.sda) end_packet();
                else begin_packet();
            end
            if (active && previous_scl!=pins.scl) begin
                check(cycle-scl_edge_cycle==HALF_PERIOD, "wrong I2C clock half-period");
                scl_edge_cycle=cycle;
            end
            if (active && previous_scl && !pins.scl) begin
                if (bits_seen==8) begin
                    check(pins.sda===1'b1, "master did not release SDA before ACK");
                    ack_drive=!(stops==nack_write && bytes_seen==nack_byte);
                end else ack_drive=0;
            end
            if (active && !previous_scl && pins.scl) begin
                if (bits_seen==8) begin
                    saw_nack=(stops==nack_write && bytes_seen==nack_byte);
                    check(pins.sda===saw_nack, "wrong level on the ninth I2C clock");
                    bits_seen=0;
                end else if (bytes_seen==4 || saw_nack) begin
                    check(!stop_clock && pins.sda===1'b0, "missing STOP setup");
                    stop_clock=1;
                end else begin
                    packet={packet[30:0],pins.sda};
                    bits_seen++;
                    if (bits_seen==8) bytes_seen++;
                end
            end
            previous_xclr=1;
            previous_scl=pins.scl;
            previous_sda=pins.sda;
        end
    end

    task automatic idle(input bit faulted);
        check(pins.ready===1'b1 && pins.error===faulted, "unexpected idle or fault status");
        check(!pins.written && !pins.stable && !pins.xclr, "stale readiness after reset/fault");
        check(pins.scl===1'b1 && pins.sda===1'b1, "I2C not released after reset/fault");
    endtask

    task automatic release_reset();
        repeat (3) @(negedge pins.clk);
        pins.rst_n=1;
        @(negedge pins.clk);
        idle(0);
    endtask

    task automatic boot(input bit hdr, input bit slow, input bit [7:0] gain,
                        input int fail_write=-1, input int fail_byte=0);
        @(negedge pins.clk);
        check(pins.ready===1'b1 && pins.clock_locked, "boot without START readiness");
        expected_hdr=hdr;
        expected_sdr_30=slow;
        expected_gain=gain;
        recipe_length=hdr ? 139 : 203;
        hold_cycles=hdr ? HDR_HOLD : SDR_HOLD;
        release_cycles=hdr ? HDR_RELEASE : SDR_RELEASE;
        wake_cycles=hdr ? HDR_WAKE : SDR_WAKE;
        starts=0;
        stops=0;
        writes=0;
        nacks=0;
        standby_stop=0;
        wake_gap=0;
        nack_write=fail_write;
        nack_byte=fail_byte;
        pins.hdr=hdr;
        pins.sdr_30=slow;
        pins.gain=gain;
        pins.start=1;
        @(negedge pins.clk);
        pins.start=0;
        check(!pins.ready && !pins.xclr && !pins.written && !pins.stable,
            "START did not enter reset hold");
    endtask

    task automatic wait_written();
        while (!pins.written && !pins.error) @(negedge pins.clk);
        check(pins.written && !pins.error && pins.xclr && !pins.ready,
            "all writes did not publish configuration");
        check(writes==recipe_length && nacks==0 && wake_gap>=wake_cycles,
            "write count or wake wait differs from recipe");
        check(pins.stable===!expected_hdr, "wrong stable status after final ACK");
    endtask

    task automatic wait_nack();
        while (!pins.error && !pins.written) @(negedge pins.clk);
        idle(1);
        check(starts==nack_write+1 && stops==starts && nacks==1 && writes==nack_write,
            "NACK did not stop configuration at the injected byte");
        repeat (8) @(negedge pins.clk);
        idle(1);
        $display("CASE: eye=%0d NACK write=%0d byte=%0d acknowledged_writes=%0d",
            EYE, nack_write, nack_byte, writes);
    endtask

    task automatic pair(input bit good);
        @(negedge pins.clk);
        pins.pair_ok=good;
        pins.pair_event=1;
        @(negedge pins.clk);
        pins.pair_event=0;
    endtask

    task automatic qualify_hdr();
        repeat (7) begin
            pair(1);
            check(pins.written && !pins.stable, "HDR qualified before eight consecutive good pairs");
        end
        pair(1);
        check(pins.written && pins.stable, "HDR did not qualify on pair eight");
    endtask
endmodule

module tb_sensor_config;
    bit clk=0;
    always #20 clk=~clk;
    sensor_config_pins a(clk), b(clk);
    sensor_config_probe eye0(a);
    sensor_config_probe #(.EYE(1), .HALF_PERIOD(125), .SDR_HOLD(250000),
        .SDR_RELEASE(250000), .SDR_WAKE(625000)) eye1(b);

    imx415_sensor_config #(.I2C_HALF_PERIOD(4), .SDR_RESET_HOLD_CYCLES(5),
        .SDR_RELEASE_WAIT_CYCLES(7), .SDR_WAKE_CYCLES(41), .HDR_RESET_HOLD_CYCLES(9),
        .HDR_RELEASE_WAIT_CYCLES(11), .HDR_REGULATOR_WAIT_CYCLES(43)) dut0 (
        .i_clk(clk), .i_rst_n(a.rst_n), .i_start(a.start), .o_start_ready(a.ready),
        .i_clock_locked(a.clock_locked), .i_abort(a.abort_config), .i_source_fault(a.source_fault),
        .i_hdr(a.hdr), .i_sdr_30(a.sdr_30), .i_gain_code(a.gain),
        .i_pair_event(a.pair_event), .i_pair_ok(a.pair_ok), .o_xclr(a.xclr),
        .o_scl(a.scl), .io_sda(a.sda), .o_config_written(a.written), .o_stable(a.stable),
        .o_error(a.error), .o_register_index(), .o_rx_diag_cfg());
    // Use the production timing defaults on this independent bus.
    imx415_sensor_config dut1 (
        .i_clk(clk), .i_rst_n(b.rst_n), .i_start(b.start), .o_start_ready(b.ready),
        .i_clock_locked(b.clock_locked), .i_abort(b.abort_config), .i_source_fault(b.source_fault),
        .i_hdr(b.hdr), .i_sdr_30(b.sdr_30), .i_gain_code(b.gain),
        .i_pair_event(b.pair_event), .i_pair_ok(b.pair_ok), .o_xclr(b.xclr),
        .o_scl(b.scl), .io_sda(b.sda), .o_config_written(b.written), .o_stable(b.stable),
        .o_error(b.error), .o_register_index(), .o_rx_diag_cfg());

    initial begin
        fork
            begin
                eye0.release_reset();
                a.start=1;
                repeat (5) begin
                    @(negedge clk);
                    eye0.idle(0);
                end
                a.start=0;
                a.clock_locked=1;
                eye0.boot(0,0,8'h2c,0,1);
                eye0.wait_nack();
                eye0.boot(0,1,8'h31,101,2);
                eye0.wait_nack();
                eye0.boot(1,1,8'h28,138,4);
                eye0.wait_nack();

                eye0.boot(1,1,8'h49);
                wait (eye0.active);
                @(negedge clk);
                a.hdr=0;
                a.sdr_30=0;
                a.gain=8'hde;
                a.start=1;
                repeat (8) eye0.pair(1);
                a.start=0;
                eye0.wait_written();
                repeat (3) eye0.pair(1);
                eye0.pair(0);
                eye0.qualify_hdr();
                eye0.pair(0);
                eye0.check(a.written && !a.stable, "bad pair did not invalidate HDR stability");
                eye0.qualify_hdr();
                a.source_fault=1;
                @(negedge clk);
                eye0.idle(1);
                a.source_fault=0;
                $display("CASE: eye=0 HDR writes=139 bad_pair_requalification=8 source_fault=PASS wake_cycles=%0d",
                    eye0.wake_gap);

                eye0.boot(0,0,8'h25);
                wait (eye0.active && eye0.bits_seen>=3);
                @(negedge clk);
                a.abort_config=1;
                @(negedge clk);
                eye0.idle(1);
                eye0.check(eye0.starts==1 && eye0.stops==0, "abort did not interrupt an active write");
                a.abort_config=0;

                eye0.boot(0,0,8'h27);
                wait (eye0.standby_stop!=0);
                repeat (5) @(negedge clk);
                eye0.check(eye0.stops==202 && !a.written && !a.stable, "reset did not target SDR wake");
                a.rst_n=0;
                repeat (45) begin
                    @(negedge clk);
                    eye0.idle(0);
                end
                eye0.check(eye0.starts==202 && eye0.stops==202, "XMSTA transmitted after wake reset");
                a.rst_n=1;
                $display("CASE: eye=0 abort_mid_write=PASS reset_during_wake=PASS");

                // Drop this eye's clock lock during overlapping writes. The
                // other eye must finish its original recipe uninterrupted.
                wait (eye1.writes>=2 && eye1.active);
                eye0.boot(0,0,8'h38);
                wait (eye0.active && eye0.bits_seen>=3);
                @(negedge clk);
                eye0.check(eye1.active && !b.written && !b.error, "second eye was not writing concurrently");
                a.clock_locked=0;
                @(negedge clk);
                eye0.idle(1);
                eye0.check(eye0.starts==1 && eye0.stops==0, "clock loss did not interrupt the write");
                a.clock_locked=1;
                repeat (8) @(negedge clk);
                eye0.idle(1);

                eye0.boot(0,1,8'h52);
                wait (eye0.active);
                @(negedge clk);
                a.hdr=1;
                a.sdr_30=0;
                a.gain=8'he7;
                eye0.wait_written();
                eye0.check(b.xclr && !b.written && !b.error, "short eye waited for the other eye");
                $display("CASE: eye=0 SDR30 writes=203 start_latched=PASS lock_loss_restart=PASS wake_cycles=%0d",
                    eye0.wake_gap);
            end
            begin
                eye1.release_reset();
                b.clock_locked=1;
                eye1.boot(0,0,8'h36);
                wait (eye1.active);
                @(negedge clk);
                b.hdr=1;
                b.sdr_30=1;
                b.gain=8'haf;
                eye1.wait_written();
                $display("CASE: eye=1 SDR60 writes=203 start_latched=PASS wake_cycles=%0d wake_ns=%0d",
                    eye1.wake_gap, 40*eye1.wake_gap);
            end
        join
        repeat (8) @(negedge clk);
        eye0.check(a.written && a.stable && b.written && b.stable, "independent configuration lost");
        $display("RESULT: PASS shared_sensor_config");
        $finish;
    end

    initial begin
        #150_000_000;
        $fatal(1, "shared sensor configuration simulation timeout");
    end
endmodule
