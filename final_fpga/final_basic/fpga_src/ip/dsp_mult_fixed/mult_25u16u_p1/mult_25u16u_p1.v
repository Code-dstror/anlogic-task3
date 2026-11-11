/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 07 2026 01:04:01
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	
**	Ip Version	:	1.1
\************************************************************/
module mult_25u16u_p1
(
  input                         ce,
  input                         rst,
  input                         clk,
  input   [24:0]                a,
  input   [15:0]                b,
  output  [40:0]                p
);

  mult_25u16u_p1_multiplier_top
  #(
      .A_WIDTH(25),
      .B_WIDTH(16),
      .A_SIGNED(0),
      .B_SIGNED(0),
      .HAS_CE(1),
      .HAS_SCLR(1),
      .CE_OVER_SCLR(0),
      .MODEL_TYPE(0),
      .B_VALUE_WIDTH(8),
      .B_VALUE_NEGE(0),
      .B_VALUE(69'd255),
      .MULT_TYPE(1),
      .DELAY(1),
      .OUT_HIGH(40),
      .OUT_LOW(0),
      .P_WIDTH(41),
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
