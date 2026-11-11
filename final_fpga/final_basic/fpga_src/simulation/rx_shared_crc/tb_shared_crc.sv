`timescale 1ns/1ps
module tb_shared_crc;
    wire [1:0] done;
    shared_crc_case #(.BITS(10)) raw10(done[0]);
    shared_crc_case #(.BITS(12)) raw12(done[1]);
    initial begin wait(&done);$display("RESULT: PASS SHARED_RX_CRC RAW10_RAW12 cycle_equivalent");$finish;end
    initial begin #2000000;$fatal(1,"shared CRC watchdog");end
endmodule

module shared_crc_case #(parameter integer BITS=12)(output reg done=0);
    reg clk=0,rst_n=0,identity_n=0,cycle_enable=0;
    reg valid=0,ready0=1,ready1=1;
    reg [31:0] word=0,rng=32'hb61ae29d;
    always #5 clk=~clk;
    wire [446:0] candidate,reference;
    `include "miter_instances.vh"
    integer comparisons=0,packets=0,checks=0,words=0;
    always @(negedge clk)if(rst_n && identity_n)begin
        if(candidate!==reference)$fatal(1,"CRC AB mismatch BITS=%0d at%0t candidate=%h reference=%h",BITS,$time,candidate,reference);
        // This is the induction premise used to share the combinational cone.
        if(dut.u_long.crc!==prior.u_long.crc || prior.u_long.crc!==prior.u_short.crc)
            $fatal(1,"CRC state equivalence BITS=%0d",BITS);
        comparisons++;
    end
    function [5:0] ecc(input [23:0] h);
        begin
            ecc[0]=^(h&24'hf12cb7);ecc[1]=^(h&24'hf2555b);ecc[2]=^(h&24'h749a6d);
            ecc[3]=^(h&24'hb8e38e);ecc[4]=^(h&24'hdf03f0);ecc[5]=^(h&24'heffc00);
        end
    endfunction
    function [31:0] header(input integer vc,input integer dt,input integer wc);
        reg [23:0] h;begin h={16'(wc),2'(vc),6'(dt)};header={2'd0,ecc(h),h};end
    endfunction
    function [15:0] cb(input [15:0] c,input [7:0] b);
        reg [15:0] n;integer k;begin n=c^b;for(k=0;k<8;k++)n=n[0]?(n>>1)^16'h8408:n>>1;cb=n;end
    endfunction
    task drive(input [31:0] w,input bit v);
        begin @(posedge clk);#1;word=w;valid=v;words++;
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            ready0=rng[0]||rng[3];ready1=rng[1]||rng[7];end
    endtask
    task gap(input integer count);
        integer k;begin for(k=0;k<count;k++)drive(32'hffffffff,0);end
    endtask
    task cold;
        begin @(posedge clk);#1;rst_n=0;identity_n=0;valid=0;cycle_enable=0;
            gap(4);rst_n=1;identity_n=1;cycle_enable=1;gap(4);end
    endtask
    task sp(input integer vc,input integer dt,input integer number);
        begin drive(header(vc,dt,number),1);gap(1);end
    endtask
    task packet(input integer vc,input integer dt,input integer count,input bit bad);
        integer j,k;reg [31:0] w;reg [15:0] c;reg [7:0] b;
        begin
            drive(header(vc,dt,count),1);c=16'hffff;
            for(j=0;j<count+2;j=j+4)begin
                w=32'hffffffff;
                for(k=0;k<4;k++)begin
                    if(j+k<count)begin b=8'(j+k*17);c=cb(c,b);w[k*8+:8]=b;end
                    else if(j+k==count)w[k*8+:8]=c[7:0]^(bad?1:0);
                    else if(j+k==count+1)w[k*8+:8]=c[15:8];
                end
                drive(w,1);
                if(j%20==0)gap(1);
            end
            gap(2);packets++;
        end
    endtask
    integer n,v,length;
    initial begin
        cold;
        // Uncorrectable startup headers do not poison the first trusted FS.
        drive(32'hc0000000,1);gap(3);sp(0,0,0);sp(1,0,3);
        for(n=0;n<80;n++)begin
            for(v=0;v<4;v++)begin
                length=n<20?n:((BITS==12?6:5)*(1+n%16));
                packet(v,BITS==12?6'h2c:6'h2b,length,n%7==0);
                if(n%5==0)packet(v,6'h30,n%19,0);
            end
            if(n%8==0)begin sp(0,1,n);sp(1,1,n);sp(0,0,n);sp(1,0,n+5);end
            if(n==25)begin drive(32'hc0000000,1);gap(4);end
            if(n==40)begin rst_n=0;gap(3);rst_n=1;gap(4);sp(0,0,12);sp(1,0,13);end
            if(n==60)cold;
        end
        // Truncation, independent member stalls and subsequent decoder reset.
        drive(header(0,BITS==12?6'h2c:6'h2b,65535),1);drive(32'h12345678,1);gap(3);
        rst_n=0;gap(3);rst_n=1;gap(3);cold;
        ready0=1;ready1=1;sp(0,0,1);sp(1,0,1);
        packet(0,BITS==12?6'h2c:6'h2b,BITS==12?2916:2430,0);
        packet(1,BITS==12?6'h2c:6'h2b,BITS==12?2916:2430,1);
        packet(0,BITS==12?6'h2c:6'h2b,BITS==12?65532:65535,0);
        packet(1,BITS==12?6'h2c:6'h2b,BITS==12?65532:65535,1);
        sp(0,1,1);sp(1,1,1);gap(30);
        $display("SHARED_CRC_CASE_PASS bits=%0d comparisons=%0d packets=%0d words=%0d",BITS,comparisons,packets,words);
        done=1;
    end
endmodule
