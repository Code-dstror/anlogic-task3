`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Fixed-address v4 shape checker for one sequential 40-bit RAM pass.
// No image payload or extension vector is retained here.
module lane_sparse_extension_checker (
    input wire i_clk,i_rst_n,i_begin,
    input wire i_valid,
    input wire [8:0] i_index,
    input wire [39:0] i_data,
    output wire o_good
);
    reg bad;
    reg [3:0] enabled;
    reg [8:0] count;
    reg [31:0] prior_bytes;
    reg [10:0] prior_x;
    reg [8:0] prior_y;
    reg [1:0] row_points;
    reg point_seen;
    localparam [31:0] SPARSE_MAGIC=`PCIE_RECORD_V4_SPARSE_MAGIC;
    localparam [9:0] POINT_FIRST_WORD=(`PCIE_RECORD_V4_POINTS_OFFSET+4)/5;
    localparam [11:0] POINTS_OFFSET=`PCIE_RECORD_V4_POINTS_OFFSET;
    wire [9:0] point_end_word=POINT_FIRST_WORD+{1'b0,count};
    wire [39:0] point_word={i_data[7:0],prior_bytes};
    wire [10:0] point_x=point_word[10:0];
    wire [8:0] point_y=point_word[19:11];
    wire [10:0] strength=point_word[30:20];
    wire [3:0] width=point_word[34:31];
    wire [1:0] color=point_word[36:35];
    wire is_point={1'b0,i_index}>=POINT_FIRST_WORD && {1'b0,i_index}<point_end_word;
    wire point_good=point_word[39:37]==0 && point_x<11'd1920 &&
        point_y>=`PCIE_RECORD_V4_ROI_BEGIN && point_y<=`PCIE_RECORD_V4_ROI_END && strength<=11'd2040 &&
        width>=4'd1 && width<=4'd8 && (color==`PCIE_RECORD_V4_CLASS_WHITE || color==`PCIE_RECORD_V4_CLASS_YELLOW) &&
        (!point_seen || point_y>prior_y ||
         (point_y==prior_y && {1'b0,point_x}>={1'b0,prior_x}+12'd24 && row_points<2'd3));
    reg word_good;
    always @* begin
        word_good=1'b1;
        case(i_index)
            25:word_good=i_data[39:24]==SPARSE_MAGIC[15:0];
            26:word_good=i_data[15:0]==SPARSE_MAGIC[31:16] && i_data[23:16]==`PCIE_RECORD_V4_SPARSE_SCHEMA &&
                i_data[31:24]==`PCIE_RECORD_V4_POINT_BYTES && i_data[39:36]==0;
            27:word_good=i_data[7:0]=={4'd0,enabled} && i_data[15:8]<=1 &&
                (i_data[23:16]==`PCIE_RECORD_V4_STATUS_OK || i_data[23:16]==`PCIE_RECORD_V4_STATUS_NO_CANDIDATES ||
                 i_data[23:16]==`PCIE_RECORD_V4_STATUS_LOCAL_ERROR || i_data[23:16]==`PCIE_RECORD_V4_STATUS_SOURCE_ERROR) &&
                i_data[39:24]<=`PCIE_RECORD_V4_POINT_COUNT_MAX &&
                (enabled[1] || (i_data[39:24]==0 && i_data[23:16]==0)) &&
                (i_data[23:16]==`PCIE_RECORD_V4_STATUS_OK ?
                    (!enabled[1] || i_data[39:24]!=0) : i_data[39:24]==0) &&
                (i_data[23:16]!=`PCIE_RECORD_V4_STATUS_SOURCE_ERROR || i_data[15:8]==1);
            28:word_good=i_data[15:0]==`PCIE_RECORD_V4_ROI_BEGIN && i_data[31:16]==`PCIE_RECORD_V4_ROI_END;
            default:word_good=1'b1;
        endcase
        // Fixed v4 fields are byte-addressed on the wire and five-byte
        // aligned in this RAM. Decode their word once, with fixed bit masks;
        // no i_index*5 or per-byte offset comparators are needed.
        case(i_index)
            28:if(!enabled[0] && i_data[39:32]!=0)word_good=0;
            29,30,31,32,33,34,35,36,37,38,39,40:
                if(!enabled[0] && i_data!=0)word_good=0;
            41:if(i_data[39:36]!=0 || (!enabled[0] && i_data[35:0]!=0))word_good=0;
            42:if(!enabled[2] && i_data!=0)word_good=0;
            43:if((!enabled[2] && i_data[7:0]!=0) ||
                  (!enabled[3] && i_data[39:8]!=0))word_good=0;
            44:if(!enabled[3] && i_data!=0)word_good=0;
            45:if(i_data[39:33]!=0 || (!enabled[3] && i_data[32:0]!=0))word_good=0;
            46,47,48,49,50:if(i_data!=0)word_good=0;
            51:if(i_data[7:0]!=0)word_good=0;
            default:begin end
        endcase
        // POINTS_OFFSET=256=5*51+1: the final point's low byte belongs to
        // word(point_end_word-1); that word's remaining four bytes are padding.
        // Preserve the original upper byte boundary even for invalid indices.
        if(i_index<9'd410)begin
            if({1'b0,i_index}>=point_end_word)begin
                if(i_data!=0)word_good=0;
            end else if({1'b0,i_index}==point_end_word-10'd1 && i_data[39:8]!=0)word_good=0;
        end
        if(is_point && !point_good)word_good=0;
    end
    assign o_good=!bad && (!i_valid || word_good);
    always @(posedge i_clk)begin
        if(!i_rst_n || i_begin)begin
            bad<=0;enabled<=0;count<=0;prior_bytes<=0;
            prior_x<=0;prior_y<=0;row_points<=0;point_seen<=0;
        end else if(i_valid)begin
            if(!word_good)bad<=1;
            prior_bytes<=i_data[39:8];
            if(i_index==26)enabled<=i_data[35:32];
            if(i_index==27)count<=i_data[32:24];
            if(is_point)begin
                prior_x<=point_x;prior_y<=point_y;point_seen<=1;
                row_points<=point_seen && point_y==prior_y ? row_points+1'b1 : 1;
            end
        end
    end
endmodule
