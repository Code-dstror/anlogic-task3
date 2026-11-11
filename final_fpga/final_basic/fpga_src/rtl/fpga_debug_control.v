`timescale 1ns/1ps
// Independent 25 MHz control plane. Packet layout is specified in debug_uart.md.
// UART and queue storage are vendor IP; this module only handles commands.
// Stage3 private candidate: one CRC step serves RX and accepted TX bytes.
module fpga_debug_control #(
    parameter integer UART_DIV = 27,
    parameter integer TIMEOUT_CYCLES = 2500000,
    parameter integer DOMAIN_COUNT = 2,
    parameter integer IMAGE_CONFIG_ENABLE = 0,
    parameter integer HDR_CAPABLE = 0,
    parameter [4:0] IMAGE_CONFIG_DEFAULT = 5'b00111,
    parameter integer COLOR_CONFIG_ENABLE = 0,
    parameter [9:0] COLOR_CONFIG_DEFAULT = 10'h080,
    parameter [29:0] COLOR_WB_DEFAULT = {10'd256,10'd256,10'd256},
    parameter integer DEBUG_PROFILE = 0,
    parameter integer DEBUG_EXT_ENABLE = 0,
    parameter integer MAINTENANCE_INTERLOCK = 0,
    parameter integer COOPERATIVE_LOCAL_STOP_ENABLE = 0,
    parameter [DOMAIN_COUNT-1:0] TRACE_BANK_MASK =
        (DEBUG_PROFILE == 1 ? 0 : {DOMAIN_COUNT{1'b1}})
) (
    input wire i_clk, input wire i_rx, output wire o_tx,
    input wire [511:0] i_sys_status,
    output wire o_debug_rst_n, output wire o_app_rst_n,
    output reg o_local = 1'b1, output reg o_run = 1'b0,
    output reg o_clear = 1'b0,
    output reg [DOMAIN_COUNT-1:0] o_request,
    output reg [DOMAIN_COUNT*40-1:0] o_command,
    input wire [DOMAIN_COUNT-1:0] i_ack, input wire [DOMAIN_COUNT*40-1:0] i_response,
    output reg [31:0] o_rx_errors,
    output reg [31:0] o_timeouts,
    output reg [4:0] o_image_config = IMAGE_CONFIG_DEFAULT,
    output reg [9:0] o_color_config = COLOR_CONFIG_DEFAULT,
    output reg [29:0] o_color_wb = COLOR_WB_DEFAULT,
    input wire i_maintenance_authorized,
    input wire [2:0] i_maintenance_state,
    output reg o_maintenance_denied,
    input wire i_local_stop_authorized,
    input wire i_local_stop_ready,
    input wire i_local_stop_done,
    output reg o_local_stop_request
);
    reg [9:0] por_count = 0;
    reg por_done = 0;
    reg [9:0] app_count;
    assign o_debug_rst_n = por_done;
    assign o_app_rst_n = por_done && app_count == 0;
    always @(posedge i_clk) if (!por_done) begin
        por_count <= por_count + 1'b1;
        if (&por_count) por_done <= 1'b1;
    end
    wire [7:0] rx_data;
    wire rx_valid, rx_error, tx_ready;
    reg tx_enable;
    reg [7:0] tx_data;
    uart #(.CLK_DIV_NUM(UART_DIV), .DATA_BIT(8),
           .PARITY_BIT("None"), .STOP_BIT("1")) u_uart (
        .clk(i_clk), .rst_n(por_done), .rxd(i_rx), .txd(o_tx),
        .rx_vld(rx_valid), .rx_data(rx_data), .rx_err(rx_error),
        .tx_rdy(tx_ready), .tx_en(tx_enable), .tx_data(tx_data));
    wire [46:0] fifo_data;
    wire fifo_full, fifo_empty, fifo_valid, wr_done, rd_done;
    reg [4:0] flush_count;
    wire queue_reset = !por_done || flush_count!=0;
    wire pop;
    camera_event_fifo_47x512 u_rx_queue (
        .di({39'd0,rx_data}), .clkw(i_clk), .clkr(i_clk),
        .wrst(queue_reset), .rrst(queue_reset),
        .we(rx_valid && !rx_error && wr_done && !fifo_full && !queue_reset), .re(pop),
        .dout(fifo_data), .full_flag(fifo_full), .empty_flag(fifo_empty),
        .valid(fifo_valid), .wr_rst_done(wr_done), .rd_rst_done(rd_done),
        .aempty(), .afull(), .overflow(), .underflow(), .wr_success(),
        .rdusedw(), .wrusedw());
    function [7:0] crc8;
        input [7:0] prior, value;
        reg [7:0] c;
        integer j;
        begin
            c = prior ^ value;
            for (j=0;j<8;j=j+1) c = c[7] ? (c<<1)^8'h07 : c<<1;
            crc8 = c;
        end
    endfunction
    function [103:0] response;
        input [7:0] seq, op, bank, code;
        input [31:0] value;
        begin
            // CRC is accumulated at SEND handshakes; the last byte is selected
            // from that accumulator rather than this placeholder.
            response = {8'd0,value,code,8'd5,bank,op,seq,8'd1,16'h5aa5};
        end
    endfunction
    localparam RECEIVE=0, EXECUTE=1, WAIT_DOMAIN=2, SEND=3, WAIT_LOCAL_STOP=4;
    reg [2:0] state;
    reg [3:0] byte_index, tx_index;
    reg [95:0] request_frame;
    reg [103:0] tx_frame;
    reg [7:0] crc;
    reg [31:0] timer;
    reg [DOMAIN_COUNT-1:0] ack_meta, ack_sync;
    reg [511:0] sys_snapshot;
    reg [31:0] clear_epoch, snapshot_epoch;
    reg snapshot_valid;
    reg [DOMAIN_COUNT-1:0] domain_snapshot_valid, domain_trace_valid;
    // RECEIVE and SEND are mutually exclusive. A byte advances this same CRC
    // network only when its existing queue/UART handshake advances the frame.
    wire [7:0] crc_byte = state == SEND ? tx_frame[7:0] : fifo_data[7:0];
    wire [7:0] crc_next = crc8(crc, crc_byte);
    localparam [31:0] PROFILE_WORD = DEBUG_PROFILE;
    wire [7:0] seq = request_frame[31:24];
    wire [7:0] op = request_frame[39:32];
    wire [7:0] bank = request_frame[47:40];
    wire [31:0] arg = request_frame[87:56];
    wire functional_control = bank == 0 &&
        (op == 8'h02 || op == 8'h03 || op == 8'h04 || op == 8'h05 ||
         op == 8'h06 || op == 8'h08 || op == 8'h0a || op == 8'h0c);
    wire maintenance_control = functional_control ||
        (DEBUG_EXT_ENABLE != 0 && op == 8'h32);
    // Inputs belong to the independent 25 MHz control domain. Neither a quiet
    // output stream nor C2H BUSY=0 proves that the host has retired DMA addresses.
    wire local_stop_control=COOPERATIVE_LOCAL_STOP_ENABLE!=0 && bank==0 && op==8'h03 && o_run;
    wire local_stop_allowed=(i_local_stop_authorized === 1'b1) && o_local &&
        ((i_local_stop_ready === 1'b1) || o_local_stop_request);
    wire maintenance_allowed = (i_maintenance_authorized === 1'b1) &&
        (i_maintenance_state === 3'd1) && o_local && !o_run &&
        (COOPERATIVE_LOCAL_STOP_ENABLE==0 ||
         ((i_local_stop_ready === 1'b1) && !o_local_stop_request));
    wire maintenance_blocked = MAINTENANCE_INTERLOCK != 0 &&
        maintenance_control && !(local_stop_control ? local_stop_allowed : maintenance_allowed);
    assign pop = state==RECEIVE && rd_done && fifo_valid && !fifo_empty && !queue_reset;
    // Response data remains stable from ack until the next request to that bank.
    always @(posedge i_clk) begin
        ack_meta <= i_ack; ack_sync <= ack_meta;
        tx_enable <= 0;
        o_maintenance_denied <= 0;
        if (!por_done) begin
            o_local<=1; o_run<=0; o_clear<=0; o_request<=0; o_command<=0;
            o_local_stop_request<=0;
            app_count<=1023; o_rx_errors<=0; o_timeouts<=0;
            o_image_config<=IMAGE_CONFIG_DEFAULT;
            o_color_config<=COLOR_CONFIG_DEFAULT;
            o_color_wb<=COLOR_WB_DEFAULT;
            state<=RECEIVE; byte_index<=0; tx_index<=0; request_frame<=0;
            crc<=0; timer<=0; tx_frame<=0; tx_data<=8'hff;
            ack_meta<=0; ack_sync<=0; sys_snapshot<=0; flush_count<=0;
            clear_epoch<=0; snapshot_epoch<=0; snapshot_valid<=0;
            domain_snapshot_valid<=0; domain_trace_valid<=0;
        end else begin
            if(app_count!=0) app_count<=app_count-1'b1;
            if(flush_count!=0) flush_count<=flush_count-1'b1;
            if(rx_error || (rx_valid && (fifo_full || !wr_done))) begin
                o_rx_errors<=o_rx_errors+1'b1;
                flush_count<=31;
                // Never execute a frame spanning a lost/invalid byte.
                if(state==RECEIVE) begin byte_index<=0; crc<=0; end
            end else case(state)
            RECEIVE: begin
                if(pop) begin
                    timer<=0;
                    if(byte_index==0) begin
                        if(fifo_data[7:0]==8'ha5) byte_index<=1;
                    end else if(byte_index==1) begin
                        if(fifo_data[7:0]==8'h5a) begin byte_index<=2; crc<=0; end
                        else byte_index <= fifo_data[7:0]==8'ha5 ? 1 : 0;
                    end else begin
                        request_frame[byte_index*8+:8]<=fifo_data[7:0];
                        if(byte_index==11) begin
                            byte_index<=0;
                            if(crc==fifo_data[7:0] && request_frame[23:16]==1 &&
                               request_frame[55:48]==4) state<=EXECUTE;
                            else o_rx_errors<=o_rx_errors+1'b1;
                        end else begin crc<=crc_next; byte_index<=byte_index+1'b1; end
                    end
                end else if(byte_index!=0) begin
                    if(timer==TIMEOUT_CYCLES-1) begin byte_index<=0; timer<=0; o_rx_errors<=o_rx_errors+1'b1; end
                    else timer<=timer+1'b1;
                end
            end
            EXECUTE: begin
                tx_index<=0; timer<=0; crc<=0; state<=SEND;
                tx_frame<=response(seq,op,bank,8'd0,32'd0);
                if(maintenance_blocked) begin
                    tx_frame<=response(seq,op,bank,6,0);
                    o_maintenance_denied<=1;
                end else if(bank==0) case(op)
                    8'h01: tx_frame<=response(seq,op,bank,0,32'h44424731);
                    8'h02: if(o_local) o_run<=1; else tx_frame<=response(seq,op,bank,3,0);
                    8'h03: if(local_stop_control) begin
                        if(local_stop_allowed) begin
                            o_local_stop_request<=1; state<=WAIT_LOCAL_STOP;
                        end else begin
                            tx_frame<=response(seq,op,bank,6,0); o_maintenance_denied<=1;
                        end
                    end else begin o_run<=0; app_count<=1023; end
                    8'h04: begin o_run<=0; app_count<=1023; end
                    8'h05: begin
                        o_clear<=!o_clear; o_rx_errors<=0; o_timeouts<=0;
                        clear_epoch<=clear_epoch+1'b1; snapshot_valid<=0;
                        domain_snapshot_valid<=0; domain_trace_valid<=0;
                    end
                    8'h06: if(arg<=1) begin o_run<=0; app_count<=1023; o_local<=!arg[0]; end
                        else tx_frame<=response(seq,op,bank,1,0);
                    // Image settings are a stable bundle for the next session.
                    // LOCAL_IDLE plus the reset pulse prevents a mid-frame mux
                    // change or a host-owned DMA transaction from being cut.
                    8'h07: if(IMAGE_CONFIG_ENABLE && arg==0)
                        tx_frame<=response(seq,op,bank,0,{27'd0,o_image_config});
                        else tx_frame<=response(seq,op,bank,1,0);
                    8'h08: if(!IMAGE_CONFIG_ENABLE || arg[31:5]!=0 ||
                                 (arg[3] && (!HDR_CAPABLE || !arg[4])) ||
                                 (!HDR_CAPABLE && arg[4]))
                        tx_frame<=response(seq,op,bank,1,0);
                        else if(!o_local) tx_frame<=response(seq,op,bank,3,0);
                        else if(o_run) tx_frame<=response(seq,op,bank,2,0);
                        else begin
                            o_image_config<=arg[4:0]; app_count<=1023;
                            tx_frame<=response(seq,op,bank,0,arg);
                        end
                    // Bayer and sensor gain settle under application reset.
                    // The independent debug domain retains them for the next
                    // session, including subsequent mode and reset commands.
                    8'h09: if(COLOR_CONFIG_ENABLE && arg==0)
                        tx_frame<=response(seq,op,bank,0,{22'd0,o_color_config});
                        else tx_frame<=response(seq,op,bank,1,0);
                    8'h0a: if(!COLOR_CONFIG_ENABLE || arg[31:10]!=0 ||
                                 arg[9:2]>8'd32)
                        tx_frame<=response(seq,op,bank,1,0);
                        else if(!o_local) tx_frame<=response(seq,op,bank,3,0);
                        else if(o_run) tx_frame<=response(seq,op,bank,2,0);
                        else begin
                            o_color_config<=arg[9:0]; app_count<=1023;
                            tx_frame<=response(seq,op,bank,0,arg);
                        end
                    // Q8 gains are committed together while capture is reset.
                    8'h0b: if(COLOR_CONFIG_ENABLE && arg==0)
                        tx_frame<=response(seq,op,bank,0,{2'd0,o_color_wb});
                        else tx_frame<=response(seq,op,bank,1,0);
                    8'h0c: if(!COLOR_CONFIG_ENABLE || arg[31:30]!=0 ||
                                 arg[9:0]==0 || arg[19:10]==0 || arg[29:20]==0)
                        tx_frame<=response(seq,op,bank,1,0);
                        else if(!o_local) tx_frame<=response(seq,op,bank,3,0);
                        else if(o_run) tx_frame<=response(seq,op,bank,2,0);
                        else begin
                            o_color_wb<=arg[29:0]; app_count<=1023;
                            tx_frame<=response(seq,op,bank,0,arg);
                        end
                    8'h10: if(DEBUG_EXT_ENABLE != 0 && !snapshot_valid)
                        tx_frame<=response(seq,op,bank,2,0);
                        else if(arg<16) tx_frame<=response(seq,op,bank,0,sys_snapshot[arg[3:0]*32+:32]);
                        else tx_frame<=response(seq,op,bank,1,0);
                    8'h11: begin
                        sys_snapshot<=i_sys_status; snapshot_epoch<=clear_epoch;
                        snapshot_valid<=1;
                    end
                    8'h30: if(DEBUG_EXT_ENABLE == 0) tx_frame<=response(seq,op,bank,1,0);
                        else case(arg)
                            0: tx_frame<=response(seq,op,bank,0,32'h32474244);
                            1: tx_frame<=response(seq,op,bank,0,1);
                            2: tx_frame<=response(seq,op,bank,0,PROFILE_WORD);
                            3: tx_frame<=response(seq,op,bank,0,32'd5 |
                                (MAINTENANCE_INTERLOCK != 0 ? 32'd16 : 32'd0));
                            default: tx_frame<=response(seq,op,bank,1,0);
                        endcase
                    8'h31: if(DEBUG_EXT_ENABLE == 0) tx_frame<=response(seq,op,bank,1,0);
                        else case(arg)
                            0: tx_frame<=response(seq,op,bank,0,clear_epoch);
                            1: tx_frame<=response(seq,op,bank,0,snapshot_epoch);
                            2: tx_frame<=response(seq,op,bank,0,{31'd0,snapshot_valid});
                            3: tx_frame<=response(seq,op,bank,0,0);
                            default: tx_frame<=response(seq,op,bank,1,0);
                        endcase
                    8'h32: if(DEBUG_EXT_ENABLE == 0 || arg != clear_epoch)
                        tx_frame<=response(seq,op,bank,1,0);
                        else begin
                            clear_epoch<=clear_epoch+1'b1; snapshot_valid<=0;
                            o_rx_errors<=0; o_timeouts<=0;
                            tx_frame<=response(seq,op,bank,0,clear_epoch+1'b1);
                        end
                    8'h33: tx_frame<=response(seq,op,bank,DEBUG_EXT_ENABLE != 0 ? 5 : 1,0);
                    default: tx_frame<=response(seq,op,bank,1,0);
                endcase
                else if(bank>=1 && bank<=DOMAIN_COUNT) begin
                    if(ack_sync[bank-1]!=o_request[bank-1]) tx_frame<=response(seq,op,bank,2,0);
                    else if(DEBUG_EXT_ENABLE != 0 && !TRACE_BANK_MASK[bank-1] &&
                        (op == 8'h20 || op == 8'h21 || op == 8'h22 || op == 8'h23))
                        tx_frame<=response(seq,op,bank,5,0);
                    else if(DEBUG_EXT_ENABLE != 0 &&
                        ((op == 8'h10 && !domain_snapshot_valid[bank-1]) ||
                         (op == 8'h21 && !domain_trace_valid[bank-1])))
                        tx_frame<=response(seq,op,bank,2,0);
                    else begin
                        o_command[(bank-1)*40+:40]<={op,arg};
                        o_request[bank-1]<=!o_request[bank-1];
                        state<=WAIT_DOMAIN;
                    end
                end else tx_frame<=response(seq,op,bank,1,0);
            end
            // STOP completion has its own owner proof. A timeout preserves
            // RUN and admission pause; it never resets an outstanding frame.
            WAIT_LOCAL_STOP: begin
                if(!local_stop_allowed) begin
                    tx_frame<=response(seq,op,bank,6,0); o_maintenance_denied<=1; state<=SEND;
                end else if(i_local_stop_done === 1'b1) begin
                    o_run<=0; app_count<=1023; o_local_stop_request<=0;
                    tx_frame<=response(seq,op,bank,0,0); state<=SEND;
                end else if(timer==TIMEOUT_CYCLES-1) begin
                    tx_frame<=response(seq,op,bank,4,0); o_timeouts<=o_timeouts+1'b1; state<=SEND;
                end else timer<=timer+1'b1;
            end
            WAIT_DOMAIN: begin
                if(ack_sync[bank-1]==o_request[bank-1]) begin
                    tx_frame<=response(seq,op,bank,i_response[(bank-1)*40+32+:8],i_response[(bank-1)*40+:32]);
                    if(i_response[(bank-1)*40+32+:8] == 0) begin
                        if(op == 8'h11) domain_snapshot_valid[bank-1]<=1;
                        if(op == 8'h20) domain_trace_valid[bank-1]<=1;
                        if(op == 8'h32) begin
                            domain_snapshot_valid[bank-1]<=0;
                            domain_trace_valid[bank-1]<=0;
                        end
                    end
                    state<=SEND;
                end else if(timer==TIMEOUT_CYCLES-1) begin
                    tx_frame<=response(seq,op,bank,4,0); state<=SEND;
                    o_timeouts<=o_timeouts+1'b1;
                    domain_snapshot_valid[bank-1]<=0;
                    domain_trace_valid[bank-1]<=0;
                end else timer<=timer+1'b1;
            end
            SEND: if(tx_ready && !tx_enable) begin
                tx_enable<=1; tx_data<=tx_index==12 ? crc : tx_frame[7:0];
                tx_frame<={8'd0,tx_frame[103:8]};
                if(tx_index>=2 && tx_index<12) crc<=crc_next;
                if(tx_index==12) begin state<=RECEIVE; tx_index<=0; timer<=0; end
                else tx_index<=tx_index+1'b1;
            end
            endcase
        end
    end
endmodule
