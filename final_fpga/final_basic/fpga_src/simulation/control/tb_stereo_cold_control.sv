`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"
`include "stereo_control_v1.vh"
module tb_stereo_cold_control;
    reg user_clk=0,pixel_clk=0,dfi_clk=0,pixel_run=1,dfi_run=1;
    always #5 user_clk=~user_clk;
    always #7 if(pixel_run)pixel_clk=~pixel_clk;
    always #11 if(dfi_run)dfi_clk=~dfi_clk;
    reg user_rst_n=0,pixel_rst_n=0,dfi_rst_n=0;
    reg write_valid=0,read_valid=0;
    reg [11:0] write_offset=0,read_offset=0;
    reg [31:0] write_data=0;reg [3:0] write_strobes=0;
    wire [1:0] write_response,read_response;
    wire read_response_valid;wire [31:0] read_data;
    reg i_app_enable=0,i_c2h_running=0,i_user_config_idle=1,i_pixel_quiet=1,i_dfi_quiet=1;
    wire o_user_busy,o_user_locked,o_user_mode,o_user_start_inhibit;
    wire o_pixel_mode,o_dfi_mode,o_pixel_pause,o_dfi_pause;
    wire [7:0] o_user_frame_divisor,o_pixel_frame_divisor,o_dfi_frame_divisor;
    integer checks=0;
    stereo_cold_control dut(.*);
    task automatic check(input bit condition,input string message);
        begin checks++;if(!condition)$fatal(1,"STEREO_CONTROL %s t=%0t",message,$time);end
    endtask
    task automatic clocks(input integer count);
        repeat(count)@(negedge user_clk);
    endtask
    task automatic write(input [11:0] address,input [31:0] value,input [3:0] strobes,input [1:0] response);
        begin
            @(negedge user_clk);write_offset=address;write_data=value;write_strobes=strobes;write_valid=1;
            #1;check(write_response==response,"write response exact");
            @(negedge user_clk);write_valid=0;
        end
    endtask
    task automatic read(input [11:0] address,input [31:0] expected,input [1:0] response);
        begin
            @(negedge user_clk);read_offset=address;read_valid=1;
            @(posedge user_clk);#1;
            check(read_response_valid&&read_response==response,"one registered read response");
            if(response==0)check(read_data==expected,"read value exact");
            @(negedge user_clk);read_valid=0;
        end
    endtask
    task automatic cold_reset;
        begin
            user_rst_n=0;pixel_rst_n=0;dfi_rst_n=0;i_app_enable=0;i_c2h_running=0;
            pixel_run=1;dfi_run=1;i_pixel_quiet=1;i_dfi_quiet=1;i_user_config_idle=1;
            clocks(5);user_rst_n=1;pixel_rst_n=1;dfi_rst_n=1;clocks(15);
            check(!o_user_busy&&!o_user_locked&&!o_user_mode&&!o_pixel_mode&&!o_dfi_mode,
                  "cold cohort returns all domains to MONO");
            check(!o_user_start_inhibit&&!o_pixel_pause&&!o_dfi_pause,"cold cohort release complete");
        end
    endtask
    task automatic select_dual;
        begin
            write(`PCIE_REG_STEREO_REQUEST_MODE,`STEREO_MODES_DUAL_SDR,4'hf,0);
            write(`PCIE_REG_STEREO_COMMAND,`STEREO_COMMANDS_APPLY,4'hf,0);
            check(o_user_busy&&o_user_start_inhibit&&!o_user_mode,"request busy before recipients ack");
        end
    endtask
    initial begin
        cold_reset();
        read(`PCIE_REG_STEREO_MAGIC,`STEREO_MAGIC,0);
        read(`PCIE_REG_STEREO_ABI_VERSION,`STEREO_ABI_VERSION,0);
        read(`PCIE_REG_STEREO_CAPABILITIES,32'hff000203,0);
        read(12'hfa8,0,2);read(12'hfac,0,2);
        write(12'hfa8,2,4'hf,2);
        write(12'hfa8,1,4'h3,2);
        write(12'hfac,1,4'hf,2);
        write(`PCIE_REG_STEREO_REQUEST_MODE,1,4'h3,2);
        read(`PCIE_REG_STEREO_ERROR,`STEREO_ERRORS_INVALID,0);
        write(`PCIE_REG_STEREO_REQUEST_MODE,3,4'hf,2);
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,0,4'hf,2);
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,256,4'hf,2);
        write(`PCIE_REG_STEREO_ACTIVE_DIVISOR,1,4'hf,2);
        write(12'hf7c,0,4'hf,2);read(12'hf7c,0,2);
        read(`PCIE_REG_STEREO_REQUEST_MODE,0,0);
        i_user_config_idle=0;
        write(`PCIE_REG_STEREO_COMMAND,1,4'hf,2);
        read(`PCIE_REG_STEREO_ERROR,`STEREO_ERRORS_BUSY,0);i_user_config_idle=1;

        // DFI may acknowledge first; PIX has both a stopped clock and a quiet gate.
        @(negedge pixel_clk);pixel_run=0;i_pixel_quiet=0;select_dual();clocks(18);
        check(o_user_busy&&!o_user_mode&&!o_pixel_mode&&o_dfi_mode&&o_dfi_pause,
              "one ack cannot publish or release the acknowledged domain");
        pixel_run=1;clocks(10);
        check(o_user_busy&&o_pixel_pause&&!o_pixel_mode,"running but nonquiet PIX waits");
        i_pixel_quiet=1;clocks(18);
        check(!o_user_busy&&o_user_mode&&o_pixel_mode&&o_dfi_mode,
              "both actual acks publish dual mode");
        check(!o_pixel_pause&&!o_dfi_pause&&!o_user_start_inhibit,"both release after joint ack");
        read(`PCIE_REG_STEREO_STATUS,10,0);

        i_app_enable=1;clocks(3);i_app_enable=0;
        write(`PCIE_REG_STEREO_REQUEST_MODE,0,4'hf,2);
        check(o_user_locked&&o_user_mode&&o_pixel_mode&&o_dfi_mode,"APP lock persists after APP falls");
        read(`PCIE_REG_STEREO_ERROR,`STEREO_ERRORS_LOCKED,0);

        cold_reset();
        @(negedge dfi_clk);dfi_run=0;i_dfi_quiet=0;select_dual();clocks(15);
        check(o_user_busy&&!o_user_mode&&o_pixel_mode&&!o_dfi_mode&&o_pixel_pause,
              "PIX ack alone cannot publish while DFI clock stopped");
        dfi_run=1;clocks(12);
        check(o_user_busy&&o_dfi_pause&&!o_dfi_mode,"DFI quiet gate independent of clock");
        i_dfi_quiet=1;clocks(18);
        check(o_user_mode&&o_pixel_mode&&o_dfi_mode&&!o_user_busy,"DFI completes second ack");

        // A forbidden DMA start while the mailbox is outstanding quarantines it.
        cold_reset();i_dfi_quiet=0;select_dual();clocks(12);i_c2h_running=1;clocks(12);
        i_dfi_quiet=1;i_c2h_running=0;clocks(18);
        check(o_user_busy&&o_user_locked&&!o_user_mode&&o_user_start_inhibit,
              "racing DMA start cannot publish partially applied mode");
        check(o_pixel_pause&&o_dfi_pause,"quarantine remains in both consumers");
        write(`PCIE_REG_STEREO_COMMAND,1,4'hf,2);

        // Any recipient reset invalidates the whole mode mailbox cohort.
        pixel_rst_n=0;#1;
        check(o_user_start_inhibit&&o_pixel_pause&&o_dfi_pause,"partial PIX reset inhibits all domains");
        pixel_rst_n=1;clocks(18);
        check(!o_user_mode&&!o_pixel_mode&&!o_dfi_mode&&!o_user_busy&&!o_user_locked,
              "partial reset cannot leave stale request or mode in another domain");
        select_dual();clocks(18);check(o_user_mode,"fresh request after partial reset");
        dfi_rst_n=0;#1;check(o_user_start_inhibit&&o_pixel_pause&&o_dfi_pause,"partial DFI reset inhibits all domains");
        dfi_rst_n=1;clocks(18);check(!o_user_mode&&!o_pixel_mode&&!o_dfi_mode,"DFI reset invalidates cohort");
        // Reserved topology2 and retired Rice registers are rejected.
        // JPEG cadence remains one mailbox bundle with stopped-domain coverage.
        cold_reset();
        write(`PCIE_REG_STEREO_REQUEST_MODE,2,4'hf,2);
        write(12'hfa8,1,4'hf,2);read(12'hfac,0,2);
        write(`PCIE_REG_STEREO_REQUEST_MODE,`STEREO_MODES_DUAL_JPEG,4'hf,0);
        read(`PCIE_REG_STEREO_REQUEST_DIVISOR,2,0);
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,255,4'hf,0);
        @(negedge dfi_clk);dfi_run=0;
        write(`PCIE_REG_STEREO_COMMAND,1,4'hf,0);clocks(18);
        check(o_pixel_mode&&o_pixel_frame_divisor==255&&
              !o_user_mode&&!o_dfi_mode&&o_user_frame_divisor==2&&o_dfi_frame_divisor==2,
              "recipient applies complete JPEG bundle while USER waits for second ACK");
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,2,4'hf,2);
        check(dut.held_profile=={8'd255,2'd1},"busy write cannot change held mailbox");
        dfi_run=1;clocks(20);
        check(o_user_mode&&o_dfi_mode&&o_user_frame_divisor==255&&o_dfi_frame_divisor==255,
              "both ACKs publish complete JPEG cadence bundle");
        // Re-stage JPEG before startup; mode write restores N2 defaults.
        write(`PCIE_REG_STEREO_REQUEST_MODE,`STEREO_MODES_DUAL_JPEG,4'hf,0);
        read(`PCIE_REG_STEREO_REQUEST_DIVISOR,2,0);
        read(`PCIE_REG_STEREO_STATUS,8,0);
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,1,4'hf,0);
        write(`PCIE_REG_STEREO_COMMAND,1,4'hf,0);clocks(20);
        read(`PCIE_REG_STEREO_ACTIVE_MODE,1,0);
        read(`PCIE_REG_STEREO_ACTIVE_DIVISOR,1,0);
        check(o_pixel_mode&&o_pixel_frame_divisor==1,"JPEG mode and cadence applied atomically");
        i_c2h_running=1;clocks(3);
        write(`PCIE_REG_STEREO_REQUEST_DIVISOR,4,4'hf,2);
        check(o_user_frame_divisor==1,"DMA lock preserves live cadence");
        cold_reset();
        write(`PCIE_REG_STEREO_REQUEST_MODE,`STEREO_MODES_MONO,4'hf,0);
        write(`PCIE_REG_STEREO_COMMAND,1,4'hf,0);clocks(20);
        check(!o_user_mode&&!o_pixel_mode&&!o_dfi_mode&&!o_user_busy,"MONO applies in all domains");
        i_app_enable=1;clocks(3);i_app_enable=0;
        write(`PCIE_REG_STEREO_REQUEST_MODE,1,4'hf,2);
        check(!o_user_mode&&!o_pixel_mode&&!o_dfi_mode,"APP lock preserves MONO ownership");
        $display("RESULT: PASS STEREO COLD CONTROL checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"STEREO CONTROL watchdog");end
endmodule
