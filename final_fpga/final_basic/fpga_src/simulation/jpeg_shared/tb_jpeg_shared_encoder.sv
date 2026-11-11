`timescale 1ns/1ps
module tb_jpeg_shared_encoder #(
    parameter integer CASE_INDEX=0, WIDTH=4, HEIGHT=1, QUALITY=75, RESTART=0,
    parameter integer EXPECTED_BYTES=625, OUTPUT_STALLS=1,
    parameter ROM_ROOT="rom_init"
);
    reg clk=0;always #4 clk=!clk;
    reg rst_n=0,source_valid=0,sof=0,eol=0,status_valid=0,frame_ok=1;
    reg [95:0] rgb=0;
    reg [31:0] luma=0,capture=0,status_id=0,session=0,epoch=0;
    reg [7:0] quality=QUALITY;
    reg [15:0] restart=RESTART;
    reg camera=0;
    reg [12:0] width=WIDTH,height=HEIGHT;
    wire source_ready,status_ready,axis_valid,axis_last,result_valid,result_ok,idle;
    wire [127:0] axis_data;
    wire [15:0] axis_keep;
    wire [31:0] result_id,result_epoch;
    wire [24:0] result_length;
    wire [7:0] result_error,result_quality;
    reg axis_ready=1,result_ready=0;
    jpeg_encoder_top #(.MAX_WIDTH(WIDTH),.MAX_HEIGHT(HEIGHT),.SHARED_STREAM_ENABLE(1),
        .TINY_DISTRIBUTED_RAM_ENABLE(0),.COEFF_BANKED_STORAGE_ENABLE(1),
        .MCU_ROW_STREAM_ENABLE(1),.FIXED_GEOMETRY_ENABLE(1),
        .ROM_INIT_ROOT(ROM_ROOT),.ROM_INIT_SUFFIX(".mif.dath")) dut (
        .i_clk(clk),.i_rst_n(rst_n),.i_rgb(rgb),.i_luma(luma),.i_quality(quality),
        .i_session_id(session),.i_mode_epoch(epoch),.i_camera_id(camera),.i_restart_mcus(restart),
        .i_rgb_valid(source_valid),.o_rgb_ready(source_ready),.i_sof(sof),.i_eol(eol),
        .i_capture_id(capture),.i_width(width),.i_height(height),
        .i_frame_status_valid(status_valid),.o_frame_status_ready(status_ready),
        .i_frame_status_id(status_id),.i_frame_ok(frame_ok),
        .o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),.o_axis_tvalid(axis_valid),
        .i_axis_tready(axis_ready),.o_axis_tlast(axis_last),
        .o_result_valid(result_valid),.i_result_ready(result_ready),.o_result_id(result_id),
        .o_result_ok(result_ok),.o_payload_length(result_length),.o_error_code(result_error),
        .o_result_quality(result_quality),.o_result_epoch(result_epoch),.o_idle(idle));
    reg [127:0] inputs[0:WIDTH*HEIGHT/4-1];
    reg [7:0] golden[0:EXPECTED_BYTES-1];
    integer cycles=0,start_cycle=0,last_cycle=0,result_cycle=0,got=0,last_count=0,sent=0;
    integer source_wait=0,mcu_blocks=0,column_count=0,token_count=0,entropy_bytes=0,formatter_bytes=0;
    integer dct_wait=0,column_wait=0,token_wait=0,entropy_wait=0,format_wait=0;
    integer entropy_collect=0,entropy_load=0,entropy_dc=0,entropy_ac=0,entropy_other=0;
    integer ent_blocks=0,previous_ent=-1,ent_interval_count=0,ent_interval_sum=0,ent_interval_max=0;
    integer mcu_previous=-1,mcu_interval_sum=0,mcu_interval_count=0,mcu_interval_max=0;
    integer lane,n,hold_left=0,tail_hold=0,stable_checks=0,output_fd=0,recovery=0;
    reg checking=0,source_active=0,held=0,force_stall=0,tail_held=0;
    reg [144:0] held_axis;
    wire [144:0] axis_payload={axis_last,axis_keep,axis_data};
    reg [31:0] rng=32'h75a42260;
    string path;
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(force_stall) axis_ready=0;
        else if(checking&&OUTPUT_STALLS&&axis_valid&&axis_last&&tail_hold<17) begin
            tail_hold=tail_hold+1;tail_held=1;axis_ready=0;
        end else axis_ready=!checking||!OUTPUT_STALLS||rng[2:0]!=0;
    end
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>20000000) $fatal(1,"encoder timeout case%0d state=%0d entropy=%0d sent=%0d bytes=%0d",CASE_INDEX,dut.state,dut.u_entropy.state,sent,got);
        if(cycles%262144==0&&checking)
            $display("PROGRESS encoder case%0d cycle=%0d source=%0d/%0d bytes=%0d/%0d ent_blocks=%0d",CASE_INDEX,cycles-start_cycle,sent,WIDTH*HEIGHT/4,got,EXPECTED_BYTES,ent_blocks);
        if(!rst_n) held=0;
        else begin
            if(held) begin
                stable_checks=stable_checks+1;
                if(!axis_valid||axis_payload!==held_axis) $fatal(1,"encoder published AXIS changed under stall");
            end
            held=axis_valid&&!axis_ready;if(held) held_axis=axis_payload;
            if(checking) begin
                if(source_active&&!source_valid) $fatal(1,"encoder source inserted an active-frame bubble");
                if(source_valid&&source_ready) begin if(sof) start_cycle=cycles;sent=sent+1;end
                if(source_valid&&!source_ready) source_wait=source_wait+1;
                if(dut.mcu_row_valid&&dut.mcu_row_ready&&dut.mcu_row_index==7) begin
                    mcu_blocks=mcu_blocks+1;
                    if(mcu_previous>=0&&mcu_blocks>(WIDTH+15)/16*((HEIGHT+7)/8)*2) begin
                        mcu_interval_count=mcu_interval_count+1;mcu_interval_sum=mcu_interval_sum+cycles-mcu_previous;
                        if(cycles-mcu_previous>mcu_interval_max) mcu_interval_max=cycles-mcu_previous;
                    end
                    mcu_previous=cycles;
                end
                if(dut.mcu_valid&&!dut.dct_ready) dct_wait=dct_wait+1;
                if(dut.stream.col_valid&&dut.stream.col_ready) column_count=column_count+1;
                if(dut.stream.col_valid&&!dut.stream.col_ready) column_wait=column_wait+1;
                if(dut.coeff_token_valid&&dut.coeff_token_ready) begin
                    token_count=token_count+1;
                    if(dut.coeff_token[146:145]==1) begin
                        ent_blocks=ent_blocks+1;
                        if(previous_ent>=0&&ent_blocks>(WIDTH+15)/16*((HEIGHT+7)/8)*2) begin
                            ent_interval_count=ent_interval_count+1;ent_interval_sum=ent_interval_sum+cycles-previous_ent;
                            if(cycles-previous_ent>ent_interval_max) ent_interval_max=cycles-previous_ent;
                        end
                        previous_ent=cycles;
                    end
                end
                if(dut.coeff_token_valid&&!dut.coeff_token_ready) token_wait=token_wait+1;
                if(dut.ent_valid&&dut.fmt_ent_ready) entropy_bytes=entropy_bytes+1;
                if(dut.ent_valid&&!dut.fmt_ent_ready) entropy_wait=entropy_wait+1;
                if(dut.fmt_valid&&dut.pack_ready) formatter_bytes=formatter_bytes+1;
                if(dut.fmt_valid&&!dut.pack_ready) format_wait=format_wait+1;
                // Collection runs in parallel with active DC/AC states.
                if(dut.u_entropy.collecting) entropy_collect=entropy_collect+1;
                if(dut.u_entropy.pending_launch) entropy_load=entropy_load+1;
                case(dut.u_entropy.state)
                    1:entropy_dc=entropy_dc+1;
                    2:entropy_ac=entropy_ac+1;
                    default:entropy_other=entropy_other+1;
                endcase
                if(axis_valid&&axis_ready) begin
                    if(axis_keep==0||(axis_keep&(axis_keep+16'd1))!=0||(!axis_last&&axis_keep!=16'hffff))
                        $fatal(1,"encoder invalid KEEP/LAST");
                    if(output_fd) $fdisplay(output_fd,"%032h %04h",axis_data,axis_keep);
                    for(lane=0;lane<16;lane=lane+1) if(axis_keep[lane]) begin
                        if(got>=EXPECTED_BYTES||axis_data[lane*8 +:8]!==golden[got])
                            $fatal(1,"encoder byte mismatch case%0d offset=%0d actual=%h expected=%h ent_state=%0d",CASE_INDEX,got,axis_data[lane*8 +:8],golden[got],dut.u_entropy.state);
                        got=got+1;
                    end
                    if(axis_last) begin last_count=last_count+1;last_cycle=cycles;end
                end
                if(axis_valid&&axis_last&&!axis_ready&&result_valid) $fatal(1,"encoder result before held final AXIS acceptance");
            end
        end
    end
    task clear_metrics;
        begin
            got=0;last_count=0;sent=0;start_cycle=0;last_cycle=0;source_wait=0;
            mcu_blocks=0;column_count=0;token_count=0;entropy_bytes=0;formatter_bytes=0;
            dct_wait=0;column_wait=0;token_wait=0;entropy_wait=0;format_wait=0;
            entropy_collect=0;entropy_load=0;entropy_dc=0;entropy_ac=0;entropy_other=0;
            ent_blocks=0;previous_ent=-1;ent_interval_count=0;ent_interval_sum=0;ent_interval_max=0;
            mcu_previous=-1;mcu_interval_count=0;mcu_interval_sum=0;mcu_interval_max=0;tail_hold=0;
        end
    endtask
    task drive_status;
        input integer success;
        begin
            @(negedge clk);status_id=capture;frame_ok=success;status_valid=1;
            @(posedge clk);while(!status_ready) @(posedge clk);
            @(negedge clk);status_valid=0;
        end
    endtask
    task accept_result;
        input integer success,expected_error;
        reg [105:0] result_copy;
        begin
            wait(result_valid);@(negedge clk);
            if(result_id!==capture||result_ok!==success[0]||result_error!==expected_error[7:0]||
               result_length!==(success ? EXPECTED_BYTES : 0))
                $fatal(1,"encoder result case%0d id=%h ok=%b code=%0d bytes=%0d expected_success=%0d",CASE_INDEX,result_id,result_ok,result_error,result_length,success);
            if(success&&(result_quality!=QUALITY||result_epoch!=32'h20200000+CASE_INDEX))
                $fatal(1,"encoder frame quality/epoch did not freeze");
            result_copy={result_id,result_ok,result_error,result_length,result_quality,result_epoch};
            repeat(5) begin
                @(negedge clk);
                if(!result_valid||{result_id,result_ok,result_error,result_length,result_quality,result_epoch}!==result_copy)
                    $fatal(1,"encoder result changed while held");
            end
            result_ready=1;@(negedge clk);result_ready=0;wait(idle);
        end
    endtask
    task good_frame;
        begin
            wait(idle);@(negedge clk);clear_metrics();checking=1;
            width=WIDTH;height=HEIGHT;quality=QUALITY;restart=RESTART;
            session=32'h10100000+CASE_INDEX;epoch=32'h20200000+CASE_INDEX;camera=CASE_INDEX%2;
            capture=32'h70300000+CASE_INDEX+recovery*100;
            path=$sformatf("case%0d.axis.hex",CASE_INDEX);output_fd=$fopen(path,"w");
            for(n=0;n<WIDTH*HEIGHT/4;n=n+1) begin
                @(negedge clk);rgb=inputs[n][95:0];luma=inputs[n][127:96];
                sof=n==0;eol=n%(WIDTH/4)==WIDTH/4-1;source_valid=1;source_active=1;
                @(posedge clk);while(!source_ready) @(posedge clk);
                if(n==0) begin
                    // Only these frame controls may change after the accepted SOF.
                    @(negedge clk);quality=1;restart=65535;epoch=0;session=0;camera=!camera;
                    // The next pixel still arrives on this same negative edge.
                    if(WIDTH*HEIGHT/4>1) begin
                        n=n+1;rgb=inputs[n][95:0];luma=inputs[n][127:96];sof=0;eol=n%(WIDTH/4)==WIDTH/4-1;
                        @(posedge clk);while(!source_ready) @(posedge clk);
                    end
                end
            end
            @(negedge clk);source_active=0;source_valid=0;sof=0;eol=0;
            drive_status(1);wait(result_valid);result_cycle=cycles;
            if(got!=EXPECTED_BYTES||last_count!=1||sent!=WIDTH*HEIGHT/4||
                mcu_blocks!=(WIDTH+15)/16*((HEIGHT+7)/8)*4||column_count!=mcu_blocks*8||token_count!=mcu_blocks*9)
                $fatal(1,"encoder frame counts mismatch case%0d bytes=%0d sent=%0d blocks=%0d columns=%0d tokens=%0d",CASE_INDEX,got,sent,mcu_blocks,column_count,token_count);
            $display("ENCODER_METRIC case=%0d width=%0d height=%0d Q=%0d RST=%0d service_cycles=%0d axis_cycles=%0d bytes=%0d input_wait=%0d mcu_blocks=%0d ent_blocks=%0d mcu_avg_x100=%0d mcu_max=%0d ent_avg_x100=%0d ent_max=%0d",
                CASE_INDEX,WIDTH,HEIGHT,QUALITY,RESTART,result_cycle-start_cycle+1,last_cycle-start_cycle+1,got,source_wait,mcu_blocks,ent_blocks,
                mcu_interval_count ? mcu_interval_sum*100/mcu_interval_count : 0,mcu_interval_max,
                ent_interval_count ? ent_interval_sum*100/ent_interval_count : 0,ent_interval_max);
            $display("ENCODER_STAGE case=%0d dct_wait=%0d col_wait=%0d token_wait=%0d entbyte_wait=%0d fmt_wait=%0d entropy_bytes=%0d formatter_bytes=%0d collect=%0d load=%0d dc=%0d ac=%0d other=%0d",
                CASE_INDEX,dct_wait,column_wait,token_wait,entropy_wait,format_wait,entropy_bytes,formatter_bytes,entropy_collect,entropy_load,entropy_dc,entropy_ac,entropy_other);
            $fclose(output_fd);output_fd=0;
            accept_result(1,0);@(negedge clk);checking=0;
        end
    endtask
    task bad_frame;
        input integer status_fault;
        begin
            wait(idle);@(negedge clk);checking=0;capture=capture+1;
            quality=QUALITY;restart=RESTART;width=status_fault ? WIDTH : 12;height=1;
            rgb=inputs[0][95:0];luma=inputs[0][127:96];sof=1;eol=1;source_valid=1;
            @(posedge clk);while(!source_ready) @(posedge clk);
            @(negedge clk);source_valid=0;sof=0;eol=0;
            if(status_fault) begin
                force_stall=1;wait(axis_valid);drive_status(0);
                repeat(11) @(negedge clk);
                if(result_valid) $fatal(1,"encoder failed result overtook held candidate AXIS");
                force_stall=0;
            end
            accept_result(0,status_fault ? 1 : 2);
        end
    endtask
    initial begin
        path=$sformatf("case%0d.inputs.hex",CASE_INDEX);$readmemh(path,inputs,0,WIDTH*HEIGHT/4-1);
        path=$sformatf("case%0d.bytes.hex",CASE_INDEX);$readmemh(path,golden,0,EXPECTED_BYTES-1);
        repeat(160) @(negedge clk);rst_n=1;
        good_frame();
        if(CASE_INDEX==0) begin
            bad_frame(1);recovery=1;good_frame();bad_frame(0);recovery=2;good_frame();
        end
        if(OUTPUT_STALLS&&!tail_held) $fatal(1,"encoder final AXIS stall not exercised");
        $display("RESULT: PASS shared encoder case%0d stable=%0d error/recovery=%0d",CASE_INDEX,stable_checks,recovery);
        $finish;
    end
endmodule
