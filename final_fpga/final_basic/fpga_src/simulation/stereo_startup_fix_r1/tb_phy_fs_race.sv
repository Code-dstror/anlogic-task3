`timescale 1ns/1ps
module tb_phy_fs_race;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,phy=0,ev=0,valid=0,sof=0,eol=0;
 reg [1:0] kind=0;reg [31:0] seq=0;
 wire quarantine,idle,cap,source,ok,event_ready,fault;
 integer checks=0,good=0;
 production_source_identity_guard guard0(.clk(clk),.rst_n(rst),.phy_ready(phy),
  .receive_fault(1'b0),.parser_identity_fault(1'b0),.i_recovery_quiet(idle&&event_ready),
  .event_valid(ev),.event_kind(kind),.event_identity_valid(1'b1),.quarantine(quarantine));
 stereo_capture_source4 #(.WIDTH(8),.HEIGHT(1),.SEPARATE_DATA_RESET(1)) dut(
  .clk(clk),.rst_n(rst),.i_data_reset_n(rst),.i_enable(1'b1),.i_session(32'd1),.i_epoch(32'd0),
  .i_time_ns(64'd0),.i_time_valid(1'b1),.i_data(40'd0),.i_valid(valid),.i_accept(1'b1),.i_sof(sof),.i_eol(eol),.i_abort(1'b0),
  .i_sequence(seq),.i_identity_valid(1'b1),.i_event_valid(ev),.o_event_ready(event_ready),.i_event_kind(kind),
  .i_event_ok(1'b1),.i_event_error(4'd0),.i_event_sequence(seq),.i_event_identity_valid(1'b1),
  .i_receive_fault(1'b0),.i_identity_quarantine(quarantine),
  .o_capture_data(),.o_capture_valid(cap),.o_capture_accept(),.o_capture_sof(),.o_capture_eol(),.o_capture_abort(),
  .o_capture_geometry_done(),.o_capture_session(),.o_capture_epoch(),.o_capture_sequence(),.o_capture_metadata(),
  .o_raw_source_valid(source),.i_raw_source_ready(1'b1),.o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_sequence(),
  .o_raw_source_camera(),.o_raw_source_ok(ok),.o_raw_source_error(),.o_idle(idle),.o_fault(fault));
 task tick;begin @(negedge clk);#1;end endtask
 task check(input bit p,input string msg);begin checks++;if(!p)begin $display("FAIL %s",msg);$fatal(1);end end endtask
 task event_send(input [1:0] k,input integer s);begin kind=k;seq=s;ev=1;tick();ev=0;end endtask
 always @(posedge clk)if(source&&ok)good++;
 initial begin
  repeat(3)tick();rst=1;repeat(3)tick();
  // Trustworthy-looking event may be queued while synchronized PHY goes low.
  event_send(0,1);check(quarantine&&!idle&&!cap&&!source,"PHY-low FS starts only transient unfed owner then quarantine");
  repeat(6)begin tick();check(!source&&!cap,"quarantined initial owner cannot become successful source");end
  check(idle&&fault,"unfed failed owner retires, quarantine remains");
  phy=1;event_send(0,2);check(!quarantine&&idle&&!cap,"healthy recovery FS clears guard but does not admit using old quarantine");
  event_send(0,3);check(!idle,"later healthy FS opens real owner");
  valid=1;sof=1;tick();sof=0;eol=1;tick();valid=0;eol=0;event_send(1,3);
  repeat(12)tick();check(good==1&&idle&&!fault,"later true frame succeeds once with no false prior success");
  $display("RESULT: PASS PHY_FS_RACE checks=%0d good=%0d",checks,good);$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
