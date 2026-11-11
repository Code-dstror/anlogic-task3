`timescale 1ns/1ps
module tb_unified_job_uart;
    reg sys=0, pix=0, dfi=0, usr=0, word_clk=0, reset_n=0, dfi_running=1;
    always #5 sys=~sys;
    always #4 pix=~pix;
    always #3 if(dfi_running)dfi=~dfi;
    always #7 usr=~usr;
    always #6 word_clk=~word_clk;
    reg [223:0] dfi_page=(224'd1<<223)|(224'd1<<203)|224'h12345678;
    reg [223:0] pix_page=224'h56780001;
    wire tx;
    uart_status_observer #(.UART_DIV(8),.REPORT_INTERVAL_CYCLES(2048),
        .SNAPSHOT_TIMEOUT_CYCLES(64),.CFG_DIAG_ENABLE(1),.JOB_PAGE_ENABLE(1),
        .CFG_FRAME_VERSION(1),.RX_DIAG_ENABLE(0)) dut(
        .i_sys_clk(sys),.i_sys_rst_n(reset_n),.i_pixel_clk(pix),.i_dfi_clk(dfi),
        .i_user_clk(usr),.i_domain_observer_rst_n({3{reset_n}}),
        .i_domain_reset_n({3{reset_n}}),.i_sys_status(16'd0),.i_domain_flags(36'd0),
        .i_domain_faults(12'd0),.i_domain_progress(6'd0),.i_cfg_domains({pix_page,dfi_page}),
        .i_cfg_domain_reset_n({2{reset_n}}),.i_rx_word_clk(word_clk),.i_rx_domains(384'd0),
        .i_rx_reset_n({3{reset_n}}),.o_trace_request(),.o_trace_index(),.i_trace_ack(1'b0),
        .i_trace_data(320'd0),.o_uart_tx(tx));
    integer fd,round_no,byte_no,bit_no;
    reg [7:0] value;
    initial begin
        fd=$fopen("job_uart.bin","wb");
        if(!fd)$fatal(1,"cannot open binary capture");
        repeat(8)@(negedge sys);
        reset_n=1;
        for(round_no=0;round_no<5;round_no++)begin
            for(byte_no=0;byte_no<97;byte_no++)begin
                @(negedge tx);
                #120; // 1.5 bit periods to data bit zero
                for(bit_no=0;bit_no<8;bit_no++)begin
                    value[bit_no]=tx;
                    #80;
                end
                if(tx!==1'b1 || $isunknown(value))$fatal(1,"invalid serial byte");
                $fwrite(fd,"%c",value);
            end
            if(round_no==0)dfi_running=0;
            if(round_no==2)begin
                dfi_page[31:0]=32'h89abcdef;
                dfi_running=1;
            end
        end
        $fclose(fd);
        $display("PASS UNIFIED_JOB_UART_WIRE");
        $finish;
    end
    initial begin #3000000;$fatal(1,"UART timeout");end
endmodule
