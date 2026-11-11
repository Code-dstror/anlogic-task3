`timescale 1ns/1ps
// Wire-level observer check. The source model is a held four-phase SYS endpoint
// with a stoppable WORD side, not a substitute for the capture-leaf tests.
module uart_rx_trace_tb;
    parameter integer TRACE_ENABLED=1;
    parameter integer REAL_LEAF=0;
    reg sys=0,word_raw=0,rst=0,word_running=0;
    always #20 sys=~sys;
    always #5 word_raw=~word_raw;
    wire word_clk=word_raw&&word_running;
    wire tx,request;
    wire [5:0] index;
    reg ack_word=0;
    reg [1:0] request_sync=0,ack_sync=0;
    reg [319:0] held=0;
    integer requests=0;
    reg [15:0] generation=1;
    reg [255:0] sample_word;
    always @(posedge word_clk or negedge rst)begin
        if(!rst)begin request_sync<=0;ack_word<=0;requests<=0;generation<=1;held<=0;end
        else begin
            request_sync<={request_sync[0],request};
            if(!request_sync[1])ack_word<=0;
            else if(!ack_word)begin
                requests<=requests+1;
                if(requests==4)generation<=2;
                sample_word=0;
                sample_word[31:0]=32'h12345600|index;
                sample_word[63:32]=32'h23456789;
                sample_word[95:64]=32'h3456789a;
                sample_word[127:96]=32'h456789ab;
                sample_word[191:160]=32'hfedc0000|index;
                sample_word[252]=(index==32);
                held<=0;
                held[255:0]<=sample_word;
                held[271:256]<=requests>=4 ? 16'd2 : generation;
                held[303:272]<=requests>=4 ? 32'd200 : 32'd100;
                held[309:304]<=index;
                held[315:310]<=32;
                held[316]<=1;
                held[318]<=index<40;
                held[319]<=1;
                ack_word<=1;
            end
        end
    end
    always @(posedge sys or negedge rst)
        if(!rst)ack_sync<=0;else ack_sync<={ack_sync[0],ack_word};

    // The joint case uses the actual single-clock capture RAM and CDC leaf.
    reg [31:0] live_cycle=0;
    always @(posedge word_clk or negedge rst)
        if(!rst)live_cycle<=0;else live_cycle<=live_cycle+1'b1;
    wire actual_ack;
    wire [319:0] actual_data;
    wire [255:0] actual_sample={3'd0,(live_cycle==50),220'd0,live_cycle};
    rx_first_loss_trace trace_leaf(
        .i_word_clk(word_clk),.i_observer_rst_n(rst),.i_cohort_rst_n(rst),
        .i_enable(1'b1),.i_trigger(live_cycle==50),.i_sample(actual_sample),
        .i_sys_clk(sys),.i_sys_rst_n(rst),.i_request(REAL_LEAF!=0&&request),
        .i_index(index),.o_ack(actual_ack),.o_data(actual_data));
    wire endpoint_ack=REAL_LEAF!=0?actual_ack:ack_sync[1];
    wire [319:0] endpoint_data=REAL_LEAF!=0?actual_data:held;

    uart_status_observer #(.UART_DIV(4),.REPORT_INTERVAL_CYCLES(12000),
        .SNAPSHOT_TIMEOUT_CYCLES(30),.CFG_DIAG_ENABLE(1),.CFG_FRAME_VERSION(2),
        .RX_DIAG_ENABLE(1),.RX_TRACE_ENABLE(TRACE_ENABLED)) dut(
        .i_sys_clk(sys),.i_sys_rst_n(rst),.i_pixel_clk(sys),.i_dfi_clk(sys),.i_user_clk(sys),
        .i_domain_observer_rst_n({3{rst}}),.i_domain_reset_n(3'b111),
        .i_sys_status(16'h1234),.i_domain_flags(36'h5a3_2d4_816),
        .i_domain_faults(12'd0),.i_domain_progress(6'd0),
        .i_cfg_domains(448'd0),.i_cfg_domain_reset_n(2'b11),
        .i_rx_word_clk(word_clk),.i_rx_domains(384'h12345678),.i_rx_reset_n(3'b111),
        .o_trace_request(request),.o_trace_index(index),.i_trace_ack(endpoint_ack),
        .i_trace_data(endpoint_data),.o_uart_tx(tx));

    integer checks=0,frozen_checks=0,late_checks=0;
    reg previous_request=0,previous_ack=0;
    reg [5:0] previous_index=63;
    reg [1:0] previous_phase=0;
    reg [319:0] previous_bank=0;
    always @(negedge sys)if(rst)begin
        checks=checks+1;
        if((previous_request||previous_ack)&&index!==previous_index)
            $fatal(1,"trace index changed during outstanding four-phase transaction");
        if(previous_request&&!request&&!previous_ack)
            $fatal(1,"trace timeout cancelled request before ACK");
        if(request&&!previous_request&&index!==previous_index)
            $fatal(1,"trace index not prepared before request");
        if(previous_phase==1||previous_phase==2)begin
            frozen_checks=frozen_checks+1;
            if(dut.report_trace_data!==previous_bank)$fatal(1,"RT bank changed during FREEZE/SEND");
        end
        if(request&&endpoint_ack&&dut.report_phase==2)late_checks=late_checks+1;
        previous_request=request;previous_ack=endpoint_ack;previous_index=index;
        previous_phase=dut.report_phase;previous_bank=dut.report_trace_data;
    end

    integer fd,at=0,length_=0,frames=0,round_=0,kind=0,rxframes=0,rtframes=0;
    reg [7:0] bytes_[0:67];
    initial begin : receive
        reg [7:0] value;integer bit_,j;
        fd=$fopen($sformatf("uart_trace%0d_leaf%0d.bin",TRACE_ENABLED,REAL_LEAF),"wb");
        forever begin
            @(negedge tx);#240;
            for(bit_=0;bit_<8;bit_=bit_+1)begin value[bit_]=tx;#160;end
            if(tx!==1)$fatal(1,"UART stop bit");
            bytes_[at]=value;$fwrite(fd,"%c",value);
            if(at==1)begin
                if(bytes_[0]=="O"&&value=="B")begin length_=29;if(kind!=0)$fatal(1,"OB order");end
                else if(bytes_[0]=="C"&&value=="G")begin length_=68;if(kind!=1)$fatal(1,"CG order");end
                else if(bytes_[0]=="R"&&value=="X")begin length_=64;if(kind!=2)$fatal(1,"RX order");end
                else if(bytes_[0]=="R"&&value=="T")begin length_=64;if(kind!=3)$fatal(1,"RT order");end
                else $fatal(1,"unknown magic");
            end
            // Resume WORD in the middle of RT0: ACK will arrive during SEND.
            if(TRACE_ENABLED&&kind==3&&round_==0&&at==18)word_running=1;
            if(length_!=0&&at==length_-1)begin
                frames=frames+1;
                if(kind==0)begin
                    if({bytes_[5],bytes_[4]}!==round_)$fatal(1,"OB sequence");
                end else if({bytes_[7],bytes_[6]}!==round_)$fatal(1,"mixed frame sequence");
                if(kind==2)begin
                    rxframes=rxframes+1;
                    if(round_==0&&bytes_[8][0]!==0)$fatal(1,"stopped WORD marked fresh");
                    if(round_>0&&bytes_[8][0]!==1)$fatal(1,"resumed WORD not fresh");
                    if(!TRACE_ENABLED&&round_==0)word_running=1;
                end
                if(kind==3)begin
                    rtframes=rtframes+1;
                    if(round_==0)begin
                        if(bytes_[8]!==0)$fatal(1,"late ACK marked current round fresh");
                        if(!request||!endpoint_ack)$fatal(1,"late ACK was consumed during SEND");
                        for(j=10;j<50;j=j+1)if(bytes_[j]!==0)$fatal(1,"late ACK tore RT0 payload");
                    end else begin
                        if(bytes_[8]!==1)$fatal(1,"available trace not fresh");
                        if(round_==1&&bytes_[48][5:0]!==63)$fatal(1,"late stale ready promoted sample sweep");
                        if(round_==2&&bytes_[48][5:0]!==0)$fatal(1,"ready status did not start index0");
                        if(!REAL_LEAF)begin
                            if(round_==4&&{bytes_[43],bytes_[42]}!==2)$fatal(1,"generation change fixture missing");
                            if(round_==5&&bytes_[48][5:0]!==63)$fatal(1,"generation change did not restart status");
                            if(round_==6&&bytes_[48][5:0]!==0)$fatal(1,"new generation did not restart index0");
                        end
                    end
                end
                if(kind==(TRACE_ENABLED?3:2))begin
                    kind=0;round_=round_+1;
                    if(round_==50)begin
                        if(TRACE_ENABLED&&late_checks==0)$fatal(1,"no late ACK exercised");
                        if(frozen_checks<100)$fatal(1,"no frozen bank coverage");
                        $fclose(fd);
                        $display("RESULT: PASS uart_rx_trace enabled=%0d leaf=%0d frames=%0d checks=%0d frozen=%0d late=%0d",
                            TRACE_ENABLED,REAL_LEAF,frames,checks,frozen_checks,late_checks);
                        $finish;
                    end
                end else kind=kind+1;
                at=0;length_=0;
            end else at=at+1;
        end
    end
    initial begin repeat(10)@(negedge sys);rst=1;end
    initial begin #30000000;$fatal(1,"trace wire watchdog");end
endmodule
