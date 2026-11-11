`timescale 1ns/1ps

// Retained DFI authority for two deterministic LONG/SHORT banks. The writer
// borrows its descriptor through s_begin_ready; no complete tuple is copied.
module hdr_pair_bank_owner_serial #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer CAMERA_COUNT=1
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
    localparam [2:0] FREE=0,LONG_WRITE=1,WAIT_SHORT=2,SHORT_WRITE=3,
        READY=4,ACQUIRED=5;
    localparam [2:0] IDLE=0,SCAN_REQUEST=1,SCAN_WORDS=2,
        SCAN_CHECK=3,WRITE_WORDS=4,REPLY=5;
    reg [2:0] state;
    reg [2:0] bank_state[0:1];
    reg [63:0] bank_id[0:1],bank_lease[0:1],bank_arrival[0:1];
    reg [31:0] bank_generation[0:1];
    reg [63:0] lease_counter,pair_counter;
    reg [31:0] generation_counter;
    reg configured,fault,capture_busy,capture_bank,capture_member;
    reg [31:0] session,epoch,max_delta,max_wait,max_age;
    reg [2:0] ratio_log2;reg hdr_enable;
    reg sequence_seen;
    reg [31:0] last_sequence;
    reg [63:0] last_timestamp;
    reg selected_bank,selected_member,accepted,turn,offer_bank;
    reg offer_valid;
    reg [3:0] write_word;
    reg scan_bad,scan_tried_other;
    reg [63:0] long_timestamp;
    reg [31:0] long_exposure;
    reg [3:0] directory_clear;
    wire [3:0] directory_valid;
    wire directory_fault,directory_write_busy,directory_read_busy;
    wire [3:0] directory_locked={{2{bank_state[1]==ACQUIRED}},
        {2{bank_state[0]==ACQUIRED}}};
    wire [1:0] selected_slot={selected_bank,selected_member};
    wire [31:0] selected_generation=bank_generation[selected_bank]+selected_member;
    wire [63:0] selected_lease=bank_lease[selected_bank]+selected_member;
    wire [63:0] input_age=i_now-s_frame[204:141];
    wire [31:0] sequence_delta=s_frame[108:77]-last_sequence;
    wire [63:0] pair_delta=s_frame[204:141]-long_timestamp;
    wire [63:0] scaled_short_exposure={32'd0,s_frame[302:271]}<<ratio_log2;
    wire input_legal=configured && hdr_enable && s_frame[383:367]==0 && s_frame[0] &&
        s_frame[4]==0 && (s_frame[2:1]==1 || s_frame[2:1]==2) &&
        s_frame[76:45]==session && session!=0 && s_frame[140:109]==epoch &&
        s_frame[220:205]==WIDTH && s_frame[236:221]==HEIGHT &&
        s_frame[238:237]==1 && s_frame[302:271]!=0 && s_frame[334:303]!=0 &&
        s_frame[366:335]!=0 && s_frame[204:141]<=i_now && input_age<max_age &&
        (!sequence_seen || (sequence_delta!=0 && !sequence_delta[31] &&
            s_frame[204:141]>=last_timestamp));
    wire [1:0] expired={bank_state[1]==WAIT_SHORT &&
        i_now-bank_arrival[1]>=max_wait,bank_state[0]==WAIT_SHORT &&
        i_now-bank_arrival[0]>=max_wait};
    wire [1:0] waiting={bank_state[1]==WAIT_SHORT && !expired[1],
        bank_state[0]==WAIT_SHORT && !expired[0]};
    wire [1:0] free_banks={bank_state[1]==FREE,bank_state[0]==FREE};
    wire free_select=free_banks[turn] ? turn : !turn;
    wire wait_select=waiting[turn] ? turn : !turn;
    wire next_exhausted=lease_counter>64'hfffffffffffffffd ||
        generation_counter>32'hfffffffd || pair_counter==64'hffffffffffffffff;
    assign o_exhausted=next_exhausted;
    assign o_fault=fault || directory_fault || i_transport_fault;
    assign o_empty=bank_state[0]==FREE && bank_state[1]==FREE &&
        state==IDLE && !capture_busy && !directory_read_busy && !offer_valid;
    wire same_config_identity=configured && session==i_session && epoch==i_epoch;
    wire config_invalid=i_session==0 || i_max_wait==0 || i_max_age==0 ||
        (i_hdr_enable && (i_ratio_log2==0 || i_ratio_log2>4)) ||
        (same_config_identity && (max_delta!=i_max_delta || max_wait!=i_max_wait ||
            max_age!=i_max_age || ratio_log2!=i_ratio_log2 || hdr_enable!=i_hdr_enable));
    assign o_config_ready=(o_empty || (state==IDLE && !capture_busy &&
        !directory_read_busy && (config_invalid || same_config_identity))) && !o_fault;
    assign o_capture_busy=capture_busy;
    assign o_bank_states={bank_state[1],bank_state[0]};
    assign s_begin_ready=state==REPLY;
    assign o_begin_accepted=accepted && !i_stop && !o_fault;
    // REPLY latches selected_bank/member into the active capture. IDLE
    // cannot select another transaction while capture_busy. Therefore this
    // full-width selected arithmetic also serves the live writer exactly.
    assign o_capture_slot=selected_slot;
    assign o_capture_generation=selected_generation;
    assign o_capture_lease=selected_lease;
    assign o_finish_ready=capture_busy && !o_fault;
    assign o_pair_valid=offer_valid && !i_stop && !o_fault && !i_config_valid;
    assign o_pair_bank=offer_bank;
    assign o_pair_id=bank_id[offer_bank];
    assign o_release_ready=!o_fault && i_read_quiet && i_write_quiet && i_ticket_released &&
        !directory_read_busy;
    wire release_fire=i_release_valid && o_release_ready;

    // Native directory words are aligned; comparisons need only the current
    // 32-bit RAM word and the borrowed incoming frame, not a resident frame FF.
    reg [31:0] write_data;
    always @* begin
        write_data=0;
        case(write_word)
            0:write_data={19'd0,6'd0,selected_slot,s_frame[4:0]};
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
    wire directory_write_ready;
    wire scanning=state==SCAN_REQUEST || state==SCAN_WORDS;
    wire external_allowed=(state==IDLE || state==REPLY) && !i_release_valid &&
        bank_state[i_directory_read_slot[1]]==ACQUIRED;
    wire directory_read_request=state==SCAN_REQUEST ||
        (external_allowed && i_directory_read_valid);
    wire [1:0] directory_read_slot=scanning ? {selected_bank,1'b0} : i_directory_read_slot;
    wire directory_request_ready;
    wire [31:0] directory_data;
    wire [3:0] directory_word;
    wire directory_output_valid,directory_output_last;
    assign o_directory_read_ready=external_allowed && directory_request_ready;
    assign m_directory_valid=directory_output_valid && !scanning;
    assign m_directory_data=directory_data;
    assign m_directory_word=directory_word;
    assign m_directory_last=directory_output_last;
    hdr_pair_directory u_directory(
        .i_clk(i_clk),.i_identity_rst_n(i_identity_rst_n),
        .i_locked(directory_locked),.i_clear(directory_clear),
        .s_slot(selected_slot),.s_data(write_data),.s_valid(state==WRITE_WORDS),
        .s_last(write_word==15),.s_ready(directory_write_ready),
        .i_read_slot(directory_read_slot),.i_read_valid(directory_read_request),
        .o_read_ready(directory_request_ready),.m_data(directory_data),
        .m_word(directory_word),.m_valid(directory_output_valid),
        .m_last(directory_output_last),.m_ready(scanning || m_directory_ready),
        .o_valid(directory_valid),.o_write_busy(directory_write_busy),
        .o_read_busy(directory_read_busy),.o_fault(directory_fault));
    integer bank;
    always @(posedge i_clk or negedge i_identity_rst_n) begin
        if(!i_identity_rst_n)begin
            state<=IDLE;configured<=0;fault<=0;capture_busy<=0;
            capture_bank<=0;capture_member<=0;session<=0;epoch<=0;
            max_delta<=0;max_wait<=0;max_age<=0;ratio_log2<=0;hdr_enable<=0;
            sequence_seen<=0;last_sequence<=0;last_timestamp<=0;
            lease_counter<=0;generation_counter<=0;pair_counter<=0;
            selected_bank<=0;selected_member<=0;accepted<=0;turn<=0;
            offer_bank<=0;offer_valid<=0;write_word<=0;
            scan_bad<=0;scan_tried_other<=0;long_timestamp<=0;long_exposure<=0;
            directory_clear<=0;o_config_error<=0;o_reject_count<=0;o_expire_count<=0;
            for(bank=0;bank<2;bank=bank+1)begin
                bank_state[bank]<=FREE;bank_id[bank]<=0;bank_lease[bank]<=0;
                bank_arrival[bank]<=0;bank_generation[bank]<=0;
            end
        end else begin
            directory_clear<=0;o_config_error<=0;
            if(i_transport_fault)fault<=1;
            if(i_config_valid && o_config_ready)begin
                if(config_invalid)
                    o_config_error<=1;
                else begin configured<=1;session<=i_session;epoch<=i_epoch;
                    max_delta<=i_max_delta;max_wait<=i_max_wait;max_age<=i_max_age;
                    ratio_log2<=i_ratio_log2;hdr_enable<=i_hdr_enable;
                    if(!configured || session!=i_session)sequence_seen<=0;
                end
            end
            // A valid new policy drains unacquired candidates, then applies
            // only when the unique authority is empty. Invalid requests do
            // not destroy residents. A held acquired pair is never flushed.
            if(i_config_valid && !config_invalid && !same_config_identity && !o_fault && !i_stop &&
                state==IDLE && !capture_busy && !directory_read_busy &&
                bank_state[0]!=ACQUIRED && bank_state[1]!=ACQUIRED)begin
                bank_state[0]<=FREE;bank_state[1]<=FREE;
                directory_clear<=4'b1111;offer_valid<=0;
            end
            // A presented READY pair remains stable until its actual acquire.
            if(!offer_valid && !i_stop && !o_fault && !i_config_valid &&
                bank_state[0]!=ACQUIRED && bank_state[1]!=ACQUIRED)begin
                if(bank_state[turn]==READY)begin offer_bank<=turn;offer_valid<=1;end
                else if(bank_state[!turn]==READY)begin offer_bank<=!turn;offer_valid<=1;end
            end
            if(o_pair_valid && i_pair_ready)begin
                bank_state[offer_bank]<=ACQUIRED;offer_valid<=0;turn<=!offer_bank;
            end
            if(release_fire)begin
                if(bank_state[i_release_bank]!=ACQUIRED ||
                    i_release_pair_id!=bank_id[i_release_bank] || directory_read_busy)
                    fault<=1;
                else begin bank_state[i_release_bank]<=FREE;
                    directory_clear<=i_release_bank ? 4'b1100 : 4'b0011;end
            end
            // STOP discards only unacquired banks with no payload write active.
            // An acquired bank still requires the authenticated release above.
            if(i_stop && !capture_busy && state==IDLE && !directory_read_busy)begin
                offer_valid<=0;
                for(bank=0;bank<2;bank=bank+1)begin
                    if(bank_state[bank]!=ACQUIRED)begin
                        bank_state[bank]<=FREE;
                        directory_clear[bank*2+:2]<=2'b11;
                    end
                end
            end
            if(i_finish_valid && o_finish_ready)begin
                capture_busy<=0;
                if(!i_finish_ok || i_stop)begin
                    bank_state[capture_bank]<=FREE;
                    directory_clear<=capture_bank ? 4'b1100 : 4'b0011;
                end else if(capture_member)bank_state[capture_bank]<=READY;
                else begin bank_state[capture_bank]<=WAIT_SHORT;bank_arrival[capture_bank]<=i_now;end
            end
            case(state)
                IDLE: begin
                    if(!capture_busy && !directory_read_busy && !i_directory_read_valid &&
                        !i_stop && !o_fault && !i_config_valid && !release_fire)begin
                        // Expiry has priority over SOP on the same clock.
                        if(|expired)begin
                            for(bank=0;bank<2;bank=bank+1)if(expired[bank])begin
                                bank_state[bank]<=FREE;directory_clear[bank*2+:2]<=2'b11;
                            end
                            o_expire_count<=o_expire_count+expired[0]+expired[1];
                        end else if(s_begin_valid)begin
                            accepted<=0;selected_member<=s_frame[2:1]==2;
                            if(!input_legal)state<=REPLY;
                            else if(s_frame[2:1]==1)begin
                                if(free_banks!=0 && !next_exhausted)begin
                                    selected_bank<=free_select;
                                    bank_id[free_select]<=pair_counter+1'b1;
                                    bank_lease[free_select]<=lease_counter+1'b1;
                                    bank_generation[free_select]<=generation_counter+1'b1;
                                    pair_counter<=pair_counter+1'b1;lease_counter<=lease_counter+2'd2;
                                    generation_counter<=generation_counter+2'd2;
                                    bank_state[free_select]<=LONG_WRITE;
                                    write_word<=0;accepted<=1;state<=WRITE_WORDS;
                                end else state<=REPLY;
                            end else if(waiting!=0)begin
                                selected_bank<=wait_select;scan_tried_other<=0;
                                scan_bad<=0;state<=SCAN_REQUEST;
                            end else state<=REPLY;
                        end
                    end
                end
                SCAN_REQUEST:if(directory_request_ready)state<=SCAN_WORDS;
                SCAN_WORDS:if(directory_output_valid)begin
                    case(directory_word)
                        0:if(directory_data[4:3]!=s_frame[4:3] ||
                            directory_data[2:0]!=3'b011)scan_bad<=1;
                        2:if(directory_data!=s_frame[76:45])scan_bad<=1;
                        4:if(directory_data!=s_frame[140:109])scan_bad<=1;
                        5:long_timestamp[31:0]<=directory_data;
                        6:long_timestamp[63:32]<=directory_data;
                        7:if(directory_data!=s_frame[236:205])scan_bad<=1;
                        8:long_exposure<=directory_data;
                        9:if(directory_data!=s_frame[334:303])scan_bad<=1;
                        10:if(directory_data!=s_frame[270:239])scan_bad<=1;
                        11:if(directory_data!=s_frame[366:335])scan_bad<=1;
                        14:if(directory_data!={30'd0,s_frame[238:237]})scan_bad<=1;
                        default:begin end
                    endcase
                    if(directory_output_last)state<=SCAN_CHECK;
                end
                SCAN_CHECK:begin
                    if(!scan_bad && {32'd0,long_exposure}==scaled_short_exposure &&
                        s_frame[204:141]>=long_timestamp && pair_delta<=max_delta &&
                        !expired[selected_bank] && !i_stop)begin
                        bank_state[selected_bank]<=SHORT_WRITE;accepted<=1;
                        write_word<=0;state<=WRITE_WORDS;
                    end else if(!scan_tried_other && waiting[!selected_bank])begin
                        selected_bank<=!selected_bank;scan_tried_other<=1;
                        scan_bad<=0;state<=SCAN_REQUEST;
                    end else state<=REPLY;
                end
                WRITE_WORDS:if(directory_write_ready)begin
                    if(write_word==15)state<=REPLY;
                    else write_word<=write_word+1'b1;
                end
                REPLY:if(s_begin_valid)begin
                    if(o_begin_accepted)begin
                        capture_busy<=1;capture_bank<=selected_bank;
                        capture_member<=selected_member;
                        sequence_seen<=1;last_sequence<=s_frame[108:77];
                        last_timestamp<=s_frame[204:141];
                    end else begin
                        o_reject_count<=o_reject_count+1'b1;
                        if(accepted)begin bank_state[selected_bank]<=FREE;
                            directory_clear<=selected_bank ? 4'b1100 : 4'b0011;end
                    end
                    state<=IDLE;
                end
                default:begin fault<=1;state<=IDLE;end
            endcase
        end
    end
    generate if(CAMERA_COUNT!=1 || WIDTH<4 || HEIGHT<1 || WIDTH%4!=0)begin:g_bad_profile
        HDR_PAIR_BANK_REQUIRES_QUALIFIED_SINGLE_CAMERA_GEOMETRY invalid_profile();
    end endgenerate
endmodule
