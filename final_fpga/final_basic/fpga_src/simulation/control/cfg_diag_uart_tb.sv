`timescale 1ns/1ps
module cfg_diag_uart_tb;
    wire o_trace_request; wire [5:0] o_trace_index;
    wire i_trace_ack=0; wire [319:0] i_trace_data=0;
    wire i_rx_word_clk=0; wire [383:0] i_rx_domains=0; wire [2:0] i_rx_reset_n=0;
    parameter integer CFG_TEST_VERSION=2;
    localparam integer DIV=4,BIT_NS=160;
    reg i_sys_clk=0,pixel_raw=0,dfi_raw=0,user_raw=0;
    always #20 i_sys_clk=~i_sys_clk;
    always #4 pixel_raw=~pixel_raw;
    always #3.75 dfi_raw=~dfi_raw;
    always #7 user_raw=~user_raw;
    reg pixel_running=1,user_running=0;
    wire i_pixel_clk=pixel_raw&&pixel_running;
    wire i_dfi_clk=dfi_raw;
    wire i_user_clk=user_raw&&user_running;
    reg i_sys_rst_n=0;
    wire [2:0] i_domain_observer_rst_n;
    reset_release_sync rp(i_pixel_clk,i_sys_rst_n,i_domain_observer_rst_n[0]);
    reset_release_sync rd(i_dfi_clk,i_sys_rst_n,i_domain_observer_rst_n[1]);
    reset_release_sync ru(i_user_clk,i_sys_rst_n,i_domain_observer_rst_n[2]);
    reg [2:0] i_domain_reset_n=7;
    wire [15:0] i_sys_status=16'h25a7;
    wire [35:0] i_domain_flags=36'habc123def;
    wire [11:0] i_domain_faults=0;
    wire [5:0] i_domain_progress=0;
    wire [447:0] i_cfg_domains;
    reg [1:0] i_cfg_domain_reset_n=3;
    reg [4:0] cause_values=0;
    wire o_uart_tx;
    uart_status_observer #(.UART_DIV(DIV),.REPORT_INTERVAL_CYCLES(5000),
        .SNAPSHOT_TIMEOUT_CYCLES(30),.CFG_DIAG_ENABLE(1),.CFG_FRAME_VERSION(CFG_TEST_VERSION)) dut(.*);
    function automatic [31:0] pattern_word(input [31:0] seed,input integer index);
        pattern_word=seed^(32'h19876543*index);
    endfunction
    wire [1:0] clocks={i_pixel_clk,i_user_clk};
    genvar g,w;
    generate for(g=0;g<2;g=g+1)begin:patterns
        reg [31:0] seed=32'h12340000+g;
        always @(posedge clocks[g])seed<=seed+32'h1020301;
        for(w=0;w<7;w=w+1)begin:words
            wire [31:0] pattern=pattern_word(seed,w);
            if(g==1&&w==5)
                assign i_cfg_domains[g*224+w*32+:32]=(pattern&32'h83ffffff)|({27'd0,cause_values}<<26);
            else assign i_cfg_domains[g*224+w*32+:32]=pattern;
        end
    end endgenerate

    integer checks=0,ob_frames=0,cg_frames=0,fd,index=0,length=0,bit_number,j,d,k;
    integer expected_sequence=0,previous_frames;
    reg [7:0] packet[0:67],value,c8;
    reg [15:0] c16,last_ob_sequence;
    reg [1:0] last_fresh=0,last_reset=0;
    reg [4:0] last_causes=0;
    reg expect_cg=0,valid_byte;
    reg [31:0] seed,word_value;
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"cfg_diag_uart: %s",why);end
    endtask
    function automatic [7:0] crc8(input [7:0] prior,input [7:0] byte_value);
        reg [7:0] c;integer n;
        begin c=prior^byte_value;for(n=0;n<8;n=n+1)c=c[7]?(c<<1)^8'h07:c<<1;crc8=c;end
    endfunction
    function automatic [15:0] crc16(input [15:0] prior,input [7:0] byte_value);
        reg [15:0] c;integer n;
        begin c=prior^{byte_value,8'd0};for(n=0;n<8;n=n+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
    endfunction
    function automatic [31:0] packet_word(input integer offset);
        packet_word={packet[offset+3],packet[offset+2],packet[offset+1],packet[offset]};
    endfunction
    always @(negedge i_sys_rst_n)begin index=0;length=0;expect_cg=0;expected_sequence=0;end
    initial begin
        fd=$fopen("cfg_diag_wire.bin","wb");check(fd!=0,"open wire file");
        forever begin
            @(negedge o_uart_tx);
            if(i_sys_rst_n)begin
                valid_byte=1;value=0;
                #(BIT_NS/2);if(!i_sys_rst_n)valid_byte=0;
                if(valid_byte)check(!o_uart_tx,"start bit");
                for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
                    #BIT_NS;if(!i_sys_rst_n)valid_byte=0;value[bit_number]=o_uart_tx;
                end
                #BIT_NS;if(!i_sys_rst_n)valid_byte=0;
                if(valid_byte)begin
                    check(o_uart_tx,"stop bit");packet[index]=value;
                    if(index==1)begin
                        if(packet[0]==8'h4f&&value==8'h42)length=29;
                        else if(packet[0]==8'h43&&value==8'h47)length=68;
                        else $fatal(1,"unexpected UART magic");
                    end
                    if(length!=0&&index==length-1)begin
                        if(length==29)begin
                            check(!expect_cg,"OB/CG pair is not interleaved");
                            check(packet[2]==2&&packet[3]==29,"unchanged OB header");
                            check({packet[5],packet[4]}==16'(expected_sequence),"OB sequence");
                            check(packet[6][7:3]==0&&packet[7][7:3]==0,"OB reserved mask");
                            check({packet[9],packet[8]}==i_sys_status,"unchanged OB sys flags");
                            for(d=0;d<3;d=d+1)begin
                                if(packet[6][d])check({packet[11+d*6],packet[10+d*6]}=={4'd0,i_domain_flags[d*12+:12]},"unchanged OB status byte order");
                                check(packet_word(12+d*6)==0,"unchanged OB event counters");
                            end
                            c8=0;for(j=0;j<28;j=j+1)c8=crc8(c8,packet[j]);
                            check(packet[28]==c8,"OB CRC8");
                            last_ob_sequence=16'(expected_sequence);expected_sequence=expected_sequence+1;
                            expect_cg=1;ob_frames=ob_frames+1;
                        end else begin
                            check(expect_cg,"CG follows its OB");
                            check(packet[2]==CFG_TEST_VERSION&&packet[3]==1&&packet[4]==68&&packet[5]==0,"CG header version actual wire byte");
                            check({packet[7],packet[6]}==last_ob_sequence,"same report sequence");
                            check(packet[8][7:2]==0&&packet[9][7:2]==0,"CG reserved masks");
                            c16=16'hffff;for(j=0;j<66;j=j+1)c16=crc16(c16,packet[j]);
                            check({packet[67],packet[66]}==c16,"independent CG CRC16");
                            for(d=0;d<2;d=d+1)if(packet[8][d])begin
                                seed=packet_word(10+d*28);
                                for(k=0;k<7;k=k+1)begin
                                    word_value=packet_word(10+d*28+k*4);
                                    if(d==1&&k==5)begin
                                        check((word_value&32'h83ffffff)===(pattern_word(seed,k)&32'h83ffffff),"PIX flags preserve non-cause bits of atomic bank");
                                        last_causes=word_value[30:26];
                                    end else check(word_value===pattern_word(seed,k),"all seven source words are one atomic bank");
                                end
                            end
                            last_fresh=packet[8][1:0];last_reset=packet[9][1:0];
                            expect_cg=0;cg_frames=cg_frames+1;
                        end
                        for(j=0;j<length;j=j+1)$fwrite(fd,"%c",packet[j]);
                        index=0;length=0;
                    end else index=index+1;
                end
                #(BIT_NS/2);
            end
        end
    end
    task next_pair;
        begin previous_frames=cg_frames;wait(cg_frames>previous_frames);#1;end
    endtask

    // Standalone mailbox scoreboarding uses sampled source input, not DUT
    // diagnostic state. Business reset has no connection to the mailbox.
    reg unit_request=0;
    wire unit_ack;
    wire [223:0] unit_snapshot;
    reg [223:0] held_bank,expected_bank;
    integer held_checks=0,captures=0;
    cfg_diag_snapshot #(.DATA_WIDTH(224)) unit_bank(.i_clk(i_pixel_clk),
        .i_observer_rst_n(i_domain_observer_rst_n[0]),.i_request(unit_request),
        .i_data(i_cfg_domains[447:224]),.o_ack(unit_ack),.o_snapshot(unit_snapshot));
    reg capture_now,hold_now;
    always @(posedge i_pixel_clk)begin
        capture_now=i_domain_observer_rst_n[0]&&unit_bank.request_sync[1]&&!unit_ack;
        hold_now=i_domain_observer_rst_n[0]&&unit_ack&&unit_bank.request_sync[1];
        expected_bank=i_cfg_domains[447:224];held_bank=unit_snapshot;
        #1;
        if(capture_now)begin captures=captures+1;check(unit_snapshot===expected_bank,"mailbox captures exact source edge");end
        if(hold_now)begin held_checks=held_checks+1;check(unit_snapshot===held_bank,"held mailbox is immutable");end
    end
    initial begin
        integer cause_index;
        repeat(10)@(negedge i_sys_clk);i_sys_rst_n=1;
        next_pair();check(last_fresh==2'b10,"cold stopped USER is unavailable, PIX fresh");
        next_pair();check(last_fresh==2'b10,"pending USER request is not forged fresh");
        @(negedge user_raw);user_running=1;
        next_pair();if(last_fresh!=3)next_pair();check(last_fresh==3,"late USER ACK recovers");
        // Change the five live inputs independently and clear them again.
        // Two rounds allow a previously held sample to drain before checking.
        for(cause_index=0;cause_index<7;cause_index=cause_index+1)begin
            cause_values=cause_index<5 ? (5'b00001<<cause_index) : (cause_index==5 ? 5'b11111 : 5'b00000);
            next_pair();next_pair();
            check(last_fresh[1]&&last_causes==cause_values,"all five live cause inputs serialize without aliasing or stickiness");
        end
        unit_request=1;wait(unit_ack);repeat(30)@(negedge i_pixel_clk);
        i_cfg_domain_reset_n=2;next_pair();next_pair();
        check(last_fresh==3&&last_reset==2,"business reset reports a fresh reset-domain snapshot");
        check(held_checks>100,"many held-bank checks during business reset");
        unit_request=0;wait(!unit_ack);
        i_cfg_domain_reset_n=3;
        @(negedge pixel_raw);pixel_running=0;
        next_pair();next_pair();check(!last_fresh[1],"stopped PIX cannot claim fresh repeatedly");
        @(negedge pixel_raw);pixel_running=1;
        next_pair();if(last_fresh!=3)next_pair();check(last_fresh==3,"stopped PIX recovery");
        wait(dut.serial_active);#3;i_sys_rst_n=0;
        #1;check(o_uart_tx,"cold reset idles interrupted TX");
        #(BIT_NS*20);i_sys_rst_n=1;
        next_pair();check(last_ob_sequence==0&&last_fresh==3,"cold reset restarts intact pair at sequence zero");
        next_pair();check(captures>0&&held_checks>100,"mailbox assertions executed");
        $fclose(fd);
        $display("RESULT: PASS cfg_diag_uart version=%0d checks=%0d ob_frames=%0d cfg_frames=%0d captures=%0d held_checks=%0d",CFG_TEST_VERSION,checks,ob_frames,cg_frames,captures,held_checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"CFG UART watchdog");end
endmodule
