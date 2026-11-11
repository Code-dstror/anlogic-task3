`timescale 1ns/1ps

module tb_fusion_product;
    localparam int WIDTH = 480;
    localparam int HEIGHT = 32;
    localparam int GROUPS_PER_ROW = WIDTH / 4;
    localparam int RAW_BYTES = GROUPS_PER_ROW * HEIGHT * 5;
    localparam int HEADER_BYTES = 2112;
    localparam int BUFFER_BYTES = 65536;
    localparam logic [63:0] HOST_BASE = 64'h00000001_10000000;
    localparam logic [63:0] FENCE_ADDR = 64'h00000001_20000040;
    localparam logic [31:0] FENCE_COOKIE = 32'hdec417aa;
    localparam int APP_BASE = 'h80000;
    localparam int WB_R = 333;
    localparam int WB_G = 178;
    localparam int WB_B = 226;
    localparam logic [31:0] WB_WORD = (1 << 30) | (WB_B << 20) | (WB_G << 10) | WB_R;

    logic sys_clk = 0, board_ref_clk_100m = 0, pcie_mperst = 0;
    logic i_pixel_clk = 0, i_clock_ready = 0, i_mem_clk = 0, i_mem_ready = 0;
    logic i_host_clk = 0, i_host_link_up = 0, i_host_bme = 0;
    bit dfi_running = 0;
    always #20 sys_clk = ~sys_clk;
    always #5 board_ref_clk_100m = ~board_ref_clk_100m;
    always #4 i_pixel_clk = ~i_pixel_clk;
    always #3.751 if (dfi_running) i_mem_clk = ~i_mem_clk;
    initial begin
        #1.301;
        forever #4 i_host_clk = ~i_host_clk;
    end

    logic [39:0] i_crop_data = 0;
    logic i_crop_valid = 0, i_crop_sof = 0, i_crop_eol = 0;
    logic [31:0] i_crop_sequence = 0;
    logic i_crop_identity_valid = 0;
    wire o_crop_ready;
    logic i_event_valid = 0, i_event_ok = 0, i_event_identity_valid = 0;
    logic [1:0] i_event_kind = 0;
    logic [3:0] i_event_error = 0;
    logic [31:0] i_event_sequence = 0;
    wire o_event_ready;
    wire [2:0] o_sensor_profile;
    logic [2:0] i_sensor_profile = 0;
    logic i_sensor_config_done = 0, i_sensor_mode_running = 0;

    logic i_mem_awready = 0, i_mem_wready = 0, i_mem_arready = 0;
    logic [3:0] i_mem_bid = 0, i_mem_rid = 0;
    logic [1:0] i_mem_bresp = 0, i_mem_rresp = 0;
    logic i_mem_bvalid = 0, i_mem_rlast = 0, i_mem_rvalid = 0;
    logic [127:0] i_mem_rdata = 0;
    wire o_mem_reset_n;
    wire [3:0] o_mem_awid, o_mem_arid;
    wire [27:0] o_mem_awaddr, o_mem_araddr;
    wire [7:0] o_mem_awlen, o_mem_arlen;
    wire [2:0] o_mem_awsize, o_mem_arsize;
    wire [1:0] o_mem_awburst, o_mem_arburst;
    wire o_mem_awvalid, o_mem_wvalid, o_mem_wlast, o_mem_bready;
    wire o_mem_arvalid, o_mem_rready;
    wire [127:0] o_mem_wdata;
    wire [15:0] o_mem_wstrb;

    logic [127:0] i_cq_data = 0, i_rc_data = 0;
    logic [3:0] i_cq_keep = 0, i_rc_keep = 0;
    logic [87:0] i_cq_user = 0;
    logic [74:0] i_rc_user = 0;
    logic i_cq_last = 0, i_cq_valid = 0, i_cc_ready = 0;
    logic i_rc_last = 0, i_rc_valid = 0, i_tlp_halt = 0;
    wire o_cq_ready, o_cc_last, o_cc_valid, o_rc_ready;
    wire [127:0] o_cc_data, o_tlp_data;
    wire [3:0] o_cc_keep;
    wire [32:0] o_cc_user;
    wire [63:0] o_tlp_address;
    wire [7:0] o_tlp_byte_enable;
    wire [12:0] o_tlp_byte_length;
    wire [1:0] o_tlp_format;
    wire [9:0] o_tlp_tag;
    wire o_tlp_header_valid, o_tlp_data_valid, o_tlp_end;

    wire o_pixel_reset_n, o_dfi_reset_n, o_user_reset_n;
    wire o_cfg_ack_fire, o_cfg_ack_ok, o_cold_config_sof, o_uhd_pixel;
    wire [31:0] o_cfg_ack_session, o_cfg_ack_epoch;
    wire o_capture_enabled, o_capture_frame_accept, o_session_armed, o_buffer_armed;
    wire o_replay_source_fire, o_replay_source_ok, o_jpeg_source_done, o_jpeg_source_failed;
    wire [63:0] o_replay_source_tag, o_ticket_job;
    wire o_jpeg_start_fire, o_jpeg_result_fire, o_jpeg_result_ok;
    wire [15:0] o_jpeg_start_width, o_jpeg_start_height;
    wire [31:0] o_jpeg_start_sequence, o_writer_ack_sequence;
    wire [24:0] o_jpeg_result_length;
    wire o_writer_ack_fire, o_writer_ack_ok, o_ticket_result, o_ticket_error;
    wire o_raw_slot_retired, o_raw_empty, o_record_offer, o_record_retire_fire;
    wire o_ring_retire_response_valid, o_record_quiet, o_fault;
    wire [3:0] o_ring_retire_response_code;

    uhd_integration_fixture dut (
        .mipi_clk_hs_rx_p(1'b0), .mipi_data_hs_p(4'b0),
        .mipi1_clk_hs_rx_p(1'b0), .mipi1_data_hs_p(4'b0),
        .cam_scl(), .cam_sda(), .cam_mclk(), .cam_xclr(),
        .cam1_scl(), .cam1_sda(), .cam1_mclk(), .cam1_xclr(),
        .uart_tx(), .uart_rx(1'b1),
        .ddr_ck_p(), .ddr_ck_n(), .ddr_reset_n(), .ddr_cke(), .ddr_odt(),
        .ddr_cs_n(), .ddr_ras_n(), .ddr_cas_n(), .ddr_we_n(), .ddr_ba(), .ddr_addr(),
        .ddr_dqs_p(), .ddr_dqs_n(), .ddr_dq(), .ddr_dm(),
        .refclk_p(1'b0), .refclk_n(1'b0), .rxp(1'b0), .rxn(1'b0), .txp(), .txn(),
        .i_crop_abort(1'b0), .i_sensor_config_error(1'b0),
        .o_isp_reset_n(), .o_isp_width(), .o_isp_height(), .o_isp_raw_data(),
        .o_isp_raw_valid(), .o_isp_raw_sof(), .o_isp_raw_eol(), .o_isp_rgb_ready(),
        .i_isp_raw_ready(1'b0), .i_isp_idle(1'b0), .i_isp_rgb(96'b0),
        .i_isp_rgb_valid(1'b0), .i_isp_rgb_sof(1'b0), .i_isp_rgb_eol(1'b0),
        .*
    );

    string scenario, stage = "startup";
    int pixel_cycles = 0;
    int geometry = 1;
    typedef enum {PRODUCT_GOOD, PRODUCT_RAW_SLVERR, PRODUCT_HARD_TIMEOUT} product_expectation_t;
    product_expectation_t product_expectation = PRODUCT_GOOD;
    bit stress_jpeg_responses = 0, deadline_jpeg_responses = 0, frame_active = 0;
    wire frame_bad = product_expectation != PRODUCT_GOOD;
    wire inject_raw_slverr = product_expectation == PRODUCT_RAW_SLVERR;
    wire expect_hard_timeout = product_expectation == PRODUCT_HARD_TIMEOUT;
    logic [31:0] expected_seq = 0, cfg_session = 0, cfg_epoch = 0;
    logic [31:0] ack_session = 0, ack_epoch = 0;
    logic [9:0] scene_r = 0, scene_g = 0, scene_b = 0;
    int boot_acks = 0, cfg_acks = 0, cold_sofs = 0, capture_count = 0;
    int source_count = 0, jpeg_source_count = 0, start_count = 0, result_count = 0;
    int writer_count = 0, ticket_count = 0, raw_retire_count = 0;
    int offer_count = 0, retire_count = 0, retire_response_count = 0;
    int jpeg_length = 0;
    logic [63:0] source_job = 0, ticket_job = 0;
    time start_time, result_time, writer_time, offer_time, retire_time, retire_response_time;

    task automatic check(input logic condition, input string diagnostic);
        if (condition !== 1'b1)
            $fatal(1, "BB_FAIL stage=%s time_ns=%0t %s", stage, $time, diagnostic);
    endtask

    function automatic logic [39:0] bayer_group(input int row);
        // GBRG, with the earliest sample in the least-significant 10 bits.
        if (row % 2 == 0)
            return {scene_b, scene_g, scene_b, scene_g};
        return {scene_g, scene_r, scene_g, scene_r};
    endfunction

    `include "memory_bfm.svh"
    `include "native_bfm.svh"

    logic [2:0] requested_sensor_profile = 0;
    int sensor_settle_cycles = 0;
    always @(negedge sys_clk) begin
        if (!i_clock_ready || $isunknown(o_sensor_profile)) begin
            i_sensor_config_done = 0;
            i_sensor_mode_running = 0;
            sensor_settle_cycles = 0;
        end else if (requested_sensor_profile != o_sensor_profile) begin
            requested_sensor_profile = o_sensor_profile;
            i_sensor_config_done = 0;
            i_sensor_mode_running = 0;
            sensor_settle_cycles = 0;
        end else if (sensor_settle_cycles == 4) begin
            i_sensor_profile = requested_sensor_profile;
            i_sensor_config_done = 1;
            i_sensor_mode_running = 1;
        end else begin
            sensor_settle_cycles++;
        end
    end

    always @(posedge i_pixel_clk) begin
        pixel_cycles++;
        if (pixel_cycles >= 200000) begin
            $display("BB_WATCHDOG resets=%b%b%b%b sensor=%d capture_en=%b app_arm=%b buffer_arm=%b fault=%b quiet=%b raw_empty=%b",
                     o_pixel_reset_n, o_user_reset_n, o_dfi_reset_n, o_mem_reset_n, o_sensor_profile,
                     o_capture_enabled, o_session_armed, o_buffer_armed, o_fault, o_record_quiet, o_raw_empty);
            $display("BB_WATCHDOG cfg_ack=%0d cold_sof=%0d capture=%0d raw_wbytes=%0d raw_rbeats=%0d start=%0d source=%0d jpeg_source=%0d result=%0d writer=%0d ticket=%0d raw_retire=%0d record_offer=%0d retire=%0d",
                     cfg_acks, cold_sofs, capture_count, raw_write_bytes, raw_read_beats, start_count,
                     source_count, jpeg_source_count, result_count, writer_count, ticket_count,
                     raw_retire_count, offer_count, retire_count);
            check(0, "200000 PIX-cycle watchdog");
        end
        if (o_pixel_reset_n) begin
            if (o_cfg_ack_fire) begin
                check(o_cfg_ack_ok, "negative CFG ACK for a legal transaction");
                ack_session = o_cfg_ack_session;
                ack_epoch = o_cfg_ack_epoch;
                if (ack_epoch == 0)
                    boot_acks++;
                else
                    cfg_acks++;
                $display("BB_CFG_ACK session=%08x epoch=%0d time_ns=%0t",
                         ack_session, ack_epoch, $time);
            end
            if (o_cold_config_sof)
                cold_sofs++;
            if (o_capture_frame_accept) begin
                check(frame_active, "capture admitted while APP was cold");
                capture_count++;
                check(capture_count == 1, "duplicate capture admission");
            end
            if (o_replay_source_fire) begin
                check(frame_active && source_count == 0, "unexpected or duplicate replay SOURCE");
                source_count++;
                source_job = o_replay_source_tag;
                $display("BB_SOURCE seq=%0d ok=%b job=%016x raw_read_beats=%0d time_ns=%0t",
                         expected_seq, o_replay_source_ok, source_job, raw_read_beats, $time);
                if (stress_jpeg_responses && !frame_bad && o_replay_source_ok !== 1'b1)
                    report_stress_failure();
                check(o_replay_source_ok == !frame_bad, "RAW replay SOURCE polarity");
            end
            if (o_jpeg_source_done || o_jpeg_source_failed) begin
                check(frame_active && jpeg_source_count == 0, "unexpected or duplicate JPEG SOURCE");
                jpeg_source_count++;
                check(o_jpeg_source_failed == frame_bad, "JPEG SOURCE polarity");
                $display("BB_JPEG_SOURCE seq=%0d done=%b failed=%b time_ns=%0t",
                         expected_seq, o_jpeg_source_done, o_jpeg_source_failed, $time);
            end
            if (o_jpeg_result_fire) begin
                check(frame_active && result_count == 0, "unexpected or duplicate JPEG result");
                result_count++;
                check(o_jpeg_result_ok == !frame_bad, "JPEG result polarity");
                jpeg_length = o_jpeg_result_length;
                if (!frame_bad)
                    check(jpeg_length >= 4, "invalid successful JPEG length");
                result_time = $time;
                $display("BB_JPEG_RESULT seq=%0d ok=%b length=%0d time_ns=%0t",
                         expected_seq, o_jpeg_result_ok, jpeg_length, $time);
            end
        end
    end

    // Sample DFI terminal events alongside the independent AXI debt ledger.
    task automatic observe_product;
        if (o_jpeg_start_fire) begin
            check(frame_active && start_count == 0, "unexpected or duplicate JPEG START");
            check(o_jpeg_start_sequence == expected_seq, "JPEG START capture sequence");
            check(o_jpeg_start_width == WIDTH && o_jpeg_start_height == HEIGHT, "JPEG START geometry");
            start_count++;
            start_time = $time;
            $display("BB_JPEG_START seq=%0d time_ns=%0t", expected_seq, $time);
        end
        if (o_writer_ack_fire) begin
            check(frame_active && writer_count == 0, "unexpected or duplicate writer ACK");
            check(o_writer_ack_sequence == expected_seq, "writer ACK capture sequence");
            check(o_writer_ack_ok == !frame_bad, "writer ACK polarity");
            check(jpeg_write_debt == 0, "writer ACK before all accepted JPEG AW/W/B drain");
            if (!frame_bad)
                check(last_jpeg_b > last_jpeg_wlast && jpeg_write_bytes >= jpeg_length && jpeg_length > 0,
                      "success writer ACK without delayed final B or all payload bytes");
            writer_count++;
            writer_time = $time;
            $display("BB_WRITER_ACK seq=%0d ok=%b wbytes=%0d last_b_ns=%0t time_ns=%0t",
                     expected_seq, o_writer_ack_ok, jpeg_write_bytes, last_jpeg_b, $time);
        end
        if (o_ticket_result) begin
            check(frame_active && ticket_count == 0, "unexpected or duplicate ticket result");
            check(o_ticket_error == frame_bad, "ticket error polarity");
            ticket_job = o_ticket_job;
            ticket_count++;
            $display("BB_TICKET seq=%0d error=%b job=%016x time_ns=%0t",
                     expected_seq, o_ticket_error, ticket_job, $time);
        end
        if (o_raw_slot_retired) begin
            check(frame_active && raw_retire_count == 0, "unexpected or duplicate RAW retirement");
            check(raw_write_debt == 0 && raw_read_debt == 0, "RAW retired with outstanding AXI debt");
            raw_retire_count++;
            $display("BB_RAW_RETIRE seq=%0d time_ns=%0t", expected_seq, $time);
        end
        if (o_record_offer) begin
            check(frame_active && !frame_bad, "successful record offered for cold or failed frame");
            check(jpeg_write_debt == 0 && last_jpeg_b > last_jpeg_wlast &&
                  jpeg_write_bytes >= jpeg_length && jpeg_length > 0,
                  "record offered before the final successful JPEG B");
            if (offer_count == 0) begin
                offer_count++;
                offer_time = $time;
                $display("BB_RECORD_OFFER seq=%0d time_ns=%0t", expected_seq, $time);
            end
        end
        if (o_record_retire_fire) begin
            check(frame_active && !frame_bad && retire_count == 0, "unexpected or duplicate JPEG retire");
            check(host_ack_seen, "JPEG slot retired before matching host ACK transfer");
            retire_count++;
            retire_time = $time;
            $display("BB_RECORD_RETIRE seq=%0d time_ns=%0t", expected_seq, $time);
        end
        if (o_ring_retire_response_valid) begin
            check(frame_active && !frame_bad && retire_response_count == 0 && retire_count == 1,
                  "unexpected or duplicate JPEG retire response");
            check(host_ack_seen && o_ring_retire_response_code == 0, "JPEG retirement failed");
            retire_response_count++;
            retire_response_time = $time;
            $display("BB_RING_RETIRE_RESPONSE seq=%0d code=%0d time_ns=%0t",
                     expected_seq, o_ring_retire_response_code, $time);
        end
    endtask

    task automatic send_event(input logic [1:0] kind, input logic [31:0] sequence_number);
        @(negedge i_pixel_clk);
        i_event_valid = 1;
        i_event_kind = kind;
        i_event_ok = 1;
        i_event_error = 0;
        i_event_sequence = sequence_number;
        i_event_identity_valid = 1;
        do @(posedge i_pixel_clk); while (o_event_ready !== 1'b1);
        @(negedge i_pixel_clk);
        i_event_valid = 0;
    endtask

    task automatic send_frame(input logic [31:0] sequence_number);
        $display("BB_FRAME_INPUT seq=%0d raw_rgb=%0d,%0d,%0d time_ns=%0t",
                 sequence_number, scene_r, scene_g, scene_b, $time);
        send_event(0, sequence_number);
        for (int row = 0; row < HEIGHT; row++) begin
            for (int group_index = 0; group_index < GROUPS_PER_ROW; group_index++) begin
                @(negedge i_pixel_clk);
                i_crop_valid = 1;
                i_crop_data = bayer_group(row);
                i_crop_sof = row == 0 && group_index == 0;
                i_crop_eol = group_index == GROUPS_PER_ROW - 1;
                i_crop_sequence = sequence_number;
                i_crop_identity_valid = 1;
                do @(posedge i_pixel_clk); while (o_crop_ready !== 1'b1);
            end
        end
        @(negedge i_pixel_clk);
        i_crop_valid = 0;
        send_event(1, sequence_number);
    endtask

    task automatic clear_product_observations;
        capture_count = 0;
        source_count = 0;
        jpeg_source_count = 0;
        start_count = 0;
        result_count = 0;
        writer_count = 0;
        ticket_count = 0;
        raw_retire_count = 0;
        offer_count = 0;
        retire_count = 0;
        retire_response_count = 0;
        jpeg_length = 0;
        source_job = 0;
        ticket_job = 0;
        start_time = 0;
        result_time = 0;
        writer_time = 0;
        offer_time = 0;
        retire_time = 0;
        retire_response_time = 0;
    endtask

    task automatic begin_frame(input logic [31:0] sequence_number,
                               input product_expectation_t expectation,
                               input logic [9:0] red, green, blue);
        @(negedge i_pixel_clk);
        check(o_raw_empty && o_record_quiet && all_axi_drained(), "previous transaction has debt");
        check(o_buffer_armed && o_session_armed && o_capture_enabled, "product submitted without ARM");
        expected_seq = sequence_number;
        product_expectation = expectation;
        frame_active = 1;
        scene_r = red;
        scene_g = green;
        scene_b = blue;
        clear_product_observations();
        clear_axi_frame();
        clear_host_frame();
    endtask

    task automatic wait_product_terminals;
        while (capture_count == 0 || source_count == 0 || jpeg_source_count == 0 ||
               start_count == 0 || result_count == 0 || writer_count == 0 ||
               ticket_count == 0 || raw_retire_count == 0 || !o_raw_empty)
            @(negedge i_pixel_clk);
        check(source_job == ticket_job, "full SOURCE and ticket job identities differ");
        check(raw_write_bytes == RAW_BYTES && raw_read_beats > 0, "no real RAW capture/replay");
        check(start_time <= result_time, "JPEG result before START");
        if (!frame_bad)
            check(result_time <= writer_time, "successful writer ACK before JPEG result");
    endtask

    task automatic check_ready_during_b(input logic [31:0] ready_mask);
        check(ready_mask == 0 && offer_count == 0 && writer_count == 0 && host_packet_count == 0,
              "READY, writer or record advanced during the final B hold");
        $display("BB_LAST_B_BLOCK seq=%0d result_available=%b result_ns=%0t wbytes=%0d ready_mask=%08x pending_b=%0d time_ns=%0t",
                 expected_seq, result_count != 0, result_time, jpeg_write_bytes,
                 ready_mask, jpeg_write_debt, $time);
    endtask

    task automatic complete_product(input string basename);
        logic [31:0] ready_mask;
        time ready_probe_time;
        wait (jpeg_eoi_written);
        bar_read(APP_BASE + 'h020, ready_mask);
        check(jpeg_write_debt > 0, "test missed the final B hold after WLAST with EOI");
        check_ready_during_b(ready_mask);
        ready_probe_time = $time;
        while (result_count == 0 && jpeg_write_debt > 0)
            @(negedge i_mem_clk);
        if (result_count != 0 && jpeg_write_debt > 0) begin
            bar_read(APP_BASE + 'h020, ready_mask);
            if (jpeg_write_debt > 0)
                check_ready_during_b(ready_mask);
        end
        wait_product_terminals();
        wait_host_safe_and_ack(basename);
        while (retire_response_count == 0 || !o_record_quiet || !all_axi_drained())
            @(negedge i_mem_clk);
        repeat (48) @(negedge i_host_clk);
        check(offer_count == 1 && retire_count == 1 && retire_response_count == 1 &&
              last_jpeg_b > ready_probe_time && offer_time >= last_jpeg_b && retire_time >= host_ack_time &&
              retire_response_time >= retire_time, "positive product terminal/debt mismatch");
        if (deadline_jpeg_responses) begin
            check(exact_b_count == jpeg_aw_count && exact_b_count > 0, "not all JPEG B at the service deadline");
            $display("BB_DEADLINE_PASS seq=%0d jpeg_b=%0d latency_cycles=%0d",
                     expected_seq, exact_b_count, B_SERVICE_LIMIT);
        end
        $display("BB_PRODUCT_PASS file=%s seq=%0d session=%08x epoch=%0d wlast_ns=%0t last_b_ns=%0t offer_ns=%0t safe_ns=%0t ack_ns=%0t retire_ns=%0t response_ns=%0t raw_bytes=%0d raw_read_beats=%0d jpeg_aw=%0d tlp_packets=%0d fence=%0d axistalls=%0d tlpstalls=%0d",
                 basename, expected_seq, cfg_session, cfg_epoch, last_jpeg_wlast, last_jpeg_b,
                 offer_time, safe_time, host_ack_time, retire_time, retire_response_time, raw_write_bytes,
                 raw_read_beats, jpeg_aw_count, host_packet_count, fence_count, axi_stalls, tlp_stalls);
    endtask

    task automatic boot_and_configure(input logic [31:0] cold_sequence);
        logic [31:0] readback;
        stage = "real BOOT";
        wait (o_pixel_reset_n && o_dfi_reset_n && o_mem_reset_n && o_user_reset_n);
        $display("BB_RESETS_RELEASED time_ns=%0t", $time);
        poll_register(APP_BASE + 'h01c, 'hc0, 'h40);
        poll_register(APP_BASE + 'h244, 'h1f, 'h10);
        expect_register(APP_BASE + 'h018, 0);
        expect_register(APP_BASE + 'h258, 0);
        expect_register(APP_BASE + 'h254, 75);
        expect_register(APP_BASE + 'hf9c, 0);
        bar_read(APP_BASE + 'h21c, cfg_session);
        check(cfg_session != 0 && boot_acks == 1 && ack_session == cfg_session,
              "BOOT session does not match the real epoch-zero ACK");
        $display("BB_BOOT session=%08x geometry=%0d time_ns=%0t", cfg_session, geometry, $time);

        stage = "cold geometry and sensor profile";
        expect_register(APP_BASE + 'hfc4, 'h107);
        bar_write(APP_BASE + 'hf8c, 0);
        bar_write(APP_BASE + 'hfa8, 0);
        bar_write(APP_BASE + 'hfb4, 0);
        bar_write(APP_BASE + 'hfbc, geometry);
        expect_register(APP_BASE + 'hfbc, geometry);
        bar_write(APP_BASE + 'hf90, 1);
        poll_register(APP_BASE + 'hf94, 3, 2);
        expect_register(APP_BASE + 'hf98, 0);
        expect_register(APP_BASE + 'hfc0, geometry);
        expect_register(APP_BASE + 'hfac, 0);
        expect_register(APP_BASE + 'hfb8, 0);
        wait (o_uhd_pixel && i_sensor_profile == (geometry + 4) && i_sensor_config_done);
        expect_register(APP_BASE + 'h20c, 3);
        expect_register(APP_BASE + 'h210, 1);
        expect_register(APP_BASE + 'h214, 3840);
        expect_register(APP_BASE + 'h218, 2160);
        expect_register(APP_BASE + 'h208, 'h7f);
        expect_register(APP_BASE + 'h39c, 4);
        expect_register(APP_BASE + 'h3a0, 1);
        expect_register(APP_BASE + 'h3a4, 'h0d);
        expect_register(APP_BASE + 'h21c, cfg_session);
        $display("BB_GEOMETRY code=%0d profile=%0d time_ns=%0t", geometry, i_sensor_profile, $time);

        stage = "schema2 WB PREPARE and whole ACK";
        // CFG1 host first advertises the FRAME_APPLIED capability.
        bar_write(APP_BASE + 'h274, 1);
        expect_register(APP_BASE + 'h274, 1);
        bar_write(APP_BASE + 'h220, 1);
        bar_write(APP_BASE + 'h224, cfg_session);
        bar_write(APP_BASE + 'h228, 0);
        bar_write(APP_BASE + 'h22c, 73);
        bar_write(APP_BASE + 'h230, 0);
        bar_write(APP_BASE + 'h234, 1);
        bar_write(APP_BASE + 'h238, 0);
        bar_write(APP_BASE + 'h23c, 0);
        for (int index = 0; index < 32; index++) begin
            case (index)
                0: readback = 2;
                1: readback = WB_WORD;
                12: readback = 'h10;
                default: readback = 0;
            endcase
            bar_write(APP_BASE + 'he00 + 4 * index, readback);
        end
        bar_write(APP_BASE + 'h240, 4);
        poll_register(APP_BASE + 'h244, 'h1f, 'h13);
        expect_register(APP_BASE + 'h248, 1);
        expect_register(APP_BASE + 'h24c, 0);
        expect_register(APP_BASE + 'h258, 0);
        bar_write(APP_BASE + 'h240, 2);
        wait (cfg_acks == 1);
        check(ack_session == cfg_session && ack_epoch == 1, "CFG whole ACK identity");
        cfg_epoch = ack_epoch;
        expect_register(APP_BASE + 'h258, 0);

        stage = "cold real FS/SOF/FE and APPLIED";
        scene_r = 172;
        scene_g = 440;
        scene_b = 858;
        send_frame(cold_sequence);
        poll_register(APP_BASE + 'h244, 'h1f, 'h14);
        expect_register(APP_BASE + 'h248, 1);
        expect_register(APP_BASE + 'h24c, 0);
        expect_register(APP_BASE + 'h254, 73);
        expect_register(APP_BASE + 'h258, cfg_epoch);
        expect_register(APP_BASE + 'h25c, cold_sequence);
        expect_register(APP_BASE + 'h260, 0);
        expect_register(APP_BASE + 'h278, cfg_session);
        expect_register(APP_BASE + 'he80, 2);
        expect_register(APP_BASE + 'he84, WB_WORD);
        expect_register(APP_BASE + 'heb0, 'h10);
        check(cold_sofs == 1 && capture_count == 0 && start_count == 0 && host_packet_count == 0,
              "cold observation must apply CFG without a product");
        $display("BB_CFG_APPLIED session=%08x epoch=%0d first_sequence=%0d wb=%08x time_ns=%0t",
                 cfg_session, cfg_epoch, cold_sequence, WB_WORD, $time);

        stage = "record v4 and native ARM";
        bar_write(APP_BASE + 'h290, 4);
        bar_write(APP_BASE + 'h294, 1);
        bar_write(APP_BASE + 'h298, cfg_session);
        bar_write(APP_BASE + 'h29c, 1);
        poll_register(APP_BASE + 'h2a0, 7, 2);
        expect_register(APP_BASE + 'h2a4, 1);
        expect_register(APP_BASE + 'h2a8, cfg_session);
        expect_register(APP_BASE + 'h2ac, 0);
        expect_register(APP_BASE + 'h2b0, 4);
        expect_register(APP_BASE + 'h2b4, HEADER_BYTES);
        poll_register('h00c, 'h3e, 'h10);
        bar_write('h008, 8);
        poll_register('h00c, 'h3e, 0);
        arm_buffer(1);
        bar_write(APP_BASE + 'h018, 1);
        wait (o_session_armed && o_capture_enabled);
        $display("BB_APP_ARM time_ns=%0t", $time);
    endtask

    task automatic set_boundary_ready(input bit ready);
        pcie_mperst = ready;
        i_clock_ready = ready;
        i_host_link_up = ready;
        i_host_bme = ready;
        i_mem_ready = ready;
    endtask

    task automatic drain_hard_timeout;
        stage = "hard timeout with late matching B";
        begin_frame(11, PRODUCT_HARD_TIMEOUT, 172, 440, 858);
        send_frame(11);
        while (hard_fault_time == 0 || late_b_count == 0 || source_count == 0 || !all_axi_drained())
            @(negedge i_mem_clk);
        repeat (64) @(negedge i_host_clk);
        check(o_fault && !o_capture_enabled && late_b_count == 1 && late_b_time >= hard_fault_time,
              "hard timeout did not latch and drain the late matching B");
        check(capture_count == 1 && start_count == 1 && source_count == 1 &&
              raw_write_bytes == RAW_BYTES && raw_read_beats > 0 && raw_slverr_count == 0,
              "hard timeout did not come from an otherwise legal product");
        check(all_axi_drained() && !i_mem_bvalid && !i_mem_rvalid &&
              raw_aw_count == raw_b_count && jpeg_aw_count == jpeg_b_count &&
              raw_ar_count == raw_rlast_count && jpeg_ar_count == jpeg_rlast_count,
              "committed AXI debt remained at the hard timeout boundary");
        check(offer_count == 0 && host_packet_count == 0 && host_bytes == 0 &&
              fence_count == 0 && retire_count == 0 && retire_response_count == 0,
              "hard timeout published a successful record or retirement");
        $display("BB_HARD_TIMEOUT_DRAINED seq=11 fault_ns=%0t late_b_ns=%0t raw_aw=%0d raw_ar=%0d raw_r=%0d jpeg_aw=%0d jpeg_b=%0d axi_debt=0 host_bytes=0 time_ns=%0t",
                 hard_fault_time, late_b_time, raw_aw_count, raw_ar_count, raw_read_beats,
                 jpeg_aw_count, jpeg_b_count, $time);
    endtask

    task automatic verify_perst_link_isolation;
        stage = "ordinary PERST/link cycle after hard timeout";
        @(negedge sys_clk);
        check(all_axi_drained() && !i_mem_bvalid && !i_mem_rvalid,
              "link pulse attempted before AXI obligations drained");
        pcie_mperst = 0;
        i_host_link_up = 0;
        i_host_bme = 0;
        repeat (16) @(negedge sys_clk);
        check(o_fault && o_mem_reset_n, "ordinary PERST/link reset unexpectedly cleared hard fault");
        $display("BB_LINK_PERST_LOW fault=%b user_reset_n=%b mem_reset_n=%b time_ns=%0t",
                 o_fault, o_user_reset_n, o_mem_reset_n, $time);
        pcie_mperst = 1;
        i_host_link_up = 1;
        i_host_bme = 1;
        repeat (16) @(negedge sys_clk);
        check(o_fault && !o_capture_enabled && all_axi_drained() && host_bytes == 0 &&
              offer_count == 0 && retire_count == 0, "ordinary link recovery escaped hard fault");
        $display("BB_LINK_PERST_BOUNDARY fault=%b axi_debt=0 host_bytes=0 time_ns=%0t", o_fault, $time);
    endtask

    task automatic run_capture_sequence;
        stage = "first real RAW to JPEG to host ACK";
        begin_frame(11, PRODUCT_GOOD, 172, 440, 858);
        send_frame(11);
        complete_product("first");

        if (scenario != "stopped") begin
            stage = "negative post-START RAW SLVERR";
            arm_buffer(2);
            begin_frame(12, PRODUCT_RAW_SLVERR, 321, 280, 580);
            send_frame(12);
            wait_product_terminals();
            while (!o_record_quiet || !all_axi_drained())
                @(negedge i_mem_clk);
            repeat (64) @(negedge i_host_clk);
            check(raw_slverr_count == 1 && raw_slverr_time > start_time, "no committed post-START SLVERR");
            check(offer_count == 0 && host_bytes == 0 && host_packet_count == 0 &&
                  fence_count == 0 && retire_count == 0 && retire_response_count == 0,
                  "failed frame produced a successful record or retirement");
            poll_register('h00c, 'h3e, 2);
            check(o_buffer_armed && o_session_armed && o_capture_enabled,
                  "unbound buffer or capture ownership lost after recoverable RAW failure");
            expect_register(APP_BASE + 'h21c, cfg_session);
            expect_register(APP_BASE + 'h258, cfg_epoch);
            $display("BB_FAILURE_TERMINAL_PASS seq=12 session=%08x start_ns=%0t slverr_ns=%0t raw_bytes=%0d raw_read_beats=%0d jpeg_aw=%0d",
                     cfg_session, start_time, raw_slverr_time, raw_write_bytes, raw_read_beats, jpeg_aw_count);

            stage = "same-session real recovery";
            begin_frame(13, PRODUCT_GOOD, 613, 328, 234);
            send_frame(13);
            complete_product("recovery");
        end
    endtask

    initial begin : scenario_driver
        $timeformat(-9, 3, "", 0);
        check($value$plusargs("CASE=%s", scenario), "CASE plusarg is required");
        check(scenario == "normal" || scenario == "stopped" || scenario == "deadline" ||
              scenario == "timeout" || scenario == "cold_recovery" || scenario == "stress", "unknown CASE");
        stress_jpeg_responses = scenario == "stress";
        deadline_jpeg_responses = scenario == "deadline";
        dfi_running = scenario != "stopped";
        geometry = scenario == "stopped" ? 2 : 1;
        $display("BB_BEGIN case=%s geometry=%0d", scenario, geometry);
        #111;
        set_boundary_ready(1);
        if (scenario == "stopped") begin
            stage = "DFI stopped at startup";
            #100000;
            $display("BB_DFI_STOPPED pixel_reset_n=%b user_reset_n=%b dfi_reset_n=%b time_ns=%0t",
                     o_pixel_reset_n, o_user_reset_n, o_dfi_reset_n, $time);
            // The memory cohort may hold PIX in reset until DFI resumes.
            check(o_user_reset_n && !o_dfi_reset_n, "USER/DFI reset ownership with DFI stopped");
            check(!o_session_armed && !o_buffer_armed && !o_capture_enabled,
                  "ownership escaped before DFI resumed");
            dfi_running = 1;
        end
        if (scenario == "cold_recovery")
            host_session++;
        boot_and_configure(scenario == "cold_recovery" ? 20 : 10);
        if (scenario == "timeout") begin
            drain_hard_timeout();
            verify_perst_link_isolation();
        end else if (scenario == "cold_recovery") begin
            stage = "first real product in a fresh cold elaboration";
            check(!o_fault, "hard fault present in fresh cold elaboration");
            begin_frame(21, PRODUCT_GOOD, 613, 328, 234);
            send_frame(21);
            complete_product("cold_recovery");
        end else begin
            run_capture_sequence();
        end
        $display("BB_SIM_PASS case=%s geometry=%0d pixel_cycles=%0d", scenario, geometry, pixel_cycles);
        $finish;
    end
endmodule
