`timescale 1ns/1ps

module hdr_cfg_drain_tb;
    localparam integer CONFIG_WAIT_CYCLES = 900;
    localparam integer TOKEN_WAIT_CYCLES = 120;
    localparam integer REJECT_GROUPS = 256;
    localparam logic [31:0] SESSION = 32'h512c_8a47;
    localparam logic [3:0] TRUSTED_FS = 4'd7;
    localparam logic [3:0] CROPPED_RAW = 4'd0;
    localparam logic [3:0] VERIFIED_FE = 4'd6;
    localparam logic [39:0] OLD_LONG = {10'd84, 10'd103, 10'd225, 10'd512};
    localparam logic [39:0] OLD_SHORT = {10'd605, 10'd163, 10'd47, 10'd811};
    localparam logic [39:0] NEW_LONG = {10'd145, 10'd601, 10'd389, 10'd742};
    localparam logic [39:0] NEW_SHORT = {10'd899, 10'd465, 10'd33, 10'd260};

    logic i_pixel_clk = 0;
    logic i_dfi_clk = 0;
    always #5 i_pixel_clk = !i_pixel_clk;
    always #7 i_dfi_clk = !i_dfi_clk;

    logic i_pixel_rst_n = 0;
    logic i_dfi_rst_n = 0;
    logic i_hdr_rst_n = 0;
    logic i_admit_enable = 0;
    logic i_stable = 1;
    logic i_hdr_fault = 0;
    logic [31:0] i_timeout_phase = 0;
    logic [63:0] i_time = 0;
    logic i_time_valid = 1;
    logic [146:0] s_long_data = 0;
    logic [146:0] s_short_data = 0;
    logic s_long_valid = 0;
    logic s_short_valid = 0;
    wire s_long_ready;
    wire s_short_ready;
    wire [79:0] o_raw_data;
    wire [1:0] o_raw_valid;
    wire [1:0] o_raw_sof;
    wire [1:0] o_raw_eol;
    wire [1:0] o_raw_abort;
    wire [1:0] o_source_valid;
    logic [1:0] i_source_ready = 0;
    wire [1:0] o_source_ok;
    wire [191:0] o_source_identity;
    wire [15:0] o_source_error;
    wire [1:0] i_ingress_idle;
    wire [1:0] i_enqueue_fire;
    logic [1:0] i_consume_fire = 0;
    logic i_write_quiet = 1;
    logic [1183:0] s_cfg_data = 0;
    logic s_cfg_valid = 0;
    wire s_cfg_ready;
    wire [1183:0] m_cfg_ack_data;
    wire m_cfg_ack_valid;
    wire m_cfg_ack_ok;
    logic m_cfg_ack_ready = 0;
    wire o_hdr_quiet;
    wire [1183:0] o_active_config;
    wire o_initialized;
    wire o_cfg_busy;
    wire o_cfg_reset_done;
    wire o_cfg_fault;
    wire [1:0] o_source_drain_fault;
    wire [1:0] o_dfi_drain_fault;

    hdr_cfg_drain_carrier dut (.*);
    PH1_PHY_GSR PH1_PHY_GSR();

    always @(posedge i_pixel_clk) begin
        if (i_timeout_phase == 32'd12499999)
            i_timeout_phase <= 0;
        else
            i_timeout_phase <= i_timeout_phase + 1;
        i_time <= i_time + 64'd10;
    end

    function automatic logic [1183:0] config_tuple(
        input logic [31:0] request_id,
        input logic [31:0] epoch,
        input logic [15:0] extension_mode
    );
        logic [1023:0] ext;
        logic [1183:0] cfg;
        ext = 0;
        ext[15:0] = extension_mode;
        if (extension_mode == 16'h0202) begin
            ext[66:64] = 3'd4;
            ext[76:67] = 10'd50;
            ext[86:77] = 10'd50;
            ext[108:105] = 4'd15;
            ext[191:128] = 64'd1000000;
            ext[223:192] = 32'd50000000;
            ext[255:224] = 32'd100000000;
        end
        cfg = 0;
        cfg[31:0] = request_id;
        cfg[63:32] = SESSION;
        cfg[72:66] = 7'd75;
        cfg[80:74] = 7'd1;
        cfg[159:128] = epoch;
        cfg[1183:160] = ext;
        return cfg;
    endfunction

    function automatic logic [146:0] token(
        input logic [3:0] code,
        input logic [31:0] group_id,
        input logic [31:0] capture_sequence,
        input logic [39:0] raw
    );
        logic [146:0] value;
        value = 0;
        value[39:0] = raw;
        value[40] = code == CROPPED_RAW;
        value[41] = code == CROPPED_RAW;
        value[46:43] = code;
        value[78:47] = group_id;
        value[110:79] = capture_sequence;
        value[112:111] = 2'b11;
        return value;
    endfunction

    task automatic fail(input string category, input string detail);
        $display("RESULT FAIL %s %s t=%0t", category, detail, $time);
        $finish;
    endtask

    logic watch_cohort = 0;
    logic model_ingress = 0;
    logic [1:0] ingress_owned = 0;
    assign i_ingress_idle = ~ingress_owned;
    assign i_enqueue_fire = model_ingress ? o_raw_valid : 2'b00;
    always @(posedge i_pixel_clk) begin
        if (!i_pixel_rst_n)
            ingress_owned <= 0;
        else
            ingress_owned <= (ingress_owned | i_enqueue_fire) & ~(o_source_valid & i_source_ready);
    end

    integer enqueued [0:1] = '{0, 0};
    integer consumed [0:1] = '{0, 0};
    logic expect_pair = 0;
    logic [31:0] expected_epoch;
    logic [31:0] expected_seq [0:1];
    logic [39:0] expected_raw [0:1];
    integer raw_count [0:1] = '{0, 0};
    integer taken_count [0:1] = '{0, 0};
    logic [1:0] fe_taken = 0;
    logic [1:0] source_stalled = 0;
    logic [104:0] stalled_source [0:1];
    integer short_stall_cycles = 0;

    logic [1183:0] expected_cfg;
    integer request_count = 0;
    integer ack_count = 0;
    integer first_ack_count = 0;
    integer ack_stall_cycles = 0;
    logic ack_stalled = 0;
    logic stress_active = 0;
    logic observe_stress_drain = 0;
    logic pix_drain_fault_seen = 0;
    logic dfi_drain_fault_seen = 0;
    integer reject_tokens [0:1] = '{0, 0};
    integer reject_quiet_bad = 0;
    integer reject_unblocked_cycles = 0;
    integer reject_unblocked_quiet_bad = 0;
    integer reject_write_debt_cycles = 0;
    logic dehaze_offer_during_stress = 0;

    always @(posedge i_dfi_clk) begin
        if (watch_cohort && o_dfi_drain_fault !== 2'b00) begin
            if (!observe_stress_drain)
                fail("DUT_DFI_DRAIN_FAULT", $sformatf("fault=%b", o_dfi_drain_fault));
            if (!dfi_drain_fault_seen)
                $display("OBS STRESS_DFI_DRAIN_FAULT fault=%b t=%0t", o_dfi_drain_fault, $time);
            dfi_drain_fault_seen = 1;
        end
        for (int lane = 0; lane < 2; lane++) begin
            if (i_consume_fire[lane]) begin
                if (consumed[lane] >= enqueued[lane] || i_write_quiet)
                    fail("TB_WRITE_MODEL", $sformatf("invalid consume lane=%0d", lane));
                consumed[lane]++;
            end
        end
    end

    always @(posedge i_pixel_clk) begin
        if (watch_cohort) begin
            if (o_cfg_reset_done !== 1'b1)
                fail("DUT_COHORT_RESET", $sformatf("reset_done=%b", o_cfg_reset_done));
            if (o_cfg_fault !== 1'b0 || o_source_drain_fault !== 2'b00) begin
                if (!observe_stress_drain)
                    fail("DUT_CAPTURE_DRAIN_FAULT",
                         $sformatf("cfg_fault=%b source_fault=%b", o_cfg_fault, o_source_drain_fault));
                if (!pix_drain_fault_seen)
                    $display("OBS STRESS_CAPTURE_DRAIN_FAULT cfg_fault=%b source_fault=%b t=%0t",
                             o_cfg_fault, o_source_drain_fault, $time);
                pix_drain_fault_seen = 1;
            end

            if (expect_pair) begin
                if (s_long_valid && s_long_ready && s_long_data[46:43] == VERIFIED_FE)
                    fe_taken[0] = 1;
                if (s_short_valid && s_short_ready && s_short_data[46:43] == VERIFIED_FE)
                    fe_taken[1] = 1;
            end
            if (stress_active) begin
                if (s_long_valid && s_long_ready) begin
                    if (reject_tokens[0] == 0)
                        $display("OBS FIRST_REJECT_TOKEN lane=0 event=%0d t=%0t", s_long_data[46:43], $time);
                    reject_tokens[0]++;
                end
                if (s_short_valid && s_short_ready) begin
                    if (reject_tokens[1] == 0)
                        $display("OBS FIRST_REJECT_TOKEN lane=1 event=%0d t=%0t", s_short_data[46:43], $time);
                    reject_tokens[1]++;
                end
                if (o_hdr_quiet !== 1'b1)
                    reject_quiet_bad++;
                if (!i_write_quiet)
                    reject_write_debt_cycles++;
                if (i_write_quiet && i_ingress_idle == 2'b11 &&
                    enqueued[0] == consumed[0] && enqueued[1] == consumed[1]) begin
                    reject_unblocked_cycles++;
                    if (o_hdr_quiet !== 1'b1)
                        reject_unblocked_quiet_bad++;
                end
            end

            if (o_raw_abort !== 2'b00)
                fail("DUT_UNEXPECTED_ABORT", $sformatf("abort=%b", o_raw_abort));
            for (int lane = 0; lane < 2; lane++) begin
                if (o_raw_valid[lane] === 1'b1) begin
                    if (!expect_pair || raw_count[lane] != 0 ||
                        o_raw_data[40*lane +: 40] !== expected_raw[lane] ||
                        o_raw_sof[lane] !== 1'b1 || o_raw_eol[lane] !== 1'b1)
                        fail("DUT_RAW", $sformatf("unexpected RAW4 lane=%0d data=%h sof=%b eol=%b",
                                                   lane, o_raw_data[40*lane +: 40],
                                                   o_raw_sof[lane], o_raw_eol[lane]));
                    raw_count[lane]++;
                end else if (o_raw_valid[lane] !== 1'b0) begin
                    fail("DUT_RAW", $sformatf("unknown RAW valid lane=%0d", lane));
                end
                if (i_enqueue_fire[lane])
                    enqueued[lane]++;

                if (source_stalled[lane] &&
                    (o_source_valid[lane] !== 1'b1 ||
                     {o_source_ok[lane], o_source_identity[96*lane +: 96],
                      o_source_error[8*lane +: 8]} !== stalled_source[lane]))
                    fail("DUT_SOURCE_BACKPRESSURE",
                         $sformatf("held SOURCE changed lane=%0d", lane));
                if (o_source_valid[lane] === 1'b1) begin
                    if (!expect_pair || !fe_taken[lane] || raw_count[lane] != 1 ||
                        taken_count[lane] != 0 || o_source_ok[lane] !== 1'b1 ||
                        o_source_identity[96*lane +: 96] !==
                            {SESSION, expected_epoch, expected_seq[lane]})
                        fail("DUT_SOURCE",
                             $sformatf("lane=%0d id=%h ok=%b err=%h FE=%b",
                                       lane, o_source_identity[96*lane +: 96],
                                       o_source_ok[lane], o_source_error[8*lane +: 8],
                                       fe_taken[lane]));
                    if (i_source_ready[lane]) begin
                        taken_count[lane]++;
                        $display("OBS SOURCE lane=%0d id=%h ok=%b t=%0t",
                                 lane, o_source_identity[96*lane +: 96],
                                 o_source_ok[lane], $time);
                    end
                end else if (o_source_valid[lane] !== 1'b0) begin
                    fail("DUT_SOURCE", $sformatf("unknown SOURCE valid lane=%0d", lane));
                end
                source_stalled[lane] = o_source_valid[lane] && !i_source_ready[lane];
                if (source_stalled[lane]) begin
                    stalled_source[lane] = {o_source_ok[lane], o_source_identity[96*lane +: 96],
                                            o_source_error[8*lane +: 8]};
                    if (lane == 1)
                        short_stall_cycles++;
                end
            end

            if (s_cfg_valid && s_cfg_ready) begin
                request_count++;
                if (request_count != ack_count + 1 || i_admit_enable)
                    fail("TB_CONFIG_MODEL", "unexpected CONFIG request handshake");
                $display("OBS CONFIG_ACCEPT req=%0d epoch=%0d t=%0t",
                         s_cfg_data[31:0], s_cfg_data[159:128], $time);
            end
            if (ack_stalled && m_cfg_ack_valid !== 1'b1)
                fail("DUT_ACK_BACKPRESSURE", "withdrew held CONFIG ACK");
            if (m_cfg_ack_valid === 1'b1) begin
                if (i_ingress_idle !== 2'b11 || i_write_quiet !== 1'b1 ||
                    enqueued[0] != consumed[0] || enqueued[1] != consumed[1] ||
                    (expect_pair && (taken_count[0] != 1 || taken_count[1] != 1)))
                    fail("DUT_PREMATURE_ACK",
                         $sformatf("ingress=%b write_quiet=%b enq=%0d/%0d consumed=%0d/%0d SOURCE=%0d/%0d",
                                   i_ingress_idle, i_write_quiet, enqueued[0], enqueued[1],
                                   consumed[0], consumed[1], taken_count[0], taken_count[1]));
                if (request_count != ack_count + 1 || m_cfg_ack_ok !== 1'b1 ||
                    m_cfg_ack_data !== expected_cfg || o_active_config !== expected_cfg)
                    fail("DUT_CONFIG_ACK",
                         $sformatf("req=%0d epoch=%0d ok=%b active_matches=%b tuple_matches=%b",
                                   m_cfg_ack_data[31:0], m_cfg_ack_data[159:128], m_cfg_ack_ok,
                                   o_active_config === expected_cfg, m_cfg_ack_data === expected_cfg));
                if (first_ack_count != request_count) begin
                    first_ack_count = request_count;
                    if (m_cfg_ack_data[159:128] == 2 && stress_active)
                        dehaze_offer_during_stress = 1;
                    $display("OBS CONFIG_OFFER req=%0d epoch=%0d stress=%b t=%0t",
                             m_cfg_ack_data[31:0], m_cfg_ack_data[159:128], stress_active, $time);
                end
                if (m_cfg_ack_ready) begin
                    ack_count++;
                    $display("OBS CONFIG_ACK req=%0d epoch=%0d held_cycles=%0d t=%0t",
                             m_cfg_ack_data[31:0], m_cfg_ack_data[159:128], ack_stall_cycles, $time);
                    ack_stall_cycles = 0;
                end else begin
                    ack_stall_cycles++;
                end
            end else if (m_cfg_ack_valid !== 1'b0) begin
                fail("DUT_CONFIG_ACK", "unknown ACK valid");
            end
            ack_stalled = m_cfg_ack_valid && !m_cfg_ack_ready;
        end
    end

    task automatic send_token(
        input int lane,
        input logic [3:0] code,
        input logic [31:0] group_id,
        input logic [31:0] capture_sequence,
        input logic [39:0] raw
    );
        @(negedge i_pixel_clk);
        if (lane == 0) begin
            s_long_data = token(code, group_id, capture_sequence, raw);
            s_long_valid = 1;
        end else begin
            s_short_data = token(code, group_id, capture_sequence, raw);
            s_short_valid = 1;
        end
        repeat (TOKEN_WAIT_CYCLES) begin
            @(posedge i_pixel_clk);
            if ((lane == 0 ? s_long_ready : s_short_ready) === 1'b1) begin
                if (!stress_active)
                    $display("OBS HDR_TOKEN lane=%0d event=%0d group=%0d sequence=%0d t=%0t",
                             lane, code, group_id, capture_sequence, $time);
                return;
            end
        end
        fail("DUT_HDR_TOKEN_TIMEOUT",
             $sformatf("lane=%0d event=%0d group=%0d", lane, code, group_id));
    endtask

    task automatic stop_lane(input int lane);
        @(negedge i_pixel_clk);
        if (lane == 0)
            s_long_valid = 0;
        else
            s_short_valid = 0;
    endtask

    task automatic send_config(input logic [1183:0] cfg);
        @(negedge i_pixel_clk);
        expected_cfg = cfg;
        s_cfg_data = cfg;
        s_cfg_valid = 1;
        repeat (CONFIG_WAIT_CYCLES) begin
            @(posedge i_pixel_clk);
            if (s_cfg_ready === 1'b1) begin
                @(negedge i_pixel_clk);
                s_cfg_valid = 0;
                return;
            end
        end
        fail("DUT_CONFIG_REQUEST_TIMEOUT", $sformatf("req=%0d", cfg[31:0]));
    endtask

    task automatic retire_ack(input int ordinal);
        if (ack_count != ordinal - 1 || first_ack_count != ordinal)
            fail("TB_CONFIG_MODEL", $sformatf("ACK retirement without offer ordinal=%0d", ordinal));
        repeat (6) @(negedge i_pixel_clk);
        m_cfg_ack_ready = 1;
        @(negedge i_pixel_clk);
        m_cfg_ack_ready = 0;
        if (ack_count != ordinal)
            fail("DUT_CONFIG_ACK", $sformatf("ACK failed to retire ordinal=%0d", ordinal));
    endtask

    task automatic await_ack(input int ordinal);
        repeat (CONFIG_WAIT_CYCLES) begin
            @(negedge i_pixel_clk);
            if (first_ack_count == ordinal) begin
                retire_ack(ordinal);
                return;
            end
        end
        fail("DUT_CONFIG_ACK_TIMEOUT", $sformatf("ordinal=%0d busy=%b", ordinal, o_cfg_busy));
    endtask

    task automatic start_pair(
        input logic [31:0] group_id,
        input logic [31:0] epoch,
        input logic [31:0] long_seq,
        input logic [31:0] short_seq,
        input logic [39:0] long_raw,
        input logic [39:0] short_raw,
        input logic [1:0] source_ready
    );
        @(negedge i_pixel_clk);
        if (o_active_config[159:128] !== epoch || o_initialized !== 1'b1)
            fail("DUT_ACTIVE_EPOCH", $sformatf("expected=%0d", epoch));
        expect_pair = 1;
        expected_epoch = epoch;
        expected_seq[0] = long_seq;
        expected_seq[1] = short_seq;
        expected_raw[0] = long_raw;
        expected_raw[1] = short_raw;
        raw_count = '{0, 0};
        taken_count = '{0, 0};
        fe_taken = 0;
        model_ingress = 1;
        i_source_ready = source_ready;
        i_admit_enable = 1;
        send_token(0, TRUSTED_FS, group_id, long_seq, 0);
        stop_lane(0);
        send_token(1, TRUSTED_FS, group_id, short_seq, 0);
        stop_lane(1);
        fork
            begin
                send_token(0, CROPPED_RAW, group_id, long_seq, long_raw);
                stop_lane(0);
            end
            begin
                repeat (2) @(posedge i_pixel_clk);
                send_token(1, CROPPED_RAW, group_id, short_seq, short_raw);
                stop_lane(1);
            end
        join
        repeat (TOKEN_WAIT_CYCLES) begin
            @(negedge i_pixel_clk);
            if (raw_count[0] == 1 && raw_count[1] == 1)
                return;
        end
        fail("DUT_PAIR_RAW_TIMEOUT", $sformatf("epoch=%0d RAW=%0d/%0d", epoch, raw_count[0], raw_count[1]));
    endtask

    task automatic send_true_fe(input logic [31:0] group_id);
        fork
            begin
                send_token(0, VERIFIED_FE, group_id, expected_seq[0], 0);
                stop_lane(0);
            end
            begin
                repeat (2) @(posedge i_pixel_clk);
                send_token(1, VERIFIED_FE, group_id, expected_seq[1], 0);
                stop_lane(1);
            end
        join
    endtask

    task automatic await_old_short_hold;
        repeat (TOKEN_WAIT_CYCLES) begin
            @(negedge i_pixel_clk);
            if (taken_count[0] == 1 && source_stalled[1]) begin
                repeat (20) @(negedge i_pixel_clk);
                if (!source_stalled[1] || short_stall_cycles < 20 ||
                    o_hdr_quiet !== 1'b0 || first_ack_count != 2)
                    fail("DUT_HELD_SOURCE_DRAIN", "old SHORT SOURCE failed to hold CONFIG drain");
                $display("OBS OLD_SOURCE_HELD short_stall=%0d busy=%b t=%0t",
                         short_stall_cycles, o_cfg_busy, $time);
                i_source_ready = 2'b11;
                return;
            end
        end
        fail("DUT_OLD_SOURCE_TIMEOUT", "old epoch did not reach held SHORT and retired LONG");
    endtask

    task automatic finish_pair;
        repeat (TOKEN_WAIT_CYCLES) begin
            @(negedge i_pixel_clk);
            if (taken_count[0] == 1 && taken_count[1] == 1 && o_hdr_quiet === 1'b1) begin
                expect_pair = 0;
                model_ingress = 0;
                return;
            end
        end
        fail("DUT_PAIR_DRAIN_TIMEOUT",
             $sformatf("epoch=%0d SOURCE=%0d/%0d quiet=%b",
                       expected_epoch, taken_count[0], taken_count[1], o_hdr_quiet));
    endtask

    task automatic reject_lane(input int lane, input logic [31:0] base_sequence);
        for (int group = 0; group < REJECT_GROUPS; group++) begin
            send_token(lane, TRUSTED_FS, 32'd21 + group, base_sequence + group, 0);
            send_token(lane, CROPPED_RAW, 32'd21 + group, base_sequence + group, 40'h8597_abcbad);
            send_token(lane, VERIFIED_FE, 32'd21 + group, base_sequence + group, 0);
        end
        stop_lane(lane);
    endtask

    task automatic drain_old_writes;
        repeat (12) @(negedge i_dfi_clk);
        i_write_quiet = 0;
        i_consume_fire = 2'b01;
        @(negedge i_dfi_clk);
        i_consume_fire = 0;
        repeat (6) @(negedge i_dfi_clk);
        i_consume_fire = 2'b10;
        @(negedge i_dfi_clk);
        i_consume_fire = 0;
        repeat (24) @(negedge i_dfi_clk);
        if (enqueued[0] != 1 || enqueued[1] != 1 || consumed[0] != 1 || consumed[1] != 1)
            fail("TB_WRITE_MODEL", "old RAW4 write debts did not reconcile");
        i_write_quiet = 1;
        $display("OBS OLD_WRITES_DRAINED enqueued=%0d/%0d consumed=%0d/%0d reject_tokens=%0d/%0d t=%0t",
                 enqueued[0], enqueued[1], consumed[0], consumed[1],
                 reject_tokens[0], reject_tokens[1], $time);
    endtask

    task automatic observe_pressure_ack;
        while (stress_active) begin
            @(negedge i_pixel_clk);
            #1;
            if (first_ack_count == 3) begin
                retire_ack(3);
                return;
            end
        end
    endtask

    initial begin : simulation_watchdog
        #100_000;
        fail("TB_SIM_WATCHDOG", "100 us watchdog reached");
    end

    initial begin : scenario
        $timeformat(-9, 0, " ns", 6);
        #220;
        @(negedge i_dfi_clk);
        i_dfi_rst_n = 1;
        @(negedge i_pixel_clk);
        i_pixel_rst_n = 1;
        i_hdr_rst_n = 1;
        for (int cycle = 0; cycle < CONFIG_WAIT_CYCLES && o_cfg_reset_done !== 1'b1; cycle++)
            @(negedge i_pixel_clk);
        if (o_cfg_reset_done !== 1'b1)
            fail("DUT_COHORT_RESET_TIMEOUT", "paired capture reset completion missing");
        watch_cohort = 1;

        send_config(config_tuple(32'd0, 32'd0, 16'h0000));
        await_ack(1);
        send_config(config_tuple(32'd101, 32'd1, 16'h0202));
        await_ack(2);

        start_pair(32'd20, 32'd1, 32'd1000, 32'd9000, OLD_LONG, OLD_SHORT, 2'b01);
        i_admit_enable = 0;
        fork
            send_config(config_tuple(32'd102, 32'd2, 16'h0802));
            begin
                send_true_fe(32'd20);
                await_old_short_hold();
                finish_pair();
            end
        join
        if (enqueued[0] != 1 || enqueued[1] != 1 || consumed[0] != 0 || consumed[1] != 0)
            fail("TB_WRITE_MODEL", "expected one pending transport item per old member");
        repeat (40) @(negedge i_pixel_clk);
        if (first_ack_count != 2 || o_cfg_busy !== 1'b1 ||
            o_active_config !== config_tuple(32'd101, 32'd1, 16'h0202))
            fail("DUT_TRANSPORT_DRAIN", "queued old RAW4 transport did not hold CONFIG");
        $display("OBS OLD_TRANSPORT_HELD enqueued=%0d/%0d consumed=%0d/%0d t=%0t",
                 enqueued[0], enqueued[1], consumed[0], consumed[1], $time);

        // Faults still fail the test. Observe through the writer drain to classify
        // whether a rejected-token fault prevents the real CONFIG from completing.
        observe_stress_drain = 1;
        stress_active = 1;
        fork
            begin
                fork
                    reject_lane(0, 32'd1001);
                    begin
                        repeat (2) @(posedge i_pixel_clk);
                        reject_lane(1, 32'd9001);
                    end
                join
                stress_active = 0;
            end
            drain_old_writes();
            observe_pressure_ack();
        join
        $display("OBS REJECT_STRESS tokens=%0d/%0d quiet_bad=%0d writer_busy_cycles=%0d drained_cycles=%0d drained_quiet_bad=%0d config_offer=%b",
                 reject_tokens[0], reject_tokens[1], reject_quiet_bad, reject_write_debt_cycles,
                 reject_unblocked_cycles, reject_unblocked_quiet_bad, dehaze_offer_during_stress);
        if (reject_tokens[0] != 3*REJECT_GROUPS || reject_tokens[1] != 3*REJECT_GROUPS ||
            reject_write_debt_cycles < 12 || reject_unblocked_cycles < 200)
            fail("TB_STRESS_COVERAGE", "did not sustain enough traffic across modeled write drain");
        if (!dehaze_offer_during_stress) begin
            $display("OBS PRESSURE_EXIT_WITHOUT_ACK busy=%b epoch=%0d t=%0t",
                     o_cfg_busy, o_active_config[159:128], $time);
            for (int cycle = 0; cycle < CONFIG_WAIT_CYCLES && first_ack_count < 3; cycle++)
                @(negedge i_pixel_clk);
            if (first_ack_count == 3 && ack_count < 3)
                retire_ack(3);
            $display("OBS POST_STRESS ack=%0d busy=%b epoch=%0d t=%0t",
                     ack_count, o_cfg_busy, o_active_config[159:128], $time);
            if (reject_unblocked_quiet_bad != 0 || pix_drain_fault_seen || dfi_drain_fault_seen)
                fail("DUT_REJECTED_TRAFFIC_BLOCKS_CONFIG",
                     $sformatf("old SOURCE and modeled debts drained, no dehaze ACK under traffic, recovery=%b pix_fault=%b dfi_fault=%b",
                               ack_count == 3, pix_drain_fault_seen, dfi_drain_fault_seen));
            fail("DUT_CONFIG_LIVENESS_UNDER_TRAFFIC", "dehaze ACK did not appear during drained rejected traffic");
        end
        if (pix_drain_fault_seen || dfi_drain_fault_seen)
            fail("DUT_REJECTED_TRAFFIC_DRAIN_FAULT",
                 $sformatf("unadmitted tokens produced a drain fault pix=%b dfi=%b",
                           pix_drain_fault_seen, dfi_drain_fault_seen));
        if (reject_quiet_bad != 0)
            fail("DUT_REJECTED_TRAFFIC_DROPS_QUIET", "unadmitted tokens disturbed HDR quiet");
        observe_stress_drain = 0;

        @(negedge i_pixel_clk);
        i_hdr_rst_n = 0;
        repeat (8) @(negedge i_pixel_clk);
        send_config(config_tuple(32'd103, 32'd3, 16'h0202));
        await_ack(4);
        @(negedge i_pixel_clk);
        i_hdr_rst_n = 1;
        repeat (8) @(negedge i_pixel_clk);
        start_pair(32'd277, 32'd3, 32'd1257, 32'd9257, NEW_LONG, NEW_SHORT, 2'b11);
        send_true_fe(32'd277);
        finish_pair();
        i_admit_enable = 0;
        @(negedge i_dfi_clk);
        i_write_quiet = 0;
        i_consume_fire = 2'b11;
        @(negedge i_dfi_clk);
        i_consume_fire = 0;
        repeat (4) @(negedge i_dfi_clk);
        i_write_quiet = 1;
        repeat (16) @(negedge i_pixel_clk);
        if (enqueued[0] != 2 || enqueued[1] != 2 || consumed[0] != 2 || consumed[1] != 2 ||
            request_count != 4 || ack_count != 4)
            fail("TB_FINAL_RECONCILIATION", "terminal fixture counts do not reconcile");
        $display("RESULT PASS HDR_CONFIG_DRAIN old_epoch=1 dehaze_epoch=2 new_epoch=3 source=2/2 cfg_ack=4 t=%0t",
                 $time);
        $finish;
    end
endmodule
