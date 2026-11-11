`timescale 1ns/1ps
// Existing production OB/CGv2/RX combination; RT is tied off exactly as top.
module tb_uart_no_rt;
    reg sys=0,pixel_raw=0,dfi_raw=0,user_raw=0,word_raw=0;
    always #20 sys=~sys;
    always #4 pixel_raw=~pixel_raw;
    always #3.75 dfi_raw=~dfi_raw;
    always #5 user_raw=~user_raw;
    always #5 word_raw=~word_raw;
    reg word_running=0,user_running=0,rst=0;
    wire pixel=pixel_raw,dfi=dfi_raw,user_clk=user_raw&&user_running,word_clk=word_raw&&word_running;
    wire [2:0] observer_reset_n;
    reset_release_sync rp(pixel,rst,observer_reset_n[0]);
    reset_release_sync rd(dfi,rst,observer_reset_n[1]);
    reset_release_sync ru(user_clk,rst,observer_reset_n[2]);
    reg [2:0] business_reset_n=7,rx_reset_n=7;
    reg [447:0] cfg_data={14{32'h12345678}};
    reg [383:0] rx_data={32'h52544347,32'h12345678,32'h89abcdef,32'h76543210,
        32'hdeadc0de,32'habcd0123,32'h1234abcd,32'h90abcdef,32'd9,32'd8,32'd7,32'd6};
    wire tx;
    uart_status_observer #(.UART_DIV(4),.REPORT_INTERVAL_CYCLES(8000),
        .SNAPSHOT_TIMEOUT_CYCLES(30),.CFG_DIAG_ENABLE(1),.CFG_FRAME_VERSION(2),
        .RX_DIAG_ENABLE(1),.RX_TRACE_ENABLE(0)) dut(
        .i_sys_clk(sys),.i_sys_rst_n(rst),.i_pixel_clk(pixel),.i_dfi_clk(dfi),.i_user_clk(user_clk),
        .i_domain_observer_rst_n(observer_reset_n),.i_domain_reset_n(business_reset_n),
        .i_sys_status(16'h1234),.i_domain_flags(36'h5a3_2d4_816),.i_domain_faults(12'd0),.i_domain_progress(6'd0),
        .i_cfg_domains(cfg_data),.i_cfg_domain_reset_n(2'b11),
        .i_rx_word_clk(word_clk),.i_rx_domains(rx_data),.i_rx_reset_n(rx_reset_n),
        .o_trace_request(),.o_trace_index(),.i_trace_ack(1'b0),.i_trace_data(320'd0),.o_uart_tx(tx));

    function automatic [7:0] crc8(input [7:0] old,input [7:0] b);
        reg [7:0] c;integer k;
        begin c=old^b;for(k=0;k<8;k=k+1)c=c[7]?(c<<1)^8'h07:c<<1;crc8=c;end
    endfunction
    function automatic [15:0] crc16(input [15:0] old,input [7:0] b);
        reg [15:0] c;integer k;
        begin c=old^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
    endfunction
    integer checks=0,frozen_checks=0;
    reg [143:0] previous_ob;
    reg [447:0] previous_cfg;
    reg [383:0] previous_rx;
    reg was_sending;
    always @(posedge sys)begin
        was_sending=rst&&dut.report_phase==2;
        previous_ob=dut.report_domains;previous_cfg=dut.report_cfg_domains;previous_rx=dut.report_rx_domains;
        #0.1;
        if(rst&&(dut.o_trace_request||dut.send_trace))$fatal(1,"disabled RT path became active");
        if(was_sending)begin
            frozen_checks=frozen_checks+1;
            if({dut.report_domains,dut.report_cfg_domains,dut.report_rx_domains}!==
               {previous_ob,previous_cfg,previous_rx})$fatal(1,"mixed snapshot changed during SEND");
        end
    end

    integer fd,at=0,len=0,kind=0,round_id=0,frames=0,expected_sequence=0,reset_epochs=0;
    integer ob_unavailable=0,rx_unavailable=0,fully_fresh=0,business_reset_reports=0;
    reg [7:0] bytes_[0:67];
    initial begin : receive
        reg [7:0] b,c8;reg [15:0] c16;integer bit_id,j;
        fd=$fopen("uart_no_rt.bin","wb");
        forever begin
            @(negedge tx);#240;
            for(bit_id=0;bit_id<8;bit_id=bit_id+1)begin b[bit_id]=tx;#160;end
            if(tx!==1)$fatal(1,"UART stop bit");
            bytes_[at]=b;$fwrite(fd,"%c",b);
            if(at==1)begin
                if(bytes_[0]=="O"&&b=="B")begin len=29;if(kind!=0)$fatal(1,"OB order");end
                else if(bytes_[0]=="C"&&b=="G")begin len=68;if(kind!=1)$fatal(1,"CG order");end
                else if(bytes_[0]=="R"&&b=="X")begin len=64;if(kind!=2)$fatal(1,"RX order");end
                else $fatal(1,"unexpected magic including retired RT");
            end
            if(len!=0&&at==len-1)begin
                frames=frames+1;checks=checks+1;
                if(kind==0)begin
                    if(bytes_[2]!=2||bytes_[3]!=29||{bytes_[5],bytes_[4]}!==expected_sequence[15:0])$fatal(1,"OB schema/sequence");
                    c8=0;for(j=0;j<28;j=j+1)c8=crc8(c8,bytes_[j]);
                    if(bytes_[28]!==c8)$fatal(1,"OB CRC8");
                    if(bytes_[6][2:0]!=7)ob_unavailable=ob_unavailable+1;
                    if(bytes_[7][2:0]!=7)business_reset_reports=business_reset_reports+1;
                end else begin
                    if({bytes_[7],bytes_[6]}!==expected_sequence[15:0])$fatal(1,"same-round sequence");
                    c16=16'hffff;for(j=0;j<len-2;j=j+1)c16=crc16(c16,bytes_[j]);
                    if({bytes_[len-1],bytes_[len-2]}!==c16)$fatal(1,"CG/RX CRC16");
                    if(kind==1&&(bytes_[2]!=2||bytes_[3]!=1||bytes_[4]!=68||bytes_[5]!=0))$fatal(1,"CGv2 schema");
                    if(kind==2)begin
                        if(bytes_[2]!=1||bytes_[3]!=1||bytes_[4]!=64||bytes_[5]!=0)$fatal(1,"RX schema");
                        if(bytes_[8][0]==0)rx_unavailable=rx_unavailable+1;
                        if(bytes_[8][2:0]==7)fully_fresh=fully_fresh+1;
                        if((round_id==0||round_id==3||round_id==6)&&bytes_[8][0]!==0)$fatal(1,"stopped WORD marked fresh");
                        if((round_id==2||round_id==5||round_id==8)&&bytes_[8][2:0]!==7)$fatal(1,"resumed WORD did not recover");
                    end
                end
                if(kind==2)begin
                    expected_sequence=expected_sequence+1;kind=0;round_id=round_id+1;
                    case(round_id)
                        1:begin word_running=1;user_running=1;end
                        3:begin word_running=0;user_running=0;business_reset_n=3;rx_reset_n=6;end
                        4:begin word_running=1;user_running=1;business_reset_n=7;rx_reset_n=7;
                            cfg_data={14{32'h87654321}};rx_data={12{32'h52544347}};end
                        6:begin
                            word_running=0;rst=0;#0.1;
                            if(tx!==1||dut.o_trace_request)$fatal(1,"cold reset did not isolate UART");
                            #160;rst=1;expected_sequence=0;reset_epochs=reset_epochs+1;
                        end
                        7:word_running=1;
                        9:begin
                            if(ob_unavailable<2||rx_unavailable<3||fully_fresh<3||business_reset_reports<1||reset_epochs!=1)
                                $fatal(1,"missing stopped clock/reset coverage");
                            $fclose(fd);
                            $display("RESULT: PASS uart_no_rt OB=9 CGv2=9 RX=9 RT=0 checks=%0d frozen=%0d unavailable_ob=%0d unavailable_rx=%0d fresh_rx=%0d business_reset=%0d cold_reset=%0d",
                                checks,frozen_checks,ob_unavailable,rx_unavailable,fully_fresh,business_reset_reports,reset_epochs);
                            $finish;
                        end
                    endcase
                end else kind=kind+1;
                at=0;len=0;
            end else at=at+1;
        end
    end
    initial begin repeat(10)@(negedge sys);rst=1;end
    initial begin #5000000;$fatal(1,"UART no-RT watchdog");end
endmodule
