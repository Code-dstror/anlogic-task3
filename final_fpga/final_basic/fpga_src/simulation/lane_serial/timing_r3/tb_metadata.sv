`timescale 1ns/1ps
module tb_metadata;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,inject_valid=0,flush=0;
reg [159:0] frame_tag=160'hfedcba98765432100123456789abcdef00112233;
reg [220:0] metadata=0,good;
reg [43:0] gx=0,gy=0;reg [31:0] center=0;
stage3_filter_color_analysis4 #(.F22_FIXED1080P_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst_n),.cancel(1'b0),.start_valid(1'b0),.start_ready(),
 .cfg_width(13'd1920),.cfg_height(13'd1080),.cfg_gray(1'b0),.cfg_legacy_gaussian(1'b0),
 .cfg_color_filter(1'b0),.cfg_multiscale(1'b1),.cfg_lane(1'b1),.cfg_context(160'd0),
 .cfg_threshold(11'd40),.cfg_gx_min(11'd0),.cfg_ratio(2'd0),.cfg_sign(2'd0),
 .cfg_min_count(20'd0),.cfg_min_strips(4'd0),.cfg_y_begin(52'd0),.cfg_y_end(52'd0),
 .cfg_left(52'd0),.cfg_split(52'd0),.cfg_right(52'd0),.source_error(1'b0),
 .s_valid(1'b0),.s_ready(),.s_rgb(96'd0),.s_y(32'd0),.s_sof(1'b0),.s_eol(1'b0),
 .m_valid(),.m_ready(1'b1),.m_rgb(),.m_y(),.m_sof(),.m_eol(),.busy(),
 .frame_complete(),.frame_error(),.error_code(),.terminal_context(),
 .pyramid_valid(),.pyramid_pending(),.pyramid_ready(1'b0),.pyramid_data(),
 .lane_valid(),.lane_ready(1'b0),.lane_data(),.lane_read_enable(1'b0),.lane_read_index(9'd0),
 .lane_read_data(),.lane_read_valid(),.pyramid_drops(),.lane_drops(),.lane_started(),.lane_finished(),.lane_failed());
reg expected_valid=0,expected_bad=0,have_bad=0;
reg [8:0] expected_x,expected_y;reg [43:0] expected_gx,expected_gy;reg [31:0] expected_center;
integer checks=0,selected=0,i,j,random_state=32'hb00c1234;
function original_bad;
 input [220:0] m;input [159:0] c;
 begin original_bad=m[220:61]!=c||m[58:46]!=480||m[45:33]!=270||m[6:3]!=15||
 m[32:29]!=0||m[19:16]!=0||m[2]!=(m[32:20]==0&&m[19:7]==0)||
 m[1]!=(m[32:20]==476)||m[0]!=(m[32:20]==476&&m[19:7]==269);end
endfunction
function [220:0] good_metadata;
 input integer xx,yy;
 begin good_metadata={frame_tag,2'd2,13'd480,13'd270,13'(xx),13'(yy),4'hf,
 (xx==0&&yy==0),(xx==476),(xx==476&&yy==269)};end
endfunction
task tick;begin @(posedge clk);#1;end endtask
always @(posedge clk)begin
 if(!rst_n||flush)expected_valid=0;
 else begin
   expected_valid=inject_valid&&metadata[60:59]==2;
   if(expected_valid)begin
     expected_bad=original_bad(metadata,frame_tag);have_bad=1;selected=selected+1;
     expected_x=metadata[28:20];expected_y=metadata[15:7];
     expected_gx=gx;expected_gy=gy;expected_center=center;
   end
 end
 #1;
 if(dut.quarter_delayed!==expected_valid)$fatal(1,"metadata event latency changed");
 if(have_bad)begin
   if(dut.quarter_bad!==expected_bad)$fatal(1,"metadata bad split differs got%0d exp%0d parts%h",dut.quarter_bad,expected_bad,dut.quarter_bad_parts);
   if({dut.quarter_x,dut.quarter_y,dut.quarter_gx,dut.quarter_gy,dut.quarter_center}!==
      {expected_x,expected_y,expected_gx,expected_gy,expected_center})$fatal(1,"metadata/data event alignment");
   checks=checks+1;
 end
end
initial begin
 force dut.low_valid=inject_valid;force dut.low_metadata=metadata;
 force dut.analysis_context=frame_tag;force dut.lane_active=1'b1;
 force dut.analysis_start_fire=flush;force dut.low_gx=gx;force dut.low_gy=gy;
 force dut.low_center_y=center;
 repeat(5)tick();rst_n=1;
 // Every bit of the original metadata is flipped alone, including all160
 // identity bits and every geometry/keep/marker bit; scale changes suppress.
 good=good_metadata(200,200);
 for(i=0;i<221;i=i+1)begin
   @(negedge clk);metadata=good^(221'd1<<i);inject_valid=1;
   gx=gx+44'h12345;gy=~gx;center=center+32'h1234567;tick();
 end
 // Boundary SOF, EOL, EOF and adjacent correct/bad events with no gaps.
 for(i=0;i<1000;i=i+1)begin
   @(negedge clk);frame_tag={frame_tag[158:0],frame_tag[159]^frame_tag[87]};
   case(i%4)
   0:metadata=good_metadata(0,0);
   1:metadata=good_metadata(476,200);
   2:metadata=good_metadata(476,269);
   3:metadata=good_metadata(200,200);
   endcase
   if(i%3==0)metadata[61+(i%160)]=!metadata[61+(i%160)];
   if(i%7==0)metadata[60:59]=1;
   inject_valid=i%5!=0;flush=i%43==0;
   gx={$random(random_state),12'(i)};gy=~gx;center=$random(random_state);tick();
 end
 @(negedge clk);flush=0;inject_valid=0;repeat(4)tick();
 if(selected<800)$fatal(1,"metadata coverage selected%0d",selected);
 $display("RESULT: PASS TIMING_R3_QUARTER_BAD_SPLIT checks%0d selected%0d all160_identity_bits_all_shape_bits_SOF_EOL_EOF_consecutive_event_valid_flush_data_alignment",checks,selected);$finish;
end
initial begin #30000;$fatal(1,"metadata watchdog");end
endmodule
