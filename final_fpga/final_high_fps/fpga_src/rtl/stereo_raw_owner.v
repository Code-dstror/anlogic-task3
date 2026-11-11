`timescale 1ns/1ps
// Four cold descriptors: two independently owned RAW10 slots per camera.
// Stereo here means two videos, never a qualified optical/synchronized pair.
module stereo_raw_owner #(
    parameter integer WIDTH=1920, HEIGHT=1080,
    parameter integer UHD_WIDTH=0, UHD_HEIGHT=0
)(
    input wire clk, rst_n, i_enable, i_stop,
    input wire [31:0] i_session,i_epoch,
    input wire [383:0] s_frame,input wire s_begin_valid,i_begin_camera,
    output wire s_begin_ready,o_begin_accepted,output wire [1:0] o_capture_slot,
    input wire [1:0] i_finish_valid,i_finish_ok,output wire [1:0] o_finish_ready,
    output wire o_job_valid,input wire i_job_ready,
    output reg [383:0] o_job_frame,output reg [63:0] o_job_lease,
    output wire [63:0] o_job_id,output reg [1:0] o_job_bayer,
    output reg o_job_time_valid,
    input wire i_retire_valid,input wire [63:0] i_retire_job_id,
    input wire i_release_quiet,output wire o_retire_ready,
    output reg o_retire_done,o_retire_error,
    output wire o_empty,o_job_owned,output wire o_fault,output reg [31:0] o_dropped,
    input wire i_uhd
);
    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    localparam [1:0] FREE=0,WRITING=1,READY=2,OWNED=3;
    localparam [1:0] B_IDLE=0,B_WRITE=1,B_REPLY=2,B_RESERVE=3;
    localparam [2:0] J_IDLE=0,J_REQUEST=1,J_READ=2,J_OFFER=3,J_OWNED=4;
    reg [1:0] slots[0:3],begin_state,selected_slot;
    reg [2:0] job_state;
    reg [1:0] active_valid,active_slot,job_slot,job_turn;
    reg [1:0] allocation_turn;
    reg [31:0] generation,selected_generation;
    reg accepted,fault;
    reg [3:0] word_index,clear_slots;
    wire directory_write_ready,directory_read_ready,directory_valid;
    wire [31:0] directory_data;
    wire [3:0] directory_word;
    wire directory_last,directory_fault,directory_write_busy,directory_read_busy;
    wire [3:0] directory_entries;
    wire [1:0] camera_base={i_begin_camera,1'b0};
    wire preferred_free=slots[{i_begin_camera,allocation_turn[i_begin_camera]}]==FREE;
    wire alternate_free=slots[{i_begin_camera,!allocation_turn[i_begin_camera]}]==FREE;
    wire [1:0] chosen_slot={i_begin_camera,preferred_free?allocation_turn[i_begin_camera]:!allocation_turn[i_begin_camera]};
    wire geometry_legal=UHD_ENABLED&&i_uhd ?
        (!i_begin_camera&&s_frame[220:205]==UHD_WIDTH&&s_frame[236:221]==UHD_HEIGHT) :
        (s_frame[220:205]==WIDTH&&s_frame[236:221]==HEIGHT);
    wire input_legal=i_enable&&!i_stop&&!fault&&i_session!=0&&
        s_frame[76:45]==i_session&&s_frame[140:109]==i_epoch&&
        s_frame[4]==i_begin_camera&&geometry_legal&&
        s_frame[238:237]==1&&s_frame[383:372]==0&&s_frame[370]&&
        !active_valid[i_begin_camera]&&generation!=32'hffffffff;
    wire [383:0] original_descriptor={17'd0,s_frame[366:0]};
    reg [383:0] normalized_descriptor;
    reg [31:0] write_data;
    always @* begin
        normalized_descriptor=original_descriptor;
        normalized_descriptor[44:13]=selected_generation;
        normalized_descriptor[12:5]={7'd0,selected_slot[0]};
        // Pair qualification is intentionally absent. Source/provenance is retained.
        normalized_descriptor[0]=1'b0;
        case(word_index)
            12:write_data=selected_generation;
            13:write_data=0;
            14:write_data={29'd0,s_frame[369:368],s_frame[371]};
            15:write_data=0;
            default:write_data=normalized_descriptor[word_index*32 +: 32];
        endcase
    end
    assign s_begin_ready=begin_state==B_REPLY&&!fault;
    assign o_begin_accepted=accepted;
    assign o_capture_slot={1'b0,selected_slot[0]};
    assign o_finish_ready=active_valid & {2{!fault}};
    assign o_job_valid=job_state==J_OFFER&&!fault;
    assign o_job_owned=job_state==J_OWNED&&!fault;
    assign o_job_id=64'h8000000000000000|o_job_lease;
    // READY follows the matching SOURCE terminal and all write responses.
    // BEGIN allocates only FREE, so another slot's writer cannot own this
    // immutable OWNED slot. Retire only after proving the target itself quiet.
    wire job_capture_quiet=slots[job_slot]==OWNED&&
        (!active_valid[job_slot[1]]||active_slot[job_slot[1]]!=job_slot[0]);
    assign o_retire_ready=job_state==J_OWNED&&job_capture_quiet&&i_release_quiet&&!fault;
    assign o_fault=fault||directory_fault;
    assign o_empty=slots[0]==FREE&&slots[1]==FREE&&slots[2]==FREE&&slots[3]==FREE&&
        begin_state==B_IDLE&&job_state==J_IDLE&&active_valid==0&&
        !directory_write_busy&&!directory_read_busy;
    wire [3:0] locked={(slots[3]==OWNED),(slots[2]==OWNED),(slots[1]==OWNED),(slots[0]==OWNED)};
    hdr_pair_directory u_directory(
        .i_clk(clk),.i_identity_rst_n(rst_n),.i_locked(locked),.i_clear(clear_slots),
        .s_slot(selected_slot),.s_data(write_data),.s_valid(begin_state==B_WRITE),
        .s_last(word_index==15),.s_ready(directory_write_ready),
        .i_read_slot(job_slot),.i_read_valid(job_state==J_REQUEST),.o_read_ready(directory_read_ready),
        .m_data(directory_data),.m_word(directory_word),.m_valid(directory_valid),
        .m_last(directory_last),.m_ready(job_state==J_READ),.o_valid(directory_entries),
        .o_write_busy(directory_write_busy),.o_read_busy(directory_read_busy),.o_fault(directory_fault));
    reg candidate_valid;
    reg [1:0] candidate;
    reg [1:0] head0,head1;
    reg head0_ready,head1_ready;
    always @* begin
        // With two live slots allocation_turn points at the older reservation.
        // WRITING is live too: a newer READY may never overtake that head.
        // With only one live slot its age is unambiguous.
        head0=slots[0]==FREE?2'd1:slots[1]==FREE?2'd0:{1'b0,allocation_turn[0]};
        head1=slots[2]==FREE?2'd3:slots[3]==FREE?2'd2:{1'b1,allocation_turn[1]};
        head0_ready=slots[head0]==READY&&directory_entries[head0]&&!clear_slots[head0];
        head1_ready=slots[head1]==READY&&directory_entries[head1]&&!clear_slots[head1];
        candidate_valid=head0_ready||head1_ready;
        candidate=head0;
        // Round-robin the two eligible eye heads, independently of local slot.
        if(head1_ready&&(!head0_ready||job_turn[1]))begin
            candidate=head1;
        end
    end
    integer k;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            begin_state<=B_IDLE;job_state<=J_IDLE;selected_slot<=0;generation<=0;
            selected_generation<=0;accepted<=0;word_index<=0;clear_slots<=0;fault<=0;
            active_valid<=0;active_slot<=0;allocation_turn<=0;job_slot<=0;job_turn<=0;
            o_job_frame<=0;o_job_lease<=0;o_job_bayer<=0;o_job_time_valid<=0;
            o_retire_done<=0;o_retire_error<=0;o_dropped<=0;
            for(k=0;k<4;k=k+1)slots[k]<=FREE;
        end else begin
            clear_slots<=0;o_retire_done<=0;o_retire_error<=0;
            if(directory_fault)fault<=1;
            for(k=0;k<2;k=k+1)begin
                if(i_finish_valid[k]&&o_finish_ready[k])begin
                    active_valid[k]<=0;
                    if(i_finish_ok[k]&&!i_stop)slots[{k[0],active_slot[k]}]<=READY;
                    else begin slots[{k[0],active_slot[k]}]<=FREE;clear_slots[{k[0],active_slot[k]}]<=1;end
                end
            end
            // READY has not been offered downstream; STOP may discard only these slots.
            if(i_stop)for(k=0;k<4;k=k+1)if(slots[k]==READY)begin slots[k]<=FREE;clear_slots[k]<=1;end
            case(begin_state)
                B_IDLE:if(s_begin_valid)begin
                    accepted<=input_legal&&(preferred_free||alternate_free);
                    selected_slot<=chosen_slot;word_index<=0;
                    // BEGIN borrows the descriptor through its reply. Separate
                    // its wide legality mux from generation/slot write enables;
                    // the selected FREE slot cannot be taken by a job reader.
                    begin_state<=B_RESERVE;
                end
                B_RESERVE:begin
                    // STOP may arrive after the legal request was observed but
                    // before a slot was reserved. Do not publish an allocation.
                    if(accepted&&!i_stop&&!fault)begin
                        generation<=generation+1'b1;selected_generation<=generation+1'b1;
                        // Update at reservation, before directory write/BEGIN ACK.
                        // Otherwise the in-progress newer reservation temporarily
                        // makes the old turn point at the wrong occupied slot.
                        allocation_turn[selected_slot[1]]<=!selected_slot[0];
                        slots[selected_slot]<=WRITING;begin_state<=B_WRITE;
                    end else begin
                        accepted<=0;
                        begin_state<=B_REPLY;if(!(&o_dropped))o_dropped<=o_dropped+1'b1;
                    end
                end
                B_WRITE:if(directory_write_ready)begin
                    if(word_index==15)begin_state<=B_REPLY;
                    else word_index<=word_index+1'b1;
                end
                B_REPLY:if(s_begin_valid&&s_begin_ready)begin
                    if(accepted)begin
                        active_valid[selected_slot[1]]<=1;
                        active_slot[selected_slot[1]]<=selected_slot[0];
                    end
                    begin_state<=B_IDLE;
                end
                default:fault<=1;
            endcase
            case(job_state)
                J_IDLE:if(i_enable&&!i_stop&&candidate_valid&&!fault)begin
                    job_slot<=candidate;slots[candidate]<=OWNED;job_state<=J_REQUEST;
                end
                J_REQUEST:if(directory_read_ready)begin o_job_frame<=0;o_job_lease<=0;job_state<=J_READ;end
                J_READ:if(directory_valid)begin
                    if(directory_word<12)o_job_frame[directory_word*32 +: 32]<=directory_data;
                    if(directory_word==12)o_job_lease[31:0]<=directory_data;
                    if(directory_word==13)o_job_lease[63:32]<=directory_data;
                    if(directory_word==14)begin o_job_bayer<=directory_data[2:1];o_job_time_valid<=directory_data[0];end
                    if(directory_last)begin
                        if(i_stop)begin slots[job_slot]<=FREE;clear_slots[job_slot]<=1;job_state<=J_IDLE;end
                        else job_state<=J_OFFER;
                    end
                end
                J_OFFER:if(o_job_valid&&i_job_ready)job_state<=J_OWNED;
                J_OWNED:if(i_retire_valid&&o_retire_ready)begin
                    o_retire_done<=1;o_retire_error<=i_retire_job_id!=o_job_id;
                    if(i_retire_job_id==o_job_id)begin
                        slots[job_slot]<=FREE;clear_slots[job_slot]<=1;
                        job_turn<={!job_slot[1],1'b0};job_state<=J_IDLE;
                    end
                end
                default:fault<=1;
            endcase
        end
    end
endmodule
