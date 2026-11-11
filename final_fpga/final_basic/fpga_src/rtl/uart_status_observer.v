`timescale 1ns/1ps
`default_nettype none

// TX-only independent diagnostic sink. All outward signals stay inside this
// observer except o_uart_tx. There is deliberately no UART RX or business ACK.
// Packed domain order: PIX=0, DFI=1, USER=2. Business resets are observed only.
module uart_status_observer #(
    parameter integer UART_DIV=217,
    parameter integer REPORT_INTERVAL_CYCLES=25000000,
    parameter integer SNAPSHOT_TIMEOUT_CYCLES=25000,
    parameter integer CFG_DIAG_ENABLE=0,
    parameter integer CFG_FRAME_VERSION=1,
    parameter integer JOB_PAGE_ENABLE=0,
    parameter integer JOB_SYS_CONFIG_ENABLE=0,
    parameter integer RX_DIAG_ENABLE=0,
    parameter integer RX_TRACE_ENABLE=0
) (
    input wire i_sys_clk,
    input wire i_sys_rst_n,
    input wire i_pixel_clk,
    input wire i_dfi_clk,
    input wire i_user_clk,
    input wire [2:0] i_domain_observer_rst_n,
    input wire [2:0] i_domain_reset_n,
    input wire [15:0] i_sys_status,
    input wire [35:0] i_domain_flags,
    input wire [11:0] i_domain_faults,
    input wire [5:0] i_domain_progress,
    input wire [447:0] i_cfg_domains,
    input wire [1:0] i_cfg_domain_reset_n,
    input wire [63:0] i_job_sys_config,
    input wire i_rx_word_clk,
    input wire [383:0] i_rx_domains,
    input wire [2:0] i_rx_reset_n,
    // SYS-domain four-phase endpoint. The leaf owns ACK synchronization and
    // holds this entire bank until request returns low; it has no business ACK.
    output reg o_trace_request,
    output reg [5:0] o_trace_index,
    input wire i_trace_ack,
    input wire [319:0] i_trace_data,
    output wire o_uart_tx
);
    function integer counter_width;
        input integer count;
        integer remaining;
        begin
            counter_width=0;remaining=count-1;
            while(remaining>0)begin counter_width=counter_width+1;remaining=remaining>>1;end
            if(counter_width<1)counter_width=1;
        end
    endfunction
    localparam integer REPORT_WIDTH=counter_width(REPORT_INTERVAL_CYCLES);
    localparam integer TIMEOUT_WIDTH=counter_width(SNAPSHOT_TIMEOUT_CYCLES);
    localparam integer BAUD_WIDTH=counter_width(UART_DIV);
    localparam [1:0] POLL=0,FREEZE=1,SEND=2,IDLE=3;
    localparam [1:0] REQUEST_IDLE=0,WAIT_ACK_HIGH=1,ACK_SETTLE=2,WAIT_ACK_LOW=3;
    reg [1:0] report_phase;
    reg [1:0] snapshot_phase[0:2];
    reg [2:0] request_level;
    wire [2:0] ack_level;
    wire [143:0] source_snapshot;
    wire [2:0] source_clock={i_user_clk,i_dfi_clk,i_pixel_clk};
    genvar g;
    generate for(g=0;g<3;g=g+1)begin:g_domain
        uart_observer_snapshot u_snapshot(
            .i_clk(source_clock[g]),.i_rst_n(i_domain_observer_rst_n[g]),
            .i_request(request_level[g]),.i_flags(i_domain_flags[g*12+:12]),
            .i_faults(i_domain_faults[g*4+:4]),.i_progress(i_domain_progress[g*2+:2]),
            .o_ack(ack_level[g]),.o_snapshot(source_snapshot[g*48+:48]));
    end endgenerate
    // CFG packing is independent of the legacy OB domain order: USER=0, PIX=1.
    reg [1:0] cfg_snapshot_phase[0:1];
    reg [1:0] cfg_request_level;
    wire [1:0] cfg_ack_level;
    wire [447:0] cfg_source_snapshot;
    generate if(CFG_DIAG_ENABLE!=0) begin:g_cfg_diag
        for(g=0;g<2;g=g+1)begin:g_domain
            cfg_diag_snapshot #(.DATA_WIDTH(224)) u_snapshot(
                .i_clk(g==0 ? (JOB_PAGE_ENABLE ? i_dfi_clk : i_user_clk) : i_pixel_clk),
                .i_observer_rst_n(g==0 ? (JOB_PAGE_ENABLE ? i_domain_observer_rst_n[1] : i_domain_observer_rst_n[2]) : i_domain_observer_rst_n[0]),
                .i_request(cfg_request_level[g]),.i_data(i_cfg_domains[g*224+:224]),
                .o_ack(cfg_ack_level[g]),.o_snapshot(cfg_source_snapshot[g*224+:224]));
        end
    end else begin:g_no_cfg_diag
        assign cfg_ack_level=0;
        assign cfg_source_snapshot=0;
    end endgenerate
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] cfg_ack_meta,cfg_ack_sync;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [1:0] cfg_reset_meta,cfg_reset_sync;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] ack_meta,ack_sync;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] reset_meta,reset_sync;
    // These are the sole destination registers of the three held CDC banks.
    // SDC must bound each exact bundled-data path; no per-bit synchronizers.
    reg [143:0] report_domains;
    // Sole SYS destination of the two held CFG banks, frozen through OB+CG TX.
    reg [447:0] report_cfg_domains;
    reg [1:0] cfg_round_fresh,cfg_frame_fresh,cfg_frame_reset;
    reg [2:0] round_fresh,frame_fresh,frame_reset;
    reg [15:0] sequence_count,frame_sequence,frame_sys;
    reg [REPORT_WIDTH-1:0] interval_count;
    reg [TIMEOUT_WIDTH-1:0] timeout_count;
    reg [BAUD_WIDTH-1:0] baud_count;
    reg [9:0] serial_word;
    reg [3:0] bit_index;
    reg [6:0] byte_index;
    reg serial_active;
    reg send_cfg,send_rx,send_trace;
    reg [1:0] trace_snapshot_phase;
    reg trace_index_prepared,trace_round_fresh,trace_frame_fresh;
    reg [5:0] trace_next_index;
    reg [15:0] trace_generation;
    reg trace_generation_known;
    // Only POLL/IDLE may write this report bank. FREEZE/SEND hold all 64B.
    reg [319:0] report_trace_data;
    reg [2:0] rx_request_level,rx_round_fresh,rx_frame_fresh,rx_frame_reset;
    reg [1:0] rx_snapshot_phase[0:2];
    wire [2:0] rx_ack_level;
    wire [383:0] rx_source_snapshot;
    reg [383:0] report_rx_domains;
    (* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] rx_ack_meta,rx_ack_sync,rx_reset_meta,rx_reset_sync;
    generate if(RX_DIAG_ENABLE!=0)begin:g_rx_diag
        wire word_observer_rst_n;
        reset_release_sync u_word_reset(.i_clk(i_rx_word_clk),.i_async_rst_n(i_sys_rst_n),.o_rst_n(word_observer_rst_n));
        for(g=0;g<3;g=g+1)begin:g_domain
            cfg_diag_snapshot #(.DATA_WIDTH(128)) u_snapshot(
                .i_clk(g==0?i_rx_word_clk:g==1?i_sys_clk:i_pixel_clk),
                .i_observer_rst_n(g==0?word_observer_rst_n:g==1?i_sys_rst_n:i_domain_observer_rst_n[0]),
                .i_request(rx_request_level[g]),.i_data(i_rx_domains[g*128+:128]),
                .o_ack(rx_ack_level[g]),.o_snapshot(rx_source_snapshot[g*128+:128]));
        end
    end else begin:g_no_rx_diag
        assign rx_ack_level=0;assign rx_source_snapshot=0;
    end endgenerate
    reg [7:0] crc;
    reg [15:0] cfg_crc;
    integer domain_index;
    assign o_uart_tx=serial_active ? serial_word[0] : 1'b1;

    function [7:0] crc8;
        input [7:0] prior,value;
        reg [7:0] c;
        integer bit_number;
        begin
            c=prior^value;
            for(bit_number=0;bit_number<8;bit_number=bit_number+1)
                c=c[7] ? (c<<1)^8'h07 : c<<1;
            crc8=c;
        end
    endfunction
    function [15:0] crc16;
        input [15:0] prior;
        input [7:0] value;
        reg [15:0] c;
        integer bit_number;
        begin
            c=prior^{value,8'd0};
            for(bit_number=0;bit_number<8;bit_number=bit_number+1)
                c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc16=c;
        end
    endfunction
    reg [7:0] packet_byte;
    always @* begin
        if(send_trace)begin
            packet_byte=0;
            case(byte_index)
                0:packet_byte=8'h52;
                1:packet_byte=8'h54;
                2:packet_byte=1;
                3:packet_byte=1;
                4:packet_byte=64;
                6:packet_byte=frame_sequence[7:0];
                7:packet_byte=frame_sequence[15:8];
                8:packet_byte={7'd0,trace_frame_fresh};
                62:packet_byte=cfg_crc[7:0];
                63:packet_byte=cfg_crc[15:8];
                default:if(byte_index>=10&&byte_index<=49)
                    packet_byte=report_trace_data[(byte_index-10)*8+:8];
            endcase
        end else if(send_rx)begin
            packet_byte=0;
            case(byte_index)
                0:packet_byte=8'h52;
                1:packet_byte=8'h58;
                2:packet_byte=8'd1;
                3:packet_byte=8'd1;
                4:packet_byte=8'd64;
                5:packet_byte=0;
                6:packet_byte=frame_sequence[7:0];
                7:packet_byte=frame_sequence[15:8];
                8:packet_byte={5'd0,rx_frame_fresh};
                9:packet_byte={5'd0,rx_frame_reset};
                62:packet_byte=cfg_crc[7:0];
                63:packet_byte=cfg_crc[15:8];
                default:if(byte_index>=10&&byte_index<=57)packet_byte=report_rx_domains[(byte_index-10)*8+:8];
            endcase
        end else if(send_cfg)begin
            case(byte_index)
                0:packet_byte=JOB_PAGE_ENABLE ? 8'h44 : 8'h43;
                1:packet_byte=JOB_PAGE_ENABLE ? 8'h4a : 8'h47;
                2:packet_byte=CFG_FRAME_VERSION;
                3:packet_byte=8'd1;
                4:packet_byte=8'd68;
                5:packet_byte=8'd0;
                6:packet_byte=frame_sequence[7:0];
                7:packet_byte=frame_sequence[15:8];
                8:packet_byte={6'd0,cfg_frame_fresh};
                9:packet_byte={6'd0,cfg_frame_reset};
                66:packet_byte=cfg_crc[7:0];
                67:packet_byte=cfg_crc[15:8];
                default:begin
                    packet_byte=0;
                    if(byte_index>=10&&byte_index<=65)
                        packet_byte=report_cfg_domains[(byte_index-10)*8+:8];
                end
            endcase
        end else begin
        case(byte_index)
            0:packet_byte=8'h4f;
            1:packet_byte=8'h42;
            2:packet_byte=8'd2;
            3:packet_byte=8'd29;
            4:packet_byte=frame_sequence[7:0];
            5:packet_byte=frame_sequence[15:8];
            6:packet_byte={5'd0,frame_fresh};
            7:packet_byte={5'd0,frame_reset};
            8:packet_byte=frame_sys[7:0];
            9:packet_byte=frame_sys[15:8];
            10:packet_byte=report_domains[7:0];
            11:packet_byte=report_domains[15:8];
            12:packet_byte=report_domains[23:16];
            13:packet_byte=report_domains[31:24];
            14:packet_byte=report_domains[39:32];
            15:packet_byte=report_domains[47:40];
            16:packet_byte=report_domains[55:48];
            17:packet_byte=report_domains[63:56];
            18:packet_byte=report_domains[71:64];
            19:packet_byte=report_domains[79:72];
            20:packet_byte=report_domains[87:80];
            21:packet_byte=report_domains[95:88];
            22:packet_byte=report_domains[103:96];
            23:packet_byte=report_domains[111:104];
            24:packet_byte=report_domains[119:112];
            25:packet_byte=report_domains[127:120];
            26:packet_byte=report_domains[135:128];
            27:packet_byte=report_domains[143:136];
            28:packet_byte=crc;
            default:packet_byte=0;
        endcase
        end
    end
    generate if(UART_DIV<2||REPORT_INTERVAL_CYCLES<1||SNAPSHOT_TIMEOUT_CYCLES<2)begin:g_invalid_parameters
        UART_OBSERVER_REQUIRES_POSITIVE_TIMERS invalid_configuration();
    end endgenerate

    always @(posedge i_sys_clk or negedge i_sys_rst_n) begin
        if(!i_sys_rst_n)begin
            report_phase<=POLL;request_level<=0;ack_meta<=0;ack_sync<=0;
            reset_meta<=0;reset_sync<=0;report_domains<=0;
            cfg_request_level<=0;cfg_ack_meta<=0;cfg_ack_sync<=0;
            cfg_reset_meta<=0;cfg_reset_sync<=0;report_cfg_domains<=0;
            cfg_round_fresh<=0;cfg_frame_fresh<=0;cfg_frame_reset<=0;
            round_fresh<=0;frame_fresh<=0;frame_reset<=0;
            sequence_count<=0;frame_sequence<=0;frame_sys<=0;
            interval_count<=0;timeout_count<=0;baud_count<=0;
            serial_word<=10'h3ff;bit_index<=0;byte_index<=0;serial_active<=0;crc<=0;
            send_cfg<=0;send_rx<=0;send_trace<=0;cfg_crc<=16'hffff;
            o_trace_request<=0;o_trace_index<=63;trace_next_index<=63;
            trace_snapshot_phase<=REQUEST_IDLE;trace_index_prepared<=0;
            trace_round_fresh<=0;trace_frame_fresh<=0;report_trace_data<=0;
            trace_generation<=0;trace_generation_known<=0;
            rx_request_level<=0;rx_round_fresh<=0;rx_frame_fresh<=0;rx_frame_reset<=0;
            rx_ack_meta<=0;rx_ack_sync<=0;rx_reset_meta<=0;rx_reset_sync<=0;report_rx_domains<=0;
            for(domain_index=0;domain_index<3;domain_index=domain_index+1)rx_snapshot_phase[domain_index]<=REQUEST_IDLE;
            for(domain_index=0;domain_index<3;domain_index=domain_index+1)
                snapshot_phase[domain_index]<=REQUEST_IDLE;
            for(domain_index=0;domain_index<2;domain_index=domain_index+1)
                cfg_snapshot_phase[domain_index]<=REQUEST_IDLE;
        end else begin
            ack_meta<=ack_level;ack_sync<=ack_meta;
            rx_ack_meta<=rx_ack_level;rx_ack_sync<=rx_ack_meta;
            rx_reset_meta<=RX_DIAG_ENABLE!=0?i_rx_reset_n:3'd0;rx_reset_sync<=rx_reset_meta;
            reset_meta<=i_domain_reset_n;reset_sync<=reset_meta;
            cfg_ack_meta<=cfg_ack_level;cfg_ack_sync<=cfg_ack_meta;
            cfg_reset_meta<=CFG_DIAG_ENABLE!=0 ? i_cfg_domain_reset_n : 2'b00;
            cfg_reset_sync<=cfg_reset_meta;
            if(interval_count<REPORT_INTERVAL_CYCLES-1)interval_count<=interval_count+1'b1;
            case(report_phase)
                POLL:begin
                    if((round_fresh==3'b111&&(CFG_DIAG_ENABLE==0||cfg_round_fresh==2'b11)&&(RX_DIAG_ENABLE==0||rx_round_fresh==3'b111)&&
                        (RX_TRACE_ENABLE==0||trace_round_fresh))||
                        timeout_count==SNAPSHOT_TIMEOUT_CYCLES-1)
                        report_phase<=FREEZE;
                    else timeout_count<=timeout_count+1'b1;
                end
                FREEZE:begin
                    // The previous POLL edge may capture its final ACK. This
                    // extra edge freezes matching metadata before the first bit.
                    frame_fresh<=round_fresh;frame_reset<=reset_sync;frame_sys<=i_sys_status;
                    cfg_frame_fresh<=cfg_round_fresh;cfg_frame_reset<=cfg_reset_sync;
                    if(JOB_PAGE_ENABLE!=0&&JOB_SYS_CONFIG_ENABLE!=0)
                        report_cfg_domains[320+:64]<=i_job_sys_config;
                    rx_frame_fresh<=rx_round_fresh;rx_frame_reset<=rx_reset_sync;
                    trace_frame_fresh<=trace_round_fresh;
                    frame_sequence<=sequence_count;sequence_count<=sequence_count+1'b1;
                    byte_index<=0;crc<=0;report_phase<=SEND;
                    send_cfg<=0;send_rx<=0;send_trace<=0;cfg_crc<=16'hffff;
                end
                SEND:begin
                    if(!serial_active)begin
                        serial_word<={1'b1,packet_byte,1'b0};serial_active<=1;
                        bit_index<=0;baud_count<=0;
                        if(send_rx||send_trace)begin
                            if(byte_index<62)cfg_crc<=crc16(cfg_crc,packet_byte);
                        end else if(send_cfg)begin
                            if(byte_index<66)cfg_crc<=crc16(cfg_crc,packet_byte);
                        end else if(byte_index<28)crc<=crc8(crc,packet_byte);
                    end else if(baud_count==UART_DIV-1)begin
                        baud_count<=0;
                        if(bit_index==9)begin
                            serial_active<=0;
                            if(!send_cfg&&!send_rx&&!send_trace&&byte_index==28)begin
                                if(CFG_DIAG_ENABLE!=0)begin
                                    send_cfg<=1;byte_index<=0;cfg_crc<=16'hffff;
                                end else if(RX_DIAG_ENABLE!=0)begin send_rx<=1;byte_index<=0;cfg_crc<=16'hffff;end
                                else if(RX_TRACE_ENABLE!=0)begin send_trace<=1;byte_index<=0;cfg_crc<=16'hffff;end
                                else report_phase<=IDLE;
                            end else if(send_cfg&&byte_index==67)begin
                                if(RX_DIAG_ENABLE!=0)begin send_cfg<=0;send_rx<=1;byte_index<=0;cfg_crc<=16'hffff;end
                                else if(RX_TRACE_ENABLE!=0)begin send_cfg<=0;send_trace<=1;byte_index<=0;cfg_crc<=16'hffff;end
                                else report_phase<=IDLE;
                            end else if(send_rx&&byte_index==63)begin
                                if(RX_TRACE_ENABLE!=0)begin send_rx<=0;send_trace<=1;byte_index<=0;cfg_crc<=16'hffff;end
                                else report_phase<=IDLE;
                            end else if(send_trace&&byte_index==63)report_phase<=IDLE;
                            else byte_index<=byte_index+1'b1;
                        end else begin
                            serial_word<={1'b1,serial_word[9:1]};bit_index<=bit_index+1'b1;
                        end
                    end else baud_count<=baud_count+1'b1;
                end
                IDLE:if(interval_count==REPORT_INTERVAL_CYCLES-1)begin
                    report_phase<=POLL;round_fresh<=0;timeout_count<=0;interval_count<=0;
                    cfg_round_fresh<=0;rx_round_fresh<=0;trace_round_fresh<=0;
                end
                default:report_phase<=IDLE;
            endcase
            if(RX_TRACE_ENABLE!=0)begin
                case(trace_snapshot_phase)
                    REQUEST_IDLE:if(report_phase==POLL&&!trace_round_fresh&&!i_trace_ack)begin
                        // The mux address is stable a full SYS cycle before REQ.
                        if(!trace_index_prepared)begin
                            o_trace_index<=trace_next_index;trace_index_prepared<=1;
                        end else begin
                            o_trace_request<=1;trace_index_prepared<=0;
                            trace_snapshot_phase<=WAIT_ACK_HIGH;
                        end
                    end
                    WAIT_ACK_HIGH:if(i_trace_ack)trace_snapshot_phase<=ACK_SETTLE;
                    ACK_SETTLE:if(!i_trace_ack)trace_snapshot_phase<=WAIT_ACK_HIGH;
                        else if(report_phase==POLL||report_phase==IDLE)begin
                            report_trace_data<=i_trace_data;
                            if(report_phase==POLL)trace_round_fresh<=1;
                            // An IDLE/late result is retained as raw stale data,
                            // but cannot promote ready or advance the read sweep.
                            if(report_phase!=POLL||!i_trace_data[316])
                                trace_next_index<=63;
                            else if(o_trace_index==63)trace_next_index<=0;
                            else if(!trace_generation_known||trace_generation!=i_trace_data[271:256])
                                trace_next_index<=63;
                            else if(o_trace_index==39)trace_next_index<=0;
                            else trace_next_index<=o_trace_index+1'b1;
                            trace_generation<=i_trace_data[271:256];trace_generation_known<=1;
                            o_trace_request<=0;trace_snapshot_phase<=WAIT_ACK_LOW;
                        end
                    WAIT_ACK_LOW:if(!i_trace_ack)trace_snapshot_phase<=REQUEST_IDLE;
                    default:begin o_trace_request<=0;trace_snapshot_phase<=REQUEST_IDLE;end
                endcase
            end
            // Four-phase observer handshake. Timeout never drops/retries an
            // outstanding request. Late ACKs remain held during SEND/FREEZE;
            // this freezes every payload byte without a duplicate frame RAM.
            for(domain_index=0;domain_index<3;domain_index=domain_index+1)begin
                case(snapshot_phase[domain_index])
                    REQUEST_IDLE:if(report_phase==POLL&&!round_fresh[domain_index]&&!ack_sync[domain_index])begin
                        request_level[domain_index]<=1;snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                    end
                    WAIT_ACK_HIGH:if(ack_sync[domain_index])snapshot_phase[domain_index]<=ACK_SETTLE;
                    ACK_SETTLE:begin
                        if(!ack_sync[domain_index])snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                        else if(report_phase==POLL||report_phase==IDLE)begin
                            report_domains[domain_index*48+:48]<=source_snapshot[domain_index*48+:48];
                            if(report_phase==POLL)round_fresh[domain_index]<=1;
                            request_level[domain_index]<=0;snapshot_phase[domain_index]<=WAIT_ACK_LOW;
                        end
                    end
                    WAIT_ACK_LOW:if(!ack_sync[domain_index])snapshot_phase[domain_index]<=REQUEST_IDLE;
                    default:begin request_level[domain_index]<=0;snapshot_phase[domain_index]<=REQUEST_IDLE;end
                endcase
            end
            if(RX_DIAG_ENABLE!=0)begin
                for(domain_index=0;domain_index<3;domain_index=domain_index+1)begin
                    case(rx_snapshot_phase[domain_index])
                        REQUEST_IDLE:if(report_phase==POLL&&!rx_round_fresh[domain_index]&&!rx_ack_sync[domain_index])begin
                            rx_request_level[domain_index]<=1;rx_snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                        end
                        WAIT_ACK_HIGH:if(rx_ack_sync[domain_index])rx_snapshot_phase[domain_index]<=ACK_SETTLE;
                        ACK_SETTLE:if(!rx_ack_sync[domain_index])rx_snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                            else if(report_phase==POLL||report_phase==IDLE)begin
                                report_rx_domains[domain_index*128+:128]<=rx_source_snapshot[domain_index*128+:128];
                                if(report_phase==POLL)rx_round_fresh[domain_index]<=1;
                                rx_request_level[domain_index]<=0;rx_snapshot_phase[domain_index]<=WAIT_ACK_LOW;
                            end
                        WAIT_ACK_LOW:if(!rx_ack_sync[domain_index])rx_snapshot_phase[domain_index]<=REQUEST_IDLE;
                        default:begin rx_request_level[domain_index]<=0;rx_snapshot_phase[domain_index]<=REQUEST_IDLE;end
                    endcase
                end
            end
            // Same bounded POLL and four-phase contract as the legacy banks.
            // Late ACKs stay outstanding throughout both wire frames.
            if(CFG_DIAG_ENABLE!=0)begin
                for(domain_index=0;domain_index<2;domain_index=domain_index+1)begin
                    case(cfg_snapshot_phase[domain_index])
                        REQUEST_IDLE:if(report_phase==POLL&&!cfg_round_fresh[domain_index]&&!cfg_ack_sync[domain_index])begin
                            cfg_request_level[domain_index]<=1;
                            cfg_snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                        end
                        WAIT_ACK_HIGH:if(cfg_ack_sync[domain_index])cfg_snapshot_phase[domain_index]<=ACK_SETTLE;
                        ACK_SETTLE:begin
                            if(!cfg_ack_sync[domain_index])cfg_snapshot_phase[domain_index]<=WAIT_ACK_HIGH;
                            else if(report_phase==POLL||report_phase==IDLE)begin
                                report_cfg_domains[domain_index*224+:224]<=cfg_source_snapshot[domain_index*224+:224];
                                if(report_phase==POLL)cfg_round_fresh[domain_index]<=1;
                                cfg_request_level[domain_index]<=0;
                                cfg_snapshot_phase[domain_index]<=WAIT_ACK_LOW;
                            end
                        end
                        WAIT_ACK_LOW:if(!cfg_ack_sync[domain_index])cfg_snapshot_phase[domain_index]<=REQUEST_IDLE;
                        default:begin cfg_request_level[domain_index]<=0;cfg_snapshot_phase[domain_index]<=REQUEST_IDLE;end
                    endcase
                end
            end
        end
    end
endmodule
`default_nettype wire
