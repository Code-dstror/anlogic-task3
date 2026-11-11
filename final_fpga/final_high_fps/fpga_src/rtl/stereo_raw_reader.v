`timescale 1ns/1ps
// One bounded RAW10 frame read; the sole shared replay FIFO receives DATA/FENCE.
// Cancellation drains an accepted AXI burst and any already offered token first.
module stereo_raw_reader #(
    parameter integer WIDTH=1920,HEIGHT=1080,
    parameter integer EXTERNAL_DECODER=0,
    parameter [3:0] AXI_ID=4'd1,
    parameter integer VERIFY_DECODE_ACTIVE=0,
    parameter integer UHD_WIDTH=0,UHD_HEIGHT=0
)(
    input wire clk,rst_n,
    input wire i_start_valid,output wire o_start_ready,
    input wire [27:0] i_base,input wire [63:0] i_job_id,input wire i_cancel,
    output reg [146:0] m_data,output reg m_valid,input wire m_ready,
    output wire o_done_valid,o_done_ok,input wire i_done_ready,
    output wire o_bus_quiet,output reg o_fault,
    output wire o_decode_start_valid,input wire i_decode_start_ready,
    output wire o_decode_release,o_decode_cancel,o_decode_run,
    output wire [127:0] o_decode_data,output wire [15:0] o_decode_keep,
    output wire o_decode_valid,o_decode_last,input wire i_decode_ready,
    input wire [39:0] i_decode_raw,input wire i_decode_raw_valid,
    output wire o_decode_raw_ready,input wire i_decode_sof,i_decode_eol,
    input wire i_decode_done,i_decode_aborted,i_decode_quiet,i_decode_active,
    output wire [3:0] m_axi_arid,output wire [27:0] m_axi_araddr,
    output wire [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [127:0] m_axi_rdata,
    input wire [1:0] m_axi_rresp,input wire m_axi_rlast,m_axi_rvalid,
    output wire m_axi_rready,
    input wire i_start_uhd
);
    localparam integer FRAME_GROUPS=WIDTH/4*HEIGHT, UHD_FRAME_GROUPS=UHD_WIDTH/4*UHD_HEIGHT;
    localparam integer FRAME_BYTES=FRAME_GROUPS*5, UHD_FRAME_BYTES=UHD_FRAME_GROUPS*5;
    localparam UHD_ENABLED=UHD_WIDTH!=0||UHD_HEIGHT!=0;
    localparam integer CHECK_ACTIVE=EXTERNAL_DECODER!=0&&VERIFY_DECODE_ACTIVE!=0;
    localparam [2:0] IDLE=0,START=1,PLAN=2,ADDRESS=3,READ=4,DRAIN=5,FENCE=6,DONE=7;
    reg [2:0] state;
    reg [27:0] address;
    reg [31:0] remaining,groups;
    reg [4:0] beats,beats_left;
    reg [63:0] job;
    reg failed,decoder_finished,start_settled,frame_uhd;
    wire start_uhd=UHD_ENABLED&&i_start_uhd;
    reg [7:0] error_code;
    wire token_fire=m_valid&&m_ready;
    wire token_room=!m_valid||m_ready;
    wire [4:0] remaining_beats=remaining>=256?5'd16:{1'b0,remaining[7:4]}+(|remaining[3:0]);
    wire [4:0] boundary_beats=address[11:8]==15?5'd16-{1'b0,address[7:4]}:5'd16;
    wire [4:0] next_beats=remaining_beats<boundary_beats?remaining_beats:boundary_beats;
    wire [4:0] actual_bytes=remaining>=16?5'd16:remaining[4:0];
    wire [15:0] expected_keep=actual_bytes==16?16'hffff:(16'hffff>>(16-actual_bytes));
    wire shape_ok=m_axi_rid==AXI_ID&&m_axi_rlast==(beats_left==1);
    wire response_ok=shape_ok&&m_axi_rresp==0;
    wire [39:0] raw;
    wire raw_valid,raw_ready,raw_sof,raw_eol,raw_abort,raw_done,decoder_ready;
    wire decoder_run=state!=IDLE&&state!=DRAIN&&state!=FENCE&&state!=DONE;
    wire decoder_complete=remaining==0&&(decoder_finished||raw_done);
    wire decoder_expected=state==PLAN||state==ADDRESS||state==READ;
    wire context_lost=CHECK_ACTIVE!=0&&decoder_expected&&!i_decode_active&&!decoder_complete;
    wire consume_data=state==READ&&!failed&&!i_cancel&&!context_lost&&response_ok;
    wire raw_fire=raw_valid&&raw_ready;
    wire raw_last=groups==(frame_uhd?UHD_FRAME_GROUPS-1:FRAME_GROUPS-1);
    wire [55:0] extended_raw={4'd0,raw[39:30],4'd0,raw[29:20],4'd0,raw[19:10],4'd0,raw[9:0]};
    wire decoder_quiet;
    assign o_decode_start_valid=i_start_valid && state==IDLE && !m_valid && !o_fault;
    assign o_decode_release=o_done_valid && i_done_ready;
    assign o_decode_cancel=i_cancel;assign o_decode_run=decoder_run;
    assign o_decode_data=m_axi_rdata;assign o_decode_keep=expected_keep;
    assign o_decode_valid=m_axi_rvalid && consume_data;assign o_decode_last=remaining<=16;
    assign o_decode_raw_ready=raw_ready;
    generate if(EXTERNAL_DECODER!=0)begin:g_external_decoder
        assign decoder_ready=i_decode_ready;
        assign raw=i_decode_raw;assign raw_valid=i_decode_raw_valid;
        assign raw_sof=i_decode_sof;assign raw_eol=i_decode_eol;
        assign raw_done=i_decode_done;assign raw_abort=i_decode_aborted;
        assign decoder_quiet=i_decode_quiet;
    end else begin:g_local_decoder
    assign decoder_quiet=1'b1;
    raw10_frame_replay u_decoder(
        .i_clk(clk),.i_rst_n(rst_n&&decoder_run),.i_start(state==START),
        .i_width(frame_uhd?UHD_WIDTH[15:0]:WIDTH[15:0]),.i_height(frame_uhd?UHD_HEIGHT[15:0]:HEIGHT[15:0]),
        .i_axis_tdata(m_axi_rdata),.i_axis_tkeep(expected_keep),
        .i_axis_tvalid(m_axi_rvalid&&consume_data),.o_axis_tready(decoder_ready),
        .i_axis_tlast(remaining<=16),.o_data(raw),.o_valid(raw_valid),.i_ready(raw_ready),
        .o_sof(raw_sof),.o_eol(raw_eol),.o_abort(raw_abort),.o_done(raw_done));
    end endgenerate
    assign raw_ready=token_room&&!failed&&!i_cancel&&!context_lost&&decoder_run;
    assign o_start_ready=state==IDLE&&!m_valid&&!o_fault&&
        (EXTERNAL_DECODER==0 || i_decode_start_ready);
    assign o_done_valid=state==DONE&&!m_valid;
    assign o_done_ok=!failed&&!o_fault;
    assign o_bus_quiet=state!=ADDRESS&&state!=READ&&!m_valid;
    assign m_axi_arid=AXI_ID;assign m_axi_araddr=address;
    assign m_axi_arlen={3'd0,beats}-1'b1;assign m_axi_arsize=4;assign m_axi_arburst=1;
    assign m_axi_arvalid=state==ADDRESS;
    assign m_axi_rready=state==READ&&((failed||i_cancel||!response_ok)?1'b1:decoder_ready);
    wire read_fire=m_axi_rvalid&&m_axi_rready;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;address<=0;remaining<=0;beats<=0;beats_left<=0;job<=0;
            groups<=0;failed<=0;error_code<=0;decoder_finished<=0;start_settled<=0;frame_uhd<=0;
            o_fault<=0;m_valid<=0;m_data<=0;
        end else begin
            if(token_fire)m_valid<=0;
            if(raw_done)decoder_finished<=1;
            if(context_lost&&!failed&&!i_cancel)begin failed<=1;if(error_code==0)error_code<=6;end
            if(raw_abort)begin failed<=1;if(error_code==0)error_code<=3;end
            if(i_cancel&&state!=IDLE&&state!=DONE&&state!=FENCE)begin failed<=1;if(error_code==0)error_code<=1;end
            if(m_axi_rvalid&&state!=READ)begin o_fault<=1;failed<=1;if(error_code==0)error_code<=4;end
            if(raw_fire)begin
                m_data<={2'd0,9'd0,1'b0,groups,raw_last,raw_eol,raw_sof,4'hf,40'd0,extended_raw};
                m_valid<=1;groups<=groups+1'b1;
            end
            case(state)
                IDLE:if(i_start_valid&&o_start_ready)begin
                    address<=i_base;job<=i_job_id;remaining<=start_uhd?UHD_FRAME_BYTES:FRAME_BYTES;groups<=0;
                    frame_uhd<=start_uhd;
                    failed<=i_cancel||i_job_id==0||i_base[3:0]!=0;
                    error_code<=i_cancel?1:(i_job_id==0||i_base[3:0]!=0)?5:0;
                    decoder_finished<=0;start_settled<=0;state<=START;
                end
                START:begin
                    if(CHECK_ACTIVE==0)state<=PLAN;
                    else if(failed||i_cancel)state<=DRAIN;
                    // The shared core samples its START after the grant edge.
                    else if(!start_settled)start_settled<=1;
                    else if(i_decode_active)state<=PLAN;
                    else begin failed<=1;error_code<=6;state<=DRAIN;end
                end
                PLAN:begin
                    if(failed||i_cancel||o_fault||context_lost)state<=DRAIN;
                    else if(remaining==0)begin
                        if(decoder_complete)state<=DRAIN;
                    end else begin beats<=next_beats;beats_left<=next_beats;state<=ADDRESS;end
                end
                // AR is a promise and remains presented through cancellation.
                ADDRESS:if(m_axi_arready)state<=READ;
                READ:if(read_fire)begin
                    if(!response_ok)begin failed<=1;if(error_code==0)error_code<=2;end
                    if(!shape_ok)o_fault<=1;
                    if(remaining>=actual_bytes)remaining<=remaining-actual_bytes;
                    if(beats_left!=0)beats_left<=beats_left-1'b1;
                    // A premature RLAST cannot discharge the promised burst.
                    if(m_axi_rlast&&beats_left==1)begin
                        address<=address+{19'd0,beats,4'd0};
                        state<=(failed||i_cancel||!response_ok||context_lost)?DRAIN:PLAN;
                    end
                end
                DRAIN:if(!m_valid&&decoder_quiet)state<=FENCE;
                FENCE:if(!m_valid)begin
                    m_data<={2'd1,40'd0,error_code,(!failed&&!o_fault),job,groups};m_valid<=1;
                end else if(token_fire)state<=DONE;
                DONE:if(i_done_ready&&o_done_valid)state<=IDLE;
                default:begin o_fault<=1;failed<=1;end
            endcase
        end
    end
    generate if(WIDTH<4||WIDTH%4!=0||HEIGHT<1||FRAME_BYTES>16777216||
        (UHD_ENABLED&&(UHD_WIDTH<4||UHD_WIDTH%4!=0||UHD_WIDTH>65532||UHD_HEIGHT<1||UHD_HEIGHT>65535||
         (64'd5*(UHD_WIDTH/4)*UHD_HEIGHT)>64'd16777216)))begin:g_bad
        STEREO_READER_REQUIRES_BOUNDED_RAW10_FRAME bad_profile();
    end endgenerate
endmodule
