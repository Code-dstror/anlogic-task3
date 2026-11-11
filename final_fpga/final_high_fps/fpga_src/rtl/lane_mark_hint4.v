// RGB888 lane0 occupies bits23:0, with R in bits23:16. Native groups are
// observed only on their actual handshake. Each output bit is the OR over
// native [4*x..4*x+3,4*y..4*y+3], independent of pixel pipeline stalls.
// Two official ERAMs: one packed vertical accumulator and sixteen completed
// quarter rows. A coordinate/tag check detects a consumer that falls behind
// or precedes production; it degrades only the lane result.
module lane_mark_hint4(
    input wire clk,rst_n,clear,start,enable,
    input wire pixel_fire,
    input wire [95:0] pixel_rgb,
    input wire pixel_eol,
    input wire query,
    input wire [8:0] query_x,query_y,
    output wire [7:0] hint,
    output reg hint_valid,
    output reg alignment_error
);
    reg [8:0] native_group;
    reg [10:0] native_row;
    reg [4:0] chunk_offset;
    reg [4:0] chunk_index;
    reg [39:0] chunk;
    reg [8:0] row_tag[0:15];
    reg [15:0] row_valid;
    reg [4:0] read_offset;
    wire active=rst_n&&!clear&&enable;
    function [1:0] mark;
        input [23:0] rgb;
        reg [7:0] r,g,b,lo,hi,rglo,rghi,diff;
        begin
            r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];
            rglo=r<g?r:g;rghi=r>g?r:g;
            lo=rglo<b?rglo:b;hi=rghi>b?rghi:b;
            diff=r>g?r-g:g-r;
            mark[0]=lo>=95 && hi-lo<=40;
            mark[1]=r>=70&&g>=70&&({1'b0,b}+9'd24)<{1'b0,rglo}&&
                diff<=(rghi[7:2]>24 ? {2'd0,rghi[7:2]} : 8'd24);
        end
    endfunction
    wire [1:0] group_mark=mark(pixel_rgb[23:0])|mark(pixel_rgb[47:24])|
        mark(pixel_rgb[71:48])|mark(pixel_rgb[95:72]);
    wire [39:0] accum_old;
    wire accum_read=active&&pixel_fire&&chunk_offset==0;
    wire chunk_last=chunk_offset==19;
    wire [39:0] completed_chunk={group_mark,chunk[39:2]};
    wire [39:0] combined_chunk=native_row[1:0]==0 ? completed_chunk : completed_chunk|accum_old;
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(32),.ADDR_WIDTH(5)) vertical(
        .clk(clk),.wr_en(active&&pixel_fire&&chunk_last&&native_row[1:0]!=3),
        .wr_addr(chunk_index),.wr_data(combined_chunk),
        .rd_en(accum_read),.rd_addr(chunk_index),.rd_data(accum_old));
    wire [8:0] write_address={native_row[5:2],4'd0}+{native_row[5:2],3'd0}+chunk_index;
    wire [8:0] query_chunk=query_x/20;
    wire [8:0] query_address={query_y[3:0],4'd0}+{query_y[3:0],3'd0}+query_chunk;
    wire query_ok=query&&query_x<480&&query_y<270&&row_valid[query_y[3:0]]&&
        row_tag[query_y[3:0]]==query_y;
    wire [39:0] stored;
    td_sdp_ram40 #(.WIDTH(40),.DEPTH(384),.ADDR_WIDTH(9)) rows(
        .clk(clk),.wr_en(active&&pixel_fire&&chunk_last&&native_row[1:0]==3),
        .wr_addr(write_address),.wr_data(combined_chunk),
        .rd_en(active&&query_ok),.rd_addr(query_address),.rd_data(stored));
    assign hint=(stored>>(read_offset*2));
    always @(posedge clk)begin
        if(!rst_n||clear||start)begin
            native_group<=0;native_row<=0;chunk_offset<=0;chunk_index<=0;
            row_valid<=0;hint_valid<=0;alignment_error<=0;read_offset<=0;
        end else begin
            hint_valid<=active&&query_ok;
            if(active&&query)begin
                read_offset<=query_x%20;
                if(!query_ok)alignment_error<=1;
            end
            if(active&&pixel_fire)begin
                chunk<=completed_chunk;
                if(chunk_last)begin chunk_offset<=0;chunk_index<=chunk_index+1'b1;end
                else chunk_offset<=chunk_offset+1'b1;
                // A completed row is made visible atomically, including its
                // last packed word. Native input is fixed 1920 pixels/row.
                if(pixel_eol)begin
                    native_group<=0;native_row<=native_row+1'b1;chunk_index<=0;chunk_offset<=0;
                    if(native_row[1:0]==3)begin
                        row_valid[native_row[5:2]]<=1;
                        row_tag[native_row[5:2]]<=native_row[10:2];
                    end
                end else native_group<=native_group+1'b1;
            end
        end
    end
endmodule
