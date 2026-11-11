`timescale 1ns/1ps
module tb_packer #(
    parameter integer MAX_BYTES = 17
);
    reg clk = 0;
    always #4 clk = ~clk;

    reg rst_n = 0;
    reg abort_frame = 0;
    reg in_valid = 0;
    reg in_last = 0;
    reg [7:0] in_byte = 0;
    wire in_ready;
    wire [127:0] out_data;
    wire [15:0] out_keep;
    wire out_valid;
    reg out_ready = 0;
    wire out_last;
    wire frame_error, overflow, idle;

    jpeg_byte_packer #(.MAX_PAYLOAD_BYTES(MAX_BYTES)) dut (
        .i_clk(clk), .i_rst_n(rst_n), .i_abort(abort_frame),
        .i_byte(in_byte), .i_valid(in_valid), .o_ready(in_ready),
        .i_last(in_last), .o_axis_tdata(out_data), .o_axis_tkeep(out_keep),
        .o_axis_tvalid(out_valid), .i_axis_tready(out_ready),
        .o_axis_tlast(out_last), .o_frame_error(frame_error),
        .o_overflow(overflow), .o_idle(idle)
    );

    // Accepted bytes carry their source LAST bit. Pop only on a real AXIS transfer.
    logic [8:0] pending[$];
    integer cycle = 0;
    integer input_bytes = 0;
    integer error_due = -1;
    bit closing = 0;
    bit discarding = 0;
    bit abort_drain = 0;
    bit input_held = 0;
    bit output_held = 0;
    logic [8:0] held_input;
    logic [144:0] held_output;
    bit held_output_last;
    integer held_count;

    bit took_input, took_output;
    bit sampled_valid, sampled_last;
    integer input_transfers = 0;
    integer output_transfers = 0;
    integer prefix_transfers = 0;
    integer completed = 0;
    integer error_pulses = 0;
    integer abort_beats = 0;
    integer abort_tails = 0;
    integer input_stalls = 0;
    integer output_stalls = 0;
    integer tail_stalls = 0;
    integer same_edge = 0;
    bit [15:0] tail_sizes = 0;

    task automatic trim_queue(input integer retain);
        while (pending.size() > retain)
            void'(pending.pop_back());
    endtask

    always @(posedge clk) begin : score
        integer size;
        bit last;
        bit [15:0] keep;
        cycle = cycle + 1;
        took_input = 0;
        took_output = 0;
        sampled_valid = 0;
        sampled_last = 0;

        if (!rst_n) begin
            pending.delete();
            input_bytes = 0;
            error_due = -1;
            closing = 0;
            discarding = 0;
            abort_drain = 0;
            input_held = 0;
            output_held = 0;
        end else begin
            if ((^{in_ready, out_valid, frame_error, overflow, idle}) === 1'bx)
                $fatal(1, "cycle %0d has unknown interface control", cycle);
            if (input_held && (!in_valid || {in_last, in_byte} !== held_input))
                $fatal(1, "fixture changed an unaccepted source byte at cycle %0d", cycle);
            if (output_held &&
                (!out_valid || {out_data, out_keep, out_last} !== held_output))
                $fatal(1, "cycle %0d changed held AXIS DATA/KEEP/LAST", cycle);
            if (abort_frame && in_ready)
                $fatal(1, "cycle %0d input READY high during abort", cycle);

            took_input = in_valid && in_ready;
            took_output = out_valid && out_ready;
            sampled_valid = out_valid;
            sampled_last = out_last;

            if (abort_frame) begin
                input_bytes = 0;
                discarding = 0;
                closing = output_held && held_output_last;
                abort_drain = output_held;
                trim_queue(output_held ? held_count : 0);
            end
            if (took_input) begin
                input_transfers = input_transfers + 1;
                if (closing || abort_drain)
                    $fatal(1, "cycle %0d accepted next frame before pending offer drained", cycle);
                if (discarding) begin
                    if (in_last)
                        discarding = 0;
                end else if (input_bytes == MAX_BYTES) begin
                    if (error_due >= 0)
                        $fatal(1, "cycle %0d second overflow while previous error pending", cycle);
                    // Error is registered at the overlong-byte acceptance edge.
                    error_due = cycle + 1;
                    discarding = !in_last;
                    input_bytes = 0;
                    trim_queue(output_held ? held_count : 0);
                    $display("MAX=%0d excess byte accepted cycle=%0d last=%0b", MAX_BYTES, cycle, in_last);
                end else begin
                    pending.push_back({in_last, in_byte});
                    input_bytes = input_bytes + 1;
                    if (in_last) begin
                        closing = 1;
                        input_bytes = 0;
                    end
                end
            end

            if (frame_error !== overflow)
                $fatal(1, "cycle %0d overflow and frame_error disagree", cycle);
            if (overflow) begin
                if (cycle != error_due)
                    $fatal(1, "cycle %0d overflow pulse expected at cycle %0d", cycle, error_due);
                error_due = -1;
                error_pulses = error_pulses + 1;
                $display("MAX=%0d error pulse cycle=%0d", MAX_BYTES, cycle);
            end else if (cycle == error_due) begin
                $fatal(1, "cycle %0d missing overflow/frame_error pulse", cycle);
            end

            if (out_valid) begin
                if (idle)
                    $fatal(1, "cycle %0d idle while AXIS offer pending", cycle);
                size = 0;
                last = 0;
                keep = 0;
                while (size < 16 && size < pending.size() && !last) begin
                    last = pending[size][8];
                    if (out_data[size*8 +: 8] !== pending[size][7:0])
                        $fatal(1, "cycle %0d lane %0d data %02h expected %02h",
                               cycle, size, out_data[size*8 +: 8], pending[size][7:0]);
                    keep[size] = 1;
                    size = size + 1;
                end
                if (!last && size != 16)
                    $fatal(1, "cycle %0d emitted incomplete nonterminal beat, %0d bytes queued", cycle, size);
                if (out_keep !== keep || out_last !== last)
                    $fatal(1, "cycle %0d KEEP/LAST %04h/%0b expected %04h/%0b",
                           cycle, out_keep, out_last, keep, last);
                if (took_output) begin
                    repeat (size)
                        void'(pending.pop_front());
                    output_transfers = output_transfers + 1;
                    if (abort_drain) begin
                        abort_beats = abort_beats + 1;
                        if (last)
                            abort_tails = abort_tails + 1;
                        abort_drain = 0;
                    end else if (last) begin
                        completed = completed + 1;
                        tail_sizes[size-1] = 1;
                    end else begin
                        prefix_transfers = prefix_transfers + 1;
                        if (took_input)
                            same_edge = same_edge + 1;
                    end
                    if (last)
                        closing = 0;
                end else begin
                    held_count = size;
                    output_stalls = output_stalls + 1;
                    if (last)
                        tail_stalls = tail_stalls + 1;
                end
            end
            output_held = out_valid && !out_ready;
            held_output = {out_data, out_keep, out_last};
            held_output_last = out_last;
            input_held = in_valid && !in_ready;
            held_input = {in_last, in_byte};
            if (input_held)
                input_stalls = input_stalls + 1;
        end
    end

    task automatic step(
        input bit valid = 0, input byte unsigned data = 0, input bit last = 0,
        input bit ready = 1, input bit abort_now = 0, input bit reset_n = 1
    );
        @(negedge clk);
        in_valid = valid;
        in_byte = data;
        in_last = last;
        out_ready = ready;
        abort_frame = abort_now;
        rst_n = reset_n;
        @(posedge clk);
        #1;
    endtask

    function automatic byte unsigned sample_byte(input integer seed, input integer offset);
        return (73 * seed + 29 * offset + 7 * offset * offset);
    endfunction

    task automatic send_byte(
        input byte unsigned data, input bit last, input bit ready = 1
    );
        for (integer attempt = 0; attempt < 24; attempt = attempt + 1) begin
            step(1, data, last, ready);
            if (took_input)
                return;
        end
        $fatal(1, "cycle %0d timed out offering input byte %02h LAST=%0b", cycle, data, last);
    endtask

    task automatic wait_offer(input bit last);
        for (integer attempt = 0; attempt < 12; attempt = attempt + 1) begin
            step(0, 0, 0, 0);
            if (sampled_valid) begin
                if (sampled_last !== last)
                    $fatal(1, "cycle %0d expected stalled LAST=%0b", cycle, last);
                return;
            end
        end
        $fatal(1, "cycle %0d missing expected stalled offer LAST=%0b", cycle, last);
    endtask

    task automatic expect_idle;
        for (integer attempt = 0; attempt < 12; attempt = attempt + 1) begin
            step();
            if (idle && in_ready && !sampled_valid) begin
                repeat (2) begin
                    step();
                    if (!idle || !in_ready || sampled_valid)
                        $fatal(1, "cycle %0d idle did not persist", cycle);
                end
                if (pending.size() || closing || discarding || input_bytes || abort_drain)
                    $fatal(1, "cycle %0d DUT idle before scoreboard drained", cycle);
                return;
            end
        end
        $fatal(1, "cycle %0d idle did not recover", cycle);
    endtask

    task automatic finish_frame(input integer goal);
        for (integer attempt = 0; attempt < 12 && completed < goal; attempt = attempt + 1)
            step();
        if (completed != goal)
            $fatal(1, "cycle %0d frame did not reach terminal, completed %0d expected %0d",
                   cycle, completed, goal);
        expect_idle();
    endtask

    task automatic good_frame(input integer length, input integer seed);
        integer goal;
        goal = completed + 1;
        for (integer offset = 0; offset < length; offset = offset + 1) begin
            if ((offset % 5) == 2)
                step();
            send_byte(sample_byte(seed, offset), offset == length-1);
        end
        finish_frame(goal);
    endtask

    task automatic reject_frame(input bit last_on_excess, input integer seed);
        integer before_prefix, before_done, before_error;
        before_prefix = prefix_transfers;
        before_done = completed;
        before_error = error_pulses;
        for (integer offset = 0; offset < MAX_BYTES; offset = offset + 1)
            send_byte(sample_byte(seed, offset), 0);
        repeat (3) step();
        if (prefix_transfers != before_prefix + 1)
            $fatal(1, "cycle %0d missing committed prefix before overflow", cycle);
        send_byte(sample_byte(seed, MAX_BYTES), last_on_excess);
        if (!last_on_excess) begin
            // Enough discarded bytes to expose an incorrectly restarted frame.
            for (integer offset = 1; offset <= 20; offset = offset + 1)
                send_byte(sample_byte(seed, MAX_BYTES + offset), offset == 20);
        end
        expect_idle();
        if (error_pulses != before_error + 1 || completed != before_done)
            $fatal(1, "cycle %0d overflow had incorrect failure/terminal counts", cycle);
        good_frame(MAX_BYTES, seed + 1);
    endtask

    task automatic abort_visible(input bit terminal, input integer seed);
        integer before_aborts, before_tails, before_done;
        before_aborts = abort_beats;
        before_tails = abort_tails;
        before_done = completed;
        for (integer offset = 0; offset < (terminal ? 6 : 16); offset = offset + 1)
            send_byte(sample_byte(seed, offset), terminal && offset == 5, 0);
        wait_offer(terminal);
        repeat (3) step(0, 0, 0, 0, 1);
        if (terminal) begin
            // Deassert abort before releasing the previously offered tail.
            repeat (2) step(0, 0, 0, 0);
            step();
        end else begin
            step(0, 0, 0, 1, 1);
        end
        if (!took_output || sampled_last !== terminal)
            $fatal(1, "cycle %0d committed abort offer failed to drain", cycle);
        expect_idle();
        if (abort_beats != before_aborts + 1 || abort_tails != before_tails + terminal ||
            completed != before_done)
            $fatal(1, "cycle %0d incorrect abort drain counts", cycle);
        good_frame(7, seed + 1);
    endtask

    initial begin : stimulus
        integer goal, before_done;
        $display("PACKER START MAX=%0d", MAX_BYTES);
        repeat (3) step(0, 0, 0, 0, 0, 0);

        for (integer length = 1; length <= MAX_BYTES; length = length + 1)
            good_frame(length, length);
        $display("MAX=%0d scored every legal length 1..%0d", MAX_BYTES, MAX_BYTES);

        goal = completed + 1;
        for (integer offset = 0; offset < 16; offset = offset + 1)
            send_byte(sample_byte(101, offset), 0, 0);
        wait_offer(0);
        repeat (3) step(0, 0, 0, 0);
        step(1, sample_byte(101, 16), 1);
        if (!took_input || !took_output || sampled_last)
            $fatal(1, "cycle %0d full prefix failed simultaneous output and successor input", cycle);
        $display("MAX=%0d full prefix transferred with successor byte at cycle=%0d", MAX_BYTES, cycle);
        finish_frame(goal);

        goal = completed + 2;
        send_byte(sample_byte(102, 0), 1, 0);
        wait_offer(1);
        repeat (3) begin
            step(1, sample_byte(103, 0), 1, 0);
            if (took_input)
                $fatal(1, "cycle %0d accepted new frame with stalled terminal", cycle);
        end
        step(1, sample_byte(103, 0), 1);
        if (!took_output || !sampled_last || took_input)
            $fatal(1, "cycle %0d terminal precedence violated", cycle);
        send_byte(sample_byte(103, 0), 1);
        finish_frame(goal);

        reject_frame(1, 104);
        reject_frame(0, 106);

        before_done = completed;
        repeat (5) send_byte(sample_byte(108, cycle), 0, 0);
        repeat (2) step(0, 0, 0, 0, 1);
        expect_idle();
        if (completed != before_done)
            $fatal(1, "cycle %0d partial abort completed a frame", cycle);
        good_frame(3, 109);
        abort_visible(0, 110);
        abort_visible(1, 112);

        before_done = completed;
        send_byte(sample_byte(114, 0), 1, 0);
        wait_offer(1);
        repeat (3) step(0, 0, 0, 0, 0, 0);
        good_frame(MAX_BYTES, 115);
        if (completed != before_done + 1)
            $fatal(1, "cycle %0d reset leaked a pre-reset tail", cycle);

        if (tail_sizes != 16'hffff || same_edge == 0 || error_pulses != 2 ||
            abort_beats != 2 || abort_tails != 1 || input_stalls < 4 || tail_stalls < 4)
            $fatal(1, "MAX=%0d missing requested coverage", MAX_BYTES);
        $display("PACKER PASS MAX=%0d cycles=%0d frames=%0d in=%0d out=%0d tails=%04h same_edge=%0d in_stall=%0d out_stall=%0d tail_stall=%0d errors=%0d abort_drains=%0d abort_tails=%0d",
                 MAX_BYTES, cycle, completed, input_transfers, output_transfers, tail_sizes,
                 same_edge, input_stalls, output_stalls, tail_stalls, error_pulses, abort_beats, abort_tails);
        $finish;
    end

    initial begin
        #24000;
        $fatal(1, "MAX=%0d hit simulation watchdog", MAX_BYTES);
    end
endmodule
