// Private helper: i_frame_context is the parent frame owner, held through all output transfers.
// Dimensions are the existing local START-latched values, not live configuration.
// F22 Y-only clamped3x3 service. Two existing official 32-bit row wrappers;
// each wrapper selects a fitting fixed official core, without IP overrides.
module full_filter_y_window4 #(
    parameter integer MAX_WIDTH = 1920,
    parameter integer MAX_HEIGHT = 1080,
    parameter integer FIXED_WIDTH = 0,
    parameter integer FIXED_HEIGHT = 0
) (
    input wire clk, rst_n, cancel,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width, start_height,
    input wire [159:0] i_frame_context,
    input wire s_valid,
    output wire s_ready,
    input wire [31:0] s_data,
    input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_eof,
    output wire m_valid,
    output wire window_pending,
    input wire m_ready,
    output wire [287:0] m_window,
    output wire [218:0] m_metadata,
    output reg done,
    output reg error
);
    localparam [1:0] ST_INPUT=2'd0,ST_FLUSH=2'd1,ST_BOTTOM=2'd2,ST_DRAIN=2'd3;
    reg active, output_valid;
    reg [1:0] state;
    reg write_bank;
    localparam integer X_BITS=FIXED_WIDTH ? $clog2(FIXED_WIDTH+4) : 13;
    localparam integer Y_BITS=FIXED_HEIGHT ? $clog2(FIXED_HEIGHT+1) : 13;
    localparam integer BEAT_BITS=FIXED_WIDTH ? $clog2((FIXED_WIDTH+3)/4) : 10;
    reg [12:0] width,height;
    reg [Y_BITS-1:0] row_index;
    reg [BEAT_BITS-1:0] beat_index;
    wire [9:0] ram_read_address=beat_index;
    reg [32:0] pixel_metadata;
    assign m_metadata={i_frame_context,width,height,pixel_metadata};
    wire run=rst_n&&!cancel;
    wire advance=run&&active&&(!output_valid||m_ready);
    // The final group number and mask depend only on the accepted START.
    reg [BEAT_BITS-1:0] last_beat;
    reg [3:0] last_keep;
    wire at_last_beat=beat_index==last_beat;
    wire [3:0] expected_keep=at_last_beat ? last_keep : 4'hf;
    reg read_last,read_row_first,read_row_final;
    reg center_last,center_sof,center_row_final;
    wire malformed=s_keep!=expected_keep || s_sof!=(row_index==0&&beat_index==0) ||
        s_eol!=(beat_index==last_beat) || s_eof!=(row_index==height-1'b1&&beat_index==last_beat);
    assign start_ready=run&&!active;
    assign s_ready=advance&&state==ST_INPUT;
    // Raw registered ownership is safe for a sibling arbiter's payload select.
    // Cancel still masks the transfer, but cannot enter the window-data mux.
    assign window_pending=active&&output_valid;
    assign m_valid=run&&window_pending;
    wire take_input=s_valid&&s_ready&&!malformed;
    wire take_bottom=advance&&state==ST_BOTTOM;
    wire take_flush=advance&&state==ST_FLUSH;
    wire request_read=(take_input&&row_index!=0)||take_bottom;
    wire [31:0] clean_input;
    genvar pixel;
    generate for(pixel=0;pixel<4;pixel=pixel+1) begin:g_clean
        assign clean_input[pixel*8 +:8]=s_keep[pixel] ? s_data[pixel*8 +:8] : 8'd0;
    end endgenerate
    reg read_valid,read_first,read_flush,read_top_repeat,read_bottom_repeat;
    reg read_bank;
    reg [X_BITS-1:0] read_x_n;
    reg [Y_BITS-1:0] read_y_n;
    wire [12:0] read_x=read_x_n,read_y=read_y_n;
    reg [3:0] read_keep;
    reg [31:0] read_input;
    // The incoming row reuses its y-2 bank, one clock AFTER reading it.
    // Consecutive groups have different addresses. Even a one-group row
    // executes ST_FLUSH before requesting address zero on the next row.
    reg write_pending;
    always @(posedge clk) write_pending<=take_input;
    wire [31:0] bank_data [0:1];
    genvar bank;
    generate for(bank=0;bank<2;bank=bank+1) begin:g_bank
        preprocess_line_ram32x1024 #(.DEPTH((MAX_WIDTH+3)/4)) ram (
            .clk(clk),.wr_en(run&&write_pending&&read_bank==bank),.wr_addr(read_x[11:2]),.wr_data(read_input),
            .rd_en(request_read&&((write_bank!=bank)||(row_index>1))),
            .rd_addr(ram_read_address),.rd_data(bank_data[bank]));
    end endgenerate
    wire [31:0] middle=read_bank ? bank_data[0] : bank_data[1];
    wire [31:0] earlier=read_bank ? bank_data[1] : bank_data[0];
    wire [31:0] top=read_top_repeat ? middle : earlier;
    wire [31:0] bottom=read_bottom_repeat ? middle : read_input;
    wire [95:0] rows_now={bottom,middle,top};
    reg [95:0] center_rows;
    reg [23:0] left_column;
    reg [X_BITS-1:0] center_x_n;
    reg [Y_BITS-1:0] center_y_n;
    wire [12:0] center_x=center_x_n,center_y=center_y_n;
    reg [3:0] center_keep;
    // Four consecutive three-column windows share six physical columns.
    // Keep the one-pixel right border in the first missing column of a short tail.
    reg [143:0] output_strip;
    wire [143:0] next_strip;
    genvar r, c, lane;
    generate for(r=0;r<3;r=r+1) begin:g_strip_row
        assign next_strip[r*48+:8]=left_column[r*8+:8];
        assign next_strip[r*48+8+:8]=center_rows[r*32+:8];
        for(c=1;c<4;c=c+1) begin:g_tail
            assign next_strip[r*48+(c+1)*8+:8]=(!center_keep[c] && read_flush) ?
                center_rows[r*32+(c-1)*8+:8] : center_rows[r*32+c*8+:8];
        end
        assign next_strip[r*48+40+:8]=read_flush ?
            center_rows[r*32+24+:8] : rows_now[r*32+:8];
        for(lane=0;lane<4;lane=lane+1) begin:g_expand
            assign m_window[lane*72+r*24+:24]=pixel_metadata[3+lane] ?
                output_strip[r*48+lane*8+:24] : 24'd0;
        end
    end endgenerate

    integer row_capture;
    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            active<=0;output_valid<=0;read_valid<=0;done<=0;error<=0;
            state<=ST_INPUT;write_bank<=0;row_index<=0;beat_index<=0;
        end else begin
            done<=0;error<=0;
            if(start_valid&&start_ready) begin
                output_valid<=0;read_valid<=0;state<=ST_INPUT;write_bank<=0;row_index<=0;beat_index<=0;
                if(start_width==0||start_width>MAX_WIDTH||start_width>2048||
                   start_height==0||start_height>MAX_HEIGHT||
                   (FIXED_WIDTH!=0 && start_width!=FIXED_WIDTH)||
                   (FIXED_HEIGHT!=0 && start_height!=FIXED_HEIGHT)) begin
                    active<=0;error<=1;
                end else begin
                    active<=1;
                    width<=FIXED_WIDTH ? FIXED_WIDTH : start_width;
                    height<=FIXED_HEIGHT ? FIXED_HEIGHT : start_height;
                    last_beat<=FIXED_WIDTH ? (FIXED_WIDTH+3)/4-1 : start_width[11:2]-(start_width[1:0]==0);
                    case(start_width[1:0])
                        2'd1: last_keep<=4'b0001;
                        2'd2: last_keep<=4'b0011;
                        2'd3: last_keep<=4'b0111;
                        default: last_keep<=4'b1111;
                    endcase
                end
            end else if(active&&s_valid&&s_ready&&malformed) begin
                active<=0;output_valid<=0;read_valid<=0;error<=1;
            end else if(advance) begin
                read_valid<=request_read||(take_flush&&row_index!=0);
                if(take_input||take_bottom||take_flush) begin
                    read_first<=!take_flush&&beat_index==0;
                    read_flush<=take_flush;
                    read_last<=at_last_beat;
                    read_row_first<=row_index==1;
                    read_row_final<=row_index==height;
                    read_top_repeat<=row_index==1;
                    read_bottom_repeat<=take_bottom;
                    read_bank<=write_bank;
                    read_x_n<={beat_index,2'b0};read_y_n<=row_index-1'b1;
                    read_keep<=expected_keep;read_input<=clean_input;
                end
                output_valid<=read_valid&&!read_first;
                if(read_valid) begin
                    if(!read_flush) begin
                        center_rows<=rows_now;center_x_n<=read_x;center_y_n<=read_y;center_keep<=read_keep;
                        center_last<=read_last;center_sof<=read_first&&read_row_first;
                        center_row_final<=read_row_final;
                        for(row_capture=0;row_capture<3;row_capture=row_capture+1)
                            left_column[row_capture*8 +:8]<=read_first ? rows_now[row_capture*32 +:8] :
                                center_rows[row_capture*32+24 +:8];
                    end
                    if(!read_first) begin
                        output_strip<=next_strip;
                        pixel_metadata<={center_x,center_y,center_keep,
                            center_sof,center_last,center_last&&center_row_final};
                    end
                end
                if(take_input||take_bottom) begin
                    if(beat_index==last_beat) state<=ST_FLUSH;
                    else beat_index<=beat_index+1'b1;
                end else if(take_flush) begin
                    beat_index<=0;
                    if(row_index==height) state<=ST_DRAIN;
                    else begin
                        row_index<=row_index+1'b1;
                        write_bank<=!write_bank;
                        state<=row_index==height-1'b1 ? ST_BOTTOM : ST_INPUT;
                    end
                end
                if(output_valid&&m_ready&&m_metadata[0]) begin
                    active<=0;output_valid<=0;read_valid<=0;done<=1;
                end
            end
        end
    end
endmodule
