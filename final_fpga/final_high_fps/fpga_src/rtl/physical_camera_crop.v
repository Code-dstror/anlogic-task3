`timescale 1ns / 1ps

// 按行列范围裁剪相机 RAW 像素流并传递帧异常
module physical_camera_crop #(
    // 裁剪尺寸
    parameter integer WIDTH = 1920,
    parameter integer HEIGHT = 1080,
    // 裁剪起点
    parameter integer FIRST_ROW = 20,
    parameter integer FIRST_GROUP = 1,
    parameter integer UHD_WIDTH=0,UHD_HEIGHT=0,UHD_FIRST_ROW=16,UHD_FIRST_GROUP=3
) (
    // 时钟与复位
    input wire i_clk,
    input wire i_rst_n,
    // RAW 像素流
    input wire [39:0] i_raw_data,
    input wire i_raw_valid,
    output wire o_raw_ready,
    input wire i_raw_sof,
    input wire [31:0] i_raw_sequence,
    input wire i_raw_identity_valid,
    output wire [31:0] o_sequence,
    output wire o_identity_valid,
    input wire i_raw_eol,
    input wire i_raw_abort,
    output wire [39:0] o_data,
    output wire o_valid,
    input wire i_ready,
    output wire o_sof,
    output wire o_eol,
    output wire o_abort,
    input wire i_uhd
);
    localparam integer UHD_ENABLED=UHD_WIDTH!=0&&UHD_HEIGHT!=0;
    reg frame_uhd;
    wire selected_uhd=UHD_ENABLED!=0&&(i_raw_sof?i_uhd:frame_uhd);
    wire [12:0] first_group=selected_uhd?UHD_FIRST_GROUP:FIRST_GROUP;
    wire [12:0] first_row=selected_uhd?UHD_FIRST_ROW:FIRST_ROW;
    wire [12:0] last_group=selected_uhd?UHD_FIRST_GROUP+UHD_WIDTH/4-1:FIRST_GROUP+WIDTH/4-1;
    wire [12:0] last_row=selected_uhd?UHD_FIRST_ROW+UHD_HEIGHT-1:FIRST_ROW+HEIGHT-1;
    reg [12:0] row_count, group_count;
    reg [31:0] frame_sequence;
    reg frame_identity_valid;
    reg active, completed, abort_o, abort_pending;
    reg [39:0] held_data;
    reg held_pending, held_release, held_sof, held_final_row;
    assign o_sequence=(!held_release && i_raw_sof) ? i_raw_sequence : frame_sequence;
    assign o_identity_valid=(!held_release && i_raw_sof) ? i_raw_identity_valid : frame_identity_valid;
    wire [12:0] row_now = i_raw_sof ? 13'd0 : row_count;
    wire [12:0] group_now = i_raw_sof ? 13'd0 : group_count;
    wire selected_row = row_now >= first_row && row_now <= last_row;
    wire selected_group = group_now >= first_group && group_now <= last_group;
    wire broken_start = i_raw_sof && active && !completed;
    wire selected = selected_row && selected_group;
    wire allowed = (active || i_raw_sof) && !i_raw_abort && !broken_start;
    wire input_transfer = i_raw_valid && o_raw_ready;
    wire direct_selected = allowed && selected && group_now < last_group;
    wire output_transfer = o_valid && i_ready;
    assign o_data = held_release ? held_data : i_raw_data;
    assign o_valid = held_release || (i_raw_valid && direct_selected);
    assign o_sof = held_release ? held_sof :
                   (row_now == first_row && group_now == first_group);
    assign o_eol = held_release;
    assign o_raw_ready = abort_pending ? 1'b0 : i_raw_abort ? 1'b1 : held_release ? 1'b0 :
                         ((!allowed || !selected) ? 1'b1 :
                          ((group_now == last_group) ? !held_pending : i_ready));
    assign o_abort = abort_o;
    // 仅在输入输出握手时推进裁剪位置并保持待发送数据
    always @(posedge i_clk) begin
        if (!i_rst_n) begin
            row_count <= 0;frame_sequence<=0;frame_identity_valid<=0;frame_uhd<=0;
            group_count <= 0;
            active <= 0;
            completed <= 0;
            abort_o <= 0;
            abort_pending <= 0;
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
                if (abort_pending)begin
                    abort_o <= 1;
                    abort_pending <= 0;
                    completed <= 0;
                end else if (held_final_row)
                    completed <= 1;
            end
            if (input_transfer) begin
                if (i_raw_sof) begin
                    frame_sequence<=i_raw_sequence;frame_identity_valid<=i_raw_identity_valid;frame_uhd<=UHD_ENABLED!=0&&i_uhd;
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
                if (allowed && selected && group_now == last_group) begin
                    held_data <= i_raw_data;
                    held_pending <= 1;
                    held_sof <= row_now == first_row && group_now == first_group;
                    held_final_row <= row_now == last_row;
                    if (i_raw_eol)
                        held_release <= 1;
                end else if (i_raw_eol && held_pending) begin
                    held_release <= 1;
                end
                if (i_raw_abort || broken_start ||
                    (allowed && selected_row && i_raw_eol && group_now < last_group) ||
                    (allowed && (row_now == 8191 || group_now == 8191))) begin
                    active <= 0;
                    completed <= 0;
                    if(held_release && !output_transfer)begin
                        // Ordinary ABORT may retire only after the group
                        // already presented to the consumer really transfers.
                        abort_pending <= 1;
                    end else begin
                        abort_o <= 1;
                        held_pending <= 0;
                        held_release <= 0;
                    end
                end
            end
        end
    end
endmodule
