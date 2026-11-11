`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// One validated header owns this USER-clock RAM until its real final EXT take.
module pcie_header_extension_ram #(
    parameter integer RECORD_V2_ENABLE=0,
    parameter integer RECORD_V3_ENABLE=0,
    parameter integer RECORD_EXTENSION_WIDTH=RECORD_V3_ENABLE?3072:1024
)(
    input wire i_clk,i_rst_n,
    input wire [127:0] i_src_tdata,
    input wire [15:0] i_src_tkeep,
    input wire i_src_tvalid,
    output wire o_src_tready,
    input wire i_src_tlast,
    input wire [15:0] i_selected_version,
    output wire o_meta_valid,
    input wire i_meta_ready,
    output wire [31:0] o_meta_frame_sequence,o_meta_payload_length,
    output wire [15:0] o_meta_width,o_meta_height,
    output wire [7:0] o_meta_pixel_format,o_meta_compression,o_meta_quality,
    output wire [63:0] o_meta_timestamp_ns,
    output wire [31:0] o_meta_status,o_meta_error_code,
    output wire [15:0] o_meta_slot_id,
    output wire [31:0] o_meta_payload_crc32,
    output wire [15:0] o_meta_record_version,
    output wire [RECORD_EXTENSION_WIDTH-1:0] o_meta_record_extension,
    output wire [127:0] o_payload_tdata,
    output wire [15:0] o_payload_tkeep,
    output wire o_payload_tvalid,
    input wire i_payload_tready,
    output wire o_payload_tlast,
    output reg o_header_error,
    output reg [31:0] o_last_error,
    output wire o_busy,
    output wire [127:0] o_extension_tdata,
    output wire o_extension_tvalid,o_extension_tlast,
    input wire i_extension_tready
);
    generate if((RECORD_EXTENSION_WIDTH!=1024&&RECORD_EXTENSION_WIDTH!=3072)||
                (RECORD_V3_ENABLE&&RECORD_EXTENSION_WIDTH!=3072))begin:g_invalid_shape
        HEADER_RAM_REQUIRES_LEGAL_1024_OR_3072_PROFILE invalid_shape();
    end endgenerate
    localparam [2:0] HEADER=0,WRITE_TAIL=1,META=2,PAYLOAD=3,DRAIN=4;
    reg [2:0] state;
    reg [4:0] header_index;
    reg [15:0] selected_version;
    reg [127:0] header_zero,header_one,header_two;
    reg [11:0] extension_flags;
    reg [31:0] source_session,source_epoch;
    reg [23:0] source_descriptor;
    reg [3:0] sparse_enabled;
    reg extension_good;
    reg [166:0] write_buffer;
    reg [7:0] write_bits;
    reg [6:0] write_index;
    reg input_complete;
    wire [4:0] last_header_index=selected_version==3?27:selected_version==2?11:3;
    wire [15:0] current_selection=(RECORD_V2_ENABLE||RECORD_V3_ENABLE)?i_selected_version:16'd1;
    wire beat_good=i_src_tkeep==16'hffff&&!i_src_tlast;
    wire base_good=beat_good&&i_src_tdata==0&&header_zero[31:0]==`PCIE_FRAME_MAGIC&&
        header_zero[47:32]==selected_version&&
        (selected_version==1||((RECORD_V2_ENABLE||RECORD_V3_ENABLE)&&selected_version==2)||
         (RECORD_V3_ENABLE&&selected_version==3))&&
        header_zero[63:48]==(selected_version==3?448:selected_version==2?192:64)&&
        header_zero[127:96]!=0&&header_zero[127:96]<=`PCIE_MAX_PAYLOAD&&
        header_one[63:56]==1&&header_two[95:80]==0&&
        (selected_version==1||header_two[79:64]<`PCIE_RECORD_V2_SLOT_COUNT);

    // Every original full-vector predicate is checked at its accepted flit.
    // Only cross-flit identity/enable anchors are retained, never a full EXT FF.
    reg flit_good;
    always @* begin
        flit_good=1;
        case(header_index-4)
            0:flit_good=i_src_tdata[31:0]==`PCIE_RECORD_V2_EXTENSION_MAGIC&&
                i_src_tdata[47:32]==`PCIE_RECORD_V2_SCHEMA_VERSION&&i_src_tdata[63:60]==0&&
                (!(i_src_tdata[58]||i_src_tdata[59])||i_src_tdata[48])&&
                (i_src_tdata[48]?i_src_tdata[95:64]!=0:i_src_tdata[127:64]==0);
            1:flit_good=i_src_tdata[95:64]!=0&&i_src_tdata[127:96]!=0&&
                (extension_flags[0]?
                 (i_src_tdata[31:0]==header_zero[95:64]&&i_src_tdata[39:32]<=1&&
                  i_src_tdata[47:40]<=1&&(i_src_tdata[55:48]==1||i_src_tdata[55:48]==2)&&
                  i_src_tdata[63:56]<=2):i_src_tdata[63:0]==0);
            2:flit_good=(extension_flags[1]?i_src_tdata[31:0]!=0:
                {i_src_tdata[127:96],i_src_tdata[31:0]}==0)&&
                (extension_flags[2]||i_src_tdata[63:32]==0)&&
                (extension_flags[3]||i_src_tdata[95:64]==0);
            3:flit_good=(extension_flags[5]?i_src_tdata[63:0]!=0:i_src_tdata[63:0]==0)&&
                (extension_flags[6]?i_src_tdata[127:64]!=0:i_src_tdata[127:64]==0);
            4:flit_good=(extension_flags[7]?i_src_tdata[63:0]!=0:i_src_tdata[63:0]==0)&&
                (extension_flags[8]?
                 (extension_flags[0]&&i_src_tdata[95:64]==source_session&&
                  i_src_tdata[127:96]==source_epoch):i_src_tdata[127:64]==0);
            5:flit_good=(extension_flags[8]?
                (i_src_tdata[31:0]==header_zero[95:64]&&i_src_tdata[55:32]==source_descriptor&&
                 i_src_tdata[63:56]==1&&i_src_tdata[79:64]==0&&
                 i_src_tdata[95:80]==`PCIE_RECORD_V2_NEUTRAL_CONTEXT_SCHEMA):i_src_tdata[95:0]==0)&&
                (extension_flags[9]?
                 (extension_flags[8]&&i_src_tdata[111:96]!=0&&i_src_tdata[111:96]==i_src_tdata[127:112]):
                 i_src_tdata[127:96]==0);
            6:flit_good=extension_flags[9]?
                (i_src_tdata[111:96]!=0&&i_src_tdata[127:112]!=0):i_src_tdata==0;
            7:flit_good=(extension_flags[9]?
                (i_src_tdata[7:0]==1&&i_src_tdata[15:8]==0&&i_src_tdata[23:16]==1):
                 i_src_tdata[23:0]==0)&&
                (extension_flags[4]?(i_src_tdata[47:40]==1||i_src_tdata[47:40]==2):
                 (header_one[127:64]==0&&i_src_tdata[47:40]==0))&&
                i_src_tdata[63:51]==0&&i_src_tdata[127:64]==0;
            8:flit_good=i_src_tdata[31:0]==`PCIE_RECORD_V3_SPARSE_MAGIC&&
                i_src_tdata[39:32]==`PCIE_RECORD_V3_SPARSE_SCHEMA&&
                i_src_tdata[47:40]==`PCIE_RECORD_V3_STRIPS&&
                i_src_tdata[55:52]==i_src_tdata[51:48]&&i_src_tdata[127:57]==0&&
                (!(|i_src_tdata[51:49])||i_src_tdata[48]);
            9,10,11,12:flit_good=sparse_enabled[0]||i_src_tdata==0;
            13:flit_good=(sparse_enabled[0]||i_src_tdata[11:0]==0)&&
                (sparse_enabled[1]||i_src_tdata[127:12]==0);
            14,15,16,17,18,19,20,21:flit_good=sparse_enabled[1]||i_src_tdata==0;
            22:flit_good=(sparse_enabled[1]||i_src_tdata[55:0]==0)&&
                (sparse_enabled[2]||i_src_tdata[103:56]==0)&&
                (sparse_enabled[3]||i_src_tdata[127:104]==0);
            23:flit_good=(sparse_enabled[3]||i_src_tdata[80:0]==0)&&i_src_tdata[127:81]==0;
            default:flit_good=0;
        endcase
    end

    wire write_phase=state==HEADER||state==WRITE_TAIL;
    wire ram_write=i_rst_n&&write_phase&&(write_bits>=40||(input_complete&&write_bits!=0));
    wire write_room=write_bits<40||(ram_write&&write_bits<80);
    reg lease;
    wire source_fire=i_src_tvalid&&o_src_tready;
    wire extension_input=source_fire&&state==HEADER&&header_index>=4&&beat_good;
    wire meta_fire=o_meta_valid&&i_meta_ready;
    assign o_src_tready=i_rst_n&&((state==HEADER&&(header_index<4||write_room))||state==DRAIN||
        (state==PAYLOAD&&!lease&&i_payload_tready));
    assign o_meta_valid=i_rst_n&&state==META;
    assign o_payload_tdata=i_src_tdata;
    assign o_payload_tkeep=i_src_tkeep;
    assign o_payload_tlast=i_src_tlast;
    assign o_payload_tvalid=i_rst_n&&state==PAYLOAD&&!lease&&i_src_tvalid;
    assign o_busy=state!=HEADER||header_index!=0||lease;
    assign o_meta_frame_sequence=header_zero[95:64];
    assign o_meta_payload_length=header_zero[127:96];
    assign o_meta_width=header_one[15:0];
    assign o_meta_height=header_one[31:16];
    assign o_meta_pixel_format=header_one[39:32];
    assign o_meta_compression=header_one[47:40];
    assign o_meta_quality=header_one[55:48];
    assign o_meta_timestamp_ns=header_one[127:64];
    assign o_meta_status=header_two[31:0];
    assign o_meta_error_code=header_two[63:32];
    assign o_meta_slot_id=header_two[79:64];
    assign o_meta_payload_crc32=header_two[127:96];
    assign o_meta_record_version=selected_version;
    assign o_meta_record_extension={RECORD_EXTENSION_WIDTH{1'b0}};

    reg [166:0] write_buffer_next;
    reg [7:0] write_bits_next;
    always @* begin
        write_buffer_next=ram_write?write_buffer>>40:write_buffer;
        write_bits_next=ram_write?(write_bits>=40?write_bits-40:0):write_bits;
        if(extension_input)begin
            // Input room leaves only 0/8/16/24/32 old bits after the real write.
            case(write_bits_next)
                0:write_buffer_next=write_buffer_next|{39'd0,i_src_tdata};
                8:write_buffer_next=write_buffer_next|{31'd0,i_src_tdata,8'd0};
                16:write_buffer_next=write_buffer_next|{23'd0,i_src_tdata,16'd0};
                24:write_buffer_next=write_buffer_next|{15'd0,i_src_tdata,24'd0};
                32:write_buffer_next=write_buffer_next|{7'd0,i_src_tdata,32'd0};
                default:write_buffer_next=write_buffer_next;
            endcase
            write_bits_next=write_bits_next+128;
        end
    end

    wire [6:0] ram_word_count=selected_version==3?77:26;
    wire [4:0] extension_flits=selected_version==3?24:8;
    reg [206:0] read_buffer;
    reg [7:0] read_bits;
    reg [6:0] read_index;
    reg read_pending,pending_final;
    reg [4:0] output_index;
    wire [5:0] pending_bits=pending_final?(selected_version==3?32:24):40;
    wire stream_fire=o_extension_tvalid&&i_extension_tready;
    wire [8:0] projected_read_bits={1'b0,read_bits}+(read_pending?pending_bits:0)-(stream_fire?128:0);
    wire ram_read=i_rst_n&&lease&&read_index<ram_word_count&&projected_read_bits<=167;
    wire [39:0] ram_read_data;
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(512),.ADDR_WIDTH(9)) u_extension_ram(
        .clk(i_clk),.wr_en(ram_write),.wr_addr({2'd0,write_index}),.wr_data(write_buffer[39:0]),
        .rd_en(ram_read),.rd_addr({2'd0,read_index}),.rd_data(ram_read_data));
    assign o_extension_tdata=read_buffer[127:0];
    assign o_extension_tvalid=i_rst_n&&lease&&read_bits>=128;
    assign o_extension_tlast=output_index==extension_flits-1;
    reg [206:0] read_buffer_next;
    reg [7:0] read_bits_next;
    always @* begin
        read_buffer_next=stream_fire?read_buffer>>128:read_buffer;
        read_bits_next=stream_fire?read_bits-128:read_bits;
        if(read_pending)begin
            // The 40/128 packing phase is byte aligned and reserves at most 160 bits.
            case(read_bits_next)
                0:read_buffer_next=read_buffer_next|{167'd0,ram_read_data};
                8:read_buffer_next=read_buffer_next|{159'd0,ram_read_data,8'd0};
                16:read_buffer_next=read_buffer_next|{151'd0,ram_read_data,16'd0};
                24:read_buffer_next=read_buffer_next|{143'd0,ram_read_data,24'd0};
                32:read_buffer_next=read_buffer_next|{135'd0,ram_read_data,32'd0};
                40:read_buffer_next=read_buffer_next|{127'd0,ram_read_data,40'd0};
                48:read_buffer_next=read_buffer_next|{119'd0,ram_read_data,48'd0};
                56:read_buffer_next=read_buffer_next|{111'd0,ram_read_data,56'd0};
                64:read_buffer_next=read_buffer_next|{103'd0,ram_read_data,64'd0};
                72:read_buffer_next=read_buffer_next|{95'd0,ram_read_data,72'd0};
                80:read_buffer_next=read_buffer_next|{87'd0,ram_read_data,80'd0};
                88:read_buffer_next=read_buffer_next|{79'd0,ram_read_data,88'd0};
                96:read_buffer_next=read_buffer_next|{71'd0,ram_read_data,96'd0};
                104:read_buffer_next=read_buffer_next|{63'd0,ram_read_data,104'd0};
                112:read_buffer_next=read_buffer_next|{55'd0,ram_read_data,112'd0};
                120:read_buffer_next=read_buffer_next|{47'd0,ram_read_data,120'd0};
                128:read_buffer_next=read_buffer_next|{39'd0,ram_read_data,128'd0};
                136:read_buffer_next=read_buffer_next|{31'd0,ram_read_data,136'd0};
                144:read_buffer_next=read_buffer_next|{23'd0,ram_read_data,144'd0};
                152:read_buffer_next=read_buffer_next|{15'd0,ram_read_data,152'd0};
                160:read_buffer_next=read_buffer_next|{7'd0,ram_read_data,160'd0};
                default:read_buffer_next=read_buffer_next;
            endcase
            read_bits_next=read_bits_next+pending_bits;
        end
    end

    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            state<=HEADER;header_index<=0;selected_version<=1;
            header_zero<=0;header_one<=0;header_two<=0;
            extension_flags<=0;source_session<=0;source_epoch<=0;source_descriptor<=0;sparse_enabled<=0;
            extension_good<=1;write_buffer<=0;write_bits<=0;write_index<=0;input_complete<=0;
            o_header_error<=0;o_last_error<=`PCIE_ERROR_NONE;
        end else begin
            o_header_error<=0;
            write_buffer<=write_buffer_next;write_bits<=write_bits_next;
            if(ram_write)write_index<=write_index+1'b1;
            case(state)
                HEADER:if(source_fire)begin
                    if(!beat_good)begin
                        state<=i_src_tlast?HEADER:DRAIN;header_index<=0;
                        write_buffer<=0;write_bits<=0;input_complete<=0;
                        o_header_error<=1;o_last_error<=`PCIE_ERROR_HEADER_FORMAT;
                    end else begin
                        if(header_index==0)begin
                            header_zero<=i_src_tdata;selected_version<=current_selection;
                            write_buffer<=0;write_bits<=0;write_index<=0;input_complete<=0;
                            extension_good<=1;extension_flags<=0;sparse_enabled<=0;
                        end
                        if(header_index==1)header_one<=i_src_tdata;
                        if(header_index==2)header_two<=i_src_tdata;
                        if(header_index>=4)begin
                            extension_good<=extension_good&&flit_good;
                            if(header_index==4)begin
                                extension_flags<=i_src_tdata[59:48];
                                source_session<=i_src_tdata[95:64];source_epoch<=i_src_tdata[127:96];
                            end
                            if(header_index==5)source_descriptor<=i_src_tdata[55:32];
                            if(header_index==12)sparse_enabled<=i_src_tdata[51:48];
                        end
                        if(header_index==3&&!base_good)begin
                            state<=DRAIN;header_index<=0;
                            o_header_error<=1;o_last_error<=`PCIE_ERROR_HEADER_FORMAT;
                        end else if(header_index==last_header_index)begin
                            header_index<=0;
                            if(selected_version==1)begin state<=META;o_last_error<=`PCIE_ERROR_NONE;end
                            else begin state<=WRITE_TAIL;input_complete<=1;end
                        end else header_index<=header_index+1'b1;
                    end
                end
                WRITE_TAIL:if(write_bits_next==0)begin
                    input_complete<=0;
                    if(extension_good)begin state<=META;o_last_error<=`PCIE_ERROR_NONE;end
                    else begin state<=DRAIN;o_header_error<=1;o_last_error<=`PCIE_ERROR_HEADER_FORMAT;end
                end
                META:if(meta_fire)state<=PAYLOAD;
                PAYLOAD:if(source_fire&&i_src_tlast)begin state<=HEADER;header_index<=0;end
                DRAIN:if(source_fire&&i_src_tlast)begin state<=HEADER;header_index<=0;end
                default:begin state<=HEADER;header_index<=0;end
            endcase
        end
    end
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)begin
            lease<=0;read_buffer<=0;read_bits<=0;read_index<=0;
            read_pending<=0;pending_final<=0;output_index<=0;
        end else if(meta_fire&&selected_version!=1)begin
            lease<=1;read_buffer<=0;read_bits<=0;read_index<=0;
            read_pending<=0;pending_final<=0;output_index<=0;
        end else if(lease)begin
            read_buffer<=read_buffer_next;read_bits<=read_bits_next;
            read_pending<=ram_read;
            if(ram_read)begin pending_final<=read_index==ram_word_count-1;read_index<=read_index+1'b1;end
            if(stream_fire)begin
                if(o_extension_tlast)begin lease<=0;read_pending<=0;read_buffer<=0;read_bits<=0;end
                else output_index<=output_index+1'b1;
            end
        end else read_pending<=0;
    end
endmodule
