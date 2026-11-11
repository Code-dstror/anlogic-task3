`timescale 1ns/1ps
`include "pcie_protocol_v1.vh"

// Compare publication, handshakes and counters against the frozen RTL. Payload
// while VALID=0 is intentionally unspecified by the speculative implementation.
module timing_extension_case #(parameter integer STATS=1)(output reg done=0);
    reg i_clk=0;
    always #4 i_clk=~i_clk;
    reg i_rst_n=0,s_begin_valid=0,s_stats_valid=0,m_extension_ready=0;
    reg [31:0] i_source_session=1,i_source_epoch=0,i_source_sequence=0;
    reg [7:0] i_source_camera=0,i_source_kind=0,i_source_format=1;
    reg [7:0] i_exposure_role=0,i_time_quality=0,i_processing_member=0,i_processing_mode=0;
    reg i_exposure_valid=0,i_gain_valid=0,i_calibration_valid=0,i_pair_valid=0;
    reg i_job_valid=0,i_write_tag_valid=0,i_qualified=0;
    reg [31:0] i_actual_exposure=0,i_exposure_group=0,i_actual_gain=0,i_calibration_id=0;
    reg [63:0] i_pair_id=0,i_job_id=0,i_write_tag=0;
    reg [15:0] i_record_flags=0;
    reg [159:0] s_stats_context=0;
    reg [183:0] s_statistics=0;
    wire o_begin_ready,o_stats_ready,m_extension_valid,o_input_fault;
    wire [1023:0] m_extension_data;
    wire [31:0] o_stale_count,o_error_count;
    wire ref_begin_ready,ref_stats_ready,ref_extension_valid,ref_input_fault;
    wire [1023:0] ref_extension_data;
    wire [31:0] ref_stale_count,ref_error_count;
    frame_record_extension_builder #(.NEUTRAL_STATS_ENABLE(STATS),
        .OBSERVATION_WIDTH(4),.OBSERVATION_HEIGHT(3)) dut(.*);
    timing_extension_reference #(.NEUTRAL_STATS_ENABLE(STATS),
        .OBSERVATION_WIDTH(4),.OBSERVATION_HEIGHT(3)) reference_dut(
        .o_begin_ready(ref_begin_ready),.o_stats_ready(ref_stats_ready),
        .m_extension_valid(ref_extension_valid),.m_extension_data(ref_extension_data),
        .o_stale_count(ref_stale_count),.o_error_count(ref_error_count),
        .o_input_fault(ref_input_fault),.*);

    integer checks=0,published=0,stall_checks=0,aborted_wait=0,aborted_present=0;
    integer bad_sources=0,incomplete_results=0,stale_in_wait=0;
    integer transaction,variant,k,waits;
    reg [31:0] rng=32'h83d1971a+STATS;
    reg [159:0] admitted_context;
    reg [31:0] old_stale,old_errors;
    reg was_stalled;
    reg [1023:0] held_data;

    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    function [159:0] source_context;
        begin source_context={16'd1,16'd0,8'd1,i_source_format,i_source_kind,
            i_source_camera,i_source_sequence,i_source_epoch,i_source_session};end
    endfunction
    task check(input bit condition,input string reason);
        begin checks=checks+1;if(!condition)$fatal(1,"extension STATS=%0d: %s",STATS,reason);end
    endtask
    task cycle;
        begin @(negedge i_clk);#1;end
    endtask
    task good_source(input integer sequence_number);
        begin
            i_source_session=32'h7a000001+sequence_number;
            i_source_epoch=32'h15170000+sequence_number;
            i_source_sequence=sequence_number;
            i_source_camera=sequence_number%2;i_source_kind=(sequence_number/2)%2;
            i_source_format=sequence_number%2 ? 2 : 1;
            i_exposure_role=sequence_number%3;i_time_quality=sequence_number%3;
            i_processing_member=sequence_number%2;i_processing_mode=8'h20+sequence_number;
            i_exposure_valid=sequence_number[0];i_gain_valid=sequence_number[1];
            i_calibration_valid=sequence_number[2];i_pair_valid=sequence_number[3];
            i_job_valid=sequence_number[4];i_write_tag_valid=sequence_number[5];i_qualified=sequence_number[6];
            i_actual_exposure=random_word();i_exposure_group=random_word();
            i_actual_gain=random_word();i_calibration_id=random_word();
            i_pair_id={random_word(),random_word()}|64'd1;
            i_job_id={random_word(),random_word()};i_write_tag={random_word(),random_word()};
            i_record_flags=sequence_number%8;
        end
    endtask
    task complete_stats;
        begin
            s_statistics=0;s_statistics[15:0]=12;s_statistics[31:16]=12;
            s_statistics[63:32]=32'd1000;s_statistics[79:64]=2;s_statistics[95:80]=3;
            s_statistics[103:96]=8;s_statistics[111:104]=100;
            s_statistics[127:112]=16'h3291;s_statistics[143:128]=4;s_statistics[159:144]=3;
            s_statistics[167:160]=1;s_statistics[175:168]=0;s_statistics[183:176]=1;
        end
    endtask
    task damage_stats(input integer field);
        begin
            case(field)
                0:s_statistics[15:0]=11;
                1:s_statistics[31:16]=11;
                2:s_statistics[143:128]=5;
                3:s_statistics[159:144]=4;
                4:s_statistics[167:160]=0;
                5:s_statistics[175:168]=1;
                6:s_statistics[183:176]=0;
                7:s_statistics[103:96]=101;
                8:s_statistics[79:64]=13;
                9:s_statistics[95:80]=13;
                10:s_statistics[63:32]=3061;
            endcase
        end
    endtask
    task reset_case;
        begin
            i_rst_n=0;s_begin_valid=0;s_stats_valid=0;m_extension_ready=0;
            #1;check(!m_extension_valid&&!o_begin_ready&&!o_stats_ready,"asynchronous reset immediately hides publication and handshakes");
            repeat(2)cycle();i_rst_n=1;cycle();
            check(o_begin_ready&&!m_extension_valid&&!o_input_fault,"reset restores idle without stale publication");
        end
    endtask
    task begin_case(input integer sequence_number);
        begin
            check(o_begin_ready,"begin is accepted only at the idle boundary");
            good_source(sequence_number);admitted_context=source_context();
            s_begin_valid=1;cycle();s_begin_valid=0;
            check(!o_begin_ready&&!o_input_fault,"accepted source owns the builder");
            if(STATS)check(!m_extension_valid,"statistics-enabled frame waits");
            else check(m_extension_valid,"no-statistics frame publishes on the original edge");
        end
    endtask
    task publish_stats(input bit incomplete);
        begin
            s_stats_context=admitted_context;complete_stats();
            if(incomplete)damage_stats(variant%11);
            s_stats_valid=1;cycle();s_stats_valid=0;
            check(m_extension_valid&&!o_input_fault,"matching statistics close waiting on the original edge");
            check(m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_CONTEXT-64)*8+:160]==admitted_context,
                "published context retains the accepted source");
            check(m_extension_data[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-64)*8+`PCIE_RECORD_V2_FLAG_NEUTRAL_CONTEXT],
                "matching context is explicitly valid");
            check(m_extension_data[(`PCIE_RECORD_V2_OFFSET_VALIDITY_FLAGS-64)*8+`PCIE_RECORD_V2_FLAG_NEUTRAL_STATS]==!incomplete,
                "only complete accepted statistics set their validity flag");
            if(incomplete)begin
                incomplete_results=incomplete_results+1;
                check(m_extension_data[(`PCIE_RECORD_V2_OFFSET_NEUTRAL_SAMPLED-64)*8+:184]==0,
                    "incomplete accepted statistics publish canonical zero");
            end
        end
    endtask
    task consume_case(input integer stall_cycles);
        begin
            check(m_extension_valid,"record is present before a stall");
            for(k=0;k<stall_cycles;k=k+1)begin
                good_source(random_word()%32768);s_stats_context={5{random_word()}};
                complete_stats();s_stats_valid=k%2;cycle();
                check(m_extension_valid,"unrelated inputs cannot retract a stalled record");
            end
            s_stats_valid=0;m_extension_ready=1;cycle();m_extension_ready=0;
            check(o_begin_ready&&!m_extension_valid,"one terminal handshake releases the record");
        end
    endtask

    always @(posedge i_clk)begin
        was_stalled=i_rst_n&&m_extension_valid&&!m_extension_ready;
        held_data=m_extension_data;
        if(i_rst_n&&m_extension_valid&&m_extension_ready)published=published+1;
        #1;
        check({o_begin_ready,o_stats_ready,m_extension_valid,o_input_fault}===
              {ref_begin_ready,ref_stats_ready,ref_extension_valid,ref_input_fault},
              "cycle-equivalent handshake, publication and fault outputs");
        check({o_stale_count,o_error_count}==={ref_stale_count,ref_error_count},
              "stale/error counters retain original precedence and reset");
        if(m_extension_valid)check(m_extension_data===ref_extension_data,
              "every published byte equals the frozen implementation");
        if(was_stalled)begin
            stall_checks=stall_checks+1;
            check(m_extension_valid&&m_extension_data===held_data,"PRESENT stall preserves all 1024 payload bits");
        end
    end

    initial begin
        repeat(3)cycle();i_rst_n=1;cycle();
        // Statistics simultaneous with BEGIN were stale before this change and
        // cannot be consumed early by speculative sampling.
        old_stale=o_stale_count;s_stats_valid=1;complete_stats();
        begin_case(127);s_stats_valid=0;
        check(o_stale_count==old_stale+1,"same-edge BEGIN statistics remain stale");
        if(STATS)begin
            // A complete unaccepted payload must not leave a valid-statistics
            // flag behind when the accepted payload is incomplete.
            good_source(777);s_stats_context=~admitted_context;complete_stats();
            repeat(3)begin cycle();check(dut.expected_context==admitted_context,"speculative stats cannot replace the source identity");end
            old_stale=o_stale_count;s_stats_valid=1;cycle();s_stats_valid=0;
            stale_in_wait=stale_in_wait+1;
            check(o_stale_count==old_stale+1&&!m_extension_valid,"mismatched context is counted and keeps waiting");
            variant=0;old_errors=o_error_count;publish_stats(1);
            check(o_error_count==old_errors+1,"true incomplete statistics count one error");
        end
        consume_case(7);
        if(STATS)for(variant=1;variant<11;variant=variant+1)begin
            begin_case(100+variant);complete_stats();s_stats_context=~admitted_context;
            cycle();publish_stats(1);consume_case(2);
        end

        // Every source-shape rejection stays faulted and never exposes the
        // speculative bank. Only reset can admit another frame.
        for(variant=0;variant<9;variant=variant+1)begin
            reset_case();good_source(123);
            case(variant)
                0:i_source_session=0;
                1:i_source_camera=2;
                2:i_source_kind=2;
                3:i_source_format=0;
                4:i_exposure_role=3;
                5:i_time_quality=3;
                6:i_processing_member=2;
                7:i_record_flags=8;
                8:begin i_pair_valid=1;i_pair_id=0;end
            endcase
            s_begin_valid=1;cycle();s_begin_valid=0;bad_sources=bad_sources+1;
            check(o_input_fault&&!m_extension_valid&&!o_begin_ready&&o_error_count==1,"bad SOURCE is rejected exactly once");
            good_source(151);s_stats_valid=1;complete_stats();repeat(3)cycle();s_stats_valid=0;
            check(o_input_fault&&!m_extension_valid&&!o_begin_ready,"FAULT never publishes speculative bytes");
        end
        reset_case();

        for(transaction=0;transaction<160;transaction=transaction+1)begin
            begin_case(transaction+200);
            if(STATS)begin
                waits=random_word()%7;
                for(variant=0;variant<waits;variant=variant+1)begin
                    good_source(random_word()%32768);s_stats_context=admitted_context^160'h100;
                    complete_stats();s_stats_valid=variant%2;cycle();
                    check(!m_extension_valid&&dut.expected_context==admitted_context,"noise while waiting cannot publish or corrupt identity");
                    if(s_stats_valid)stale_in_wait=stale_in_wait+1;
                end
                s_stats_valid=0;
            end
            if(STATS&&transaction%13==0)begin
                aborted_wait=aborted_wait+1;reset_case();
            end else begin
                if(STATS)begin variant=transaction%11;publish_stats(transaction%4==0);end
                if(transaction%17==0)begin
                    aborted_present=aborted_present+1;#2;reset_case();
                end else consume_case(random_word()%8);
            end
        end
        check(published>100&&stall_checks>100&&bad_sources==9,"meaningful publication, stalls and fault cases all executed");
        if(STATS)check(incomplete_results>20&&aborted_wait>5&&stale_in_wait>20,"statistics failures and reset-while-waiting executed");
        check(aborted_present>5,"reset during PRESENT executed");
        $display("RESULT: PASS timing_extension_builder STATS=%0d checks=%0d published=%0d stalls=%0d bad_sources=%0d incomplete=%0d reset_wait=%0d reset_present=%0d stale_wait=%0d",
            STATS,checks,published,stall_checks,bad_sources,incomplete_results,aborted_wait,aborted_present,stale_in_wait);
        done=1;
    end
endmodule

module tb_timing_extension_builder;
    wire plain_done,stats_done;
    timing_extension_case #(.STATS(0)) plain_case(plain_done);
    timing_extension_case #(.STATS(1)) stats_case(stats_done);
    initial begin wait(plain_done&&stats_done);$display("RESULT: PASS timing_extension_builder_all");$finish;end
    initial begin #1000000;$fatal(1,"extension builder watchdog");end
endmodule
