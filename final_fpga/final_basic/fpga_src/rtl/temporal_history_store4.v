`timescale 1ns / 1ps

// RGB888 temporal history: official FIFO buffers, external DDR banks only.
module temporal_history_store4 #(
    parameter [3:0] AXI_ID = 4'd2
) (
    input wire i_clk, i_rst_n, i_ddr_reset_done,
    output wire o_reset_done,
    input wire i_offer_camera,
    output wire o_offer_valid,
    output wire [383:0] o_offer_frame,
    output wire [63:0] o_offer_tag, o_offer_key,
    input wire i_plan_valid,
    output wire o_plan_ready,
    input wire [383:0] i_plan_frame,
    input wire [63:0] i_plan_tag, i_plan_key,
    input wire i_plan_history_selected,
    input wire [63:0] i_plan_history_tag,
    input wire [95:0] s_rgb,
    input wire [3:0] s_keep,
    input wire s_sof, s_eol, s_last, s_valid,
    input wire [31:0] s_index,
    input wire [63:0] s_tag,
    output wire s_ready,
    output reg [95:0] h_rgb,
    output reg [3:0] h_keep,
    output reg h_sof, h_eol, h_last, h_valid,
    output reg [31:0] h_index,
    output wire [63:0] h_tag,
    input wire h_ready,
    output wire [383:0] o_read_frame,
    output wire [63:0] o_read_tag, o_read_key,
    output wire o_read_quiescent,
    output reg m_history_status_valid,
    input wire m_history_status_ready,
    output wire [383:0] m_history_status_frame,
    output wire [63:0] m_history_status_tag, m_history_status_key,
    output reg m_history_status_ok,
    output reg [7:0] m_history_status_error,
    input wire i_fence_valid,
    output wire o_fence_ready,
    input wire [383:0] i_fence_frame,
    input wire [63:0] i_fence_tag, i_fence_key,
    input wire i_fence_ok,
    input wire [7:0] i_fence_error,
    input wire [31:0] i_fence_pixels,
    output wire m_ack_valid,
    input wire m_ack_ready,
    output wire [383:0] m_ack_frame,
    output wire [63:0] m_ack_tag, m_ack_key,
    output reg m_ack_ok,
    output reg [7:0] m_ack_error,
    output wire [31:0] m_ack_pixels,
    input wire i_publish_valid,
    output wire o_publish_ready,
    input wire [383:0] i_publish_frame,
    input wire [63:0] i_publish_tag, i_publish_key,
    input wire i_publish_ok, i_publish_commit,
    input wire i_cancel,
    output wire o_busy, o_fault,
    output wire [7:0] o_error,
    output wire [3:0] o_active_banks, o_pinned_banks,
    output wire [1:0] o_candidate_bank,
    input wire i_debug_clear,
    output reg [31:0] o_aw_count, o_w_count, o_b_count,
    output reg [31:0] o_ar_count, o_r_count, o_commit_count, o_fault_count,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast, m_axi_wvalid,
    input wire m_axi_wready,
    input wire [3:0] m_axi_bid,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    output wire [3:0] m_axi_arid,
    output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    input wire [3:0] m_axi_rid,
    input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast, m_axi_rvalid,
    output wire m_axi_rready
);
    localparam [31:0] RGB_STRIDE=32'd6221824;
    localparam [31:0] RGB_END=32'd24887296;
    localparam [31:0] ARENA_SPLIT=32'd8388608;
    localparam [2:0] J_IDLE=0,J_RUN=1,J_ACK=2,J_PUBLISH=3,J_FAULT=4;
    localparam [1:0] W_IDLE=0,W_AW=1;
    localparam [1:0] R_IDLE=0,R_AR=1;
    localparam [7:0] E_CONFIG=1,E_HISTORY=2,E_STREAM=3,E_FENCE=4,
                     E_B=5,E_R=6,E_CANCEL=7,E_PROTOCOL=8,E_PUBLISH=9;
    reg [2:0] job_state;
    reg [1:0] write_state,read_state;
    reg [383:0] frame,old_frame,offer_frame_camera0,offer_frame_camera1;
    reg [63:0] tag,pipeline_key,old_tag,old_key;
    reg [63:0] offer_tag_camera0,offer_tag_camera1,offer_key_camera0,offer_key_camera1;
    reg [31:0] offer_bytes_camera0,offer_bytes_camera1;
    reg offer_valid_camera0,offer_valid_camera1,active_camera0,active_camera1;
    reg [1:0] candidate_bank;
    reg [3:0] pinned_banks;
    reg history_selected,bad;
    reg [7:0] error_code;
    reg fence_seen,fence_ok;
    reg [7:0] fence_error;
    reg history_status_sent;
    wire camera=i_plan_frame[4];
    wire offered_valid=camera ? offer_valid_camera1 : offer_valid_camera0;
    wire [383:0] offered_frame=camera ? offer_frame_camera1 : offer_frame_camera0;
    wire [63:0] offered_tag=camera ? offer_tag_camera1 : offer_tag_camera0;
    wire [63:0] offered_key=camera ? offer_key_camera1 : offer_key_camera0;
    wire [31:0] offered_bytes=camera ? offer_bytes_camera1 : offer_bytes_camera0;
    wire offered_bank=camera ? active_camera1 : active_camera0;
    wire plan_config_good=i_plan_tag!=0 && i_plan_frame[76:45]!=0 &&
        i_plan_frame[44:13]!=0 && i_plan_frame[12:5]<4 &&
        i_plan_frame[2:1]!=3 && i_plan_frame[383:367]==0 &&
        (i_plan_frame[238:237]==1 || i_plan_frame[238:237]==2) &&
        i_plan_frame[220:205]>=1 && i_plan_frame[220:205]<=1920 &&
        i_plan_frame[236:221]>=1 && i_plan_frame[236:221]<=1080 &&
        (!offer_valid_camera0 || i_plan_tag!=offer_tag_camera0) &&
        (!offer_valid_camera1 || i_plan_tag!=offer_tag_camera1);
    wire history_good=offered_valid && i_plan_history_tag==offered_tag &&
        i_plan_key==offered_key && i_plan_frame[0] && offered_frame[0] &&
        i_plan_frame[302:271]!=0 && i_plan_frame[4:1]==offered_frame[4:1] &&
        i_plan_frame[76:45]==offered_frame[76:45] &&
        i_plan_frame[140:109]==offered_frame[140:109] &&
        i_plan_frame[334:205]==offered_frame[334:205] &&
        i_plan_frame[108:77]==offered_frame[108:77]+32'd1 &&
        i_plan_frame[204:141]>offered_frame[204:141] && offered_bytes!=0;

    function [31:0] bank_base;
        input [1:0] bank;
        begin
            case(bank)
                0: bank_base=0;
                1: bank_base=32'd6221824;
                2: bank_base=32'd12443648;
                default: bank_base=32'd18665472;
            endcase
        end
    endfunction
    function [27:0] physical_address;
        input [31:0] logical_address;
        begin
            if(logical_address<ARENA_SPLIT)
                physical_address=28'h1800000+logical_address[27:0];
            else physical_address=28'hf000000+logical_address[27:0]-28'h0800000;
        end
    endfunction
    function [4:0] burst_limit;
        input [31:0] logical_address;
        reg [12:0] boundary_bytes;
        reg [31:0] scatter_bytes;
        begin
            boundary_bytes=13'd4096-{1'b0,logical_address[11:0]};
            scatter_bytes=logical_address<ARENA_SPLIT ? ARENA_SPLIT-logical_address : RGB_END-logical_address;
            if(scatter_bytes<boundary_bytes) boundary_bytes=scatter_bytes[12:0];
            burst_limit=boundary_bytes>=256 ? 5'd16 : boundary_bytes[8:4];
        end
    endfunction
    function [2:0] lanes;
        input [3:0] keep;
        begin lanes={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction

    wire wf_source_ready,wf_source_done,wf_sink_valid,wf_sink_done;
    wire [146:0] wf_sink_data;
    wire [9:0] wf_available;
    wire rf_source_ready,rf_source_done,rf_sink_valid,rf_sink_done;
    wire [146:0] rf_sink_data;
    wire [9:0] rf_available;
    assign o_reset_done=i_rst_n && i_ddr_reset_done && wf_source_done && wf_sink_done && rf_source_done && rf_sink_done;
    assign o_plan_ready=o_reset_done && job_state==J_IDLE && AXI_ID[3:2]==0;
    wire plan_fire=i_plan_valid && o_plan_ready;
    assign o_busy=job_state!=J_IDLE;
    assign o_offer_valid=i_offer_camera ? offer_valid_camera1 : offer_valid_camera0;
    assign o_offer_frame=i_offer_camera ? offer_frame_camera1 : offer_frame_camera0;
    assign o_offer_tag=i_offer_camera ? offer_tag_camera1 : offer_tag_camera0;
    assign o_offer_key=i_offer_camera ? offer_key_camera1 : offer_key_camera0;
    assign o_active_banks={offer_valid_camera1 && active_camera1,offer_valid_camera1 && !active_camera1,
                           offer_valid_camera0 && active_camera0,offer_valid_camera0 && !active_camera0};
    assign o_pinned_banks=pinned_banks;
    assign o_candidate_bank=candidate_bank;
    assign o_fault=(bad && job_state!=J_IDLE) || AXI_ID[3:2]!=0;
    assign o_error=AXI_ID[3:2]!=0 ? E_CONFIG : error_code;
    assign o_read_frame=old_frame;assign o_read_tag=old_tag;assign o_read_key=old_key;assign h_tag=old_tag;
    assign m_history_status_frame=old_frame;assign m_history_status_tag=old_tag;assign m_history_status_key=old_key;
    assign m_ack_frame=frame;assign m_ack_tag=tag;assign m_ack_key=pipeline_key;

    // Byte alignment reservoir: at most27 bytes before a16-byte FIFO push.
    reg [223:0] pack_data;
    reg [4:0] pack_count;
    reg [223:0] pack_next;
    reg [4:0] pack_count_next;
    reg [15:0] input_x,input_y;
    reg [31:0] input_index,input_pixels;
    reg input_done;
    wire input_row_last={1'b0,input_x}+17'd4>={1'b0,frame[220:205]};
    wire input_frame_last=input_row_last && input_y==frame[236:221]-16'd1;
    wire [16:0] input_remaining={1'b0,frame[220:205]}-{1'b0,input_x};
    wire [3:0] expected_input_keep=!input_row_last || input_remaining>=4 ? 4'hf :
        input_remaining==3 ? 4'h7 : input_remaining==2 ? 4'h3 : 4'h1;
    wire stream_good=s_tag==tag && s_index==input_index && s_keep==expected_input_keep &&
        s_sof==(input_index==0) && s_eol==input_row_last && s_last==input_frame_last && !input_done;
    wire draining=bad || i_cancel;
    wire pack_emit=job_state==J_RUN && !draining &&
        (pack_count>=16 || ((input_done || fence_seen) && pack_count!=0));
    wire [4:0] pack_emit_bytes=pack_count>=16 ? 5'd16 : pack_count;
    wire [15:0] pack_strb=pack_emit_bytes==16 ? 16'hffff : (16'hffff>>(16-pack_emit_bytes));
    wire pack_fire=pack_emit && wf_source_ready;
    assign s_ready=o_reset_done && job_state==J_RUN && !fence_seen &&
        (draining || (!input_done && (pack_count<16 || pack_fire)));
    wire input_fire=s_valid && s_ready;
    wire [2:0] input_lanes=lanes(s_keep);
    wire [4:0] input_bytes={2'd0,input_lanes}+{1'd0,input_lanes,1'b0};
    wire [95:0] input_rgb_masked=s_rgb & (96'hffffffffffffffffffffffff>>((12-input_bytes)*8));
    always @(*) begin
        pack_next=pack_data;pack_count_next=pack_count;
        if(pack_fire) begin
            pack_next=pack_data>>(pack_emit_bytes*8);
            pack_count_next=pack_count-pack_emit_bytes;
        end
        if(input_fire && !draining && stream_good) begin
            pack_next=pack_next | ({{128{1'b0}},input_rgb_masked}<<(pack_count_next*8));
            pack_count_next=pack_count_next+input_bytes;
        end
        if(draining) begin pack_next=0;pack_count_next=0;end
    end
    wire [146:0] wf_source_data={3'b000,pack_strb,pack_data[127:0]};
    reg [31:0] write_enqueued,write_dequeued;
    wire wf_pop;
    raw_capture_fifo_ip u_write_fifo(
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data(wf_source_data),
        .i_source_valid(pack_emit),.o_source_ready(wf_source_ready),.o_source_reset_done(wf_source_done),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(wf_sink_data),
        .o_sink_valid(wf_sink_valid),.i_sink_ready(wf_pop),.o_available_count(wf_available),.o_sink_reset_done(wf_sink_done));
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            pack_data<=0;pack_count<=0;input_x<=0;input_y<=0;input_index<=0;input_pixels<=0;input_done<=0;
            write_enqueued<=0;write_dequeued<=0;
        end else if(plan_fire) begin
            pack_data<=0;pack_count<=0;input_x<=0;input_y<=0;input_index<=0;input_pixels<=0;input_done<=0;
            write_enqueued<=0;write_dequeued<=0;
        end else begin
            pack_data<=pack_next;pack_count<=pack_count_next;
            if(pack_fire) write_enqueued<=write_enqueued+1'b1;
            if(wf_sink_valid && wf_pop) write_dequeued<=write_dequeued+1'b1;
            if(input_fire) begin
                input_pixels<=input_pixels+{29'd0,input_lanes};input_index<=input_index+1'b1;
                if(input_row_last) begin input_x<=0;input_y<=input_y+1'b1;end else input_x<=input_x+16'd4;
                if(s_last || input_frame_last) input_done<=1;
            end
        end
    end

    // Two accepted AWs: each complete W reservation survives until real B.
    reg [31:0] write_logical;
    reg [27:0] write_address;
    reg [4:0] write_length,write_beat;
    reg [4:0] write_head_length,write_tail_length;
    reg [1:0] write_queue_count,write_outstanding,write_completed;
    reg write_protocol_lost;
    wire [31:0] write_pending=write_enqueued-write_dequeued;
    wire [5:0] write_reserved=write_queue_count==0 ? 6'd0 :
        {1'b0,write_head_length}-{1'b0,write_beat}+(write_queue_count==2 ? {1'b0,write_tail_length} : 6'd0);
    wire [31:0] write_unreserved=write_pending-{26'd0,write_reserved};
    wire [4:0] write_boundary=burst_limit(write_logical);
    wire write_closed=(input_done || fence_seen) && pack_count==0;
    wire [4:0] write_choice=write_closed && write_unreserved<write_boundary ? write_unreserved[4:0] : write_boundary;
    wire write_start=job_state==J_RUN && write_state==W_IDLE && !draining &&
        write_outstanding<2 && write_queue_count<2 && write_choice!=0 &&
        wf_available>={4'd0,write_reserved}+{5'd0,write_choice};
    assign m_axi_awid=AXI_ID;assign m_axi_awaddr=write_address;
    assign m_axi_awlen={3'd0,write_length}-8'd1;assign m_axi_awsize=3'd4;assign m_axi_awburst=2'b01;
    assign m_axi_awvalid=o_reset_done && write_state==W_AW;
    assign m_axi_wdata=wf_sink_data[127:0];assign m_axi_wstrb=wf_sink_data[143:128];
    assign m_axi_wlast=write_beat==write_head_length-5'd1;
    assign m_axi_wvalid=o_reset_done && write_queue_count!=0 && wf_sink_valid;
    assign wf_pop=(write_queue_count!=0 && m_axi_wready) ||
        (write_queue_count==0 && write_state==W_IDLE && draining);
    assign m_axi_bready=o_reset_done && write_completed!=0;
    wire aw_fire=m_axi_awvalid && m_axi_awready;
    wire w_fire=m_axi_wvalid && m_axi_wready;
    wire b_fire=m_axi_bvalid && m_axi_bready;
    wire write_terminal=w_fire && m_axi_wlast;
    wire b_retire=b_fire && m_axi_bid==AXI_ID;
    wire write_quiet=write_state==W_IDLE && write_queue_count==0 && write_outstanding==0 &&
        !write_protocol_lost && pack_count==0 && write_pending==0;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            write_state<=W_IDLE;write_logical<=0;write_address<=0;write_length<=0;write_beat<=0;
            write_head_length<=0;write_tail_length<=0;write_queue_count<=0;write_outstanding<=0;write_completed<=0;write_protocol_lost<=0;
        end
        else if(plan_fire) begin
            write_state<=W_IDLE;write_logical<=bank_base({camera,offered_valid ? !offered_bank : 1'b0});
            write_address<=0;write_length<=0;write_beat<=0;
            write_head_length<=0;write_tail_length<=0;write_queue_count<=0;write_outstanding<=0;write_completed<=0;write_protocol_lost<=0;
        end else begin
            if(b_fire && m_axi_bid!=AXI_ID) write_protocol_lost<=1;
            case({aw_fire,b_retire})
                2'b10: write_outstanding<=write_outstanding+1'b1;
                2'b01: write_outstanding<=write_outstanding-1'b1;
                default: begin end
            endcase
            case({write_terminal,b_retire})
                2'b10: write_completed<=write_completed+1'b1;
                2'b01: write_completed<=write_completed-1'b1;
                default: begin end
            endcase
            case({aw_fire,write_terminal})
                2'b10: begin
                    if(write_queue_count==0) write_head_length<=write_length;else write_tail_length<=write_length;
                    write_queue_count<=write_queue_count+1'b1;
                end
                2'b01: begin write_head_length<=write_tail_length;write_queue_count<=write_queue_count-1'b1;end
                2'b11: begin
                    if(write_queue_count==1) write_head_length<=write_length;
                    else begin write_head_length<=write_tail_length;write_tail_length<=write_length;end
                end
                default: begin end
            endcase
            if(write_terminal) write_beat<=0;else if(w_fire) write_beat<=write_beat+1'b1;
            case(write_state)
                W_IDLE: if(write_start) begin write_address<=physical_address(write_logical);write_length<=write_choice;write_state<=W_AW;end
                W_AW: if(aw_fire) begin write_logical<=write_logical+{23'd0,write_length,4'd0};write_state<=W_IDLE;end
                default: write_state<=W_IDLE;
            endcase
        end
    end

    reg [31:0] read_logical,read_remaining,read_total_bytes;
    reg [27:0] read_address;
    reg [4:0] read_length;
    reg [4:0] read_head_length,read_tail_length;
    reg [1:0] read_outstanding;
    reg read_protocol_lost;
    reg [8:0] read_beat;
    reg [31:0] read_enqueued,read_dequeued;
    wire [31:0] read_pending=read_enqueued-read_dequeued;
    wire [4:0] read_boundary=burst_limit(read_logical);
    wire [4:0] read_choice=read_remaining<read_boundary ? read_remaining[4:0] : read_boundary;
    wire [5:0] read_reserved=read_outstanding==0 ? 6'd0 :
        (read_beat<{4'd0,read_head_length} ? {1'b0,read_head_length}-read_beat[5:0] : 6'd0)+
        (read_outstanding==2 ? {1'b0,read_tail_length} : 6'd0);
    wire read_start=job_state==J_RUN && read_state==R_IDLE && history_selected && !draining &&
        read_outstanding<2 && read_remaining!=0 &&
        read_pending+{26'd0,read_reserved}+{27'd0,read_choice}<=32'd496;
    assign m_axi_arid=AXI_ID;assign m_axi_araddr=read_address;
    assign m_axi_arlen={3'd0,read_length}-8'd1;assign m_axi_arsize=3'd4;assign m_axi_arburst=2'b01;
    assign m_axi_arvalid=o_reset_done && read_state==R_AR;
    assign m_axi_rready=o_reset_done && read_outstanding!=0 && (draining || rf_source_ready);
    wire ar_fire=m_axi_arvalid && m_axi_arready;
    wire r_fire=m_axi_rvalid && m_axi_rready;
    wire rf_push=r_fire && !draining;
    wire read_terminal=r_fire && m_axi_rlast && m_axi_rid==AXI_ID &&
        read_beat=={4'd0,read_head_length}-9'd1 && !read_protocol_lost;
    wire read_protocol_error=r_fire && (m_axi_rid!=AXI_ID ||
        m_axi_rlast!=(read_beat=={4'd0,read_head_length}-9'd1));
    wire rf_pop;
    raw_capture_fifo_ip u_read_fifo(
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data({16'd0,m_axi_rlast,m_axi_rresp,m_axi_rdata}),
        .i_source_valid(m_axi_rvalid && read_outstanding!=0 && !draining),
        .o_source_ready(rf_source_ready),.o_source_reset_done(rf_source_done),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(rf_sink_data),.o_sink_valid(rf_sink_valid),
        .i_sink_ready(rf_pop),.o_available_count(rf_available),.o_sink_reset_done(rf_sink_done));
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            read_state<=R_IDLE;read_logical<=0;read_remaining<=0;read_total_bytes<=0;
            read_address<=0;read_length<=0;read_beat<=0;read_enqueued<=0;read_dequeued<=0;
            read_head_length<=0;read_tail_length<=0;read_outstanding<=0;read_protocol_lost<=0;
        end else if(plan_fire) begin
            read_state<=R_IDLE;read_logical<=bank_base({camera,offered_bank});
            read_remaining<=i_plan_history_selected && history_good && plan_config_good ? (offered_bytes+32'd15)>>4 : 0;
            read_total_bytes<=offered_bytes;read_address<=0;read_length<=0;read_beat<=0;read_enqueued<=0;read_dequeued<=0;
            read_head_length<=0;read_tail_length<=0;read_outstanding<=0;read_protocol_lost<=0;
        end else begin
            if(rf_push) read_enqueued<=read_enqueued+1'b1;
            if(rf_sink_valid && rf_pop) read_dequeued<=read_dequeued+1'b1;
            if(draining) read_remaining<=0;
            if(read_protocol_error) read_protocol_lost<=1;
            case({ar_fire,read_terminal})
                2'b10: begin
                    if(read_outstanding==0) read_head_length<=read_length;else read_tail_length<=read_length;
                    read_outstanding<=read_outstanding+1'b1;
                end
                2'b01: begin read_head_length<=read_tail_length;read_outstanding<=read_outstanding-1'b1;end
                2'b11: begin
                    if(read_outstanding==1) read_head_length<=read_length;
                    else begin read_head_length<=read_tail_length;read_tail_length<=read_length;end
                end
                default: begin end
            endcase
            if(read_terminal) read_beat<=0;else if(r_fire && read_beat!=9'd511) read_beat<=read_beat+1'b1;
            case(read_state)
                R_IDLE: if(read_start) begin
                    read_address<=physical_address(read_logical);read_length<=read_choice;read_state<=R_AR;
                end
                R_AR: if(ar_fire) begin
                    if(!draining) read_remaining<=read_remaining-{27'd0,read_length};
                    read_logical<=read_logical+{23'd0,read_length,4'd0};read_state<=R_IDLE;
                end
                default: read_state<=R_IDLE;
            endcase
        end
    end

    // Two-beat byte alignment only; no image cache. A held native group persists.
    reg [255:0] unpack_data,unpack_next;
    reg [5:0] unpack_count,unpack_count_next;
    reg [31:0] read_bytes_popped;
    reg [15:0] output_x,output_y;
    reg [31:0] output_index;
    reg all_groups_formed;
    wire output_row_last={1'b0,output_x}+17'd4>={1'b0,frame[220:205]};
    wire output_frame_last=output_row_last && output_y==frame[236:221]-16'd1;
    wire [16:0] output_remaining={1'b0,frame[220:205]}-{1'b0,output_x};
    wire [3:0] output_keep=!output_row_last || output_remaining>=4 ? 4'hf :
        output_remaining==3 ? 4'h7 : output_remaining==2 ? 4'h3 : 4'h1;
    wire [2:0] output_lanes=lanes(output_keep);
    wire [4:0] output_bytes={2'd0,output_lanes}+{1'd0,output_lanes,1'b0};
    wire [31:0] read_bytes_remaining=read_total_bytes-read_bytes_popped;
    wire [4:0] read_take_bytes=read_bytes_remaining>=16 ? 5'd16 : read_bytes_remaining[4:0];
    wire h_advance=!h_valid || h_ready;
    assign rf_pop=job_state!=J_IDLE && (draining || (!all_groups_formed && unpack_count<=16));
    wire read_pop=rf_sink_valid && rf_pop;
    reg form_group;
    reg [95:0] formed_rgb;
    always @(*) begin
        unpack_next=unpack_data;unpack_count_next=unpack_count;
        form_group=0;formed_rgb=0;
        if(read_pop && !draining) begin
            unpack_next=unpack_next | ({{128{1'b0}},(rf_sink_data[127:0] &
                (128'hffffffffffffffffffffffffffffffff>>((16-read_take_bytes)*8)))}<<(unpack_count*8));
            unpack_count_next=unpack_count+{1'b0,read_take_bytes};
        end
        if(h_advance && !all_groups_formed && history_selected && !draining &&
           unpack_count_next>={1'b0,output_bytes}) begin
            form_group=1;
            formed_rgb=unpack_next[95:0] & (96'hffffffffffffffffffffffff>>((12-output_bytes)*8));
            unpack_next=unpack_next>>(output_bytes*8);unpack_count_next=unpack_count_next-{1'b0,output_bytes};
        end
        if(draining) begin unpack_next=0;unpack_count_next=0;end
    end
    assign o_read_quiescent=!history_selected || (read_state==R_IDLE && read_outstanding==0 &&
        !read_protocol_lost && read_remaining==0 &&
        read_pending==0 && unpack_count==0 && !h_valid);
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            unpack_data<=0;unpack_count<=0;read_bytes_popped<=0;output_x<=0;output_y<=0;output_index<=0;all_groups_formed<=0;
            h_rgb<=0;h_keep<=0;h_sof<=0;h_eol<=0;h_last<=0;h_valid<=0;h_index<=0;
        end else if(plan_fire) begin
            unpack_data<=0;unpack_count<=0;read_bytes_popped<=0;output_x<=0;output_y<=0;output_index<=0;all_groups_formed<=0;h_valid<=0;
        end else begin
            unpack_data<=unpack_next;unpack_count<=unpack_count_next;
            if(read_pop && !draining) read_bytes_popped<=read_bytes_popped+{27'd0,read_take_bytes};
            if(h_advance) begin
                h_valid<=form_group;
                if(form_group) begin
                    h_rgb<=formed_rgb;h_keep<=output_keep;h_sof<=output_index==0;h_eol<=output_row_last;
                    h_last<=output_frame_last;h_index<=output_index;output_index<=output_index+1'b1;
                    if(output_row_last) begin output_x<=0;output_y<=output_y+1'b1;end else output_x<=output_x+16'd4;
                    if(output_frame_last) all_groups_formed<=1;
                end
            end
        end
    end

    wire fence_fire=i_fence_valid && o_fence_ready;
    wire fence_match=i_fence_frame==frame && i_fence_tag==tag && i_fence_key==pipeline_key;
    wire fence_count_good=i_fence_pixels==input_pixels && (!i_fence_ok || input_done);
    assign o_fence_ready=o_reset_done && job_state==J_RUN && !fence_seen;
    assign m_ack_valid=o_reset_done && job_state==J_ACK;
    assign m_ack_pixels=input_pixels;
    assign o_publish_ready=o_reset_done && job_state==J_PUBLISH && o_read_quiescent &&
        (!history_selected || history_status_sent);
    wire publish_fire=i_publish_valid && o_publish_ready;
    wire publish_match=i_publish_frame==frame && i_publish_tag==tag && i_publish_key==pipeline_key;
    wire publish_commit=publish_fire && publish_match && i_publish_ok && i_publish_commit &&
        m_ack_ok && !bad && !i_cancel && frame[0] && frame[302:271]!=0;
    wire backend_fault_now=(i_cancel && job_state!=J_IDLE) ||
        (input_fire && !stream_good && !draining) ||
        (fence_fire && (!fence_match || !fence_count_good)) ||
        (b_fire && (m_axi_bid!=AXI_ID || m_axi_bresp!=0)) ||
        (r_fire && (m_axi_rresp!=0 || read_protocol_error)) ||
        (publish_fire && (!publish_match || (i_publish_commit && (!i_publish_ok || !m_ack_ok))));
    wire [7:0] backend_error_now=i_cancel ? E_CANCEL : input_fire && !stream_good ? E_STREAM :
        fence_fire && (!fence_match || !fence_count_good) ? E_FENCE :
        b_fire && (m_axi_bid!=AXI_ID || m_axi_bresp!=0) ? E_B :
        r_fire && (m_axi_rid!=AXI_ID || m_axi_rresp!=0) ? E_R :
        r_fire ? E_PROTOCOL : E_PUBLISH;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            job_state<=J_IDLE;frame<=0;tag<=0;pipeline_key<=0;old_frame<=0;old_tag<=0;old_key<=0;
            history_selected<=0;bad<=0;error_code<=0;candidate_bank<=0;pinned_banks<=0;
            fence_seen<=0;fence_ok<=0;fence_error<=0;history_status_sent<=0;
            m_ack_ok<=0;m_ack_error<=0;m_history_status_valid<=0;m_history_status_ok<=0;m_history_status_error<=0;
            offer_valid_camera0<=0;offer_valid_camera1<=0;active_camera0<=0;active_camera1<=0;
            offer_frame_camera0<=0;offer_frame_camera1<=0;offer_tag_camera0<=0;offer_tag_camera1<=0;
            offer_key_camera0<=0;offer_key_camera1<=0;offer_bytes_camera0<=0;offer_bytes_camera1<=0;
        end else begin
            if(backend_fault_now && !bad) begin bad<=1;error_code<=backend_error_now;end
            if(m_history_status_valid && m_history_status_ready) begin m_history_status_valid<=0;history_status_sent<=1;end
            if(history_selected && !history_status_sent && !m_history_status_valid && job_state!=J_IDLE && o_read_quiescent) begin
                m_history_status_valid<=1;m_history_status_ok<=!bad && !i_cancel;
                m_history_status_error<=bad ? error_code : i_cancel ? E_CANCEL : 8'd0;
            end
            case(job_state)
                J_IDLE: if(plan_fire) begin
                    frame<=i_plan_frame;tag<=i_plan_tag;pipeline_key<=i_plan_key;
                    old_frame<=offered_frame;old_tag<=i_plan_history_tag;old_key<=offered_key;
                    history_selected<=i_plan_history_selected;candidate_bank<={camera,offered_valid ? !offered_bank : 1'b0};
                    pinned_banks<=i_plan_history_selected && history_good ? (4'b0001<<{camera,offered_bank}) : 4'd0;
                    bad<=!plan_config_good || (i_plan_history_selected && !history_good);
                    error_code<=!plan_config_good ? E_CONFIG : i_plan_history_selected && !history_good ? E_HISTORY : 8'd0;
                    fence_seen<=0;fence_ok<=0;fence_error<=0;history_status_sent<=!i_plan_history_selected;
                    m_history_status_valid<=0;m_ack_ok<=0;m_ack_error<=0;job_state<=J_RUN;
                end
                J_RUN: begin
                    if(fence_fire && fence_match) begin
                        fence_seen<=1;fence_ok<=i_fence_ok && fence_count_good;fence_error<=i_fence_error;
                    end
                    if(fence_seen && write_quiet && o_read_quiescent) begin
                        m_ack_ok<=fence_ok && !bad && !i_cancel && frame[0] && frame[302:271]!=0;
                        m_ack_error<=bad ? error_code : i_cancel ? E_CANCEL :
                            fence_ok && frame[0] && frame[302:271]!=0 ? 8'd0 : fence_error!=0 ? fence_error : E_FENCE;
                        job_state<=J_ACK;
                    end
                end
                J_ACK: if(m_ack_valid && m_ack_ready) job_state<=J_PUBLISH;
                J_PUBLISH: if(publish_fire && publish_match) begin
                    if(publish_commit) begin
                        if(frame[4]) begin
                            offer_valid_camera1<=1;active_camera1<=candidate_bank[0];offer_frame_camera1<=frame;
                            offer_tag_camera1<=tag;offer_key_camera1<=pipeline_key;
                            offer_bytes_camera1<=input_pixels+(input_pixels<<1);
                        end else begin
                            offer_valid_camera0<=1;active_camera0<=candidate_bank[0];offer_frame_camera0<=frame;
                            offer_tag_camera0<=tag;offer_key_camera0<=pipeline_key;
                            offer_bytes_camera0<=input_pixels+(input_pixels<<1);
                        end
                    end
                    pinned_banks<=0;history_selected<=0;job_state<=J_IDLE;
                end
                J_FAULT: begin end
                default: begin job_state<=J_FAULT;bad<=1;error_code<=E_PROTOCOL;end
            endcase
        end
    end

    // Diagnostics never participate in allocation, bus control or publication.
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            o_aw_count<=0;o_w_count<=0;o_b_count<=0;o_ar_count<=0;o_r_count<=0;o_commit_count<=0;o_fault_count<=0;
        end else if(i_debug_clear) begin
            o_aw_count<=0;o_w_count<=0;o_b_count<=0;o_ar_count<=0;o_r_count<=0;o_commit_count<=0;o_fault_count<=0;
        end else begin
            if(aw_fire) o_aw_count<=o_aw_count+1'b1;
            if(w_fire) o_w_count<=o_w_count+1'b1;
            if(b_fire) o_b_count<=o_b_count+1'b1;
            if(ar_fire) o_ar_count<=o_ar_count+1'b1;
            if(r_fire) o_r_count<=o_r_count+1'b1;
            if(publish_commit) o_commit_count<=o_commit_count+1'b1;
            if((backend_fault_now && !bad) || (plan_fire && (!plan_config_good || (i_plan_history_selected && !history_good))))
                o_fault_count<=o_fault_count+1'b1;
        end
    end
endmodule
