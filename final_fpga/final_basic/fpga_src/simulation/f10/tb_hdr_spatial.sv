`timescale 1ns/1ps
module tb_hdr_spatial;
    localparam SW=248,SH=19,W=240,H=16,N=W*H/4;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0;reg [3:0] error=0;
    reg [95:0] pair_data=0;wire [1:0] ready,cv,cs,ce,ca,cr;
    wire [79:0] cropped;wire [7:0] crop_error;
    wire merge_ready,merge_valid,merge_sof,merge_eol,isp_ready,rgb_valid,rgb_sof,rgb_eol;
    wire [55:0] merged;wire [3:0] motion;wire [95:0] rgb;
    reg rgb_ready=0;
    reg [95:0] sensor[0:SW*SH/4-1],rgb_expected[0:N-1];
    reg [79:0] crop_expected[0:N-1];reg [59:0] merge_expected[0:N-1];
    integer checks=0,cycles=0,crop_count=0,merge_count=0,rgb_count=0;
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:member
        real_hdr_member_crop10 #(.SENSOR_WIDTH(SW),.SENSOR_HEIGHT(SH),.CROP_X(4),.CROP_Y(1),.WIDTH(W),.HEIGHT(H)) crop (
            .i_clk(clk),.i_reset_n(rst_n),.s_data(pair_data[g*48+:48]),.s_valid(valid),.s_ready(ready[g]),
            .s_sof(sof),.s_eol(eol),.s_abort(1'b0),.s_error(error),.s_group(32'd9),.s_sequence(32'd7),
            .s_identity_valid(1'b1),.s_cycle_valid(1'b1),.s_frame_number(16'd7),
            .m_data(cropped[g*40+:40]),.m_valid(cv[g]),.m_ready(cr[g]),.m_sof(cs[g]),.m_eol(ce[g]),
            .m_abort(ca[g]),.m_error(crop_error[g*4+:4]),.m_group(),.m_sequence(),
            .m_identity_valid(),.m_cycle_valid(),.m_frame_number(),.o_geometry_errors(),.o_complete_frames());
        assign cr[g]=crop_error[g*4+:4]!=0?1'b1:merge_ready&&cv[1-g];
    end endgenerate
    hdr_merge4 merge (
        .clk(clk),.rst_n(rst_n),.clear(1'b0),.cfg_ratio_log2(3'd4),.cfg_black_long(10'd32),
        .cfg_black_short(10'd16),.cfg_motion_base(14'd64),.cfg_motion_shift(4'd3),
        .s_long(cropped[39:0]),.s_short(cropped[79:40]),.s_valid(&cv&&crop_error==0),.s_ready(merge_ready),
        .s_sof(cs[0]),.s_eol(ce[0]),.m_raw(merged),.m_valid(merge_valid),.m_ready(isp_ready),
        .m_sof(merge_sof),.m_eol(merge_eol),.m_motion(motion));
    shared_wide_isp #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.HDR_BLACK_CORRECTED_ENABLE(1)) isp (
        .clk(clk),.rst_n(rst_n),.cfg_width(13'(W)),.cfg_height(13'(H)),.cfg_bayer_phase(2'd3),
        .cfg_hdr(1'b1),.cfg_tone_shift(4'd4),.cfg_wb_gains({10'd832,10'd410,10'd909}),
        .s_data(merged),.s_valid(merge_valid),.s_ready(isp_ready),.s_sof(merge_sof),.s_eol(merge_eol),
        .m_data(rgb),.m_valid(rgb_valid),.m_ready(rgb_ready),.m_sof(rgb_sof),.m_eol(rgb_eol),
        .o_job_idle(),.stat_beats(),.stat_frames(),.stat_saturated());
    task automatic check(input bit good,input string why);
        begin checks=checks+1;if(!good)$fatal(1,"F10 HDR %s crop=%0d merge=%0d rgb=%0d",why,crop_count,merge_count,rgb_count);end
    endtask
    always @(negedge clk)rgb_ready=rst_n&&(cycles%11>=3);
    always @(posedge clk)begin
        cycles=cycles+1;if(cycles>100000)$fatal(1,"F10 HDR watchdog");
        if(rst_n)begin
            check(cv[0]===cv[1]&&crop_error[3:0]===crop_error[7:4]&&! (|ca),"symmetric geometry ownership and no ABORT");
            if(&cv&&crop_error==0&&merge_ready)begin
                check(cropped===crop_expected[crop_count],"RAW12 quantization/crop/lane ordering");
                check(cs[0]==(crop_count==0)&&ce[0]==(crop_count%(W/4)==W/4-1),"crop SOF/EOL at all row edges");
                crop_count=crop_count+1;
            end
            if(merge_valid&&isp_ready)begin
                check({motion,merged}===merge_expected[merge_count],"knee/motion RAW14 exact");merge_count=merge_count+1;
            end
            if(rgb_valid&&rgb_ready)begin
                check(rgb===rgb_expected[rgb_count],"asymmetric Bayer/T96/WB/gamma exact including image borders");
                check(rgb_sof==(rgb_count==0)&&rgb_eol==(rgb_count%(W/4)==W/4-1),"RGB SOF/EOL at all row edges");
                rgb_count=rgb_count+1;
            end
        end
    end
    task automatic send(input [95:0] d,input bit first,last,input [3:0] kind);
        begin
            @(negedge clk);pair_data=d;sof=first;eol=last;error=kind;valid=1;
            do @(posedge clk);while(!(&ready));
            @(negedge clk);valid=0;sof=0;eol=0;error=0;
        end
    endtask
    initial begin
        $readmemh("sensor.hex",sensor);$readmemh("crop.hex",crop_expected);
        $readmemh("merge.hex",merge_expected);$readmemh("rgb.hex",rgb_expected);
        repeat(8)@(negedge clk);rst_n=1;
        send({2{48'h000100000007}},0,0,7);
        for(integer n=0;n<SW*SH/4;n=n+1)send(sensor[n],n==0,n%(SW/4)==SW/4-1,0);
        send(0,0,0,6);
        wait(rgb_count==N);repeat(12)@(negedge clk);
        check(crop_count==N&&merge_count==N,"complete cropped/merged frame counts");
        check(member[0].crop.o_complete_frames==1&&member[1].crop.o_complete_frames==1,"true full sensor raster terminal");
        $display("RESULT: PASS F10_HDR_SPATIAL checks=%0d pixels=%0d crop=(4,1) phase=3",checks,W*H);$finish;
    end
endmodule
