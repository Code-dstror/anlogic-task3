`timescale 1ns/1ps

module source_reset_tb;
    localparam int CONTEXT_IN = 0, CONTEXT_OUT = 1, RGB_IN = 2, RGB_OUT = 3,
                   STALE_IN = 4, STATUS_IN = 5, NOTICE_OUT = 6, RESULT_OUT = 7,
                   TAIL_OUT = 8, CLEANUP_CLEAR = 9, FAILED_OUT = 10;
    localparam int MAX_WAIT = 24;
    int transfers[11];
    int stall_edges[5];
    int pixel_edges = 0;
    int frame_id;
    string scenario;

    bit pixel_clk = 0, dfi_clk = 0, dfi_run = 1;
    bit pixel_rst_n = 1, dfi_rst_n = 1;
    wire common_rst_n = pixel_rst_n && dfi_rst_n;

    bit owner_valid = 0, borrow_live = 0, owner_member;
    logic [383:0] owner_frame;
    logic [63:0] owner_lease, owner_job, owner_pair, owner_native_tag;
    logic [31:0] owner_writer_tag;

    bit context_valid = 0, context_ready = 0;
    logic [575:0] context_in;
    wire context_in_ready, context_out_valid;
    wire [575:0] context_out;

    bit rgb_valid = 0, rgb_ready = 0, rgb_sof, rgb_eol, rgb_last;
    logic [95:0] rgb_in;
    logic [31:0] rgb_index;
    wire rgb_in_ready, rgb_out_valid, rgb_out_sof, rgb_out_eol, rgb_out_last;
    wire [95:0] rgb_out;
    wire [3:0] rgb_out_keep;
    wire [31:0] rgb_out_index;
    wire [63:0] rgb_out_tag;

    bit status_valid = 0, status_ok = 0, read_quiet = 0;
    logic [63:0] status_tag;
    logic [7:0] status_error;
    logic [31:0] status_groups;
    wire status_ready;
    wire [31:0] stale_status_count;

    bit notice_ready = 0, pipeline_quiet = 0;
    wire notice_valid, notice_ok;
    wire [575:0] notice_context;
    wire [7:0] notice_error;

    bit result_ready = 0;
    wire result_valid, result_member, result_error;
    wire [383:0] result_frame;
    wire [63:0] result_lease, result_job, result_pair, result_write_tag;
    wire pixel_fault, dfi_fault, pool_idle;

    bit tail_valid = 0, tail_ready = 0, failed_ready = 0;
    wire drain_pending, cleanup_rst_n, cleanup_data_rst_n;
    wire failed_valid, cleanup_fault, cleanup_pulse;
    wire [31:0] stale_cleanup_count;
    bit saw_local_clear, saw_data_clear;

    wire context_fire = context_out_valid && context_ready;
    wire sof_fire = rgb_out_valid && rgb_ready && rgb_out_sof;
    wire notice_fire = notice_valid && notice_ready;

    private_rgb_source_borrow4 #(
        .MAX_WIDTH(1920), .MAX_HEIGHT(1080), .NR_ENABLE(0),
        .NEUTRAL_STATS_ENABLE(0), .DEHAZE_ENABLE(0)
    ) source_dut (
        .i_pixel_clk(pixel_clk), .i_pixel_rst_n(pixel_rst_n),
        .i_dfi_clk(dfi_clk), .i_dfi_rst_n(dfi_rst_n),
        .i_owner_valid(owner_valid), .i_borrow_live(borrow_live),
        .i_owner_frame(owner_frame), .i_owner_lease(owner_lease),
        .i_owner_job(owner_job), .i_owner_pair(owner_pair),
        .i_owner_native_tag(owner_native_tag), .i_owner_writer_tag(owner_writer_tag),
        .i_owner_member(owner_member),
        .s_context(context_in), .s_context_valid(context_valid),
        .s_context_ready(context_in_ready), .m_context(context_out),
        .m_context_valid(context_out_valid), .m_context_ready(context_ready),
        .s_rgb(rgb_in), .s_keep(4'hf), .s_sof(rgb_sof), .s_eol(rgb_eol),
        .s_last(rgb_last), .s_valid(rgb_valid), .s_ready(rgb_in_ready),
        .s_tag(owner_native_tag), .s_index(rgb_index),
        .m_rgb(rgb_out), .m_keep(rgb_out_keep), .m_sof(rgb_out_sof),
        .m_eol(rgb_out_eol), .m_last(rgb_out_last), .m_valid(rgb_out_valid),
        .m_tag(rgb_out_tag), .m_index(rgb_out_index), .m_ready(rgb_ready),
        .s_status_valid(status_valid), .s_status_ready(status_ready),
        .s_status_context(context_in), .s_status_tag(status_tag),
        .s_status_ok(status_ok), .s_status_error(status_error),
        .s_status_groups(status_groups), .i_original_read_quiescent(read_quiet),
        .o_stale_original_status_count(stale_status_count),
        .m_source_notice_valid(notice_valid), .m_source_notice_ready(notice_ready),
        .m_source_notice_context(notice_context), .m_source_notice_ok(notice_ok),
        .m_source_notice_error(notice_error),
        .i_processed_sof_fire(sof_fire), .i_writer_source_start_fire(1'b0),
        .i_pipeline_quiescent(pipeline_quiet), .i_pipeline_ok(1'b1), .i_pipeline_error(8'b0),
        .m_processed_source_valid(result_valid), .m_processed_source_ready(result_ready),
        .m_processed_source_frame(result_frame), .m_processed_source_lease(result_lease),
        .m_processed_source_job(result_job), .m_processed_source_pair(result_pair),
        .m_processed_source_write_tag(result_write_tag),
        .m_processed_source_member(result_member), .m_processed_source_error(result_error),
        .o_pixel_fault(pixel_fault), .o_dfi_fault(dfi_fault), .o_pool_idle(pool_idle),

        .i_f21_config(67'b0), .i_f21_required_lut_generation(32'b0),
        .f21_cfg_begin_valid(1'b0), .f21_cfg_generation(32'b0), .f21_cfg_valid(1'b0),
        .f21_cfg_index(9'b0), .f21_cfg_value(11'b0), .f21_cfg_commit_valid(1'b0),
        .f21_cfg_abort(1'b0), .f21_cfg_status_ready(1'b0),
        .i_neutral_stats_request(1'b0), .i_neutral_record_begin(1'b0),
        .i_neutral_record_context(160'b0), .m_neutral_stats_ready(1'b0),
        .i_writer_start_fire(1'b0), .s_write_valid(1'b0),
        .s_write_tag(32'b0), .s_write_sequence(32'b0), .s_write_session(32'b0),
        .s_write_epoch(32'b0), .s_write_camera(1'b0), .s_write_ok(1'b0), .s_write_error(8'b0),
        .i_ddr_reset_done(1'b0), .i_matrix_fault(1'b0), .i_matrix_hard_fault(1'b0),
        .i_dfi_cancel(1'b0), .i_nr_enable(1'b0), .i_history_reset(1'b0),
        .i_motion_guard(8'b0), .i_static_threshold(8'b0), .i_weak_threshold(8'b0),
        .i_motion_threshold(8'b0), .m_nr_result_ready(1'b0),
        .rgb_axi_awready(1'b0), .rgb_axi_arready(1'b0), .rgb_axi_wready(1'b0),
        .rgb_axi_bid(4'b0), .rgb_axi_rid(4'b0), .rgb_axi_bresp(2'b0), .rgb_axi_rresp(2'b0),
        .rgb_axi_bvalid(1'b0), .rgb_axi_rlast(1'b0), .rgb_axi_rvalid(1'b0), .rgb_axi_rdata(128'b0),
        .map_axi_awready(1'b0), .map_axi_arready(1'b0), .map_axi_wready(1'b0),
        .map_axi_bid(4'b0), .map_axi_rid(4'b0), .map_axi_bresp(2'b0), .map_axi_rresp(2'b0),
        .map_axi_bvalid(1'b0), .map_axi_rlast(1'b0), .map_axi_rvalid(1'b0), .map_axi_rdata(128'b0)
    );

    hdr_pair_product_abort_drain4 #(
        .SYNC_CLEAR_ENABLE(1), .SEPARATE_DATA_RESET(1), .FALLING_INPUT_RESET(1)
    ) cleanup_dut (
        .clk(pixel_clk), .rst_n(common_rst_n), .i_data_reset_n(common_rst_n),
        .i_context_fire(context_fire), .i_context_tag(context_out[447:384]),
        .i_source_fire(notice_fire), .i_source_tag(notice_context[447:384]),
        .i_source_ok(notice_ok), .i_source_read_quiescent(read_quiet),
        .i_native_job_start(sof_fire), .i_native_valid(rgb_out_valid),
        .i_isp_valid(1'b0), .i_preprocess_valid(tail_valid), .i_admission_valid(1'b0),
        .o_drain_pending(drain_pending), .o_local_rst_n(cleanup_rst_n),
        .o_local_data_rst_n(cleanup_data_rst_n), .i_failed_status_ready(failed_ready),
        .o_failed_status_valid(failed_valid), .o_protocol_fault(cleanup_fault),
        .o_stale_source_count(stale_cleanup_count), .o_cleanup_pulse(cleanup_pulse)
    );

    always #7 if (dfi_run) dfi_clk = ~dfi_clk;

    function automatic logic [95:0] rgb_pattern(input int id, input int index);
        return 96'hA7_42_B9_35_DA_07_D8_56_9C_03_BC_E1 ^
               {32'h015f006e + id, 32'hf7a0e3d4 - (id << 9) - index,
                32'h196eb527 ^ ((id << 20) | (index << 8) | index)};
    endfunction

    task automatic require(input bit condition, input string reason);
        if (!condition) begin
            $display("BLACKBOX_FAIL case=%s frame=%0d PIX_edge=%0d ns=%0t reason=%s",
                     scenario, frame_id, pixel_edges, $realtime, reason);
            $display("LEDGER context=%0d/%0d rgb=%0d/%0d stale=%0d source=%0d notice=%0d result=%0d tail=%0d clear=%0d failed=%0d",
                     transfers[CONTEXT_IN], transfers[CONTEXT_OUT], transfers[RGB_IN],
                     transfers[RGB_OUT], transfers[STALE_IN], transfers[STATUS_IN],
                     transfers[NOTICE_OUT], transfers[RESULT_OUT], transfers[TAIL_OUT],
                     transfers[CLEANUP_CLEAR], transfers[FAILED_OUT]);
            $fatal(1, "Independent SOURCE/cleanup assertion");
        end
    endtask

    always @(negedge cleanup_rst_n) begin
        if (common_rst_n && transfers[NOTICE_OUT] == 1 && !status_ok) begin
            require(transfers[TAIL_OUT] == 1 && !tail_valid, "local clear interrupted presented tail");
            saw_local_clear = 1;
        end
    end

    always @(negedge cleanup_data_rst_n) begin
        if (common_rst_n && transfers[NOTICE_OUT] == 1 && !status_ok) begin
            require(transfers[TAIL_OUT] == 1 && !tail_valid, "local data clear interrupted presented tail");
            saw_data_clear = 1;
        end
    end

    // Ready and valid are sampled at the PIX rising edge, before registered updates.
    // Compare every presented beat, including stalled offers and the accepting edge.
    bit held_context = 0, held_rgb = 0, held_notice = 0, held_result = 0, held_failed = 0;
    always @(posedge pixel_clk or negedge common_rst_n) begin
        if (!common_rst_n) begin
            held_context = 0;
            held_rgb = 0;
            held_notice = 0;
            held_result = 0;
            held_failed = 0;
        end else begin
            pixel_edges++;
            require(!held_context || context_out_valid === 1'b1, "stalled context withdrawn");
            require(!held_rgb || rgb_out_valid === 1'b1, "stalled RGB withdrawn");
            require(!held_notice || notice_valid === 1'b1, "stalled notice withdrawn");
            require(!held_result || result_valid === 1'b1, "stalled processed SOURCE withdrawn");
            require(!held_failed || failed_valid === 1'b1, "stalled cleanup STATUS withdrawn");
            held_context = context_out_valid && !context_ready;
            held_rgb = rgb_out_valid && !rgb_ready;
            held_notice = notice_valid && !notice_ready;
            held_result = result_valid && !result_ready;
            held_failed = failed_valid && !failed_ready;
            stall_edges[0] += held_context;
            stall_edges[1] += held_rgb;
            stall_edges[2] += held_notice;
            stall_edges[3] += held_result;
            stall_edges[4] += held_failed;

            if (context_valid && context_in_ready) begin
                require(transfers[CONTEXT_IN] == 0, "duplicate input context");
                transfers[CONTEXT_IN]++;
                $display("EVENT context_in frame=%0d edge=%0d tag=%h", frame_id, pixel_edges, owner_native_tag);
            end
            if (context_out_valid) begin
                require(transfers[CONTEXT_IN] == 1 && transfers[CONTEXT_OUT] == 0 &&
                        context_out === context_in, "context ordering, duplication or 576-bit identity");
                if (context_ready) transfers[CONTEXT_OUT]++;
            end
            if (rgb_valid && rgb_in_ready) begin
                require(transfers[RGB_IN] < 4 && rgb_index == transfers[RGB_IN], "input RGB index or duplicate");
                transfers[RGB_IN]++;
            end
            if (rgb_out_valid) begin
                require(transfers[CONTEXT_OUT] == 1 && transfers[RGB_OUT] < 4, "RGB without context or duplicate");
                require(rgb_out === rgb_pattern(frame_id, transfers[RGB_OUT]) &&
                        rgb_out_keep === 4'hf && rgb_out_sof === (transfers[RGB_OUT] == 0) &&
                        rgb_out_eol === ((transfers[RGB_OUT] % 2) == 1) &&
                        rgb_out_last === (transfers[RGB_OUT] == 3) &&
                        rgb_out_tag === owner_native_tag && rgb_out_index === transfers[RGB_OUT],
                        "RGB data, framing or identity mismatch");
                if (rgb_ready) begin
                    require(transfers[RGB_OUT] < transfers[RGB_IN], "output RGB not accepted at input");
                    transfers[RGB_OUT]++;
                end
            end
            if (notice_valid) begin
                require(read_quiet && status_valid && status_tag == owner_native_tag &&
                        transfers[RGB_IN] == 4 && transfers[NOTICE_OUT] == 0 &&
                        notice_context === context_in && notice_ok === status_ok &&
                        notice_error === status_error, "notice premature, duplicate or mismatched");
                if (notice_ready) begin
                    transfers[NOTICE_OUT]++;
                    $display("EVENT notice frame=%0d edge=%0d ok=%b error=%h",
                             frame_id, pixel_edges, notice_ok, notice_error);
                end
            end
            if (status_valid && status_ready) begin
                if (status_tag != owner_native_tag) begin
                    require(transfers[STALE_IN] == 0, "duplicate stale SOURCE handshake");
                    transfers[STALE_IN]++;
                end else begin
                    require(transfers[STATUS_IN] == 0 && transfers[NOTICE_OUT] == 1 &&
                            pipeline_quiet && status_groups == transfers[RGB_IN],
                            "original SOURCE consumed before notice or pipeline drain");
                    transfers[STATUS_IN]++;
                end
            end
            if (result_valid) begin
                require(transfers[STATUS_IN] == 1 && transfers[RESULT_OUT] == 0 && pipeline_quiet &&
                        result_frame === owner_frame && result_lease === owner_lease &&
                        result_job === owner_job && result_pair === owner_pair &&
                        result_write_tag === {32'b0, owner_writer_tag} &&
                        result_member === owner_member && result_error === !status_ok,
                        "processed SOURCE premature, duplicate or mismatched");
                if (result_ready) begin
                    transfers[RESULT_OUT]++;
                    $display("EVENT processed_source frame=%0d edge=%0d job=%h error=%b",
                             frame_id, pixel_edges, result_job, result_error);
                end
            end

            if (tail_valid && tail_ready) transfers[TAIL_OUT]++;
            if (cleanup_pulse) begin
                require(!status_ok && transfers[NOTICE_OUT] == 1 && transfers[TAIL_OUT] == 1 &&
                        transfers[CLEANUP_CLEAR] == 0 && !tail_valid,
                        "cleanup clear occurred before committed presentation drained or duplicated");
                transfers[CLEANUP_CLEAR]++;
                $display("EVENT cleanup_clear frame=%0d edge=%0d", frame_id, pixel_edges);
            end
            if (failed_valid) begin
                require(transfers[CLEANUP_CLEAR] == 1 && transfers[FAILED_OUT] == 0 &&
                        saw_local_clear && saw_data_clear &&
                        drain_pending === 1'b1 && cleanup_rst_n === 1'b1 &&
                        cleanup_data_rst_n === 1'b1, "cleanup STATUS before clear release or duplicate");
                if (failed_ready) begin
                    transfers[FAILED_OUT]++;
                    $display("EVENT failed_status frame=%0d edge=%0d", frame_id, pixel_edges);
                end
            end
        end
    end

    task automatic rise;
        require(pixel_clk == 0, "fixture expected PIX low");
        #5 pixel_clk = 1;
        #1;
    endtask

    task automatic fall;
        require(pixel_clk == 1, "fixture expected PIX high");
        #5 pixel_clk = 0;
        #1;
    endtask

    task automatic tick;
        rise();
        fall();
    endtask

    task automatic wait_transfers(input int channel, input int count, input string purpose);
        for (int i = 0; transfers[channel] < count && i < MAX_WAIT; i++) tick();
        require(transfers[channel] == count, purpose);
    endtask

    task automatic quiet_outputs(input string where);
        require({context_out_valid, rgb_out_valid, notice_valid, result_valid, failed_valid} === 5'b0,
                $sformatf("unexpected presented output at %s", where));
    endtask

    task automatic new_owner(input int id);
        frame_id = id;
        foreach (transfers[channel]) transfers[channel] = 0;
        foreach (stall_edges[channel]) stall_edges[channel] = 0;
        owner_frame = '0;
        owner_frame[76:45] = 32'hc492e100 | id;
        owner_frame[4] = id[0];
        owner_frame[220:205] = 16'd8;
        owner_frame[236:221] = 16'd2;
        owner_lease = 64'hcb190751e8257a30 + id;
        owner_job = 64'ha3382f904850d610 + id;
        owner_pair = 64'h88f0d0c0542c1a70 + id;
        owner_native_tag = 64'h7adcb3d0208e3c20 + id;
        owner_writer_tag = 32'hfb101a60 + id;
        owner_member = id[1];
        context_in = {owner_job, owner_frame[76:45], 31'b0, owner_frame[4],
                      owner_native_tag, owner_frame};
        owner_valid = 1;
        borrow_live = 1;
        context_valid = 1;
        context_ready = 0;
        rgb_valid = 0;
        rgb_ready = 0;
        status_valid = 0;
        status_ok = 1;
        status_error = 0;
        read_quiet = 0;
        notice_ready = 0;
        pipeline_quiet = 0;
        result_ready = 0;
        tail_valid = 0;
        tail_ready = 0;
        failed_ready = 0;
        saw_local_clear = 0;
        saw_data_clear = 0;
    endtask

    task automatic through_r3;
        for (int r = 1; r <= 3; r++) begin
            rise();
            require(transfers[CONTEXT_IN] == 0, $sformatf("input context accepted at R%0d before R4", r));
            quiet_outputs($sformatf("R%0d", r));
            if (r < 3) fall();
        end
    endtask

    task automatic take_r4(input bit extend_phases);
        through_r3();
        if (extend_phases) #83;
        quiet_outputs("high phase before F3");
        fall();
        quiet_outputs("F3");
        if (extend_phases) #67;
        quiet_outputs("low phase after F3 before R4");
        rise();
        require(transfers[CONTEXT_IN] == 1, "eligible first context missed R4");
        $display("COVER R4 first_context=1 extended_phases=%0d frame=%0d edge=%0d",
                 extend_phases, frame_id, pixel_edges);
        context_valid = 0;
        fall();
    endtask

    task automatic startup(input int id, input bit dfi_first, input bit extend_phases);
        new_owner(id);
        #2;
        quiet_outputs("both reset");
        if (dfi_first) dfi_rst_n = 1;
        else pixel_rst_n = 1;
        repeat (2) tick();
        quiet_outputs("one domain still reset");
        require(transfers[CONTEXT_IN] == 0, "input context accepted with peer reset");
        if (dfi_first) pixel_rst_n = 1;
        else dfi_rst_n = 1;
        take_r4(extend_phases);
    endtask

    task automatic finish_context;
        repeat (3) tick();
        require(stall_edges[0] != 0 && transfers[CONTEXT_OUT] == 0, "no held context before ready");
        context_ready = 1;
        wait_transfers(CONTEXT_OUT, 1, "output context did not transfer");
        context_ready = 0;
    endtask

    task automatic offer_rgb(input int index);
        rgb_in = rgb_pattern(frame_id, index);
        rgb_index = index;
        rgb_sof = (index == 0);
        rgb_eol = ((index % 2) == 1);
        rgb_last = (index == 3);
        rgb_valid = 1;
    endtask

    task automatic offer_status(input bit ok, input bit stale, input int groups);
        status_ok = ok;
        status_error = ok ? 8'h00 : 8'hb3;
        status_tag = stale ? (owner_native_tag ^ 64'h8000000000000001) : owner_native_tag;
        status_groups = groups;
        status_valid = 1;
    endtask

    task automatic send_rgb(input bit same_edge_status);
        for (int index = 0; index < 4; index++) begin
            offer_rgb(index);
            if (same_edge_status && index == 3) begin
                rgb_ready = 1;
                offer_status(1, 0, 4);
                tick();
                require(transfers[RGB_IN] == 4, "same-edge final RGB did not transfer");
            end else begin
                rgb_ready = 0;
                repeat (2) tick();
                rgb_ready = 1;
            end
            wait_transfers(RGB_IN, index + 1, "input RGB did not transfer");
            rgb_valid = 0;
            wait_transfers(RGB_OUT, index + 1, "output RGB did not transfer");
        end
        rgb_ready = 0;
        require(stall_edges[1] != 0, "no RGB backpressure observed");
    endtask

    task automatic send_stale_status;
        logic [31:0] before_count;
        before_count = stale_status_count;
        offer_status(1, 1, 4);
        wait_transfers(STALE_IN, 1, "wrong-tag original SOURCE not consumed");
        status_valid = 0;
        repeat (3) tick();
        require(stale_status_count === before_count + 1 && transfers[NOTICE_OUT] == 0 &&
                transfers[RESULT_OUT] == 0, "wrong-tag SOURCE did not increment only the stale count");
        quiet_outputs("after stale SOURCE");
    endtask

    task automatic finish_notice;
        repeat (3) tick();
        require({notice_valid, result_valid} === 2'b0 && transfers[STATUS_IN] == 0,
                "original SOURCE consumed or published before read drain");
        read_quiet = 1;
        repeat (3) tick();
        require(stall_edges[2] != 0 && transfers[NOTICE_OUT] == 0 && transfers[STATUS_IN] == 0,
                "no independently held SOURCE notice");
        notice_ready = 1;
        wait_transfers(NOTICE_OUT, 1, "SOURCE notice did not transfer");
        notice_ready = 0;
        repeat (2) tick();
        require(transfers[STATUS_IN] == 0 && result_valid === 1'b0,
                "original SOURCE consumed while downstream pipeline busy");
    endtask

    task automatic hold_result;
        pipeline_quiet = 1;
        wait_transfers(STATUS_IN, 1, "matching original SOURCE did not transfer");
        status_valid = 0;
        repeat (3) tick();
        require(stall_edges[3] != 0 && transfers[RESULT_OUT] == 0 && result_valid === 1'b1,
                "no independently held processed SOURCE");
    endtask

    task automatic retire(input bit expected_error);
        result_ready = 1;
        wait_transfers(RESULT_OUT, 1, "processed SOURCE did not transfer");
        for (int i = 0; pool_idle !== 1'b1 && i < MAX_WAIT; i++) tick();
        require(pool_idle === 1'b1, "pool did not return idle after processed SOURCE");
        repeat (3) tick();
        quiet_outputs("retired frame");
        require(transfers[CONTEXT_IN] == 1 && transfers[CONTEXT_OUT] == 1 &&
                transfers[RGB_IN] == 4 && transfers[RGB_OUT] == 4 && transfers[STATUS_IN] == 1 &&
                transfers[NOTICE_OUT] == 1 && transfers[RESULT_OUT] == 1 &&
                transfers[FAILED_OUT] == int'(expected_error), "final transaction conservation");
        require({cleanup_fault, drain_pending} === 2'b0 && stale_cleanup_count === 32'b0,
                "cleanup protocol fault, stale notice or missing retirement");
        if (!expected_error) require({pixel_fault, dfi_fault} === 2'b0, "fault on legal frame");
        $display("TERMINAL frame=%0d job=%h error=%0d context=1 rgb=4 notice=1 result=1 failed=%0d pool_idle=1",
                 frame_id, owner_job, expected_error, transfers[FAILED_OUT]);
        $display("COVER stall_edges context=%0d rgb=%0d notice=%0d result=%0d cleanup_status=%0d",
                 stall_edges[0], stall_edges[1], stall_edges[2], stall_edges[3], stall_edges[4]);
        context_ready = 0;
        result_ready = 0;
        owner_valid = 0;
        borrow_live = 0;
    endtask

    task automatic positive_frame(input bit inject_stale, input bit same_edge_status);
        finish_context();
        send_rgb(same_edge_status);
        if (inject_stale) send_stale_status();
        if (!same_edge_status) offer_status(1, 0, 4);
        finish_notice();
        hold_result();
        retire(0);
    endtask

    task automatic next_owner(input int id);
        new_owner(id);
        wait_transfers(CONTEXT_IN, 1, "next owner context did not transfer");
        context_valid = 0;
    endtask

    task automatic stopped_reset(input bit reset_dfi, input bit stop_dfi_high, input int next_id);
        bit stopped_pixel;
        stopped_pixel = pixel_clk;
        if (stop_dfi_high) @(posedge dfi_clk);
        else @(negedge dfi_clk);
        #1 dfi_run = 0;
        #19;
        require(pixel_clk == stopped_pixel && dfi_clk == stop_dfi_high, "fixture clocks failed to stop");
        if (reset_dfi) dfi_rst_n = 0;
        else pixel_rst_n = 0;
        #2;
        quiet_outputs("asynchronous reset with both clocks stopped");
        require({cleanup_rst_n, cleanup_data_rst_n} === 2'b0,
                "cleanup reset not asserted with stopped clocks");
        #33;
        new_owner(next_id);
        #3;
        pixel_rst_n = 1;
        dfi_rst_n = 1;
        #31;
        quiet_outputs("release with both clocks still stopped");
        require(pixel_clk == stopped_pixel && dfi_clk == stop_dfi_high, "fixture clocks advanced during reset");
        $display("COVER stopped_clock_reset authority=%s PIX=%0d DFI=%0d", reset_dfi ? "DFI" : "PIX",
                 stopped_pixel, stop_dfi_high);
        dfi_run = 1;
        if (stopped_pixel) begin
            fall();
            quiet_outputs("initial fall after stopped-clock reset");
        end
        take_r4(1);
        positive_frame(0, 0);
    endtask

    task automatic negative_cleanup;
        finish_context();
        send_rgb(0);
        // This downstream work is already presented before the negative notice.
        tail_valid = 1;
        offer_status(0, 0, 4);
        finish_notice();
        for (int i = 0; drain_pending !== 1'b1 && i < MAX_WAIT; i++) tick();
        require(drain_pending === 1'b1, "negative notice did not start cleanup drain");
        repeat (3) tick();
        rise();
        #29;
        require({cleanup_rst_n, cleanup_data_rst_n, failed_valid, cleanup_pulse} === 4'b1100,
                "cleanup cleared with a presented downstream tail before falling edge");
        fall();
        require({cleanup_rst_n, cleanup_data_rst_n, failed_valid, cleanup_pulse} === 4'b1100,
                "cleanup cleared with a presented downstream tail at falling edge");
        tail_ready = 1;
        wait_transfers(TAIL_OUT, 1, "downstream tail did not transfer");
        tail_valid = 0;
        hold_result();
        for (int i = 0; failed_valid !== 1'b1 && i < MAX_WAIT; i++) tick();
        require(failed_valid === 1'b1 && transfers[CLEANUP_CLEAR] == 1,
                "cleanup failed to publish negative STATUS after tail drained");
        repeat (3) tick();
        require(stall_edges[4] != 0 && failed_valid === 1'b1 && drain_pending === 1'b1,
                "cleanup did not hold STATUS and drain ownership under backpressure");
        failed_ready = 1;
        wait_transfers(FAILED_OUT, 1, "cleanup failed STATUS did not transfer");
        for (int i = 0; drain_pending !== 1'b0 && i < MAX_WAIT; i++) tick();
        require(drain_pending === 1'b0, "cleanup did not leave drain after STATUS handshake");
        retire(1);
    endtask

    initial begin
        #20000;
        require(0, "simulation watchdog 20 us");
    end

    initial begin
        $timeformat(-9, 0, "", 0);
        if (!$value$plusargs("case=%s", scenario)) require(0, "missing case plusarg");
        #1;
        pixel_rst_n = 0;
        dfi_rst_n = 0;
        repeat (2) tick();

        case (scenario)
            "r4_first": begin
                startup(1, 1, 1);
                positive_frame(1, 0);
                next_owner(2);
                positive_frame(0, 1);
            end
            "reassert_r3": begin
                new_owner(3);
                pixel_rst_n = 1;
                repeat (2) tick();
                quiet_outputs("PIX released before DFI");
                dfi_rst_n = 1;
                through_r3();
                #83;
                quiet_outputs("extended R3 high before reset reassertion");
                pixel_rst_n = 0;
                #29;
                quiet_outputs("R3 high canceled before F3");
                new_owner(4);
                #13 pixel_rst_n = 1;
                #37;
                quiet_outputs("no rising edge since release while high");
                fall();
                quiet_outputs("first fall after R3 cancellation");
                take_r4(1);
                positive_frame(0, 0);
            end
            "reset_context": begin
                startup(5, 1, 0);
                repeat (3) tick();
                require(context_out_valid === 1'b1 && transfers[CONTEXT_OUT] == 0, "fixture lacks held context");
                stopped_reset(0, 1, 6);
            end
            "reset_rgb": begin
                startup(7, 0, 0);
                finish_context();
                offer_rgb(0);
                rise();
                require(rgb_out_valid === 1'b1 && transfers[RGB_OUT] == 0, "fixture lacks held RGB");
                stopped_reset(1, 1, 8);
            end
            "reset_notice": begin
                startup(9, 1, 0);
                finish_context();
                send_rgb(0);
                offer_status(1, 0, 4);
                read_quiet = 1;
                repeat (3) tick();
                require(notice_valid === 1'b1 && transfers[NOTICE_OUT] == 0, "fixture lacks held notice");
                stopped_reset(1, 0, 10);
            end
            "reset_result": begin
                startup(11, 0, 0);
                finish_context();
                send_rgb(0);
                offer_status(1, 0, 4);
                finish_notice();
                hold_result();
                rise();
                stopped_reset(0, 0, 12);
            end
            "negative_cleanup": begin
                startup(13, 0, 1);
                negative_cleanup();
                next_owner(14);
                positive_frame(0, 0);
            end
            default: require(0, "unknown case plusarg");
        endcase

        $display("BLACKBOX_PASS case=%s", scenario);
        $finish;
    end
endmodule
