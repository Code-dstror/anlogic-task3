`timescale 1ns/1ps
module tb_control_mux #(parameter W=617,parameter BORROW=1);
  reg sc=0,dc=0,clock_enable=1,sr=0,dr=0,sv=0,ready=0;
  reg [W-1:0] data;
  wire ar,br,ad,bd,asd,bsd,av,bv;
  wire [W-1:0] ao,bo;
  reg [W-1:0] queue[0:1023];
  integer sent=0,received=0,total=0,checks=0,held_checks=0;
  reg held=0;reg[W-1:0] prior;
  always begin #4;if(clock_enable)sc=~sc;else sc=0;end
  always #6.5 dc=~dc;
  control_message_fifo_ip #(.MESSAGE_WIDTH(W),.BORROW_SOURCE(BORROW)) dut(
    sc,sr,data,sv,ar,asd,dc,dr,ao,av,ready,ad);
  control_message_fifo_reference #(.MESSAGE_WIDTH(W),.BORROW_SOURCE(BORROW)) refdut(
    sc,sr,data,sv,br,bsd,dc,dr,bo,bv,ready,bd);
  function automatic [W-1:0] pattern(input integer n);
    integer b;reg[31:0] v;
    begin for(b=0;b<W;b=b+1)begin
      v=32'h9e3779b9*(n+1)+32'h01020307*(b/32);pattern[b]=v[b%32];
      if(n==0)pattern[b]=1;if(n==1)pattern[b]=0;
    end end
  endfunction
  always @(posedge sc or negedge sr or negedge dr)begin
    if({ar,asd}!={br,bsd})$fatal(1,"source handshake/reset differs");
    if(!sr||!dr)sent=0;
    else if(sv&&ar)begin queue[sent]=data;sent=sent+1;end
  end
  always @(posedge dc or negedge sr or negedge dr)begin
    if({av,ad}!={bv,bd})$fatal(1,"sink handshake/reset differs");
    if(!sr||!dr)begin received=0;held=0;end
    else begin
      if(av&&ao!==bo)$fatal(1,"A/B word mismatch");
      if(held&&(!av||ao!==prior))$fatal(1,"held output changed");
      if(held)held_checks=held_checks+1;
      if(av&&ready)begin
        if(received>=sent||ao!==queue[received])$fatal(1,"independent endian/ordering check");
        received=received+1;total=total+1;
      end
      held=av&&!ready;prior=ao;checks=checks+1;
    end
  end
  task await_reset;
    begin wait(asd&&ad);repeat(2)@(negedge sc);end
  endtask
  task automatic offer(input integer n);
    begin
      @(negedge sc);data=pattern(n);sv=1;
      @(posedge sc);while(!ar)@(posedge sc);
      @(negedge sc);sv=0;
    end
  endtask
  task drain;
    begin wait(received==sent);repeat(100)@(negedge dc);end
  endtask
  initial begin
    #25;sr=1;dr=1;await_reset;
    fork
      begin for(integer n=0;n<600;n=n+1)offer(n);end
      begin
        wait(dut.fifo_full);repeat(23)@(negedge dc);ready=1;
        repeat(900)begin @(negedge dc);ready=$urandom_range(0,3)!=0;end
        ready=1;
      end
    join
    drain;
    // Cancel a partial message while the source clock is stopped. Both
    // original and candidate must close the public interface asynchronously.
    ready=0;@(negedge sc);data=pattern(700);sv=1;
    repeat(3)@(negedge sc);clock_enable=0;sr=0;sv=0;
    #23;sr=1;repeat(18)@(negedge dc);
    if(asd||av)$fatal(1,"stopped source reset reopened early");
    clock_enable=1;await_reset;ready=1;
    for(integer n=0;n<15;n=n+1)offer(n+800);
    drain;
    @(negedge dc);dr=0;#19;dr=1;await_reset;
    for(integer n=0;n<7;n=n+1)offer(n+900);
    drain;
    if(total!=622||held_checks==0)$fatal(1,"coverage incomplete");
    $display("PASS_CONTROL_MUX W=%0d BORROW=%0d messages=%0d checks=%0d held=%0d",W,BORROW,total,checks,held_checks);
    $finish;
  end
  initial begin #2000000;$display("WATCH sent=%0d received=%0d total=%0d source_done=%b sink_done=%b full=%b ready=%b sr=%b dr=%b",sent,received,total,asd,ad,dut.fifo_full,ready,sr,dr);$fatal(1,"control mux watchdog");end
endmodule
