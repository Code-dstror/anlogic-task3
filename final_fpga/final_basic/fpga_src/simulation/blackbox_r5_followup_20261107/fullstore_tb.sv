`timescale 1ns/1ps

module fullstore_tb #(parameter integer LOCAL_RETIRE = 1);
    localparam integer WIDTH = 8;
    localparam integer HEIGHT = 2;
    localparam integer GROUPS = WIDTH * HEIGHT / 4;
    localparam integer FRAME_BYTES = GROUPS * 5;

    reg pixel_clk = 0;
    reg dfi_clk = 0;
    always #4 pixel_clk = !pixel_clk;
    always #3.75 dfi_clk = !dfi_clk;
    reg rst_n;
    reg capture_enable;
    reg config_valid;
    wire config_ready, config_error;
    reg [31:0] config_session, config_epoch;
    reg [63:0] pair_now = 64'h10000;

    reg [39:0] capture_data [0:1];
    reg [1:0] capture_valid, capture_sof, capture_eol, source_valid, source_ok;
    reg [31:0] capture_session [0:1], capture_epoch [0:1], capture_seq [0:1];
    reg [196:0] capture_metadata [0:1];
    reg [7:0] source_error [0:1];
    wire [1:0] source_ready, enqueue_fire, capture_idle, frame_accept;
    wire write_quiet, ownership_quiet;

    reg job_ready, processing_done, retire_valid;
    reg [63:0] processing_id, retire_id;
    wire job_valid, retire_ready, retire_done, retire_error, stereo_empty;
    wire [383:0] job_frame;
    wire [63:0] job_lease, job_id;
    wire [1:0] job_bayer;
    wire job_time_valid;

    reg req_valid, rsp_ready;
    reg [2:0] req_op;
    reg req_camera;
    reg [1:0] req_slot;
    reg [31:0] req_generation, req_session;
    reg [63:0] req_lease, req_job_id;
    reg [383:0] req_descriptor;
    wire req_ready, rsp_valid;
    wire [3:0] rsp_code;
    wire native_done, native_error;
    wire [63:0] native_job_id;

    reg sink_select, replay_ready;
    wire replay_valid, fifo_source_reset_done, fifo_sink_reset_done;
    wire [146:0] replay_data;

    wire dec_start_valid, dec_start_ready, dec_release, dec_cancel, dec_run;
    wire dec_valid, dec_last, dec_ready, dec_raw_valid, dec_raw_ready;
    wire dec_sof, dec_eol, dec_done, dec_aborted, dec_quiet, dec_active;
    wire [127:0] dec_data;
    wire [15:0] dec_keep;
    wire [39:0] dec_raw;

    wire awvalid, awready, wvalid, wready, wlast, bready;
    reg bvalid;
    wire [3:0] awid;
    reg [3:0] bid;
    wire [27:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    wire arvalid, arready, rready;
    reg rvalid, rlast;
    wire [3:0] arid;
    reg [3:0] rid;
    wire [27:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    reg [127:0] rdata;

    full_raw_store #(
        .WIDTH(WIDTH), .HEIGHT(HEIGHT), .DESCRIPTOR_ENABLE(1),
        .DUAL_CAPTURE_ENABLE(1), .PAIR_METADATA_ENABLE(1), .STEREO_ENABLE(1),
        .CAMERA_COUNT(1), .CANONICAL_PRIVATE_FETCH_ENABLE(1), .OFFICIAL_CRC_QUALIFIED(1),
        .STEREO_CAPTURE_DIVISOR(1), .STEREO_RUNTIME_CADENCE(1),
        .SOURCE_TERMINAL_ENABLE(1), .SHARED_REPLAY_FIFO_ENABLE(1),
        .PRIVATE_REPLAY_ENABLE(1), .SHARED_DECODE_ENABLE(1), .RAW_EXPORT_ENABLE(1),
        .STEREO_SLOT_LOCAL_RETIRE_ENABLE(LOCAL_RETIRE), .SECOND_HDR_CAMERA(0)
    ) store (
        .i_cam1_hdr_enable(1'b0), .i_cam1_hdr_data(80'b0), .i_cam1_hdr_valid(2'b0),
        .i_cam1_hdr_sof(2'b0), .i_cam1_hdr_eol(2'b0), .i_cam1_hdr_abort(2'b0),
        .i_cam1_hdr_sequence(64'b0), .i_cam1_hdr_metadata(394'b0),
        .i_cam1_hdr_source_valid(2'b0), .i_cam1_hdr_source_ok(2'b0),
        .i_cam1_hdr_source_session(64'b0), .i_cam1_hdr_source_epoch(64'b0),
        .i_cam1_hdr_source_sequence(64'b0), .i_cam1_hdr_source_error(16'b0),
        .i_stereo_mode(1'b1), .i_raw_export(1'b0), .i_raw_cancel(1'b0),
        .i_raw_record_ready(1'b1), .i_raw_ready(1'b1),
        .i_raw_retire_valid(1'b0), .i_raw_retire_identity(128'b0),
        .i_stereo_mode_pixel(1'b1), .i_stereo_frame_divisor_pixel(8'd1),
        .o_stereo_job_valid(job_valid), .i_stereo_job_ready(job_ready), .o_stereo_job_frame(job_frame),
        .o_stereo_job_lease(job_lease), .o_stereo_job_id(job_id),
        .o_stereo_job_bayer(job_bayer), .o_stereo_job_time_valid(job_time_valid),
        .i_stereo_retire_valid(retire_valid), .i_stereo_retire_job_id(retire_id),
        .o_stereo_retire_ready(retire_ready), .o_stereo_retire_done(retire_done),
        .o_stereo_retire_error(retire_error), .o_stereo_empty(stereo_empty),
        .i_stereo_processing_done(processing_done), .i_stereo_processing_error(1'b0),
        .i_stereo_processing_job_id(processing_id),
        .o_decode_start_valid(dec_start_valid), .i_decode_start_ready(dec_start_ready),
        .o_decode_release(dec_release), .o_decode_cancel(dec_cancel), .o_decode_run(dec_run),
        .o_decode_data(dec_data), .o_decode_keep(dec_keep), .o_decode_valid(dec_valid),
        .o_decode_last(dec_last), .i_decode_ready(dec_ready), .i_decode_raw(dec_raw),
        .i_decode_raw_valid(dec_raw_valid), .o_decode_raw_ready(dec_raw_ready),
        .i_decode_sof(dec_sof), .i_decode_eol(dec_eol), .i_decode_done(dec_done),
        .i_decode_aborted(dec_aborted), .i_decode_quiet(dec_quiet), .i_decode_active(dec_active),
        .i_sdr_lz_enable(1'b0), .i_lz_fault(1'b0), .i_lz_region_quiet(1'b1),
        .i_capture_time_valid(1'b1), .i_bayer_valid(1'b1), .i_isp_bayer_phase(2'd1),
        .i_sdr_read_request_valid(1'b0), .i_sdr_read_request_context(448'b0),
        .i_sdr_read_ready(1'b1), .i_sdr_reader_cancel(1'b0),
        .i_sdr_release_valid(1'b0), .i_sdr_release_context(448'b0), .i_sdr_consumer_quiet(1'b1),
        .s_hdr_axi_arid(4'b0), .s_hdr_axi_araddr(28'b0), .s_hdr_axi_arlen(8'b0),
        .s_hdr_axi_arsize(3'b0), .s_hdr_axi_arburst(2'b0), .s_hdr_axi_arvalid(1'b0), .s_hdr_axi_rready(1'b1),
        .i_identity_rst_n(rst_n), .i_pair_stop(1'b0), .i_pair_fault(1'b0),
        .i_pair_config_valid(config_valid), .o_pair_config_ready(config_ready), .o_pair_config_error(config_error),
        .i_pair_session(config_session), .i_pair_epoch(config_epoch), .i_pair_max_wait(32'd10000),
        .i_pair_max_age(32'd10000), .i_pair_max_delta(64'd10000), .i_pair_ratio(3'd1), .i_pair_hdr_enable(1'b0),
        .i_pair_ready(1'b1), .i_pair_release_valid(1'b0), .i_pair_release_bank(1'b0), .i_pair_release_id(64'b0),
        .i_pair_read_quiet(1'b1), .i_pair_product_quiet(1'b1), .i_pair_ticket_released(1'b1),
        .i_pair_directory_valid(1'b0), .i_pair_directory_slot(2'b0), .m_pair_directory_ready(1'b1),
        .i_pair_now(pair_now), .i_capture_enable(capture_enable),
        .i_pixel_clk(pixel_clk), .i_pixel_rst_n(rst_n), .i_dfi_clk(dfi_clk), .i_dfi_rst_n(rst_n),
        .i_ddr_ready(1'b1), .i_cfs_enable(1'b0), .i_physical_mono_current_enable(1'b0),
        .i_user_clk(dfi_clk), .i_user_rst_n(rst_n),
        .i_capture_data(capture_data[0]), .i_capture_valid(capture_valid[0]), .i_capture_accept(capture_valid[0]),
        .i_capture_sof(capture_sof[0]), .i_capture_eol(capture_eol[0]), .i_capture_abort(1'b0),
        .i_capture_epoch(capture_epoch[0]), .i_session_id(capture_session[0]), .i_frame_sequence(capture_seq[0]),
        .i_mode_epoch(capture_epoch[0]), .i_capture_metadata(capture_metadata[0]),
        .i_capture_source_valid(source_valid[0]), .o_capture_source_ready(source_ready[0]),
        .i_capture_source_session(capture_session[0]), .i_capture_source_epoch(capture_epoch[0]),
        .i_capture_source_sequence(capture_seq[0]), .i_capture_source_camera(1'b0),
        .i_capture_source_ok(source_ok[0]), .i_capture_source_error(source_error[0]),
        .i_capture1_clk(pixel_clk), .i_capture1_rst_n(rst_n),
        .i_capture1_data(capture_data[1]), .i_capture1_valid(capture_valid[1]), .i_capture1_accept(capture_valid[1]),
        .i_capture1_sof(capture_sof[1]), .i_capture1_eol(capture_eol[1]), .i_capture1_abort(1'b0),
        .i_capture1_session(capture_session[1]), .i_capture1_sequence(capture_seq[1]),
        .i_capture1_epoch(capture_epoch[1]), .i_capture1_metadata(capture_metadata[1]),
        .i_capture1_source_valid(source_valid[1]), .o_capture1_source_ready(source_ready[1]),
        .i_capture1_source_session(capture_session[1]), .i_capture1_source_epoch(capture_epoch[1]),
        .i_capture1_source_sequence(capture_seq[1]), .i_capture1_source_camera(1'b1),
        .i_capture1_source_ok(source_ok[1]), .i_capture1_source_error(source_error[1]),
        .o_capture0_enqueue_fire(enqueue_fire[0]), .o_capture1_enqueue_fire(enqueue_fire[1]),
        .o_capture0_idle(capture_idle[0]), .o_capture1_idle(capture_idle[1]),
        .o_capture0_frame_accept(frame_accept[0]), .o_capture1_frame_accept(frame_accept[1]),
        .o_capture_write_quiescent(write_quiet), .o_private_ownership_quiescent(ownership_quiet),
        .i_commit_ready(1'b1), .i_ref_valid(1'b0), .i_ref_op(2'b0), .i_ref_mask(2'b0),
        .i_ref_frame0(384'b0), .i_ref_frame1(384'b0), .i_ref_lease0(64'b0), .i_ref_lease1(64'b0), .i_ref_job_id(64'b0),
        .i_shared_replay_source_select(1'b1), .i_shared_replay_sink_select(sink_select),
        .s_shared_replay_data(147'b0), .s_shared_replay_valid(1'b0),
        .o_shared_replay_source_reset_done(fifo_source_reset_done),
        .m_shared_replay_data(replay_data), .m_shared_replay_valid(replay_valid),
        .m_shared_replay_ready(replay_ready), .o_shared_replay_sink_reset_done(fifo_sink_reset_done),
        .i_private_req_valid(req_valid), .o_private_req_ready(req_ready), .i_private_req_op(req_op),
        .i_private_req_camera(req_camera), .i_private_req_slot(req_slot),
        .i_private_req_generation(req_generation), .i_private_req_session(req_session),
        .i_private_req_lease(req_lease), .i_private_req_job_id(req_job_id),
        .i_private_req_offset(32'b0), .i_private_req_length(32'b0), .i_public_read_admission_enable(1'b0),
        .i_mask_command_ready(1'b1), .i_mask_response_data(147'b0), .i_mask_response_valid(1'b0),
        .i_mask_block_data(147'b0), .i_mask_block_valid(1'b0), .i_mask_owner_complete(1'b0),
        .i_private_descriptor(req_descriptor), .i_private_pair_id(64'b0), .i_private_member_index(1'b0),
        .o_private_rsp_valid(rsp_valid), .i_private_rsp_ready(rsp_ready), .o_private_rsp_code(rsp_code),
        .i_private_read_ready(1'b1), .o_private_native_done(native_done),
        .o_private_native_error(native_error), .o_private_native_job_id(native_job_id),
        .i_replay_context_ready(1'b1), .i_host_replay_context_ready(1'b1), .i_replay_safe(1'b1), .i_replay_ready(1'b1),
        .i_bar_write_valid(1'b0), .i_bar_write_offset(12'b0), .i_bar_write_data(32'b0), .i_bar_write_strobes(4'b0),
        .i_bar_read_valid(1'b0), .i_bar_read_offset(12'b0),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(2'b00), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(2'b00), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    shared_raw10_decode_service #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) service (
        .clk(dfi_clk), .rst_n(rst_n),
        .hdr_start_valid(1'b0), .hdr_start_ready(), .hdr_release(1'b0), .hdr_abort(2'b0),
        .hdr_member(1'b0), .hdr_data(128'b0), .hdr_keep(16'b0), .hdr_valid(1'b0), .hdr_last(1'b0),
        .hdr_ready(), .hdr_raw_member(), .hdr_raw(), .hdr_raw_valid(), .hdr_raw_ready(1'b0),
        .hdr_done(), .hdr_aborted(), .stereo_start_valid(dec_start_valid), .stereo_start_ready(dec_start_ready),
        .stereo_release(dec_release), .stereo_cancel(dec_cancel), .stereo_run(dec_run),
        .stereo_data(dec_data), .stereo_keep(dec_keep), .stereo_valid(dec_valid), .stereo_last(dec_last),
        .stereo_ready(dec_ready), .stereo_raw(dec_raw), .stereo_raw_valid(dec_raw_valid),
        .stereo_raw_ready(dec_raw_ready), .stereo_sof(dec_sof), .stereo_eol(dec_eol),
        .stereo_done(dec_done), .stereo_aborted(dec_aborted), .stereo_quiet(dec_quiet),
        .stereo_active(dec_active), .quiet()
    );
    string case_name, stage;
    integer dfi_cycle = 0;
    reg [1:0] hold_b;
    bit write_open, b_pending, read_open;
    integer write_slot, write_offset, write_left;
    reg [3:0] write_id;
    integer read_slot, read_offset, read_left, read_delay;
    reg [3:0] read_id;
    reg [7:0] memory [0:3][0:63];
    reg [63:0] memory_valid [0:3];
    bit slot_b_complete [0:3];
    reg [31:0] slot_seq [0:3];
    integer aw_count, w_count, b_count, ar_count, r_count;
    integer enqueue_count [0:1], source_count [0:1], frame_count [0:1];
    integer capture_trace_count [0:1];
    bit last_source_ok [0:1];
    reg [31:0] last_source_seq [0:1];

    integer config_count, job_count, req_count, rsp_count, retire_count, retire_done_count;
    reg [3:0] response_code;
    bit job_live, allow_replay, native_seen, processed_seen;
    reg [383:0] live_frame;
    reg [63:0] live_lease, live_id;
    integer live_memory_slot, pixel_groups, pixel_fences;
    bit replay_held;
    reg [146:0] held_replay;

    assign awready = rst_n && !write_open && !b_pending;
    assign wready = rst_n && write_open;
    assign arready = rst_n && !read_open;

    function automatic [27:0] slot_base(input integer slot);
        case (slot)
            0: slot_base = 28'h2000000;
            1: slot_base = 28'h3000000;
            2: slot_base = 28'h6000000;
            3: slot_base = 28'h7000000;
            default: slot_base = 28'h0;
        endcase
    endfunction

    function automatic integer address_slot(input [27:0] addr);
        address_slot = -1;
        for (integer slot = 0; slot < 4; slot = slot + 1)
            if (addr >= slot_base(slot) && addr < slot_base(slot) + 64) address_slot = slot;
    endfunction

    function automatic [9:0] pixel_value(input bit cam, input [31:0] seq, input integer index);
        pixel_value = cam * 361 + seq * 121 + index * 73 + index / 4 * 17;
    endfunction

    function automatic [135:0] data_token(input bit cam, input [31:0] seq, input integer group_index);
        data_token = 0;
        data_token[134:103] = group_index;
        data_token[102] = group_index == GROUPS - 1;
        data_token[101] = group_index % (WIDTH / 4) == WIDTH / 4 - 1;
        data_token[100] = group_index == 0;
        data_token[99:96] = 4'hf;
        for (integer lane = 0; lane < 4; lane = lane + 1)
            data_token[14 * lane +: 14] = {4'b0, pixel_value(cam, seq, group_index * 4 + lane)};
    endfunction

    function automatic [127:0] read_memory(input integer slot, input integer offset);
        read_memory = 0;
        for (integer lane = 0; lane < 16; lane = lane + 1)
            if (memory_valid[slot][offset + lane])
                read_memory[8 * lane +: 8] = memory[slot][offset + lane];
    endfunction

    task automatic fail(input string why);
        $display("FULLSTORE_FAIL case=%s local=%0d stage=%s dfi=%0d %s",
                 case_name, LOCAL_RETIRE, stage, dfi_cycle, why);
        $display("CAP enqueue=%0d/%0d source=%0d/%0d idle=%b frame_accept=%b quiet=%b ownership_quiet=%b",
                 enqueue_count[0], enqueue_count[1], source_count[0], source_count[1],
                 capture_idle, frame_accept, write_quiet, ownership_quiet);
        $display("AXI count AW/W/B=%0d/%0d/%0d AR/R=%0d/%0d b_pending=%b held_b=%b write_slot=%0d",
                 aw_count, w_count, b_count, ar_count, r_count, b_pending, hold_b, write_slot);
        $display("JOB count=%0d v/r=%b%b id=%h lease=%h config=%0d v/r/err=%b%b%b FIFO reset=%b%b DATA/FENCE=%0d/%0d native=%b retire=%0d/%0d v/r=%b%b",
                 job_count, job_valid, job_ready, live_id, live_lease, config_count, config_valid,
                 config_ready, config_error, fifo_source_reset_done, fifo_sink_reset_done, pixel_groups,
                 pixel_fences, native_seen, retire_count, retire_done_count, retire_valid, retire_ready);
        $fatal(1);
    endtask

    function automatic bit legal_burst(input [27:0] addr, input [7:0] len,
                                       input [2:0] size, input [1:0] burst);
        return !$isunknown({addr, len, size, burst}) && addr[3:0] == 0 && size == 4 && burst == 1 &&
               len <= 15 && int'(addr[11:0]) + 16 * (int'(len) + 1) <= 4096;
    endfunction

    always @(posedge dfi_clk) begin : ddr_bfm
        integer slot;
        integer offset;
        dfi_cycle = dfi_cycle + 1;
        pair_now <= pair_now + 1;
        if (!rst_n) begin
            write_open <= 0;
            b_pending <= 0;
            bvalid <= 0;
            read_open <= 0;
            rvalid <= 0;
            aw_count = 0;
            w_count = 0;
            b_count = 0;
            ar_count = 0;
            r_count = 0;
            for (integer bank = 0; bank < 4; bank = bank + 1) begin
                memory_valid[bank] = 0;
                slot_b_complete[bank] = 0;
            end
        end else begin
            if (awvalid && awready) begin
                slot = address_slot(awaddr);
                if (slot < 0 || !legal_burst(awaddr, awlen, awsize, awburst)) fail("illegal AW");
                offset = int'(awaddr - slot_base(slot));
                if (offset + 16 * (int'(awlen) + 1) > 64) fail("AW exceeds sparse slot window");
                if (offset == 0) begin
                    memory_valid[slot] = 0;
                    slot_b_complete[slot] = 0;
                    slot_seq[slot] = capture_seq[slot >= 2];
                end
                write_slot <= slot;
                write_offset <= offset;
                write_left <= int'(awlen) + 1;
                write_id <= awid;
                write_open <= 1;
                aw_count = aw_count + 1;
                $display("AW dfi=%0d slot=%0d addr=%h beats=%0d id=%h", dfi_cycle, slot, awaddr, int'(awlen) + 1, awid);
            end
            if (wvalid && wready) begin
                if (wlast !== (write_left == 1) || $isunknown(wstrb)) fail("W shape disagrees with AW");
                for (integer lane = 0; lane < 16; lane = lane + 1) begin
                    if (wstrb[lane]) begin
                        memory[write_slot][write_offset + lane] = wdata[8 * lane +: 8];
                        memory_valid[write_slot][write_offset + lane] = 1;
                    end
                end
                w_count = w_count + 1;
                $display("W dfi=%0d slot=%0d offset=%0d strb=%h last=%b", dfi_cycle, write_slot, write_offset, wstrb, wlast);
                if (write_left == 1) begin
                    write_open <= 0;
                    b_pending <= 1;
                end else begin
                    write_left <= write_left - 1;
                    write_offset <= write_offset + 16;
                end
            end
            if (b_pending && !bvalid && !hold_b[write_slot >= 2]) begin
                bid <= write_id;
                bvalid <= 1;
            end
            if (bvalid && bready) begin
                bvalid <= 0;
                b_pending <= 0;
                if (&memory_valid[write_slot][FRAME_BYTES-1:0]) slot_b_complete[write_slot] = 1;
                b_count = b_count + 1;
                $display("B dfi=%0d slot=%0d id=%h full_frame=%b", dfi_cycle, write_slot, bid, slot_b_complete[write_slot]);
            end

            if (arvalid && arready) begin
                slot = address_slot(araddr);
                if (!job_live || !allow_replay) fail("unexpected AR without an authorized replay");
                if (slot != live_memory_slot || !legal_burst(araddr, arlen, arsize, arburst))
                    fail($sformatf("AR does not target the live job slot addr=%h slot=%0d expected=%0d", araddr, slot, live_memory_slot));
                offset = int'(araddr - slot_base(slot));
                if (offset + 16 * (int'(arlen) + 1) > 32 || !slot_b_complete[slot]) fail("AR exceeded written frame");
                read_slot <= slot;
                read_offset <= offset;
                read_left <= int'(arlen) + 1;
                read_id <= arid;
                read_open <= 1;
                read_delay <= 3;
                ar_count = ar_count + 1;
                $display("AR dfi=%0d job=%h slot=%0d addr=%h beats=%0d", dfi_cycle, live_id, slot, araddr, int'(arlen) + 1);
            end
            if (read_open) begin
                if (rvalid && rready) begin
                    rvalid <= 0;
                    r_count = r_count + 1;
                    $display("R dfi=%0d job=%h slot=%0d offset=%0d last=%b", dfi_cycle, live_id, read_slot, read_offset, rlast);
                    if (read_left == 1) begin
                        read_open <= 0;
                    end else begin
                        read_left <= read_left - 1;
                        read_offset <= read_offset + 16;
                    end
                end else if (!rvalid) begin
                    if (read_delay != 0) begin
                        read_delay <= read_delay - 1;
                    end else begin
                        rid <= read_id;
                        rdata <= read_memory(read_slot, read_offset);
                        rlast <= read_left == 1;
                        rvalid <= 1;
                    end
                end
            end
        end
    end
    always @(posedge pixel_clk) begin
        if (!rst_n) begin
            replay_held = 0;
            for (integer cam = 0; cam < 2; cam = cam + 1) begin
                enqueue_count[cam] = 0;
                source_count[cam] = 0;
                frame_count[cam] = 0;
                capture_trace_count[cam] = 0;
                last_source_ok[cam] = 0;
            end
        end else begin
            for (integer cam = 0; cam < 2; cam = cam + 1) begin
                if (enqueue_fire[cam]) enqueue_count[cam] = enqueue_count[cam] + 1;
                if (frame_accept[cam]) frame_count[cam] = frame_count[cam] + 1;
                if ((capture_valid[cam] || enqueue_fire[cam]) && capture_trace_count[cam] < 12) begin
                    capture_trace_count[cam] = capture_trace_count[cam] + 1;
                    $display("CAP_EDGE t=%0t cam=%0d valid=%b sof=%b eol=%b data=%h enq=%b accept=%b idle=%b",
                             $time, cam, capture_valid[cam], capture_sof[cam], capture_eol[cam], capture_data[cam],
                             enqueue_fire[cam], frame_accept[cam], capture_idle[cam]);
                end
                if (source_valid[cam] && source_ready[cam]) begin
                    source_count[cam] = source_count[cam] + 1;
                    last_source_ok[cam] = source_ok[cam];
                    last_source_seq[cam] = capture_seq[cam];
                    $display("SOURCE t=%0t cam=%0d seq=%0d ok=%b error=%0d", $time, cam, capture_seq[cam], source_ok[cam], source_error[cam]);
                end
            end
            if (replay_held && (replay_valid !== 1'b1 || replay_data !== held_replay))
                fail("PIX replay token changed while stalled");
            replay_held = replay_valid && !replay_ready;
            held_replay = replay_data;
            if (replay_valid && (!job_live || !allow_replay || pixel_fences != 0))
                fail("PIX replay token appeared outside its authorized job");
            if (replay_valid && replay_ready) begin
                case (replay_data[146:145])
                    2'd0: begin
                        if (pixel_groups >= GROUPS ||
                            replay_data[135:0] !== data_token(live_frame[4], live_frame[108:77], pixel_groups))
                            fail($sformatf("PIX DATA mismatch group=%0d got=%h expected=%h", pixel_groups,
                                           replay_data[135:0], data_token(live_frame[4], live_frame[108:77], pixel_groups)));
                        pixel_groups = pixel_groups + 1;
                    end
                    2'd1: begin
                        if (replay_data[144:105] !== 40'b0 || replay_data[104:97] !== 8'b0 ||
                            replay_data[96] !== 1'b1 || replay_data[95:32] !== live_id ||
                            replay_data[31:0] !== GROUPS || pixel_groups != GROUPS)
                            fail($sformatf("bad PIX FENCE token=%h", replay_data));
                        pixel_fences = pixel_fences + 1;
                        $display("PIX_FENCE t=%0t job=%h cam=%0d groups=%0d", $time, live_id, live_frame[4], pixel_groups);
                    end
                    default: fail("bad PIX token kind");
                endcase
            end
        end
    end

    always @(posedge dfi_clk) begin : owner_monitor
        integer slot;
        bit cam;
        if (!rst_n) begin
            config_count = 0;
            job_count = 0;
            req_count = 0;
            rsp_count = 0;
            retire_count = 0;
            retire_done_count = 0;
            job_live = 0;
        end else begin
            if (config_valid && config_ready) begin
                if (config_error !== 1'b0) fail("pair config rejected");
                config_count = config_count + 1;
                $display("CONFIG dfi=%0d session=%h epoch=%h writer_quiet=%b", dfi_cycle, config_session, config_epoch, write_quiet);
            end
            if (job_valid) begin
                if ($isunknown({job_frame[140:4], job_lease, job_id}) || job_id == 0 || job_lease == 0)
                    fail("invalid offered job identity");
                cam = job_frame[4];
                if (job_frame[6:5] > 1) fail("nonlocal stereo slot identity");
                slot = 2 * int'(cam) + int'(job_frame[6:5]);
                if (!slot_b_complete[slot] || slot_seq[slot] != job_frame[108:77] ||
                    !last_source_ok[cam] || last_source_seq[cam] != job_frame[108:77])
                    fail("job offered without both a matching successful SOURCE and actual B");
                if (job_ready) begin
                    if (job_live) fail("job overlap in single replay test");
                    job_count = job_count + 1;
                    live_frame = job_frame;
                    live_lease = job_lease;
                    live_id = job_id;
                    live_memory_slot = slot;
                    pixel_groups = 0;
                    pixel_fences = 0;
                    native_seen = 0;
                    processed_seen = 0;
                    job_live = 1;
                    $display("JOB dfi=%0d id=%h cam=%0d slot=%0d DDR_slot=%0d gen=%h session=%h seq=%0d epoch=%h",
                             dfi_cycle, job_id, cam, job_frame[6:5], slot, job_frame[44:13],
                             job_frame[76:45], job_frame[108:77], job_frame[140:109]);
                end
            end
            if (req_valid && req_ready) req_count = req_count + 1;
            if (rsp_valid && rsp_ready) begin
                rsp_count = rsp_count + 1;
                response_code = rsp_code;
                $display("PRIVATE_RSP dfi=%0d op=%0d request_job=%h code=%0d", dfi_cycle, req_op, req_job_id, rsp_code);
            end
            if (processing_done) begin
                if (!job_live || processing_id !== live_id || pixel_fences != 1 || processed_seen)
                    fail("processing BFM was not causally after the PIX FENCE");
                processed_seen = 1;
                $display("PROCESSING_BFM dfi=%0d job=%h", dfi_cycle, live_id);
            end
            if (native_done && !native_seen) begin
                if (!job_live || !allow_replay || native_error !== 1'b0 || native_job_id !== live_id)
                    fail("native completion identity or outcome mismatch");
                native_seen = 1;
                $display("NATIVE_DONE dfi=%0d job=%h", dfi_cycle, live_id);
            end
            if (retire_valid && retire_ready) begin
                if (!job_live || !processed_seen || retire_id !== live_id) fail("unexpected stereo retire handshake");
                retire_count = retire_count + 1;
                $display("RETIRE_ACCEPT dfi=%0d job=%h writer_quiet=%b b_pending=%b", dfi_cycle, live_id, write_quiet, b_pending);
            end
            if (retire_done) begin
                if (!job_live || retire_count != retire_done_count + 1 || retire_error !== 1'b0)
                    fail("stereo retire result without its valid request or with an error");
                retire_done_count = retire_done_count + 1;
                job_live = 0;
                $display("RETIRE_DONE dfi=%0d job=%h writer_quiet=%b b_pending=%b", dfi_cycle, live_id, write_quiet, b_pending);
            end
        end
    end

    task automatic tick_dfi;
        @(negedge dfi_clk);
    endtask

    task automatic tick_pixel;
        @(negedge pixel_clk);
    endtask

    task automatic finish_config(input integer target_count);
        while (config_count < target_count) tick_dfi();
        config_valid = 0;
        repeat (12) tick_dfi();
    endtask

    task automatic boot;
        stage = "reset and CDC FIFO initialization";
        rst_n = 0;
        capture_enable = 0;
        config_valid = 0;
        capture_valid = 0;
        capture_sof = 0;
        capture_eol = 0;
        source_valid = 0;
        source_ok = 0;
        job_ready = 0;
        processing_done = 0;
        retire_valid = 0;
        req_valid = 0;
        rsp_ready = 0;
        sink_select = 0;
        replay_ready = 0;
        hold_b = 0;
        allow_replay = 0;
        for (integer cam = 0; cam < 2; cam = cam + 1) begin
            capture_session[cam] = 0;
            capture_epoch[cam] = 0;
            capture_seq[cam] = 0;
            capture_metadata[cam] = 0;
            capture_data[cam] = 0;
            source_error[cam] = 0;
        end
        config_session = 32'h39;
        config_epoch = 32'h73;
        repeat (16) tick_dfi();
        rst_n = 1;
        capture_enable = 1;
        while (fifo_source_reset_done !== 1'b1 || fifo_sink_reset_done !== 1'b1) tick_dfi();
        stage = "initial configuration";
        config_valid = 1;
        finish_config(1);
    endtask

    task automatic send_capture(input bit cam, input [31:0] seq);
        integer next_frame;
        stage = $sformatf("camera %0d crop capture seq %0d", cam, seq);
        tick_pixel();
        capture_session[cam] = config_session;
        capture_epoch[cam] = config_epoch;
        capture_seq[cam] = seq;
        capture_metadata[cam] = {4'b0, 1'b1, 128'b0, pair_now};
        next_frame = frame_count[cam] + 1;
        for (integer group_index = 0; group_index < GROUPS; group_index = group_index + 1) begin
            for (integer lane = 0; lane < 4; lane = lane + 1)
                capture_data[cam][lane * 10 +: 10] = pixel_value(cam, seq, group_index * 4 + lane);
            capture_sof[cam] = group_index == 0;
            capture_eol[cam] = group_index % (WIDTH / 4) == WIDTH / 4 - 1;
            capture_valid[cam] = 1;
            tick_pixel();
        end
        capture_valid[cam] = 0;
        capture_sof[cam] = 0;
        capture_eol[cam] = 0;
        repeat (2) tick_pixel();
        if (frame_count[cam] != next_frame) fail("crop SOF did not start exactly one capture");
        $display("CAPTURE t=%0t cam=%0d seq=%0d RAW4=%0d", $time, cam, seq, GROUPS);
    endtask

    task automatic send_source(input bit cam, input bit ok);
        integer next_source;
        stage = $sformatf("camera %0d source terminal", cam);
        tick_pixel();
        next_source = source_count[cam] + 1;
        source_ok[cam] = ok;
        source_error[cam] = ok ? 8'd0 : 8'd7;
        source_valid[cam] = 1;
        while (source_count[cam] < next_source) tick_pixel();
        source_valid[cam] = 0;
    endtask

    task automatic take_job(input bit cam, input [31:0] seq);
        integer next_job;
        stage = $sformatf("camera %0d job offer seq %0d", cam, seq);
        tick_dfi();
        next_job = job_count + 1;
        sink_select = 1;
        job_ready = 1;
        while (job_count < next_job) tick_dfi();
        job_ready = 0;
        if (live_frame[4] !== cam || live_frame[108:77] !== seq ||
            live_frame[76:45] !== capture_session[cam] || live_frame[140:109] !== capture_epoch[cam] ||
            live_frame[204:141] !== capture_metadata[cam][63:0])
            fail("offered frame does not match the selected capture cohort and timestamp");
    endtask

    task automatic private_command(input [2:0] op, input integer wrong_field);
        integer next_req, next_rsp;
        stage = $sformatf("private op=%0d wrong_field=%0d", op, wrong_field);
        next_req = req_count + 1;
        next_rsp = rsp_count + 1;
        req_op = op;
        req_camera = live_frame[4];
        req_slot = live_frame[6:5];
        req_generation = live_frame[44:13] ^ (wrong_field == 3 ? 32'h1 : 32'h0);
        req_session = live_frame[76:45];
        req_lease = live_lease ^ (wrong_field == 2 ? 64'h1 : 64'h0);
        req_job_id = live_id ^ (wrong_field == 1 ? 64'h1 : 64'h0);
        req_descriptor = live_frame;
        rsp_ready = 1;
        req_valid = 1;
        while (req_count < next_req) tick_dfi();
        req_valid = 0;
        while (rsp_count < next_rsp) tick_dfi();
        rsp_ready = 0;
        if ($isunknown(response_code) || ((response_code == 0) != (wrong_field == 0)))
            fail($sformatf("private command outcome mismatch op=%0d wrong_field=%0d code=%0d", op, wrong_field, response_code));
    endtask

    task automatic process_job;
        allow_replay = 1;
        private_command(3'd4, 0);
        stage = "PIX replay DATA and FENCE";
        while (replay_valid !== 1'b1) tick_pixel();
        repeat (3) tick_pixel();
        replay_ready = 1;
        while (pixel_fences == 0) tick_pixel();
        tick_dfi();
        stage = "processing completion BFM and native done";
        processing_id = live_id;
        processing_done = 1;
        tick_dfi();
        processing_done = 0;
        while (!native_seen) tick_dfi();
    endtask

    task automatic retire_job;
        integer next_retire, next_done;
        private_command(3'd5, 0);
        stage = "stereo slot retire";
        next_retire = retire_count + 1;
        next_done = retire_done_count + 1;
        retire_id = live_id;
        retire_valid = 1;
        while (retire_count < next_retire) tick_dfi();
        retire_valid = 0;
        while (retire_done_count < next_done) tick_dfi();
        allow_replay = 0;
        tick_pixel();
        sink_select = 0;
        replay_ready = 0;
        tick_dfi();
    endtask

    task automatic normal_job(input bit cam, input [31:0] seq);
        send_capture(cam, seq);
        send_source(cam, 1);
        take_job(cam, seq);
        process_job();
        retire_job();
    endtask

    task automatic wait_held_b(input bit cam);
        stage = $sformatf("camera %0d actual AW/W with B withheld", cam);
        tick_dfi();
        while (!b_pending || (write_slot >= 2) != cam) tick_dfi();
        if (bvalid || !hold_b[cam] || write_quiet !== 1'b0 || !(&memory_valid[write_slot][FRAME_BYTES-1:0]))
            fail("setup did not establish a complete W burst with B debt and a live writer");
        $display("HOLD_B dfi=%0d cam=%0d slot=%0d writer_quiet=%b", dfi_cycle, cam, write_slot, write_quiet);
    endtask
    task automatic staggered_jobs;
        integer saved_b_count, first_retire_target;
        send_capture(0, 1);
        send_source(0, 1);
        take_job(0, 1);
        hold_b[1] = 1;
        send_capture(1, 1);
        send_source(1, 1);
        wait_held_b(1);
        saved_b_count = b_count;
        process_job();
        first_retire_target = retire_done_count + 1;
        fork
            retire_job();
            begin
                repeat (36) tick_dfi();
                if (write_quiet !== 1'b0 || !b_pending || bvalid || b_count != saved_b_count || write_slot < 2)
                    fail("other eye did not retain its real B debt through the comparison window");
                if (LOCAL_RETIRE && retire_done_count != first_retire_target)
                    fail("target failed to retire with only the other eye's B outstanding");
                if (!LOCAL_RETIRE && retire_done_count >= first_retire_target)
                    fail("global-gate control unexpectedly retired with the other eye's B outstanding");
                $display("RETIRE_WINDOW dfi=%0d local=%0d retired=%0d target=%0d writer_quiet=%b other_B_pending=%b",
                         dfi_cycle, LOCAL_RETIRE, retire_done_count, first_retire_target, write_quiet, b_pending);
                hold_b[1] = 0;
            end
        join
        take_job(1, 1);
        process_job();
        retire_job();
        normal_job(0, 2);
    endtask

    task automatic config_and_rejections;
        integer old_config_count, held_b_count;
        hold_b[0] = 1;
        send_capture(0, 3);
        wait_held_b(0);
        send_source(0, 0);
        tick_dfi();
        stage = "bad SOURCE after its successful B with configuration unchanged";
        held_b_count = b_count;
        hold_b[0] = 0;
        while (b_count == held_b_count || write_quiet !== 1'b1) tick_dfi();
        repeat (12) tick_dfi();
        if (job_valid || job_count != 0 || !stereo_empty) fail("bad SOURCE escaped as a stereo job");
        $display("BAD_SOURCE_REJECTED dfi=%0d B=%0d job_count=%0d session=%h epoch=%h", dfi_cycle, b_count, job_count,
                 config_session, config_epoch);

        hold_b[0] = 1;
        send_capture(0, 4);
        wait_held_b(0);
        send_source(0, 0);
        tick_dfi();
        stage = "new configuration with a prior writer still owing B";
        old_config_count = config_count;
        held_b_count = b_count;
        config_session = 32'h3a;
        config_epoch = 32'h74;
        config_valid = 1;
        repeat (24) begin
            tick_dfi();
            if (config_count != old_config_count || write_quiet !== 1'b0 || !b_pending || b_count != held_b_count)
                fail("new configuration completed or writer appeared quiet with B debt");
        end
        $display("CONFIG_BLOCKED dfi=%0d writer_quiet=%b B_pending=%b clocks=24", dfi_cycle, write_quiet, b_pending);
        hold_b[0] = 0;
        finish_config(old_config_count + 1);
        if (b_count != held_b_count + 1 || job_valid || job_count != 0)
            fail("bad SOURCE produced a job or its B was not drained");
        send_capture(1, 5);
        send_source(1, 1);
        take_job(1, 5);
        for (integer field_index = 1; field_index <= 3; field_index = field_index + 1) begin
            private_command(3'd4, field_index);
            repeat (4) tick_dfi();
        end
        process_job();
        retire_job();
    endtask

    initial begin
        if (!$value$plusargs("CASE=%s", case_name)) $fatal(1, "missing +CASE");
        boot();
        case (case_name)
            "normal": begin
                normal_job(0, 1);
                normal_job(1, 1);
                normal_job(0, 2);
            end
            "stagger": staggered_jobs();
            "config_reject": config_and_rejections();
            default: fail("unknown case");
        endcase
        stage = "final quiet";
        repeat (8) tick_dfi();
        if (write_quiet !== 1'b1 || ownership_quiet !== 1'b1 || stereo_empty !== 1'b1)
            fail("integration did not return to quiet and empty");
        $display("FULLSTORE_PASS case=%s local=%0d jobs=%0d retired=%0d dfi=%0d AW/W/B=%0d/%0d/%0d AR/R=%0d/%0d",
                 case_name, LOCAL_RETIRE, job_count, retire_done_count, dfi_cycle,
                 aw_count, w_count, b_count, ar_count, r_count);
        $finish;
    end

    initial begin
        #60000;
        fail("simulation watchdog expired");
    end
endmodule
