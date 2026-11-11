`timescale 1ns/1ps
module rx_diag_leaf_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,idrst=0,valid=0;reg [31:0] word_data=0;
 wire [63:0] diag;wire fault;wire [31:0] sequence_count;
 physical_csi_word_core #(.RX_DIAG_ENABLE(1)) parser(
  .i_clk(clk),.i_reset_n(rst),.i_identity_rst_n(idrst),.i_word(word_data),.i_word_valid(valid),.i_sink_ready(1'b1),
  .o_identity_diag(diag),.o_identity_fault(fault),.o_source_sequence_count(sequence_count),
  .o_packet_done(),.o_wait_for_sync(),.o_length_error(),.o_payload_crc_error(),.o_header_ecc_error(),
  .o_error_code(),.o_abort(),.o_eol(),.o_sof(),.o_valid(),.o_data());
 reg start=0,pair_event=0,pair_ok=0;wire write_valid,stable,done_cfg;reg write_done=0;
 wire [31:0] cfg_diag;
 imx415_hdr2_config_owner #(.RESET_HOLD_CYCLES(2),.RELEASE_WAIT_CYCLES(2),.REGULATOR_WAIT_CYCLES(2)) owner(
  .i_clk(clk),.i_rst_n(idrst),.i_start(start),.i_clock_locked(1'b1),.i_abort(1'b0),.i_source_fault(1'b0),
  .i_pair_event(pair_event),.i_pair_ok(pair_ok),.o_write_valid(write_valid),.i_write_ready(1'b1),
  .i_write_done(write_done),.i_write_error(1'b0),.o_config_written(done_cfg),.o_stable(stable),.o_diag_state(cfg_diag),
  .o_black_raw10(),.o_gain_q16(),.o_ratio_log2(),.o_short_driver_lines(),.o_long_driver_lines(),
  .o_register_index(),.o_error(),.o_write_register(),.o_busy(),.o_xclr(),.o_start_ready());
 always @(posedge clk)write_done<=write_valid;
 reg [146:0] token0=0,token1=0;reg v0=0,v1=0,pair_fault=0;
 wire ready0,ready1;wire [31:0] pair_phase;wire [47:0] pair_counts;
 real_hdr_pair_cycle_gate #(.TIMEOUT_CYCLES(16)) cycle_owner(
  .i_clk(clk),.i_reset_n(idrst),.i_fault(pair_fault),.i_stable(1'b0),.i_admit_enable(1'b0),
  .i_session(32'd1),.i_epoch(32'd1),.i_time(64'd100),.i_time_valid(1'b1),.i_capture0_idle(1'b1),.i_capture1_idle(1'b1),
  .s0_data(token0),.s1_data(token1),.s0_valid(v0),.s1_valid(v1),.s0_ready(ready0),.s1_ready(ready1),
  .m0_data(),.m1_data(),.m0_valid(),.m1_valid(),.m0_sof(),.m1_sof(),.m0_eol(),.m1_eol(),.m0_abort(),.m1_abort(),
  .o_sequence0(),.o_sequence1(),.o_session(),.o_epoch(),.o_metadata0(),.o_metadata1(),.o_source0_valid(),.o_source1_valid(),
  .i_source0_ready(1'b1),.i_source1_ready(1'b1),.o_source_session(),.o_source_epoch(),.o_source0_sequence(),.o_source1_sequence(),
  .o_source_ok(),.o_source_error(),.o_pair_event(),.o_pair_ok(),.o_diag_pair(pair_phase),.o_diag_counts(pair_counts),
  .o_good_pairs(),.o_bad_pairs(),.o_not_admitted_pairs(),.o_quiet());
 task tick;@(negedge clk);endtask
 task pair(input bit ok);begin pair_event=1;pair_ok=ok;tick();pair_event=0;tick();end endtask
 task token(input bit member,input integer kind,input integer group_id);
  reg [146:0] data;begin
   data=0;data[46:43]=kind;data[78:47]=group_id;data[110:79]=group_id;data[111]=1;data[112]=1;
   if(member)begin token1=data;v1=1;end else begin token0=data;v0=1;end
   tick();v0=0;v1=0;tick();
  end
 endtask
 initial begin
  repeat(3)tick();rst=1;idrst=1;tick();
  valid=1;word_data=32'hffffffff;tick();valid=0;tick();
  if(fault||diag!==0)$fatal(1,"pre-FS bad header must not establish identity loss");
  valid=1;word_data=0;tick();valid=0;tick();
  if(sequence_count!=1||fault)$fatal(1,"first FS establishes startup identity");
  valid=1;word_data=32'hffffffff;tick();valid=0;tick();
  if(!fault||diag[6:4]!==1||diag[63:32]!==32'hffffffff)$fatal(1,"first bad header attribution");
  word_data=32'h12345678;valid=1;tick();valid=0;tick();
  if(diag[63:32]!==32'hffffffff)$fatal(1,"first cause overwritten");
  rst=0;idrst=0;tick();rst=1;idrst=1;tick();
  if(fault||diag!==0)$fatal(1,"identity cohort reset");
  valid=1;word_data=0;tick();valid=0;tick();
  if(sequence_count!=1)$fatal(1,"real FS identity counter");
  rst=0;tick();tick();if(!fault||diag[6:4]!==2||diag[31:16]!==1)$fatal(1,"decoder reset attribution");
  rst=1;idrst=0;tick();idrst=1;tick();start=1;tick();start=0;
  wait(done_cfg);tick();if(cfg_diag[15:12]!=6||stable)$fatal(1,"written means WARMUP, not STABLE");
  repeat(7)pair(1);if(stable||cfg_diag[31:24]!=7)$fatal(1,"eight consecutive warmup boundary");
  pair(0);if(stable||cfg_diag[31:24]!=0)$fatal(1,"bad pair restarts warmup");
  repeat(8)pair(1);if(!stable||cfg_diag[15:12]!=7)$fatal(1,"actual stable boundary");
  pair(0);if(stable||cfg_diag[15:12]!=6)$fatal(1,"stable loss visible");
  token(0,7,1);token(1,7,1);token(0,6,1);token(1,6,1);
  if(pair_counts!==48'h000100000001)$fatal(1,"good unadmitted pair is observable during warmup");
  token(0,7,2);repeat(18)tick();
  if(pair_counts[31:16]!=1||pair_phase[31:24]!=11)$fatal(1,"missing member timeout attribution");
  token(0,7,3);pair_fault=1;tick();pair_fault=0;tick();
  if(pair_phase[31:24]!=11||pair_phase[23:16]!=9)$fatal(1,"first bad cause retained while last cause advances");
  $display("RESULT: PASS rx_diag_leaf first_header reset_cohort warmup_7_bad_8 stable_loss");$finish;
 end
 initial begin #1000000;$fatal(1,"leaf watchdog");end
endmodule
