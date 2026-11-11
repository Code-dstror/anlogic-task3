`timescale 1ns/1ps

// Independent stimulus and scoreboard. Every observation is a public port.
module adapter_tb;
  localparam int LINE_GROUPS = 1920 / 4;
  localparam int FRAME_GROUPS = LINE_GROUPS * 1080;
  localparam int WAIT_CYCLES = 96;

  logic clk = 0, run_clk = 1, rst_n = 1;
  always #4 if (run_clk) clk = ~clk;

  logic [575:0] s_context = 0;
  logic s_context_valid = 0;
  wire s_context_ready;
  logic [95:0] s_rgb = 0;
  logic s_valid = 0, s_sof = 0, s_eol = 0;
  wire s_ready;
  logic i_cancel = 0, i_pipeline_error = 0;
  logic i_pipeline_quiescent = 0, i_source_read_quiescent = 0;
  logic i_source_status_valid = 0, i_source_status_ok = 0;
  logic [63:0] i_source_status_tag = 0;
  logic [7:0] i_source_status_error = 0;
  wire o_source_status_ready;
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
  wire [63:0] m_status_tag;
  wire [7:0] m_status_error;
  wire [31:0] m_status_groups;
  wire o_read_quiescent, o_busy, o_cancel_request;
  wire [31:0] o_input_groups, o_output_groups, o_stale_status_count;

  camera_rgb_native_fixed1080_borrow4 #(.MAX_WIDTH(1920), .MAX_HEIGHT(1080)) dut (.*);

  string scenario;
  bit live, source_seen;
  int unsigned inputs_seen, outputs_seen, input_contexts, output_contexts, terminals;
  int unsigned out_limit;
  int malformed_at;
  bit invert_sof, invert_eol;
  logic [23:0] salt;
  logic [63:0] owner_tag;
  logic [575:0] owner_context;
  bit rgb_held, context_held, status_held;
  logic [198:0] held_rgb;
  logic [575:0] held_context;
  logic [104:0] held_status;
  wire [198:0] rgb_tuple = {m_rgb, m_keep, m_sof, m_eol, m_last, m_tag, m_index};
  wire [104:0] status_tuple = {m_status_tag, m_status_ok, m_status_error, m_status_groups};

  function automatic logic [95:0] pixel_pattern(input int unsigned g, input logic [23:0] key);
    logic [23:0] base;
    base = 24'(24'h34b6d7 * (g+1)) ^ key;
    return {base ^ 24'h924ba5, base ^ 24'h39c716, base ^ 24'h118efd, base};
  endfunction

  function automatic bit raster_sof(input int g);
    return (g == 0) ^ (invert_sof && g == malformed_at);
  endfunction

  function automatic bit raster_eol(input int g);
    return (g % LINE_GROUPS == LINE_GROUPS - 1) ^ (invert_eol && g == malformed_at);
  endfunction

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      live = 0;
      rgb_held = 0;
      context_held = 0;
      status_held = 0;
    end else begin
      if (rgb_held && (m_valid !== 1'b1 || rgb_tuple !== held_rgb))
        $fatal(1, "held RGB was withdrawn or changed at accepted output %0d", outputs_seen);
      if (context_held && (m_context_valid !== 1'b1 || m_context !== held_context))
        $fatal(1, "held context was withdrawn or changed");
      if (status_held && (m_status_valid !== 1'b1 || status_tuple !== held_status))
        $fatal(1, "held terminal was withdrawn or changed");

      if (s_context_valid && s_context_ready) begin
        input_contexts++;
        if (!live || input_contexts != 1)
          $fatal(1, "context accepted more than once in one owner lifetime");
      end
      if (live && input_contexts == 1 && !s_context_valid && s_context_ready)
        $fatal(1, "second context advertised before terminal consumption");
      if (m_context_valid) begin
        if (!live || input_contexts != 1 || output_contexts != 0 || m_context !== owner_context)
          $fatal(1, "unexpected, duplicated or changed published context");
        if (m_context_ready) output_contexts++;
      end

      if (s_valid && s_ready) inputs_seen++;
      if (m_valid) begin
        if (!live || outputs_seen >= inputs_seen || outputs_seen >= out_limit ||
            m_index !== 32'(outputs_seen) || m_tag !== owner_tag || m_keep !== 4'hf ||
            m_sof !== raster_sof(outputs_seen) || m_eol !== raster_eol(outputs_seen) ||
            m_last !== (outputs_seen == FRAME_GROUPS - 1) ||
            m_rgb !== pixel_pattern(outputs_seen, salt))
          $fatal(1, "RGB mismatch/unexpected offer: in=%0d out=%0d limit=%0d index=%0d tag=%h sideband=%b%b%b/%h rgb=%h",
                 inputs_seen, outputs_seen, out_limit, m_index, m_tag, m_sof, m_eol, m_last, m_keep, m_rgb);
        if (m_ready) outputs_seen++;
      end

      if (live && i_source_status_valid && o_source_status_ready && i_source_status_tag === owner_tag)
        source_seen = 1;
      if (o_read_quiescent !== m_status_valid)
        $fatal(1, "adapter read-quiescent disagrees with terminal VALID");
      if (m_status_valid) begin
        if (!live || !source_seen || !i_pipeline_quiescent || !i_source_read_quiescent ||
            s_valid || (m_valid && !m_ready) || output_contexts != 1 || terminals != 0 ||
            m_status_tag !== owner_tag || m_status_groups !== 32'(outputs_seen))
          $fatal(1, "premature/duplicate/wrong terminal: source=%b quiet=%b%b context=%0d rgb=%0d status=%h",
                 source_seen, i_pipeline_quiescent, i_source_read_quiescent,
                 output_contexts, outputs_seen, status_tuple);
        if (m_status_ready) begin
          terminals++;
          live = 0;
        end
      end
      rgb_held = m_valid && !m_ready;
      context_held = m_context_valid && !m_context_ready;
      status_held = m_status_valid && !m_status_ready;
      if (rgb_held) held_rgb = rgb_tuple;
      if (context_held) held_context = m_context;
      if (status_held) held_status = status_tuple;
    end
  end

  task automatic reset_adapter(input bit stop_clock);
    // Enter at a falling edge, or before the first edge for initial reset.
    if (stop_clock) run_clk = 0;
    #1 rst_n = 0;
    #2;
    if (m_valid !== 1'b0 || m_status_valid !== 1'b0 || m_context_valid !== 1'b0)
      $fatal(1, "asynchronous reset left public VALID asserted (stopped clock=%b)", stop_clock);
    s_valid = 0;
    s_context_valid = 0;
    i_source_status_valid = 0;
    i_cancel = 0;
    i_pipeline_error = 0;
    i_pipeline_quiescent = 0;
    i_source_read_quiescent = 0;
    m_context_ready = 1;
    m_ready = 1;
    m_status_ready = 0;
    #16 rst_n = 1;
    #2;
    if (stop_clock) begin
      if (m_valid !== 1'b0 || m_status_valid !== 1'b0 || m_context_valid !== 1'b0)
        $fatal(1, "VALID reappeared when reset released with clock stopped");
      run_clk = 1;
    end
    repeat (4) @(negedge clk);
    if (o_busy !== 1'b0) $fatal(1, "reset did not release owner");
  endtask

  task automatic begin_owner(input logic [63:0] tag, input logic [23:0] pattern_key,
                             input bit stall_context);
    if (live) $fatal(1, "fixture started an owner while its prior terminal was live");
    owner_tag = tag;
    salt = pattern_key;
    owner_context = {576{1'b0}};
    for (int word_index = 0; word_index < 9; word_index++)
      owner_context[word_index*64 +: 64] = tag ^ (64'h23653216838b3bb9 * (word_index+1));
    owner_context[447:384] = tag;
    owner_context[220:205] = 16'd1920;
    owner_context[236:221] = 16'd1080;
    input_contexts = 0;
    output_contexts = 0;
    inputs_seen = 0;
    outputs_seen = 0;
    terminals = 0;
    source_seen = 0;
    malformed_at = -1;
    invert_sof = 0;
    invert_eol = 0;
    out_limit = FRAME_GROUPS;
    i_pipeline_quiescent = 0;
    i_source_read_quiescent = 0;
    m_context_ready = !stall_context;
    live = 1;
    s_context = owner_context;
    s_context_valid = 1;
    for (int t = 0; t < WAIT_CYCLES; t++) begin
      @(negedge clk);
      if (input_contexts == 1) break;
    end
    if (input_contexts != 1 || o_busy !== 1'b1)
      $fatal(1, "initial context not borrowed");
    s_context_valid = 0; // Keep the entire payload stable through the status handshake.
  endtask

  task automatic wait_context_offer;
    for (int t = 0; t < WAIT_CYCLES && m_context_valid !== 1'b1; t++) @(negedge clk);
    if (m_context_valid !== 1'b1) $fatal(1, "no context offer");
  endtask

  task automatic wait_context_consumed;
    for (int t = 0; t < WAIT_CYCLES && output_contexts != 1; t++) @(negedge clk);
    if (output_contexts != 1) $fatal(1, "context was not transferred");
  endtask

  task automatic send_group(input int g);
    s_rgb = pixel_pattern(g, salt);
    s_sof = raster_sof(g);
    s_eol = raster_eol(g);
    s_valid = 1;
    for (int t = 0; t < WAIT_CYCLES; t++) begin
      @(posedge clk);
      if (s_ready === 1'b1) begin
        @(negedge clk);
        s_valid = 0;
        return;
      end
    end
    $fatal(1, "no input handshake for group %0d", g);
  endtask

  task automatic wait_outputs(input int expected);
    for (int t = 0; t < WAIT_CYCLES && outputs_seen != expected; t++) @(negedge clk);
    if (outputs_seen != expected)
      $fatal(1, "RGB drain expected %0d handshakes, observed %0d", expected, outputs_seen);
  endtask

  task automatic wait_rgb_offer;
    for (int t = 0; t < WAIT_CYCLES && m_valid !== 1'b1; t++) @(negedge clk);
    if (m_valid !== 1'b1) $fatal(1, "no RGB offer under stall");
  endtask

  task automatic send_source(input logic [63:0] tag, input bit ok, input logic [7:0] code,
                             input bit stale, input bit cancel_also, input bit pipe_also);
    logic [31:0] prior_count;
    prior_count = o_stale_status_count;
    i_source_status_tag = tag;
    i_source_status_ok = ok;
    i_source_status_error = code;
    i_source_status_valid = 1;
    for (int t = 0; t < WAIT_CYCLES; t++) begin
      #1;
      // Assert faults for the edge with READY, so simultaneous-priority tests
      // do not silently become an earlier fault followed by SOURCE.
      i_cancel = cancel_also && (o_source_status_ready === 1'b1);
      i_pipeline_error = pipe_also && (o_source_status_ready === 1'b1);
      @(posedge clk);
      if (o_source_status_ready === 1'b1) begin
        if (i_cancel != cancel_also || i_pipeline_error != pipe_also)
          $fatal(1, "fixture did not place faults on the SOURCE acceptance edge");
        @(negedge clk);
        i_source_status_valid = 0;
        i_cancel = 0;
        i_pipeline_error = 0;
        // Leave one additional sampled cycle for the public counter update.
        @(negedge clk);
        if (o_stale_status_count !== prior_count + (stale ? 32'd1 : 32'd0))
          $fatal(1, "SOURCE stale count: previous=%0d current=%0d expected delta=%0d for tag=%h",
                 prior_count, o_stale_status_count, stale, tag);
        return;
      end
      @(negedge clk);
    end
    $fatal(1, "SOURCE offer not accepted tag=%h stale=%b", tag, stale);
  endtask

  task automatic wait_terminal(input bit ok, input logic [7:0] code);
    for (int t = 0; t < WAIT_CYCLES && m_status_valid !== 1'b1; t++) @(negedge clk);
    if (m_status_valid !== 1'b1)
      $fatal(1, "terminal missing: in=%0d out=%0d SOURCE accepted=%b", inputs_seen, outputs_seen, source_seen);
    if (m_status_ok !== ok || m_status_error !== code || m_status_groups !== 32'(outputs_seen))
      $fatal(1, "terminal result: expected ok=%b code=%0d groups=%0d, got ok=%b code=%0d groups=%0d",
             ok, code, outputs_seen, m_status_ok, m_status_error, m_status_groups);
    if (o_input_groups !== 32'(inputs_seen) || o_output_groups !== 32'(outputs_seen))
      $fatal(1, "public counts differ from handshakes: expected %0d/%0d got %0d/%0d",
             inputs_seen, outputs_seen, o_input_groups, o_output_groups);
    repeat (4) @(negedge clk);
  endtask

  task automatic consume_terminal;
    m_status_ready = 1;
    @(negedge clk);
    m_status_ready = 0;
    for (int t = 0; t < WAIT_CYCLES && o_busy !== 1'b0; t++) @(negedge clk);
    if (terminals != 1 || o_busy !== 1'b0 || m_status_valid !== 1'b0)
      $fatal(1, "terminal did not retire exactly one owner");
    repeat (3) @(negedge clk);
  endtask

  task automatic both_quiet;
    i_pipeline_quiescent = 1;
    i_source_read_quiescent = 1;
  endtask

  task automatic clean_prefix(input logic [63:0] tag, input logic [23:0] pattern_key);
    begin_owner(tag, pattern_key, 0);
    wait_context_consumed();
    for (int g = 0; g < 8; g++) send_group(g);
    wait_outputs(8);
    send_source(tag, 1, 0, 0, 0, 0);
    both_quiet();
    wait_terminal(0, 5);
    consume_terminal();
  endtask

  task automatic first_raster;
    m_ready = 0;
    begin_owner(64'h1234bcb500db17a1, 24'h29f9b0, 1);
    wait_context_offer();
    fork
      send_group(0);
      begin
        repeat (7) @(negedge clk);
        m_context_ready = 1;
        wait_context_consumed();
      end
    join
    wait_rgb_offer();
    repeat (4) @(negedge clk);
    m_ready = 1;
    for (int g = 1; g < FRAME_GROUPS; g++) begin
      if (g == LINE_GROUPS - 1 || g == FRAME_GROUPS - 1) begin
        wait_outputs(g);
        m_ready = 0;
        send_group(g);
        wait_rgb_offer();
        repeat (5) @(negedge clk);
        m_ready = 1;
      end else send_group(g);
    end
    wait_outputs(FRAME_GROUPS);
    both_quiet();
    repeat (8) @(negedge clk); // An accepted LAST cannot substitute for SOURCE.
    i_source_read_quiescent = 0;
    send_source(owner_tag, 1, 0, 0, 0, 0);
    repeat (8) @(negedge clk); // Matching SOURCE cannot substitute for reader drain.
    i_source_read_quiescent = 1;
    wait_terminal(1, 0);
    consume_terminal();
    $display("RASTER groups=%0d lines=%0d terminal_error=0", outputs_seen, 1080);
  endtask

  task automatic cancel_prefix(input int held_at);
    begin_owner(64'h818adaf37538bef1 + 64'(held_at), 24'h44bc78, 0);
    wait_context_consumed();
    for (int g = 0; g < held_at; g++) send_group(g);
    wait_outputs(held_at);
    m_ready = 0;
    send_group(held_at);
    wait_rgb_offer();
    repeat (3) @(negedge clk);
    out_limit = held_at + 1;
    i_cancel = 1;
    @(negedge clk);
    i_cancel = 0;
    repeat (5) @(negedge clk);
    m_ready = 1;
    for (int g = held_at + 1; g < 8; g++) send_group(g);
    wait_outputs(held_at + 1);
    send_source(owner_tag, 0, 8'h9e, 0, 0, 0);
    both_quiet();
    wait_terminal(0, 3);
    consume_terminal();
    $display("CANCEL held_at=%0d accepted_rgb=%0d accepted_input=%0d", held_at, outputs_seen, inputs_seen);
    clean_prefix(64'ha064d76de613d228 + 64'(held_at), 24'hce86ae);
  endtask

  task automatic reset_case(input string stall_point, input bit stop_clock);
    begin_owner(64'h9844590d802937c6, 24'h8ce167, stall_point == "context");
    if (stall_point == "context") wait_context_offer();
    else begin
      wait_context_consumed();
      if (stall_point == "rgb") begin
        m_ready = 0;
        send_group(0);
        wait_rgb_offer();
      end else begin
        for (int g = 0; g < 8; g++) send_group(g);
        wait_outputs(8);
        send_source(owner_tag, 1, 0, 0, 0, 0);
        both_quiet();
        wait_terminal(0, 5);
      end
    end
    repeat (3) @(negedge clk);
    reset_adapter(stop_clock);
    clean_prefix(64'hf192a4da0e02989a, 24'hb4a3dd);
    $display("RESET stalled=%s stopped=%b recovery_groups=%0d", stall_point, stop_clock, outputs_seen);
  endtask

  task automatic bad_raster(input bit extra_sof);
    begin_owner(64'hd87418a1c49157b1 + 64'(extra_sof), 24'hd9bca0, 0);
    wait_context_consumed();
    malformed_at = 4;
    invert_sof = extra_sof;
    invert_eol = !extra_sof;
    for (int g = 0; g < malformed_at; g++) send_group(g);
    wait_outputs(malformed_at);
    send_group(malformed_at);
    send_source(owner_tag, 1, 0, 0, 0, 0);
    both_quiet();
    wait_terminal(0, 2);
    consume_terminal();
    $display("MALFORMED extra_sof=%b accepted_rgb=%0d", extra_sof, outputs_seen);
  endtask

  task automatic source_identity;
    logic [63:0] prior_tag, current_tag;
    prior_tag = 64'hb380111a021f653c;
    current_tag = prior_tag ^ 64'h0004000000000000; // Identical low half, different upper tag bit.
    clean_prefix(prior_tag, 24'h889320);
    begin_owner(current_tag, 24'h298b4e, 0);
    wait_context_consumed();
    for (int g = 0; g < 4; g++) send_group(g);
    wait_outputs(4);
    both_quiet();
    send_source(prior_tag, 0, 8'hd7, 1, 0, 0);
    repeat (7) @(negedge clk);
    // A matching positive SOURCE may precede the last RGB input. Keep the
    // pipeline non-quiescent until the remaining offered groups transfer.
    i_pipeline_quiescent = 0;
    send_source(current_tag, 1, 0, 0, 0, 0);
    send_source(current_tag, 0, 8'h98, 1, 0, 0);
    for (int g = 4; g < 8; g++) send_group(g);
    wait_outputs(8);
    both_quiet();
    wait_terminal(0, 5);
    consume_terminal();
    $display("SOURCE_IDENTITY previous_owner_stale=1 duplicate_stale=1 accepted_rgb=%0d", outputs_seen);
  endtask

  task automatic failed_source(input bit ok, input logic [7:0] code,
                               input bit cancel_also, input bit pipe_also,
                               input logic [7:0] expected);
    begin_owner(64'hb97d1538e164a050 ^ 64'(expected), 24'h8f4b1a ^ 24'(expected), 0);
    wait_context_consumed();
    for (int g = 0; g < 8; g++) send_group(g);
    wait_outputs(8);
    send_source(owner_tag, ok, code, 0, cancel_also, pipe_also);
    both_quiet();
    wait_terminal(0, expected);
    consume_terminal();
    $display("SOURCE_FAILURE ok=%b source_error=%0d cancel=%b pipeline=%b terminal_error=%0d",
             ok, code, cancel_also, pipe_also, expected);
  endtask

  initial begin
    if (!$value$plusargs("CASE=%s", scenario)) $fatal(1, "missing +CASE");
    reset_adapter(0);
    case (scenario)
      "first_raster": first_raster();
      "cancel_first": cancel_prefix(0);
      "cancel_middle": cancel_prefix(3);
      "reset_context": reset_case("context", 0);
      "reset_output": reset_case("rgb", 0);
      "reset_status": reset_case("terminal", 0);
      "stopped_clock": reset_case("rgb", 1);
      "malformed": begin
        bad_raster(0);
        bad_raster(1);
        clean_prefix(64'h126e920f3c62042c, 24'ha88c5d);
      end
      "source_identity": source_identity();
      "source_fault": begin
        failed_source(0, 8'h00, 0, 0, 8'd6);
        failed_source(1, 8'ha6, 0, 0, 8'ha6);
        failed_source(0, 8'h9d, 0, 1, 8'd4);
        failed_source(0, 8'h8d, 1, 1, 8'd3);
        clean_prefix(64'h48b53ef9541a61f6, 24'hf17c42);
      end
      default: $fatal(1, "unknown +CASE %s", scenario);
    endcase
    $display("PASS adapter %s", scenario);
    $finish;
  end

  initial begin
    if (!$test$plusargs("CASE=first_raster")) begin
      #50_000;
      $fatal(1, "short scenario simulator watchdog");
    end else begin
      #10_000_000;
      $fatal(1, "one raster simulator watchdog");
    end
  end
endmodule
