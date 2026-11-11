`timescale 1ns/1ps

module tb_dfi_formatter;
    import dfi_araw_oracle::*;

    localparam payload_t FIRST_PAYLOAD = 160'h956103f4_7ae9521b_de3ea510_18d42fc9_8b5c3167;
    localparam payload_t FRESH_PAYLOAD = 160'hd19702a4_87981ad4_1245e9b0_99ced3f1_b47c8650;

    bit clk = 0, running = 1;
    logic cold_n = 1;
    wire state_n, data_n;
    descriptor_t desc = '0;
    bit start_valid = 0;
    wire start_ready;
    axis_t payload = '0;
    bit payload_valid = 0;
    wire payload_ready;
    axis_t record_data;
    wire record_valid, done, drained;
    bit record_ready = 0;

    bit stalled = 0;
    axis_t held;
    int starts = 0, transfers = 0, completions = 0;

    dfi_araw_ports carrier (.*);

    always #3.751 if (running) clk = !clk;

    task automatic fail(input string message);
        $display("FAIL dfi_formatter t=%0t %s", $time, message);
        $fatal(1);
    endtask

    always @(posedge clk or negedge cold_n) begin
        if (!cold_n) stalled <= 0;
        else begin
            if (!state_n && ((start_valid && start_ready) || record_valid || done))
                fail("formatter activity before R4");
            if (state_n) begin
                if (stalled && (record_valid !== 1'b1 || !axis_matches(record_data, held)))
                    fail("formatter changed a stalled beat");
                if (done !== (record_valid && record_ready && record_data.last))
                    fail("DONE is not the accepted final payload edge");
                if (start_valid && start_ready) starts <= starts + 1;
                if (record_valid && record_ready) transfers <= transfers + 1;
                if (done) completions <= completions + 1;
                stalled <= record_valid && !record_ready;
                if (record_valid) held <= record_data;
            end
        end
    end

    task automatic start_at_r4;
        for (int edge_no = 1; edge_no <= 3; edge_no++) begin
            @(posedge clk);
            if ({data_n, state_n} !== 2'b00) fail("early release at formatter sample");
            #0.001;
            if ({data_n, state_n, record_valid} !== {edge_no == 3, 2'b00})
                fail("wrong formatter state at R1–R3");
            @(negedge clk);
            #0.001;
            if ({data_n, state_n, record_valid} !== {edge_no == 3, edge_no == 3, 1'b0})
                fail("wrong formatter state at F1–F3");
        end
        @(posedge clk);
        if ({start_valid, start_ready} !== 2'b11) fail("first legal START was not accepted at R4");
        @(negedge clk);
        start_valid = 0;
    endtask

    task automatic send_payload(input payload_t raw);
        for (int beat = 0; beat < 2; beat++) begin
            payload = payload_beat(raw, beat);
            payload_valid = 1;
            do @(posedge clk); while (payload_ready !== 1'b1);
            @(negedge clk);
        end
        payload_valid = 0;
    endtask

    task automatic take_record(input descriptor_t value, input payload_t raw);
        axis_t expected;
        do @(posedge clk); while (record_valid !== 1'b1);
        repeat (4) @(posedge clk);
        @(negedge clk);
        record_ready = 1;
        for (int beat = 0; beat < RECORD_BEATS; beat++) begin
            do @(posedge clk); while (record_valid !== 1'b1);
            expected = record_beat(value, raw, beat);
            if (!axis_matches(record_data, expected))
                fail($sformatf("beat %0d got data/keep/last=%032x/%04x/%b expected=%032x/%04x/%b",
                               beat, record_data.data, record_data.keep, record_data.last,
                               expected.data, expected.keep, expected.last));
        end
        #0.001;
        if (drained !== 1'b1) fail("formatter did not drain on accepted tail");
        @(negedge clk);
        record_ready = 0;
    endtask

    initial begin : scenarios
        desc = descriptor(32'h125a_3917, 0);
        start_valid = 1;
        #1 cold_n = 0;
        #40 cold_n = 1;
        start_at_r4();
        fork
            send_payload(FIRST_PAYLOAD);
            take_record(desc, FIRST_PAYLOAD);
        join
        $display("OBS dfi_formatter first_R4_record_done bytes=%0d", RECORD_BYTES);

        @(negedge clk);
        desc = descriptor(32'h125a_3918, 1);
        start_valid = 1;
        do @(posedge clk); while (start_ready !== 1'b1);
        @(negedge clk);
        start_valid = 0;
        do @(posedge clk); while (record_valid !== 1'b1);
        repeat (3) @(posedge clk);
        @(negedge clk);
        running = 0;
        #1 cold_n = 0;
        #0.001;
        if ({state_n, data_n, record_valid, done} !== 4'b0000)
            fail("stopped cold reset failed to withdraw held header");

        desc = descriptor(32'h125a_3919, 1);
        start_valid = 1;
        #45 cold_n = 1;
        #45;
        if ({state_n, data_n, record_valid, done} !== 4'b0000) fail("formatter advanced while stopped");
        running = 1;
        start_at_r4();
        fork
            send_payload(FRESH_PAYLOAD);
            take_record(desc, FRESH_PAYLOAD);
        join
        repeat (4) @(posedge clk);
        if (starts != 3 || transfers != 12 || completions != 2 || record_valid !== 1'b0)
            fail($sformatf("terminal START/AXIS/DONE=%0d/%0d/%0d", starts, transfers, completions));
        $display("PASS dfi_formatter starts=%0d beats=%0d done=%0d R4 first_header_stall stopped_reset fresh_record",
                 starts, transfers, completions);
        $finish;
    end

    initial begin
        #20000;
        fail($sformatf("watchdog START/AXIS/DONE=%0d/%0d/%0d", starts, transfers, completions));
    end
endmodule
