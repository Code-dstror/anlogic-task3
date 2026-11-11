`timescale 1ns/1ps
// One real shared ISP and JPEG, reused sequentially by two eye contexts.
module tb_dual_pipeline;
    localparam W=240,H=16,N=W*H/4;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0,status_valid=0,result_ready=0;
    reg [55:0] raw=0;reg [31:0] id=0,epoch=0;reg camera=0;
    reg [7:0] quality=0;reg [15:0] restart=0;
    wire raw_ready,rgb_valid,rgb_sof,rgb_eol,rgb_ready,isp_idle;
    wire [95:0] rgb;wire [31:0] luma;
    wire status_ready,axis_valid,axis_last,result_valid,result_ok,idle;
    wire [127:0] axis_data;wire [15:0] axis_keep;
    wire [31:0] result_id,result_epoch;wire [24:0] length;
    wire [7:0] error_code,result_quality;
    reg axis_ready=0;integer cycles=0,checks=0,bytes_out=0,tail_count=0,frame=0,fd,rgb_count=0;
    reg [55:0] raw_vectors[0:N-1];reg [95:0] expected[0:N-1];
    reg stalled=0;reg [144:0] held;reg result_held=0;reg [97:0] held_result;
    shared_wide_isp #(.MAX_WIDTH(W),.MAX_HEIGHT(H)) isp(
        .clk(clk),.rst_n(rst_n),.cfg_width(13'(W)),.cfg_height(13'(H)),.cfg_bayer_phase(2'd0),
        .cfg_hdr(1'b0),.cfg_tone_shift(4'd4),.cfg_wb_gains({10'd832,10'd410,10'd909}),
        .s_data(raw),.s_valid(valid),.s_ready(raw_ready),.s_sof(sof),.s_eol(eol),
        .m_data(rgb),.m_valid(rgb_valid),.m_ready(rgb_ready),.m_sof(rgb_sof),.m_eol(rgb_eol),
        .o_job_idle(isp_idle),.stat_beats(),.stat_frames(),.stat_saturated());
    genvar g;
    generate for(g=0;g<4;g++)begin:lum
        wire [23:0] c=rgb[g*24+:24];
        wire [15:0] y=77*c[23:16]+150*c[15:8]+29*c[7:0]+128;
        assign luma[g*8+:8]=y[15:8];
    end endgenerate
    jpeg_encoder_top #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.SHARED_STREAM_ENABLE(1),
        .TINY_DISTRIBUTED_RAM_ENABLE(1),.COEFF_BANKED_STORAGE_ENABLE(1),
        .MCU_ROW_STREAM_ENABLE(1),.FIXED_GEOMETRY_ENABLE(1),
        .ROM_INIT_ROOT("./rom_init"),.ROM_INIT_SUFFIX(".mif.dath")) dut(
        .i_clk(clk),.i_rst_n(rst_n),.i_rgb(rgb),.i_luma(luma),.i_quality(quality),
        .i_session_id(32'd55),.i_mode_epoch(epoch),.i_camera_id(camera),.i_restart_mcus(restart),
        .i_rgb_valid(rgb_valid),.o_rgb_ready(rgb_ready),.i_sof(rgb_sof),.i_eol(rgb_eol),.i_capture_id(id),
        .i_width(13'(W)),.i_height(13'(H)),.i_frame_status_valid(status_valid),
        .o_frame_status_ready(status_ready),.i_frame_status_id(id),.i_frame_ok(1'b1),
        .o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),.o_axis_tvalid(axis_valid),
        .i_axis_tready(axis_ready),.o_axis_tlast(axis_last),.o_result_valid(result_valid),
        .i_result_ready(result_ready),.o_result_id(result_id),.o_result_ok(result_ok),
        .o_payload_length(length),.o_error_code(error_code),.o_result_quality(result_quality),
        .o_result_epoch(result_epoch),.o_idle(idle));
    task check(input bit good,input string reason);
        begin checks++;if(!good)$fatal(1,"DUAL_PIPELINE %s frame=%0d rgb=%0d",reason,frame,rgb_count);end
    endtask
    always @(negedge clk)axis_ready=rst_n&&(cycles%13>=3);
    always @(posedge clk)begin
        cycles++;if(cycles>400000)$fatal(1,"DUAL_PIPELINE watchdog");
        if(rst_n)begin
            if(stalled)check(axis_valid&&{axis_last,axis_keep,axis_data}===held,"payload stalls preserve all sideband");
            stalled=axis_valid&&!axis_ready;if(stalled)held={axis_last,axis_keep,axis_data};
            if(result_held)check(result_valid&&{result_id,result_epoch,result_quality,length,result_ok}===held_result,"result ownership stable");
            result_held=result_valid&&!result_ready;
            if(result_held)held_result={result_id,result_epoch,result_quality,length,result_ok};
            if(rgb_valid&&rgb_ready)begin
                check(rgb_count<N&&rgb===expected[rgb_count],"independent scalar ISP pixel/lane/border oracle");
                check(rgb_sof==(rgb_count==0)&&rgb_eol==(rgb_count%(W/4)==W/4-1),"ISP SOF/EOL");rgb_count++;
            end
            if(axis_valid&&axis_ready)begin
                check(axis_keep!=0,"nonempty payload beat");
                for(integer k=0;k<16;k++)if(axis_keep[k])begin $fwrite(fd,"%c",axis_data[k*8+:8]);bytes_out++;end
                if(axis_last)tail_count++;
            end
        end
    end
    initial begin
        $readmemh("raw.hex",raw_vectors);$readmemh("rgb.hex",expected);
        repeat(8)@(negedge clk);rst_n=1;
        for(frame=0;frame<2;frame++)begin
            wait(idle&&isp_idle);@(negedge clk);
            id=101+frame;epoch=21+frame;camera=frame;quality=frame==0?37:91;restart=frame==0?3:5;
            bytes_out=0;tail_count=0;rgb_count=0;fd=$fopen(frame==0?"case0.actual.jpg":"case1.actual.jpg","wb");
            for(integer n=0;n<N;n++)begin
                raw=raw_vectors[n];valid=1;sof=n==0;eol=n%(W/4)==W/4-1;
                do @(posedge clk);while(!raw_ready);
                @(negedge clk);
            end
            valid=0;sof=0;eol=0;wait(rgb_count==N);@(negedge clk);
            // Live next-eye fields cannot mutate the accepted encoder context.
            camera=!frame;epoch=32'hf0000000+frame;quality=frame==0?91:37;restart=frame==0?5:3;
            status_valid=1;do @(posedge clk);while(!status_ready);@(negedge clk);status_valid=0;
            wait(result_valid);@(negedge clk);
            check(result_ok&&error_code==0&&result_id==101+frame,"result success/capture identity");
            check(result_quality==(frame==0?37:91)&&result_epoch==21+frame,"frozen quality/epoch");
            check(dut.camera_id==frame&&dut.session_id==55,"frozen eye/session identity");
            check(length==bytes_out&&tail_count==1&&rgb_count==N,"complete JPEG and one terminal beat");
            repeat(7)begin @(negedge clk);check(result_valid&&!idle,"owned result blocks next-eye reuse");end
            $fclose(fd);$display("DUAL_PIPELINE_EYE PASS camera=%0d sequence=%0d bytes=%0d",frame,result_id,bytes_out);
            result_ready=1;@(negedge clk);result_ready=0;
        end
        $display("RESULT: PASS DUAL_SHARED_ISP_JPEG checks=%0d",checks);$finish;
    end
endmodule
