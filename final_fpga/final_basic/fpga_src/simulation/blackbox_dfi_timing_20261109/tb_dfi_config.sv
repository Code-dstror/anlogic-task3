`timescale 1ns/1ps

module tb_dfi_config;
    localparam logic [31:0] SESSION = 32'h3a72_91cf;
    localparam logic [31:0] NEW_SESSION = 32'h706b_c894;
    localparam logic [63:0] DELTA = 64'd1000000;
    localparam logic [31:0] WAIT_NS = 32'd50000000;
    localparam logic [31:0] AGE = 32'd100000000;
    typedef logic [373:0] tuple_t;

    bit pixel_clk = 0;
    bit dfi_clk = 0;
    bit dfi_run = 1;
    logic pixel_rst_n = 1;
    logic dfi_rst_n = 1;
    tuple_t request_data = '0;
    bit request_valid = 0;
    bit request_ok = 0;
    wire request_ready;
    tuple_t ack_data;
    wire ack_valid, ack_ok;
    bit ack_ready = 0;

    wire job_valid;
    wire [31:0] job_session, job_epoch;
    wire [1:0] job_mode;
    wire job_mono;
    wire [63:0] job_delta;
    wire [31:0] job_wait, job_age;
    tuple_t job_snapshot;
    bit job_ready = 0, job_done = 0, job_error = 0, job_busy = 0;

    wire active_valid, active_hdr;
    wire [31:0] active_session, active_epoch;
    tuple_t active_data;
    wire pixel_reset_done, dfi_reset_done;
    wire pixel_busy, dfi_busy, pixel_fault, dfi_fault;
    wire [31:0] stale_ack_count, stale_done_count;
    wire lut_inhibit;

    int jobs = 0, acks = 0;
    bit expect_active = 0, expect_hdr = 0;
    tuple_t active_expected = '0;
    bit check_active = 0;

    PH1_PHY_GSR PH1_PHY_GSR();

    frame_job_config_cdc #(
        .EXT_WIDTH(214), .WIDTH(1920), .HEIGHT(1080), .EXT_STRIPS(4),
        .DEHAZE_LUT_GUARD_ENABLE(0), .EXT_COMBINATIONS(32'd0), .EXT_SUPPORTED(8'h34),
        .COMPACT_EMPTY_EXTENSION_ENABLE(0), .COMPACT_STAGE2_EXTENSION_ENABLE(1),
        .TRUSTED_INPUT(1)
    ) dut (
        .i_pixel_clk(pixel_clk), .i_pixel_rst_n(pixel_rst_n),
        .i_dfi_clk(dfi_clk), .i_dfi_rst_n(dfi_rst_n),
        .s_frontend_applied_data(request_data), .s_frontend_applied_valid(request_valid),
        .s_frontend_applied_ok(request_ok), .s_frontend_applied_ready(request_ready),
        .m_whole_ack_data(ack_data), .m_whole_ack_valid(ack_valid), .m_whole_ack_ok(ack_ok),
        .m_whole_ack_ready(ack_ready), .i_pair_mode(2'd0), .i_mono_enable(1'b1),
        .i_max_delta_ns(DELTA), .i_max_wait_ns(WAIT_NS), .i_max_age_ns(AGE),
        .o_job_config_valid(job_valid), .o_job_session(job_session), .o_job_epoch(job_epoch),
        .o_job_mode(job_mode), .o_job_mono_enable(job_mono), .o_job_max_delta_ns(job_delta),
        .o_job_max_wait_ns(job_wait), .o_job_max_age_ns(job_age), .o_job_config_snapshot(job_snapshot),
        .i_job_config_ready(job_ready), .i_job_config_done(job_done),
        .i_job_config_error(job_error), .i_job_config_busy(job_busy),
        .o_active_valid(active_valid), .o_active_session(active_session), .o_active_epoch(active_epoch),
        .o_active_config(active_data), .o_active_hdr(active_hdr),
        .i_dehaze_lut_valid(1'b0), .i_dehaze_lut_generation(32'd0), .i_dehaze_update_busy(1'b0),
        .o_dehaze_lut_update_inhibit(lut_inhibit), .o_source_reset_done(pixel_reset_done),
        .o_source_busy(pixel_busy), .o_source_fault(pixel_fault), .o_stale_ack_count(stale_ack_count),
        .o_dfi_reset_done(dfi_reset_done), .o_dfi_busy(dfi_busy), .o_dfi_fault(dfi_fault),
        .o_stale_job_done_count(stale_done_count)
    );

    always #5.617 pixel_clk = !pixel_clk;
    always #3.751 if (dfi_run) dfi_clk = !dfi_clk;

    task automatic fail(input string message);
        $display("FAIL dfi_config t=%0t %s", $time, message);
        $fatal(1);
    endtask

    function automatic tuple_t tuple(input logic [31:0] id, session, epoch,
                                     input int schema, input bit hdr);
        logic [213:0] ext;
        ext = '0;
        if (schema == 2) begin
            ext[213] = 1;
            if (hdr) begin
                ext[1:0] = 2;
                ext[42:40] = 4;
                ext[84:81] = 15;
                ext[148:85] = DELTA;
                ext[180:149] = WAIT_NS;
                ext[212:181] = AGE;
            end
        end else if (schema == 1 && hdr) begin
            ext[34] = 1;
            ext[37:35] = 4;
            ext[79:76] = 15;
            ext[143:80] = DELTA;
            ext[175:144] = WAIT_NS;
            ext[207:176] = AGE;
        end
        tuple = '0;
        tuple[31:0] = id;
        tuple[63:32] = session;
        tuple[72:66] = 75;
        tuple[80:74] = 1;
        tuple[159:128] = epoch;
        tuple[373:160] = ext;
    endfunction

    task automatic verify_active;
        if ({active_valid, active_hdr, active_session, active_epoch, active_data} !==
            {expect_active, expect_hdr, active_expected[63:32], active_expected[159:128], active_expected})
            fail($sformatf("ACTIVE active/hdr/session/epoch=%b/%b/%08x/%08x expected=%b/%b/%08x/%08x data=%094x expected=%094x",
                           active_valid, active_hdr, active_session, active_epoch,
                           expect_active, expect_hdr, active_expected[63:32], active_expected[159:128],
                           active_data, active_expected));
    endtask

    always @(posedge dfi_clk) begin
        if (job_valid && job_ready) jobs <= jobs + 1;
        #0.001;
        if (check_active) verify_active();
    end

    always @(posedge pixel_clk) if (ack_valid && ack_ready) acks <= acks + 1;

    task automatic wait_link;
        wait (pixel_reset_done === 1'b1 && dfi_reset_done === 1'b1);
        @(negedge pixel_clk);
        if ({pixel_fault, dfi_fault, lut_inhibit} !== 3'b000) fail("fault or LUT inhibit after reset");
    endtask

    task automatic send_request(input tuple_t value, input bit frontend_ok);
        @(negedge pixel_clk);
        request_data = value;
        request_ok = frontend_ok;
        request_valid = 1;
        do @(posedge pixel_clk); while (request_ready !== 1'b1);
        @(negedge pixel_clk);
        request_valid = 0;
    endtask

    task automatic check_job(input tuple_t value, input bit hdr);
        logic [1:0] mode;
        mode = hdr ? 2'd2 : 2'd0;
        if ({job_valid, job_snapshot, job_session, job_epoch, job_mode, job_mono,
             job_delta, job_wait, job_age} !==
            {1'b1, value, value[63:32], value[159:128], mode, !hdr, DELTA, WAIT_NS, AGE})
            fail($sformatf("DFI offer mismatch session=%08x epoch=%08x mode=%d mono=%b snapshot=%094x",
                           job_session, job_epoch, job_mode, job_mono, job_snapshot));
    endtask

    task automatic accept_job(input tuple_t value, input bit hdr, input int stall);
        do @(posedge dfi_clk); while (job_valid !== 1'b1);
        check_job(value, hdr);
        repeat (stall) begin
            @(posedge dfi_clk);
            check_job(value, hdr);
        end
        @(negedge dfi_clk);
        job_ready = 1;
        @(posedge dfi_clk);
        check_job(value, hdr);
        @(negedge dfi_clk);
        job_ready = 0;
    endtask

    task automatic finish_job(input tuple_t value, input bit hdr, err, busy);
        repeat (3) @(negedge dfi_clk);
        verify_active();
        if (ack_valid !== 1'b0) fail("ACK offered before downstream completion");
        job_done = 1;
        job_error = err;
        job_busy = busy;
        @(posedge dfi_clk);
        if (!err && !busy) begin
            expect_active = 1;
            expect_hdr = hdr;
            active_expected = value;
        end
        #0.002;
        verify_active();
        @(negedge dfi_clk);
        job_done = 0;
        job_error = 0;
        job_busy = 0;
    endtask

    task automatic take_ack(input tuple_t value, input bit success, input int stall);
        do @(posedge pixel_clk); while (ack_valid !== 1'b1);
        repeat (stall) begin
            if ({ack_valid, ack_ok, ack_data} !== {1'b1, success, value})
                fail($sformatf("held PIX ACK mismatch ok=%b expected=%b data=%094x", ack_ok, success, ack_data));
            @(posedge pixel_clk);
        end
        @(negedge pixel_clk);
        ack_ready = 1;
        @(posedge pixel_clk);
        if ({ack_valid, ack_ok, ack_data} !== {1'b1, success, value})
            fail($sformatf("PIX ACK transfer mismatch ok=%b expected=%b data=%094x", ack_ok, success, ack_data));
        @(negedge pixel_clk);
        ack_ready = 0;
    endtask

    task automatic transact(input tuple_t value, input bit hdr, frontend_ok, err, busy,
                            input int stall);
        int previous_jobs, previous_acks;
        previous_jobs = jobs;
        previous_acks = acks;
        fork
            send_request(value, frontend_ok);
            begin
                if (frontend_ok) begin
                    accept_job(value, hdr, stall);
                    finish_job(value, hdr, err, busy);
                end
                take_ack(value, frontend_ok && !err && !busy, stall);
            end
            begin
                if (!frontend_ok) begin
                    do begin
                        @(posedge dfi_clk);
                        if (job_valid !== 1'b0) fail("DFI offer from frontend negative ACK");
                    end while (acks == previous_acks);
                end
            end
        join
        if (jobs != previous_jobs + int'(frontend_ok) || acks != previous_acks + 1)
            fail("incorrect request/ack handshakes");
        if ({pixel_fault, dfi_fault} !== 2'b00) fail("fault on legal CONFIG exchange");
    endtask

    initial begin : scenarios
        tuple_t aborted;
        logic [31:0] stale_before;
        #1 pixel_rst_n = 0;
        #0.002;
        verify_active();
        check_active = 1;
        #299.998 pixel_rst_n = 1;
        wait_link();

        transact(tuple(0, SESSION, 0, 0, 0), 0, 1, 0, 0, 2);
        $display("OBS dfi_config first_boot_ack jobs=%0d acks=%0d", jobs, acks);
        transact(tuple(32'h902a_6831, SESSION, 1, 1, 1), 1, 1, 0, 0, 5);
        transact(tuple(32'h45b3_91ce, SESSION, 2, 2, 0), 0, 1, 1, 0, 2);
        transact(tuple(32'ha53b_9f10, SESSION, 2, 2, 0), 0, 1, 0, 1, 2);

        @(negedge dfi_clk);
        stale_before = stale_done_count;
        job_done = 1;
        @(posedge dfi_clk);
        #0.002;
        if (stale_done_count !== stale_before + 1) fail("late DONE did not count once");
        verify_active();
        @(negedge dfi_clk);
        job_done = 0;
        repeat (6) @(posedge pixel_clk);
        if (ack_valid !== 1'b0) fail("late DONE fabricated PIX ACK");

        transact(tuple(32'h893c_2b7a, SESSION, 2, 2, 0), 0, 1, 0, 0, 3);
        transact(tuple(32'h61c4_8d29, SESSION, 3, 2, 1), 1, 1, 0, 0, 4);
        transact(tuple(32'hb725_eda2, SESSION, 4, 2, 0), 0, 0, 0, 0, 2);

        aborted = tuple(32'hcd58_9a71, SESSION, 4, 2, 0);
        fork
            send_request(aborted, 1);
            accept_job(aborted, 0, 1);
        join
        @(negedge dfi_clk);
        dfi_run = 0;
        #2 pixel_rst_n = 0;
        expect_active = 0;
        expect_hdr = 0;
        active_expected = '0;
        #0.002;
        verify_active();
        if ({dfi_reset_done, job_valid} !== 2'b00) fail("stopped DFI reset did not withdraw CONFIG");
        #70 pixel_rst_n = 1;
        #70;
        verify_active();
        if ({dfi_reset_done, job_valid, ack_valid} !== 3'b000) fail("release advanced while DFI stopped");
        dfi_run = 1;
        wait_link();
        repeat (8) @(negedge pixel_clk);
        if ({ack_valid, job_valid} !== 2'b00) fail("pre-reset CONFIG replayed");
        transact(tuple(0, NEW_SESSION, 0, 0, 0), 0, 1, 0, 0, 2);
        if (jobs != 8 || acks != 8) fail($sformatf("terminal counters jobs=%0d acks=%0d", jobs, acks));
        $display("PASS dfi_config jobs=%0d acks=%0d both_schemas error busy late_done frontend_reject stopped_dfi_boot", jobs, acks);
        $finish;
    end

    initial begin
        #100000;
        fail($sformatf("watchdog jobs=%0d acks=%0d reset_done=%b%b valid(request/job/ack)=%b%b%b",
                       jobs, acks, pixel_reset_done, dfi_reset_done, request_valid, job_valid, ack_valid));
    end
endmodule
