`timescale 1ns/1ps
// Decode CFS tokens into four-byte beats using official banked history RAM.
module cfs_lz77_decoder #(
    parameter integer CONTEXT_WIDTH=160,
    parameter integer MAX_RAW_LENGTH=2560
) (
    input wire i_clk,i_rst_n,
    input wire i_start_valid,
    output wire o_start_ready,
    input wire [31:0] i_block_id,
    input wire [CONTEXT_WIDTH-1:0] i_context,
    input wire [11:0] i_raw_length,i_stored_length,
    input wire i_input_valid,
    output wire o_input_ready,
    input wire [31:0] i_input_data,
    input wire [3:0] i_input_keep,
    input wire i_input_last,
    output wire o_output_valid,
    input wire i_output_ready,
    output wire [31:0] o_output_data,
    output wire [3:0] o_output_keep,
    output wire o_output_last,
    output wire [31:0] o_output_block_id,
    output wire [CONTEXT_WIDTH-1:0] o_output_context,
    output wire o_status_valid,
    input wire i_status_ready,
    output wire o_status_ok,
    output wire [7:0] o_status_error,
    output wire [11:0] o_status_count,
    output wire [31:0] o_status_block_id,
    output wire [CONTEXT_WIDTH-1:0] o_status_context
);
    localparam [2:0] S_IDLE=0,S_TOKEN=1,S_LITERAL=2,S_MATCH=3,
                     S_FINISH=4,S_DRAIN=5,S_DONE=6;
    localparam integer MAX_STORED_LENGTH=MAX_RAW_LENGTH+(MAX_RAW_LENGTH+127)/128;
    localparam integer HISTORY_WORDS=(MAX_RAW_LENGTH+3)/4;
    reg [2:0] state,state_next;
    reg [31:0] block_id;
    reg [CONTEXT_WIDTH-1:0] block_context;
    reg [11:0] raw_length,stored_length,received_count,decoded_count,committed_count;
    reg [7:0] error_code,literal_left,match_left;
    reg [15:0] match_distance;
    reg input_complete;
    reg [63:0] byte_window;
    reg [3:0] window_count;
    reg output_valid,output_is_match,output_last;
    reg [2:0] output_bytes;
    reg [31:0] literal_word;
    reg [1:0] read_base_low;
    reg [15:0] output_distance;
    wire [31:0] history_word;
    wire [31:0] output_word=output_is_match ? history_word : literal_word;
    wire output_fire=output_valid && i_output_ready;
    wire output_slot=!output_valid || i_output_ready;
    wire start_fire=i_start_valid && o_start_ready;
    wire parameter_ok=i_raw_length>=1 && i_raw_length<=MAX_RAW_LENGTH &&
        i_stored_length>=1 && i_stored_length<=MAX_STORED_LENGTH;
    wire parsing=state==S_TOKEN || state==S_LITERAL || state==S_MATCH || state==S_FINISH;

    reg [2:0] input_bytes;
    reg input_keep_ok;
    reg [31:0] masked_input;
    always @(*) begin
        input_bytes=0;input_keep_ok=1;masked_input=0;
        case(i_input_keep)
            4'b0001:begin input_bytes=1;masked_input={24'd0,i_input_data[7:0]};end
            4'b0011:begin input_bytes=2;masked_input={16'd0,i_input_data[15:0]};end
            4'b0111:begin input_bytes=3;masked_input={8'd0,i_input_data[23:0]};end
            4'b1111:begin input_bytes=4;masked_input=i_input_data;end
            default:input_keep_ok=0;
        endcase
    end
    reg [2:0] consume_bytes,issue_bytes,reserved_consumption;
    reg issue_output,issue_match,load_literal,load_match;
    reg [15:0] issue_distance;
    reg [7:0] new_literal_length,new_match_length,failure_code;
    reg [31:0] issue_literal_word;
    reg [2:0] first_literal_bytes,second_literal_bytes;
    reg [7:0] second_header,second_literal_length;
    reg [3:0] second_available;
    reg [12:0] second_literal_end;
    integer literal_lane;
    reg [12:0] output_end;
    wire [3:0] remaining_window=window_count-consume_bytes;
    wire [3:0] input_window_remaining=window_count-reserved_consumption;
    assign o_start_ready=i_rst_n && state==S_IDLE;
    assign o_input_ready=i_rst_n && !input_complete &&
        ((parsing && input_window_remaining<=4) || state==S_DRAIN);
    wire input_fire=i_input_valid && o_input_ready;
    wire [12:0] received_end={1'b0,received_count}+input_bytes;
    wire [7:0] token_byte=byte_window[7:0];
    wire [7:0] token_match_length={1'b0,token_byte[6:0]}+8'd3;
    wire [7:0] token_literal_length={1'b0,token_byte[6:0]}+8'd1;
    wire [15:0] token_distance=byte_window[23:8];
    wire [12:0] match_end={1'b0,decoded_count}+token_match_length;
    wire [12:0] literal_end={1'b0,decoded_count}+token_literal_length;
    wire [11:0] read_source=decoded_count-issue_distance;

    // State transitions and issue decisions use the current parser window only.
    always @(*) begin
        state_next=state;consume_bytes=0;issue_bytes=0;reserved_consumption=0;issue_output=0;issue_match=0;
        load_literal=0;load_match=0;issue_distance=match_distance;
        new_literal_length=0;new_match_length=0;failure_code=0;output_end={1'b0,decoded_count};
        issue_literal_word=byte_window[31:0];first_literal_bytes=0;second_literal_bytes=0;
        second_header=0;second_literal_length=0;second_available=0;second_literal_end=0;
        case(state)
            S_IDLE:if(start_fire) state_next=parameter_ok ? S_TOKEN : S_DONE;
            S_TOKEN:if(output_slot) begin
                if(window_count==0) begin
                    if(input_complete) failure_code=7;
                end else if(!token_byte[7]) begin
                    if(literal_end>{1'b0,raw_length}) failure_code=6;
                    else begin
                        consume_bytes=1;load_literal=1;new_literal_length=token_literal_length;
                        state_next=S_LITERAL;
                        // Merge the header with payload, then at most one more literal token.
                        if(window_count>=2) begin
                            first_literal_bytes=token_literal_length<4 ? token_literal_length[2:0] : 3'd4;
                            if(window_count-1<first_literal_bytes) first_literal_bytes=window_count-1;
                            consume_bytes=1+first_literal_bytes;issue_bytes=first_literal_bytes;
                            issue_output=1;issue_literal_word=byte_window[39:8];
                            new_literal_length=token_literal_length-first_literal_bytes;
                            output_end={1'b0,decoded_count}+first_literal_bytes;
                            if(new_literal_length==0) begin
                                state_next=output_end=={1'b0,raw_length} ? S_FINISH : S_TOKEN;
                                if(first_literal_bytes<4 && output_end<{1'b0,raw_length} &&
                                    window_count>=first_literal_bytes+2) begin
                                    case(first_literal_bytes)
                                        3'd1:second_header=byte_window[23:16];
                                        3'd2:second_header=byte_window[31:24];
                                        3'd3:second_header=byte_window[39:32];
                                        default:second_header=8'h80;
                                    endcase
                                    if(!second_header[7]) begin
                                        second_literal_length={1'b0,second_header[6:0]}+8'd1;
                                        second_literal_end=output_end+second_literal_length;
                                        if(second_literal_end>{1'b0,raw_length}) failure_code=6;
                                        else begin
                                            second_available=window_count-first_literal_bytes-2;
                                            second_literal_bytes=4-first_literal_bytes;
                                            if(second_literal_length<second_literal_bytes)
                                                second_literal_bytes=second_literal_length[2:0];
                                            if(second_available<second_literal_bytes)
                                                second_literal_bytes=second_available[2:0];
                                            for(literal_lane=0;literal_lane<4;literal_lane=literal_lane+1)
                                                if(literal_lane>=first_literal_bytes &&
                                                    literal_lane<first_literal_bytes+second_literal_bytes)
                                                    issue_literal_word[literal_lane*8 +:8]=byte_window[(literal_lane+2)*8 +:8];
                                            consume_bytes=consume_bytes+1+second_literal_bytes;
                                            issue_bytes=first_literal_bytes+second_literal_bytes;
                                            new_literal_length=second_literal_length-second_literal_bytes;
                                            output_end={1'b0,decoded_count}+issue_bytes;
                                            state_next=new_literal_length!=0 ? S_LITERAL :
                                                (output_end=={1'b0,raw_length} ? S_FINISH : S_TOKEN);
                                        end
                                    end
                                end
                            end
                        end
                    end
                end else if(window_count<3) begin
                    if(input_complete) failure_code=4;
                end else if(token_distance==0 || token_distance>4096 || token_distance>decoded_count)
                    failure_code=5;
                else if(match_end>{1'b0,raw_length}) failure_code=6;
                else begin
                    consume_bytes=3;load_match=1;new_match_length=token_match_length;
                    issue_distance=token_distance;issue_output=1;issue_match=1;
                    issue_bytes=token_match_length<4 ? token_match_length[2:0] : 3'd4;
                    output_end={1'b0,decoded_count}+issue_bytes;
                    if(token_match_length>issue_bytes) state_next=S_MATCH;
                    else state_next=output_end=={1'b0,raw_length} ? S_FINISH : S_TOKEN;
                end
            end
            S_LITERAL:if(output_slot) begin
                if(window_count==0) begin
                    if(input_complete) failure_code=4;
                end else begin
                    issue_bytes=literal_left<4 ? literal_left[2:0] : 3'd4;
                    if(window_count<issue_bytes) issue_bytes=window_count[2:0];
                    consume_bytes=issue_bytes;issue_output=1;
                    output_end={1'b0,decoded_count}+issue_bytes;
                    if(literal_left==issue_bytes)
                        state_next=output_end=={1'b0,raw_length} ? S_FINISH : S_TOKEN;
                end
            end
            S_MATCH:if(output_slot) begin
                issue_bytes=match_left<4 ? match_left[2:0] : 3'd4;
                issue_output=1;issue_match=1;output_end={1'b0,decoded_count}+issue_bytes;
                if(match_left==issue_bytes)
                    state_next=output_end=={1'b0,raw_length} ? S_FINISH : S_TOKEN;
            end
            S_FINISH:begin
                if(window_count!=0) failure_code=8;
                else if(input_complete && output_slot) state_next=S_DONE;
            end
            S_DRAIN:if(input_complete && output_slot) state_next=S_DONE;
            S_DONE:if(i_status_ready) state_next=S_IDLE;
            default:state_next=S_IDLE;
        endcase
        // Reserve parser space before transport validation, avoiding a ready/fault loop.
        reserved_consumption=consume_bytes;
        // Transport faults outrank token interpretation on the same edge.
        if(parsing && input_fire) begin
            if(!input_keep_ok) failure_code=2;
            else if(received_end>{1'b0,stored_length} ||
                i_input_last!=(received_end=={1'b0,stored_length})) failure_code=3;
        end
        if(failure_code!=0) begin
            state_next=S_DRAIN;consume_bytes=0;issue_output=0;issue_match=0;
            load_literal=0;load_match=0;issue_bytes=0;
        end
    end
    always @(posedge i_clk) begin
        if(!i_rst_n) state<=S_IDLE;
        else state<=state_next;
    end
    wire [63:0] shifted_window=byte_window>>(consume_bytes*8);
    wire [63:0] inserted_input={32'd0,masked_input}<<(remaining_window*8);
    always @(posedge i_clk) begin
        if(!i_rst_n) begin
            block_id<=0;block_context<=0;raw_length<=0;stored_length<=0;received_count<=0;
            decoded_count<=0;committed_count<=0;error_code<=0;input_complete<=0;
            literal_left<=0;match_left<=0;match_distance<=0;byte_window<=0;window_count<=0;
            output_valid<=0;output_is_match<=0;output_last<=0;output_bytes<=0;
            literal_word<=0;read_base_low<=0;output_distance<=0;
        end else if(start_fire) begin
            block_id<=i_block_id;block_context<=i_context;raw_length<=i_raw_length;stored_length<=i_stored_length;
            received_count<=0;decoded_count<=0;committed_count<=0;input_complete<=0;
            error_code<=parameter_ok ? 8'd0 : 8'd1;
            literal_left<=0;match_left<=0;match_distance<=0;byte_window<=0;window_count<=0;
            output_valid<=0;output_last<=0;output_bytes<=0;
        end else begin
            if(output_fire) committed_count<=committed_count+output_bytes;
            if(output_slot) begin
                output_valid<=issue_output;
                if(issue_output) begin
                    output_is_match<=issue_match;output_bytes<=issue_bytes;
                    output_last<=output_end=={1'b0,raw_length};
                    decoded_count<=output_end[11:0];
                    if(issue_match) begin read_base_low<=read_source[1:0];output_distance<=issue_distance;end
                    else literal_word<=issue_literal_word;
                end
            end
            if(load_literal) literal_left<=new_literal_length;
            else if(issue_output && !issue_match) literal_left<=literal_left-issue_bytes;
            if(load_match) begin match_distance<=issue_distance;match_left<=new_match_length-issue_bytes;end
            else if(issue_output && issue_match) match_left<=match_left-issue_bytes;
            if(input_fire) begin
                received_count<=received_end[11:0];
                if(i_input_last || received_end>={1'b0,stored_length}) input_complete<=1;
            end
            if(failure_code!=0) begin
                if(error_code==0) error_code<=failure_code;
                window_count<=0;byte_window<=0;
            end else if(parsing) begin
                byte_window<=shifted_window | (input_fire ? inserted_input : 64'd0);
                window_count<=remaining_window+(input_fire ? input_bytes : 3'd0);
            end
        end
    end

    // Each source/destination group touches each physical byte bank at most once.
    wire [31:0] bank_responses;
    genvar bank;
    generate for(bank=0;bank<4;bank=bank+1) begin:g_history
        localparam [1:0] BANK_ID=bank;
        wire [1:0] write_delta=BANK_ID-committed_count[1:0];
        wire [1:0] read_delta=BANK_ID-read_source[1:0];
        wire [12:0] write_address={1'b0,committed_count}+write_delta;
        wire [12:0] read_address={1'b0,read_source}+read_delta;
        wire [9:0] write_word=write_address[11:2];
        wire [9:0] read_word=read_address[11:2];
        wire write_enable=i_rst_n && output_fire && write_delta<output_bytes;
        wire read_enable=i_rst_n && issue_output && issue_match;
        wire [7:0] write_byte=output_word[write_delta*8 +:8];
        wire [7:0] ram_byte;
        reg bypass_valid;
        reg [7:0] bypass_byte;
        td_sdp_ram #(.WIDTH(8),.DEPTH(HISTORY_WORDS),.ADDR_WIDTH(10)) u_ram (
            .clk(i_clk),.wr_en(write_enable),.wr_addr(write_word),.wr_data(write_byte),
            .rd_en(read_enable),.rd_addr(read_word),.rd_data(ram_byte));
        // The cross-port collision result is replaced, independent of vendor ordering.
        always @(posedge i_clk) begin
            if(!i_rst_n) begin bypass_valid<=0;bypass_byte<=0;end
            else if(read_enable) begin
                bypass_valid<=write_enable && write_word==read_word;
                bypass_byte<=write_byte;
            end
        end
        assign bank_responses[bank*8 +:8]=bypass_valid ? bypass_byte : ram_byte;
    end endgenerate
    wire [1:0] source_bank0=read_base_low;
    wire [1:0] source_bank1=read_base_low+2'd1;
    wire [1:0] source_bank2=read_base_low+2'd2;
    wire [1:0] source_bank3=read_base_low+2'd3;
    wire [7:0] seed0=bank_responses[source_bank0*8 +:8];
    wire [7:0] seed1=bank_responses[source_bank1*8 +:8];
    wire [7:0] seed2=bank_responses[source_bank2*8 +:8];
    wire [7:0] seed3=bank_responses[source_bank3*8 +:8];
    assign history_word=output_distance==1 ? {seed0,seed0,seed0,seed0} :
        output_distance==2 ? {seed1,seed0,seed1,seed0} :
        output_distance==3 ? {seed0,seed2,seed1,seed0} : {seed3,seed2,seed1,seed0};
    assign o_output_valid=i_rst_n && output_valid;
    assign o_output_data=output_word;
    assign o_output_keep=output_bytes==4 ? 4'b1111 :
        output_bytes==3 ? 4'b0111 : output_bytes==2 ? 4'b0011 : 4'b0001;
    assign o_output_last=output_last;
    assign o_output_block_id=block_id;
    assign o_output_context=block_context;
    assign o_status_valid=i_rst_n && state==S_DONE;
    assign o_status_ok=error_code==0;
    assign o_status_error=error_code;
    assign o_status_count=committed_count;
    assign o_status_block_id=block_id;
    assign o_status_context=block_context;
endmodule
