`timescale 1ns/1ps

module tb_cfg_field;
  // Public BAR ABI: docs/pcie_protocol_v1.json and docs/s01_config_transaction.md.
  localparam [11:0] CFG_MAGIC=12'h200, CFG_ABI=12'h204, CFG_FEATURES=12'h208,
      CFG_PROFILE=12'h20c, CFG_PRESENT=12'h210, CFG_SESSION=12'h21c,
      REQ_SEQ=12'h220, REQ_SESSION=12'h224, REQ_MODE=12'h228, REQ_Q=12'h22c,
      REQ_FLAGS=12'h230, REQ_MIN_Q=12'h234, REQ_BUDGET=12'h238, REQ_RESTART=12'h23c,
      CFG_CMD=12'h240, CFG_STATUS=12'h244, RESP_SEQ=12'h248, CFG_ERROR=12'h24c,
      ACTIVE_MODE=12'h250, ACTIVE_Q=12'h254, CFG_EPOCH=12'h258,
      FIRST_SEQ=12'h25c, APPLIED_CAM=12'h260, ACTIVE_FLAGS=12'h264,
      ACTIVE_MIN_Q=12'h268, ACTIVE_BUDGET=12'h26c, ACTIVE_RESTART=12'h270,
      HOST_CAP=12'h274, ACTIVE_SESSION=12'h278,
      EXT_SCHEMAS=12'h39c, EXT_V2_MODES=12'h3a0, EXT_V2_ENABLES=12'h3a4,
      EXT_SHADOW=12'he00, EXT_ACTIVE=12'he80;
  localparam [31:0] BUSY=1, READY=2, APPLIED=4, ERROR=8, SESSION_READY=16;
  localparam [31:0] STATUS_BITS=BUSY|READY|APPLIED|ERROR|SESSION_READY;
  localparam [31:0] PREPARE_EXT=4, COMMIT=2, RESET_ERROR=6;
  localparam [31:0] SDR_REQUEST=32'h0000_0051, HDR_REQUEST=32'h0000_0052;
  localparam [31:0] SDR_FIRST=32'hfa10_007b, HDR_FIRST=32'h0000_0000;

  bit user_clk=0, pixel_clk=0;
  always #4 user_clk = ~user_clk;
  always #5 pixel_clk = ~pixel_clk;
  bit user_rst_n=0, pixel_rst_n=0, pipeline_idle=1, frame_accept=0;
  bit source_fault=0;
  bit [31:0] frame_sequence=0;
  bit write_valid=0, read_valid=0;
  bit [11:0] write_offset=0, read_offset=0;
  bit [31:0] write_data=0;
  wire [1:0] write_response, read_response;
  wire read_response_valid;
  wire [31:0] read_data;
  wire [31:0] user_session, source_session, mode_epoch;
  wire user_initialized, pixel_initialized, source_ready, pause_new_jobs;
  wire m_config_valid, s_config_ack_ready;
  wire [1183:0] m_config_data, active_config;
  bit m_config_ready=0, s_config_ack_valid=0, s_config_ack_ok=0;
  bit [1183:0] s_config_ack_data=0;
  wire active_schema2;
  wire [1:0] active_product_mode;
  wire [5:0] active_processing_enables;
  string scenario;
  logic [31:0] session_id, camera_present;
  logic [1183:0] predecessor;

  mono_config_service_v2 #(
    .PROFILE(1), .MAX_WIDTH(1920), .MAX_HEIGHT(1080), .REMOTE_CONFIG_ENABLE(1),
    .EXT_WIDTH(1024), .EXT_STRIPS(4), .EXT_COMBINATIONS(0), .EXT_SUPPORTED(8'h34),
    .V2_SUPPORTED_MODES(3'b101), .V2_SUPPORTED_ENABLES(6'h3f),
    .LIVE_GRAY_FIXED_ENABLE(0), .LIVE_BASIC_MODES_ENABLE(1),
    .COMPACT_EMPTY_EXTENSION_ENABLE(0), .COMPACT_STAGE2_EXTENSION_ENABLE(1),
    .LANE_GAUSSIAN_ONLY(1), .CFG_DIAG_ENABLE(0), .STEREO_CAPABLE(1)
`ifndef SEED92_CFG
    , .APPLY_SOURCE_FAULT_ENABLE(1)
