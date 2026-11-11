`timescale 1ns/1ps
module tb_jpeg_dynamic;
    localparam W=240,H=16,N=W*H/4;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0,status_valid=0,result_ready=0;
    reg [95:0] rgb=0;reg [31:0] luma=0,id=0,epoch=0;
    reg [7:0] quality=0;reg [15:0] restart=0;
    wire ready,status_ready,axis_valid,axis_last,result_valid,result_ok,idle;
    wire [127:0] axis_data;wire [15:0] axis_keep;
    wire [31:0] result_id,result_epoch;wire [24:0] length;
    wire [7:0] error_code,result_quality;
    reg axis_ready=0;integer cycles=0,checks=0,bytes_out=0,tail_count=0,frame=0,fd;
    reg [127:0] vectors[0:N-1];reg stalled=0;reg [144:0] held;
    jpeg_encoder_top #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.SHARED_STREAM_ENABLE(1),
        .TINY_DISTRIBUTED_RAM_ENABLE(1),.COEFF_BANKED_STORAGE_ENABLE(1),
        .MCU_ROW_STREAM_ENABLE(1),.FIXED_GEOMETRY_ENABLE(1),
        .ROM_INIT_ROOT("./rom_init"),.ROM_INIT_SUFFIX(".mif.dath")) dut (
        .i_clk(clk),.i_rst_n(rst_n),.i_rgb(rgb),.i_luma(luma),.i_quality(quality),
        .i_session_id(32'd55),.i_mode_epoch(epoch),.i_camera_id(1'b0),.i_restart_mcus(restart),
        .i_rgb_valid(valid),.o_rgb_ready(ready),.i_sof(sof),.i_eol(eol),.i_capture_id(id),
        .i_width(13'(W)),.i_height(13'(H)),.i_frame_status_valid(status_valid),
        .o_frame_status_ready(status_ready),.i_frame_status_id(id),.i_frame_ok(1'b1),
        .o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),.o_axis_tvalid(axis_valid),
        .i_axis_tready(axis_ready),.o_axis_tlast(axis_last),.o_result_valid(result_valid),
        .i_result_ready(result_ready),.o_result_id(result_id),.o_result_ok(result_ok),
        .o_payload_length(length),.o_error_code(error_code),.o_result_quality(result_quality),
        .o_result_epoch(result_epoch),.o_idle(idle));
    task automatic check(input bit good,input string reason);
        begin checks=checks+1;if(!good)$fatal(1,"F10 JPEG %s",reason);end
    endtask
    always @(negedge clk)axis_ready=rst_n&&(cycles%13>=3);
    always @(posedge clk)begin
        cycles=cycles+1;if(cycles>300000)$fatal(1,"F10 JPEG watchdog");
        if(rst_n)begin
            if(stalled)check(axis_valid&&{axis_last,axis_keep,axis_data}===held,"AXIS stable under stall");
            stalled=axis_valid&&!axis_ready;
            if(stalled)held={axis_last,axis_keep,axis_data};
            if(axis_valid&&axis_ready)begin
                check(axis_keep!=0,"nonempty output beat");
                for(integer k=0;k<16;k=k+1)if(axis_keep[k])begin
                    $fwrite(fd,"%c",axis_data[k*8+:8]);bytes_out=bytes_out+1;
                end
                if(axis_last)tail_count=tail_count+1;
            end
        end
    end
    initial begin
        repeat(8)@(negedge clk);rst_n=1;
        for(frame=0;frame<2;frame=frame+1)begin
            wait(idle);@(negedge clk);
            if(frame==0)$readmemh("case0.inputs.hex",vectors);else $readmemh("case1.inputs.hex",vectors);
            id=32'd101+frame;epoch=32'd21+frame;quality=frame==0?37:91;restart=frame==0?3:5;
            bytes_out=0;tail_count=0;fd=$fopen(frame==0?"case0.actual.jpg":"case1.actual.jpg","wb");
            for(integer n=0;n<N;n=n+1)begin
                rgb=vectors[n][95:0];luma=vectors[n][127:96];valid=1;sof=n==0;eol=n%(W/4)==W/4-1;
                do @(posedge clk);while(!ready);
                @(negedge clk);
                // Deliberately change the next frame's live controls while the
                // current frame remains owned. Identity and geometry stay fixed.
                quality=frame==0?91:37;restart=frame==0?5:3;epoch=32'hf0000000+frame;
            end
            valid=0;sof=0;eol=0;status_valid=1;
            do @(posedge clk);while(!status_ready);
            @(negedge clk);status_valid=0;
            wait(result_valid);@(negedge clk);
            check(result_ok&&error_code==0&&result_id==101+frame,"real result identity and success");
            check(result_quality==(frame==0?37:91)&&result_epoch==21+frame,"frozen dynamic Q/epoch metadata");
            check(length==bytes_out&&tail_count==1,"byte length and one final TLAST");
            repeat(5)begin @(negedge clk);check(result_valid,"result retains ownership until consumed");end
            $fclose(fd);
            $display("F10_JPEG_FRAME PASS case=%0d Q=%0d RST=%0d epoch=%0d bytes=%0d",frame,result_quality,frame==0?3:5,result_epoch,bytes_out);
            result_ready=1;@(negedge clk);result_ready=0;
        end
        $display("RESULT: PASS F10_DYNAMIC_JPEG checks=%0d",checks);$finish;
    end
endmodule
