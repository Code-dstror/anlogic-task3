`timescale 1ns/1ps
module r4_fork_payload_case #(parameter integer WIDTH=130)(output reg done=0);
    reg clk=0,rst_n=0,clear=0,s_valid=0;
    reg [1:0] destinations=0,m_ready=0;
    reg [WIDTH-1:0] s_payload=0;
    wire s_ready,ref_ready;
    wire [1:0] m_valid,ref_valid;
    wire [WIDTH-1:0] payload0,payload1,ref_payload0,ref_payload1;
    stage3_stream_fork2 #(.WIDTH(WIDTH)) dut(clk,rst_n,clear,destinations,s_valid,s_ready,s_payload,
        m_valid,m_ready,payload0,payload1);
    r4_fork_reference #(.WIDTH(WIDTH)) refdut(clk,rst_n,clear,destinations,s_valid,ref_ready,s_payload,
        ref_valid,m_ready,ref_payload0,ref_payload1);
    reg [WIDTH-1:0] queue0[0:65535],queue1[0:65535];
    integer rd0=0,wr0=0,rd1=0,wr1=0;
    integer checks=0,cycles=0,pushes=0,pops0=0,pops1=0,simultaneous=0;
    integer full_stalls=0,held_checks=0,hidden_differences=0,stopped_clear=0,stopped_reset=0;
    integer mask,index,bit_index;
    reg [31:0] rng=32'haf1d0973+WIDTH;
    reg old_owned0,old_owned1;
    reg [WIDTH-1:0] old_storage0,old_storage1;
    function [31:0] random_word;
        begin rng=rng*32'd1664525+32'd1013904223;random_word=rng;end
    endfunction
    task check(input bit ok,input string why);
        begin checks=checks+1;if(!ok)$fatal(1,"fork WIDTH=%0d cycle=%0d: %s",WIDTH,cycles,why);end
    endtask
    task compare;
        begin
            check({s_ready,m_valid,dut.count0,dut.count1,dut.write_index,dut.read_index0,
                dut.read_index1,dut.run,dut.reset_release}===
                {ref_ready,ref_valid,refdut.count0,refdut.count1,refdut.write_index,refdut.read_index0,
                refdut.read_index1,refdut.run,refdut.reset_release},"all public and internal ownership/control bits");
            if(m_valid[0])begin
                check(payload0===ref_payload0,"consumer0 all valid payload bits vs fixed R3");
                check(rd0<wr0&&payload0===queue0[rd0],"consumer0 independent queue including stall");
            end
            if(m_valid[1])begin
                check(payload1===ref_payload1,"consumer1 all valid payload bits vs fixed R3");
                check(rd1<wr1&&payload1===queue1[rd1],"consumer1 independent queue including stall");
            end
            if(dut.storage0!==refdut.storage0||dut.storage1!==refdut.storage1)
                hidden_differences=hidden_differences+1;
        end
    endtask
    task payload_random;
        begin for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1)s_payload[bit_index]=random_word()>>18;end
    endtask
    task step;
        begin
            #1;compare();
            old_owned0=(refdut.count0!=0&&!refdut.read_index0)||refdut.count0==2||
                       (refdut.count1!=0&&!refdut.read_index1)||refdut.count1==2;
            old_owned1=(refdut.count0!=0&&refdut.read_index0)||refdut.count0==2||
                       (refdut.count1!=0&&refdut.read_index1)||refdut.count1==2;
            old_storage0=dut.storage0;old_storage1=dut.storage1;
            if(!rst_n||!refdut.reset_release[2]||!refdut.run||clear)begin
                rd0=0;wr0=0;rd1=0;wr1=0;
            end else begin
                if(m_valid[0]&&m_ready[0])begin rd0=rd0+1;pops0=pops0+1;end
                if(m_valid[1]&&m_ready[1])begin rd1=rd1+1;pops1=pops1+1;end
                if(s_valid&&s_ready)begin
                    pushes=pushes+1;
                    if((m_valid&m_ready)!=0)simultaneous=simultaneous+1;
                    if(destinations[0])begin queue0[wr0]=s_payload;wr0=wr0+1;end
                    if(destinations[1])begin queue1[wr1]=s_payload;wr1=wr1+1;end
                end
                if(s_valid&&!s_ready)full_stalls=full_stalls+1;
            end
            #2;clk=1;cycles=cycles+1;#1;
            if(old_owned0===1'b1)begin check(dut.storage0===old_storage0,"owned physical slot0 holds");held_checks=held_checks+1;end
            if(old_owned1===1'b1)begin check(dut.storage1===old_storage1,"owned physical slot1 holds");held_checks=held_checks+1;end
            compare();#1;clk=0;
        end
    endtask
    task boot;
        begin
            rst_n=0;clear=0;s_valid=0;m_ready=0;
            repeat(2)step();rst_n=1;repeat(7)step();
        end
    endtask
    initial begin
        boot();
        for(mask=0;mask<4;mask=mask+1)begin
            // Destinations are frame-stable in both real filter adapters.
            clear=1;step();clear=0;destinations=mask;
            s_valid=1;m_ready=0;repeat(5)begin payload_random();step();end
            // One cursor can stall while the other drains; full blocks push.
            m_ready=1;repeat(9)begin payload_random();step();end
            m_ready=2;repeat(9)begin payload_random();step();end
            m_ready=3;repeat(20)begin payload_random();step();end
            // Clear masks VALID even with a stopped clock; ownership flushes
            // only on the original edge, including clear during a full stall.
            m_ready=0;repeat(4)step();clear=1;#11;compare();
            check(m_valid==0&&s_ready==0,"stopped-clock clear immediately masks handshakes");
            stopped_clear=stopped_clear+1;step();clear=0;step();
            // A narrow asynchronous reset while stopped is retained by the
            // original release pipe; no stale owned payload revives.
            repeat(4)step();rst_n=0;#3;compare();rst_n=1;#7;compare();
            stopped_reset=stopped_reset+1;repeat(7)step();
            for(index=0;index<16000;index=index+1)begin
                payload_random();s_valid=(random_word()>>15)%4!=0;
                m_ready=random_word()>>13;clear=(random_word()>>11)%211==0;
                if(index%997==996)begin rst_n=0;step();rst_n=1;end
                step();
            end
            clear=0;s_valid=0;m_ready=3;repeat(8)step();
            check(rd0==wr0&&rd1==wr1,"both independent destination queues drained");
        end
        check(pushes>1000&&pops0>1000&&pops1>1000&&simultaneous>1000,"meaningful transfers and pop/refill");
        check(full_stalls>1000&&held_checks>1000&&hidden_differences>1000,"held slots and hidden payload differences exercised");
        $display("RESULT: PASS r4_fork WIDTH=%0d checks=%0d cycles=%0d pushes=%0d pops=%0d/%0d simultaneous=%0d full_stalls=%0d held=%0d hidden=%0d stopped_clear=%0d stopped_reset=%0d",WIDTH,checks,cycles,pushes,pops0,pops1,simultaneous,full_stalls,held_checks,hidden_differences,stopped_clear,stopped_reset);
        done=1;
    end
endmodule
module r4_fork_payload_tb;
    wire done0,done1,done2;
    r4_fork_payload_case #(.WIDTH(130)) c0(done0);
    r4_fork_payload_case #(.WIDTH(274)) c1(done1);
    r4_fork_payload_case #(.WIDTH(322)) c2(done2);
    initial begin wait(done0&&done1&&done2);$display("RESULT: PASS r4_fork_all");$finish;end
    initial begin #1000000;$fatal(1,"fork timeout");end
endmodule
