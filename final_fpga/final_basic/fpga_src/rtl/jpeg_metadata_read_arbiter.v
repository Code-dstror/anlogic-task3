`timescale 1ns/1ps

// Register one typed metadata grant; MASK BUSY never revokes a JPEG header.
module jpeg_metadata_read_arbiter (
    input wire i_clk,i_rst_n,i_start_block,
    input wire s_jpeg_req_valid,
    output wire s_jpeg_req_ready,
    input wire [144:0] s_jpeg_req_tuple,s_jpeg_probe_tuple,
    input wire [15:0] s_jpeg_req_version,
    output wire m_jpeg_rsp_valid,m_jpeg_rsp_ok,m_jpeg_rsp_shape_valid,
    input wire m_jpeg_rsp_ready,
    output wire [144:0] m_jpeg_rsp_tuple,
    output wire [7:0] m_jpeg_rsp_error,
    input wire s_jpeg_stream_start,
    output wire [127:0] m_jpeg_stream_data,
    output wire m_jpeg_stream_valid,m_jpeg_stream_last,
    input wire m_jpeg_stream_ready,
    input wire s_mask_req_valid,
    output wire s_mask_req_ready,
    input wire [144:0] s_mask_req_tuple,
    output wire m_mask_rsp_valid,m_mask_rsp_ok,m_mask_rsp_qualified,
    input wire m_mask_rsp_ready,
    output wire [144:0] m_mask_rsp_tuple,
    output wire [7:0] m_mask_rsp_error,
    output wire [23:0] m_mask_rsp_pixels,
    output wire [2:0] m_mask_rsp_source_type,
    output wire m_store_req_valid,
    input wire m_store_req_ready,
    output wire [144:0] m_store_req_tuple,
    output wire [15:0] m_store_req_version,
    output wire m_store_req_mask,
    input wire s_store_rsp_valid,s_store_rsp_ok,s_store_rsp_shape_valid,
    output wire s_store_rsp_ready,
    input wire [144:0] s_store_rsp_tuple,
    input wire [7:0] s_store_rsp_error,
    input wire s_store_rsp_mask_qualified,
    input wire [23:0] s_store_rsp_pixels,
    input wire [2:0] s_store_rsp_source_type,
    output wire m_store_stream_start,
    input wire [127:0] s_store_stream_data,
    input wire s_store_stream_valid,s_store_stream_last,
    output wire s_store_stream_ready,
    input wire i_store_read_quiescent,
    output wire o_jpeg_probe_idle,o_quiescent,
    output reg o_protocol_fault
);
    localparam [2:0] IDLE=0,JPEG_REQ=1,JPEG_OWN=2,MASK_REQ=3,MASK_OWN=4,DRAIN=5;
    localparam [7:0] E_BUSY=2;
    reg [2:0] state,state_next;
    reg [144:0] grant_tuple,busy_tuple;
    reg [15:0] grant_version;
    reg busy_valid;
    wire jpeg_grant=i_rst_n && !o_protocol_fault && state==IDLE &&
        !i_start_block && m_store_req_ready && s_jpeg_req_valid;
    wire mask_fire=s_mask_req_valid && s_mask_req_ready;
    wire mask_grant=mask_fire && state==IDLE && !i_start_block &&
        m_store_req_ready && !s_jpeg_req_valid;
    wire response_matches=s_store_rsp_tuple==grant_tuple;
    wire jpeg_response=state==JPEG_OWN && s_store_rsp_valid && response_matches && !o_protocol_fault;
    wire mask_response=state==MASK_OWN && s_store_rsp_valid && response_matches && !o_protocol_fault;
    wire response_fire=s_store_rsp_valid && s_store_rsp_ready;

    assign s_jpeg_req_ready=i_rst_n && !o_protocol_fault && state==IDLE &&
        !i_start_block && m_store_req_ready;
    assign s_mask_req_ready=i_rst_n && !o_protocol_fault && !busy_valid &&
        state!=MASK_REQ && state!=MASK_OWN;
    assign m_store_req_valid=i_rst_n && !o_protocol_fault && (state==JPEG_REQ || state==MASK_REQ);
    // Idle probe belongs to JPEG; a registered grant selects the real request.
    assign m_store_req_tuple=state==IDLE ? s_jpeg_probe_tuple:grant_tuple;
    assign m_store_req_version=grant_version;
    assign m_store_req_mask=state==MASK_REQ || state==MASK_OWN;
    assign m_jpeg_rsp_valid=i_rst_n && jpeg_response;
    assign m_jpeg_rsp_tuple=s_store_rsp_tuple;
    assign m_jpeg_rsp_ok=s_store_rsp_ok;
    assign m_jpeg_rsp_error=s_store_rsp_error;
    assign m_jpeg_rsp_shape_valid=s_store_rsp_shape_valid;
    assign m_mask_rsp_valid=i_rst_n && (busy_valid || mask_response);
    assign m_mask_rsp_tuple=busy_valid ? busy_tuple:s_store_rsp_tuple;
    assign m_mask_rsp_ok=!busy_valid && s_store_rsp_ok;
    assign m_mask_rsp_error=busy_valid ? E_BUSY:s_store_rsp_error;
    assign m_mask_rsp_qualified=!busy_valid && s_store_rsp_mask_qualified;
    assign m_mask_rsp_pixels=busy_valid ? 24'd0:s_store_rsp_pixels;
    assign m_mask_rsp_source_type=busy_valid ? 3'd0:s_store_rsp_source_type;
    assign s_store_rsp_ready=i_rst_n && !o_protocol_fault && response_matches &&
        ((state==JPEG_OWN && m_jpeg_rsp_ready) ||
         (state==MASK_OWN && !busy_valid && m_mask_rsp_ready));
    assign m_store_stream_start=i_rst_n && jpeg_response && s_jpeg_stream_start;
    assign m_jpeg_stream_data=s_store_stream_data;
    assign m_jpeg_stream_valid=i_rst_n && state==JPEG_OWN && !o_protocol_fault && s_store_stream_valid;
    assign m_jpeg_stream_last=s_store_stream_last;
    assign s_store_stream_ready=i_rst_n && state==JPEG_OWN && !o_protocol_fault && m_jpeg_stream_ready;
    assign o_jpeg_probe_idle=i_rst_n && state==IDLE && !i_start_block && !o_protocol_fault;
    assign o_quiescent=i_rst_n && state==IDLE && !busy_valid && !o_protocol_fault;

    always @(posedge i_clk)begin
        if(!i_rst_n)state<=IDLE;
        else state<=state_next;
    end
    always @(*)begin
        state_next=state;
        case(state)
        IDLE:if(jpeg_grant)state_next=JPEG_REQ;
             else if(mask_grant)state_next=MASK_REQ;
        JPEG_REQ:if(m_store_req_valid && m_store_req_ready)state_next=JPEG_OWN;
        MASK_REQ:if(m_store_req_valid && m_store_req_ready)state_next=MASK_OWN;
        JPEG_OWN:if(response_fire)state_next=DRAIN;
        MASK_OWN:if(response_fire)state_next=DRAIN;
        DRAIN:if(i_store_read_quiescent)state_next=IDLE;
        default:state_next=state;
        endcase
    end
    always @(posedge i_clk)begin
        if(!i_rst_n)begin
            grant_tuple<=0;grant_version<=0;busy_tuple<=0;busy_valid<=0;o_protocol_fault<=0;
        end else begin
            if(busy_valid && m_mask_rsp_ready)busy_valid<=0;
            if(jpeg_grant)begin grant_tuple<=s_jpeg_req_tuple;grant_version<=s_jpeg_req_version;end
            if(mask_grant)begin grant_tuple<=s_mask_req_tuple;grant_version<=16'd3;end
            if(mask_fire && !mask_grant)begin busy_tuple<=s_mask_req_tuple;busy_valid<=1;end
            if(((state==JPEG_OWN || state==MASK_OWN) && s_store_rsp_valid && !response_matches) || state>DRAIN)
                o_protocol_fault<=1;
        end
    end
endmodule
