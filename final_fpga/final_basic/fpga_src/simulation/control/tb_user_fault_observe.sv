`timescale 1ns/1ps
module tb_user_fault_observe;
    reg user_clk=0;
    always #4 user_clk=~user_clk;
    reg debug_user_rst_n=0,user_rst_n=1,debug_app_rst_n=1,app_hard_rst_n=1;
    reg [7:0] transport_observe=0;
    reg [1:0] product_fault_user=0;
    reg product_axil_fault=0,transport_recovery=0,memory_fault_user=0;
    reg reset_pending_user=0,memory_owner_ready=1,product_buffer_armed=0,cfg_user_initialized=1,user_link_up=1;
    reg jpeg_user_retire_valid=0,jpeg_user_retire_ready=0;
    reg actual_c2h_valid=0,actual_c2h_ready=0,actual_c2h_last=0;
    wire [3:0] o_faults,o_causes;
    wire [2:0] o_first_phase;
    wire [11:0] o_flags;
    wire [1:0] o_progress;
    extracted_user_observer dut(.*);
    integer checks=0,cause_cases=0,first_kind,phase,k,submit_events=0;
    reg [3:0] expected_mask;
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"USER first observation: %s",reason);end
    endtask
    task cycle;
        begin @(posedge user_clk);#1;end
    endtask
    task clear_inputs;
        begin
            transport_observe=0;product_fault_user=0;product_axil_fault=0;transport_recovery=0;memory_fault_user=0;
            user_rst_n=1;debug_app_rst_n=1;app_hard_rst_n=1;
            jpeg_user_retire_valid=0;jpeg_user_retire_ready=0;
            actual_c2h_valid=0;actual_c2h_ready=0;actual_c2h_last=0;
        end
    endtask
    task cold_clear;
        begin
            @(negedge user_clk);clear_inputs();debug_user_rst_n=0;#1;
            check(o_faults==0&&o_first_phase==0&&o_progress==0,"only debug cold asynchronously clears observer cause/phase/events");
            cycle();@(negedge user_clk);debug_user_rst_n=1;cycle();
        end
    endtask
    task inject_cause(input integer kind,input integer native_phase);
        begin
            clear_inputs();transport_observe[6:4]=3'(native_phase);
            case(kind)
                0:transport_observe[2]=1;
                1:transport_observe[3]=1;
                2:memory_fault_user=1;
                3:product_fault_user[1]=1;
            endcase
        end
    endtask
    always @(posedge user_clk)begin #0.5;if(debug_user_rst_n&&o_progress[0])submit_events=submit_events+1;end
    initial begin
        cold_clear();
        for(first_kind=0;first_kind<4;first_kind=first_kind+1)for(phase=0;phase<8;phase=phase+1)begin
            cold_clear();@(negedge user_clk);inject_cause(first_kind,phase);expected_mask=4'(1<<first_kind);
            #1;check(o_faults==0&&o_causes==expected_mask,"real combinational mapping exposes exactly the injected first cause");
            cycle();
            check(o_faults==expected_mask&&o_first_phase==3'(phase)&&o_flags[8:6]==3'(phase),
                "first nonzero mask and first observed phase latch together");
            @(negedge user_clk);transport_observe[3:2]=3;product_fault_user[1]=1;memory_fault_user=1;
            product_axil_fault=1;transport_recovery=1;transport_observe[6:4]=3'((phase+3)%8);
            repeat(3)begin
                cycle();check(o_faults==expected_mask&&o_first_phase==3'(phase)&&o_flags[8:6]==3'(phase),
                    "later other causes and native phases cannot overwrite the first observation");
            end
            @(negedge user_clk);user_rst_n=0;debug_app_rst_n=0;app_hard_rst_n=0;
            repeat(3)begin
                cycle();check(o_faults==expected_mask&&o_first_phase==3'(phase),
                    "business USER and APP resets do not clear first-observed evidence");
            end
            cause_cases=cause_cases+1;
        end
        cold_clear();@(negedge user_clk);transport_observe[6:4]=3'd3;transport_observe[3]=1;memory_fault_user=1;
        cycle();check(o_faults==6&&o_first_phase==3,"first simultaneous mask retains both completion and memory causes");
        cause_cases=cause_cases+1;
        cold_clear();@(negedge user_clk);product_axil_fault=1;transport_observe[6:4]=3'd2;
        cycle();check(o_faults==8&&o_first_phase==2,"AXIL fault belongs to the product/protocol bucket");
        cause_cases=cause_cases+1;
        cold_clear();@(negedge user_clk);transport_recovery=1;transport_observe[6:4]=3'd6;
        cycle();check(o_faults==0,"protocol fallback is not invented before an observed FAULT phase");
        @(negedge user_clk);transport_observe[6:4]=3'd7;
        cycle();check(o_faults==8&&o_first_phase==7&&o_flags[8:6]==7,
            "internal protocol incident may first be observable only at FAULT7; no physical instant phase is invented");
        cause_cases=cause_cases+1;

        cold_clear();
        for(k=0;k<6;k=k+1)begin
            @(negedge user_clk);actual_c2h_valid=1;actual_c2h_ready=1;actual_c2h_last=1;user_link_up=k[0];
            cycle();check(!o_progress[0],"AXIS TLAST and link changes never masquerade as accepted SUBMIT");
        end
        @(negedge user_clk);actual_c2h_last=0;user_link_up=0;transport_observe[7]=1;
        cycle();check(o_progress[0]&&submit_events==1,"event0 registers only the real accept_submit diagnostic pulse");
        @(negedge user_clk);transport_observe[7]=0;actual_c2h_last=1;
        cycle();check(!o_progress[0]&&submit_events==1,"SUBMIT event does not repeat on later data/frame activity");
        for(k=0;k<4;k=k+1)begin
            @(negedge user_clk);jpeg_user_retire_valid=k[0];jpeg_user_retire_ready=k[1];
            cycle();check(o_progress[1]==(k==3),"event1 still means an actual retire valid/ready handshake");
        end
        cold_clear();
        $display("RESULT: PASS user_fault_observe checks=%0d cause_cases=%0d native_phases=8 submit_events=%0d business_reset_preserved=32",checks,cause_cases,submit_events);
        $finish;
    end
    initial begin #100000;$fatal(1,"USER fault observation watchdog");end
endmodule
