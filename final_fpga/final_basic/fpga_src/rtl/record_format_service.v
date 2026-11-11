`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// One actual DFI selection decision is returned through the official ACK FIFO.
module record_format_service #(
    parameter integer RECORD_V3_ENABLE=0,
    parameter integer NEUTRAL_STATS_ENABLE = 0
) (
    input wire i_user_clk,
    input wire i_user_rst_n,
    input wire write_valid,
    input wire [11:0] write_offset,
    input wire [31:0] write_data,
    input wire [3:0] write_strobes,
    output wire [1:0] write_response,
    input wire read_valid,
    input wire [11:0] read_offset,
    output wire read_response_valid,
    output wire [31:0] read_data,
    output wire [1:0] read_response,
    input wire [31:0] i_user_source_session,
    input wire i_user_source_session_ready,
    input wire i_app_enable,
    input wire i_c2h_running,
    input wire i_tx_busy,
    input wire i_source_functional_quiescent,
    input wire i_session_armed,
    input wire i_rearm_ready,
    output wire o_user_busy,
    output wire [15:0] o_user_selected_version,
    output wire [15:0] o_user_selected_header_length,
    output wire [31:0] o_user_selection_epoch,
    output wire o_user_reset_done,
    output wire [31:0] o_stale_ack_count,
    input wire i_dfi_clk,
    input wire i_dfi_rst_n,
    input wire [31:0] i_dfi_source_session,
    input wire i_dfi_quiescent,
    output reg [15:0] o_dfi_selected_version,
    output reg [31:0] o_dfi_selection_epoch,
    output wire o_dfi_reset_done
);
    wire cohort_reset_n = i_user_rst_n && i_dfi_rst_n;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] user_release, dfi_release;
    wire user_local_reset_n = user_release[2];
    wire dfi_local_reset_n = dfi_release[2];
    wire command_source_done, command_sink_done;
    wire ack_source_done, ack_sink_done;
    wire user_local_done = user_local_reset_n && command_source_done && ack_sink_done;
    wire dfi_local_done = dfi_local_reset_n && command_sink_done && ack_source_done;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] dfi_done_user_sync, user_done_dfi_sync;
    wire [146:0] command_source_data, command_sink_data, ack_sink_data;
    // BAR creates a 96-bit command with 51 constant high zero bits. The
    // final DFI reply has 131 meaningful bits and 16 constant high zeros.
    wire [95:0] received_command;
    wire [130:0] received_ack;
    assign command_sink_data={51'd0,received_command};
    assign ack_sink_data={16'd0,received_ack};
    wire command_source_valid, command_source_ready, command_sink_valid;
    wire command_sink_ready, ack_source_ready, ack_sink_valid, ack_sink_ready;
    reg [146:0] ack_source_data;
    reg ack_source_valid,decision_pending,reply_pending;
    reg decision_quiet;
    reg [2:0] command_error;
    wire [2:0] decision_error=ack_source_data[66:64];
    wire [15:0] next_version = o_dfi_selected_version;
    wire [15:0] next_header = next_version == `PCIE_PROTOCOL_VERSION ? 16'd64 :
        (next_version == `PCIE_RECORD_V4_VERSION ? `PCIE_RECORD_V4_HEADER_LENGTH : 16'd192);
    wire [31:0] next_epoch = o_dfi_selection_epoch;

    // Common asynchronous assertion and independent synchronous local release.
    always @(posedge i_user_clk or negedge cohort_reset_n) begin
        if (!cohort_reset_n) user_release <= 0;
        else user_release <= {user_release[1:0], 1'b1};
    end
    always @(posedge i_dfi_clk or negedge cohort_reset_n) begin
        if (!cohort_reset_n) dfi_release <= 0;
        else dfi_release <= {dfi_release[1:0], 1'b1};
    end
    always @(posedge i_user_clk or negedge user_local_reset_n) begin
        if (!user_local_reset_n) dfi_done_user_sync <= 0;
        else dfi_done_user_sync <= {dfi_done_user_sync[0], dfi_local_done};
    end
    always @(posedge i_dfi_clk or negedge dfi_local_reset_n) begin
        if (!dfi_local_reset_n) user_done_dfi_sync <= 0;
        else user_done_dfi_sync <= {user_done_dfi_sync[0], user_local_done};
    end
    assign o_user_reset_done = user_local_done && dfi_done_user_sync[1];
    assign o_dfi_reset_done = dfi_local_done && user_done_dfi_sync[1];

    record_format_bar #(.NEUTRAL_STATS_ENABLE(NEUTRAL_STATS_ENABLE),.RECORD_V3_ENABLE(RECORD_V3_ENABLE)) user_bar (
        .clk(i_user_clk), .rst_n(user_local_reset_n), .stream_ready(o_user_reset_done),
        .write_valid(write_valid), .write_offset(write_offset), .write_data(write_data),
        .write_strobes(write_strobes), .write_response(write_response),
        .read_valid(read_valid), .read_offset(read_offset),
        .read_response_valid(read_response_valid), .read_data(read_data), .read_response(read_response),
        .i_user_source_session(i_user_source_session), .i_user_source_session_ready(i_user_source_session_ready),
        .i_app_enable(i_app_enable), .i_c2h_running(i_c2h_running), .i_tx_busy(i_tx_busy),
        .i_source_functional_quiescent(i_source_functional_quiescent),
        .i_session_armed(i_session_armed), .i_rearm_ready(i_rearm_ready),
        .cmd_data(command_source_data), .cmd_valid(command_source_valid), .cmd_ready(command_source_ready),
        .rsp_data(ack_sink_data), .rsp_valid(ack_sink_valid), .rsp_ready(ack_sink_ready),
        .o_user_busy(o_user_busy), .o_user_selected_version(o_user_selected_version),
        .o_user_selected_header_length(o_user_selected_header_length),
        .o_user_selection_epoch(o_user_selection_epoch), .o_stale_ack_count(o_stale_ack_count)
    );
    control_message_fifo_ip #(.MESSAGE_WIDTH(96),.BORROW_SOURCE(1)) command_fifo (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_user_clk), .i_source_rst_n(cohort_reset_n),
        .i_source_data(command_source_data[95:0]), .i_source_valid(command_source_valid),
        .o_source_ready(command_source_ready), .o_source_reset_done(command_source_done),
        .i_sink_clk(i_dfi_clk), .i_sink_rst_n(cohort_reset_n),
        .o_sink_data(received_command), .o_sink_valid(command_sink_valid),
        .i_sink_ready(command_sink_ready), .o_sink_reset_done(command_sink_done)
    );
    control_message_fifo_ip #(.MESSAGE_WIDTH(131),.BORROW_SOURCE(1)) ack_fifo (
        .o_sink_flit_read(),.o_sink_flit_data(),.o_sink_flit_index(),
        .i_source_clk(i_dfi_clk), .i_source_rst_n(cohort_reset_n),
        .i_source_data(ack_source_data[130:0]), .i_source_valid(ack_source_valid),
        .o_source_ready(ack_source_ready), .o_source_reset_done(ack_source_done),
        .i_sink_clk(i_user_clk), .i_sink_rst_n(cohort_reset_n),
        .o_sink_data(received_ack), .o_sink_valid(ack_sink_valid),
        .i_sink_ready(ack_sink_ready), .o_sink_reset_done(ack_sink_done)
    );

    // False boundary/session produces a real negative response, never a stuck READY.
    assign command_sink_ready = o_dfi_reset_done && !ack_source_valid && !decision_pending && !reply_pending;
    always @(*) begin
        command_error = `PCIE_RECORD_V2_ERROR_OK;
        if (command_sink_data[146:96] != 0 || command_sink_data[31:0] == 0)
            command_error = `PCIE_RECORD_V2_ERROR_INVALID;
        else if (command_sink_data[95:64] != `PCIE_PROTOCOL_VERSION &&
                 command_sink_data[95:64] != `PCIE_RECORD_V2_VERSION &&
                 (!RECORD_V3_ENABLE || command_sink_data[95:64] != `PCIE_RECORD_V4_VERSION))
            command_error = `PCIE_RECORD_V2_ERROR_UNSUPPORTED;
        else if (command_sink_data[63:32] == 0 || i_dfi_source_session == 0 ||
                 command_sink_data[63:32] != i_dfi_source_session)
            command_error = `PCIE_RECORD_V2_ERROR_SESSION;
    end
    always @(posedge i_dfi_clk or negedge dfi_local_reset_n) begin
        if (!dfi_local_reset_n) begin
            o_dfi_selected_version <= `PCIE_PROTOCOL_VERSION;
            o_dfi_selection_epoch <= 0;
            ack_source_data <= 0;
            ack_source_valid <= 0;
            decision_pending <= 0;
            reply_pending <= 0;
            decision_quiet <= 0;
        end else begin
            if (ack_source_valid && ack_source_ready) ack_source_valid <= 0;
            if (command_sink_valid && command_sink_ready) begin
                // Freeze the actual DFI boundary at command consumption.
                // The long global quiet cone terminates at one local bit;
                // it no longer drives the epoch/version register enables.
                // Unpublished ACK storage retains request/version/identity.
                ack_source_data <= {64'd0,command_sink_data[79:64],command_error,command_sink_data[63:0]};
                decision_quiet <= i_dfi_quiescent;
                decision_pending <= 1;
            end
            if (decision_pending) begin
                // USER remains busy through the real return ACK; production
                // uses that owner to inhibit new frame admission. Never
                // resample a later quiet/session value to change this choice.
                if (decision_error == 0 && decision_quiet) begin
                    o_dfi_selected_version <= ack_source_data[82:67];
                    o_dfi_selection_epoch <= o_dfi_selection_epoch + 1'b1;
                end
                if (decision_error == 0 && !decision_quiet)
                    ack_source_data[66:64] <= `PCIE_RECORD_V2_ERROR_BUSY;
                decision_pending <= 0;
                reply_pending <= 1;
            end
            if (reply_pending) begin
                ack_source_data <= {16'd0, next_epoch, next_version, next_header,
                                    decision_error, ack_source_data[63:0]};
                ack_source_valid <= 1;
                reply_pending <= 0;
            end
        end
    end
endmodule
