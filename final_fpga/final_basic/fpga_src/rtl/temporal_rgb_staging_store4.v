`timescale 1ns / 1ps

// Original RGB is captured once, then reread beside its committed old history.
module temporal_rgb_staging_store4 #(parameter integer EXTERNAL_FIFO_ENABLE=0) (
    input wire i_external_fifo_reset_done,
    output wire [146:0] q_cw_source_data,output wire q_cw_source_valid,input wire q_cw_source_ready,
    input wire [146:0] q_cw_sink_data,input wire q_cw_sink_valid,output wire q_cw_sink_ready,
    input wire [9:0] q_cw_available,
    output wire [146:0] q_cr_source_data,output wire q_cr_source_valid,input wire q_cr_source_ready,
    input wire [146:0] q_cr_sink_data,input wire q_cr_sink_valid,output wire q_cr_sink_ready,
    input wire [9:0] q_cr_available,
    output wire [146:0] q_hr_source_data,output wire q_hr_source_valid,input wire q_hr_source_ready,
    input wire [146:0] q_hr_sink_data,input wire q_hr_sink_valid,output wire q_hr_sink_ready,
    input wire [9:0] q_hr_available,
    output wire o_write_quiescent,
    input wire i_clk,i_rst_n,i_ddr_reset_done,output wire o_reset_done,
    input wire i_offer_camera,output wire o_offer_valid,
    output wire [383:0] o_offer_frame,output wire [63:0] o_offer_tag,o_offer_key,
    input wire i_capture_valid,output wire o_capture_ready,
    input wire [383:0] i_capture_frame,input wire [63:0] i_capture_tag,i_capture_key,
    input wire [95:0] s_rgb,input wire [3:0] s_keep,
    input wire s_sof,s_eol,s_last,s_valid,output wire s_ready,
    input wire [31:0] s_index,input wire [63:0] s_tag,
    input wire i_fence_valid,output wire o_fence_ready,
    input wire [383:0] i_fence_frame,input wire [63:0] i_fence_tag,i_fence_key,
    input wire i_fence_ok,input wire [7:0] i_fence_error,
    input wire [31:0] i_fence_pixels,input wire i_source_read_quiescent,
    output wire m_capture_ack_valid,input wire m_capture_ack_ready,
    output wire [383:0] m_capture_ack_frame,output wire [63:0] m_capture_ack_tag,m_capture_ack_key,
    output reg m_capture_ack_ok,output reg [7:0] m_capture_ack_error,
    output wire [31:0] m_capture_ack_pixels,
    input wire i_process_valid,output wire o_process_ready,
    input wire [383:0] i_process_frame,input wire [63:0] i_process_tag,i_process_key,
    input wire i_process_history_selected,input wire [383:0] i_process_history_frame,
    input wire [63:0] i_process_history_tag,i_process_history_key,
    output wire [95:0] c_rgb,h_rgb,output wire [3:0] c_keep,h_keep,
    output wire c_sof,c_eol,c_last,c_valid,input wire c_ready,
    output wire h_sof,h_eol,h_last,h_valid,input wire h_ready,
    output wire [31:0] c_index,h_index,output wire [63:0] c_tag,h_tag,
    output wire m_current_status_valid,input wire m_current_status_ready,
    output wire [383:0] m_current_status_frame,
    output wire [63:0] m_current_status_tag,m_current_status_key,
    output wire m_current_status_ok,output wire [7:0] m_current_status_error,
    output wire [31:0] m_current_status_groups,
    output wire m_history_status_valid,input wire m_history_status_ready,
    output wire [383:0] m_history_status_frame,
    output wire [63:0] m_history_status_tag,m_history_status_key,
    output wire m_history_status_ok,m_history_status_skipped,
    output wire [7:0] m_history_status_error,output wire [31:0] m_history_status_groups,
    output wire o_current_read_quiescent,o_history_read_quiescent,o_read_quiescent,
    input wire i_publish_valid,output wire o_publish_ready,
    input wire [383:0] i_publish_frame,input wire [63:0] i_publish_tag,i_publish_key,
    input wire i_publish_ok,i_publish_commit,input wire i_cancel,
    output wire o_publish_fire,o_publish_committed,o_busy,o_fault,o_quarantined,
    output wire [7:0] o_error,output wire [3:0] o_active_banks,o_pinned_banks,
    output wire [1:0] o_candidate_bank,o_read_owned,
    output reg [31:0] o_stale_control_count,o_aw_count,o_w_count,o_b_count,o_ar_count,o_r_count,o_commit_count,
    output wire [3:0] m_axi_awid,m_axi_arid,
    output wire [27:0] m_axi_awaddr,m_axi_araddr,output wire [7:0] m_axi_awlen,m_axi_arlen,
    output wire [2:0] m_axi_awsize,m_axi_arsize,output wire [1:0] m_axi_awburst,m_axi_arburst,
    output wire m_axi_awvalid,m_axi_arvalid,input wire m_axi_awready,m_axi_arready,
    output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
    input wire [3:0] m_axi_bid,m_axi_rid,input wire [1:0] m_axi_bresp,m_axi_rresp,
    input wire m_axi_bvalid,m_axi_rlast,m_axi_rvalid,output wire m_axi_bready,m_axi_rready,
    input wire [127:0] m_axi_rdata
);
    localparam [3:0] AXI_ID=4'd2;
    localparam [31:0] RGB_END=32'd24887296,ARENA_SPLIT=32'd8388608;
    localparam [2:0] J_IDLE=0,J_CAPTURE=1,J_ACK=2,J_WAIT_PROCESS=3,J_PROCESS=4,J_PUBLISH=5,J_FAULT=6;
    localparam [1:0] W_IDLE=0,W_AW=1;
    localparam [7:0] E_CONFIG=1,E_HISTORY=2,E_STREAM=3,E_FENCE=4,E_B=5,E_R=6,E_CANCEL=7,E_PROTOCOL=8,E_PUBLISH=9;
    reg [2:0] job_state;
    reg [1:0] write_state;
    reg write_protocol_lost;
    reg [383:0] frame,old_frame,offer_frame0,offer_frame1;
    reg [63:0] tag,pipeline_key,old_tag,old_key,offer_tag0,offer_tag1,offer_key0,offer_key1;
    reg [31:0] offer_bytes0,offer_bytes1,old_bytes;
    reg offer_valid0,offer_valid1,active0,active1,old_bank;
    reg [1:0] candidate_bank;
    reg [3:0] pinned_banks;
    reg bad,history_selected,fence_seen,fence_ok;
    reg [7:0] error_code,fence_error;
    wire camera=i_capture_frame[4];
    wire offered_valid=camera ? offer_valid1 : offer_valid0;
    wire offered_bank=camera ? active1 : active0;
    wire [383:0] offered_frame=camera ? offer_frame1 : offer_frame0;
    wire [63:0] offered_tag=camera ? offer_tag1 : offer_tag0;
    wire [63:0] offered_key=camera ? offer_key1 : offer_key0;
    wire [31:0] offered_bytes=camera ? offer_bytes1 : offer_bytes0;
    wire capture_config_good=i_capture_tag!=0 && i_capture_frame[76:45]!=0 &&
        i_capture_frame[44:13]!=0 && i_capture_frame[12:5]<4 && i_capture_frame[2:1]!=3 &&
        i_capture_frame[383:367]==0 && (i_capture_frame[238:237]==1 || i_capture_frame[238:237]==2) &&
        i_capture_frame[220:205]!=0 && i_capture_frame[220:205]<=1920 &&
        i_capture_frame[236:221]!=0 && i_capture_frame[236:221]<=1080 &&
        (!offer_valid0 || i_capture_tag!=offer_tag0) && (!offer_valid1 || i_capture_tag!=offer_tag1);
    wire process_match=i_process_frame==frame && i_process_tag==tag && i_process_key==pipeline_key;
    wire history_good=old_tag!=0 && old_bytes!=0 && i_process_history_frame==old_frame &&
        i_process_history_tag==old_tag && i_process_history_key==old_key && pipeline_key==old_key &&
        frame[0] && old_frame[0] && frame[302:271]!=0 && frame[4:1]==old_frame[4:1] &&
        frame[76:45]==old_frame[76:45] && frame[140:109]==old_frame[140:109] &&
        frame[334:205]==old_frame[334:205] && frame[108:77]==old_frame[108:77]+32'd1 &&
        frame[204:141]>old_frame[204:141];
    wire cancel_now=i_cancel && job_state!=J_IDLE && job_state!=J_PUBLISH;
    wire draining=bad || cancel_now;
    wire wf_source_ready,wf_source_done,wf_sink_valid,wf_sink_done;
    wire [146:0] wf_sink_data;
    wire [9:0] wf_available;
    wire current_reset_done,history_reset_done;
    wire current_protocol_lost,history_protocol_lost,current_response_error,history_response_error;
    wire current_status_sent,history_status_sent;
    reg read_identity_lost;
    assign o_reset_done=i_rst_n && i_ddr_reset_done && wf_source_done && wf_sink_done && current_reset_done && history_reset_done;
    assign o_capture_ready=o_reset_done && job_state==J_IDLE && !o_quarantined;
    wire capture_fire=i_capture_valid && o_capture_ready;
    assign o_process_ready=o_reset_done && job_state==J_WAIT_PROCESS && !o_quarantined;
    wire process_control_fire=i_process_valid && o_process_ready;
    wire process_fire=process_control_fire && process_match;
    wire process_read_good=m_capture_ack_ok && !draining && (!i_process_history_selected || history_good);
    assign o_offer_valid=i_offer_camera ? offer_valid1 : offer_valid0;
    assign o_offer_frame=i_offer_camera ? offer_frame1 : offer_frame0;
    assign o_offer_tag=i_offer_camera ? offer_tag1 : offer_tag0;
    assign o_offer_key=i_offer_camera ? offer_key1 : offer_key0;
    assign o_active_banks={offer_valid1 && active1,offer_valid1 && !active1,offer_valid0 && active0,offer_valid0 && !active0};
    assign o_candidate_bank=candidate_bank;assign o_pinned_banks=pinned_banks;
    assign o_busy=job_state!=J_IDLE;
    assign o_quarantined=write_protocol_lost || read_identity_lost || current_protocol_lost || history_protocol_lost;
    assign o_fault=(bad && o_busy) || o_quarantined;assign o_error=error_code;

    function [31:0] bank_base;
        input [1:0] bank;
        begin case(bank) 0:bank_base=0;1:bank_base=32'd6221824;2:bank_base=32'd12443648;default:bank_base=32'd18665472;endcase end
    endfunction
    function [27:0] physical_address;
        input [31:0] logical_address;
        begin physical_address=logical_address<ARENA_SPLIT ? 28'h1800000+logical_address[27:0] :
            28'hf000000+logical_address[27:0]-28'h0800000;end
    endfunction
    function [4:0] burst_limit;
        input [31:0] logical_address;
        reg [12:0] boundary_bytes;
        reg [31:0] scatter_bytes;
        begin boundary_bytes=13'd4096-{1'b0,logical_address[11:0]};
            scatter_bytes=logical_address<ARENA_SPLIT ? ARENA_SPLIT-logical_address : RGB_END-logical_address;
            if(scatter_bytes<boundary_bytes) boundary_bytes=scatter_bytes[12:0];
            burst_limit=boundary_bytes>=256 ? 5'd16 : boundary_bytes[8:4];end
    endfunction
    function [2:0] lanes;
        input [3:0] keep;
        begin lanes={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction

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
    wire pack_emit=job_state==J_CAPTURE && !draining &&
        (pack_count>=16 || ((input_done || fence_seen) && pack_count!=0));
    wire [4:0] pack_emit_bytes=pack_count>=16 ? 5'd16 : pack_count;
    wire [15:0] pack_strb=pack_emit_bytes==16 ? 16'hffff : (16'hffff>>(16-pack_emit_bytes));
    wire pack_fire=pack_emit && wf_source_ready;
    assign s_ready=o_reset_done && job_state==J_CAPTURE && !fence_seen &&
        (draining || input_done || pack_count<16 || pack_fire);
    wire input_fire=s_valid && s_ready;
    wire [2:0] input_lanes=lanes(s_keep);
    wire [4:0] input_bytes={2'd0,input_lanes}+{1'd0,input_lanes,1'b0};
    wire [95:0] input_rgb_masked=s_rgb & (96'hffffffffffffffffffffffff>>((12-input_bytes)*8));
    always @(*) begin
        pack_next=pack_data;pack_count_next=pack_count;
        if(pack_fire) begin
            // Every transfer removes16 bytes or the entire final residue.
            // Masked append keeps all bits above pack_count zero, so there
            // is no remainder to shift when the last fragment is shorter.
            pack_next=pack_count>=16 ? (pack_data>>128) : 224'd0;
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
    assign q_cw_source_data=wf_source_data;
    assign q_cw_source_valid=pack_emit;
    assign q_cw_sink_ready=wf_pop;
    generate if(EXTERNAL_FIFO_ENABLE==0) begin: g_internal_cw
    raw_capture_fifo_ip u_write_fifo(
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data(wf_source_data),
        .i_source_valid(pack_emit),.o_source_ready(wf_source_ready),.o_source_reset_done(wf_source_done),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(wf_sink_data),
        .o_sink_valid(wf_sink_valid),.i_sink_ready(wf_pop),.o_available_count(wf_available),.o_sink_reset_done(wf_sink_done));
    end else begin: g_external_cw
        assign wf_source_ready=q_cw_source_ready;
        assign wf_source_done=i_external_fifo_reset_done;
        assign wf_sink_data=q_cw_sink_data;
        assign wf_sink_valid=q_cw_sink_valid;
        assign wf_sink_done=i_external_fifo_reset_done;
        assign wf_available=q_cw_available;
    end endgenerate
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            pack_data<=0;pack_count<=0;input_x<=0;input_y<=0;input_index<=0;input_pixels<=0;input_done<=0;
            write_enqueued<=0;write_dequeued<=0;
        end else if(capture_fire) begin
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
    wire [31:0] write_pending=write_enqueued-write_dequeued;
    wire [5:0] write_reserved=write_queue_count==0 ? 6'd0 :
        {1'b0,write_head_length}-{1'b0,write_beat}+(write_queue_count==2 ? {1'b0,write_tail_length} : 6'd0);
    wire [31:0] write_unreserved=write_pending-{26'd0,write_reserved};
    wire [4:0] write_boundary=burst_limit(write_logical);
    wire write_closed=(input_done || fence_seen) && pack_count==0;
    wire [4:0] write_choice=write_closed && write_unreserved<write_boundary ? write_unreserved[4:0] : write_boundary;
    wire write_start=job_state==J_CAPTURE && write_state==W_IDLE && !draining &&
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
    assign o_write_quiescent=write_quiet;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            write_state<=W_IDLE;write_logical<=0;write_address<=0;write_length<=0;write_beat<=0;
            write_head_length<=0;write_tail_length<=0;write_queue_count<=0;write_outstanding<=0;write_completed<=0;write_protocol_lost<=0;
        end
        else if(capture_fire) begin
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



    wire current_request_valid,history_request_valid,current_request_ready,history_request_ready;
    wire [27:0] current_request_address,history_request_address;
    wire [4:0] current_request_length,history_request_length;
    wire current_owned,history_owned,current_rready,history_rready;
    reg ar_active,ar_select,ar_turn;
    wire ar_fire=m_axi_arvalid && m_axi_arready;
    assign m_axi_arid=ar_select ? 4'd1 : 4'd0;
    assign m_axi_araddr=ar_select ? history_request_address : current_request_address;
    assign m_axi_arlen={3'd0,(ar_select ? history_request_length : current_request_length)}-8'd1;
    assign m_axi_arsize=3'd4;assign m_axi_arburst=2'b01;
    assign m_axi_arvalid=o_reset_done && ar_active;
    assign current_request_ready=ar_fire && !ar_select;
    assign history_request_ready=ar_fire && ar_select;
    wire current_response=m_axi_rid==0 && current_owned;
    wire history_response=m_axi_rid==1 && history_owned;
    assign m_axi_rready=o_reset_done && (current_response ? current_rready :
        history_response ? history_rready : current_owned || history_owned);
    wire r_fire=m_axi_rvalid && m_axi_rready;
    wire unknown_response=r_fire && !current_response && !history_response;
    assign o_read_owned={history_owned,current_owned};
    assign o_read_quiescent=o_current_read_quiescent && o_history_read_quiescent && !read_identity_lost;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin ar_active<=0;ar_select<=0;ar_turn<=0;read_identity_lost<=0;end
        else begin
            if(unknown_response) read_identity_lost<=1;
            if(ar_fire) begin ar_active<=0;ar_turn<=!ar_select;end
            if(!ar_active && (current_request_valid || history_request_valid)) begin
                ar_active<=1;
                ar_select<=current_request_valid && history_request_valid ? ar_turn : history_request_valid;
            end
        end
    end
    temporal_rgb_staging_reader4 #(.EXTERNAL_FIFO_ENABLE(EXTERNAL_FIFO_ENABLE)) current_reader(
        .i_external_fifo_reset_done(i_external_fifo_reset_done),
        .q_r_source_data(q_cr_source_data),.q_r_source_valid(q_cr_source_valid),.q_r_source_ready(q_cr_source_ready),
        .q_r_sink_data(q_cr_sink_data),.q_r_sink_valid(q_cr_sink_valid),.q_r_sink_ready(q_cr_sink_ready),.q_r_available(q_cr_available),

        .clk(i_clk),.rst_n(i_rst_n),.o_reset_done(current_reset_done),.i_start(process_fire),
        .i_enabled(process_read_good),.i_skipped(1'b0),.i_bad(draining),.i_error(error_code),
        .i_base(bank_base(candidate_bank)),.i_bytes(input_pixels+(input_pixels<<1)),.i_frame(frame),.i_tag(tag),
        .m_request_valid(current_request_valid),.m_request_ready(current_request_ready),
        .m_request_address(current_request_address),.m_request_length(current_request_length),
        .i_rdata(m_axi_rdata),.i_rresp(m_axi_rresp),.i_rlast(m_axi_rlast),
        .i_rvalid(m_axi_rvalid && current_response),.o_rready(current_rready),.o_owned(current_owned),
        .o_protocol_lost(current_protocol_lost),.o_response_error(current_response_error),
        .m_rgb(c_rgb),.m_keep(c_keep),.m_sof(c_sof),.m_eol(c_eol),.m_last(c_last),
        .m_valid(c_valid),.m_ready(c_ready),.m_index(c_index),.m_tag(c_tag),
        .m_status_valid(m_current_status_valid),.m_status_ready(m_current_status_ready),
        .m_status_ok(m_current_status_ok),.m_status_error(m_current_status_error),
        .m_status_groups(m_current_status_groups),.o_status_sent(current_status_sent),.o_read_quiescent(o_current_read_quiescent));
    temporal_rgb_staging_reader4 #(.EXTERNAL_FIFO_ENABLE(EXTERNAL_FIFO_ENABLE)) history_reader(
        .i_external_fifo_reset_done(i_external_fifo_reset_done),
        .q_r_source_data(q_hr_source_data),.q_r_source_valid(q_hr_source_valid),.q_r_source_ready(q_hr_source_ready),
        .q_r_sink_data(q_hr_sink_data),.q_r_sink_valid(q_hr_sink_valid),.q_r_sink_ready(q_hr_sink_ready),.q_r_available(q_hr_available),

        .clk(i_clk),.rst_n(i_rst_n),.o_reset_done(history_reset_done),.i_start(process_fire),
        .i_enabled(process_read_good && i_process_history_selected),.i_skipped(!i_process_history_selected),
        .i_bad(draining),.i_error(error_code),.i_base(bank_base({frame[4],old_bank})),.i_bytes(old_bytes),.i_frame(frame),.i_tag(old_tag),
        .m_request_valid(history_request_valid),.m_request_ready(history_request_ready),
        .m_request_address(history_request_address),.m_request_length(history_request_length),
        .i_rdata(m_axi_rdata),.i_rresp(m_axi_rresp),.i_rlast(m_axi_rlast),
        .i_rvalid(m_axi_rvalid && history_response),.o_rready(history_rready),.o_owned(history_owned),
        .o_protocol_lost(history_protocol_lost),.o_response_error(history_response_error),
        .m_rgb(h_rgb),.m_keep(h_keep),.m_sof(h_sof),.m_eol(h_eol),.m_last(h_last),
        .m_valid(h_valid),.m_ready(h_ready),.m_index(h_index),.m_tag(h_tag),
        .m_status_valid(m_history_status_valid),.m_status_ready(m_history_status_ready),
        .m_status_ok(m_history_status_ok),.m_status_error(m_history_status_error),
        .m_status_groups(m_history_status_groups),.o_status_sent(history_status_sent),.o_read_quiescent(o_history_read_quiescent));
    assign m_history_status_skipped=!history_selected;
    assign m_current_status_frame=frame;assign m_current_status_tag=tag;assign m_current_status_key=pipeline_key;
    assign m_history_status_frame=old_frame;assign m_history_status_tag=old_tag;assign m_history_status_key=old_key;
    assign m_capture_ack_frame=frame;assign m_capture_ack_tag=tag;assign m_capture_ack_key=pipeline_key;
    assign m_capture_ack_pixels=input_pixels;
    assign m_capture_ack_valid=o_reset_done && job_state==J_ACK;
    wire fence_fire=i_fence_valid && o_fence_ready;
    wire fence_match=i_fence_frame==frame && i_fence_tag==tag && i_fence_key==pipeline_key;
    wire fence_good=i_fence_pixels==input_pixels && (!i_fence_ok || (input_done && i_fence_error==0));
    assign o_fence_ready=o_reset_done && job_state==J_CAPTURE && !fence_seen && !s_valid && i_source_read_quiescent;
    assign o_publish_ready=o_reset_done && job_state==J_PUBLISH && write_quiet && o_read_quiescent &&
        current_status_sent && history_status_sent && !o_quarantined;
    wire publish_control_fire=i_publish_valid && o_publish_ready;
    wire publish_match=i_publish_frame==frame && i_publish_tag==tag && i_publish_key==pipeline_key;
    assign o_publish_fire=publish_control_fire && publish_match;
    wire commit_eligible=m_capture_ack_ok && m_current_status_ok &&
        (!history_selected || m_history_status_ok) && !bad && frame[0] && frame[302:271]!=0;
    assign o_publish_committed=o_publish_fire && i_publish_ok && i_publish_commit && commit_eligible;
    wire backend_fault_now=cancel_now || (input_fire && !stream_good && !draining) ||
        (fence_fire && fence_match && (!fence_good || !i_fence_ok || i_fence_error!=0)) ||
        (b_fire && (m_axi_bid!=AXI_ID || m_axi_bresp!=0)) || current_response_error || history_response_error || unknown_response;
    wire [7:0] backend_error_now=cancel_now ? E_CANCEL : input_fire && !stream_good ? E_STREAM :
        fence_fire && fence_match ? (i_fence_error!=0 ? i_fence_error : E_FENCE) :
        b_fire ? E_B : unknown_response ? E_PROTOCOL : E_R;

    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            job_state<=J_IDLE;frame<=0;old_frame<=0;tag<=0;pipeline_key<=0;old_tag<=0;old_key<=0;old_bytes<=0;old_bank<=0;
            offer_frame0<=0;offer_frame1<=0;offer_tag0<=0;offer_tag1<=0;offer_key0<=0;offer_key1<=0;offer_bytes0<=0;offer_bytes1<=0;
            offer_valid0<=0;offer_valid1<=0;active0<=0;active1<=0;candidate_bank<=0;pinned_banks<=0;
            bad<=0;error_code<=0;history_selected<=0;fence_seen<=0;fence_ok<=0;fence_error<=0;
            m_capture_ack_ok<=0;m_capture_ack_error<=0;o_stale_control_count<=0;
        end else begin
            if(backend_fault_now && !bad) begin bad<=1;error_code<=backend_error_now;end
            if((fence_fire && !fence_match) || (process_control_fire && !process_match) ||
                (publish_control_fire && !publish_match)) begin
                if(!(&o_stale_control_count)) o_stale_control_count<=o_stale_control_count+1'b1;
            end
            case(job_state)
                J_IDLE: if(capture_fire) begin
                    frame<=i_capture_frame;tag<=i_capture_tag;pipeline_key<=i_capture_key;
                    old_frame<=offered_frame;old_tag<=offered_tag;old_key<=offered_key;old_bytes<=offered_bytes;old_bank<=offered_bank;
                    candidate_bank<={camera,offered_valid ? !offered_bank : 1'b0};
                    pinned_banks<=4'b0001<<{camera,offered_valid ? !offered_bank : 1'b0};
                    bad<=!capture_config_good;error_code<=capture_config_good ? 8'd0 : E_CONFIG;
                    fence_seen<=0;fence_ok<=0;fence_error<=0;history_selected<=0;m_capture_ack_ok<=0;m_capture_ack_error<=0;
                    job_state<=J_CAPTURE;
                end
                J_CAPTURE: begin
                    if(fence_fire && fence_match) begin fence_seen<=1;fence_ok<=i_fence_ok && fence_good && i_fence_error==0;fence_error<=i_fence_error;end
                    if(fence_seen && write_quiet) begin
                        m_capture_ack_ok<=fence_ok && !draining;
                        m_capture_ack_error<=bad ? error_code : cancel_now ? E_CANCEL : fence_ok ? 8'd0 : fence_error!=0 ? fence_error : E_FENCE;
                        job_state<=J_ACK;
                    end
                end
                J_ACK: if(m_capture_ack_valid && m_capture_ack_ready) job_state<=J_WAIT_PROCESS;
                J_WAIT_PROCESS: if(process_fire) begin
                    history_selected<=i_process_history_selected;
                    if(i_process_history_selected && history_good) pinned_banks<=pinned_banks | (4'b0001<<{frame[4],old_bank});
                    if(i_process_history_selected && !history_good && !bad) begin bad<=1;error_code<=E_HISTORY;end
                    job_state<=J_PROCESS;
                end
                J_PROCESS: if(o_read_quiescent && current_status_sent && history_status_sent) job_state<=J_PUBLISH;
                J_PUBLISH: if(o_publish_fire) begin
                    if(o_publish_committed) begin
                        if(frame[4]) begin offer_valid1<=1;active1<=candidate_bank[0];offer_frame1<=frame;offer_tag1<=tag;offer_key1<=pipeline_key;offer_bytes1<=input_pixels+(input_pixels<<1);end
                        else begin offer_valid0<=1;active0<=candidate_bank[0];offer_frame0<=frame;offer_tag0<=tag;offer_key0<=pipeline_key;offer_bytes0<=input_pixels+(input_pixels<<1);end
                    end
                    pinned_banks<=0;job_state<=J_IDLE;
                end
                J_FAULT: begin end
                default: begin job_state<=J_FAULT;bad<=1;error_code<=E_PROTOCOL;end
            endcase
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin o_aw_count<=0;o_w_count<=0;o_b_count<=0;o_ar_count<=0;o_r_count<=0;o_commit_count<=0;end
        else begin
            if(aw_fire) o_aw_count<=o_aw_count+1'b1;if(w_fire) o_w_count<=o_w_count+1'b1;
            if(b_fire) o_b_count<=o_b_count+1'b1;if(ar_fire) o_ar_count<=o_ar_count+1'b1;
            if(r_fire) o_r_count<=o_r_count+1'b1;if(o_publish_committed) o_commit_count<=o_commit_count+1'b1;
        end
    end
endmodule

// One explicitly authenticated read slot and one official R FIFO per bank.
module temporal_rgb_staging_reader4 #(parameter integer EXTERNAL_FIFO_ENABLE=0) (
    input wire i_external_fifo_reset_done,
    output wire [146:0] q_r_source_data,output wire q_r_source_valid,input wire q_r_source_ready,
    input wire [146:0] q_r_sink_data,input wire q_r_sink_valid,output wire q_r_sink_ready,
    input wire [9:0] q_r_available,

    input wire clk,rst_n,output wire o_reset_done,
    input wire i_start,i_enabled,i_skipped,i_bad,input wire [7:0] i_error,
    input wire [31:0] i_base,i_bytes,input wire [383:0] i_frame,input wire [63:0] i_tag,
    output reg m_request_valid,input wire m_request_ready,
    output reg [27:0] m_request_address,output reg [4:0] m_request_length,
    input wire [127:0] i_rdata,input wire [1:0] i_rresp,input wire i_rlast,i_rvalid,
    output wire o_rready,output reg o_owned,output reg o_protocol_lost,output wire o_response_error,
    output reg [95:0] m_rgb,output reg [3:0] m_keep,
    output reg m_sof,m_eol,m_last,m_valid,input wire m_ready,
    output reg [31:0] m_index,output wire [63:0] m_tag,
    output reg m_status_valid,input wire m_status_ready,
    output reg m_status_ok,output reg [7:0] m_status_error,
    output wire [31:0] m_status_groups,output reg o_status_sent,output wire o_read_quiescent
);
    localparam [31:0] RGB_END=32'd24887296,SPLIT=32'd8388608;
    reg active,enabled,skipped;
    reg [31:0] logical_position,remaining_beats,total_bytes,enqueued,dequeued,bytes_popped,groups_consumed,next_index;
    reg [4:0] owned_length;
    reg [8:0] response_beat;
    reg [15:0] x,y,width,height;
    reg [63:0] locked_tag;
    reg all_formed;
    reg [255:0] unpack_data,unpack_next;
    reg [5:0] unpack_count,unpack_count_next;
    wire fifo_source_ready,fifo_source_done,fifo_sink_valid,fifo_sink_done;
    wire fifo_pop;
    wire [146:0] fifo_sink_data;
    wire [9:0] fifo_available;
    wire [31:0] pending=enqueued-dequeued;
    wire request_fire=m_request_valid && m_request_ready;
    wire response_bad=i_rlast!=(response_beat=={4'd0,owned_length}-9'd1);
    assign o_rready=o_owned && (i_bad || i_rresp!=0 || response_bad || o_protocol_lost || fifo_source_ready);
    wire response_fire=i_rvalid && o_rready;
    wire fifo_push=response_fire && !i_bad && i_rresp==0 && !response_bad && !o_protocol_lost;
    wire response_terminal=response_fire && i_rlast && !response_bad && !o_protocol_lost;
    assign o_response_error=response_fire && (i_rresp!=0 || response_bad);
    wire [12:0] boundary_bytes=13'd4096-{1'b0,logical_position[11:0]};
    wire [31:0] scatter_bytes=logical_position<SPLIT ? SPLIT-logical_position : RGB_END-logical_position;
    wire [12:0] limit_bytes=scatter_bytes<boundary_bytes ? scatter_bytes[12:0] : boundary_bytes;
    wire [4:0] boundary=limit_bytes>=256 ? 5'd16 : limit_bytes[8:4];
    wire [4:0] choice=remaining_beats<boundary ? remaining_beats[4:0] : boundary;
    wire reserve=active && enabled && !i_bad && !m_request_valid && !o_owned &&
        remaining_beats!=0 && pending+{27'd0,choice}<=496;
    assign o_reset_done=fifo_source_done && fifo_sink_done;
    assign m_tag=locked_tag;assign m_status_groups=groups_consumed;
    assign q_r_source_data={19'd0,i_rdata};
    assign q_r_source_valid=i_rvalid && o_owned && !i_bad && i_rresp==0 && !response_bad && !o_protocol_lost;
    assign q_r_sink_ready=fifo_pop;
    generate if(EXTERNAL_FIFO_ENABLE==0) begin: g_internal_r
    raw_capture_fifo_ip u_read_fifo(
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data({19'd0,i_rdata}),
        .i_source_valid(i_rvalid && o_owned && !i_bad && i_rresp==0 && !response_bad && !o_protocol_lost),
        .o_source_ready(fifo_source_ready),.o_source_reset_done(fifo_source_done),
        .i_sink_clk(clk),.i_sink_rst_n(rst_n),.o_sink_data(fifo_sink_data),.o_sink_valid(fifo_sink_valid),
        .i_sink_ready(fifo_pop),.o_available_count(fifo_available),.o_sink_reset_done(fifo_sink_done));
    end else begin: g_external_r
        assign fifo_source_ready=q_r_source_ready;
        assign fifo_source_done=i_external_fifo_reset_done;
        assign fifo_sink_data=q_r_sink_data;
        assign fifo_sink_valid=q_r_sink_valid;
        assign fifo_sink_done=i_external_fifo_reset_done;
        assign fifo_available=q_r_available;
    end endgenerate
    wire row_last={1'b0,x}+17'd4>={1'b0,width};
    wire frame_last=row_last && y==height-1'b1;
    wire [16:0] remaining_pixels={1'b0,width}-{1'b0,x};
    wire [3:0] keep=remaining_pixels>=4 ? 4'hf : remaining_pixels==3 ? 4'h7 : remaining_pixels==2 ? 4'h3 : 4'h1;
    wire [2:0] count={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};
    wire [4:0] group_bytes={2'd0,count}+{1'd0,count,1'b0};
    wire [31:0] bytes_remaining=total_bytes-bytes_popped;
    wire [4:0] take_bytes=bytes_remaining>=16 ? 5'd16 : bytes_remaining[4:0];
    wire advance=!m_valid || m_ready;
    assign fifo_pop=active && (i_bad || (!all_formed && unpack_count<=16));
    wire read_pop=fifo_sink_valid && fifo_pop;
    reg form_group;
    reg [95:0] formed_rgb;
    always @(*) begin
        unpack_next=unpack_data;unpack_count_next=unpack_count;form_group=0;formed_rgb=0;
        if(read_pop && !i_bad) begin
            unpack_next=unpack_next | ({{128{1'b0}},fifo_sink_data[127:0] &
                (128'hffffffffffffffffffffffffffffffff>>((16-take_bytes)*8))}<<(unpack_count*8));
            unpack_count_next=unpack_count+{1'b0,take_bytes};
        end
        if(advance && enabled && !all_formed && !i_bad && unpack_count_next>={1'b0,group_bytes}) begin
            // keep is generated above as 1/3/7/f, so consumption is exactly
            // 1/2/3/4 RGB pixels. Expose these fixed routes to synthesis.
            form_group=1;
            case(keep)
                4'h1: begin formed_rgb={72'd0,unpack_next[23:0]};unpack_next={24'd0,unpack_next[255:24]};end
                4'h3: begin formed_rgb={48'd0,unpack_next[47:0]};unpack_next={48'd0,unpack_next[255:48]};end
                4'h7: begin formed_rgb={24'd0,unpack_next[71:0]};unpack_next={72'd0,unpack_next[255:72]};end
                default: begin formed_rgb=unpack_next[95:0];unpack_next={96'd0,unpack_next[255:96]};end
            endcase
            unpack_count_next=unpack_count_next-{1'b0,group_bytes};
        end
        if(i_bad) begin unpack_next=0;unpack_count_next=0;end
    end
    assign o_read_quiescent=!m_request_valid && !o_owned && !o_protocol_lost && remaining_beats==0 &&
        pending==0 && unpack_count==0 && !m_valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;enabled<=0;skipped<=0;logical_position<=0;remaining_beats<=0;total_bytes<=0;
            enqueued<=0;dequeued<=0;bytes_popped<=0;groups_consumed<=0;next_index<=0;owned_length<=0;response_beat<=0;
            x<=0;y<=0;width<=0;height<=0;locked_tag<=0;all_formed<=0;unpack_data<=0;unpack_count<=0;
            m_request_valid<=0;m_request_address<=0;m_request_length<=0;o_owned<=0;o_protocol_lost<=0;
            m_rgb<=0;m_keep<=0;m_sof<=0;m_eol<=0;m_last<=0;m_valid<=0;m_index<=0;
            m_status_valid<=0;m_status_ok<=0;m_status_error<=0;o_status_sent<=0;
        end else if(i_start) begin
            active<=1;enabled<=i_enabled;skipped<=i_skipped;logical_position<=i_base;
            remaining_beats<=i_enabled ? (i_bytes+32'd15)>>4 : 0;total_bytes<=i_enabled ? i_bytes : 0;
            enqueued<=0;dequeued<=0;bytes_popped<=0;groups_consumed<=0;next_index<=0;owned_length<=0;response_beat<=0;
            x<=0;y<=0;width<=i_frame[220:205];height<=i_frame[236:221];locked_tag<=i_tag;all_formed<=0;
            unpack_data<=0;unpack_count<=0;m_request_valid<=0;o_owned<=0;o_protocol_lost<=0;
            m_valid<=0;m_index<=0;m_status_valid<=0;m_status_ok<=0;m_status_error<=0;o_status_sent<=0;
        end else begin
            unpack_data<=unpack_next;unpack_count<=unpack_count_next;
            if(i_bad) remaining_beats<=0;
            if(reserve) begin
                m_request_address<=logical_position<SPLIT ? 28'h1800000+logical_position[27:0] :
                    28'hf000000+logical_position[27:0]-28'h0800000;
                m_request_length<=choice;m_request_valid<=1;
            end
            if(request_fire) begin
                m_request_valid<=0;o_owned<=1;owned_length<=m_request_length;response_beat<=0;
                logical_position<=logical_position+{23'd0,m_request_length,4'd0};
                if(!i_bad) remaining_beats<=remaining_beats-{27'd0,m_request_length};
            end
            if(response_fire) begin
                if(response_bad) o_protocol_lost<=1;
                if(response_terminal) begin o_owned<=0;response_beat<=0;end
                else if(response_beat!=511) response_beat<=response_beat+1'b1;
            end
            if(fifo_push) enqueued<=enqueued+1'b1;
            if(read_pop) begin dequeued<=dequeued+1'b1;if(!i_bad) bytes_popped<=bytes_popped+{27'd0,take_bytes};end
            if(m_valid && m_ready) groups_consumed<=groups_consumed+1'b1;
            if(advance) begin
                m_valid<=form_group;
                if(form_group) begin
                    m_rgb<=formed_rgb;m_keep<=keep;m_sof<=next_index==0;m_eol<=row_last;m_last<=frame_last;
                    m_index<=next_index;next_index<=next_index+1'b1;
                    if(row_last) begin x<=0;y<=y+1'b1;end else x<=x+16'd4;
                    if(frame_last) all_formed<=1;
                end
            end
            if(active && o_read_quiescent && !o_status_sent && !m_status_valid) begin
                m_status_valid<=1;m_status_ok<=!i_bad && (skipped || (enabled && all_formed));
                m_status_error<=i_bad ? (i_error!=0 ? i_error : 8'd7) : skipped || (enabled && all_formed) ? 8'd0 : 8'd6;
            end
            if(m_status_valid && m_status_ready) begin m_status_valid<=0;o_status_sent<=1;end
        end
    end
endmodule
