/************************************************************\
**	Copyright (c) 2012-2026 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Gen time	:	Oct 14 2026 19:56:08
**	IpTool version	:	2026.08(208212 2026/08/14)
**	App version	:	Release_2026.2
**	Ip Version	:	2.0
\************************************************************/
module fdct_mac19s14s_z33s_p34_m1p1
(
  input                         CLK,
  input                         CE,
  input                         RST,
  input   [18:0]                A,
  input   [13:0]                Y,
  input   [32:0]                Z,
  output  [33:0]                P
);

  fdct_mac19s14s_z33s_p34_m1p1_dsp_macro_0
  #(
      .REGISTER7(0),
      .REGISTER8(0),
      .REGISTER11(0),
      .REGISTER12(0),
      .REGISTER13(0),
      .REGISTER14(0),
      .REGISTER15(1),
      .REGISTER16(0),
      .REGISTER17(0),
      .REGISTER18(0),
      .REGISTER19(0),
      .REGISTER24(1),
      .A_INPUT_TYPE("SIGNED"),
      .Y_INPUT_TYPE("SIGNED"),
      .Z_INPUT_TYPE("SIGNED"),
      .A_INPUT_WIDTH(19),
      .Y_INPUT_WIDTH(14),
      .Z_INPUT_WIDTH(33),
      .P_OUTPUT_WIDTH(34),
      .USER_CTRL0(30'b100000000000010010010000001110)
  )dsp_macro_0_Inst
  (
      .CLK(CLK),
      .CE(CE),
      .RST(RST),
      .A(A),
      .Y(Y),
      .Z(Z),
      .P(P)
  );
endmodule
