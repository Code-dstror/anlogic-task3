`timescale 1ns/1ps
package r3_gray_fifo_values;
    function automatic [95:0] pixels(input integer number);
        integer lane,selector;reg [31:0] mixed;reg [23:0] rgb;
        begin
            for(lane=0;lane<4;lane=lane+1)begin
                selector=(number*4+lane)%11;mixed=32'(number)*32'h9e3779b9+32'(lane)*32'h1020304;
                case(selector)
                    0:rgb=0;1:rgb=24'hffffff;2:rgb=24'hff0000;3:rgb=24'h00ff00;
                    4:rgb=24'h0000ff;5:rgb=24'hff00ff;6:rgb=24'hffff00;7:rgb=24'h00ffff;
                    default:rgb=mixed[23:0];
                endcase
                pixels[lane*24+:24]=rgb;
            end
        end
    endfunction
    function automatic [31:0] luma(input [95:0] rgb);
        integer lane,r,g,b,y;
        begin
            for(lane=0;lane<4;lane=lane+1)begin
                r=rgb[lane*24+16+:8];g=rgb[lane*24+8+:8];b=rgb[lane*24+:8];
                y=(77*r+150*g+29*b+128)>>8;luma[lane*8+:8]=8'(y);
            end
        end
    endfunction
endpackage

module r3_gray_parent_case #(parameter integer REFERENCE=0)(output reg done=0);
    import r3_gray_fifo_values::*;
    reg raw_clk=0,clock_running=1;always #4 raw_clk=~raw_clk;
    wire clk=raw_clk&&clock_running;
    reg rst_n=0,source_valid=0,source_sof=0,source_eol=0,source_done=0,source_error=0;
    reg [95:0] source_rgb=0;
    reg hook_gate=1,output_ready=1;
    wire source_ready,hook_valid,hook_ready,hook_sof,hook_eol,hook_last;
    wire [95:0] hook_rgb;wire [31:0] hook_y;
    wire output_valid,output_sof,output_eol,frame_done,frame_error,pending,owned;
    wire [95:0] output_rgb;wire [31:0] output_y;
    wire neutral_valid,neutral_sof,neutral_eol,neutral_last;
    wire [95:0] neutral_rgb;wire [31:0] neutral_y;wire [1:0] fifo_count;
    r3_gray_parent_probe #(.REFERENCE(REFERENCE)) dut(.*);
    reg [130:0] observed_hook[0:1023];
    integer checks=0,hook_groups=0,output_groups=0,neutral_groups=0,done_count=0;
    integer cycle_count=0,last_hook_cycle=-1,fullrate_groups=0,first_input_cycle=-1,first_hook_cycle=-1;
    integer flow_mode=0,hook_stalls=0,output_stalls=0,n,k,limit,accepted;
    integer last_stall_frame=-1,tail_stall_remaining=0,forced_last_stalls=0;
    reg checking_good=1;
    reg [31:0] rng=32'h7183caef+REFERENCE,rv;
    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"r3 gray parent REF=%0d: %s",REFERENCE,reason);end
    endtask
    always @(negedge clk)begin
        if(flow_mode==0)begin hook_gate=1;output_ready=1;end
        else if(flow_mode==2)begin hook_gate=0;output_ready=0;end
        else begin
            rv=random_word();
            if(hook_stalls==6||rv[3:1]!=0)begin hook_gate=1;hook_stalls=0;end
            else begin hook_gate=0;hook_stalls=hook_stalls+1;end
            if(hook_valid&&hook_last&&hook_groups/128>last_stall_frame)begin
                last_stall_frame=hook_groups/128;tail_stall_remaining=3;
            end
            if(tail_stall_remaining!=0)begin
                hook_gate=0;tail_stall_remaining=tail_stall_remaining-1;forced_last_stalls=forced_last_stalls+1;
            end
            if(output_stalls==6||rv[11:9]!=0)begin output_ready=1;output_stalls=0;end
            else begin output_ready=0;output_stalls=output_stalls+1;end
        end
    end
    always @(posedge clk)begin
        cycle_count=cycle_count+1;
        if(rst_n&&!source_error)begin
            if(checking_good)check(!frame_error,"well-formed consecutive frames never raise a frame error");
            if(first_input_cycle<0&&source_valid&&source_ready)first_input_cycle=cycle_count;
            check(neutral_valid==(hook_valid&&hook_ready),"neutral observes exactly the queued F21 pop handshake");
            if(hook_valid&&hook_ready)begin
                check(hook_groups<1024,"bounded transaction trace");
                check(hook_rgb===pixels(hook_groups)&&hook_y===luma(pixels(hook_groups)),"F21 sees exact original RGB and BT.601 luma");
                check(hook_sof==(hook_groups%128==0)&&hook_eol==(hook_groups%16==15)&&hook_last==(hook_groups%128==127),
                    "SOF/EOL/EOF retain their accepted frame/row positions");
                check({neutral_rgb,neutral_y,neutral_sof,neutral_eol,neutral_last}===
                    {hook_rgb,hook_y,hook_sof,hook_eol,hook_last},"neutral tuple and boundary flags match the same actual pop");
                observed_hook[hook_groups]={hook_last,hook_sof,hook_eol,hook_rgb,hook_y};
                if(first_hook_cycle<0)first_hook_cycle=cycle_count;
                if(hook_groups<256)begin
                    if(hook_groups%128!=0)check(cycle_count==last_hook_cycle+1,"no-bubble frame sustains exactly one group per clock");
                    fullrate_groups=fullrate_groups+1;
                end
                last_hook_cycle=cycle_count;hook_groups=hook_groups+1;neutral_groups=neutral_groups+1;
            end
            if(output_valid&&output_ready)begin
                check(output_rgb===pixels(output_groups)&&output_y===luma(pixels(output_groups)),"parent output retains the ordered identity-hook transaction");
                check(output_sof==(output_groups%128==0)&&output_eol==(output_groups%16==15),"parent output preserves frame and row flags");
                output_groups=output_groups+1;
            end
            if(frame_done)done_count=done_count+1;
        end
    end
    task send_frame(input integer frame_number);
        integer group_number;
        begin
            group_number=0;@(negedge clk);source_valid=1;source_done=0;
            source_rgb=pixels(frame_number*128);source_sof=1;source_eol=0;
            while(group_number<128)begin
                @(posedge clk);if(source_ready)group_number=group_number+1;
                @(negedge clk);
                if(group_number<128)begin source_rgb=pixels(frame_number*128+group_number);source_sof=group_number==0;source_eol=group_number%16==15;end
                else begin source_valid=0;source_done=1;end
            end
            @(posedge clk);@(negedge clk);source_done=0;
        end
    endtask
    task fill_blocked;
        begin
            flow_mode=2;@(negedge clk);source_valid=1;source_done=0;source_sof=1;source_eol=0;source_rgb=pixels(9000);
            accepted=0;limit=0;
            begin:fill_loop
                forever begin
                    @(posedge clk);if(source_ready)accepted=accepted+1;
                    @(negedge clk);limit=limit+1;check(limit<30,"finite gray capacity backpressures a blocked F21 hook");
                    if(!source_ready)disable fill_loop;
                    source_sof=0;source_eol=accepted%16==15;source_rgb=pixels(9000+accepted);
                end
            end
            source_valid=0;
            check(pending&&owned,"blocked frame remains owned and visibly pending");
            if(!REFERENCE)check(fifo_count==2,"both real FIFO slots are owned before cancellation/reset");
        end
    endtask
    initial begin
        #2000;@(negedge clk);rst_n=1;
        send_frame(0);send_frame(1);wait(done_count==2&&!pending&&!owned);
        check(hook_groups==256&&output_groups==256&&fullrate_groups==256,"two consecutive full-rate frames completed exactly");
        flow_mode=1;send_frame(2);send_frame(3);wait(done_count==4&&!pending&&!owned);
        check(hook_groups==512&&output_groups==512,"random finite stalls preserve two further frames");
        check(forced_last_stalls>=6,"both finite-stall frames exercised a three-clock final-beat stall");
        checking_good=0;fill_blocked();source_error=1;#1;
        check(!hook_valid&&pending,"cancel immediately withdraws VALID without falsely declaring quiet before its clock");
        @(posedge clk);#1;check(!pending&&frame_error,"synchronous cancel actually clears all ledgers and reports abort");
        @(negedge clk);source_error=0;repeat(3)@(negedge clk);checking_good=1;
        checking_good=0;fill_blocked();source_valid=1;source_sof=1;#1;
        check(!hook_valid&&pending&&source_ready,"a malformed repeated SOF immediately cancels the blocked F21 presentation");
        @(posedge clk);#1;check(!pending&&frame_error&&!owned,"the actual malformed-SOF path clears all owned work on its cancel edge");
        @(negedge clk);source_valid=0;source_sof=0;repeat(3)@(negedge clk);checking_good=1;
        fill_blocked();clock_running=0;#0.5;rst_n=0;#1;
        check(!hook_valid&&!output_valid&&!pending,"global reset asynchronously clears held parent/FIFO work without a clock");
        #2;rst_n=1;#33;
        check(!hook_valid&&!output_valid&&!pending,"deasserting a short stopped-clock global reset cannot revive old tokens");
        @(negedge raw_clk);clock_running=1;flow_mode=0;repeat(6)@(negedge clk);
        send_frame(4);wait(done_count==5&&!pending&&!owned);
        check(hook_groups==640&&output_groups==640&&neutral_groups==640,"fresh frame after abort/reset contains no stale transaction");
        check(first_hook_cycle-first_input_cycle==(REFERENCE?3:4),"empty FIFO adds exactly one clock; R1 transaction latency is retained as the reference");
        $display("RESULT: PASS r3_gray_parent REF=%0d checks=%0d hook_groups=%0d output_groups=%0d neutral_groups=%0d fullrate_groups=%0d first_hook_latency=%0d final_stall_cycles=%0d",
            REFERENCE,checks,hook_groups,output_groups,neutral_groups,fullrate_groups,first_hook_cycle-first_input_cycle,forced_last_stalls);
        done=1;
    end
endmodule

module r3_gray_boundary_case(output reg done=0);
    import r3_gray_fifo_values::*;
    reg raw_clk=0,clock_running=1;always #4 raw_clk=~raw_clk;
    wire clk=raw_clk&&clock_running;
    reg rst_n=0,cancel=0,s_valid=0,s_sof=0,s_eol=0,g_down_ready=0;
    reg [95:0] s_data=0;
    wire g_ready,g_valid,g_sof,g_eol,pending;wire [95:0] g_original;wire [31:0] g_luma;
    r3_gray_boundary_probe dut(.*);
    reg [129:0] expected[0:2047];integer wr=0,rd=0,checks=0,n,k,limit;
    integer pops=0,simultaneous=0,hidden_prefills=0,full_holds=0;
    reg [129:0] old0,old1,raw_tuple,held_tuple;reg [1:0] old_count;reg old_tail,was_stalled;
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"r3 gray actual buffer: %s",reason);end
    endtask
    task cycle;
        begin @(posedge clk);#1;end
    endtask
    task drive(input integer number);
        begin s_data=pixels(number);s_sof=number%128==0;s_eol=number%16==15;end
    endtask
    always @(negedge rst_n)begin wr=0;rd=0;end
    always @(posedge clk)begin
        old0=dut.gray_fifo_payload0;old1=dut.gray_fifo_payload1;old_count=dut.gray_fifo_count;old_tail=dut.gray_fifo_tail;
        raw_tuple={dut.raw_gray_sof,dut.raw_gray_eol,dut.raw_gray_original,dut.raw_gray_luma};
        held_tuple={g_sof,g_eol,g_original,g_luma};was_stalled=rst_n&&!cancel&&g_valid&&!g_down_ready;
        if(!rst_n||cancel)begin wr=0;rd=0;end
        else begin
            if(g_valid&&g_down_ready)begin
                check(rd<wr,"buffer cannot publish a token not accepted by the actual gray source");
                check({g_sof,g_eol,g_original,g_luma}===expected[rd],"buffer preserves exact accepted RGB/Y/sidebands and order");
                rd=rd+1;pops=pops+1;
            end
            if(s_valid&&g_ready)begin expected[wr]={s_sof,s_eol,s_data,luma(s_data)};wr=wr+1;end
            if(dut.gray_fifo_push&&dut.gray_fifo_pop)simultaneous=simultaneous+1;
        end
        #1;
        check(dut.raw_gray_ready==(dut.gray_fifo_count<2),"raw READY is solely local occupancy");
        check(dut.gray_fifo_count<=2,"occupancy never exceeds two owned slots");
        if(old_count<2)begin
            if(old_tail)begin
                check(dut.gray_fifo_payload1===raw_tuple&&dut.gray_fifo_payload0===old0,"only the unowned tail1 pre-samples the true push tuple");
            end else begin
                check(dut.gray_fifo_payload0===raw_tuple&&dut.gray_fifo_payload1===old1,"only the unowned tail0 pre-samples the true push tuple");
            end
            if(old_count==0&&!dut.raw_gray_valid&&(dut.gray_fifo_payload0!==old0||dut.gray_fifo_payload1!==old1))hidden_prefills=hidden_prefills+1;
        end else begin
            full_holds=full_holds+1;
            check(dut.gray_fifo_payload0===old0&&dut.gray_fifo_payload1===old1,"full owned slots never write, including full recovery");
        end
        if(was_stalled)check(g_valid&&{g_sof,g_eol,g_original,g_luma}===held_tuple,"occupied stalled head payload remains stable");
    end
    task fill_full(input integer base_number);
        begin
            g_down_ready=0;s_valid=1;drive(base_number);n=0;limit=0;
            while(dut.gray_fifo_count!=2||g_ready)begin
                @(posedge clk);if(g_ready)n=n+1;
                @(negedge clk);drive(base_number+n);limit=limit+1;check(limit<20,"actual gray plus two slots fill within bounded capacity");
            end
            s_valid=0;check(pending&&g_valid,"full queue is a visible owned token ledger");
        end
    endtask
    initial begin
        #2000;@(negedge clk);rst_n=1;
        for(k=0;k<12;k=k+1)begin @(negedge clk);drive(k);cycle();check(!g_valid&&!pending,"empty invalid prefill stays hidden");end
        fill_full(100);repeat(5)cycle();
        #0.25;cancel=1;#0.5;check(!g_valid&&pending&&dut.gray_fifo_count==2,"a short edge-free cancel only masks presentation and preserves pending");
        cancel=0;#0.5;check(g_valid&&pending&&dut.gray_fifo_count==2,"without a cancel clock edge the original owned tuple is retained");
        @(negedge clk);g_down_ready=1;cycle();
        check(dut.gray_fifo_count==1&&dut.raw_gray_ready,"full pop restores source capacity on the following clock");
        s_valid=1;
        for(k=0;k<32;k=k+1)begin @(negedge clk);drive(200+k);cycle();end
        @(negedge clk);s_valid=0;repeat(8)cycle();check(!pending&&wr==rd,"normal drain reaches real quiet");
        fill_full(500);@(negedge clk);cancel=1;#1;
        check(!g_valid&&pending&&dut.gray_fifo_count==2,"cancel masks VALID immediately but pending cannot disappear early");
        cycle();check(!pending&&dut.gray_fifo_count==0,"cancel edge clears real ownership without resetting payload");
        @(negedge clk);cancel=0;repeat(4)cycle();
        fill_full(700);@(negedge clk);clock_running=0;#0.5;rst_n=0;#1;
        check(!g_valid&&!pending&&dut.gray_fifo_count==0,"hard reset clears count/head/tail asynchronously while clock is stopped");
        #2;rst_n=1;#33;check(!g_valid&&!pending,"short reset cannot resurrect stale two-slot contents");
        @(negedge raw_clk);clock_running=1;g_down_ready=1;repeat(6)cycle();
        check(!g_valid&&!pending,"no old token appears when clocks resume");
        check(simultaneous>20&&hidden_prefills>3&&full_holds>3,"steady pop/push, hidden prefill and owned full-slot checks executed");
        $display("RESULT: PASS r3_gray_actual_boundary checks=%0d pops=%0d simultaneous=%0d hidden_prefills=%0d full_holds=%0d",checks,pops,simultaneous,hidden_prefills,full_holds);
        done=1;
    end
endmodule

module r3_gray_fifo_tb;
    wire current_done,reference_done,boundary_done;
    r3_gray_parent_case #(.REFERENCE(0)) current_case(current_done);
    r3_gray_parent_case #(.REFERENCE(1)) reference_case(reference_done);
    r3_gray_boundary_case boundary_case(boundary_done);
    integer k;
    initial begin
        wait(current_done&&reference_done&&boundary_done);
        for(k=0;k<640;k=k+1)if(current_case.observed_hook[k]!==reference_case.observed_hook[k])$fatal(1,"candidate transaction differs from R1 at %0d",k);
        $display("RESULT: PASS r3_gray_fifo_all R1_transaction_comparisons=640");$finish;
    end
    initial begin #500000;$fatal(1,"r3 gray FIFO watchdog");end
endmodule
