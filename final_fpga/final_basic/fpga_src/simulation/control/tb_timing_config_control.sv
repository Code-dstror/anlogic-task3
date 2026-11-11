`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

module timing_config_control_case #(parameter integer TRUSTED=0)(output reg done=0);
    wire base_done;
    timing_config_base #(.TRUSTED_COMMANDS(TRUSTED)) base(base_done);
    wire ref_command_ready,ref_response_valid,ref_source_ready,ref_pause_new_jobs;
    wire [39:0] ref_response_data;
    wire [1:0] ref_active_mode,ref_active_product_mode;
    wire [7:0] ref_active_quality,ref_minimum_quality;
    wire ref_adaptive_quality,ref_pixel_initialized,ref_m_config_valid,ref_s_config_ack_ready;
    wire ref_config_fault,ref_active_schema2,ref_active_legacy_gaussian;
    wire [24:0] ref_frame_budget;
    wire [15:0] ref_restart_mcus;
    wire [31:0] ref_source_session,ref_mode_epoch,ref_config_stale_ack_count;
    wire [1183:0] ref_m_config_data,ref_active_config;
    wire [5:0] ref_active_processing_enables;
    timing_config_engine_reference #(.TRUSTED_COMMANDS(TRUSTED),
        .V2_SUPPORTED_MODES(3'b101),.V2_SUPPORTED_ENABLES(6'h3f)) reference_dut(
        .clk(base.clk),.rst_n(base.rst_n),.command_data(base.command_data),
        .command_valid(base.command_valid),.command_ready(ref_command_ready),
        .response_data(ref_response_data),.response_valid(ref_response_valid),.response_ready(base.response_ready),
        .pipeline_idle(base.pipeline_idle),.frame_accept(base.frame_accept),.frame_sequence(base.frame_sequence),
        .source_ready(ref_source_ready),.pause_new_jobs(ref_pause_new_jobs),.active_mode(ref_active_mode),
        .active_quality(ref_active_quality),.minimum_quality(ref_minimum_quality),.adaptive_quality(ref_adaptive_quality),
        .frame_budget(ref_frame_budget),.restart_mcus(ref_restart_mcus),
        .source_session(ref_source_session),.mode_epoch(ref_mode_epoch),.pixel_initialized(ref_pixel_initialized),
        .m_config_data(ref_m_config_data),.m_config_valid(ref_m_config_valid),.m_config_ready(base.m_config_ready),
        .s_config_ack_data(base.s_config_ack_data),.s_config_ack_valid(base.s_config_ack_valid),
        .s_config_ack_ok(base.s_config_ack_ok),.s_config_ack_ready(ref_s_config_ack_ready),
        .config_fault(ref_config_fault),.config_stale_ack_count(ref_config_stale_ack_count),
        .active_config(ref_active_config),.active_schema2(ref_active_schema2),
        .active_legacy_gaussian(ref_active_legacy_gaussian),.active_product_mode(ref_active_product_mode),
        .active_processing_enables(ref_active_processing_enables));
    integer checks=0,eligible_cycles=0,wait_entries=0,wait_exits=0;
    integer response_stalls=0,replies=0,error_mask=0,trial,limit,index,j;
    reg [2:0] last_state=0;
    reg [31:0] rng=32'hb17ed9c1+TRUSTED;
    reg [1183:0] plan;
    reg [1023:0] saved_extension;
    reg [39:0] held_response;
    reg [31:0] expected_word;
    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"timing config TRUSTED=%0d: %s",TRUSTED,reason);end
    endtask
    task compare_outputs;
        begin
            check({base.command_ready,base.response_valid,base.source_ready,base.pause_new_jobs,
                base.active_mode,base.active_quality,base.minimum_quality,base.adaptive_quality,
                base.frame_budget,base.restart_mcus,base.source_session,base.mode_epoch,
                base.pixel_initialized,base.m_config_valid,base.s_config_ack_ready,
                base.config_fault,base.config_stale_ack_count,base.active_schema2,
                base.active_legacy_gaussian,base.active_product_mode,base.active_processing_enables}===
                {ref_command_ready,ref_response_valid,ref_source_ready,ref_pause_new_jobs,
                ref_active_mode,ref_active_quality,ref_minimum_quality,ref_adaptive_quality,
                ref_frame_budget,ref_restart_mcus,ref_source_session,ref_mode_epoch,
                ref_pixel_initialized,ref_m_config_valid,ref_s_config_ack_ready,
                ref_config_fault,ref_config_stale_ack_count,ref_active_schema2,
                ref_active_legacy_gaussian,ref_active_product_mode,ref_active_processing_enables},
                "all scalar outputs remain cycle equivalent to fixed f3fc9adb");
            check(base.response_data===ref_response_data,"all response bits remain cycle equivalent, including stalls");
            check(base.m_config_data===ref_m_config_data&&base.active_config===ref_active_config,
                "full 1184-bit remote and active tuples remain cycle equivalent");
            check(base.dut.frame_apply_eligible===
                (base.dut.state==3&&base.dut.initialized&&base.dut.remote_applied&&!base.dut.remote_fault),
                "registered eligibility equals the original current-state predicate on every edge");
        end
    endtask
    always @(posedge base.clk)begin
        if(base.rst_n&&base.response_valid&&!base.response_ready)response_stalls=response_stalls+1;
        if(base.rst_n&&base.response_valid&&base.response_ready&&base.dut.tx_state==3&&base.dut.reply_kind==3)
            error_mask=error_mask|(1<<base.response_data[2:0]);
        #1;
        compare_outputs();
        if(base.dut.frame_apply_eligible)eligible_cycles=eligible_cycles+1;
        if(base.dut.state==3&&last_state!=3)wait_entries=wait_entries+1;
        if(base.dut.state!=3&&last_state==3)wait_exits=wait_exits+1;
        last_state=base.dut.state;
    end
    // Also check combinational apply/stop outputs before the next clock edge.
    always @(negedge base.clk)begin #2;compare_outputs();end

    task send_packet(input [1:0] kind,input [31:0] sequence_value,session_value,quality_value);
        integer word_index;
        reg [31:0] value;
        begin
            base.flit({1'b1,kind==3,kind,kind!=3,3'd0,session_value});
            if(kind!=3)for(word_index=0;word_index<41;word_index=word_index+1)begin
                case(word_index)
                    0:value=sequence_value;1:value=session_value;2:value=0;3:value=quality_value;
                    4:value=1;5:value=7;6:value=12345;7:value=17;8:value=1;
                    default:value=base.extension[(word_index-9)*32+:32];
                endcase
                base.flit({1'b0,word_index==40,6'(word_index),value});
            end
        end
    endtask
    task take_reply(input [1:0] kind,input [31:0] sequence_value,third_value,last_value);
        integer word_index,stall;
        begin
            for(word_index=0;word_index<4;word_index=word_index+1)begin
                limit=0;
                while(!base.response_valid)begin @(negedge base.clk);limit=limit+1;check(limit<120,"reply is bounded");end
                held_response=base.response_data;stall=2+random_word()%6;
                repeat(stall)begin
                    @(negedge base.clk);#1;
                    base.frame_sequence=base.frame_sequence+32'h11990b07;
                    check(base.response_valid&&base.response_data===held_response,"reply stays immutable under source noise and backpressure");
                end
                case(word_index)
                    0:expected_word=base.source_session;1:expected_word=sequence_value;
                    2:expected_word=third_value;3:expected_word=last_value;
                endcase
                check(base.response_data[31:0]===expected_word,"reply carries exact session/sequence/epoch/error/frame");
                check(base.response_data[39:32]==(word_index==0?{2'b10,kind,4'd0}:{1'b0,word_index==3,6'(word_index-1)}),
                    "reply kind/index/last retain four-flit framing");
                base.response_ready=1;@(posedge base.clk);@(negedge base.clk);base.response_ready=0;
            end
            replies=replies+1;
        end
    endtask
    task boot;
        begin
            send_packet(3,0,32'h12345678,70);base.take_plan(plan);base.send_ack(plan,1);
            take_reply(0,0,0,0);check(base.pixel_initialized&&!base.dut.frame_apply_eligible,"BOOT clears frame eligibility");
        end
    endtask

    initial begin
        wait(base_done);@(negedge base.clk);
        base.reset_engine();send_packet(0,17,32'h12345678,70);
        take_reply(3,17,`PCIE_CFG_ERROR_SESSION,0);boot();
        // A well-shaped BOOT for the current session takes the decoder's
        // final INVALID branch rather than the malformed-packet branch.
        send_packet(3,0,32'h12345678,70);take_reply(3,0,`PCIE_CFG_ERROR_INVALID,0);
        base.flit({1'b1,1'b1,2'd3,1'b0,3'b001,32'h12345678});
        take_reply(3,0,`PCIE_CFG_ERROR_INVALID,0);
        send_packet(0,17,32'h12345678,0);take_reply(3,17,`PCIE_CFG_ERROR_INVALID,0);
        send_packet(0,17,32'h12345678,70);take_reply(1,17,0,0);
        send_packet(0,18,32'h12345678,70);take_reply(3,18,`PCIE_CFG_ERROR_BUSY,0);
        send_packet(1,18,32'h12345678,70);take_reply(3,18,`PCIE_CFG_ERROR_STALE,0);
        send_packet(2,17,32'h12345678,70);take_reply(0,17,0,0);
        if(!TRUSTED)begin
            saved_extension=base.extension;base.extension[9:8]=1;
            send_packet(0,17,32'h12345678,70);take_reply(3,17,`PCIE_CFG_ERROR_UNSUPPORTED,0);
            base.extension=saved_extension;base.extension[31:16]=16'h0001;
            send_packet(0,17,32'h12345678,70);take_reply(3,17,`PCIE_CFG_ERROR_INVALID,0);
            base.extension=saved_extension;
        end
        for(trial=0;trial<10;trial=trial+1)begin
            base.reset_engine();boot();
            send_packet(0,17,32'h12345678,70);take_reply(1,17,0,0);
            send_packet(1,17,32'h12345678,70);base.take_plan(plan);
            check(base.dut.state==3&&!base.dut.frame_apply_eligible,"WAIT_FRAME enters with no premature ACK eligibility");
            base.pipeline_idle=0;base.frame_accept=1;base.frame_sequence=32'h7000+trial;
            base.send_ack(plan,trial%3!=1);
            if(trial%3==1)begin
                check(base.config_fault&&!base.dut.frame_apply_eligible&&base.mode_epoch==0,
                    "matching negative ACK wins over simultaneous frame event");
                take_reply(3,17,`PCIE_CFG_ERROR_RESET,0);
            end else if(trial%3==2)begin
                check(base.dut.frame_apply_eligible&&base.mode_epoch==0,"positive ACK qualifies without inventing a frame");
                #2;base.rst_n=0;#1;
                compare_outputs();
                check(!base.source_ready&&!base.response_valid&&!base.dut.frame_apply_eligible,
                    "asynchronous reset instantly cancels an armed apply");
                repeat(3)@(negedge base.clk);base.rst_n=1;base.frame_accept=0;
                repeat(4)@(negedge base.clk);
                check(!base.pixel_initialized&&!base.response_valid,"cancelled apply cannot leak after reset");
            end else begin
                check(base.dut.frame_apply_eligible&&base.mode_epoch==0,"positive ACK registers eligibility on the original retirement edge");
                repeat(3)@(negedge base.clk);
                base.pipeline_idle=1;base.frame_sequence=32'h9000+trial;
                @(posedge base.clk);@(negedge base.clk);base.frame_accept=0;
                check(base.mode_epoch==1&&!base.dut.frame_apply_eligible,"actual accepted frame exits WAIT_FRAME exactly once");
                take_reply(2,17,1,32'h9000+trial);
                // A new BOOT clears epoch and all apply eligibility on the
                // same decision edge, rather than inheriting the last ACK.
                send_packet(3,0,32'h87654321,70);base.take_plan(plan);base.send_ack(plan,1);
                take_reply(0,0,0,0);
                check(base.source_session==32'h87654321&&!base.dut.frame_apply_eligible,"new-session BOOT clears prior apply state");
            end
            base.pipeline_idle=1;base.frame_accept=0;
        end
        check(eligible_cycles>10&&wait_entries>=11&&wait_exits>=11&&response_stalls>100,
            "eligibility transitions and reply stalls executed");
        check((error_mask&(TRUSTED?8'h5e:8'h7e))==(TRUSTED?8'h5e:8'h7e),
            "all reachable ERROR code paths executed");
        $display("RESULT: PASS timing_config_control TRUSTED=%0d checks=%0d eligible_cycles=%0d wait_entries=%0d wait_exits=%0d response_stalls=%0d replies=%0d error_mask=%02x",
            TRUSTED,checks,eligible_cycles,wait_entries,wait_exits,response_stalls,replies,error_mask);
        done=1;
    end
endmodule

module tb_timing_config_control;
    wire strict_done,trusted_done;
    timing_config_control_case #(.TRUSTED(0)) strict_case(strict_done);
    timing_config_control_case #(.TRUSTED(1)) trusted_case(trusted_done);
    initial begin wait(strict_done&&trusted_done);$display("RESULT: PASS timing_config_control_all");$finish;end
    initial begin #3000000;$fatal(1,"timing config control watchdog");end
endmodule
