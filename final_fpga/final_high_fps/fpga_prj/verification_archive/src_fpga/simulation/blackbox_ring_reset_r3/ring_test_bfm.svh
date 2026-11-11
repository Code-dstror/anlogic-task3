    // Each queue position represents one accepted AXI address. The W/R beat
    // indices and B debt advance only on the corresponding pin handshakes.
    localparam int MAX_BURSTS = 512;
    typedef struct packed {
        logic [27:0] address;
        logic [3:0] id;
        int beats;
        int first_word;
    } burst_t;
    burst_t aw_queue [0:MAX_BURSTS-1], ar_queue [0:MAX_BURSTS-1];
    logic [7:0] ddr [int unsigned];
    int aw_count, aw_words, w_burst, w_beat, w_words, b_count;
    int ar_count, ar_words, r_burst, r_beat, r_words;
    int aw_pause = 0, w_pause = 0, ar_pause = 0;
    int aw_stalls, w_stalls, ar_stalls, r_stalls;
    bit b_taken, r_taken, write_b_error;
    bit final_b_open = 1;
    bit hold_aw, hold_w, hold_b, hold_ar, hold_r;
    logic [44:0] previous_aw, previous_ar;
    logic [144:0] previous_w;
    logic [5:0] previous_b;
    logic [134:0] previous_r;
    wire [44:0] aw_offer = {o_axi_awaddr, o_axi_awid, o_axi_awlen, o_axi_awsize, o_axi_awburst};
    wire [44:0] ar_offer = {o_axi_araddr, o_axi_arid, o_axi_arlen, o_axi_arsize, o_axi_arburst};
    wire [144:0] w_offer = {o_axi_wdata, o_axi_wstrb, o_axi_wlast};
    wire [5:0] b_offer = {i_axi_bid, i_axi_bresp};
    wire [134:0] r_offer = {i_axi_rdata, i_axi_rid, i_axi_rresp, i_axi_rlast};

    task automatic new_axi_write;
        aw_count = 0;
        aw_words = 0;
        w_burst = 0;
        w_beat = 0;
        w_words = 0;
        b_count = 0;
        write_b_error = 0;
    endtask

    task automatic new_axi_read;
        ar_count = 0;
        ar_words = 0;
        r_burst = 0;
        r_beat = 0;
        r_words = 0;
    endtask

    task automatic reset_axi;
        new_axi_write();
        new_axi_read();
        ddr.delete();
        {hold_aw, hold_w, hold_b, hold_ar, hold_r, b_taken, r_taken} = '0;
        aw_stalls = 0;
        w_stalls = 0;
        ar_stalls = 0;
        r_stalls = 0;
    endtask

    function automatic bit final_write_waiting;
        return writer_live && w_words == beat_count(write_frame.length) && b_count == w_burst - 1;
    endfunction

    function automatic bit writes_complete;
        return aw_count != 0 && b_count == aw_count
            && w_burst == aw_count && w_words == beat_count(write_frame.length);
    endfunction

    function automatic bit reads_drained;
        return ar_count != 0 && r_burst == ar_count && r_words == beat_count(read_frame.length);
    endfunction

    function automatic logic [127:0] ddr_word(input int unsigned address);
        logic [127:0] data;
        for (int lane = 0; lane < 16; lane++)
            data[lane * 8 +: 8] = ddr.exists(address + lane) ? ddr[address + lane] : 8'ha5;
        return data;
    endfunction

    always @(negedge i_clk) begin : drive_axi
        burst_t burst;
        bit final_burst;
        if (!i_cold_rst_n) begin
            i_axi_awready = 0;
            i_axi_wready = 0;
            i_axi_arready = 0;
            i_axi_bvalid = 0;
            i_axi_rvalid = 0;
        end else begin
            i_axi_awready = aw_pause == 0;
            if (aw_pause > 0 && o_axi_awvalid)
                aw_pause--;
            i_axi_wready = w_burst < aw_count && w_pause == 0 && cycle % 11 > 2;
            if (w_burst < aw_count && w_pause > 0 && o_axi_wvalid)
                w_pause--;
            i_axi_arready = ar_pause == 0;
            if (ar_pause > 0 && o_axi_arvalid)
                ar_pause--;

            if (!i_axi_bvalid || b_taken) begin
                i_axi_bvalid = 0;
                if (b_count < w_burst) begin
                    burst = aw_queue[b_count];
                    final_burst = burst.first_word + burst.beats == beat_count(write_frame.length);
                    if (!final_burst || final_b_open) begin
                        i_axi_bid = burst.id;
                        i_axi_bresp = final_burst ? write_frame.final_bresp : 2'b00;
                        i_axi_bvalid = 1;
                    end
                end
            end
            if (!i_axi_rvalid || r_taken) begin
                i_axi_rvalid = 0;
                if (r_burst < ar_count && cycle % 7 != 3) begin
                    burst = ar_queue[r_burst];
                    i_axi_rid = burst.id;
                    i_axi_rresp = 2'b00;
                    i_axi_rlast = r_beat == burst.beats - 1;
                    i_axi_rdata = ddr_word(burst.address + r_beat * 16);
                    i_axi_rvalid = 1;
                end
            end
        end
    end

    task automatic sample_axi_holds;
        if (hold_aw)
            check(o_axi_awvalid && aw_offer === previous_aw, "AW changed under stall");
        if (hold_w)
            check(o_axi_wvalid && w_offer === previous_w, "W changed under stall");
        if (hold_b)
            check(i_axi_bvalid && b_offer === previous_b, "BFM changed B under stall");
        if (hold_ar)
            check(o_axi_arvalid && ar_offer === previous_ar, "AR changed under stall");
        if (hold_r)
            check(i_axi_rvalid && r_offer === previous_r, "BFM changed R under stall");
        hold_aw = o_axi_awvalid && !i_axi_awready;
        hold_w = o_axi_wvalid && !i_axi_wready;
        hold_b = i_axi_bvalid && !o_axi_bready;
        hold_ar = o_axi_arvalid && !i_axi_arready;
        hold_r = i_axi_rvalid && !o_axi_rready;
        previous_aw = aw_offer;
        previous_w = w_offer;
        previous_b = b_offer;
        previous_ar = ar_offer;
        previous_r = r_offer;
        aw_stalls += hold_aw;
        w_stalls += hold_w;
        ar_stalls += hold_ar;
        r_stalls += hold_r;
    endtask

    task automatic sample_axi_write;
        burst_t burst;
        logic [15:0] keep;
        int unsigned address;
        if (o_axi_awvalid && i_axi_awready) begin
            check(writer_live && aw_count < MAX_BURSTS, "AW has no active capture");
            check({o_axi_awid, o_axi_awsize, o_axi_awburst} === {4'd0, 3'd4, 2'b01},
                  "AW ID, SIZE or BURST");
            burst = '{o_axi_awaddr, o_axi_awid, int'(o_axi_awlen) + 1, aw_words};
            check(burst.beats <= 16 && burst.address[11:0] + burst.beats * 16 <= 4096,
                  "AW exceeds 16 beats or crosses 4 KiB");
            check(burst.address == SLOT_BASE[write_frame.slot] + aw_words * 16,
                  $sformatf("AW address cap=%0d addr=%h expected=%h",
                            write_frame.capture_id, burst.address,
                            SLOT_BASE[write_frame.slot] + aw_words * 16));
            check(aw_words + burst.beats <= beat_count(write_frame.length),
                  "AW promises more words than the capture");
            aw_queue[aw_count] = burst;
            aw_count++;
            aw_words += burst.beats;
            $fdisplay(trace_fd, "%0d:%0d AW %h", reset_case, cycle, aw_offer);
        end
        if (o_axi_wvalid && i_axi_wready) begin
            check(writer_live && w_burst < aw_count && w_words < data_beats,
                  "W has no accepted AW or input DATA");
            burst = aw_queue[w_burst];
            keep = keep_for(write_frame.length, w_words);
            check(o_axi_wlast === (w_beat == burst.beats - 1), "WLAST does not match AWLEN");
            check(o_axi_wstrb === keep, "WSTRB does not match accepted DATA KEEP");
            check(mask_data(o_axi_wdata, keep) === mask_data(beat_for(write_frame, w_words), keep),
                  $sformatf("W byte mismatch at word %0d", w_words));
            address = burst.address + w_beat * 16;
            for (int lane = 0; lane < 16; lane++)
                if (o_axi_wstrb[lane])
                    ddr[address + lane] = o_axi_wdata[lane * 8 +: 8];
            $fdisplay(trace_fd, "%0d:%0d W %h %h %b", reset_case, cycle,
                      mask_data(o_axi_wdata, o_axi_wstrb), o_axi_wstrb, o_axi_wlast);
            w_words++;
            if (o_axi_wlast) begin
                w_burst++;
                w_beat = 0;
            end else
                w_beat++;
        end
        b_taken = i_axi_bvalid && o_axi_bready;
        if (b_taken) begin
            check(writer_live && b_count < w_burst, "B has no completed W burst");
            check(i_axi_bid === aw_queue[b_count].id, "BFM BID does not match AWID");
            write_b_error |= i_axi_bresp != 0;
            b_count++;
            $fdisplay(trace_fd, "%0d:%0d B %h", reset_case, cycle, b_offer);
        end
    endtask

    task automatic sample_axi_read;
        burst_t burst;
        if (o_axi_arvalid && i_axi_arready) begin
            check(reader_live && ar_count < MAX_BURSTS, "AR has no claimed capture");
            check({o_axi_arid, o_axi_arsize, o_axi_arburst} === {4'd0, 3'd4, 2'b01},
                  "AR ID, SIZE or BURST");
            burst = '{o_axi_araddr, o_axi_arid, int'(o_axi_arlen) + 1, ar_words};
            check(burst.beats <= 16 && burst.address[11:0] + burst.beats * 16 <= 4096,
                  "AR exceeds 16 beats or crosses 4 KiB");
            check(burst.address == SLOT_BASE[read_frame.slot] + ar_words * 16,
                  $sformatf("AR address cap=%0d addr=%h expected=%h",
                            read_frame.capture_id, burst.address,
                            SLOT_BASE[read_frame.slot] + ar_words * 16));
            check(ar_words + burst.beats <= beat_count(read_frame.length),
                  "AR promises more words than the capture");
            ar_queue[ar_count] = burst;
            ar_count++;
            ar_words += burst.beats;
            $fdisplay(trace_fd, "%0d:%0d AR %h", reset_case, cycle, ar_offer);
        end
        r_taken = i_axi_rvalid && o_axi_rready;
        if (r_taken) begin
            check(reader_live && r_burst < ar_count, "R has no accepted AR");
            burst = ar_queue[r_burst];
            check(i_axi_rid === burst.id && i_axi_rlast === (r_beat == burst.beats - 1),
                  "BFM RID or RLAST does not match AR");
            $fdisplay(trace_fd, "%0d:%0d R %h", reset_case, cycle, r_offer);
            r_words++;
            if (i_axi_rlast) begin
                r_burst++;
                r_beat = 0;
            end else
                r_beat++;
        end
    endtask
