`timescale 1ns/1ps
module tb_color2 #(parameter integer MATRIX=0,BYPASS=0,FULL=0);
localparam integer N=FULL?518400:1024;
localparam signed [10:0] C00=MATRIX?11'sd1023:11'sd256,C01=MATRIX?11'sh400:11'sd0,C02=MATRIX?11'sd31:11'sd0;
localparam signed [10:0] C10=MATRIX?-11'sd128:11'sd0,C11=MATRIX?11'sd384:11'sd256,C12=MATRIX?11'sd17:11'sd0;
localparam signed [10:0] C20=MATRIX?11'sd512:11'sd0,C21=MATRIX?-11'sd511:11'sd0,C22=11'sd256;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,run=0;
reg [167:0] input_words[0:N-1];reg [32:0] metadata[0:N-1];
reg [95:0] expected[0:N-1];reg expected_clip[0:N-1];
integer sent[0:1],received[0:1],first_accept[0:1],last_accept[0:1],clipped_count[0:1],cycle=0;
reg [1:0] output_ready=0,held=0;
reg [97:0] held_word[0:1];integer last_stall[0:1];
wire [1:0] input_valid,input_ready,output_valid,output_sof,output_eol;
wire [167:0] source_data[0:1];wire [32:0] source_meta[0:1];
wire [95:0] output_data[0:1];wire [31:0] beats[0:1],frames[0:1],saturated[0:1];
genvar p;
generate for(p=0;p<2;p=p+1)begin:g_source
 assign input_valid[p]=run&&sent[p]<N;
 assign source_data[p]=input_valid[p]?input_words[sent[p]]:168'd0;
 assign source_meta[p]=input_valid[p]?metadata[sent[p]]:33'd0;
end endgenerate
wire [29:0] cfg_gains0=source_meta[0][0]?source_meta[0][32:3]:30'((cycle*1103515245)^32'h12345678);
wire [29:0] cfg_gains1=source_meta[1][0]?source_meta[1][32:3]:30'((cycle*12345)^32'h87654321);
wide_color_pipeline #(.GAMMA_BYPASS(BYPASS),.CCM00(C00),.CCM01(C01),.CCM02(C02),.CCM10(C10),.CCM11(C11),.CCM12(C12),.CCM20(C20),.CCM21(C21),.CCM22(C22)) fixed4(
 .clk(clk),.rst_n(rst_n),.cfg_hdr(source_meta[0][0]?source_meta[0][2]:cycle[2]),.cfg_tone_shift(4'(cycle)),.cfg_wb_gains(cfg_gains0),
 .s_data(source_data[0]),.s_valid(input_valid[0]),.s_ready(input_ready[0]),.s_sof(source_meta[0][0]),.s_eol(source_meta[0][1]),
 .m_data(output_data[0]),.m_valid(output_valid[0]),.m_ready(output_ready[0]),.m_sof(output_sof[0]),.m_eol(output_eol[0]),
 .stat_beats(beats[0]),.stat_frames(frames[0]),.stat_saturated(saturated[0]));
wide_color_pipeline2 #(.GAMMA_BYPASS(BYPASS),.CCM00(C00),.CCM01(C01),.CCM02(C02),.CCM10(C10),.CCM11(C11),.CCM12(C12),.CCM20(C20),.CCM21(C21),.CCM22(C22)) shared2(
 .clk(clk),.rst_n(rst_n),.cfg_hdr(source_meta[1][0]?source_meta[1][2]:cycle[1]),.cfg_tone_shift(4'(cycle+7)),.cfg_wb_gains(cfg_gains1),
 .s_data(source_data[1]),.s_valid(input_valid[1]),.s_ready(input_ready[1]),.s_sof(source_meta[1][0]),.s_eol(source_meta[1][1]),
 .m_data(output_data[1]),.m_valid(output_valid[1]),.m_ready(output_ready[1]),.m_sof(output_sof[1]),.m_eol(output_eol[1]),
 .stat_beats(beats[1]),.stat_frames(frames[1]),.stat_saturated(saturated[1]));
always @(negedge clk)begin:drive_ready
 integer port;
 cycle=cycle+1;
 for(port=0;port<2;port=port+1)begin
   output_ready[port]=rst_n&&(FULL?1'b1:(port==0?(cycle%13>3&&cycle%47>10):(cycle%11>2&&cycle%41>8)));
   if(rst_n&&received[port]==N-1&&output_valid[port]&&last_stall[port]<7)begin output_ready[port]=0;last_stall[port]=last_stall[port]+1;end
 end
end
always @(posedge clk)begin:score
 integer port;
 for(port=0;port<2;port=port+1)begin
   if(!rst_n)begin sent[port]<=0;received[port]=0;first_accept[port]=-1;last_accept[port]=-1;clipped_count[port]=0;last_stall[port]=0;held[port]=0;end
   else begin
     if(input_valid[port]&&input_ready[port])begin
       if(first_accept[port]<0)first_accept[port]=cycle;
       last_accept[port]=cycle;sent[port]<=sent[port]+1;
     end
     if(held[port]&&(!output_valid[port]||{output_sof[port],output_eol[port],output_data[port]}!==held_word[port]))$fatal(1,"output stall stability port%0d",port);
     held[port]=output_valid[port]&&!output_ready[port];
     held_word[port]={output_sof[port],output_eol[port],output_data[port]};
     if(output_valid[port]&&output_ready[port])begin
       if(received[port]>=N||output_data[port]!==expected[received[port]]||output_sof[port]!==metadata[received[port]][0]||output_eol[port]!==metadata[received[port]][1])
         $fatal(1,"independent RGB/metadata mismatch port%0d group%0d got%h expected%h sof%0d eol%0d",port,received[port],output_data[port],expected[received[port]],output_sof[port],output_eol[port]);
       if((port==0?fixed4.gamma_clipped[1]:shared2.output_clipped)!==expected_clip[received[port]])$fatal(1,"group clipping metadata port%0d group%0d",port,received[port]);
       clipped_count[port]=clipped_count[port]+expected_clip[received[port]];
       received[port]=received[port]+1;
     end
   end
 end
end
task tick;begin @(posedge clk);#1;end endtask
integer k,waits;
initial begin
 for(k=0;k<2;k=k+1)begin sent[k]=0;received[k]=0;last_stall[k]=0;end
 if(FULL)begin
   $readmemh("full_input.hex",input_words);$readmemh("full_meta.hex",metadata);$readmemh("full_expected.hex",expected);$readmemh("full_clip.hex",expected_clip);
 end else begin
   $readmemh("small_input.hex",input_words);$readmemh("small_meta.hex",metadata);
   if(MATRIX==0&&BYPASS==0)begin $readmemh("small_m0_b0.hex",expected);$readmemh("small_m0_clip.hex",expected_clip);end
   else if(MATRIX==1&&BYPASS==0)begin $readmemh("small_m1_b0.hex",expected);$readmemh("small_m1_clip.hex",expected_clip);end
   else begin $readmemh("small_m1_b1.hex",expected);$readmemh("small_m1_clip.hex",expected_clip);end
 end
 repeat(24)tick();@(negedge clk);rst_n=1;run=1;
 if(!FULL)begin
   repeat(80)tick();@(negedge clk);rst_n=0;run=0;repeat(4)tick();
   if(output_valid!=0)$fatal(1,"reset left old valid");@(negedge clk);rst_n=1;run=1;
 end
 waits=0;while((received[0]!=N||received[1]!=N)&&waits<N*8+2000)begin tick();waits=waits+1;end
 if(received[0]!=N||received[1]!=N)$fatal(1,"output timeout a%0d b%0d",received[0],received[1]);
 repeat(4)tick();
 for(k=0;k<2;k=k+1)begin
   if(beats[k]!=N||frames[k]!=(FULL?1:16)||saturated[k]!=clipped_count[k]||last_stall[k]!=7)$fatal(1,"stats/tail stall port%0d beats%0d frames%0d sat%0d/%0d",k,beats[k],frames[k],saturated[k],clipped_count[k]);
 end
 if(FULL&&last_accept[1]-first_accept[1]>2*(N-1)+32)$fatal(1,"2PPC steady service has extra bubbles span%0d",last_accept[1]-first_accept[1]);
 $display("RESULT: PASS COLOR2_AB matrix%0d bypass%0d full%0d groups%0d pixels%0d span4=%0d span2=%0d independent_signed_round_clip_gamma finite_stall last7 reset mode_freeze",MATRIX,BYPASS,FULL,N,N*4,last_accept[0]-first_accept[0],last_accept[1]-first_accept[1]);$finish;
end
initial begin #100000000;$fatal(1,"color watchdog");end
endmodule
