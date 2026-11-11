`timescale 1ns/1ps
`default_nettype none
// HDR reuses the existing DFI->PIX replay FIFO. Both metadata owners remain
// held; the processing command CDC already delivered the exact PIX identity.
module hdr_raw14_shared_transport4 #(
    parameter integer MAX_WIDTH=1920,MAX_HEIGHT=1080
)(
    input wire i_source_clk,i_source_rst_n,i_source_phase_owned,
    input wire [575:0] s_context,input wire s_context_valid,
    output wire s_context_ready,output wire o_source_reset_done,
    input wire [55:0] s_raw,input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_last,s_valid,output wire s_ready,
    input wire [63:0] s_tag,input wire [31:0] s_index,
    input wire s_status_valid,output wire s_status_ready,
    input wire [63:0] s_status_tag,input wire s_status_ok,
    input wire [7:0] s_status_error,input wire i_source_read_quiescent,
    output wire [146:0] m_fifo_data,output wire m_fifo_valid,input wire m_fifo_ready,
    input wire i_fifo_source_reset_done,
    output wire o_source_protocol_fault,
    input wire i_sink_clk,i_sink_rst_n,i_sink_phase_owned,
    input wire [575:0] i_prepared_context,input wire i_owner_prepared,
    output wire [575:0] m_context,output wire m_context_valid,input wire m_context_ready,
    output wire o_sink_reset_done,
    input wire [146:0] s_fifo_data,input wire s_fifo_valid,output wire s_fifo_ready,
    input wire i_fifo_sink_reset_done,
    output wire [95:0] m_raw_capsule,output wire [3:0] m_keep,
    output wire m_sof,m_eol,m_last,m_valid,m_bad,input wire m_ready,
    output wire [63:0] m_tag,output wire [31:0] m_index,
    output wire m_status_valid,input wire m_status_ready,
    output wire [63:0] m_status_tag,output wire m_status_ok,
    output wire [7:0] m_status_error,output wire [31:0] m_status_groups,
    output wire o_sink_read_quiescent,output reg o_sink_protocol_fault
);
    localparam [1:0] DATA=0,FENCE=1;
    wire cohort_reset_n=i_source_rst_n&&i_sink_rst_n;
    wire source_local_rst_n,sink_local_rst_n;
    // One cohort asserts both domains without a clock. Only the receiving
    // domain's third release Q may enable its state or normal data controls.
    // The external shared FIFO has its own matching local release chains;
    // its done inputs must remain the actual corresponding-domain outputs.
    reset_release_sync u_source_reset(
        .i_clk(i_source_clk),.i_async_rst_n(cohort_reset_n),.o_rst_n(source_local_rst_n));
    reset_release_sync u_sink_reset(
        .i_clk(i_sink_clk),.i_async_rst_n(cohort_reset_n),.o_rst_n(sink_local_rst_n));
    reg source_active,source_bad,source_end_seen;
    reg [15:0] source_x,source_y;
    reg [31:0] source_groups;
    reg sink_active,sink_bad,sink_end_seen,sink_context_taken;
    reg fence_checked,fence_match_q;
    reg [31:0] sink_groups;
    (* preserve="true", ASYNC_REG="TRUE" *) reg sink_fault_meta,sink_fault_sync;
    // Borrow only actual owner-held fields, never current CONFIG or capture.
    wire [15:0] source_width=s_context[220:205],source_height=s_context[236:221];
    wire [15:0] sink_width=i_prepared_context[220:205],sink_height=i_prepared_context[236:221];
    wire [63:0] source_tag=s_context[447:384],sink_tag=i_prepared_context[447:384];
    function [3:0] row_keep;
        input [16:0] remaining;
        begin row_keep=remaining>=4 ? 4'hf : remaining==3 ? 4'h7 :
            remaining==2 ? 4'h3 : remaining==1 ? 4'h1 : 4'h0;end
    endfunction
    wire source_row_last={1'b0,source_x}+17'd4>={1'b0,source_width};
    wire source_frame_last=source_row_last&&source_y==source_height-1'b1;
    wire source_word_bad=source_end_seen||s_tag!=source_tag||s_index!=source_groups||
        s_keep!=row_keep({1'b0,source_width}-{1'b0,source_x})||
        s_sof!=(source_groups==0)||s_eol!=source_row_last||s_last!=source_frame_last;
    wire source_frame_good=source_tag!=0&&source_width!=0&&source_width<=MAX_WIDTH&&
        source_height!=0&&source_height<=MAX_HEIGHT;
    wire source_status_matches=s_status_tag==source_tag;
    wire effective_ok=s_status_ok&&!source_bad&&source_end_seen;
    wire [7:0] effective_error=s_status_error!=0 ? s_status_error :
        (s_status_ok&&!effective_ok ? 8'd1 : 8'd0);
    assign o_source_reset_done=source_local_rst_n&&i_fifo_source_reset_done;
    assign o_sink_reset_done=sink_local_rst_n&&i_fifo_sink_reset_done;
    assign o_source_protocol_fault=sink_fault_sync;
    assign s_context_ready=o_source_reset_done&&i_source_phase_owned&&!source_active&&!sink_fault_sync;
    assign s_ready=o_source_reset_done&&source_active&&!source_end_seen&&m_fifo_ready;
    assign s_status_ready=o_source_reset_done&&source_active&&!s_valid&&i_source_read_quiescent&&
        (!source_status_matches||m_fifo_ready);
    // An already offered DATA/FENCE remains offered through a hard quarantine.
    assign m_fifo_valid=o_source_reset_done&&source_active&&
        ((s_valid&&!source_end_seen)||(!s_valid&&s_status_valid&&i_source_read_quiescent&&source_status_matches));
    assign m_fifo_data=s_valid ?
        {DATA,9'd0,source_word_bad,s_index,s_last,s_eol,s_sof,s_keep,40'd0,s_raw} :
        {FENCE,40'd0,effective_error,effective_ok,source_tag,source_groups};
    assign m_context=i_prepared_context;
    assign m_context_valid=o_sink_reset_done&&i_sink_phase_owned&&i_owner_prepared&&
        !sink_context_taken&&!o_sink_protocol_fault;
    assign m_raw_capsule=s_fifo_data[95:0];assign m_keep=s_fifo_data[99:96];
    assign m_sof=s_fifo_data[100];assign m_eol=s_fifo_data[101];assign m_last=s_fifo_data[102];
    assign m_index=s_fifo_data[134:103];assign m_tag=sink_tag;
    wire [1:0] payload_kind=s_fifo_data[146:145];
    // The source checks geometry before the official FIFO accepts DATA and
    // carries that result in bit 135. Do not rebuild a second row/column
    // walker here: the FIFO preserves both pixels and their checked flags.
    // Keep the receiving owner, ordering, end and FENCE checks at this side.
    wire sink_word_bad=sink_end_seen||s_fifo_data[144:136]!=0||s_fifo_data[135]||
        s_fifo_data[95:56]!=0||m_index!=sink_groups;
    wire fence_matches=s_fifo_data[144:105]==0&&s_fifo_data[95:32]==sink_tag&&
        s_fifo_data[31:0]==sink_groups;
    assign m_valid=o_sink_reset_done&&sink_active&&s_fifo_valid&&payload_kind==DATA;
    assign m_bad=sink_word_bad;
    // The FIFO retains a FENCE until the SOURCE consumer accepts it. Validate
    // that held head once before publication, keeping the wide owner/count
    // comparison away from downstream SOURCE enables and cleanup controls.
    wire fence_offer=o_sink_reset_done&&sink_active&&s_fifo_valid&&payload_kind==FENCE;
    assign m_status_valid=fence_offer&&fence_checked&&fence_match_q;
    assign m_status_tag=sink_tag;assign m_status_groups=s_fifo_data[31:0];
    assign m_status_ok=s_fifo_data[96]&&!sink_bad&&sink_end_seen;
    assign m_status_error=s_fifo_data[104:97]!=0 ? s_fifo_data[104:97] :
        (s_fifo_data[96]&&!m_status_ok ? 8'd1 : 8'd0);
    assign o_sink_read_quiescent=m_status_valid;
    assign s_fifo_ready=(m_valid&&m_ready)||(m_status_valid&&m_status_ready);
    always @(posedge i_source_clk or negedge source_local_rst_n)begin
        if(!source_local_rst_n)begin sink_fault_meta<=0;sink_fault_sync<=0;end
        else begin sink_fault_meta<=o_sink_protocol_fault;sink_fault_sync<=sink_fault_meta;end
    end
    always @(posedge i_source_clk or negedge source_local_rst_n)begin
        if(!source_local_rst_n)begin source_active<=0;source_bad<=0;source_end_seen<=0;source_x<=0;source_y<=0;source_groups<=0;end
        else begin
            if(s_context_valid&&s_context_ready)begin
                source_active<=1;source_bad<=!source_frame_good;source_end_seen<=0;
                source_x<=0;source_y<=0;source_groups<=0;
            end
            if(s_valid&&s_ready)begin
                source_bad<=source_bad||source_word_bad;source_end_seen<=source_end_seen||s_last;
                source_groups<=source_groups+1'b1;
                if(source_row_last)begin source_x<=0;source_y<=source_y+1'b1;end
                else source_x<=source_x+16'd4;
            end
            if(s_status_valid&&s_status_ready&&source_status_matches)source_active<=0;
        end
    end
    always @(posedge i_sink_clk or negedge sink_local_rst_n)begin
        if(!sink_local_rst_n)begin
            sink_active<=0;sink_bad<=0;sink_end_seen<=0;sink_context_taken<=0;
            fence_checked<=0;fence_match_q<=0;
            sink_groups<=0;o_sink_protocol_fault<=0;
        end else begin
            if(!sink_active||(m_status_valid&&m_status_ready))fence_checked<=0;
            else if(fence_offer&&!fence_checked)begin
                fence_checked<=1;fence_match_q<=fence_matches;
            end
            if(!i_sink_phase_owned&&!sink_active)sink_context_taken<=0;
            if(m_context_valid&&m_context_ready)begin
                sink_context_taken<=1;sink_active<=1;sink_bad<=0;sink_end_seen<=0;
                sink_groups<=0;
                if(sink_tag==0||sink_width==0||sink_width>MAX_WIDTH||sink_height==0||sink_height>MAX_HEIGHT)
                    o_sink_protocol_fault<=1;
            end
            if(sink_active&&s_fifo_valid&&(payload_kind>FENCE||
                (payload_kind==FENCE&&fence_checked&&!fence_match_q)))
                o_sink_protocol_fault<=1;
            if(m_valid&&m_ready)begin
                sink_bad<=sink_bad||sink_word_bad;sink_end_seen<=sink_end_seen||m_last;
                sink_groups<=sink_groups+1'b1;
            end
            if(m_status_valid&&m_status_ready)sink_active<=0;
        end
    end
endmodule
`default_nettype wire
