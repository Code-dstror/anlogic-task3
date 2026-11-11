`timescale 1ns/1ps
module tb_uart_status_observer;
    localparam integer UART_DIV=4,REPORT_CYCLES=4000,TIMEOUT_CYCLES=30;
    localparam integer BIT_NS=40*UART_DIV;
    reg i_sys_clk=0,pixel_raw=0,dfi_raw=0,user_raw=0;
    always #20 i_sys_clk=~i_sys_clk;
    always #4 pixel_raw=~pixel_raw;
    always #3.75 dfi_raw=~dfi_raw;
    always #7 user_raw=~user_raw;
    reg pixel_running=1,dfi_running=1,user_running=0;
    wire i_pixel_clk=pixel_running&&pixel_raw;
    wire i_dfi_clk=dfi_running&&dfi_raw;
    wire i_user_clk=user_running&&user_raw;
    reg i_sys_rst_n=0;
    wire [2:0] i_domain_observer_rst_n;
    reset_release_sync rp(.i_clk(i_pixel_clk),.i_async_rst_n(i_sys_rst_n),.o_rst_n(i_domain_observer_rst_n[0]));
    reset_release_sync rd(.i_clk(i_dfi_clk),.i_async_rst_n(i_sys_rst_n),.o_rst_n(i_domain_observer_rst_n[1]));
    reset_release_sync ru(.i_clk(i_user_clk),.i_async_rst_n(i_sys_rst_n),.o_rst_n(i_domain_observer_rst_n[2]));
    reg [2:0] i_domain_reset_n=7;
    reg [15:0] i_sys_status=16'h25a7;
    wire [35:0] i_domain_flags;
    reg [11:0] i_domain_faults=0;
    wire [5:0] i_domain_progress;
    wire o_uart_tx;
    uart_status_observer #(.UART_DIV(UART_DIV),.REPORT_INTERVAL_CYCLES(REPORT_CYCLES),
        .SNAPSHOT_TIMEOUT_CYCLES(TIMEOUT_CYCLES)) dut(.*);

    wire [2:0] source_clocks={i_user_clk,i_dfi_clk,i_pixel_clk};
    integer checks=0,frames=0,snapshot_captures=0,received_captures=0,held_checks=0;
    integer wraps=0,frames_at_stop,expected_sequence=0,file_handle,receiver_index=0;
    integer byte_number,bit_number,target;
    reg [7:0] received_byte;
    reg byte_valid;
    reg [7:0] frame_bytes[0:28];
    reg [223:0] frozen_prefix;
    reg [2:0] last_fresh=0,last_reset=0;
    reg [7:0] received_crc;
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"UART observer: %s",reason);end
    endtask
    function [7:0] crc_reference;
        input [223:0] prefix;
        reg [7:0] value;
        reg feedback;
        integer b,n;
        begin
            value=0;
            for(b=0;b<28;b=b+1)for(n=7;n>=0;n=n-1)begin
                feedback=value[7]^prefix[b*8+n];
                value={value[6:0],1'b0};
                if(feedback)value=value^8'h07;
            end
            crc_reference=value;
        end
    endfunction

    // Domain scoreboards independently count the registered input pulses.
    // Changing all flags on every source edge detects a torn binary CDC word.
    genvar g;
    generate for(g=0;g<3;g=g+1)begin:source_model
        reg [7:0] pattern=0;
        reg [15:0] count0=0,count1=0;
        reg [3:0] sticky=0;
        reg [47:0] expected_snapshot,held_snapshot;
        reg capture_now,hold_now;
        assign i_domain_flags[g*12+:12]={pattern[3:0]^4'ha,pattern};
        assign i_domain_progress[g*2+:2]={pattern[2:0]==3'd2,1'b1};
        always @(posedge source_clocks[g] or negedge i_domain_observer_rst_n[g])begin
            if(!i_domain_observer_rst_n[g])begin pattern<=0;count0<=0;count1<=0;sticky<=0;end
            else begin
                pattern<=pattern+1'b1;count0<=count0+1'b1;
                if(i_domain_progress[g*2+1])count1<=count1+1'b1;
                sticky<=sticky|i_domain_faults[g*4+:4];
                if(count0==16'hffff)wraps=wraps+1;
            end
        end
        always @(posedge source_clocks[g])begin
            capture_now=i_domain_observer_rst_n[g]&&dut.g_domain[g].u_snapshot.request_sync[1]&&!dut.ack_level[g];
            hold_now=i_domain_observer_rst_n[g]&&dut.ack_level[g]&&dut.g_domain[g].u_snapshot.request_sync[1];
            expected_snapshot={count1,count0,sticky,i_domain_flags[g*12+:12]};
            held_snapshot=dut.source_snapshot[g*48+:48];
            #1;
            if(capture_now)begin
                snapshot_captures=snapshot_captures+1;
                check(dut.source_snapshot[g*48+:48]===expected_snapshot,"source freezes one exact status/counter tuple");
            end
            if(hold_now)begin
                held_checks=held_checks+1;
                check(dut.source_snapshot[g*48+:48]===held_snapshot,"source bank stays immutable throughout held request/ACK");
            end
        end
    end endgenerate

    reg [143:0] held_report;
    reg was_sending;
    integer d;
    reg [47:0] sampled_bank;
    always @(posedge i_sys_clk)begin
        was_sending=i_sys_rst_n&&(dut.report_phase==1||dut.report_phase==2);
        held_report=dut.report_domains;
        if(i_sys_rst_n&&dut.report_phase==1)
            frozen_prefix={dut.report_domains,i_sys_status,{5'd0,dut.reset_sync},
                {5'd0,dut.round_fresh},dut.sequence_count,8'd29,8'd2,16'h424f};
        #1;
        if(was_sending)check(dut.report_domains===held_report,"destination bank stays fixed during FREEZE and every TX bit");
    end
    generate for(g=0;g<3;g=g+1)begin:destination_model
        reg take_now;
        reg [47:0] bank;
        always @(posedge i_sys_clk)begin
            take_now=i_sys_rst_n&&dut.snapshot_phase[g]==2&&dut.ack_sync[g]&&
                (dut.report_phase==0||dut.report_phase==3);
            bank=dut.source_snapshot[g*48+:48];
            #1;
            if(take_now)begin
                received_captures=received_captures+1;
                check(dut.report_domains[g*48+:48]===bank,"ACK plus settle edge transfers the complete held CDC word");
            end
        end
    end endgenerate

    // A real 8N1 bit receiver checks wire data and CRC rather than peeking at
    // the DUT serializer's byte selection. Complete packets are saved for the
    // independent PC decoder; reset-truncated packets are discarded here.
    always @(negedge i_sys_rst_n)begin receiver_index=0;expected_sequence=0;end
    initial begin
        file_handle=$fopen("uart_frames.bin","wb");check(file_handle!=0,"wire capture file opens");
        forever begin
            @(negedge o_uart_tx);
            if(i_sys_rst_n)begin
                byte_valid=1;received_byte=0;
                #(BIT_NS/2);if(!i_sys_rst_n)byte_valid=0;
                if(byte_valid)check(!o_uart_tx,"start bit center is low");
                for(bit_number=0;bit_number<8;bit_number=bit_number+1)begin
                    #BIT_NS;if(!i_sys_rst_n)byte_valid=0;
                    received_byte[bit_number]=o_uart_tx;
                end
                #BIT_NS;if(!i_sys_rst_n)byte_valid=0;
                if(byte_valid)begin
                    check(o_uart_tx,"stop bit center is high");
                    frame_bytes[receiver_index]=received_byte;
                    if(receiver_index==28)begin
                        check({frame_bytes[3],frame_bytes[2],frame_bytes[1],frame_bytes[0]}==32'h1d02424f,
                            "fixed magic/version/length are on the wire");
                        check({frame_bytes[5],frame_bytes[4]}==16'(expected_sequence),"report sequence advances once per complete frame");
                        for(byte_number=0;byte_number<28;byte_number=byte_number+1)
                            check(frame_bytes[byte_number]===frozen_prefix[byte_number*8+:8],"wire payload equals one frozen coherent report");
                        received_crc=crc_reference(frozen_prefix);
                        check(frame_bytes[28]===received_crc,"independent CRC8 matches all 28 bytes");
                        last_fresh=frame_bytes[6][2:0];last_reset=frame_bytes[7][2:0];
                        for(byte_number=0;byte_number<29;byte_number=byte_number+1)
                            $fwrite(file_handle,"%c",frame_bytes[byte_number]);
                        frames=frames+1;expected_sequence=expected_sequence+1;receiver_index=0;
                    end else receiver_index=receiver_index+1;
                end
                #(BIT_NS/2);
            end
        end
    end

    task next_frame;
        integer previous_frames;
        begin previous_frames=frames;wait(frames>previous_frames);#1;end
    endtask
    task resume_pixel;
        begin @(negedge pixel_raw);pixel_running=1;end
    endtask
    task resume_dfi;
        begin @(negedge dfi_raw);dfi_running=1;end
    endtask
    task resume_user;
        begin @(negedge user_raw);user_running=1;end
    endtask

    initial begin
        repeat(10)@(negedge i_sys_clk);i_sys_rst_n=1;
        next_frame();
        check($time<70000,"first cold-start report is prompt rather than waiting a whole period");
        check(last_fresh==3'b011&&last_reset==7,"stopped-at-boot USER is invalid while SYS still reports");
        next_frame();
        check(!last_fresh[2]&&dut.request_level[2]&&!dut.ack_level[2],"timeout keeps the original pending request high across reports");
        resume_user();next_frame();
        check(last_fresh==7,"late USER response recovers into a coherent fresh report");

        wait(dut.request_level[0]);wait(dut.ack_level[0]);
        @(negedge pixel_raw);pixel_running=0;
        next_frame();next_frame();
        check(!last_fresh[0],"clock stopped with ACK in flight cannot be reported fresh repeatedly");
        check(!dut.request_level[0]&&dut.ack_level[0],"four-phase release waits for the real stopped domain ACK low");
        resume_pixel();next_frame();
        if(!last_fresh[0])next_frame();
        check(last_fresh[0],"PIX resumes after ACK-high stop without a false retry or deadlock");

        wait(dut.request_level[1]);wait(dut.ack_level[1]);wait(!dut.request_level[1]);
        @(negedge dfi_raw);dfi_running=0;
        next_frame();next_frame();
        check(!last_fresh[1],"release-wait timeout still transmits bounded reports");
        resume_dfi();next_frame();if(!last_fresh[1])next_frame();
        check(last_fresh[1],"DFI release-wait recovers on resumed clocks");

        i_domain_faults=12'hfff;repeat(5)@(negedge i_sys_clk);i_domain_faults=0;
        i_domain_reset_n[2]=0;
        next_frame();next_frame();
        check(last_fresh[2]&&!last_reset[2],"business reset is observed without blocking or resetting the mailbox");
        check(dut.report_domains[111:108]==4'hf,"observer faults survive application reset");
        i_domain_reset_n[2]=1;next_frame();
        check(last_fresh==7&&last_reset==7,"all observed business domains recover");
        check(wraps>0,"16-bit progress rollover actually executed");

        wait(dut.serial_active&&dut.byte_index==7);#3;i_sys_rst_n=0;
        #1;check(o_uart_tx,"independent cold reset immediately idles TX");
        #(BIT_NS*20);i_sys_rst_n=1;
        next_frame();
        check(expected_sequence==1&&last_fresh==7,"cold reset cancels a partial frame and restarts a coherent sequence0");
        next_frame();
        check(snapshot_captures>25&&received_captures>25&&held_checks>100,"many coherent CDC captures and held-bank checks executed");
        $fclose(file_handle);
        $display("RESULT: PASS uart_status_observer checks=%0d frames=%0d source_snapshots=%0d received_snapshots=%0d held_checks=%0d wraps=%0d",
            checks,frames,snapshot_captures,received_captures,held_checks,wraps);
        $finish;
    end
    initial begin #10000000;$fatal(1,"UART observer watchdog");end
endmodule
