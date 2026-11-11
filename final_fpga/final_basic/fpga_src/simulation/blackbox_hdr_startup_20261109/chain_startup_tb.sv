`timescale 1ns/1ps

module chain_i2c_slave #(
    parameter integer EYE = 0
) (
    input wire reset_n,
    input wire scl,
    inout wire sda,
    output integer starts,
    output integer acks,
    output integer writes
);
    reg ack = 0;
    reg [7:0] byte_value;
    pullup (sda);
    assign sda = ack ? 1'b0 : 1'bz;

    initial begin
        starts = 0;
        acks = 0;
        writes = 0;
        forever begin
            @(negedge sda);
            if (reset_n && scl === 1'b1) begin
                starts++;
                for (int index = 0; index < 4; index++) begin
                    byte_value = 0;
                    repeat (8) begin
                        @(posedge scl);
                        byte_value = {byte_value[6:0], sda};
                    end
                    if (index == 0 && byte_value !== 8'h34)
                        $fatal(1, "CHAIN_FAIL eye=%0d unexpected I2C address byte=%h", EYE, byte_value);
                    @(negedge scl);
                    ack = 1;
                    @(posedge scl);
                    acks++;
                    @(negedge scl);
                    ack = 0;
                end
                do @(posedge sda); while (scl !== 1'b1);
                writes++;
            end
        end
    end
endmodule

module chain_startup_tb;
    localparam integer WARMUP_PAIRS = 8;
    localparam integer PAIR_DEADLINE = 4096;
    localparam integer HOLD_CYCLES = 32;
    localparam [31:0] SESSION = 32'h391ab04e;
    localparam [31:0] EPOCH = 32'h20261109;

    reg cfg_clk = 0;
    reg pix_clk = 0;
    reg word_clk = 0;
    always #20 cfg_clk = ~cfg_clk;
    always #5 pix_clk = ~pix_clk;
    initial begin
        #1.25;
        forever #4.5 word_clk = ~word_clk;
    end

    reg reset_n = 0;
    reg start = 0;
    wire [1:0] start_ready, config_written, config_error, xclr, scl, sda;
    wire [7:0] register_index [0:1];
    wire integer register_writes [0:1], i2c_starts [0:1], i2c_acks [0:1];
    reg word_enable = 0;
    reg [1:0] word_valid = 0;
    reg [31:0] csi_word [0:1];
    wire [1:0] word_fifo_ready, hdr_stable, pair_event, pair_ok, quiet;
    wire [1:0] identity_fault, pair_overflow;
    reg [63:0] time_ns = 0;
    wire [31:0] good_pairs [0:1], bad_pairs [0:1], not_admitted_pairs [0:1];
    wire [79:0] raw_data [0:1];
    wire [1:0] raw_valid [0:1], raw_sof [0:1], raw_eol [0:1], raw_abort [0:1];
    wire [393:0] metadata [0:1];
    wire [1:0] source_valid [0:1], source_ok [0:1];
    reg [1:0] source_ready [0:1];
    wire [63:0] source_session [0:1], source_epoch [0:1], source_sequence [0:1];
    wire [15:0] source_error [0:1];

    PH1_PHY_GSR PH1_PHY_GSR();
    for (genvar eye = 0; eye < 2; eye++) begin : eyes
        chain_i2c_slave #(.EYE(eye)) slave (
            .reset_n(reset_n), .scl(scl[eye]), .sda(sda[eye]),
            .starts(i2c_starts[eye]), .acks(i2c_acks[eye]), .writes(register_writes[eye])
        );
        seed12_hdr_startup_carrier dut (
            .i_cfg_clk(cfg_clk), .i_word_clk(word_clk), .i_pixel_clk(pix_clk),
            .i_reset_n(reset_n), .i_config_start(start), .i_clock_locked(1'b1),
            .i_hdr_profile(1'b1), .o_start_ready(start_ready[eye]),
            .o_config_written(config_written[eye]), .o_config_error(config_error[eye]),
            .o_xclr(xclr[eye]), .o_scl(scl[eye]), .io_sda(sda[eye]),
            .o_register_index(register_index[eye]), .i_word_enable(word_enable),
            .i_word(csi_word[eye]), .i_word_valid(word_valid[eye]),
            .o_word_fifo_ready(word_fifo_ready[eye]), .i_peer_stable(hdr_stable[1-eye]),
            .i_admit_enable(1'b1), .o_hdr_stable(hdr_stable[eye]),
            .i_session(SESSION), .i_epoch(EPOCH), .i_time_ns(time_ns),
            .i_time_valid(1'b1), .i_capture_idle(2'b11), .o_raw_data(raw_data[eye]),
            .o_raw_valid(raw_valid[eye]), .o_raw_sof(raw_sof[eye]), .o_raw_eol(raw_eol[eye]),
            .o_raw_abort(raw_abort[eye]), .o_metadata(metadata[eye]),
            .o_source_valid(source_valid[eye]), .i_source_ready(source_ready[eye]),
            .o_source_ok(source_ok[eye]), .o_source_session(source_session[eye]),
            .o_source_epoch(source_epoch[eye]), .o_source_sequence(source_sequence[eye]),
            .o_source_error(source_error[eye]), .o_pair_event(pair_event[eye]),
            .o_pair_ok(pair_ok[eye]), .o_quiet(quiet[eye]), .o_good_pairs(good_pairs[eye]),
            .o_bad_pairs(bad_pairs[eye]), .o_not_admitted_pairs(not_admitted_pairs[eye]),
            .o_identity_fault(identity_fault[eye]), .o_pair_overflow(pair_overflow[eye])
        );
    end

    int round = 0;
    int offered_pairs [0:1];
    int good_events [0:1], bad_events [0:1];
    int offered_fs [0:1][0:1];
    int raw_count [0:1][0:1], source_count [0:1][0:1], stall_cycles [0:1][0:1];
    bit fe_sent [0:1][0:1], was_stalled [0:1][0:1];
    logic [31:0] raw_group [0:1][0:1];
    logic [39:0] expected_raw [0:1][0:1];
    logic [31:0] expected_sequence [0:1][0:1];
    logic [104:0] held_source [0:1][0:1];

    always @(negedge pix_clk) time_ns <= time_ns + 64'd10;
    always @(posedge cfg_clk) begin
        if (reset_n && start)
            $display("CHAIN_CFG_START ready=%b xclr=%b scl=%b sda=%b time=%t", start_ready, xclr, scl, sda, $time);
        if (reset_n && |config_error)
            $fatal(1, "CHAIN_FAIL HDR write error eyes=%b", config_error);
    end

    function automatic [31:0] csi_header(
        input int vc, input logic [5:0] data_type, input logic [15:0] field
    );
        logic [23:0] data;
        logic [5:0] parity;
        data = {field, vc[1:0], data_type};
        parity[0] = ^(data & 24'hf12cb7);
        parity[1] = ^(data & 24'hf2555b);
        parity[2] = ^(data & 24'h749a6d);
        parity[3] = ^(data & 24'hb8e38e);
        parity[4] = ^(data & 24'hdf03f0);
        parity[5] = ^(data & 24'heffc00);
        return {2'b00, parity, data};
    endfunction

    function automatic [47:0] sensor_samples(input int eye, input int vc, input int ordinal);
        logic [11:0] p0, p1, p2, p3;
        int offset;
        offset = 512 * eye + 64 * vc;
        p0 = 12'h025 + offset + ordinal;
        p1 = 12'h31e + offset + 2 * ordinal;
        p2 = 12'h773 + offset + ordinal;
        p3 = 12'hffd + ((ordinal + eye + vc) % 3);
        return {p3, p2, p1, p0};
    endfunction

    function automatic [39:0] raw10_reference(input logic [47:0] samples);
        int rounded;
        for (int pixel = 0; pixel < 4; pixel++) begin
            rounded = (int'(samples[12*pixel +: 12]) + 2) / 4;
            raw10_reference[10*pixel +: 10] = (rounded > 1023) ? 10'd1023 : rounded[9:0];
        end
    endfunction

    function automatic [15:0] line_crc(input logic [47:0] bytes);
        logic [15:0] crc;
        crc = 16'hffff;
        for (int bit_index = 0; bit_index < 48; bit_index++) begin
            if (crc[0] ^ bytes[bit_index])
                crc = (crc >> 1) ^ 16'h8408;
            else
                crc = crc >> 1;
        end
        return crc;
    endfunction

    task automatic send_burst(
        input int eye, input int count, input logic [95:0] words, input int fe_vc = -1
    );
        repeat (8) @(negedge word_clk);
        word_valid[eye] = 1;
        for (int index = 0; index < count; index++) begin
            csi_word[eye] = words[32*index +: 32];
            @(posedge word_clk);
            if (fe_vc >= 0)
                fe_sent[eye][fe_vc] = 1;
            @(negedge word_clk);
        end
        word_valid[eye] = 0;
    endtask

    task automatic send_member(input int eye, input int vc);
        logic [15:0] frame_number;
        logic [47:0] samples, payload;
        int ordinal;
        ordinal = ++offered_fs[eye][vc];
        frame_number = 16'h4200 + 256 * eye + 64 * vc + 3 * ordinal;
        samples = sensor_samples(eye, vc, ordinal);
        payload = {
            samples[39:36], samples[27:24], samples[47:40], samples[35:28],
            samples[15:12], samples[3:0], samples[23:16], samples[11:4]
        };
        send_burst(eye, 1, {64'd0, csi_header(vc, 6'h00, frame_number)});
        send_burst(eye, 3, {line_crc(payload), payload, csi_header(vc, 6'h2c, 16'd6)});
        if (round != 0)
            repeat (128) @(negedge pix_clk);
        send_burst(eye, 1, {64'd0, csi_header(vc, 6'h01, frame_number)}, vc);
    endtask

    task automatic send_pair(input int eye);
        send_member(eye, 0);
        send_member(eye, 1);
        offered_pairs[eye]++;
    endtask

    always @(posedge pix_clk) begin : scoreboard
        logic [196:0] member_metadata;
        logic [104:0] source_bundle;
        logic [1:0] role;
        if (reset_n) begin
            for (int eye = 0; eye < 2; eye++) begin
                if (pair_event[eye]) begin
                    case (pair_ok[eye])
                        1'b1: begin
                            good_events[eye]++;
                            if (good_events[eye] > offered_pairs[eye])
                                $fatal(1, "CHAIN_FAIL eye=%0d good event without complete pair", eye);
                        end
                        1'b0: bad_events[eye]++;
                        default: $fatal(1, "CHAIN_FAIL eye=%0d unknown pair result", eye);
                    endcase
                end
                if (hdr_stable[eye] && good_events[eye] < WARMUP_PAIRS)
                    $fatal(1, "CHAIN_FAIL eye=%0d early stable good=%0d", eye, good_events[eye]);

                for (int vc = 0; vc < 2; vc++) begin
                    if (raw_valid[eye][vc] || source_valid[eye][vc]) begin
                        if (round == 0 || hdr_stable !== 2'b11)
                            $fatal(1, "CHAIN_FAIL early product eye=%0d vc=%0d stable=%b", eye, vc, hdr_stable);
                    end
                    if (round != 0 && raw_abort[eye][vc])
                        $fatal(1, "CHAIN_FAIL unexpected RAW abort eye=%0d vc=%0d", eye, vc);
                    if (raw_valid[eye][vc]) begin
                        member_metadata = metadata[eye][197*vc +: 197];
                        role = (vc == 0) ? 2'd1 : 2'd2;
                        if (raw_count[eye][vc] >= round || raw_sof[eye][vc] !== 1'b1 ||
                            raw_eol[eye][vc] !== 1'b1 || member_metadata[196:193] !== {2'b11, role})
                            $fatal(1, "CHAIN_FAIL unexpected RAW shape or role eye=%0d vc=%0d", eye, vc);
                        if (raw_data[eye][40*vc +: 40] !== expected_raw[eye][vc])
                            $fatal(1, "CHAIN_FAIL RAW eye=%0d vc=%0d got=%h want=%h", eye, vc,
                                raw_data[eye][40*vc +: 40], expected_raw[eye][vc]);
                        raw_group[eye][vc] = member_metadata[191:160];
                        raw_count[eye][vc]++;
                        $display("CHAIN_RAW round=%0d eye=%0d vc=%0d raw10=%h group=%h", round, eye, vc,
                            raw_data[eye][40*vc +: 40], raw_group[eye][vc]);
                    end

                    source_bundle = {
                        source_ok[eye][vc], source_session[eye][32*vc +: 32],
                        source_epoch[eye][32*vc +: 32], source_sequence[eye][32*vc +: 32],
                        source_error[eye][8*vc +: 8]
                    };
                    if (was_stalled[eye][vc] &&
                        (source_valid[eye][vc] !== 1'b1 || source_bundle !== held_source[eye][vc]))
                        $fatal(1, "CHAIN_FAIL stalled SOURCE changed eye=%0d vc=%0d", eye, vc);
                    was_stalled[eye][vc] = source_valid[eye][vc] && !source_ready[eye][vc];
                    if (was_stalled[eye][vc]) begin
                        held_source[eye][vc] = source_bundle;
                        stall_cycles[eye][vc]++;
                    end
                    if (source_valid[eye][vc]) begin
                        if (!fe_sent[eye][vc] || raw_count[eye][vc] != round || source_count[eye][vc] >= round)
                            $fatal(1, "CHAIN_FAIL SOURCE order/count eye=%0d vc=%0d FE=%b", eye, vc, fe_sent[eye][vc]);
                        if (source_bundle !== {1'b1, SESSION, EPOCH, expected_sequence[eye][vc], 8'd0})
                            $fatal(1, "CHAIN_FAIL SOURCE identity eye=%0d vc=%0d bundle=%h wanted_sequence=%0d",
                                eye, vc, source_bundle, expected_sequence[eye][vc]);
                        if (source_ready[eye][vc]) begin
                            source_count[eye][vc]++;
                            $display("CHAIN_SOURCE round=%0d eye=%0d vc=%0d seq=%0d session=%h epoch=%h hold=%0d",
                                round, eye, vc, source_sequence[eye][32*vc +: 32], SESSION, EPOCH, stall_cycles[eye][vc]);
                        end
                    end
                end
            end
        end
    end

    task automatic hold_first_cam1_short;
        for (int cycle = 0; cycle < PAIR_DEADLINE && source_valid[1][1] !== 1'b1; cycle++)
            @(negedge pix_clk);
        if (source_valid[1][1] !== 1'b1)
            $fatal(1, "CHAIN_FAIL CAM1 SHORT did not offer SOURCE under finite stall");
        repeat (HOLD_CYCLES) @(negedge pix_clk);
        source_ready[1][1] = 1;
    endtask

    function automatic bit round_drained;
        if (quiet !== 2'b11 || hdr_stable !== 2'b11)
            return 0;
        for (int eye = 0; eye < 2; eye++) begin
            if (good_events[eye] != WARMUP_PAIRS + round || good_pairs[eye] !== WARMUP_PAIRS + round)
                return 0;
            for (int vc = 0; vc < 2; vc++)
                if (raw_count[eye][vc] != round || source_count[eye][vc] != round)
                    return 0;
        end
        return 1;
    endfunction

    task automatic check_admitted_round(input int next_round);
        @(negedge pix_clk);
        round = next_round;
        for (int eye = 0; eye < 2; eye++) begin
            for (int vc = 0; vc < 2; vc++) begin
                expected_sequence[eye][vc] = WARMUP_PAIRS + round + ((eye == 1 && vc == 1) ? 1 : 0);
                if (offered_fs[eye][vc] + 1 != expected_sequence[eye][vc])
                    $fatal(1, "CHAIN_FIXTURE_FAIL incorrect FS count eye=%0d vc=%0d", eye, vc);
                expected_raw[eye][vc] = raw10_reference(sensor_samples(eye, vc, expected_sequence[eye][vc]));
                fe_sent[eye][vc] = 0;
            end
        end
        if (round == 1)
            source_ready[1][1] = 0;
        fork
            send_pair(0);
            send_pair(1);
            if (next_round == 1)
                hold_first_cam1_short();
        join
        for (int cycle = 0; cycle < PAIR_DEADLINE && !round_drained(); cycle++)
            @(negedge pix_clk);
        if (!round_drained())
            $fatal(1, "CHAIN_FAIL round=%0d incomplete good=%0d/%0d quiet=%b stable=%b",
                round, good_events[0], good_events[1], quiet, hdr_stable);
        for (int eye = 0; eye < 2; eye++) begin
            if ((^raw_group[eye][0]) === 1'bx || raw_group[eye][0] !== raw_group[eye][1])
                $fatal(1, "CHAIN_FAIL unequal group eye=%0d long=%h short=%h", eye, raw_group[eye][0], raw_group[eye][1]);
        end
        if (stall_cycles[1][1] < HOLD_CYCLES)
            $fatal(1, "CHAIN_FAIL insufficient observed SOURCE stall cycles=%0d", stall_cycles[1][1]);
        $display("CHAIN_DRAIN round=%0d quiet=%b good=%0d/%0d", round, quiet, good_events[0], good_events[1]);
        #2000;
    endtask

    initial begin : directed_case
        for (int eye = 0; eye < 2; eye++) begin
            csi_word[eye] = 0;
            source_ready[eye] = 2'b11;
            offered_pairs[eye] = 0;
            good_events[eye] = 0;
            bad_events[eye] = 0;
            for (int vc = 0; vc < 2; vc++) begin
                offered_fs[eye][vc] = 0;
                raw_count[eye][vc] = 0;
                source_count[eye][vc] = 0;
                stall_cycles[eye][vc] = 0;
            end
        end
        repeat (12) @(posedge cfg_clk);
        #3 reset_n = 1;
        repeat (4) @(posedge cfg_clk);
        wait (start_ready === 2'b11);
        @(negedge cfg_clk) start = 1;
        @(negedge cfg_clk) start = 0;
        wait (config_written === 2'b11);
        repeat (4) @(negedge cfg_clk);
        if (register_writes[0] != 139 || register_writes[1] != 139 ||
            register_index[0] !== 8'd138 || register_index[1] !== 8'd138)
            $fatal(1, "CHAIN_FAIL recipe termination writes=%0d/%0d index=%0d/%0d",
                register_writes[0], register_writes[1], register_index[0], register_index[1]);
        $display("CHAIN_CONFIG both HDR recipes complete writes=%0d/%0d index=%0d/%0d xclr=%b",
            register_writes[0], register_writes[1], register_index[0], register_index[1], xclr);
        @(negedge word_clk) word_enable = 1;
        wait (word_fifo_ready === 2'b11);
        repeat (16) @(posedge word_clk);

        fork
            begin
                send_pair(0);
                repeat (WARMUP_PAIRS - 1) begin
                    #2000;
                    send_pair(0);
                end
            end
            begin
                send_member(1, 1);
                $display("CHAIN_PREFIX CAM1 complete VC1 before any CAM1 VC0 FS");
                repeat (WARMUP_PAIRS) begin
                    #2000;
                    send_pair(1);
                end
            end
        join
        repeat (3 * PAIR_DEADLINE) @(negedge pix_clk);
        $display("CHAIN_WARMUP offered=%0d/%0d good=%0d/%0d bad=%0d/%0d good_count=%0d/%0d bad_count=%0d/%0d not_admitted=%0d/%0d stable=%b quiet=%b identity=%b overflow=%b",
            offered_pairs[0], offered_pairs[1], good_events[0], good_events[1], bad_events[0], bad_events[1],
            good_pairs[0], good_pairs[1], bad_pairs[0], bad_pairs[1], not_admitted_pairs[0], not_admitted_pairs[1],
            hdr_stable, quiet, identity_fault, pair_overflow);
        if (hdr_stable[0] !== 1'b1 || good_events[0] != WARMUP_PAIRS || good_pairs[0] !== WARMUP_PAIRS)
            $fatal(1, "CHAIN_FAIL healthy LONG-first control failed qualification");
        if (hdr_stable[1] !== 1'b1 || good_events[1] != WARMUP_PAIRS || good_pairs[1] !== WARMUP_PAIRS)
            $fatal(1, "CHAIN_WARMUP_LIVENESS_FAIL CAM1 did not qualify after eight offered pairs and three pair deadlines");
        if ({identity_fault, pair_overflow} !== 4'b0)
            $fatal(1, "CHAIN_FAIL unexpected sticky identity/overflow after legal warmup");

        check_admitted_round(1);
        check_admitted_round(2);
        if (!round_drained() || {identity_fault, pair_overflow} !== 4'b0)
            $fatal(1, "CHAIN_FAIL final idle or sticky fault");
        $display("CHAIN_PASS dual-eye HDR first transaction, finite SOURCE hold and following transaction");
        $finish;
    end

    initial begin
        #7900000;
        $fatal(1, "CHAIN_FAIL simulation watchdog ready=%b written=%b error=%b xclr=%b scl=%b sda=%b starts=%0d/%0d ACKs=%0d/%0d writes=%0d/%0d index=%0d/%0d word_ready=%b stable=%b round=%0d",
            start_ready, config_written, config_error, xclr, scl, sda,
            i2c_starts[0], i2c_starts[1], i2c_acks[0], i2c_acks[1],
            register_writes[0], register_writes[1], register_index[0], register_index[1],
            word_fifo_ready, hdr_stable, round);
    end
endmodule
