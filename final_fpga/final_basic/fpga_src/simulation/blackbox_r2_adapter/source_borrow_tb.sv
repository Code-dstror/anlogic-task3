`timescale 1ns/1ps

// Real owner + real native adapter. Only the external ISP is a transport fixture.
module source_borrow_tb;
  localparam int LINE_GROUPS = 1920 / 4;
  localparam int FRAME_GROUPS = LINE_GROUPS * 1080;
  localparam int WAIT_CYCLES = 144;
  logic i_pixel_clk = 0, i_pixel_rst_n = 1;
  always #4 i_pixel_clk = ~i_pixel_clk;

  logic i_context_fire = 0, i_context_private = 1;
  logic [383:0] i_context_frame = 0;
  logic [63:0] i_context_job = 0, i_context_pair = 0, i_context_key = 0, i_context_aux = 0;
  logic i_context_member = 0;
  wire o_context_available, o_payload_enable, o_pool_idle;
  logic i_owner_published = 0, i_owner_valid = 0;
  logic [383:0] i_owner_frame = 0;
  logic [63:0] i_owner_lease = 0, i_owner_job = 0, i_owner_pair = 0, i_owner_native_tag = 0;
  logic [31:0] i_owner_writer_tag = 0;
  logic i_owner_member = 0;
  logic [1:0] i_bayer_phase = 2;
  logic [29:0] i_wb_gains = 30'h10040100;
  logic i_hdr_enable = 0;
  logic [3:0] i_tone_shift = 0;
  wire [55:0] o_isp_raw_data;
  wire o_isp_raw_valid, o_isp_raw_sof, o_isp_raw_eol;
  logic allow_raw = 1;
  logic [95:0] i_isp_rgb = 0;
  logic i_isp_rgb_valid = 0, i_isp_rgb_sof = 0, i_isp_rgb_eol = 0;
  wire o_isp_rgb_ready, o_isp_reset_n;
  wire i_isp_raw_ready = o_isp_reset_n && allow_raw && (!i_isp_rgb_valid || o_isp_rgb_ready);
  wire i_isp_idle = !i_isp_rgb_valid;
  wire [1:0] o_isp_bayer_phase;
  wire [29:0] o_isp_wb_gains;
  wire o_isp_hdr_enable;
  wire [3:0] o_isp_tone_shift;
  logic [55:0] s_raw_data = 0;
  logic s_raw_valid = 0, s_raw_sof = 0, s_raw_eol = 0;
  wire s_raw_ready;
  logic s_raw_source_valid = 0;
  wire s_raw_source_ready;
  logic [383:0] s_raw_source_frame = 0;
  logic [63:0] s_raw_source_lease = 0, s_raw_source_job = 0, s_raw_source_pair = 0, s_raw_source_tag = 0;
  logic s_raw_source_member = 0, s_raw_source_ok = 0;
  logic [7:0] s_raw_source_error = 0;
  logic i_raw_source_read_quiescent = 1, i_pixel_cancel = 0;
  logic i_pipeline_quiescent = 1, i_post_pool_idle = 1, i_post_pixel_fault = 0, i_processed_source_fire = 0;
  wire [575:0] m_context;
  wire m_context_valid;
  logic m_context_ready = 1;
  wire [95:0] m_rgb;
  wire [3:0] m_keep;
  wire m_sof, m_eol, m_last, m_valid;
  logic m_ready = 1;
  wire [63:0] m_tag;
  wire [31:0] m_index;
  wire m_status_valid, m_status_ok;
  logic m_status_ready = 0;
  wire [575:0] m_status_context;
  wire [63:0] m_status_tag;
  wire [7:0] m_status_error;
  wire [31:0] m_status_groups;
  wire o_original_read_quiescent;
  wire o_locked_owner_valid;
  wire [383:0] o_locked_frame;
  wire [63:0] o_locked_lease, o_locked_job, o_locked_pair, o_locked_native_tag;
  wire [31:0] o_locked_writer_tag;
  wire o_locked_member;
  wire o_pixel_fault, o_isp_idle, o_isp_cleanup;
  wire [31:0] o_stale_raw_source_count;

  private_raw_isp_borrow4 #(
    .MAX_WIDTH(1920), .MAX_HEIGHT(1080), .RAW_SAMPLE_BITS(14),
    .EXTERNAL_ISP_ENABLE(1), .ORIGINAL_SYNC_CLEAR_ENABLE(1)
  ) dut (.*);

  function automatic logic [55:0] raw_pattern(input int unsigned g, input logic [13:0] key);
    return {14'(11*g ^ (g>>5)) ^ key ^ 14'h3f25, 14'(13*g) + key,
            14'(g>>10) ^ key ^ 14'h0ddf, 14'(g) ^ key};
  endfunction

  function automatic logic [95:0] map_rgb(input logic [55:0] raw);
    for (int lane = 0; lane < 4; lane++)
      map_rgb[24*lane+:24] = {raw[14*lane+:14] ^ 14'h22d5, raw[14*lane+:10] ^ 10'h163};
  endfunction

  function automatic bit raster_eol(input int g);
    return g % LINE_GROUPS == LINE_GROUPS - 1;
  endfunction

  always @(posedge i_pixel_clk or negedge o_isp_reset_n) begin
    if (!o_isp_reset_n) begin
      i_isp_rgb_valid <= 0;
      i_isp_rgb <= 0;
      i_isp_rgb_sof <= 0;
      i_isp_rgb_eol <= 0;
    end else if (o_isp_raw_valid && i_isp_raw_ready) begin
      i_isp_rgb_valid <= 1;
      i_isp_rgb <= map_rgb(o_isp_raw_data);
      i_isp_rgb_sof <= o_isp_raw_sof;
      i_isp_rgb_eol <= o_isp_raw_eol;
    end else if (i_isp_rgb_valid && o_isp_rgb_ready) i_isp_rgb_valid <= 0;
  end

  string scenario;
  bit owner_live, source_resolved, allow_pixel_fault, track_cleanup, post_retired;
  int unsigned owner_contexts, raw_input_groups, isp_raw_groups, rgb_groups;
  int unsigned terminal_count, cleanup_count, cleanup_reset_falls, rgb_limit;
  logic [13:0] salt;
  logic [575:0] expected_context;
  bit raw_held, rgb_held, context_held, status_held;
  logic [57:0] held_raw;
  logic [198:0] held_rgb;
  logic [575:0] held_context;
  logic [680:0] held_status;
  wire [57:0] raw_tuple = {o_isp_raw_data, o_isp_raw_sof, o_isp_raw_eol};
  wire [198:0] rgb_tuple = {m_rgb, m_keep, m_sof, m_eol, m_last, m_tag, m_index};
  wire [680:0] status_tuple = {m_status_context, m_status_tag, m_status_ok, m_status_error, m_status_groups};

  always @(negedge o_isp_reset_n) if (i_pixel_rst_n && owner_live) begin
    if (raw_held || rgb_held) $fatal(1, "local ISP reset interrupted a held public offer");
    if (track_cleanup) cleanup_reset_falls++;
  end

  always @(posedge i_pixel_clk or negedge i_pixel_rst_n) begin
    if (!i_pixel_rst_n) begin
      owner_live = 0;
      raw_held = 0;
      rgb_held = 0;
      context_held = 0;
      status_held = 0;
    end else begin
      if (raw_held && (o_isp_raw_valid !== 1'b1 || raw_tuple !== held_raw))
        $fatal(1, "held ISP RAW was withdrawn or changed at ISP group %0d", isp_raw_groups);
      if (rgb_held && (m_valid !== 1'b1 || rgb_tuple !== held_rgb))
        $fatal(1, "held RGB was withdrawn or changed at native group %0d", rgb_groups);
      if (context_held && (m_context_valid !== 1'b1 || m_context !== held_context))
        $fatal(1, "held context changed");
      if (status_held && (m_status_valid !== 1'b1 || status_tuple !== held_status))
        $fatal(1, "held native terminal changed");

      if (owner_live && !post_retired && !i_context_fire && o_pool_idle === 1'b1)
        $fatal(1, "pool reported idle before processed SOURCE retirement");
      if (owner_live && !allow_pixel_fault && o_pixel_fault !== 1'b0)
        $fatal(1, "ordinary owner transfer latched pixel fault");
      if (o_locked_owner_valid && (!owner_live ||
          {o_locked_frame, o_locked_lease, o_locked_job, o_locked_pair, o_locked_native_tag,
           o_locked_writer_tag, o_locked_member} !==
          {i_owner_frame, i_owner_lease, i_owner_job, i_owner_pair, i_owner_native_tag,
           i_owner_writer_tag, i_owner_member}))
        $fatal(1, "locked RAW identity differs from the public owner");
      if (m_context_valid) begin
        if (!owner_live || owner_contexts != 0 || m_context !== expected_context)
          $fatal(1, "native context is wrong or duplicated");
        if (m_context_ready) owner_contexts++;
      end

      if (s_raw_valid && s_raw_ready) raw_input_groups++;
      if (o_isp_raw_valid) begin
        if (!owner_live || !o_locked_owner_valid || o_isp_raw_data !== raw_pattern(isp_raw_groups, salt) ||
            o_isp_raw_sof !== (isp_raw_groups == 0) || o_isp_raw_eol !== raster_eol(isp_raw_groups))
          $fatal(1, "ISP RAW payload/identity mismatch at group %0d", isp_raw_groups);
        if (i_isp_raw_ready) begin
          if (isp_raw_groups >= raw_input_groups)
            $fatal(1, "ISP RAW accepted data not supplied by reader");
          isp_raw_groups++;
        end
      end
      if (m_valid) begin
        if (!owner_live || rgb_groups >= isp_raw_groups || rgb_groups >= rgb_limit ||
            m_rgb !== map_rgb(raw_pattern(rgb_groups, salt)) || m_keep !== 4'hf ||
            m_sof !== (rgb_groups == 0) || m_eol !== raster_eol(rgb_groups) ||
            m_last !== (rgb_groups == FRAME_GROUPS - 1) || m_tag !== i_owner_native_tag ||
            m_index !== 32'(rgb_groups))
          $fatal(1, "native RGB payload/identity mismatch at group %0d: index=%0d raw=%0d limit=%0d",
                 rgb_groups, m_index, isp_raw_groups, rgb_limit);
        if (m_ready) begin
          if (owner_contexts != 1) $fatal(1, "RGB retired before native context handshake");
          rgb_groups++;
        end
      end
      if (s_raw_source_valid && s_raw_source_ready && owner_live &&
          {s_raw_source_frame, s_raw_source_lease, s_raw_source_job, s_raw_source_pair,
           s_raw_source_member, s_raw_source_tag} ===
          {i_owner_frame, i_owner_lease, i_owner_job, i_owner_pair, i_owner_member, i_owner_native_tag})
        source_resolved = 1;
      if (o_isp_cleanup) begin
        if (!owner_live || cleanup_count != 0 || (m_valid && !m_ready) || (o_isp_raw_valid && !i_isp_raw_ready))
          $fatal(1, "premature or duplicated ISP cleanup pulse");
        cleanup_count++;
      end
      if (m_status_valid) begin
        if (!owner_live || !source_resolved || !o_original_read_quiescent || owner_contexts != 1 ||
            !i_isp_idle || (m_valid && !m_ready) || (o_isp_raw_valid && !i_isp_raw_ready) || terminal_count != 0 ||
            m_status_context !== expected_context || m_status_tag !== i_owner_native_tag ||
            m_status_groups !== 32'(rgb_groups))
          $fatal(1, "premature/duplicate/wrong native terminal: source=%b isp_idle=%b groups=%0d",
                 source_resolved, i_isp_idle, rgb_groups);
        if (allow_pixel_fault && m_status_ok !== 1'b0)
          $fatal(1, "SOURCE without read drain returned a positive terminal");
        if (m_status_ready) terminal_count++;
      end
      raw_held = o_isp_raw_valid && !i_isp_raw_ready;
      rgb_held = m_valid && !m_ready;
      context_held = m_context_valid && !m_context_ready;
      status_held = m_status_valid && !m_status_ready;
      if (raw_held) held_raw = raw_tuple;
      if (rgb_held) held_rgb = rgb_tuple;
      if (context_held) held_context = m_context;
      if (status_held) held_status = status_tuple;
    end
  end

  task automatic reset_fixture;
    #1 i_pixel_rst_n = 0;
    #2;
    if (m_valid !== 1'b0 || m_context_valid !== 1'b0 || m_status_valid !== 1'b0)
      $fatal(1, "cold reset did not invalidate native outputs");
    i_context_fire = 0;
    i_owner_valid = 0;
    i_owner_published = 0;
    s_raw_valid = 0;
    s_raw_source_valid = 0;
    i_raw_source_read_quiescent = 1;
    i_pixel_cancel = 0;
    i_pipeline_quiescent = 1;
    i_post_pool_idle = 1;
    i_processed_source_fire = 0;
    m_context_ready = 1;
    m_ready = 1;
    m_status_ready = 0;
    allow_raw = 1;
    #18 i_pixel_rst_n = 1;
    @(negedge i_pixel_clk);
  endtask

  task automatic begin_owner(input logic [63:0] nonce, input logic [13:0] key, input bit hold_context);
    for (int t = 0; t < WAIT_CYCLES && o_context_available !== 1'b1; t++) @(negedge i_pixel_clk);
    if (o_context_available !== 1'b1 || owner_live) $fatal(1, "no context availability for new owner");
    for (int w = 0; w < 6; w++) i_owner_frame[64*w+:64] = nonce ^ (64'h8e34cd2919ab827b * (w+1));
    i_owner_frame[220:205] = 16'd1920;
    i_owner_frame[236:221] = 16'd1080;
    i_owner_lease = nonce ^ 64'ha6ba2a16e54f91bd;
    i_owner_job = nonce ^ 64'h798abd23f7a119ea;
    i_owner_pair = nonce ^ 64'h1d8209b631da377a;
    i_owner_native_tag = nonce ^ 64'hbc178374ef79c6b5;
    i_owner_writer_tag = nonce[31:0] ^ 32'he17209d6;
    i_owner_member = nonce[0];
    i_context_frame = i_owner_frame;
    i_context_job = i_owner_job;
    i_context_pair = i_owner_pair;
    i_context_member = i_owner_member;
    i_context_key = {i_context_frame[76:45], 31'd0, i_context_frame[4]};
    i_context_aux = i_context_job;
    expected_context = {i_owner_job, i_context_key, i_owner_native_tag, i_owner_frame};
    salt = key;
    owner_contexts = 0;
    raw_input_groups = 0;
    isp_raw_groups = 0;
    rgb_groups = 0;
    terminal_count = 0;
    cleanup_count = 0;
    cleanup_reset_falls = 0;
    rgb_limit = FRAME_GROUPS;
    track_cleanup = 0;
    source_resolved = 0;
    allow_pixel_fault = 0;
    post_retired = 0;
    m_context_ready = !hold_context;
    owner_live = 1;
    i_owner_published = 1;
    i_owner_valid = 1;
    i_context_fire = 1;
    @(negedge i_pixel_clk);
    i_context_fire = 0;
    i_raw_source_read_quiescent = 0;
    i_pipeline_quiescent = 0;
    i_post_pool_idle = 0;
    if (hold_context) begin
      for (int t = 0; t < WAIT_CYCLES && m_context_valid !== 1'b1; t++) @(negedge i_pixel_clk);
      if (m_context_valid !== 1'b1) $fatal(1, "native context did not publish while stalled");
      repeat (6) @(negedge i_pixel_clk);
      m_context_ready = 1;
    end
    for (int t = 0; t < WAIT_CYCLES &&
         (owner_contexts != 1 || o_payload_enable !== 1'b1 || o_isp_reset_n !== 1'b1); t++) @(negedge i_pixel_clk);
    if (owner_contexts != 1 || o_payload_enable !== 1'b1 || o_locked_owner_valid !== 1'b1 || o_isp_reset_n !== 1'b1)
      $fatal(1, "owner failed to open RAW payload after valid context (contexts=%0d enable=%b lock=%b reset_n=%b)",
             owner_contexts, o_payload_enable, o_locked_owner_valid, o_isp_reset_n);
  endtask

  task automatic send_group(input int g);
    s_raw_data = raw_pattern(g, salt);
    s_raw_sof = g == 0;
    s_raw_eol = raster_eol(g);
    s_raw_valid = 1;
    for (int t = 0; t < WAIT_CYCLES; t++) begin
      @(posedge i_pixel_clk);
      if (s_raw_ready === 1'b1) begin
        @(negedge i_pixel_clk);
        s_raw_valid = 0;
        return;
      end
    end
    $fatal(1, "no RAW reader handshake at group %0d", g);
  endtask

  task automatic wait_rgb_count(input int expected);
    for (int t = 0; t < WAIT_CYCLES && rgb_groups != expected; t++) @(negedge i_pixel_clk);
    if (rgb_groups != expected)
      $fatal(1, "expected %0d native RGB transfers, saw %0d (reader=%0d ISP RAW=%0d)",
             expected, rgb_groups, raw_input_groups, isp_raw_groups);
  endtask

  task automatic wait_rgb_offer;
    for (int t = 0; t < WAIT_CYCLES && m_valid !== 1'b1; t++) @(negedge i_pixel_clk);
    if (m_valid !== 1'b1) $fatal(1, "no RGB offer under backpressure");
  endtask

  task automatic send_source(input int corrupt_field, input bit ok, input logic [7:0] code,
                             input bit stale, input bit simultaneous_cancel);
    logic [31:0] prior_count;
    prior_count = o_stale_raw_source_count;
    s_raw_source_frame = i_owner_frame;
    s_raw_source_lease = i_owner_lease;
    s_raw_source_job = i_owner_job;
    s_raw_source_pair = i_owner_pair;
    s_raw_source_member = i_owner_member;
    s_raw_source_tag = i_owner_native_tag;
    case (corrupt_field)
      1: s_raw_source_frame[382] ^= 1'b1;
      2: s_raw_source_lease[29] ^= 1'b1;
      3: s_raw_source_job[61] ^= 1'b1;
      4: s_raw_source_pair[42] ^= 1'b1;
      5: s_raw_source_member ^= 1'b1;
      6: s_raw_source_tag[34] ^= 1'b1;
      default: ;
    endcase
    s_raw_source_ok = ok;
    s_raw_source_error = code;
    s_raw_source_valid = 1;
    for (int t = 0; t < WAIT_CYCLES; t++) begin
      #1 i_pixel_cancel = simultaneous_cancel && (s_raw_source_ready === 1'b1);
      @(posedge i_pixel_clk);
      if (s_raw_source_ready === 1'b1) begin
        if (i_pixel_cancel !== simultaneous_cancel)
          $fatal(1, "fixture did not align cancel with SOURCE acceptance");
        @(negedge i_pixel_clk);
        s_raw_source_valid = 0;
        i_pixel_cancel = 0;
        @(negedge i_pixel_clk);
        if (o_stale_raw_source_count !== prior_count + (stale ? 32'd1 : 32'd0))
          $fatal(1, "SOURCE stale accounting: field=%0d expected delta=%0d count=%0d->%0d",
                 corrupt_field, stale, prior_count, o_stale_raw_source_count);
        return;
      end
      @(negedge i_pixel_clk);
    end
    $fatal(1, "reader SOURCE offer did not handshake: field=%0d stale=%b", corrupt_field, stale);
  endtask

  task automatic accept_terminal(input bit ok, input logic [7:0] code, input int expected_groups,
                                 input int expected_cleanup);
    i_pipeline_quiescent = 1;
    for (int t = 0; t < WAIT_CYCLES && m_status_valid !== 1'b1; t++) @(negedge i_pixel_clk);
    if (m_status_valid !== 1'b1)
      $fatal(1, "native terminal missing (source=%b rgb=%0d cleanup=%0d reset_falls=%0d)",
             source_resolved, rgb_groups, cleanup_count, cleanup_reset_falls);
    if (m_status_ok !== ok || m_status_error !== code || m_status_groups !== 32'(expected_groups))
      $fatal(1, "native terminal expected %b/%0d/%0d got %b/%0d/%0d",
             ok, code, expected_groups, m_status_ok, m_status_error, m_status_groups);
    if (cleanup_count != expected_cleanup || (expected_cleanup != 0 && cleanup_reset_falls != 1))
      $fatal(1, "cleanup pulse/reset count: expected %0d, pulse=%0d reset=%0d",
             expected_cleanup, cleanup_count, cleanup_reset_falls);
    repeat (6) @(negedge i_pixel_clk);
    m_status_ready = 1;
    @(negedge i_pixel_clk);
    m_status_ready = 0;
    if (terminal_count != 1) $fatal(1, "native terminal was not consumed exactly once");
    // Prove native terminal, downstream idle, and processed SOURCE are separate.
    repeat (4) @(negedge i_pixel_clk);
    i_post_pool_idle = 1;
    repeat (4) @(negedge i_pixel_clk);
    i_processed_source_fire = 1;
    post_retired = 1;
    @(negedge i_pixel_clk);
    i_processed_source_fire = 0;
    for (int t = 0; t < WAIT_CYCLES && o_pool_idle !== 1'b1; t++) @(negedge i_pixel_clk);
    if (o_pool_idle !== 1'b1 || o_pixel_fault !== 1'b0 || o_isp_reset_n !== 1'b1)
      $fatal(1, "pool/ISP did not recover after processing retirement: idle=%b fault=%b reset_n=%b",
             o_pool_idle, o_pixel_fault, o_isp_reset_n);
    $display("NATIVE_TERMINAL ok=%b error=%0d reader=%0d isp_raw=%0d rgb=%0d cleanup=%0d reset=%0d",
             ok, code, raw_input_groups, isp_raw_groups, rgb_groups, cleanup_count, cleanup_reset_falls);
    owner_live = 0;
    i_owner_published = 0;
    i_owner_valid = 0;
    repeat (3) @(negedge i_pixel_clk);
  endtask

  task automatic first_raster;
    begin_owner(64'h846526dcbb4d828b, 14'h235d, 1);
    for (int g = 0; g < FRAME_GROUPS; g++) begin
      if (g == 0 || g == LINE_GROUPS - 1 || g == FRAME_GROUPS - 1) begin
        wait_rgb_count(g);
        m_ready = 0;
        send_group(g);
        wait_rgb_offer();
        repeat (4) @(negedge i_pixel_clk);
        if (g != FRAME_GROUPS - 1) m_ready = 1;
      end else send_group(g);
    end
    // All RAW delivered, while the real final RGB offer is still stalled.
    i_raw_source_read_quiescent = 1;
    send_source(6, 0, 8'hc8, 1, 0);
    send_source(0, 1, 8'h00, 0, 0);
    send_source(0, 0, 8'hdb, 1, 0);
    m_ready = 1;
    wait_rgb_count(FRAME_GROUPS);
    if (raw_input_groups != FRAME_GROUPS || isp_raw_groups != FRAME_GROUPS)
      $fatal(1, "complete raster did not account for every RAW handshake");
    accept_terminal(1, 0, FRAME_GROUPS, 0);
  endtask

  task automatic recovery_prefix(input logic [63:0] nonce);
    begin_owner(nonce, 14'h1b3d, 0);
    for (int g = 0; g < 8; g++) send_group(g);
    wait_rgb_count(8);
    track_cleanup = 1;
    i_raw_source_read_quiescent = 1;
    send_source(0, 0, 0, 0, 0);
    accept_terminal(0, 3, 8, 1);
  endtask

  task automatic source_failure(input bit cancel_also);
    begin_owner(64'h96c5caff1bb09351, 14'h12a3, 0);
    for (int g = 0; g < 4; g++) send_group(g);
    wait_rgb_count(4);
    if (!cancel_also) begin
      // Every owner field is independently necessary; the bad offers are
      // legal while the real reader is still active and not read-quiescent.
      for (int f = 1; f <= 5; f++) send_source(f, 0, 8'hf0, 1, 0);
    end
    m_ready = 0;
    send_group(4);
    wait_rgb_offer();
    repeat (4) @(negedge i_pixel_clk);
    rgb_limit = 5;
    i_raw_source_read_quiescent = 1;
    track_cleanup = 1;
    send_source(0, 0, 8'ha5, 0, cancel_also);
    repeat (5) @(negedge i_pixel_clk);
    m_ready = 1;
    wait_rgb_count(5);
    // The private owner turns a reader SOURCE failure into a native cancel.
    // An explicit reader code remains distinct from the native terminal ABI.
    accept_terminal(0, 8'd3, 5, 1);
    recovery_prefix(64'h74865800582b027e);
  endtask

  task automatic cancel_raw_offer;
    begin_owner(64'h6c286892d2c67e3b, 14'h0a6a, 0);
    for (int g = 0; g < 4; g++) send_group(g);
    wait_rgb_count(4);
    allow_raw = 0;
    fork
      send_group(4);
      begin
        for (int t = 0; t < WAIT_CYCLES && o_isp_raw_valid !== 1'b1; t++) @(negedge i_pixel_clk);
        if (o_isp_raw_valid !== 1'b1) $fatal(1, "RAW did not publish under backpressure");
        repeat (4) @(negedge i_pixel_clk);
        rgb_limit = 4;
        track_cleanup = 1;
        i_pixel_cancel = 1;
        @(negedge i_pixel_clk);
        i_pixel_cancel = 0;
        repeat (5) @(negedge i_pixel_clk);
        allow_raw = 1;
      end
    join
    for (int t = 0; t < WAIT_CYCLES && isp_raw_groups != 5; t++) @(negedge i_pixel_clk);
    if (isp_raw_groups != 5) $fatal(1, "stalled RAW offer was not drained");
    i_raw_source_read_quiescent = 1;
    send_source(0, 0, 0, 0, 0);
    accept_terminal(0, 3, 4, 1);
    recovery_prefix(64'h5273fa76a12ec382);
  endtask

  task automatic source_without_drain;
    begin_owner(64'hcb8d27b40f5ba0f5, 14'h3ad9, 0);
    for (int g = 0; g < 8; g++) send_group(g);
    wait_rgb_count(8);
    allow_pixel_fault = 1;
    send_source(0, 1, 0, 0, 0); // Intentional reader contract violation.
    for (int t = 0; t < WAIT_CYCLES && o_pixel_fault !== 1'b1; t++) @(negedge i_pixel_clk);
    if (o_pixel_fault !== 1'b1) $fatal(1, "exact SOURCE without reader drain did not latch pixel fault");
    i_pipeline_quiescent = 1;
    i_post_pool_idle = 1;
    i_raw_source_read_quiescent = 1;
    repeat (12) begin
      @(negedge i_pixel_clk);
      if (o_pixel_fault !== 1'b1 || o_context_available !== 1'b0 || o_pool_idle !== 1'b0)
        $fatal(1, "undrained SOURCE fault failed to block new owner until reset");
    end
    reset_fixture();
    recovery_prefix(64'hc57ed62299a3e61e);
  endtask

  initial begin
    if (!$value$plusargs("CASE=%s", scenario)) $fatal(1, "missing +CASE");
    reset_fixture();
    case (scenario)
      "first_raster": first_raster();
      "source_failure": source_failure(0);
      "cancel_priority": source_failure(1);
      "cancel_raw_offer": cancel_raw_offer();
      "source_without_drain": source_without_drain();
      default: $fatal(1, "unknown +CASE %s", scenario);
    endcase
    $display("PASS source_borrow %s", scenario);
    $finish;
  end

  initial begin
    if (!$test$plusargs("CASE=first_raster")) begin
      #80_000;
      $fatal(1, "short scenario simulator watchdog");
    end else begin
      #16_000_000;
      $fatal(1, "one raster simulator watchdog");
    end
  end
endmodule
