/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 07 2026 01:28:41
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	2.0
\************************************************************/
module div_19s14s_q8
(
  input                         aclk,
  input                         aresetn,
  input   [23:0]                s_axis_dividend_tdata,
  input                         s_axis_dividend_tvalid,
  output                        s_axis_dividend_tready,
  input   [15:0]                s_axis_divisor_tdata,
  input                         s_axis_divisor_tvalid,
  output                        s_axis_divisor_tready,
  output  [39:0]                m_axis_dout_tdata,
  output                        m_axis_dout_tvalid,
  input                         m_axis_dout_tready
);

  div_19s14s_q8_divider_top
  #(
      .OPERAND_SIGN(1),
      .DIVIDEND_DW(19),
      .DIVISOR_DW(14),
      .DIVIDEND_CEIL_DW(24),
      .DIVISOR_CEIL_DW(16),
      .OUTPUT_DW(40),
      .FLOW_CONTROL(1),
      .OUT_BLOCKING(1),
      .LATENCY(25)
  )divider_top_Inst
  (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_dividend_tdata(s_axis_dividend_tdata),
      .s_axis_dividend_tvalid(s_axis_dividend_tvalid),
      .s_axis_dividend_tready(s_axis_dividend_tready),
      .s_axis_divisor_tdata(s_axis_divisor_tdata),
      .s_axis_divisor_tvalid(s_axis_divisor_tvalid),
      .s_axis_divisor_tready(s_axis_divisor_tready),
      .m_axis_dout_tdata(m_axis_dout_tdata),
      .m_axis_dout_tvalid(m_axis_dout_tvalid),
      .m_axis_dout_tready(m_axis_dout_tready)
  );
endmodule
