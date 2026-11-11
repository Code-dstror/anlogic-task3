`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
// R5's exact six record-service schedules, now all required to select V3.
module r6_record_reset_case #(parameter LATE_USER=0,LATE_DFI=0,RESTART_MODE=0,CASE_ID=0)(output reg done=0);
  reg user_clk=0,dfi_clk=0,user_run=!LATE_USER,dfi_run=!LATE_DFI,rst_n=1;
  reg dfi_reset_gate=1;
  always #4 user_clk=user_run?!user_clk:0;
  always #5 dfi_clk=dfi_run?!dfi_clk:0;
  reg write_valid=0,read_valid=0;
  reg [11:0] write_offset=0,read_offset=0;
  reg [31:0] write_data=0;
  wire [31:0] read_data;
  wire user_done,dfi_done,user_busy;
  wire [15:0] user_version,dfi_version;
  integer checks=0;
  record_format_service #(.RECORD_V3_ENABLE(1),.NEUTRAL_STATS_ENABLE(1)) dut(
    .i_user_clk(user_clk),.i_user_rst_n(rst_n),.write_valid(write_valid),.write_offset(write_offset),
    .write_data(write_data),.write_strobes(4'hf),.write_response(),.read_valid(read_valid),.read_offset(read_offset),
    .read_response_valid(),.read_data(read_data),.read_response(),.i_user_source_session(32'd2),
    .i_user_source_session_ready(1'b1),.i_app_enable(1'b0),.i_c2h_running(1'b0),.i_tx_busy(1'b0),
    .i_source_functional_quiescent(1'b1),.i_session_armed(1'b0),.i_rearm_ready(1'b1),
    .o_user_busy(user_busy),.o_user_selected_version(user_version),.o_user_selected_header_length(),
    .o_user_selection_epoch(),.o_user_reset_done(user_done),.o_stale_ack_count(),
    .i_dfi_clk(dfi_clk),.i_dfi_rst_n(rst_n&&dfi_reset_gate),.i_dfi_source_session(32'd2),.i_dfi_quiescent(1'b1),
    .o_dfi_selected_version(dfi_version),.o_dfi_selection_epoch(),.o_dfi_reset_done(dfi_done));
  task check(input bit value,input string why);
    begin checks=checks+1;if(!value)$fatal(1,"case=%0d %s",CASE_ID,why);end
  endtask
  task wr(input [11:0] offset,input [31:0] value);
    begin @(negedge user_clk);write_valid=1;write_offset=offset;write_data=value;
      @(negedge user_clk);write_valid=0;end
  endtask
  task rd(input [11:0] offset,output [31:0] value);
    begin @(negedge user_clk);read_valid=1;read_offset=offset;
      @(posedge user_clk);#1;value=read_data;@(negedge user_clk);read_valid=0;end
  endtask
  task select_record(input [31:0] sequence_id,input bit expect_reset);
    reg [31:0] status,error,response_sequence;
    integer guard;
    begin
      wr(`PCIE_REG_RECORD_REQUEST_VERSION,3);wr(`PCIE_REG_RECORD_REQUEST_SEQUENCE,sequence_id);
      wr(`PCIE_REG_RECORD_REQUEST_SESSION,2);wr(`PCIE_REG_RECORD_COMMAND,1);
      guard=0;
      do begin rd(`PCIE_REG_RECORD_STATUS,status);guard=guard+1;end while(!status[1]&&guard<1000);
      rd(`PCIE_REG_RECORD_ERROR,error);rd(`PCIE_REG_RECORD_RESPONSE_SEQUENCE,response_sequence);
      check(guard<1000,"SELECT returns terminal response");
      check(response_sequence==sequence_id,"new sequence replaces old terminal identity");
      check(status==(expect_reset?6:2)&&error==(expect_reset?5:0),"expected actual terminal error");
      if(!expect_reset)check(user_version==3&&dfi_version==3,"USER/DFI actual selection agrees");
      $display("SELECT case=%0d seq=%0d status=%0d error=%0d user_reset_done=%0d dfi_reset_done=%0d",CASE_ID,sequence_id,status,error,user_done,dfi_done);
    end
  endtask
  initial begin
    #1;rst_n=0;#99;rst_n=1;
    #500;user_run=1;dfi_run=1;
    repeat(200)@(negedge user_clk);
    if(RESTART_MODE!=0)begin
      check(user_done&&dfi_done,"both clocks and both FIFO directions are ready before PERST-style event");
      $display("BEFORE_PERST case=%0d mode=%0d user_input_rst_n=%0d dfi_input_rst_n=%0d u=%0d d=%0d",CASE_ID,RESTART_MODE,rst_n,rst_n&&dfi_reset_gate,user_done,dfi_done);
      @(negedge user_clk);
      if(RESTART_MODE==1)begin
        // USER was already fully stopped before the DFI/common assertion.
        user_run=0;#1;dfi_reset_gate=0;
      end else if(RESTART_MODE==2)begin
        // Top keeps ownership reset high across PERST. The last USER edge
        // clocks this port's reset high, before a peer assertion is observed.
        dfi_reset_gate=0;@(posedge user_clk);#1;user_run=0;
      end else dfi_reset_gate=0; // Both clocks continue: normal reset control.
      #200;dfi_reset_gate=1;
      #500;user_run=1;
      repeat(200)@(negedge user_clk);
      $display("AFTER_PERST case=%0d mode=%0d user_input_rst_n=%0d dfi_input_rst_n=%0d u=%0d d=%0d",CASE_ID,RESTART_MODE,rst_n,rst_n&&dfi_reset_gate,user_done,dfi_done);
    end
    check(user_done&&dfi_done,"every R5 stopped-clock schedule now releases normally");
    select_record(1,0);
    select_record(2,0);
    $display("RESULT: PASS R6_RECORD_RESET case=%0d checks=%0d",CASE_ID,checks);done=1;
  end
endmodule
module r6_record_reset_tb;
  wire d0,d1,d2,d3,d4,d5;
  r6_record_reset_case #(.CASE_ID(0)) simultaneous(d0);
  r6_record_reset_case #(.LATE_USER(1),.CASE_ID(1)) user_late(d1);
  r6_record_reset_case #(.LATE_DFI(1),.CASE_ID(2)) dfi_late(d2);
  r6_record_reset_case #(.RESTART_MODE(1),.CASE_ID(3)) perst_clock_stopped_first(d3);
  r6_record_reset_case #(.RESTART_MODE(2),.CASE_ID(4)) perst_one_last_user_edge(d4);
  r6_record_reset_case #(.RESTART_MODE(3),.CASE_ID(5)) perst_both_clocks_running(d5);
  initial begin wait(d0&&d1&&d2&&d3&&d4&&d5);$display("RESULT: PASS r6_record_reset_tb");$finish;end
  initial begin #200000;$fatal(1,"record reset start watchdog");end
endmodule
