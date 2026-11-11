// Four binary pixels per group, three fixed official DP20 row banks.
// Nearest-clamp borders and ordinary-fault held-output drain are explicit.
module preprocess_binary_window4 #(
    parameter integer MAX_WIDTH=3840,
    parameter integer MAX_HEIGHT=2160
) (
    input wire clk,rst_n,cancel,source_error,
    input wire start_valid,
    output wire start_ready,
    input wire [12:0] start_width,start_height,
    input wire [159:0] start_context,
    input wire s_valid,
    output wire s_ready,
    input wire [3:0] s_mask,s_keep,
    input wire s_sof,s_eol,s_eof,
    output wire m_valid,
    input wire m_ready,
    output reg [35:0] m_window,
    output reg [218:0] m_metadata,
    output reg done,error,
    output reg [7:0] error_code,
    output reg [159:0] status_context
);
    localparam [2:0] ST_INPUT=0,ST_FLUSH=1,ST_BOTTOM=2,ST_DRAIN=3,ST_FAULT=4;
    reg active,output_valid;
    reg [2:0] state;
    reg [1:0] write_bank;
    reg [12:0] width,height,row_index;
    reg [9:0] beat_index;
    reg [159:0] frame_context;
    wire run=rst_n&&!cancel;
    wire advance=run&&active&&state!=ST_FAULT&&!source_error&&(!output_valid||m_ready);
    wire [12:0] groups=(width+13'd3)>>2;
    wire [9:0] last_beat=groups[9:0]-10'd1;
    wire [12:0] remaining=width-{1'b0,beat_index,2'b0};
    wire [3:0] expected_keep=remaining>=4 ? 4'hf : (4'h1<<remaining)-4'd1;
    wire malformed=s_keep!=expected_keep || s_sof!=(row_index==0&&beat_index==0)
        || s_eol!=(beat_index==last_beat) || s_eof!=(row_index==height-1'b1&&beat_index==last_beat);
    assign start_ready=run&&!active;
    assign s_ready=advance&&state==ST_INPUT;
    assign m_valid=run&&active&&output_valid;
    wire take_input=s_valid&&s_ready&&!malformed;
    wire take_bottom=advance&&state==ST_BOTTOM;
    wire take_flush=advance&&state==ST_FLUSH;
    wire request_read=(take_input&&row_index!=0)||take_bottom;
    wire [1:0] previous_bank=write_bank==0 ? 2'd2 : write_bank-2'd1;
    wire [1:0] earlier_bank=write_bank==2 ? 2'd0 : write_bank+2'd1;
    wire [3:0] clean_input=s_mask&s_keep;
    wire [3:0] bank_data [0:2];
    genvar bank;
    generate for(bank=0;bank<3;bank=bank+1) begin:g_bank
        td_sdp_ram #(.WIDTH(4),.DEPTH(1024),.ADDR_WIDTH(10)) ram (
            .clk(clk),.wr_en(take_input&&write_bank==bank),.wr_addr(beat_index),.wr_data(clean_input),
            .rd_en(request_read&&((previous_bank==bank)||((row_index>1)&&earlier_bank==bank))),
            .rd_addr(beat_index),.rd_data(bank_data[bank]));
    end endgenerate

    reg read_valid,read_first,read_flush,read_top_repeat,read_bottom_repeat;
    reg [1:0] read_previous_bank,read_earlier_bank;
    reg [12:0] read_x,read_y;
    reg [3:0] read_keep,read_input;
    wire [3:0] middle=bank_data[read_previous_bank];
    wire [3:0] top=read_top_repeat ? middle : bank_data[read_earlier_bank];
    wire [3:0] bottom=read_bottom_repeat ? middle : read_input;
    wire [11:0] rows_now={bottom,middle,top};
    reg [11:0] center_rows;
    reg [2:0] left_column;
    reg [12:0] center_x,center_y;
    reg [3:0] center_keep;
    integer lane,row,last_lane;
    reg left_value,right_value;
    reg [35:0] next_window;
    always @* begin
        next_window=0;
        last_lane=center_keep[3] ? 3 : center_keep[2] ? 2 : center_keep[1] ? 1 : 0;
        left_value=0;right_value=0;
        for(lane=0;lane<4;lane=lane+1) begin
            if(center_keep[lane]) begin
                for(row=0;row<3;row=row+1) begin
                    left_value=lane==0 ? left_column[row] : center_rows[row*4+lane-1];
                    if(lane==last_lane&&read_flush) right_value=center_rows[row*4+last_lane];
                    else if(lane==3) right_value=rows_now[row*4];
                    else right_value=center_rows[row*4+lane+1];
                    next_window[lane*9+row*3 +:3]={right_value,center_rows[row*4+lane],left_value};
                end
            end
        end
    end

    integer row_capture;
    always @(posedge clk) begin
        if(!rst_n||cancel) begin
            active<=0;output_valid<=0;read_valid<=0;done<=0;error<=0;error_code<=0;status_context<=0;
            state<=ST_INPUT;write_bank<=0;row_index<=0;beat_index<=0;
        end else begin
            done<=0;error<=0;
            if(start_valid&&start_ready) begin
                output_valid<=0;read_valid<=0;state<=ST_INPUT;write_bank<=0;row_index<=0;beat_index<=0;
                status_context<=start_context;frame_context<=start_context;error_code<=0;
                if(start_width==0||start_width>MAX_WIDTH||start_width>3840
                    ||start_height==0||start_height>MAX_HEIGHT||start_height>2160) begin
                    active<=0;done<=1;error<=1;error_code<=1;
                end else begin active<=1;width<=start_width;height<=start_height;end
            end else if(active&&state!=ST_FAULT
                &&(source_error||(s_valid&&s_ready&&malformed))) begin
                state<=ST_FAULT;read_valid<=0;
                output_valid<=output_valid&&!m_ready;
                error_code<=source_error ? 8'd3 : 8'd2;
            end else if(active&&state==ST_FAULT) begin
                if(!output_valid||m_ready) begin
                    active<=0;output_valid<=0;done<=1;error<=1;
                end
            end else if(advance) begin
                read_valid<=request_read||(take_flush&&row_index!=0);
                if(request_read||take_flush) begin
                    read_first<=!take_flush&&beat_index==0;read_flush<=take_flush;
                    read_top_repeat<=row_index==1;read_bottom_repeat<=take_bottom;
                    read_previous_bank<=previous_bank;read_earlier_bank<=earlier_bank;
                    read_x<={1'b0,beat_index,2'b0};read_y<=row_index-1'b1;
                    read_keep<=expected_keep;read_input<=clean_input;
                end
                output_valid<=read_valid&&!read_first;
                if(read_valid) begin
                    if(!read_flush) begin
                        center_rows<=rows_now;center_x<=read_x;center_y<=read_y;center_keep<=read_keep;
                        for(row_capture=0;row_capture<3;row_capture=row_capture+1)
                            left_column[row_capture]<=read_first ? rows_now[row_capture*4] : center_rows[row_capture*4+3];
                    end
                    if(!read_first) begin
                        m_window<=next_window;
                        m_metadata<={frame_context,width,height,center_x,center_y,center_keep,
                            center_x==0&&center_y==0,center_x+13'd4>=width,
                            center_x+13'd4>=width&&center_y==height-1'b1};
                    end
                end
                if(take_input||take_bottom) begin
                    if(beat_index==last_beat) state<=ST_FLUSH;
                    else beat_index<=beat_index+1'b1;
                end else if(take_flush) begin
                    beat_index<=0;
                    if(row_index==height) state<=ST_DRAIN;
                    else begin
                        row_index<=row_index+1'b1;write_bank<=write_bank==2 ? 2'd0 : write_bank+1'b1;
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
