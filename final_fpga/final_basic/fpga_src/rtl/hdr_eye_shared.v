`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Two cameras share the admission/scan/write engine. Each camera retains its
// acquired pair, two banks, two writers and a separate directory read port.
module hdr_eye_shared #(
    parameter integer WIDTH=1920,HEIGHT=1080
)(
    input wire clk,rst_n,stop,transport_fault,input wire [63:0] now_ns,
    input wire config_valid,output wire config_ready,output reg config_error,
    input wire [31:0] cfg_session,cfg_epoch,cfg_delta,cfg_wait,cfg_age,
    input wire [2:0] cfg_ratio,input wire cfg_hdr,
    input wire [767:0] frames,input wire [1:0] begin_valid,member,
    output wire [1:0] begin_ready,accepted,
    output wire [3:0] capture_slots,output wire [31:0] camera0_generation,output wire [63:0] camera0_lease,
    input wire [3:0] finish_valid,finish_ok,output wire [3:0] finish_ready,
    output wire [1:0] pair_valid,pair_bank,output wire [127:0] pair_ids,input wire [1:0] pair_take,
    input wire [1:0] release_valid,input wire release_bank,input wire [63:0] release_id,
    input wire read_quiet,ticket_released,input wire [1:0] write_quiet,output wire [1:0] release_ready,
    input wire [1:0] ext_req,ext_slot,ext_consume,output wire [1:0] ext_ready,ext_valid,ext_last,
    output wire [63:0] ext_data,output wire [7:0] ext_word,output wire [1:0] empty,output wire fault,
    output wire [1:0] diag_begin_reject,diag_pair_expire,
    output wire [3:0] diag_bad_finish,output wire [7:0] diag_bank_states
);
    localparam [2:0] FREE=0,BUILD=1,READY=4,OWNED=5;
    localparam [3:0] IDLE=0,CHECK_BEGIN=1,REQ=2,SCAN=3,CHECK_PAIR=4,WRITE=5,REPLY=6,
        READ_SEQ=7,READ_LOW=8,READ_HIGH=9;
    reg [3:0] state;
    reg [2:0] bank_state[0:3];
    reg [1:0] seen[0:3],busy[0:3],done[0:3];
    reg [3:0] bad,first_role;
    reg [31:0] group_id[0:3];
    reg [63:0] arrival[0:3];
    reg [30:0] serial[0:3],counter[0:1];
    reg [1:0] newest,bank_turn,offered,offered_bank;
    reg [3:0] writing,writing_bank,seq_seen;
    reg [3:0] published_history;
    reg forward_seq,low_time_ge;
    // Per-eye floor for new allocations. A capacity-denied exposure cannot
    // later contribute to a complete group, even if the peer sees a free bank.
    reg [31:0] capacity_drop_group[0:1];
    reg [1:0] capacity_drop_seen;
    reg after_capacity_drop,remember_capacity_drop;
    reg configured,hdr;
    reg [31:0] session,epoch,max_delta,max_wait,max_age;
    reg [2:0] ratio;
    reg eye,eye_turn,role,bank,allow,consume_failed_peer,sticky_fault;
    reg [7:0] clear_slots;
    reg [3:0] word;
    // Only the accumulated zero/nonzero predicate is observed at CHECK_PAIR.
    // Keep the same accepted SCAN words, masks, clear edges and decision cycle.
    reg bad_bytes;
    reg [32:0] difference;
    reg low_ok,borrow,time_ok;
    wire [3:0] slot={2'd0,bank,role};
    wire [1:0] selected={eye,bank};
    wire [383:0] frame=eye?frames[767:384]:frames[383:0];
    wire [31:0] seq=frame[108:77];
    wire [63:0] stamp=frame[204:141];
    wire [31:0] group_in=frame[366:335];
    wire [1:0] lane={eye,member[eye]};
    wire [30:0] active_serial=serial[selected];
    wire [31:0] generation=active_serial==0?{31'b0,role}:{active_serial,1'b0}-{31'b0,!role};
    wire [63:0] lease={31'd0,eye,generation};
    assign capture_slots={2{slot[1:0]}};
    assign camera0_generation=generation;
    assign camera0_lease=lease;
    wire [1:0] selected_eye=eye?2'b10:2'b01;
    assign begin_ready=state==REPLY?selected_eye:0;
    assign accepted=begin_ready&{2{allow&&!stop&&!fault&&!bad[selected]}};
    assign diag_begin_reject=begin_ready&begin_valid&~accepted&{2{!stop&&!fault&&!config_valid}};
    assign diag_bad_finish=finish_valid&finish_ready&~finish_ok;
    wire [1:0] dir_busy,dir_fault,dir_write_ready,dir_read_ready,dir_valid,dir_last;
    wire [7:0] dir_word;
    wire [63:0] dir_data;
    wire [31:0] data=eye?dir_data[63:32]:dir_data[31:0];
    wire [3:0] index=eye?dir_word[7:4]:dir_word[3:0];
    wire [3:0] bank_live,bank_idle,discard_bank,complete_bank,expired_bank;
    wire [1:0] release_fire=release_valid&release_ready;
    wire same_cfg=configured&&session==cfg_session&&epoch==cfg_epoch;
    wire invalid_cfg=cfg_session==0||cfg_wait==0||cfg_age==0||(cfg_hdr&&cfg_ratio!=4)||
        (same_cfg&&(cfg_delta!=max_delta||cfg_wait!=max_wait||cfg_age!=max_age||cfg_ratio!=ratio||cfg_hdr!=hdr));
    wire cfg_safe=(&empty)||(state==IDLE&&writing==0&&dir_busy==0&&(same_cfg||invalid_cfg));
    assign config_ready=cfg_safe&&!fault;
    assign fault=transport_fault||sticky_fault||(|dir_fault);
    assign finish_ready=writing&{4{!fault}};
    wire [1:0] can_start=begin_valid & ~dir_busy & ~ext_req & ~release_fire;
    wire [1:0] scan_req={2{state==REQ||state==SCAN}}&selected_eye;
    wire [1:0] write_req={2{state==WRITE}}&selected_eye;

    // Two pages per (eye,role). Fill the inactive page during the existing
    // directory writes and flip exactly one pointer only on an accepted BEGIN.
    // A STOP or rejected second member leaves the prior three words intact.
    wire [1:0] read_index=state==READ_SEQ?0:state==READ_LOW?1:2;
    wire [1:0] history_lane={eye,role};
    wire [4:0] history_rd={lane,published_history[lane],read_index};
    wire [4:0] history_wr={history_lane,!published_history[history_lane],word[1:0]};
    wire [31:0] history_in=word==0?seq:word==1?stamp[31:0]:stamp[63:32];
    wire [31:0] history_q;
    td_sdp_ram40 #(.WIDTH(32),.DEPTH(32),.ADDR_WIDTH(5)) member_history(
        .clk(clk),.rd_en(state==READ_SEQ||state==READ_LOW||state==READ_HIGH),.rd_addr(history_rd),.rd_data(history_q),
        .wr_en(state==WRITE&&word<3&&dir_write_ready[eye]),.wr_addr(history_wr),.wr_data(history_in));
    wire [31:0] seq_step=seq-history_q;
    wire [31:0] capacity_group_step=group_in-capacity_drop_group[eye];
    wire successive=!seq_seen[lane]||(forward_seq&&
        (stamp[63:32]>history_q||(stamp[63:32]==history_q&&low_time_ge)));
    wire proper_role=member[eye]?(frame[2:1]==2&&frame[302:271]==200):(frame[2:1]==1&&frame[302:271]==3200);
    // The legal interval is (now-max_age, now], with no unsigned 64-bit
    // rollover for descriptor age. Share now.high-1 with bank expiry below.
    wire [31:0] prior_high=now_ns[63:32]-32'd1;
    wire [32:0] age_cut={1'b0,now_ns[31:0]}-{1'b0,max_age};
    wire stamp_same_epoch=stamp[63:32]==now_ns[63:32];
    wire stamp_previous_epoch=stamp[63:32]==prior_high;
    wire stamp_above_cut=stamp[31:0]>age_cut[31:0];
    wire stamp_in_age=(stamp_same_epoch&&stamp[31:0]<=now_ns[31:0]&&
        (age_cut[32]||stamp_above_cut))||
        (age_cut[32]&&now_ns[63:32]!=0&&stamp_previous_epoch&&stamp_above_cut);
    wire legal=configured&&hdr&&frame[383:367]==0&&frame[0]&&frame[3]&&frame[4]==eye&&
        proper_role&&!writing[lane]&&successive&&frame[76:45]==session&&frame[140:109]==epoch&&
        frame[220:205]==WIDTH&&frame[236:221]==HEIGHT&&frame[238:237]==1&&
        frame[334:303]==256&&frame[270:239]==32'h56a3d02f&&group_in!=0&&
        stamp_in_age;
    wire [1:0] match_bank,failed_peer,free_bank,resident;
    genvar k;
    generate for(k=0;k<2;k=k+1)begin:g_match
        wire [1:0] id={eye,k[0]};
        assign free_bank[k]=bank_state[id]==FREE;
        assign resident[k]=!free_bank[k]&&group_id[id]==group_in;
        assign failed_peer[k]=bank_state[id]==BUILD&&bad[id]&&group_id[id]==group_in&&!seen[id][member[eye]];
        assign match_bank[k]=bank_state[id]==BUILD&&!bad[id]&&group_id[id]==group_in&&
            !seen[id][member[eye]]&&(busy[id]!=0||bank_live[id]);
    end endgenerate
    wire chosen_free=free_bank[bank_turn[eye]]?bank_turn[eye]:!bank_turn[eye];
    wire chosen_match=match_bank[bank_turn[eye]]?bank_turn[eye]:!bank_turn[eye];
    wire [1:0] allocation={eye,chosen_free};
    reg [31:0] write_data,expected,mask;
    always @*begin
        case(word)
            0:write_data={25'd0,bank,role,eye,1'b1,role?2'd2:2'd1,1'b1};
            1:write_data=generation;
            2:write_data=session;
            3:write_data=seq;
            4:write_data=epoch;
            5:write_data=stamp[31:0];
            6:write_data=stamp[63:32];
            7:write_data={HEIGHT[15:0],WIDTH[15:0]};
            8:write_data=role?32'd200:32'd3200;
            9:write_data=32'd256;
            10:write_data=32'h56a3d02f;
            11:write_data=group_in;
            12:write_data=lease[31:0];
            13:write_data=lease[63:32];
            14:write_data=32'd1;
            default:write_data=0;
        endcase
        expected=0;mask=32'hffffffff;
        case(index)
            0:begin expected={27'd0,eye,1'b1,role?2'd1:2'd2,1'b1};mask=32'h1f;end
            2:expected=session;
            4:expected=epoch;
            7:expected={HEIGHT[15:0],WIDTH[15:0]};
            8:expected=role?32'd3200:32'd200;
            9:expected=256;
            10:expected=32'h56a3d02f;
            11:expected=group_in;
            14:expected=1;
            default:mask=0;
        endcase
    end
    wire [32:0] wait_cut={1'b0,now_ns[31:0]}-{1'b0,max_wait};
    wire mismatch=|((expected^data)&mask);
    generate for(k=0;k<4;k=k+1)begin:g_compare
        // For W<2^32 the open lower bound of (now-W, now] is shared.
        // If now.low<W it straddles one high-word boundary, including wrap.
        wire same_epoch=arrival[k][63:32]==now_ns[63:32];
        wire previous_epoch=arrival[k][63:32]==prior_high;
        wire at_or_before=arrival[k][31:0]<=now_ns[31:0];
        wire above_cut=arrival[k][31:0]>wait_cut[31:0];
        assign bank_live[k]=(same_epoch&&at_or_before&&(wait_cut[32]||above_cut))||
            (wait_cut[32]&&previous_epoch&&above_cut);
        assign bank_idle[k]=(state==IDLE||eye!=k/2)&&!dir_busy[k/2];
        assign discard_bank[k]=(bad[k]&&(seen[k]==0||seen[k]==3))||stop||
            (config_valid&&!invalid_cfg&&!same_cfg);
        assign complete_bank[k]=seen[k]==3&&done[k]==3;
        assign expired_bank[k]=bank_idle[k]&&bank_state[k]==BUILD&&busy[k]==0&&
            !discard_bank[k]&&!complete_bank[k]&&!bank_live[k];
        assign diag_bank_states[k*2+:2]={bank_state[k][2],bank_state[k][0]};
    end endgenerate
    assign diag_pair_expire={|expired_bank[3:2],|expired_bank[1:0]};
    wire [31:0] half=index[0]?stamp[31:0]:stamp[63:32];
    wire [31:0] short_half=role?half:data,long_half=role?data:half;
    generate for(k=0;k<2;k=k+1)begin:g_directory
        localparam BASE=k*2;
        wire [1:0] locks={bank_state[BASE+1]==OWNED,bank_state[BASE]==OWNED};
        wire external_enable=!release_valid[k]&&locks[ext_slot[1]]&&
                           (state==IDLE||eye!=k||state==REPLY);
        wire [1:0] read_slot=scan_req[k]?{bank,first_role[selected]}:ext_slot;
        wire read_request=(state==REQ&&eye==k)||(external_enable&&ext_req[k]);
        assign ext_ready[k]=external_enable&&dir_read_ready[k];
        assign ext_valid[k]=dir_valid[k]&&!scan_req[k];
        assign ext_last[k]=dir_last[k];
        assign ext_data[k*32+:32]=dir_data[k*32+:32];
        assign ext_word[k*4+:4]=dir_word[k*4+:4];
        assign release_ready[k]=!fault&&read_quiet&&write_quiet[k]&&ticket_released&&!dir_busy[k];
        wire here_idle=state==IDLE||eye!=k;
        assign empty[k]=bank_state[BASE]==FREE&&bank_state[BASE+1]==FREE&&
            here_idle&&writing[BASE+:2]==0&&!dir_busy[k]&&!offered[k];
        assign pair_valid[k]=offered[k]&&!stop&&!fault&&!config_valid;
        assign pair_bank[k]=offered_bank[k];
        assign pair_ids[k*64+:64]={32'd0,k[0],serial[{k[0],offered_bank[k]}]};
        hdr_pair_directory directory(
            .i_clk(clk),.i_identity_rst_n(rst_n),.i_locked({{2{locks[1]}},{2{locks[0]}}}),
            .i_clear(clear_slots[k*4+:4]),.s_slot(slot[1:0]),.s_data(write_data),.s_valid(write_req[k]),
            .s_last(word==15),.s_ready(dir_write_ready[k]),.i_read_slot(read_slot),.i_read_valid(read_request),
            .o_read_ready(dir_read_ready[k]),.m_data(dir_data[k*32+:32]),.m_word(dir_word[k*4+:4]),
            .m_valid(dir_valid[k]),.m_last(dir_last[k]),.m_ready(scan_req[k]||ext_consume[k]),
            .o_valid(),.o_write_busy(),.o_read_busy(dir_busy[k]),.o_fault(dir_fault[k]));
    end endgenerate
    always @(posedge clk)begin
        if(state==REPLY&&begin_valid[eye]&&remember_capacity_drop)
            capacity_drop_group[eye]<=group_in;
    end
    integer e,b;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;eye<=0;eye_turn<=0;role<=0;bank<=0;allow<=0;sticky_fault<=0;config_error<=0;
            configured<=0;session<=0;epoch<=0;max_delta<=0;max_wait<=0;max_age<=0;ratio<=0;hdr<=0;
            writing<=0;writing_bank<=0;seq_seen<=0;published_history<=0;newest<=0;offered<=0;offered_bank<=0;bank_turn<=0;
            capacity_drop_seen<=0;after_capacity_drop<=0;remember_capacity_drop<=0;
            bad<=0;first_role<=0;word<=0;bad_bytes<=0;clear_slots<=0;counter[0]<=0;counter[1]<=0;
            for(b=0;b<4;b=b+1)begin
                bank_state[b]<=FREE;seen[b]<=0;busy[b]<=0;done[b]<=0;group_id[b]<=0;arrival[b]<=0;
                serial[b]<=0;
            end
        end else begin
            clear_slots<=0;config_error<=0;
            if(transport_fault)sticky_fault<=1;
            if(config_valid&&config_ready)begin
                if(invalid_cfg)config_error<=1;
                else begin
                    configured<=1;session<=cfg_session;epoch<=cfg_epoch;max_delta<=cfg_delta;
                    max_wait<=cfg_wait;max_age<=cfg_age;ratio<=cfg_ratio;hdr<=cfg_hdr;
                    if(!same_cfg)begin seq_seen<=0;capacity_drop_seen<=0;end
                end
            end
            for(e=0;e<2;e=e+1)begin
                if(!offered[e]&&!stop&&!fault&&!config_valid&&
                    bank_state[e*2]!=OWNED&&bank_state[e*2+1]!=OWNED)begin
                    if(bank_state[e*2]==READY&&(bank_state[e*2+1]==FREE||bad[e*2+1]||newest[e]))begin
                        offered[e]<=1;offered_bank[e]<=0;
                    end else if(bank_state[e*2+1]==READY&&(bank_state[e*2]==FREE||bad[e*2]||!newest[e]))begin
                        offered[e]<=1;offered_bank[e]<=1;
                    end
                end
                if(pair_valid[e]&&pair_take[e])begin
                    bank_state[e*2+offered_bank[e]]<=OWNED;offered[e]<=0;bank_turn[e]<=!offered_bank[e];
                end
                if(release_fire[e])begin
                    if(bank_state[e*2+release_bank]!=OWNED||release_id!={32'd0,e[0],serial[e*2+release_bank]})sticky_fault<=1;
                    else begin bank_state[e*2+release_bank]<=FREE;clear_slots[(e*2+release_bank)*2+:2]<=3;end
                end
            end
            for(b=0;b<4;b=b+1)begin
                // These payload fields have no owner in FREE. Preload them
                // on the original decision edge, without the late admission
                // qualifier in their CE. A bank becoming BUILD freezes the
                // same now/group/role value that allocation used previously.
                if(bank_state[b]==FREE&&state==CHECK_BEGIN)begin
                    group_id[b]<=group_in;arrival[b]<=now_ns;first_role[b]<=member[eye];
                end
                if(finish_valid[b]&&finish_ready[b])begin
                    writing[b]<=0;busy[(b/2)*2+writing_bank[b]][b%2]<=0;done[(b/2)*2+writing_bank[b]][b%2]<=1;
                    if(!finish_ok[b]||stop)bad[(b/2)*2+writing_bank[b]]<=1;
                end
                if(bank_idle[b])begin
                    if(bank_state[b]==BUILD&&busy[b]==0)begin
                        // A failed first member can finish before its queued peer has
                        // reached BEGIN. Retain the group until rejecting that peer,
                        // expiry or STOP. Other eyes and good ready banks continue.
                        if(discard_bank[b])begin
                            bank_state[b]<=FREE;clear_slots[b*2+:2]<=3;
                        end else if(complete_bank[b])bank_state[b]<=READY;
                        else if(!bank_live[b])begin bank_state[b]<=FREE;clear_slots[b*2+:2]<=3;end
                    end
                    if(bank_state[b]==READY&&stop)begin bank_state[b]<=FREE;clear_slots[b*2+:2]<=3;offered[b/2]<=0;end
                end
            end
            case(state)
                IDLE:if(|can_start&&!fault)begin eye<=can_start[eye_turn]?eye_turn:!eye_turn;state<=READ_SEQ;end
                READ_SEQ:state<=READ_LOW;
                READ_LOW:begin forward_seq<=seq_step!=0&&!seq_step[31];state<=READ_HIGH;end
                READ_HIGH:begin
                    low_time_ge<=stamp[31:0]>=history_q;
                    after_capacity_drop<=!capacity_drop_seen[eye]||
                        (capacity_group_step!=0&&!capacity_group_step[31]);
                    state<=CHECK_BEGIN;
                end
                CHECK_BEGIN:begin
                    role<=member[eye];allow<=0;consume_failed_peer<=0;remember_capacity_drop<=0;
                    if(stop||fault||config_valid||!legal)state<=REPLY;
                    else if(|failed_peer)begin bank<=failed_peer[1];consume_failed_peer<=1;state<=REPLY;end
                    else if(|match_bank)begin bank<=chosen_match;bad_bytes<=0;state<=REQ;end
                    else if(!(|resident)&&after_capacity_drop&&counter[eye]!=31'h7fffffff)begin
                        if(|free_bank)begin
                            bank<=chosen_free;newest[eye]<=chosen_free;bank_state[allocation]<=BUILD;
                            seen[allocation]<=0;busy[allocation]<=0;done[allocation]<=0;bad[allocation]<=0;
                            serial[allocation]<=counter[eye]+1'b1;counter[eye]<=counter[eye]+1'b1;
                            clear_slots[allocation*2+:2]<=3;allow<=1;word<=0;state<=WRITE;
                        end else if(!release_fire[eye])begin
                            remember_capacity_drop<=1;state<=REPLY;
                        end
                        // A same-eye release accepted on this edge is visible
                        // as a free bank on the next decision edge.
                    end else state<=REPLY;
                end
                REQ:if(dir_read_ready[eye])state<=SCAN;
                SCAN:if(dir_valid[eye])begin
                    bad_bytes<=bad_bytes|mismatch;
                    if(index==5||index==6)difference<={1'b0,short_half}-{1'b0,long_half};
                    if(index==6)begin borrow<=difference[32];low_ok<=(difference[31:0]<=max_delta);end
                    if(index==7)time_ok<=low_ok&&difference=={32'd0,borrow};
                    if(dir_last[eye])state<=CHECK_PAIR;
                end
                CHECK_PAIR:begin
                    if(!(|bad_bytes)&&time_ok&&!bad[selected]&&!stop)begin allow<=1;word<=0;state<=WRITE;end
                    else begin bad[selected]<=1;consume_failed_peer<=1;state<=REPLY;end
                end
                WRITE:if(dir_write_ready[eye])begin if(word==15)state<=REPLY;else word<=word+1'b1;end
                REPLY:if(begin_valid[eye])begin
                    if(remember_capacity_drop)capacity_drop_seen[eye]<=1;
                    if(accepted[eye])begin
                        writing[{eye,role}]<=1;writing_bank[{eye,role}]<=bank;
                        seen[selected][role]<=1;busy[selected][role]<=1;
                        seq_seen[history_lane]<=1;published_history[history_lane]<=!published_history[history_lane];
                    end else begin
                        if(allow)bad[selected]<=1;
                        if(consume_failed_peer)seen[selected][role]<=1;
                    end
                    eye_turn<=!eye;state<=IDLE;
                end
                default:begin sticky_fault<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
