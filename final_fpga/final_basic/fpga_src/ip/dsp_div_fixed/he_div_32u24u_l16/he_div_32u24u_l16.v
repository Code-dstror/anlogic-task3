/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 09 2026 21:46:01
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	2.0
\************************************************************/
module he_div_32u24u_l16
(
  input                         aclk,
  input                         aresetn,
  input   [31:0]                s_axis_dividend_tdata,
  input                         s_axis_dividend_tvalid,
  input   [23:0]                s_axis_divisor_tdata,
  input                         s_axis_divisor_tvalid,
  output  [55:0]                m_axis_dout_tdata,
  output                        m_axis_dout_tvalid
);

  he_div_32u24u_l16_divider_top
  #(
      .OPERAND_SIGN(0),
      .DIVIDEND_DW(32),
      .DIVISOR_DW(24),
      .DIVIDEND_CEIL_DW(32),
      .DIVISOR_CEIL_DW(24),
      .OUTPUT_DW(56),
      .FLOW_CONTROL(0),
      .LATENCY(16)
  )divider_top_Inst
  (
      .aclk(aclk),
      .aresetn(aresetn),
      .s_axis_dividend_tdata(s_axis_dividend_tdata),
      .s_axis_dividend_tvalid(s_axis_dividend_tvalid),
      .s_axis_divisor_tdata(s_axis_divisor_tdata),
      .s_axis_divisor_tvalid(s_axis_divisor_tvalid),
      .m_axis_dout_tdata(m_axis_dout_tdata),
      .m_axis_dout_tvalid(m_axis_dout_tvalid)
  );
endmodule
