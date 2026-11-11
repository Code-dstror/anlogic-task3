`timescale 1ns / 1ps
`include "c2h_transport_limits.vh"

// Direct PH1A client0 C2H; complete packet RAM with two-entry prefetch.
// See c2h_rq_packetizer_spec.md for ownership, cancellation and reset limits.
module c2h_native_packetizer #(
    parameter [31:0] MAX_RECORD_BYTES = `C2H_MAX_RECORD_BYTES
) (
    input wire i_clk,
    input wire i_rst_n,
    input wire i_dma_enable,
    input wire i_source_abort,
    input wire i_cmd_valid,
    output wire o_cmd_ready,
    input wire [63:0] i_cmd_address,
    input wire [31:0] i_cmd_length,
    input wire [31:0] i_cmd_capacity,
    input wire [127:0] i_cmd_identity,
    input wire i_cancel_valid,
    input wire [127:0] i_cancel_identity,
    input wire [127:0] i_axis_tdata,
    input wire [15:0] i_axis_tkeep,
    input wire i_axis_tlast,
    input wire i_axis_tvalid,
    output wire o_axis_tready,
    output wire [127:0] o_tlp_data,
    output wire [63:0] o_tlp_address,
    output wire [7:0] o_tlp_byte_enable,
    output wire [12:0] o_tlp_byte_length,
    output wire [1:0] o_tlp_format,
    output wire o_tlp_header_valid, o_tlp_data_valid, o_tlp_end,
    input wire i_tlp_halt,
    output wire o_result_valid,
    input wire i_result_ready,
    output wire [127:0] o_result_identity,
    output wire [2:0] o_result_status,
    output wire [31:0] o_local_emitted_bytes
);

    localparam [3:0] ST_IDLE = 4'd0, ST_VALIDATE = 4'd1,
        ST_PLAN = 4'd2, ST_LOAD = 4'd3, ST_PREFETCH = 4'd4,
        ST_HEADER = 4'd5, ST_DATA = 4'd6, ST_READ = 4'd7,
        ST_PACKET_DONE = 4'd8, ST_DRAIN = 4'd9, ST_RESULT = 4'd10;
    localparam [2:0] STATUS_OK = 3'd0, STATUS_COMMAND = 3'd1,
        STATUS_CANCEL = 3'd2, STATUS_STREAM = 3'd3,
        STATUS_DISABLED = 3'd4, STATUS_INTERNAL = 3'd5, STATUS_SOURCE_ABORT = 3'd6;

    reg [3:0] state, state_next;
    reg [63:0] address;
    reg [31:0] record_length, capacity, input_remaining, emitted_bytes;
    reg [127:0] identity;
    reg [2:0] status;
    reg enabled_at_command, eof_seen;
    reg [7:0] packet_bytes, load_remaining;
    reg [2:0] write_index, read_index;
    wire [127:0] read_data;
    reg [127:0] front_data;
    reg front_valid, read_pending;
    reg [3:0] next_fetch;
    reg [7:0] planned_bytes;
    reg [15:0] expected_keep;
    reg [3:0] first_be, last_be, last_keep;

    wire cancel_match = i_cancel_valid && (i_cancel_identity == identity);
    wire abort_request = (status != STATUS_OK) || cancel_match || !i_dma_enable || i_source_abort;
    wire [64:0] end_address = {1'b0, address} + {33'd0, record_length};
    wire command_bad = (address[3:0] != 4'd0) || (record_length == 0) ||
        (record_length > capacity) || (record_length > MAX_RECORD_BYTES) || end_address[64];
    wire [12:0] page_room = 13'd4096 - {1'b0, address[11:0]};
    wire [4:0] beat_bytes = (load_remaining >= 16) ? 5'd16 : {1'b0, load_remaining[3:0]};
    wire expected_last = input_remaining <= 16;
    wire stream_bad = (i_axis_tkeep != expected_keep) || (i_axis_tlast != expected_last);
    wire input_fire = i_axis_tvalid && o_axis_tready;
    wire rq_fire = o_tlp_data_valid && !i_tlp_halt;
    wire [2:0] last_index = (packet_bytes - 8'd1) >> 4;
    wire [5:0] packet_dwords = ({1'b0, packet_bytes} + 9'd3) >> 2;

    assign o_cmd_ready = state == ST_IDLE;
    assign o_axis_tready = ((state == ST_LOAD) && !abort_request) || (state == ST_DRAIN && !i_source_abort);
    assign o_tlp_data_valid = i_rst_n && state == ST_DATA;
    assign o_tlp_header_valid = o_tlp_data_valid && read_index == 0;
    assign o_tlp_end = o_tlp_data_valid && read_index == last_index;
    assign o_tlp_data = front_data;
    assign o_tlp_address = address;
    assign o_tlp_byte_enable = {last_be,first_be};
    assign o_tlp_byte_length = {5'd0,packet_dwords,2'b00};
    assign o_tlp_format = address[63:32] != 0 ? 2'b11 : 2'b10;
    wire move_to_front = read_pending && (!front_valid || rq_fire);
    wire fetch = (state == ST_PREFETCH || state == ST_DATA) &&
        next_fetch <= {1'b0,last_index} && (!read_pending || move_to_front);
    wire prefetch_ready = front_valid && (read_pending || last_index == 0);
    assign o_result_valid = state == ST_RESULT;
    assign o_result_identity = identity;
    assign o_result_status = status;
    assign o_local_emitted_bytes = emitted_bytes;

    // Aligned addresses make all intermediate packet boundaries full stream beats.
    always @(*) begin
        planned_bytes = 8'd128;
        if (input_remaining < 128)
            planned_bytes = input_remaining[7:0];
        if (page_room < {5'd0, planned_bytes})
            planned_bytes = page_room[7:0];
        expected_keep = 16'hffff;
        if (beat_bytes < 16)
            expected_keep = (16'h0001 << beat_bytes) - 16'h0001;
        case (packet_bytes[1:0])
            2'd1: last_be = 4'b0001;
            2'd2: last_be = 4'b0011;
            2'd3: last_be = 4'b0111;
            default: last_be = 4'b1111;
        endcase
        first_be = 4'hf;
        if (packet_bytes <= 4) begin
            first_be = last_be;
            last_be = 4'h0;
        end
        case (packet_dwords[1:0])
            2'd1: last_keep = 4'b0001;
            2'd2: last_keep = 4'b0011;
            2'd3: last_keep = 4'b0111;
            default: last_keep = 4'b1111;
        endcase
    end

    always @(*) begin
        state_next = state;
        case (state)
            ST_IDLE: if (i_cmd_valid) state_next = ST_VALIDATE;
            ST_VALIDATE: begin
                if (command_bad || !enabled_at_command)
                    state_next = ST_RESULT;
                else if (i_source_abort) state_next = ST_RESULT;
                else if (abort_request) state_next = ST_DRAIN;
                else state_next = ST_PLAN;
            end
            ST_PLAN: begin
                if(i_source_abort) state_next=ST_RESULT;
                else if (abort_request) state_next = ST_DRAIN;
                else state_next = ST_LOAD;
            end
            ST_LOAD: begin
                if (abort_request) begin
                    if (eof_seen || i_source_abort) state_next = ST_RESULT;
                    else state_next = ST_DRAIN;
                end else if (input_fire) begin
                    if (stream_bad) begin
                        if (i_axis_tlast) state_next = ST_RESULT;
                        else state_next = ST_DRAIN;
                    end else if (load_remaining <= 16) state_next = ST_PREFETCH;
                end
            end
            ST_PREFETCH: begin
                if (abort_request) begin
                    if (eof_seen || i_source_abort) state_next = ST_RESULT;
                    else state_next = ST_DRAIN;
                end else if (prefetch_ready) state_next = ST_DATA;
            end
            ST_HEADER: if (rq_fire) state_next = ST_DATA;
            ST_DATA: if (rq_fire) begin
                if (read_index == last_index) state_next = ST_PACKET_DONE;
                else state_next = ST_DATA;
            end
            ST_READ: state_next = ST_DATA;
            ST_PACKET_DONE: begin
                if (eof_seen || i_source_abort) state_next = ST_RESULT;
                else if (abort_request) state_next = ST_DRAIN;
                else state_next = ST_PLAN;
            end
            ST_DRAIN: if (i_source_abort || (input_fire && i_axis_tlast)) state_next = ST_RESULT;
            ST_RESULT: if (i_result_ready) state_next = ST_IDLE;
            default: state_next = ST_RESULT;
        endcase
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) state <= ST_IDLE;
        else state <= state_next;
    end

    c2h_packet_ram packet_memory (
        .i_clk(i_clk), .i_write(state == ST_LOAD && input_fire && !stream_bad),
        .i_write_address(write_index), .i_write_data(i_axis_tdata),
        .i_read(fetch),
        .i_read_address(next_fetch[2:0]), .o_read_data(read_data)
    );

    // front plus the RAM's registered output are the only two payload slots.
    // A read reserves the pending slot before data becomes visible next cycle.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            front_valid<=0; read_pending<=0; next_fetch<=0;
        end else if (state==ST_IDLE || state==ST_PLAN || state==ST_PACKET_DONE ||
                     state==ST_DRAIN || state==ST_RESULT) begin
            front_valid<=0; read_pending<=0; next_fetch<=0;
        end else begin
            if (move_to_front) begin front_data<=read_data; front_valid<=1; end
            else if (rq_fire) front_valid<=0;
            if (move_to_front) read_pending<=0;
            if (fetch) begin read_pending<=1; next_fetch<=next_fetch+1'b1; end
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            address <= 0;
            record_length <= 0;
            capacity <= 0;
            input_remaining <= 0;
            emitted_bytes <= 0;
            identity <= 0;
            status <= STATUS_OK;
            enabled_at_command <= 0;
            eof_seen <= 0;
            packet_bytes <= 0;
            load_remaining <= 0;
            write_index <= 0;
            read_index <= 0;
        end else begin
            // The first abort cause is sticky until this command's result retires.
            if (state != ST_IDLE && state != ST_RESULT && status == STATUS_OK) begin
                if (cancel_match) status <= STATUS_CANCEL;
                else if (!i_dma_enable) status <= STATUS_DISABLED;
            end
            case (state)
                ST_IDLE: if (i_cmd_valid) begin
                    address <= i_cmd_address;
                    record_length <= i_cmd_length;
                    capacity <= i_cmd_capacity;
                    input_remaining <= i_cmd_length;
                    emitted_bytes <= 0;
                    identity <= i_cmd_identity;
                    status <= STATUS_OK;
                    enabled_at_command <= i_dma_enable;
                    eof_seen <= 0;
                end
                ST_VALIDATE: begin
                    if (command_bad) status <= STATUS_COMMAND;
                    else if (!enabled_at_command) status <= STATUS_DISABLED;
                end
                ST_PLAN: begin
                    packet_bytes <= planned_bytes;
                    load_remaining <= planned_bytes;
                    write_index <= 0;
                    read_index <= 0;
                end
                ST_LOAD: if (input_fire) begin
                    eof_seen <= i_axis_tlast;
                    if (stream_bad) status <= STATUS_STREAM;
                    else begin
                        input_remaining <= input_remaining - {27'd0, beat_bytes};
                        load_remaining <= load_remaining - {3'd0, beat_bytes};
                        write_index <= write_index + 1'b1;
                    end
                end
                ST_DATA: if (rq_fire && read_index != last_index)
                    read_index <= read_index + 1'b1;
                ST_PACKET_DONE: begin
                    address <= address + {56'd0, packet_bytes};
                    emitted_bytes <= emitted_bytes + {24'd0, packet_bytes};
                end
                ST_DRAIN: if (input_fire && i_axis_tlast) eof_seen <= 1;
                ST_PREFETCH, ST_HEADER, ST_READ, ST_RESULT: begin end
                default: status <= STATUS_INTERNAL;
            endcase
            if(i_source_abort && state!=ST_IDLE && state!=ST_RESULT)begin
                status<=STATUS_SOURCE_ABORT;
                eof_seen<=1;
            end
        end
    end
endmodule
