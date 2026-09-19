`timescale 1ns/1ps
module csi2_raw10_word_core (
 input wire i_clk,
 input wire i_reset_n,
 input wire [31:0] i_word,
 input wire i_word_valid,
 input wire i_sink_ready,
 output reg [39:0] o_data,
 output reg o_valid,
 output reg o_sof,
 output reg o_eol,
 output reg o_abort,
 output reg [3:0] o_error_code,
 output reg o_header_ecc_error,
 output reg o_payload_crc_error,
 output reg o_length_error,
 output wire o_wait_for_sync,
 output reg o_packet_done
);
localparam HDR = 1'b0;
localparam PKT = 1'b1;
reg state, frame_open, first_group, dropping, raw_packet, crc_lo_seen;
reg [15:0] left, crc;
reg [7:0] crc_lo;
reg [2:0] bcnt;
reg [31:0] bytes;
reg last_pending, last_sof;
reg [39:0] last_data;
integer i, j;
reg [23:0] h, hc;
reg [5:0] syn, col;
reg found, good;
reg [7:0] dt, b;
reg [15:0] wc, nleft, ncrc;
reg [2:0] nbcnt;
reg [31:0] nbytes;
reg nseen, emit, finish, bad, eol;
reg [7:0] nlo;
reg [39:0] edata;
function [5:0] he;
input [23:0] d;
begin
 he[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
he[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
he[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
he[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
he[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
he[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
end
 endfunction
 function [15:0] cb;
input [15:0] c;
input [7:0] x;
integer k;
reg [15:0] v;
begin
  v=c^x;
for(k=0;
k<8;
k=k+1)v=v[0]?((v>>1)^16'h8408):(v>>1);
cb=v;
end
 endfunction
 function [39:0] up;
input [39:0] p;
begin
  up[9:0]={p[7:0],p[33:32]};
up[19:10]={p[15:8],p[35:34]};
up[29:20]={p[23:16],p[37:36]};
up[39:30]={p[31:24],p[39:38]};
end
 endfunction
 // Header words are accepted only in HDR; long-packet payload and CRC use PKT.
 assign o_wait_for_sync=(state==HDR);

 // The final RAW group is committed only after its packet CRC is known good.
 // Fatal events replace any blocked ordinary pixel so an error cannot be lost.
 always@(posedge i_clk or negedge i_reset_n)begin
  if(!i_reset_n)begin state<=HDR;
frame_open<=0;
first_group<=0;
dropping<=0;
raw_packet<=0;
left<=0;
crc<=16'hffff;
crc_lo<=0;
crc_lo_seen<=0;
bcnt<=0;
bytes<=0;
last_pending<=0;
last_sof<=0;
last_data<=0;
o_data<=0;
o_valid<=0;
o_sof<=0;
o_eol<=0;
o_abort<=0;
o_error_code<=0;
o_header_ecc_error<=0;
o_payload_crc_error<=0;
o_length_error<=0;
o_packet_done<=0;
end
  else begin o_packet_done<=0;
if(o_valid&&i_sink_ready)begin o_valid<=0;
o_sof<=0;
o_eol<=0;
o_abort<=0;
o_error_code<=0;
end
   if(i_word_valid)begin
    if(state==HDR)begin h=i_word[23:0];
syn=he(h)^i_word[29:24];
hc=h;
found=(syn==0);
if((syn!=0)&&((syn&(syn-1'b1))==0))found=1;
for(i=0;
i<24;
i=i+1)begin col=he(24'b1<<i);
if((syn!=0)&&(syn==col))begin hc[i]=~h[i];
found=1;
end end good=found&&(i_word[31:30]==0);
dt={2'b0,hc[5:0]};
wc=hc[23:8];
if(!good)begin o_header_ecc_error<=1;
dropping<=1;
last_pending<=0;
o_valid<=1;
o_sof<=0;
o_eol<=0;
o_abort<=1;
o_error_code<=1;
o_packet_done<=1;
end
     else if((hc[7:6]==0)&&(dt==0))begin if(frame_open&&!dropping)begin o_valid<=1;
o_sof<=0;
o_eol<=0;
o_abort<=1;
o_error_code<=5;
end frame_open<=1;
first_group<=1;
dropping<=0;
last_pending<=0;
o_packet_done<=1;
end
     else if((hc[7:6]==0)&&(dt==1))begin frame_open<=0;
first_group<=0;
o_packet_done<=1;
end
     else if(dt>8'h0f)begin raw_packet<=(hc[7:6]==0)&&(dt==8'h2b);
left<=wc;
crc<=16'hffff;
crc_lo_seen<=0;
bcnt<=0;
bytes<=0;
last_pending<=0;
state<=PKT;
if((dt==8'h2b)&&((wc%5)!=0))begin o_length_error<=1;
dropping<=1;
o_valid<=1;
o_sof<=0;
o_eol<=0;
o_abort<=1;
o_error_code<=4;
end end
     else o_packet_done<=1;
end else begin nleft=left;
ncrc=crc;
nbcnt=bcnt;
nbytes=bytes;
nseen=crc_lo_seen;
nlo=crc_lo;
emit=0;
finish=0;
bad=0;
eol=0;
edata=0;
for(j=0;
j<4;
j=j+1)begin b=i_word[j*8+:8];
if(nleft!=0)begin ncrc=cb(ncrc,b);
nleft=nleft-1'b1;
if(raw_packet)begin if(nbcnt==4)begin edata=up({b,nbytes});
emit=1;
eol=(nleft==0);
nbcnt=0;
nbytes=0;
end else begin nbytes[nbcnt*8+:8]=b;
nbcnt=nbcnt+1'b1;
end end end else if(!nseen)begin nlo=b;
nseen=1;
end else if(!finish)begin finish=1;
bad=({b,nlo}!=ncrc);
end end
     left<=nleft;
crc<=ncrc;
bcnt<=nbcnt;
bytes<=nbytes;
crc_lo_seen<=nseen;
crc_lo<=nlo;
if(emit&&!dropping&&frame_open)begin if(!o_valid||i_sink_ready)begin if(eol)begin last_data<=edata;
last_sof<=first_group;
last_pending<=1;
first_group<=0;
end else begin o_data<=edata;
o_valid<=1;
o_sof<=first_group;
o_eol<=0;
o_abort<=0;
o_error_code<=0;
first_group<=0;
end end else begin dropping<=1;
last_pending<=0;
o_valid<=1;
o_sof<=0;
o_eol<=0;
o_abort<=1;
o_error_code<=3;
end end
     if(finish)begin state<=HDR;
o_packet_done<=1;
if(bad)begin o_payload_crc_error<=1;
dropping<=1;
last_pending<=0;
o_valid<=1;
o_sof<=0;
o_eol<=0;
o_abort<=1;
o_error_code<=2;
end else if(!dropping&&frame_open&&(last_pending||(emit&&eol)))begin
 if(!o_valid||i_sink_ready)begin
  o_data<=(emit&&eol)?edata:last_data;
  o_valid<=1;
  o_sof<=(emit&&eol)?first_group:last_sof;
  o_eol<=1;
  o_abort<=0;
  o_error_code<=0;
  first_group<=0;
  last_pending<=0;
 end else begin
  dropping<=1;
  last_pending<=0;
  o_valid<=1;
  o_sof<=0;
  o_eol<=0;
  o_abort<=1;
  o_error_code<=3;
 end
end end
    end
   end
  end
 end
endmodule
