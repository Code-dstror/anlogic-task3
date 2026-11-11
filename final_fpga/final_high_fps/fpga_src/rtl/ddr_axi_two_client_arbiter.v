`timescale 1ns / 1ps

// Two DFI-domain AXI clients share the existing 128-bit DDR AXI interface.
// Each client has a complete 16-beat read-response buffer, so an indefinitely
// stalled PCIe consumer cannot hold the DDR read owner after its RLAST arrives.
module ddr_axi_two_client_arbiter #(
    parameter integer TIMEOUT_CYCLES = 4096
) (
    input wire clk,
    input wire rst_n,
    output reg fault,
    output reg o_recovery_required,
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

    localparam [1:0] W_IDLE=0, W_ADDR=1, W_DATA=2, W_RESP=3;
    localparam [1:0] R_IDLE=0, R_ADDR=1, R_DATA=2;
    localparam TIMEOUT_EN = TIMEOUT_CYCLES > 1;
    function integer timeout_width;
        input integer limit;
        reg [31:0] value;
        begin
            value=limit>0 ? limit : 0;timeout_width=0;
            while(value!=0)begin timeout_width=timeout_width+1;value=value>>1;end
            if(timeout_width==0)timeout_width=1;
        end
    endfunction
    localparam integer WAIT_WIDTH=timeout_width(TIMEOUT_CYCLES>1 ? TIMEOUT_CYCLES-1 : 0);
    localparam [WAIT_WIDTH-1:0] WAIT_LIMIT=TIMEOUT_CYCLES>1 ? TIMEOUT_CYCLES-1 : 0;
    reg [1:0] w_state, r_state;
    reg w_owner, r_owner, w_turn, r_turn;
    reg [3:0] w_id, r_id;
    reg [27:0] w_addr, r_addr;
    reg [7:0] w_len, r_len;
    reg [4:0] w_remaining, r_remaining;
    reg [WAIT_WIDTH-1:0] w_wait, r_wait;
    // Total accepted responses include the shallow RAM and its held output beat.
    reg [4:0] count0, count1;
    wire [134:0] response0, response1;
    wire response_write_ready0, response_write_ready1;
    wire response_valid0, response_valid1;
    wire response_source_done0, response_sink_done0;
    wire response_source_done1, response_sink_done1;

    // Addresses are byte addresses. The fixed memory client contract is
    // 16-byte-aligned INCR, one to sixteen 16-byte beats, within one 4 KiB page.
    function command_supported;
        input [27:0] address;
        input [7:0] length;
        input [2:0] size;
        input [1:0] burst;
        reg [12:0] page_end;
        begin
            page_end = {1'b0, address[11:0]} +
                       {4'd0, ({1'b0, length[3:0]} + 5'd1), 4'd0};
            command_supported = address[3:0] == 4'd0 && length[7:4] == 4'd0 &&
                                size == 3'd4 && burst == 2'b01 &&
                                page_end <= 13'd4096;
        end
    endfunction

    wire w_select = s0_awvalid && s1_awvalid ? w_turn : !s0_awvalid;
    wire w_request = s0_awvalid || s1_awvalid;
    wire [3:0] selected_w_id = w_select ? s1_awid : s0_awid;
    wire [27:0] selected_w_addr = w_select ? s1_awaddr : s0_awaddr;
    wire [7:0] selected_w_len = w_select ? s1_awlen : s0_awlen;
    wire selected_w_supported = w_select ?
        command_supported(s1_awaddr, s1_awlen, s1_awsize, s1_awburst) :
        command_supported(s0_awaddr, s0_awlen, s0_awsize, s0_awburst);
    wire eligible_r0 = s0_arvalid && count0 == 0 &&
                      response_source_done0 && response_sink_done0;
    wire eligible_r1 = s1_arvalid && count1 == 0 &&
                      response_source_done1 && response_sink_done1;
    wire r_select = eligible_r0 && eligible_r1 ? r_turn : !eligible_r0;
    wire r_request = eligible_r0 || eligible_r1;
    wire [3:0] selected_r_id = r_select ? s1_arid : s0_arid;
    wire [27:0] selected_r_addr = r_select ? s1_araddr : s0_araddr;
    wire [7:0] selected_r_len = r_select ? s1_arlen : s0_arlen;
    wire selected_r_supported = r_select ?
        command_supported(s1_araddr, s1_arlen, s1_arsize, s1_arburst) :
        command_supported(s0_araddr, s0_arlen, s0_arsize, s0_arburst);

    assign m_awid = w_id;
    assign m_awaddr = w_addr;
    assign m_awlen = w_len;
    assign m_awsize = 3'd4;
    assign m_awburst = 2'b01;
    assign m_awvalid = w_state == W_ADDR;
    assign s0_awready = w_state == W_ADDR && !w_owner && m_awready;
    assign s1_awready = w_state == W_ADDR && w_owner && m_awready;
    assign m_wdata = w_owner ? s1_wdata : s0_wdata;
    assign m_wstrb = w_owner ? s1_wstrb : s0_wstrb;
    assign m_wlast = w_owner ? s1_wlast : s0_wlast;
    assign m_wvalid = w_state == W_DATA && (w_owner ? s1_wvalid : s0_wvalid);
    assign s0_wready = w_state == W_DATA && !w_owner && m_wready;
    assign s1_wready = w_state == W_DATA && w_owner && m_wready;
    assign s0_bid = m_bid;
    assign s1_bid = m_bid;
    assign s0_bresp = m_bresp;
    assign s1_bresp = m_bresp;
    assign s0_bvalid = w_state == W_RESP && !w_owner && m_bvalid;
    assign s1_bvalid = w_state == W_RESP && w_owner && m_bvalid;
    assign m_bready = w_state == W_RESP && (w_owner ? s1_bready : s0_bready);

    assign m_arid = r_id;
    assign m_araddr = r_addr;
    assign m_arlen = r_len;
    assign m_arsize = 3'd4;
    assign m_arburst = 2'b01;
    assign m_arvalid = r_state == R_ADDR;
    assign s0_arready = r_state == R_ADDR && !r_owner && m_arready;
    assign s1_arready = r_state == R_ADDR && r_owner && m_arready;
    assign m_rready = r_state == R_DATA && r_remaining != 0 &&
                      (r_owner ? count1 < 5'd16 && response_write_ready1 :
                                 count0 < 5'd16 && response_write_ready0);
    assign s0_rid = response0[134:131];
    assign s0_rresp = response0[130:129];
    assign s0_rlast = response0[128];
    assign s0_rdata = response0[127:0];
    assign s0_rvalid = response_valid0;
    assign s1_rid = response1[134:131];
    assign s1_rresp = response1[130:129];
    assign s1_rlast = response1[128];
    assign s1_rdata = response1[127:0];
    assign s1_rvalid = response_valid1;

    wire aw_fire = m_awvalid && m_awready;
    wire w_fire = m_wvalid && m_wready;
    wire b_fire = m_bvalid && m_bready;
    wire ar_fire = m_arvalid && m_arready;
    wire r_fire = m_rvalid && m_rready;
    wire push0 = r_fire && !r_owner;
    wire push1 = r_fire && r_owner;
    wire pop0 = s0_rvalid && s0_rready;
    wire pop1 = s1_rvalid && s1_rready;
    wire w_address_changed = w_state == W_ADDR &&
        (w_owner ? (!s1_awvalid || s1_awid != w_id || s1_awaddr != w_addr ||
                    s1_awlen != w_len || s1_awsize != 3'd4 || s1_awburst != 2'b01) :
                   (!s0_awvalid || s0_awid != w_id || s0_awaddr != w_addr ||
                    s0_awlen != w_len || s0_awsize != 3'd4 || s0_awburst != 2'b01));
    wire r_address_changed = r_state == R_ADDR &&
        (r_owner ? (!s1_arvalid || s1_arid != r_id || s1_araddr != r_addr ||
                    s1_arlen != r_len || s1_arsize != 3'd4 || s1_arburst != 2'b01) :
                   (!s0_arvalid || s0_arid != r_id || s0_araddr != r_addr ||
                    s0_arlen != r_len || s0_arsize != 3'd4 || s0_arburst != 2'b01));
    wire w_timeout = TIMEOUT_EN && w_state != W_IDLE &&
                     !(w_state == W_RESP && m_bvalid) &&
                     !aw_fire && !w_fire && !b_fire &&
                     w_wait >= WAIT_LIMIT;
    wire r_timeout = TIMEOUT_EN && r_state != R_IDLE && !ar_fire && !r_fire &&
                     r_wait >= WAIT_LIMIT;
    wire bad_write = w_state == W_IDLE && !o_recovery_required && w_request && !selected_w_supported;
    wire bad_read = r_state == R_IDLE && !o_recovery_required && r_request && !selected_r_supported;
    wire write_protocol_error = w_fire && (m_wlast != (w_remaining == 1));
    wire write_identity_error = b_fire && m_bid != w_id;
    wire read_identity_error = r_fire &&
        (m_rid != r_id || m_rlast != (r_remaining == 1));
    wire response_status_error = (b_fire && m_bresp != 2'b00) ||
                                 (r_fire && m_rresp != 2'b00);
    wire hard_error = bad_write || bad_read || w_address_changed || r_address_changed ||
                      write_protocol_error || write_identity_error || read_identity_error ||
                      w_timeout || r_timeout || (m_bvalid && w_state != W_RESP) ||
                      (m_rvalid && r_state != R_DATA);

    // Authenticated response status is diagnostic: current frame owners may
    // need further legal bursts to drain. Only loss of transaction identity or
    // protocol/progress proof stops new grants and requires a common recovery.
    // Neither sticky output cancels accepted work or manufactures quiescence.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin fault <= 1'b0; o_recovery_required <= 1'b0; end
        else begin
            if (hard_error || response_status_error) fault <= 1'b1;
            if (hard_error) o_recovery_required <= 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            w_owner <= 0;
            w_turn <= 0;
            w_id <= 0;
            w_addr <= 0;
            w_len <= 0;
            w_remaining <= 0;
            w_wait <= 0;
        end else begin
            if (!TIMEOUT_EN || w_state == W_IDLE || aw_fire || w_fire || b_fire ||
                (w_state == W_RESP && m_bvalid)) w_wait <= 0;
            else if (w_wait != WAIT_LIMIT) w_wait <= w_wait + 1'b1;
            case (w_state)
                W_IDLE: if (!o_recovery_required && w_request && selected_w_supported) begin
                    w_owner <= w_select;
                    w_id <= selected_w_id;
                    w_addr <= selected_w_addr;
                    w_len <= selected_w_len;
                    w_remaining <= {1'b0, selected_w_len[3:0]} + 5'd1;
                    w_state <= W_ADDR;
                end
                W_ADDR: if (aw_fire) w_state <= W_DATA;
                W_DATA: if (w_fire) begin
                    if (w_remaining != 0) w_remaining <= w_remaining - 1'b1;
                    if (w_remaining == 1) w_state <= W_RESP;
                end
                W_RESP: if (b_fire) begin
                    w_turn <= !w_owner;
                    w_state <= W_IDLE;
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state <= R_IDLE;
            r_owner <= 0;
            r_turn <= 0;
            r_id <= 0;
            r_addr <= 0;
            r_len <= 0;
            r_remaining <= 0;
            r_wait <= 0;
        end else begin
            if (!TIMEOUT_EN || r_state == R_IDLE || ar_fire || r_fire) r_wait <= 0;
            else if (r_wait != WAIT_LIMIT) r_wait <= r_wait + 1'b1;
            case (r_state)
                R_IDLE: if (!o_recovery_required && r_request && selected_r_supported) begin
                    r_owner <= r_select;
                    r_id <= selected_r_id;
                    r_addr <= selected_r_addr;
                    r_len <= selected_r_len;
                    r_remaining <= {1'b0, selected_r_len[3:0]} + 5'd1;
                    r_state <= R_ADDR;
                end
                R_ADDR: if (ar_fire) r_state <= R_DATA;
                R_DATA: if (r_fire) begin
                    r_remaining <= r_remaining - 1'b1;
                    // An early/missing RLAST cannot silently complete the owner.
                    if (r_remaining == 1 && m_rlast) begin
                        r_turn <= !r_owner;
                        r_state <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

    // Both clients and the response banks share DFI clk and its coordinated
    // ownership reset. A full burst can complete independently of client ready.
    assign response_source_done0=rst_n;
    assign response_sink_done0=rst_n;
    assign response_source_done1=rst_n;
    assign response_sink_done1=rst_n;
    ddr_response_bank16 u_response_fifo0 (
        .clk(clk),.rst_n(rst_n),.s_data({m_rid,m_rresp,m_rlast,m_rdata}),
        .s_valid(push0),.s_ready(response_write_ready0),
        .m_data(response0),.m_valid(response_valid0),.m_ready(s0_rready));
    ddr_response_bank16 u_response_fifo1 (
        .clk(clk),.rst_n(rst_n),.s_data({m_rid,m_rresp,m_rlast,m_rdata}),
        .s_valid(push1),.s_ready(response_write_ready1),
        .m_data(response1),.m_valid(response_valid1),.m_ready(s1_rready));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count0 <= 0;
            count1 <= 0;
        end else begin
            case ({push0, pop0})
                2'b10: count0 <= count0 + 1'b1;
                2'b01: count0 <= count0 - 1'b1;
                default: begin end
            endcase
            case ({push1, pop1})
                2'b10: count1 <= count1 + 1'b1;
                2'b01: count1 <= count1 - 1'b1;
                default: begin end
            endcase
        end
    end
endmodule
