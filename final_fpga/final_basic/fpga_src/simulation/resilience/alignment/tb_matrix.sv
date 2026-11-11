`timescale 1ns/1ps
module tb_matrix;
 parameter integer CASES=1;
 localparam integer STEPS=240,WORDS=17;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,ws=1,pd=0;
 reg [31:0] raw=0;
 wire [31:0] bd,aw,gw;
 wire [3:0] lv,found;wire [11:0] offset,taps;wire av,gv;
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:g_byte
  csi_rx_byte_align_observed u(.I_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
   .I_lan_data_in(raw[8*lane+:8]),.I_wait_for_sync(ws),.I_packet_done(pd),
   .O_data_out_vaild(lv[lane]),.O_data_out(bd[8*lane+:8]),
   .o_diag_offset(offset[3*lane+:3]),.o_diag_found(found[lane]));
 end endgenerate
 csi_rx_word_align_observed #(.MIPI_LAN(4)) wa(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_packet_done(pd),.I_wait_for_sync(ws),.O_packet_done_out(),
  .I_word_in(bd),.I_valid_in(lv),.O_word_out(aw),.O_valid_out(av),.o_diag_taps(taps));
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gb(.I_word_clock(clk),.I_reset_n(rst),.I_enable(1'b1),
  .I_lane_data(aw),.I_lane_data_valid(av),.O_word_out(gw),.O_valid_out(gv));
 reg [31:0] stimulus[0:240*512-1],expected[0:17*512-1];
 integer id,cycle,count,mismatches,first_cycle,bad_index,same_edge,max_age;
 reg [31:0] first_word,bad_got,bad_expected;
 reg [11:0] acquired_taps,acquired_offset;
 reg seen_acquisition;
 integer age0,age1,age2,age3;
 initial begin
  $readmemh("raw.hex",stimulus,0,STEPS*CASES-1);
  $readmemh("expected.hex",expected,0,WORDS*CASES-1);
  for(id=0;id<CASES;id=id+1)begin
   rst=0;raw=0;ws=1;pd=0;repeat(8)@(negedge clk);
   rst=1;count=0;mismatches=0;first_cycle=-1;first_word=0;
   bad_index=-1;bad_got=0;bad_expected=0;same_edge=0;max_age=0;
   acquired_taps=0;acquired_offset=0;seen_acquisition=0;
   for(cycle=0;cycle<STEPS;cycle=cycle+1)begin
    raw=stimulus[id*STEPS+cycle];#1;
    age0=g_byte[0].u.r_error_cunt;age1=g_byte[1].u.r_error_cunt;
    age2=g_byte[2].u.r_error_cunt;age3=g_byte[3].u.r_error_cunt;
    if(age0>max_age)max_age=age0;if(age1>max_age)max_age=age1;
    if(age2>max_age)max_age=age2;if(age3>max_age)max_age=age3;
    if(wa.w_next_valid&&!wa.r_valid&&ws&&((age0&16)||(age1&16)||(age2&16)||(age3&16)))same_edge++;
    if(wa.r_valid&&!seen_acquisition)begin
     seen_acquisition=1;acquired_taps=taps;acquired_offset=offset;
    end
    if(gv&&count<WORDS)begin
     if(count==0)begin first_word=gw;first_cycle=cycle;end
     if(gw!==expected[id*WORDS+count])begin
      mismatches++;
      if(bad_index<0)begin bad_index=count;bad_got=gw;bad_expected=expected[id*WORDS+count];end
     end
     count++;
    end
    // Scheduled parser-like envelope: leave wait-sync after first geared word,
    // end only after all independently expected words have been presented.
    // The production parser is deliberately not instantiated in this bench.
    @(negedge clk);
    if(count>0)ws=0;
    if(count==WORDS)pd=1;
   end
   $display("CASE id=%0d count=%0d mismatch=%0d first_cycle=%0d first=%08h bad_index=%0d got=%08h expected=%08h taps=%03h offset=%03h timeout_same=%0d max_age=%0d",id,count,mismatches,first_cycle,first_word,bad_index,bad_got,bad_expected,acquired_taps,acquired_offset,same_edge,max_age);
  end
  $display("RESULT: HARNESS_COMPLETE cases=%0d",CASES);$finish;
 end
 initial begin #5000000;$fatal(1,"bounded matrix timeout");end
endmodule
