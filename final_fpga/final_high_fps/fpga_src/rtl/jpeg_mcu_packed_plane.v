`timescale 1ns / 1ps

// Five adjacent bytes per existing official RAM40 word; three read banks.
module jpeg_mcu_packed_plane #(
    parameter integer MAX_SAMPLES = 1920,
    parameter integer IN_BYTES = 4,
    parameter integer FULL_ROW_ENABLE = 0,
    parameter integer PACKED_READ_ENABLE = 0,
    parameter integer REGISTER_WRITE_PORTS = 0
) (
    input wire clk, rst_n,
    input wire wr_valid, wr_bank,
    input wire [2:0] wr_row,
    input wire wr_first, wr_last,
    input wire [IN_BYTES*8-1:0] wr_data,
    input wire rd_enable, rd_bank,
    input wire [2:0] rd_row,
    input wire [12:0] rd_start,
    output reg [63:0] rd_data,
    output wire [119:0] o_bank_words,
    output wire [14:0] o_byte_select
);
    localparam integer ROW_WORDS = (MAX_SAMPLES + 4) / 5;
    localparam integer WORDS = 16 * ROW_WORDS;
    localparam integer BANK_WORDS = (WORDS + 2) / 3;
    localparam integer CELLS = (BANK_WORDS + 511) / 512;
    reg [31:0] carry;
    reg [2:0] carry_bytes;
    reg [14:0] next_word;
    reg tail_pending;
    reg [39:0] tail_data;
    reg [14:0] tail_word;
    reg [1:0] next_write_bank;
    reg [14:0] next_write_address;
    wire [14:0] row_base = {wr_bank,wr_row} * ROW_WORDS;
    wire [2:0] prefix_bytes = wr_first ? 3'd0 : carry_bytes;
    wire [3:0] joined_bytes = {1'b0,prefix_bytes} + IN_BYTES;
    wire [63:0] joined = (wr_first ? 64'd0 : {32'd0,carry}) |
        ({{(64-IN_BYTES*8){1'b0}},wr_data} << (prefix_bytes * 8));
    wire [14:0] current_word = wr_first ? row_base : next_word;
    wire full_word = wr_valid && joined_bytes >= 5;
    wire partial_word = wr_valid && wr_last && joined_bytes < 5;
    wire write_enable = rst_n && (tail_pending || full_word || partial_word);
    wire [14:0] write_word = tail_pending ? tail_word : current_word;
    wire [39:0] write_data = tail_pending ? tail_data : joined[39:0];
    // Complete rows have a multiple of three words, hence start in bank zero.
    wire [1:0] write_bank = FULL_ROW_ENABLE ? next_write_bank : write_word % 3;
    wire [14:0] write_address = FULL_ROW_ENABLE ? next_write_address : write_word / 3;
    wire ram_write_enable;
    wire [1:0] ram_write_bank;
    wire [14:0] ram_write_address;
    wire [39:0] ram_write_data;
    generate if (REGISTER_WRITE_PORTS) begin:g_write_port
        reg pending;
        reg [1:0] bank_q;
        reg [14:0] address_q;
        reg [39:0] data_q;
        // The MCU owner starts reading a completed eight-row bank only after
        // this last write has drained. Register the whole RAM write tuple to
        // isolate reset/admission/packing logic from the physical RAM pins.
        // A canceled pending write may touch unowned RAM during reset; no
        // canceled bank can become readable until a complete new fill.
        always @(posedge clk) begin
            pending <= write_enable;
            // Speculative payload sampling keeps reset/acceptance off the
            // wide register CE. Only the aligned pending bit owns a write.
            bank_q <= write_bank;
            address_q <= write_address;
            data_q <= write_data;
        end
        assign ram_write_enable=pending;
        assign ram_write_bank=bank_q;
        assign ram_write_address=address_q;
        assign ram_write_data=data_q;
    end else begin:g_direct_write
        assign ram_write_enable=write_enable;
        assign ram_write_bank=write_bank;
        assign ram_write_address=write_address;
        assign ram_write_data=write_data;
    end endgenerate

    // At most four new bytes: a row's first input cannot produce a full word.
    always @(posedge clk) begin
        if (!rst_n) begin
            carry <= 0; carry_bytes <= 0; next_word <= 0;
            tail_pending <= 0; tail_data <= 0; tail_word <= 0;
            next_write_bank <= 0; next_write_address <= 0;
        end else begin
            tail_pending <= 0;
            if (wr_valid) begin
                if (FULL_ROW_ENABLE) begin
                    if (wr_first) begin
                        next_write_bank <= 0;
                        next_write_address <= {wr_bank,wr_row} * (ROW_WORDS/3);
                    end else if (full_word) begin
                        if (next_write_bank == 2) begin
                            next_write_bank <= 0;
                            next_write_address <= next_write_address + 1'b1;
                        end else next_write_bank <= next_write_bank + 1'b1;
                    end
                end
                if (joined_bytes >= 5) begin
                    carry <= {8'd0,joined[63:40]};
                    carry_bytes <= joined_bytes - 5;
                    next_word <= current_word + 1'b1;
                end else begin
                    carry <= joined[31:0];
                    carry_bytes <= joined_bytes[2:0];
                    next_word <= current_word;
                end
                if (wr_last) begin
                    carry <= 0;
                    carry_bytes <= 0;
                    if (!FULL_ROW_ENABLE && joined_bytes > 5) begin
                        tail_pending <= 1;
                        tail_data <= {16'd0,joined[63:40]};
                        tail_word <= current_word + 1'b1;
                    end
                end
            end
        end
    end

    wire [14:0] first_read_word = {rd_bank,rd_row} * ROW_WORDS + rd_start / 5;
    wire [1:0] read_rotation = FULL_ROW_ENABLE ? (rd_start/5)%3 : first_read_word % 3;
    wire [14:0] first_read_address = FULL_ROW_ENABLE ?
        {rd_bank,rd_row} * (ROW_WORDS/3) + rd_start/15 : first_read_word / 3;
    wire [2:0] read_offset = rd_start % 5;
    reg [14:0] held_byte_select;
    wire [119:0] bank_words;
    assign o_bank_words=bank_words;
    assign o_byte_select=held_byte_select;
    wire [63:0] byte_windows [0:14];
    integer select_index;
    // Decode before the RAM read edge; each output uses fixed byte slices.
    // The same read CE holds this selector and the official RAM results.
    always @(posedge clk) begin
        if (!rst_n) held_byte_select <= 0;
        else if (rd_enable) begin
            for (select_index=0;select_index<15;select_index=select_index+1)
                held_byte_select[select_index] <=
                    read_rotation == select_index/5 && read_offset == select_index%5;
        end
    end
    integer output_select;
    always @* begin
        rd_data = 0;
        if (!PACKED_READ_ENABLE)
            for (output_select=0;output_select<15;output_select=output_select+1)
                rd_data = rd_data |
                    (byte_windows[output_select] & {64{held_byte_select[output_select]}});
    end
    genvar window_index, byte_index;
    generate for (window_index=0;window_index<15;window_index=window_index+1) begin:g_read_window
        for (byte_index=0;byte_index<8;byte_index=byte_index+1) begin:g_byte
            // Rotation is cyclic over three five-byte words, low byte first.
            assign byte_windows[window_index][byte_index*8+:8] =
                bank_words[((window_index+byte_index)%15)*8+:8];
        end
    end endgenerate
    genvar bank, cell_index;
    generate for (bank=0;bank<3;bank=bank+1) begin:g_bank
        wire [14:0] bank_read_address = first_read_address + (bank < read_rotation);
        reg [14:0] held_cell;
        wire [CELLS*40-1:0] cell_words;
        always @(posedge clk) begin
            if (!rst_n) held_cell <= CELLS;
            else if (rd_enable) held_cell <= bank_read_address >> 9;
        end
        assign bank_words[bank*40+:40] = held_cell < CELLS ?
            cell_words[held_cell*40+:40] : 40'd0;
        for(cell_index=0;cell_index<CELLS;cell_index=cell_index+1) begin:g_cell
            // Shape/configuration are owned by the generated IPC, not this RTL.
            ram40_sdp_fixed u_configured_ip(
                .dia(ram_write_data),.addra(ram_write_address[8:0]),.addrb(bank_read_address[8:0]),
                .cea(ram_write_enable && ram_write_bank==bank && (ram_write_address>>9)==cell_index),
                .ceb(rd_enable && (bank_read_address>>9)==cell_index),
                .clka(clk),.dob(cell_words[cell_index*40+:40]));
        end
    end endgenerate
    generate if (MAX_SAMPLES<4 || MAX_SAMPLES>3840 ||
        (IN_BYTES!=2 && IN_BYTES!=4) || MAX_SAMPLES%IN_BYTES!=0 ||
        (FULL_ROW_ENABLE && MAX_SAMPLES%15!=0)) begin:g_bad_shape
        JPEG_PACKED_PLANE_INVALID_CAPACITY invalid_configuration();
    end endgenerate
endmodule
