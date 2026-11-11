/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 07 2026 18:18:38
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	2.0
\************************************************************/
module cfs_div_32u16u_l28
(
  input                         aclk,
  input                         aresetn,
  input   [31:0]                s_axis_dividend_tdata,
  input                         s_axis_dividend_tvalid,
  input   [15:0]                s_axis_divisor_tdata,
  input                         s_axis_divisor_tvalid,
  output  [47:0]                m_axis_dout_tdata,
  output                        m_axis_dout_tvalid
);

  cfs_div_32u16u_l28_divider_top
  #(
      .OPERAND_SIGN(0),
      .DIVIDEND_DW(32),
      .DIVISOR_DW(16),
      .DIVIDEND_CEIL_DW(32),
      .DIVISOR_CEIL_DW(16),
      .OUTPUT_DW(48),
      .FLOW_CONTROL(0),
      .LATENCY(28)
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
