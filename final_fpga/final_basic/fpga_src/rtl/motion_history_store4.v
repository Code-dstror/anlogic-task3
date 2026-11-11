`timescale 1ns / 1ps

// External raw-Y history and independent confidence/mask planes. No image RAM.
module motion_history_store4 #(parameter [3:0] AXI_ID=4'd2,parameter integer EXTERNAL_FIFO_ENABLE=0) (
    input wire i_external_fifo_reset_done,
    output wire [146:0] q_mw_source_data,output wire q_mw_source_valid,input wire q_mw_source_ready,
    input wire [146:0] q_mw_sink_data,input wire q_mw_sink_valid,output wire q_mw_sink_ready,
    input wire [9:0] q_mw_available,
    output wire o_write_quiescent,
    input wire i_clk,i_rst_n,i_ddr_reset_done,
    output wire o_reset_done,
    input wire i_offer_camera,
    output wire o_offer_valid,
    output wire [383:0] o_offer_frame,
    output wire [63:0] o_offer_key,
    output wire [159:0] o_offer_context,
    output wire [31:0] o_offer_tag,
    input wire i_begin_valid,
    output wire o_begin_ready,
    input wire [383:0] i_begin_frame,i_begin_history_frame,
    input wire [63:0] i_begin_key,
    input wire [159:0] i_begin_context,
    input wire [31:0] i_begin_tag,i_begin_history_tag,
    input wire [8:0] i_begin_width,
    input wire [7:0] i_begin_height,
    input wire i_begin_history_used,
    input wire s_y_valid,
    output wire s_y_ready,
    input wire [31:0] s_y,
    input wire [3:0] s_y_keep,
    input wire s_y_sof,s_y_eol,s_y_last,
    input wire s_map_valid,
    output wire s_map_ready,
    input wire [7:0] s_confidence,
    input wire [3:0] s_mask,s_map_keep,
    input wire s_map_sof,s_map_eol,s_map_last,
    input wire [8:0] s_map_x,
    input wire [7:0] s_map_y,
    output reg h_valid,
    input wire h_ready,
    output reg [31:0] h_y,
    output reg [3:0] h_keep,
    output reg h_sof,h_eol,h_last,
    output wire [31:0] h_tag,
    output wire o_read_quiescent,
    input wire i_close_valid,
    output wire o_close_ready,
    input wire [383:0] i_close_frame,
    input wire [63:0] i_close_key,
    input wire [159:0] i_close_context,
    input wire [31:0] i_close_tag,
    input wire i_close_commit_candidate,
    input wire [15:0] i_close_write_pixels,
    output wire m_ack_valid,
    input wire m_ack_ready,
    output wire [383:0] m_ack_frame,
    output wire [63:0] m_ack_key,
    output wire [159:0] m_ack_context,
    output wire [31:0] m_ack_tag,
    output wire m_ack_quiescent,
    output reg m_ack_write_ok,
    output wire [15:0] m_ack_write_pixels,
    output wire [7:0] m_ack_error,
    input wire i_publish_valid,
    output wire o_publish_ready,
    input wire [383:0] i_publish_frame,
    input wire [63:0] i_publish_key,
    input wire [159:0] i_publish_context,
    input wire [31:0] i_publish_tag,
    input wire i_publish_success,i_publish_temporal_trust,
    input wire i_publish_global_change,i_publish_brightness_change,
    output wire o_map_committed,o_map_f26_success,o_map_temporal_trust,
    output wire o_map_global_change,o_map_brightness_change,
    output wire [383:0] o_map_frame,o_map_history_frame,
    output wire [63:0] o_map_key,
    output wire [159:0] o_map_context,
    output wire [31:0] o_map_tag,o_map_history_tag,
    output wire [8:0] o_map_width,
    output wire [7:0] o_map_height,
    output wire [15:0] o_map_full_pixels,
    input wire i_project_plan_valid,
    output wire o_project_plan_ready,
    input wire i_project_use_map,
    input wire [383:0] i_project_frame,i_project_history_frame,
    input wire [63:0] i_project_key,i_project_tag,i_project_history_tag,
    output reg map_valid,
    input wire map_ready,
    output reg [7:0] map_confidence,
    output reg [3:0] map_keep,
    output reg map_sof,map_eol,map_last,
    output reg [31:0] map_index,
    output wire [63:0] map_stream_tag,
    input wire i_project_close_valid,
    output wire o_project_close_ready,
    input wire [383:0] i_project_close_frame,
    input wire [63:0] i_project_close_key,i_project_close_tag,
    input wire i_project_close_cancel,
    output wire m_project_ack_valid,
    input wire m_project_ack_ready,
    output wire [383:0] m_project_ack_frame,
    output wire [63:0] m_project_ack_key,m_project_ack_tag,
    output wire m_project_ack_quiescent,
    output reg m_project_ack_ok,
    output wire [31:0] m_project_ack_groups,
    input wire i_release_valid,
    output wire o_release_ready,
    input wire [383:0] i_release_frame,
    input wire [63:0] i_release_key,i_release_tag,
    input wire i_cancel,i_project_cancel,
    output wire o_busy,o_fault,
    output wire [7:0] o_error,
    output wire [3:0] o_active_banks,o_pinned_banks,
    input wire i_debug_clear,
    output reg [31:0] o_aw_count,o_w_count,o_b_count,o_ar_count,o_r_count,
    output reg [31:0] o_Y_commit_count,o_map_commit_count,o_release_count,o_fault_count,
    output wire [3:0] m_axi_awid,
    output wire [27:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0] m_axi_wstrb,
    output wire m_axi_wlast,m_axi_wvalid,
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
    input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready
);
    localparam [3:0] J_IDLE=0,J_BUILD=1,J_ACK=2,J_PUBLISH=3,
        J_MAP=4,J_PROJECT=5,J_PROJ_ACK=6,J_QUARANTINE=7;
    localparam [2:0] P_GATHER=0,P_CONF0=1,P_CONF1=2,P_MASK=3,P_WAIT=4;
    localparam [7:0] E_CONFIG=1,E_HISTORY=2,E_STREAM=3,E_CLOSE=4,
        E_B=5,E_R=6,E_CANCEL=7,E_PROTOCOL=8,E_PUBLISH=9,E_PROJECT=10;
    localparam [31:0] Y_BASE=32'd24887296,MAP_BASE=32'd25133056,
        MASK_BASE=32'd25147456,ARENA_END=32'd25165824,ARENA_SPLIT=32'd8388608;
    reg [3:0] job_state;
    reg [383:0] frame,old_frame,offer0,offer1;
    reg [63:0] pipeline_key,offer_key0,offer_key1;
    reg [159:0] context_locked,offer_context0,offer_context1;
    reg [31:0] tag,old_tag,offer_tag0,offer_tag1;
    reg [15:0] offer_pixels0,offer_pixels1;
    reg [8:0] width,offer_width0,offer_width1;
    reg [7:0] height,offer_height0,offer_height1;
    reg offer_valid0,offer_valid1,active0,active1,history_used;
    reg [1:0] candidate_bank;
    reg [3:0] pinned_banks;
    reg bad,close_seen,close_permission,project_close_seen;
    reg [7:0] error_code;
    reg map_committed,f26_success,temporal_trust,global_hint,brightness_hint;
    reg [15:0] full_pixels;
    wire camera=i_begin_frame[4];
    wire offered_valid=camera ? offer_valid1 : offer_valid0;
    wire [383:0] offered_frame=camera ? offer1 : offer0;
    wire [63:0] offered_key=camera ? offer_key1 : offer_key0;
    wire [31:0] offered_tag=camera ? offer_tag1 : offer_tag0;
    wire [15:0] offered_pixels=camera ? offer_pixels1 : offer_pixels0;
    wire [8:0] offered_width=camera ? offer_width1 : offer_width0;
    wire [7:0] offered_height=camera ? offer_height1 : offer_height0;
    wire offered_bank=camera ? active1 : active0;
    wire begin_good=i_begin_tag!=0 && i_begin_width!=0 && i_begin_width<=320 &&
        i_begin_height!=0 && i_begin_height<=180 && i_begin_frame[0] &&
        i_begin_frame[302:271]!=0 && i_begin_frame[76:45]!=0 && i_begin_frame[44:13]!=0 &&
        i_begin_frame[12:5]<4 && i_begin_frame[2:1]!=3 && i_begin_frame[383:367]==0 &&
        (i_begin_frame[238:237]==1 || i_begin_frame[238:237]==2) &&
        i_begin_frame[220:205]==({7'd0,i_begin_width}<<2)+({7'd0,i_begin_width}<<1) &&
        i_begin_frame[236:221]==({8'd0,i_begin_height}<<2)+({8'd0,i_begin_height}<<1) &&
        (!offer_valid0 || i_begin_tag!=offer_tag0) && (!offer_valid1 || i_begin_tag!=offer_tag1);
    wire history_good=offered_valid && i_begin_history_frame==offered_frame &&
        i_begin_history_tag==offered_tag && i_begin_key==offered_key &&
        i_begin_width==offered_width && i_begin_height==offered_height &&
        i_begin_frame[4:1]==offered_frame[4:1] && i_begin_frame[76:45]==offered_frame[76:45] &&
        i_begin_frame[140:109]==offered_frame[140:109] &&
        i_begin_frame[334:205]==offered_frame[334:205] && offered_frame[108:77]!=32'hffffffff &&
        i_begin_frame[108:77]==offered_frame[108:77]+32'd1 &&
        i_begin_frame[204:141]>offered_frame[204:141] && offered_pixels!=0;
    function [31:0] y_base;
        input [1:0] bank;
        begin case(bank)
            0:y_base=32'd24887296;1:y_base=32'd24948736;
            2:y_base=32'd25010176;default:y_base=32'd25071616;
        endcase end
    endfunction
    function [27:0] physical;
        input [31:0] logical;
        begin physical=logical<ARENA_SPLIT ? 28'h1800000+logical[27:0] :
            28'hf000000+logical[27:0]-28'h0800000;end
    endfunction
    function [4:0] boundary;
        input [31:0] logical;
        reg [12:0] bytes;
        begin
            bytes=13'd4096-{1'b0,logical[11:0]};
            boundary=bytes>=256 ? 5'd16 : bytes[8:4];
        end
    endfunction
    function [2:0] lanes;
        input [3:0] keep;
        begin lanes={2'd0,keep[0]}+{2'd0,keep[1]}+{2'd0,keep[2]}+{2'd0,keep[3]};end
    endfunction
    function [3:0] keep_for;
        input [8:0] remaining;
        begin keep_for=remaining>=4 ? 4'hf : remaining==3 ? 4'h7 : remaining==2 ? 4'h3 : 4'h1;end
    endfunction
    wire wf_source_ready,wf_source_done,wf_sink_valid,wf_sink_done;
    wire rf_source_ready,rf_source_done,rf_sink_valid,rf_sink_done;
    wire [146:0] wf_sink_data,rf_sink_data;
    wire [9:0] wf_available,rf_available;
    assign o_reset_done=i_rst_n && i_ddr_reset_done && wf_source_done && wf_sink_done && rf_source_done && rf_sink_done;
    assign o_begin_ready=o_reset_done && job_state==J_IDLE && AXI_ID[3:2]==0;
    wire begin_fire=i_begin_valid && o_begin_ready;
    assign o_busy=job_state!=J_IDLE;
    assign o_fault=(bad && job_state!=J_IDLE) || AXI_ID[3:2]!=0;
    assign o_error=AXI_ID[3:2]!=0 ? E_CONFIG : error_code;
    assign o_offer_valid=i_offer_camera ? offer_valid1 : offer_valid0;
    assign o_offer_frame=i_offer_camera ? offer1 : offer0;
    assign o_offer_key=i_offer_camera ? offer_key1 : offer_key0;
    assign o_offer_context=i_offer_camera ? offer_context1 : offer_context0;
    assign o_offer_tag=i_offer_camera ? offer_tag1 : offer_tag0;
    assign o_active_banks={offer_valid1 && active1,offer_valid1 && !active1,
        offer_valid0 && active0,offer_valid0 && !active0};
    assign o_pinned_banks=pinned_banks;
    assign h_tag=tag;
    assign o_map_committed=map_committed;assign o_map_f26_success=f26_success;
    assign o_map_temporal_trust=temporal_trust;assign o_map_global_change=global_hint;
    assign o_map_brightness_change=brightness_hint;
    assign o_map_frame=frame;assign o_map_history_frame=old_frame;assign o_map_key=pipeline_key;
    assign o_map_context=context_locked;assign o_map_tag=tag;assign o_map_history_tag=old_tag;
    assign o_map_width=width;assign o_map_height=height;assign o_map_full_pixels=full_pixels;
    assign map_stream_tag={32'd0,tag};

    // One128-cell microblock; only bounded alignment registers, never an image.
    reg [2:0] pack_phase;
    reg chunk_sealed;
    reg [31:0] chunk_base;
    reg [7:0] chunk_y_count,chunk_map_count,chunk_size;
    reg [159:0] y_pack,y_pack_next;
    reg [4:0] y_pack_count,y_pack_count_next;
    wire [255:0] confidence_pack;
    wire [127:0] mask_pack;
    reg [5:0] confidence_partial;
    reg [2:0] mask_partial;
    reg [23:0] y_carry;
    reg [5:0] confidence_carry;
    reg [2:0] mask_carry;
    reg [2:0] y_carry_count,map_carry_count;
    reg [8:0] y_x,map_x;
    reg [7:0] y_row,map_row;
    reg [15:0] y_pixels,map_pixels;
    reg y_done,map_done;
    wire project_phase=job_state==J_PROJECT || job_state==J_PROJ_ACK;
    wire draining=bad || (job_state==J_BUILD && i_cancel) || (project_phase && i_project_cancel);
    wire y_row_last=y_x+9'd4>=width;
    wire map_row_last=map_x+9'd4>=width;
    wire y_last=y_row_last && y_row==height-8'd1;
    wire map_final=map_row_last && map_row==height-8'd1;
    wire [3:0] y_expected_keep=keep_for(width-y_x),map_expected_keep=keep_for(width-map_x);
    wire y_good=s_y_keep==y_expected_keep && s_y_sof==(y_pixels==0) && s_y_eol==y_row_last && s_y_last==y_last && !y_done;
    wire map_good=s_map_keep==map_expected_keep && s_map_sof==(map_pixels==0) && s_map_eol==map_row_last &&
        s_map_last==map_final && s_map_x==map_x && s_map_y==map_row && !map_done;
    wire [2:0] y_lanes=lanes(s_y_keep),map_lanes=lanes(s_map_keep);
    wire [7:0] y_room=8'd128-chunk_y_count,map_room=8'd128-chunk_map_count;
    wire [2:0] y_take=y_room<y_lanes ? y_room[2:0] : y_lanes;
    wire [2:0] map_take=map_room<map_lanes ? map_room[2:0] : map_lanes;
    wire chunk_complete=(chunk_y_count==128 && chunk_map_count==128) || (y_done && map_done);
    wire [4:0] y_emit_bytes=y_pack_count>=16 ? 5'd16 : y_pack_count;
    wire y_emit=job_state==J_BUILD && !draining && pack_phase==P_GATHER &&
        (y_pack_count>=16 || (chunk_sealed && y_pack_count!=0));
    wire conf_emit=job_state==J_BUILD && !draining && (pack_phase==P_CONF0 || pack_phase==P_CONF1);
    wire mask_emit=job_state==J_BUILD && !draining && pack_phase==P_MASK;
    wire wf_emit=y_emit || conf_emit || mask_emit;
    wire wf_push=wf_emit && wf_source_ready;
    wire y_push=y_emit && wf_source_ready;
    wire [4:0] conf_bytes=pack_phase==P_CONF1 ? (({1'b0,chunk_size}+9'd3)>>2)-9'd16 :
        chunk_size>64 ? 5'd16 : ({1'b0,chunk_size}+9'd3)>>2;
    wire [4:0] mask_bytes=({1'b0,chunk_size}+9'd7)>>3;
    wire [4:0] emit_bytes=y_emit ? y_emit_bytes : conf_emit ? conf_bytes : mask_bytes;
    wire [15:0] emit_strb=emit_bytes==16 ? 16'hffff : (16'hffff>>(16-emit_bytes));
    wire [127:0] emit_data=y_emit ? y_pack[127:0] : conf_emit ?
        (pack_phase==P_CONF1 ? confidence_pack[255:128] : confidence_pack[127:0]) : mask_pack;
    assign s_y_ready=o_reset_done && job_state==J_BUILD && !close_seen &&
        (draining || (!y_done && !chunk_sealed && pack_phase==P_GATHER && chunk_y_count<128 &&
        (y_pack_count<16 || y_push)));
    assign s_map_ready=o_reset_done && job_state==J_BUILD && !close_seen &&
        (draining || (!map_done && !chunk_sealed && pack_phase==P_GATHER && chunk_map_count<128));
    wire y_fire=s_y_valid && s_y_ready,map_fire=s_map_valid && s_map_ready;
    // Append at most four cells to a three-cell partial group. Only this
    // narrow reservoir shifts; the 128-cell payload has fixed bank slices.
    wire [7:0] folded_input={s_mask[3] ? 2'd0 : s_confidence[7:6],
        s_mask[2] ? 2'd0 : s_confidence[5:4],
        s_mask[1] ? 2'd0 : s_confidence[3:2],
        s_mask[0] ? 2'd0 : s_confidence[1:0]};
    wire [7:0] take_confidence_mask=map_take==4 ? 8'hff : map_take==3 ? 8'h3f :
        map_take==2 ? 8'h0f : map_take==1 ? 8'h03 : 8'h00;
    wire [3:0] take_mask_mask=map_take==4 ? 4'hf : map_take==3 ? 4'h7 :
        map_take==2 ? 4'h3 : map_take==1 ? 4'h1 : 4'h0;
    wire [15:0] appended_confidence={10'd0,confidence_partial} |
        ({8'd0,folded_input & take_confidence_mask} << {chunk_map_count[1:0],1'b0});
    wire [7:0] appended_mask={5'd0,mask_partial} |
        ({4'd0,s_mask & take_mask_mask} << chunk_map_count[1:0]);
    wire [3:0] appended_cells={2'd0,chunk_map_count[1:0]}+{1'b0,map_take};
    wire [5:0] first_map_group=chunk_map_count[7:2];
    wire [5:0] second_map_group=first_map_group+6'd1;
    wire [2:0] carry_cells=map_lanes-map_take;
    wire [5:0] carry_confidence_mask=carry_cells==3 ? 6'h3f :
        carry_cells==2 ? 6'h0f : carry_cells==1 ? 6'h03 : 6'h00;
    wire [2:0] carry_mask_mask=carry_cells==3 ? 3'h7 :
        carry_cells==2 ? 3'h3 : carry_cells==1 ? 3'h1 : 3'h0;
    reg [31:0] write_enqueued,write_dequeued;
    wire wf_pop;
    wire [146:0] wf_source_data={3'd0,emit_strb,emit_data};
    assign q_mw_source_data=wf_source_data;
    assign q_mw_source_valid=wf_emit;
    assign q_mw_sink_ready=wf_pop;
    generate if(EXTERNAL_FIFO_ENABLE==0) begin: g_internal_mw
    raw_capture_fifo_ip u_write_fifo(
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data(wf_source_data),
        .i_source_valid(wf_emit),.o_source_ready(wf_source_ready),.o_source_reset_done(wf_source_done),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(wf_sink_data),.o_sink_valid(wf_sink_valid),
        .i_sink_ready(wf_pop),.o_available_count(wf_available),.o_sink_reset_done(wf_sink_done));
    end else begin: g_external_mw
        assign wf_source_ready=q_mw_source_ready;
        assign wf_source_done=i_external_fifo_reset_done;
        assign wf_sink_data=q_mw_sink_data;
        assign wf_sink_valid=q_mw_sink_valid;
        assign wf_sink_done=i_external_fifo_reset_done;
        assign wf_available=q_mw_available;
    end endgenerate
    reg [1:0] write_plane;
    reg [4:0] plane_remaining;
    wire chunk_retire=pack_phase==P_WAIT && write_plane==3;
    always @(*) begin
        y_pack_next=y_pack;y_pack_count_next=y_pack_count;
        if(y_push) begin y_pack_next=y_pack>>(y_emit_bytes*8);y_pack_count_next=y_pack_count-y_emit_bytes;end
        if(y_fire && y_good && !draining) begin
            y_pack_next=y_pack_next | (({128'd0,s_y} & (160'hffffffff>>(32-y_take*8)))<<(y_pack_count_next*8));
            y_pack_count_next=y_pack_count_next+y_take;
        end
        if(draining) begin y_pack_next=0;y_pack_count_next=0;end
    end
    genvar map_group;
    generate for(map_group=0;map_group<32;map_group=map_group+1)begin: g_map_group
        reg [7:0] confidence;
        reg [3:0] mask;
        assign confidence_pack[map_group*8+:8]=confidence;
        assign mask_pack[map_group*4+:4]=mask;
        always @(posedge i_clk or negedge i_rst_n)begin
            if(!i_rst_n)begin confidence<=0;mask<=0;end
            else if(begin_fire || draining)begin confidence<=0;mask<=0;end
            else if(chunk_retire)begin
                confidence<=map_group==0 ? {2'd0,confidence_carry} : 8'd0;
                mask<=map_group==0 ? {1'b0,mask_carry} : 4'd0;
            end else if(map_fire && map_good)begin
                if(first_map_group==map_group)begin
                    confidence<=appended_confidence[7:0];mask<=appended_mask[3:0];
                end else if(appended_cells>4 && second_map_group==map_group)begin
                    confidence<=appended_confidence[15:8];mask<=appended_mask[7:4];
                end
            end
        end
    end endgenerate
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            pack_phase<=P_GATHER;chunk_sealed<=0;chunk_base<=0;chunk_y_count<=0;chunk_map_count<=0;chunk_size<=0;
            y_pack<=0;y_pack_count<=0;confidence_partial<=0;mask_partial<=0;
            y_carry<=0;confidence_carry<=0;mask_carry<=0;y_carry_count<=0;map_carry_count<=0;
            y_x<=0;y_row<=0;map_x<=0;map_row<=0;y_pixels<=0;map_pixels<=0;y_done<=0;map_done<=0;
            write_enqueued<=0;write_dequeued<=0;
        end else if(begin_fire) begin
            pack_phase<=P_GATHER;chunk_sealed<=0;chunk_base<=0;chunk_y_count<=0;chunk_map_count<=0;chunk_size<=0;
            y_pack<=0;y_pack_count<=0;confidence_partial<=0;mask_partial<=0;
            y_carry<=0;confidence_carry<=0;mask_carry<=0;y_carry_count<=0;map_carry_count<=0;
            y_x<=0;y_row<=0;map_x<=0;map_row<=0;y_pixels<=0;map_pixels<=0;y_done<=0;map_done<=0;
            write_enqueued<=0;write_dequeued<=0;
        end else begin
            y_pack<=y_pack_next;y_pack_count<=y_pack_count_next;
            if(wf_push) write_enqueued<=write_enqueued+1'b1;
            if(wf_sink_valid && wf_pop) write_dequeued<=write_dequeued+1'b1;
            if(y_fire) begin
                y_pixels<=y_pixels+{13'd0,y_lanes};
                if(y_row_last) begin y_x<=0;y_row<=y_row+1'b1;end else y_x<=y_x+9'd4;
                if(s_y_last || y_last) y_done<=1;
                if(y_good && !draining) begin
                    chunk_y_count<=chunk_y_count+y_take;
                    y_carry_count<=y_lanes-y_take;y_carry<=s_y>>(y_take*8);
                end
            end
            if(map_fire) begin
                map_pixels<=map_pixels+{13'd0,map_lanes};
                if(map_row_last) begin map_x<=0;map_row<=map_row+1'b1;end else map_x<=map_x+9'd4;
                if(s_map_last || map_final) map_done<=1;
                if(map_good && !draining) begin
                    chunk_map_count<=chunk_map_count+map_take;map_carry_count<=carry_cells;
                    confidence_partial<=appended_cells>=4 ? appended_confidence[13:8] : appended_confidence[5:0];
                    mask_partial<=appended_cells>=4 ? appended_mask[6:4] : appended_mask[2:0];
                    confidence_carry<=(folded_input >> {map_take,1'b0}) & carry_confidence_mask;
                    mask_carry<=(s_mask >> map_take) & carry_mask_mask;
                end
            end
            if(draining) begin
                pack_phase<=P_GATHER;chunk_sealed<=0;chunk_y_count<=0;chunk_map_count<=0;
                confidence_partial<=0;mask_partial<=0;y_carry_count<=0;map_carry_count<=0;
            end else begin
                if(pack_phase==P_GATHER && !chunk_sealed && chunk_complete && chunk_y_count!=0) begin
                    chunk_sealed<=1;chunk_size<=chunk_y_count;
                end
                if(pack_phase==P_GATHER && chunk_sealed && y_pack_count==0) pack_phase<=P_CONF0;
                if(wf_push && pack_phase==P_CONF0) pack_phase<=chunk_size>64 ? P_CONF1 : P_MASK;
                if(wf_push && pack_phase==P_CONF1) pack_phase<=P_MASK;
                if(wf_push && pack_phase==P_MASK) pack_phase<=P_WAIT;
                if(chunk_retire) begin
                    pack_phase<=P_GATHER;chunk_sealed<=0;chunk_base<=chunk_base+{24'd0,chunk_size};
                    chunk_y_count<={5'd0,y_carry_count};chunk_map_count<={5'd0,map_carry_count};
                    y_pack<={136'd0,y_carry};y_pack_count<={2'd0,y_carry_count};
                    confidence_partial<=confidence_carry;mask_partial<=mask_carry;
                    y_carry_count<=0;map_carry_count<=0;y_carry<=0;confidence_carry<=0;mask_carry<=0;
                end
            end
        end
    end

    // Two AW credits, same-ID ordered W and real B. No extra payload queue.
    reg aw_pending;
    reg [27:0] write_address;
    reg [4:0] write_length,write_beat,write_head_length,write_tail_length;
    reg [1:0] write_queue_count,write_outstanding,write_completed;
    reg write_protocol_lost;
    reg [31:0] plane_logical;
    wire [31:0] write_pending=write_enqueued-write_dequeued;
    wire [5:0] write_reserved=write_queue_count==0 ? 6'd0 :
        {1'b0,write_head_length}-{1'b0,write_beat}+(write_queue_count==2 ? {1'b0,write_tail_length} : 6'd0);
    wire [4:0] write_boundary=boundary(plane_logical);
    wire [4:0] write_choice=plane_remaining<write_boundary ? plane_remaining : write_boundary;
    wire write_start=job_state==J_BUILD && !aw_pending && !draining && chunk_sealed && write_plane<3 &&
        write_outstanding<2 && write_queue_count<2 && write_choice!=0 &&
        wf_available>={4'd0,write_reserved}+{5'd0,write_choice};
    assign m_axi_awid=AXI_ID;assign m_axi_awaddr=write_address;
    assign m_axi_awlen={3'd0,write_length}-8'd1;assign m_axi_awsize=3'd4;assign m_axi_awburst=2'b01;
    assign m_axi_awvalid=o_reset_done && aw_pending;
    assign m_axi_wdata=wf_sink_data[127:0];assign m_axi_wstrb=wf_sink_data[143:128];
    assign m_axi_wlast=write_beat==write_head_length-5'd1;
    assign m_axi_wvalid=o_reset_done && write_queue_count!=0 && wf_sink_valid;
    assign wf_pop=(write_queue_count!=0 && m_axi_wready) || (write_queue_count==0 && !aw_pending && draining);
    assign m_axi_bready=o_reset_done && write_completed!=0;
    wire aw_fire=m_axi_awvalid && m_axi_awready,w_fire=m_axi_wvalid && m_axi_wready,b_fire=m_axi_bvalid && m_axi_bready;
    wire write_terminal=w_fire && m_axi_wlast,b_retire=b_fire && m_axi_bid==AXI_ID;
    wire write_quiet=!aw_pending && write_queue_count==0 && write_outstanding==0 && !write_protocol_lost &&
        write_pending==0 && y_pack_count==0 && (draining || (pack_phase==P_GATHER && chunk_y_count==0));
    assign o_write_quiescent=write_quiet;
    wire seal_now=pack_phase==P_GATHER && !chunk_sealed && chunk_complete && chunk_y_count!=0 && !draining;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            aw_pending<=0;write_address<=0;write_length<=0;write_beat<=0;
            write_head_length<=0;write_tail_length<=0;write_queue_count<=0;write_outstanding<=0;write_completed<=0;
            write_protocol_lost<=0;write_plane<=0;plane_logical<=0;plane_remaining<=0;
        end else if(begin_fire) begin
            aw_pending<=0;write_beat<=0;write_queue_count<=0;write_outstanding<=0;write_completed<=0;write_protocol_lost<=0;
            write_plane<=0;plane_logical<=y_base({camera,offered_valid ? !offered_bank : 1'b0});plane_remaining<=0;
        end else begin
            if(b_fire && m_axi_bid!=AXI_ID) write_protocol_lost<=1;
            case({aw_fire,b_retire})
                2'b10:write_outstanding<=write_outstanding+1'b1;
                2'b01:write_outstanding<=write_outstanding-1'b1;default:begin end
            endcase
            case({write_terminal,b_retire})
                2'b10:write_completed<=write_completed+1'b1;
                2'b01:write_completed<=write_completed-1'b1;default:begin end
            endcase
            case({aw_fire,write_terminal})
                2'b10:begin
                    if(write_queue_count==0) write_head_length<=write_length;else write_tail_length<=write_length;
                    write_queue_count<=write_queue_count+1'b1;
                end
                2'b01:begin write_head_length<=write_tail_length;write_queue_count<=write_queue_count-1'b1;end
                2'b11:begin
                    if(write_queue_count==1) write_head_length<=write_length;
                    else begin write_head_length<=write_tail_length;write_tail_length<=write_length;end
                end
                default:begin end
            endcase
            if(write_terminal) write_beat<=0;else if(w_fire) write_beat<=write_beat+1'b1;
            if(seal_now) begin
                write_plane<=0;plane_logical<=y_base(candidate_bank)+chunk_base;
                plane_remaining<=({1'b0,chunk_y_count}+9'd15)>>4;
            end
            if(write_start) begin write_address<=physical(plane_logical);write_length<=write_choice;aw_pending<=1;end
            if(aw_fire) begin
                aw_pending<=0;plane_logical<=plane_logical+{23'd0,write_length,4'd0};
                plane_remaining<=plane_remaining-write_length;
                if(plane_remaining==write_length) begin
                    write_plane<=write_plane+1'b1;
                    if(write_plane==0) begin plane_logical<=MAP_BASE+(chunk_base>>2);plane_remaining<=({1'b0,chunk_size}+9'd63)>>6;end
                    if(write_plane==1) begin plane_logical<=MASK_BASE+(chunk_base>>3);plane_remaining<=1;end
                end
            end
        end
    end

    // Shared read FIFO; BUILD consumes raw Y, PROJECT repeats confidence rows.
    reg ar_pending;
    reg [31:0] read_logical,read_remaining,read_total_bytes;
    reg [27:0] read_address;
    reg [4:0] read_length,read_head_length,read_tail_length;
    reg [1:0] read_outstanding;
    reg read_protocol_lost;
    reg [8:0] read_beat;
    reg [31:0] read_enqueued,read_dequeued;
    wire [31:0] read_pending=read_enqueued-read_dequeued;
    wire [4:0] read_boundary=boundary(read_logical);
    wire [4:0] read_choice=read_remaining<read_boundary ? read_remaining[4:0] : read_boundary;
    wire [5:0] read_reserved=read_outstanding==0 ? 6'd0 :
        (read_beat<{4'd0,read_head_length} ? {1'b0,read_head_length}-read_beat[5:0] : 6'd0)+
        (read_outstanding==2 ? {1'b0,read_tail_length} : 6'd0);
    wire reading_enabled=(job_state==J_BUILD && history_used) || job_state==J_PROJECT;
    wire read_start=reading_enabled && !ar_pending && !draining && read_outstanding<2 && read_remaining!=0 &&
        read_pending+{26'd0,read_reserved}+{27'd0,read_choice}<=32'd496;
    assign m_axi_arid=AXI_ID;assign m_axi_araddr=read_address;
    assign m_axi_arlen={3'd0,read_length}-8'd1;assign m_axi_arsize=3'd4;assign m_axi_arburst=2'b01;
    assign m_axi_arvalid=o_reset_done && ar_pending;
    assign m_axi_rready=o_reset_done && read_outstanding!=0 && (draining || rf_source_ready);
    wire ar_fire=m_axi_arvalid && m_axi_arready,r_fire=m_axi_rvalid && m_axi_rready;
    wire rf_push=r_fire && !draining;
    wire read_terminal=r_fire && m_axi_rlast && m_axi_rid==AXI_ID &&
        read_beat=={4'd0,read_head_length}-9'd1 && !read_protocol_lost;
    wire read_protocol_error=r_fire && (m_axi_rid!=AXI_ID ||
        m_axi_rlast!=(read_beat=={4'd0,read_head_length}-9'd1));
    wire rf_pop;
    raw_capture_fifo_ip u_read_fifo(
        .i_source_clk(i_clk),.i_source_rst_n(i_rst_n),.i_source_data({16'd0,m_axi_rlast,m_axi_rresp,m_axi_rdata}),
        .i_source_valid(m_axi_rvalid && read_outstanding!=0 && !draining),.o_source_ready(rf_source_ready),.o_source_reset_done(rf_source_done),
        .i_sink_clk(i_clk),.i_sink_rst_n(i_rst_n),.o_sink_data(rf_sink_data),.o_sink_valid(rf_sink_valid),
        .i_sink_ready(rf_pop),.o_available_count(rf_available),.o_sink_reset_done(rf_sink_done));
    wire project_fire=i_project_plan_valid && o_project_plan_ready;
    wire project_match=i_project_frame==frame && i_project_history_frame==old_frame && i_project_key==pipeline_key &&
        i_project_tag=={32'd0,tag} && i_project_history_tag=={32'd0,old_tag};
    reg [255:0] unpack_data,unpack_next;
    reg [8:0] unpack_bits,unpack_bits_next;
    reg [31:0] read_bytes_popped;
    reg [8:0] output_x;
    reg [15:0] output_y;
    reg [31:0] output_index,project_groups;
    reg all_groups_formed,row_first_word;
    reg [31:0] row_bit_base;
    reg [2:0] repeat_phase;
    reg [6:0] row_skip_bits;
    wire output_row_last=output_x+9'd4>=width;
    wire [3:0] output_keep=keep_for(width-output_x);
    wire [2:0] output_lanes=lanes(output_keep);
    wire output_frame_last=output_row_last && output_y==(job_state==J_PROJECT ? frame[236:221]-16'd1 : {8'd0,height}-16'd1);
    wire output_advance=job_state==J_PROJECT ? (!map_valid || map_ready) : (!h_valid || h_ready);
    wire [5:0] output_bits=job_state==J_PROJECT ? {2'd0,output_lanes,1'b0} : {output_lanes,3'd0};
    wire [31:0] read_bytes_remaining=read_total_bytes-read_bytes_popped;
    wire [4:0] read_take_bytes=read_bytes_remaining>=16 ? 5'd16 : read_bytes_remaining[4:0];
    wire [8:0] pop_bits=job_state==J_PROJECT ? 9'd128-(row_first_word ? {2'd0,row_skip_bits} : 9'd0) : {1'b0,read_take_bytes,3'd0};
    assign rf_pop=(job_state==J_BUILD || job_state==J_PROJECT) &&
        (draining || (!all_groups_formed && unpack_bits<=128));
    wire read_pop=rf_sink_valid && rf_pop;
    // Prefix discard belongs to one received word, before the shared reservoir.
    wire [127:0] read_word=rf_sink_data[127:0] >>
        (job_state==J_PROJECT && row_first_word ? row_skip_bits : 7'd0);
    reg form_group;
    reg [31:0] formed_y;
    reg [7:0] formed_conf;
    always @(*) begin
        unpack_next=unpack_data;unpack_bits_next=unpack_bits;form_group=0;formed_y=0;formed_conf=0;
        if(read_pop && !draining) begin
            // A pop appends at most128 bits at an even offset0..128. BUILD
            // adds/consumes bytes; PROJECT adds/consumes two-bit cells.
            unpack_next=unpack_next | ({128'd0,read_word} << {unpack_bits[7:1],1'b0});
            unpack_bits_next=unpack_bits+pop_bits;
        end
        if(output_advance && !all_groups_formed && reading_enabled && !draining && unpack_bits_next>=output_bits) begin
            form_group=1;
            case(output_lanes)
                3'd1:begin formed_y={24'd0,unpack_next[7:0]};formed_conf={6'd0,unpack_next[1:0]};end
                3'd2:begin formed_y={16'd0,unpack_next[15:0]};formed_conf={4'd0,unpack_next[3:0]};end
                3'd3:begin formed_y={8'd0,unpack_next[23:0]};formed_conf={2'd0,unpack_next[5:0]};end
                default:begin formed_y=unpack_next[31:0];formed_conf=unpack_next[7:0];end
            endcase
            // Exactly four possible Y8 groups or four confidence2 groups.
            case(output_bits)
                6'd2:unpack_next={2'd0,unpack_next[255:2]};
                6'd4:unpack_next={4'd0,unpack_next[255:4]};
                6'd6:unpack_next={6'd0,unpack_next[255:6]};
                6'd8:unpack_next={8'd0,unpack_next[255:8]};
                6'd16:unpack_next={16'd0,unpack_next[255:16]};
                6'd24:unpack_next={24'd0,unpack_next[255:24]};
                6'd32:unpack_next={32'd0,unpack_next[255:32]};
                default:unpack_next=0;
            endcase
            unpack_bits_next=unpack_bits_next-output_bits;
            if(job_state==J_PROJECT && output_row_last) begin unpack_next=0;unpack_bits_next=0;end
        end
        if(draining) begin unpack_next=0;unpack_bits_next=0;end
    end
    wire row_advance=form_group && job_state==J_PROJECT && output_row_last && !output_frame_last;
    wire [31:0] next_row_bit_base=row_bit_base+(repeat_phase==5 ? {22'd0,width,1'b0} : 32'd0);
    wire [31:0] next_row_aligned=next_row_bit_base>>7;
    wire [9:0] next_row_bits={3'd0,next_row_bit_base[6:0]}+{width,1'b0};
    wire [31:0] next_row_words=({22'd0,next_row_bits}+32'd127)>>7;
    wire read_bus_quiet=!ar_pending && read_outstanding==0 && !read_protocol_lost && read_remaining==0 && read_pending==0;
    assign o_read_quiescent=read_bus_quiet && unpack_bits==0 && !h_valid && !map_valid;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            ar_pending<=0;read_logical<=0;read_remaining<=0;read_total_bytes<=0;read_address<=0;read_length<=0;
            read_head_length<=0;read_tail_length<=0;read_outstanding<=0;read_protocol_lost<=0;read_beat<=0;
            read_enqueued<=0;read_dequeued<=0;
        end else if(begin_fire || project_fire) begin
            ar_pending<=0;read_beat<=0;read_outstanding<=0;read_protocol_lost<=0;read_enqueued<=0;read_dequeued<=0;
            if(begin_fire) begin
                read_logical<=y_base({camera,offered_bank});read_total_bytes<={16'd0,offered_pixels};
                read_remaining<=i_begin_history_used && history_good && begin_good ? ({16'd0,offered_pixels}+32'd15)>>4 : 0;
            end else begin
                read_logical<=MAP_BASE;read_total_bytes<=0;
                read_remaining<=i_project_use_map && project_match && map_committed ? ({22'd0,width,1'b0}+32'd127)>>7 : 0;
            end
        end else begin
            if(rf_push) read_enqueued<=read_enqueued+1'b1;
            if(read_pop) read_dequeued<=read_dequeued+1'b1;
            if(draining) read_remaining<=0;
            if(read_protocol_error) read_protocol_lost<=1;
            case({ar_fire,read_terminal})
                2'b10:begin
                    if(read_outstanding==0) read_head_length<=read_length;else read_tail_length<=read_length;
                    read_outstanding<=read_outstanding+1'b1;
                end
                2'b01:begin read_head_length<=read_tail_length;read_outstanding<=read_outstanding-1'b1;end
                2'b11:begin
                    if(read_outstanding==1) read_head_length<=read_length;
                    else begin read_head_length<=read_tail_length;read_tail_length<=read_length;end
                end
                default:begin end
            endcase
            if(read_terminal) read_beat<=0;else if(r_fire && read_beat!=511) read_beat<=read_beat+1'b1;
            if(read_start) begin read_address<=physical(read_logical);read_length<=read_choice;ar_pending<=1;end
            if(ar_fire) begin
                ar_pending<=0;read_logical<=read_logical+{23'd0,read_length,4'd0};
                if(!draining) read_remaining<=read_remaining-{27'd0,read_length};
            end
            if(row_advance) begin read_logical<=MAP_BASE+{next_row_aligned[27:0],4'd0};read_remaining<=next_row_words;end
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            unpack_data<=0;unpack_bits<=0;read_bytes_popped<=0;output_x<=0;output_y<=0;output_index<=0;
            project_groups<=0;all_groups_formed<=0;row_first_word<=1;row_bit_base<=0;repeat_phase<=0;row_skip_bits<=0;
            h_valid<=0;h_y<=0;h_keep<=0;h_sof<=0;h_eol<=0;h_last<=0;
            map_valid<=0;map_confidence<=0;map_keep<=0;map_sof<=0;map_eol<=0;map_last<=0;map_index<=0;
        end else if(begin_fire || project_fire) begin
            unpack_data<=0;unpack_bits<=0;read_bytes_popped<=0;output_x<=0;output_y<=0;output_index<=0;
            project_groups<=0;all_groups_formed<=0;row_first_word<=1;row_bit_base<=0;repeat_phase<=0;row_skip_bits<=0;h_valid<=0;map_valid<=0;
        end else begin
            unpack_data<=unpack_next;unpack_bits<=unpack_bits_next;
            if(read_pop && !draining) begin read_bytes_popped<=read_bytes_popped+{27'd0,read_take_bytes};row_first_word<=0;end
            if(h_valid && h_ready) h_valid<=0;
            if(map_valid && map_ready) begin map_valid<=0;project_groups<=project_groups+1'b1;end
            if(form_group) begin
                if(job_state==J_PROJECT) begin
                    map_valid<=1;map_confidence<=formed_conf;map_keep<=output_keep;map_sof<=output_index==0;
                    map_eol<=output_row_last;map_last<=output_frame_last;map_index<=output_index;
                end else begin h_valid<=1;h_y<=formed_y;h_keep<=output_keep;h_sof<=output_index==0;h_eol<=output_row_last;h_last<=output_frame_last;end
                output_index<=output_index+1'b1;
                if(output_row_last) begin output_x<=0;output_y<=output_y+1'b1;end else output_x<=output_x+9'd4;
                if(output_frame_last) all_groups_formed<=1;
            end
            if(row_advance) begin
                row_bit_base<=next_row_bit_base;row_skip_bits<=next_row_bit_base[6:0];row_first_word<=1;
                repeat_phase<=repeat_phase==5 ? 3'd0 : repeat_phase+1'b1;
            end
        end
    end

    wire close_fire=i_close_valid && o_close_ready;
    wire close_match=i_close_frame==frame && i_close_key==pipeline_key && i_close_context==context_locked && i_close_tag==tag;
    wire close_good=i_close_write_pixels==y_pixels && (!i_close_commit_candidate || (y_done && map_done && y_pixels==map_pixels));
    assign o_close_ready=o_reset_done && job_state==J_BUILD && !close_seen;
    assign m_ack_valid=o_reset_done && job_state==J_ACK;
    assign m_ack_frame=frame;assign m_ack_key=pipeline_key;assign m_ack_context=context_locked;assign m_ack_tag=tag;
    assign m_ack_quiescent=write_quiet && o_read_quiescent;assign m_ack_write_pixels=y_pixels;assign m_ack_error=error_code;
    assign o_publish_ready=o_reset_done && job_state==J_PUBLISH && m_ack_quiescent;
    wire publish_fire=i_publish_valid && o_publish_ready;
    wire publish_match=i_publish_frame==frame && i_publish_key==pipeline_key && i_publish_context==context_locked && i_publish_tag==tag;
    wire publish_commit=publish_fire && publish_match && i_publish_success && m_ack_write_ok && !bad && !i_cancel;
    assign o_project_plan_ready=o_reset_done && job_state==J_MAP && o_read_quiescent;
    assign o_project_close_ready=o_reset_done && job_state==J_PROJECT && !project_close_seen;
    wire project_close_fire=i_project_close_valid && o_project_close_ready;
    wire project_close_match=i_project_close_frame==frame && i_project_close_key==pipeline_key && i_project_close_tag=={32'd0,tag};
    assign m_project_ack_valid=o_reset_done && job_state==J_PROJ_ACK;
    assign m_project_ack_frame=frame;assign m_project_ack_key=pipeline_key;assign m_project_ack_tag={32'd0,tag};
    assign m_project_ack_quiescent=o_read_quiescent;assign m_project_ack_groups=project_groups;
    assign o_release_ready=o_reset_done && job_state==J_MAP && o_read_quiescent && write_quiet;
    wire release_fire=i_release_valid && o_release_ready;
    wire release_match=i_release_frame==frame && i_release_key==pipeline_key && i_release_tag=={32'd0,tag};
    wire fault_now=(job_state==J_BUILD && i_cancel) || (job_state==J_PROJECT && i_project_cancel) ||
        (y_fire && !y_good && !draining) || (map_fire && !map_good && !draining) ||
        (close_fire && (!close_match || !close_good)) ||
        (b_fire && (m_axi_bid!=AXI_ID || m_axi_bresp!=0)) || (r_fire && (m_axi_rresp!=0 || read_protocol_error)) ||
        (publish_fire && (!publish_match || (i_publish_success && !m_ack_write_ok))) ||
        (project_fire && i_project_use_map && (!project_match || !map_committed)) ||
        (project_close_fire && (!project_close_match || i_project_close_cancel));
    wire [7:0] fault_code=(i_cancel || i_project_cancel) ? E_CANCEL :
        (y_fire && !y_good) || (map_fire && !map_good) ? E_STREAM :
        close_fire ? E_CLOSE : b_fire ? E_B : r_fire ? (read_protocol_error ? E_PROTOCOL : E_R) :
        publish_fire ? E_PUBLISH : E_PROJECT;
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            job_state<=J_IDLE;frame<=0;old_frame<=0;pipeline_key<=0;context_locked<=0;tag<=0;old_tag<=0;
            width<=0;height<=0;history_used<=0;candidate_bank<=0;pinned_banks<=0;bad<=0;error_code<=0;
            close_seen<=0;close_permission<=0;project_close_seen<=0;m_ack_write_ok<=0;m_project_ack_ok<=0;
            map_committed<=0;f26_success<=0;temporal_trust<=0;global_hint<=0;brightness_hint<=0;full_pixels<=0;
            offer_valid0<=0;offer_valid1<=0;active0<=0;active1<=0;offer0<=0;offer1<=0;
            offer_key0<=0;offer_key1<=0;offer_context0<=0;offer_context1<=0;offer_tag0<=0;offer_tag1<=0;
            offer_pixels0<=0;offer_pixels1<=0;offer_width0<=0;offer_width1<=0;offer_height0<=0;offer_height1<=0;
        end else begin
            if(fault_now && !bad) begin bad<=1;error_code<=fault_code;end
            case(job_state)
                J_IDLE:if(begin_fire) begin
                    frame<=i_begin_frame;old_frame<=i_begin_history_frame;pipeline_key<=i_begin_key;context_locked<=i_begin_context;
                    tag<=i_begin_tag;old_tag<=i_begin_history_tag;width<=i_begin_width;height<=i_begin_height;history_used<=i_begin_history_used;
                    candidate_bank<={camera,offered_valid ? !offered_bank : 1'b0};
                    pinned_banks<=i_begin_history_used && history_good ? (4'b1<<{camera,offered_bank}) : 4'd0;
                    bad<=!begin_good || (i_begin_history_used && !history_good);
                    error_code<=!begin_good ? E_CONFIG : i_begin_history_used && !history_good ? E_HISTORY : 8'd0;
                    close_seen<=0;close_permission<=0;project_close_seen<=0;m_ack_write_ok<=0;map_committed<=0;
                    f26_success<=0;temporal_trust<=0;global_hint<=0;brightness_hint<=0;full_pixels<=0;job_state<=J_BUILD;
                end
                J_BUILD:begin
                    if(close_fire && close_match) begin close_seen<=1;close_permission<=i_close_commit_candidate && close_good;end
                    if(close_seen && !close_permission && !bad) begin bad<=1;error_code<=E_CLOSE;end
                    if(close_seen && write_quiet && o_read_quiescent) begin
                        m_ack_write_ok<=close_permission && !bad && !i_cancel;full_pixels<=y_pixels;job_state<=J_ACK;
                    end
                end
                J_ACK:if(m_ack_valid && m_ack_ready) job_state<=J_PUBLISH;
                J_PUBLISH:if(publish_fire && publish_match) begin
                    if(publish_commit) begin
                        if(frame[4]) begin
                            offer_valid1<=1;active1<=candidate_bank[0];offer1<=frame;offer_key1<=pipeline_key;offer_context1<=context_locked;
                            offer_tag1<=tag;offer_pixels1<=y_pixels;offer_width1<=width;offer_height1<=height;
                        end else begin
                            offer_valid0<=1;active0<=candidate_bank[0];offer0<=frame;offer_key0<=pipeline_key;offer_context0<=context_locked;
                            offer_tag0<=tag;offer_pixels0<=y_pixels;offer_width0<=width;offer_height0<=height;
                        end
                    end
                    map_committed<=publish_commit && history_used;f26_success<=publish_commit;
                    temporal_trust<=publish_commit && history_used && i_publish_temporal_trust;
                    global_hint<=i_publish_global_change;brightness_hint<=i_publish_brightness_change;
                    pinned_banks<=0;history_used<=0;job_state<=J_MAP;
                end
                J_MAP:begin
                    if(project_fire && i_project_use_map) begin
                        bad<=!project_match || !map_committed;error_code<=project_match && map_committed ? 8'd0 : E_PROJECT;
                        project_close_seen<=0;m_project_ack_ok<=0;job_state<=J_PROJECT;
                    end
                    if(release_fire && release_match) begin map_committed<=0;job_state<=J_IDLE;bad<=0;error_code<=0;end
                end
                J_PROJECT:begin
                    if(project_close_fire && project_close_match) project_close_seen<=1;
                    if(project_close_seen && o_read_quiescent) begin
                        m_project_ack_ok<=!bad && !i_project_cancel && all_groups_formed;job_state<=J_PROJ_ACK;
                    end
                end
                J_PROJ_ACK:if(m_project_ack_valid && m_project_ack_ready) job_state<=J_MAP;
                J_QUARANTINE:begin end
                default:begin job_state<=J_QUARANTINE;bad<=1;error_code<=E_PROTOCOL;end
            endcase
        end
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if(!i_rst_n) begin
            o_aw_count<=0;o_w_count<=0;o_b_count<=0;o_ar_count<=0;o_r_count<=0;
            o_Y_commit_count<=0;o_map_commit_count<=0;o_release_count<=0;o_fault_count<=0;
        end else if(i_debug_clear) begin
            o_aw_count<=0;o_w_count<=0;o_b_count<=0;o_ar_count<=0;o_r_count<=0;
            o_Y_commit_count<=0;o_map_commit_count<=0;o_release_count<=0;o_fault_count<=0;
        end else begin
            if(aw_fire) o_aw_count<=o_aw_count+1'b1;if(w_fire) o_w_count<=o_w_count+1'b1;
            if(b_fire) o_b_count<=o_b_count+1'b1;if(ar_fire) o_ar_count<=o_ar_count+1'b1;
            if(r_fire) o_r_count<=o_r_count+1'b1;
            if(publish_commit) o_Y_commit_count<=o_Y_commit_count+1'b1;
            if(publish_commit && history_used) o_map_commit_count<=o_map_commit_count+1'b1;
            if(release_fire && release_match) o_release_count<=o_release_count+1'b1;
            if(fault_now && !bad) o_fault_count<=o_fault_count+1'b1;
        end
    end
endmodule
