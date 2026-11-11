`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"
// One outstanding aligned DWORD BAR access, translated from the real PH1A CQ
// descriptor format. Unsupported reads return UR; posted writes are discarded.
module c2h_bar_cq # (parameter [2:0] CONTROL_BAR = 3'd0) (
    input wire i_clk, input wire i_rst_n,
    input wire [127:0] i_cq_data, input wire [3:0] i_cq_keep,
    input wire [87:0] i_cq_user, input wire i_cq_last, input wire i_cq_valid,
    output wire o_cq_ready,
    output wire [127:0] o_cc_data, output wire [3:0] o_cc_keep,
    output wire [32:0] o_cc_user, output wire o_cc_last, output wire o_cc_valid,
    input wire i_cc_ready,
    output wire [11:0] o_reg_address, output wire o_reg_write,
    output wire [31:0] o_reg_wdata, output wire [3:0] o_reg_wstrb,
    input wire [31:0] i_reg_rdata,
    output wire [31:0] o_axil_awaddr, output wire [2:0] o_axil_awprot,
    output wire o_axil_awvalid, input wire i_axil_awready,
    output wire [31:0] o_axil_wdata, output wire [3:0] o_axil_wstrb,
    output wire o_axil_wvalid, input wire i_axil_wready,
    input wire [1:0] i_axil_bresp, input wire i_axil_bvalid, output wire o_axil_bready,
    output wire [31:0] o_axil_araddr, output wire [2:0] o_axil_arprot,
    output wire o_axil_arvalid, input wire i_axil_arready,
    input wire [31:0] i_axil_rdata, input wire [1:0] i_axil_rresp,
    input wire i_axil_rvalid, output wire o_axil_rready, output wire o_axil_fault
);
    localparam [3:0] S_HEADER=0, S_WRITE=1, S_READ=2, S_REPLY=3, S_DRAIN=4,
        S_AXI_WRITE=5,S_AXI_B=6,S_AXI_AR=7,S_AXI_R=8;
    localparam [31:0] USER_BASE=`PCIE_USER_BAR_BASE;
    reg [3:0] state, next_state;
    reg [11:0] address;
    reg [15:0] requester;
    reg [7:0] tag;
    reg [2:0] traffic_class;
    reg [3:0] first_be;
    reg unsupported, pending_read;
    reg external_access, aw_pending, w_pending, axil_fault;
    reg [31:0] external_address, external_wdata;
    reg [127:0] reply;
    wire header_fire = i_cq_valid && o_cq_ready;
    wire is_read = i_cq_data[78:75] == 0;
    wire is_write = i_cq_data[78:75] == 1;
    wire needs_completion = i_cq_data[78:75] < 12 && !is_write;
    wire to_external = i_cq_data[19:12] == USER_BASE[19:12];
    wire private_page = i_cq_data[19:12] == 0;
    wire supported = i_cq_keep == 4'hf && i_cq_data[74:64] == 1 &&
        i_cq_data[114:112] == CONTROL_BAR &&
        i_cq_data[111:104] == 0 && i_cq_data[1:0] == 0 && i_cq_user[7:4] == 0 &&
        (private_page || to_external) &&
        (is_read || is_write) && ((to_external && is_write) || i_cq_user[3:0] == 4'hf) && !i_cq_user[41];
    assign o_cq_ready = state == S_HEADER || state == S_WRITE || state == S_DRAIN;
    assign o_reg_address = address;
    // The PH1A 128-bit converter can pad a one-DWORD payload with KEEP=F.
    // supported already requires length=1; only the low DWORD is consumed.
    assign o_reg_write = state == S_WRITE && header_fire && i_cq_last && (i_cq_keep == 4'h1 || i_cq_keep == 4'hf) && !unsupported && !external_access;
    assign o_reg_wdata = i_cq_data[31:0];
    assign o_reg_wstrb = first_be;
    assign o_cc_data = reply;
    assign o_cc_keep = unsupported ? 4'h7 : 4'hf;
    assign o_cc_user = 0;
    assign o_cc_last = 1;
    assign o_cc_valid = state == S_REPLY;
    assign o_axil_awaddr=external_address;
    assign o_axil_awprot=0;
    assign o_axil_awvalid=state==S_AXI_WRITE && aw_pending;
    assign o_axil_wdata=external_wdata;
    assign o_axil_wstrb=first_be;
    assign o_axil_wvalid=state==S_AXI_WRITE && w_pending;
    assign o_axil_bready=state==S_AXI_B;
    assign o_axil_araddr=external_address;
    assign o_axil_arprot=0;
    assign o_axil_arvalid=state==S_AXI_AR;
    assign o_axil_rready=state==S_AXI_R;
    assign o_axil_fault=axil_fault;
    always @(*) begin
        next_state = state;
        case (state)
            S_HEADER: if (header_fire) begin
                if (needs_completion) begin
                    if (i_cq_last) next_state = S_READ;
                    else next_state = S_DRAIN;
                end else if (is_write && !i_cq_last) next_state = S_WRITE;
                else if (!i_cq_last) next_state = S_DRAIN;
            end
            S_WRITE: if (header_fire) begin
                if (i_cq_last && (i_cq_keep==4'h1 || i_cq_keep==4'hf) && !unsupported && external_access) next_state=S_AXI_WRITE;
                else if (i_cq_last) next_state = S_HEADER;
                else next_state = S_DRAIN;
            end
            S_READ: begin
                if(external_access&&!unsupported)next_state=S_AXI_AR;
                else next_state=S_REPLY;
            end
            S_REPLY: if (i_cc_ready) next_state = S_HEADER;
            S_DRAIN: if (header_fire && i_cq_last) begin
                if (pending_read) next_state = S_READ;
                else next_state = S_HEADER;
            end
            S_AXI_WRITE: if((!aw_pending||i_axil_awready)&&(!w_pending||i_axil_wready))next_state=S_AXI_B;
            S_AXI_B: if(i_axil_bvalid)next_state=S_HEADER;
            S_AXI_AR: if(i_axil_arready)next_state=S_AXI_R;
            S_AXI_R: if(i_axil_rvalid)next_state=S_REPLY;
            default: next_state = S_HEADER;
        endcase
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) state <= S_HEADER;
        else state <= next_state;
    end
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            address<=0; requester<=0; tag<=0; traffic_class<=0;
            first_be<=0; unsupported<=0; pending_read<=0; reply<=0;
            external_access<=0;aw_pending<=0;w_pending<=0;external_address<=0;external_wdata<=0;axil_fault<=0;
        end else begin
            if (state == S_HEADER && header_fire) begin
                address <= i_cq_data[11:0];
                requester <= i_cq_data[95:80];
                tag <= i_cq_data[103:96];
                traffic_class <= i_cq_data[123:121];
                first_be <= i_cq_user[3:0];
                unsupported <= !supported || (needs_completion && !i_cq_last);
                pending_read <= needs_completion;
                external_access<=to_external;
                external_address<=i_cq_data[31:0];
            end
            if(state==S_WRITE&&header_fire)begin external_wdata<=i_cq_data[31:0];aw_pending<=1;w_pending<=1;end
            if(o_axil_awvalid&&i_axil_awready)aw_pending<=0;
            if(o_axil_wvalid&&i_axil_wready)w_pending<=0;
            if(state==S_AXI_B&&i_axil_bvalid&&i_axil_bresp!=0)axil_fault<=1;
            if (state == S_READ) begin
                reply <= 0;
                reply[6:0] <= address[6:0];
                reply[63:48] <= requester;
                reply[71:64] <= tag;
                reply[91:89] <= traffic_class;
                if (unsupported) reply[45:43] <= 3'd1;
                else begin
                    reply[27:16] <= 12'd4;
                    reply[42:32] <= 11'd1;
                    reply[127:96] <= i_reg_rdata;
                end
            end
            if(state==S_AXI_R&&i_axil_rvalid)begin
                reply[127:96]<=i_axil_rdata;
                if(i_axil_rresp!=0)begin
                    unsupported<=1;axil_fault<=1;reply[42:32]<=0;reply[27:16]<=0;
                    if(i_axil_rresp==3)reply[45:43]<=1;else reply[45:43]<=4;
                end
            end
        end
    end
endmodule
