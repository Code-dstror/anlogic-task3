// Verilog netlist created by Tang Dynasty Release_2026.2
// Wed Oct  7 11:17:23 2026

`timescale 1ns / 1ps
module cfs_crc32_p1
  (
  clk,
  din,
  din_en,
  packet_end,
  packet_start,
  rst,
  crc_out,
  crc_out_vld
  );

  input clk;
  input [31:0] din;
  input din_en;
  input packet_end;
  input packet_start;
  input rst;
  output [31:0] crc_out;
  output crc_out_vld;

  // parameter COMP_CRC = 1;
  // parameter COMP_DATA = 0;
  // parameter INIT_VALUE = 32'b10011011111100011010100100001111;
  // parameter TRAN_CRC = 1;
  // parameter TRAN_DATA = 1;
  // parameter W_DATA = 32;
  wire [31:0] al_a8b23f08;
  wire [31:0] al_9c667979;
  wire [31:0] al_b925cf5b;
  wire [31:0] al_e692b01b;
  wire al_f6981785;
  wire al_b3e2b095;
  wire al_2f32596b;
  wire al_ca940860;
  wire al_45ef761c;
  wire al_d9bfd92f;
  wire al_1b1db758;
  wire al_ae97fd5e;
  wire al_31685553;
  wire al_f30b825d;
  wire al_24b5356f;
  wire al_620ee392;
  wire al_860501d;
  wire al_46f7f1f6;
  wire al_abf75a68;
  wire al_3f47ae94;
  wire al_47a34a8;
  wire al_585b9892;
  wire al_a0f5191c;
  wire al_faeaa392;
  wire al_ac44599e;
  wire al_e529755e;
  wire al_2fc445a4;
  wire al_c26603f1;
  wire al_a02591ed;
  wire al_ccef2d2d;
  wire al_fc312581;
  wire al_53c3c716;
  wire al_6bf6a16c;
  wire al_f92431fb;
  wire al_e3ddfbd3;
  wire al_89178476;
  wire al_b8fb48ff;
  wire al_be5fe36;
  wire al_14cbbec8;
  wire al_8120bf4d;
  wire al_7354420;
  wire al_b4471c3b;
  wire al_d8a36d67;
  wire al_aeffe097;
  wire al_bcee4da4;
  wire al_fb2a9898;
  wire al_56c4fcba;
  wire al_911f6fe9;
  wire al_e64626b6;
  wire al_3b9cba4e;
  wire al_c74a9571;
  wire al_ae74637d;
  wire al_6ee39c47;
  wire al_4ae694ef;
  wire al_b15c20bc;
  wire al_c665ec5d;
  wire al_891594a9;
  wire al_819a2685;
  wire al_ce83e092;
  wire al_7d62ea53;
  wire al_47d18657;
  wire al_f52af87e;
  wire al_74e73e;
  wire al_98c67744;
  wire al_58f667d1;
  wire al_4726cb06;
  wire al_a1989f7d;
  wire al_3f80181;
  wire al_193c437e;
  wire al_9fdf1e71;
  wire al_41557436;
  wire al_bced07d8;
  wire al_a9b750a;
  wire al_400edb29;
  wire al_c5ac1b65;
  wire al_4a7dff61;
  wire al_a7d54dac;
  wire al_9213e63;
  wire al_728efc21;
  wire al_480fc418;
  wire al_2eaa0831;
  wire al_dc3a3160;
  wire al_37c91d95;
  wire al_d0b8020;
  wire al_8792b600;
  wire al_dd91ce5;
  wire al_b429b9f4;
  wire al_e2e17f54;
  wire al_bcc2d142;
  wire al_5bfbcd40;
  wire al_ade5815;
  wire al_2fa168c5;
  wire al_78a5bd30;
  wire al_98d82759;
  wire al_10ab4c6d;
  wire al_36b577e1;
  wire al_10fa1aaf;
  wire al_fdb48e41;
  wire al_f59e83cb;
  wire al_eb2816e2;
  wire al_23783854;
  wire al_3ef0c0d8;
  wire al_a3c00921;
  wire al_d920e471;
  wire al_6dcbba55;
  wire al_8aa16c13;
  wire al_c65c44d8;
  wire al_c4b11ed6;
  wire al_a4c81ae;
  wire al_4f2e6977;
  wire al_3a652dd7;
  wire al_dfbc5200;
  wire al_9006e254;
  wire al_889d0a3;
  wire al_7316f68e;
  wire al_b378fb4c;
  wire al_d61dbbe2;
  wire al_50aa637d;
  wire al_b49eba87;
  wire al_1f926e6c;
  wire al_5ca66c5d;
  wire al_a8b53724;
  wire al_df67b5a5;
  wire al_39132e63;
  wire al_b07e78e;
  wire al_f6ba4b08;
  wire al_8d0029b9;
  wire al_7d800c96;
  wire al_a6e8fef4;
  wire al_20d7e1e;
  wire al_ed2b4ef5;
  wire al_16f38f00;
  wire al_a57150ce;
  wire al_6b1f677f;
  wire al_6a5c7bf3;
  wire al_fb75046b;
  wire al_706b4c24;
  wire al_4f2045c5;
  wire al_e6a40dc4;
  wire al_41c11af1;
  wire al_4d48443e;
  wire al_5854a817;
  wire al_54062695;
  wire al_8e5758c4;
  wire al_d42076e6;
  wire al_9f2e5b30;
  wire al_1b269f89;
  wire al_2f1a5af3;
  wire al_924ea640;
  wire al_104976d9;
  wire al_cbc0c746;
  wire al_109a1633;
  wire al_cdad152a;
  wire al_21f3c606;
  wire al_8f183839;
  wire al_f89eee8f;
  wire al_65459d91;
  wire al_a05eef16;
  wire al_5c4da1bf;
  wire al_66c102d9;
  wire al_2a5f90f6;
  wire al_95ae97c3;
  wire al_46dd1675;
  wire al_a59c2b8;
  wire al_401856a3;
  wire al_b620a2c2;
  wire al_73fb00f5;
  wire al_75f0d032;
  wire al_e59218b2;
  wire al_9c44f52e;
  wire al_6ce87b4e;
  wire al_5398b6b2;
  wire al_f17c516b;
  wire al_827e1925;
  wire al_c928032d;
  wire al_2197e301;
  wire al_f070b719;
  wire al_4d290666;
  wire al_875461e8;
  wire al_bd3e6902;
  wire al_2a6117da;
  wire al_2b8394c6;
  wire al_ba83a52c;
  wire al_7897898b;
  wire al_14fadafb;
  wire al_fe60cde9;
  wire al_81097bd3;
  wire al_6bf245d5;
  wire al_9b8401f;
  wire al_20893c30;
  wire al_c5e914ef;
  wire al_5a8c08c5;
  wire al_1331d09b;
  wire al_4e123ffc;
  wire al_3010f43a;
  wire al_569c3dfd;
  wire al_47852ffd;
  wire al_bb7e8769;
  wire al_13d41bbb;
  wire al_b73f6920;
  wire al_56e826c8;
  wire al_7d7b01bf;
  wire al_9d06dea3;
  wire al_72cfbdcd;
  wire al_f59bea52;

  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_4453a271 (
    .a(al_b3e2b095),
    .b(al_ae97fd5e),
    .c(din_en),
    .d(al_9c667979[31]),
    .o(al_a8b23f08[0]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(32'h690069ff))
    al_2e1f07e5 (
    .a(al_74e73e),
    .b(al_98c67744),
    .c(al_7d62ea53),
    .d(din_en),
    .e(al_9c667979[21]),
    .o(al_a8b23f08[10]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_f416c962 (
    .a(al_193c437e),
    .b(din_en),
    .c(al_9c667979[20]),
    .o(al_a8b23f08[11]));
  AL_MAP_LUT5 #(
    .EQN("(~(C)*~(E)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(32'h90609f6f))
    al_12a3fc52 (
    .a(al_bced07d8),
    .b(din[16]),
    .c(din_en),
    .d(al_9c667979[15]),
    .e(al_9c667979[19]),
    .o(al_a8b23f08[12]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_1392d76d (
    .a(al_c5ac1b65),
    .b(din[0]),
    .c(din_en),
    .d(al_9c667979[18]),
    .o(al_a8b23f08[13]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_4b97d082 (
    .a(al_37c91d95),
    .b(al_b429b9f4),
    .c(din_en),
    .d(al_9c667979[17]),
    .o(al_a8b23f08[14]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_3631cae4 (
    .a(al_10fa1aaf),
    .b(din_en),
    .c(al_9c667979[16]),
    .o(al_a8b23f08[15]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(32'h960096ff))
    al_bdf98448 (
    .a(al_a3c00921),
    .b(al_d920e471),
    .c(al_8aa16c13),
    .d(din_en),
    .e(al_9c667979[15]),
    .o(al_a8b23f08[16]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+~(A)*B)"),
    .INIT(8'h47))
    al_10f10d04 (
    .a(al_4f2e6977),
    .b(din_en),
    .c(al_9c667979[14]),
    .o(al_a8b23f08[17]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_3fbd2f85 (
    .a(al_b378fb4c),
    .b(al_b49eba87),
    .c(din_en),
    .d(al_9c667979[13]),
    .o(al_a8b23f08[18]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_3e2e7ca9 (
    .a(al_a8b53724),
    .b(al_37c91d95),
    .c(din_en),
    .d(al_9c667979[12]),
    .o(al_a8b23f08[19]));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(C)+~(A)*B)"),
    .INIT(8'h45))
    al_bfe0a167 (
    .a(al_620ee392),
    .b(din_en),
    .c(al_9c667979[30]),
    .o(al_a8b23f08[1]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+~(A)*~(B)*C+A*B*C)"),
    .INIT(16'h909f))
    al_43d93fa6 (
    .a(al_b07e78e),
    .b(al_8d0029b9),
    .c(din_en),
    .d(al_9c667979[11]),
    .o(al_a8b23f08[20]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(32'h690069ff))
    al_eb27db9f (
    .a(al_20d7e1e),
    .b(al_ed2b4ef5),
    .c(al_47a34a8),
    .d(din_en),
    .e(al_9c667979[10]),
    .o(al_a8b23f08[21]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+~(A)*~(B)*C+A*B*C)"),
    .INIT(16'h909f))
    al_27436889 (
    .a(al_706b4c24),
    .b(al_4f2045c5),
    .c(din_en),
    .d(al_9c667979[9]),
    .o(al_a8b23f08[22]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_9089d93e (
    .a(al_5854a817),
    .b(al_54062695),
    .c(din_en),
    .d(al_9c667979[8]),
    .o(al_a8b23f08[23]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+~(A)*~(B)*C+A*B*C)"),
    .INIT(16'h909f))
    al_da9f02c (
    .a(al_109a1633),
    .b(al_21f3c606),
    .c(din_en),
    .d(al_9c667979[7]),
    .o(al_a8b23f08[24]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(32'h690069ff))
    al_d574ca53 (
    .a(al_5c4da1bf),
    .b(al_66c102d9),
    .c(al_c26603f1),
    .d(din_en),
    .e(al_9c667979[6]),
    .o(al_a8b23f08[25]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_6019e0e7 (
    .a(al_46dd1675),
    .b(al_a59c2b8),
    .c(din_en),
    .d(al_9c667979[5]),
    .o(al_a8b23f08[26]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(32'h960096ff))
    al_641fde69 (
    .a(al_c928032d),
    .b(al_2197e301),
    .c(al_73fb00f5),
    .d(din_en),
    .e(al_9c667979[4]),
    .o(al_a8b23f08[27]));
  AL_MAP_LUT5 #(
    .EQN("(~(D)*~(E)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(32'h690069ff))
    al_582d7767 (
    .a(al_ba83a52c),
    .b(al_7316f68e),
    .c(al_14fadafb),
    .d(din_en),
    .e(al_9c667979[3]),
    .o(al_a8b23f08[28]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_a4f5fe35 (
    .a(al_c5e914ef),
    .b(din_en),
    .c(al_9c667979[2]),
    .o(al_a8b23f08[29]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_6bf27b5a (
    .a(al_faeaa392),
    .b(din_en),
    .c(al_9c667979[29]),
    .o(al_a8b23f08[2]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A)"),
    .INIT(8'hab))
    al_311fe6b5 (
    .a(al_13d41bbb),
    .b(din_en),
    .c(al_9c667979[1]),
    .o(al_a8b23f08[30]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+~(A)*B)"),
    .INIT(8'h47))
    al_be898a53 (
    .a(al_72cfbdcd),
    .b(din_en),
    .c(al_9c667979[0]),
    .o(al_a8b23f08[31]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_360b04c9 (
    .a(al_c26603f1),
    .b(al_e3ddfbd3),
    .c(din_en),
    .d(al_9c667979[28]),
    .o(al_a8b23f08[3]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_1dac565f (
    .a(al_b3e2b095),
    .b(al_be5fe36),
    .c(din_en),
    .d(al_9c667979[27]),
    .o(al_a8b23f08[4]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_73ba0dd (
    .a(al_aeffe097),
    .b(din_en),
    .c(al_9c667979[26]),
    .o(al_a8b23f08[5]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A*B)"),
    .INIT(8'h8b))
    al_75979bdc (
    .a(al_3b9cba4e),
    .b(din_en),
    .c(al_9c667979[25]),
    .o(al_a8b23f08[6]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+~(A)*~(B)*C+A*B*C)"),
    .INIT(16'h909f))
    al_1cc7f1cc (
    .a(al_4ae694ef),
    .b(al_b378fb4c),
    .c(din_en),
    .d(al_9c667979[24]),
    .o(al_a8b23f08[7]));
  AL_MAP_LUT3 #(
    .EQN("(~(B)*~(C)+A)"),
    .INIT(8'hab))
    al_a0c4c256 (
    .a(al_891594a9),
    .b(din_en),
    .c(al_9c667979[23]),
    .o(al_a8b23f08[8]));
  AL_MAP_LUT4 #(
    .EQN("(~(C)*~(D)+A*~(B)*C+~(A)*B*C)"),
    .INIT(16'h606f))
    al_cfde7e69 (
    .a(al_7d62ea53),
    .b(al_47d18657),
    .c(din_en),
    .d(al_9c667979[22]),
    .o(al_a8b23f08[9]));
  AL_DFF_X al_199edd97 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[0]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[0]));
  AL_DFF_X al_db98af9 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[10]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[10]));
  AL_DFF_X al_ef38973 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[11]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[11]));
  AL_DFF_X al_7229c613 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[12]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[12]));
  AL_DFF_X al_8796c25 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[13]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[13]));
  AL_DFF_X al_296f034f (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[14]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[14]));
  AL_DFF_X al_7e297152 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[15]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[15]));
  AL_DFF_X al_538dc904 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[16]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[16]));
  AL_DFF_X al_f178516b (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[17]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[17]));
  AL_DFF_X al_f3e5d5b2 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[18]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[18]));
  AL_DFF_X al_ce77cbc1 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[19]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[19]));
  AL_DFF_X al_569525b7 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[1]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[1]));
  AL_DFF_X al_15ca617d (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[20]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[20]));
  AL_DFF_X al_793ea41 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[21]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[21]));
  AL_DFF_X al_a7afb08d (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[22]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[22]));
  AL_DFF_X al_5b915821 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[23]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[23]));
  AL_DFF_X al_9b993a05 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[24]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[24]));
  AL_DFF_X al_bb74f270 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[25]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[25]));
  AL_DFF_X al_1ca13994 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[26]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[26]));
  AL_DFF_X al_b66fc110 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[27]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[27]));
  AL_DFF_X al_65525337 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[28]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[28]));
  AL_DFF_X al_cb1ed8e4 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[29]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[29]));
  AL_DFF_X al_b97e5230 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[2]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[2]));
  AL_DFF_X al_a04dea9b (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[30]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[30]));
  AL_DFF_X al_cb784fe7 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[31]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[31]));
  AL_DFF_X al_6423af54 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[3]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[3]));
  AL_DFF_X al_3651b565 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[4]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[4]));
  AL_DFF_X al_492963db (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[5]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[5]));
  AL_DFF_X al_79d25576 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[6]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[6]));
  AL_DFF_X al_820af518 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[7]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[7]));
  AL_DFF_X al_44257690 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[8]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[8]));
  AL_DFF_X al_9972b776 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_a8b23f08[9]),
    .en(packet_end),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out[9]));
  AL_DFF_X al_544c6c43 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(packet_end),
    .en(1'b1),
    .sr(1'b0),
    .ss(1'b0),
    .q(crc_out_vld));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_46aa3c88 (
    .a(din[3]),
    .b(din[1]),
    .c(al_9c667979[28]),
    .d(al_9c667979[30]),
    .o(al_7d7b01bf));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_b26d85a8 (
    .a(din[25]),
    .b(din[19]),
    .c(din[6]),
    .d(al_9c667979[6]),
    .e(al_9c667979[12]),
    .f(al_9c667979[25]),
    .o(al_9d06dea3));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_e80713a (
    .a(al_924ea640),
    .b(al_81097bd3),
    .c(al_6bf245d5),
    .d(al_7d7b01bf),
    .e(al_9d06dea3),
    .o(al_72cfbdcd));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_ffeb8fa3 (
    .a(al_104976d9),
    .b(din[19]),
    .c(din[6]),
    .d(din[1]),
    .o(al_f59bea52));
  AL_MAP_LUT6 #(
    .EQN("(A*~(F)+B*~(C)*~(D)*F+~(B)*C*~(D)*F+~(B)*~(C)*D*F+B*C*D*F+~(E))"),
    .INIT(64'hc33cffffaaaaffff))
    al_78fcb05f (
    .a(al_72cfbdcd),
    .b(al_f59bea52),
    .c(al_53c3c716),
    .d(al_81097bd3),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[0]));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_95bb2fc1 (
    .a(al_81097bd3),
    .b(al_6bf245d5),
    .o(al_20d7e1e));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_b4a91637 (
    .a(al_2eaa0831),
    .b(al_98d82759),
    .c(al_6b1f677f),
    .d(din[29]),
    .e(din[26]),
    .f(al_9c667979[2]),
    .o(al_ed2b4ef5));
  AL_MAP_LUT3 #(
    .EQN("(A*~(B)*~(C)+~(A)*B*~(C)+~(A)*~(B)*C+A*B*C)"),
    .INIT(8'h96))
    al_63471ecc (
    .a(din[29]),
    .b(din[26]),
    .c(din[18]),
    .o(al_16f38f00));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_7f4254b3 (
    .a(al_5bfbcd40),
    .b(al_81097bd3),
    .c(al_16f38f00),
    .d(din[28]),
    .e(din[17]),
    .f(din[3]),
    .o(al_a57150ce));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(D)*E*~(F)+~(A)*B*~(D)*E*~(F)+~(A)*~(B)*D*E*~(F)+A*B*D*E*~(F)+C*E*F)"),
    .INIT(64'hf0f0000099660000))
    al_5e68c402 (
    .a(al_20d7e1e),
    .b(al_ed2b4ef5),
    .c(al_a57150ce),
    .d(al_47a34a8),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[10]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_799374b1 (
    .a(din[31]),
    .b(din[15]),
    .c(din[5]),
    .d(al_9c667979[0]),
    .e(al_9c667979[16]),
    .f(al_9c667979[26]),
    .o(al_39132e63));
  AL_MAP_LUT6 #(
    .EQN("(A*B*~(C)*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+A*B*~(C)*D*E*~(F)+~(A)*B*C*D*E*~(F)+~(A)*B*~(C)*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+A*B*~(C)*D*~(E)*F+~(A)*B*C*D*~(E)*F+A*B*~(C)*~(D)*E*F+~(A)*B*C*~(D)*E*F+~(A)*B*~(C)*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h8448488448848448))
    al_a488644d (
    .a(al_4e123ffc),
    .b(al_9213e63),
    .c(al_bd3e6902),
    .d(al_23783854),
    .e(al_7d800c96),
    .f(din[5]),
    .o(al_a6e8fef4));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(E)+~(A)*B*~(E)+~(D)+C)"),
    .INIT(32'hf0fff6ff))
    al_1572e20a (
    .a(al_b07e78e),
    .b(al_8d0029b9),
    .c(al_a6e8fef4),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[11]));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_dac17b15 (
    .a(al_f6981785),
    .b(al_39132e63),
    .o(al_b07e78e));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_cf131015 (
    .a(din[17]),
    .b(din[6]),
    .c(al_9c667979[14]),
    .d(al_9c667979[25]),
    .o(al_f6ba4b08));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_8f6e9ebc (
    .a(al_3010f43a),
    .b(al_2f1a5af3),
    .c(al_f59e83cb),
    .d(al_f6ba4b08),
    .e(al_eb2816e2),
    .o(al_8d0029b9));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_78fcea07 (
    .a(din[28]),
    .b(din[17]),
    .c(din[6]),
    .d(din[3]),
    .o(al_7d800c96));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_b0c687a1 (
    .a(din[29]),
    .b(din[27]),
    .c(al_9c667979[2]),
    .d(al_9c667979[4]),
    .o(al_5ca66c5d));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_51ea7b6 (
    .a(al_3010f43a),
    .b(al_eb2816e2),
    .c(al_dc3a3160),
    .d(al_10ab4c6d),
    .e(al_5ca66c5d),
    .o(al_a8b53724));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_74213ac4 (
    .a(al_bd3e6902),
    .b(al_d0b8020),
    .c(al_a02591ed),
    .d(din[31]),
    .e(din[27]),
    .f(din[1]),
    .o(al_df67b5a5));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*D*~(E)+A*B*D*~(E)+~(C)*D*E)"),
    .INIT(32'h0f009900))
    al_cb2b2670 (
    .a(al_a8b53724),
    .b(al_37c91d95),
    .c(al_df67b5a5),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[12]));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_927af59b (
    .a(din[28]),
    .b(din[3]),
    .c(al_9c667979[3]),
    .d(al_9c667979[28]),
    .e(al_9c667979[31]),
    .o(al_889d0a3));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_d9f51af9 (
    .a(al_889d0a3),
    .b(al_728efc21),
    .c(al_dc3a3160),
    .d(al_2fc445a4),
    .e(al_50aa637d),
    .o(al_b49eba87));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_556ad434 (
    .a(al_d61dbbe2),
    .b(al_585b9892),
    .c(din[30]),
    .d(din[26]),
    .e(din[15]),
    .f(din[0]),
    .o(al_1f926e6c));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+~(C)*E+~(D))"),
    .INIT(32'h0fff99ff))
    al_c0a4dd7a (
    .a(al_b378fb4c),
    .b(al_b49eba87),
    .c(al_1f926e6c),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[13]));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_eacc2312 (
    .a(din[21]),
    .b(al_9c667979[10]),
    .o(al_7316f68e));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_ab912dc6 (
    .a(al_7316f68e),
    .b(al_14fadafb),
    .c(din[15]),
    .d(din[13]),
    .e(al_9c667979[16]),
    .f(al_9c667979[18]),
    .o(al_b378fb4c));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_e212de16 (
    .a(din[29]),
    .b(din[24]),
    .c(din[21]),
    .d(din[17]),
    .e(din[13]),
    .f(din[12]),
    .o(al_d61dbbe2));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_1d777ff0 (
    .a(din[26]),
    .b(din[12]),
    .c(din[0]),
    .d(al_9c667979[19]),
    .o(al_50aa637d));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_25ad1252 (
    .a(din[28]),
    .b(din[23]),
    .c(din[14]),
    .d(al_9c667979[3]),
    .e(al_9c667979[17]),
    .o(al_a4c81ae));
  AL_MAP_LUT4 #(
    .EQN("(~(B)*C*D+A*~(B)*C)"),
    .INIT(16'h3020))
    al_782c78ca (
    .a(al_4f2e6977),
    .b(al_9006e254),
    .c(din_en),
    .d(packet_start),
    .o(al_b925cf5b[14]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_d6d668c9 (
    .a(al_fb2a9898),
    .b(al_56c4fcba),
    .c(al_a4c81ae),
    .d(al_14fadafb),
    .e(al_73fb00f5),
    .f(al_abf75a68),
    .o(al_4f2e6977));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_f24dd9c1 (
    .a(din[28]),
    .b(din[23]),
    .c(din[14]),
    .o(al_3a652dd7));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_3f821c48 (
    .a(din[16]),
    .b(din[12]),
    .c(din[8]),
    .d(din[5]),
    .o(al_dfbc5200));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96690000))
    al_ffed48e6 (
    .a(al_3a652dd7),
    .b(al_fe60cde9),
    .c(al_a05eef16),
    .d(al_dfbc5200),
    .e(packet_start),
    .o(al_9006e254));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_5c87da14 (
    .a(din[27]),
    .b(din[11]),
    .c(al_9c667979[4]),
    .d(al_9c667979[20]),
    .o(al_f59e83cb));
  AL_MAP_LUT3 #(
    .EQN("(A*~(B)*~(C)+~(A)*B*~(C)+~(A)*~(B)*C+A*B*C)"),
    .INIT(8'h96))
    al_c761af7b (
    .a(al_ccef2d2d),
    .b(din[28]),
    .c(al_9c667979[3]),
    .o(al_d920e471));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_88e13c8b (
    .a(din[22]),
    .b(din[15]),
    .c(din[13]),
    .d(al_9c667979[9]),
    .e(al_9c667979[16]),
    .f(al_9c667979[18]),
    .o(al_6dcbba55));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_6cc25d5e (
    .a(al_f59e83cb),
    .b(al_eb2816e2),
    .c(al_6dcbba55),
    .o(al_8aa16c13));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_44ad1930 (
    .a(din[22]),
    .b(din[15]),
    .c(din[13]),
    .d(din[4]),
    .o(al_c65c44d8));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_564a33ee (
    .a(al_23783854),
    .b(al_3ef0c0d8),
    .c(al_c65c44d8),
    .d(din[28]),
    .e(din[24]),
    .f(din[16]),
    .o(al_c4b11ed6));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(F)+A*B*~(C)*~(F)+A*~(B)*C*~(F)+~(A)*B*C*~(F)+~(D)*F+~(E))"),
    .INIT(64'h00ffffff6969ffff))
    al_205dc494 (
    .a(al_a3c00921),
    .b(al_d920e471),
    .c(al_8aa16c13),
    .d(al_c4b11ed6),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[15]));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_8e757451 (
    .a(din[16]),
    .b(din[7]),
    .c(al_9c667979[15]),
    .d(al_9c667979[24]),
    .o(al_eb2816e2));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_b53b7e01 (
    .a(din[27]),
    .b(din[19]),
    .c(din[11]),
    .d(din[7]),
    .o(al_23783854));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_a4f85b8 (
    .a(din[26]),
    .b(din[23]),
    .c(din[10]),
    .d(din[1]),
    .o(al_3ef0c0d8));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_d667e31 (
    .a(al_569c3dfd),
    .b(al_e529755e),
    .o(al_a3c00921));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_cd578eab (
    .a(din[12]),
    .b(din[2]),
    .o(al_5bfbcd40));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_2cb34745 (
    .a(din[31]),
    .b(din[26]),
    .c(din[10]),
    .d(al_9c667979[0]),
    .e(al_9c667979[21]),
    .o(al_10ab4c6d));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_da238ab7 (
    .a(din[27]),
    .b(din[7]),
    .c(din[2]),
    .d(al_9c667979[4]),
    .e(al_9c667979[24]),
    .f(al_9c667979[29]),
    .o(al_36b577e1));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_b3828b44 (
    .a(al_98d82759),
    .b(al_ade5815),
    .c(al_2fa168c5),
    .d(al_10ab4c6d),
    .e(al_36b577e1),
    .f(al_ccef2d2d),
    .o(al_10fa1aaf));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_dcde7b2c (
    .a(al_5bfbcd40),
    .b(al_3ef0c0d8),
    .c(din[31]),
    .d(din[27]),
    .e(din[19]),
    .f(din[7]),
    .o(al_fdb48e41));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(E)+~(B)*~(C)*E+B*C*E+~(D))"),
    .INIT(32'hc3ff55ff))
    al_9cc5c5ea (
    .a(al_10fa1aaf),
    .b(al_fdb48e41),
    .c(al_78a5bd30),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[16]));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_f5d78ac9 (
    .a(din[18]),
    .b(din[14]),
    .c(din[9]),
    .d(din[5]),
    .e(al_9c667979[26]),
    .o(al_ade5815));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_efac1d83 (
    .a(al_9c667979[5]),
    .b(al_9c667979[13]),
    .c(al_9c667979[17]),
    .d(al_9c667979[22]),
    .o(al_2fa168c5));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_8fdc1e71 (
    .a(din[18]),
    .b(din[14]),
    .c(din[9]),
    .d(din[5]),
    .o(al_78a5bd30));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_67a1a46b (
    .a(din[12]),
    .b(al_9c667979[19]),
    .o(al_98d82759));
  AL_MAP_LUT2 #(
    .EQN("(A*B)"),
    .INIT(4'h8))
    al_d44b6fbd (
    .a(din_en),
    .b(packet_start),
    .o(al_9213e63));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_6c8b0698 (
    .a(al_f6981785),
    .b(al_480fc418),
    .c(din[1]),
    .d(al_9c667979[30]),
    .o(al_37c91d95));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_e1045c74 (
    .a(din[25]),
    .b(din[18]),
    .c(din[13]),
    .o(al_d0b8020));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_6e40502e (
    .a(din[11]),
    .b(din[9]),
    .c(din[6]),
    .d(al_9c667979[20]),
    .e(al_9c667979[22]),
    .f(al_9c667979[25]),
    .o(al_8792b600));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_e71e51a0 (
    .a(din[22]),
    .b(din[17]),
    .c(din[4]),
    .d(din[0]),
    .o(al_dd91ce5));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_97a313b (
    .a(al_2eaa0831),
    .b(al_728efc21),
    .c(al_dc3a3160),
    .d(al_8792b600),
    .e(al_d9bfd92f),
    .o(al_b429b9f4));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_5c7d06e6 (
    .a(din[30]),
    .b(din[26]),
    .c(din[11]),
    .d(din[9]),
    .e(din[8]),
    .f(din[6]),
    .o(al_e2e17f54));
  AL_MAP_LUT5 #(
    .EQN("(A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+A*B*C*~(D)*E+A*B*~(C)*D*E+A*~(B)*C*D*E)"),
    .INIT(32'h28828228))
    al_5fdeb3f1 (
    .a(al_9213e63),
    .b(al_d0b8020),
    .c(al_dd91ce5),
    .d(al_e2e17f54),
    .e(din[1]),
    .o(al_bcc2d142));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*D*~(E)+A*B*D*~(E)+C)"),
    .INIT(32'hf0f0f9f0))
    al_1957e792 (
    .a(al_37c91d95),
    .b(al_b429b9f4),
    .c(al_bcc2d142),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[17]));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_c48dd89e (
    .a(din[30]),
    .b(al_9c667979[1]),
    .o(al_728efc21));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_c768f130 (
    .a(din[13]),
    .b(al_9c667979[18]),
    .o(al_480fc418));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_a110217d (
    .a(din[17]),
    .b(al_9c667979[14]),
    .o(al_2eaa0831));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_4d89fbd8 (
    .a(din[25]),
    .b(din[18]),
    .c(al_9c667979[5]),
    .d(al_9c667979[6]),
    .e(al_9c667979[13]),
    .o(al_dc3a3160));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_6edd10e7 (
    .a(din[25]),
    .b(din[7]),
    .c(al_9c667979[6]),
    .d(al_9c667979[24]),
    .o(al_400edb29));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_fae0a1db (
    .a(al_7316f68e),
    .b(al_14fadafb),
    .c(al_75f0d032),
    .d(al_400edb29),
    .e(al_4726cb06),
    .f(al_a1989f7d),
    .o(al_c5ac1b65));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_36593390 (
    .a(din[25]),
    .b(din[21]),
    .c(din[16]),
    .d(din[12]),
    .e(din[7]),
    .f(din[3]),
    .o(al_4a7dff61));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_c67557c9 (
    .a(al_fe60cde9),
    .b(al_3f47ae94),
    .c(al_4a7dff61),
    .d(din[10]),
    .o(al_a7d54dac));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(C)*D*~(E)+A*C*D*~(E)+~(B)*~(C)*D*E+B*C*D*E)"),
    .INIT(32'hc300a500))
    al_fefc6186 (
    .a(al_c5ac1b65),
    .b(al_a7d54dac),
    .c(din[0]),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[18]));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_63e9a4cc (
    .a(al_9c44f52e),
    .b(al_569c3dfd),
    .c(al_8792b600),
    .d(al_2a6117da),
    .e(din[15]),
    .f(al_9c667979[16]),
    .o(al_bced07d8));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_c5134974 (
    .a(al_6a5c7bf3),
    .b(al_fc312581),
    .c(din[28]),
    .d(din[24]),
    .e(din[23]),
    .f(din[15]),
    .o(al_a9b750a));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(C)*D*~(E)*~(F)+A*C*D*~(E)*~(F)+A*~(C)*D*~(E)*F+~(A)*C*D*~(E)*F+B*~(C)*D*E+~(B)*C*D*E)"),
    .INIT(64'h3c005a003c00a500))
    al_c6df8751 (
    .a(al_bced07d8),
    .b(al_a9b750a),
    .c(din[16]),
    .d(din_en),
    .e(packet_start),
    .f(al_9c667979[15]),
    .o(al_b925cf5b[19]));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_da83532c (
    .a(din[31]),
    .b(din[15]),
    .o(al_4e123ffc));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699600000000))
    al_f2af5287 (
    .a(al_47852ffd),
    .b(al_3010f43a),
    .c(al_569c3dfd),
    .d(al_bb7e8769),
    .e(al_20893c30),
    .f(din_en),
    .o(al_13d41bbb));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_723e088a (
    .a(al_4e123ffc),
    .b(din[30]),
    .c(din[22]),
    .d(din[14]),
    .e(din[4]),
    .o(al_b73f6920));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_7124f27d (
    .a(al_53c3c716),
    .b(din[24]),
    .c(din[20]),
    .d(din[19]),
    .e(din[18]),
    .f(din[7]),
    .o(al_56e826c8));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(D)+B*~(C)*D+~(B)*C*D)"),
    .INIT(16'h3c55))
    al_52760a13 (
    .a(al_13d41bbb),
    .b(al_b73f6920),
    .c(al_56e826c8),
    .d(al_9213e63),
    .o(al_b925cf5b[1]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_fe3f8fd9 (
    .a(din[30]),
    .b(din[19]),
    .c(din[14]),
    .d(al_9c667979[1]),
    .e(al_9c667979[12]),
    .f(al_9c667979[17]),
    .o(al_3010f43a));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_ac512d6f (
    .a(din[24]),
    .b(din[4]),
    .c(al_9c667979[7]),
    .d(al_9c667979[27]),
    .o(al_569c3dfd));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_ca2b3f37 (
    .a(din[31]),
    .b(din[15]),
    .c(al_9c667979[0]),
    .d(al_9c667979[16]),
    .o(al_47852ffd));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_d2e8810a (
    .a(din[22]),
    .b(din[20]),
    .c(din[3]),
    .d(al_9c667979[9]),
    .e(al_9c667979[11]),
    .f(al_9c667979[28]),
    .o(al_bb7e8769));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_d04d5381 (
    .a(din[10]),
    .b(al_9c667979[21]),
    .o(al_4726cb06));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_fa4b5310 (
    .a(al_3f47ae94),
    .b(al_45ef761c),
    .c(al_9fdf1e71),
    .d(din[27]),
    .e(din[19]),
    .f(din[10]),
    .o(al_41557436));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(D)+~(B)*D+~(C))"),
    .INIT(16'h3f5f))
    al_97fc722f (
    .a(al_193c437e),
    .b(al_41557436),
    .c(din_en),
    .d(packet_start),
    .o(al_b925cf5b[20]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_af29db32 (
    .a(din[8]),
    .b(din[5]),
    .c(din[3]),
    .d(al_9c667979[23]),
    .e(al_9c667979[26]),
    .f(al_9c667979[28]),
    .o(al_a1989f7d));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_9e84a77 (
    .a(din[15]),
    .b(din[14]),
    .c(din[6]),
    .d(al_9c667979[16]),
    .e(al_9c667979[17]),
    .f(al_9c667979[25]),
    .o(al_3f80181));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_554f9aab (
    .a(al_4726cb06),
    .b(al_a1989f7d),
    .c(al_ccef2d2d),
    .d(al_3f80181),
    .e(al_fb75046b),
    .o(al_193c437e));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_80a2af18 (
    .a(din[22]),
    .b(din[15]),
    .c(din[14]),
    .d(din[6]),
    .o(al_9fdf1e71));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_365f4402 (
    .a(al_924ea640),
    .b(din[26]),
    .o(al_74e73e));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_bb949485 (
    .a(al_ade5815),
    .b(al_2fa168c5),
    .o(al_98c67744));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_44295236 (
    .a(al_2f32596b),
    .b(al_104976d9),
    .c(al_78a5bd30),
    .d(din[26]),
    .e(din[13]),
    .o(al_58f667d1));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(F)+~(A)*B*~(C)*~(F)+~(A)*~(B)*C*~(F)+A*B*C*~(F)+~(D)*F+~(E))"),
    .INIT(64'h00ffffff9696ffff))
    al_77f68374 (
    .a(al_74e73e),
    .b(al_98c67744),
    .c(al_7d62ea53),
    .d(al_58f667d1),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[21]));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_336b9d6 (
    .a(al_f6981785),
    .b(al_480fc418),
    .o(al_7d62ea53));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_71b5f884 (
    .a(al_47852ffd),
    .b(al_2eaa0831),
    .c(al_9c44f52e),
    .d(al_7354420),
    .e(din[19]),
    .f(al_9c667979[12]),
    .o(al_47d18657));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699600000000))
    al_abb4d54a (
    .a(al_4e123ffc),
    .b(al_6a5c7bf3),
    .c(al_b4471c3b),
    .d(al_dd91ce5),
    .e(din[19]),
    .f(packet_start),
    .o(al_f52af87e));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+~(D)+C)"),
    .INIT(32'hf0fff9ff))
    al_dfac8b4d (
    .a(al_7d62ea53),
    .b(al_47d18657),
    .c(al_f52af87e),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[22]));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966900000000))
    al_aa1491b5 (
    .a(al_f6981785),
    .b(al_39132e63),
    .c(al_6ee39c47),
    .d(al_46f7f1f6),
    .e(al_fb2a9898),
    .f(din_en),
    .o(al_891594a9));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_25926ca5 (
    .a(al_4e123ffc),
    .b(al_bd3e6902),
    .c(din[5]),
    .o(al_819a2685));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_178919f6 (
    .a(din[25]),
    .b(din[18]),
    .o(al_ce83e092));
  AL_MAP_LUT6 #(
    .EQN("(B*~(C)*D*~(E)*~(F)+~(B)*C*D*~(E)*~(F)+~(B)*~(C)*D*E*~(F)+B*C*D*E*~(F)+~(B)*~(C)*D*~(E)*F+B*C*D*~(E)*F+B*~(C)*D*E*F+~(B)*C*D*E*F+~(A)*~(D))"),
    .INIT(64'h3c55c355c3553c55))
    al_c303c536 (
    .a(al_891594a9),
    .b(al_819a2685),
    .c(al_ce83e092),
    .d(al_9213e63),
    .e(al_5bfbcd40),
    .f(din[11]),
    .o(al_b925cf5b[23]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_f5b0ef6c (
    .a(din[30]),
    .b(din[14]),
    .c(din[11]),
    .d(al_9c667979[1]),
    .e(al_9c667979[17]),
    .f(al_9c667979[20]),
    .o(al_6ee39c47));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_752142de (
    .a(al_6ee39c47),
    .b(al_4726cb06),
    .c(al_7d7b01bf),
    .d(din[4]),
    .e(al_9c667979[27]),
    .o(al_4ae694ef));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_4b048d88 (
    .a(din[30]),
    .b(din[15]),
    .c(din[14]),
    .d(din[13]),
    .e(din[3]),
    .f(din[1]),
    .o(al_b15c20bc));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_7156e9d (
    .a(al_fe60cde9),
    .b(al_b15c20bc),
    .c(din[21]),
    .d(din[11]),
    .e(din[10]),
    .f(din[4]),
    .o(al_c665ec5d));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(E)+~(A)*B*~(E)+~(C)*E+~(D))"),
    .INIT(32'h0fff66ff))
    al_45e482c9 (
    .a(al_4ae694ef),
    .b(al_b378fb4c),
    .c(al_c665ec5d),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[24]));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_9669d8a (
    .a(din[16]),
    .b(din[12]),
    .c(din[2]),
    .d(al_9c667979[15]),
    .e(al_9c667979[19]),
    .f(al_9c667979[29]),
    .o(al_fb2a9898));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_96878c32 (
    .a(al_911f6fe9),
    .b(din[29]),
    .c(din[16]),
    .d(din[13]),
    .e(din[10]),
    .o(al_c74a9571));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_e6d3e94b (
    .a(al_5bfbcd40),
    .b(din[28]),
    .c(din[20]),
    .d(din[3]),
    .o(al_ae74637d));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(E)+~(B)*~(C)*E+B*C*E+~(D))"),
    .INIT(32'hc3ff55ff))
    al_da68978d (
    .a(al_3b9cba4e),
    .b(al_c74a9571),
    .c(al_ae74637d),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[25]));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_e42a57bd (
    .a(din[20]),
    .b(al_9c667979[8]),
    .c(al_9c667979[11]),
    .o(al_56c4fcba));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_9f95df67 (
    .a(din[23]),
    .b(din[14]),
    .c(din[9]),
    .d(din[0]),
    .o(al_911f6fe9));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_d22f79a1 (
    .a(din[10]),
    .b(al_9c667979[17]),
    .c(al_9c667979[21]),
    .d(al_9c667979[22]),
    .o(al_e64626b6));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_3740a141 (
    .a(al_fb2a9898),
    .b(al_889d0a3),
    .c(al_56c4fcba),
    .d(al_f17c516b),
    .e(al_911f6fe9),
    .f(al_e64626b6),
    .o(al_3b9cba4e));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_7ec7a5b2 (
    .a(din[31]),
    .b(din[21]),
    .c(din[0]),
    .d(al_9c667979[0]),
    .e(al_9c667979[10]),
    .o(al_8120bf4d));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_357f1ddc (
    .a(al_cbc0c746),
    .b(din[28]),
    .c(din[21]),
    .d(din[7]),
    .e(din[3]),
    .o(al_bcee4da4));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*E*~(F)+~(B)*~(C)*~(D)*E*F+B*C*~(D)*E*F+B*~(C)*D*E*F+~(B)*C*D*E*F)"),
    .INIT(64'h3cc3000055550000))
    al_4e9cc0ca (
    .a(al_aeffe097),
    .b(al_bcee4da4),
    .c(al_b4471c3b),
    .d(al_827e1925),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[26]));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_db824c8e (
    .a(din[12]),
    .b(din[8]),
    .c(din[5]),
    .d(al_9c667979[19]),
    .e(al_9c667979[23]),
    .f(al_9c667979[26]),
    .o(al_7354420));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_753e6fb8 (
    .a(din[13]),
    .b(din[12]),
    .c(din[8]),
    .d(din[5]),
    .o(al_b4471c3b));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_7fd37929 (
    .a(din[13]),
    .b(din[7]),
    .c(al_9c667979[18]),
    .d(al_9c667979[24]),
    .o(al_d8a36d67));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_d99df4a5 (
    .a(al_889d0a3),
    .b(al_8120bf4d),
    .c(al_73fb00f5),
    .d(al_7354420),
    .e(al_2fc445a4),
    .f(al_d8a36d67),
    .o(al_aeffe097));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_875c4853 (
    .a(al_f59e83cb),
    .b(al_7354420),
    .c(al_728efc21),
    .d(al_569c3dfd),
    .e(al_e529755e),
    .o(al_be5fe36));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_dac3c4d2 (
    .a(al_95ae97c3),
    .b(al_f30b825d),
    .c(al_6ce87b4e),
    .d(din[26]),
    .e(din[10]),
    .o(al_14cbbec8));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+~(C)*E+~(D))"),
    .INIT(32'h0fff99ff))
    al_c5f19ec3 (
    .a(al_b3e2b095),
    .b(al_be5fe36),
    .c(al_14cbbec8),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[27]));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_134ec923 (
    .a(din[26]),
    .b(din[10]),
    .c(al_9c667979[5]),
    .d(al_9c667979[21]),
    .o(al_e529755e));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_a22dbd71 (
    .a(din[11]),
    .b(din[9]),
    .c(din[6]),
    .d(din[4]),
    .o(al_fc312581));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_9e428b1f (
    .a(din[25]),
    .b(din[3]),
    .o(al_53c3c716));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_3308bc59 (
    .a(din[4]),
    .b(al_9c667979[6]),
    .c(al_9c667979[27]),
    .d(al_9c667979[28]),
    .o(al_6bf6a16c));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_68f56ad3 (
    .a(din[29]),
    .b(din[7]),
    .c(din[5]),
    .d(al_9c667979[2]),
    .e(al_9c667979[24]),
    .f(al_9c667979[26]),
    .o(al_f92431fb));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_a40f95f5 (
    .a(al_53c3c716),
    .b(al_ccef2d2d),
    .c(al_6bf6a16c),
    .d(al_f92431fb),
    .e(din[11]),
    .f(al_9c667979[20]),
    .o(al_e3ddfbd3));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_efb9b9d3 (
    .a(din[25]),
    .b(din[23]),
    .c(din[5]),
    .d(din[3]),
    .e(din[1]),
    .o(al_89178476));
  AL_MAP_LUT3 #(
    .EQN("(A*~(B)*~(C)+~(A)*B*~(C)+~(A)*~(B)*C+A*B*C)"),
    .INIT(8'h96))
    al_45431a14 (
    .a(al_a02591ed),
    .b(al_fc312581),
    .c(al_89178476),
    .o(al_b8fb48ff));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+C*E+~(D))"),
    .INIT(32'hf0ff99ff))
    al_aac2a844 (
    .a(al_c26603f1),
    .b(al_e3ddfbd3),
    .c(al_b8fb48ff),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[28]));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_bce313e4 (
    .a(din[9]),
    .b(din[6]),
    .c(al_9c667979[22]),
    .d(al_9c667979[25]),
    .o(al_2fc445a4));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_dc221a7a (
    .a(al_e529755e),
    .b(al_2fc445a4),
    .o(al_c26603f1));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_35eefd27 (
    .a(din[29]),
    .b(din[26]),
    .c(din[19]),
    .d(din[10]),
    .e(din[7]),
    .o(al_a02591ed));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_babfe3c8 (
    .a(din[23]),
    .b(din[19]),
    .c(din[1]),
    .d(al_9c667979[8]),
    .e(al_9c667979[12]),
    .f(al_9c667979[30]),
    .o(al_ccef2d2d));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_22457413 (
    .a(din[25]),
    .b(din[18]),
    .c(al_9c667979[6]),
    .d(al_9c667979[13]),
    .o(al_46f7f1f6));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_1a17d383 (
    .a(din[24]),
    .b(din[10]),
    .c(al_9c667979[7]),
    .d(al_9c667979[21]),
    .o(al_a0f5191c));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_d1b20a1b (
    .a(al_f6981785),
    .b(al_46f7f1f6),
    .c(al_abf75a68),
    .d(al_47a34a8),
    .e(al_2fc445a4),
    .f(al_a0f5191c),
    .o(al_faeaa392));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_c068d61e (
    .a(al_2f32596b),
    .b(al_3f47ae94),
    .c(din[24]),
    .d(din[10]),
    .e(din[2]),
    .o(al_ac44599e));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*D*~(E)+~(B)*~(C)*D*E+B*C*D*E)"),
    .INIT(32'hc3005500))
    al_fac42217 (
    .a(al_faeaa392),
    .b(al_ac44599e),
    .c(al_585b9892),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[29]));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_d65c6c67 (
    .a(din[8]),
    .b(din[5]),
    .c(al_9c667979[23]),
    .d(al_9c667979[26]),
    .o(al_abf75a68));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_5d540a31 (
    .a(din[8]),
    .b(din[5]),
    .o(al_3f47ae94));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_dd8619b5 (
    .a(din[28]),
    .b(din[3]),
    .c(din[2]),
    .d(al_9c667979[3]),
    .e(al_9c667979[28]),
    .f(al_9c667979[29]),
    .o(al_47a34a8));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_f3dd3529 (
    .a(din[28]),
    .b(din[25]),
    .c(din[18]),
    .d(din[9]),
    .e(din[6]),
    .f(din[3]),
    .o(al_585b9892));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_9b385aad (
    .a(din[29]),
    .b(din[24]),
    .c(din[17]),
    .d(al_9c667979[2]),
    .e(al_9c667979[7]),
    .f(al_9c667979[14]),
    .o(al_14fadafb));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_5173b346 (
    .a(din[25]),
    .b(din[18]),
    .c(din[7]),
    .d(al_9c667979[6]),
    .e(al_9c667979[13]),
    .f(al_9c667979[24]),
    .o(al_20893c30));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_392aeaeb (
    .a(al_14fadafb),
    .b(al_81097bd3),
    .c(al_6bf245d5),
    .d(al_ca940860),
    .e(al_20893c30),
    .f(al_9b8401f),
    .o(al_c5e914ef));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_68161877 (
    .a(din[30]),
    .b(din[23]),
    .c(din[14]),
    .d(din[7]),
    .e(din[1]),
    .o(al_5a8c08c5));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_9553d8a8 (
    .a(al_fe60cde9),
    .b(al_81097bd3),
    .c(al_d0b8020),
    .d(al_5a8c08c5),
    .o(al_1331d09b));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(D)+~(B)*D+~(C))"),
    .INIT(16'h3f5f))
    al_18b09f48 (
    .a(al_c5e914ef),
    .b(al_1331d09b),
    .c(din_en),
    .d(packet_start),
    .o(al_b925cf5b[2]));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_306bc25f (
    .a(din[29]),
    .b(din[24]),
    .c(din[17]),
    .o(al_fe60cde9));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_3069f671 (
    .a(din[31]),
    .b(din[22]),
    .c(din[15]),
    .d(din[5]),
    .e(din[0]),
    .o(al_81097bd3));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_5cc29a0b (
    .a(al_9c667979[0]),
    .b(al_9c667979[9]),
    .c(al_9c667979[16]),
    .d(al_9c667979[26]),
    .e(al_9c667979[31]),
    .o(al_6bf245d5));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_c8f73a8b (
    .a(din[30]),
    .b(din[14]),
    .c(din[13]),
    .d(al_9c667979[1]),
    .e(al_9c667979[17]),
    .f(al_9c667979[18]),
    .o(al_9b8401f));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_f35f05c (
    .a(din[24]),
    .b(din[8]),
    .c(din[5]),
    .d(din[4]),
    .o(al_f30b825d));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_b959d941 (
    .a(din[27]),
    .b(din[17]),
    .c(din[9]),
    .d(al_9c667979[4]),
    .e(al_9c667979[14]),
    .f(al_9c667979[22]),
    .o(al_24b5356f));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966900000000))
    al_84ab45e8 (
    .a(al_a1989f7d),
    .b(al_569c3dfd),
    .c(al_924ea640),
    .d(al_ca940860),
    .e(al_24b5356f),
    .f(din_en),
    .o(al_620ee392));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_a88935d9 (
    .a(al_45ef761c),
    .b(din[27]),
    .c(din[17]),
    .d(din[9]),
    .o(al_860501d));
  AL_MAP_LUT5 #(
    .EQN("(~(B)*C*~(D)*~(E)+B*C*D*~(E)+B*C*~(D)*E+~(B)*C*D*E+A*~(C))"),
    .INIT(32'h3acaca3a))
    al_4a7a60c1 (
    .a(al_620ee392),
    .b(al_860501d),
    .c(al_9213e63),
    .d(al_f30b825d),
    .e(al_104976d9),
    .o(al_b925cf5b[30]));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_96f287da (
    .a(din[22]),
    .b(din[4]),
    .c(din[0]),
    .d(al_9c667979[9]),
    .e(al_9c667979[27]),
    .f(al_9c667979[31]),
    .o(al_f6981785));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_c38c03e0 (
    .a(din[26]),
    .b(din[8]),
    .c(al_9c667979[23]),
    .o(al_d9bfd92f));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_d0850502 (
    .a(din[16]),
    .b(din[3]),
    .c(al_9c667979[5]),
    .d(al_9c667979[15]),
    .e(al_9c667979[28]),
    .o(al_1b1db758));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_d9d988ab (
    .a(al_f6981785),
    .b(al_ca940860),
    .c(al_d9bfd92f),
    .d(al_1b1db758),
    .o(al_ae97fd5e));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_febc0f50 (
    .a(al_2f32596b),
    .b(al_6ce87b4e),
    .c(al_45ef761c),
    .d(din[26]),
    .e(din[16]),
    .f(din[8]),
    .o(al_31685553));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+~(C)*E+~(D))"),
    .INIT(32'h0fff99ff))
    al_b7d1091b (
    .a(al_b3e2b095),
    .b(al_ae97fd5e),
    .c(al_31685553),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[31]));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_296ef727 (
    .a(al_e59218b2),
    .b(al_9c44f52e),
    .o(al_b3e2b095));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_298e1b2a (
    .a(din[22]),
    .b(din[4]),
    .c(din[0]),
    .o(al_2f32596b));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_2836d54d (
    .a(din[23]),
    .b(din[1]),
    .c(al_9c667979[8]),
    .d(al_9c667979[30]),
    .o(al_ca940860));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_b0d3c2f9 (
    .a(din[23]),
    .b(din[3]),
    .c(din[1]),
    .o(al_45ef761c));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_a5951acf (
    .a(din[30]),
    .b(din[22]),
    .c(din[16]),
    .d(din[14]),
    .e(din[4]),
    .f(din[0]),
    .o(al_bd3e6902));
  AL_MAP_LUT6 #(
    .EQN("(A*~(C)*~(D)*~(F)+~(A)*C*~(D)*~(F)+~(A)*~(C)*D*~(F)+A*C*D*~(F)+~(E)+B)"),
    .INIT(64'hccccffffeddeffff))
    al_484fdc4a (
    .a(al_ba83a52c),
    .b(al_7897898b),
    .c(al_7316f68e),
    .d(al_14fadafb),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[3]));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_298db2b1 (
    .a(din[28]),
    .b(din[23]),
    .c(al_9c667979[3]),
    .d(al_9c667979[8]),
    .o(al_2a6117da));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_44cc47f8 (
    .a(din[16]),
    .b(din[12]),
    .c(al_9c667979[15]),
    .d(al_9c667979[19]),
    .o(al_2b8394c6));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_4be0f8cd (
    .a(al_f6981785),
    .b(al_2b8394c6),
    .c(al_e59218b2),
    .d(al_2a6117da),
    .e(al_9b8401f),
    .o(al_ba83a52c));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966900000000))
    al_1e07c572 (
    .a(al_bd3e6902),
    .b(al_d61dbbe2),
    .c(din[28]),
    .d(din[23]),
    .e(din[6]),
    .f(packet_start),
    .o(al_7897898b));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_a59da24a (
    .a(din[27]),
    .b(din[25]),
    .c(din[11]),
    .d(al_9c667979[4]),
    .e(al_9c667979[6]),
    .f(al_9c667979[20]),
    .o(al_73fb00f5));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_4fa62f5d (
    .a(din[31]),
    .b(din[0]),
    .o(al_5398b6b2));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_3d0a12d2 (
    .a(din[29]),
    .b(din[13]),
    .c(al_9c667979[2]),
    .d(al_9c667979[18]),
    .o(al_f17c516b));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_900c2e73 (
    .a(din[31]),
    .b(din[27]),
    .c(din[25]),
    .d(din[11]),
    .e(din[0]),
    .o(al_827e1925));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_b4b1802d (
    .a(al_5398b6b2),
    .b(al_75f0d032),
    .c(al_f17c516b),
    .d(al_9c667979[0]),
    .o(al_c928032d));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_b4d536aa (
    .a(al_e59218b2),
    .b(al_9c44f52e),
    .c(al_ccef2d2d),
    .d(din[28]),
    .e(al_9c667979[3]),
    .o(al_2197e301));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_d5b7aed9 (
    .a(din[28]),
    .b(din[19]),
    .c(din[16]),
    .d(din[12]),
    .o(al_f070b719));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_4f24fa1f (
    .a(din[29]),
    .b(din[23]),
    .c(din[13]),
    .d(din[1]),
    .o(al_4d290666));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_76f24529 (
    .a(al_6ce87b4e),
    .b(al_827e1925),
    .c(al_f070b719),
    .d(al_4d290666),
    .o(al_875461e8));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(D)*E*~(F)+A*B*~(D)*E*~(F)+A*~(B)*D*E*~(F)+~(A)*B*D*E*~(F)+C*E*F)"),
    .INIT(64'hf0f0000066990000))
    al_9b872415 (
    .a(al_c928032d),
    .b(al_2197e301),
    .c(al_875461e8),
    .d(al_73fb00f5),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[4]));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_ca03c0c (
    .a(din[16]),
    .b(din[12]),
    .c(al_9c667979[15]),
    .d(al_9c667979[19]),
    .e(al_9c667979[31]),
    .o(al_75f0d032));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_46f283b4 (
    .a(din[6]),
    .b(al_9c667979[25]),
    .o(al_e59218b2));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_45f0a271 (
    .a(din[20]),
    .b(din[7]),
    .c(din[2]),
    .d(al_9c667979[11]),
    .e(al_9c667979[24]),
    .f(al_9c667979[29]),
    .o(al_9c44f52e));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_dda885cb (
    .a(din[20]),
    .b(din[7]),
    .c(din[6]),
    .d(din[2]),
    .o(al_6ce87b4e));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_256f0a04 (
    .a(din[30]),
    .b(din[27]),
    .c(din[12]),
    .d(din[11]),
    .o(al_95ae97c3));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*D*~(E)+A*B*D*~(E)+C)"),
    .INIT(32'hf0f0f9f0))
    al_c955dc55 (
    .a(al_46dd1675),
    .b(al_a59c2b8),
    .c(al_b620a2c2),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[5]));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_b4f92b82 (
    .a(al_2f1a5af3),
    .b(al_f59e83cb),
    .c(al_924ea640),
    .d(din[24]),
    .e(al_9c667979[7]),
    .o(al_46dd1675));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_c93426fc (
    .a(al_98d82759),
    .b(al_728efc21),
    .c(al_dc3a3160),
    .d(al_10ab4c6d),
    .o(al_a59c2b8));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_f853f81b (
    .a(din[31]),
    .b(din[28]),
    .c(din[25]),
    .d(din[24]),
    .e(din[18]),
    .f(din[3]),
    .o(al_401856a3));
  AL_MAP_LUT6 #(
    .EQN("(A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h8228288228828228))
    al_a470d95f (
    .a(al_9213e63),
    .b(al_95ae97c3),
    .c(al_104976d9),
    .d(al_401856a3),
    .e(din[26]),
    .f(din[10]),
    .o(al_b620a2c2));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_a673ede7 (
    .a(din[20]),
    .b(al_9c667979[11]),
    .o(al_65459d91));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*E*~(F)+~(A)*B*~(C)*E*~(F)+~(A)*~(B)*C*E*~(F)+A*B*C*E*~(F)+D*E*F)"),
    .INIT(64'hff00000096960000))
    al_f9983349 (
    .a(al_5c4da1bf),
    .b(al_66c102d9),
    .c(al_c26603f1),
    .d(al_2a5f90f6),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[6]));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_3b7a7bbe (
    .a(din[27]),
    .b(din[25]),
    .c(din[20]),
    .d(din[11]),
    .e(din[2]),
    .o(al_a05eef16));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_beb7bead (
    .a(al_14fadafb),
    .b(al_73fb00f5),
    .o(al_5c4da1bf));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_390d7643 (
    .a(al_65459d91),
    .b(al_728efc21),
    .c(al_ca940860),
    .d(din[2]),
    .e(al_9c667979[29]),
    .o(al_66c102d9));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_e197e567 (
    .a(al_fe60cde9),
    .b(al_a05eef16),
    .c(al_cbc0c746),
    .d(al_3ef0c0d8),
    .e(din[30]),
    .o(al_2a5f90f6));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_6620ba21 (
    .a(din[23]),
    .b(din[8]),
    .c(al_9c667979[8]),
    .d(al_9c667979[23]),
    .o(al_1b269f89));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_10b7ba3a (
    .a(al_2f1a5af3),
    .b(al_924ea640),
    .o(al_109a1633));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_562255b6 (
    .a(din[29]),
    .b(din[24]),
    .c(din[16]),
    .d(al_9c667979[2]),
    .e(al_9c667979[7]),
    .f(al_9c667979[15]),
    .o(al_cdad152a));
  AL_MAP_LUT5 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)+~(A)*B*~(C)*~(D)*~(E)+~(A)*~(B)*C*~(D)*~(E)+A*B*C*~(D)*~(E)+~(A)*~(B)*~(C)*D*~(E)+A*B*~(C)*D*~(E)+A*~(B)*C*D*~(E)+~(A)*B*C*D*~(E)+~(A)*~(B)*~(C)*~(D)*E+A*B*~(C)*~(D)*E+A*~(B)*C*~(D)*E+~(A)*B*C*~(D)*E+A*~(B)*~(C)*D*E+~(A)*B*~(C)*D*E+~(A)*~(B)*C*D*E+A*B*C*D*E)"),
    .INIT(32'h96696996))
    al_60e03c6e (
    .a(al_47852ffd),
    .b(al_1b269f89),
    .c(al_e529755e),
    .d(al_2fc445a4),
    .e(al_cdad152a),
    .o(al_21f3c606));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_319e16ce (
    .a(al_4e123ffc),
    .b(al_cbc0c746),
    .c(din[29]),
    .d(din[24]),
    .e(din[23]),
    .f(din[8]),
    .o(al_8f183839));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_dcec435c (
    .a(al_104976d9),
    .b(din[28]),
    .c(din[26]),
    .d(din[16]),
    .e(din[10]),
    .f(din[3]),
    .o(al_f89eee8f));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*E*~(F)+~(A)*B*E*~(F)+C*~(D)*E*F+~(C)*D*E*F)"),
    .INIT(64'h0ff0000066660000))
    al_457e60cd (
    .a(al_109a1633),
    .b(al_21f3c606),
    .c(al_8f183839),
    .d(al_f89eee8f),
    .e(din_en),
    .f(packet_start),
    .o(al_b925cf5b[7]));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_a545be77 (
    .a(din[28]),
    .b(din[3]),
    .c(al_9c667979[3]),
    .d(al_9c667979[28]),
    .o(al_2f1a5af3));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_d082861d (
    .a(din[21]),
    .b(din[7]),
    .c(din[2]),
    .d(al_9c667979[10]),
    .e(al_9c667979[24]),
    .f(al_9c667979[29]),
    .o(al_924ea640));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_83b3ba56 (
    .a(din[21]),
    .b(din[7]),
    .c(din[2]),
    .o(al_104976d9));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_d69cf315 (
    .a(din[9]),
    .b(din[6]),
    .o(al_cbc0c746));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_e7a6b112 (
    .a(din[27]),
    .b(din[9]),
    .c(al_9c667979[4]),
    .d(al_9c667979[22]),
    .o(al_4d48443e));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_ee6660a6 (
    .a(al_5398b6b2),
    .b(al_8e5758c4),
    .c(al_d42076e6),
    .d(din[23]),
    .e(din[21]),
    .f(din[8]),
    .o(al_9f2e5b30));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(E)+A*B*~(E)+~(C)*E+~(D))"),
    .INIT(32'h0fff99ff))
    al_1b2efa4a (
    .a(al_5854a817),
    .b(al_54062695),
    .c(al_9f2e5b30),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[8]));
  AL_MAP_LUT4 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)+A*B*~(C)*~(D)+A*~(B)*C*~(D)+~(A)*B*C*~(D)+A*~(B)*~(C)*D+~(A)*B*~(C)*D+~(A)*~(B)*C*D+A*B*C*D)"),
    .INIT(16'h9669))
    al_c8b7100e (
    .a(al_1b269f89),
    .b(al_4d48443e),
    .c(al_3010f43a),
    .d(al_65459d91),
    .o(al_5854a817));
  AL_MAP_LUT2 #(
    .EQN("(~(A)*~(B)+A*B)"),
    .INIT(4'h9))
    al_8b143021 (
    .a(al_889d0a3),
    .b(al_8120bf4d),
    .o(al_54062695));
  AL_MAP_LUT2 #(
    .EQN("(A*~(B)+~(A)*B)"),
    .INIT(4'h6))
    al_1f24c587 (
    .a(din[14]),
    .b(din[9]),
    .o(al_8e5758c4));
  AL_MAP_LUT6 #(
    .EQN("(A*~(B)*~(C)*~(D)*~(E)*~(F)+~(A)*B*~(C)*~(D)*~(E)*~(F)+~(A)*~(B)*C*~(D)*~(E)*~(F)+A*B*C*~(D)*~(E)*~(F)+~(A)*~(B)*~(C)*D*~(E)*~(F)+A*B*~(C)*D*~(E)*~(F)+A*~(B)*C*D*~(E)*~(F)+~(A)*B*C*D*~(E)*~(F)+~(A)*~(B)*~(C)*~(D)*E*~(F)+A*B*~(C)*~(D)*E*~(F)+A*~(B)*C*~(D)*E*~(F)+~(A)*B*C*~(D)*E*~(F)+A*~(B)*~(C)*D*E*~(F)+~(A)*B*~(C)*D*E*~(F)+~(A)*~(B)*C*D*E*~(F)+A*B*C*D*E*~(F)+~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966996696996))
    al_481e9cd6 (
    .a(din[30]),
    .b(din[28]),
    .c(din[27]),
    .d(din[20]),
    .e(din[19]),
    .f(din[3]),
    .o(al_d42076e6));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_de060daa (
    .a(din[18]),
    .b(al_9c667979[5]),
    .c(al_9c667979[13]),
    .o(al_6b1f677f));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*~(F)+A*B*~(C)*~(D)*~(E)*~(F)+A*~(B)*C*~(D)*~(E)*~(F)+~(A)*B*C*~(D)*~(E)*~(F)+A*~(B)*~(C)*D*~(E)*~(F)+~(A)*B*~(C)*D*~(E)*~(F)+~(A)*~(B)*C*D*~(E)*~(F)+A*B*C*D*~(E)*~(F)+A*~(B)*~(C)*~(D)*E*~(F)+~(A)*B*~(C)*~(D)*E*~(F)+~(A)*~(B)*C*~(D)*E*~(F)+A*B*C*~(D)*E*~(F)+~(A)*~(B)*~(C)*D*E*~(F)+A*B*~(C)*D*E*~(F)+A*~(B)*C*D*E*~(F)+~(A)*B*C*D*E*~(F)+A*~(B)*~(C)*~(D)*~(E)*F+~(A)*B*~(C)*~(D)*~(E)*F+~(A)*~(B)*C*~(D)*~(E)*F+A*B*C*~(D)*~(E)*F+~(A)*~(B)*~(C)*D*~(E)*F+A*B*~(C)*D*~(E)*F+A*~(B)*C*D*~(E)*F+~(A)*B*C*D*~(E)*F+~(A)*~(B)*~(C)*~(D)*E*F+A*B*~(C)*~(D)*E*F+A*~(B)*C*~(D)*E*F+~(A)*B*C*~(D)*E*F+A*~(B)*~(C)*D*E*F+~(A)*B*~(C)*D*E*F+~(A)*~(B)*C*D*E*F+A*B*C*D*E*F)"),
    .INIT(64'h9669699669969669))
    al_4c5a40e8 (
    .a(din[29]),
    .b(din[26]),
    .c(din[22]),
    .d(din[18]),
    .e(din[13]),
    .f(din[8]),
    .o(al_e6a40dc4));
  AL_MAP_LUT6 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)*F+A*B*~(C)*~(D)*~(E)*F+A*~(B)*C*~(D)*~(E)*F+~(A)*B*C*~(D)*~(E)*F+A*~(B)*~(C)*D*~(E)*F+~(A)*B*~(C)*D*~(E)*F+~(A)*~(B)*C*D*~(E)*F+A*B*C*D*~(E)*F+A*~(B)*~(C)*~(D)*E*F+~(A)*B*~(C)*~(D)*E*F+~(A)*~(B)*C*~(D)*E*F+A*B*C*~(D)*E*F+~(A)*~(B)*~(C)*D*E*F+A*B*~(C)*D*E*F+A*~(B)*C*D*E*F+~(A)*B*C*D*E*F)"),
    .INIT(64'h6996966900000000))
    al_405be576 (
    .a(al_6a5c7bf3),
    .b(al_e6a40dc4),
    .c(din[30]),
    .d(din[27]),
    .e(din[19]),
    .f(packet_start),
    .o(al_41c11af1));
  AL_MAP_LUT5 #(
    .EQN("(~(C)*D*E+A*~(B)*~(C)*D+~(A)*B*~(C)*D)"),
    .INIT(32'h0f000600))
    al_84aebee9 (
    .a(al_706b4c24),
    .b(al_4f2045c5),
    .c(al_41c11af1),
    .d(din_en),
    .e(packet_start),
    .o(al_b925cf5b[9]));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_b229d878 (
    .a(din[20]),
    .b(din[7]),
    .c(din[2]),
    .o(al_6a5c7bf3));
  AL_MAP_LUT4 #(
    .EQN("(A*~(B)*~(C)*~(D)+~(A)*B*~(C)*~(D)+~(A)*~(B)*C*~(D)+A*B*C*~(D)+~(A)*~(B)*~(C)*D+A*B*~(C)*D+A*~(B)*C*D+~(A)*B*C*D)"),
    .INIT(16'h6996))
    al_868a738d (
    .a(din[27]),
    .b(din[22]),
    .c(al_9c667979[4]),
    .d(al_9c667979[9]),
    .o(al_fb75046b));
  AL_MAP_LUT3 #(
    .EQN("(~(A)*~(B)*~(C)+A*B*~(C)+A*~(B)*C+~(A)*B*C)"),
    .INIT(8'h69))
    al_115a30c0 (
    .a(al_9c44f52e),
    .b(din[19]),
    .c(al_9c667979[12]),
    .o(al_706b4c24));
  AL_MAP_LUT5 #(
    .EQN("(~(A)*~(B)*~(C)*~(D)*~(E)+A*B*~(C)*~(D)*~(E)+A*~(B)*C*~(D)*~(E)+~(A)*B*C*~(D)*~(E)+A*~(B)*~(C)*D*~(E)+~(A)*B*~(C)*D*~(E)+~(A)*~(B)*C*D*~(E)+A*B*C*D*~(E)+A*~(B)*~(C)*~(D)*E+~(A)*B*~(C)*~(D)*E+~(A)*~(B)*C*~(D)*E+A*B*C*~(D)*E+~(A)*~(B)*~(C)*D*E+A*B*~(C)*D*E+A*~(B)*C*D*E+~(A)*B*C*D*E)"),
    .INIT(32'h69969669))
    al_422bfc09 (
    .a(al_728efc21),
    .b(al_f17c516b),
    .c(al_6b1f677f),
    .d(al_fb75046b),
    .e(al_d9bfd92f),
    .o(al_4f2045c5));
  AL_DFF_X al_58248dfa (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[0]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[0]));
  AL_DFF_X al_5a84b92 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[10]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[10]));
  AL_DFF_X al_574da391 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[11]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[11]));
  AL_DFF_X al_23571c74 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[12]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[12]));
  AL_DFF_X al_3fabb2f3 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[13]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[13]));
  AL_DFF_X al_470bf7b9 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[14]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[14]));
  AL_DFF_X al_2ea65faa (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[15]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[15]));
  AL_DFF_X al_5c4b1f00 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[16]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[16]));
  AL_DFF_X al_2f50a102 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[17]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[17]));
  AL_DFF_X al_ffd8e36 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[18]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[18]));
  AL_DFF_X al_7d7a3b34 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[19]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[19]));
  AL_DFF_X al_1846848f (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[1]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[1]));
  AL_DFF_X al_7b8a472f (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[20]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[20]));
  AL_DFF_X al_bc6363af (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[21]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[21]));
  AL_DFF_X al_4f2f5bed (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[22]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[22]));
  AL_DFF_X al_23c67ac8 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[23]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[23]));
  AL_DFF_X al_472d90fd (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[24]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[24]));
  AL_DFF_X al_fd26c628 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[25]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[25]));
  AL_DFF_X al_b32e2c21 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[26]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[26]));
  AL_DFF_X al_832acf04 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[27]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[27]));
  AL_DFF_X al_eb05734 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[28]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[28]));
  AL_DFF_X al_2f852b28 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[29]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[29]));
  AL_DFF_X al_d5c57d0b (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[2]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[2]));
  AL_DFF_X al_32349375 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[30]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[30]));
  AL_DFF_X al_9e197bb6 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[31]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[31]));
  AL_DFF_X al_60c3cd42 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[3]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[3]));
  AL_DFF_X al_e4e5531b (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[4]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[4]));
  AL_DFF_X al_a6967cce (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[5]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[5]));
  AL_DFF_X al_a8e0a8e2 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[6]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[6]));
  AL_DFF_X al_787d04c7 (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[7]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[7]));
  AL_DFF_X al_5390cd0b (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[8]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[8]));
  AL_DFF_X al_3b942c3f (
    .ar(rst),
    .as(1'b0),
    .clk(clk),
    .d(al_b925cf5b[9]),
    .en(al_e692b01b[31]),
    .sr(1'b0),
    .ss(1'b0),
    .q(al_9c667979[9]));
  AL_MAP_LUT2 #(
    .EQN("(B+A)"),
    .INIT(4'he))
    al_bda344fa (
    .a(din_en),
    .b(packet_start),
    .o(al_e692b01b[31]));

endmodule 

