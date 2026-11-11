`timescale 1ns/1ps
// One retained DFI authority, one non-reused ticket, one current PIX descriptor.
module raw_job_ticket_context_cdc (
    input wire i_source_clk,i_identity_rst_n,i_source_rst_n,i_pixel_clk,i_pixel_rst_n,
    input wire [31:0] i_session,
    input wire i_recovery_valid,i_authority_empty,i_source_read_quiescent,i_source_write_quiescent,
    output wire o_recovery_ready,o_recovery_required,o_ticket_exhausted,o_owner_hold,
    input wire [576:0] i_owner_member,
    input wire i_owner_live,s_job_valid,
    output wire s_job_ready,
    input wire [576:0] s_cancel_member,
    input wire s_cancel_valid,output wire s_cancel_ready,
    input wire [146:0] s_write_result,
    input wire s_write_result_valid,output wire s_write_result_ready,
    output wire [146:0] m_processing_result,
    output wire m_processing_result_valid,input wire m_processing_result_ready,
    output wire [63:0] o_source_ticket,
    input wire i_pool_idle,i_admission_ready,i_context_valid,
    input wire [383:0] i_context_frame,
    input wire [63:0] i_context_ticket,
    input wire i_context_member_index,i_context_private,
    output wire o_context_ready,
    input wire i_native_job_start,i_store_start_fire,i_pipeline_error,
    input wire i_native_result_valid,i_native_result_error,
    input wire [63:0] i_native_result_ticket,
    input wire i_native_result_member_index,
    output wire [383:0] o_frame,
    output reg [63:0] o_pixel_lease,o_pixel_job_id,o_pixel_pair_id,
    output wire o_source_reset_done,o_pixel_reset_done,
    output wire [63:0] o_pixel_ticket,
    output wire o_member_index,
    output wire [31:0] o_write_tag,
    output wire o_busy,o_context_owned,
    output wire o_source_fault,
    output reg o_pixel_fault,
    output reg [7:0] o_first_fault_code,
    output reg [31:0] o_completed_count,o_cancelled_count,
    output reg [31:0] o_stale_write_count,o_stale_reply_count,o_stale_native_count,
    output wire [2:0] o_diag_state,
    output wire [3:0] o_diag_ticket_pixel
);
    localparam [2:0] SYNC=0,JOB=1,CANCEL=2,RELEASE=3,SYNC_ACK=4,TERMINAL=5,RELEASE_ACK=6;
    localparam [2:0] RECOVER=0,WAIT_SYNC=1,IDLE=2,RUN=3,WAIT_RELEASE=4,RESULT=5,FAULT=6;
    wire cohort_reset=i_identity_rst_n && i_source_rst_n && i_pixel_rst_n;
    wire source_reset,pixel_reset;
    reset_release_sync u_source_reset(.i_clk(i_source_clk),.i_async_rst_n(cohort_reset),.o_rst_n(source_reset));
    reset_release_sync u_pixel_reset(.i_clk(i_pixel_clk),.i_async_rst_n(cohort_reset),.o_rst_n(pixel_reset));
    reg [31:0] epoch,operation_sequence;
    reg [2:0] state,next_state;
    // Read-only DFI state; this tap cannot affect ticket ownership or progress.
    assign o_diag_state=state;
    reg source_fault,pixel_fault_meta,pixel_fault_sync;
    reg tx_active;
    reg [2:0] tx_kind;
    reg [2:0] tx_part;
    reg write_seen,write_failed,terminal_seen,terminal_failed,terminal_native,terminal_writer;
    reg result_error,source_cancelled;
    wire source_channel_done,pixel_channel_done;
    wire f_source_done,f_pixel_done,r_source_done,r_pixel_done;
    assign source_channel_done=f_source_done && r_source_done;
    assign pixel_channel_done=f_pixel_done && r_pixel_done;
    wire [63:0] ticket={epoch,operation_sequence};
    assign o_source_ticket=ticket;
    assign o_source_fault=source_fault || pixel_fault_sync;
    assign o_recovery_required=state==RECOVER || state==WAIT_SYNC || state==FAULT || o_source_fault;
    assign o_owner_hold=state!=IDLE;
    assign o_ticket_exhausted=operation_sequence==32'hffffffff || epoch==32'hffffffff;
    wire recovery_allowed=source_reset && (state==RECOVER) && !tx_active && source_channel_done &&
        i_authority_empty && i_source_read_quiescent && i_source_write_quiescent &&
        epoch!=32'hffffffff;
    assign o_recovery_ready=recovery_allowed;
    wire recover_take=i_recovery_valid && o_recovery_ready;
    wire owner_legal=i_owner_live && i_owner_member[511:448]!=0 && i_owner_member[447:384]!=0 &&
        i_owner_member[76:45]==i_session && i_session!=0 && i_owner_member[44:13]!=0 &&
        i_owner_member[383:367]==0 && i_owner_member[12:5]<4 &&
        i_owner_member[220:205]!=0 && i_owner_member[236:221]!=0;
    assign s_job_ready=state==IDLE && !tx_active && source_channel_done && !o_source_fault &&
        !o_ticket_exhausted && owner_legal && !recover_take;
    wire job_take=s_job_valid && s_job_ready;
    assign s_cancel_ready=state==RUN && !tx_active && source_channel_done && !o_source_fault;
    wire cancel_take=s_cancel_valid && s_cancel_ready;
    assign s_write_result_ready=source_channel_done && !o_source_fault;
    wire write_take=s_write_result_valid && s_write_result_ready;
    wire write_ticket_matches=s_write_result[31:0]==operation_sequence && s_write_result[95:64]==i_owner_member[76:45];
    wire write_identity_matches=s_write_result[63:32]==i_owner_member[108:77] &&
        s_write_result[127:96]==i_owner_member[140:109] && s_write_result[128]==i_owner_member[4];
    wire write_shape=s_write_result[146:138]==0 && (!s_write_result[129] || s_write_result[137:130]==0);
    wire operation_complete=state==RUN && terminal_seen && !tx_active &&
        i_source_read_quiescent && i_source_write_quiescent &&
        ((terminal_native && terminal_writer && write_seen) ||
         (terminal_failed && !terminal_native && !terminal_writer && !write_seen));
    assign m_processing_result_valid=state==RESULT && source_channel_done && !o_source_fault;
    assign m_processing_result={81'd0,result_error,i_owner_member[576],i_owner_member[511:448]};

    // Hardware epoch and writer sequence survive STOP and either application reset.
    // CFG sessions are arbitrary nonzero labels, never ticket generations.
    // Sequence NEVER restarts on rekey: even repeated CFG labels cannot alias
    // a delayed 32-bit writer tag. Exhaustion requires a true cold reset.
    always @(posedge i_source_clk or negedge i_identity_rst_n)begin
        if(!i_identity_rst_n)begin epoch<=0;operation_sequence<=0;end
        else if(recover_take)epoch<=epoch+1'b1;
        else if(job_take)operation_sequence<=operation_sequence+1'b1;
    end
    always @(posedge i_source_clk or negedge source_reset)begin
        if(!source_reset)begin pixel_fault_meta<=0;pixel_fault_sync<=0;end
        else begin pixel_fault_meta<=o_pixel_fault;pixel_fault_sync<=pixel_fault_meta;end
    end
    reg [127:0] forward_payload;
    always @*begin
        forward_payload=tx_kind==SYNC ? {64'd0,epoch,32'd0} : {64'd0,ticket};
        if(tx_kind==JOB)begin
            case(tx_part)
                0:forward_payload=i_owner_member[127:0];
                1:forward_payload=i_owner_member[255:128];
                2:forward_payload=i_owner_member[383:256];
                3:forward_payload=i_owner_member[511:384];
                4:forward_payload={64'd0,i_owner_member[575:512]};
                default:forward_payload={63'd0,i_owner_member[576],ticket};
            endcase
        end
    end
    wire [146:0] forward_word={tx_kind,tx_part,13'd0,forward_payload};
    wire forward_ready;
    wire forward_valid=tx_active && source_channel_done && !o_source_fault;
    wire forward_fire=forward_valid && forward_ready;
    wire forward_last=tx_kind!=JOB || tx_part==5;
    wire [146:0] pixel_word;
    wire pixel_word_valid,pixel_word_ready,pixel_word_fire;
    control_message_fifo_ip #(.BORROW_SOURCE(1)) u_forward(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_source_clk),.i_source_rst_n(source_reset),.i_source_data(forward_word),
        .i_source_valid(forward_valid),.o_source_ready(forward_ready),.o_source_reset_done(f_source_done),
        .i_sink_clk(i_pixel_clk),.i_sink_rst_n(pixel_reset),.o_sink_data(pixel_word),
        .o_sink_valid(pixel_word_valid),.i_sink_ready(pixel_word_ready),.o_sink_reset_done(f_pixel_done));

    reg pixel_active,context_owned,native_started,writer_started,native_seen,failed,terminal_sent;
    reg [383:0] frame;
    reg [63:0] pixel_ticket;
    reg member;
    reg [31:0] pixel_session;
    reg job_collect;
    reg [2:0] job_part;
    reg ack_valid;
    reg [2:0] ack_kind;
    reg [4:0] ack_flags;
    wire ack_ready,ack_fire;
    wire [79:0] ack_word={ack_kind,ack_flags,pixel_ticket,8'd0};
    wire [79:0] return_word;
    wire return_valid,return_ready,return_fire;
    control_message_fifo_ip #(.MESSAGE_WIDTH(80),.BORROW_SOURCE(1)) u_return(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_pixel_clk),.i_source_rst_n(pixel_reset),.i_source_data(ack_word),
        .i_source_valid(ack_valid && !o_pixel_fault),.o_source_ready(ack_ready),.o_source_reset_done(r_pixel_done),
        .i_sink_clk(i_source_clk),.i_sink_rst_n(source_reset),.o_sink_data(return_word),
        .o_sink_valid(return_valid),.i_sink_ready(return_ready),.o_sink_reset_done(r_source_done));
    assign ack_fire=ack_valid && ack_ready && !o_pixel_fault;
    assign return_ready=source_channel_done && !o_source_fault;
    assign return_fire=return_valid && return_ready;
    wire [2:0] reply_kind=return_word[79:77];
    wire [4:0] reply_flags=return_word[76:72];
    wire [63:0] reply_ticket=return_word[71:8];
    wire reply_shape=return_word[7:0]==0 && reply_flags[4:3]==0;
    wire sync_echo=return_fire && state==WAIT_SYNC && reply_kind==SYNC_ACK && reply_ticket=={epoch,32'd0} && reply_flags==0 && reply_shape;
    wire release_echo=return_fire && state==WAIT_RELEASE && reply_kind==RELEASE_ACK && reply_ticket==ticket && reply_flags==0 && reply_shape;
    wire terminal_echo=return_fire && state==RUN && reply_kind==TERMINAL && reply_ticket==ticket;
    always @*begin
        next_state=state;
        case(state)
            RECOVER:if(recover_take)next_state=WAIT_SYNC;
            WAIT_SYNC:if(sync_echo)next_state=IDLE;
            IDLE:begin if(recover_take)next_state=WAIT_SYNC;else if(job_take)next_state=RUN;end
            RUN:if(operation_complete)next_state=WAIT_RELEASE;
            WAIT_RELEASE:if(release_echo)next_state=RESULT;
            RESULT:if(m_processing_result_valid && m_processing_result_ready)next_state=IDLE;
            FAULT:next_state=FAULT;
            default:next_state=FAULT;
        endcase
        if(o_source_fault)next_state=FAULT;
    end
    always @(posedge i_source_clk or negedge source_reset)begin
        if(!source_reset)state<=RECOVER;else state<=next_state;
    end
    always @(posedge i_source_clk or negedge source_reset)begin
        if(!source_reset)begin
            tx_active<=0;tx_kind<=SYNC;tx_part<=0;source_fault<=0;
            write_seen<=0;write_failed<=0;terminal_seen<=0;terminal_failed<=0;terminal_native<=0;terminal_writer<=0;
            result_error<=0;source_cancelled<=0;o_stale_write_count<=0;o_stale_reply_count<=0;
            o_first_fault_code<=0;o_completed_count<=0;o_cancelled_count<=0;
        end else begin
            if(o_first_fault_code==0)begin
                if((state==RUN || state==WAIT_RELEASE || state==RESULT) && !i_owner_live)o_first_fault_code<=1;
                else if(cancel_take && s_cancel_member!=i_owner_member)o_first_fault_code<=2;
                else if(write_take && state==RUN && write_ticket_matches && (!write_identity_matches || !write_shape || write_seen))o_first_fault_code<=3;
                else if((terminal_echo && (!reply_shape || terminal_seen || (reply_flags[2] && !reply_flags[1]))) ||
                        (terminal_seen && write_seen && !terminal_writer))o_first_fault_code<=4;
                else if(pixel_fault_sync)o_first_fault_code<=5;
            end
            if(m_processing_result_valid && m_processing_result_ready && !(&o_completed_count))o_completed_count<=o_completed_count+1'b1;
            if(cancel_take && s_cancel_member==i_owner_member && !(&o_cancelled_count))o_cancelled_count<=o_cancelled_count+1'b1;
            if(forward_fire)begin if(forward_last)tx_active<=0;else tx_part<=tx_part+1'b1;end
            if(recover_take)begin tx_active<=1;tx_kind<=SYNC;tx_part<=0;end
            if(job_take)begin
                tx_active<=1;tx_kind<=JOB;tx_part<=0;
                write_seen<=0;write_failed<=0;terminal_seen<=0;terminal_failed<=0;terminal_native<=0;terminal_writer<=0;result_error<=0;source_cancelled<=0;
            end
            if((state==RUN || state==WAIT_RELEASE || state==RESULT) && !i_owner_live)source_fault<=1;
            if(cancel_take)begin
                if(s_cancel_member!=i_owner_member)source_fault<=1;
                else begin tx_active<=1;tx_kind<=CANCEL;tx_part<=0;source_cancelled<=1;end
            end
            if(write_take)begin
                if(state!=RUN || !write_ticket_matches)begin if(!(&o_stale_write_count))o_stale_write_count<=o_stale_write_count+1'b1;end
                else if(!write_identity_matches || !write_shape || write_seen)source_fault<=1;
                else begin write_seen<=1;write_failed<=!s_write_result[129];end
            end
            if(return_fire)begin
                if(sync_echo || release_echo)begin end
                else if(terminal_echo)begin
                    if(!reply_shape || terminal_seen || (reply_flags[2] && !reply_flags[1]))source_fault<=1;
                    else begin terminal_seen<=1;terminal_failed<=reply_flags[0];terminal_native<=reply_flags[1];terminal_writer<=reply_flags[2];end
                end else if(!(&o_stale_reply_count))o_stale_reply_count<=o_stale_reply_count+1'b1;
            end
            if(terminal_seen && write_seen && !terminal_writer)source_fault<=1;
            if(operation_complete)begin
                tx_active<=1;tx_kind<=RELEASE;tx_part<=0;result_error<=terminal_failed || write_failed || source_cancelled || cancel_take;
            end
        end
    end

    wire [2:0] incoming_kind=pixel_word[146:144];
    wire [2:0] incoming_part=pixel_word[143:141];
    wire control_shape=pixel_word[140:128]==0 && incoming_part==0 && pixel_word[127:64]==0;
    wire current_control=pixel_word[63:0]==pixel_ticket && pixel_active;
    assign pixel_word_ready=pixel_channel_done && !o_pixel_fault && !ack_valid;
    assign pixel_word_fire=pixel_word_valid && pixel_word_ready;
    wire cancel_now=pixel_word_fire && incoming_kind==CANCEL && control_shape && current_control;
    wire context_match=i_context_private && i_context_member_index==member &&
        i_context_ticket==pixel_ticket && i_context_frame==frame;
    assign o_diag_ticket_pixel={pixel_active,context_match,context_owned,terminal_sent};
    assign o_context_ready=pixel_active && !context_owned && !native_seen && !terminal_sent &&
        !o_pixel_fault && i_pool_idle && i_admission_ready && context_match && !cancel_now;
    wire context_take=i_context_valid && o_context_ready;
    wire native_match=pixel_active && i_native_result_ticket==pixel_ticket;
    wire send_terminal=pixel_active && native_seen && i_pool_idle && !terminal_sent && !ack_valid && !o_pixel_fault &&
        ((native_started && writer_started) || (failed && !native_started && !writer_started));
    assign o_frame=frame;
    assign o_source_reset_done=source_channel_done && state!=RECOVER && state!=WAIT_SYNC;
    assign o_pixel_reset_done=pixel_channel_done && pixel_session!=0;
    assign o_pixel_ticket=pixel_ticket;
    assign o_member_index=member;
    assign o_write_tag=context_owned ? pixel_ticket[31:0] : 32'd0;
    assign o_busy=pixel_active; // All six publication words are now valid.
    assign o_context_owned=context_owned && !terminal_sent;
    always @(posedge i_pixel_clk or negedge pixel_reset)begin
        if(!pixel_reset)begin
            pixel_active<=0;context_owned<=0;native_started<=0;writer_started<=0;native_seen<=0;failed<=0;terminal_sent<=0;
            frame<=0;o_pixel_lease<=0;o_pixel_job_id<=0;o_pixel_pair_id<=0;pixel_ticket<=0;member<=0;pixel_session<=0;job_collect<=0;job_part<=0;
            ack_valid<=0;ack_kind<=SYNC_ACK;ack_flags<=0;o_pixel_fault<=0;o_stale_native_count<=0;
        end else begin
            if(ack_fire)ack_valid<=0;
            if(pixel_word_fire)begin
                if(incoming_kind==JOB)begin
                    if(pixel_word[140:128]!=0 || pixel_active || (job_collect ? incoming_part!=job_part : incoming_part!=0))o_pixel_fault<=1;
                    else begin
                        case(incoming_part)
                            0:frame[127:0]<=pixel_word[127:0];
                            1:frame[255:128]<=pixel_word[127:0];
                            2:frame[383:256]<=pixel_word[127:0];
                            3:begin o_pixel_lease<=pixel_word[63:0];o_pixel_job_id<=pixel_word[127:64];end
                            4:begin
                                if(pixel_word[127:64]!=0)o_pixel_fault<=1;
                                else o_pixel_pair_id<=pixel_word[63:0];
                            end
                            5:begin
                                if(pixel_word[127:65]!=0 || pixel_word[63:32]!=pixel_session || pixel_word[31:0]==0 || frame[76:45]==0)o_pixel_fault<=1;
                                else begin
                                    pixel_ticket<=pixel_word[63:0];member<=pixel_word[64];pixel_active<=1;
                                    context_owned<=0;native_started<=0;writer_started<=0;native_seen<=0;failed<=0;terminal_sent<=0;
                                end
                            end
                        endcase
                        if(incoming_part==5)begin job_collect<=0;job_part<=0;end
                        else begin job_collect<=1;job_part<=incoming_part+1'b1;end
                    end
                end else if(!control_shape || job_collect)o_pixel_fault<=1;
                else if(incoming_kind==SYNC)begin
                    if(pixel_active || pixel_word[31:0]!=0 || pixel_word[63:32]==0 || pixel_word[63:32]<=pixel_session)o_pixel_fault<=1;
                    else begin pixel_session<=pixel_word[63:32];pixel_ticket<=pixel_word[63:0];ack_valid<=1;ack_kind<=SYNC_ACK;ack_flags<=0;end
                end else if(incoming_kind==CANCEL && current_control)begin
                    failed<=1;
                    if(!context_owned && !native_started && !writer_started)native_seen<=1;
                end else if(incoming_kind==RELEASE && current_control)begin
                    if(!terminal_sent || !i_pool_idle)o_pixel_fault<=1;
                    else begin pixel_active<=0;context_owned<=0;ack_valid<=1;ack_kind<=RELEASE_ACK;ack_flags<=0;end
                end else if(incoming_kind!=CANCEL && incoming_kind!=RELEASE)o_pixel_fault<=1;
            end
            if(pixel_active && !terminal_sent)begin
                if(i_context_valid && !context_owned && !context_match)o_pixel_fault<=1;
                if(context_take)context_owned<=1;
                if(i_native_job_start)begin if(!context_owned || native_started)o_pixel_fault<=1;else native_started<=1;end
                if(i_store_start_fire)begin if(!context_owned || writer_started || !(native_started || i_native_job_start))o_pixel_fault<=1;else writer_started<=1;end
                if(i_pipeline_error)failed<=1;
            end
            if(i_native_result_valid)begin
                if(!native_match)begin if(!(&o_stale_native_count))o_stale_native_count<=o_stale_native_count+1'b1;end
                else if(i_native_result_member_index!=member || native_seen || (!i_native_result_error && !(native_started || i_native_job_start)))o_pixel_fault<=1;
                else begin native_seen<=1;if(i_native_result_error)failed<=1;end
            end
            if(send_terminal)begin
                terminal_sent<=1;ack_valid<=1;ack_kind<=TERMINAL;
                ack_flags<={2'd0,writer_started,native_started,failed || i_pipeline_error || cancel_now};
            end
        end
    end
endmodule
