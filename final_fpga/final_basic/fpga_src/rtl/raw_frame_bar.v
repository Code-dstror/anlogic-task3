`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// RAW command owner and retryable block cache, entirely in the PCIe user domain.
module raw_frame_bar #(
    parameter integer DESCRIPTOR_ENABLE = 0,
    parameter integer MASK_EXPORT_ENABLE = 0
) (
    input wire i_clk, input wire i_rst_n,
    input wire i_session_ready,
    input wire i_write_valid, input wire [11:0] i_write_offset,
    input wire [31:0] i_write_data, input wire [3:0] i_write_strobes,
    output wire [1:0] o_write_response,
    input wire i_read_valid, input wire [11:0] i_read_offset,
    output reg o_read_response_valid, output reg [31:0] o_read_data,
    output reg [1:0] o_read_response,
    output reg [31:0] o_command_session,
    output reg [127:0] o_command_data, output reg o_command_valid,
    input wire i_command_ready,
    input wire [127:0] i_response_data, input wire [1:0] i_response_kind,
    input wire i_response_valid, output wire o_response_ready,
    input wire [127:0] i_block_data, input wire [15:0] i_block_keep,
    input wire i_block_last, input wire i_block_error, input wire i_block_valid,
    output wire o_block_ready, output reg o_retire_toggle
);
    reg [31:0] request_camera, request_slot, request_generation, request_session;
    reg [31:0] request_offset, request_length, request_sequence;
    reg [31:0] active_sequence, response_sequence, session_generation;
    reg [2:0] active_operation;
    reg busy, done, cache_valid, read_failure;
    reg [3:0] error_code, accepted_code;
    reg [31:0] descriptor_generation, descriptor_sequence, descriptor_epoch;
    reg [31:0] descriptor_bytes, descriptor_samples;
    reg [15:0] descriptor_width, descriptor_height;
    reg descriptor_camera, descriptor_pinned;
    reg [1:0] descriptor_slot;
    reg [2:0] descriptor_state;
    reg [127:0] pending_word0, pending_word1;
    reg [31:0] pending_session, descriptor_session;
    reg [7:0] pending_format, descriptor_format;
    reg [2:0] pending_source_type, descriptor_source_type;
    reg active_mask_target;
    reg [31:0] capture_count, read_count, drop_count, hardware_error_count;
    reg [31:0] cache_byte_count, active_length;
    reg [7:0] cache_write_index;
    reg [1:0] session_sync;
    reg session_previous;
    reg [1:0] read_pipe;
    reg read_cache, read_allowed;
    reg [1:0] read_lane;
    reg [31:0] register_read_data;
    wire [139:0] cache_output;
    wire [127:0] clean_block;
    wire block_fire = i_block_valid && o_block_ready;
    wire cache_request = i_read_offset >= `PCIE_RAW_CACHE_BASE &&
                         i_read_offset < `PCIE_RAW_CACHE_BASE + `PCIE_RAW_CACHE_BYTES;
    wire [11:0] cache_offset = i_read_offset - `PCIE_RAW_CACHE_BASE;
    wire parameter_write = (i_write_offset >= `PCIE_REG_RAW_REQUEST_CAMERA &&
                           i_write_offset <= `PCIE_REG_RAW_REQUEST_SEQUENCE) ||
                           (DESCRIPTOR_ENABLE && i_write_offset == `PCIE_REG_RAW_REQUEST_SESSION);
    wire command_write = i_write_offset == `PCIE_REG_RAW_COMMAND;
    // Target zero keeps its original full-word legality check. No reserved bit
    // becomes legal merely because the optional mask target is compiled.
    wire mask_command = MASK_EXPORT_ENABLE != 0 && DESCRIPTOR_ENABLE != 0 &&
        i_write_data >= `PCIE_MASK_EXPORT_COMMAND_TARGET_MASK &&
        i_write_data <= (`PCIE_MASK_EXPORT_COMMAND_TARGET_MASK + `PCIE_RAW_COMMAND_FETCH);
    wire legal_command = i_write_data <= `PCIE_RAW_COMMAND_REPLAY || mask_command;
    assign o_write_response = !busy && (parameter_write || command_write) &&
                              i_write_offset[1:0] == 0 ? 2'b00 : 2'b10;
    assign o_response_ready = 1'b1;
    assign o_block_ready = busy && active_operation == `PCIE_RAW_COMMAND_FETCH;

    function [31:0] merge_bytes;
        input [31:0] old_data, new_data;
        input [3:0] strobes;
        integer lane;
        begin
            merge_bytes = old_data;
            for (lane = 0; lane < 4; lane = lane + 1)
                if (strobes[lane]) merge_bytes[lane*8 +: 8] = new_data[lane*8 +: 8];
        end
    endfunction
    function [4:0] byte_count;
        input [15:0] keep;
        integer lane;
        begin
            byte_count = 0;
            for (lane = 0; lane < 16; lane = lane + 1)
                byte_count = byte_count + keep[lane];
        end
    endfunction
    genvar bank, byte_lane;
    generate
        for (byte_lane = 0; byte_lane < 16; byte_lane = byte_lane + 1) begin : g_mask
            assign clean_block[byte_lane*8 +: 8] = i_block_keep[byte_lane] ?
                                                    i_block_data[byte_lane*8 +: 8] : 8'd0;
        end
        for (bank = 0; bank < 7; bank = bank + 1) begin : g_cache
            wire [139:0] padded_block = {12'd0,clean_block};
            // Reuse the registered TD dual-port ERAM configuration; no inferred cache RAM.
            isp_line_ram_20x1024_ip u_ram (
                .clka(i_clk), .addra({2'd0,cache_write_index}),
                .dia(padded_block[bank*20 +: 20]), .cea(1'b1),
                .wea(block_fire && !i_block_error && cache_write_index < 160), .doa(),
                .addrb({2'd0,cache_offset[11:4]}), .dib(20'd0),
                .ceb(i_read_valid && cache_request), .web(1'b0),
                .dob(cache_output[bank*20 +: 20])
            );
        end
    endgenerate

    // Session identity survives application reset while the PCIe endpoint remains alive.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            session_sync <= 0;
            session_previous <= 0;
            session_generation <= 0;
        end else begin
            session_sync <= {session_sync[0],i_session_ready};
            session_previous <= session_sync[1];
            if (session_sync[1] && !session_previous)
                session_generation <= session_generation + 1'b1;
        end
    end

    // Parameter writes remain shadow state until the single command doorbell.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            request_session <= 0; o_command_session <= 0;
            pending_word0 <= 0; pending_word1 <= 0; pending_session <= 0; pending_format <= 0;
            descriptor_session <= 0; descriptor_format <= 0;
            pending_source_type <= 0; descriptor_source_type <= 0; active_mask_target <= 0;
            request_camera <= 0; request_slot <= 0; request_generation <= 0;
            request_offset <= 0; request_length <= 0; request_sequence <= 0;
            active_sequence <= 0; response_sequence <= 0; active_operation <= 0;
            busy <= 0; done <= 0; cache_valid <= 0; read_failure <= 0;
            error_code <= 0; accepted_code <= 0; o_command_valid <= 0;
            o_command_data <= 0; o_retire_toggle <= 0;
            descriptor_generation <= 0; descriptor_sequence <= 0; descriptor_epoch <= 0;
            descriptor_bytes <= 0; descriptor_samples <= 0;
            descriptor_width <= 0; descriptor_height <= 0;
            descriptor_camera <= 0; descriptor_slot <= 0;
            descriptor_state <= 0; descriptor_pinned <= 0;
            capture_count <= 0; read_count <= 0; drop_count <= 0; hardware_error_count <= 0;
            cache_byte_count <= 0; cache_write_index <= 0; active_length <= 0;
        end else begin
            if (o_command_valid && i_command_ready) o_command_valid <= 0;
            if (i_write_valid && o_write_response == 0) begin
                case (i_write_offset)
                    `PCIE_REG_RAW_REQUEST_SESSION: request_session <= merge_bytes(request_session,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_CAMERA: request_camera <= merge_bytes(request_camera,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_SLOT: request_slot <= merge_bytes(request_slot,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_GENERATION: request_generation <= merge_bytes(request_generation,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_OFFSET: request_offset <= merge_bytes(request_offset,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_LENGTH: request_length <= merge_bytes(request_length,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_REQUEST_SEQUENCE: request_sequence <= merge_bytes(request_sequence,i_write_data,i_write_strobes);
                    `PCIE_REG_RAW_COMMAND: begin
                        active_sequence <= request_sequence;
                        active_operation <= i_write_data[2:0];
                        active_mask_target <= mask_command;
                        active_length <= request_length;
                        done <= 0; cache_valid <= 0; read_failure <= 0;
                        error_code <= 0; cache_byte_count <= 0; cache_write_index <= 0;
                        if (!session_sync[1] || request_sequence == 0 ||
                            request_sequence == active_sequence || i_write_strobes != 4'hf ||
                            !legal_command || request_camera > 1 || request_slot > 3 ||
                            (mask_command && request_slot >= `PCIE_MASK_EXPORT_SLOTS_PER_CAMERA)) begin
                            done <= 1;
                            response_sequence <= request_sequence;
                            error_code <= !session_sync[1] ? `PCIE_RAW_ERROR_RESET : `PCIE_RAW_ERROR_INVALID;
                        end else begin
                            busy <= 1;
                            o_command_valid <= 1;
                            o_command_session <= DESCRIPTOR_ENABLE ? request_session : 0;
                            o_command_data <= {25'd0,mask_command,request_length,request_offset,
                                               request_generation,request_slot[1:0],
                                               request_camera[0],i_write_data[2:0]};
                        end
                    end
                    default: begin end
                endcase
            end
            if (i_response_valid) begin
                case (i_response_kind)
                    0: pending_word0 <= i_response_data;
                    1: begin
                        if (DESCRIPTOR_ENABLE && i_response_data[127]) begin
                            pending_session <= i_response_data[31:0];
                            pending_format <= i_response_data[39:32];
                            pending_source_type <= active_mask_target ? i_response_data[42:40] : 3'd0;
                        end else begin
                            pending_word1 <= i_response_data;
                            accepted_code <= i_response_data[74:71];
                        end
                    end
                    2: begin
                        descriptor_sequence <= pending_word0[31:0];
                        descriptor_epoch <= pending_word0[63:32];
                        descriptor_generation <= pending_word0[95:64];
                        descriptor_bytes <= pending_word0[127:96];
                        descriptor_width <= pending_word1[15:0]; descriptor_height <= pending_word1[31:16];
                        descriptor_samples <= pending_word1[63:32]; descriptor_slot <= pending_word1[65:64];
                        descriptor_camera <= pending_word1[66]; descriptor_state <= pending_word1[69:67];
                        descriptor_pinned <= pending_word1[70];
                        descriptor_session <= DESCRIPTOR_ENABLE ? pending_session : 0;
                        descriptor_format <= DESCRIPTOR_ENABLE ? pending_format : 1;
                        descriptor_source_type <= active_mask_target ? pending_source_type : 3'd0;
                        capture_count <= i_response_data[31:0]; read_count <= i_response_data[63:32];
                        drop_count <= i_response_data[95:64]; hardware_error_count <= i_response_data[127:96];
                        if (accepted_code != 0 || (active_operation != `PCIE_RAW_COMMAND_FETCH &&
                                                  active_operation != `PCIE_RAW_COMMAND_REPLAY)) begin
                            busy <= 0; done <= 1; error_code <= accepted_code;
                            response_sequence <= active_sequence;
                        end
                    end
                    3: begin
                        busy <= 0; done <= 1; response_sequence <= active_sequence;
                        error_code <= read_failure ? `PCIE_RAW_ERROR_AXI : i_response_data[3:0];
                        cache_valid <= !read_failure && i_response_data[3:0] == 0 &&
                                       active_operation == `PCIE_RAW_COMMAND_FETCH;
                    end
                endcase
            end
            if (block_fire) begin
                if (i_block_error || cache_write_index >= 160) read_failure <= 1;
                cache_byte_count <= cache_byte_count + byte_count(i_block_keep);
                cache_write_index <= cache_write_index + 1'b1;
                if (i_block_last) begin
                    if (cache_byte_count + byte_count(i_block_keep) != active_length)
                        read_failure <= 1;
                    o_retire_toggle <= !o_retire_toggle;
                end
            end
            if (!session_sync[1]) begin
                cache_valid <= 0; o_command_valid <= 0;
                if (busy) begin
                    busy <= 0; done <= 1; error_code <= `PCIE_RAW_ERROR_RESET;
                    response_sequence <= active_sequence;
                end
            end
        end
    end

    // All extension reads use a two-cycle response, including the synchronous ERAM port.
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            read_pipe <= 0; read_cache <= 0; read_allowed <= 0; read_lane <= 0;
            register_read_data <= 0; o_read_response_valid <= 0;
            o_read_data <= 0; o_read_response <= 0;
        end else begin
            read_pipe <= {read_pipe[0],i_read_valid};
            o_read_response_valid <= read_pipe[1];
            if (i_read_valid) begin
                read_cache <= cache_request;
                read_lane <= i_read_offset[3:2];
                read_allowed <= i_read_offset[1:0] == 0;
                register_read_data <= 0;
                if (cache_request) read_allowed <= cache_valid && !busy &&
                                                    cache_offset < cache_byte_count && i_read_offset[1:0] == 0;
                else case (i_read_offset)
                    `PCIE_REG_RAW_MAGIC: register_read_data <= `PCIE_RAW_MAGIC;
                    `PCIE_REG_RAW_ABI_VERSION: register_read_data <= `PCIE_RAW_ABI_VERSION;
                    `PCIE_REG_RAW_CONFIG: register_read_data <= `PCIE_RAW_CONFIG;
                    `PCIE_REG_RAW_MAX_BLOCK: register_read_data <= `PCIE_RAW_MAX_BLOCK;
                    `PCIE_REG_RAW_MAX_FRAME: register_read_data <= `PCIE_RAW_MAX_FRAME;
                    `PCIE_REG_RAW_STATUS: register_read_data <= {27'd0,session_sync[1],cache_valid,(error_code!=0),done,busy};
                    `PCIE_REG_RAW_RESPONSE_SEQUENCE: register_read_data <= response_sequence;
                    `PCIE_REG_RAW_ERROR: register_read_data <= {28'd0,error_code};
                    `PCIE_REG_RAW_REQUEST_SESSION: register_read_data <= request_session;
                    `PCIE_REG_RAW_DESC_SESSION: register_read_data <= descriptor_session;
                    `PCIE_REG_RAW_DESC_FORMAT: register_read_data <= {24'd0,descriptor_format};
                    `PCIE_REG_RAW_EXPORT_FEATURES: register_read_data <=
                        MASK_EXPORT_ENABLE != 0 && DESCRIPTOR_ENABLE != 0 ? `PCIE_MASK_EXPORT_FEATURE_MASK : 0;
                    `PCIE_REG_RAW_EXPORT_SOURCE_TYPE: register_read_data <= {29'd0,descriptor_source_type};
                    `PCIE_REG_RAW_DESC_CAMERA: register_read_data <= {31'd0,descriptor_camera};
                    `PCIE_REG_RAW_DESC_SLOT: register_read_data <= {30'd0,descriptor_slot};
                    `PCIE_REG_RAW_DESC_GENERATION: register_read_data <= descriptor_generation;
                    `PCIE_REG_RAW_DESC_FRAME_SEQUENCE: register_read_data <= descriptor_sequence;
                    `PCIE_REG_RAW_DESC_MODE_EPOCH: register_read_data <= descriptor_epoch;
                    `PCIE_REG_RAW_DESC_WIDTH: register_read_data <= {16'd0,descriptor_width};
                    `PCIE_REG_RAW_DESC_HEIGHT: register_read_data <= {16'd0,descriptor_height};
                    `PCIE_REG_RAW_DESC_SAMPLE_COUNT: register_read_data <= descriptor_samples;
                    `PCIE_REG_RAW_DESC_PACKED_BYTES: register_read_data <= descriptor_bytes;
                    `PCIE_REG_RAW_DESC_STATE: register_read_data <= {23'd0,descriptor_pinned,5'd0,descriptor_state};
                    `PCIE_REG_RAW_CACHE_VALID_BYTES: register_read_data <= cache_valid ? cache_byte_count : 0;
                    `PCIE_REG_RAW_SESSION: register_read_data <= session_generation;
                    `PCIE_REG_RAW_CAPTURE_COUNT: register_read_data <= capture_count;
                    `PCIE_REG_RAW_READ_COUNT: register_read_data <= read_count;
                    `PCIE_REG_RAW_DROP_COUNT: register_read_data <= drop_count;
                    `PCIE_REG_RAW_ERROR_COUNT: register_read_data <= hardware_error_count;
                    default: read_allowed <= 0;
                endcase
            end
            if (read_pipe[1]) begin
                o_read_response <= read_allowed ? 2'b00 : 2'b10;
                o_read_data <= !read_allowed ? 0 : read_cache ?
                               cache_output[read_lane*32 +: 32] : register_read_data;
            end
        end
    end
endmodule
