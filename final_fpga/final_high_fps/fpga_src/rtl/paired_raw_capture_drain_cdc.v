`timescale 1ns/1ps
`default_nettype none
// Same source clock only. Each member captures/leases its own exact target;
// only packet transport, identity and FIFO plumbing are shared.
module paired_raw_capture_drain_cdc(
    input wire i_source_clk,i_source_rst_n,i_dfi_clk,i_dfi_rst_n,
    input wire [1:0] i_enqueue_fire,i_source_idle,i_consume_fire,
    input wire i_write_quiescent,
    input wire [1:0] s_drain_valid,output wire [1:0] s_drain_ready,
    input wire [31:0] s_drain_session,s_drain_epoch,
    output reg [1:0] m_drain_valid,input wire m_drain_ready,
    output wire [31:0] m_drain_session,m_drain_epoch,
    output wire [63:0] m_drain_target0,m_drain_target1,m_drain_id,
    output wire [1:0] o_apply_quiescent,
    output reg [63:0] o_enqueued_count0,o_enqueued_count1,o_consumed_count0,o_consumed_count1,
    output reg [1:0] o_source_fault,o_dfi_fault,
    output reg [31:0] o_stale_ack_count,
    output wire o_source_reset_done,o_dfi_reset_done
);
    wire cohort_rst_n=i_source_rst_n&&i_dfi_rst_n;
    wire source_rst_n,dfi_rst_n;
    reset_release_sync u_source_reset(.i_clk(i_source_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(source_rst_n));
    reset_release_sync u_dfi_reset(.i_clk(i_dfi_clk),.i_async_rst_n(cohort_rst_n),.o_rst_n(dfi_rst_n));
    // [263] ACK-success; request[263:256]/ACK[262:256] zero.
    // [255:192] nonreused id, [191:160]session, [159:128]future epoch,
    // [127:64]member1 target, [63:0]member0 target. Never sum the targets.
    reg [263:0] source_packet;
    // Keep the request mailbox published through the final ACK source
    // handshake. Its complete payload is the DFI owner's immutable packet.
    wire [263:0] dfi_packet;
    reg [1:0] captured,source_quiet;
    reg source_busy,request_started,request_pending,dfi_owned,ack_pending;
    reg [63:0] next_id,dfi_last_id;
    reg [31:0] source_session,dfi_session;
    reg [1:0] dfi_fault_meta,dfi_fault_sync;
    wire request_ready,request_valid,request_sink_ready,ack_ready,ack_valid;
    wire [263:0] request_data;
    assign dfi_packet=request_data;
    wire request_source_done,request_sink_done,ack_source_done,ack_sink_done;
    control_message_fifo_ip #(.MESSAGE_WIDTH(264),.BORROW_SOURCE(1)) u_request(
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_source_clk),.i_source_rst_n(source_rst_n),.i_source_data(source_packet),
        .i_source_valid(request_pending),.o_source_ready(request_ready),.o_source_reset_done(request_source_done),
        .i_sink_clk(i_dfi_clk),.i_sink_rst_n(dfi_rst_n),.o_sink_data(request_data),.o_sink_valid(request_valid),
        .i_sink_ready(request_sink_ready),.o_sink_reset_done(request_sink_done));
    wire ack_flit_read;
    wire [39:0] ack_flit_data;
    wire [4:0] ack_flit_index;
    reg [6:0] ack_word_match;
    wire ack_matches=&ack_word_match;
    // Compare each actual received flit to the original source-owned packet.
    // The DFI echo is never copied into the expected value. All seven words
    // must be replaced before the mailbox may assert its complete-message VALID.
    // A complete source owner is immutable until that genuine ACK is accepted.
    always @(posedge i_source_clk or negedge source_rst_n)begin
        if(!source_rst_n)ack_word_match<=0;
        else if(ack_flit_read)begin
            case(ack_flit_index)
                0:ack_word_match[0]<=source_busy&&captured==2'b11&&ack_flit_data==source_packet[39:0];
                1:ack_word_match[1]<=ack_flit_data==source_packet[79:40];
                2:ack_word_match[2]<=ack_flit_data==source_packet[119:80];
                3:ack_word_match[3]<=ack_flit_data==source_packet[159:120];
                4:ack_word_match[4]<=ack_flit_data==source_packet[199:160];
                5:ack_word_match[5]<=ack_flit_data==source_packet[239:200];
                6:ack_word_match[6]<=ack_flit_data[23:0]=={1'b1,7'd0,source_packet[255:240]};
                default:ack_word_match<=0;
            endcase
        end
    end
    control_message_fifo_ip #(.MESSAGE_WIDTH(264),.BORROW_SOURCE(1)) u_ack(
        .o_sink_flit_read(ack_flit_read),.o_sink_flit_data(ack_flit_data),.o_sink_flit_index(ack_flit_index),
        .i_source_clk(i_dfi_clk),.i_source_rst_n(dfi_rst_n),.i_source_data({1'b1,7'd0,dfi_packet[255:0]}),
        .i_source_valid(ack_pending),.o_source_ready(ack_ready),.o_source_reset_done(ack_source_done),
        .i_sink_clk(i_source_clk),.i_sink_rst_n(source_rst_n),.o_sink_data(),.o_sink_valid(ack_valid),
        .i_sink_ready(o_source_reset_done),.o_sink_reset_done(ack_sink_done));
    assign o_source_reset_done=source_rst_n&&request_source_done&&ack_sink_done;
    assign o_dfi_reset_done=dfi_rst_n&&request_sink_done&&ack_source_done;
    assign s_drain_ready={2{o_source_reset_done}}&~captured&~m_drain_valid&~o_source_fault&i_source_idle&~i_enqueue_fire;
    wire [1:0] capture=s_drain_valid&s_drain_ready;
    wire first_capture=(|capture)&&captured==0;
    wire identity_bad=s_drain_session==0||(source_session!=0&&source_session!=s_drain_session)||(&next_id);
    wire continuation_bad=s_drain_session!=source_packet[191:160]||s_drain_epoch!=source_packet[159:128];
    wire request_take=request_valid&&o_dfi_reset_done&&!dfi_owned&&!(|o_dfi_fault);
    assign request_sink_ready=o_dfi_reset_done&&ack_pending&&ack_ready;
    assign o_apply_quiescent={2{o_source_reset_done}}&source_quiet&~o_source_fault&i_source_idle&~i_enqueue_fire;
    // Borrow the one immutable packet through the accepted proof lease.
    assign m_drain_session=source_packet[191:160];assign m_drain_epoch=source_packet[159:128];
    assign m_drain_target0=source_packet[63:0];assign m_drain_target1=source_packet[127:64];
    assign m_drain_id=source_packet[255:192];
    integer c;
    always @(posedge i_source_clk or negedge source_rst_n)begin
        if(!source_rst_n)begin
            o_enqueued_count0<=0;o_enqueued_count1<=0;o_source_fault<=0;o_stale_ack_count<=0;
            source_packet<=0;captured<=0;source_quiet<=0;source_busy<=0;
            request_started<=0;request_pending<=0;next_id<=0;source_session<=0;m_drain_valid<=0;
            dfi_fault_meta<=0;dfi_fault_sync<=0;
        end else begin
            dfi_fault_meta<=o_dfi_fault;dfi_fault_sync<=dfi_fault_meta;
            for(c=0;c<2;c=c+1)begin
                if(dfi_fault_sync[c])begin o_source_fault[c]<=1;source_quiet[c]<=0;end
                if(!i_source_idle[c]||i_enqueue_fire[c])source_quiet[c]<=0;
                // A member's lease starts at ITS capture, not when the other
                // member eventually becomes quiet or the combined packet sends.
                if(captured[c]&&(!i_source_idle[c]||i_enqueue_fire[c]))begin
                    o_source_fault[c]<=1;source_quiet[c]<=0;
                end
            end
            if(i_enqueue_fire[0])begin
                if(&o_enqueued_count0)o_source_fault[0]<=1;else o_enqueued_count0<=o_enqueued_count0+64'd1;
            end
            if(i_enqueue_fire[1])begin
                if(&o_enqueued_count1)o_source_fault[1]<=1;else o_enqueued_count1<=o_enqueued_count1+64'd1;
            end
            if(first_capture)begin
                if(identity_bad)o_source_fault<=2'b11;
                else begin
                    source_session<=s_drain_session;next_id<=next_id+64'd1;
                    source_packet[263:256]<=0;source_packet[255:192]<=next_id+64'd1;
                    source_packet[191:160]<=s_drain_session;source_packet[159:128]<=s_drain_epoch;
                    source_busy<=1;
                    if(capture[0])begin captured[0]<=1;source_packet[63:0]<=o_enqueued_count0;end
                    if(capture[1])begin captured[1]<=1;source_packet[127:64]<=o_enqueued_count1;end
                end
            end else if(|capture)begin
                if(continuation_bad)begin
                    if(capture[0])o_source_fault[0]<=1;
                    if(capture[1])o_source_fault[1]<=1;
                end
                else begin
                    if(capture[0])begin captured[0]<=1;source_packet[63:0]<=o_enqueued_count0;end
                    if(capture[1])begin captured[1]<=1;source_packet[127:64]<=o_enqueued_count1;end
                end
            end
            if(captured==2'b11&&source_busy&&!request_started)begin request_started<=1;request_pending<=1;end
            // Sticky faults cannot withdraw a packet once held at the FIFO.
            if(request_pending&&request_ready)request_pending<=0;
            if(ack_valid&&o_source_reset_done)begin
                if(source_busy&&captured==2'b11&&ack_matches)begin
                    source_busy<=0;
                    if(!( |o_source_fault)&&!(|dfi_fault_sync)&&(&i_source_idle)&&!(|i_enqueue_fire))begin
                        source_quiet<=2'b11;m_drain_valid<=2'b11;
                    end
                end else if(!(&o_stale_ack_count))o_stale_ack_count<=o_stale_ack_count+32'd1;
            end
            // Only true positive aggregate application releases BOTH leases.
            if((&m_drain_valid)&&m_drain_ready)begin
                m_drain_valid<=0;source_quiet<=0;captured<=0;request_started<=0;
            end
        end
    end
    wire over0=o_consumed_count0>dfi_packet[63:0]||(i_consume_fire[0]&&o_consumed_count0>=dfi_packet[63:0]);
    wire over1=o_consumed_count1>dfi_packet[127:64]||(i_consume_fire[1]&&o_consumed_count1>=dfi_packet[127:64]);
    always @(posedge i_dfi_clk or negedge dfi_rst_n)begin
        if(!dfi_rst_n)begin
            o_consumed_count0<=0;o_consumed_count1<=0;o_dfi_fault<=0;
            dfi_owned<=0;ack_pending<=0;dfi_last_id<=0;dfi_session<=0;
        end else begin
            if(i_consume_fire[0])begin
                if(&o_consumed_count0)o_dfi_fault[0]<=1;else o_consumed_count0<=o_consumed_count0+64'd1;
            end
            if(i_consume_fire[1])begin
                if(&o_consumed_count1)o_dfi_fault[1]<=1;else o_consumed_count1<=o_consumed_count1+64'd1;
            end
            if(request_take)begin
                dfi_owned<=1;
                if(request_data[263:256]!=0||request_data[191:160]==0||request_data[255:192]==0||
                   request_data[255:192]<=dfi_last_id||(dfi_session!=0&&request_data[191:160]!=dfi_session))o_dfi_fault<=2'b11;
                else begin dfi_session<=request_data[191:160];dfi_last_id<=request_data[255:192];end
            end
            if(dfi_owned&&!(|o_dfi_fault))begin
                if(over0)o_dfi_fault[0]<=1;
                if(over1)o_dfi_fault[1]<=1;
                if(!over0&&!over1&&!ack_pending&&o_consumed_count0==dfi_packet[63:0]&&
                   o_consumed_count1==dfi_packet[127:64]&&!(|i_consume_fire)&&i_write_quiescent)ack_pending<=1;
            end
            if(ack_pending&&ack_ready)begin ack_pending<=0;dfi_owned<=0;end
        end
    end
endmodule
`default_nettype wire
