`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"

// Reserve an idle metadata owner, then bind it on the actual ring START edge.
module jpeg_record_metadata_gate #(
    parameter integer RECORD_EXTENSION_WIDTH=1024,
    // The ordered egress owns s_extension until this store is quiescent.
    parameter integer BORROW_PENDING_EXTENSION=0,
    parameter integer STAGING_EXTENSION_ENABLE=0,
    parameter integer BORROW_HEADER=0,
    parameter integer STREAM_READ=0,
    parameter integer SHARED_MASK_METADATA=0
) (
    input wire i_clk,i_rst_n,
    input wire s_start_valid,
    output wire o_start_ready,
    input wire [31:0] s_start_writer_tag,s_start_sequence,s_start_session,s_start_epoch,
    input wire s_start_camera,
    input wire i_ring_start_ready,
    output wire o_ring_start_valid,
    output wire o_start_reserved,
    input wire [RECORD_EXTENSION_WIDTH-1:0] s_extension,
    input wire s_extension_valid,
    output wire o_extension_ready,
    input wire s_extension_shape_valid,
    output wire o_extension_read_enable,
    output wire [8:0] o_extension_read_index,
    input wire [39:0] i_extension_read_data,
    input wire s_write_result_valid,
    output wire o_write_result_ready,
    input wire [31:0] s_write_result_tag,s_write_result_sequence,s_write_result_session,s_write_result_epoch,
    input wire s_write_result_camera,
    input wire [15:0] s_write_result_slot,
    input wire [31:0] s_write_result_generation,
    input wire s_write_result_ok,
    input wire [7:0] s_write_result_error,
    input wire i_ready_valid,
    input wire [15:0] i_ready_slot,
    input wire [31:0] i_ready_generation,i_ready_session,i_ready_sequence,i_ready_epoch,
    input wire i_ready_camera,
    input wire [15:0] i_selected_version,
    output wire o_header_ready,
    output wire [RECORD_EXTENSION_WIDTH-1:0] o_header_extension,
    input wire i_header_fire,
    input wire i_header_release,
    output wire [127:0] o_header_stream_data,
    output wire o_header_stream_valid,o_header_stream_last,
    input wire i_header_stream_ready,
    input wire s_mask_req_valid,
    output wire o_mask_req_ready,
    input wire [15:0] s_mask_req_slot,
    input wire [31:0] s_mask_req_generation,s_mask_req_session,s_mask_req_sequence,s_mask_req_epoch,
    input wire s_mask_req_camera,
    output wire o_mask_rsp_valid,o_mask_rsp_ok,
    input wire i_mask_rsp_ready,
    output wire [7:0] o_mask_rsp_error,
    output wire [15:0] o_mask_rsp_slot,
    output wire [31:0] o_mask_rsp_generation,o_mask_rsp_session,o_mask_rsp_sequence,o_mask_rsp_epoch,
    output wire o_mask_rsp_camera,o_mask_rsp_qualified,
    output wire [23:0] o_mask_rsp_pixels,
    output wire [2:0] o_mask_rsp_source_type,
    output wire o_quiescent,
    output wire o_fault,
    output wire [31:0] o_stale_write_count,o_bad_extension_count
);
    generate if(RECORD_EXTENSION_WIDTH!=1024 && RECORD_EXTENSION_WIDTH!=3072 && RECORD_EXTENSION_WIDTH!=16384) begin : invalid_record_width
        RECORD_EXTENSION_REQUIRES_1024_3072_OR_16384 u_invalid_record_width();
    end endgenerate
    generate if(SHARED_MASK_METADATA!=0 && (STREAM_READ==0 || RECORD_EXTENSION_WIDTH!=3072))begin : invalid_shared_profile
        SHARED_MASK_METADATA_REQUIRES_STREAM_3072 u_invalid_shared_profile();
    end endgenerate
    generate if(STREAM_READ!=0 && BORROW_HEADER==0)begin : invalid_stream_lifetime
        STREAM_READ_REQUIRES_BORROW_HEADER u_invalid_stream_lifetime();
    end endgenerate
    `include "pcie_record_v3_validate.vh"
    wire selected_extended=i_selected_version==`PCIE_RECORD_V2_VERSION ||
        (RECORD_EXTENSION_WIDTH==3072 && i_selected_version==`PCIE_RECORD_V3_VERSION) ||
        (RECORD_EXTENSION_WIDTH==16384 && i_selected_version==`PCIE_RECORD_V4_VERSION);
    localparam [2:0] QUERY_IDLE=0,QUERY_REQUEST=1,QUERY_RESPONSE=2,QUERY_HEADER_HELD=3,QUERY_PROBE=4;
    reg [2:0] query_state,query_next;
    reg reserved,input_fault;
    reg [144:0] query_tuple;
    reg [15:0] query_version;
    wire [144:0] live_tuple={i_ready_slot,i_ready_generation,i_ready_session,i_ready_sequence,i_ready_epoch,i_ready_camera};
    // Freeze the existing query tuple before probing the asynchronous catalog.
    // Its address no longer selects a live/held 145-bit mux on the response path.
    wire [144:0] probe_tuple=query_tuple;
    wire store_begin_ready,store_write_quiet,store_read_quiet,store_fault;
    wire store_req_ready,store_available,store_rsp_valid,store_rsp_ok,store_rsp_camera;
    wire [7:0] store_rsp_error,store_write_error;
    wire [15:0] store_rsp_slot;
    wire [31:0] store_rsp_generation,store_rsp_session,store_rsp_sequence,store_rsp_epoch;
    wire [RECORD_EXTENSION_WIDTH-1:0] store_rsp_extension;
    wire [2047:0] sparse_response=store_rsp_extension >> 1024;
    wire [144:0] response_tuple;
    assign {store_rsp_slot,store_rsp_generation,store_rsp_session,store_rsp_sequence,store_rsp_epoch,store_rsp_camera}=response_tuple;
    wire response_tuple_matches=response_tuple==query_tuple;
    wire ready_tuple_matches=i_ready_valid && live_tuple==query_tuple;
    wire store_rsp_shape_valid;
    wire arb_quiet,arb_probe_idle,arb_fault;
    wire ram_req_valid,ram_req_ready,ram_req_mask,ram_rsp_valid,ram_rsp_ready,ram_rsp_ok,ram_rsp_shape_valid;
    wire ram_rsp_mask_qualified,ram_stream_start,ram_stream_valid,ram_stream_last,ram_stream_ready;
    wire [144:0] ram_req_tuple,ram_rsp_tuple,mask_response_tuple;
    wire [15:0] ram_req_version;
    wire [7:0] ram_rsp_error;
    wire [23:0] ram_rsp_pixels;
    wire [2:0] ram_rsp_source_type;
    wire [127:0] ram_stream_data;
    wire legacy_response_shape_valid=store_rsp_ok && store_rsp_error==0 &&
        store_rsp_extension[31:0]==`PCIE_RECORD_V2_EXTENSION_MAGIC &&
        store_rsp_extension[47:32]==`PCIE_RECORD_V2_SCHEMA_VERSION &&
        store_rsp_extension[48+`PCIE_RECORD_V2_FLAG_SOURCE_IDENTITY] && store_rsp_extension[63:60]==0 &&
        store_rsp_extension[95:64]==store_rsp_session && store_rsp_extension[127:96]==store_rsp_epoch &&
        store_rsp_extension[159:128]==store_rsp_sequence && store_rsp_extension[167:160]=={7'd0,store_rsp_camera} &&
        store_rsp_extension[175:168]<=`PCIE_RECORD_V2_SOURCE_PHYSICAL &&
        (store_rsp_extension[183:176]==`PCIE_RECORD_V2_FORMAT_RAW10 || store_rsp_extension[183:176]==`PCIE_RECORD_V2_FORMAT_RAW14) &&
        store_rsp_extension[191:184]<=`PCIE_RECORD_V2_ROLE_SHORT &&
        store_rsp_extension[223:192]==store_rsp_session && store_rsp_extension[255:224]==store_rsp_generation &&
        store_rsp_extension[959:947]==0 && store_rsp_extension[1023:960]==0 &&
        (i_selected_version!=`PCIE_RECORD_V3_VERSION || sparse_v3_valid(sparse_response));
    wire response_shape_valid=STREAM_READ!=0 ?
        (store_rsp_ok && store_rsp_error==0 && store_rsp_shape_valid) : legacy_response_shape_valid;
    wire arm_start=i_rst_n && !o_fault && !reserved && query_state==QUERY_IDLE &&
        !store_rsp_valid && arb_quiet && s_start_valid && store_begin_ready && i_ring_start_ready;
    // ARM has actual ring readiness. An unarmed full-ring START lets old READY retire.
    wire launch_query=i_rst_n && !o_fault && !reserved && query_state==QUERY_IDLE &&
        !arm_start && selected_extended && i_ready_valid &&
        arb_probe_idle && store_req_ready;
    wire ring_start_fire=o_ring_start_valid && i_ring_start_ready;
    wire store_req_valid=i_rst_n && query_state==QUERY_REQUEST;
    // CLAIM transfers slot ownership, but a borrowing formatter still reads
    // the same extension until its actual final header beat leaves the buffer.
    wire store_rsp_ready=BORROW_HEADER!=0 ?
        (query_state==QUERY_HEADER_HELD && i_header_release) :
        (i_header_fire && o_header_ready && selected_extended);
    assign o_start_reserved=i_rst_n && reserved;
    // Once presented, START is held even if pause/control traffic lowers READY.
    assign o_ring_start_valid=i_rst_n && reserved;
    assign o_start_ready=i_rst_n && reserved && i_ring_start_ready;
    wire bad_extension_seen;
    assign o_fault=input_fault || store_fault || arb_fault || bad_extension_seen;
    assign o_header_extension=store_rsp_extension;
    assign o_header_ready=i_selected_version==`PCIE_PROTOCOL_VERSION ? 1'b1 :
        (i_rst_n && !o_fault && query_state==QUERY_RESPONSE && store_rsp_valid &&
         response_tuple_matches && response_shape_valid && ready_tuple_matches);
    assign o_quiescent=i_rst_n && !o_fault && !reserved && query_state==QUERY_IDLE &&
        arb_quiet && store_write_quiet && store_read_quiet && !store_rsp_valid && !s_start_valid &&
        !s_extension_valid && !s_write_result_valid && !i_ready_valid && !i_header_fire;
    assign {o_mask_rsp_slot,o_mask_rsp_generation,o_mask_rsp_session,o_mask_rsp_sequence,o_mask_rsp_epoch,o_mask_rsp_camera}=mask_response_tuple;

    generate if(SHARED_MASK_METADATA!=0)begin : g_shared_read
        jpeg_metadata_read_arbiter u_read_arbiter (
            .i_clk(i_clk),.i_rst_n(i_rst_n),.i_start_block(reserved || arm_start),
            .s_jpeg_req_valid(store_req_valid),.s_jpeg_req_ready(store_req_ready),
            .s_jpeg_req_tuple(query_tuple),.s_jpeg_probe_tuple(probe_tuple),.s_jpeg_req_version(query_version),
            .m_jpeg_rsp_valid(store_rsp_valid),.m_jpeg_rsp_ok(store_rsp_ok),.m_jpeg_rsp_shape_valid(store_rsp_shape_valid),
            .m_jpeg_rsp_ready(store_rsp_ready),.m_jpeg_rsp_tuple(response_tuple),.m_jpeg_rsp_error(store_rsp_error),
            .s_jpeg_stream_start(i_header_fire && o_header_ready && selected_extended),
            .m_jpeg_stream_data(o_header_stream_data),.m_jpeg_stream_valid(o_header_stream_valid),
            .m_jpeg_stream_last(o_header_stream_last),.m_jpeg_stream_ready(i_header_stream_ready),
            .s_mask_req_valid(s_mask_req_valid),.s_mask_req_ready(o_mask_req_ready),
            .s_mask_req_tuple({s_mask_req_slot,s_mask_req_generation,s_mask_req_session,s_mask_req_sequence,s_mask_req_epoch,s_mask_req_camera}),
            .m_mask_rsp_valid(o_mask_rsp_valid),.m_mask_rsp_ok(o_mask_rsp_ok),.m_mask_rsp_qualified(o_mask_rsp_qualified),
            .m_mask_rsp_ready(i_mask_rsp_ready),.m_mask_rsp_tuple(mask_response_tuple),.m_mask_rsp_error(o_mask_rsp_error),
            .m_mask_rsp_pixels(o_mask_rsp_pixels),.m_mask_rsp_source_type(o_mask_rsp_source_type),
            .m_store_req_valid(ram_req_valid),.m_store_req_ready(ram_req_ready),.m_store_req_tuple(ram_req_tuple),
            .m_store_req_version(ram_req_version),.m_store_req_mask(ram_req_mask),
            .s_store_rsp_valid(ram_rsp_valid),.s_store_rsp_ok(ram_rsp_ok),.s_store_rsp_shape_valid(ram_rsp_shape_valid),
            .s_store_rsp_ready(ram_rsp_ready),.s_store_rsp_tuple(ram_rsp_tuple),.s_store_rsp_error(ram_rsp_error),
            .s_store_rsp_mask_qualified(ram_rsp_mask_qualified),.s_store_rsp_pixels(ram_rsp_pixels),
            .s_store_rsp_source_type(ram_rsp_source_type),.m_store_stream_start(ram_stream_start),
            .s_store_stream_data(ram_stream_data),.s_store_stream_valid(ram_stream_valid),
            .s_store_stream_last(ram_stream_last),.s_store_stream_ready(ram_stream_ready),
            .i_store_read_quiescent(store_read_quiet),.o_jpeg_probe_idle(arb_probe_idle),
            .o_quiescent(arb_quiet),.o_protocol_fault(arb_fault));
    end else begin : g_jpeg_read_only
        assign arb_quiet=1'b1;assign arb_probe_idle=1'b1;assign arb_fault=1'b0;
        assign ram_req_valid=store_req_valid;assign store_req_ready=ram_req_ready;
        assign ram_req_tuple=probe_tuple;assign ram_req_version=query_version;assign ram_req_mask=1'b0;
        assign store_rsp_valid=ram_rsp_valid;assign ram_rsp_ready=store_rsp_ready;
        assign store_rsp_ok=ram_rsp_ok;assign store_rsp_error=ram_rsp_error;
        assign response_tuple=ram_rsp_tuple;assign store_rsp_shape_valid=ram_rsp_shape_valid;
        assign ram_stream_start=i_header_fire && o_header_ready && selected_extended;
        assign o_header_stream_data=ram_stream_data;assign o_header_stream_valid=ram_stream_valid;
        assign o_header_stream_last=ram_stream_last;assign ram_stream_ready=i_header_stream_ready;
        assign o_mask_req_ready=1'b0;assign o_mask_rsp_valid=1'b0;assign o_mask_rsp_ok=1'b0;
        assign o_mask_rsp_error=8'd0;assign mask_response_tuple=145'd0;assign o_mask_rsp_qualified=1'b0;
        assign o_mask_rsp_pixels=24'd0;assign o_mask_rsp_source_type=3'd0;
    end endgenerate

    jpeg_record_metadata_store #(.RECORD_EXTENSION_WIDTH(RECORD_EXTENSION_WIDTH),
        .BORROW_PENDING_EXTENSION(BORROW_PENDING_EXTENSION),.STAGING_EXTENSION_ENABLE(STAGING_EXTENSION_ENABLE),
        .BORROW_READ_IDENTITY(BORROW_HEADER!=0 && STREAM_READ!=0 && SHARED_MASK_METADATA==0),
        .STREAM_READ(STREAM_READ),.MASK_READ(SHARED_MASK_METADATA)) u_store (
        .i_clk(i_clk),.i_rst_n(i_rst_n),.s_begin_valid(ring_start_fire),.s_begin_ready(store_begin_ready),
        .s_begin_writer_tag(s_start_writer_tag),.s_begin_sequence(s_start_sequence),
        .s_begin_session(s_start_session),.s_begin_epoch(s_start_epoch),.s_begin_camera(s_start_camera),
        .s_extension(s_extension),.s_extension_valid(s_extension_valid),.s_extension_ready(o_extension_ready),
        .s_extension_shape_valid(s_extension_shape_valid),.o_extension_read_enable(o_extension_read_enable),
        .o_extension_read_index(o_extension_read_index),.i_extension_read_data(i_extension_read_data),
        .s_write_result_valid(s_write_result_valid),.s_write_result_ready(o_write_result_ready),
        .s_write_result_tag(s_write_result_tag),.s_write_result_sequence(s_write_result_sequence),
        .s_write_result_session(s_write_result_session),.s_write_result_epoch(s_write_result_epoch),
        .s_write_result_camera(s_write_result_camera),.s_write_result_slot(s_write_result_slot),
        .s_write_result_generation(s_write_result_generation),.s_write_result_ok(s_write_result_ok),
        .s_write_result_error(s_write_result_error),.o_write_quiescent(store_write_quiet),
        .o_read_quiescent(store_read_quiet),.o_protocol_fault(store_fault),
        .o_stale_write_count(o_stale_write_count),.o_bad_extension_count(o_bad_extension_count),.o_bad_extension_seen(bad_extension_seen),.o_write_error(store_write_error),
        .s_read_req_valid(ram_req_valid),.s_read_req_ready(ram_req_ready),
        .s_read_req_slot(ram_req_tuple[144:129]),.s_read_req_generation(ram_req_tuple[128:97]),
        .s_read_req_session(ram_req_tuple[96:65]),.s_read_req_sequence(ram_req_tuple[64:33]),
        .s_read_req_epoch(ram_req_tuple[32:1]),.s_read_req_camera(ram_req_tuple[0]),.o_metadata_available(store_available),
        .m_read_rsp_valid(ram_rsp_valid),.m_read_rsp_ready(ram_rsp_ready),
        .m_read_rsp_ok(ram_rsp_ok),.m_read_rsp_error(ram_rsp_error),.m_read_rsp_slot(ram_rsp_tuple[144:129]),
        .m_read_rsp_generation(ram_rsp_tuple[128:97]),.m_read_rsp_session(ram_rsp_tuple[96:65]),
        .m_read_rsp_sequence(ram_rsp_tuple[64:33]),.m_read_rsp_epoch(ram_rsp_tuple[32:1]),.m_read_rsp_camera(ram_rsp_tuple[0]),
        .m_read_rsp_extension(store_rsp_extension),.s_read_req_version(ram_req_version),
        .m_read_rsp_shape_valid(ram_rsp_shape_valid),
        .s_read_stream_start(ram_stream_start),
        .m_read_stream_data(ram_stream_data),.m_read_stream_valid(ram_stream_valid),
        .m_read_stream_last(ram_stream_last),.m_read_stream_ready(ram_stream_ready),
        .s_read_req_mask(ram_req_mask),.m_read_rsp_mask_qualified(ram_rsp_mask_qualified),
        .m_read_rsp_mask_pixels(ram_rsp_pixels),.m_read_rsp_source_type(ram_rsp_source_type)
    );
    always @(*)begin
        query_next=query_state;
        case(query_state)
            QUERY_IDLE:if(launch_query)query_next=QUERY_PROBE;
            QUERY_PROBE:begin
                // No request has transferred yet, so an abandoned READY probe
                // owns no response and can return to IDLE without a fake fault.
                if(!selected_extended || !ready_tuple_matches || query_version!=i_selected_version)
                    query_next=QUERY_IDLE;
                else if(store_available && store_req_ready)query_next=QUERY_REQUEST;
            end
            QUERY_REQUEST:if(store_req_valid && store_req_ready)query_next=QUERY_RESPONSE;
            QUERY_RESPONSE:if(i_header_fire && o_header_ready && selected_extended)
                query_next=BORROW_HEADER!=0 ? QUERY_HEADER_HELD : QUERY_IDLE;
            QUERY_HEADER_HELD:if(BORROW_HEADER!=0 && store_rsp_valid && store_rsp_ready)
                query_next=QUERY_IDLE;
            default:query_next=QUERY_RESPONSE;
        endcase
    end
    always @(posedge i_clk)begin
        if(!i_rst_n)begin query_state<=QUERY_IDLE;reserved<=0;query_tuple<=0;query_version<=0;input_fault<=0;end
        else begin
            query_state<=query_next;
            if(arm_start)reserved<=1;
            if(ring_start_fire)reserved<=0;
            if(launch_query)begin query_tuple<=live_tuple;query_version<=i_selected_version;end
            if((reserved && (!s_start_valid || !store_begin_ready)) ||
               (query_state!=QUERY_IDLE && query_state!=QUERY_PROBE && query_version!=i_selected_version) ||
               ((query_state==QUERY_REQUEST || query_state==QUERY_RESPONSE) &&
                (!selected_extended || !ready_tuple_matches)) ||
               (query_state==QUERY_HEADER_HELD && BORROW_HEADER!=0 &&
                (!selected_extended || !store_rsp_valid || !response_tuple_matches || !response_shape_valid)) ||
               (query_state==QUERY_RESPONSE && store_rsp_valid && (!response_tuple_matches || !response_shape_valid)) ||
               (i_header_fire && selected_extended && !o_header_ready) ||
               (i_selected_version!=`PCIE_PROTOCOL_VERSION && !selected_extended) ||
               (query_state==QUERY_HEADER_HELD && BORROW_HEADER==0))input_fault<=1;
        end
    end
endmodule
