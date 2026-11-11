`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// One held DFI extension, serialized into the existing official SDP primitive.
module ddr_extension_staging_ram #(
    parameter integer RECORD_EXTENSION_WIDTH=3072,
    // Only an owner that holds the same flit and stable identity may opt in.
    // The ordinary standalone interface retains all first-flit checks.
    parameter integer FIRST_FLIT_PRECHECKED=0
)(
    input wire i_clk,i_rst_n,i_begin,
    input wire [31:0] i_session,i_epoch,i_sequence,
    input wire i_camera,
    input wire [127:0] s_data,
    input wire s_valid,s_last,
    output wire s_ready,
    output wire o_complete,o_shape_valid,
    input wire i_read_enable,
    input wire [8:0] i_read_index,
    output wire [39:0] o_read_data
);
    localparam integer WORD_WIDTH=RECORD_EXTENSION_WIDTH==1024 ? 32 : 40;
    localparam integer WORDS=(RECORD_EXTENSION_WIDTH+WORD_WIDTH-1)/WORD_WIDTH;
    localparam integer FLITS=RECORD_EXTENSION_WIDTH/128;
    localparam [1:0] IDLE=0,WRITE=1,HOLD=2;
    reg [1:0] state,state_next;
    localparam integer WORD_BYTES=WORD_WIDTH/8;
    reg [4:0] write_bytes;
    wire [WORD_WIDTH-1:0] ram_word;
    reg [8:0] write_index;
    reg [6:0] input_index;
    reg input_complete,base_good,last_good;
    reg sparse_any,sparse_header_good,sparse_body_good;
    reg [3:0] sparse_enabled;
    wire ram_write=i_rst_n && state==WRITE &&
        (write_bytes>=WORD_BYTES || (input_complete && write_bytes!=0));
    wire write_room=write_bytes<WORD_BYTES ||
        (ram_write && write_bytes<2*WORD_BYTES);
    wire input_fire=s_valid && s_ready;
    wire final_write=ram_write && input_complete && write_bytes<=WORD_BYTES;
    wire [WORD_WIDTH-1:0] ram_read_data;
    assign s_ready=i_rst_n && state==WRITE && !input_complete && write_room;
    assign o_complete=i_rst_n && state==HOLD;
    wire v4_good;
    generate if(RECORD_EXTENSION_WIDTH==16384)begin : g_sparse_v4_check
        // Capture the same word as the SDP write. On the first HOLD
        // cycle the checker combines its earlier verdict with this final
        // registered word, so shape/ownership retain their original timing.
        reg verify_valid;
        reg [8:0] verify_index;
        reg [39:0] verify_word;
        always @(posedge i_clk) begin
            verify_valid<=ram_write && !i_begin;
            if(ram_write) begin verify_index<=write_index; verify_word<=ram_word; end
        end
        lane_sparse_extension_checker u_check (
            .i_clk(i_clk),.i_rst_n(i_rst_n),.i_begin(i_begin),
            .i_valid(verify_valid),.i_index(verify_index),.i_data(verify_word),.o_good(v4_good));
    end else begin : g_no_v4_check
        assign v4_good=1'b1;
    end endgenerate
    assign o_shape_valid=o_complete && base_good && last_good && write_index==WORDS &&
        (RECORD_EXTENSION_WIDTH==16384 ? v4_good :
         (RECORD_EXTENSION_WIDTH==1024 || !sparse_any || (sparse_header_good && sparse_body_good)));
    assign o_read_data={{(40-WORD_WIDTH){1'b0}},ram_read_data};
    td_sdp_ram40 #(.WIDTH(WORD_WIDTH),.DEPTH(512),.ADDR_WIDTH(9)) u_staging_ram (
        .clk(i_clk),.wr_en(ram_write),.wr_addr(write_index),
        .wr_data(ram_word),
        .rd_en(i_rst_n && state==HOLD && i_read_enable && i_read_index<WORDS),
        .rd_addr(i_read_index),.rd_data(ram_read_data));

    wire base_flit_good=input_index==0 ?
        (FIRST_FLIT_PRECHECKED!=0 || (s_data[31:0]==`PCIE_RECORD_V2_EXTENSION_MAGIC &&
         s_data[47:32]==`PCIE_RECORD_V2_SCHEMA_VERSION &&
         s_data[48+`PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY] && s_data[63:60]==0 &&
         s_data[95:64]==i_session && s_data[127:96]==i_epoch)) :
        input_index==1 ? (s_data[31:0]==i_sequence &&
         s_data[39:32]=={7'd0,i_camera} && s_data[127:64]==0) :
        input_index==7 ? s_data[127:51]==0 : 1'b1;
    reg sparse_flit_good;
    always @* begin
        sparse_flit_good=1'b1;
        case(input_index)
            9,10,11,12:sparse_flit_good=sparse_enabled[0] || s_data==0;
            13:sparse_flit_good=(sparse_enabled[0] || s_data[11:0]==0) &&
                (sparse_enabled[1] || s_data[127:12]==0);
            14,15,16,17,18,19,20,21:sparse_flit_good=sparse_enabled[1] || s_data==0;
            22:sparse_flit_good=(sparse_enabled[1] || s_data[55:0]==0) &&
                (sparse_enabled[2] || s_data[103:56]==0) &&
                (sparse_enabled[3] || s_data[127:104]==0);
            23:sparse_flit_good=(sparse_enabled[3] || s_data[80:0]==0) && s_data[127:81]==0;
            default:sparse_flit_good=1'b1;
        endcase
    end
    // Bytes left from the old flit after the RAM write on this edge.
    // A simultaneous input transfer is permitted only with 0..4 left.
    wire [4:0] residual=ram_write ? (write_bytes>=WORD_BYTES ? write_bytes-WORD_BYTES : 0) : write_bytes;
    wire [4:0] next_bytes=residual+(input_fire ? 5'd16 : 5'd0);
    // Place each new 128-bit flit at a fixed offset, preceded by the
    // preceding flit's four highest bytes. The RAM word alignment stays
    // constant until another flit arrives; each RAM write advances 5 or
    // 4 bytes. Logical byte count prevents unused startup data escaping.
    reg [31:0] prev_high;
    reg [159:0] window;
    // Each 16-byte flit advances the 5-byte packing phase by one.
    // A new owner starts at byte four, directly after the ignored carry.
    reg [4:0] select_byte;
    always @(posedge i_clk) begin
        if(i_begin) select_byte<=5'b00001;
        else if(input_fire) select_byte<={select_byte[0],select_byte[4:1]};
    end
    always @(posedge i_clk) begin
        if(input_fire) begin
            window<={s_data,prev_high};
            prev_high<=s_data[127:96];
        end else if(ram_write) window<=window>>WORD_WIDTH;
    end
    wire [WORD_WIDTH-1:0] selected_word;
    generate if(WORD_BYTES==4) begin:g_aligned_word
        assign selected_word=window[32+:32];
    end else begin:g_five_byte_word
        assign selected_word=({40{select_byte[0]}} & window[0+:40]) |
                             ({40{select_byte[1]}} & window[8+:40]) |
                             ({40{select_byte[2]}} & window[16+:40]) |
                             ({40{select_byte[3]}} & window[24+:40]) |
                             ({40{select_byte[4]}} & window[32+:40]);
    end endgenerate
    assign ram_word=selected_word;
    always @* begin
        state_next=state;
        case(state)
            IDLE:state_next=IDLE;
            WRITE:if(final_write)state_next=HOLD;
            HOLD:state_next=HOLD;
            default:state_next=IDLE;
        endcase
        if(i_begin)state_next=WRITE;
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)state<=IDLE;
        else state<=state_next;
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            write_bytes<=0;write_index<=0;input_index<=0;input_complete<=0;
            base_good<=1;last_good<=1;sparse_any<=0;sparse_header_good<=0;
            sparse_body_good<=1;sparse_enabled<=0;
        end else if(i_begin)begin
            write_bytes<=0;write_index<=0;input_index<=0;input_complete<=0;
            base_good<=1;last_good<=1;sparse_any<=0;sparse_header_good<=0;
            sparse_body_good<=1;sparse_enabled<=0;
        end else if(state==WRITE)begin
            write_bytes<=next_bytes;
            if(ram_write)write_index<=write_index+1'b1;
            if(input_fire)begin
                base_good<=base_good && base_flit_good;
                last_good<=last_good && (s_last==(input_index==FLITS-1));
                if(s_last || input_index==FLITS-1)input_complete<=1;
                else input_index<=input_index+1'b1;
                if(RECORD_EXTENSION_WIDTH==3072 && input_index>=8)begin
                    sparse_any<=sparse_any || (|s_data);
                    if(input_index==8)begin
                        sparse_enabled<=s_data[51:48];
                        sparse_header_good<=s_data[31:0]==`PCIE_RECORD_V3_SPARSE_MAGIC &&
                            s_data[39:32]==`PCIE_RECORD_V3_SPARSE_SCHEMA &&
                            s_data[47:40]==`PCIE_RECORD_V3_STRIPS &&
                            s_data[55:52]==s_data[51:48] && s_data[127:57]==0 &&
                            (!(|s_data[51:49]) || s_data[48]);
                    end else sparse_body_good<=sparse_body_good && sparse_flit_good;
                end
            end
        end
    end
endmodule
