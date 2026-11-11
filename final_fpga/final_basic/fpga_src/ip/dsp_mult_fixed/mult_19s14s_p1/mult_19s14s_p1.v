/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 07 2026 01:03:55
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	1.1
\************************************************************/
module mult_19s14s_p1
(
  input                         ce,
  input                         rst,
  input                         clk,
  input   [18:0]                a,
  input   [13:0]                b,
  output  [32:0]                p
);

  mult_19s14s_p1_multiplier_top
  #(
      .A_WIDTH(19),
      .B_WIDTH(14),
      .A_SIGNED(1),
      .B_SIGNED(1),
      .HAS_CE(1),
      .HAS_SCLR(1),
      .CE_OVER_SCLR(0),
      .MODEL_TYPE(0),
      .B_VALUE_WIDTH(8),
      .B_VALUE_NEGE(0),
      .B_VALUE(69'd255),
      .MULT_TYPE(1),
      .DELAY(1),
      .OUT_HIGH(32),
      .OUT_LOW(0),
      .P_WIDTH(33),
      .ROUND_OUTPUT(0)
  )multiplier_top_Inst
  (
      .ce(ce),
      .rst(rst),
      .clk(clk),
      .a(a),
      .b(b),
      .p(p)
  );
endmodule
