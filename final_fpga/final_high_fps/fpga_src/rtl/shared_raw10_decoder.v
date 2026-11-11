`timescale 1ns / 1ps
// Two frame cursors share one canonical RAW10 byte reservoir. Geometry is the
// authenticated, already computed parent PREPARE result, not a host byte count.
module shared_raw10_decoder (
    input wire i_clk, input wire i_rst_n,
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
    reg [167:0] pack_data,pack_next;
    reg [4:0] pack_bytes,bytes_next;
    reg owner,owner_next;
    reg [31:0] total_bytes,total_groups;
    reg [31:0] received_long,received_short,emitted_long,emitted_short;
    reg [31:0] received_long_next,received_short_next,emitted_long_next,emitted_short_next;
    reg [1:0] done_pulse,abort_pulse,done_next,abort_next;
    wire [1:0] owner_state=owner?state_short:state_long;
    wire [1:0] incoming_state=i_axis_member?state_short:state_long;
    wire [31:0] received=i_axis_member?received_short:received_long;
    wire [31:0] emitted=owner?emitted_short:emitted_long;
    wire [31:0] owner_received=owner?received_short:received_long;
    wire [31:0] remaining=total_bytes-received;
    wire [4:0] incoming_bytes=remaining>=16?5'd16:remaining[4:0];
    wire [15:0] expected_keep=incoming_bytes==16?16'hffff:(16'hffff>>(16-incoming_bytes));
    wire raw_fire=o_valid&&i_ready;
    wire [4:0] after_pop=raw_fire?pack_bytes-5'd5:pack_bytes;
    wire switch_allowed=pack_bytes==0||(raw_fire&&pack_bytes==5);
    wire axis_fire=i_axis_valid&&o_axis_ready;
    wire bad_word=remaining==0||i_axis_keep!=expected_keep||i_axis_last!=(remaining<=16);
    wire overlapping_start=i_start&&(state_long!=IDLE||state_short!=IDLE);
    wire [1:0] abort_request=i_abort|{2{overlapping_start}};
    wire [34:0] configured_bytes={3'd0,i_total_groups}+({3'd0,i_total_groups}<<2);
    wire configured_valid=i_total_groups!=0&&configured_bytes[34:32]==0&&configured_bytes[31:0]==i_total_bytes;
    assign o_member=owner;
    assign o_data=pack_data[39:0];
    assign o_valid=owner_state!=IDLE&&pack_bytes>=5;
    assign o_axis_ready=incoming_state==ACTIVE&&after_pop<=5&&
        (owner==i_axis_member||switch_allowed)&&!i_start&&!(|abort_request)&&
        state_long!=ABORT_WAIT&&state_short!=ABORT_WAIT;
    assign o_done=done_pulse;
    assign o_abort=abort_pulse;

    // A legal append has only six phases. Precompute both native-pop
    // cases from registered byte count so late i_ready never controls a
    // subtract-and-variable-shift chain. Writes above the owned byte count
    // are speculative: they cannot alter a presented native group, and an
    // accepted AXIS word overwrites those bytes on its original edge.
    // State/count alone discard errors and START; no late fault/start/AXIS
    // admission signal needs to clear or enable the 168-bit payload bank.
    reg [167:0] payload_without_pop, payload_with_pop;
    always @(*) begin
        payload_without_pop = pack_data;
        case (pack_bytes)
            0: payload_without_pop = {40'd0, i_axis_data};
            1: payload_without_pop = {32'd0, i_axis_data, pack_data[7:0]};
            2: payload_without_pop = {24'd0, i_axis_data, pack_data[15:0]};
            3: payload_without_pop = {16'd0, i_axis_data, pack_data[23:0]};
            4: payload_without_pop = {8'd0, i_axis_data, pack_data[31:0]};
            5: payload_without_pop = {i_axis_data, pack_data[39:0]};
            default: begin end
        endcase
        payload_with_pop = pack_data >> 40;
        case (pack_bytes)
            5: payload_with_pop = {40'd0, i_axis_data};
            6: payload_with_pop = {32'd0, i_axis_data, pack_data[47:40]};
            7: payload_with_pop = {24'd0, i_axis_data, pack_data[55:40]};
            8: payload_with_pop = {16'd0, i_axis_data, pack_data[63:40]};
            9: payload_with_pop = {8'd0, i_axis_data, pack_data[71:40]};
            10: payload_with_pop = {i_axis_data, pack_data[79:40]};
            default: begin end
        endcase
        pack_next = raw_fire ? payload_with_pop : payload_without_pop;
    end

    always @(*)begin
        next_long=state_long;next_short=state_short;
        bytes_next=pack_bytes;owner_next=owner;
        received_long_next=received_long;received_short_next=received_short;
        emitted_long_next=emitted_long;emitted_short_next=emitted_short;
        done_next=0;abort_next=0;
        if(raw_fire)begin
            bytes_next=after_pop;
            if(owner)emitted_short_next=emitted_short+1'b1;
            else emitted_long_next=emitted_long+1'b1;
            if(emitted==total_groups-1'b1)begin
                if(owner_state==DRAIN&&owner_received==total_bytes&&after_pop==0)begin
                    done_next[owner]=1;
                    if(owner)next_short=IDLE;else next_long=IDLE;
                end else begin
                    abort_next[owner]=1;bytes_next=0;
                    if(owner)next_short=IDLE;else next_long=IDLE;
                end
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
                if(i_axis_member)received_short_next=received_short+incoming_bytes;
                else received_long_next=received_long+incoming_bytes;
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
            received_long_next=0;received_short_next=0;emitted_long_next=0;emitted_short_next=0;
            if(configured_valid)begin next_long=ACTIVE;next_short=ACTIVE;end
            else begin next_long=IDLE;next_short=IDLE;abort_next=3;end
        end
    end
    // Byte count and member state invalidate reservoir contents. The first
    // accepted word after invalidation uses phase zero and overwrites every
    // bit; held native groups remain protected by ABORT_WAIT. Keeping invalid
    // payload avoids terminal/abort qualification driving 168 clear muxes.
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin state_long<=IDLE;state_short<=IDLE;end
        else begin state_long<=next_long;state_short<=next_short;end
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            pack_data<=0;pack_bytes<=0;owner<=0;total_bytes<=0;total_groups<=0;
            received_long<=0;received_short<=0;emitted_long<=0;emitted_short<=0;
            done_pulse<=0;abort_pulse<=0;
        end else begin
            pack_data<=pack_next;pack_bytes<=bytes_next;owner<=owner_next;
            received_long<=received_long_next;received_short<=received_short_next;
            emitted_long<=emitted_long_next;emitted_short<=emitted_short_next;
            done_pulse<=done_next;abort_pulse<=abort_next;
            if(i_start&&!overlapping_start)begin total_bytes<=i_total_bytes;total_groups<=i_total_groups;end
        end
    end
endmodule
