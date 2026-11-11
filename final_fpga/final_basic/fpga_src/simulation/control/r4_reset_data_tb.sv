`timescale 1ns/1ps
module r4_reset_data_case #(parameter SYNC=0,COHORT=0)(output reg done=0);
    reg clk=0,clock_enable=1,local_reset_n=0,f21_reset_n=1;
    wire rst_n;
    PH1_LOGIC_BUFG u_reset_global(.i(local_reset_n),.o(rst_n));
    always #4 if(clock_enable)clk=~clk;
    reg context_fire=0,source_fire=0,source_ok=0,source_quiet=1,native_start=0;
    reg [63:0] context_tag=0,source_tag=0;
    reg [3:0] presented=0;
    reg status_ready=0,s_valid=0,m_ready=0;
    reg [15:0] s_data=0;
    wire d_reset,d_data_reset,d_pending,d_status,d_fault,d_pulse;
    wire r_reset,r_pending,r_status,r_fault,r_pulse;
    wire z_reset,z_data_reset,z_pending,z_status,z_fault,z_pulse;
    wire [31:0] d_stale,r_stale,z_stale;
    hdr_pair_product_abort_drain4 #(.SYNC_CLEAR_ENABLE(SYNC),.SEPARATE_DATA_RESET(1)) dut(
        .clk(clk),.rst_n(rst_n),.i_context_fire(context_fire),.i_context_tag(context_tag),
        .i_source_fire(source_fire),.i_source_tag(source_tag),.i_source_ok(source_ok),
        .i_source_read_quiescent(source_quiet),.i_native_job_start(native_start),
        .i_native_valid(presented[0]),.i_isp_valid(presented[1]),
        .i_preprocess_valid(presented[2]),.i_admission_valid(presented[3]),
        .o_local_rst_n(d_reset),.o_drain_pending(d_pending),.o_failed_status_valid(d_status),
        .i_failed_status_ready(status_ready),.o_protocol_fault(d_fault),
        .o_stale_source_count(d_stale),.o_cleanup_pulse(d_pulse),
        .i_data_reset_n(local_reset_n),.o_local_data_rst_n(d_data_reset));
    r4_abort_reference #(.SYNC_CLEAR_ENABLE(SYNC)) reference(
        .clk(clk),.rst_n(rst_n),.i_context_fire(context_fire),.i_context_tag(context_tag),
        .i_source_fire(source_fire),.i_source_tag(source_tag),.i_source_ok(source_ok),
        .i_source_read_quiescent(source_quiet),.i_native_job_start(native_start),
        .i_native_valid(presented[0]),.i_isp_valid(presented[1]),
        .i_preprocess_valid(presented[2]),.i_admission_valid(presented[3]),
        .o_local_rst_n(r_reset),.o_drain_pending(r_pending),.o_failed_status_valid(r_status),
        .i_failed_status_ready(status_ready),.o_protocol_fault(r_fault),
        .o_stale_source_count(r_stale),.o_cleanup_pulse(r_pulse));
    // Default must ignore even a deliberately different new input.
    hdr_pair_product_abort_drain4 #(.SYNC_CLEAR_ENABLE(SYNC)) legacy_default(
        .clk(clk),.rst_n(rst_n),.i_context_fire(context_fire),.i_context_tag(context_tag),
        .i_source_fire(source_fire),.i_source_tag(source_tag),.i_source_ok(source_ok),
        .i_source_read_quiescent(source_quiet),.i_native_job_start(native_start),
        .i_native_valid(presented[0]),.i_isp_valid(presented[1]),
        .i_preprocess_valid(presented[2]),.i_admission_valid(presented[3]),
        .o_local_rst_n(z_reset),.o_drain_pending(z_pending),.o_failed_status_valid(z_status),
        .i_failed_status_ready(status_ready),.o_protocol_fault(z_fault),
        .o_stale_source_count(z_stale),.o_cleanup_pulse(z_pulse),
        .i_data_reset_n(~local_reset_n),.o_local_data_rst_n(z_data_reset));
    wire [15:0] d_word,r_word;
    wire d_ready,r_ready,d_valid,r_valid,d_buffered,r_buffered;
    // The production boundary has only posedge ledger clear, no ASR process.
    stream_reset_boundary2 #(.WIDTH(16),.EXTERNAL_SOURCE(COHORT)) new_boundary(
        .clk(clk),.run_n(1'b1),.async_n(f21_reset_n&&d_data_reset),
        .s_data(s_data),.s_valid(s_valid),.s_ready(d_ready),
        .m_data(d_word),.m_valid(d_valid),.m_ready(m_ready),.pending(d_buffered));
    stream_reset_boundary2 #(.WIDTH(16),.EXTERNAL_SOURCE(COHORT)) old_boundary(
        .clk(clk),.run_n(1'b1),.async_n(f21_reset_n&&r_reset),
        .s_data(s_data),.s_valid(s_valid),.s_ready(r_ready),
        .m_data(r_word),.m_valid(r_valid),.m_ready(m_ready),.pending(r_buffered));
    integer checks=0,cycles=0,guard=0,clears=0;
    task check(input bit pass,input [255:0] label_text);
        begin checks=checks+1;if(!pass)$fatal(1,"sync%0d cohort%0d %0s",SYNC,COHORT,label_text);end
    endtask
    task compare;
        begin
            check({d_reset,d_pending,d_status,d_fault,d_stale,d_pulse} ===
                  {r_reset,r_pending,r_status,r_fault,r_stale,r_pulse},"all original outputs equal R3");
            check({z_reset,z_pending,z_status,z_fault,z_stale,z_pulse} ===
                  {r_reset,r_pending,r_status,r_fault,r_stale,r_pulse},"default compatibility");
            check(d_data_reset===r_reset&&z_data_reset===r_reset,"same-value data copy");
            check({d_ready,d_valid,d_buffered}==={r_ready,r_valid,r_buffered},"boundary control equal");
            if(d_valid)check(d_word===r_word,"owned payload equality");
        end
    endtask
    always @(posedge clk)begin cycles=cycles+1;#0.1;compare();end
    always @(negedge clk)begin #0.1;compare();end
    task ticks(input integer n);begin repeat(n)begin @(posedge clk);#0.2;end end endtask
    task launch_bad(input [63:0] tag_value);
        begin
            @(negedge clk);context_tag=tag_value;context_fire=1;ticks(1);
            @(negedge clk);context_fire=0;native_start=1;presented=4'b1001;ticks(1);
            @(negedge clk);native_start=0;source_tag=tag_value;source_fire=1;source_ok=0;ticks(1);
            @(negedge clk);source_fire=0;
            repeat(7)begin ticks(1);check(d_reset&&d_pending,"presented frame holds clear");end
            @(negedge clk);presented=0;
            guard=0;while(d_reset)begin ticks(1);guard=guard+1;check(guard<20,"clear bounded");end
            clears=clears+1;
        end
    endtask
    initial begin
        #(COHORT*1.0);ticks(3);local_reset_n=1;ticks(3);
        @(negedge clk);s_valid=1;s_data=16'h8123;ticks(3);
        check(d_buffered&&d_valid,"queue full with downstream stall");
        @(negedge clk);s_valid=0;clock_enable=0;
        #1;local_reset_n=0;#0.2;compare();
        check(COHORT ? !d_ready : !d_valid,"stopped-clock immediate withdrawal");
        #1;local_reset_n=1;#0.2;compare(); // narrow pulse, no edge: do not claim ledger flush
        #7;local_reset_n=0;#0.2;compare();
        #9;clock_enable=1;ticks(2);local_reset_n=1;ticks(2);
        check(!d_buffered&&!d_valid,"reset held through edge clears old ledger");
        @(negedge clk);s_valid=1;s_data=16'h0246;m_ready=1;ticks(8);
        @(negedge clk);s_valid=0;ticks(3);
        // Keep both the independent F21 reset term and cleanup term live.
        f21_reset_n=0;#0.2;compare();ticks(2);f21_reset_n=1;ticks(2);
        launch_bad(64'h100+COHORT);
        guard=0;while(!d_status)begin ticks(1);guard=guard+1;check(guard<20,"status bounded");end
        repeat(6)begin ticks(1);check(d_status,"failed status stall preserved");end
        @(negedge clk);status_ready=1;ticks(3);
        check(!d_pending&&d_reset,"cleanup retires to idle");
        @(negedge clk);source_tag=64'hbad;source_fire=1;ticks(1);
        @(negedge clk);source_fire=0;ticks(2);check(d_stale==1,"stale source tracked");
        launch_bad(64'h200+COHORT);
        @(negedge clk);local_reset_n=0;#0.2;compare();ticks(3);
        local_reset_n=1;ticks(5);check(!d_pending&&!d_status&&!d_fault&&d_stale==0,"reset during clear recovers");
        $display("RESULT: PASS r4_reset_data_case sync=%0d cohort=%0d cycles=%0d checks=%0d clear_windows=%0d",SYNC,COHORT,cycles,checks,clears);
        done=1;
    end
endmodule
module r4_reset_data_tb;
    wire [3:0] done;
    r4_reset_data_case #(.SYNC(0),.COHORT(0)) a(done[0]);
    r4_reset_data_case #(.SYNC(0),.COHORT(1)) b(done[1]);
    r4_reset_data_case #(.SYNC(1),.COHORT(0)) c(done[2]);
    r4_reset_data_case #(.SYNC(1),.COHORT(1)) d(done[3]);
    initial begin wait(&done);$display("RESULT: PASS r4_reset_data_all");$finish;end
    initial begin #20000;$fatal(1,"timeout");end
endmodule
