`timescale 1ns/1ps
module r3_gray_clear_case #(parameter integer NEUTRAL=1)(output reg done=0);
    reg raw_clk=0,clock_running=1;
    always #4 raw_clk=~raw_clk;
    wire clk=raw_clk&&clock_running;
    reg rst_n=0,clear=0,enable=0,s_valid=0,m_ready=0,s_sof=0,s_eol=0;
    wire [12:0] width=64,height=8;
    reg [95:0] s_data=0;
    wire c_ready,c_valid,c_sof,c_eol,c_pending,r_ready,r_valid,r_sof,r_eol,r_pending;
    wire [95:0] c_data,c_original,r_data,r_original;
    wire [31:0] c_luma,r_luma;
    r3_gray_candidate #(.NEUTRAL_TAP_ENABLE(NEUTRAL)) candidate(
        .clk(clk),.rst_n(rst_n),.clear(clear),.enable(enable),.width(width),.height(height),
        .s_valid(s_valid),.s_ready(c_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),
        .m_valid(c_valid),.m_ready(m_ready),.m_data(c_data),.m_sof(c_sof),.m_eol(c_eol),
        .m_luma(c_luma),.m_original_data(c_original),.o_pending(c_pending));
    r3_gray_reference #(.NEUTRAL_TAP_ENABLE(NEUTRAL)) reference_dut(
        .clk(clk),.rst_n(rst_n),.clear(clear),.enable(enable),.width(width),.height(height),
        .s_valid(s_valid),.s_ready(r_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),
        .m_valid(r_valid),.m_ready(m_ready),.m_data(r_data),.m_sof(r_sof),.m_eol(r_eol),
        .m_luma(r_luma),.m_original_data(r_original),.o_pending(r_pending));
    wire [225:0] candidate_tuple={c_data,c_original,c_luma,c_sof,c_eol};
    wire [225:0] reference_tuple={r_data,r_original,r_luma,r_sof,r_eol};
    reg [225:0] expected[0:8191];
    integer write_index=0,read_index=0,checks=0,numeric_groups=0,cycle_number=0;
    integer phase=0,fullrate_groups=0,last_fullrate=-1,extra_clear_advances=0;
    integer mask,k,n,token=0,stall_run=0,short_pulses=0,global_resets=0;
    reg accepted_at_edge=0,extra_at_edge,previous_clear;
    reg [225:0] held_tuple;
    reg [31:0] rng=32'h614ca0ef+NEUTRAL,random_value;
    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    function [95:0] pixel_group(input integer number);
        integer lane,selector;
        reg [31:0] mixed;
        reg [23:0] rgb;
        begin
            for(lane=0;lane<4;lane=lane+1)begin
                selector=(number*4+lane)%11;
                mixed=32'(number)*32'h9e3779b9+32'(lane)*32'h1020304;
                case(selector)
                    0:rgb=24'h000000;1:rgb=24'hffffff;
                    2:rgb=24'hff0000;3:rgb=24'h00ff00;4:rgb=24'h0000ff;
                    5:rgb=24'hff00ff;6:rgb=24'hffff00;7:rgb=24'h00ffff;
                    default:rgb=mixed[23:0];
                endcase
                pixel_group[lane*24+:24]=rgb;
            end
        end
    endfunction
    function [225:0] expected_group(input [95:0] rgb,input bit gray,sof,eol);
        integer lane,red,green,blue,y;
        reg [95:0] output_rgb;
        reg [31:0] luma;
        begin
            for(lane=0;lane<4;lane=lane+1)begin
                red=rgb[lane*24+16+:8];green=rgb[lane*24+8+:8];blue=rgb[lane*24+:8];
                y=(77*red+150*green+29*blue+128)>>8;
                luma[lane*8+:8]=8'(y);
                output_rgb[lane*24+:24]=gray ? {3{8'(y)}} : rgb[lane*24+:24];
            end
            expected_group={output_rgb,(NEUTRAL?rgb:96'd0),luma,sof,eol};
        end
    endfunction
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"r3 gray NEUTRAL=%0d phase=%0d: %s",NEUTRAL,phase,reason);end
    endtask
    task cycle;
        begin @(posedge clk);#1;end
    endtask
    task drive_token(input integer number);
        begin
            s_data=pixel_group(number);s_sof=number%128==0;s_eol=number%16==15;enable=number[0];
        end
    endtask
    task clear_epoch;
        begin
            @(negedge clk);clear=1;s_valid=0;cycle();
            @(negedge clk);clear=0;m_ready=1;
        end
    endtask
    always @(negedge rst_n)begin write_index=0;read_index=0;end
    always @(posedge clk)begin
        cycle_number=cycle_number+1;
        accepted_at_edge=rst_n&&!clear&&s_valid&&c_ready;
        extra_at_edge=rst_n&&clear&&candidate.advance&&!reference_dut.advance;
        if(!rst_n||clear)begin write_index=0;read_index=0;end
        else begin
            if(c_valid&&m_ready)begin
                check(read_index<write_index,"no output is invented before a real input acceptance");
                check(candidate_tuple===expected[read_index],"BT.601 luma, selected RGB, original RGB and SOF/EOL match accepted source");
                check(reference_tuple===expected[read_index],"frozen R1 agrees with the independent numerical/transaction model");
                read_index=read_index+1;numeric_groups=numeric_groups+1;
                if(phase==1)begin
                    if(last_fullrate>=0)check(cycle_number==last_fullrate+1,"two no-bubble frames sustain one group per clock");
                    last_fullrate=cycle_number;fullrate_groups=fullrate_groups+1;
                end
            end
            if(accepted_at_edge)begin
                check(write_index<8192,"directed transaction model remains bounded");
                expected[write_index]=expected_group(s_data,enable,s_sof,s_eol);write_index=write_index+1;
            end
        end
        #1;
        check({c_ready,c_valid,c_sof,c_eol,c_pending}==={r_ready,r_valid,r_sof,r_eol,r_pending},
            "public handshake, valid, sidebands and pending are cycle equivalent");
        check(candidate.valid_pipe===reference_dut.valid_pipe,"all valid stages keep identical ownership");
        if(c_valid)check(candidate_tuple===reference_tuple,"every owned output byte equals frozen R1, including stalls");
        if(!clear)check(candidate.advance===reference_dut.advance,"all non-clear data advances are identical");
        if(extra_at_edge)extra_clear_advances=extra_clear_advances+1;
    end
    initial begin
        #2000;@(negedge clk);rst_n=1;m_ready=1;
        repeat(3)cycle();phase=1;
        // Two continuous 64x8 frames (128 groups each), no artificial bubbles.
        for(n=0;n<256;n=n+1)begin @(negedge clk);s_valid=1;drive_token(n);cycle();check(accepted_at_edge,"full-rate source accepts every clock");end
        @(negedge clk);s_valid=0;repeat(5)cycle();
        check(fullrate_groups==256,"both complete no-bubble frame transaction sequences retired");phase=2;
        for(n=0;n<3000;n=n+1)begin
            @(negedge clk);previous_clear=clear;random_value=random_word();
            clear=n%31==0;
            if(clear)s_valid=0;
            else if(!s_valid||accepted_at_edge||previous_clear)begin
                s_valid=random_value[9:8]!=0;
                if(s_valid)begin token=token+1;drive_token(token+500);end
            end
            if(stall_run>=6||random_value[18:16]!=0)begin m_ready=1;stall_run=0;end
            else begin m_ready=0;stall_run=stall_run+1;end
            cycle();
        end
        clear_epoch();
        // Every possible occupancy pattern, including a stalled stage2.
        phase=3;
        for(mask=0;mask<8;mask=mask+1)begin
            clear_epoch();
            for(k=0;k<3;k=k+1)begin @(negedge clk);s_valid=(mask>>(2-k))&1;drive_token(4000+mask*3+k);cycle();end
            check(reference_dut.valid_pipe==3'(mask),"all eight valid-stage patterns are actually reached");
            @(negedge clk);m_ready=0;clear=1;s_valid=0;#0.5;
            check(!c_valid&&!c_ready&&c_pending==(mask!=0),"clear immediately masks transfers but does not fake pending before its edge");
            cycle();check(!c_pending&&!r_pending,"clear edge cancels every old ownership stage");
        end
        clear_epoch();phase=4;
        for(k=0;k<3;k=k+1)begin @(negedge clk);s_valid=1;m_ready=0;drive_token(5000+k);cycle();end
        @(negedge clk);s_valid=0;held_tuple=candidate_tuple;
        repeat(8)begin cycle();check(c_valid&&candidate_tuple===held_tuple,"owned stalled payload remains stable without clear");end
        @(negedge clk);#0.5;clear=1;#0.5;
        check(!c_valid&&!c_ready&&c_pending,"sub-clock clear masks presentation while ownership remains pending");
        #0.5;clear=0;#0.5;
        check(c_valid&&candidate_tuple===held_tuple&&c_pending,"clear pulse without an edge changes no registered data/ownership");short_pulses=short_pulses+1;
        clear_epoch();
        phase=5;
        for(k=0;k<3;k=k+1)begin @(negedge clk);s_valid=1;m_ready=0;drive_token(6000+k);cycle();end
        @(negedge clk);s_valid=0;clock_running=0;#0.5;rst_n=0;#1;
        check(!c_valid&&!c_pending&&!r_valid&&!r_pending,"short global reset asynchronously clears owned tokens while clock is stopped");
        #2;rst_n=1;#33;
        check(!c_valid&&!c_pending,"global reset cannot revive old tokens before a stopped clock resumes");
        @(negedge raw_clk);clock_running=1;m_ready=1;repeat(6)cycle();
        check(!c_valid&&!c_pending,"no stale output follows resumed clocks");global_resets=global_resets+1;
        phase=6;
        for(n=0;n<32;n=n+1)begin @(negedge clk);s_valid=1;drive_token(7000+n);cycle();end
        @(negedge clk);s_valid=0;repeat(6)cycle();
        check(read_index==write_index&&!c_pending,"fresh epoch drains to true quiet after all cancellations");
        check(numeric_groups>1000&&extra_clear_advances>=4,"meaningful numerical and extra-clear-CE cases executed");
        $display("RESULT: PASS r3_gray_clear NEUTRAL=%0d checks=%0d numeric_groups=%0d fullrate_groups=%0d extra_clear_advances=%0d short_clear_pulses=%0d stopped_clock_global_resets=%0d",
            NEUTRAL,checks,numeric_groups,fullrate_groups,extra_clear_advances,short_pulses,global_resets);
        done=1;
    end
endmodule

module r3_gray_clear_tb;
    wire plain_done,neutral_done;
    r3_gray_clear_case #(.NEUTRAL(0)) plain_case(plain_done);
    r3_gray_clear_case #(.NEUTRAL(1)) neutral_case(neutral_done);
    initial begin wait(plain_done&&neutral_done);$display("RESULT: PASS r3_gray_clear_all");$finish;end
    initial begin #500000;$fatal(1,"r3 gray watchdog");end
endmodule
