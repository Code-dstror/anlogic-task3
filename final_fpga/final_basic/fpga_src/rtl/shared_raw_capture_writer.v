`timescale 1ns/1ps

// One RAW10 ingress FIFO consumer. At most one real AXI burst is outstanding.
// Metadata is borrowed by the bank owner before any address is presented.
module shared_raw_capture_writer #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter [27:0] RAW_BASE=28'h2000000,
    parameter [3:0] AXI_ID=4'd1,
    parameter integer CAMERA_COUNT=1, FIXED_HDR_ROLE=0, COMPACT_CAPTURE_HEADER=0
) (
    input wire i_clk,i_identity_rst_n,i_stop,i_sdr_profile,
    input wire [127:0] s_data,input wire [15:0] s_keep,
    input wire [1:0] s_user,input wire s_valid,s_last,
    input wire [9:0] i_available,output reg s_ready,
    output reg [383:0] o_frame,
    output wire o_begin_valid,input wire i_begin_ready,i_begin_accepted,
    input wire [1:0] i_capture_slot,
    output wire o_finish_valid,o_finish_ok,input wire i_finish_ready,
    output wire o_quiet,output reg o_protocol_fault,
    output reg [31:0] o_success_count,o_error_count,
    output wire [3:0] m_axi_awid,output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,output wire m_axi_bready
);
    localparam integer FRAME_SAMPLES=WIDTH*HEIGHT;
    localparam integer FRAME_BYTES=(FRAME_SAMPLES*10+7)/8;
    localparam [3:0] IDLE=0,CONTEXT0=1,CONTEXT1=2,CONTEXT2=3,
        ADMIT=4,PLAN=5,ADDRESS=6,DATA=7,RESPONSE=8,END_FRAME=9,DRAIN=10,FINISH=11,
        RESERVE=12;
    reg [3:0] state;
    reg granted,bad,fill,terminal_seen;
    reg profile_sdr;
    // First unwritten beat; includes an extra terminal value when the frame
    // contains a power-of-two number of beats. Progress includes zero-strobe
    // filler for an AW already accepted before a malformed input token.
    localparam integer FRAME_BEATS=(FRAME_BYTES+15)/16;
    localparam integer PROGRESS_BITS=$clog2(FRAME_BEATS+1);
    localparam [PROGRESS_BITS-1:0] LAST_INDEX=FRAME_BEATS-1;
    localparam [PROGRESS_BITS-1:0] TAIL_START=FRAME_BEATS>16 ? FRAME_BEATS-16 : 0;
    localparam [15:0] TAIL_KEEP=16'hffff >> ((16-(FRAME_BYTES%16))%16);
    reg [PROGRESS_BITS-1:0] beat_index;
    reg [2:0] slot_key;
    wire [3:0] slot_page=RAW_BASE[27:24]+{1'b0,slot_key};
    wire [19:0] slot_word=beat_index;
    wire frame_done=beat_index==FRAME_BEATS;
    // ADDRESS owns AWLEN until acceptance. DATA then reuses these bits
    // for the number of remaining beats after the currently presented W.
    reg [3:0] beats_after;
    // Bounded scheduling delay only: reserve existing FIFO tokens, never
    // infer END, B completion, quiet or owner release from elapsed cycles.
    reg [7:0] plan_age;
    reg [4:0] plan_available;
    wire is_start=s_user==1 && !s_last;
    wire is_context=s_user==1 && s_last && s_keep==16'hffff;
    wire is_terminal=s_user==2 || s_user==3;
    wire start_legal=s_keep==16'hffff && (CAMERA_COUNT==2 || s_data[96]==0) &&
        s_data[47:32]==WIDTH && s_data[63:48]==HEIGHT &&
        s_data[127:97]==FRAME_SAMPLES && !i_stop && !o_protocol_fault;
    wire context0_legal=is_context && s_data[39:32]==1 &&
        s_data[71:40]==o_frame[108:77] && s_data[103:72]==o_frame[140:109] &&
        (profile_sdr ? ((s_data[107:104]==2 && s_data[127:116]==0) ||
                       (s_data[107:104]==3 && s_data[127:117]==0)) :
        (s_data[107:104]==1 && s_data[127:113]==0 &&
        s_data[112] && s_data[111] && (s_data[110:109]==1 || s_data[110:109]==2)));
    wire compact_context_legal=s_user==1 && s_last &&
        s_keep[15:4]==12'hca1 && s_keep[3:2]==FIXED_HDR_ROLE[1:0] && s_keep[0] &&
        s_data[127:96]==o_frame[140:109] && s_data[95:64]==o_frame[108:77];
    // Third private word preserves every scalar flag and calibration bit.
    // Repeated epoch/sequence binds it to the preceding START and timestamp.
    wire compact3_legal=is_context && s_data[127:96]==o_frame[140:109] &&
        s_data[95:64]==o_frame[108:77] && s_data[31:25]==0 &&
        (CAMERA_COUNT==2 || !s_data[24]) &&
        (profile_sdr ? ((s_data[3:0]==2 && s_data[23:12]==0) ||
                       (s_data[3:0]==3 && s_data[23:13]==0)) :
        (s_data[3:0]==1 && s_data[23:9]==0 && s_data[8] && s_data[7] &&
         (s_data[6:5]==1 || s_data[6:5]==2)));
    wire context2_legal=is_context && s_data[95:64]==o_frame[108:77] &&
        s_data[127:96]==o_frame[140:109];
    wire [15:0] expected_keep=beat_index==LAST_INDEX ? TAIL_KEEP : 16'hffff;
    wire data_legal=s_user==0 && s_keep==expected_keep &&
        s_last==(beat_index==LAST_INDEX);
    wire end_legal=s_user==2 && !s_last && s_keep==16'hffff &&
        s_data[127:65]==0 && s_data[64] && s_data[63:32]==FRAME_SAMPLES &&
        s_data[31:0]==FRAME_BYTES && frame_done;
    wire [4:0] remaining_beats=beat_index<TAIL_START ? 5'd16 :
        FRAME_BEATS[4:0]-slot_word[4:0];
    wire [4:0] boundary_beats=slot_word[7:4]==4'hf ?
        5'd16-{1'b0,slot_word[3:0]} : 5'd16;
    wire [4:0] planned_beats=remaining_beats<boundary_beats ? remaining_beats : boundary_beats;
    wire [4:0] available_beats=i_available>=16 ? 5'd16 : i_available[4:0];
    wire [4:0] reserved_beats=plan_available<planned_beats ? plan_available : planned_beats;
    wire coalesce_ready=reserved_beats==planned_beats || (&plan_age);
    wire input_fire=s_valid && s_ready;
    wire write_fire=m_axi_wvalid && m_axi_wready;
    assign o_begin_valid=state==ADMIT;
    assign o_finish_valid=state==FINISH && granted;
    assign o_finish_ok=!bad;
    assign o_quiet=state==IDLE && !granted;
    assign m_axi_awid=AXI_ID;
    assign m_axi_awaddr={slot_page,slot_word,4'b0000};
    assign m_axi_awlen={4'd0,beats_after};
    assign m_axi_awsize=3'd4;
    assign m_axi_awburst=2'd1;
    assign m_axi_awvalid=state==ADDRESS;
    assign m_axi_wvalid=state==DATA && (fill || s_valid);
    assign m_axi_wdata=!fill && s_user==0 ? s_data : 128'd0;
    assign m_axi_wstrb=!fill && data_legal ? expected_keep : 16'd0;
    assign m_axi_wlast=beats_after==0;
    assign m_axi_bready=state==RESPONSE;
    always @* begin
        s_ready=0;
        case(state)
            IDLE:s_ready=1;
            CONTEXT0,CONTEXT1,CONTEXT2:s_ready=!is_start;
            DATA:s_ready=!fill && !is_start && m_axi_wready;
            END_FRAME,DRAIN:s_ready=!is_start;
            default:s_ready=0;
        endcase
    end
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin
            profile_sdr<=0;
            state<=IDLE;granted<=0;bad<=0;fill<=0;terminal_seen<=0;
            slot_key<=0;beat_index<=0;beats_after<=0;
            plan_age<=0;plan_available<=0;
            o_frame<=0;o_protocol_fault<=0;o_success_count<=0;o_error_count<=0;
        end else begin
            if(state!=PLAN && state!=RESERVE)plan_age<=0;
            else if((s_valid || plan_age!=0) && !(&plan_age))plan_age<=plan_age+1'b1;
            if(i_stop && state!=IDLE && state!=FINISH)bad<=1;
            // A response without a committed address/data transaction is not
            // absorbed and never counts as successful completion.
            if(m_axi_bvalid && state!=RESPONSE)begin o_protocol_fault<=1;bad<=1;end
            case(state)
                IDLE:if(input_fire && is_start)begin
                    profile_sdr<=i_sdr_profile;
                    o_frame<=0;bad<=0;fill<=0;terminal_seen<=0;granted<=0;
                    beat_index<=0;
                    o_frame[108:77]<=s_data[31:0];
                    o_frame[4]<=s_data[96];
                    o_frame[140:109]<=s_data[95:64];
                    o_frame[220:205]<=WIDTH;o_frame[236:221]<=HEIGHT;
                    o_frame[238:237]<=1;
                    if(COMPACT_CAPTURE_HEADER!=0)begin
                        o_frame[76:45]<=s_data[63:32];
                        o_frame[366:335]<=s_data[127:96];
                    end
                    if(FIXED_HDR_ROLE!=0)begin
                        o_frame[4]<=1'b1;
                        o_frame[76:45]<=s_data[63:32];
                        o_frame[366:335]<=s_data[127:96];
                    end
                    if(COMPACT_CAPTURE_HEADER!=0 ? (s_keep==16'hc030 && !i_stop && !o_protocol_fault) : FIXED_HDR_ROLE!=0 ? (s_keep==16'hffff && !i_stop && !o_protocol_fault) : start_legal)state<=CONTEXT0;
                    else begin bad<=1;state<=DRAIN;end
                end
                CONTEXT0,CONTEXT1,CONTEXT2:begin
                    if(s_valid && is_start)begin bad<=1;state<=FINISH;end
                    else if(input_fire)begin
                        if(COMPACT_CAPTURE_HEADER!=0)begin
                            if(state==CONTEXT0 && is_context)begin
                                o_frame[204:141]<=s_data[63:0];
                                o_frame[302:271]<=s_data[95:64];
                                o_frame[334:303]<=s_data[127:96];
                                state<=CONTEXT1;
                            end else if(state==CONTEXT1 && compact3_legal)begin
                                o_frame[270:239]<=s_data[63:32];
                                o_frame[4]<=s_data[24];
                                o_frame[3]<=s_data[4];
                                o_frame[2:1]<=s_data[6:5];
                                o_frame[0]<=s_data[7];
                                if(profile_sdr)begin
                                    o_frame[371]<=s_data[3:0]==3 && s_data[12];
                                    o_frame[367]<=s_data[8];
                                    o_frame[370:368]<=s_data[11:9];
                                end
                                state<=ADMIT;
                            end else begin bad<=1;state<=is_terminal?FINISH:DRAIN;end
                        end else if(FIXED_HDR_ROLE!=0)begin
                            // The accepted FIFO header repeats the START's epoch and
                            // sequence. A failed recipe never qualifies for a RAW slot.
                            if(state==CONTEXT0 && compact_context_legal)begin
                                o_frame[0]<=s_keep[1];
                                o_frame[2:1]<=FIXED_HDR_ROLE[1:0];o_frame[3]<=1'b1;
                                o_frame[204:141]<=s_data[63:0];
                                o_frame[302:271]<=FIXED_HDR_ROLE==1 ? 32'd3200 : 32'd200;
                                o_frame[334:303]<=32'd256;o_frame[270:239]<=32'h56a3d02f;
                                state<=ADMIT;
                            end else begin bad<=1;state<=is_terminal?FINISH:DRAIN;end
                        end else if((state==CONTEXT0 && context0_legal) ||
                            (state==CONTEXT1 && is_context) ||
                            (state==CONTEXT2 && context2_legal))begin
                            if(state==CONTEXT0)begin
                                o_frame[76:45]<=s_data[31:0];
                                if(profile_sdr)begin
                                    o_frame[371]<=s_data[107:104]==3 && s_data[116];
                                    o_frame[367]<=s_data[112];
                                    o_frame[370:368]<=s_data[115:113];
                                end
                                o_frame[3]<=s_data[108];o_frame[2:1]<=s_data[110:109];
                                o_frame[0]<=s_data[111];state<=CONTEXT1;
                            end else if(state==CONTEXT1)begin
                                o_frame[204:141]<=s_data[63:0];
                                o_frame[302:271]<=s_data[95:64];
                                o_frame[334:303]<=s_data[127:96];state<=CONTEXT2;
                            end else begin
                                o_frame[270:239]<=s_data[31:0];
                                o_frame[366:335]<=s_data[63:32];state<=ADMIT;
                            end
                        end else begin
                            bad<=1;state<=is_terminal ? FINISH : DRAIN;
                        end
                    end
                end
                ADMIT:if(i_begin_ready)begin
                    if(i_begin_accepted)begin
                        granted<=1;slot_key<={o_frame[4],i_capture_slot};state<=PLAN;
                    end else begin bad<=1;state<=DRAIN;end
                end
                PLAN:begin
                    if(i_stop || bad || o_protocol_fault || m_axi_bvalid)begin bad<=1;state<=DRAIN;end
                    else if(s_valid)begin
                        if(s_user!=0)begin bad<=1;state<=DRAIN;end
                        else begin
                            // No tokens are consumed in PLAN/RESERVE. This
                            // snapshot is conservative while the producer may
                            // add tokens, and cuts rdusedw's correction/addition
                            // away from the burst decision and address state.
                            plan_available<=available_beats;state<=RESERVE;
                        end
                    end
                end
                RESERVE:begin
                    if(i_stop || bad || o_protocol_fault || m_axi_bvalid)begin bad<=1;state<=DRAIN;end
                    else if(reserved_beats!=0 && coalesce_ready)begin
                            beats_after<=reserved_beats[3:0]-1'b1;state<=ADDRESS;
                    end else state<=PLAN;
                end
                ADDRESS:if(m_axi_awready)state<=DATA;
                DATA:if(write_fire)begin
                    beats_after<=beats_after-1'b1;
                    beat_index<=beat_index+1'b1;
                    if(!fill)begin
                        if(!data_legal)begin bad<=1;fill<=1;end
                        if(is_terminal)terminal_seen<=1;
                    end
                    if(beats_after==0)state<=RESPONSE;
                end
                RESPONSE:if(m_axi_bvalid)begin
                    if(m_axi_bid!=AXI_ID || m_axi_bresp!=0)bad<=1;
                    if(m_axi_bid!=AXI_ID) o_protocol_fault<=1;
                    if(bad || i_stop || m_axi_bid!=AXI_ID || m_axi_bresp!=0)begin
                        state<=terminal_seen ? FINISH : DRAIN;
                    end else if(frame_done)state<=END_FRAME;
                    else state<=PLAN;
                end
                END_FRAME:begin
                    if(s_valid && is_start)begin bad<=1;state<=FINISH;end
                    else if(input_fire)begin
                        if(!end_legal)bad<=1;
                        state<=is_terminal ? FINISH : DRAIN;
                    end
                end
                DRAIN:begin
                    if(s_valid && is_start)state<=FINISH;
                    else if(input_fire && is_terminal)state<=FINISH;
                end
                FINISH:if(!granted || i_finish_ready)begin
                    if(granted && !bad && !i_stop)o_success_count<=o_success_count+1'b1;
                    else o_error_count<=o_error_count+1'b1;
                    granted<=0;state<=IDLE;
                end
                default:begin o_protocol_fault<=1;bad<=1;state<=DRAIN;end
            endcase
        end
    end
    generate if(WIDTH<4 || WIDTH%4!=0 || HEIGHT<1 || FRAME_BYTES>16777216 ||
        RAW_BASE[23:0]!=0)begin:g_bad_geometry
        HDR_CAPTURE_REQUIRES_BOUNDED_RAW10_SLOT_GEOMETRY invalid_profile();
    end endgenerate
endmodule
