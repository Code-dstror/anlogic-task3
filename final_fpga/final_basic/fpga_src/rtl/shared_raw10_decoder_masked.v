`timescale 1ns / 1ps
// Two frame cursors share one canonical RAW10 byte reservoir. Geometry is the
// authenticated, already computed parent PREPARE result, not a host byte count.
module shared_raw10_decoder_masked #(
    parameter integer BYTE_COUNT_WIDTH=32, GROUP_COUNT_WIDTH=32
) (
    input wire i_clk, input wire i_rst_n,
    input wire [1:0] i_member_mask, output wire o_idle,
    output wire [31:0] o_emitted0,
    input wire i_start, input wire [31:0] i_total_bytes, input wire [31:0] i_total_groups,
    input wire [1:0] i_abort,
    input wire i_axis_member, input wire [127:0] i_axis_data,
    input wire [15:0] i_axis_keep, input wire i_axis_valid, input wire i_axis_last,
    output wire o_axis_ready,
    output wire o_member, output wire [39:0] o_data, output wire o_valid,
    input wire i_ready, output wire [1:0] o_done, output wire [1:0] o_abort
);
    localparam [1:0] IDLE=0,ACTIVE=1,DRAIN=2,ABORT_WAIT=3;
    reg [1:0] state_long,state_short,next_long,next_short;
    reg [127:0] word_q;
    reg [39:0] tail_q;
    reg [4:0] head;
    wire [207:0] window = {40'd0,word_q,tail_q};
    reg [4:0] pack_bytes,bytes_next;
    reg owner,owner_next;
    // Number of complete, nonterminal 16-byte transfers still expected.
    // Counts are independent even though only the latched reservoir owner pops.
    localparam integer FULL_WIDTH = BYTE_COUNT_WIDTH > 4 ? BYTE_COUNT_WIDTH-4 : 1;
    reg [FULL_WIDTH-1:0] full_long,full_short;
    reg [4:0] final_bytes;
    reg [GROUP_COUNT_WIDTH-1:0] emitted_long;
    reg [1:0] done_pulse,abort_pulse,done_next,abort_next;
    wire [1:0] owner_state=owner?state_short:state_long;
    wire [1:0] incoming_state=i_axis_member?state_short:state_long;
    wire last_expected = (i_axis_member ? full_short : full_long) == 0;
    wire [4:0] incoming_bytes = last_expected ? final_bytes : 5'd16;
    wire [15:0] expected_keep = last_expected ? (16'hffff >> (16-final_bytes)) : 16'hffff;
    wire raw_fire=o_valid&&i_ready;
    wire [4:0] after_pop=raw_fire?pack_bytes-5'd5:pack_bytes;
    wire switch_allowed=pack_bytes==0||(raw_fire&&pack_bytes==5);
    wire axis_fire=i_axis_valid&&o_axis_ready;
    wire bad_word=i_axis_keep!=expected_keep||i_axis_last!=last_expected;
    wire overlapping_start=i_start&&(state_long!=IDLE||state_short!=IDLE);
    wire [1:0] abort_request=i_abort|{2{overlapping_start}};
    wire [34:0] configured_bytes={3'd0,i_total_groups}+({3'd0,i_total_groups}<<2);
    // Default widths retain the standalone 32-bit configuration contract.
    // Narrow instances reject values that would otherwise alias on capture.
    wire configured_fits=(i_total_bytes >> BYTE_COUNT_WIDTH)==0 &&
        (i_total_groups >> GROUP_COUNT_WIDTH)==0;
    wire configured_valid=configured_fits&&i_total_groups!=0&&configured_bytes[34:32]==0&&configured_bytes[31:0]==i_total_bytes;
    assign o_idle=state_long==IDLE&&state_short==IDLE&&pack_bytes==0;
    assign o_emitted0=emitted_long;
    assign o_member=owner;
    assign o_data=window[head*8+:40];
    assign o_valid=owner_state!=IDLE&&pack_bytes>=5;
    assign o_axis_ready=incoming_state==ACTIVE&&after_pop<=5&&
        (owner==i_axis_member||switch_allowed)&&!i_start&&!(|abort_request)&&
        state_long!=ABORT_WAIT&&state_short!=ABORT_WAIT;
    assign o_done=done_pulse;
    assign o_abort=abort_pulse;

    // An append leaves at most five old bytes. An earlier partial AXIS
    // transfer was necessarily a terminal and can never be extended; hence
    // those old bytes are always the suffix of the last complete 16B word.
    // Capturing a rejected word while a group is stalled (after_pop == 5)
    // transfers that exact held group into tail_q; ABORT_WAIT protects it.
    always @(posedge i_clk) begin
        if(axis_fire) begin
            word_q <= i_axis_data;
            tail_q <= word_q[127:88];
            head <= 5'd5-after_pop;
        end else if(raw_fire) head <= head+5'd5;
    end

    always @(*)begin
        next_long=state_long;next_short=state_short;
        bytes_next=pack_bytes;owner_next=owner;
        done_next=0;abort_next=0;
        if(raw_fire)begin
            bytes_next=after_pop;
            // START proved frame_bytes == 5 * groups. A validated last word
            // entered DRAIN and switching is permitted only on an empty
            // reservoir. Thus this is precisely the final accepted group.
            if(owner_state==DRAIN && pack_bytes==5)begin
                done_next[owner]=1;
                if(owner)next_short=IDLE;else next_long=IDLE;
            end
        end
        if(axis_fire)begin
            if(bad_word)begin
                if(owner==i_axis_member&&o_valid&&!raw_fire)begin
                    if(i_axis_member)next_short=ABORT_WAIT;else next_long=ABORT_WAIT;
                end else begin
                    abort_next[i_axis_member]=1;
                    if(i_axis_member)next_short=IDLE;else next_long=IDLE;
                    if(owner==i_axis_member)bytes_next=0;
                end
            end else begin
                owner_next=i_axis_member;
                bytes_next=after_pop+incoming_bytes;
                if(i_axis_last)begin
                    if(i_axis_member)next_short=DRAIN;else next_long=DRAIN;
                end
            end
        end
        // An abort never destroys a held native group; a peer has no shared
        // reservoir contents to discard until it is the latched owner.
        if((abort_request[0]&&state_long!=IDLE)||state_long==ABORT_WAIT)begin
            done_next[0]=0;
            if(!owner&&o_valid&&!raw_fire)next_long=ABORT_WAIT;
            else begin
                next_long=IDLE;abort_next[0]=1;
                if(!owner)bytes_next=0;
            end
        end
        if((abort_request[1]&&state_short!=IDLE)||state_short==ABORT_WAIT)begin
            done_next[1]=0;
            if(owner&&o_valid&&!raw_fire)next_short=ABORT_WAIT;
            else begin
                next_short=IDLE;abort_next[1]=1;
                if(owner)bytes_next=0;
            end
        end
        if(i_start&&!overlapping_start)begin
            bytes_next=0;owner_next=0;
            if(configured_valid && (i_member_mask==1 || i_member_mask==3))begin
                next_long=i_member_mask[0]?ACTIVE:IDLE;
                next_short=i_member_mask[1]?ACTIVE:IDLE;
            end else begin next_long=IDLE;next_short=IDLE;abort_next=i_member_mask;end
        end
    end
    // Reset and abort invalidate the window by clearing the owned byte
    // count; payload is observed only when five or more bytes are valid.
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin state_long<=IDLE;state_short<=IDLE;end
        else begin state_long<=next_long;state_short<=next_short;end
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            pack_bytes<=0;owner<=0;
            full_long<=0;full_short<=0;final_bytes<=0;emitted_long<=0;
            done_pulse<=0;abort_pulse<=0;
        end else begin
            pack_bytes<=bytes_next;owner<=owner_next;
            done_pulse<=done_next;abort_pulse<=abort_next;
            if(i_start&&!overlapping_start)begin
                full_long <= (i_total_bytes-1'b1)>>4;
                full_short <= (i_total_bytes-1'b1)>>4;
                final_bytes <= i_total_bytes[3:0]==0 ? 5'd16 : {1'b0,i_total_bytes[3:0]};
                emitted_long <= 0;
            end else begin
                if(raw_fire && !owner) emitted_long <= emitted_long+1'b1;
                if(axis_fire && !bad_word && !last_expected)begin
                    if(i_axis_member) full_short <= full_short-1'b1;
                    else full_long <= full_long-1'b1;
                end
            end
        end
    end
endmodule
