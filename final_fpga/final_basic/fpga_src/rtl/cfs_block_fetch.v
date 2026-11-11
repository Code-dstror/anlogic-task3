`timescale 1ns/1ps
// Fully qualify up to two blocks before canonical range bytes become visible.
module cfs_block_fetch #(
    parameter integer OFFICIAL_CRC_QUALIFIED=0,
    parameter [3:0] AXI_ID=4'd2
) (
    input wire i_clk,i_rst_n,i_cancel,
    input wire i_plan_valid,output wire o_plan_ready,
    input wire [383:0] i_frame,input wire [159:0] i_context,input wire [63:0] i_tag,
    input wire [31:0] i_generation,i_total_samples,i_block_count,
    input wire [27:0] i_slot_base,input wire [31:0] i_slot_span,i_data_offset,
    input wire [31:0] i_range_offset,i_first_block,input wire [11:0] i_range_length,i_first_offset,
    input wire [15:0] i_width,i_first_start_x,i_second_start_x,
    output wire [2:0] o_cache_write_enable,output wire [29:0] o_cache_write_address,
    output wire [95:0] o_cache_write_data,
    output wire [2:0] o_cache_read_enable,output wire [29:0] o_cache_read_address,
    input wire [95:0] i_cache_read_data,
    output wire o_crc_request_valid,input wire i_crc_request_ready,
    output wire [383:0] o_crc_frame,output wire [159:0] o_crc_context,output wire [63:0] o_crc_tag,
    output wire [31:0] o_crc_generation,o_crc_block_id,
    output wire o_crc_stored,output wire [11:0] o_crc_length,
    output wire o_crc_data_valid,input wire i_crc_data_ready,
    output wire [31:0] o_crc_data,output wire [3:0] o_crc_keep,output wire o_crc_last,
    input wire i_crc_result_valid,output wire o_crc_result_ready,
    input wire [383:0] i_crc_frame,input wire [159:0] i_crc_context,input wire [63:0] i_crc_tag,
    input wire [31:0] i_crc_generation,i_crc_block_id,i_crc,
    input wire [11:0] i_crc_length,
    input wire i_crc_stored,i_crc_ok,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
    output wire o_valid,input wire i_ready,output wire [127:0] o_data,
    output wire [15:0] o_keep,output wire o_last,
    output wire [383:0] o_frame,output wire [159:0] o_context,output wire [63:0] o_tag,
    output wire o_ack_valid,input wire i_ack_ready,output wire o_ack_ok,
    output wire [7:0] o_ack_error,output wire [11:0] o_ack_count,
    output reg [31:0] o_stale_crc_count,output reg o_protocol_fault,output wire o_idle
);
    localparam [4:0] S_IDLE=0,S_INDEX_ARM=1,S_AR=2,S_R=3,S_INDEX_CHECK=4,S_PAYLOAD_ARM=5,
        S_SPLIT_DRAIN=6,S_CRC_REQ=7,S_CRC_DATA=8,S_CRC_RESULT=9,S_DEC_ARM=10,
        S_DEC_STREAM=11,S_DEC_DRAIN=12,S_NEXT=13,S_OUTPUT=14,S_ACK=15,S_FAULT=16;
    reg [4:0] state;
    reg [383:0] frame;
    reg [159:0] context_q;
    reg [63:0] tag;
    reg [31:0] generation,total_samples,block_count,data_offset,first_block,block_id;
    reg [27:0] slot_base,read_address;
    reg [31:0] slot_span;
    reg [11:0] range_length,first_offset,raw_length,stored_length,samples,stored_received;
    reg [15:0] width,first_x,second_x;
    reg [7:0] error_code;
    reg second,need_second,read_index,compressed,crc_stored;
    reg [127:0] index_low,index_high,split_data;
    reg split_valid;
    reg [1:0] split_lane;
    reg [9:0] split_word;
    reg [4:0] read_beats;
    reg [5:0] read_number;
    reg [31:0] raw_crc,stored_crc;
    reg cache_pending;
    reg [9:0] cache_issued,cache_position;
    reg [11:0] decoded_count,decoder_input_count;
    reg decoder_seen,decoder_ok;
    reg [11:0] decoder_count;
    reg [11:0] output_count;
    reg output_valid;
    reg [127:0] output_data;
    reg [15:0] output_keep;
    reg output_last;
    reg [2:0] output_issued;
    reg output_pending;
    reg [1:0] output_lane;
    reg [9:0] output_word;
    reg output_bank;
    wire dec_start_ready,dec_ready,dec_valid,dec_last,dec_status_valid,dec_status_ok,dec_overflow;
    wire [31:0] dec_data;
    wire [3:0] dec_keep;
    wire [7:0] dec_error;
    wire [11:0] dec_input_count,dec_output_count;
    wire [159:0] dec_context,dec_status_context;
    wire [63:0] total_raw=({32'd0,i_total_samples}*10+7)>>3;
    wire [63:0] total_span={32'd0,i_data_offset}+{32'd0,i_block_count}*2560;
    wire plan_ok=i_generation!=0 && i_total_samples!=0 && i_block_count==(({32'd0,i_total_samples}+2047)>>11) &&
        i_slot_base[5:0]==0 && i_data_offset[5:0]==0 && {32'd0,i_block_count}*32<=i_data_offset &&
        total_span<=i_slot_span && {36'd0,i_slot_base}+i_slot_span<=64'h10000000 &&
        i_width!=0 && i_first_start_x<i_width && i_second_start_x<i_width &&
        i_range_length>=1 && i_range_length<=2560 && i_range_offset[3:0]==0 &&
        {32'd0,i_range_offset}+i_range_length<=total_raw && i_first_block<i_block_count &&
        i_first_offset<2560 && {32'd0,i_first_block}*2560+i_first_offset==i_range_offset;
    wire [31:0] remaining_samples=total_samples-(block_id<<11);
    wire [11:0] expected_samples=remaining_samples>=2048 ? 12'd2048 : remaining_samples[11:0];
    wire [15:0] expected_raw=(expected_samples*16'd10+7)>>3;
    wire [63:0] expected_offset={32'd0,data_offset}+{32'd0,block_id}*2560;
    wire [15:0] index_raw=index_low[47:32],index_stored=index_low[63:48];
    wire [15:0] index_aligned=index_low[79:64],index_samples=index_low[95:80];
    wire index_ok=index_low[31:0]==expected_offset && index_raw==expected_raw &&
        index_samples==expected_samples && index_stored>=1 && index_stored<=2560 &&
        index_aligned==((index_stored+16'd63)&16'hffc0) &&
        index_high[63:32]==generation && index_high[127:96]==block_id &&
        index_high[87:80]==1 && index_high[95:88]==1 &&
        ((index_high[71:64]==0 && index_high[79:72]==0 && index_stored==index_raw &&
          index_low[127:96]==index_high[31:0]) ||
         (index_high[71:64]==1 && index_high[79:72]==1 &&
          {1'b0,index_aligned}+17'd64<=(({1'b0,index_raw}+63)&17'h1ffc0))) &&
        expected_offset+2560<=slot_span && expected_offset<=32'hffffffff;
    function [4:0] burst_size;
        input [27:0] address;input [11:0] remaining;
        reg [12:0] boundary,beats;
        begin boundary=4096-{1'b0,address[11:0]};beats=({1'b0,remaining}+15)>>4;
            burst_size=beats>16 ? 5'd16 : beats[4:0];
            if(burst_size>(boundary>>4))burst_size=boundary>>4;
        end
    endfunction
    function [2:0] bytes4;
        input [3:0] keep;
        begin bytes4={2'd0,keep[0]}+keep[1]+keep[2]+keep[3];end
    endfunction
    wire [11:0] crc_length=crc_stored ? stored_length : raw_length;
    wire crc_match=i_crc_frame==frame && i_crc_context==context_q && i_crc_tag==tag &&
        i_crc_generation==generation && i_crc_block_id==block_id && i_crc_stored==crc_stored && i_crc_length==crc_length;
    wire [11:0] cache_remaining=(state==S_DEC_STREAM ? stored_length : crc_length)-{cache_position,2'b00};
    wire cache_consumer_ready=state==S_DEC_STREAM ? dec_ready : i_crc_data_ready;
    wire cache_read=(state==S_CRC_DATA || state==S_DEC_STREAM) &&
        (!cache_pending || cache_consumer_ready) &&
        {cache_issued,2'b00}<(state==S_DEC_STREAM ? stored_length : crc_length);
    wire cache_fire=cache_pending && cache_consumer_ready && (state==S_CRC_DATA || state==S_DEC_STREAM);
    wire cache_last=cache_remaining<=4;
    wire [3:0] cache_keep=cache_remaining>=4 ? 4'hf : (4'hf>>(4-cache_remaining));
    wire [1:0] read_bank=(state==S_DEC_STREAM || crc_stored) ? 2'd1 : (second ? 2'd2 : 2'd0);
    wire [31:0] cache_data=read_bank==0 ? i_cache_read_data[31:0] :
        (read_bank==1 ? i_cache_read_data[63:32] : i_cache_read_data[95:64]);
    wire raw_copy=state==S_CRC_DATA && crc_stored && !compressed && cache_fire;
    wire [2:0] raw_tail_bits={samples[1:0],1'b0};
    wire [7:0] raw_tail_byte=cache_data>>((bytes4(cache_keep)-1)*8);
    wire decoded_write=dec_valid && state==S_DEC_STREAM && decoded_count<raw_length;
    wire output_read=state==S_OUTPUT && !output_valid && output_issued<4 &&
        output_count<range_length && error_code==0 && !i_cancel;
    wire [12:0] absolute_position={1'b0,first_offset}+output_count;
    wire current_output_bank=absolute_position>=2560;
    wire [11:0] local_output_offset=current_output_bank ? absolute_position-2560 : absolute_position[11:0];
    wire [9:0] requested_output_word=local_output_offset[11:2]+output_issued;
    wire [11:0] output_remaining=range_length-output_count;
    wire r_fire=m_axi_rvalid && m_axi_rready;
    wire split_write=split_valid && error_code==0;
    wire [31:0] split_write_data=split_data>>(split_lane*32);
    wire crc_fire=o_crc_data_valid && i_crc_data_ready;
    assign o_plan_ready=i_rst_n && state==S_IDLE && !o_protocol_fault;
    assign o_crc_request_valid=i_rst_n && state==S_CRC_REQ;
    assign o_crc_frame=frame;assign o_crc_context=context_q;assign o_crc_tag=tag;
    assign o_crc_generation=generation;assign o_crc_block_id=block_id;
    assign o_crc_stored=crc_stored;assign o_crc_length=crc_length;
    assign o_crc_data_valid=i_rst_n && state==S_CRC_DATA && cache_pending;
    assign o_crc_data=cache_data;assign o_crc_keep=cache_keep;assign o_crc_last=cache_last;
    assign o_crc_result_ready=i_rst_n;
    assign o_cache_write_enable={((raw_copy || decoded_write) && second),split_write,
        ((raw_copy || decoded_write) && !second)};
    assign o_cache_write_address={
        (decoded_write ? decoded_count[11:2] : cache_position),
        (split_word+{8'd0,split_lane}),
        (decoded_write ? decoded_count[11:2] : cache_position)};
    assign o_cache_write_data={decoded_write ? dec_data : cache_data,
        split_write_data,decoded_write ? dec_data : cache_data};
    assign o_cache_read_enable={((cache_read && read_bank==2) || (output_read && current_output_bank)),
        (cache_read && read_bank==1),((cache_read && read_bank==0) || (output_read && !current_output_bank))};
    assign o_cache_read_address={output_read ? requested_output_word : cache_issued,
        cache_issued,output_read ? requested_output_word : cache_issued};
    assign m_axi_arid=AXI_ID;assign m_axi_araddr=read_address;
    assign m_axi_arlen={3'd0,read_beats}-8'd1;assign m_axi_arsize=4;assign m_axi_arburst=1;
    assign m_axi_arvalid=i_rst_n && state==S_AR;
    assign m_axi_rready=i_rst_n && state==S_R && (!split_valid || read_index || error_code!=0 || i_cancel);
    assign o_valid=i_rst_n && output_valid;assign o_data=output_data;
    assign o_keep=output_keep;assign o_last=output_last;
    assign o_frame=frame;assign o_context=context_q;assign o_tag=tag;
    assign o_ack_valid=i_rst_n && state==S_ACK;
    assign o_ack_ok=error_code==0;assign o_ack_error=error_code;assign o_ack_count=output_count;
    assign o_idle=state==S_IDLE;
    cfs_block_decoder u_decoder (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_abort(error_code!=0 || i_cancel),
        .i_start_valid(state==S_DEC_ARM),.o_start_ready(dec_start_ready),
        .i_sample_count(samples),.i_stored_length(stored_length),.i_width(width),
        .i_block_start_x(second ? second_x : first_x),.i_context(context_q),
        .i_valid(state==S_DEC_STREAM && cache_pending && error_code==0 && !i_cancel),
        .o_ready(dec_ready),.i_data(cache_data),.i_keep(cache_keep),.i_last(cache_last),
        .o_valid(dec_valid),.i_ready(1'b1),.o_data(dec_data),.o_keep(dec_keep),.o_last(dec_last),
        .o_context(dec_context),.o_status_valid(dec_status_valid),.i_status_ready(1'b1),
        .o_status_ok(dec_status_ok),.o_status_error(dec_error),
        .o_status_overflow(dec_overflow),
        .o_status_input_length(dec_input_count),.o_status_output_length(dec_output_count),
        .o_status_context(dec_status_context)
    );
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            state<=S_IDLE;frame<=0;context_q<=0;tag<=0;generation<=0;total_samples<=0;block_count<=0;
            data_offset<=0;first_block<=0;block_id<=0;slot_base<=0;slot_span<=0;
            range_length<=0;first_offset<=0;width<=0;first_x<=0;second_x<=0;raw_length<=0;
            stored_length<=0;samples<=0;stored_received<=0;error_code<=0;second<=0;need_second<=0;
            read_index<=0;compressed<=0;crc_stored<=0;index_low<=0;index_high<=0;
            split_data<=0;split_valid<=0;split_lane<=0;split_word<=0;read_address<=0;read_beats<=0;read_number<=0;
            raw_crc<=0;stored_crc<=0;cache_pending<=0;cache_issued<=0;cache_position<=0;
            decoded_count<=0;decoder_input_count<=0;decoder_seen<=0;decoder_ok<=0;decoder_count<=0;
            output_count<=0;output_valid<=0;output_data<=0;output_keep<=0;output_last<=0;
            output_issued<=0;output_pending<=0;output_lane<=0;output_word<=0;output_bank<=0;
            o_stale_crc_count<=0;o_protocol_fault<=AXI_ID>3;
        end else begin
            if(i_plan_valid && o_plan_ready) begin
                frame<=i_frame;context_q<=i_context;tag<=i_tag;generation<=i_generation;
                total_samples<=i_total_samples;block_count<=i_block_count;data_offset<=i_data_offset;
                first_block<=i_first_block;block_id<=i_first_block;slot_base<=i_slot_base;slot_span<=i_slot_span;
                range_length<=i_range_length;first_offset<=i_first_offset;width<=i_width;
                first_x<=i_first_start_x;second_x<=i_second_start_x;second<=0;
                need_second<=({1'b0,i_first_offset}+i_range_length)>2560;
                error_code<=!plan_ok ? 8'd1 : (!OFFICIAL_CRC_QUALIFIED ? 8'd11 : 8'd0);
                output_count<=0;output_valid<=0;cache_pending<=0;split_valid<=0;
                state<=plan_ok && OFFICIAL_CRC_QUALIFIED ? S_INDEX_ARM : S_ACK;
            end
            if(i_cancel && state!=S_IDLE && state!=S_ACK && error_code==0)error_code<=8'd9;
            if(state==S_INDEX_ARM) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else begin
                    read_index<=1;read_address<=slot_base+block_id*32;read_beats<=2;
                    read_number<=0;index_low<=0;index_high<=0;state<=S_AR;
                end
            end
            if(state==S_AR && m_axi_arready)state<=S_R;
            if(r_fire) begin
                if(m_axi_rid!=AXI_ID) begin o_protocol_fault<=1;state<=S_FAULT;end
                else begin
                    if(read_number<63)read_number<=read_number+1;
                    if(m_axi_rresp!=0 && error_code==0)error_code<=8'd6;
                    if(m_axi_rlast!=(read_number+1==read_beats) && error_code==0)error_code<=8'd7;
                    if(read_index) begin
                        if(read_number==0)index_low<=m_axi_rdata;
                        if(read_number==1)index_high<=m_axi_rdata;
                    end else if(error_code==0 && !i_cancel && stored_received<stored_length && read_number<read_beats) begin
                        split_data<=m_axi_rdata;split_valid<=1;split_lane<=0;split_word<=stored_received[11:2];
                        stored_received<=stored_received+((stored_length-stored_received)>=16 ? 12'd16 : stored_length-stored_received);
                    end
                    if(m_axi_rlast)state<=read_index ? S_INDEX_CHECK : S_SPLIT_DRAIN;
                end
            end
            if(split_valid) begin
                split_lane<=split_lane+1;
                if(split_lane==3)split_valid<=0;
            end
            if(state==S_INDEX_CHECK) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else if(!index_ok) begin error_code<=8'd2;state<=S_ACK;end
                else begin
                    raw_length<=index_raw[11:0];stored_length<=index_stored[11:0];samples<=index_samples[11:0];
                    raw_crc<=index_low[127:96];stored_crc<=index_high[31:0];compressed<=index_high[71:64]==1;
                    stored_received<=0;state<=S_PAYLOAD_ARM;
                end
            end
            if(state==S_PAYLOAD_ARM) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else begin
                    read_index<=0;read_address<=slot_base+expected_offset[27:0]+stored_received;
                    read_beats<=burst_size(slot_base+expected_offset[27:0]+stored_received,stored_length-stored_received);
                    read_number<=0;state<=S_AR;
                end
            end
            if(state==S_SPLIT_DRAIN && !split_valid) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else if(stored_received==stored_length) begin crc_stored<=1;state<=S_CRC_REQ;end
                else state<=S_PAYLOAD_ARM;
            end
            if(state==S_CRC_REQ && i_crc_request_ready) begin cache_issued<=0;cache_pending<=0;state<=S_CRC_DATA;end
            if(cache_fire) begin
                cache_pending<=0;
                if(state==S_CRC_DATA && cache_last)state<=S_CRC_RESULT;
                if(state==S_DEC_STREAM)decoder_input_count<=decoder_input_count+bytes4(cache_keep);
                if(raw_copy && cache_last && raw_tail_bits!=0 && (raw_tail_byte>>raw_tail_bits)!=0 && error_code==0)
                    error_code<=8'd2;
            end
            if(cache_read) begin cache_pending<=1;cache_position<=cache_issued;cache_issued<=cache_issued+1;end
            if(i_crc_result_valid) begin
                if(state==S_CRC_RESULT && crc_match) begin
                    if(!i_crc_ok || i_crc!=(crc_stored ? stored_crc : raw_crc)) begin
                        if(error_code==0)error_code<=8'd5;state<=S_ACK;
                    end else if(error_code!=0 || i_cancel)state<=S_ACK;
                    else if(crc_stored && compressed)state<=S_DEC_ARM;
                    else state<=S_NEXT;
                end else if(o_stale_crc_count!=32'hffffffff)o_stale_crc_count<=o_stale_crc_count+1;
            end
            if(state==S_DEC_ARM) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else if(dec_start_ready) begin
                    state<=S_DEC_STREAM;cache_issued<=0;cache_pending<=0;decoded_count<=0;
                    decoder_input_count<=0;decoder_seen<=0;
                end
            end
            if(decoded_write)decoded_count<=decoded_count+bytes4(dec_keep);
            if(dec_status_valid && (state==S_DEC_STREAM || state==S_DEC_DRAIN)) begin
                decoder_seen<=1;decoder_ok<=dec_status_ok && dec_input_count==stored_length &&
                    dec_output_count==raw_length && dec_status_context==context_q;
                decoder_count<=dec_output_count;
            end
            if(state==S_DEC_STREAM && decoder_seen) begin
                cache_pending<=0;
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else if(!decoder_ok || decoded_count!=raw_length) begin error_code<=8'd4;state<=S_ACK;end
                else begin crc_stored<=0;state<=S_CRC_REQ;end
            end
            if(state==S_NEXT) begin
                if(error_code!=0 || i_cancel)state<=S_ACK;
                else if(need_second && !second) begin second<=1;block_id<=block_id+1;state<=S_INDEX_ARM;end
                else begin state<=S_OUTPUT;output_issued<=0;output_pending<=0;end
            end
            if(output_read) begin
                output_pending<=1;output_lane<=output_issued[1:0];output_word<=requested_output_word;
                output_bank<=current_output_bank;output_issued<=output_issued+1;
            end else if(output_pending)output_pending<=0;
            if(output_pending && state==S_OUTPUT && !output_valid && error_code==0 && !i_cancel) begin
                output_data[output_lane*32+:32]<=output_bank ? i_cache_read_data[95:64] : i_cache_read_data[31:0];
                if(output_lane==3) begin
                    output_valid<=1;output_keep<=output_remaining>=16 ? 16'hffff : (16'hffff>>(16-output_remaining));
                    output_last<=output_remaining<=16;
                end
            end
            if(state==S_OUTPUT && o_valid && i_ready) begin
                output_valid<=0;output_count<=output_count+(output_remaining>=16 ? 12'd16 : output_remaining);
                output_issued<=0;output_pending<=0;
                if(output_last || error_code!=0 || i_cancel)state<=S_ACK;
            end
            if(state==S_OUTPUT && (error_code!=0 || i_cancel) && !output_valid && !output_pending)state<=S_ACK;
            if(state==S_ACK && i_ack_ready)state<=S_IDLE;
        end
    end
endmodule
