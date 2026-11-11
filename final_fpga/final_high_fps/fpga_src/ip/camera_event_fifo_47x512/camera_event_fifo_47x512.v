/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Nov 04 2026 22:13:56
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	3.0
\************************************************************/
module camera_event_fifo_47x512
(
  input   [46:0]                di,
  input                         clkr,
  input                         rrst,
  input                         re,
  input                         clkw,
  input                         wrst,
  input                         we,
  output  [46:0]                dout,
  output                        empty_flag,
  output                        aempty,
  output                        full_flag,
  output                        afull,
  output                        valid,
  output                        overflow,
  output                        underflow,
  output                        wr_success,
  output  [9:0]                 rdusedw,
  output  [9:0]                 wrusedw,
  output                        wr_rst_done,
  output                        rd_rst_done
);

  camera_event_fifo_47x512_soft_fifo
  #(
      .COMMON_CLK_EN(0),
      .MEMORY_TYPE(0),
      .RST_TYPE(1),
      .DATA_WIDTH_W(47),
      .ADDR_WIDTH_W(9),
      .DATA_WIDTH_R(47),
      .ADDR_WIDTH_R(9),
      .DOUT_INITVAL(47'h0),
      .OUTREG_EN("NOREG"),
      .SHOW_AHEAD_EN(1),
      .AL_FULL_NUM(504),
      .AL_EMPTY_NUM(2),
      .RDUSEDW_WIDTH(10),
      .WRUSEDW_WIDTH(10),
      .ASYNC_RST_SYNC_RELS(0),
      .SYNC_STAGE(2)
  )soft_fifo_Inst
  (
      .di(di),
      .clkr(clkr),
      .rrst(rrst),
      .re(re),
      .clkw(clkw),
      .wrst(wrst),
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
