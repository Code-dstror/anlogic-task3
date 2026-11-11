`timescale 1ns / 1ps

// Stoppable four-lane RGB transport. Official FIFOs own queued storage and CDC.
module native_rgb4_frame_cdc #(
    parameter integer MAX_WIDTH=3840, MAX_HEIGHT=2160
) (
    input wire i_source_clk, i_source_rst_n,
    input wire [575:0] s_context, input wire s_context_valid,
    output wire s_context_ready, output wire o_source_reset_done,
    input wire [95:0] s_rgb, input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_last, s_valid, output wire s_ready,
    input wire [63:0] s_tag, input wire [31:0] s_index,
    input wire s_status_valid, output wire s_status_ready,
    input wire [63:0] s_status_tag, input wire s_status_ok,
    input wire [7:0] s_status_error,
    input wire i_source_read_quiescent,
    output reg [31:0] o_source_stale_status_count,
    output wire o_source_protocol_fault,
    input wire i_sink_clk, i_sink_rst_n,
    output wire [575:0] m_context, output wire m_context_valid,
    input wire m_context_ready, output wire o_sink_reset_done,
    output wire [95:0] m_rgb, output wire [3:0] m_keep,
    output wire m_sof, m_eol, m_last, m_valid, input wire m_ready,
    output wire [63:0] m_tag, output wire [31:0] m_index,
    output wire m_bad,
    output wire m_status_valid, input wire m_status_ready,
    output wire [63:0] m_status_tag, output wire m_status_ok,
    output wire [7:0] m_status_error,
    output wire [31:0] m_status_groups,
    output wire o_sink_read_quiescent,
    output reg o_sink_protocol_fault
);
    localparam [1:0] DATA=0, FENCE=1;
    localparam [7:0] E_STREAM=1;
    wire cohort_reset_n=i_source_rst_n && i_sink_rst_n;
    wire command_source_done,command_sink_done,command_source_ready,command_sink_valid;
    wire command_fault,command_source_fault;
    wire [577:0] command_sink_data;
    wire payload_source_done,payload_sink_done,payload_source_ready,payload_sink_valid;
    wire [146:0] payload_sink_data,payload_source_data;
    wire payload_source_valid,payload_sink_ready;
    reg source_active,source_bad,source_end_seen;
    reg [63:0] source_tag;
    reg [15:0] source_width,source_height,source_x,source_y;
    reg [31:0] source_groups;
    reg sink_active,sink_bad,sink_end_seen;
    reg [63:0] sink_tag;
    reg [15:0] sink_width,sink_height,sink_x,sink_y;
    reg [31:0] sink_groups;
    reg sink_fault_meta,sink_fault_sync;

    function [3:0] row_keep;
        input [16:0] remaining;
        begin row_keep=remaining>=4 ? 4'hf : remaining==3 ? 4'h7 :
            remaining==2 ? 4'h3 : remaining==1 ? 4'h1 : 4'h0;end
    endfunction
    wire source_row_last={1'b0,source_x}+17'd4 >= {1'b0,source_width};
    wire source_frame_last=source_row_last && source_y==source_height-1'b1;
    wire source_word_bad=source_end_seen || s_tag!=source_tag || s_index!=source_groups ||
        s_keep!=row_keep({1'b0,source_width}-{1'b0,source_x}) ||
        s_sof!=(source_groups==0) || s_eol!=source_row_last || s_last!=source_frame_last;
    wire source_frame_good=s_context[447:384]!=0 &&
        s_context[220:205]!=0 && s_context[220:205]<=MAX_WIDTH &&
        s_context[236:221]!=0 && s_context[236:221]<=MAX_HEIGHT;
    wire source_status_matches=s_status_tag==source_tag;
    wire source_effective_ok=s_status_ok && !source_bad && source_end_seen;
    wire [7:0] source_effective_error=s_status_error!=0 ? s_status_error :
        (s_status_ok && !source_effective_ok ? E_STREAM : 8'd0);
    wire source_data_fire=s_valid && s_ready;
    wire source_status_fire=s_status_valid && s_status_ready && source_status_matches;
    assign o_source_reset_done=command_source_done && payload_source_done;
    assign o_sink_reset_done=command_sink_done && payload_sink_done;
    assign o_source_protocol_fault=command_source_fault || sink_fault_sync;
    assign s_context_ready=o_source_reset_done && !source_active &&
        command_source_ready && !o_source_protocol_fault;
    assign s_ready=o_source_reset_done && source_active && !source_end_seen &&
        payload_source_ready && !o_source_protocol_fault;
    // Source STATUS may close a zero/prefix job, but never an outstanding VALID.
    assign s_status_ready=o_source_reset_done && source_active && !s_valid &&
        i_source_read_quiescent && !o_source_protocol_fault &&
        (!source_status_matches || payload_source_ready);
    assign payload_source_valid=o_source_reset_done && source_active && !o_source_protocol_fault &&
        ((s_valid && !source_end_seen) ||
         (!s_valid && s_status_valid && i_source_read_quiescent && source_status_matches));
    // FENCE shares the payload FIFO, so even a failed prefix has an ordered end.
    assign payload_source_data=s_valid ?
        {DATA,9'd0,source_word_bad,s_index,s_last,s_eol,s_sof,s_keep,s_rgb} :
        {FENCE,40'd0,source_effective_error,source_effective_ok,source_tag,source_groups};

    raw_pair_command_cdc u_context_fifo (
        .i_source_clk(i_source_clk),.i_source_rst_n(cohort_reset_n),
        .s_command({2'd0,s_context}),
        .s_command_valid(s_context_valid && o_source_reset_done && !source_active && !o_source_protocol_fault),
        .s_command_ready(command_source_ready),.o_source_reset_done(command_source_done),
        .i_sink_clk(i_sink_clk),.i_sink_rst_n(cohort_reset_n),.m_command(command_sink_data),
        .m_command_valid(command_sink_valid),
        .m_command_ready(m_context_valid && m_context_ready),.o_sink_reset_done(command_sink_done),
        .o_protocol_fault(command_fault),.o_source_protocol_fault(command_source_fault));
    axis_frame_fifo_ip u_payload_fifo (
        .i_source_clk(i_source_clk),.i_source_rst_n(cohort_reset_n),
        .i_source_data(payload_source_data),.i_source_valid(payload_source_valid),
        .o_source_ready(payload_source_ready),.o_source_reset_done(payload_source_done),
        .i_sink_clk(i_sink_clk),.i_sink_rst_n(cohort_reset_n),
        .o_sink_data(payload_sink_data),.o_sink_valid(payload_sink_valid),
        .i_sink_ready(payload_sink_ready),.o_sink_reset_done(payload_sink_done));

    assign m_context=command_sink_data[575:0];
    assign m_context_valid=o_sink_reset_done && !sink_active && command_sink_valid &&
        !o_sink_protocol_fault && !command_fault && command_sink_data[577:576]==0;
    wire [1:0] payload_kind=payload_sink_data[146:145];
    assign m_rgb=payload_sink_data[95:0];assign m_keep=payload_sink_data[99:96];
    assign m_sof=payload_sink_data[100];assign m_eol=payload_sink_data[101];
    assign m_last=payload_sink_data[102];assign m_index=payload_sink_data[134:103];
    assign m_tag=sink_tag;
    wire sink_row_last={1'b0,sink_x}+17'd4 >= {1'b0,sink_width};
    wire sink_frame_last=sink_row_last && sink_y==sink_height-1'b1;
    wire sink_word_bad=sink_end_seen || payload_sink_data[144:136]!=0 || payload_sink_data[135] ||
        m_index!=sink_groups || m_keep!=row_keep({1'b0,sink_width}-{1'b0,sink_x}) ||
        m_sof!=(sink_groups==0) || m_eol!=sink_row_last || m_last!=sink_frame_last;
    assign m_bad=sink_word_bad;
    // A protocol fault does not retract an already presented DATA beat.
    assign m_valid=o_sink_reset_done && sink_active && payload_sink_valid && payload_kind==DATA;
    wire fence_matches=payload_sink_data[144:105]==0 &&
        payload_sink_data[95:32]==sink_tag && payload_sink_data[31:0]==sink_groups;
    assign m_status_valid=o_sink_reset_done && sink_active && payload_sink_valid &&
        payload_kind==FENCE && fence_matches;
    assign m_status_tag=sink_tag;assign m_status_groups=payload_sink_data[31:0];
    assign m_status_ok=payload_sink_data[96] && !sink_bad && sink_end_seen;
    assign m_status_error=payload_sink_data[104:97]!=0 ? payload_sink_data[104:97] :
        (payload_sink_data[96] && !m_status_ok ? E_STREAM : 8'd0);
    assign o_sink_read_quiescent=m_status_valid;
    assign payload_sink_ready=(m_valid && m_ready) || (m_status_valid && m_status_ready);

    always @(posedge i_source_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin sink_fault_meta<=0;sink_fault_sync<=0;end
        else begin sink_fault_meta<=o_sink_protocol_fault;sink_fault_sync<=sink_fault_meta;end
    end
    always @(posedge i_source_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin
            source_active<=0;source_bad<=0;source_end_seen<=0;source_tag<=0;
            source_width<=0;source_height<=0;source_x<=0;source_y<=0;source_groups<=0;
            o_source_stale_status_count<=0;
        end else if(!o_source_reset_done) begin
            source_active<=0;source_bad<=0;source_end_seen<=0;source_tag<=0;
            source_width<=0;source_height<=0;source_x<=0;source_y<=0;source_groups<=0;
            o_source_stale_status_count<=0;
        end else begin
            if(s_context_valid && s_context_ready) begin
                source_active<=1;source_bad<=!source_frame_good;source_end_seen<=0;
                source_tag<=s_context[447:384];source_width<=s_context[220:205];
                source_height<=s_context[236:221];source_x<=0;source_y<=0;source_groups<=0;
            end
            if(source_data_fire) begin
                source_bad<=source_bad || source_word_bad;source_end_seen<=source_end_seen || s_last;
                source_groups<=source_groups+1'b1;
                if(source_row_last) begin source_x<=0;source_y<=source_y+1'b1;end
                else source_x<=source_x+16'd4;
            end
            if(s_status_valid && s_status_ready && !source_status_matches &&
                !(&o_source_stale_status_count))
                o_source_stale_status_count<=o_source_stale_status_count+1'b1;
            if(source_status_fire) source_active<=0;
        end
    end
    always @(posedge i_sink_clk or negedge cohort_reset_n) begin
        if(!cohort_reset_n) begin
            sink_active<=0;sink_bad<=0;sink_end_seen<=0;sink_tag<=0;
            sink_width<=0;sink_height<=0;sink_x<=0;sink_y<=0;sink_groups<=0;o_sink_protocol_fault<=0;
        end else if(!o_sink_reset_done) begin
            sink_active<=0;sink_bad<=0;sink_end_seen<=0;sink_tag<=0;
            sink_width<=0;sink_height<=0;sink_x<=0;sink_y<=0;sink_groups<=0;o_sink_protocol_fault<=0;
        end else begin
            if(command_fault || (!sink_active && command_sink_valid && command_sink_data[577:576]!=0) ||
                (sink_active && payload_sink_valid &&
                 (payload_kind>FENCE || (payload_kind==FENCE && !fence_matches))))
                o_sink_protocol_fault<=1;
            if(m_context_valid && m_context_ready) begin
                sink_active<=1;sink_bad<=0;sink_end_seen<=0;sink_tag<=m_context[447:384];
                sink_width<=m_context[220:205];sink_height<=m_context[236:221];
                sink_x<=0;sink_y<=0;sink_groups<=0;
            end
            if(m_valid && m_ready) begin
                sink_bad<=sink_bad || sink_word_bad;sink_end_seen<=sink_end_seen || m_last;
                sink_groups<=sink_groups+1'b1;
                if(sink_row_last) begin sink_x<=0;sink_y<=sink_y+1'b1;end
                else sink_x<=sink_x+16'd4;
            end
            if(m_status_valid && m_status_ready) sink_active<=0;
        end
    end
endmodule
