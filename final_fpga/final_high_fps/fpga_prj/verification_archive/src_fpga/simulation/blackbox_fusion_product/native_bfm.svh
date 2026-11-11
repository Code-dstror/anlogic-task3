    int user_cycles = 0;
    int cc_count = 0;
    logic [127:0] last_cc = 0;
    logic [3:0] last_cc_keep = 0;
    bit last_cc_last = 0;
    logic [7:0] next_cq_tag = 'h80;
    bit [7:0] host_memory[int unsigned];
    int host_packet_count = 0, host_bytes = 0, tlp_stalls = 0;
    int packet_bytes_left = 0, packet_bytes_total = 0, packet_offset = 0;
    logic [7:0] packet_be = 0;
    bit held_tlp_header_valid = 0, held_tlp_data_valid = 0, held_tlp_end = 0;
    logic [96:0] held_tlp_header;
    logic [127:0] held_tlp_data;
    int fence_count = 0, rc_count = 0, fence_cycle = 0;
    bit rc_taken = 0, host_ack_seen = 0;
    time safe_time = 0, host_ack_time = 0;
    logic [127:0] buffer_identity = 0;
    logic [63:0] host_session = 64'h6b33_f817_33b2_ba41;

    function automatic logic [31:0] host_word(input int offset);
        return {host_memory[offset + 3], host_memory[offset + 2],
                host_memory[offset + 1], host_memory[offset]};
    endfunction

    task automatic clear_host_frame;
        check(packet_bytes_left == 0 && !i_rc_valid, "unfinished PCIe packet at new frame");
        host_memory.delete();
        host_packet_count = 0;
        host_bytes = 0;
        tlp_stalls = 0;
        fence_count = 0;
        rc_count = 0;
        fence_cycle = 0;
        host_ack_seen = 0;
        safe_time = 0;
        host_ack_time = 0;
    endtask

    always @(posedge i_host_clk) begin : host_accepted
        int packet_position, host_address, data_bytes;
        bit enabled_byte;
        rc_taken = 0;
        if (o_user_reset_n) begin
            user_cycles++;
            if (o_cc_valid && i_cc_ready) begin
                cc_count++;
                last_cc = o_cc_data;
                last_cc_keep = o_cc_keep;
                last_cc_last = o_cc_last;
            end
            if (held_tlp_header_valid)
                check(o_tlp_header_valid &&
                      {o_tlp_address, o_tlp_byte_enable, o_tlp_byte_length,
                       o_tlp_format, o_tlp_tag} === held_tlp_header, "TLP header changed under HALT");
            if (held_tlp_data_valid)
                check(o_tlp_data_valid && o_tlp_data === held_tlp_data, "TLP data changed under HALT");
            if (held_tlp_header_valid || held_tlp_data_valid)
                check(o_tlp_end === held_tlp_end, "TLP END changed under HALT");
            held_tlp_header_valid = i_tlp_halt && o_tlp_header_valid;
            held_tlp_data_valid = i_tlp_halt && o_tlp_data_valid;
            held_tlp_header = {o_tlp_address, o_tlp_byte_enable, o_tlp_byte_length,
                               o_tlp_format, o_tlp_tag};
            held_tlp_data = o_tlp_data;
            held_tlp_end = o_tlp_end;
            if (held_tlp_header_valid || held_tlp_data_valid)
                tlp_stalls++;

            if (!i_tlp_halt && o_tlp_header_valid) begin
                check(frame_active && !frame_bad && last_jpeg_b > last_jpeg_wlast &&
                      jpeg_write_debt == 0, "PCIe record traffic before final B or on failed frame");
                check(packet_bytes_left == 0 && fence_count == 0, "unexpected TLP header overlap");
                check(!$isunknown({o_tlp_format, o_tlp_address, o_tlp_byte_length, o_tlp_tag}),
                      "TLP header contains unknown fields");
                if (o_tlp_format == 2 || o_tlp_format == 3) begin
                    check(o_tlp_data_valid && o_tlp_byte_length >= 4 &&
                          o_tlp_byte_length[1:0] == 0 && o_tlp_address[1:0] == 0,
                          "malformed posted write");
                    check(o_tlp_address >= HOST_BASE &&
                          o_tlp_address + o_tlp_byte_length <= HOST_BASE + BUFFER_BYTES,
                          "TLP write outside the armed host buffer");
                    check(int'(o_tlp_address[11:0]) + int'(o_tlp_byte_length) <= 4096,
                          "TLP crosses 4KiB boundary");
                    packet_bytes_left = int'(o_tlp_byte_length);
                    packet_bytes_total = packet_bytes_left;
                    packet_offset = int'(o_tlp_address - HOST_BASE);
                    packet_be = o_tlp_byte_enable;
                    check(!$isunknown(packet_be), "unknown byte enable");
                    host_packet_count++;
                end else begin
                    check(!o_tlp_data_valid && o_tlp_address == FENCE_ADDR &&
                          o_tlp_byte_length == 4 && o_tlp_tag == 'h1a, "malformed native fence");
                    check(host_bytes == HEADER_BYTES + jpeg_length && host_packet_count != 0,
                          "fence before complete host payload");
                    fence_count++;
                    fence_cycle = user_cycles;
                    $display("BB_FENCE seq=%0d bytes=%0d time_ns=%0t", expected_seq, host_bytes, $time);
                end
            end
            if (!i_tlp_halt && o_tlp_data_valid) begin
                check(packet_bytes_left > 0, "TLP payload without posted write header");
                data_bytes = packet_bytes_left < 16 ? packet_bytes_left : 16;
                for (int lane = 0; lane < data_bytes; lane++) begin
                    packet_position = packet_bytes_total - packet_bytes_left + lane;
                    host_address = packet_offset + packet_position;
                    if (packet_position < 4)
                        enabled_byte = packet_be[packet_position];
                    else if (packet_position >= packet_bytes_total - 4)
                        enabled_byte = packet_be[4 + packet_position % 4];
                    else
                        enabled_byte = 1;
                    if (enabled_byte) begin
                        check(!host_memory.exists(host_address),
                              $sformatf("duplicate host byte %0d", host_address));
                        check(!$isunknown(o_tlp_data[lane * 8 +: 8]), "unknown enabled TLP byte");
                        host_memory[host_address] = o_tlp_data[lane * 8 +: 8];
                        host_bytes++;
                    end
                end
                packet_bytes_left -= data_bytes;
                check(o_tlp_end == (packet_bytes_left == 0), "TLP END/length mismatch");
            end
            if (i_rc_valid && o_rc_ready) begin
                check(fence_count == 1 && rc_count == 0, "duplicate or unrequested fence completion");
                rc_count++;
                rc_taken = 1;
                $display("BB_RC seq=%0d cookie=%08x time_ns=%0t", expected_seq, FENCE_COOKIE, $time);
            end
        end else begin
            held_tlp_header_valid = 0;
            held_tlp_data_valid = 0;
        end
    end

    always @(negedge i_host_clk) begin
        i_cc_ready = o_user_reset_n && user_cycles % 5 != 1;
        i_tlp_halt = o_user_reset_n && user_cycles % 11 < 3;
        if (!o_user_reset_n || rc_taken)
            i_rc_valid = 0;
        if (o_user_reset_n && !i_rc_valid && fence_count == 1 && rc_count == 0 &&
            user_cycles >= fence_cycle + 7) begin
            i_rc_data = 0;
            i_rc_data[6:0] = FENCE_ADDR[6:0];
            i_rc_data[28:16] = 4;
            i_rc_data[30] = 1;
            i_rc_data[42:32] = 1;
            i_rc_data[71:64] = 'h1a;
            i_rc_data[127:96] = FENCE_COOKIE;
            i_rc_keep = 'hf;
            i_rc_user = 0;
            i_rc_user[42] = 1;
            i_rc_last = 1;
            i_rc_valid = 1;
        end
    end

    task automatic cq_transfer(input logic [127:0] data, input logic [3:0] keep,
                               input bit last, input bit host_ack);
        @(negedge i_host_clk);
        i_cq_data = data;
        i_cq_keep = keep;
        i_cq_user = 'hf;
        i_cq_last = last;
        i_cq_valid = 1;
        do @(posedge i_host_clk); while (o_cq_ready !== 1'b1);
        if (host_ack) begin
            check(safe_time != 0 && !host_ack_seen, "ACK without SAFE_RESULT");
            host_ack_seen = 1;
            host_ack_time = $time;
            $display("BB_HOST_ACK seq=%0d time_ns=%0t", expected_seq, host_ack_time);
        end
        @(negedge i_host_clk);
        i_cq_valid = 0;
    endtask

    function automatic logic [127:0] cq_header(input logic [31:0] address,
                                                input bit write_request,
                                                input logic [7:0] request_tag);
        logic [127:0] header_bits;
        header_bits = 0;
        header_bits[31:0] = address;
        header_bits[74:64] = 1;
        header_bits[78:75] = write_request ? 1 : 0;
        header_bits[95:80] = 'h0010;
        header_bits[103:96] = request_tag;
        return header_bits;
    endfunction

    task automatic bar_read(input logic [31:0] address, output logic [31:0] value);
        int prior_cc_count;
        logic [7:0] tag;
        prior_cc_count = cc_count;
        tag = next_cq_tag;
        next_cq_tag++;
        cq_transfer(cq_header(address, 0, tag), 'hf, 1, 0);
        while (cc_count == prior_cc_count)
            @(negedge i_host_clk);
        check(cc_count == prior_cc_count + 1 && last_cc_keep == 'hf && last_cc_last &&
              last_cc[45:43] == 0 && last_cc[42:32] == 1 && last_cc[71:64] == tag,
              $sformatf("bad CC for BAR read addr=%05x tag=%02x cc=%032x keep=%x last=%b",
                        address, tag, last_cc, last_cc_keep, last_cc_last));
        value = last_cc[127:96];
    endtask

    task automatic bar_write(input logic [31:0] address, input logic [31:0] value);
        cq_transfer(cq_header(address, 1, next_cq_tag), 'hf, 0, 0);
        next_cq_tag++;
        cq_transfer({96'b0, value}, 1, 1, address == 'h008 && value == 16);
    endtask

    task automatic expect_register(input logic [31:0] address, input logic [31:0] expected);
        logic [31:0] readback;
        bar_read(address, readback);
        check(readback == expected,
              $sformatf("BAR[%05x]=%08x expected %08x", address, readback, expected));
    endtask

    task automatic poll_register(input logic [31:0] address, mask, expected);
        logic [31:0] readback, cfg_error, cfg_response;
        for (int retry = 0; retry < 2000; retry++) begin
            bar_read(address, readback);
            if ((readback & mask) === expected)
                return;
            if (address == APP_BASE + 'h244 && readback[3]) begin
                bar_read(APP_BASE + 'h24c, cfg_error);
                bar_read(APP_BASE + 'h248, cfg_response);
                check(0, $sformatf("CFG status=%08x error=%0d response_sequence=%0d",
                                   readback, cfg_error, cfg_response));
            end
        end
        check(0, $sformatf("BAR poll addr=%05x last=%08x mask=%08x expected=%08x",
                           address, readback, mask, expected));
    endtask

    task automatic arm_buffer(input logic [31:0] generation);
        poll_register('h00c, 'h3e, 0);
        buffer_identity = {host_session, generation, 32'h00000000};
        bar_write('h020, HOST_BASE[31:0]);
        bar_write('h024, HOST_BASE[63:32]);
        bar_write('h028, BUFFER_BYTES);
        for (int word_index = 0; word_index < 4; word_index++)
            bar_write('h030 + 4 * word_index, buffer_identity[word_index * 32 +: 32]);
        bar_write('h040, FENCE_ADDR[31:0]);
        bar_write('h044, FENCE_ADDR[63:32]);
        bar_write('h048, FENCE_COOKIE);
        bar_write('h008, 1);
        wait (o_buffer_armed);
        poll_register('h00c, 'h3e, 2);
        $display("BB_BUFFER_ARM generation=%0d identity=%032x time_ns=%0t",
                 generation, buffer_identity, $time);
    endtask

    task automatic wait_host_safe_and_ack(input string basename);
        logic [127:0] bound_identity;
        logic [31:0] native_record_length, native_sent_length;
        int output_handle, byte_value;
        wait (fence_count == 1 && rc_count == 1);
        poll_register('h00c, 'hc, 4);
        safe_time = $time;
        expect_register('h080, 0);
        bar_read('h084, native_sent_length);
        bar_read('h088, native_record_length);
        check(native_record_length == HEADER_BYTES + jpeg_length &&
              native_sent_length == native_record_length && host_bytes == native_record_length,
              $sformatf("native result length disagreement sent=%0d record=%0d reconstructed=%0d jpeg=%0d",
                        native_sent_length, native_record_length, host_bytes, jpeg_length));
        for (int word_index = 0; word_index < 4; word_index++) begin
            expect_register('h090 + 4 * word_index, buffer_identity[word_index * 32 +: 32]);
            bar_read('h0a0 + 4 * word_index, bound_identity[word_index * 32 +: 32]);
        end
        check(bound_identity == {16'h4a50, host_word(88), host_word(92),
                                 host_memory[41], host_memory[40], host_word(8)},
              $sformatf("bound product identity does not match transferred AJPG: %032x", bound_identity));
        check(host_word(0) == 'h47504a41 && host_word(8) == expected_seq &&
              host_word(72) == cfg_session && host_word(76) == cfg_epoch &&
              host_word(80) == expected_seq && host_word(12) == jpeg_length,
              "host record identity or length mismatch");
        output_handle = $fopen({basename, ".ajpg"}, "wb");
        check(output_handle != 0, "cannot create AJPG evidence file");
        for (int offset = 0; offset < native_record_length; offset++) begin
            check(host_memory.exists(offset), $sformatf("missing host byte %0d", offset));
            byte_value = int'(host_memory[offset]);
            $fwrite(output_handle, "%c", byte_value);
        end
        $fclose(output_handle);
        $display("BB_SAFE seq=%0d sent=%0d record=%0d bound=%032x time_ns=%0t",
                 expected_seq, native_sent_length, native_record_length, bound_identity, safe_time);
        repeat (48) @(negedge i_host_clk);
        check(retire_count == 0 && retire_response_count == 0, "slot retired during SAFE before host ACK");
        bar_write('h008, 16);
    endtask
