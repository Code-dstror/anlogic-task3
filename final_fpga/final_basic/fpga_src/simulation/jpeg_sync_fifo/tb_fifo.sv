`timescale 1ns/1ps
module tb_fifo;
    reg clk=0,clock_enable=1;always #4 if(clock_enable)clk=!clk;
    reg rst_n=0,s_valid=0,m_ready=0;
    reg [146:0] s_data=0;
    wire s_ready,m_valid,reset_done;
    wire [146:0] m_data;
    wire [9:0] resident;
    jpeg_quant_sync_fifo dut(clk,rst_n,s_data,s_valid,s_ready,m_data,m_valid,m_ready,reset_done,resident);
    reg [146:0] expected[0:65535];
    integer head=0,tail=0,checks=0,full_swaps=0,stream_cycles=0,cycles=0;
    reg held_valid=0;reg [146:0] held;
    reg streaming=0;
    reg [31:0] rng=32'h53181972;
    always @(negedge rst_n)begin head=0;tail=0;held_valid=0;end
    function [146:0] word_for(input integer n);
        word_for={2'(n%3),1'(n%9==8),16'hffff,32'(n^32'h93ac712f),32'(n/77),32'(n*41),32'(n)};
    endfunction
    always @(posedge clk)begin
        cycles=cycles+1;if(cycles>30000)$fatal(1,"FIFO timeout");
        if(!rst_n)begin head=0;tail=0;held_valid=0;end
        else if(reset_done)begin
            if(held_valid && (!m_valid || m_data!==held))$fatal(1,"held output changed");
            held_valid=m_valid&&!m_ready;if(held_valid)held=m_data;
            if(s_valid&&s_ready)begin expected[tail]=s_data;tail=tail+1;end
            if(m_valid&&m_ready)begin
                if(head>=tail || m_data!==expected[head])$fatal(1,"FIFO mismatch head=%0d got=%h expected=%h",head,m_data,expected[head]);
                head=head+1;checks=checks+1;
            end
            if(resident==512 && s_valid&&s_ready&&m_valid&&m_ready)full_swaps=full_swaps+1;
            if(dut.push && dut.fetch && dut.write_address==dut.read_address)$fatal(1,"same-address cross-port collision");
            if(streaming)begin
                if(!s_ready||!m_valid)$fatal(1,"continuous stream bubble");stream_cycles=stream_cycles+1;
            end
            #1;if(resident!=tail-head)$fatal(1,"resident mismatch actual=%0d expected=%0d",resident,tail-head);
        end
    end
    task reset_queue;
        begin
            @(negedge clk);rst_n=0;s_valid=0;m_ready=0;
            #1;if(s_ready||m_valid||reset_done)$fatal(1,"reset isolation not asynchronous");
            repeat(4)@(negedge clk);rst_n=1;
            repeat(2)begin @(negedge clk);if(reset_done)$fatal(1,"early reset release");end
            wait(reset_done);@(negedge clk);
            if(m_valid||resident!=0)$fatal(1,"old cohort survived reset");
        end
    endtask
    task put(input integer value);
        begin @(negedge clk);s_valid=1;s_data=word_for(value);@(posedge clk);while(!s_ready)@(posedge clk);end
    endtask
    integer n;
    initial begin
        reset_queue();
        for(n=0;n<512;n=n+1)put(n);
        @(negedge clk);s_valid=0;repeat(12)@(negedge clk);
        if(s_ready||resident!=512)$fatal(1,"capacity not exactly512");
        m_ready=1;s_valid=1;streaming=1;
        for(n=512;n<2512;n=n+1)begin s_data=word_for(n);@(negedge clk);end
        streaming=0;s_valid=0;wait(resident==0);repeat(4)@(negedge clk);
        if(m_valid)$fatal(1,"empty valid");
        // Random bounded source/sink bubbles and a held final token.
        for(n=0;n<4000;n=n+1)begin
            @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            m_ready=rng[2:0]!=0;
            if(!s_valid||s_ready)begin s_valid=rng[4:3]!=0;s_data=word_for(10000+n);end
        end
        @(negedge clk);s_valid=0;m_ready=1;wait(resident==0);
        put(999999);@(negedge clk);s_valid=0;m_ready=0;wait(m_valid);
        repeat(1000)@(negedge clk);m_ready=1;wait(resident==0);
        // Cancel a held output and queued RAM words, then reuse both pointers.
        m_ready=0;for(n=0;n<100;n=n+1)put(20000+n);
        // Reset assertion/release while the only clock is stopped: release
        // must still wait three real local edges, with no old token exposed.
        @(negedge clk);clock_enable=0;s_valid=0;#2;rst_n=0;#1;
        if(m_valid||s_ready||reset_done)$fatal(1,"stopped-clock reset assertion failed");
        #20;rst_n=1;#20;if(reset_done)$fatal(1,"reset released without local clocks");
        clock_enable=1;wait(reset_done);@(negedge clk);
        if(m_valid||resident!=0)$fatal(1,"stopped-clock cancel leaked old cohort");
        m_ready=1;for(n=0;n<700;n=n+1)put(30000+n);
        @(negedge clk);s_valid=0;wait(resident==0);repeat(4)@(negedge clk);
        if(checks<5000||full_swaps<1900||stream_cycles!=2000)$fatal(1,"coverage missing");
        $display("RESULT: PASS sync FIFO checks=%0d full_pop_push=%0d continuous=%0d",checks,full_swaps,stream_cycles);$finish;
    end
endmodule
