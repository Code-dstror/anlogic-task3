`timescale 1ns / 1ps

// Pixel-domain replay boundary. Payload/metadata CDC belongs to the official
// upstream FIFO; these registers hold one admitted member, not a payload queue.
module raw_replay_context_boundary #(
    parameter integer HOST_REPLAY_CONTEXT_ENABLE = 0
) (
    input wire clk, rst_n, i_safe,
    input wire [146:0] s_data, input wire s_valid, output wire s_ready,
    output reg o_active,
    output wire [39:0] o_data, output wire o_valid, input wire i_ready,
    output wire o_sof, o_eol, o_abort,
    output wire o_context_valid, input wire i_context_ready,
    output reg [383:0] o_descriptor,
    output reg [63:0] o_job_id, o_pair_id,
    output reg o_member_index, o_private,
    output wire o_host_replay_context_valid,
    input wire i_host_replay_context_ready,
    output wire [383:0] o_host_replay_descriptor,
    output reg o_host_replay_metadata_valid,
    output reg o_done_valid, input wire i_done_ready,
    output reg o_done_error, output reg o_protocol_fault
);
    localparam [1:0] IDLE=0, HEADERS=1, CONTEXT=2, RUN=3;
    reg [1:0] state, header_index;
    reg [15:0] width, height;
    reg failed, last_seen;
    reg host_context, host_context_accepted;
    wire start_kind = s_data[146:145] == 1;
    wire context_kind = s_data[146:145] == 2;
    wire well_formed_header = s_data[143:128] == 16'hffff && !s_data[144];
    wire take = s_valid && s_ready;
    // Decode the IDLE admission directly. Referencing the combined DATA READY
    // here feeds replay.i_start back through replay READY after flattening.
    wire start_ready = state == IDLE && i_safe && !o_protocol_fault && !o_done_valid;
    wire legacy_start = start_ready && s_valid && start_kind &&
                        well_formed_header && !s_data[32] &&
                        (!HOST_REPLAY_CONTEXT_ENABLE || !s_data[34]);
    wire context_start = state == CONTEXT && i_safe &&
                         (o_private ? i_context_ready :
                          (host_context_accepted || (o_host_replay_context_valid && i_host_replay_context_ready))) &&
                         !o_protocol_fault;
    wire replay_ready, replay_done, replay_abort;
    assign o_context_valid = state == CONTEXT && o_private && !o_protocol_fault;
    assign o_host_replay_context_valid = HOST_REPLAY_CONTEXT_ENABLE &&
        state == CONTEXT && host_context && !host_context_accepted && !o_protocol_fault;
    assign o_host_replay_descriptor = HOST_REPLAY_CONTEXT_ENABLE ? o_descriptor : 384'd0;
    assign s_ready = !o_protocol_fault && !o_done_valid &&
        (state == IDLE ? i_safe : state == HEADERS ? 1'b1 :
         state == RUN ? (failed ? 1'b1 : replay_ready) : 1'b0);
    raw10_frame_replay u_replay (
        .i_clk(clk), .i_rst_n(rst_n), .i_start(legacy_start || context_start),
        .i_width(legacy_start ? s_data[15:0] : width),
        .i_height(legacy_start ? s_data[31:16] : height),
        .i_axis_tdata(s_data[127:0]), .i_axis_tkeep(s_data[143:128]),
        .i_axis_tvalid(s_valid && state == RUN && !failed && !o_protocol_fault),
        .i_axis_tlast(s_data[144]), .o_axis_tready(replay_ready),
        .o_data(o_data), .o_valid(o_valid), .i_ready(i_ready),
        .o_sof(o_sof), .o_eol(o_eol), .o_abort(replay_abort), .o_done(replay_done)
    );
    assign o_abort = replay_abort;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; header_index<=0; width<=0; height<=0;
            failed<=0; last_seen<=0; o_active<=0;
            o_descriptor<=0; o_job_id<=0; o_pair_id<=0;
            o_member_index<=0; o_private<=0;
            host_context<=0; host_context_accepted<=0; o_host_replay_metadata_valid<=0;
            o_done_valid<=0; o_done_error<=0; o_protocol_fault<=0;
        end else begin
            if (o_done_valid && i_done_ready) o_done_valid<=0;
            if (state == IDLE && take) begin
                if (!start_kind || !well_formed_header) o_protocol_fault<=1;
                else begin
                    width<=s_data[15:0]; height<=s_data[31:16];
                    failed<=0; last_seen<=0; o_done_error<=0;
                    o_descriptor<=0; o_job_id<=0; o_pair_id<=0;
                    o_private<=s_data[32]; o_member_index<=s_data[33];
                    host_context<=HOST_REPLAY_CONTEXT_ENABLE && !s_data[32] && s_data[34];
                    host_context_accepted<=0;
                    o_host_replay_metadata_valid<=0;
                    if (s_data[32] || (HOST_REPLAY_CONTEXT_ENABLE && s_data[34])) begin
                        state<=HEADERS; header_index<=0;
                    end
                    else begin state<=RUN; o_active<=1; end
                end
            end
            if (state == HEADERS && take) begin
                if (!context_kind || !well_formed_header) o_protocol_fault<=1;
                else begin
                    case (header_index)
                        0: o_descriptor[127:0]<=s_data[127:0];
                        1: o_descriptor[255:128]<=s_data[127:0];
                        2: o_descriptor[383:256]<=s_data[127:0];
                        3: begin
                            if(host_context) begin
                                if(|s_data[127:1]) o_protocol_fault<=1;
                                else begin o_host_replay_metadata_valid<=s_data[0];state<=CONTEXT;end
                            end else begin
                                o_job_id<=s_data[63:0];o_pair_id<=s_data[127:64];state<=CONTEXT;
                            end
                        end
                    endcase
                    header_index<=header_index+1'b1;
                end
            end
            // Context acceptance is independent of the later safe-to-start
            // proof. Once accepted, do not repeat CTX while waiting for safe.
            if(o_host_replay_context_valid && i_host_replay_context_ready)
                host_context_accepted<=1;
            if (context_start) begin state<=RUN; o_active<=1; end
            if (state == RUN && take) begin
                if (start_kind || context_kind) o_protocol_fault<=1;
                if (s_data[144]) last_seen<=1;
            end
            if (replay_abort) begin failed<=1; o_done_error<=1; end
            if (state == RUN && !o_protocol_fault && !(take && (start_kind || context_kind)) && (replay_done ||
                ((failed || replay_abort) && (last_seen || (take && s_data[144]))))) begin
                state<=IDLE; o_active<=0; failed<=0; last_seen<=0;
                o_done_valid<=1;
                o_done_error<=failed || replay_abort;
            end
        end
    end
endmodule
