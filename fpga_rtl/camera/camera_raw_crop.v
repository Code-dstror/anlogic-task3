`timescale 1ns / 1ps
// Crop whole four-pixel groups while preserving a genuine ready/valid stream.
// Configuration is static until reset. An abort invalidates the entire frame.
module camera_raw_crop #(
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    parameter integer FIRST_ROW = 20,
    parameter integer FIRST_GROUP = 1
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire [39:0] i_raw_data,
    input wire i_raw_valid,
    output wire o_raw_ready,
    input wire i_raw_sof,
    input wire i_raw_eol,
    input wire i_raw_abort,
    output wire [39:0] o_data,
    output wire o_valid,
    input wire i_ready,
    output wire o_sof,
    output wire o_eol,
    output wire o_abort
);
    localparam integer LAST_GROUP = FIRST_GROUP + WIDTH/4 - 1;
    localparam integer LAST_ROW = FIRST_ROW + HEIGHT - 1;
    reg [12:0] row_count, group_count;
    reg active, completed, abort_o;
    reg [39:0] held_data;
    reg held_pending, held_release, held_sof, held_final_row;
    wire [12:0] row_now = i_raw_sof ? 13'd0 : row_count;
    wire [12:0] group_now = i_raw_sof ? 13'd0 : group_count;
    wire selected_row = row_now >= FIRST_ROW && row_now <= LAST_ROW;
    wire selected_group = group_now >= FIRST_GROUP && group_now <= LAST_GROUP;
    wire broken_start = i_raw_sof && active && !completed;
    wire selected = selected_row && selected_group;
    wire allowed = (active || i_raw_sof) && !i_raw_abort && !broken_start;
    wire input_transfer = i_raw_valid && o_raw_ready;
    wire direct_selected = allowed && selected && group_now < LAST_GROUP;
    wire output_transfer = o_valid && i_ready;
    assign o_data = held_release ? held_data : i_raw_data;
    assign o_valid = held_release || (i_raw_valid && direct_selected);
    assign o_sof = held_release ? held_sof :
                   (row_now == FIRST_ROW && group_now == FIRST_GROUP);
    assign o_eol = held_release;
    assign o_raw_ready = i_raw_abort ? 1'b1 : held_release ? 1'b0 :
                         ((!allowed || !selected) ? 1'b1 :
                          ((group_now == LAST_GROUP) ? !held_pending : i_ready));
    assign o_abort = abort_o;
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            row_count <= 0;
            group_count <= 0;
            active <= 0;
            completed <= 0;
            abort_o <= 0;
            held_data <= 0;
            held_pending <= 0;
            held_release <= 0;
            held_sof <= 0;
            held_final_row <= 0;
        end else begin
            abort_o <= 0;
            if (output_transfer && held_release) begin
                held_pending <= 0;
                held_release <= 0;
                if (held_final_row)
                    completed <= 1;
            end
            if (input_transfer) begin
                if (i_raw_sof) begin
                    active <= 1;
                    completed <= 0;
                end
                if (i_raw_eol) begin
                    row_count <= row_now + 1'b1;
                    group_count <= 0;
                end else begin
                    row_count <= row_now;
                    group_count <= group_now + 1'b1;
                end
                if (allowed && selected && group_now == LAST_GROUP) begin
                    held_data <= i_raw_data;
                    held_pending <= 1;
                    held_sof <= row_now == FIRST_ROW && group_now == FIRST_GROUP;
                    held_final_row <= row_now == LAST_ROW;
                    if (i_raw_eol)
                        held_release <= 1;
                end else if (i_raw_eol && held_pending) begin
                    held_release <= 1;
                end
                if (i_raw_abort || broken_start ||
                    (allowed && selected_row && i_raw_eol && group_now < LAST_GROUP) ||
                    (allowed && (row_now == 8191 || group_now == 8191))) begin
                    abort_o <= 1;
                    active <= 0;
                    completed <= 0;
                    held_pending <= 0;
                    held_release <= 0;
                end
            end
        end
    end
endmodule
