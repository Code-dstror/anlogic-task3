`timescale 1ns/1ps
// PH1A TRGT1 to the camera register endpoint. Only one host read owns the
// completion lookup at a time. Client0 DMA and BYPASS fence traffic are separate.
module camera_pcie_bar_rx (
    input wire core_clk, core_rst_n,
    input wire radm_trgt1_hv, radm_trgt1_dv, radm_trgt1_eot,
    input wire radm_trgt1_tlp_abort, radm_trgt1_dllp_abort, radm_trgt1_ecrc_err,
    input wire radm_trgt1_poisoned,
    input wire [3:0] radm_trgt1_dwen, radm_trgt1_first_be, radm_trgt1_last_be,
    input wire [1:0] radm_trgt1_fmt, radm_trgt1_ats,
    input wire [4:0] radm_trgt1_type,
    input wire [2:0] radm_trgt1_attr, radm_trgt1_tc, radm_trgt1_in_membar_range,
    input wire [15:0] radm_trgt1_reqid,
    input wire [63:0] radm_trgt1_addr,
    input wire [127:0] radm_trgt1_data,
    input wire [9:0] radm_trgt1_tag, radm_trgt1_dw_len, trgt_lookup_id,
    input wire radm_trgt1_rom_in_range, radm_trgt1_func_num, radm_trgt1_vfunc_active,
    input wire trgt_lookup_empty,
    output wire trgt1_radm_halt,
    output wire [127:0] m_axis_cq_tdata,
    output wire [3:0] m_axis_cq_tkeep,
    output wire [87:0] m_axis_cq_tuser,
    output wire m_axis_cq_tvalid, m_axis_cq_tlast,
    input wire m_axis_cq_tready,
    output reg [9:0] o_read_lookup, o_read_tag,
    output wire o_read_pending,
    input wire i_reply_done
);
    localparam IDLE=3'd0, RECEIVE=3'd1, HEADER=3'd2, PAYLOAD=3'd3, WAIT_REPLY=3'd4;
    localparam DROP=2'd0, WRITE=2'd1, READ=2'd2, UNSUPPORTED=2'd3;
    reg [2:0] state;
    reg [1:0] request_kind;
    reg data_seen, poisoned;
    reg [63:0] address;
    reg [31:0] payload;
    reg [15:0] requester;
    reg [9:0] dw_length;
    reg [2:0] attributes, traffic_class, bar;
    reg other_function;
    reg [7:0] byte_enables;

    wire memory_request=radm_trgt1_type==5'h00;
    wire needs_reply=(memory_request && !radm_trgt1_fmt[1]) ||
        radm_trgt1_type==5'h01 || radm_trgt1_type==5'h02 ||
        radm_trgt1_type==5'h04 || radm_trgt1_type==5'h05 ||
        (radm_trgt1_type>=5'h0c && radm_trgt1_type<=5'h0e);
    wire [1:0] header_kind=memory_request ?
        (radm_trgt1_fmt[1] ? WRITE : READ) : needs_reply ? UNSUPPORTED : DROP;
    wire taking_header=state==IDLE && radm_trgt1_hv;
    wire [1:0] kind=taking_header ? header_kind : request_kind;
    wire seen=taking_header ? 1'b0 : data_seen;
    wire bad_end=radm_trgt1_tlp_abort || radm_trgt1_dllp_abort || radm_trgt1_ecrc_err;
    wire native_valid=radm_trgt1_hv || radm_trgt1_dv;
    wire odd_payload=radm_trgt1_dv && (seen || radm_trgt1_dwen!=4'b0001);
    wire packet_bad=bad_end || (taking_header ? radm_trgt1_poisoned : poisoned);

    // UG913: the target holds its beat until HALT is sampled low. Only the
    // active incoming packet can advance. Retain an accepted write until EOT
    // has qualified its data, before making any MMIO side effect possible.
    assign trgt1_radm_halt=!core_rst_n || !trgt_lookup_empty ||
        (state!=IDLE && state!=RECEIVE);
    wire accept=native_valid && !trgt1_radm_halt && (taking_header || state==RECEIVE);
    assign o_read_pending=core_rst_n && state==WAIT_REPLY;
    wire [3:0] cq_type=request_kind==WRITE ? 4'd1 : request_kind==READ ? 4'd0 : 4'd2;
    wire [127:0] header_word={1'b0,attributes,traffic_class,6'd20,bar,
        7'd0,other_function,o_read_tag[7:0],requester,1'b0,cq_type,1'b0,dw_length,address};
    assign m_axis_cq_tvalid=core_rst_n && (state==HEADER || state==PAYLOAD);
    assign m_axis_cq_tdata=state==PAYLOAD ? {96'd0,payload} : header_word;
    assign m_axis_cq_tkeep=state==PAYLOAD ? 4'h1 : 4'hf;
    assign m_axis_cq_tlast=state==PAYLOAD || request_kind!=WRITE;
    assign m_axis_cq_tuser=state==HEADER ? {47'd0,1'b1,32'd0,byte_enables} : 88'd0;

    always @(posedge core_clk) begin
        if(accept && taking_header) begin
            address<={radm_trgt1_addr[63:2],radm_trgt1_ats};
            bar<=radm_trgt1_rom_in_range ? 3'd6 : radm_trgt1_in_membar_range;
            requester<=radm_trgt1_reqid;
            o_read_tag<=radm_trgt1_tag;
            o_read_lookup<=trgt_lookup_id;
            traffic_class<=radm_trgt1_tc;
            attributes<=radm_trgt1_attr;
            other_function<=radm_trgt1_func_num || radm_trgt1_vfunc_active;
            dw_length<=radm_trgt1_dw_len;
            byte_enables<={radm_trgt1_last_be,radm_trgt1_first_be};
        end
        if(accept && radm_trgt1_dv) payload<=radm_trgt1_data[31:0];
    end
    always @(posedge core_clk or negedge core_rst_n) begin
        if(!core_rst_n) begin
            state<=IDLE;
            data_seen<=0;
            poisoned<=0;
            request_kind<=DROP;
        end else if(accept) begin
            data_seen<=seen || radm_trgt1_dv;
            poisoned<=packet_bad;
            request_kind<=kind;
            state<=RECEIVE;
            if(kind==WRITE && (odd_payload || (taking_header && radm_trgt1_dw_len!=1)))
                request_kind<=DROP;
            if(kind==READ && (seen || radm_trgt1_dv)) request_kind<=UNSUPPORTED;
            if(radm_trgt1_eot) begin
                if(packet_bad || kind==DROP ||
                   (kind==WRITE && (!radm_trgt1_dv || odd_payload ||
                    (taking_header && radm_trgt1_dw_len!=1)))) state<=IDLE;
                else state<=HEADER;
            end
        end else if(state==HEADER && m_axis_cq_tready)
            state<=request_kind==WRITE ? PAYLOAD : WAIT_REPLY;
        else if((state==PAYLOAD && m_axis_cq_tready) || (state==WAIT_REPLY && i_reply_done))
            state<=IDLE;
    end
endmodule
