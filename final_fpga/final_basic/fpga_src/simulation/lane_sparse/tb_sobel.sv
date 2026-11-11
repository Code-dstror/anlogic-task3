`timescale 1ns/1ps
module tb_sobel;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,cancel=0,s_valid=0,m_ready=1;
wire s_ready,m_valid;reg [287:0] s_window=0;reg [3:0] s_keep=15;
reg [12:0] s_x=0;
wire [43:0] m_gx,m_gy,m_magnitude;wire [31:0] m_center_y,m_filtered_y;
wire [3:0] m_keep;wire [1:0] m_scale;wire [12:0] m_width,m_height,m_x,m_y;
wire m_sof,m_eol,m_eof;wire [159:0] m_context;
full_filter_sobel4 dut(.clk(clk),.rst_n(rst_n),.cancel(cancel),.s_valid(s_valid),.s_ready(s_ready),
 .s_window(s_window),.s_filtered_y(32'd0),.s_keep(s_keep),.s_scale(2'd2),.s_width(13'd480),.s_height(13'd270),
 .s_x(s_x),.s_y(13'd200),.s_sof(1'b0),.s_eol(1'b0),.s_eof(1'b0),.i_frame_context(160'h9876),
 .m_valid(m_valid),.m_ready(m_ready),.m_gx(m_gx),.m_gy(m_gy),.m_magnitude(m_magnitude),.m_filtered_y(m_filtered_y),
 .m_center_y(m_center_y),.m_keep(m_keep),.m_scale(m_scale),.m_width(m_width),.m_height(m_height),.m_x(m_x),.m_y(m_y),
 .m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_context(m_context));
reg [287:0] queue[0:255];reg [3:0] keeps[0:255];reg [12:0] xs[0:255];
integer wp=0,rp=0,comparisons=0,t=0,l=0,k=0,v=0,cy=0;
integer p[0:8];integer gx,gy,gauss,mag;
reg stalled=0;reg [256:0] held;
wire [256:0] result_bits={m_gx,m_gy,m_magnitude,m_center_y,m_filtered_y,m_keep,m_x,m_scale,m_width,m_height,m_y,m_sof,m_eol,m_eof};
always @(posedge clk)begin
 if(!rst_n||cancel)begin wp=0;rp=0;stalled=0;end
 else begin
   if(stalled&&result_bits!==held)$fatal(1,"Sobel held output changed");
   stalled=m_valid&&!m_ready;held=result_bits;
   if(m_valid&&m_ready)begin
     if(rp>=wp)$fatal(1,"extra Sobel token");
     if(m_keep!==keeps[rp]||m_x!==xs[rp]||m_context!==160'h9876)$fatal(1,"Sobel metadata alignment");
     for(integer lane=0;lane<4;lane=lane+1)begin
       for(integer n=0;n<9;n=n+1)p[n]=queue[rp][lane*72+n*8+:8];
       gx=p[2]-p[0]+2*(p[5]-p[3])+p[8]-p[6];
       gy=p[6]-p[0]+2*(p[7]-p[1])+p[8]-p[2];
       gauss=(p[0]+2*p[1]+p[2]+2*p[3]+4*p[4]+2*p[5]+p[6]+2*p[7]+p[8]+8)>>4;
       if(!keeps[rp][lane])begin gx=0;gy=0;gauss=0;p[4]=0;end
       mag=(gx<0?-gx:gx)+(gy<0?-gy:gy);
       if(m_gx[lane*11+:11]!==gx[10:0]||m_gy[lane*11+:11]!==gy[10:0]||
         m_magnitude[lane*11+:11]!==mag[10:0]||m_center_y[lane*8+:8]!==p[4][7:0]||
         m_filtered_y[lane*8+:8]!==gauss[7:0])$fatal(1,"Sobel p11/CE/math mismatch token%0d lane%0d",rp,lane);
     end
     rp=rp+1;comparisons=comparisons+1;
   end
   if(s_valid&&s_ready)begin queue[wp]=s_window;keeps[wp]=s_keep;xs[wp]=s_x;wp=wp+1;end
 end
end
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(5)tick();rst_n=1;
 for(t=0;t<110;t=t+1)begin
   @(negedge clk);s_valid=1;s_x=t*4;s_keep=t%5==0?7:15;
   for(l=0;l<4;l=l+1)for(k=0;k<9;k=k+1)s_window[l*72+k*8+:8]=(t*31+l*17+k*43)%256;
   if(t<2)for(l=0;l<4;l=l+1)for(k=0;k<9;k=k+1)
      s_window[l*72+k*8+:8]=k%3==0?(t==0?0:255):k%3==2?(t==0?255:0):128;
   m_ready=t%7>=3;#1;
   while(!s_ready)begin tick();@(negedge clk);cy=cy+1;m_ready=cy%7>=3;#1;end
   tick();
 end
 @(negedge clk);s_valid=0;m_ready=1;repeat(8)tick();
 if(rp!=wp||comparisons!=110)$fatal(1,"Sobel count");
 // Cancel under a real pipeline stall, then a new token must not borrow p11.
 @(negedge clk);m_ready=0;s_valid=1;repeat(2)tick();@(negedge clk);cancel=1;tick();
 @(negedge clk);cancel=0;s_valid=0;m_ready=1;repeat(5)tick();if(m_valid)$fatal(1,"cancel stale token");
 @(negedge clk);s_valid=1;s_window={36{8'd255}};s_keep=15;s_x=0;tick();
 @(negedge clk);s_valid=0;repeat(6)tick();
 if(rp!=1||wp!=1)$fatal(1,"Sobel recovery count");
 $display("RESULT: PASS LANE_SPARSE_SOBEL p11_three_CE keep signed_extremes finite_stall cancel_recovery");$finish;
end
initial begin #100000;$fatal(1,"Sobel watchdog");end
endmodule
