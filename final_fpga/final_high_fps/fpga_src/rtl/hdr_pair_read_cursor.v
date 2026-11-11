`timescale 1ns/1ps

// One immutable acquired pair, two bounded byte cursors, one outstanding AR.
// A small response queue overlaps the next burst latency with RAW10 decoding.
// No per-chunk descriptor FETCH/RETIRE or complete-frame metadata copies.
module hdr_pair_read_cursor #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter [27:0] RAW_BASE=28'h2000000,
    parameter [3:0] AXI_ID=4'd1
) (
    input wire i_clk,i_identity_rst_n,
    input wire i_start_valid,i_pair_bank,i_pair_camera,output wire o_start_ready,
    input wire i_cancel,
    // A true bit certifies an empty member FIFO/reservoir with 512 free groups.
    input wire [1:0] i_member_credit,
    output wire [31:0] o_long_offset,o_short_offset,
    output wire [127:0] m_data,output wire [15:0] m_keep,
    output wire m_member,m_valid,m_last,input wire m_ready,
    output wire o_result_valid,output wire o_result_ok,input wire i_result_ready,
    output wire o_bus_quiet,output reg o_protocol_fault,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    localparam integer FRAME_BYTES=WIDTH*HEIGHT/4*5;
    localparam [2:0] IDLE=0,SELECT=1,PREPARE=2,ADDRESS=3,READ=4,RESULT=5,CHUNK=6;
    reg [2:0] state;
    reg bank,camera,member,turn,failed;
    // A full chunk fills 512 RAW10 groups and ends on a 16-beat boundary.
    // Only the final frame word can be partial.
    localparam [7:0] CHUNK_WORDS=8'd160;
    localparam integer FRAME_WORDS=(FRAME_BYTES+15)/16;
    localparam integer INDEX_BITS=$clog2(FRAME_WORDS+1);
    localparam [15:0] LAST_KEEP=16'hffff >> ((16-FRAME_BYTES%16)%16);
    localparam integer LAST_CHUNK_START=FRAME_WORDS>CHUNK_WORDS ? FRAME_WORDS-CHUNK_WORDS : 0;
    reg [INDEX_BITS-1:0] long_word,short_word;
    reg [7:0] chunk_words;
    reg [4:0] beats_left;
    wire [INDEX_BITS-1:0] selected_word=member ? short_word : long_word;
    wire [19:0] slot_word=selected_word;
    wire [3:0] page=RAW_BASE[27:24]+{1'b0,camera,bank,member};
    wire [1:0] candidates={short_word<FRAME_WORDS && i_member_credit[1],
        long_word<FRAME_WORDS && i_member_credit[0]};
    wire selected_member=candidates[1] && (!candidates[0] || turn);
    wire [7:0] next_chunk=selected_word<LAST_CHUNK_START ? CHUNK_WORDS :
        FRAME_WORDS[7:0]-slot_word[7:0];
    wire [4:0] remaining_beats=chunk_words>=16 ? 5'd16 : chunk_words[4:0];
    wire [4:0] boundary_beats=slot_word[7:4]==15 ?
        5'd16-{1'b0,slot_word[3:0]} : 5'd16;
    wire [4:0] next_beats=remaining_beats<boundary_beats ? remaining_beats : boundary_beats;
    wire last_word=selected_word==FRAME_WORDS-1;
    wire shape_ok=m_axi_rid==AXI_ID && m_axi_rlast==(beats_left==1);
    wire response_ok=shape_ok && m_axi_rresp==0;
    wire read_fire=m_axi_rvalid && m_axi_rready;
    wire output_fire=m_valid && m_ready;
    wire buffer_ready;
    wire [134:0] buffer_word;
    wire buffer_push=read_fire && !failed && !i_cancel && response_ok;
    // Includes the RAM contents and its held registered output. A hidden RAM
    // read may be pending while m_valid is low, so m_valid alone is not quiet.
    reg [4:0] queued_words;
    wire buffer_empty=queued_words==0;
    // The same-cohort enqueue/dequeue total equals the response bank's RAM
    // plus held output. It gives synchronous capacity without putting its
    // asynchronous reset mask onto the cursor's next-state data cone.
    wire buffer_capacity=queued_words<16;
    ddr_response_bank16 u_response_buffer(
        .clk(i_clk),.rst_n(i_identity_rst_n),
        .s_data({6'd0,last_word,m_axi_rdata}),.s_valid(buffer_push),.s_ready(buffer_ready),
        .m_data(buffer_word),.m_valid(m_valid),.m_ready(m_ready));
    assign m_data=buffer_word[127:0];
    assign m_last=buffer_word[128];
    assign m_keep=m_last ? LAST_KEEP : 16'hffff;
    // SELECT cannot change member until every queued word was consumed.
    assign m_member=member;
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)queued_words<=0;
        else case({buffer_push,output_fire})
            2'b10:queued_words<=queued_words+1'b1;
            2'b01:queued_words<=queued_words-1'b1;
            default:begin end
        endcase
    end
    assign o_long_offset=long_word==FRAME_WORDS ? FRAME_BYTES : {long_word,4'b0};
    assign o_short_offset=short_word==FRAME_WORDS ? FRAME_BYTES : {short_word,4'b0};
    assign o_start_ready=state==IDLE && buffer_empty && !o_protocol_fault;
    assign o_result_valid=state==RESULT && buffer_empty && !o_protocol_fault;
    assign o_result_ok=!failed;
    assign o_bus_quiet=state!=ADDRESS && state!=READ && buffer_empty && !o_protocol_fault;
    assign m_axi_arid=AXI_ID;
    assign m_axi_araddr={page,slot_word,4'b0};
    assign m_axi_arlen={3'd0,beats_left}-1'b1;
    assign m_axi_arsize=3'd4;
    assign m_axi_arburst=2'd1;
    assign m_axi_arvalid=state==ADDRESS;
    assign m_axi_rready=state==READ && (failed || i_cancel || buffer_capacity);
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin
            state<=IDLE;bank<=0;camera<=0;member<=0;turn<=0;failed<=0;
            long_word<=0;short_word<=0;chunk_words<=0;beats_left<=0;
            o_protocol_fault<=0;
        end else begin
            if(i_cancel && state!=IDLE && state!=RESULT)failed<=1;
            if(m_axi_rvalid && state!=READ)begin o_protocol_fault<=1;failed<=1;end
            case(state)
                IDLE:if(i_start_valid && o_start_ready)begin
                    bank<=i_pair_bank;camera<=i_pair_camera;long_word<=0;short_word<=0;failed<=i_cancel;
                    turn<=0;state<=SELECT;
                end
                SELECT:begin
                    if(failed || i_cancel || o_protocol_fault || m_axi_rvalid ||
                        (long_word==FRAME_WORDS && short_word==FRAME_WORDS))state<=RESULT;
                    else if(candidates!=0 && buffer_empty)begin
                        member<=selected_member;turn<=!selected_member;
                        state<=CHUNK;
                    end
                end
                // Credit reserves an empty member before the wide offset /
                // remainder calculation. No R or output transfer occurs here,
                // so its certified 512-group capacity cannot be consumed.
                CHUNK:begin
                    if(failed || i_cancel || o_protocol_fault || m_axi_rvalid)state<=RESULT;
                    else begin
                        chunk_words<=next_chunk;
                        state<=PREPARE;
                    end
                end
                PREPARE:begin
                    if(failed || i_cancel || o_protocol_fault || m_axi_rvalid)state<=RESULT;
                    else begin beats_left<=next_beats;state<=ADDRESS;end
                end
                ADDRESS:if(m_axi_arready)state<=READ;
                READ:if(read_fire)begin
                    if(!shape_ok)o_protocol_fault<=1;
                    if(!response_ok)failed<=1;
                    // A good beat enters the response queue above. Address
                    // progress is real R acceptance; decoding drains separately.
                    if(beats_left!=0)beats_left<=beats_left-1'b1;
                    if(chunk_words!=0)begin
                        chunk_words<=chunk_words-1'b1;
                        if(member)short_word<=short_word+1'b1;
                        else long_word<=long_word+1'b1;
                    end
                    if(m_axi_rlast)begin
                        if(failed || i_cancel || !response_ok)state<=RESULT;
                        else state <= (chunk_words <= 1) ? SELECT : PREPARE;
                    end
                end
                RESULT:if(o_result_valid && i_result_ready)state<=IDLE;
                default:begin o_protocol_fault<=1;failed<=1;state<=RESULT;end
            endcase
        end
    end
    generate if(WIDTH<4 || WIDTH%4!=0 || HEIGHT<1 || FRAME_BYTES>16777216 ||
        RAW_BASE[23:0]!=0)begin:g_bad_profile
        HDR_PAIR_CURSOR_REQUIRES_BOUNDED_RAW10_SLOT_GEOMETRY invalid_profile();
    end endgenerate
endmodule
