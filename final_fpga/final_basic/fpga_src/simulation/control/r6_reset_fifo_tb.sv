`timescale 1ns/1ps

// Each payload includes its cohort and sequence; every accepted word is checked.
module r6_reset_fifo_case #(parameter KIND=0,PHASE=0)(output reg done=0);
    localparam WIDTH=KIND==1 ? 617 : 147;
    localparam FLITS=(WIDTH+39)/40;
    reg source_clk=0,sink_clk=0,source_clock_run=1,sink_clock_run=1;
    reg source_rst_n=1,sink_rst_n=1;
    wire cohort_rst_n=source_rst_n&&sink_rst_n;
    always #4 source_clk=source_clock_run ? !source_clk : 0;
    initial begin #PHASE;forever #5 sink_clk=sink_clock_run ? !sink_clk : 0;end
    integer cohort=0,sent=0,received=0,limit=0,source_edges=0,sink_edges=0;
    integer checks=0,events=0,last_fire=0,measured_gaps=0;
    reg source_enable=0,drain_enable=0,backpressure=0,measure=0;
    wire source_valid=source_enable&&sent<limit;
    wire sink_ready=drain_enable&&(!backpressure||((sink_edges%7)>1&&(sink_edges%11)!=3));
    wire source_ready,source_done,sink_valid,sink_done;
    wire [WIDTH-1:0] source_data,sink_data;
    reg stalled=0;
    reg [WIDTH-1:0] stalled_data;

    function [WIDTH-1:0] payload(input integer epoch,input integer sequence_id);
        integer k;
        begin
            for(k=0;k<WIDTH;k=k+1)payload[k]=((k*13+sequence_id*7+epoch*3)%17)<8;
            payload[63:0]={epoch[31:0],sequence_id[31:0]};
        end
    endfunction
    assign source_data=payload(cohort,sent);
    generate if(KIND==2)begin:g_axis
        axis_frame_fifo_ip dut(.i_source_clk(source_clk),.i_source_rst_n(source_rst_n),
            .i_source_data(source_data),.i_source_valid(source_valid),.o_source_ready(source_ready),
            .o_source_reset_done(source_done),.i_sink_clk(sink_clk),.i_sink_rst_n(sink_rst_n),
            .o_sink_data(sink_data),.o_sink_valid(sink_valid),.i_sink_ready(sink_ready),.o_sink_reset_done(sink_done));
    end else begin:g_control
        control_message_fifo_ip #(.MESSAGE_WIDTH(WIDTH),.BORROW_SOURCE(KIND==1)) dut(
            .i_source_clk(source_clk),.i_source_rst_n(source_rst_n),.i_source_data(source_data),
            .i_source_valid(source_valid),.o_source_ready(source_ready),.o_source_reset_done(source_done),
            .i_sink_clk(sink_clk),.i_sink_rst_n(sink_rst_n),.o_sink_data(sink_data),
            .o_sink_valid(sink_valid),.i_sink_ready(sink_ready),.o_sink_reset_done(sink_done));
    end endgenerate

    task check(input bit condition,input string why);
        begin checks=checks+1;if(!condition)$fatal(1,"kind=%0d phase=%0d cohort=%0d %s",KIND,PHASE,cohort,why);end
    endtask
    always @(posedge source_clk or negedge cohort_rst_n)begin
        if(!cohort_rst_n)begin sent<=0;source_edges<=0;last_fire<=0;measured_gaps<=0;end
        else begin
            source_edges<=source_edges+1;
            if(source_valid&&source_ready)begin
                if(measure&&sent!=0)begin
                    check(source_edges-last_fire==(KIND==2 ? 1 : FLITS+(KIND==0)),"unchanged no-bubble source throughput");
                    measured_gaps<=measured_gaps+1;
                end
                sent<=sent+1;last_fire<=source_edges;
            end
        end
    end
    always @(posedge sink_clk or negedge cohort_rst_n)begin
        if(!cohort_rst_n)begin received<=0;sink_edges<=0;stalled<=0;end
        else begin
            sink_edges<=sink_edges+1;
            if(stalled&&sink_done)check(sink_valid&&sink_data===stalled_data,"valid and full payload remain stable under finite stall");
            stalled<=sink_valid&&!sink_ready;
            stalled_data<=sink_data;
            if(sink_valid&&sink_ready)begin
                check(received<sent,"no unsolicited or duplicated message after reset");
                check(sink_data===payload(cohort,received),"full payload and cohort/sequence order");
                received<=received+1;
            end
        end
    end
    task await_ready;
        integer guard;
        begin
            guard=0;
            while((!source_done||!sink_done)&&guard<80)begin @(negedge source_clk);guard=guard+1;end
            check(source_done&&sink_done,"both ports eventually ready within80 resumed source edges");
        end
    endtask
    task await_sent;
        integer guard;
        begin
            guard=0;
            while(sent<limit&&guard<1200)begin @(negedge source_clk);guard=guard+1;end
            check(sent==limit,"all requested messages accepted");
        end
    endtask
    task drain;
        integer guard;
        begin
            drain_enable=1;guard=0;
            while(received<limit&&guard<1200)begin @(negedge sink_clk);guard=guard+1;end
            check(received==limit,"all accepted messages delivered after finite backpressure");
            repeat(6)@(negedge sink_clk);
            check(!sink_valid,"no trailing message from previous cohort");
        end
    endtask
    task queue_old;
        begin
            drain_enable=0;source_enable=1;limit=sent+3;await_sent();
            // Include a held output and further queued flits at each reset.
            repeat(FLITS+10)@(negedge sink_clk);
            check(sink_valid,"old cohort has a held output before reset");
            source_enable=0;
        end
    endtask
    task assert_reset(input integer reset_side);
        begin
            source_enable=0;limit=0;drain_enable=0;cohort=cohort+1;
            if(reset_side==0)source_rst_n=0;else sink_rst_n=0;
            #0.1;check(!source_ready&&!source_done&&!sink_valid&&!sink_done,"public isolation asserts without either clock");
        end
    endtask
    task release_reset;
        begin source_rst_n=1;sink_rst_n=1;end
    endtask
    task stop_clock(input integer stop_side);
        begin if(stop_side==0)source_clock_run=0;else sink_clock_run=0;end
    endtask
    task stop_after_edges(input integer stop_side,input integer edges);
        integer k;
        begin
            for(k=0;k<edges;k=k+1)begin
                if(stop_side==0)@(posedge source_clk);else @(posedge sink_clk);
                #0.2;
            end
            stop_clock(stop_side);
        end
    endtask
    task recover_and_transfer;
        begin
            source_clock_run=1;sink_clock_run=1;await_ready();
            limit=7;source_enable=1;backpressure=1;drain_enable=1;await_sent();drain();
            source_enable=0;backpressure=0;events=events+1;
        end
    endtask
    integer side,reset_side,phase_step;
    initial begin
        // Late initial clocks in both directions, then both-clock short pulse.
        #1;source_clock_run=0;assert_reset(0);#21;release_reset();#100;
        recover_and_transfer();
        queue_old();@(negedge sink_clk);sink_clock_run=0;assert_reset(1);#21;release_reset();#100;
        recover_and_transfer();
        for(side=0;side<2;side=side+1)begin
            for(reset_side=0;reset_side<2;reset_side=reset_side+1)begin
                for(phase_step=0;phase_step<13;phase_step=phase_step+1)begin
                    queue_old();
                    if(side==0)@(negedge source_clk);else @(negedge sink_clk);
                    #0.3;assert_reset(reset_side);
                    if(phase_step<4)begin
                        // Stop before, or1/2/3 edges after assertion; includes
                        // R5's one-last-edge counterexample, in both directions.
                        stop_after_edges(side,phase_step);#41;release_reset();
                    end else begin
                        // A1ns pulse may fit between both clocks' edges. Stop
                        // at every release/peer-sync/reset-pin transition.
                        #0.9;release_reset();stop_after_edges(side,phase_step-4);
                    end
                    #100;recover_and_transfer();
                end
            end
        end
        queue_old();@(negedge source_clk);source_clock_run=0;sink_clock_run=0;
        assert_reset(0);#0.9;release_reset();#51;
        source_clock_run=1;repeat(20)@(negedge source_clk);
        check(!source_done,"running source waits for stopped sink to sample reset");
        recover_and_transfer();
        queue_old();@(negedge sink_clk);source_clock_run=0;sink_clock_run=0;
        assert_reset(1);#0.9;release_reset();#51;
        sink_clock_run=1;repeat(20)@(negedge sink_clk);
        check(!sink_done,"running sink waits for stopped source to sample reset");
        recover_and_transfer();
        // Reset interrupts a borrowed/captured message before its last flit.
        if(KIND!=2)begin
            limit=sent+1;source_enable=1;drain_enable=0;
            repeat(2)@(negedge source_clk);source_clock_run=0;
            assert_reset(0);#0.9;release_reset();#100;recover_and_transfer();
        end
        // A continuous producer checks source throughput independently of
        // deliberately inserted sink stalls. The64-word burst cannot fill512.
        // Start a clean cohort so the first interval has no deliberate pause.
        @(negedge source_clk);assert_reset(0);#0.9;release_reset();await_ready();
        limit=64;source_enable=1;drain_enable=1;measure=1;await_sent();drain();
        check(measured_gaps==63,"all consecutive source acceptance intervals measured");
        source_enable=0;
        $display("RESULT: PASS FIFO_RESET kind=%0d phase=%0d reset_events=%0d checks=%0d throughput_gaps=%0d",KIND,PHASE,events,checks,measured_gaps);
        done=1;
    end
endmodule

module r6_reset_fifo_tb;
    wire [11:0] done;
    genvar kind,phase_id;
    generate for(kind=0;kind<3;kind=kind+1)begin:k
        for(phase_id=0;phase_id<4;phase_id=phase_id+1)begin:p
            r6_reset_fifo_case #(.KIND(kind),.PHASE(phase_id)) test_case(done[kind*4+phase_id]);
        end
    end endgenerate
    initial begin wait(&done);$display("RESULT: PASS r6_reset_fifo_tb");$finish;end
    initial begin #500000;$fatal(1,"bounded reset/traffic test watchdog");end
endmodule
