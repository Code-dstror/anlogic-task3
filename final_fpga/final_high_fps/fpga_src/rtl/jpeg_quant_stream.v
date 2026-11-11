`timescale 1ns/1ps
`include "jpeg_quant_config.vh"
// Eight parallel official-DSP quantizers plus conflict-free banked zigzag.
module jpeg_quant_stream #(
    parameter integer MAX_WIDTH=1920,
    parameter integer MAX_HEIGHT=1080,
    parameter ROM_INIT_ROOT=`JPEG_QUANT_DEFAULT_ROOT,
    parameter ROM_INIT_SUFFIX=".mif",
    parameter integer TINY_DISTRIBUTED_RAM_ENABLE=0
) (
    input wire i_clk,i_rst_n,
    input wire i_column_valid,
    output wire o_column_ready,
    input wire [127:0] i_column_data,
    input wire [2:0] i_column_index,
    input wire [1:0] i_component,i_block_index,
    input wire [8:0] i_mcu_x,i_mcu_y,
    input wire i_frame_last,
    input wire [31:0] i_capture_id,
    input wire [6:0] i_quality,
    input wire [31:0] i_epoch,i_session_id,
    input wire i_camera_id,
    output wire o_token_valid,
    input wire i_token_ready,
    output wire [146:0] o_token_data,
    output reg o_error,
    input wire [6:0] i_table_quality,
    input wire i_table_component,
    input wire [2:0] i_table_column,
    input wire i_table_enable,
    output wire [63:0] o_table_quantizers
);
    `include "jpeg_quant_bank_map.vh"
    reg faulted,frame_open,input_bank,next_input_bank;
    reg [2:0] expected_column;
    reg [6:0] frame_quality;
    reg [31:0] frame_epoch,frame_session;
    reg frame_camera;
    reg [54:0] block_metadata;
    // The current input registers already hold the latest block's entire
    // header. Keep one snapshot for the other bank until its reader starts.
    reg [127:0] prior_header;
    wire [127:0] latest_header={1'b0,frame_camera,frame_quality,
        block_metadata[32],block_metadata[34:33],block_metadata[54:53],
        block_metadata[43:35],block_metadata[52:44],frame_session,frame_epoch,block_metadata[31:0]};
    reg [1:0] bank_writable,bank_full;
    wire [54:0] input_metadata={i_component,i_mcu_x,i_mcu_y,i_block_index,i_frame_last,i_capture_id};
    wire first_column=expected_column==0;
    wire selected_input_bank=first_column ? next_input_bank : input_bank;
    wire [6:0] selected_quality=frame_open ? frame_quality : i_quality;
    wire malformed=i_column_index!=expected_column || i_component==3 ||
        i_mcu_x >= (MAX_WIDTH+15)/16 || i_mcu_y >= (MAX_HEIGHT+7)/8 ||
        (first_column ? (selected_quality<1 || selected_quality>100) : input_metadata!=block_metadata);

    reg [4:0] valid_pipe;
    reg [3:0] tag0,tag1,tag2,tag3,tag4;
    reg [127:0] coefficient0,coefficient1,quantized;
    reg [7:0] negative1,negative2;
    reg [15:0] numerator[0:7];
    reg [24:0] reciprocal[0:7];
    wire [40:0] product[0:7];
    wire [32:0] rom_data[0:7];
    wire write_ready=bank_writable[tag4[3]];
    wire advance=!valid_pipe[4] || write_ready;
    wire write_column=i_rst_n && valid_pipe[4] && write_ready;
    wire input_fire=i_column_valid && o_column_ready;
    wire take_column=input_fire && !malformed;
    wire [6:0] quality_index=selected_quality-1'b1;
    wire [10:0] rom_address={quality_index,i_component!=0,i_column_index};

    reg reader_active,reader_bank,next_reader_bank,read_pending;
    reg [2:0] reader_batch,pending_batch;
    reg token_valid;
    reg [146:0] token;
    wire fifo_ready;
    wire token_advance=!token_valid || fifo_ready;
    wire start_reader=!reader_active && !read_pending && token_advance && bank_full[next_reader_bank];
    wire read_request=i_rst_n && token_advance && (reader_active || start_reader);
    wire read_bank=reader_active ? reader_bank : next_reader_bank;
    wire [2:0] read_batch=reader_active ? reader_batch : 3'd0;
    wire reservable=bank_writable[next_input_bank] ||
        (reader_active && reader_bank==next_input_bank) ||
        (start_reader && next_reader_bank==next_input_bank);
    assign o_column_ready=i_rst_n && !faulted && advance && (!first_column || reservable);
    jpeg_quant_sync_fifo u_token_fifo (
        .i_clk(i_clk),.i_rst_n(i_rst_n),
        .s_data(token),.s_valid(i_rst_n && token_valid),.s_ready(fifo_ready),
        .m_data(o_token_data),.m_valid(o_token_valid),.m_ready(i_token_ready),
        .o_reset_done(),.o_resident());
    wire [6:0] table_quality_index=i_table_quality-1'b1;
    wire [10:0] table_address={table_quality_index,i_table_component,i_table_column};
    wire table_enable=i_table_enable && i_table_quality>=1 && i_table_quality<=100;
    wire [127:0] bank_data,zigzag_data;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1) begin:g_lane
        localparam [2:0] LANE_ID=lane;
        jpeg_quant_table_rom #(.LANE(lane),.INIT_ROOT(ROM_INIT_ROOT),.INIT_SUFFIX(ROM_INIT_SUFFIX)) u_rom (
            .i_clk(i_clk),.i_read_enable(take_column),.i_address(rom_address),.o_data(rom_data[lane]),
            .i_reciprocal_enable(i_rst_n && advance && valid_pipe[0]),
            .i_table_enable(table_enable),.i_table_address(table_address),.o_quantizer(o_table_quantizers[lane*8 +:8]));
        td_dsp_mult #(.A_WIDTH(25),.B_WIDTH(16),.INPUT_FORMAT("UNSIGNED")) u_quant_mult (
            .clk(i_clk),.rst_n(i_rst_n),.en(advance),
            .a(reciprocal[lane]),.b(numerator[lane]),.p(product[lane]));
        wire [2:0] read_column=quant_read_column({LANE_ID,read_batch});
        td_sdp_ram #(.WIDTH(16),.DEPTH(16),.ADDR_WIDTH(4),
            .DISTRIBUTED_ENABLE(TINY_DISTRIBUTED_RAM_ENABLE)) u_zigzag_ram (
            .clk(i_clk),.wr_en(write_column),.wr_addr({tag4[3],tag4[2:0]}),
            .wr_data(quant_write_word(LANE_ID,tag4[2:0],quantized)),
            .rd_en(read_request),.rd_addr({read_bank,read_column}),.rd_data(bank_data[lane*16 +:16]));
        assign zigzag_data[lane*16 +:16]=quant_read_word(LANE_ID,pending_batch,bank_data);
    end endgenerate
    integer v;
    reg [15:0] magnitude,quotient;
    reg [16:0] rounded_twice;
    always @(posedge i_clk) begin
        if(!i_rst_n) begin
            valid_pipe<=0;tag0<=0;tag1<=0;tag2<=0;tag3<=0;tag4<=0;
        end else if(advance) begin
            valid_pipe<={valid_pipe[3:0],take_column};
            coefficient0<=i_column_data;tag0<={selected_input_bank,i_column_index};
            coefficient1<=coefficient0;
            tag1<=tag0;tag2<=tag1;tag3<=tag2;tag4<=tag3;
            for(v=0;v<8;v=v+1) begin
                // Fold abs()'s +1 into the bounded 0..127 rounding term.
                // All signed 16-bit coefficients, including -32768, remain exact.
                magnitude=coefficient1[v*16 +:16] ^ {16{coefficient1[v*16+15]}};
                // The low bit supplies the carry needed for a negative
                // coefficient's one's complement. Only bits 16:1 are used.
                rounded_twice={magnitude,coefficient1[v*16+15]}+{9'd0,rom_data[v][32:26],1'b1};
                numerator[v]<=rounded_twice[16:1];
                reciprocal[v]<=rom_data[v][24:0];
                negative1[v]<=coefficient1[v*16+15];negative2[v]<=negative1[v];
                quotient=product[v][39:24];
                quantized[v*16 +:16]<=(quotient^{16{negative2[v]}})+{15'd0,negative2[v]};
            end
        end
    end
    always @(posedge i_clk) begin
        if(!i_rst_n) begin
            faulted<=0;o_error<=0;frame_open<=0;expected_column<=0;
            input_bank<=0;next_input_bank<=0;frame_quality<=75;
            frame_epoch<=0;frame_session<=0;frame_camera<=0;block_metadata<=0;
            prior_header<=0;bank_writable<=2'b11;bank_full<=0;
            reader_active<=0;reader_bank<=0;next_reader_bank<=0;
            reader_batch<=0;pending_batch<=0;read_pending<=0;token_valid<=0;token<=0;
        end else begin
            o_error<=0;
            if(input_fire) begin
                if(malformed) begin faulted<=1;o_error<=1;end
                else begin
                    if(first_column) begin
                        input_bank<=next_input_bank;next_input_bank<=!next_input_bank;
                        block_metadata<=input_metadata;
                        if(!frame_open) begin
                            frame_open<=1;frame_quality<=i_quality;frame_epoch<=i_epoch;
                            frame_session<=i_session_id;frame_camera<=i_camera_id;
                        end
                        prior_header<=latest_header;
                    end
                    if(i_column_index==7) begin
                        expected_column<=0;
                        if(i_frame_last) frame_open<=0;
                    end else expected_column<=expected_column+1'b1;
                end
            end
            if(token_advance) begin
                token_valid<=0;
                if(read_pending) begin
                    token_valid<=1;token<={2'b00,pending_batch==7,16'hffff,zigzag_data};
                end else if(start_reader) begin
                    token_valid<=1;token<={2'b01,1'b0,16'hffff,next_reader_bank==input_bank ? latest_header : prior_header};
                end
                read_pending<=read_request;
            end
            if(read_request) begin
                pending_batch<=read_batch;
                if(start_reader) begin
                    reader_bank<=next_reader_bank;next_reader_bank<=!next_reader_bank;
                    bank_full[read_bank]<=0;
                end
                if(read_batch==7) begin reader_active<=0;bank_writable[read_bank]<=1;end
                else begin reader_active<=1;reader_batch<=read_batch+1'b1;end
            end
            if(write_column && tag4[2:0]==7) begin
                bank_full[tag4[3]]<=1;bank_writable[tag4[3]]<=0;
            end
        end
    end
endmodule
