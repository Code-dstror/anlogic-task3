`timescale 1ns/1ps

// 解析 CSI 字流并组装 RAW10 像素与帧事件
module physical_csi_word_core #(parameter integer RX_DIAG_ENABLE=0,parameter integer FRAME_EVENTS_ENABLE = 1,
 parameter [31:0] SEQUENCE_INITIAL = 32'd0,
 parameter integer FRAME_RESYNC_ENABLE = 0) (
    // 时钟与复位
 input wire i_clk,
 input wire i_reset_n,
 input wire i_identity_rst_n,
 output wire [31:0] o_source_sequence_count,
 output wire o_identity_fault,
 output wire [63:0] o_identity_diag,
 // Passive, same-WORD-cycle taps for the first-loss recorder.
 output wire [63:0] o_trace_parser,
 output wire o_trace_trigger,
    // CSI 字输入
 input wire [31:0] i_word,
 input wire i_word_valid,
    // 输出端接收握手
 input wire i_sink_ready,
    // RAW 像素流
 output reg [39:0] o_data,
 output reg o_valid,
 output reg o_sof,
 output reg o_eol,
    // 帧中止、包解析错误与边界控制
 output reg o_abort,
 output reg [3:0] o_error_code,
 output reg o_header_ecc_error,
 output reg o_payload_crc_error,
 output reg o_length_error,
 output wire o_wait_for_sync,
 output reg o_packet_done
);
localparam [1:0] HDR = 2'd0;
localparam [1:0] PKT = 2'd1;
localparam [1:0] DRAIN = 2'd2;
reg [1:0] state;
reg frame_open, first_group, dropping, raw_packet, crc_lo_seen;
reg [15:0] left, crc;
reg [7:0] crc_lo;
reg [2:0] bcnt;
reg [31:0] bytes;
reg last_pending, last_sof;
reg [39:0] last_data;
// Enabled mode separates parser requests from the public held output.
// One terminal, one unannounced FS and a coalesced drop bit are bounded.
// Announced failures terminate negatively; unseen losses are diagnostics.
reg terminal_pending, fs_pending, event_open, drop_pending;
reg [3:0] terminal_code;
reg next_terminal, next_fs, next_open, next_drop;
reg [3:0] next_code;
reg request_valid, request_sof, request_eol, request_abort;
reg [39:0] request_data;
reg [3:0] request_code;
reg output_used;
wire output_available = (!o_valid || i_sink_ready) &&
    ((FRAME_EVENTS_ENABLE == 0) || (!terminal_pending && !fs_pending && !drop_pending));
integer i, j;
reg [23:0] h, hc;
reg [5:0] syn, col;
reg found, good;
reg [7:0] dt, b;
reg [15:0] wc, nleft, ncrc;
reg [15:0] crc1, crc2, crc3, crc4;
reg [2:0] payload_count;
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
    // 包完成后等待上游有效字排空；排空期间也暂停下一次字节同步

// Count each corrected target-VC FS before any output/drop/coalescing decision.
// Identity authority is cold-reset independently of decoder soft recovery.
reg [31:0] sequence_counter;
reg sequence_trusted;
reg sequence_started;
integer header_index;
always @* begin
h=i_word[23:0];
syn=he(h)^i_word[29:24];
hc=h;
found=(syn==0);
if((syn!=0)&&((syn&(syn-1'b1))==0))found=1;
for(header_index=0;
header_index<24;
header_index=header_index+1)begin col=he(24'b1<<header_index);
if((syn!=0)&&(syn==col))begin hc[header_index]=~h[header_index];
found=1;
end end good=found&&(i_word[31:30]==0);
dt={2'b0,hc[5:0]};
wc=hc[23:8];
end
wire recognized_fs=i_reset_n && i_identity_rst_n && i_word_valid && state==HDR && good && hc[7:6]==0 && dt==0;
wire uncertain_header=i_reset_n && i_word_valid && state==HDR && !good;
// Before the first target-VC FS no sequence has been published. Reject bad
// startup packets without poisoning that future first identity. After FS the
// same ambiguity can hide a frame boundary. Strict callers stay untrusted;
// SDR recovery may establish a new unique identity at a later recognized FS.
wire identity_header_loss=uncertain_header && sequence_started;
wire identity_decoder_loss=!i_reset_n && sequence_started;
assign o_trace_trigger=i_identity_rst_n && sequence_trusted &&
    (identity_header_loss || identity_decoder_loss ||
     (recognized_fs && sequence_counter==32'hffffffff));
assign o_trace_parser={frame_open,dropping,crc_lo_seen,o_packet_done,
    sequence_trusted,sequence_started,raw_packet,good,syn,left,state,sequence_counter};
// Recovery never relabels the old frame or its queued FS/terminal controls.
wire [32:0] next_fs_identity={i_identity_rst_n &&
    (sequence_trusted || FRAME_RESYNC_ENABLE != 0) && sequence_counter!=32'hffffffff,
    sequence_counter==32'hffffffff ? 32'hffffffff : sequence_counter+32'd1};
assign o_source_sequence_count=sequence_counter;
assign o_identity_fault=!sequence_trusted;
always @(posedge i_clk or negedge i_identity_rst_n) begin
    if(!i_identity_rst_n)begin sequence_counter<=SEQUENCE_INITIAL;sequence_trusted<=1;sequence_started<=0;end
    else begin
        if(identity_decoder_loss||identity_header_loss)sequence_trusted<=0;
        if(recognized_fs)begin
            sequence_started<=1;
            if(sequence_counter==32'hffffffff)sequence_trusted<=0;
            else begin
                sequence_counter<=sequence_counter+32'd1;
                if(FRAME_RESYNC_ENABLE != 0)sequence_trusted<=1;
            end
        end
    end
end
generate if(RX_DIAG_ENABLE!=0)begin:g_identity_diag
 reg [31:0] first_reason,first_header;
 wire [2:0] loss_cause={recognized_fs&&sequence_counter==32'hffffffff,
     identity_decoder_loss,identity_header_loss};
 always @(posedge i_clk or negedge i_identity_rst_n)begin
  if(!i_identity_rst_n)begin first_reason<=0;first_header<=0;end
  // Schema zero means no first loss has been recorded in this cohort. A
  // recovered later loss must not replace RX while RT still holds the first.
  else if(first_reason[3:0]==4'd0 && sequence_trusted&&|loss_cause)begin
   first_reason<={sequence_counter[15:0],syn,i_reset_n,i_word_valid,(state==HDR),loss_cause,4'd1};
   first_header<=uncertain_header?i_word:32'd0;
  end
 end
 assign o_identity_diag={first_header,first_reason};
end else begin:g_no_identity_diag
 assign o_identity_diag=0;
end endgenerate
reg [32:0] frame_identity, pending_fs_identity, pending_terminal_identity;
reg [32:0] request_identity, next_pending_fs_identity, next_pending_terminal_identity;

 assign o_wait_for_sync=(state==HDR);

    // 最后一组 RAW 像素须在整包 CRC 确认正确后提交
    // 默认路径仍允许致命错误覆盖；事件路径保持已呈现输出并有序终结
 // 根据包头、负载和校验事件推进接收状态
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
terminal_pending<=0; fs_pending<=0; event_open<=0; terminal_code<=0; drop_pending<=0;
frame_identity<=0;pending_fs_identity<=0;pending_terminal_identity<=0;
end
  else begin o_packet_done<=0;
request_valid=0; request_data=0; request_sof=0; request_eol=0;
request_abort=0; request_code=0;
request_identity=frame_identity;
next_pending_fs_identity=pending_fs_identity;next_pending_terminal_identity=pending_terminal_identity;
next_terminal=terminal_pending; next_code=terminal_code;
next_fs=fs_pending; next_open=event_open; next_drop=drop_pending; output_used=0;
if(o_valid&&i_sink_ready)begin o_valid<=0;
o_sof<=0;
o_eol<=0;
o_abort<=0;
o_error_code<=0;
end
   if(i_word_valid)begin
    if(state==HDR)begin
if(!good)begin o_header_ecc_error<=1;
dropping<=1;
last_pending<=0;
request_valid=1;
request_sof=0;
request_eol=0;
request_abort=1;
request_code=1;
o_packet_done<=1;
state<=DRAIN;
end
     else if((hc[7:6]==0)&&(dt==0))begin
frame_identity<=next_fs_identity;
if(frame_open&&!dropping)begin request_valid=1;
request_sof=0;
request_eol=0;
request_abort=1;
request_code=5;
end else if(FRAME_EVENTS_ENABLE != 0)begin
request_valid=1; request_code=7; request_identity=next_fs_identity;
end
if(FRAME_EVENTS_ENABLE != 0 && frame_open && !dropping)begin
next_fs=1;next_pending_fs_identity=next_fs_identity;end
frame_open<=1;
first_group<=1;
dropping<=0;
last_pending<=0;
o_packet_done<=1;
state<=DRAIN;
end
     else if((hc[7:6]==0)&&(dt==1))begin
if(FRAME_EVENTS_ENABLE != 0 && frame_open && !dropping)begin
request_valid=1; request_code=6;
end
frame_open<=0;
first_group<=0;
o_packet_done<=1;
state<=DRAIN;
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
request_valid=1;
request_sof=0;
request_eol=0;
request_abort=1;
request_code=4;
end end
     else begin o_packet_done<=1;
state<=DRAIN;
end
 end else if(state==PKT) begin
    // 每个输入字只决定一次负载与 CRC 的分界，CRC 候选值不依赖剩余字节计数递减链
crc1=cb(crc,i_word[7:0]);
crc2=cb(crc1,i_word[15:8]);
crc3=cb(crc2,i_word[23:16]);
crc4=cb(crc3,i_word[31:24]);
if(left>=16'd4)payload_count=3'd4;
else payload_count=left[2:0];
nleft=left-{13'd0,payload_count};
case(payload_count)
 3'd0:ncrc=crc;
 3'd1:ncrc=crc1;
 3'd2:ncrc=crc2;
 3'd3:ncrc=crc3;
 default:ncrc=crc4;
endcase
nbcnt=bcnt;
nbytes=bytes;
nseen=crc_lo_seen;
nlo=crc_lo;
emit=0;
finish=0;
bad=0;
eol=0;
edata=0;
case(left)
 16'd0:begin
  finish=1;
  if(crc_lo_seen)bad=({i_word[7:0],crc_lo}!=ncrc);
  else begin nlo=i_word[7:0];nseen=1;bad=({i_word[15:8],i_word[7:0]}!=ncrc);end
 end
 16'd1:begin nlo=i_word[15:8];nseen=1;finish=1;bad=({i_word[23:16],i_word[15:8]}!=ncrc);end
 16'd2:begin nlo=i_word[23:16];nseen=1;finish=1;bad=({i_word[31:24],i_word[23:16]}!=ncrc);end
 16'd3:begin nlo=i_word[31:24];nseen=1;end
 default:begin end
endcase
// Fixed 4-byte WORD positions within a CSI RAW group. A short final
// payload word has no following payload before the next header. Any
// bytes above nbcnt are unowned and are never exposed as RAW pixels.
if(raw_packet && payload_count!=0)begin
 case(bcnt)
  0:begin nbcnt=payload_count;nbytes=i_word;end
  1:if(payload_count>=3'd4)begin
      emit=1;edata=up({i_word[31:0],bytes[7:0]});eol=left==16'd4;
      nbcnt=payload_count-3'd4;nbytes=0;
  end else begin
      nbcnt=bcnt+payload_count;nbytes={i_word,bytes[7:0]};
  end
  2:if(payload_count>=3'd3)begin
      emit=1;edata=up({i_word[23:0],bytes[15:0]});eol=left==16'd3;
      nbcnt=payload_count-3'd3;nbytes=i_word[31:24];
  end else begin
      nbcnt=bcnt+payload_count;nbytes={i_word,bytes[15:0]};
  end
  3:if(payload_count>=3'd2)begin
      emit=1;edata=up({i_word[15:0],bytes[23:0]});eol=left==16'd2;
      nbcnt=payload_count-3'd2;nbytes=i_word[31:16];
  end else begin
      nbcnt=bcnt+payload_count;nbytes={i_word,bytes[23:0]};
  end
  4:if(payload_count>=3'd1)begin
      emit=1;edata=up({i_word[7:0],bytes[31:0]});eol=left==16'd1;
      nbcnt=payload_count-3'd1;nbytes=i_word[31:8];
  end else begin
      nbcnt=bcnt+payload_count;nbytes={i_word,bytes[31:0]};
  end
  default:begin nbcnt=0;nbytes=0;end
 endcase
end
     left<=nleft;
crc<=ncrc;
bcnt<=nbcnt;
bytes<=nbytes;
crc_lo_seen<=nseen;
crc_lo<=nlo;
if(emit&&!dropping&&frame_open)begin if(output_available)begin if(eol)begin last_data<=edata;
last_sof<=first_group;
last_pending<=1;
first_group<=0;
end else begin request_data=edata;
request_valid=1;
request_sof=first_group;
request_eol=0;
request_abort=0;
request_code=0;
first_group<=0;
end end else begin dropping<=1;
last_pending<=0;
request_valid=1;
request_sof=0;
request_eol=0;
request_abort=1;
request_code=3;
end end
     if(finish)begin state<=DRAIN;
o_packet_done<=1;
if(bad)begin o_payload_crc_error<=1;
dropping<=1;
last_pending<=0;
request_valid=1;
request_sof=0;
request_eol=0;
request_abort=1;
request_code=2;
end else if(!dropping&&frame_open&&(last_pending||(emit&&eol)))begin
 if(output_available)begin
  request_data=(emit&&eol)?edata:last_data;
  request_valid=1;
  request_sof=(emit&&eol)?first_group:last_sof;
  request_eol=1;
  request_abort=0;
  request_code=0;
  first_group<=0;
  last_pending<=0;
 end else begin
  dropping<=1;
  last_pending<=0;
  request_valid=1;
  request_sof=0;
  request_eol=0;
  request_abort=1;
  request_code=3;
 end
end end
    end
   end else if(state==DRAIN) state<=HDR;
   if(FRAME_EVENTS_ENABLE == 0)begin
    // Preserve the legacy fatal-event override, including its timing.
    if(request_valid)begin
     o_data<=request_data; o_valid<=1; o_sof<=request_sof;
     o_eol<=request_eol; o_abort<=request_abort; o_error_code<=request_code;
    end
   end else begin
    // Drain older controls before a newly parsed request. DATA cannot pass
    // either control; output_available excludes these pending registers.
    if(!o_valid || i_sink_ready)begin
     if(terminal_pending)begin
      o_data<={7'd0,pending_terminal_identity}; o_valid<=1; o_sof<=0; o_eol<=0;
      o_abort<=(terminal_code != 6); o_error_code<=terminal_code;
      next_terminal=0; output_used=1;
     end else if(drop_pending)begin
      // A dropped, never announced FS must not poison the preceding owner.
      o_data<={7'd0,1'b0,sequence_counter}; o_valid<=1; o_sof<=0; o_eol<=0;
      o_abort<=0; o_error_code<=8;
      next_drop=0; output_used=1;
     end else if(fs_pending)begin
      o_data<={7'd0,pending_fs_identity}; o_valid<=1; o_sof<=0; o_eol<=0;
      o_abort<=0; o_error_code<=7;
      next_fs=0; next_open=1; output_used=1;
     end
    end
    if(request_valid)begin
     if(request_code == 0)begin
      o_data<=request_data; o_valid<=1; o_sof<=request_sof;
      o_eol<=request_eol; o_abort<=0; o_error_code<=0;
     end else if(request_code == 7)begin
      if(!next_open && !next_terminal && !next_fs && !next_drop &&
         (!o_valid || i_sink_ready) && !output_used)begin
       o_data<={7'd0,request_identity}; o_valid<=1; o_sof<=0; o_eol<=0;
       o_abort<=0; o_error_code<=7; next_open=1;
      end else if(!next_fs)begin
       next_fs=1;next_pending_fs_identity=request_identity;
      end else begin
       // No unbounded frame queue: this unseen frame is discarded.
       next_fs=0; next_drop=1; dropping<=1;
      end
     end else begin
      // A failure before its FS was published discards that unseen FS.
      // A previously queued successful FE belongs to the preceding frame
      // and is never overwritten by errors of this discarded next frame.
      if(next_open)begin
       if(!next_terminal)begin
        if((!o_valid || i_sink_ready) && !output_used)begin
         o_data<={7'd0,request_identity}; o_valid<=1; o_sof<=0; o_eol<=0;
         o_abort<=(request_code != 6); o_error_code<=request_code;
        end else begin next_terminal=1; next_code=request_code;next_pending_terminal_identity=request_identity; end
        next_open=0;
       end
      end else if(request_code != 5)begin
       next_fs=0;
       if(request_code == 3)next_drop=1;
      end
     end
    end
    terminal_pending<=next_terminal; terminal_code<=next_code;
    fs_pending<=next_fs; event_open<=next_open; drop_pending<=next_drop;
    pending_fs_identity<=next_pending_fs_identity;pending_terminal_identity<=next_pending_terminal_identity;
   end
  end
 end
endmodule
