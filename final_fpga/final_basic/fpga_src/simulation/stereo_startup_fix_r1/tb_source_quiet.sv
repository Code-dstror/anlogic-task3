`timescale 1ns/1ps
module tb_source_quiet;
  reg clk=0; always #5 clk=~clk;
  reg rst=0,enable=0;
  reg receive_fault=0;
  wire quarantine;
  reg [1:0] valid=0,sof=0,eol=0,abort_in=0,ev=0,source_ready=0;
  reg [31:0] seq[0:1],evseq[0:1];
  reg [1:0] kind[0:1];
  wire [1:0] idle,fault,cap,source,source_ok,geometry,event_ready;
  wire [31:0] source_seq[0:1];
  wire [7:0] source_err[0:1];
  integer checks=0,candidate=0,captured=0,good=0,bad=0;
  production_source_identity_guard guard0(.clk(clk),.rst_n(rst),.phy_ready(1'b1),
    .receive_fault(receive_fault),.parser_identity_fault(1'b0),
    .i_recovery_quiet(idle[0]&&event_ready[0]),.event_valid(ev[0]),.event_kind(kind[0]),
    .event_identity_valid(1'b1),.quarantine(quarantine));
  genvar c; generate for(c=0;c<2;c=c+1)begin:eye
    stereo_capture_source4 #(.CAMERA_ID(c),.WIDTH(8),.HEIGHT(1),.SEPARATE_DATA_RESET(1)) dut(
      .clk(clk),.rst_n(rst),.i_data_reset_n(rst),.i_enable(enable),
      .i_session(32'd17),.i_epoch(32'd23),.i_time_ns(64'd12345),.i_time_valid(1'b1),
      .i_data(40'h123456789a),.i_valid(valid[c]),.i_accept(1'b1),.i_sof(sof[c]),.i_eol(eol[c]),.i_abort(abort_in[c]),
      .i_sequence(seq[c]),.i_identity_valid(1'b1),.i_event_valid(ev[c]),.o_event_ready(event_ready[c]),
      .i_event_kind(kind[c]),.i_event_ok(1'b1),.i_event_error(4'd0),.i_event_sequence(evseq[c]),.i_event_identity_valid(1'b1),
      .i_receive_fault(c==0 ? receive_fault:1'b0),.i_identity_quarantine(c==0 ? quarantine:1'b0),
      .o_capture_valid(cap[c]),.o_capture_geometry_done(geometry[c]),
      .o_capture_data(),.o_capture_accept(),.o_capture_sof(),.o_capture_eol(),.o_capture_abort(),
      .o_capture_session(),.o_capture_epoch(),.o_capture_sequence(),.o_capture_metadata(),
      .o_raw_source_valid(source[c]),.i_raw_source_ready(source_ready[c]),.o_raw_source_ok(source_ok[c]),
      .o_raw_source_sequence(source_seq[c]),.o_raw_source_error(source_err[c]),
      .o_raw_source_session(),.o_raw_source_epoch(),.o_raw_source_camera(),.o_idle(idle[c]),.o_fault(fault[c]));
  end endgenerate
  task check(input bit b,input string msg);begin
    checks++; if(!b)begin $display("FAIL %s idle=%b source=%b valid=%b",msg,idle,source,valid);$fatal(1);end
  end endtask
  task tick;begin @(negedge clk); #1; end endtask
  task event0(input [1:0] k,input integer s);begin
    kind[0]=k;evseq[0]=s;ev[0]=1;tick();ev[0]=0;
  end endtask
  always @(posedge clk)if(rst)begin
    if(cap[0])captured++;
    if(source[0]&&source_ready[0])begin if(source_ok[0])good++;else bad++;end
  end
  initial begin
    if($value$plusargs("candidate=%d",candidate))begin end
    seq[0]=0;seq[1]=0;kind[0]=0;kind[1]=0;evseq[0]=0;evseq[1]=0;
    repeat(3)tick();rst=1;repeat(3)tick();
    // Disabled free-running eyes alternate every PIX cycle. No simultaneous
    // input blank exists, yet neither source owns an admitted frame.
    for(integer n=0;n<64;n++)begin
      valid=n%2 ? 2'b01:2'b10;seq[0]=99;seq[1]=199;tick();
      check(!source&&!cap&&!fault,"disabled input owns nothing");
      check(candidate ? (&idle) : (idle==~valid),"expected unowned idle semantics");
      if(!candidate)check(!(&idle),"baseline has no two-eye quiet window");
    end
    $display("OBSERVE disabled alternating 64 cycles candidate=%0d both_idle=%b",candidate,&idle);
    // Orphan abort without owner must not invent ownership or output.
    valid=0;abort_in=3;tick();check(!source&&!cap,"orphan abort produces nothing");
    check(candidate ? (&idle) : !(|idle),"unowned abort idle behavior");
    abort_in=0;tick();enable=1;event0(0,7);
    check(!idle[0],"accepted FS owns source before RAW context");
    // Disabling admission must preserve the already admitted obligation.
    enable=0;repeat(4)begin tick();check(!idle[0],"disable cannot bypass live owner");end
    seq[0]=7;valid=1;sof=1;eol=0;tick();check(captured==1,"first admitted crop transferred");
    sof=0;eol=1;tick();valid=0;eol=0;event0(1,7);
    repeat(8)tick();check(source[0]&&source_ok[0]&&source_seq[0]==7,"complete old frame held at RAW SOURCE");
    repeat(8)begin tick();check(!idle[0]&&source[0]&&source_ok[0]&&source_seq[0]==7,"held SOURCE blocks idle after disable");end
    source_ready=3;repeat(8)tick();check(good==1&&idle[0],"old owner retires only after SOURCE handshake");
    // A partial disabled-after-FS owner with abort still returns negative.
    enable=1;event0(0,8);enable=0;seq[0]=8;valid=1;sof=1;tick();
    valid=0;sof=0;abort_in=1;tick();abort_in=0;event0(2,8);repeat(12)tick();
    check(bad==1&&idle[0],"partial old owner abort retires negatively");
    // Recovery opens a new owner and produces exact geometry normally.
    enable=1;event0(0,9);seq[0]=9;valid=1;sof=1;tick();sof=0;eol=1;tick();
    valid=0;eol=0;event0(1,9);repeat(14)tick();check(good==2&&idle[0]&&!fault[0],"healthy recovery owner succeeds");
    // Guard fault priority is unchanged. A faulty FS cannot open an owner.
    receive_fault=1;event0(0,10);check(quarantine&&!cap[0]&&idle[0],"faulty FS quarantined without capture");
    receive_fault=0;valid=1;seq[0]=99;event0(0,11);
    check(candidate ? !quarantine : quarantine,"unowned input affects only guard recovery quiet");
    check(!cap[0]&&!source[0],"FS clearing quarantine cannot admit using old quarantine");
    // Disabled quiet FS clears baseline as well, then a later true FS works.
    valid=0;enable=0;tick();event0(0,12);check(!quarantine,"healthy quiet FS rearms guard");
    enable=1;event0(0,13);seq[0]=13;valid=1;sof=1;tick();sof=0;eol=1;tick();
    valid=0;eol=0;event0(1,13);repeat(14)tick();check(good==3&&idle[0]&&!fault[0],"guard recovery permits later good frame");
    $display("RESULT: PASS SOURCE_QUIET candidate=%0d checks=%0d good=%0d bad=%0d",candidate,checks,good,bad);$finish;
  end
  initial begin #100000;$fatal(1,"timeout");end
endmodule
