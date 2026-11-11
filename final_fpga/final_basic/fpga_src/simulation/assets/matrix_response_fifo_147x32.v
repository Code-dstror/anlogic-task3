/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 07 2026 15:51:28
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	3.0
\************************************************************/
module matrix_response_fifo_147x32
(
  input                         rst,
  input   [146:0]               di,
  input                         clk,
  input                         re,
  input                         we,
  output  [146:0]               dout,
  output                        empty_flag,
  output                        aempty,
  output                        full_flag,
  output                        afull,
  output                        valid,
  output                        overflow,
  output                        underflow,
  output                        wr_success,
  output  [5:0]                 rdusedw,
  output  [5:0]                 wrusedw,
  output                        wr_rst_done,
  output                        rd_rst_done
);

  matrix_response_fifo_147x32_soft_fifo
  #(
      .COMMON_CLK_EN(1),
      .MEMORY_TYPE(5),
      .RST_TYPE(1),
      .DATA_WIDTH_W(147),
      .ADDR_WIDTH_W(5),
      .DATA_WIDTH_R(147),
      .ADDR_WIDTH_R(5),
      .DOUT_INITVAL(147'h0),
      .OUTREG_EN("NOREG"),
      .SHOW_AHEAD_EN(1),
      .AL_FULL_NUM(29),
      .AL_EMPTY_NUM(2),
      .RDUSEDW_WIDTH(6),
      .WRUSEDW_WIDTH(6),
      .ASYNC_RST_SYNC_RELS(1),
      .SYNC_STAGE(2)
  )soft_fifo_Inst
  (
      .rst(rst),
      .di(di),
      .clk(clk),
      .re(re),
      .we(we),
      .dout(dout),
      .empty_flag(empty_flag),
      .aempty(aempty),
      .full_flag(full_flag),
      .afull(afull),
      .valid(valid),
      .overflow(overflow),
      .underflow(underflow),
      .wr_success(wr_success),
      .rdusedw(rdusedw),
      .wrusedw(wrusedw),
      .wr_rst_done(wr_rst_done),
      .rd_rst_done(rd_rst_done)
  );
endmodule
