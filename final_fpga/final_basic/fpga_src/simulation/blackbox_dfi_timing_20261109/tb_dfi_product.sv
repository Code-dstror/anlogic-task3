`timescale 1ns/1ps

module tb_dfi_product;
    import dfi_araw_oracle::*;

    localparam payload_t RAW = 160'h045183ce_7c9d5a6b_1234cdef_836258f1_0a9be372;
    localparam logic [127:0] IDENTITY = 128'h3c42_78e1_a196_b2d7_5f90_a36e_416b_905c;
    localparam logic [31:0] RETIRE_STATUS = 32'h6c51_228f;

    bit clk = 0, user_clk = 0;
    logic cold_n = 1;
    wire state_n, data_n;
    descriptor_t desc;
    bit offer = 0;
    wire source_record_ready;
    wire start_valid = offer && source_record_ready;
    wire start_ready;
    axis_t payload = '0;
    bit payload_valid = 0;
    wire payload_ready;
    axis_t record_data;
    wire record_valid, record_ready, done, drained;

    wire source_record_valid = offer && start_ready;
    wire source_cancel, source_retire_valid;
    wire [127:0] source_retire_identity;
    wire [31:0] source_retire_status;
    bit source_retire_ready = 0, source_done = 0;
    wire source_drained = source_done && drained;

    wire user_record_valid;
    bit user_record_ready = 0;
    wire [31:0] user_length;
    wire [127:0] user_identity;
    axis_t user_axis;
    wire user_axis_valid;
    bit user_axis_ready = 0;
    wire user_done_valid, user_done_ok, user_drained;
    bit user_retire_valid = 0;
    wire user_retire_ready;
    wire source_busy, user_busy, source_fault, user_fault, source_reset_done, user_reset_done;

    int source_records = 0, source_completions = 0, source_retirements = 0;
    int user_records = 0, user_bytes = 0, user_safes = 0;
    bit user_success = 0;
    bit user_stalled = 0;
    axis_t held_user_beat;

    dfi_araw_ports carrier (.*);

    product_record_cdc cdc (
        .s_clk(clk), .m_clk(user_clk), .s_cold_rst_n(cold_n), .m_cold_rst_n(cold_n),
        .s_record_valid(source_record_valid), .s_record_ready(source_record_ready),
        .s_record_length(RECORD_BYTES), .s_record_identity(IDENTITY),
        .s_axis_data(record_data.data), .s_axis_keep(record_data.keep),
        .s_axis_valid(record_valid), .s_axis_last(record_data.last), .s_axis_ready(record_ready),
        .s_done_valid(source_done), .s_done_ok(source_done), .s_drained(source_drained), .s_cancel(source_cancel),
        .s_retire_valid(source_retire_valid), .s_retire_ready(source_retire_ready),
        .s_retire_identity(source_retire_identity), .s_retire_status(source_retire_status),
        .m_record_valid(user_record_valid), .m_record_ready(user_record_ready),
        .m_record_length(user_length), .m_record_identity(user_identity),
        .m_axis_data(user_axis.data), .m_axis_keep(user_axis.keep),
        .m_axis_valid(user_axis_valid), .m_axis_last(user_axis.last), .m_axis_ready(user_axis_ready),
        .m_done_valid(user_done_valid), .m_drained(user_drained), .m_done_ok(user_done_ok), .m_cancel(1'b0),
        .m_retire_valid(user_retire_valid), .m_retire_ready(user_retire_ready),
        .m_retire_identity(IDENTITY), .m_retire_status(RETIRE_STATUS),
        .s_busy(source_busy), .m_busy(user_busy), .s_fault(source_fault), .m_fault(user_fault),
        .s_reset_done(source_reset_done), .m_reset_done(user_reset_done)
    );

    always #3.751 clk = !clk;
    initial begin
        #1.217;
        forever begin
            #6 user_clk = 1;
            #2 user_clk = 0;
        end
    end

    task automatic fail(input string message);
        $display("FAIL dfi_product t=%0t %s", $time, message);
        $fatal(1);
    endtask

    always @(posedge clk or negedge cold_n) begin
        if (!cold_n) source_done <= 0;
        else if (source_reset_done) begin
            if ({source_fault, source_cancel} !== 2'b00) fail("source fault/cancel on legal record");
            if (source_record_valid && source_record_ready) source_records <= source_records + 1;
            if (done !== (record_valid && record_ready && record_data.last))
                fail("formatter DONE does not identify the accepted source tail");
            if (done) begin
                source_done <= 1;
                source_completions <= source_completions + 1;
            end
            if (source_retire_valid) begin
                if (user_safes != 1 || !source_done) fail("source retirement preceded SAFE or source completion");
                if ({source_retire_identity, source_retire_status} !== {IDENTITY, RETIRE_STATUS})
                    fail("returned source identity/status mismatch");
                if (source_retire_ready) begin
                    source_done <= 0;
                    source_retirements <= source_retirements + 1;
                end
            end
            if (source_done && !source_retire_ready && source_record_ready !== 1'b0)
                fail("CDC allowed replacement of the owned record before source retirement");
        end
    end

    always @(posedge user_clk) begin : user_scoreboard
        int bytes_at_sample;
        if (user_reset_done) begin
            if (user_fault !== 1'b0) fail("USER fault on legal record");
            if (user_record_valid && user_record_ready) user_records <= user_records + 1;
            if (user_stalled && (user_axis_valid !== 1'b1 || !axis_matches(user_axis, held_user_beat)))
                fail("USER AXIS changed while stalled");
            user_stalled <= user_axis_valid && !user_axis_ready;
            if (user_axis_valid) held_user_beat <= user_axis;

            bytes_at_sample = user_bytes;
            if (user_axis_valid && user_axis_ready) begin
                if (user_records != 1) fail("USER AXIS advanced without an accepted record descriptor");
                bytes_at_sample += $countones(user_axis.keep);
                user_bytes <= bytes_at_sample;
            end
            if (user_done_valid && user_drained) begin
                if (user_done_ok !== 1'b1 || bytes_at_sample != int'(RECORD_BYTES))
                    fail($sformatf("USER DONE/drained with ok=%b and %0d accepted bytes", user_done_ok, bytes_at_sample));
                user_success <= 1;
            end
            if (user_retire_valid && user_retire_ready) begin
                if (!user_success) fail("USER SAFE before success terminal");
                user_safes <= user_safes + 1;
            end
        end
    end

    task automatic issue_source;
        @(negedge clk);
        offer = 1;
        do @(posedge clk); while ({start_valid, start_ready, source_record_valid, source_record_ready} !== 4'b1111);
        @(negedge clk);
        offer = 0;
        for (int beat = 0; beat < 2; beat++) begin
            payload = payload_beat(RAW, beat);
            payload_valid = 1;
            do @(posedge clk); while (payload_ready !== 1'b1);
            @(negedge clk);
        end
        payload_valid = 0;
    endtask

    task automatic accept_user;
        axis_t expected;
        do @(posedge user_clk); while (user_record_valid !== 1'b1);
        repeat (4) begin
            if ({user_record_valid, user_length, user_identity} !== {1'b1, RECORD_BYTES, IDENTITY})
                fail("USER descriptor changed under READY stall");
            @(posedge user_clk);
        end
        @(negedge user_clk);
        user_record_ready = 1;
        @(posedge user_clk);
        if ({user_record_valid, user_length, user_identity} !== {1'b1, RECORD_BYTES, IDENTITY})
            fail("USER descriptor handshake payload mismatch");
        @(negedge user_clk);
        user_record_ready = 0;

        do @(posedge user_clk); while (user_axis_valid !== 1'b1);
        repeat (4) @(posedge user_clk);
        @(negedge user_clk);
        user_axis_ready = 1;
        for (int beat = 0; beat < RECORD_BEATS; beat++) begin
            do @(posedge user_clk); while (user_axis_valid !== 1'b1);
            expected = record_beat(desc, RAW, beat);
            if (!axis_matches(user_axis, expected))
                fail($sformatf("USER beat %0d got data/keep/last=%032x/%04x/%b expected=%032x/%04x/%b",
                               beat, user_axis.data, user_axis.keep, user_axis.last,
                               expected.data, expected.keep, expected.last));
        end
        @(negedge user_clk);
        user_axis_ready = 0;
        wait (user_success);
        $display("OBS dfi_product USER_DONE bytes=%0d t=%0t", user_bytes, $time);
        @(negedge user_clk);
        user_retire_valid = 1;
        do @(posedge user_clk); while (user_retire_ready !== 1'b1);
        $display("OBS dfi_product USER_SAFE t=%0t", $time);
        @(negedge user_clk);
        user_retire_valid = 0;
    endtask

    task automatic retire_source;
        do @(posedge clk); while (source_retire_valid !== 1'b1);
        repeat (4) begin
            if ({source_retire_valid, source_retire_identity, source_retire_status} !==
                {1'b1, IDENTITY, RETIRE_STATUS}) fail("held source retirement changed during READY stall");
            @(posedge clk);
        end
        @(negedge clk);
        source_retire_ready = 1;
        @(posedge clk);
        if ({source_retire_valid, source_retire_identity, source_retire_status} !==
            {1'b1, IDENTITY, RETIRE_STATUS}) fail("source retirement handshake payload mismatch");
        $display("OBS dfi_product SOURCE_RETIRE t=%0t", $time);
        @(negedge clk);
        source_retire_ready = 0;
    endtask

    initial begin
        desc = descriptor(32'h7ca2_49d6, 1);
        #1 cold_n = 0;
        #300 cold_n = 1;
        wait (source_reset_done === 1'b1 && user_reset_done === 1'b1);
        fork
            issue_source();
            accept_user();
            retire_source();
        join
        wait ({source_busy, user_busy} === 2'b00);
        if (source_records != 1 || source_completions != 1 || source_retirements != 1 ||
            user_records != 1 || user_bytes != int'(RECORD_BYTES) || user_safes != 1)
            fail("descriptor, data or retirement counts disagree");
        $display("PASS dfi_product descriptor=%0d bytes=%0d source_done=%0d USER_SAFE=%0d SOURCE_RETIRE=%0d official_fifo",
                 user_records, user_bytes, source_completions, user_safes, source_retirements);
        $finish;
    end

    initial begin
        #100000;
        fail($sformatf("watchdog reset=%b%b source record/done/retired=%0d/%0d/%0d user descriptor/bytes/safe=%0d/%0d/%0d done=%b%b%b",
                       source_reset_done, user_reset_done, source_records, source_completions, source_retirements,
                       user_records, user_bytes, user_safes, user_done_valid, user_done_ok, user_drained));
    end
endmodule
