`timescale 1ns/1ps
// Private LZ NORMAL-only binding: caller owns immutable identity through result acceptance.
// Prefix packing remains unchanged; the first word maps its fixed seed
// into the existing unmodified official FFFFFFFF core.
module cfs_crc32_adapter #(
    parameter integer INPUT_BYTES=4,
    parameter integer PREFIX_CORES=0
) (
    input wire i_clk,i_rst_n,i_abort,
    input wire i_request_valid,output wire o_request_ready,
    input wire [383:0] i_frame,input wire [159:0] i_context,
    input wire [63:0] i_tag,input wire [31:0] i_generation,i_block_id,
    input wire i_stored,input wire [11:0] i_length,
    input wire i_data_valid,output wire o_data_ready,
    input wire [INPUT_BYTES*8-1:0] i_data,
    input wire [INPUT_BYTES-1:0] i_keep,input wire i_last,
    output wire o_result_valid,input wire i_result_ready,
    output wire [383:0] o_frame,output wire [159:0] o_context,
    output wire [63:0] o_tag,output wire [31:0] o_generation,o_block_id,
    output wire o_stored,output wire [11:0] o_length,
    output wire [31:0] o_crc,output wire o_ok
);
    localparam [2:0] S_IDLE=0,S_ARM=1,S_DATA=2,S_WAIT=3,S_RESULT=4;
    localparam integer PACK_BYTES=INPUT_BYTES+3;
    localparam [INPUT_BYTES-1:0] FULL_KEEP={INPUT_BYTES{1'b1}};
    reg [2:0] state,state_next;
    reg [31:0] crc_o;
    reg stored_o,error_o,source_closed;
    reg [11:0] length_o;
    reg [12:0] count;
    reg [1:0] prefix;
    reg [PACK_BYTES*8-1:0] pack_data,merged_data;
    reg [4:0] pack_count,merged_count,keep_count;
    reg [INPUT_BYTES*8-1:0] accepted_data;
    integer lane;
    wire [31:0] selected_crc;
    wire selected_valid;
    reg first_word;
    reg [31:0] first_word_xor;
    // In reflected, low-byte-first coordinates a full-word CRC update is
    // T32(state XOR data). Thus an initial-state difference is exactly a
    // first-input-word XOR; the registered official recurrence is untouched.
    // Constants are bitreverse32(FFFFFFFF XOR the frozen official INIT).
    always @(*) begin
        case(prefix)
            2'd1:first_word_xor=32'h0f6a7026; // official INIT 9BF1A90F
            2'd2:first_word_xor=32'h65e3626f; // official INIT 09B93859
            2'd3:first_word_xor=32'h5cd1d97e; // official INIT 816474C5
            default:first_word_xor=0;
        endcase
    end
    wire [31:0] core_data=merged_data[31:0] ^ (first_word ? first_word_xor : 32'd0);
    wire request_fire=i_request_valid && o_request_ready;
    wire [1:0] request_prefix=2'd0-i_length[1:0];
    wire data_fire=i_data_valid && o_data_ready;
    wire [12:0] accepted_end=count+keep_count;
    wire input_bad=i_keep==0 || (i_keep & (i_keep+1'b1))!=0 ||
        (!i_last && i_keep!=FULL_KEEP) || accepted_end>length_o ||
        i_last!=(accepted_end==length_o);
    wire pack_take=state==S_DATA && merged_count>=4;
    wire final_chunk=pack_take && (source_closed || (data_fire && i_last)) && merged_count==4;
    wire bad_tail=state==S_DATA && (source_closed || (data_fire && i_last)) && merged_count<4;
    wire core_enable=i_rst_n && !i_abort && pack_take && !error_o && !(data_fire && input_bad);
    wire core_end=core_enable && final_chunk;
    wire core_start=i_rst_n && state==S_ARM && !i_abort;
    always @(*) begin
        keep_count=0;accepted_data=0;
        for(lane=0;lane<INPUT_BYTES;lane=lane+1)begin
            keep_count=keep_count+i_keep[lane];
            if(i_keep[lane])accepted_data[lane*8+:8]=i_data[lane*8+:8];
        end
        merged_data=pack_data;merged_count=pack_count;
        if(data_fire)begin
            merged_data=pack_data | ({{24{1'b0}},accepted_data}<<(pack_count*8));
            merged_count=pack_count+keep_count;
        end
    end
    // Ready remains asserted until data acceptance; FAST can couple this to W.
    assign o_request_ready=i_rst_n && state==S_IDLE && !i_abort;
    assign o_data_ready=i_rst_n && state==S_DATA && !source_closed && pack_count<4 && !i_abort;
    assign o_result_valid=i_rst_n && state==S_RESULT;
    assign o_frame=i_frame;assign o_context=i_context;assign o_tag=i_tag;
    assign o_generation=i_generation;assign o_block_id=i_block_id;
    assign o_stored=stored_o;assign o_length=length_o;
    assign o_crc=crc_o;assign o_ok=!error_o;
    cfs_crc32_32 u_p0(.clk(i_clk),.rst(!i_rst_n),.din(core_data),
        .din_en(core_enable),.packet_start(core_start),.packet_end(core_end),
        .crc_out(selected_crc),.crc_out_vld(selected_valid));
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n)first_word<=1;
        else if(core_start)first_word<=1;
        else if(core_enable)first_word<=0;
    end
    always @(*) begin
        state_next=state;
        case(state)
            S_IDLE:if(request_fire)state_next=S_ARM;
            S_ARM:state_next=(i_abort || length_o==0 || length_o>2560) ? S_RESULT : S_DATA;
            S_DATA:begin
                if(i_abort)state_next=S_RESULT;
                else if(final_chunk)state_next=(error_o || (data_fire && input_bad)) ? S_RESULT : S_WAIT;
                else if(bad_tail)state_next=S_RESULT;
            end
            S_WAIT:if(i_abort || selected_valid)state_next=S_RESULT;
            S_RESULT:if(i_result_ready)state_next=S_IDLE;
            default:state_next=S_IDLE;
        endcase
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)state<=S_IDLE;
        else state<=state_next;
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            stored_o<=0;length_o<=0;crc_o<=0;error_o<=0;count<=0;prefix<=0;
            pack_data<=0;pack_count<=0;source_closed<=0;
        end else begin
            if(request_fire)begin
                stored_o<=i_stored;length_o<=i_length;crc_o<=0;count<=0;
                prefix<=request_prefix;
                pack_data<=0;pack_count<={3'd0,request_prefix};source_closed<=0;
                error_o<=i_length==0 || i_length>2560 ||
                    (PREFIX_CORES==0 && i_length[1:0]!=0) ||
                    (INPUT_BYTES!=4 && INPUT_BYTES!=16);
            end
            if(i_abort && state!=S_IDLE && state!=S_RESULT)error_o<=1;
            if(data_fire)begin
                count<=accepted_end;
                if(input_bad)error_o<=1;
                if(i_last)source_closed<=1;
            end
            if(state==S_DATA && !i_abort)begin
                pack_data<=pack_take ? merged_data>>32 : merged_data;
                pack_count<=pack_take ? merged_count-4 : merged_count;
                if(bad_tail)error_o<=1;
            end
            if(state==S_WAIT && selected_valid && !i_abort)crc_o<=selected_crc;
        end
    end
endmodule
