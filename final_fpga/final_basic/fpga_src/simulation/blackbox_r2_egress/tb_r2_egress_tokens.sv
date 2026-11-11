`timescale 1ns/1ps

module tb_r2_egress_tokens;
    import egress_vectors::*;
    logic sink_clk = 0;
    logic rst_n = 1;
    always #5 sink_clk = ~sink_clk;
    logic [146:0] i_token_data = '0;
    logic i_token_valid = 0;
    logic o_token_ready, o_token_pending;
    `include "egress_sink_checks.svh"

    ordered_frame_egress #(
        .CONTEXT_ENABLE(1), .WRITE_TAG_ENABLE(1), .RECORD_EXTENSION_ENABLE(1),
        .RECORD_EXTENSION_WIDTH(16384), .MASK_CONTEXT_ENABLE(0), .EXTENSION_RAM_ENABLE(1)
    ) dut (.i_clk(sink_clk), .i_rst_n(rst_n), .*);

    function automatic logic [146:0] context_token(input frame_t frame);
        return {2'b11, frame.tag, 8'd1, frame.capture_id, frame.quality,
                frame.camera, frame.epoch, frame.session};
    endfunction

    function automatic logic [146:0] start_token(input frame_t frame);
        return {2'b10, 17'b0, frame.timestamp_ns, frame.height, frame.width, frame.capture_id};
    endfunction

    function automatic logic [146:0] jpeg_token(input frame_t frame, input integer beat,
                                                input bit last);
        return {2'b00, last, jpeg_keep(last), jpeg_bytes(frame, beat, last)};
    endfunction

    function automatic logic [146:0] ext_token(input integer index, input logic [127:0] data);
        return {2'b11, 17'(index), data};
    endfunction

    function automatic logic [146:0] fence_token(input frame_t frame, input integer bytes_seen,
                                                 input logic [24:0] length, input bit ok,
                                                 input logic [7:0] error_code);
        return {2'b01, 13'b0, frame.epoch, frame.quality, 26'(bytes_seen),
                error_code, ok, length, frame.capture_id};
    endfunction

    task automatic reset;
        @(negedge sink_clk);
        rst_n = 0;
        i_token_valid = 0;
        repeat (4) @(negedge sink_clk);
        rst_n = 1;
        check_quiet(3);
        if (o_protocol_fault !== 1'b0)
            $fatal(1, "egress fault survived reset");
    endtask

    task automatic send(input logic [146:0] token);
        @(negedge sink_clk);
        i_token_data = token;
        i_token_valid = 1;
        do @(posedge sink_clk); while (o_token_ready !== 1'b1);
    endtask

    task automatic clear_input;
        @(negedge sink_clk); i_token_valid = 0;
    endtask

    task automatic send_prefix(input frame_t frame, input integer beats, input bit ends);
        send(context_token(frame));
        send(start_token(frame));
        for (integer beat = 0; beat < beats; beat++)
            send(jpeg_token(frame, beat, ends && beat == beats - 1));
    endtask

    task automatic send_extension(input extension_t bytes, input integer flits);
        for (integer index = 0; index < flits; index++)
            send(ext_token(index, bytes[128*index +: 128]));
    endtask

    task automatic enter_extension(input frame_t frame);
        fork
            begin
                send_prefix(frame, 1, 1);
                clear_input();
            end
            begin
                hold_start(frame, 1);
                take_start(frame);
                take_jpeg(frame, 1, 1, 0, 0, 0);
            end
        join
    endtask

    task automatic check_quarantine;
        frame_t successor;
        integer step;
        bit consumed, probe_offer;
        successor = fixture(32'h43, 6);
        step = 0;
        probe_offer = 0;
        repeat (16) begin
            @(negedge sink_clk);
            // Attempt a complete, legal START if the faulting word is no longer held.
            if (!i_token_valid && step < 2) begin
                i_token_data = step == 0 ? context_token(successor) : start_token(successor);
                i_token_valid = 1;
                probe_offer = 1;
            end
            @(posedge sink_clk);
            if (o_protocol_fault !== 1'b1 ||
                {o_start_valid, o_jpeg_tvalid, o_record_extension_valid, o_result_valid} !== 4'b0)
                $fatal(1, "fault failed to quarantine successive offers");
            consumed = i_token_valid && o_token_ready === 1'b1;
            if (consumed) begin
                @(negedge sink_clk);
                i_token_valid = 0;
                if (probe_offer)
                    step++;
            end
        end
    endtask

    task automatic malformed(input logic [146:0] token);
        bit consumed, token_was_accepted;
        token_was_accepted = 0;
        @(negedge sink_clk);
        i_token_valid = 1;
        i_token_data = token;
        repeat (32) begin
            @(posedge sink_clk);
            consumed = i_token_valid && o_token_ready === 1'b1;
            if ({o_start_valid, o_jpeg_tvalid, o_record_extension_valid, o_result_valid} !== 4'b0)
                $fatal(1, "malformed token produced downstream offer");
            @(negedge sink_clk);
            if (consumed) begin
                i_token_valid = 0;
                token_was_accepted = 1;
            end
        end
        if (o_protocol_fault !== 1'b1)
            $fatal(1, "malformed token raised no protocol fault: %h accepted=%b",
                   token, token_was_accepted);
        check_quarantine();
    endtask

    task automatic damaged_flit(input frame_t frame, input integer index, input integer bit_no);
        extension_t value;
        logic [127:0] damaged;
        $display("CASE extension bit damage flit=%0d bit=%0d", index, bit_no);
        reset();
        enter_extension(frame);
        value = extension_for(frame);
        send_extension(value, index);
        damaged = value[128*index +: 128];
        damaged[bit_no] = ~damaged[bit_no];
        malformed(ext_token(index, damaged));
    endtask

    task automatic damaged_base(input frame_t frame, input integer index, input integer bit_no);
        extension_t value;
        bit all_flits_accepted, fault_seen, checked;
        $display("CASE complete extension with base damage flit=%0d bit=%0d", index, bit_no);
        reset();
        enter_extension(frame);
        value = extension_for(frame);
        value[128*index + bit_no] = ~value[128*index + bit_no];
        all_flits_accepted = 0;
        fault_seen = 0;
        checked = 0;
        @(negedge sink_clk);
        i_record_extension_ready = 1;
        i_result_ready = 1;
        fork : bad_base_case
            begin
                send_extension(value, 128);
                all_flits_accepted = 1;
                send(fence_token(frame, 11, 25'd11, 1, 0));
                clear_input();
            end
            begin
                repeat (1400) begin
                    @(posedge sink_clk);
                    if ({o_extension_shape_valid, o_record_extension_valid, o_result_valid}
                        !== 3'b0)
                        $fatal(1, "bad extension base exposed shape, extension or RESULT");
                    if (fault_seen && o_protocol_fault !== 1'b1)
                        $fatal(1, "bad extension base fault cleared before reset");
                    if (o_protocol_fault === 1'b1)
                        fault_seen = 1;
                end
                if (!all_flits_accepted || !fault_seen)
                    $fatal(1, "bad extension did not reach a failure terminal, flits_done=%b",
                           all_flits_accepted);
                checked = 1;
            end
        join_none
        wait (checked);
        disable bad_base_case;
        @(negedge sink_clk);
        i_record_extension_ready = 0;
        i_result_ready = 0;
    endtask

    task automatic terminal(input frame_t frame, input integer beats, input bit ends,
                            input integer damage, input bit full_rate);
        frame_t fence_frame;
        logic [24:0] length;
        logic [7:0] error_code, expected_error;
        integer bytes_seen;
        bit expected_ok;
        fence_frame = frame;
        bytes_seen = integer'(jpeg_length(beats, ends));
        length = ends ? 25'(bytes_seen) : 25'd0;
        error_code = ends ? 8'h00 : 8'h5a;
        expected_error = error_code;
        case (damage)
            1: begin bytes_seen++; expected_error = 8'he3; end
            2: begin fence_frame.capture_id ^= 32'h1000; expected_error = 8'he3; end
            3: begin fence_frame.epoch ^= 32'h0080; expected_error = 8'he4; end
            4: begin fence_frame.quality ^= 8'h04; expected_error = 8'he4; end
            default: ;
        endcase
        expected_ok = ends && damage == 0;
        $display("CASE terminal capture=%h damage=%0d last=%b", frame.capture_id, damage, ends);
        fork
            begin
                send_prefix(frame, beats, ends);
                send_extension(extension_for(frame), 128);
                send(fence_token(fence_frame, bytes_seen, length, ends, error_code));
                clear_input();
            end
            begin
                hold_start(frame, 4);
                take_start(frame);
                take_jpeg(frame, beats, ends, 4, 0, full_rate);
                hold_extension(5);
                if (full_rate)
                    read_words(extension_for(frame), 0, 409, 1);
                take_extension();
                hold_result(frame, length, expected_ok, expected_error, 6, damage == 0);
                if (o_protocol_fault !== 1'b0 && damage < 3)
                    $fatal(1, "early fault before RESULT transfer");
                take_result();
            end
        join
        if (damage == 1 || damage == 2)
            check_quarantine();
        else
            check_quiet(8);
        if (damage == 0 && o_protocol_fault !== 1'b0)
            $fatal(1, "legal terminal raised protocol fault");
    endtask

    initial begin : scenarios
        frame_t frame, successor;
        extension_t value;
        frame = fixture(32'hffff_ffff, 1);
        successor = fixture(32'h0, 2);
        value = extension_for(frame);

        $display("CASE orphan START");
        reset();
        malformed(start_token(frame));

        $display("CASE START and CONTEXT sequence mismatch");
        reset();
        send(context_token(frame));
        malformed(start_token(successor));

        damaged_flit(frame, 0, 0);   // magic
        damaged_flit(frame, 0, 32);  // schema
        damaged_flit(frame, 0, 48);  // identity
        damaged_flit(frame, 0, 60);  // reserved
        damaged_flit(frame, 0, 64);  // session low half
        damaged_flit(frame, 0, 80);  // session high half
        damaged_flit(frame, 0, 96);  // epoch low half
        damaged_flit(frame, 0, 112); // epoch high half
        damaged_base(frame, 1, 7);   // sequence
        damaged_base(frame, 1, 32);  // camera
        damaged_base(frame, 1, 39);  // camera zero extension
        damaged_base(frame, 1, 107); // reserved
        damaged_base(frame, 7, 51);  // reserved

        $display("CASE first EXT index skipped");
        reset();
        enter_extension(frame);
        malformed(ext_token(1, value[0 +: 128]));

        $display("CASE repeated flit0");
        reset();
        enter_extension(frame);
        send_extension(value, 1);
        malformed(ext_token(0, value[128 +: 128]));

        $display("CASE tail EXT index repeated");
        reset();
        enter_extension(frame);
        send_extension(value, 127);
        malformed(ext_token(126, value[127*128 +: 128]));

        $display("CASE early FENCE");
        reset();
        enter_extension(frame);
        send_extension(value, 127);
        malformed(fence_token(frame, 11, 25'd11, 1, 0));

        $display("CASE JPEG after LAST");
        reset();
        enter_extension(frame);
        malformed(jpeg_token(frame, 1, 0));

        for (integer damage = 1; damage <= 4; damage++) begin
            reset();
            terminal(frame, 2, 1, damage, 0);
        end

        reset();
        terminal(frame, 24, 1, 0, 1);
        terminal(successor, 3, 0, 0, 0);
        terminal(fixture(32'd1, 3), 2, 1, 0, 0);
        $display("R2_EGRESS_TOKENS PASS");
        $finish;
    end

    initial #200000 $fatal(1, "token suite simulation watchdog");
endmodule
