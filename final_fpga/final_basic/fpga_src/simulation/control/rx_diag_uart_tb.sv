`timescale 1ns/1ps
module rx_diag_uart_tb;
 reg sys=0,pix=0,word_raw=0;always #20 sys=~sys;always #4 pix=~pix;always #5 word_raw=~word_raw;
 reg word_running=0,rst=0;wire word_clk=word_raw&&word_running;
 reg [383:0] data=384'h12345678_43470201_00000000_00000001_00000002_00000003_00000004_00000005_00000006_00000007_00000008_00000009;
 wire tx;
 uart_status_observer #(.UART_DIV(4),.REPORT_INTERVAL_CYCLES(8000),.SNAPSHOT_TIMEOUT_CYCLES(30),.CFG_DIAG_ENABLE(1),.CFG_FRAME_VERSION(2),.RX_DIAG_ENABLE(1)) dut(
  .i_sys_clk(sys),.i_sys_rst_n(rst),.i_pixel_clk(pix),.i_dfi_clk(pix),.i_user_clk(sys),
  .i_domain_observer_rst_n({3{rst}}),.i_domain_reset_n(3'b111),.i_sys_status(16'h1234),.i_domain_flags(36'd0),.i_domain_faults(12'd0),.i_domain_progress(6'd0),
  .i_cfg_domains(448'd0),.i_cfg_domain_reset_n(2'b11),.i_rx_word_clk(word_clk),.i_rx_domains(data),.i_rx_reset_n(3'b111),
  .o_trace_request(),.o_trace_index(),.i_trace_ack(1'b0),.i_trace_data(320'd0),.o_uart_tx(tx));
 integer fd,at=0,len=0,frames=0,rxframes=0;reg [7:0] bytes_[0:67];
 function automatic [15:0] crc16(input [15:0] old,input [7:0] b);
  reg [15:0] c;integer k;begin c=old^{b,8'd0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
 endfunction
 initial begin : receive
  reg [7:0] b;reg [15:0] crc;integer i,j;
  fd=$fopen("rx_diag_wire.bin","wb");
  forever begin
   @(negedge tx);#240;
   for(i=0;i<8;i=i+1)begin b[i]=tx;#160;end
   if(tx!==1)$fatal(1,"UART stop");bytes_[at]=b;$fwrite(fd,"%c",b);
   if(at==1)begin
    if(bytes_[0]=="O"&&b=="B")len=29;
    else if(bytes_[0]=="C"&&b=="G")len=68;
    else if(bytes_[0]=="R"&&b=="X")len=64;
    else $fatal(1,"mixed magic");
   end
   if(len!=0&&at==len-1)begin
    frames=frames+1;
    if(len==64)begin
     crc=16'hffff;for(j=0;j<62;j=j+1)crc=crc16(crc,bytes_[j]);
     if({bytes_[63],bytes_[62]}!==crc)$fatal(1,"RX CRC");
     if(bytes_[2]!=1||bytes_[4]!=64)$fatal(1,"RX version");
     if(rxframes==0&&bytes_[8][0]!==0)$fatal(1,"stopped WORD reported fresh");
     if(rxframes>=2&&bytes_[8][0]!==1)$fatal(1,"resumed WORD not fresh");
     rxframes=rxframes+1;
     if(rxframes==1)word_running=1;
     if(rxframes==4)begin $fclose(fd);$display("RESULT: PASS rx_diag_uart frames=%0d rx=%0d",frames,rxframes);$finish;end
    end
    at=0;len=0;
   end else at=at+1;
  end
 end
 initial begin repeat(10)@(negedge sys);rst=1;end
 initial begin #2000000;$fatal(1,"UART watchdog");end
endmodule
