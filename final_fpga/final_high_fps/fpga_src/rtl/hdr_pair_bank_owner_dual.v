`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Retained DFI authority for two deterministic LONG/SHORT banks. The writer
// borrows its descriptor through s_begin_ready; no complete tuple is copied.
module hdr_pair_bank_owner_dual #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer CAMERA_COUNT=1, DOL2_ENABLE=0, CAMERA_ID=0
) (
    input wire i_clk,i_identity_rst_n,i_stop,i_transport_fault,
    input wire [63:0] i_now,
    input wire i_config_valid,
    output wire o_config_ready,
    input wire [31:0] i_session,i_epoch,i_max_delta,i_max_wait,i_max_age,
    input wire [2:0] i_ratio_log2,input wire i_hdr_enable,
    output reg o_config_error,
    input wire [383:0] s_frame,
    input wire s_begin_valid,
    output wire s_begin_ready,o_begin_accepted,
    output wire [1:0] o_capture_slot,
    output wire [31:0] o_capture_generation,
    output wire [63:0] o_capture_lease,
    input wire i_begin_member,
    input wire i_finish1_valid,i_finish1_ok,
    output wire o_finish1_ready,
    input wire i_finish_valid,i_finish_ok,
    output wire o_finish_ready,
    output wire o_pair_valid,
    input wire i_pair_ready,
    output wire o_pair_bank,
    output wire [63:0] o_pair_id,
    input wire i_release_valid,i_release_bank,
    input wire [63:0] i_release_pair_id,
    input wire i_read_quiet,i_write_quiet,i_ticket_released,
    output wire o_release_ready,
    input wire i_directory_read_valid,
    input wire [1:0] i_directory_read_slot,
    output wire o_directory_read_ready,
    output wire [31:0] m_directory_data,
    output wire [3:0] m_directory_word,
    output wire m_directory_valid,m_directory_last,
    input wire m_directory_ready,
    output wire o_empty,o_capture_busy,o_exhausted,o_fault,
    output wire [5:0] o_bank_states,
    output reg [31:0] o_reject_count,o_expire_count
);
    localparam [2:0] FREE=0,BUILDING=1,READY=4,ACQUIRED=5;
    localparam [2:0] IDLE=0,SCAN_REQUEST=1,SCAN_WORDS=2,SCAN_CHECK=3,WRITE_WORDS=4,REPLY=5;
    reg [2:0] state,bank_state[0:1];
    reg [1:0] bank_seen[0:1],bank_busy[0:1],bank_done[0:1];
    reg bank_bad[0:1],bank_first_member[0:1];
    reg [31:0] bank_group[0:1];
    reg [63:0] bank_arrival[0:1];
    // n counts every new FREE-bank allocation, including later failures.
    // Generation exhausts first at n=2^31-1; no serial can wrap legally.
    localparam integer ALLOCATION_SERIAL_WIDTH=31;
    reg [ALLOCATION_SERIAL_WIDTH-1:0] allocation_serial;
    reg [ALLOCATION_SERIAL_WIDTH-1:0] bank_serial[0:1];
    wire [63:0] bank_id[0:1];
    reg newest_bank;
    genvar identity_bank;
    generate for(identity_bank=0;identity_bank<2;identity_bank=identity_bank+1)begin:g_identity
        assign bank_id[identity_bank]={32'd0,CAMERA_ID[0],bank_serial[identity_bank]};
    end endgenerate
    reg configured,fault,selected_bank,selected_member,accepted,turn,offer_bank,offer_valid;
    reg [1:0] active_valid,sequence_seen;
    reg active_bank[0:1];
    reg [31:0] last_sequence[0:1];
    reg [63:0] last_timestamp[0:1];
    reg [31:0] session,epoch,max_delta,max_wait,max_age;
    reg [2:0] ratio_log2;
    reg hdr_enable;
    reg [3:0] scan_bad_parts;
    wire scan_bad=|scan_bad_parts;
    // Stored descriptor words 5 and 6 are the low and high timestamp halves.
    // Both directions pass through one zero-extended subtractor. Word 7 can
    // finish the decision before the last directory word reaches SCAN_CHECK.
    reg [32:0] scan_difference;
    reg low_acceptable,low_borrow,time_delta_ok;
    reg [3:0] write_word,directory_clear;
    wire [3:0] directory_valid;
    wire directory_fault,directory_write_busy,directory_read_busy;
    wire input_member=s_frame[2:1]==2;

    // Byte comparisons run in parallel; a late descriptor bit does not
    // traverse a 31/32-bit carry comparison before the admission gate.
    function unsigned_gt32;
        input [31:0] newer,older;
        begin
            unsigned_gt32=(newer[31:24]>older[31:24]) ||
                (newer[31:24]==older[31:24] && newer[23:16]>older[23:16]) ||
                (newer[31:16]==older[31:16] && newer[15:8]>older[15:8]) ||
                (newer[31:8]==older[31:8] && newer[7:0]>older[7:0]);
        end
    endfunction

    // Exact (newer-older) modulo 2^32 in the open interval (0,2^31).
    // Compare each retained member in parallel; the incoming role selects
    // completed predicates rather than a 32-bit operand before subtraction.
    function sequence_forward;
        input [31:0] newer,older;
        begin
            sequence_forward=newer[31]==older[31] ?
                unsigned_gt32({1'b0,newer[30:0]},{1'b0,older[30:0]}) :
                unsigned_gt32({1'b0,older[30:0]},{1'b0,newer[30:0]});
        end
    endfunction

    // Unsigned timestamp order uses parallel high/low comparisons rather
    // than propagating a borrow through all 64 bits. It is not serial time.
    function timestamp_ge;
        input [63:0] newer,older;
        begin timestamp_ge=unsigned_gt32(newer[63:32],older[63:32]) ||
            (newer[63:32]==older[63:32] && !unsigned_gt32(older[31:0],newer[31:0]));end
    endfunction

    // Exact modulo-64 age < a 32-bit window, including low/full-word wrap.
    // Compute the deadline from the retained origin and limit independently
    // of current time. The two current-low comparisons run in parallel;
    // current time no longer traverses subtract-age then compare-limit.
    function within_window;
        input [63:0] clock_value,origin;
        input [31:0] limit;
        reg [32:0] deadline_low;
        reg [31:0] next_upper;
        reg same_upper,next_upper_matches,after_origin,before_deadline;
        begin
            deadline_low={1'b0,origin[31:0]}+{1'b0,limit};
            next_upper=origin[63:32]+32'd1;
            same_upper=clock_value[63:32]==origin[63:32];
            next_upper_matches=clock_value[63:32]==next_upper;
            after_origin=clock_value[31:0]>=origin[31:0];
            before_deadline=clock_value[31:0]<deadline_low[31:0];
            within_window=(same_upper&&after_origin&&(deadline_low[32]||before_deadline)) ||
                (next_upper_matches&&deadline_low[32]&&before_deadline);
        end
    endfunction
    wire [1:0] input_sequence_legal;
    wire [1:0] bank_wait_live;
    genvar checked_member;
    generate for(checked_member=0;checked_member<2;checked_member=checked_member+1)begin:g_input_check
        assign input_sequence_legal[checked_member]=!sequence_seen[checked_member]||
            (sequence_forward(s_frame[108:77],last_sequence[checked_member])&&
             timestamp_ge(s_frame[204:141],last_timestamp[checked_member]));
        assign bank_wait_live[checked_member]=within_window(i_now,bank_arrival[checked_member],max_wait);
    end endgenerate
    wire member_legal=(s_frame[2:1]==1&&!i_begin_member&&
        s_frame[302:271]==32'd3200&&!active_valid[0]&&input_sequence_legal[0])||
        (s_frame[2:1]==2&&i_begin_member&&
        s_frame[302:271]==32'd200&&!active_valid[1]&&input_sequence_legal[1]);
    wire input_legal=configured&&hdr_enable&&s_frame[383:367]==0&&s_frame[0]&&
        s_frame[4]==CAMERA_ID[0]&&s_frame[3]==`PCIE_RECORD_V2_SOURCE_PHYSICAL&&member_legal&&
        s_frame[76:45]==session&&session!=0&&s_frame[140:109]==epoch&&
        s_frame[220:205]==WIDTH&&s_frame[236:221]==HEIGHT&&s_frame[238:237]==1&&
        s_frame[334:303]==32'd256&&s_frame[270:239]==32'h56a3d02f&&s_frame[366:335]!=0&&
        timestamp_ge(i_now,s_frame[204:141])&&within_window(i_now,s_frame[204:141],max_age);
    wire [1:0] matching={bank_state[1]==BUILDING&&!bank_bad[1]&&bank_group[1]==s_frame[366:335]&&!bank_seen[1][input_member]&&
        (bank_busy[1]!=0||bank_wait_live[1]),
        bank_state[0]==BUILDING&&!bank_bad[0]&&bank_group[0]==s_frame[366:335]&&!bank_seen[0][input_member]&&
        (bank_busy[0]!=0||bank_wait_live[0])};
    wire group_resident=(bank_state[0]!=FREE&&bank_group[0]==s_frame[366:335])||
        (bank_state[1]!=FREE&&bank_group[1]==s_frame[366:335]);
    // With both banks live, the other bank predates the last allocation.
    // A failed or expired allocation cannot make the surviving bank younger.
    wire oldest_bank=bank_state[0]==FREE ||
        (bank_state[1]!=FREE && !newest_bank);
    wire [1:0] free_banks={bank_state[1]==FREE,bank_state[0]==FREE};
    wire choose_match=matching[turn]?turn:!turn;
    wire choose_free=free_banks[turn]?turn:!turn;
    wire exhausted=allocation_serial==31'h7fffffff;
    wire [1:0] selected_slot={selected_bank,selected_member};
    wire [30:0] selected_serial=bank_serial[selected_bank];
    // LONG uses 2*n-1, SHORT uses 2*n. Preserve the pre-allocation readback.
    wire [31:0] selected_generation=selected_serial==0 ? {31'd0,selected_member} :
        {selected_serial,1'b0}-{31'd0,!selected_member};
    wire [63:0] selected_lease={31'd0,CAMERA_ID[0],selected_generation};
    wire same_config=configured&&session==i_session&&epoch==i_epoch;
    wire config_invalid=i_session==0||i_max_wait==0||i_max_age==0||
        (i_hdr_enable&&i_ratio_log2!=4)||
        (same_config&&(max_delta!=i_max_delta||max_wait!=i_max_wait||max_age!=i_max_age||ratio_log2!=i_ratio_log2||hdr_enable!=i_hdr_enable));
    assign o_fault=fault||directory_fault||i_transport_fault;
    assign o_empty=bank_state[0]==FREE&&bank_state[1]==FREE&&state==IDLE&&active_valid==0&&!directory_read_busy&&!offer_valid;
    assign o_capture_busy=|active_valid;
    assign o_bank_states={bank_state[1],bank_state[0]};
    assign o_exhausted=exhausted;
    assign o_config_ready=(o_empty||(state==IDLE&&active_valid==0&&!directory_read_busy&&(config_invalid||same_config)))&&!o_fault;
    assign s_begin_ready=state==REPLY;
    assign o_begin_accepted=accepted&&!i_stop&&!o_fault&&!bank_bad[selected_bank];
    assign o_capture_slot=selected_slot;
    assign o_capture_generation=selected_generation;
    assign o_capture_lease=selected_lease;
    assign o_finish_ready=active_valid[0]&&!o_fault;
    assign o_finish1_ready=active_valid[1]&&!o_fault;
    assign o_pair_valid=offer_valid&&!i_stop&&!o_fault&&!i_config_valid;
    assign o_pair_bank=offer_bank;
    assign o_pair_id=bank_id[offer_bank];
    assign o_release_ready=!o_fault&&i_read_quiet&&i_write_quiet&&i_ticket_released&&!directory_read_busy;
    wire release_fire=i_release_valid&&o_release_ready;
    wire external_allowed=(state==IDLE||state==REPLY)&&!i_release_valid&&bank_state[i_directory_read_slot[1]]==ACQUIRED;
    wire scanning=state==SCAN_REQUEST||state==SCAN_WORDS;
    wire directory_request_ready,directory_write_ready;
    wire [31:0] directory_data;
    wire [3:0] directory_word;
    wire directory_output_valid,directory_output_last;
    wire [1:0] directory_read_slot=scanning?{selected_bank,bank_first_member[selected_bank]}:i_directory_read_slot;
    wire directory_read_request=state==SCAN_REQUEST||(external_allowed&&i_directory_read_valid);
    assign o_directory_read_ready=external_allowed&&directory_request_ready;
    assign m_directory_valid=directory_output_valid&&!scanning;
    assign m_directory_data=directory_data;
    assign m_directory_word=directory_word;
    assign m_directory_last=directory_output_last;
    reg [31:0] write_data;
    always @* begin
        write_data=0;
        case(write_word)
            0:write_data={25'd0,selected_slot,s_frame[4:0]};
            1:write_data=selected_generation;
            2:write_data=s_frame[76:45];
            3:write_data=s_frame[108:77];
            4:write_data=s_frame[140:109];
            5:write_data=s_frame[172:141];
            6:write_data=s_frame[204:173];
            7:write_data=s_frame[236:205];
            8:write_data=s_frame[302:271];
            9:write_data=s_frame[334:303];
            10:write_data=s_frame[270:239];
            11:write_data=s_frame[366:335];
            12:write_data=selected_lease[31:0];
            13:write_data=selected_lease[63:32];
            14:write_data={30'd0,s_frame[238:237]};
            default:write_data=0;
        endcase
    end
    hdr_pair_directory u_directory(
        .i_clk(i_clk),.i_identity_rst_n(i_identity_rst_n),
        .i_locked({{2{bank_state[1]==ACQUIRED}},{2{bank_state[0]==ACQUIRED}}}),.i_clear(directory_clear),
        .s_slot(selected_slot),.s_data(write_data),.s_valid(state==WRITE_WORDS),.s_last(write_word==15),.s_ready(directory_write_ready),
        .i_read_slot(directory_read_slot),.i_read_valid(directory_read_request),.o_read_ready(directory_request_ready),
        .m_data(directory_data),.m_word(directory_word),.m_valid(directory_output_valid),.m_last(directory_output_last),
        .m_ready(scanning||m_directory_ready),.o_valid(directory_valid),.o_write_busy(directory_write_busy),.o_read_busy(directory_read_busy),.o_fault(directory_fault));
    // The requested member is SHORT for role 1; the other case borrows the
    // earlier stored SHORT. Keep short - long unsigned across the full 64 bits.
    wire [31:0] request_time_half=directory_word[0]?s_frame[172:141]:s_frame[204:173];
    wire [31:0] short_half=selected_member?request_time_half:directory_data;
    wire [31:0] long_half=selected_member?directory_data:request_time_half;
    wire [32:0] half_difference={1'b0,short_half}-{1'b0,long_half};
    // The four byte lanes accumulate independently on the original word
    // edge. SCAN_CHECK sees their OR on the original next cycle; no directory
    // output has to pass a 32-bit compare and a serial case-priority feedback.
    reg [31:0] scan_expected,scan_compare_mask;
    wire [3:0] scan_word_bad;
    always @(*) begin
        scan_expected=0;scan_compare_mask=32'hffffffff;
        case(directory_word)
            0:begin
                scan_expected={27'd0,s_frame[4:3],(selected_member?2'd1:2'd2),1'b1};
                scan_compare_mask=32'h0000001f;
            end
            2:scan_expected=s_frame[76:45];
            4:scan_expected=s_frame[140:109];
            7:scan_expected=s_frame[236:205];
            8:scan_expected=selected_member?32'd3200:32'd200;
            9:scan_expected=32'd256;
            10:scan_expected=32'h56a3d02f;
            11:scan_expected=s_frame[366:335];
            14:scan_expected={30'd0,s_frame[238:237]};
            default:scan_compare_mask=0;
        endcase
    end
    genvar scan_byte;
    generate for(scan_byte=0;scan_byte<4;scan_byte=scan_byte+1)begin:g_scan_compare
        assign scan_word_bad[scan_byte]=|((directory_data[scan_byte*8+:8] ^
            scan_expected[scan_byte*8+:8]) & scan_compare_mask[scan_byte*8+:8]);
    end endgenerate

    integer b,r;
    always @(posedge i_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin
            state<=IDLE;configured<=0;fault<=0;session<=0;epoch<=0;max_delta<=0;max_wait<=0;max_age<=0;ratio_log2<=0;hdr_enable<=0;
            active_valid<=0;sequence_seen<=0;allocation_serial<=0;newest_bank<=0;
            selected_bank<=0;selected_member<=0;accepted<=0;turn<=0;offer_bank<=0;offer_valid<=0;
            scan_bad_parts<=0;write_word<=0;directory_clear<=0;
            o_config_error<=0;o_reject_count<=0;o_expire_count<=0;
            for(b=0;b<2;b=b+1)begin
                bank_state[b]<=FREE;bank_seen[b]<=0;bank_busy[b]<=0;bank_done[b]<=0;bank_bad[b]<=0;bank_first_member[b]<=0;
                bank_group[b]<=0;bank_serial[b]<=0;bank_arrival[b]<=0;
                active_bank[b]<=0;last_sequence[b]<=0;last_timestamp[b]<=0;
            end
        end else begin
            directory_clear<=0;o_config_error<=0;
            if(i_transport_fault)fault<=1;
            if(i_config_valid&&o_config_ready)begin
                if(config_invalid)o_config_error<=1;
                else begin
                    configured<=1;session<=i_session;epoch<=i_epoch;max_delta<=i_max_delta;max_wait<=i_max_wait;max_age<=i_max_age;ratio_log2<=i_ratio_log2;hdr_enable<=i_hdr_enable;
                    if(!configured||session!=i_session||epoch!=i_epoch)sequence_seen<=0;
                end
            end
            // Member completions are independent: no fabricated LONG completion
            // is used to admit SHORT. Only each writer's real terminal/B proof
            // removes its busy bit. Failed banks wait for every active writer.
            if(i_finish_valid&&o_finish_ready)begin
                active_valid[0]<=0;bank_busy[active_bank[0]][0]<=0;bank_done[active_bank[0]][0]<=1;
                if(!i_finish_ok||i_stop)bank_bad[active_bank[0]]<=1;
            end
            if(i_finish1_valid&&o_finish1_ready)begin
                active_valid[1]<=0;bank_busy[active_bank[1]][1]<=0;bank_done[active_bank[1]][1]<=1;
                if(!i_finish1_ok||i_stop)bank_bad[active_bank[1]]<=1;
            end
            if(!offer_valid&&!i_stop&&!o_fault&&!i_config_valid&&bank_state[0]!=ACQUIRED&&bank_state[1]!=ACQUIRED)begin
                if(bank_state[oldest_bank]==READY)begin offer_bank<=oldest_bank;offer_valid<=1;end
            end
            if(o_pair_valid&&i_pair_ready)begin bank_state[offer_bank]<=ACQUIRED;offer_valid<=0;turn<=!offer_bank;end
            if(release_fire)begin
                if(bank_state[i_release_bank]!=ACQUIRED||i_release_pair_id!=bank_id[i_release_bank])fault<=1;
                else begin bank_state[i_release_bank]<=FREE;directory_clear<=i_release_bank?4'b1100:4'b0011;end
            end
            for(b=0;b<2;b=b+1)begin
                // FREE owns no capture payload. Allocation consumes this same
                // edge's candidate; successful BEGIN and the timeout origin
                // remain unchanged. Serial/generation identities are not
                // speculative and retain their original allocation condition.
                if(state==IDLE && bank_state[b]==FREE)begin
                    bank_arrival[b]<=i_now;bank_group[b]<=s_frame[366:335];
                    bank_first_member[b]<=input_member;
                end
                if(bank_state[b]==BUILDING&&bank_busy[b]==0&&state==IDLE&&!directory_read_busy)begin
                    if(bank_bad[b]||i_stop||(i_config_valid&&!config_invalid&&!same_config))begin
                        bank_state[b]<=FREE;directory_clear[b*2+:2]<=2'b11;
                    end else if(bank_seen[b]==3&&bank_done[b]==3)bank_state[b]<=READY;
                    else if(!bank_wait_live[b])begin
                        bank_state[b]<=FREE;directory_clear[b*2+:2]<=2'b11;o_expire_count<=o_expire_count+1'b1;
                    end
                end
                if(bank_state[b]==READY&&i_stop&&state==IDLE&&!directory_read_busy)begin
                    bank_state[b]<=FREE;directory_clear[b*2+:2]<=2'b11;offer_valid<=0;
                end
            end
            case(state)
                IDLE:if(!directory_read_busy&&!i_directory_read_valid&&!o_fault&&!release_fire&&s_begin_valid)begin
                    accepted<=0;selected_member<=input_member;
                    // STOP must answer an already held ADMIT negatively so its
                    // writer can drain, rather than deadlocking before grant.
                    if(i_stop||i_config_valid||!input_legal)state<=REPLY;
                    else if(|matching)begin selected_bank<=choose_match;scan_bad_parts<=0;state<=SCAN_REQUEST;end
                    else if(!group_resident&&|free_banks&&!exhausted)begin
                        selected_bank<=choose_free;newest_bank<=choose_free;bank_state[choose_free]<=BUILDING;
                        bank_seen[choose_free]<=0;bank_busy[choose_free]<=0;bank_done[choose_free]<=0;bank_bad[choose_free]<=0;

                        bank_serial[choose_free]<=allocation_serial+1'b1;
                        allocation_serial<=allocation_serial+1'b1;
                        directory_clear[choose_free*2+:2]<=2'b11;
                        accepted<=1;write_word<=0;state<=WRITE_WORDS;
                    end else state<=REPLY;
                end
                SCAN_REQUEST:if(directory_request_ready)state<=SCAN_WORDS;
                SCAN_WORDS:if(directory_output_valid)begin
                    scan_bad_parts<=scan_bad_parts | scan_word_bad;
                    if(directory_word==5 || directory_word==6)
                        scan_difference<=half_difference;
                    if(directory_word==6)begin
                        low_borrow<=scan_difference[32];
                        low_acceptable<=scan_difference[31:0]<=max_delta;
                    end
                    if(directory_word==7)
                        time_delta_ok<=low_acceptable && scan_difference=={32'b0,low_borrow};
                    if(directory_output_last)state<=SCAN_CHECK;
                end
                SCAN_CHECK:begin
                    if(!scan_bad&&time_delta_ok&&!bank_bad[selected_bank]&&!i_stop)begin
                        accepted<=1;write_word<=0;state<=WRITE_WORDS;
                    end else begin bank_bad[selected_bank]<=1;state<=REPLY;end
                end
                WRITE_WORDS:if(directory_write_ready)begin if(write_word==15)state<=REPLY;else write_word<=write_word+1'b1;end
                REPLY:if(s_begin_valid)begin
                    if(o_begin_accepted)begin
                        active_valid[selected_member]<=1;active_bank[selected_member]<=selected_bank;
                        bank_seen[selected_bank][selected_member]<=1;bank_busy[selected_bank][selected_member]<=1;
                        sequence_seen[selected_member]<=1;last_sequence[selected_member]<=s_frame[108:77];last_timestamp[selected_member]<=s_frame[204:141];
                    end else begin
                        o_reject_count<=o_reject_count+1'b1;
                        if(accepted)bank_bad[selected_bank]<=1;
                    end
                    state<=IDLE;
                end
                default:begin fault<=1;state<=IDLE;end
            endcase
        end
    end
    generate if(CAMERA_COUNT!=1||CAMERA_ID<0||CAMERA_ID>1||WIDTH<4||HEIGHT<1||WIDTH%4!=0)begin:g_bad_profile
        DOL2_CAPTURE_REQUIRES_SINGLE_CAMERA_RAW10_GEOMETRY invalid_profile();
    end endgenerate
endmodule
