    typedef struct packed {
        logic [3:0] id;
        logic [27:0] address;
        logic [7:0] last_beat;
    } burst_t;

    typedef struct packed {
        logic [3:0] id;
        bit raw_region;
        int wlast_cycle;
        int eligible_cycle;
    } response_t;

    localparam int JPEG_B_DELAY = 48;
    localparam int FINAL_JPEG_B_DELAY = 2600;
    localparam int B_SERVICE_LIMIT = 4096;
    burst_t aw_queue[$], ar_queue[$];
    response_t b_queue[$];
    bit [7:0] memory_bytes[int unsigned];
    bit raw_written[int unsigned];
    int axi_cycle = 0;
    int write_beat = 0, read_beat = 0;
    int b_first_valid_cycle = 0;
    bit b_taken = 0, r_taken = 0;
    int raw_write_debt = 0, jpeg_write_debt = 0, raw_read_debt = 0;
    int raw_write_bytes = 0, jpeg_write_bytes = 0, raw_read_beats = 0;
    int jpeg_aw_count = 0, raw_slverr_count = 0, axi_stalls = 0;
    int raw_aw_count, raw_w_count, raw_wlast_count, raw_b_count;
    int jpeg_w_count, jpeg_wlast_count, jpeg_b_count;
    int raw_ar_count, raw_rlast_count, jpeg_ar_count, jpeg_r_count, jpeg_rlast_count;
    int unsigned raw_base = 0;
    int unsigned jpeg_base = 0;
    bit jpeg_eoi_written = 0;
    time last_jpeg_b = 0, last_jpeg_wlast = 0, raw_slverr_time = 0;
    int exact_b_count = 0, late_b_count = 0, hard_fault_cycle = 0;
    time hard_fault_time = 0, late_b_time = 0;

    bit aw_stalled = 0, w_stalled = 0, ar_stalled = 0;
    logic [44:0] held_aw, held_ar;
    logic [144:0] held_w;

    function automatic bit is_raw(input int unsigned address);
        return address >= 'h02000000 && address < 'h04000000;
    endfunction

    function automatic bit is_jpeg(input int unsigned address);
        return address < 'h01000000 || (address >= 'h0a000000 && address < 'h0c000000);
    endfunction

    function automatic bit all_axi_drained();
        return aw_queue.size() == 0 && ar_queue.size() == 0 && b_queue.size() == 0 &&
               raw_write_debt == 0 && jpeg_write_debt == 0 && raw_read_debt == 0;
    endfunction

    function automatic bit jpeg_has_eoi();
        int position, segment_length;
        if (jpeg_write_bytes < 4 ||
            {memory_bytes[jpeg_base], memory_bytes[jpeg_base + 1]} != 16'hffd8 ||
            {memory_bytes[jpeg_base + jpeg_write_bytes - 2],
             memory_bytes[jpeg_base + jpeg_write_bytes - 1]} != 16'hffd9)
            return 0;
        // An FFD9 pair only counts after a validly delimited SOS.
        position = 2;
        while (position + 3 < jpeg_write_bytes - 2) begin
            if (memory_bytes[jpeg_base + position] != 'hff)
                return 0;
            do position++; while (position + 3 < jpeg_write_bytes - 2 &&
                                  memory_bytes[jpeg_base + position] == 'hff);
            segment_length = int'({memory_bytes[jpeg_base + position + 1],
                                   memory_bytes[jpeg_base + position + 2]});
            if (segment_length < 2 || position + 1 + segment_length > jpeg_write_bytes - 2)
                return 0;
            if (memory_bytes[jpeg_base + position] == 'hda)
                return 1;
            position += 1 + segment_length;
        end
        return 0;
    endfunction

    task automatic clear_axi_frame;
        raw_written.delete();
        raw_base = 0;
        raw_write_bytes = 0;
        jpeg_write_bytes = 0;
        jpeg_base = 0;
        jpeg_eoi_written = 0;
        raw_read_beats = 0;
        raw_slverr_count = 0;
        raw_slverr_time = 0;
        jpeg_aw_count = 0;
        last_jpeg_b = 0;
        last_jpeg_wlast = 0;
        axi_stalls = 0;
        raw_aw_count = 0;
        raw_w_count = 0;
        raw_wlast_count = 0;
        raw_b_count = 0;
        jpeg_w_count = 0;
        jpeg_wlast_count = 0;
        jpeg_b_count = 0;
        raw_ar_count = 0;
        raw_rlast_count = 0;
        jpeg_ar_count = 0;
        jpeg_r_count = 0;
        jpeg_rlast_count = 0;
        exact_b_count = 0;
        late_b_count = 0;
        hard_fault_cycle = 0;
        hard_fault_time = 0;
        late_b_time = 0;
    endtask

    task automatic report_stress_failure;
        $display("BB_STRESS_STATE fault=%b raw_empty=%b record_quiet=%b capture_enabled=%b session_armed=%b buffer_armed=%b dfi_cycle=%0d",
                 o_fault, o_raw_empty, o_record_quiet, o_capture_enabled,
                 o_session_armed, o_buffer_armed, axi_cycle);
        $display("BB_STRESS_TERMINALS capture=%0d start=%0d jpeg_source_done=%b jpeg_source_failed=%b jpeg_source_count=%0d result=%0d writer=%0d ticket=%0d raw_retire=%0d record_offer=%0d record_retire=%0d host_bytes=%0d",
                 capture_count, start_count, o_jpeg_source_done, o_jpeg_source_failed,
                 jpeg_source_count, result_count, writer_count, ticket_count,
                 raw_retire_count, offer_count, retire_count, host_bytes);
        $display("BB_STRESS_RAW aw=%0d w=%0d wlast=%0d b=%0d raw_bytes=%0d ar=%0d r=%0d rlast=%0d slverr=%0d write_debt=%0d read_debt=%0d",
                 raw_aw_count, raw_w_count, raw_wlast_count, raw_b_count, raw_write_bytes,
                 raw_ar_count, raw_read_beats, raw_rlast_count, raw_slverr_count,
                 raw_write_debt, raw_read_debt);
        $display("BB_STRESS_JPEG aw=%0d w=%0d wlast=%0d b=%0d jpeg_bytes=%0d ar=%0d r=%0d rlast=%0d write_debt=%0d eoi=%b",
                 jpeg_aw_count, jpeg_w_count, jpeg_wlast_count, jpeg_b_count, jpeg_write_bytes,
                 jpeg_ar_count, jpeg_r_count, jpeg_rlast_count, jpeg_write_debt, jpeg_eoi_written);
        $display("BB_STRESS_AXI_PIN ar=%b%b r=%b%b resp=%b rlast=%b aw=%b%b w=%b%b b=%b%b aw_queue=%0d ar_queue=%0d b_queue=%0d",
                 o_mem_arvalid, i_mem_arready, i_mem_rvalid, o_mem_rready, i_mem_rresp, i_mem_rlast,
                 o_mem_awvalid, i_mem_awready, o_mem_wvalid, i_mem_wready, i_mem_bvalid, o_mem_bready,
                 aw_queue.size(), ar_queue.size(), b_queue.size());
    endtask

    task automatic check_burst(input string channel_name, input logic [27:0] address,
                               input logic [7:0] length, input logic [2:0] size,
                               input logic [1:0] burst);
        check(!$isunknown({address, length, size, burst}) && size == 4 && burst == 1 &&
              address[3:0] == 0 && int'(address[11:0]) + 16 * (int'(length) + 1) <= 4096,
              $sformatf("invalid AXI %s address=%07x len=%0d size=%0d burst=%0d",
                        channel_name, address, length, size, burst));
        check(is_raw(address) || is_jpeg(address),
              $sformatf("unexpected AXI %s address %07x", channel_name, address));
    endtask

    always @(posedge i_mem_clk) begin : memory_accepted
        burst_t request;
        response_t response;
        int unsigned address, offset;
        logic [39:0] expected_group;
        b_taken = 0;
        r_taken = 0;
        if (o_dfi_reset_n && o_mem_reset_n) begin
            axi_cycle++;
            if (aw_stalled)
                check(o_mem_awvalid &&
                      {o_mem_awid, o_mem_awaddr, o_mem_awlen, o_mem_awsize, o_mem_awburst} === held_aw,
                      "AXI AW offer changed under stall");
            if (w_stalled)
                check(o_mem_wvalid && {o_mem_wdata, o_mem_wstrb, o_mem_wlast} === held_w,
                      "AXI W offer changed under stall");
            if (ar_stalled)
                check(o_mem_arvalid &&
                      {o_mem_arid, o_mem_araddr, o_mem_arlen, o_mem_arsize, o_mem_arburst} === held_ar,
                      "AXI AR offer changed under stall");
            aw_stalled = o_mem_awvalid && !i_mem_awready;
            w_stalled = o_mem_wvalid && !i_mem_wready;
            ar_stalled = o_mem_arvalid && !i_mem_arready;
            held_aw = {o_mem_awid, o_mem_awaddr, o_mem_awlen, o_mem_awsize, o_mem_awburst};
            held_w = {o_mem_wdata, o_mem_wstrb, o_mem_wlast};
            held_ar = {o_mem_arid, o_mem_araddr, o_mem_arlen, o_mem_arsize, o_mem_arburst};
            axi_stalls += int'(aw_stalled) + int'(w_stalled) + int'(ar_stalled) +
                          int'(i_mem_rvalid && !o_mem_rready) + int'(i_mem_bvalid && !o_mem_bready);

            if (o_mem_awvalid && i_mem_awready) begin
                check(frame_active, "AXI write without product admission");
                check_burst("AW", o_mem_awaddr, o_mem_awlen, o_mem_awsize, o_mem_awburst);
                check(!$isunknown(o_mem_awid), "AXI AW has unknown ID");
                request = {o_mem_awid, o_mem_awaddr, o_mem_awlen};
                aw_queue.push_back(request);
                if (is_raw(request.address)) begin
                    raw_aw_count++;
                    raw_write_debt++;
                    if (raw_base == 0) begin
                        raw_base = request.address;
                        check(raw_base == 'h02000000 || raw_base == 'h03000000,
                              "RAW write did not start at a CAM0 slot base");
                    end
                end else begin
                    check(offer_count == 0, "JPEG AW after successful record offer");
                    jpeg_write_debt++;
                    jpeg_aw_count++;
                    if (stress_jpeg_responses)
                        $display("BB_STRESS_JPEG_AW id=%x addr=%07x len=%0d time_ns=%0t",
                                 request.id, request.address, int'(request.last_beat) + 1, $time);
                end
            end

            if (o_mem_wvalid && i_mem_wready) begin
                check(aw_queue.size() != 0, "AXI W without committed AW");
                request = aw_queue[0];
                if (is_raw(request.address))
                    raw_w_count++;
                else
                    jpeg_w_count++;
                check(o_mem_wlast == (write_beat == int'(request.last_beat)), "AXI WLAST mismatch");
                check(!$isunknown(o_mem_wstrb), "unknown WSTRB");
                for (int lane = 0; lane < 16; lane++) begin
                    if (o_mem_wstrb[lane]) begin
                        address = int'(request.address) + write_beat * 16 + lane;
                        check(!$isunknown(o_mem_wdata[lane * 8 +: 8]), "unknown strobed DDR W byte");
                        memory_bytes[address] = o_mem_wdata[lane * 8 +: 8];
                        if (is_raw(address)) begin
                            offset = address - raw_base;
                            if (offset < RAW_BYTES) begin
                                expected_group = bayer_group(offset / (GROUPS_PER_ROW * 5));
                                check(!raw_written.exists(address),
                                      $sformatf("duplicate RAW write at address %08x", address));
                                check(memory_bytes[address] == expected_group[(offset % 5) * 8 +: 8],
                                      $sformatf("RAW byte %0d actual=%02x expected=%02x",
                                                offset, memory_bytes[address],
                                                expected_group[(offset % 5) * 8 +: 8]));
                                raw_written[address] = 1;
                                raw_write_bytes++;
                            end
                        end else begin
                            if (jpeg_write_bytes == 0)
                                jpeg_base = address;
                            check(address == jpeg_base + jpeg_write_bytes,
                                  "unexpected address in contiguous JPEG byte writes");
                            jpeg_write_bytes++;
                        end
                    end
                end
                if (o_mem_wlast) begin
                    request = aw_queue.pop_front();
                    response.id = request.id;
                    response.raw_region = is_raw(request.address);
                    response.wlast_cycle = axi_cycle;
                    response.eligible_cycle = axi_cycle + 5;
                    if (response.raw_region) begin
                        raw_wlast_count++;
                    end else begin
                        jpeg_wlast_count++;
                        last_jpeg_wlast = $time;
                        jpeg_eoi_written = !frame_bad && jpeg_has_eoi();
                        // Keep the targeted final hold independent of encoder RESULT.
                        if (stress_jpeg_responses || (expect_hard_timeout && jpeg_wlast_count == 1)) begin
                            response.eligible_cycle = axi_cycle + B_SERVICE_LIMIT;
                            $display("BB_STRESS_JPEG_WLAST id=%x bytes=%0d due_dfi=%0d time_ns=%0t",
                                     response.id, jpeg_write_bytes, response.eligible_cycle, $time);
                        end else if (deadline_jpeg_responses) begin
                            response.eligible_cycle = axi_cycle + B_SERVICE_LIMIT - 1;
                        end else begin
                            response.eligible_cycle = axi_cycle +
                                (jpeg_eoi_written ? FINAL_JPEG_B_DELAY : JPEG_B_DELAY);
                        end
                    end
                    b_queue.push_back(response);
                    write_beat = 0;
                end else begin
                    write_beat++;
                end
            end

            if (i_mem_bvalid && o_mem_bready) begin
                check(b_queue.size() != 0, "AXI B without WLAST");
                response = b_queue.pop_front();
                check(i_mem_bid == response.id && i_mem_bresp == 0 &&
                      axi_cycle >= response.eligible_cycle, "invalid B response model");
                if (response.raw_region) begin
                    raw_b_count++;
                    raw_write_debt--;
                end else begin
                    jpeg_b_count++;
                    jpeg_write_debt--;
                    last_jpeg_b = $time;
                    if (deadline_jpeg_responses) begin
                        check(b_first_valid_cycle - response.wlast_cycle == B_SERVICE_LIMIT,
                              "exact-deadline B was not presented on k+4096");
                        exact_b_count++;
                    end
                    if (expect_hard_timeout &&
                        response.eligible_cycle - response.wlast_cycle == B_SERVICE_LIMIT) begin
                        check(b_first_valid_cycle - response.wlast_cycle == B_SERVICE_LIMIT + 1,
                              "late B was not presented on k+4097");
                        late_b_count++;
                        late_b_time = $time;
                    end
                    if (deadline_jpeg_responses || expect_hard_timeout)
                        $display("BB_B_SERVICE seq=%0d wlast_cycle=%0d valid_cycle=%0d accept_cycle=%0d delta=%0d time_ns=%0t",
                                 expected_seq, response.wlast_cycle, b_first_valid_cycle, axi_cycle,
                                 b_first_valid_cycle - response.wlast_cycle, $time);
                    if (stress_jpeg_responses)
                        $display("BB_STRESS_JPEG_B id=%x dfi_cycle=%0d time_ns=%0t",
                                 response.id, axi_cycle, $time);
                end
                b_taken = 1;
            end

            if (o_mem_arvalid && i_mem_arready) begin
                check(frame_active, "AXI read without product admission");
                check_burst("AR", o_mem_araddr, o_mem_arlen, o_mem_arsize, o_mem_arburst);
                check(!$isunknown(o_mem_arid), "AXI AR has unknown ID");
                request = {o_mem_arid, o_mem_araddr, o_mem_arlen};
                ar_queue.push_back(request);
                if (is_raw(request.address)) begin
                    raw_ar_count++;
                    check(raw_write_bytes == RAW_BYTES && raw_write_debt == 0 &&
                          request.address >= raw_base && request.address < raw_base + RAW_BYTES,
                          "RAW replay read without captured bytes and successful write responses");
                    raw_read_debt++;
                end else begin
                    jpeg_ar_count++;
                    check(!frame_bad && jpeg_write_debt == 0 && last_jpeg_b > last_jpeg_wlast,
                          "JPEG read before final write response or for failed frame");
                end
            end

            if (i_mem_rvalid && o_mem_rready) begin
                check(ar_queue.size() != 0, "AXI R without committed AR");
                request = ar_queue[0];
                check(i_mem_rid == request.id &&
                      i_mem_rlast == (read_beat == int'(request.last_beat)), "invalid R response model");
                if (is_raw(request.address)) begin
                    raw_read_beats++;
                    if (i_mem_rresp == 2) begin
                        check(frame_bad && start_count == 1 && raw_slverr_count == 0,
                              "SLVERR lacks committed post-START RAW request");
                        raw_slverr_count++;
                        raw_slverr_time = $time;
                        $display("BB_RAW_SLVERR seq=%0d ar_addr=%07x ar_id=%x beat=%0d time_ns=%0t",
                                 expected_seq, request.address, request.id, read_beat, $time);
                    end
                end else
                    jpeg_r_count++;
                if (i_mem_rlast) begin
                    request = ar_queue.pop_front();
                    if (is_raw(request.address)) begin
                        raw_read_debt--;
                        raw_rlast_count++;
                    end else
                        jpeg_rlast_count++;
                    read_beat = 0;
                end else begin
                    read_beat++;
                end
                r_taken = 1;
            end
            observe_product();
        end else begin
            check(!frame_active || (expect_hard_timeout && all_axi_drained()),
                  "unexpected DFI/memory reset during product ownership");
            aw_stalled = 0;
            w_stalled = 0;
            ar_stalled = 0;
        end
    end

    always @(negedge i_mem_clk) begin : drive_memory
        burst_t request;
        response_t response;
        int unsigned address;
        if (o_dfi_reset_n && o_mem_reset_n) begin
            if (expect_hard_timeout && o_fault && hard_fault_time == 0) begin
                hard_fault_cycle = axi_cycle;
                hard_fault_time = $time;
                $display("BB_HARD_TIMEOUT seq=%0d dfi_cycle=%0d write_debt=%0d read_debt=%0d time_ns=%0t",
                         expected_seq, hard_fault_cycle, jpeg_write_debt + raw_write_debt, raw_read_debt, $time);
            end
            i_mem_awready = aw_queue.size() < 32 && axi_cycle % 11 != 3;
            i_mem_wready = aw_queue.size() != 0 && axi_cycle % 9 != 5;
            i_mem_arready = ar_queue.size() < 32 && axi_cycle % 13 != 4;

            if (b_taken)
                i_mem_bvalid = 0;
            if (!i_mem_bvalid && b_queue.size() != 0) begin
                response = b_queue[0];
                if (axi_cycle >= response.eligible_cycle) begin
                    b_first_valid_cycle = axi_cycle + 1;
                    i_mem_bid = response.id;
                    i_mem_bresp = 0;
                    i_mem_bvalid = 1;
                end
            end

            if (r_taken)
                i_mem_rvalid = 0;
            if (!i_mem_rvalid && ar_queue.size() != 0 && axi_cycle % 7 != 2) begin
                request = ar_queue[0];
                i_mem_rid = request.id;
                i_mem_rlast = read_beat == int'(request.last_beat);
                i_mem_rresp = 0;
                if (inject_raw_slverr && is_raw(request.address) && start_count == 1 &&
                    raw_slverr_count == 0 && read_beat == 0 && raw_read_beats >= 40)
                    i_mem_rresp = 2;
                for (int lane = 0; lane < 16; lane++) begin
                    address = int'(request.address) + read_beat * 16 + lane;
                    i_mem_rdata[lane * 8 +: 8] = memory_bytes.exists(address) ? memory_bytes[address] : 0;
                end
                i_mem_rvalid = 1;
            end
        end else begin
            i_mem_awready = 0;
            i_mem_wready = 0;
            i_mem_arready = 0;
            i_mem_bvalid = 0;
            i_mem_rvalid = 0;
        end
    end
