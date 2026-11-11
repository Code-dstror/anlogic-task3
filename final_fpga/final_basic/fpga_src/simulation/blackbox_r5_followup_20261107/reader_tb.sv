`timescale 1ns/1ps

module reader_tb;
    localparam integer WIDTH = 16;
    localparam integer HEIGHT = 16;
    localparam integer GROUPS = WIDTH * HEIGHT / 4;
    localparam integer BEATS = GROUPS * 5 / 16;

    reg clk = 0;
    always #5 clk = !clk;

    reg rst_n, service_rst_n;
    reg start_valid, cancel, out_ready, done_ready;
    reg [27:0] base;
    reg [63:0] job_id;
    wire start_ready, out_valid, done_valid, done_ok, bus_quiet, fault;
    wire [146:0] out_data;

    wire dec_start_valid, dec_start_ready, dec_release, dec_cancel, dec_run;
    wire dec_valid, dec_last, dec_ready, dec_raw_valid, dec_raw_ready;
    wire dec_sof, dec_eol, dec_done, dec_aborted, dec_quiet, dec_active;
    wire [127:0] dec_data;
    wire [15:0] dec_keep;
    wire [39:0] dec_raw;
    reg drop_start, mask_active;

    wire arvalid, rready;
    wire [3:0] arid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    reg arready, rvalid, rlast;
    reg [3:0] rid;
    reg [1:0] rresp;
    reg [127:0] rdata;

    stereo_raw_reader #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .EXTERNAL_DECODER(1), .VERIFY_DECODE_ACTIVE(1)
    ) reader (
        .clk(clk), .rst_n(rst_n),
        .i_start_valid(start_valid), .o_start_ready(start_ready),
        .i_base(base), .i_job_id(job_id), .i_cancel(cancel),
        .m_data(out_data), .m_valid(out_valid), .m_ready(out_ready),
        .o_done_valid(done_valid), .o_done_ok(done_ok), .i_done_ready(done_ready),
        .o_bus_quiet(bus_quiet), .o_fault(fault),
        .o_decode_start_valid(dec_start_valid), .i_decode_start_ready(dec_start_ready),
        .o_decode_release(dec_release), .o_decode_cancel(dec_cancel), .o_decode_run(dec_run),
        .o_decode_data(dec_data), .o_decode_keep(dec_keep), .o_decode_valid(dec_valid),
        .o_decode_last(dec_last), .i_decode_ready(dec_ready),
        .i_decode_raw(dec_raw), .i_decode_raw_valid(dec_raw_valid),
        .o_decode_raw_ready(dec_raw_ready), .i_decode_sof(dec_sof), .i_decode_eol(dec_eol),
        .i_decode_done(dec_done), .i_decode_aborted(dec_aborted), .i_decode_quiet(dec_quiet),
        .i_decode_active(dec_active && !mask_active),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    shared_raw10_decode_service #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) service (
        .clk(clk), .rst_n(service_rst_n),
        .hdr_start_valid(1'b0), .hdr_start_ready(), .hdr_release(1'b0), .hdr_abort(2'b00),
        .hdr_member(1'b0), .hdr_data(128'b0), .hdr_keep(16'b0), .hdr_valid(1'b0),
        .hdr_last(1'b0), .hdr_ready(), .hdr_raw_member(), .hdr_raw(),
        .hdr_raw_valid(), .hdr_raw_ready(1'b0), .hdr_done(), .hdr_aborted(),
        .stereo_start_valid(dec_start_valid && !drop_start),
        .stereo_start_ready(dec_start_ready), .stereo_release(dec_release),
        .stereo_cancel(dec_cancel), .stereo_run(dec_run), .stereo_data(dec_data),
        .stereo_keep(dec_keep), .stereo_valid(dec_valid), .stereo_last(dec_last),
        .stereo_ready(dec_ready), .stereo_raw(dec_raw), .stereo_raw_valid(dec_raw_valid),
        .stereo_raw_ready(dec_raw_ready), .stereo_sof(dec_sof), .stereo_eol(dec_eol),
        .stereo_done(dec_done), .stereo_aborted(dec_aborted), .stereo_quiet(dec_quiet),
        .stereo_active(dec_active), .quiet()
    );

    string case_name, stage;
    integer cycle = 0;
    integer sequence_number, expected_error;
    bit expected_ok, no_new_ar, isolate_bad_response;

    bit job_live, active_seen, ar_held, out_held, done_held, held_done_ok;
    bit first_r_out_ready, stop_on_final_r;
    reg [44:0] held_ar;
    reg [146:0] held_out;
    integer reader_start_count, service_start_count, ar_count, r_debt;
    integer requested_beats, returned_beats, data_count, fence_count;
    wire [44:0] ar_payload = {arid, araddr, arlen, arsize, arburst};

    function automatic [9:0] sample_value(input integer sequence_id, input integer pixel);
        case (pixel % 37)
            0: sample_value = 10'h000;
            1: sample_value = 10'h3ff;
            default: sample_value = (sequence_id * 193) + (pixel * 47) + (pixel / 4 * 13);
        endcase
    endfunction

    // Pack each input bit by its absolute location in the RAW10 bit stream.
    function automatic [127:0] memory_beat(input integer sequence_id, input integer beat);
        integer position;
        reg [9:0] pixel;
        for (integer bit_index = 0; bit_index < 128; bit_index = bit_index + 1) begin
            position = beat * 128 + bit_index;
            pixel = sample_value(sequence_id, position / 10);
            memory_beat[bit_index] = pixel[position % 10];
        end
    endfunction

    function automatic [135:0] data_payload(input integer sequence_id, input integer group_index);
        data_payload = 0;
        data_payload[134:103] = group_index;
        data_payload[102] = group_index == GROUPS - 1;
        data_payload[101] = (group_index % (WIDTH / 4)) == WIDTH / 4 - 1;
        data_payload[100] = group_index == 0;
        data_payload[99:96] = 4'hf;
        for (integer lane = 0; lane < 4; lane = lane + 1)
            data_payload[lane * 14 +: 14] = {4'b0, sample_value(sequence_id, group_index * 4 + lane)};
    endfunction

    task automatic fail(input string reason);
        $display("READER_FAIL case=%s stage=%s cycle=%0d job=%h %s",
                 case_name, stage, cycle, job_id, reason);
        $display("BOUNDARY grant=%0d/%0d active=%b mask=%b AR=%0d v/r=%b%b R=%0d debt=%0d v/r=%b%b OUT=%0d/%0d v/r=%b%b kind=%b DONE=%b/%b quiet=%b fault=%b",
                 reader_start_count, service_start_count, dec_active, mask_active,
                 ar_count, arvalid, arready, returned_beats, r_debt, rvalid, rready,
                 data_count, fence_count, out_valid, out_ready, out_data[146:145],
                 done_valid, done_ok, bus_quiet, fault);
        $fatal(1);
    endtask

    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!rst_n) begin
            job_live = 0;
            ar_held = 0;
            out_held = 0;
            done_held = 0;
            r_debt = 0;
        end else begin
            if (start_valid && start_ready) begin
                if (job_live) fail("accepted a new job before DONE was consumed");
                job_live = 1;
                reader_start_count = 0;
                service_start_count = 0;
                active_seen = 0;
                ar_count = 0;
                requested_beats = 0;
                returned_beats = 0;
                r_debt = 0;
                data_count = 0;
                fence_count = 0;
                stop_on_final_r = 0;
                first_r_out_ready = 1;
            end

            if (!job_live && (arvalid || out_valid || done_valid))
                fail("output appeared without a live job");
            if (job_live && dec_start_valid && dec_start_ready) begin
                reader_start_count = reader_start_count + 1;
                if (!drop_start) service_start_count = service_start_count + 1;
            end
            if (service_start_count != 0 && dec_active && !mask_active) active_seen = 1;

            if (ar_held && (arvalid !== 1'b1 || ar_payload !== held_ar))
                fail("stalled AR was withdrawn or changed");
            if (arvalid && !ar_held) begin
                if (!active_seen || service_start_count != 1 || !dec_active || mask_active)
                    fail("AR appeared without a real decode START and active confirmation");
                if (no_new_ar) fail("new AR appeared after cancellation or context loss");
                if (r_debt != 0) fail("new AR appeared with a burst outstanding");
                if ($isunknown(ar_payload) || arid != 1 || arsize != 4 || arburst != 1 || arlen > 15)
                    fail("illegal AXI AR shape");
                if (araddr != base + requested_beats * 16 || requested_beats + arlen + 1 > BEATS)
                    fail("AR does not cover the next frame bytes");
                if (int'(araddr[11:0]) + (int'(arlen) + 1) * 16 > 4096)
                    fail("AR burst crosses 4 KiB");
            end
            ar_held = arvalid && !arready;
            held_ar = ar_payload;

            if (r_debt > 0 && bus_quiet !== 1'b0)
                fail("bus became quiet before all accepted AR beats returned");
            if (rvalid && rready) begin
                if (r_debt == 0) fail("accepted an R beat without debt");
                if (returned_beats == 0) begin
                    first_r_out_ready = out_ready;
                    $display("FIRST_R case=%s job=%h cycle=%0d out_ready=%b data=%0d",
                             case_name, job_id, cycle, out_ready, data_count);
                end
                returned_beats = returned_beats + 1;
                r_debt = r_debt - 1;
                if (cancel && rlast && returned_beats == BEATS) stop_on_final_r = 1;
            end
            if (arvalid && arready) begin
                ar_count = ar_count + 1;
                r_debt = int'(arlen) + 1;
                requested_beats = requested_beats + r_debt;
                $display("AR case=%s job=%h cycle=%0d addr=%h beats=%0d",
                         case_name, job_id, cycle, araddr, r_debt);
            end

            if (out_held && (out_valid !== 1'b1 || out_data !== held_out))
                fail("stalled DATA/FENCE was withdrawn or changed");
            out_held = out_valid && !out_ready;
            held_out = out_data;
            if (done_held && (done_valid !== 1'b1 || done_ok !== held_done_ok))
                fail("stalled DONE was withdrawn or changed");
            done_held = done_valid && !done_ready;
            held_done_ok = done_ok;
            if (done_valid) begin
                if (fence_count != 1 || done_ok !== expected_ok)
                    fail("DONE preceded FENCE consumption or disagreed with FENCE result");
                if (done_ready) job_live = 0;
            end

            if (out_valid) begin
                if (fence_count != 0) fail("output followed a consumed FENCE");
                case (out_data[146:145])
                    2'd0: begin
                        if (data_count >= GROUPS || out_data[135:0] !== data_payload(sequence_number, data_count))
                            fail($sformatf("DATA mismatch group=%0d got=%h expected=%h",
                                           data_count, out_data[135:0], data_payload(sequence_number, data_count)));
                        if (out_ready) data_count = data_count + 1;
                    end
                    2'd1: begin
                        if (!isolate_bad_response && (r_debt != 0 || ar_held))
                            fail("FENCE appeared with AXI work still owed");
                        if (out_data[144:105] !== 40'b0 || out_data[95:32] !== job_id ||
                            out_data[96] !== expected_ok)
                            fail($sformatf("FENCE reserved bits, identity or outcome mismatch token=%h", out_data));
                        if (expected_ok) begin
                            if (out_data[104:97] !== 8'b0 || out_data[31:0] !== GROUPS ||
                                data_count != GROUPS || requested_beats != BEATS || returned_beats != BEATS || ar_count < 2)
                                fail("positive FENCE before all frame bytes and groups completed");
                        end else if ($isunknown(out_data[104:97]) || out_data[104:97] == 0 ||
                                     (expected_error >= 0 && int'(out_data[104:97]) != expected_error)) begin
                            fail($sformatf("bad failure error got=%0d expected=%0d", out_data[104:97], expected_error));
                        end
                        if (out_ready) begin
                            fence_count = fence_count + 1;
                            $display("FENCE case=%s job=%h cycle=%0d ok=%b err=%0d groups=%0d observed_DATA=%0d",
                                     case_name, job_id, cycle, out_data[96], out_data[104:97], out_data[31:0], data_count);
                        end
                    end
                    default: fail("unknown output token kind");
                endcase
            end
        end
    end

    task automatic tick;
        @(negedge clk);
    endtask

    task automatic common_reset;
        stage = "common reset";
        rst_n = 0;
        service_rst_n = 0;
        start_valid = 0;
        cancel = 0;
        out_ready = 0;
        done_ready = 0;
        arready = 0;
        rvalid = 0;
        drop_start = 0;
        mask_active = 0;
        no_new_ar = 0;
        isolate_bad_response = 0;
        repeat (4) tick();
        rst_n = 1;
        service_rst_n = 1;
        tick();
    endtask

    task automatic begin_job(input integer sequence_id, input [27:0] frame_base,
                             input bit ok, input integer error_code);
        stage = "job START";
        sequence_number = sequence_id;
        base = frame_base;
        job_id = 64'h8e17_35a0_1234_f000 + 64'(sequence_id);
        expected_ok = ok;
        expected_error = error_code;
        no_new_ar = 0;
        start_valid = 1;
        while (!job_live) tick();
        start_valid = 0;
    endtask

    task automatic take_ar(input integer wait_cycles);
        integer prior_count;
        stage = "AR presentation and acceptance";
        prior_count = ar_count;
        while (arvalid !== 1'b1) tick();
        repeat (wait_cycles) tick();
        arready = 1;
        tick();
        arready = 0;
        if (ar_count != prior_count + 1) fail("presented AR did not handshake");
    endtask

    task automatic return_beat(input [3:0] response_id, input bit last,
                               input [1:0] response, input bit stop_now);
        integer prior_count;
        stage = "R acceptance";
        prior_count = returned_beats;
        rid = response_id;
        rlast = last;
        rresp = response;
        rdata = memory_beat(sequence_number, prior_count);
        rvalid = 1;
        for (integer wait_cycles = 0; wait_cycles < 256; wait_cycles = wait_cycles + 1) begin
            #1;
            if (stop_now && rready === 1'b1) cancel = 1;
            tick();
            if (returned_beats != prior_count) begin
                rvalid = 0;
                cancel = 0;
                if (stop_now && !stop_on_final_r) fail("STOP did not coincide with the final R handshake");
                return;
            end
            if (cancel) fail("STOP blocked the intended coincident final R handshake");
        end
        fail("RVALID held for 256 clocks without acceptance");
    endtask

    task automatic drain_burst;
        while (r_debt != 0) return_beat(4'd1, r_debt == 1, 2'b00, 0);
    endtask

    task automatic complete_frame(input bit stop_at_final_r);
        while (requested_beats < BEATS) begin
            take_ar(2);
            while (r_debt != 0)
                return_beat(4'd1, r_debt == 1, 2'b00, stop_at_final_r && returned_beats == BEATS - 1);
        end
    endtask

    task automatic finish_job(input integer stall_cycles, input bit stop_during_fence);
        stage = "FENCE delivery";
        if (stall_cycles != 0) begin
            out_ready = 0;
            while (!(out_valid && out_data[146:145] == 2'd1)) tick();
            tick();
            if (fence_count != 0) fail("FENCE was consumed before its stall");
            $display("FENCE_STALL case=%s job=%h cycle=%0d ok=%b clocks=%0d stop=%b",
                     case_name, job_id, cycle, out_data[96], stall_cycles, stop_during_fence);
            cancel = stop_during_fence;
            repeat (stall_cycles) tick();
            cancel = 0;
            out_ready = 1;
        end
        while (fence_count == 0) tick();
        stage = "DONE delivery";
        while (!done_valid) tick();
        repeat (5) tick();
        done_ready = 1;
        tick();
        done_ready = 0;
        if (job_live) fail("DONE did not handshake");
        stage = "decoder release and reader rearm";
        while (dec_active || !start_ready) tick();
        if (bus_quiet !== 1'b1 || fault !== 1'b0)
            fail("completed job did not release the bus and decoder cleanly");
        $display("DONE case=%s job=%h cycle=%0d ok=%b ar=%0d r=%0d DATA=%0d",
                 case_name, job_id, cycle, expected_ok, ar_count, returned_beats, data_count);
    endtask

    task automatic normal_job(input integer sequence_id, input [27:0] frame_base,
                              input bit first_backpressure, input bit stall_good_fence);
        out_ready = !first_backpressure;
        begin_job(sequence_id, frame_base, 1, 0);
        if (first_backpressure) begin
            take_ar(8);
            repeat (11) tick();
            stage = "first R with ordinary DATA backpressure";
            return_beat(4'd1, r_debt == 1, 2'b00, 0);
            if (first_r_out_ready) fail("first R was accepted only after output backpressure cleared");
            repeat (8) tick();
            out_ready = 1;
            drain_burst();
        end
        complete_frame(0);
        if (stall_good_fence) begin
            while (data_count < GROUPS) tick();
            finish_job(9, 1);
        end else begin
            finish_job(0, 0);
        end
    endtask

    task automatic lose_context(input integer skew_ns, input integer low_ns);
        if (dec_active !== 1'b1) fail("setup did not establish a real decoder context");
        no_new_ar = 1;
        $display("LOCAL_RESET case=%s stage=%s cycle=%0d skew_ns=%0d low_ns=%0d AR=%0d debt=%0d DATA=%0d out_valid=%b",
                 case_name, stage, cycle, skew_ns, low_ns, ar_count, r_debt, data_count, out_valid);
        #(skew_ns) service_rst_n = 0;
        #(low_ns) service_rst_n = 1;
        #1;
        if (dec_active !== 1'b0) fail("setup local reset did not clear public decoder active");
        tick();
    endtask

    task automatic lost_start_job(input bit hide_active);
        out_ready = 1;
        mask_active = hide_active;
        drop_start = !hide_active;
        begin_job(11, 28'h004000, 0, 6);
        stage = "decode START boundary injection";
        while (reader_start_count == 0) tick();
        drop_start = 0;
        finish_job(0, 0);
        if (ar_count != 0 || service_start_count != int'(hide_active))
            fail("START boundary injection was not isolated");
        mask_active = 0;
        normal_job(12, 28'h006000, 0, 0);
    endtask

    task automatic active_loss_job(input string point);
        out_ready = 1;
        begin_job(22, 28'h008000, 0, -1);
        if (point == "before_ar") begin
            stage = "after real START and before first AR";
            while (dec_active !== 1'b1) tick();
            if (arvalid || service_start_count != 1) fail("setup missed the pre-AR context window");
            lose_context(1, 6);
        end else if (point == "held_ar") begin
            stage = "AR held by downstream backpressure";
            while (arvalid !== 1'b1) tick();
            repeat (3) tick();
            lose_context(3, 4);
            take_ar(6);
            repeat (7) tick();
            drain_burst();
        end else if (point == "accepted_ar") begin
            take_ar(4);
            repeat (7) tick();
            stage = "accepted AR and delayed first R";
            lose_context(4, 2);
            repeat (6) tick();
            drain_burst();
        end else if (point == "between_bursts") begin
            take_ar(2);
            drain_burst();
            stage = "after first burst and before second AR";
            if (arvalid || requested_beats >= BEATS) fail("setup missed the inter-burst window");
            lose_context(2, 4);
        end else if (point == "decoder_tail") begin
            complete_frame(0);
            out_ready = 0;
            stage = "all R accepted and tail DATA stalled";
            if (fence_count != 0 || data_count == GROUPS) fail("setup missed the decoder tail");
            while (!(out_valid && out_data[146:145] == 2'd0)) tick();
            repeat (2) tick();
            lose_context(4, 2);
            repeat (6) tick();
            out_ready = 1;
        end else begin
            fail("unknown loss point");
        end
        finish_job(0, 0);
        normal_job(23, 28'h00a000, 0, 0);
    endtask

    task automatic stop_during_fence_job;
        out_ready = 0;
        begin_job(31, 28'h00c000, 0, -1);
        take_ar(3);
        no_new_ar = 1;
        cancel = 1;
        tick();
        cancel = 0;
        drain_burst();
        finish_job(9, 1);
        normal_job(32, 28'h00e000, 0, 1);
        normal_job(33, 28'h010000, 0, 0);
    endtask

    task automatic bad_shape_job(input bit wrong_id);
        out_ready = 1;
        begin_job(41, 28'h012000, 0, -1);
        take_ar(2);
        if (r_debt < 2) fail("setup needs an outstanding multi-beat burst");
        isolate_bad_response = 1;
        no_new_ar = 1;
        return_beat(wrong_id ? 4'd2 : 4'd1, !wrong_id, 2'b00, 0);
        stage = "malformed R with remaining response debt withheld";
        for (integer i = 0; i < 20; i = i + 1) begin
            tick();
            if (bus_quiet !== 1'b0 || start_ready !== 1'b0)
                fail("malformed response left outstanding debt but reader appeared rearmed or quiet");
        end
        if (fault !== 1'b1) fail("malformed R did not enter fault isolation");
        $display("ISOLATED case=%s cycle=%0d fault=%b quiet=%b owed=%0d",
                 case_name, cycle, fault, bus_quiet, r_debt);
        common_reset();
        normal_job(42, 28'h014000, 0, 0);
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) $fatal(1, "missing +CASE");
        common_reset();
        case (case_name)
            "normal": begin
                normal_job(1, 28'h002000, 1, 0);
                normal_job(2, 28'h002ff0, 0, 0);
            end
            "lost_start": lost_start_job(0);
            "unseen_active": lost_start_job(1);
            "before_ar", "held_ar", "between_bursts", "decoder_tail": active_loss_job(case_name);
            "accepted_ar": begin
                normal_job(21, 28'h006000, 0, 0);
                active_loss_job(case_name);
            end
            "stop_final_r": begin
                out_ready = 1;
                begin_job(30, 28'h00c000, 0, -1);
                complete_frame(1);
                if (!stop_on_final_r) fail("setup missed STOP on the final R handshake");
                $display("STOP_LAST_R case=%s cycle=%0d R=%0d", case_name, cycle, returned_beats);
                finish_job(0, 0);
                normal_job(31, 28'h00e000, 0, 0);
            end
            "stop_fence_stall": stop_during_fence_job();
            "wrong_rid": bad_shape_job(1);
            "early_rlast": bad_shape_job(0);
            "rresp": begin
                out_ready = 1;
                begin_job(51, 28'h016000, 0, -1);
                take_ar(2);
                return_beat(4'd1, r_debt == 1, 2'b10, 0);
                drain_burst();
                while (fence_count == 0) begin
                    if (arvalid) begin
                        take_ar(1);
                        drain_burst();
                    end else begin
                        tick();
                    end
                end
                finish_job(0, 0);
                normal_job(52, 28'h018000, 0, 0);
            end
            default: fail("unknown case");
        endcase
        repeat (3) tick();
        $display("READER_CASE_PASS case=%s cycles=%0d", case_name, cycle);
        $finish;
    end

    initial begin
        #50000;
        fail("simulation watchdog expired");
    end
endmodule
