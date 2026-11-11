`timescale 1ns/1ps

module tb_cam_field;
  localparam int SDR_WRITES=203, HDR_WRITES=139, QUALIFIED_PAIRS=8;
  localparam int RECIPE_DEADLINE=300000, PHY_DEADLINE=80000;
  bit cfg_clk=0, pixel_clk=0, ref_clk=0, sensor_clk=0, hdr_mclk=0, word_clk=0;
  bit word_enable=1, reset_n=0, clock_locked=1;
  bit hdr_request=0, mode_quiet=1, pair_event=0, pair_ok=0;
  always #20 cfg_clk = ~cfg_clk;
  always #4 pixel_clk = ~pixel_clk;
  always #4.125 ref_clk = ~ref_clk;
  always #20.833 sensor_clk = ~sensor_clk;
  always #18.519 hdr_mclk = ~hdr_mclk;
  always #5.5 word_clk = word_enable ? ~word_clk : 1'b0;

  wire cam_scl, cam_mclk, cam_xclr;
  tri1 cam_sda;
  bit slave_ack=0;
  assign cam_sda = slave_ack ? 1'b0 : 1'bz;
  wire sdr_30_mode, hdr_mode, mode_running, hdr_stable;
  wire config_done, config_error, phy_ready, delay_ready, receive_fault, identity_fault;
  string scenario;

  sdr_camera_raw_frontend #(
    .WIDTH(1920), .HEIGHT(1080), .FIRST_ROW(16), .FIRST_GROUP(1),
    .RUNTIME_GAIN_ENABLE(1), .SDR_RATE_CONTROL_ENABLE(1), .EVENT_FIFO_DEPTH(512),
    .CONFIG_WAIT_CYCLES(8), .SDR_WAKE_CYCLES(24), .I2C_HALF_PERIOD(6),
    .SILENCE_CYCLES(12500000), .HDR_WARMUP_PAIRS(8), .HDR_I2C_HALF_PERIOD(7),
    .HDR_RESET_HOLD_CYCLES(8), .HDR_RELEASE_WAIT_CYCLES(12),
    .HDR_REGULATOR_WAIT_CYCLES(24)
  ) camera (
    .i_pixel_clk(pixel_clk), .i_sensor_clk(sensor_clk), .i_ref_clk(ref_clk),
    .i_reset_n(reset_n), .i_cfg_clk(cfg_clk), .i_hdr_mclk(hdr_mclk),
    .i_clock_locked(clock_locked), .i_hdr_request(hdr_request), .i_mode_quiet(mode_quiet),
    .i_sdr_30_request(1'b1), .i_hdr_pair_event(pair_event), .i_hdr_pair_ok(pair_ok),
    .i_gain_code(8'h00), .mipi_clk_hs_rx_p(word_clk), .mipi_data_hs_p(4'b0),
    .cam_scl(cam_scl), .cam_mclk(cam_mclk), .cam_xclr(cam_xclr), .cam_sda(cam_sda),
    .m_hdr0_ready(1'b1), .m_hdr1_ready(1'b1), .i_cropped_raw_ready(1'b1),
    .m_frame_event_ready(1'b1), .o_sdr_30_mode(sdr_30_mode), .o_hdr_mode(hdr_mode),
    .o_mode_running(mode_running), .o_hdr_stable(hdr_stable), .o_config_done(config_done),
    .o_config_error(config_error), .o_phy_ready(phy_ready), .o_delay_ready(delay_ready),
    .o_receive_fault(receive_fault), .o_source_identity_fault(identity_fault)
  );

  task automatic require_true(input logic cond, input string note);
    if (cond !== 1'b1) begin
      $display("BB_FAIL cam %s %s", scenario, note);
      $fatal(1,"%s",note);
    end
  endtask

  // Passive scoreboard. The slave affects SDA only on a byte's ACK bit.
  bit armed=0, started=0, saw_reset_low=0, saw_reset_release=0;
  bit early_training_window=0, early_error_seen=0;
  int cohort=0, attempts=0, successful=0, clocks_seen=0;
  int expected_writes=0, nack_write=0, fault_rises=0, config_done_rises=0;
  logic [31:0] four_bytes=0, last_success=0, previous_success=0;
  realtime last_stop=0, start_time=0, last_gap=0;

  function automatic bit nack_this_byte;
    return (attempts+1 == nack_write && clocks_seen >= 35);
  endfunction

  always @(cam_xclr) if (armed) begin
    if (cam_xclr === 1'b0) saw_reset_low=1;
    if (cam_xclr === 1'b1 && saw_reset_low) saw_reset_release=1;
  end

  always @(negedge cam_sda) if (armed && reset_n && cam_xclr === 1'b1 &&
                                 cam_scl === 1'b1 && !slave_ack) begin
    require_true(!started, "unexpected repeated I2C START");
    require_true(saw_reset_release, "I2C START before physical XCLR assertion/release");
    require_true(attempts < expected_writes, "I2C write beyond the selected recipe");
    if (nack_write != 0)
      require_true(attempts < nack_write, "I2C recipe retried after NACK");
    started=1; clocks_seen=0; four_bytes=0; start_time=$realtime;
  end

  always @(posedge cam_scl) if (armed && reset_n && started && clocks_seen < 36) begin
    require_true(cam_sda === 1'b0 || cam_sda === 1'b1, "unknown I2C bus value");
    if ((clocks_seen % 9) == 8)
      require_true(cam_sda === (nack_this_byte() ? 1'b1 : 1'b0),
                   $sformatf("I2C ACK bit mismatch at write %0d clock %0d",attempts+1,clocks_seen));
    else
      four_bytes={four_bytes[30:0],cam_sda};
    clocks_seen++;
  end

  always @(negedge cam_scl) begin
    slave_ack=armed && reset_n && started && clocks_seen < 36 &&
              (clocks_seen % 9)==8 && !nack_this_byte();
  end

  always @(posedge cam_sda) if (armed && reset_n && started &&
                                 cam_xclr === 1'b1 && cam_scl === 1'b1) begin
    require_true(clocks_seen == 36,
                 $sformatf("I2C STOP with %0d of 36 clocks at write %0d",clocks_seen,attempts+1));
    require_true(four_bytes[31:24] === 8'h34,
                 $sformatf("unexpected camera I2C address byte %02h",four_bytes[31:24]));
    attempts++;
    if (attempts != nack_write) begin
      successful++;
      previous_success=last_success;
      last_success=four_bytes;
      last_gap=start_time-last_stop;
    end
    last_stop=$realtime;
    started=0;
  end

  always @(posedge receive_fault) if (reset_n) fault_rises++;
  always @(posedge config_error) if (early_training_window) early_error_seen=1;
  always @(posedge config_done) begin
    #1;
    if (armed && reset_n) begin
      config_done_rises++;
      require_true(successful == expected_writes && nack_write == 0,
                   $sformatf("configuration DONE before recipe success: got %0d/%0d ACKed writes",
                             successful,expected_writes));
    end
  end

  task automatic arm_recipe(input bit hdr, input int nack_at);
    cohort++;
    expected_writes=hdr ? HDR_WRITES : SDR_WRITES;
    nack_write=nack_at; attempts=0; successful=0; clocks_seen=0; started=0;
    slave_ack=0; last_success=0; previous_success=0; last_stop=0;
    start_time=0; last_gap=0; config_done_rises=0;
    saw_reset_low=cam_xclr === 1'b0;
    saw_reset_release=0; armed=1;
  endtask

  task automatic reboot;
    @(negedge cfg_clk);
    armed=0; reset_n=0; mode_quiet=1; hdr_request=0; clock_locked=1;
    word_enable=1; slave_ack=0; early_training_window=0; early_error_seen=0;
    repeat (12) @(negedge cfg_clk);
    arm_recipe(0,0);
    reset_n=1;
  endtask

  task automatic switch_drained(input bit hdr, input int nack_at);
    int old_attempts;
    @(negedge cfg_clk);
    mode_quiet=0; old_attempts=attempts;
    require_true(cam_xclr && config_done, "mode change started without a running recipe");
    hdr_request=hdr;
    repeat (16) begin
      @(negedge cfg_clk);
      require_true(cam_xclr && attempts == old_attempts,
                   "physical mode change began before old work drained");
    end
    arm_recipe(hdr,nack_at);
    mode_quiet=1;
  endtask

  task automatic wait_running_recipe(input bit hdr);
    bit ready;
    ready=0;
    for (int i=0; i<RECIPE_DEADLINE && !ready; i++) begin
      @(negedge cfg_clk);
      require_true(config_error !== 1'b1,
                   $sformatf("unexpected configuration error during cohort %0d",cohort));
      ready=(config_done === 1'b1 && phy_ready === 1'b1 &&
             hdr_mode === hdr && successful == expected_writes);
    end
    require_true(ready,
                 $sformatf("configuration deadline cohort=%0d writes=%0d/%0d done=%b PHY=%b HDR=%b",
                           cohort,successful,expected_writes,config_done,phy_ready,hdr_mode));
    require_true(attempts == expected_writes && config_done_rises == 1,
                 "recipe did not produce exactly one configuration completion");
    require_true(last_success === 32'h34300200 && previous_success === 32'h34300000,
                 $sformatf("bad wake/master release tail: %08h %08h",
                           previous_success,last_success));
    require_true(last_gap > 0.0, "standby cancel and master release lacked a wake interval");
    if (!hdr) begin
      require_true(sdr_30_mode && mode_running, "SDR30 not running after real recipe");
      require_true(last_gap >= 24*40.0, "SDR wake interval shorter than 24 SYS25 clocks");
    end
    require_true(hdr_stable === 1'b0, "new mode inherited qualified HDR pairs");
    require_true(identity_fault === 1'b0, "empty digital pad produced an identity fault");
    $display("BB_CHECK cam recipe cohort=%0d HDR=%b writes=%0d tail=%08h/%08h wake_ns=%0.1f delay=%b",
             cohort,hdr,successful,previous_success,last_success,last_gap,delay_ready);
  endtask

  task automatic lose_word_clock;
    bit dropped;
    int prior_faults;
    @(negedge cfg_clk);
    require_true(phy_ready, "cannot test PHY loss before PHY is ready");
    prior_faults=fault_rises;
    word_enable=0; dropped=0;
    for (int i=0; i<PHY_DEADLINE && !dropped; i++) begin
      @(negedge cfg_clk);
      dropped=(phy_ready === 1'b0 && fault_rises > prior_faults);
    end
    require_true(dropped, $sformatf("WORD stop did not report PHY loss (ready=%b events=%0d)",
                                    phy_ready,fault_rises-prior_faults));
    $display("BB_CHECK cam WORD loss: PHY=%b receive_fault_events=%0d",phy_ready,
             fault_rises-prior_faults);
  endtask

  task automatic recover_training;
    bit ready;
    early_training_window=1; early_error_seen=0;
    lose_word_clock();
    repeat (8) @(negedge cfg_clk);
    require_true(!early_error_seen && !config_error && !hdr_stable,
                 "recoverable pre-pair PHY interruption became terminal");
    word_enable=1; ready=0;
    for (int i=0; i<PHY_DEADLINE && !ready; i++) begin
      @(negedge cfg_clk);
      require_true(!early_error_seen && !config_error, "early PHY relock raised configuration error");
      ready=phy_ready && config_done;
    end
    require_true(ready && attempts == HDR_WRITES && config_done_rises == 1 && !hdr_stable,
                 "pre-pair PHY relock did not preserve the configured HDR recipe");
    early_training_window=0;
    $display("BB_CHECK cam pre-pair PHY relocked without a second recipe");
  endtask

  task automatic deliver_pair(input bit good, input bit expected_stable);
    @(negedge pixel_clk); pair_ok=good; pair_event=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk); pair_event=0;
    repeat (24) @(negedge cfg_clk);
    require_true(config_done && !config_error && !identity_fault,
                 "a warmup pair caused a terminal error");
    require_true(hdr_stable === expected_stable,
                 $sformatf("pair ok=%b expected HDR stable=%b actual=%b",good,expected_stable,hdr_stable));
  endtask

  task automatic qualify_pairs(input bit reject_in_middle);
    require_true(!hdr_stable, "HDR stable before any pairs in this sequence");
    if (reject_in_middle) begin
      repeat (QUALIFIED_PAIRS-1) deliver_pair(1,0);
      deliver_pair(0,0);
    end
    repeat (QUALIFIED_PAIRS-1) deliver_pair(1,0);
    deliver_pair(1,1);
    require_true(hdr_mode && mode_running && phy_ready, "qualified HDR source not running");
    $display("BB_CHECK cam cohort=%0d stable after eight consecutive good pairs bad_pair=%b",
             cohort,reject_in_middle);
  endtask

  task automatic wait_terminal(input string cause);
    bit terminal_seen;
    terminal_seen=0;
    for (int i=0; i<RECIPE_DEADLINE && !terminal_seen; i++) begin
      @(negedge cfg_clk);
      terminal_seen=config_error === 1'b1 && config_done === 1'b0 && hdr_stable === 1'b0;
    end
    require_true(terminal_seen, $sformatf("%s deadline without held terminal error",cause));
    $display("BB_CHECK cam terminal %s cohort=%0d attempts=%0d successes=%0d",
             cause,cohort,attempts,successful);
  endtask

  task automatic check_no_retry(input string cause);
    int frozen_attempts;
    frozen_attempts=attempts;
    repeat (160) begin
      @(negedge cfg_clk);
      require_true(config_error && !config_done && !hdr_stable && attempts == frozen_attempts,
                   $sformatf("%s cleared terminal status or retried without reset",cause));
    end
  endtask

  initial begin
    if (!$value$plusargs("CASE=%s",scenario)) scenario="cam-training";
    require_true(scenario == "cam-training" || scenario == "cam-nack" || scenario == "cam-lock",
                 "unknown scenario");
    reboot();
    wait_running_recipe(0);
    switch_drained(1,scenario == "cam-nack" ? 3 : 0);
    if (scenario == "cam-nack") begin
      wait_terminal("I2C NACK");
      require_true(attempts == 3 && successful == 2, "NACK did not stop the third HDR register write");
      check_no_retry("I2C NACK");
      reboot();
      wait_running_recipe(0);
      switch_drained(1,0);
      wait_running_recipe(1);
      qualify_pairs(0);
    end else begin
      wait_running_recipe(1);
      if (scenario == "cam-training") begin
        recover_training();
        qualify_pairs(1);
        switch_drained(0,0);
        wait_running_recipe(0);
        switch_drained(1,0);
        wait_running_recipe(1);
        qualify_pairs(0);
        lose_word_clock();
        wait_terminal("established WORD loss");
        word_enable=1;
        check_no_retry("established WORD loss");
      end else begin
        @(negedge cfg_clk); clock_locked=0;
        wait_terminal("configuration clock lock loss during warmup");
        clock_locked=1;
        check_no_retry("configuration clock lock loss");
      end
    end
    $display("BB_PASS cam %s", scenario);
    $finish;
  end

  initial begin
    #70000000;
    require_true(0,"simulation watchdog");
  end
endmodule
