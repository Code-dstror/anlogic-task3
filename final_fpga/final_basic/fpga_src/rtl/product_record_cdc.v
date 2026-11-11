`timescale 1ns/1ps
`include "c2h_transport_limits.vh"
// One opaque record. Only ownership cold reset clears state or FIFO contents.
module product_record_cdc #(
    parameter [31:0] MAX_RECORD_BYTES=`C2H_MAX_RECORD_BYTES
)(
    input wire s_clk,m_clk,s_cold_rst_n,m_cold_rst_n,
    input wire s_record_valid,output wire s_record_ready,
    input wire [31:0] s_record_length,input wire [127:0] s_record_identity,
    input wire [127:0] s_axis_data,input wire [15:0] s_axis_keep,
    input wire s_axis_valid,s_axis_last,output wire s_axis_ready,
    input wire s_done_valid,s_done_ok,s_drained,output wire s_cancel,
    output wire s_retire_valid,input wire s_retire_ready,
    output wire [127:0] s_retire_identity,output reg [31:0] s_retire_status,
    output wire m_record_valid,input wire m_record_ready,
    output reg [31:0] m_record_length,output reg [127:0] m_record_identity,
    output wire [127:0] m_axis_data,output wire [15:0] m_axis_keep,
    output wire m_axis_valid,m_axis_last,input wire m_axis_ready,
    output wire m_done_valid,m_drained,output reg m_done_ok,input wire m_cancel,
    input wire m_retire_valid,output wire m_retire_ready,
    input wire [127:0] m_retire_identity,input wire [31:0] m_retire_status,
    output wire s_busy,m_busy,s_fault,m_fault,s_reset_done,m_reset_done
);
    localparam [2:0] S_IDLE=0,S_ID=1,S_LENGTH=2,S_DATA=3,S_DONE=4,S_WAIT=5,S_SETTLE=6,S_REPLY=7;
    localparam [2:0] M_ID=0,M_LENGTH=1,M_OFFER=2,M_DATA=3,M_DONE=4,M_RETURN=5;
    localparam [1:0] T_DATA=0,T_ID=1,T_LENGTH=2,T_DONE=3;
    wire cold_n=s_cold_rst_n && m_cold_rst_n;
    wire s_rst_n,m_rst_n,fifo_source_done,fifo_sink_done;
    wire [146:0] fifo_out;reg [146:0] fifo_in;
    wire fifo_out_valid,fifo_in_ready;reg fifo_in_valid,fifo_out_ready;
    reg [2:0] s_state,m_state;
    reg s_local_fault,m_local_fault,s_bad,s_last_seen,m_last_seen,done_ok_hold;
    reg discard_credit;
    reg payload_held,offer_held;
    // USER owns cancellation. Never sample a combinational native guard in DFI.
    // Hold sampled intent through the existing return-ACK phase; only M_ID is owner-free.
    reg m_cancel_hold;
    // Budget is derived once at admission. ceil uses 33 bits for MAX=ffffffff.
    function integer remaining_width;
        input [32:0] maximum_beats;
        reg [32:0] value;
        begin
            value=maximum_beats;remaining_width=0;
            while(value!=0)begin remaining_width=remaining_width+1;value=value>>1;end
            if(remaining_width==0)remaining_width=1;
        end
    endfunction
    localparam integer R_WIDTH=remaining_width(({1'b0,MAX_RECORD_BYTES}+33'd15)>>4);
    reg [R_WIDTH-1:0] remaining_beats;
    // Cached predicates follow the same accepted legal beat as the counter.
    // They remove wide zero/one comparisons from its own CE feedback.
    reg beats_empty,tail_expected;
    reg [15:0] tail_keep;
    wire [32:0] admission_beats=({1'b0,s_record_length}+33'd15)>>4;
    wire [15:0] admission_tail=16'hffff >> ((5'd16-{1'b0,s_record_length[3:0]}) & 5'd15);
    // One accepted DFI length supplies the token, byte checks and DONE proof.
    // The producer still retains its descriptor/identity through real retire.
    reg [31:0] record_length_hold;
    reg return_request,return_ack;reg [31:0] return_status;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] s_peer_ready,m_peer_ready;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] cancel_sync,s_fault_sync,m_fault_sync;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] return_request_sync,return_ack_sync;
    reset_release_sync s_release(.i_clk(s_clk),.i_async_rst_n(cold_n),.o_rst_n(s_rst_n));
    reset_release_sync m_release(.i_clk(m_clk),.i_async_rst_n(cold_n),.o_rst_n(m_rst_n));
    axis_frame_fifo_ip fifo(
        .i_source_clk(s_clk),.i_source_rst_n(s_rst_n),.i_source_data(fifo_in),.i_source_valid(fifo_in_valid),
        .o_source_ready(fifo_in_ready),.o_source_reset_done(fifo_source_done),
        .i_sink_clk(m_clk),.i_sink_rst_n(m_rst_n),.o_sink_data(fifo_out),.o_sink_valid(fifo_out_valid),
        .i_sink_ready(fifo_out_ready),.o_sink_reset_done(fifo_sink_done));
    assign s_reset_done=s_rst_n && fifo_source_done && s_peer_ready[1];
    assign m_reset_done=m_rst_n && fifo_sink_done && m_peer_ready[1];
    assign s_fault=s_local_fault || m_fault_sync[1];
    assign m_fault=m_local_fault || s_fault_sync[1];
    assign s_cancel=cancel_sync[1] || s_bad || s_fault;
    assign s_busy=!s_reset_done || s_state!=S_IDLE || s_fault;
    assign m_busy=!m_reset_done || m_state!=M_ID || fifo_out_valid || m_fault;
    assign s_record_ready=s_reset_done && s_state==S_IDLE && !s_cancel && !s_fault;
    // Ordinary case preserves the old fail-closed X/Z KEEP behavior.
    function keep_legal;
        input [15:0] keep;
        begin
            case(keep)
                16'h0001,16'h0003,16'h0007,16'h000f,
                16'h001f,16'h003f,16'h007f,16'h00ff,
                16'h01ff,16'h03ff,16'h07ff,16'h0fff,
                16'h1fff,16'h3fff,16'h7fff,16'hffff:keep_legal=1'b1;
                default:keep_legal=1'b0;
            endcase
        end
    endfunction
    // For legal low-contiguous KEEP, bits outside tail_keep mean an overrun.
    // Keep LAST's original four-state semantics: a shorter mask with LAST=X
    // remains X unless another old bad condition already determines the result.
    wire beat_bad=!keep_legal(s_axis_keep) || s_last_seen || beats_empty ||
        (tail_expected && ((s_axis_keep & ~tail_keep)!=0)) ||
        s_axis_last!=(tail_expected && s_axis_keep==tail_keep) ||
        (!s_axis_last && s_axis_keep!=16'hffff);
    // Malformed payload is still absorbed when the FIFO is full. Qualify that
    // discard on a clock first, so upstream burst/KEEP/VALID checks cannot feed
    // back through READY into the DDR read address/control enable. A source
    // stalled on this edge retains the same beat until the credited transfer.
    assign s_axis_ready=s_reset_done && s_state==S_DATA && !s_fault &&
        (s_bad || discard_credit || fifo_in_ready);
    wire input_fire=s_axis_valid && s_axis_ready;
    // The USER already accepted this SAFE obligation. Later faults/cancel do
    // not revoke it; quarantine still prevents any subsequent record admission.
    assign s_retire_valid=s_reset_done && s_state==S_REPLY;
    assign s_retire_identity=s_record_identity;
    always @*begin
        fifo_in=0;fifo_in_valid=0;
        if(s_reset_done && !s_fault)begin
            case(s_state)
                S_ID:begin fifo_in={T_ID,17'd0,s_record_identity};fifo_in_valid=1;end
                S_LENGTH:begin fifo_in={T_LENGTH,113'd0,record_length_hold};fifo_in_valid=1;end
                S_DATA:begin
                    fifo_in={T_DATA,s_axis_last,s_axis_keep,s_axis_data};
                    fifo_in_valid=s_axis_valid && !s_bad && !beat_bad;
                end
                S_DONE:begin fifo_in={T_DONE,144'd0,done_ok_hold};fifo_in_valid=1;end
                default:begin end
            endcase
        end
    end
    always @(posedge s_clk or negedge s_rst_n)begin
        if(!s_rst_n)begin
            s_state<=S_IDLE;s_local_fault<=0;s_bad<=0;s_last_seen<=0;remaining_beats<=0;beats_empty<=1;tail_expected<=0;tail_keep<=0;done_ok_hold<=0;
            discard_credit<=0;
            record_length_hold<=0;
            s_peer_ready<=0;cancel_sync<=0;m_fault_sync<=0;return_request_sync<=0;return_ack<=0;s_retire_status<=0;
        end else begin
            discard_credit<=s_reset_done && s_state==S_DATA && !s_fault &&
                s_axis_valid && beat_bad && !input_fire;
            s_peer_ready<={s_peer_ready[0],fifo_sink_done};
            cancel_sync<={cancel_sync[0],m_cancel_hold};m_fault_sync<={m_fault_sync[0],m_local_fault};
            return_request_sync<={return_request_sync[0],return_request};
            if(return_request_sync[1]!=return_ack && s_state!=S_WAIT && s_state!=S_SETTLE && s_state!=S_REPLY)s_local_fault<=1;
            case(s_state)
                S_IDLE:if(s_record_valid && s_record_ready)begin
                    if(s_record_length==0 || s_record_length>MAX_RECORD_BYTES)s_local_fault<=1;
                    else begin s_state<=S_ID;s_bad<=0;s_last_seen<=0;remaining_beats<=admission_beats[R_WIDTH-1:0];beats_empty<=0;tail_expected<=(s_record_length<=32'd16);tail_keep<=admission_tail;record_length_hold<=s_record_length;end
                end
                S_ID:if(fifo_in_valid && fifo_in_ready)s_state<=S_LENGTH;
                S_LENGTH:if(fifo_in_valid && fifo_in_ready)s_state<=S_DATA;
                S_DATA:begin
                    if(input_fire)begin
                        if(beat_bad)s_bad<=1;
                        if(!s_bad && !beat_bad)begin
                            remaining_beats<=remaining_beats-1'b1;
                            beats_empty<=tail_expected;tail_expected<=(remaining_beats==2);
                            if(s_axis_last)s_last_seen<=1;
                        end
                    end
                    if(s_done_valid && s_drained && !s_axis_valid)begin
                        done_ok_hold<=s_done_ok && !s_bad && s_last_seen && beats_empty;
                        s_state<=S_DONE;
                    end
                end
                S_DONE:if(fifo_in_valid && fifo_in_ready)s_state<=S_WAIT;
                S_WAIT:if(return_request_sync[1]!=return_ack)s_state<=S_SETTLE;
                S_SETTLE:begin s_retire_status<=return_status;s_state<=S_REPLY;end
                S_REPLY:if(s_retire_valid && s_retire_ready)begin return_ack<=return_request_sync[1];s_state<=S_IDLE;s_bad<=0;end
                default:s_local_fault<=1;
            endcase
            if(s_axis_valid && (s_state==S_DONE || s_state==S_WAIT || s_state==S_SETTLE || s_state==S_REPLY))s_local_fault<=1;
        end
    end
    wire [1:0] token=fifo_out[146:145];
    wire id_shape=fifo_out[144:128]==0;
    wire length_shape=fifo_out[144:32]==0 && fifo_out[31:0]!=0 && fifo_out[31:0]<=MAX_RECORD_BYTES;
    wire done_shape=fifo_out[144:1]==0;
    assign m_record_valid=m_reset_done && m_state==M_OFFER && (!m_fault || offer_held);
    assign m_axis_data=fifo_out[127:0];assign m_axis_keep=fifo_out[143:128];assign m_axis_last=fifo_out[144];
    assign m_axis_valid=m_reset_done && m_state==M_DATA && fifo_out_valid && token==T_DATA &&
        !m_last_seen && (!m_fault || payload_held);
    // A previously formed drained fact remains true; it is never a SAFE proof.
    assign m_done_valid=m_reset_done && (m_state==M_DONE || m_state==M_RETURN);
    assign m_drained=m_done_valid;
    assign m_retire_ready=m_reset_done && m_state==M_DONE && !m_fault && m_retire_identity==m_record_identity;
    always @*begin
        fifo_out_ready=0;
        if(m_reset_done)begin
            case(m_state)
                M_ID:fifo_out_ready=!m_fault && token==T_ID && id_shape;
                M_LENGTH:fifo_out_ready=!m_fault && token==T_LENGTH && length_shape;
                M_DATA:fifo_out_ready=token==T_DONE ? (!m_fault && done_shape) :
                    (m_axis_valid && m_axis_ready);
                default:begin end
            endcase
        end
    end
    always @(posedge m_clk or negedge m_rst_n)begin
        if(!m_rst_n)begin
            m_state<=M_ID;m_local_fault<=0;m_last_seen<=0;m_record_length<=0;m_record_identity<=0;m_done_ok<=0;
            payload_held<=0;offer_held<=0;m_cancel_hold<=0;
            m_peer_ready<=0;s_fault_sync<=0;return_ack_sync<=0;return_request<=0;return_status<=0;
        end else begin
            if(m_state==M_ID)m_cancel_hold<=0;
            else if(m_cancel)m_cancel_hold<=1;
            m_peer_ready<={m_peer_ready[0],fifo_source_done};s_fault_sync<={s_fault_sync[0],s_local_fault};
            return_ack_sync<={return_ack_sync[0],return_ack};
            payload_held<=m_axis_valid && !m_axis_ready;
            offer_held<=m_record_valid && !m_record_ready;
            if(m_retire_valid && m_state!=M_RETURN && (m_state!=M_DONE || m_retire_identity!=m_record_identity))m_local_fault<=1;
            case(m_state)
                M_ID:if(m_reset_done && fifo_out_valid)begin
                    if(token!=T_ID || !id_shape)m_local_fault<=1;
                    else if(fifo_out_ready)begin m_record_identity<=fifo_out[127:0];m_state<=M_LENGTH;m_done_ok<=0;m_last_seen<=0;end
                end
                M_LENGTH:if(m_reset_done && fifo_out_valid)begin
                    if(token!=T_LENGTH || !length_shape)m_local_fault<=1;
                    else if(fifo_out_ready)begin m_record_length<=fifo_out[31:0];m_state<=M_OFFER;end
                end
                M_OFFER:if(m_record_valid && m_record_ready)m_state<=M_DATA;
                M_DATA:if(m_reset_done && fifo_out_valid)begin
                    if(token==T_DATA)begin
                        if(m_last_seen)m_local_fault<=1;
                        if(m_axis_valid && m_axis_ready && m_axis_last)m_last_seen<=1;
                    end else if(token==T_DONE && done_shape)begin
                        if(fifo_out_ready)begin
                            if(fifo_out[0] && !m_last_seen)m_local_fault<=1;
                            m_done_ok<=fifo_out[0];m_state<=M_DONE;
                        end
                    end else m_local_fault<=1;
                end
                M_DONE:if(m_retire_valid && m_retire_ready)begin
                    return_status<=m_retire_status;return_request<=!return_request;m_state<=M_RETURN;
                end
                M_RETURN:if(return_ack_sync[1]==return_request)m_state<=M_ID;
                default:m_local_fault<=1;
            endcase
        end
    end
endmodule
