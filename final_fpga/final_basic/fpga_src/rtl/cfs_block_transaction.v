`timescale 1ns/1ps
// BLOCK transactions only. RAW frame/slot commit and official CRC stay external.
module cfs_block_transaction #(
    parameter integer OFFICIAL_CRC_QUALIFIED = 0,
    parameter [3:0] AXI_ID = 4'd2
) (
    input wire i_clk,i_rst_n,i_cancel,i_source_abort,
    input wire i_plan_valid,output wire o_plan_ready,
    input wire [383:0] i_frame,input wire [159:0] i_context,
    input wire [63:0] i_tag,input wire [31:0] i_generation,i_block_id,
    input wire [27:0] i_slot_base,input wire [31:0] i_slot_span,i_data_offset,
    input wire [11:0] i_samples,input wire [15:0] i_width,i_start_x,
    input wire i_valid,output wire o_ready,input wire [31:0] i_data,
    input wire [3:0] i_keep,input wire i_last,
    input wire i_fast_plan_valid,output wire o_fast_plan_ready,
    input wire [383:0] i_fast_frame,input wire [159:0] i_fast_context,
    input wire [63:0] i_fast_tag,input wire [31:0] i_fast_generation,i_fast_block_id,
    input wire [27:0] i_fast_slot_base,input wire [31:0] i_fast_slot_span,i_fast_data_offset,
    input wire [11:0] i_fast_samples,
    input wire i_fast_cancel,i_fast_source_abort,
    input wire i_fast_valid,output wire o_fast_ready,
    input wire [127:0] i_fast_data,input wire [15:0] i_fast_keep,
    input wire i_fast_last,input wire [9:0] i_fast_available,
    output wire o_fast_crc_start_valid,input wire i_fast_crc_start_ready,
    output wire [11:0] o_fast_crc_length,
    output wire o_fast_crc_tap_valid,input wire i_fast_crc_tap_ready,
    output wire [127:0] o_fast_crc_tap_data,
    output wire [15:0] o_fast_crc_tap_keep,output wire o_fast_crc_tap_last,
    input wire i_fast_crc_result_valid,output wire o_fast_crc_result_ready,
    input wire [383:0] i_fast_crc_frame,input wire [159:0] i_fast_crc_context,
    input wire [63:0] i_fast_crc_tag,
    input wire [31:0] i_fast_crc_generation,i_fast_crc_block_id,i_fast_crc,
    input wire [11:0] i_fast_crc_length,
    input wire i_fast_crc_ok,
    output wire o_crc_request_valid,input wire i_crc_request_ready,
    output wire [383:0] o_crc_frame,output wire [159:0] o_crc_context,
    output wire [63:0] o_crc_tag,output wire [31:0] o_crc_generation,o_crc_block_id,
    output wire o_crc_stored,output wire [11:0] o_crc_length,
    output wire o_crc_data_valid,input wire i_crc_data_ready,
    output wire [31:0] o_crc_data,output wire [3:0] o_crc_keep,output wire o_crc_last,
    input wire i_crc_result_valid,output wire o_crc_result_ready,
    input wire [383:0] i_crc_frame,input wire [159:0] i_crc_context,
    input wire [63:0] i_crc_tag,input wire [31:0] i_crc_generation,i_crc_block_id,i_crc,
    input wire [11:0] i_crc_length,
    input wire i_crc_stored,i_crc_ok,
    output wire [1:0] o_cache_write_enable,output wire [19:0] o_cache_write_address,
    output wire [63:0] o_cache_write_data,
    output wire [1:0] o_cache_read_enable,output wire [19:0] o_cache_read_address,
    input wire [63:0] i_cache_read_data,
    output wire [3:0] m_axi_awid,output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,output wire m_axi_awvalid,input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,output wire m_axi_bready,
    output wire o_ack_valid,input wire i_ack_ready,output wire o_ack_ok,
    output wire [7:0] o_ack_error,output wire [1:0] o_ack_reason,
    output wire [383:0] o_ack_frame,output wire [159:0] o_ack_context,
    output wire [63:0] o_ack_tag,output wire [31:0] o_ack_generation,o_ack_block_id,
    output wire [11:0] o_ack_stored_length,output wire o_ack_compressed,
    output wire o_fast_ack_valid,input wire i_fast_ack_ready,output wire o_fast_ack_ok,
    output wire [7:0] o_fast_ack_error,
    output wire [383:0] o_fast_ack_frame,output wire [159:0] o_fast_ack_context,
    output wire [63:0] o_fast_ack_tag,output wire [31:0] o_fast_ack_generation,o_fast_ack_block_id,
    output reg [31:0] o_stale_crc_count,output reg o_protocol_fault,output wire o_idle
);
    localparam [3:0] N_IDLE=0,N_ARM=1,N_CAPTURE=2,N_CRC_REQ=3,N_CRC_DATA=4,
        N_CRC_RESULT=5,N_PAYLOAD=6,N_INDEX=7,N_ACK=8;
    localparam [2:0] F_IDLE=0,F_CRC_START=1,F_PAYLOAD=2,F_CRC_RESULT=3,F_INDEX=4,F_ACK=5;
    localparam [2:0] W_IDLE=0,W_AW=1,W_DATA=2,W_B=3,W_FAULT=4;
    reg [3:0] ns;
    reg [2:0] fs,ws;
    reg [383:0] frame,fframe;
    reg [159:0] context_q,fcontext;
    reg [63:0] tag,ftag;
    reg [31:0] generation,block_id,fgeneration,fblock_id;
    reg [27:0] payload_address,index_address,fpayload_address,findex_address;
    reg [11:0] samples,raw_length,stored_length,fraw_length,input_count,candidate_count;
    reg [11:0] fcount,payload_count;
    reg [15:0] width,start_x;
    reg [7:0] error_code,ferror;
    reg [1:0] reason;
    reg compressed,source_closed,fsource_closed,crc_kind;
    reg [31:0] raw_crc,stored_crc,fraw_crc;
    reg crc_pending;
    reg [9:0] crc_issued,crc_position;
    reg [27:0] wa;
    reg [4:0] burst_beats;
    reg [4:0] beat_number;
    reg writer_fast,writer_index;
    reg [127:0] write_data;
    reg write_valid,read_pending;
    reg [1:0] read_lane;
    reg [9:0] read_word;
    reg [2:0] issued_lane;
    reg [9:0] issued_word;
    reg [11:0] fast_payload_count;
    reg fast_crc_done,fast_crc_ok,fast_fill;
    reg encoder_done,encoder_ok,encoder_overflow;
    reg [11:0] encoder_input_length,encoder_output_length;
    reg [159:0] encoder_context;
    wire enc_start_ready,enc_ready,enc_valid,enc_last,enc_status_valid,enc_status_ok,enc_overflow;
    wire [31:0] enc_data;
    wire [3:0] enc_keep;
    wire [7:0] enc_error;
    wire [11:0] enc_input_length,enc_output_length;
    wire [159:0] enc_context,enc_status_context;
    wire [15:0] raw_declared=(i_samples*16'd10+16'd7)>>3;
    wire [15:0] fast_declared=(i_fast_samples*16'd10+16'd7)>>3;
    wire [63:0] declared_offset={32'd0,i_data_offset}+i_block_id*64'd2560;
    wire [63:0] fast_offset={32'd0,i_fast_data_offset}+i_fast_block_id*64'd2560;
    wire plan_ok=i_samples>=1 && i_samples<=2048 && i_generation!=0 && i_width!=0 &&
        i_start_x<i_width && i_slot_base[5:0]==0 && i_data_offset[5:0]==0 &&
        ({32'd0,i_block_id}+1)*64'd32<=i_data_offset &&
        declared_offset+2560<=i_slot_span && {36'd0,i_slot_base}+i_slot_span<=64'h10000000;
    wire fast_plan_ok=i_fast_samples>=1 && i_fast_samples<=2048 && i_fast_generation!=0 &&
        i_fast_slot_base[5:0]==0 && i_fast_data_offset[5:0]==0 &&
        ({32'd0,i_fast_block_id}+1)*64'd32<=i_fast_data_offset &&
        fast_offset+2560<=i_fast_slot_span && {36'd0,i_fast_slot_base}+i_fast_slot_span<=64'h10000000;
    function [4:0] keep_bytes16;
        input [15:0] keep;
        integer k;
        begin keep_bytes16=0;for(k=0;k<16;k=k+1)keep_bytes16=keep_bytes16+keep[k];end
    endfunction
    function [2:0] keep_bytes4;
        input [3:0] keep;
        begin keep_bytes4={2'd0,keep[0]}+keep[1]+keep[2]+keep[3];end
    endfunction
    function [15:0] byte_mask;
        input [11:0] remaining;
        begin byte_mask=remaining>=16 ? 16'hffff : (16'hffff>>(16-remaining));end
    endfunction
    function [4:0] next_burst;
        input [27:0] address;input [11:0] remaining;
        reg [12:0] boundary;reg [12:0] needed;
        begin boundary=13'd4096-{1'b0,address[11:0]};needed=({1'b0,remaining}+15)>>4;
            next_burst=needed>16 ? 5'd16 : needed[4:0];
            if(next_burst>(boundary>>4))next_burst=boundary>>4;
        end
    endfunction
    wire [12:0] input_end={1'b0,input_count}+keep_bytes4(i_keep);
    wire input_fire=i_valid && o_ready;
    wire input_bad=(i_keep!=1 && i_keep!=3 && i_keep!=7 && i_keep!=15) ||
        (!i_last && i_keep!=15) || input_end>raw_length || i_last!=(input_end==raw_length);
    wire [11:0] crc_length=crc_kind ? stored_length : raw_length;
    wire normal_crc_match=i_crc_frame==frame && i_crc_context==context_q && i_crc_tag==tag &&
        i_crc_generation==generation && i_crc_block_id==block_id && i_crc_stored==crc_kind && i_crc_length==crc_length;
    wire fast_crc_match=i_fast_crc_frame==fframe && i_fast_crc_context==fcontext &&
        i_fast_crc_tag==ftag && i_fast_crc_generation==fgeneration && i_fast_crc_block_id==fblock_id && i_fast_crc_length==fraw_length;
    wire crc_read=ns==N_CRC_DATA && (!crc_pending || i_crc_data_ready) &&
        {crc_issued,2'b00}<crc_length;
    wire crc_fire=o_crc_data_valid && i_crc_data_ready;
    wire [11:0] crc_remaining=crc_length-{crc_position,2'b00};
    // Four synchronous reads feed one explicitly held 128-bit W beat.
    wire issue_word=ws==W_DATA && !writer_fast && !writer_index && !write_valid && issued_lane<4;
    wire selected_bank=(ns==N_CRC_DATA) ? (crc_kind && compressed) : compressed;
    wire [9:0] cache_read_address=ns==N_CRC_DATA ? crc_issued : issued_word;
    wire [31:0] selected_cache_data=selected_bank ? i_cache_read_data[63:32] : i_cache_read_data[31:0];
    wire [255:0] normal_index={block_id,8'd1,8'd1,(compressed ? 8'd1 : 8'd0),
        (compressed ? 8'd1 : 8'd0),generation,stored_crc,raw_crc,{4'd0,samples},
        (({4'd0,stored_length}+16'd63)&16'hffc0),{4'd0,stored_length},{4'd0,raw_length},
        (payload_address-index_address+block_id*32'd32)};
    reg [11:0] fsamples;
    wire [255:0] fast_index={fblock_id,8'd1,8'd1,8'd0,8'd0,fgeneration,fraw_crc,fraw_crc,
        {4'd0,fsamples},(({4'd0,fraw_length}+16'd63)&16'hffc0),{4'd0,fraw_length},
        {4'd0,fraw_length},(fpayload_address-findex_address+fblock_id*32'd32)};
    wire [11:0] writer_remaining=writer_fast ? fraw_length-fast_payload_count : stored_length-payload_count;
    wire fast_transfer=m_axi_wvalid && m_axi_wready && writer_fast && !writer_index;
    wire [4:0] fast_span_beats=next_burst(fpayload_address+fast_payload_count,fraw_length-fast_payload_count);
    wire [4:0] fast_backed_beats=i_fast_available>=fast_span_beats ? fast_span_beats : i_fast_available[4:0];
    wire fast_discard=fs==F_PAYLOAD && ferror!=0 && !(ws!=W_IDLE && writer_fast && !writer_index);
    wire fast_input_fire=i_fast_valid && o_fast_ready;
    wire [12:0] fast_end={1'b0,fcount}+keep_bytes16(i_fast_keep);
    wire [2:0] fast_tail_bits={fsamples[1:0],1'b0};
    wire [7:0] fast_tail_byte=i_fast_data>>((keep_bytes16(i_fast_keep)-1)*8);
    wire fast_bad=i_fast_keep==0 || (i_fast_keep & (i_fast_keep+16'd1))!=0 ||
        (!i_fast_last && i_fast_keep!=16'hffff) || fast_end>fraw_length ||
        i_fast_last!=(fast_end==fraw_length) ||
        (i_fast_last && fast_tail_bits!=0 && (fast_tail_byte>>fast_tail_bits)!=0);
    wire current_cancel=writer_fast ? i_fast_cancel : i_cancel;
    wire current_error=writer_fast ? ferror!=0 : error_code!=0;
    wire normal_crc_stale=i_crc_result_valid && !(ns==N_CRC_RESULT && normal_crc_match);
    wire fast_crc_stale=i_fast_crc_result_valid &&
        !(fs!=F_IDLE && fs!=F_ACK && fast_crc_match && fsource_closed && !fast_crc_done);
    wire [1:0] stale_increment={1'b0,normal_crc_stale}+{1'b0,fast_crc_stale};
    assign o_plan_ready=i_rst_n && ns==N_IDLE && !o_protocol_fault;
    assign o_fast_plan_ready=i_rst_n && fs==F_IDLE && !o_protocol_fault;
    assign o_ready=i_rst_n && ns==N_CAPTURE && !source_closed &&
        ((error_code==0 && !i_cancel) ? enc_ready : 1'b1);
    assign o_fast_ready=i_rst_n &&
        ((ws==W_DATA && writer_fast && !writer_index) ?
            (m_axi_wready && i_fast_crc_tap_ready && !fast_fill) :
            (!fsource_closed && fast_discard && i_fast_crc_tap_ready));
    assign o_fast_crc_start_valid=i_rst_n && fs==F_CRC_START && !fsource_closed && !i_fast_source_abort;
    assign o_fast_crc_length=fraw_length;
    assign o_fast_crc_tap_valid=fast_input_fire;
    assign o_fast_crc_tap_data=i_fast_data;
    assign o_fast_crc_tap_keep=i_fast_keep;
    assign o_fast_crc_tap_last=i_fast_last;
    assign o_fast_crc_result_ready=i_rst_n;
    assign o_crc_request_valid=i_rst_n && ns==N_CRC_REQ;
    assign o_crc_frame=frame;assign o_crc_context=context_q;assign o_crc_tag=tag;
    assign o_crc_generation=generation;assign o_crc_block_id=block_id;
    assign o_crc_stored=crc_kind;assign o_crc_length=crc_length;
    assign o_crc_data_valid=i_rst_n && ns==N_CRC_DATA && crc_pending;
    assign o_crc_data=selected_cache_data;
    assign o_crc_keep=crc_remaining>=4 ? 4'hf : (4'hf>>(4-crc_remaining));
    assign o_crc_last=crc_remaining<=4;
    assign o_crc_result_ready=i_rst_n;
    assign o_cache_write_enable={(enc_valid && ns==N_CAPTURE && candidate_count<2560),
        (input_fire && !input_bad && input_count<2560)};
    assign o_cache_write_address={candidate_count[11:2],input_count[11:2]};
    assign o_cache_write_data={enc_data,i_data};
    assign o_cache_read_enable={(crc_read || issue_word) && selected_bank,
        (crc_read || issue_word) && !selected_bank};
    assign o_cache_read_address={cache_read_address,cache_read_address};
    assign m_axi_awid=AXI_ID;assign m_axi_awaddr=wa;
    assign m_axi_awlen={3'd0,burst_beats}-8'd1;assign m_axi_awsize=3'd4;
    assign m_axi_awburst=2'd1;assign m_axi_awvalid=i_rst_n && ws==W_AW;
    assign m_axi_wvalid=i_rst_n && ws==W_DATA &&
        (writer_fast && !writer_index ?
            (fast_fill || (i_fast_valid && i_fast_crc_tap_ready)) : (writer_index || write_valid));
    assign m_axi_wdata=writer_index ? (writer_fast ?
        (beat_number==0 ? fast_index[127:0] : fast_index[255:128]) :
        (beat_number==0 ? normal_index[127:0] : normal_index[255:128])) :
        (writer_fast ? (fast_fill ? 128'd0 : i_fast_data) : write_data);
    assign m_axi_wstrb=writer_index ? 16'hffff :
        ((writer_fast && fast_fill) ? 16'd0 : byte_mask(writer_remaining));
    assign m_axi_wlast=beat_number+1==burst_beats;
    assign m_axi_bready=i_rst_n && ws==W_B;
    assign o_ack_valid=i_rst_n && ns==N_ACK;
    assign o_ack_ok=error_code==0;assign o_ack_error=error_code;
    assign o_ack_reason=reason;assign o_ack_frame=frame;assign o_ack_context=context_q;
    assign o_ack_tag=tag;assign o_ack_generation=generation;assign o_ack_block_id=block_id;
    assign o_ack_stored_length=stored_length;assign o_ack_compressed=compressed;
    assign o_fast_ack_valid=i_rst_n && fs==F_ACK;
    assign o_fast_ack_ok=ferror==0;assign o_fast_ack_error=ferror;
    assign o_fast_ack_frame=fframe;assign o_fast_ack_context=fcontext;assign o_fast_ack_tag=ftag;
    assign o_fast_ack_generation=fgeneration;assign o_fast_ack_block_id=fblock_id;
    assign o_idle=ns==N_IDLE && fs==F_IDLE && ws==W_IDLE;
    cfs_block_encoder u_encoder (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.i_abort((i_cancel || error_code!=0) && ns!=N_ACK),
        .i_start_valid(ns==N_ARM),.o_start_ready(enc_start_ready),.i_sample_count(samples),
        .i_candidate_limit(raw_length),.i_width(width),.i_block_start_x(start_x),.i_context(context_q),
        .i_valid(i_valid && ns==N_CAPTURE && error_code==0 && !i_cancel),.o_ready(enc_ready),
        .i_data(i_data),.i_keep(i_keep),.i_last(i_last),.o_valid(enc_valid),.i_ready(1'b1),
        .o_data(enc_data),.o_keep(enc_keep),.o_last(enc_last),.o_context(enc_context),
        .o_status_valid(enc_status_valid),.i_status_ready(ns==N_CAPTURE),.o_status_ok(enc_status_ok),
        .o_status_error(enc_error),.o_status_overflow(enc_overflow),
        .o_status_input_length(enc_input_length),.o_status_output_length(enc_output_length),
        .o_status_context(enc_status_context)
    );
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            ns<=N_IDLE;fs<=F_IDLE;ws<=W_IDLE;frame<=0;context_q<=0;tag<=0;generation<=0;block_id<=0;
            fframe<=0;fcontext<=0;ftag<=0;fgeneration<=0;fblock_id<=0;samples<=0;fsamples<=0;
            raw_length<=0;stored_length<=0;fraw_length<=0;width<=0;start_x<=0;
            payload_address<=0;index_address<=0;fpayload_address<=0;findex_address<=0;
            input_count<=0;candidate_count<=0;fcount<=0;payload_count<=0;fast_payload_count<=0;
            error_code<=0;ferror<=0;reason<=0;compressed<=0;source_closed<=0;fsource_closed<=0;
            raw_crc<=0;stored_crc<=0;fraw_crc<=0;crc_kind<=0;crc_pending<=0;crc_issued<=0;crc_position<=0;
            wa<=0;burst_beats<=0;beat_number<=0;writer_fast<=0;writer_index<=0;write_data<=0;
            write_valid<=0;read_pending<=0;read_lane<=0;read_word<=0;issued_lane<=0;issued_word<=0;
            o_stale_crc_count<=0;o_protocol_fault<=AXI_ID>3;
            encoder_done<=0;encoder_ok<=0;encoder_overflow<=0;encoder_input_length<=0;
            encoder_output_length<=0;encoder_context<=0;
            fast_crc_done<=0;fast_crc_ok<=0;fast_fill<=0;
        end else begin
            if(stale_increment!=0)o_stale_crc_count<=
                o_stale_crc_count>=32'hffffffff-stale_increment ? 32'hffffffff : o_stale_crc_count+stale_increment;
            if(i_plan_valid && o_plan_ready) begin
                frame<=i_frame;context_q<=i_context;tag<=i_tag;generation<=i_generation;block_id<=i_block_id;
                payload_address<=i_slot_base+declared_offset[27:0];index_address<=i_slot_base+i_block_id*32;
                samples<=i_samples;raw_length<=raw_declared[11:0];stored_length<=raw_declared[11:0];
                width<=i_width;start_x<=i_start_x;input_count<=0;candidate_count<=0;payload_count<=0;
                source_closed<=!plan_ok;compressed<=0;reason<=0;error_code<=plan_ok ? 0 : 1;
                crc_kind<=0;raw_crc<=0;stored_crc<=0;ns<=plan_ok ? N_ARM : N_ACK;
                encoder_done<=0;
            end
            if(i_fast_plan_valid && o_fast_plan_ready) begin
                fframe<=i_fast_frame;fcontext<=i_fast_context;ftag<=i_fast_tag;
                fgeneration<=i_fast_generation;fblock_id<=i_fast_block_id;fsamples<=i_fast_samples;
                fpayload_address<=i_fast_slot_base+fast_offset[27:0];
                findex_address<=i_fast_slot_base+i_fast_block_id*32;
                fraw_length<=fast_declared[11:0];fcount<=0;fast_payload_count<=0;fraw_crc<=0;
                fast_crc_done<=0;fast_crc_ok<=0;fast_fill<=0;
                fsource_closed<=!fast_plan_ok;ferror<=fast_plan_ok ? 0 : 1;
                fs<=fast_plan_ok ? F_CRC_START : F_ACK;
            end
            if(ns!=N_IDLE && ns!=N_ACK && i_cancel && error_code==0)error_code<=8'd9;
            if(fs!=F_IDLE && fs!=F_ACK && i_fast_cancel && ferror==0)ferror<=8'd9;
            if(ns!=N_IDLE && ns!=N_ACK && i_source_abort) begin source_closed<=1;if(error_code==0)error_code<=8'd3;end
            if(fs!=F_IDLE && fs!=F_ACK && i_fast_source_abort) begin
                fsource_closed<=1;if(ferror==0)ferror<=8'd3;
                // Ordered source-abort proves no real held/queued DATA remains.
                // Already promised AW/W still drain, with no payload overwrite.
                if(ws!=W_IDLE && writer_fast && !writer_index)fast_fill<=1;
            end
            if(ns==N_ARM && (i_cancel || i_source_abort || error_code!=0)) begin
                encoder_done<=1;ns<=N_CAPTURE;
            end else if(ns==N_ARM && enc_start_ready)ns<=N_CAPTURE;
            if(input_fire) begin
                input_count<=input_end[11:0];
                if(input_bad && error_code==0)error_code<=8'd2;
                if(i_last || input_end>=raw_length)source_closed<=1;
            end
            if(enc_valid && ns==N_CAPTURE)candidate_count<=candidate_count+keep_bytes4(enc_keep);
            if(ns==N_CAPTURE && enc_status_valid) begin
                encoder_done<=1;encoder_ok<=enc_status_ok;encoder_overflow<=enc_overflow;
                encoder_input_length<=enc_input_length;encoder_output_length<=enc_output_length;
                encoder_context<=enc_status_context;
            end
            if(ns==N_CAPTURE && encoder_done && source_closed) begin
                if(error_code!=0 || i_cancel || i_source_abort)ns<=N_ACK;
                else if((!encoder_ok && !encoder_overflow) || encoder_input_length!=raw_length || encoder_context!=context_q) begin
                    error_code<=8'd4;ns<=N_ACK;
                end else begin
                    compressed<=encoder_ok && ((({4'd0,encoder_output_length}+63)&16'hffc0)+64<=
                        (({4'd0,raw_length}+63)&16'hffc0));
                    stored_length<=(encoder_ok && ((({4'd0,encoder_output_length}+63)&16'hffc0)+64<=
                        (({4'd0,raw_length}+63)&16'hffc0))) ? encoder_output_length : raw_length;
                    reason<=encoder_overflow ? 2 : ((encoder_ok && ((({4'd0,encoder_output_length}+63)&16'hffc0)+64<=
                        (({4'd0,raw_length}+63)&16'hffc0))) ? 0 : 1);
                    crc_kind<=0;ns<=N_CRC_REQ;
                end
            end
            if(ns==N_CRC_REQ && i_crc_request_ready) begin
                crc_issued<=0;crc_pending<=0;ns<=N_CRC_DATA;
            end
            if(crc_fire) begin crc_pending<=0;if(o_crc_last)ns<=N_CRC_RESULT;end
            if(crc_read) begin crc_position<=crc_issued;crc_issued<=crc_issued+1;crc_pending<=1;end
            if(i_crc_result_valid) begin
                if(ns==N_CRC_RESULT && normal_crc_match) begin
                    if(!i_crc_ok) begin if(error_code==0)error_code<=8'd5;ns<=N_ACK;end
                    else if(!crc_kind && compressed && error_code==0 && !i_cancel) begin raw_crc<=i_crc;crc_kind<=1;ns<=N_CRC_REQ;end
                    else begin
                        if(!crc_kind)raw_crc<=i_crc;
                        stored_crc<=i_crc;
                        ns<=(error_code!=0 || i_cancel) ? N_ACK : N_PAYLOAD;
                    end
                end
            end
            if(fs==F_CRC_START && fsource_closed && ferror!=0) begin
                // No CRC packet or AXI write was promised before BEGIN.
                fast_crc_done<=1;fast_crc_ok<=0;fs<=F_ACK;
            end else if(fs==F_CRC_START && o_fast_crc_start_valid && i_fast_crc_start_ready)fs<=F_PAYLOAD;
            if(fast_input_fire) begin
                fcount<=fast_end[11:0];
                if(fast_bad && ferror==0)ferror<=8'd2;
                if(i_fast_last || fast_end>=fraw_length)fsource_closed<=1;
            end
            if(fs==F_PAYLOAD && fsource_closed && !(ws!=W_IDLE && writer_fast))fs<=F_CRC_RESULT;
            if(i_fast_crc_result_valid) begin
                if(fs!=F_IDLE && fs!=F_ACK && fast_crc_match && fsource_closed && !fast_crc_done) begin
                    fraw_crc<=i_fast_crc;fast_crc_done<=1;fast_crc_ok<=i_fast_crc_ok;
                end
            end
            if(fs==F_CRC_RESULT && fast_crc_done) begin
                if(!fast_crc_ok && ferror==0)ferror<=8'd5;
                if(ferror!=0 || !fast_crc_ok || i_fast_cancel || !OFFICIAL_CRC_QUALIFIED) begin
                    if(ferror==0 && fast_crc_ok && !i_fast_cancel && !OFFICIAL_CRC_QUALIFIED)ferror<=8'd11;
                    fs<=F_ACK;
                end else fs<=F_INDEX;
            end
            if(ws==W_IDLE && !o_protocol_fault) begin
                // A fast prepared burst takes priority; one burst cannot starve normal indefinitely
                // under the frame owner's bounded number of ENC_BUSY admissions.
                if(fs==F_PAYLOAD && ferror==0 && !i_fast_cancel && !fsource_closed &&
                    i_fast_valid && fast_backed_beats!=0) begin
                    writer_fast<=1;writer_index<=0;wa<=fpayload_address+fast_payload_count;
                    burst_beats<=fast_backed_beats;
                    beat_number<=0;ws<=W_AW;
                end else if(fs==F_INDEX) begin
                    if(ferror!=0 || i_fast_cancel)fs<=F_ACK;
                    else begin writer_fast<=1;writer_index<=1;wa<=findex_address;burst_beats<=2;beat_number<=0;ws<=W_AW;end
                end else if(ns==N_PAYLOAD) begin
                    if(error_code!=0 || i_cancel)ns<=N_ACK;
                    else begin
                        writer_fast<=0;writer_index<=0;wa<=payload_address+payload_count;
                        burst_beats<=next_burst(payload_address+payload_count,stored_length-payload_count);
                        beat_number<=0;issued_lane<=0;issued_word<=payload_count[11:2];
                        read_pending<=0;write_valid<=0;write_data<=0;ws<=W_AW;
                    end
                end else if(ns==N_INDEX) begin
                    if(error_code!=0 || i_cancel)ns<=N_ACK;
                    else begin writer_fast<=0;writer_index<=1;wa<=index_address;burst_beats<=2;beat_number<=0;ws<=W_AW;end
                end
            end
            if(ws==W_AW && m_axi_awready)ws<=W_DATA;
            if(issue_word) begin
                read_pending<=1;read_lane<=issued_lane[1:0];read_word<=issued_word;
                issued_word<=issued_word+1;issued_lane<=issued_lane+1;
            end else if(read_pending)read_pending<=0;
            if(read_pending && ws==W_DATA && !write_valid) begin
                write_data[read_lane*32+:32]<=selected_cache_data;
                if(read_lane==3)write_valid<=1;
            end
            if(ws==W_DATA && m_axi_wvalid && m_axi_wready) begin
                beat_number<=beat_number+1;write_valid<=0;read_pending<=0;issued_lane<=0;
                if(!writer_index) begin
                    if(writer_fast)fast_payload_count<=fast_payload_count+(writer_remaining>=16 ? 12'd16 : writer_remaining);
                    else payload_count<=payload_count+(writer_remaining>=16 ? 12'd16 : writer_remaining);
                end
                if(m_axi_wlast)ws<=W_B;
            end
            if(ws==W_B && m_axi_bvalid) begin
                if(m_axi_bid!=AXI_ID) begin o_protocol_fault<=1;ws<=W_FAULT;end
                else begin
                    ws<=W_IDLE;
                    if(m_axi_bresp!=0) begin
                        if(writer_fast)begin if(ferror==0)ferror<=8'd6;end
                        else begin if(error_code==0)error_code<=8'd6;end
                    end
                    if(writer_fast) begin
                        if(writer_index)fs<=F_ACK;
                        // The CRC result is needed even for a cancelled/failed tap.
                    end else if(writer_index)ns<=N_ACK;
                    else if(m_axi_bresp!=0 || current_error || current_cancel)ns<=N_ACK;
                    else if(payload_count==stored_length) begin
                        if(OFFICIAL_CRC_QUALIFIED)ns<=N_INDEX;
                        else begin error_code<=8'd11;ns<=N_ACK;end
                    end
                end
            end
            if(ns==N_ACK && i_ack_ready)ns<=N_IDLE;
            if(fs==F_ACK && i_fast_ack_ready)fs<=F_IDLE;
        end
    end
endmodule
