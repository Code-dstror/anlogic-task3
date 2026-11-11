`timescale 1ns / 1ps

// Official AXI Matrix port adapter with independent complete-burst R storage.
module ddr_axi_three_client_arbiter #(parameter integer TIMEOUT_CYCLES = 4096) (
    input wire clk,
    input wire rst_n,
    output reg fault,
    input wire [3:0] s0_awid,
    input wire [27:0] s0_awaddr,
    input wire [7:0] s0_awlen,
    input wire [2:0] s0_awsize,
    input wire [1:0] s0_awburst,
    input wire s0_awvalid,
    output wire s0_awready,
    input wire [127:0] s0_wdata,
    input wire [15:0] s0_wstrb,
    input wire s0_wlast,
    input wire s0_wvalid,
    output wire s0_wready,
    output wire [3:0] s0_bid,
    output wire [1:0] s0_bresp,
    output wire s0_bvalid,
    input wire s0_bready,
    input wire [3:0] s0_arid,
    input wire [27:0] s0_araddr,
    input wire [7:0] s0_arlen,
    input wire [2:0] s0_arsize,
    input wire [1:0] s0_arburst,
    input wire s0_arvalid,
    output wire s0_arready,
    output wire [3:0] s0_rid,
    output wire [127:0] s0_rdata,
    output wire [1:0] s0_rresp,
    output wire s0_rlast,
    output wire s0_rvalid,
    input wire s0_rready,
    input wire [3:0] s1_awid,
    input wire [27:0] s1_awaddr,
    input wire [7:0] s1_awlen,
    input wire [2:0] s1_awsize,
    input wire [1:0] s1_awburst,
    input wire s1_awvalid,
    output wire s1_awready,
    input wire [127:0] s1_wdata,
    input wire [15:0] s1_wstrb,
    input wire s1_wlast,
    input wire s1_wvalid,
    output wire s1_wready,
    output wire [3:0] s1_bid,
    output wire [1:0] s1_bresp,
    output wire s1_bvalid,
    input wire s1_bready,
    input wire [3:0] s1_arid,
    input wire [27:0] s1_araddr,
    input wire [7:0] s1_arlen,
    input wire [2:0] s1_arsize,
    input wire [1:0] s1_arburst,
    input wire s1_arvalid,
    output wire s1_arready,
    output wire [3:0] s1_rid,
    output wire [127:0] s1_rdata,
    output wire [1:0] s1_rresp,
    output wire s1_rlast,
    output wire s1_rvalid,
    input wire s1_rready,
    input wire [3:0] s2_awid,
    input wire [27:0] s2_awaddr,
    input wire [7:0] s2_awlen,
    input wire [2:0] s2_awsize,
    input wire [1:0] s2_awburst,
    input wire s2_awvalid,
    output wire s2_awready,
    input wire [127:0] s2_wdata,
    input wire [15:0] s2_wstrb,
    input wire s2_wlast,
    input wire s2_wvalid,
    output wire s2_wready,
    output wire [3:0] s2_bid,
    output wire [1:0] s2_bresp,
    output wire s2_bvalid,
    input wire s2_bready,
    input wire [3:0] s2_arid,
    input wire [27:0] s2_araddr,
    input wire [7:0] s2_arlen,
    input wire [2:0] s2_arsize,
    input wire [1:0] s2_arburst,
    input wire s2_arvalid,
    output wire s2_arready,
    output wire [3:0] s2_rid,
    output wire [127:0] s2_rdata,
    output wire [1:0] s2_rresp,
    output wire s2_rlast,
    output wire s2_rvalid,
    input wire s2_rready,
    output wire [3:0] m_awid,
    output wire [27:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire [1:0] m_awburst,
    output wire m_awvalid,
    input wire m_awready,
    output wire [127:0] m_wdata,
    output wire [15:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [3:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [3:0] m_arid,
    output wire [27:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire [2:0] m_arsize,
    output wire [1:0] m_arburst,
    output wire m_arvalid,
    input wire m_arready,
    input wire [3:0] m_rid,
    input wire [127:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready
);

    reg [2:0] reset_release;
    wire all_reset_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) reset_release<=0; else reset_release<={reset_release[1:0],1'b1};
    end
    wire matrix_reset_n=reset_release[2];
    function command_supported;
        input [27:0] address; input [7:0] length;
        input [2:0] size; input [1:0] burst;
        reg [12:0] page_end;
        begin
            page_end = {1'b0,address[11:0]} + ({5'd0,length}+13'd1)*13'd16;
            command_supported = address[3:0]==0 && length<16 && size==4 && burst==1 && page_end<=4096;
        end
    endfunction

    // Client0: two address metadata entries; payload storage remains official.
    reg [1:0] p0_writes, p0_reads, p0_awcount, p0_arcount;
    reg p0_awhead,p0_awtail,p0_arhead,p0_artail;
    reg [1:0] p0_awid0,p0_awid1,p0_arid0,p0_arid1;
    reg [27:0] p0_awaddr0,p0_awaddr1,p0_araddr0,p0_araddr1;
    reg [7:0] p0_awlen0,p0_awlen1,p0_arlen0,p0_arlen1;
    wire [1:0] p0_awid=p0_awhead?p0_awid1:p0_awid0, p0_arid=p0_arhead?p0_arid1:p0_arid0;
    wire [27:0] p0_awaddr=p0_awhead?p0_awaddr1:p0_awaddr0, p0_araddr=p0_arhead?p0_araddr1:p0_araddr0;
    wire [7:0] p0_awlen=p0_awhead?p0_awlen1:p0_awlen0, p0_arlen=p0_arhead?p0_arlen1:p0_arlen0;
    wire p0_awheld=(p0_awcount!=0), p0_arheld=(p0_arcount!=0);
    wire p0_awready,p0_arready,p0_rvalid,p0_rready,p0_wready;
    assign s0_wready=p0_wready && p0_writes!=0;
    wire [1:0] p0_rid,p0_rresp; wire [127:0] p0_rdata; wire p0_rlast;
    wire [146:0] p0_response; wire p0_fifo_ready,p0_source_done,p0_sink_done;
    reg [5:0] p0_count;
    wire p0_awgood=s0_awid[3:2]==0 && command_supported(s0_awaddr,s0_awlen,s0_awsize,s0_awburst);
    wire p0_argood=s0_arid[3:2]==0 && command_supported(s0_araddr,s0_arlen,s0_arsize,s0_arburst);
    assign s0_awready=all_reset_done && !fault && p0_writes<2 && p0_awcount<2 && p0_awgood;
    assign s0_arready=all_reset_done && !fault && p0_reads<2 && p0_arcount<2 && p0_argood;
    wire p0_awpush=s0_awvalid && s0_awready, p0_awpop=p0_awheld && p0_awready;
    wire p0_arpush=s0_arvalid && s0_arready, p0_arpop=p0_arheld && p0_arready;
    wire p0_bpop=s0_bvalid && s0_bready;
    wire p0_push=p0_rvalid && p0_rready, p0_pop=s0_rvalid && s0_rready;
    wire p0_rretire=p0_pop && s0_rlast;
    assign p0_rready=p0_fifo_ready && p0_count<32 && p0_reads!=0;
    assign s0_rid=p0_response[134:131]; assign s0_rresp=p0_response[130:129];
    assign s0_rlast=p0_response[128]; assign s0_rdata=p0_response[127:0];
    axis_frame_fifo_ip u_response_fifo0 (
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data({12'd0,2'd0,p0_rid,p0_rresp,p0_rlast,p0_rdata}),
        .i_source_valid(p0_rvalid && p0_count<32 && p0_reads!=0),.o_source_ready(p0_fifo_ready),
        .o_source_reset_done(p0_source_done),.i_sink_clk(clk),.i_sink_rst_n(rst_n),
        .o_sink_data(p0_response),.o_sink_valid(s0_rvalid),.i_sink_ready(s0_rready),.o_sink_reset_done(p0_sink_done));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p0_writes<=0;p0_reads<=0;p0_awcount<=0;p0_arcount<=0;p0_count<=0;
            p0_awhead<=0;p0_awtail<=0;p0_arhead<=0;p0_artail<=0;
            p0_awid0<=0;p0_awid1<=0;p0_arid0<=0;p0_arid1<=0;
            p0_awaddr0<=0;p0_awaddr1<=0;p0_araddr0<=0;p0_araddr1<=0;
            p0_awlen0<=0;p0_awlen1<=0;p0_arlen0<=0;p0_arlen1<=0;
        end else begin
            if (p0_awpush) begin
                p0_awtail<=!p0_awtail;
                if (p0_awtail) begin p0_awid1<=s0_awid[1:0];p0_awaddr1<=s0_awaddr;p0_awlen1<=s0_awlen;end
                else begin p0_awid0<=s0_awid[1:0];p0_awaddr0<=s0_awaddr;p0_awlen0<=s0_awlen;end
            end
            if (p0_awpop) p0_awhead<=!p0_awhead;
            if (p0_arpush) begin
                p0_artail<=!p0_artail;
                if (p0_artail) begin p0_arid1<=s0_arid[1:0];p0_araddr1<=s0_araddr;p0_arlen1<=s0_arlen;end
                else begin p0_arid0<=s0_arid[1:0];p0_araddr0<=s0_araddr;p0_arlen0<=s0_arlen;end
            end
            if (p0_arpop) p0_arhead<=!p0_arhead;
            case ({p0_awpush,p0_awpop})
                2'b10:p0_awcount<=p0_awcount+1'b1;
                2'b01:p0_awcount<=p0_awcount-1'b1;
                default:p0_awcount<=p0_awcount;
            endcase
            case ({p0_arpush,p0_arpop})
                2'b10:p0_arcount<=p0_arcount+1'b1;
                2'b01:p0_arcount<=p0_arcount-1'b1;
                default:p0_arcount<=p0_arcount;
            endcase
            case ({p0_awpush,p0_bpop})
                2'b10:p0_writes<=p0_writes+1'b1;
                2'b01:p0_writes<=p0_writes-1'b1;
                default:p0_writes<=p0_writes;
            endcase
            case ({p0_arpush,p0_rretire})
                2'b10:p0_reads<=p0_reads+1'b1;
                2'b01:p0_reads<=p0_reads-1'b1;
                default:p0_reads<=p0_reads;
            endcase
            case ({p0_push,p0_pop})
                2'b10:p0_count<=p0_count+1'b1;
                2'b01:p0_count<=p0_count-1'b1;
                default:p0_count<=p0_count;
            endcase
        end
    end
    // Client1: two address metadata entries; payload storage remains official.
    reg [1:0] p1_writes, p1_reads, p1_awcount, p1_arcount;
    reg p1_awhead,p1_awtail,p1_arhead,p1_artail;
    reg [1:0] p1_awid0,p1_awid1,p1_arid0,p1_arid1;
    reg [27:0] p1_awaddr0,p1_awaddr1,p1_araddr0,p1_araddr1;
    reg [7:0] p1_awlen0,p1_awlen1,p1_arlen0,p1_arlen1;
    wire [1:0] p1_awid=p1_awhead?p1_awid1:p1_awid0, p1_arid=p1_arhead?p1_arid1:p1_arid0;
    wire [27:0] p1_awaddr=p1_awhead?p1_awaddr1:p1_awaddr0, p1_araddr=p1_arhead?p1_araddr1:p1_araddr0;
    wire [7:0] p1_awlen=p1_awhead?p1_awlen1:p1_awlen0, p1_arlen=p1_arhead?p1_arlen1:p1_arlen0;
    wire p1_awheld=(p1_awcount!=0), p1_arheld=(p1_arcount!=0);
    wire p1_awready,p1_arready,p1_rvalid,p1_rready,p1_wready;
    assign s1_wready=p1_wready && p1_writes!=0;
    wire [1:0] p1_rid,p1_rresp; wire [127:0] p1_rdata; wire p1_rlast;
    wire [146:0] p1_response; wire p1_fifo_ready,p1_source_done,p1_sink_done;
    reg [5:0] p1_count;
    wire p1_awgood=s1_awid[3:2]==0 && command_supported(s1_awaddr,s1_awlen,s1_awsize,s1_awburst);
    wire p1_argood=s1_arid[3:2]==0 && command_supported(s1_araddr,s1_arlen,s1_arsize,s1_arburst);
    assign s1_awready=all_reset_done && !fault && p1_writes<2 && p1_awcount<2 && p1_awgood;
    assign s1_arready=all_reset_done && !fault && p1_reads<2 && p1_arcount<2 && p1_argood;
    wire p1_awpush=s1_awvalid && s1_awready, p1_awpop=p1_awheld && p1_awready;
    wire p1_arpush=s1_arvalid && s1_arready, p1_arpop=p1_arheld && p1_arready;
    wire p1_bpop=s1_bvalid && s1_bready;
    wire p1_push=p1_rvalid && p1_rready, p1_pop=s1_rvalid && s1_rready;
    wire p1_rretire=p1_pop && s1_rlast;
    assign p1_rready=p1_fifo_ready && p1_count<32 && p1_reads!=0;
    assign s1_rid=p1_response[134:131]; assign s1_rresp=p1_response[130:129];
    assign s1_rlast=p1_response[128]; assign s1_rdata=p1_response[127:0];
    axis_frame_fifo_ip u_response_fifo1 (
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data({12'd0,2'd0,p1_rid,p1_rresp,p1_rlast,p1_rdata}),
        .i_source_valid(p1_rvalid && p1_count<32 && p1_reads!=0),.o_source_ready(p1_fifo_ready),
        .o_source_reset_done(p1_source_done),.i_sink_clk(clk),.i_sink_rst_n(rst_n),
        .o_sink_data(p1_response),.o_sink_valid(s1_rvalid),.i_sink_ready(s1_rready),.o_sink_reset_done(p1_sink_done));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_writes<=0;p1_reads<=0;p1_awcount<=0;p1_arcount<=0;p1_count<=0;
            p1_awhead<=0;p1_awtail<=0;p1_arhead<=0;p1_artail<=0;
            p1_awid0<=0;p1_awid1<=0;p1_arid0<=0;p1_arid1<=0;
            p1_awaddr0<=0;p1_awaddr1<=0;p1_araddr0<=0;p1_araddr1<=0;
            p1_awlen0<=0;p1_awlen1<=0;p1_arlen0<=0;p1_arlen1<=0;
        end else begin
            if (p1_awpush) begin
                p1_awtail<=!p1_awtail;
                if (p1_awtail) begin p1_awid1<=s1_awid[1:0];p1_awaddr1<=s1_awaddr;p1_awlen1<=s1_awlen;end
                else begin p1_awid0<=s1_awid[1:0];p1_awaddr0<=s1_awaddr;p1_awlen0<=s1_awlen;end
            end
            if (p1_awpop) p1_awhead<=!p1_awhead;
            if (p1_arpush) begin
                p1_artail<=!p1_artail;
                if (p1_artail) begin p1_arid1<=s1_arid[1:0];p1_araddr1<=s1_araddr;p1_arlen1<=s1_arlen;end
                else begin p1_arid0<=s1_arid[1:0];p1_araddr0<=s1_araddr;p1_arlen0<=s1_arlen;end
            end
            if (p1_arpop) p1_arhead<=!p1_arhead;
            case ({p1_awpush,p1_awpop})
                2'b10:p1_awcount<=p1_awcount+1'b1;
                2'b01:p1_awcount<=p1_awcount-1'b1;
                default:p1_awcount<=p1_awcount;
            endcase
            case ({p1_arpush,p1_arpop})
                2'b10:p1_arcount<=p1_arcount+1'b1;
                2'b01:p1_arcount<=p1_arcount-1'b1;
                default:p1_arcount<=p1_arcount;
            endcase
            case ({p1_awpush,p1_bpop})
                2'b10:p1_writes<=p1_writes+1'b1;
                2'b01:p1_writes<=p1_writes-1'b1;
                default:p1_writes<=p1_writes;
            endcase
            case ({p1_arpush,p1_rretire})
                2'b10:p1_reads<=p1_reads+1'b1;
                2'b01:p1_reads<=p1_reads-1'b1;
                default:p1_reads<=p1_reads;
            endcase
            case ({p1_push,p1_pop})
                2'b10:p1_count<=p1_count+1'b1;
                2'b01:p1_count<=p1_count-1'b1;
                default:p1_count<=p1_count;
            endcase
        end
    end
    // Client2: two address metadata entries; payload storage remains official.
    reg [1:0] p2_writes, p2_reads, p2_awcount, p2_arcount;
    reg p2_awhead,p2_awtail,p2_arhead,p2_artail;
    reg [1:0] p2_awid0,p2_awid1,p2_arid0,p2_arid1;
    reg [27:0] p2_awaddr0,p2_awaddr1,p2_araddr0,p2_araddr1;
    reg [7:0] p2_awlen0,p2_awlen1,p2_arlen0,p2_arlen1;
    wire [1:0] p2_awid=p2_awhead?p2_awid1:p2_awid0, p2_arid=p2_arhead?p2_arid1:p2_arid0;
    wire [27:0] p2_awaddr=p2_awhead?p2_awaddr1:p2_awaddr0, p2_araddr=p2_arhead?p2_araddr1:p2_araddr0;
    wire [7:0] p2_awlen=p2_awhead?p2_awlen1:p2_awlen0, p2_arlen=p2_arhead?p2_arlen1:p2_arlen0;
    wire p2_awheld=(p2_awcount!=0), p2_arheld=(p2_arcount!=0);
    wire p2_awready,p2_arready,p2_rvalid,p2_rready,p2_wready;
    assign s2_wready=p2_wready && p2_writes!=0;
    wire [1:0] p2_rid,p2_rresp; wire [127:0] p2_rdata; wire p2_rlast;
    wire [146:0] p2_response; wire p2_fifo_ready,p2_source_done,p2_sink_done;
    reg [5:0] p2_count;
    wire p2_awgood=s2_awid[3:2]==0 && command_supported(s2_awaddr,s2_awlen,s2_awsize,s2_awburst);
    wire p2_argood=s2_arid[3:2]==0 && command_supported(s2_araddr,s2_arlen,s2_arsize,s2_arburst);
    assign s2_awready=all_reset_done && !fault && p2_writes<2 && p2_awcount<2 && p2_awgood;
    assign s2_arready=all_reset_done && !fault && p2_reads<2 && p2_arcount<2 && p2_argood;
    wire p2_awpush=s2_awvalid && s2_awready, p2_awpop=p2_awheld && p2_awready;
    wire p2_arpush=s2_arvalid && s2_arready, p2_arpop=p2_arheld && p2_arready;
    wire p2_bpop=s2_bvalid && s2_bready;
    wire p2_push=p2_rvalid && p2_rready, p2_pop=s2_rvalid && s2_rready;
    wire p2_rretire=p2_pop && s2_rlast;
    assign p2_rready=p2_fifo_ready && p2_count<32 && p2_reads!=0;
    assign s2_rid=p2_response[134:131]; assign s2_rresp=p2_response[130:129];
    assign s2_rlast=p2_response[128]; assign s2_rdata=p2_response[127:0];
    axis_frame_fifo_ip u_response_fifo2 (
        .i_source_clk(clk),.i_source_rst_n(rst_n),.i_source_data({12'd0,2'd0,p2_rid,p2_rresp,p2_rlast,p2_rdata}),
        .i_source_valid(p2_rvalid && p2_count<32 && p2_reads!=0),.o_source_ready(p2_fifo_ready),
        .o_source_reset_done(p2_source_done),.i_sink_clk(clk),.i_sink_rst_n(rst_n),
        .o_sink_data(p2_response),.o_sink_valid(s2_rvalid),.i_sink_ready(s2_rready),.o_sink_reset_done(p2_sink_done));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p2_writes<=0;p2_reads<=0;p2_awcount<=0;p2_arcount<=0;p2_count<=0;
            p2_awhead<=0;p2_awtail<=0;p2_arhead<=0;p2_artail<=0;
            p2_awid0<=0;p2_awid1<=0;p2_arid0<=0;p2_arid1<=0;
            p2_awaddr0<=0;p2_awaddr1<=0;p2_araddr0<=0;p2_araddr1<=0;
            p2_awlen0<=0;p2_awlen1<=0;p2_arlen0<=0;p2_arlen1<=0;
        end else begin
            if (p2_awpush) begin
                p2_awtail<=!p2_awtail;
                if (p2_awtail) begin p2_awid1<=s2_awid[1:0];p2_awaddr1<=s2_awaddr;p2_awlen1<=s2_awlen;end
                else begin p2_awid0<=s2_awid[1:0];p2_awaddr0<=s2_awaddr;p2_awlen0<=s2_awlen;end
            end
            if (p2_awpop) p2_awhead<=!p2_awhead;
            if (p2_arpush) begin
                p2_artail<=!p2_artail;
                if (p2_artail) begin p2_arid1<=s2_arid[1:0];p2_araddr1<=s2_araddr;p2_arlen1<=s2_arlen;end
                else begin p2_arid0<=s2_arid[1:0];p2_araddr0<=s2_araddr;p2_arlen0<=s2_arlen;end
            end
            if (p2_arpop) p2_arhead<=!p2_arhead;
            case ({p2_awpush,p2_awpop})
                2'b10:p2_awcount<=p2_awcount+1'b1;
                2'b01:p2_awcount<=p2_awcount-1'b1;
                default:p2_awcount<=p2_awcount;
            endcase
            case ({p2_arpush,p2_arpop})
                2'b10:p2_arcount<=p2_arcount+1'b1;
                2'b01:p2_arcount<=p2_arcount-1'b1;
                default:p2_arcount<=p2_arcount;
            endcase
            case ({p2_awpush,p2_bpop})
                2'b10:p2_writes<=p2_writes+1'b1;
                2'b01:p2_writes<=p2_writes-1'b1;
                default:p2_writes<=p2_writes;
            endcase
            case ({p2_arpush,p2_rretire})
                2'b10:p2_reads<=p2_reads+1'b1;
                2'b01:p2_reads<=p2_reads-1'b1;
                default:p2_reads<=p2_reads;
            endcase
            case ({p2_push,p2_pop})
                2'b10:p2_count<=p2_count+1'b1;
                2'b01:p2_count<=p2_count-1'b1;
                default:p2_count<=p2_count;
            endcase
        end
    end
    assign all_reset_done=matrix_reset_n && p0_source_done && p0_sink_done && p1_source_done && p1_sink_done && p2_source_done && p2_sink_done;
    // Two physical issued transactions per direction, exact IDs and lengths.
    reg bvalid0,bvalid1,bdone0,bdone1,b_oldest,rvalid0,rvalid1,r_oldest;
    reg [3:0] bid0,bid1,rid0,rid1;
    reg [4:0] remaining0,remaining1;
    reg whead,wtail; reg [1:0] wcount;
    reg wslot0,wslot1; reg [4:0] wleft0,wleft1;
    wire wslot=whead?wslot1:wslot0; wire [4:0] wleft=whead?wleft1:wleft0;
    wire bmatch0=bvalid0 && bdone0 && m_bid==bid0;
    wire bmatch1=bvalid1 && bdone1 && m_bid==bid1;
    wire authenticated_b=bmatch0 || bmatch1;
    wire bselect=bmatch0 && bmatch1 ? b_oldest : !bmatch0;
    wire rmatch0=rvalid0 && remaining0!=0 && m_rid==rid0;
    wire rmatch1=rvalid1 && remaining1!=0 && m_rid==rid1;
    wire authenticated_r=rmatch0 || rmatch1;
    wire rselect=rmatch0 && rmatch1 ? r_oldest : !rmatch0;
    wire [4:0] rleft=rselect?remaining1:remaining0;
    wire aw_slot_available=!bvalid0 || !bvalid1;
    wire ar_slot_available=!rvalid0 || !rvalid1;
    wire balloc=bvalid0, ralloc=rvalid0;
    wire core_bready,core_rready,core_wvalid,core_awvalid,core_arvalid;
    assign m_awvalid=core_awvalid && aw_slot_available;
    assign m_arvalid=core_arvalid && ar_slot_available;
    assign m_wvalid=core_wvalid && wcount!=0;
    assign m_bready=core_bready && authenticated_b;
    assign m_rready=core_rready && authenticated_r;
    wire aw_fire=m_awvalid && m_awready,w_fire=m_wvalid && m_wready,b_fire=m_bvalid && m_bready;
    wire ar_fire=m_arvalid && m_arready,r_fire=m_rvalid && m_rready;
    wire rcomplete=r_fire && m_rlast && rleft==1;
    wire wcomplete=w_fire && m_wlast && wleft==1;
    wire write_inflight=bvalid0 || bvalid1,read_inflight=rvalid0 || rvalid1;
    reg [31:0] write_wait,read_wait;
    wire invalid_request=(s0_awvalid && p0_writes<2 && !p0_awgood) || (s0_arvalid && p0_reads<2 && !p0_argood) ||
        (s1_awvalid && p1_writes<2 && !p1_awgood) || (s1_arvalid && p1_reads<2 && !p1_argood) ||
        (s2_awvalid && p2_writes<2 && !p2_awgood) || (s2_arvalid && p2_reads<2 && !p2_argood);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin fault<=0;bvalid0<=0;bvalid1<=0;bdone0<=0;bdone1<=0;b_oldest<=0;
            rvalid0<=0;rvalid1<=0;r_oldest<=0;bid0<=0;bid1<=0;rid0<=0;rid1<=0;
            remaining0<=0;remaining1<=0;whead<=0;wtail<=0;wcount<=0;
            wslot0<=0;wslot1<=0;wleft0<=0;wleft1<=0;write_wait<=0;read_wait<=0;
        end else begin
            if(all_reset_done && invalid_request)fault<=1;
            if(m_bvalid && !authenticated_b)fault<=1;
            if(m_rvalid && !authenticated_r)fault<=1;
            if(b_fire)begin
                if(bselect)bvalid1<=0;else bvalid0<=0;
                if(bselect?bvalid0:bvalid1)b_oldest<=!bselect;
                if(m_bresp!=0)fault<=1;
            end
            if(r_fire)begin
                if(rselect)remaining1<=remaining1-1'b1;else remaining0<=remaining0-1'b1;
                if(m_rlast!=(rleft==1) || m_rresp!=0)fault<=1;
                if(rcomplete)begin
                    if(rselect)rvalid1<=0;else rvalid0<=0;
                    if(rselect?rvalid0:rvalid1)r_oldest<=!rselect;
                end
            end
            if(w_fire)begin
                if(whead)wleft1<=wleft1-1'b1;else wleft0<=wleft0-1'b1;
                if(m_wlast!=(wleft==1))fault<=1;
                if(wcomplete)begin whead<=!whead;if(wslot)bdone1<=1;else bdone0<=1;end
            end
            if(aw_fire)begin
                if(balloc)begin bvalid1<=1;bdone1<=0;bid1<=m_awid;end
                else begin bvalid0<=1;bdone0<=0;bid0<=m_awid;end
                // If the only older entry retires while this address arrives,
                // the new entry becomes oldest. Do not retain the retired slot.
                if(!(balloc ? (bvalid0 && !(b_fire && !bselect)) :
                              (bvalid1 && !(b_fire && bselect))))b_oldest<=balloc;
                wtail<=!wtail;
                if(wtail)begin wslot1<=balloc;wleft1<={1'b0,m_awlen[3:0]}+5'd1;end
                else begin wslot0<=balloc;wleft0<={1'b0,m_awlen[3:0]}+5'd1;end
            end
            case({aw_fire,wcomplete})
                2'b10:wcount<=wcount+1'b1;2'b01:wcount<=wcount-1'b1;default:wcount<=wcount;
            endcase
            if(ar_fire)begin
                if(ralloc)begin rvalid1<=1;rid1<=m_arid;remaining1<={1'b0,m_arlen[3:0]}+5'd1;end
                else begin rvalid0<=1;rid0<=m_arid;remaining0<={1'b0,m_arlen[3:0]}+5'd1;end
                if(!(ralloc ? (rvalid0 && !(rcomplete && !rselect)) :
                              (rvalid1 && !(rcomplete && rselect))))r_oldest<=ralloc;
            end
            if(!write_inflight || aw_fire || w_fire || b_fire || (m_bvalid && authenticated_b))write_wait<=0;
            else if(write_wait<32'hffffffff)write_wait<=write_wait+1;
            if(!read_inflight || ar_fire || r_fire)read_wait<=0;
            else if(read_wait<32'hffffffff)read_wait<=read_wait+1;
            if(TIMEOUT_CYCLES>1 && ((write_inflight && write_wait>=TIMEOUT_CYCLES-1) ||
                (read_inflight && read_wait>=TIMEOUT_CYCLES-1)))fault<=1;
        end
    end
    // Port-only connection to the vendor-generated, GUI-managed configuration.
    axi_matrix_3to1_ip u_matrix (.aclk(clk),.aresetn(matrix_reset_n),
        .us0_awid(p0_awid),
        .us0_awaddr(p0_awaddr),
        .us0_awlen(p0_awlen),
        .us0_awsize(3'd4),
        .us0_awburst(2'b01),
        .us0_awlock(1'b0),
        .us0_awcache(4'd0),
        .us0_awprot(3'd0),
        .us0_awqos(4'd0),
        .us0_awvalid(p0_awheld),
        .us0_awready(p0_awready),
        .us0_arid(p0_arid),
        .us0_araddr(p0_araddr),
        .us0_arlen(p0_arlen),
        .us0_arsize(3'd4),
        .us0_arburst(2'b01),
        .us0_arlock(1'b0),
        .us0_arcache(4'd0),
        .us0_arprot(3'd0),
        .us0_arqos(4'd0),
        .us0_arvalid(p0_arheld),
        .us0_arready(p0_arready),
        .us0_wdata(s0_wdata),
        .us0_wstrb(s0_wstrb),
        .us0_wlast(s0_wlast),
        .us0_wready(p0_wready),
        .us0_wvalid(s0_wvalid && p0_writes!=0),
        .us0_bid(s0_bid[1:0]),
        .us0_bresp(s0_bresp),
        .us0_bvalid(s0_bvalid),
        .us0_bready(s0_bready),
        .us0_rid(p0_rid),
        .us0_rdata(p0_rdata),
        .us0_rresp(p0_rresp),
        .us0_rlast(p0_rlast),
        .us0_rvalid(p0_rvalid),
        .us0_rready(p0_rready),
        .us1_awid(p1_awid),
        .us1_awaddr(p1_awaddr),
        .us1_awlen(p1_awlen),
        .us1_awsize(3'd4),
        .us1_awburst(2'b01),
        .us1_awlock(1'b0),
        .us1_awcache(4'd0),
        .us1_awprot(3'd0),
        .us1_awqos(4'd0),
        .us1_awvalid(p1_awheld),
        .us1_awready(p1_awready),
        .us1_arid(p1_arid),
        .us1_araddr(p1_araddr),
        .us1_arlen(p1_arlen),
        .us1_arsize(3'd4),
        .us1_arburst(2'b01),
        .us1_arlock(1'b0),
        .us1_arcache(4'd0),
        .us1_arprot(3'd0),
        .us1_arqos(4'd0),
        .us1_arvalid(p1_arheld),
        .us1_arready(p1_arready),
        .us1_wdata(s1_wdata),
        .us1_wstrb(s1_wstrb),
        .us1_wlast(s1_wlast),
        .us1_wready(p1_wready),
        .us1_wvalid(s1_wvalid && p1_writes!=0),
        .us1_bid(s1_bid[1:0]),
        .us1_bresp(s1_bresp),
        .us1_bvalid(s1_bvalid),
        .us1_bready(s1_bready),
        .us1_rid(p1_rid),
        .us1_rdata(p1_rdata),
        .us1_rresp(p1_rresp),
        .us1_rlast(p1_rlast),
        .us1_rvalid(p1_rvalid),
        .us1_rready(p1_rready),
        .us2_awid(p2_awid),
        .us2_awaddr(p2_awaddr),
        .us2_awlen(p2_awlen),
        .us2_awsize(3'd4),
        .us2_awburst(2'b01),
        .us2_awlock(1'b0),
        .us2_awcache(4'd0),
        .us2_awprot(3'd0),
        .us2_awqos(4'd0),
        .us2_awvalid(p2_awheld),
        .us2_awready(p2_awready),
        .us2_arid(p2_arid),
        .us2_araddr(p2_araddr),
        .us2_arlen(p2_arlen),
        .us2_arsize(3'd4),
        .us2_arburst(2'b01),
        .us2_arlock(1'b0),
        .us2_arcache(4'd0),
        .us2_arprot(3'd0),
        .us2_arqos(4'd0),
        .us2_arvalid(p2_arheld),
        .us2_arready(p2_arready),
        .us2_wdata(s2_wdata),
        .us2_wstrb(s2_wstrb),
        .us2_wlast(s2_wlast),
        .us2_wready(p2_wready),
        .us2_wvalid(s2_wvalid && p2_writes!=0),
        .us2_bid(s2_bid[1:0]),
        .us2_bresp(s2_bresp),
        .us2_bvalid(s2_bvalid),
        .us2_bready(s2_bready),
        .us2_rid(p2_rid),
        .us2_rdata(p2_rdata),
        .us2_rresp(p2_rresp),
        .us2_rlast(p2_rlast),
        .us2_rvalid(p2_rvalid),
        .us2_rready(p2_rready),
        .ds0_awid(m_awid),
        .ds0_awaddr(m_awaddr),
        .ds0_awlen(m_awlen),
        .ds0_awsize(m_awsize),
        .ds0_awburst(m_awburst),
        .ds0_awvalid(core_awvalid),
        .ds0_awready(m_awready && aw_slot_available),
        .ds0_awlock(),
        .ds0_awcache(),
        .ds0_awprot(),
        .ds0_awqos(),
        .ds0_awregion(),
        .ds0_arid(m_arid),
        .ds0_araddr(m_araddr),
        .ds0_arlen(m_arlen),
        .ds0_arsize(m_arsize),
        .ds0_arburst(m_arburst),
        .ds0_arvalid(core_arvalid),
        .ds0_arready(m_arready && ar_slot_available),
        .ds0_arlock(),
        .ds0_arcache(),
        .ds0_arprot(),
        .ds0_arqos(),
        .ds0_arregion(),
        .ds0_wdata(m_wdata),
        .ds0_wstrb(m_wstrb),
        .ds0_wlast(m_wlast),
        .ds0_wvalid(core_wvalid),
        .ds0_wready(m_wready && wcount!=0),
        .ds0_bid(m_bid),
        .ds0_bresp(m_bresp),
        .ds0_bvalid(m_bvalid && authenticated_b),
        .ds0_bready(core_bready),
        .ds0_rid(m_rid),
        .ds0_rdata(m_rdata),
        .ds0_rresp(m_rresp),
        .ds0_rlast(m_rlast),
        .ds0_rvalid(m_rvalid && authenticated_r),
        .ds0_rready(core_rready));
    assign s0_bid[3:2]=2'd0;
    assign s1_bid[3:2]=2'd0;
    assign s2_bid[3:2]=2'd0;
endmodule
