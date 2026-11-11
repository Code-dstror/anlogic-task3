`timescale 1ns/1ps
// Client0 JPEG / client1 mask. A complete AW..W..B transaction owns the port.
module dol2_axi_write_arbiter #(
    parameter integer SEPARATE_DATA_RESET=0
) (
    input wire i_clk,i_axi_rst_n,
    input wire [7:0] s_awid,
    input wire [55:0] s_awaddr,
    input wire [15:0] s_awlen,
    input wire [5:0] s_awsize,
    input wire [3:0] s_awburst,
    input wire [1:0] s_awvalid,
    output wire [1:0] s_awready,
    input wire [255:0] s_wdata,
    input wire [31:0] s_wstrb,
    input wire [1:0] s_wlast,s_wvalid,
    output wire [1:0] s_wready,
    output wire [7:0] s_bid,
    output wire [3:0] s_bresp,
    output wire [1:0] s_bvalid,
    input wire [1:0] s_bready,
    output wire [3:0] m_awid,
    output wire [27:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire [1:0] m_awburst,
    output wire m_awvalid,
    input wire m_awready,
    output wire [127:0] m_wdata,
    output wire [15:0] m_wstrb,
    output wire m_wlast,m_wvalid,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire o_quiescent,
    output reg o_protocol_fault,
    input wire i_data_reset_n
);
    localparam [1:0] IDLE=0,AW=1,W=2,B=3;
    reg [1:0] state;
    reg owner,next_owner;
    reg [44:0] address;
    reg [8:0] beats_left;
    // Both reset inputs assert asynchronously. The optional data qualifier
    // releases on the preceding rising edge, before the state ASR releases.
    wire data_reset_n=SEPARATE_DATA_RESET!=0 ? i_data_reset_n : i_axi_rst_n;
    wire select_client=s_awvalid==2'b11 ? next_owner:s_awvalid[1];
    assign {m_awid,m_awaddr,m_awlen,m_awsize,m_awburst}=address;
    assign m_awvalid=data_reset_n&&state==AW;
    assign s_awready=state==AW&&data_reset_n  ?  (owner ? {m_awready,1'b0}:{1'b0,m_awready}):0;
    assign m_wdata=s_wdata[owner*128+:128];
    assign m_wstrb=s_wstrb[owner*16+:16];
    assign m_wlast=beats_left==1;
    assign m_wvalid=data_reset_n&&state==W&&s_wvalid[owner];
    assign s_wready=state==W&&data_reset_n  ?  (owner ? {m_wready,1'b0}:{1'b0,m_wready}):0;
    assign s_bid=state==B  ?  (owner ? {m_bid,4'd0}:{4'd0,m_bid}):0;
    assign s_bresp=state==B  ?  (owner ? {m_bresp,2'd0}:{2'd0,m_bresp}):0;
    assign s_bvalid=state==B&&data_reset_n  ?  (owner ? {m_bvalid,1'b0}:{1'b0,m_bvalid}):0;
    assign m_bready=data_reset_n&&state==B&&s_bready[owner];
    assign o_quiescent=data_reset_n&&state==IDLE&&s_awvalid==0&&s_wvalid==0&&!m_bvalid;
    always @(posedge i_clk or negedge i_axi_rst_n) begin
        if(!i_axi_rst_n)begin state<=IDLE;owner<=0;next_owner<=0;address<=0;beats_left<=0;o_protocol_fault<=0;end
        else begin
            if(m_bvalid && state!=B)o_protocol_fault<=1;
            case(state)
                IDLE:if(|s_awvalid)begin
                    owner<=select_client;
                    address<={s_awid[select_client*4+:4],s_awaddr[select_client*28+:28],
                        s_awlen[select_client*8+:8],s_awsize[select_client*3+:3],s_awburst[select_client*2+:2]};
                    state<=AW;
                end
                AW:begin
                    if(!s_awvalid[owner])o_protocol_fault<=1;
                    if(m_awready)begin beats_left<={1'b0,m_awlen}+1'b1;state<=W;end
                end
                W:if(m_wvalid&&m_wready)begin
                    if(s_wlast[owner]!=(beats_left==1))o_protocol_fault<=1;
                    if(beats_left==1)state<=B;else beats_left<=beats_left-1'b1;
                end
                B:if(m_bvalid&&m_bready)begin next_owner<=!owner;state<=IDLE;end
                default:begin state<=IDLE;o_protocol_fault<=1;end
            endcase
        end
    end
endmodule
