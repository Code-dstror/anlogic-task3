`timescale 1ns/1ps
module tb_timing_event_fifo;
`ifdef R8_STAGE1
    localparam DEPTH=8192;
`else
    localparam DEPTH=512;
`endif
    reg wc=0,rc=0,run_wc=1,run_rc=1,reset_n=0,wrst=0,rrst=0;
    reg [46:0] wd=0;
    reg wv=0,rr=0,random_read=0;
    wire ready,ref_ready,valid,ref_valid;
    wire [46:0] data,ref_data;
    reg [46:0] queue[0:32767];
    integer head=0,tail=0,checks=0,writes=0,reads=0,simultaneous=0;
    integer count_truth=0,stalls=0,resets=0,full_rate=0,n,pass,limit,c,p,q,full_stall;
    reg [1:0] expected_count;
    reg [31:0] rng=32'h4850abe1;
    reg [46:0] held;
    reg monitor=0;
    integer phase=0;
    always #5 wc=run_wc?!wc:0;
    always #4 rc=run_rc?!rc:0;
    always @(posedge wc or negedge reset_n)begin if(!reset_n)wrst<=0;else wrst<=1;end
    always @(posedge rc or negedge reset_n)begin if(!reset_n)rrst<=0;else rrst<=1;end
    csi2_async_event_fifo dut(.i_write_clk(wc),.i_write_reset_n(wrst),.i_write_data(wd),
        .i_write_valid(wv),.o_write_ready(ready),.i_read_clk(rc),.i_read_reset_n(rrst),
        .o_read_data(data),.o_read_valid(valid),.i_read_ready(rr));
    timing_event_fifo_reference reference(.i_write_clk(wc),.i_write_reset_n(wrst),.i_write_data(wd),
        .i_write_valid(wv),.o_write_ready(ref_ready),.i_read_clk(rc),.i_read_reset_n(rrst),
        .o_read_data(ref_data),.o_read_valid(ref_valid),.i_read_ready(rr));
    task check(input bit okay,input string why);
        begin checks=checks+1;if(!okay)$fatal(1,"event fifo depth=%0d checks=%0d %s count=%b ref=%b head=%0d tail=%0d",DEPTH,checks,why,dut.read_count,reference.read_count,head,tail);end
    endtask
    always @(negedge reset_n)begin head=0;tail=0;resets=resets+1;end
    always @(posedge wc)begin
        if(monitor&&reset_n&&wv&&ready)begin
            check(tail<32768,"bounded scoreboard");queue[tail]=wd;tail=tail+1;writes=writes+1;
        end
        #1;if(monitor)check(ready===ref_ready,"write readiness cycle-equivalent");
    end
    always @(posedge rc)begin
        if(monitor&&reset_n)begin
            if(valid&&rr)begin
                check(head<tail,"no phantom event");check(data===queue[head],"ordered full47-bit scoreboard");
                head=head+1;reads=reads+1;
            end
            if(valid&&!rr)stalls=stalls+1;
            if(dut.fifo_read_enable&&dut.read_fire)simultaneous=simultaneous+1;
        end
        #1;if(monitor)begin
            check(valid===ref_valid,"read validity cycle-equivalent");
            if(valid)check(data===ref_data,"all valid47-bit payload exact");
            check({dut.read_count,dut.read_head,dut.read_tail}===
                {reference.read_count,reference.read_head,reference.read_tail},"both slots and counters exact");
        end
    end
    always @(negedge rc)if(random_read)begin
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);rr=rng[0]|rng[1];
    end
    task cold_reset;
        begin
            wv=0;rr=0;reset_n=0;#2;
            check(!ready&&!valid&&!ref_ready&&!ref_valid,"asynchronous assertion while clocks may stop");
            repeat(8)@(posedge wc);#2;reset_n=1;
            wait(ready);repeat(8)@(negedge rc);
        end
    endtask
    task send(input [46:0] value);
        begin
            @(negedge wc);wd=value;wv=1;
            do @(posedge wc);while(!ready);
            @(negedge wc);wv=0;
        end
    endtask
    task drain;
        begin
            wv=0;rr=1;limit=0;
            while(head<tail)begin @(negedge rc);limit=limit+1;check(limit<DEPTH*4,"finite drain");end
            repeat(24)@(negedge rc);check(!valid&&!ref_valid,"empty has no duplicate tail");rr=0;
        end
    endtask
    initial begin
        // Exhaust the actual two-bit update truth table, including illegal11
        // and independently forced simultaneous push/pop. Reset afterwards.
        #100;reset_n=1;repeat(16)@(negedge rc);
        force dut.read_release=3'b111;force reference.read_release=3'b111;
        force dut.read_run=1'b1;force reference.read_run=1'b1;
        for(c=0;c<4;c=c+1)for(p=0;p<2;p=p+1)for(q=0;q<2;q=q+1)begin
            @(negedge rc);force dut.read_count=c;force reference.read_count=c;
            force dut.fifo_read_enable=p;force reference.fifo_read_enable=p;
            force dut.read_fire=q;force reference.read_fire=q;
            #1;release dut.read_count;release reference.read_count;
            expected_count=(c+p-q)&3;
            @(posedge rc);#1;check(dut.read_count===expected_count&&reference.read_count===expected_count,"all16 inc/dec truth cases");
            count_truth=count_truth+1;
        end
        release dut.fifo_read_enable;release reference.fifo_read_enable;
        release dut.read_fire;release reference.read_fire;
        release dut.read_release;release reference.read_release;
        release dut.read_run;release reference.read_run;
        phase=1;monitor=1;cold_reset();
        // Two near-full fills cross the actual official FIFO address range.
        for(pass=0;pass<2;pass=pass+1)begin
            phase=2+pass;
            n=0;full_stall=0;
            // Wait for sustained full backpressure; the first transient READY
            // gap can precede the official show-ahead pointer synchronization.
            while(full_stall<20)begin
                @(negedge wc);wv=1;
                if(ready)begin wd=47'h100000000000+pass*DEPTH+n;n=n+1;end
                @(posedge wc);#1;
                if(ready)full_stall=0;else full_stall=full_stall+1;
                check(n<DEPTH+16,"near-full stops producer");
            end
            @(negedge wc);wv=0;repeat(12)@(negedge wc);
            check(!ready&&dut.fifo_write_used>=DEPTH-8&&!dut.fifo_write_ready,
                "original near-full guard retained including official prefetch accounting");
            check(valid&&dut.read_count==2,"both local slots filled");held=data;
            repeat(12)begin @(negedge rc);check(valid&&data===held,"held head immutable");end
            drain();repeat(16)@(negedge wc);check(ready,"writer recovers capacity");
        end
        // Already queued data must retire on every read clock without bubbles.
        phase=4;for(n=0;n<128;n=n+1)send(47'h200000000000+n);
        repeat(12)@(negedge rc);rr=1;
        for(n=0;n<128;n=n+1)begin @(posedge rc);check(valid,"128 queued items continuous");full_rate=full_rate+1;end
        @(negedge rc);rr=0;repeat(16)@(negedge rc);check(!valid,"continuous drain exact end");
        // Finite randomized source offers and consumer stalls.
        phase=5;random_read=1;
        for(n=0;n<4000;n=n+1)begin
            @(negedge wc);
            if(!wv||ready)begin
                rng=rng*32'd1664525+32'd1013904223;
                wv=rng[0]|rng[2];wd={rng[14:0],rng};
            end
        end
        @(negedge wc);wv=0;random_read=0;drain();
        // Stop read clock while reset asserts and releases. No old payload may
        // reappear after new-epoch writes become visible in the restored domain.
        phase=6;for(n=0;n<20;n=n+1)send(47'h300000000000+n);
        wait(valid);@(negedge rc);run_rc=0;#2;reset_n=0;#1;check(!valid&&!ready,"stopped read reset asserts");
        repeat(8)@(negedge wc);reset_n=1;
        repeat(8)@(negedge wc);check(!valid&&!dut.fifo_read_reset_done&&!ready,
            "cohort holds both domains until stopped read reset input releases");
        run_rc=1;wait(ready);send(47'h400000000001);wait(valid);drain();
        // Symmetric stopped writer, followed by successful new-epoch transfer.
        phase=7;@(negedge wc);run_wc=0;#2;reset_n=0;#1;check(!valid&&!ready,"stopped write reset asserts");
        repeat(8)@(negedge rc);reset_n=1;repeat(8)@(negedge rc);
        check(!ready&&!dut.fifo_write_reset_done,"stopped write cannot release");
        run_wc=1;wait(ready);send(47'h500000000001);drain();
        check(count_truth==16&&simultaneous>100&&stalls>100&&full_rate==128,"required risk coverage");
        $display("RESULT: PASS timing_event_fifo depth=%0d checks=%0d truth=%0d writes=%0d reads=%0d simultaneous=%0d stalls=%0d resets=%0d continuous=%0d",
            DEPTH,checks,count_truth,writes,reads,simultaneous,stalls,resets,full_rate);$finish;
    end
    initial begin #3000000;$fatal(1,"event FIFO watchdog phase=%0d head=%0d tail=%0d ready=%b valid=%b clocks=%b%b count=%b used=%0d",phase,head,tail,ready,valid,run_wc,run_rc,dut.read_count,dut.fifo_write_used);end
endmodule
