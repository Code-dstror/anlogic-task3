`timescale 1ns / 1ps

// Reassemble tight little-endian RAW10 bytes without emitting padding samples.
module raw10_frame_replay (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_start,
    input  wire [15:0]  i_width,
    input  wire [15:0]  i_height,
    input  wire [127:0] i_axis_tdata,
    input  wire [15:0]  i_axis_tkeep,
    input  wire         i_axis_tvalid,
    output wire         o_axis_tready,
    input  wire         i_axis_tlast,
    output wire [39:0]  o_data,
    output wire         o_valid,
    input  wire         i_ready,
    output wire         o_sof,
    output wire         o_eol,
    output wire         o_abort,
    output wire         o_done
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_ACTIVE = 2'd1;
    localparam [1:0] STATE_DRAIN = 2'd2;
    localparam [1:0] STATE_ABORT = 2'd3;

    reg [1:0] state;
    reg [1:0] state_next;
    reg [167:0] pack_data;
    reg [167:0] pack_data_next;
    reg [4:0] pack_bytes;
    reg [4:0] pack_bytes_next;
    reg [31:0] expected_bytes;
    reg [31:0] expected_bytes_next;
    reg [31:0] received_bytes;
    reg [31:0] received_bytes_next;
    reg [31:0] total_groups;
    reg [31:0] total_groups_next;
    reg [31:0] emitted_groups;
    reg [31:0] emitted_groups_next;
    reg [15:0] groups_per_row;
    reg [15:0] groups_per_row_next;
    reg [15:0] group_column;
    reg [15:0] group_column_next;
    reg abort_pulse;
    reg abort_pulse_next;
    reg done_pulse;
    reg done_pulse_next;
    reg transfer_fault;

    wire raw_fire;
    wire axis_fire;
    wire [4:0] bytes_after_pop;
    wire [31:0] remaining_bytes;
    wire [4:0] incoming_bytes;
    wire [15:0] expected_keep;
    wire final_input;
    wire [63:0] configured_samples;
    wire [63:0] configured_bytes;
    wire configured_valid;

    assign o_data = pack_data[39:0];
    assign o_valid = (state != STATE_IDLE) && (pack_bytes >= 5'd5);
    assign o_sof = (emitted_groups == 32'd0);
    assign o_eol = (group_column == groups_per_row - 16'd1);
    assign o_abort = abort_pulse;
    assign o_done = done_pulse;
    assign raw_fire = o_valid && i_ready;
    assign bytes_after_pop = raw_fire ? pack_bytes - 5'd5 : pack_bytes;
    assign o_axis_tready = (state == STATE_ACTIVE) &&
                          (bytes_after_pop <= 5'd5) && !i_start;
    assign axis_fire = i_axis_tvalid && o_axis_tready;
    assign remaining_bytes = expected_bytes - received_bytes;
    assign incoming_bytes = (remaining_bytes >= 32'd16) ?
                            5'd16 : remaining_bytes[4:0];
    assign expected_keep = (incoming_bytes == 5'd16) ? 16'hffff :
                          (16'hffff >> (16 - incoming_bytes));
    assign final_input = (remaining_bytes <= 32'd16);
    assign configured_samples = 64'd1 * i_width * i_height;
    assign configured_bytes = (configured_samples >> 2) * 64'd5;
    assign configured_valid = (i_width != 16'd0) &&
                              (i_width[1:0] == 2'd0) &&
                              (i_height != 16'd0) &&
                              (configured_samples <= 64'h7fffffff) &&
                              (configured_bytes <= 64'hffffffff);

    // A legal append has only six phases. Precompute both native-pop
    // cases from registered byte count so late i_ready never controls a
    // subtract-and-variable-shift chain. Writes above the owned byte count
    // are speculative: they cannot alter a presented native group, and an
    // accepted AXIS word overwrites those bytes on its original edge.
    // State/count alone discard errors and START; no late fault/start/AXIS
    // admission signal needs to clear or enable the 168-bit payload bank.
    reg [167:0] payload_without_pop, payload_with_pop;
    always @(*) begin
        payload_without_pop = pack_data;
        case (pack_bytes)
            0: payload_without_pop = {40'd0, i_axis_tdata};
            1: payload_without_pop = {32'd0, i_axis_tdata, pack_data[7:0]};
            2: payload_without_pop = {24'd0, i_axis_tdata, pack_data[15:0]};
            3: payload_without_pop = {16'd0, i_axis_tdata, pack_data[23:0]};
            4: payload_without_pop = {8'd0, i_axis_tdata, pack_data[31:0]};
            5: payload_without_pop = {i_axis_tdata, pack_data[39:0]};
            default: begin end
        endcase
        payload_with_pop = pack_data >> 40;
        case (pack_bytes)
            5: payload_with_pop = {40'd0, i_axis_tdata};
            6: payload_with_pop = {32'd0, i_axis_tdata, pack_data[47:40]};
            7: payload_with_pop = {24'd0, i_axis_tdata, pack_data[55:40]};
            8: payload_with_pop = {16'd0, i_axis_tdata, pack_data[63:40]};
            9: payload_with_pop = {8'd0, i_axis_tdata, pack_data[71:40]};
            10: payload_with_pop = {i_axis_tdata, pack_data[79:40]};
            default: begin end
        endcase
        pack_data_next = raw_fire ? payload_with_pop : payload_without_pop;
    end

    // Same-cycle removal precedes append, so at most 21 bytes are retained.
    always @(*) begin
        state_next = state;
        pack_bytes_next = pack_bytes;
        expected_bytes_next = expected_bytes;
        received_bytes_next = received_bytes;
        total_groups_next = total_groups;
        emitted_groups_next = emitted_groups;
        groups_per_row_next = groups_per_row;
        group_column_next = group_column;
        abort_pulse_next = 1'b0;
        done_pulse_next = 1'b0;
        transfer_fault = 1'b0;

        case (state)
            STATE_IDLE: begin
                pack_bytes_next = 5'd0;
                if (i_start) begin
                    if (configured_valid) begin
                        state_next = STATE_ACTIVE;
                        expected_bytes_next = configured_bytes[31:0];
                        received_bytes_next = 32'd0;
                        total_groups_next = configured_samples[31:2];
                        emitted_groups_next = 32'd0;
                        groups_per_row_next = {2'd0, i_width[15:2]};
                        group_column_next = 16'd0;
                    end else begin
                        abort_pulse_next = 1'b1;
                    end
                end
            end
            STATE_ACTIVE, STATE_DRAIN: begin
                transfer_fault = i_start;
                if (axis_fire) begin
                    if ((remaining_bytes == 32'd0) ||
                        (i_axis_tkeep != expected_keep) ||
                        (i_axis_tlast != final_input))
                        transfer_fault = 1'b1;
                end
                if (transfer_fault) begin
                    if (o_valid && !raw_fire) begin
                        // The presented group owns this reservoir and raster
                        // position until native acceptance, even on AXIS error.
                        state_next = STATE_ABORT;
                    end else begin
                        state_next = STATE_IDLE;
                        pack_bytes_next = 5'd0;
                        abort_pulse_next = 1'b1;
                    end
                end else begin
                    if (raw_fire) begin
                        pack_bytes_next = bytes_after_pop;
                        emitted_groups_next = emitted_groups + 32'd1;
                        group_column_next = o_eol ? 16'd0 :
                                            group_column + 16'd1;
                    end
                    if (axis_fire) begin
                        pack_bytes_next = pack_bytes_next + incoming_bytes;
                        received_bytes_next = received_bytes + incoming_bytes;
                        if (final_input)
                            state_next = STATE_DRAIN;
                    end
                    if (raw_fire && (emitted_groups == total_groups - 32'd1)) begin
                        if (((state == STATE_DRAIN) || (axis_fire && final_input)) &&
                            (pack_bytes_next == 5'd0)) begin
                            state_next = STATE_IDLE;
                            done_pulse_next = 1'b1;
                        end else begin
                            state_next = STATE_IDLE;
                            pack_bytes_next = 5'd0;
                            abort_pulse_next = 1'b1;
                        end
                    end
                end
            end
            STATE_ABORT: begin
                // Keep valid/data/SOF/EOL unchanged through stall. Only this
                // group's real handshake permits discard and the abort pulse.
                if (!o_valid || raw_fire) begin
                    state_next = STATE_IDLE;
                    pack_bytes_next = 5'd0;
                    abort_pulse_next = 1'b1;
                end
            end
            default: begin
                state_next = STATE_IDLE;
                pack_bytes_next = 5'd0;
                abort_pulse_next = 1'b1;
            end
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n)
            state <= STATE_IDLE;
        else
            state <= state_next;
    end

    // Reset cannot publish completion for a partially replayed frame.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            pack_data <= 168'd0;
            pack_bytes <= 5'd0;
            expected_bytes <= 32'd0;
            received_bytes <= 32'd0;
            total_groups <= 32'd0;
            emitted_groups <= 32'd0;
            groups_per_row <= 16'd0;
            group_column <= 16'd0;
            abort_pulse <= 1'b0;
            done_pulse <= 1'b0;
        end else begin
            pack_data <= pack_data_next;
            pack_bytes <= pack_bytes_next;
            expected_bytes <= expected_bytes_next;
            received_bytes <= received_bytes_next;
            total_groups <= total_groups_next;
            emitted_groups <= emitted_groups_next;
            groups_per_row <= groups_per_row_next;
            group_column <= group_column_next;
            abort_pulse <= abort_pulse_next;
            done_pulse <= done_pulse_next;
        end
    end

endmodule
