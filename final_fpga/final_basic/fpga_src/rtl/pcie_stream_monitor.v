`timescale 1ns / 1ps
// Retained PCIe user-clock evidence. This module never controls the data path.
module pcie_stream_monitor #(
    parameter integer LOCAL_CLEAR_ENABLE = 0
) (
    input wire i_clk,
    input wire i_debug_rst_n,
    input wire i_clear,
    input wire [15:0] i_flags,
    input wire [15:0] i_keep,
    input wire [7:0] i_c2h_status,
    input wire [31:0] i_sequence,
    input wire [31:0] i_payload_length,
    output wire [511:0] o_status,
    output wire [95:0] o_sample,
    output wire o_error_event,
    input wire i_clear_local,
    output wire [31:0] o_fault_causes,
    output wire [255:0] o_fault_context
);
    reg clear_meta, clear_sync, clear_seen;
    reg [15:0] previous_flags;
    reg frame_active;
    reg [31:0] cycle_count, frame_sequence, expected_bytes, accepted_bytes;
    reg [31:0] completed_count, abort_count;
    reg first_fault_valid, running_fall_seen, abort_seen;
    reg [7:0] first_cause;
    reg [31:0] first_cycle, first_sequence, first_expected, first_bytes;
    reg [31:0] first_running_fall_cycle, first_abort_cycle;
    reg [15:0] first_flags, first_keep;
    wire clear_now = clear_sync != clear_seen ||
        (LOCAL_CLEAR_ENABLE != 0 && i_clear_local);
    wire output_fire = i_flags[1] && i_flags[2];
    wire active_now = frame_active || i_flags[13] || i_flags[14];
    wire running_fall = previous_flags[0] && !i_flags[0];
    wire [7:0] cause = {
        i_flags[11] && !previous_flags[11],
        i_flags[12], i_flags[10],
        active_now && previous_flags[7] && !i_flags[7],
        active_now && previous_flags[6] && !i_flags[6],
        active_now && previous_flags[4] && !i_flags[4],
        active_now && previous_flags[5] && !i_flags[5],
        active_now && running_fall
    };
    // Balanced popcount counts only accepted byte lanes, including a short tail.
    wire [2:0] keep_zero = {2'd0,i_keep[0]} + {2'd0,i_keep[1]} +
                           {2'd0,i_keep[2]} + {2'd0,i_keep[3]};
    wire [2:0] keep_one = {2'd0,i_keep[4]} + {2'd0,i_keep[5]} +
                          {2'd0,i_keep[6]} + {2'd0,i_keep[7]};
    wire [2:0] keep_two = {2'd0,i_keep[8]} + {2'd0,i_keep[9]} +
                          {2'd0,i_keep[10]} + {2'd0,i_keep[11]};
    wire [2:0] keep_three = {2'd0,i_keep[12]} + {2'd0,i_keep[13]} +
                            {2'd0,i_keep[14]} + {2'd0,i_keep[15]};
    wire [4:0] byte_count = {2'd0,keep_zero} + {2'd0,keep_one} +
                            {2'd0,keep_two} + {2'd0,keep_three};
    wire [31:0] transfer_bytes = output_fire ? {27'd0,byte_count} : 32'd0;
    wire [31:0] bytes_after_transfer = (i_flags[8] ? 32'd0 : accepted_bytes) + transfer_bytes;
    wire [31:0] current_sequence = i_flags[8] ? i_sequence : frame_sequence;
    wire [31:0] current_expected = i_flags[8] ? i_payload_length + 32'd64 : expected_bytes;
    assign o_error_event = (|cause) && !clear_now;
    assign o_fault_causes = {24'd0,cause};
    assign o_fault_context = {96'd0,current_sequence,current_expected,
        bytes_after_transfer,{i_keep,i_flags},cycle_count};
    assign o_sample = {cycle_count, bytes_after_transfer, i_keep, i_flags};
    // Word indices ascend from the least-significant end of the packed status.
    assign o_status = {
        first_abort_cycle, first_running_fall_cycle, {first_keep,first_flags},
        first_bytes, first_expected, first_sequence, first_cycle,
        {first_fault_valid,13'd0,abort_seen,running_fall_seen,8'd0,first_cause},
        abort_count, completed_count, accepted_bytes, expected_bytes,
        frame_sequence, cycle_count, {i_c2h_status,8'd0,i_flags},32'h50435331
    };
    always @(posedge i_clk or negedge i_debug_rst_n) begin
        if (!i_debug_rst_n) begin
            clear_meta<=0; clear_sync<=0; clear_seen<=0; previous_flags<=0;
            frame_active<=0; cycle_count<=0; frame_sequence<=0; expected_bytes<=0;
            accepted_bytes<=0; completed_count<=0; abort_count<=0;
            first_fault_valid<=0; running_fall_seen<=0; abort_seen<=0;
            first_cause<=0; first_cycle<=0; first_sequence<=0; first_expected<=0;
            first_bytes<=0; first_running_fall_cycle<=0; first_abort_cycle<=0;
            first_flags<=0; first_keep<=0;
        end else begin
            clear_meta<=i_clear; clear_sync<=clear_meta;
            previous_flags<=i_flags;
            cycle_count<=cycle_count+1'b1;
            if (clear_now) begin
                clear_seen<=clear_sync;
                frame_active<=0; frame_sequence<=0; expected_bytes<=0;
                accepted_bytes<=0; completed_count<=0; abort_count<=0;
                first_fault_valid<=0; running_fall_seen<=0; abort_seen<=0;
                first_cause<=0; first_cycle<=0; first_sequence<=0; first_expected<=0;
                first_bytes<=0; first_running_fall_cycle<=0; first_abort_cycle<=0;
                first_flags<=0; first_keep<=0;
            end else begin
                if (i_flags[8]) begin
                    frame_active<=1;
                    frame_sequence<=i_sequence;
                    expected_bytes<=i_payload_length+32'd64;
                end
                if (i_flags[8] || output_fire) accepted_bytes<=bytes_after_transfer;
                if (i_flags[9]) begin
                    completed_count<=completed_count+1'b1;
                    frame_active<=0;
                end
                if (i_flags[10]) begin
                    abort_count<=abort_count+1'b1;
                    frame_active<=0;
                end
                if (!i_flags[6] || !i_flags[7]) frame_active<=0;
                if (active_now && running_fall && !running_fall_seen) begin
                    running_fall_seen<=1;
                    first_running_fall_cycle<=cycle_count;
                end
                if (i_flags[10] && !abort_seen) begin
                    abort_seen<=1;
                    first_abort_cycle<=cycle_count;
                end
                if (o_error_event && !first_fault_valid) begin
                    first_fault_valid<=1;
                    first_cause<=cause;
                    first_cycle<=cycle_count;
                    first_sequence<=current_sequence;
                    first_expected<=current_expected;
                    first_bytes<=bytes_after_transfer;
                    first_flags<=i_flags;
                    first_keep<=i_keep;
                end
            end
        end
    end
endmodule
