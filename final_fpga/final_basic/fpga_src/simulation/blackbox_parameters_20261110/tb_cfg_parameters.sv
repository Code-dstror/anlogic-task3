`timescale 1ns/1ps

module tb_cfg_parameters;
  `include "cfg_public_constants.svh"

  typedef logic [1023:0] extension_t;
  typedef logic [1183:0] tuple_t;
  typedef struct packed {
    logic [31:0] quality;
    logic [31:0] flags;
    logic [31:0] minimum;
    logic [31:0] budget;
    logic [31:0] restart;
  } jpeg_t;

  logic user_clk = 0, pixel_clk = 0;
  logic user_rst_n = 0, pixel_rst_n = 0;
  logic i_stereo_mode = 0, write_valid = 0, read_valid = 0;
  logic [11:0] write_offset = 0, read_offset = 0;
  logic [31:0] write_data = 0;
  logic [3:0] write_strobes = 0;
  wire read_response_valid, user_initialized;
  wire [1:0] write_response, read_response;
  wire [31:0] read_data, user_session;

  logic pipeline_idle = 1, frame_accept = 0, i_apply_source_fault = 0;
  logic [31:0] frame_sequence = 0;
  logic m_config_ready = 0, s_config_ack_valid = 0, s_config_ack_ok = 0;
  tuple_t s_config_ack_data = '0;
  wire source_ready, pause_new_jobs, pixel_initialized, s_config_ack_ready, m_config_valid;
  wire [31:0] source_session, mode_epoch, config_stale_ack_count;
  wire [1183:0] m_config_data, active_config;
  wire [1:0] active_mode, active_product_mode;
  wire [7:0] active_quality, minimum_quality;
  wire adaptive_quality, active_schema2, active_legacy_gaussian;
  wire [24:0] frame_budget;
  wire [15:0] restart_mcus;
  wire [5:0] active_processing_enables;

  mono_config_service_v2 #(
    .PROFILE(1), .MAX_WIDTH(1920), .MAX_HEIGHT(1080), .REMOTE_CONFIG_ENABLE(1),
    .EXT_WIDTH(1024), .EXT_STRIPS(4), .EXT_COMBINATIONS(0), .EXT_SUPPORTED(8'h34),
    .V2_SUPPORTED_MODES(3'b101), .V2_SUPPORTED_ENABLES(6'h3f),
    .LIVE_GRAY_FIXED_ENABLE(0), .LIVE_BASIC_MODES_ENABLE(1),
    .COMPACT_EMPTY_EXTENSION_ENABLE(0), .COMPACT_STAGE2_EXTENSION_ENABLE(1),
    .LANE_GAUSSIAN_ONLY(1), .CFG_DIAG_ENABLE(0), .STEREO_CAPABLE(1),
    .APPLY_SOURCE_FAULT_ENABLE(1)
  ) dut (
    .o_user_transaction_idle(), .o_user_stereo_compatible(), .config_fault(),
    .diag_observer_rst_n(2'b0), .diag_source_fs(1'b0), .diag_source_gates(16'b0),
    .diag_domains(), .diag_domain_reset_n(), .o_apply_diagnostics(), .*
  );

  always #4 user_clk = ~user_clk;
  always #5 pixel_clk = ~pixel_clk;

  string scenario, checkpoint;
  logic [31:0] session_id, next_request;
  tuple_t published, allowed_tuple, held_offer;
  bit check_active, allow_publication, forbid_offer, was_stalled;
  int accepted_configs;

  always @(posedge pixel_clk) begin
    if (!pixel_rst_n) begin
      was_stalled = 0;
      accepted_configs = 0;
    end else begin
      if (was_stalled && (m_config_valid !== 1'b1 || m_config_data !== held_offer))
        $fatal(1, "[%s] remote configuration offer changed under backpressure", checkpoint);
      if (forbid_offer && m_config_valid !== 1'b0)
        $fatal(1, "[%s] unexpected remote configuration offer", checkpoint);
      was_stalled = m_config_valid === 1'b1 && !m_config_ready;
      if (was_stalled)
        held_offer = m_config_data;
      if (m_config_valid && m_config_ready)
        accepted_configs = accepted_configs + 1;

      #1;
      if (check_active && allow_publication && active_config === allowed_tuple) begin
        published = allowed_tuple;
        allow_publication = 0;
      end
      if (check_active && (active_config !== published || mode_epoch !== published[159:128]))
        $fatal(1, "[%s] PIX ACTIVE changed outside its qualified frame; epoch=%h expected=%h",
               checkpoint, mode_epoch, published[159:128]);
    end
  end

  initial begin
    #1_000_000;
    $fatal(1, "Simulation watchdog reached 1 ms at checkpoint %s", checkpoint);
  end

  function automatic jpeg_t jpeg(
    input logic [31:0] quality, flags, minimum, budget, restart
  );
    return {quality, flags, minimum, budget, restart};
  endfunction

  function automatic extension_t sdr(
    input logic [5:0] enables, input logic [31:0] lut_generation
  );
    extension_t value;
    value = '0;
    value[V2_SCHEMA_LSB +: V2_SCHEMA_WIDTH] = V2_SCHEMA_VALUE;
    value[V2_PRODUCT_MODE_LSB +: V2_PRODUCT_MODE_WIDTH] = V2_MONO_SDR;
    value[V2_PROCESSING_ENABLES_LSB +: V2_PROCESSING_ENABLES_WIDTH] = enables;
    value[V2_DEHAZE_LUT_GENERATION_LSB +: V2_DEHAZE_LUT_GENERATION_WIDTH] = lut_generation;
    return value;
  endfunction

  function automatic extension_t hdr(
    input logic [13:0] motion_base, input logic [3:0] motion_shift,
    input logic [31:0] max_delta, max_wait, max_age
  );
    extension_t value;
    value = sdr(0, 0);
    value[V2_PRODUCT_MODE_LSB +: V2_PRODUCT_MODE_WIDTH] = V2_MONO_HDR;
    value[V2_HDR_RATIO_LSB +: V2_HDR_RATIO_WIDTH] = 4;
    value[V2_HDR_BLACK_LONG_LSB +: V2_HDR_BLACK_LONG_WIDTH] = 50;
    value[V2_HDR_BLACK_SHORT_LSB +: V2_HDR_BLACK_SHORT_WIDTH] = 50;
    value[V2_HDR_QUALIFICATION_LSB +: V2_HDR_QUALIFICATION_WIDTH] = 15;
    value[V2_HDR_MOTION_BASE_LSB +: V2_HDR_MOTION_BASE_WIDTH] = motion_base;
    value[V2_HDR_MOTION_SHIFT_LSB +: V2_HDR_MOTION_SHIFT_WIDTH] = motion_shift;
    value[V2_HDR_MAX_DELTA_NS_LSB +: V2_HDR_MAX_DELTA_NS_WIDTH] = {32'b0, max_delta};
    value[V2_HDR_MAX_WAIT_NS_LSB +: V2_HDR_MAX_WAIT_NS_WIDTH] = max_wait;
    value[V2_HDR_MAX_AGE_NS_LSB +: V2_HDR_MAX_AGE_NS_WIDTH] = max_age;
    return value;
  endfunction

  function automatic tuple_t expected_tuple(
    input jpeg_t basic, input extension_t ext, input logic [31:0] req_id, epoch
  );
    return {ext, epoch, 6'b0, basic.restart[15:0], basic.budget[24:0], basic.minimum[6:0],
            basic.flags[0], basic.quality[6:0], CFG_MODE_COLOR[1:0], session_id, req_id};
  endfunction
  task automatic bar_write(input logic [11:0] address, input logic [31:0] value);
    @(negedge user_clk);
    write_valid = 1;
    write_offset = address;
    write_data = value;
    write_strobes = 4'hf;
    @(posedge user_clk);
    if (write_response !== 2'b00)
      $fatal(1, "[%s] BAR write %h=%h transport response %b",
             checkpoint, address, value, write_response);
    @(negedge user_clk);
    write_valid = 0;
    write_strobes = 0;
  endtask

  task automatic bar_read(input logic [11:0] address, output logic [31:0] value);
    bit got_response;
    logic [1:0] response;
    @(negedge user_clk);
    read_valid = 1;
    read_offset = address;
    @(posedge user_clk);
    #1;
    got_response = read_response_valid === 1'b1;
    value = read_data;
    response = read_response;
    @(negedge user_clk);
    read_valid = 0;
    for (int edge_count = 0; !got_response && edge_count < 128; edge_count++) begin
      @(posedge user_clk);
      #1;
      got_response = read_response_valid === 1'b1;
      value = read_data;
      response = read_response;
    end
    if (!got_response || response !== 2'b00)
      $fatal(1, "[%s] BAR read %h valid=%b transport response %b",
             checkpoint, address, got_response, response);
  endtask

  task automatic expect_bar(input logic [11:0] address, input logic [31:0] expected);
    logic [31:0] value;
    bar_read(address, value);
    if (value !== expected)
      $fatal(1, "[%s] BAR %h expected %h got %h", checkpoint, address, expected, value);
  endtask

  task automatic expect_status(
    input logic [31:0] required, forbidden, input bit poll
  );
    logic [31:0] status, error_code;
    int limit;
    limit = poll ? 1024 : 1;
    for (int attempt = 0; attempt < limit; attempt++) begin
      bar_read(CFG_STATUS, status);
      if ((status & (required | forbidden)) === required)
        return;
      if ((status & CFG_STS_ERROR) != 0 && (required & CFG_STS_ERROR) == 0)
        break;
    end
    bar_read(CFG_ERROR, error_code);
    $fatal(1, "[%s] BAR status %h error %h; required mask %h forbidden mask %h",
           checkpoint, status, error_code, required, forbidden);
  endtask

  task automatic check_pixel_active(input tuple_t expected);
    logic [7:0] schema;
    schema = expected[160 + V2_SCHEMA_LSB +: V2_SCHEMA_WIDTH];
    if (active_config !== expected || mode_epoch !== expected[159:128] ||
        active_mode !== expected[65:64] || active_quality !== {1'b0, expected[72:66]} ||
        adaptive_quality !== expected[73] || minimum_quality !== {1'b0, expected[80:74]} ||
        frame_budget !== expected[105:81] || restart_mcus !== expected[121:106] ||
        active_schema2 !== (schema == V2_SCHEMA_VALUE) || active_legacy_gaussian !== 1'b0 ||
        active_product_mode !== expected[160 + V2_PRODUCT_MODE_LSB +: V2_PRODUCT_MODE_WIDTH] ||
        active_processing_enables !== expected[160 + V2_PROCESSING_ENABLES_LSB +: V2_PROCESSING_ENABLES_WIDTH])
      $fatal(1, "[%s] PIX ACTIVE or exposed fields differ; expected tuple=%h actual=%h",
             checkpoint, expected, active_config);
  endtask

  task automatic check_user_active(input tuple_t expected);
    expect_bar(CFG_ACTIVE_SESSION, expected[63:32]);
    expect_bar(CFG_MODE_EPOCH, expected[159:128]);
    expect_bar(CFG_ACTIVE_MODE, {30'b0, expected[65:64]});
    expect_bar(CFG_ACTIVE_QUALITY, {25'b0, expected[72:66]});
    expect_bar(CFG_ACTIVE_FLAGS, {31'b0, expected[73]});
    expect_bar(CFG_ACTIVE_MIN_QUALITY, {25'b0, expected[80:74]});
    expect_bar(CFG_ACTIVE_FRAME_BUDGET, {7'b0, expected[105:81]});
    expect_bar(CFG_ACTIVE_RESTART_MCUS, {16'b0, expected[121:106]});
    for (int word_index = 0; word_index < V2_WORD_COUNT; word_index++)
      expect_bar(CFG_EXT_ACTIVE_BASE + 12'(4 * word_index), expected[160 + 32 * word_index +: 32]);
  endtask

  task automatic receive_config(
    input int stall_cycles, output tuple_t value
  );
    for (int edge_count = 0; edge_count < 2048; edge_count++) begin
      @(negedge pixel_clk);
      if (m_config_valid === 1'b1) begin
        value = m_config_data;
        repeat (stall_cycles) @(negedge pixel_clk);
        m_config_ready = 1;
        @(posedge pixel_clk);
        if (m_config_valid !== 1'b1 || m_config_data !== value)
          $fatal(1, "[%s] offer missing or changed at remote acceptance", checkpoint);
        @(negedge pixel_clk);
        m_config_ready = 0;
        forbid_offer = 1;
        return;
      end
    end
    $fatal(1, "[%s] timed out waiting for complete remote configuration offer", checkpoint);
  endtask

  task automatic send_ack(input tuple_t value);
    @(negedge pixel_clk);
    s_config_ack_valid = 1;
    s_config_ack_ok = 1;
    s_config_ack_data = value;
    for (int edge_count = 0; edge_count < 2048; edge_count++) begin
      @(posedge pixel_clk);
      if (s_config_ack_ready === 1'b1) begin
        @(negedge pixel_clk);
        s_config_ack_valid = 0;
        s_config_ack_ok = 0;
        s_config_ack_data = '0;
        return;
      end
    end
    $fatal(1, "[%s] timed out waiting for ACK acceptance", checkpoint);
  endtask
  task automatic coordinated_boot(input bit stereo);
    tuple_t boot_offer, expected;
    logic [31:0] features;
    @(negedge pixel_clk);
    check_active = 0;
    allow_publication = 0;
    forbid_offer = 0;
    pixel_rst_n = 0;
    user_rst_n = 0;
    i_stereo_mode = stereo;
    pipeline_idle = 1;
    frame_accept = 0;
    frame_sequence = 0;
    i_apply_source_fault = 0;
    m_config_ready = 0;
    s_config_ack_valid = 0;
    repeat (32) @(negedge pixel_clk);
    pixel_rst_n = 1;
    @(negedge user_clk);
    user_rst_n = 1;
    receive_config(2, boot_offer);
    send_ack(boot_offer);
    expect_status(CFG_STS_SESSION_READY, CFG_STS_ERROR, 1);
    bar_read(CFG_SESSION, session_id);
    if ($isunknown(session_id) || session_id == 0 || user_session !== session_id ||
        source_session !== session_id || user_initialized !== 1'b1 || pixel_initialized !== 1'b1)
      $fatal(1, "[%s] BOOT failed to establish one nonzero session across domains", checkpoint);
    expected = expected_tuple(jpeg(CFG_DEFAULT_QUALITY, 0, 1, 0, 0), '0, 0, 0);
    if (boot_offer !== expected || accepted_configs != 1)
      $fatal(1, "[%s] BOOT offer differs from defaults; expected=%h got=%h count=%0d",
             checkpoint, expected, boot_offer, accepted_configs);
    published = expected;
    check_active = 1;
    next_request = 1;
    check_pixel_active(expected);
    check_user_active(expected);
    expect_bar(CFG_COMPILED_PROFILE, stereo ? CFG_DUAL1920 : CFG_MONO1920);
    expect_bar(CFG_CAMERA_PRESENT, stereo ? 3 : 1);
    expect_bar(CFG_EXT_V2_ENABLES, stereo ? 32'h0f : 32'h3f);
    bar_read(CFG_FEATURES, features);
    if ((features & CFG_FEAT_FRAME_APPLIED) !== CFG_FEAT_FRAME_APPLIED)
      $fatal(1, "[%s] FRAME_APPLIED not advertised in CFG_FEATURES=%h", checkpoint, features);
  endtask

  task automatic write_prepare(
    input jpeg_t basic, input extension_t ext, output logic [31:0] req_id,
    input bit negotiate = 1
  );
    req_id = next_request;
    next_request = next_request + 1;
    bar_write(CFG_REQUEST_SESSION, session_id);
    bar_write(CFG_REQUEST_SEQUENCE, req_id);
    bar_write(CFG_REQUEST_MODE, CFG_MODE_COLOR);
    bar_write(CFG_REQUEST_QUALITY, basic.quality);
    bar_write(CFG_REQUEST_FLAGS, basic.flags);
    bar_write(CFG_REQUEST_MIN_QUALITY, basic.minimum);
    bar_write(CFG_REQUEST_FRAME_BUDGET, basic.budget);
    bar_write(CFG_REQUEST_RESTART_MCUS, basic.restart);
    for (int word_index = 0; word_index < V2_WORD_COUNT; word_index++)
      bar_write(CFG_EXT_SHADOW_BASE + 12'(4 * word_index), ext[32 * word_index +: 32]);
    if (negotiate)
      bar_write(CFG_HOST_CAPABILITIES, CFG_FEAT_FRAME_APPLIED);
    bar_write(CFG_COMMAND, CFG_CMD_PREPARE_EXT);
  endtask

  task automatic send_frame(
    input logic [31:0] seq, input bit qualified, input bit fault
  );
    @(negedge pixel_clk);
    frame_sequence = seq;
    frame_accept = 1;
    i_apply_source_fault = fault;
    if (qualified && !fault)
      allow_publication = 1;
    @(posedge pixel_clk);
    if (qualified && !fault && source_ready !== 1'b1)
      $fatal(1, "[%s] a qualified boundary had no source_ready", checkpoint);
    @(negedge pixel_clk);
    frame_accept = 0;
    i_apply_source_fault = 0;
  endtask

  task automatic prepare_commit(
    input jpeg_t basic, input extension_t ext, input bit exercise_stalls,
    output tuple_t offered
  );
    logic [31:0] req_id, status, error_code;
    tuple_t expected;
    int previous_count;
    previous_count = accepted_configs;
    @(negedge pixel_clk);
    pipeline_idle = !exercise_stalls;
    write_prepare(basic, ext, req_id);
    if (exercise_stalls) begin
      for (int edge_count = 0; pause_new_jobs !== 1'b1 && edge_count < 2048; edge_count++)
        @(negedge pixel_clk);
      if (pause_new_jobs !== 1'b1) begin
        bar_read(CFG_STATUS, status);
        bar_read(CFG_ERROR, error_code);
        $fatal(1, "[%s] PREPARE did not pause new work before the old drain; status=%h error=%h",
               checkpoint, status, error_code);
      end
      repeat (12) @(negedge pixel_clk);
      expect_status(CFG_STS_BUSY, CFG_STS_READY | CFG_STS_APPLIED | CFG_STS_ERROR, 0);
      expect_bar(CFG_MODE_EPOCH, published[159:128]);
      @(negedge pixel_clk);
      pipeline_idle = 1;
    end
    expect_status(CFG_STS_BUSY | CFG_STS_READY, CFG_STS_APPLIED | CFG_STS_ERROR, 1);
    expect_bar(CFG_RESPONSE_SEQUENCE, req_id);
    expect_bar(CFG_MODE_EPOCH, published[159:128]);
    expected = expected_tuple(basic, ext, req_id, published[159:128] + 32'd1);

    // The PREPARE identity remains in the shadow registers for COMMIT.
    forbid_offer = 0;
    bar_write(CFG_COMMAND, CFG_CMD_COMMIT);
    receive_config(exercise_stalls ? 9 : 0, offered);
    if (offered !== expected || accepted_configs != previous_count + 1)
      $fatal(1, "[%s] complete COMMIT offer differs; expected=%h got=%h count=%0d",
             checkpoint, expected, offered, accepted_configs - previous_count);
    allowed_tuple = expected;
  endtask

  task automatic before_frame(input tuple_t offered, input bit stale_and_backpressure);
    tuple_t stale;
    if (stale_and_backpressure) begin
      repeat (8) @(negedge pixel_clk);
      send_frame(32'hbad0_0001, 0, 0);
      expect_status(CFG_STS_BUSY, CFG_STS_APPLIED | CFG_STS_ERROR, 0);
      stale = offered;
      stale[159:128] = published[159:128];
      send_ack(stale);
      send_frame(32'hbad0_0002, 0, 0);
      repeat (8) @(negedge pixel_clk);
      expect_status(CFG_STS_BUSY, CFG_STS_APPLIED | CFG_STS_ERROR, 0);
      expect_bar(CFG_MODE_EPOCH, published[159:128]);
      $display("CHECK [%s] stale epoch withheld publication; stale ACK count=%0d",
               checkpoint, config_stale_ack_count);
    end
    send_ack(offered);
    // The old work has drained. The newly configured source can already be busy.
    pipeline_idle = !stale_and_backpressure;
    repeat (4) @(negedge pixel_clk);
    expect_status(CFG_STS_BUSY, CFG_STS_APPLIED | CFG_STS_ERROR, 0);
    expect_bar(CFG_MODE_EPOCH, published[159:128]);
    for (int edge_count = 0; source_ready !== 1'b1 && edge_count < 2048; edge_count++)
      @(negedge pixel_clk);
    if (source_ready !== 1'b1)
      $fatal(1, "[%s] source did not become eligible after its matching ACK", checkpoint);
  endtask

  task automatic legal(
    input string name, input jpeg_t basic, input extension_t ext,
    input logic [31:0] frame_seq, input bit exercise_stalls
  );
    tuple_t offer;
    checkpoint = name;
    $display("BEGIN [%s]", checkpoint);
    prepare_commit(basic, ext, exercise_stalls, offer);
    before_frame(offer, exercise_stalls);
    send_frame(frame_seq, 1, 0);
    expect_status(CFG_STS_APPLIED | CFG_STS_SESSION_READY,
                  CFG_STS_BUSY | CFG_STS_READY | CFG_STS_ERROR, 1);
    expect_bar(CFG_RESPONSE_SEQUENCE, offer[31:0]);
    expect_bar(CFG_ERROR, CFG_ERR_OK);
    expect_bar(CFG_APPLIED_FIRST_SEQUENCE, frame_seq);
    expect_bar(CFG_APPLIED_CAMERA, 0);
    check_pixel_active(allowed_tuple);
    check_user_active(allowed_tuple);
    $display("CHECK [%s] APPLIED session=%0d request=%0d epoch=%0d first=%h new_work_busy=%b",
             checkpoint, session_id, offer[31:0], offer[159:128], frame_seq, !pipeline_idle);
    @(negedge pixel_clk);
    pipeline_idle = 1;
  endtask
  task automatic reject_request(
    input string name, input bit stereo, input jpeg_t basic,
    input extension_t ext, input logic [31:0] error_code, input bit negotiate = 1
  );
    logic [31:0] req_id;
    checkpoint = name;
    $display("BEGIN [%s]", checkpoint);
    coordinated_boot(stereo);
    write_prepare(basic, ext, req_id, negotiate);
    expect_status(CFG_STS_ERROR, CFG_STS_BUSY | CFG_STS_READY | CFG_STS_APPLIED, 1);
    expect_bar(CFG_RESPONSE_SEQUENCE, req_id);
    expect_bar(CFG_ERROR, error_code);
    check_pixel_active(published);
    check_user_active(published);
    if (accepted_configs != 1)
      $fatal(1, "[%s] rejected input sent a configuration after BOOT", checkpoint);
    $display("CHECK [%s] ERROR=%0d retained ACTIVE and generated no offer", checkpoint, error_code);
  endtask

  task automatic reject_basic;
    extension_t ext;
    ext = sdr(V2_HISTOGRAM, 0);
    reject_request("missing_frame_applied_negotiation", 0, jpeg(75, 0, 1, 0, 0),
                   ext, CFG_ERR_INVALID, 0);
    reject_request("quality_over_100", 0, jpeg(101, 0, 1, 0, 0), ext, CFG_ERR_INVALID);
    reject_request("min_quality_zero", 0, jpeg(75, 0, 0, 0, 0), ext, CFG_ERR_INVALID);
    reject_request("min_quality_above_quality", 0, jpeg(75, 0, 76, 0, 0), ext, CFG_ERR_INVALID);
    reject_request("unknown_flag_bit", 0, jpeg(75, 2, 1, 1, 0), ext, CFG_ERR_INVALID);
    reject_request("adaptive_zero_budget", 0, jpeg(75, 1, 1, 0, 0), ext, CFG_ERR_INVALID);
    reject_request("budget_over_16MiB", 0, jpeg(75, 1, 1, 16777217, 0), ext, CFG_ERR_INVALID);
    reject_request("restart_over_65535", 0, jpeg(75, 0, 1, 0, 65536), ext, CFG_ERR_INVALID);
  endtask

  task automatic reject_hdr;
    extension_t base, changed;
    jpeg_t basic;
    basic = jpeg(83, 1, 23, 222222, 3);
    base = hdr(64, 3, 50000000, 100000000, 1000000000);
    changed = base;
    changed[V2_HDR_MAX_DELTA_NS_LSB + 32] = 1;
    reject_request("delta_high_word", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_MAX_WAIT_NS_LSB +: V2_HDR_MAX_WAIT_NS_WIDTH] = '0;
    reject_request("wait_zero", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_MAX_AGE_NS_LSB +: V2_HDR_MAX_AGE_NS_WIDTH] = '0;
    reject_request("age_zero", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_BLACK_LONG_LSB +: V2_HDR_BLACK_LONG_WIDTH] = 51;
    reject_request("black_long_changed", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_BLACK_SHORT_LSB +: V2_HDR_BLACK_SHORT_WIDTH] = 49;
    reject_request("black_short_changed", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_RATIO_LSB +: V2_HDR_RATIO_WIDTH] = 3;
    reject_request("exposure_ratio_changed", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[V2_HDR_QUALIFICATION_LSB +: V2_HDR_QUALIFICATION_WIDTH] = 14;
    reject_request("qualification_changed", 0, basic, changed, CFG_ERR_INVALID);
    changed = base;
    changed[1023] = 1;
    reject_request("reserved_extension_bit", 0, basic, changed, CFG_ERR_INVALID);
    reject_request("dual_lane_with_multiscale", 1, basic, sdr(V2_LANE | V2_MULTISCALE, 0),
                   CFG_ERR_UNSUPPORTED);
  endtask

  task automatic fault_recovery;
    tuple_t offer;
    checkpoint = "source_fault_wins_over_boundary";
    $display("BEGIN [%s]", checkpoint);
    coordinated_boot(0);
    prepare_commit(jpeg(79, 1, 33, 195400, 14), hdr(64, 3, 50000000, 100000000, 1000000000),
                   0, offer);
    before_frame(offer, 0);
    @(negedge pixel_clk);
    pipeline_idle = 0;
    send_frame(32'hfd00_0001, 1, 1);
    expect_status(CFG_STS_ERROR, CFG_STS_BUSY | CFG_STS_READY | CFG_STS_APPLIED, 1);
    expect_bar(CFG_ERROR, CFG_ERR_RESET);
    expect_bar(CFG_RESPONSE_SEQUENCE, offer[31:0]);
    send_frame(32'hfd00_0002, 0, 0);
    check_pixel_active(published);
    check_user_active(published);
    $display("CHECK [%s] RESET retained previous epoch", checkpoint);
    coordinated_boot(0);
    legal("restart_first_legal_frame", jpeg(70, 0, 30, 0, 0), sdr(V2_DEHAZE, 1),
          32'h2a00_0029, 0);
  endtask

  initial begin
    if (!$value$plusargs("case=%s", scenario))
      $fatal(1, "Specify the public configuration scenario with +case=");
    checkpoint = scenario;
    case (scenario)
      "mono": begin
        coordinated_boot(0);
        legal("mono_HE_first_frame", jpeg(1, 0, 1, 0, 0), sdr(V2_HISTOGRAM, 0), 32'h101, 1);
        legal("mono_dehaze_generation_zero", jpeg(100, 1, 100, 16777216, 65535),
              sdr(V2_DEHAZE, 0), 32'h204, 0);
        legal("mono_HDR_documented_timers", jpeg(86, 1, 41, 638149, 37),
              hdr(64, 3, 50000000, 100000000, 1000000000), 32'h30b, 1);
        legal("mono_dehaze_generation_one", jpeg(72, 0, 31, 1, 8),
              sdr(V2_DEHAZE, 1), 32'h419, 0);
      end
      "dual": begin
        coordinated_boot(1);
        legal("dual_SDR_shared_first_frame", jpeg(84, 1, 27, 108901, 511),
              sdr(V2_HISTOGRAM | V2_DEHAZE, 1), 32'h1101, 1);
        legal("dual_HDR_minimum_motion_and_timers", jpeg(100, 1, 1, 1, 65535),
              hdr(0, 0, 0, 1, 1), 32'h2209, 0);
        legal("dual_HDR_maximum_motion_and_timers", jpeg(100, 1, 49, 16777216, 32768),
              hdr(16383, 15, 32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff), 32'h330f, 0);
      end
      "reject_basic": reject_basic();
      "reject_hdr": reject_hdr();
      "fault_recovery": fault_recovery();
      default: $fatal(1, "Unknown configuration scenario %s", scenario);
    endcase
    $display("BLACKBOX_PASS CFG_PARAMETERS %s time_ns=%0.0f", scenario, $realtime);
    $finish;
  end
endmodule
