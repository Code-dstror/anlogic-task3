`timescale 1ns/1ps
module tb_shared;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,cancel=0,start_valid=0;wire start_ready;
reg cfg_gray=0,cfg_color_filter=0;
reg source_error=0,s_valid=0;wire s_ready;
reg [95:0] s_rgb=0;reg [31:0] s_y=0;reg s_sof=0,s_eol=0;
wire m_valid;reg m_ready=1;wire [95:0] m_rgb;wire [31:0] m_y;wire m_sof,m_eol;
wire busy,frame_complete,frame_error;wire [3:0] error_code;wire [159:0] terminal_context;
wire pyramid_valid,pyramid_pending;reg pyramid_ready=0;wire [683:0] pyramid_data;
wire lane_valid;reg lane_ready=0;wire [176:0] lane_data;
reg lane_read_enable=0;reg [8:0] lane_read_index=0;wire [39:0] lane_read_data;wire lane_read_valid;
wire [31:0] pyramid_drops,lane_drops,lane_started,lane_finished,lane_failed;
stage3_filter_color_analysis_serial4 #(.F22_FIXED1080P_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst_n),.cancel(cancel),.start_valid(start_valid),.start_ready(start_ready),
 .cfg_width(13'd1920),.cfg_height(13'd1080),.cfg_gray(cfg_gray),.cfg_legacy_gaussian(1'b0),
 .cfg_color_filter(cfg_color_filter),.cfg_multiscale(1'b1),.cfg_lane(1'b1),.cfg_context(160'h1234),
 .cfg_threshold(11'd40),.cfg_gx_min(11'd0),.cfg_ratio(2'd0),.cfg_sign(2'd0),.cfg_min_count(20'd0),.cfg_min_strips(4'd0),
 .cfg_y_begin(52'd0),.cfg_y_end(52'd0),.cfg_left(52'd0),.cfg_split(52'd0),.cfg_right(52'd0),
 .source_error(source_error),.s_valid(s_valid),.s_ready(s_ready),.s_rgb(s_rgb),.s_y(s_y),.s_sof(s_sof),.s_eol(s_eol),
 .m_valid(m_valid),.m_ready(m_ready),.m_rgb(m_rgb),.m_y(m_y),.m_sof(m_sof),.m_eol(m_eol),
 .busy(busy),.frame_complete(frame_complete),.frame_error(frame_error),.error_code(error_code),.terminal_context(terminal_context),
 .pyramid_valid(pyramid_valid),.pyramid_pending(pyramid_pending),.pyramid_ready(pyramid_ready),.pyramid_data(pyramid_data),
 .lane_valid(lane_valid),.lane_ready(lane_ready),.lane_data(lane_data),
 .lane_read_enable(lane_read_enable),.lane_read_index(lane_read_index),.lane_read_data(lane_read_data),.lane_read_valid(lane_read_valid),
 .pyramid_drops(pyramid_drops),.lane_drops(lane_drops),.lane_started(lane_started),.lane_finished(lane_finished),.lane_failed(lane_failed));
reg [31:0] pixel_lut[0:5759];reg [31:0] quarter_lut[0:388799];
reg [39:0] expected[0:908];integer sizes[0:2];
integer mode=0,test_mode=0,native_x=0,native_row=0,image_x=0,image_row=0;
integer cycles=0,qpoints=0,serial_points=0,half_events=0,stalls=0,n=0,index=0,l=0,qi=0;
reg monitor=0;reg [31:0] refsample,pix;reg [176:0] held;
task tick;begin @(posedge clk);#1;end endtask
always @(posedge clk)begin
 if(monitor)begin
   cycles=cycles+1;
   if(s_valid&&!s_ready)stalls=stalls+1;
   if(dut.low_valid&&dut.low_metadata[60:59]==1)half_events=half_events+1;
   if(dut.quarter_delayed)begin
     if(!dut.hints_valid||dut.hints_error)$fatal(1,"hint progress x%0d y%0d",dut.quarter_x,dut.quarter_y);
     for(integer i=0;i<4;i=i+1)begin
       qi=mode*129600+dut.quarter_y*480+dut.quarter_x+i;refsample=quarter_lut[qi];
       if(dut.quarter_gx[i*11+:11]!==refsample[10:0]||dut.quarter_gy[i*11+:11]!==refsample[21:11]||
          dut.quarter_center[i*8+:8]!==refsample[29:22]||
          (dut.hints[i*2+1]?2'd2:dut.hints[i*2]?2'd1:2'd0)!==refsample[31:30])
         $fatal(1,"quarter mismatch qx=%0d y=%0d gx%h gy%h p11%h hint%h exp%h",dut.quarter_x+i,dut.quarter_y,
           dut.quarter_gx[i*11+:11],dut.quarter_gy[i*11+:11],dut.quarter_center[i*8+:8],dut.hints[i*2+:2],refsample);
       qpoints=qpoints+1;
     end
   end
   if(dut.lane.queue_valid)begin
     qi=mode*129600+dut.lane.queue_y*480+dut.lane.queue_x;refsample=quarter_lut[qi];
     if(dut.lane.queue_sample[29:0]!==refsample[29:0]||
       (dut.lane.queue_sample[31]?2'd2:dut.lane.queue_sample[30]?2'd1:2'd0)!==refsample[31:30])
       $fatal(1,"serialized quarter mismatch qx%0d y%0d",dut.lane.queue_x,dut.lane.queue_y);
     serial_points=serial_points+1;
   end
   if(m_valid&&m_ready)begin
     if(m_sof!==(image_x==0&&image_row==0)||m_eol!==(image_x==1916))$fatal(1,"image markers");
     if(!cfg_color_filter)for(integer i=0;i<4;i=i+1)begin
       pix=pixel_lut[mode*1920+image_x+i];
       if(m_y[i*8+:8]!==pix[31:24]||m_rgb[i*24+:24]!==(cfg_gray?{3{pix[31:24]}}:pix[23:0]))$fatal(1,"image bypass/gray changed");
     end
     if(image_x==1916)begin image_x=0;image_row=image_row+1;end else image_x=image_x+4;
   end
 end
end
task begin_frame;
 input integer which,gray_enable,color_enable;
 begin
 mode=which;cfg_gray=gray_enable;cfg_color_filter=color_enable;image_x=0;image_row=0;
 cycles=0;qpoints=0;serial_points=0;half_events=0;stalls=0;
 @(negedge clk);start_valid=1;while(!start_ready)tick();tick();@(negedge clk);start_valid=0;monitor=1;
 end
endtask
task send_good;
 input integer finite_stalls;
 begin
 for(native_row=0;native_row<1080;native_row=native_row+1)for(native_x=0;native_x<1920;native_x=native_x+4)begin
   @(negedge clk);s_valid=1;s_sof=native_row==0&&native_x==0;s_eol=native_x==1916;
   for(l=0;l<4;l=l+1)begin pix=pixel_lut[mode*1920+native_x+l];s_rgb[l*24+:24]=pix[23:0];s_y[l*8+:8]=pix[31:24];end
   // Downstream stalls are finite and unrelated to quarter/hint timing.
   m_ready=!finite_stalls||cycles%31>=4;
   #1;while(!s_ready)begin tick();@(negedge clk);m_ready=!finite_stalls||cycles%31>=4;#1;end
   tick();
 end
 @(negedge clk);s_valid=0;m_ready=1;
 n=0;while((busy||!lane_valid||!pyramid_valid)&&n<15000)begin tick();n=n+1;end
 if(busy||!lane_valid||!pyramid_valid)$fatal(1,"shared finish timeout busy%0d lane%0d pyramid%0d",busy,lane_valid,pyramid_valid);
 if(lane_data[16:8]!==sizes[mode]||lane_data[7:0]!==(sizes[mode]==0?8'd1:8'd0))$fatal(1,"shared lane descriptor %h expected count%0d",lane_data,sizes[mode]);
 if(qpoints!=129600||serial_points!=129600||half_events!=129600||image_row!=1080||image_x!=0)$fatal(1,"shared event counts q%0d serial%0d half%0d image%0d",qpoints,serial_points,half_events,image_row);
 held=lane_data;repeat(9)begin tick();if(lane_data!==held||!lane_valid)$fatal(1,"shared hold");end
 for(index=0;index<sizes[mode];index=index+1)begin
   @(negedge clk);lane_read_enable=1;lane_read_index=index;tick();
   if(!lane_read_valid||lane_read_data!==expected[mode*303+index])$fatal(1,"shared point index%0d got%h exp%h",index,lane_read_data,expected[mode*303+index]);
 end
 $display("SHARED frame mode%0d gray%0d color%0d accepted518400 q129600 serial129600 half129600 points%0d cycles%0d stalls%0d",mode,cfg_gray,cfg_color_filter,sizes[mode],cycles,stalls);
 @(negedge clk);lane_read_enable=0;lane_ready=1;pyramid_ready=1;monitor=0;tick();@(negedge clk);lane_ready=0;pyramid_ready=0;
 end
endtask
initial begin
 $readmemh("native_pixels.hex",pixel_lut);$readmemh("quarter_samples.hex",quarter_lut);
 $readmemh("shared_expected.hex",expected);$readmemh("shared_sizes.hex",sizes);
 repeat(8)tick();rst_n=1;repeat(5)tick();
 begin_frame(0,0,0);send_good(0);
 begin_frame(1,1,0);send_good(1);
 begin_frame(1,0,1);send_good(1);
 begin_frame(0,0,0);monitor=0;
 for(index=0;index<500;index=index+1)begin
   @(negedge clk);s_valid=1;s_sof=index==0;s_eol=index%480==479;s_rgb={4{24'h454545}};s_y={4{8'h45}};
   #1;while(!s_ready)begin tick();@(negedge clk);end
   tick();
 end
 @(negedge clk);s_valid=0;source_error=1;tick();@(negedge clk);source_error=0;monitor=0;
 n=0;while((!lane_valid||!pyramid_valid)&&n<1000)begin tick();n=n+1;end
 if(!lane_valid||lane_data[7:0]!==129||lane_data[16:8]!==0)$fatal(1,"SOURCE bad terminal");
 @(negedge clk);lane_ready=1;pyramid_ready=1;tick();@(negedge clk);lane_ready=0;pyramid_ready=0;
 begin_frame(0,0,0);send_good(1);
 begin_frame(2,0,0);send_good(1);
 if(pyramid_drops!=0||lane_drops!=0)$fatal(1,"unexpected drop");
 $display("RESULT: PASS LANE_SERIAL_SHARED native1080p4PPC five_complete_good_frames white yellow no_markings gray colorGaussian finite_stall SOURCE_bad_good_recovery quarter_p11_sobel_hint_bitexact");$finish;
end
initial begin #100000000;$fatal(1,"shared watchdog");end
endmodule
