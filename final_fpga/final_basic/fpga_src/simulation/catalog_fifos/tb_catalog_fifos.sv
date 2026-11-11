`timescale 1ns/1ps
module fifo_case #(parameter W=40, D=512)(output reg done=0);
    localparam USED=$clog2(D)+1;
    reg wc=0,rc=0,read_clock_active=1;
    always #4 wc=~wc;
    always #5 if(read_clock_active)rc=~rc;
    reg wrst=1,rrst=1,we=0,re=0;
    reg [W-1:0] di=0;
    wire [W-1:0] q;
    wire full,empty,af,ae,valid,ov,uf,success,wdone,rdone;
    wire [USED-1:0] usedw,usedr;
`define FIFOPORTS .di(di),.clkw(wc),.wrst(wrst),.we(we),.clkr(rc),.rrst(rrst),.re(re),.dout(q),.empty_flag(empty),.aempty(ae),.full_flag(full),.afull(af),.valid(valid),.overflow(ov),.underflow(uf),.wr_success(success),.rdusedw(usedr),.wrusedw(usedw),.wr_rst_done(wdone),.rd_rst_done(rdone)
    generate if(W==147)begin:packet
        camera_packet_fifo_147x512 dut(`FIFOPORTS);
    end else if(W==40)begin:control_channel
        camera_control_fifo_40x512 dut(`FIFOPORTS);
    end else if(D==8192)begin:long_events
        camera_event_fifo_47x8192 dut(`FIFOPORTS);
    end else begin:short_events
        camera_event_fifo_47x512 dut(`FIFOPORTS);
    end endgenerate
`undef FIFOPORTS
    function automatic [W-1:0] payload(input integer n,input integer pass);
        integer k;reg [31:0] v;
        begin
            for(k=0;k<W;k=k+1)begin
                v=(n+1)*32'h9e3779b9^(k/32+1)*32'hbe631491^pass*32'h8060c62d;
                payload[k]=v[k%32];
            end
        end
    endfunction
    integer n,pass,capacity;
    reg saw_overflow=0,saw_underflow=0;
    always @(negedge wc)if(ov)saw_overflow=1;
    always @(negedge rc)if(uf)saw_underflow=1;
    initial begin
        #500;
        @(negedge wc);wrst=0;@(negedge rc);rrst=0;
        wait(wdone&&rdone);
        for(pass=0;pass<2;pass=pass+1)begin
            for(n=0;n<D;n=n+1)begin
                @(negedge wc);
                if(full)$fatal(1,"early full W=%0d D=%0d n=%0d used=%0d",W,D,n,usedw);
                di=payload(n,pass);we=1;
                @(posedge wc);#1;
            end
            @(negedge wc);we=0;repeat(9)@(negedge wc);
            capacity=D;
            while(!full&&capacity<=D+2)begin
                di=payload(capacity,pass);we=1;@(negedge wc);we=0;capacity=capacity+1;
                repeat(4)@(negedge wc);
            end
            $display("FIFO_BOUNDARY W=%0d D=%0d N=%0d full=%b af=%b used=%0d",W,D,capacity,full,af,usedw);
            if(!full||!af||capacity!=D+1||usedw!=capacity)$fatal(1,"full boundary W=%0d D=%0d used=%0d",W,D,usedw);
            // Rejected write must not overwrite head or final valid entry.
            we=1;di=~payload(0,pass);@(negedge wc);we=0;repeat(3)@(negedge wc);
            if(!saw_overflow)$fatal(1,"missing overflow W=%0d",W);
            wait(valid&&!empty);repeat(8)begin @(negedge rc);if(q!==payload(0,pass))$fatal(1,"FWFT stall");end
            for(n=0;n<capacity;n=n+1)begin
                @(negedge rc);wait(valid&&!empty);
                if(q!==payload(n,pass))$fatal(1,"data W=%0d D=%0d n=%0d q=%h",W,D,n,q);
                re=1;@(posedge rc);#1;re=0;
            end
            repeat(8)@(negedge rc);
            if(!empty||valid||usedr!=0)$fatal(1,"empty boundary W=%0d D=%0d empty=%b valid=%b ae=%b used=%0d",W,D,empty,valid,ae,usedr);
            re=1;@(negedge rc);re=0;repeat(3)@(negedge rc);
            if(!saw_underflow)$fatal(1,"missing underflow W=%0d",W);
            repeat(12)@(negedge wc);
            $display("FIFO_DRAINED W=%0d D=%0d write_count=%0d read_count=%0d full=%b empty=%b",W,D,usedw,usedr,full,empty);
            if(usedw>2||full)$fatal(1,"write count W=%0d uses=%0d",W,usedw);
        end
        // Hold both resets with the read clock stopped, resume it before local release.
        @(negedge wc);di=payload(81,2);we=1;@(negedge wc);we=0;wait(valid);
        @(negedge rc);read_clock_active=0;wrst=1;rrst=1;repeat(11)@(negedge wc);
        read_clock_active=1;repeat(6)@(negedge rc);rrst=0;@(negedge wc);wrst=0;
        wait(wdone&&rdone);repeat(12)@(negedge rc);
        if(valid||!empty||full||usedr!=0)$fatal(1,"stale reset data W=%0d valid=%b empty=%b full=%b usedw=%0d usedr=%0d",W,valid,empty,full,usedw,usedr);
        @(negedge wc);we=1;di=payload(39,3);@(negedge wc);we=0;wait(valid&&!empty);
        @(negedge rc);if(q!==payload(39,3))$fatal(1,"stale word returned after reset");
        re=1;@(negedge rc);re=0;wait(empty&&!valid);
        done=1;$display("CATALOG_FIFO_CASE W=%0d D=%0d roundtrip=%0d overflow=1 underflow=1 reset=1",W,D,2*capacity);
    end
endmodule

module tb_catalog_fifos;
    wire [3:0] done;
    fifo_case #(.W(147),.D(512)) packet(done[0]);
    fifo_case #(.W(40),.D(512)) control_channel(done[1]);
    fifo_case #(.W(47),.D(512)) recent(done[2]);
    fifo_case #(.W(47),.D(8192)) events(done[3]);
    initial begin wait(&done);$display("RESULT: PASS FOUR_CATALOG_FIFOS");$finish;end
    initial begin #2000000;$fatal(1,"FIFO watchdog completed mask=%b",done);end
endmodule