`endif
  ) service (
    .user_clk(user_clk), .user_rst_n(user_rst_n), .i_stereo_mode(1'b1),
    .write_valid(write_valid), .write_offset(write_offset), .write_data(write_data),
    .write_strobes(4'hf), .write_response(write_response), .read_valid(read_valid),
    .read_offset(read_offset), .read_response(read_response), .read_data(read_data),
    .read_response_valid(read_response_valid), .user_session(user_session),
    .user_initialized(user_initialized),
    .pixel_clk(pixel_clk), .pixel_rst_n(pixel_rst_n), .pipeline_idle(pipeline_idle),
    .frame_accept(frame_accept), .frame_sequence(frame_sequence),
`ifndef SEED92_CFG
    .i_apply_source_fault(source_fault),
`endif
    .m_config_ready(m_config_ready), .m_config_valid(m_config_valid),
    .m_config_data(m_config_data), .s_config_ack_data(s_config_ack_data),
    .s_config_ack_valid(s_config_ack_valid), .s_config_ack_ok(s_config_ack_ok),
    .s_config_ack_ready(s_config_ack_ready), .source_ready(source_ready),
    .pause_new_jobs(pause_new_jobs), .pixel_initialized(pixel_initialized),
    .source_session(source_session), .mode_epoch(mode_epoch), .active_config(active_config),
    .active_schema2(active_schema2), .active_product_mode(active_product_mode),
    .active_processing_enables(active_processing_enables),
    .diag_observer_rst_n(2'b0), .diag_source_fs(1'b0), .diag_source_gates(16'b0)
  );

  function automatic [1023:0] schema2(input bit hdr);
    logic [1023:0] extension;
    begin
      extension = '0;
      extension[0 +: 8] = 8'd2;
      extension[8 +: 2] = hdr ? 2'd2 : 2'd0;
      extension[10 +: 6] = hdr ? 6'd0 : 6'd2;
      if (hdr) begin
        extension[64 +: 3] = 3'd4;
        extension[67 +: 10] = 10'd50;
        extension[77 +: 10] = 10'd50;
        extension[87 +: 14] = 14'd64;
        extension[101 +: 4] = 4'd3;
        extension[105 +: 4] = 4'd15;
        extension[128 +: 64] = 64'd50000000;
        extension[192 +: 32] = 32'd100000000;
        extension[224 +: 32] = 32'd1000000000;
      end
      return extension;
    end
  endfunction

  task automatic require_true(input logic cond, input string note);
    if (cond !== 1'b1) begin
      $display("BB_FAIL cfg %s %s", scenario, note);
      $fatal(1, "%s", note);
    end
  endtask

  task automatic wr(input logic [11:0] address, input logic [31:0] value);
    @(negedge user_clk);
    write_valid=1; write_offset=address; write_data=value;
    @(posedge user_clk);
    require_true(write_response === 2'b00,
                 $sformatf("BAR write @%03h data=%08h response=%b", address, value, write_response));
    @(negedge user_clk);
    write_valid=0;
  endtask

  task automatic rd(input logic [11:0] address, output logic [31:0] value);
    bit got;
    got=0;
    @(negedge user_clk);
    read_valid=1; read_offset=address;
    @(posedge user_clk); #1;
    if (read_response_valid === 1'b1) begin
      require_true(read_response === 2'b00,
                   $sformatf("BAR read @%03h response=%b", address, read_response));
      value=read_data; got=1;
    end
    @(negedge user_clk); read_valid=0;
    for (int i=0; i<32 && !got; i++) begin
      @(posedge user_clk); #1;
      if (read_response_valid === 1'b1) begin
        require_true(read_response === 2'b00,
                     $sformatf("BAR read @%03h response=%b", address, read_response));
        value=read_data; got=1;
      end
    end
    require_true(got, $sformatf("BAR read @%03h timed out", address));
  endtask

  task automatic eq_bar(input logic [11:0] address, input logic [31:0] expected);
    logic [31:0] actual;
    rd(address, actual);
    require_true(actual === expected,
                 $sformatf("BAR @%03h expected=%08h actual=%08h", address, expected, actual));
  endtask

  task automatic poll_status(input logic [31:0] mask, expected, input string phase);
    logic [31:0] status, err, seq;
    bit got;
    got=0;
    for (int i=0; i<512 && !got; i++) begin
      rd(CFG_STATUS, status);
      got=(status & mask) === expected;
      if (!got && ((status & ERROR) != 0 || (status & APPLIED) != 0) &&
          ((expected & BUSY) != 0 || (expected & (APPLIED|ERROR)) != 0)) begin
        // An old APPLIED is allowed only if preparing a new owned transaction.
        // PREPARE polling starts after its write, so any terminal here is wrong.
        rd(CFG_ERROR, err); rd(RESP_SEQ, seq);
        require_true(0, $sformatf("%s unexpected terminal status=%08h error=%0d response=%08h",
                                  phase,status,err,seq));
      end
    end
    if (!got) begin
      rd(CFG_ERROR, err); rd(RESP_SEQ, seq);
      require_true(0, $sformatf("%s deadline status=%08h error=%0d response=%08h",
                                phase,status,err,seq));
    end
  endtask

  task automatic take_offer(output logic [1183:0] tuple_data, input string phase);
    bit got;
    got=0;
    for (int i=0; i<1024 && !got; i++) begin
      @(negedge pixel_clk);
      got=m_config_valid === 1'b1;
    end
    require_true(got, $sformatf("%s no digital request", phase));
    tuple_data=m_config_data;
    require_true(!$isunknown(tuple_data), $sformatf("%s unknown digital request bits",phase));
    repeat (4) begin
      @(posedge pixel_clk);
      require_true(m_config_valid && m_config_data === tuple_data,
                   $sformatf("%s digital offer changed with READY low", phase));
    end
    @(negedge pixel_clk); m_config_ready=1;
    @(posedge pixel_clk);
    require_true(m_config_valid && m_config_data === tuple_data,
                 $sformatf("%s digital offer missing on handshake", phase));
    @(negedge pixel_clk); m_config_ready=0;
  endtask

  task automatic ack_offer(input logic [1183:0] tuple_data, input string phase);
    bit got;
    @(negedge pixel_clk);
    s_config_ack_valid=1; s_config_ack_data=tuple_data; s_config_ack_ok=1;
    got=0;
    for (int i=0; i<1024 && !got; i++) begin
      @(posedge pixel_clk);
      got=s_config_ack_ready === 1'b1;
    end
    require_true(got, $sformatf("%s digital ACK was not accepted", phase));
    @(negedge pixel_clk); s_config_ack_valid=0; s_config_ack_ok=0;
  endtask

  task automatic wait_source(input string phase);
    bit got;
    got=0;
    for (int i=0; i<1024 && !got; i++) begin
      @(negedge pixel_clk);
      got=source_ready === 1'b1 && pause_new_jobs === 1'b0 && pipeline_idle;
    end
    require_true(got, $sformatf("%s source never admitted", phase));
  endtask

  task automatic frame_pulse(input logic [31:0] seq, input bit legal);
    @(negedge pixel_clk);
    require_true((source_ready && !pause_new_jobs && pipeline_idle) === legal,
                 $sformatf("frame offer legality=%b ready=%b pause=%b idle=%b",
                           legal, source_ready,pause_new_jobs,pipeline_idle));
    frame_sequence=seq; frame_accept=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk); frame_accept=0;
  endtask

  task automatic boot;
    logic [1183:0] tuple_data;
    logic [31:0] advertised;
    @(negedge user_clk); user_rst_n=0;
    @(negedge pixel_clk);
    pixel_rst_n=0; pipeline_idle=1; frame_accept=0; frame_sequence=0;
    source_fault=0; m_config_ready=0; s_config_ack_valid=0; s_config_ack_ok=0;
    repeat (12) @(negedge pixel_clk);
    pixel_rst_n=1;
    @(negedge user_clk); user_rst_n=1;
    take_offer(tuple_data, "BOOT");
    ack_offer(tuple_data, "BOOT");
    poll_status(STATUS_BITS, SESSION_READY, "BOOT");
    eq_bar(CFG_MAGIC, 32'h31474643);
    eq_bar(CFG_ABI, 1);
    // PROFILE=1 is the elaboration base; the stereo runtime advertises DUAL1920.
    eq_bar(CFG_PROFILE, 2);
    rd(CFG_PRESENT, camera_present);
    require_true((camera_present & 32'h1) != 0, "primary camera absent");
    rd(CFG_SESSION, session_id);
    require_true(!$isunknown(session_id) && session_id != 0 &&
                 session_id === source_session && session_id === user_session,
                 "BOOT session mismatch across BAR, USER and PIX");
    require_true(user_initialized && pixel_initialized, "BOOT initialization incomplete");
    eq_bar(ACTIVE_SESSION, session_id);
    eq_bar(CFG_EPOCH, 0);
    rd(CFG_FEATURES, advertised);
    require_true(advertised[0], "FRAME_APPLIED not advertised");
    eq_bar(EXT_SCHEMAS, 6);
    eq_bar(EXT_V2_MODES, 5);
    eq_bar(EXT_V2_ENABLES, 15);  // Stereo excludes the two mono-only image lanes.
    wr(HOST_CAP, 1);
    $display("BB_CHECK cfg BOOT session=%08h",session_id);
  endtask

  task automatic write_recipe(input logic [31:0] req, input bit hdr);
    logic [1023:0] extension;
    extension=schema2(hdr);
    wr(REQ_SEQ, req); wr(REQ_SESSION, session_id); wr(REQ_MODE, 0); wr(REQ_Q, 75);
    wr(REQ_FLAGS, 0); wr(REQ_MIN_Q, 1); wr(REQ_BUDGET, 0); wr(REQ_RESTART, 0);
    for (int i=0; i<32; i++) wr(EXT_SHADOW + 12'(4*i), extension[32*i +: 32]);
    wr(CFG_CMD, PREPARE_EXT);
  endtask

  task automatic check_active(input bit hdr, input logic [31:0] expected_epoch);
    logic [1023:0] extension;
    extension=schema2(hdr);
    eq_bar(CFG_SESSION, session_id); eq_bar(ACTIVE_SESSION, session_id);
    eq_bar(ACTIVE_MODE, 0); eq_bar(ACTIVE_Q, 75); eq_bar(ACTIVE_FLAGS, 0);
    eq_bar(ACTIVE_MIN_Q, 1); eq_bar(ACTIVE_BUDGET, 0); eq_bar(ACTIVE_RESTART, 0);
    eq_bar(CFG_EPOCH, expected_epoch);
    for (int i=0; i<32; i++) eq_bar(EXT_ACTIVE + 12'(4*i), extension[32*i +: 32]);
    require_true(mode_epoch === expected_epoch && active_schema2 &&
                 active_product_mode === (hdr ? 2'd2 : 2'd0) &&
                 active_processing_enables === (hdr ? 6'd0 : 6'd2),
                 "PIX ACTIVE epoch/product/enables differ from transaction");
  endtask

  task automatic check_applied(input logic [31:0] req, first, epoch, input bit hdr);
    logic [31:0] camera;
    poll_status(STATUS_BITS, SESSION_READY|APPLIED, "APPLIED");
    eq_bar(RESP_SEQ, req); eq_bar(CFG_ERROR, 0); eq_bar(FIRST_SEQ, first);
    rd(APPLIED_CAM, camera);
    require_true(!$isunknown(camera) && camera < 32 && camera_present[camera],
                 $sformatf("APPLIED camera %0d not present", camera));
    check_active(hdr, epoch);
    $display("BB_CHECK cfg APPLIED request=%08h epoch=%0d frame=%08h product=%0d enables=%0d",
             req,epoch,first,active_product_mode,active_processing_enables);
  endtask

  task automatic check_pending(input bit pre_ready, input string phase);
    logic [31:0] status;
    logic [31:0] mask;
    mask=BUSY|APPLIED|ERROR|SESSION_READY;
    if (pre_ready) mask=mask|READY;
    rd(CFG_STATUS, status);
    require_true((status & mask) === (SESSION_READY|BUSY),
                 $sformatf("%s premature transition, status=%08h", phase,status));
    require_true(active_config === predecessor && mode_epoch === 1,
                 $sformatf("%s prematurely changed PIX ACTIVE", phase));
    eq_bar(CFG_EPOCH, 1);
    eq_bar(EXT_ACTIVE, 32'h0000_0802);
  endtask

  task automatic apply_sdr;
    logic [1183:0] tuple_data;
    write_recipe(SDR_REQUEST, 0);
    poll_status(STATUS_BITS, SESSION_READY|BUSY|READY, "SDR PREPARE");
    eq_bar(RESP_SEQ, SDR_REQUEST);
    wr(CFG_CMD, COMMIT);
    take_offer(tuple_data, "SDR COMMIT");
    ack_offer(tuple_data, "SDR COMMIT");
    wait_source("SDR digital ACK");
    frame_pulse(SDR_FIRST, 1);
    check_applied(SDR_REQUEST, SDR_FIRST, 1, 0);
    predecessor=active_config;
  endtask

  task automatic apply_hdr(input bit fail_source, fault_same_edge);
    logic [1183:0] tuple_data;
    bit paused;
    @(negedge pixel_clk); pipeline_idle=0;
    write_recipe(HDR_REQUEST, 1);
    paused=0;
    for (int i=0; i<1024 && !paused; i++) begin
      @(negedge pixel_clk);
      paused=pause_new_jobs === 1'b1;
    end
    require_true(paused, "HDR PREPARE did not pause admission");
    repeat (8) begin
      check_pending(1, "HDR old work not drained");
      require_true(pause_new_jobs, "HDR PREPARE released new jobs before drain");
    end
    @(negedge pixel_clk); pipeline_idle=1;
    poll_status(STATUS_BITS, SESSION_READY|BUSY|READY, "HDR PREPARE after drain");
    eq_bar(RESP_SEQ, HDR_REQUEST);
    wr(CFG_CMD, COMMIT);
    take_offer(tuple_data, "HDR COMMIT");
    repeat (3) begin
      require_true(!source_ready && pause_new_jobs, "HDR source eligibility rose before digital ACK");
      frame_pulse(32'hfeed_0001, 0); // Adversarial: no digital ACK yet.
      check_pending(0, "HDR digital ACK withheld");
    end
    ack_offer(tuple_data, "HDR COMMIT");
    wait_source("HDR digital ACK");
    repeat (3) check_pending(0, "HDR digital ACK without real frame");

    if (!fail_source) begin
      frame_pulse(HDR_FIRST, 1);
      check_applied(HDR_REQUEST, HDR_FIRST, 2, 1);
    end else begin
      @(negedge pixel_clk);
      require_true(source_ready && !pause_new_jobs && pipeline_idle,
                   "fault case never armed first-frame admission");
      source_fault=1;
      frame_sequence=HDR_FIRST; frame_accept=fault_same_edge;
      @(posedge pixel_clk);
      @(negedge pixel_clk); frame_accept=0;
      poll_status(STATUS_BITS, SESSION_READY|ERROR,
                  fault_same_edge ? "HDR fault with simultaneous frame" : "HDR fault without frame");
      eq_bar(RESP_SEQ, HDR_REQUEST); eq_bar(CFG_ERROR, RESET_ERROR);
      check_active(0, 1);
      require_true(active_config === predecessor, "source failure changed the prior PIX tuple");
      repeat (128) begin
        @(negedge pixel_clk);
        require_true(!source_ready && !m_config_valid,
                     "terminal source failure allowed admission or retried without reset");
      end
      eq_bar(CFG_STATUS, SESSION_READY|ERROR);
      $display("BB_CHECK cfg SOURCE_ERROR request=%08h same_edge=%b epoch=%0d",
               HDR_REQUEST,fault_same_edge,mode_epoch);
    end
  endtask

  initial begin
    if (!$value$plusargs("CASE=%s",scenario)) scenario="cfg-positive";
    require_true(scenario == "cfg-positive" || scenario == "cfg-fault" ||
                 scenario == "cfg-same-edge", "unknown scenario");
    boot();
    apply_sdr();
    apply_hdr(scenario != "cfg-positive", scenario == "cfg-same-edge");
    if (scenario != "cfg-positive") begin
      boot();
      apply_sdr();
      $display("BB_CHECK cfg fresh reset reached real SDR APPLIED");
    end
    $display("BB_PASS cfg %s", scenario);
    $finish;
  end
  initial begin
    #500000;
    require_true(0, "simulation watchdog");
  end
endmodule
