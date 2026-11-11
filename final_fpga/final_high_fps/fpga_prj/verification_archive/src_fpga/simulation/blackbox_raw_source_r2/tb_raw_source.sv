`timescale 1ns/1ps
`default_nettype none

module tb_raw_source #(
    parameter integer MAX_WIDTH = 32,
    parameter integer MAX_HEIGHT = 8,
    parameter integer RAW_SAMPLE_BITS = 14,
    parameter integer EXTERNAL_ISP_ENABLE = 1,
    parameter integer ORIGINAL_SYNC_CLEAR_ENABLE = 1,
    parameter integer BASE_WIDTH = 16,
    parameter integer BASE_HEIGHT = 4
);
    localparam integer RAW_WIDTH = 4 * RAW_SAMPLE_BITS;
    logic clock_run = 1, i_pixel_clk = 0, i_pixel_rst_n = 1;
    logic i_context_fire = 0, i_context_private = 1;
    logic [383:0] i_context_frame;
    logic [63:0] i_context_job, i_context_pair, i_context_key, i_context_aux;
    logic i_context_member;
    wire o_context_available, o_payload_enable, o_pool_idle;
    logic i_owner_published = 0, i_owner_valid = 0;
    logic [383:0] i_owner_frame;
    logic [63:0] i_owner_lease, i_owner_job, i_owner_pair, i_owner_native_tag;
    logic [31:0] i_owner_writer_tag;
    logic i_owner_member;
    logic [1:0] i_bayer_phase = 2;
    logic [29:0] i_wb_gains = {10'd258, 10'd317, 10'd199};
    logic i_hdr_enable = 0;
    logic [3:0] i_tone_shift = 4;
    wire [RAW_WIDTH-1:0] o_isp_raw_data;
    wire o_isp_raw_valid, o_isp_raw_sof, o_isp_raw_eol;
    logic i_isp_raw_ready = 0;
    logic [95:0] i_isp_rgb;
    logic i_isp_rgb_valid = 0, i_isp_rgb_sof, i_isp_rgb_eol, i_isp_idle = 1;
    wire o_isp_rgb_ready, o_isp_reset_n;
    wire [1:0] o_isp_bayer_phase;
    wire [29:0] o_isp_wb_gains;
    wire o_isp_hdr_enable;
    wire [3:0] o_isp_tone_shift;
    logic [RAW_WIDTH-1:0] s_raw_data;
    logic s_raw_valid = 0, s_raw_sof, s_raw_eol;
    wire s_raw_ready;
    logic s_raw_source_valid = 0;
    wire s_raw_source_ready;
    logic [383:0] s_raw_source_frame;
    logic [63:0] s_raw_source_lease, s_raw_source_job, s_raw_source_pair, s_raw_source_tag;
    logic s_raw_source_member, s_raw_source_ok;
    logic [7:0] s_raw_source_error;
    logic i_raw_source_read_quiescent = 1, i_pixel_cancel = 0;
    logic i_pipeline_quiescent = 1, i_post_pool_idle = 1;
    logic i_post_pixel_fault = 0, i_processed_source_fire = 0;
    wire [575:0] m_context, m_status_context;
    wire m_context_valid, m_status_valid;
    logic m_context_ready = 0, m_status_ready = 0;
    wire [95:0] m_rgb;
    wire [3:0] m_keep;
    wire m_sof, m_eol, m_last, m_valid;
    logic m_ready = 0;
    wire [63:0] m_tag, m_status_tag;
    wire [31:0] m_index, m_status_groups;
    wire m_status_ok;
    wire [7:0] m_status_error;
    wire o_original_read_quiescent, o_locked_owner_valid;
    wire [383:0] o_locked_frame;
    wire [63:0] o_locked_lease, o_locked_job, o_locked_pair, o_locked_native_tag;
    wire [31:0] o_locked_writer_tag;
    wire o_locked_member;
    wire o_pixel_fault, o_isp_idle, o_isp_cleanup;
    wire [31:0] o_stale_raw_source_count;

    private_raw_isp_borrow4 #(
        .MAX_WIDTH(MAX_WIDTH), .MAX_HEIGHT(MAX_HEIGHT),
        .RAW_SAMPLE_BITS(RAW_SAMPLE_BITS), .EXTERNAL_ISP_ENABLE(EXTERNAL_ISP_ENABLE),
        .ORIGINAL_SYNC_CLEAR_ENABLE(ORIGINAL_SYNC_CLEAR_ENABLE),
        .BASE_WIDTH(BASE_WIDTH), .BASE_HEIGHT(BASE_HEIGHT)
    ) dut (.*);

    always begin
        #4;
        if (clock_run) i_pixel_clk = ~i_pixel_clk;
    end

    int frame_id = 0, groups_per_row, total_groups;
    bit active = 0, cancel_expected, processed_seen;
    logic [383:0] frame;
    logic [575:0] expected_context;
    logic [63:0] job, pair_id, native_tag, lease_id, context_key;
    logic [31:0] writer_tag;
    bit member;
    int raw_taken, isp_raw_taken, isp_rgb_taken, rgb_taken;
    int source_match, source_stale, context_taken, status_taken, cleanup_count;
    int context_stalls, mid_stalls, tail_stalls, status_stalls;
    int success_frames = 0, canceled_frames = 0, reset_discards = 0, stale_total = 0;
    bit hold_context, hold_rgb, hold_status, hold_isp_raw;
    logic [575:0] previous_context;
    logic [198:0] previous_rgb;
    logic [680:0] previous_status;
    logic [RAW_WIDTH+1:0] previous_isp_raw;

    task automatic check(input logic condition, input string why);
        if (condition !== 1'b1)
            $fatal(1, "RAW_SOURCE_GATE_FAIL t=%0t frame=%0d %s", $time, frame_id, why);
    endtask

    function automatic logic [RAW_WIDTH-1:0] raw_pattern(input int group_index);
        for (int lane = 0; lane < 4; lane++)
            raw_pattern[lane*RAW_SAMPLE_BITS +: RAW_SAMPLE_BITS] =
                RAW_SAMPLE_BITS'(1493 * frame_id + 2377 * group_index + 7339 * lane
                    + 67 * (group_index >> 2));
    endfunction

    // The external ISP model derives a repeatable RGB offer for each RAW take.
    function automatic logic [95:0] rgb_pattern(input int group_index);
        logic [RAW_WIDTH-1:0] samples;
        int unsigned sample_value;
        samples = raw_pattern(group_index);
        for (int lane = 0; lane < 4; lane++) begin
            sample_value = int'(samples[lane*RAW_SAMPLE_BITS +: RAW_SAMPLE_BITS]);
            rgb_pattern[lane*24 +: 24] = {
                8'(sample_value ^ (sample_value >> 3) ^ (43 * lane)),
                8'((sample_value >> 6) + (19 * group_index) + (11 * lane)),
                8'((sample_value >> 2) ^ (71 * frame_id) ^ (17 * group_index))
            };
        end
    endfunction

    function automatic bit row_tail(input int group_index);
        return (group_index % groups_per_row) == groups_per_row - 1;
    endfunction

    task automatic clear_monitor;
        cancel_expected = 0;
        processed_seen = 0;
        raw_taken = 0;
        isp_raw_taken = 0;
        isp_rgb_taken = 0;
        rgb_taken = 0;
        source_match = 0;
        source_stale = 0;
        context_taken = 0;
        status_taken = 0;
        cleanup_count = 0;
        context_stalls = 0;
        mid_stalls = 0;
        tail_stalls = 0;
        status_stalls = 0;
        hold_context = 0;
        hold_rgb = 0;
        hold_status = 0;
        hold_isp_raw = 0;
    endtask

    always @(posedge i_pixel_clk) begin
        // Compare every sampled control value, plus tuples only on valid offers.
        $display("TRACE edge %0t id=%0d in=%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b out=%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b%b stale=%0d",
            $time, frame_id, i_pixel_rst_n, i_context_fire, i_owner_published, i_owner_valid,
            s_raw_valid, s_raw_source_valid, i_raw_source_read_quiescent, i_pixel_cancel,
            i_isp_raw_ready, i_isp_rgb_valid, i_isp_idle, m_context_ready, m_ready, m_status_ready,
            i_processed_source_fire, i_pipeline_quiescent, i_post_pool_idle,
            o_context_available, o_payload_enable, o_pool_idle, o_locked_owner_valid,
            s_raw_ready, s_raw_source_ready, o_isp_raw_valid, o_isp_rgb_ready, o_isp_reset_n,
            m_context_valid, m_valid, m_status_valid, o_isp_cleanup, o_original_read_quiescent,
            o_isp_idle, o_pixel_fault, o_stale_raw_source_count);
        if (s_raw_valid)
            $display("TRACE input-raw %h %b%b", s_raw_data, s_raw_sof, s_raw_eol);
        if (s_raw_source_valid)
            $display("TRACE input-source %h %h %h %h %h %b%b %h", s_raw_source_frame,
                s_raw_source_lease, s_raw_source_job, s_raw_source_pair, s_raw_source_tag,
                s_raw_source_member, s_raw_source_ok, s_raw_source_error);
        if (i_isp_rgb_valid)
            $display("TRACE isp-rgb %h %b%b", i_isp_rgb, i_isp_rgb_sof, i_isp_rgb_eol);
        if (o_isp_raw_valid)
            $display("TRACE isp-raw %h %b%b", o_isp_raw_data, o_isp_raw_sof, o_isp_raw_eol);
        if (m_context_valid)
            $display("TRACE context %h", m_context);
        if (m_valid)
            $display("TRACE rgb %h %h %h %h %b%b%b", m_rgb, m_tag, m_index, m_keep, m_sof, m_eol, m_last);
        if (m_status_valid)
            $display("TRACE status %h %h %b %h %0d", m_status_context, m_status_tag,
                m_status_ok, m_status_error, m_status_groups);

        if (i_pixel_rst_n && active) begin
            if (i_context_fire)
                check(o_context_available && i_owner_published, "context command without availability");
            if (!i_owner_valid)
                check(!o_locked_owner_valid && !o_payload_enable &&
                    !s_raw_ready && !s_raw_source_ready,
                    "payload or RAW acceptance enabled before the matching owner is valid");
            if (o_payload_enable)
                check(o_locked_owner_valid, "payload qualified without locked owner");
            if (o_locked_owner_valid) begin
                check(i_owner_valid && i_owner_published, "unpublished owner borrowed");
                check({o_locked_frame, o_locked_lease, o_locked_job, o_locked_pair,
                    o_locked_native_tag, o_locked_writer_tag, o_locked_member}
                    === {frame, lease_id, job, pair_id, native_tag, writer_tag, member},
                    "locked owner identity changed");
            end

            if (hold_isp_raw)
                check(o_isp_raw_valid &&
                    {o_isp_raw_data, o_isp_raw_sof, o_isp_raw_eol} === previous_isp_raw,
                    "stalled ISP RAW offer changed");
            if (hold_context)
                check(m_context_valid && m_context === previous_context, "stalled context changed");
            if (hold_rgb)
                check(m_valid &&
                    {m_rgb, m_tag, m_index, m_keep, m_sof, m_eol, m_last} === previous_rgb,
                    "stalled RGB offer changed");
            if (hold_status)
                check(m_status_valid &&
                    {m_status_context, m_status_tag, m_status_ok, m_status_error, m_status_groups}
                    === previous_status, "stalled STATUS changed");

            if (s_raw_valid && s_raw_ready) begin
                check(o_locked_owner_valid && i_owner_valid, "RAW accepted without a live owner");
                check(raw_taken < total_groups, "extra RAW take");
                raw_taken++;
            end
            if (o_isp_raw_valid) begin
                check(isp_raw_taken < total_groups, "extra ISP RAW offer");
                check({o_isp_raw_data, o_isp_raw_sof, o_isp_raw_eol} ===
                    {raw_pattern(isp_raw_taken), (isp_raw_taken == 0), row_tail(isp_raw_taken)},
                    "ISP RAW data or framing differs from offered RAW");
                if (i_isp_raw_ready)
                    isp_raw_taken++;
            end
            if (i_isp_rgb_valid && o_isp_rgb_ready) begin
                check(isp_rgb_taken < isp_raw_taken, "BFM returned RGB ahead of ISP RAW take");
                isp_rgb_taken++;
            end
            if (m_valid) begin
                check(context_taken == 1, "RGB offered ahead of the context acceptance");
                check(rgb_taken < total_groups && rgb_taken < isp_rgb_taken,
                    "RGB offered without corresponding ISP RGB take");
                check({m_rgb, m_tag, m_index, m_keep, m_sof, m_eol, m_last} ===
                    {rgb_pattern(rgb_taken), native_tag, 32'(rgb_taken), 4'hf,
                    (rgb_taken == 0), row_tail(rgb_taken), (rgb_taken == total_groups - 1)},
                    "RGB data, identity or framing mismatch");
                if (m_ready)
                    rgb_taken++;
                else if (rgb_taken == total_groups - 1)
                    tail_stalls++;
                else if (rgb_taken == 2)
                    mid_stalls++;
            end
            if (m_context_valid) begin
                check(context_taken == 0 && m_context === expected_context,
                    "unexpected or duplicate context");
                if (m_context_ready)
                    context_taken++;
                else
                    context_stalls++;
            end
            if (s_raw_source_valid && s_raw_source_ready) begin
                check(o_locked_owner_valid && i_raw_source_read_quiescent,
                    "RAW terminal accepted outside the live quiet reader");
                if ({s_raw_source_frame, s_raw_source_lease, s_raw_source_job,
                    s_raw_source_pair, s_raw_source_tag, s_raw_source_member} ===
                    {frame, lease_id, job, pair_id, native_tag, member})
                    source_match++;
                else
                    source_stale++;
            end
            if (m_status_valid) begin
                check(status_taken == 0, "duplicate STATUS");
                check(context_taken == 1, "STATUS before context");
                check({m_status_context, m_status_tag, m_status_groups} ===
                    {expected_context, native_tag, 32'(rgb_taken)}, "STATUS identity or count mismatch");
                if (cancel_expected)
                    check(m_status_ok === 1'b0 && m_status_error === 8'd3,
                        "canceled STATUS did not report E_CANCEL");
                else
                    check(source_match == 1 && i_isp_idle && i_raw_source_read_quiescent &&
                        m_status_ok === 1'b1 && m_status_error === 8'h00 &&
                        rgb_taken == total_groups && raw_taken == total_groups,
                        "successful STATUS requires the complete legal raster");
                if (m_status_ready)
                    status_taken++;
                else
                    status_stalls++;
            end
            if (o_isp_cleanup) begin
                check(cancel_expected && isp_raw_taken > 0 && !o_isp_reset_n,
                    "ISP cleanup did not reset a canceled started frame");
                check(!o_isp_raw_valid && !i_isp_rgb_valid && !m_valid,
                    "ISP cleanup preceded drain of a presented offer");
                cleanup_count++;
            end
            if (i_processed_source_fire) begin
                check(status_taken == 1 && !processed_seen, "early or duplicate processed retirement");
                processed_seen = 1;
            end
            if (context_taken == 1 && !processed_seen)
                check(!o_pool_idle, "pool released before processed source retired");

            hold_isp_raw = o_isp_raw_valid && !i_isp_raw_ready;
            previous_isp_raw = {o_isp_raw_data, o_isp_raw_sof, o_isp_raw_eol};
            hold_context = m_context_valid && !m_context_ready;
            previous_context = m_context;
            hold_rgb = m_valid && !m_ready;
            previous_rgb = {m_rgb, m_tag, m_index, m_keep, m_sof, m_eol, m_last};
            hold_status = m_status_valid && !m_status_ready;
            previous_status = {m_status_context, m_status_tag, m_status_ok, m_status_error, m_status_groups};
        end else if (i_pixel_rst_n) begin
            check(!m_context_valid && !m_valid && !m_status_valid && !o_isp_raw_valid &&
                !s_raw_ready && !s_raw_source_ready,
                "work appeared without a public context");
        end
    end

    task automatic tick;
        @(negedge i_pixel_clk);
        #1;
    endtask

    task automatic check_reset_gate(input string boundary);
        $display("TRACE reset %0t %s clk=%b reset=%b isp=%b context=%b payload=%b raw=%b source=%b",
            $time, boundary, i_pixel_clk, i_pixel_rst_n, o_isp_reset_n, o_context_available,
            o_payload_enable, s_raw_ready, s_raw_source_ready);
        check(o_context_available === 1'b0 && o_payload_enable === 1'b0 &&
            o_locked_owner_valid === 1'b0 && !m_context_valid && !m_valid &&
            !m_status_valid && !o_isp_raw_valid && !s_raw_ready && !s_raw_source_ready,
            {"startup exposure at ", boundary});
    endtask

    task automatic startup(input bit initial_falling_edge);
        if (initial_falling_edge) begin
            @(negedge i_pixel_clk);
            #1;
            check_reset_gate("F0");
            check(!o_isp_reset_n, "release before first rising edge");
        end
        for (int edge_number = 1; edge_number <= 3; edge_number++) begin
            @(posedge i_pixel_clk);
            check_reset_gate($sformatf("R%0d-pre", edge_number));
            check(!o_isp_reset_n, "ISP release before the third falling edge");
            #1;
            check_reset_gate($sformatf("R%0d-post", edge_number));
            check(!o_isp_reset_n, "ISP release on an early rising edge");
            @(negedge i_pixel_clk);
            check_reset_gate($sformatf("F%0d-pre", edge_number));
            check(!o_isp_reset_n, "ISP reset rose before its release edge");
            #1;
            check_reset_gate($sformatf("F%0d-post", edge_number));
            check(o_isp_reset_n === (edge_number == 3), "ISP reset released on wrong falling edge");
        end
        @(posedge i_pixel_clk);
        check_reset_gate("R4-pre");
        check(o_isp_reset_n, "ISP reset low at first active rising sample");
        #1;
        $display("TRACE reset %0t R4-post context=%b isp=%b", $time, o_context_available, o_isp_reset_n);
        check(o_isp_reset_n && !o_payload_enable && !s_raw_ready && !s_raw_source_ready,
            "work enabled on R4 without a published owner");
        tick();
    endtask

    task automatic release_inputs;
        active = 0;
        i_context_fire = 0;
        i_owner_published = 0;
        i_owner_valid = 0;
        i_owner_frame = ~frame;
        i_owner_job = ~job;
        i_owner_pair = ~pair_id;
        i_owner_native_tag = ~native_tag;
        i_owner_lease = ~lease_id;
        i_owner_writer_tag = ~writer_tag;
        i_owner_member = ~member;
        s_raw_valid = 0;
        s_raw_source_valid = 0;
        i_isp_raw_ready = 0;
        i_isp_rgb_valid = 0;
        i_isp_idle = 1;
        i_raw_source_read_quiescent = 1;
        i_pixel_cancel = 0;
        i_pipeline_quiescent = 1;
        i_post_pool_idle = 1;
        i_processed_source_fire = 0;
        m_context_ready = 0;
        m_ready = 0;
        m_status_ready = 0;
    endtask

    task automatic start_frame(input int id, input bit larger_geometry);
        int width, height;
        for (int attempt = 0; attempt < 40 && !o_context_available; attempt++)
            tick();
        check(o_context_available, "timeout waiting for legal context");
        clear_monitor();
        frame_id = id;
        width = larger_geometry ? MAX_WIDTH : BASE_WIDTH;
        height = larger_geometry ? MAX_HEIGHT : BASE_HEIGHT;
        groups_per_row = width / 4;
        total_groups = groups_per_row * height;
        frame = 384'h91022345_5192abcd_32f50478_af6745d0_edcba918_a7654321_fefe02fd_7182a41d_01893caa_215def34_53a5f2a6_e1c25b08
            ^ 384'(id * 97);
        frame[220:205] = 16'(width);
        frame[236:221] = 16'(height);
        frame[76:45] = 32'h35b4_2410 + 32'(id);
        frame[4] = id[0];
        member = id[1];
        job = 64'h7766_5544_3322_1100 + 64'(id);
        pair_id = 64'h7b64_8a38_0001_7190 + 64'(id);
        native_tag = 64'hcac2_81f4_183a_5530 + 64'(id);
        lease_id = 64'h8793_9386_38bc_13b0 + 64'(id);
        writer_tag = 32'hfa5a_3b00 + 32'(id);
        context_key = {frame[76:45], 31'd0, frame[4]};
        expected_context = {job, context_key, native_tag, frame};
        i_context_frame = frame;
        i_context_job = job;
        i_context_pair = pair_id;
        i_context_key = context_key;
        i_context_aux = job;
        i_context_member = member;
        i_owner_frame = frame;
        i_owner_job = job;
        i_owner_pair = pair_id;
        i_owner_native_tag = ~native_tag;
        i_owner_lease = ~lease_id;
        i_owner_writer_tag = ~writer_tag;
        i_owner_member = member;
        i_owner_published = 1;
        active = 1;
        i_context_fire = 1;
        $display("TRACE start %0t id=%0d geom=%0dx%0d context=%h", $time, id, width, height, expected_context);
        tick();
        i_context_fire = 0;
        repeat (2) begin
            check(!o_payload_enable && !o_locked_owner_valid, "early payload during delayed owner valid");
            tick();
        end
        i_owner_native_tag = native_tag;
        i_owner_lease = lease_id;
        i_owner_writer_tag = writer_tag;
        i_owner_valid = 1;
        tick();
        for (int attempt = 0; attempt < 40 && !o_payload_enable; attempt++)
            tick();
        check(o_payload_enable && o_locked_owner_valid, "timeout waiting for qualified owner");
        i_raw_source_read_quiescent = 0;
        i_isp_idle = 0;
    endtask

    task automatic offer_raw;
        s_raw_valid = raw_taken < total_groups;
        s_raw_data = raw_pattern(raw_taken);
        s_raw_sof = raw_taken == 0;
        s_raw_eol = row_tail(raw_taken);
    endtask

    task automatic offer_rgb(input int group_limit);
        i_isp_rgb_valid = isp_rgb_taken < isp_raw_taken && isp_rgb_taken < group_limit;
        i_isp_rgb = rgb_pattern(isp_rgb_taken);
        i_isp_rgb_sof = isp_rgb_taken == 0;
        i_isp_rgb_eol = row_tail(isp_rgb_taken);
    endtask

    task automatic pump_raster(input int rgb_limit);
        for (int attempt = 0; attempt < 280; attempt++) begin
            offer_raw();
            offer_rgb(rgb_limit);
            i_isp_idle = isp_raw_taken == total_groups && isp_rgb_taken == total_groups;
            i_isp_raw_ready = (attempt % 7) >= 2;
            m_context_ready = context_stalls >= 3;
            m_ready = !((rgb_taken == 2 && mid_stalls < 2) ||
                (rgb_taken == total_groups - 1 && tail_stalls < 4));
            if (raw_taken == total_groups && isp_raw_taken == total_groups &&
                isp_rgb_taken == rgb_limit && rgb_taken == rgb_limit)
                return;
            tick();
        end
        check(0, $sformatf("raster timeout raw=%0d isp-raw=%0d isp-rgb=%0d rgb=%0d",
            raw_taken, isp_raw_taken, isp_rgb_taken, rgb_taken));
    endtask

    task automatic send_source(input int stale_field);
        logic [31:0] stale_before;
        int takes_before;
        if (!i_raw_source_read_quiescent) begin
            i_raw_source_read_quiescent = 1;
            tick();
        end
        stale_before = o_stale_raw_source_count;
        takes_before = source_stale + source_match;
        s_raw_source_frame = frame ^ (stale_field == 1 ? 384'h1 : 384'h0);
        s_raw_source_lease = lease_id ^ (stale_field == 2 ? 64'h1 : 64'h0);
        s_raw_source_job = job ^ (stale_field == 3 ? 64'h1 : 64'h0);
        s_raw_source_pair = pair_id ^ (stale_field == 4 ? 64'h1 : 64'h0);
        s_raw_source_tag = native_tag ^ (stale_field == 5 ? 64'h1 : 64'h0);
        s_raw_source_member = member ^ (stale_field == 6);
        s_raw_source_ok = 1;
        s_raw_source_error = 0;
        s_raw_source_valid = 1;
        for (int attempt = 0; attempt < 40 && source_stale + source_match == takes_before; attempt++)
            tick();
        check(source_stale + source_match == takes_before + 1, "timeout waiting for RAW SOURCE take");
        s_raw_source_valid = 0;
        if (stale_field != 0) begin
            check(o_stale_raw_source_count === stale_before + 32'd1,
                $sformatf("stale RAW SOURCE field %0d was not classified", stale_field));
            stale_total++;
        end
    endtask

    task automatic retire_frame;
        for (int attempt = 0; attempt < 60 && status_stalls < 3; attempt++)
            tick();
        check(status_stalls >= 3, "timeout waiting for held STATUS");
        m_status_ready = 1;
        tick();
        m_status_ready = 0;
        check(status_taken == 1, "STATUS failed to transfer");
        repeat (3) begin
            check(!o_pool_idle, "original STATUS released the pool before processed SOURCE");
            tick();
        end
        if (frame_id == 1) i_pipeline_quiescent = 0;
        if (frame_id == 2) i_post_pool_idle = 0;
        i_processed_source_fire = 1;
        tick();
        i_processed_source_fire = 0;
        if (!i_pipeline_quiescent || !i_post_pool_idle) begin
            repeat (3) begin
                check(!o_pool_idle, "processed SOURCE released ownership before external post drain");
                tick();
            end
            i_pipeline_quiescent = 1;
            i_post_pool_idle = 1;
        end
        for (int attempt = 0; attempt < 60 && !o_pool_idle; attempt++)
            tick();
        check(o_pool_idle && processed_seen && source_match == 1, "pool failed to retire after drain");
        check(cleanup_count == (cancel_expected ? 1 : 0), "wrong ISP cleanup pulse count");
        $display("TRACE retire %0t id=%0d raw=%0d isp-raw=%0d isp-rgb=%0d rgb=%0d stale=%0d cleanup=%0d",
            $time, frame_id, raw_taken, isp_raw_taken, isp_rgb_taken, rgb_taken, source_stale, cleanup_count);
        release_inputs();
        tick();
        check(!o_locked_owner_valid && !o_payload_enable, "released owner remained qualified");
    endtask

    task automatic success(input int id, input bit larger_geometry,
        input bit source_before_rgb_tail, input bit stale_first);
        start_frame(id, larger_geometry);
        pump_raster(source_before_rgb_tail ? total_groups - 1 : total_groups);
        if (stale_first) begin
            for (int field_index = 1; field_index <= 6; field_index++)
                send_source(field_index);
        end
        repeat (2) begin
            check(!m_status_valid, "RGB and stale SOURCE cannot establish success");
            tick();
        end
        send_source(0);
        if (source_before_rgb_tail)
            pump_raster(total_groups);
        check(context_stalls >= 3 && mid_stalls >= 2 && tail_stalls >= 4,
            "directed finite stalls did not reach the public offers");
        check(raw_taken == total_groups && isp_raw_taken == total_groups &&
            isp_rgb_taken == total_groups && rgb_taken == total_groups,
            "RAW, ISP and RGB transfers did not balance");
        retire_frame();
        success_frames++;
    endtask

    task automatic prime_stalls(input int id);
        start_frame(id, 0);
        m_ready = 0;
        for (int attempt = 0; attempt < 60; attempt++) begin
            offer_raw();
            offer_rgb(1);
            i_isp_raw_ready = isp_raw_taken == 0;
            m_context_ready = context_stalls >= 3;
            if (hold_isp_raw && hold_rgb) begin
                check(isp_raw_taken == 1 && isp_rgb_taken == 1 && rgb_taken == 0,
                    "stall fixture needs one ISP SOF and no accepted output RGB");
                return;
            end
            tick();
        end
        check(0, "could not establish concurrent stalled ISP RAW and RGB offers");
    endtask

    task automatic cancel_and_drain(input int id);
        prime_stalls(id);
        cancel_expected = 1;
        i_pixel_cancel = 1;
        repeat (3) begin
            offer_raw();
            tick();
            i_pixel_cancel = 0;
        end
        check(hold_rgb && hold_isp_raw, "cancel withdrew a still-stalled offer");
        i_isp_raw_ready = 1;
        m_ready = 1;
        for (int attempt = 0; attempt < 80; attempt++) begin
            offer_raw();
            offer_rgb(isp_raw_taken);
            if (raw_taken == total_groups && isp_rgb_taken == isp_raw_taken && !hold_rgb)
                break;
            tick();
        end
        check(raw_taken == total_groups && isp_raw_taken >= 2 &&
            isp_rgb_taken == isp_raw_taken && rgb_taken >= 1 && !hold_rgb && !hold_isp_raw,
            "cancel did not drain the promised RAW and RGB");
        i_isp_idle = 1;
        send_source(0);
        retire_frame();
        canceled_frames++;
    endtask

    task automatic discard_while_stopped(input int id, input bit high_phase);
        prime_stalls(id);
        if (high_phase)
            @(posedge i_pixel_clk);
        else
            @(negedge i_pixel_clk);
        #1;
        clock_run = 0;
        #2;
        check(i_pixel_clk === high_phase && hold_rgb && hold_isp_raw,
            "reset fixture did not stop at the selected phase with live offers");
        i_pixel_rst_n = 0;
        #1;
        check_reset_gate("async-assert-stopped");
        check(!o_isp_reset_n, "ISP reset did not assert asynchronously while stopped");
        release_inputs();
        clear_monitor();
        reset_discards++;
        #13;
        i_pixel_rst_n = 1;
        #1;
        check_reset_gate("release-stopped");
        check(!o_isp_reset_n, "release escaped the stopped clock");
        #21;
        check_reset_gate("still-stopped");
        check(i_pixel_clk === high_phase && !o_isp_reset_n, "clock or reset changed while stopped");
        clock_run = 1;
        startup(high_phase);
    endtask

    initial begin
        $timeformat(-9, 0, "ns", 0);
        #1;
        i_pixel_rst_n = 0;
        #1;
        check_reset_gate("cold-assert");
        check(!o_isp_reset_n, "ISP reset missing on cold assertion");
        repeat (3) tick();
        i_pixel_rst_n = 1;
        startup(0);
        success(1, 0, 0, 1);
        success(2, 1, 1, 0);
        cancel_and_drain(3);
        success(4, 0, 0, 0);
        discard_while_stopped(5, 1);
        success(6, 0, 0, 0);
        discard_while_stopped(7, 0);
        success(8, 1, 1, 0);
        check(success_frames == 5 && canceled_frames == 1 && reset_discards == 2 && stale_total == 6,
            "directed scenarios did not all reach their expected end");
        $display("RAW_SOURCE_GATE_PASS raw_bits=%0d success=%0d canceled=%0d reset_discards=%0d stale=%0d",
            RAW_SAMPLE_BITS, success_frames, canceled_frames, reset_discards, stale_total);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "RAW_SOURCE_GATE_FAIL simulation watchdog");
    end
endmodule

`default_nettype wire
