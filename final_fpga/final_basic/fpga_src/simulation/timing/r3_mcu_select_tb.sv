`timescale 1ns/1ps
module r3_mcu_select_tb;
    parameter integer ROW_STREAM=1,FIXED=1;
    localparam W=240,H=16,ROWS=H/8*(W/16)*4*8;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0,out_ready=0;
    reg [31:0] y=0,id=0;reg [15:0] cb=0,cr=0;
    wire ready,ref_ready,row_valid,ref_row_valid,block_valid,ref_block_valid,error_valid,ref_error;
    wire [63:0] row_data,ref_row_data;wire [511:0] samples,ref_samples;
    wire [2:0] row_index,ref_index,error_code,ref_error_code;
    wire [1:0] component,ref_component,block_id,ref_block;
    wire [8:0] mx,my,ref_x,ref_y;wire last,ref_last;
    wire [31:0] capture,ref_capture,error_id,ref_error_id;
`define MCU(R,RV,BV,D,S,I,C,B,X,Y,L,ID,E,EI,EC) \
        .i_clk(clk),.i_rst_n(rst_n),.i_valid(valid),.o_ready(R),.i_y(y),.i_cb(cb),.i_cr(cr), \
        .i_sof(sof),.i_eol(eol),.i_capture_id(id),.i_width(13'(W)),.i_height(13'(H)), \
        .o_block_valid(BV),.i_block_ready(ROW_STREAM?1'b0:out_ready),.o_samples(S), \
        .o_component(C),.o_block_index(B),.o_mcu_x(X),.o_mcu_y(Y),.o_frame_last(L),.o_capture_id(ID), \
        .o_error_valid(E),.o_error_capture_id(EI),.o_error_code(EC), \
        .o_row_valid(RV),.i_row_ready(ROW_STREAM?out_ready:1'b0),.o_row_data(D),.o_row_index(I)
    jpeg_mcu_422 #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.ROW_STREAM_ENABLE(ROW_STREAM),.FIXED_GEOMETRY_ENABLE(FIXED)) dut(
        `MCU(ready,row_valid,block_valid,row_data,samples,row_index,component,block_id,mx,my,last,capture,error_valid,error_id,error_code));
    r3_ref_jpeg_mcu_422 #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.ROW_STREAM_ENABLE(ROW_STREAM),.FIXED_GEOMETRY_ENABLE(FIXED)) baseline(
        `MCU(ref_ready,ref_row_valid,ref_block_valid,ref_row_data,ref_samples,ref_index,ref_component,ref_block,ref_x,ref_y,ref_last,ref_capture,ref_error,ref_error_id,ref_error_code));
`undef MCU
    wire present=ROW_STREAM?row_valid:block_valid;
    wire ref_present=ROW_STREAM?ref_row_valid:ref_block_valid;
    wire [511:0] data=ROW_STREAM?{448'd0,row_data}:samples;
    wire [511:0] ref_data=ROW_STREAM?{448'd0,ref_row_data}:ref_samples;
    wire [569:0] payload={component,block_id,mx,my,last,capture,row_index,data};
    wire [569:0] ref_payload={ref_component,ref_block,ref_x,ref_y,ref_last,ref_capture,ref_index,ref_data};
    integer cycles=0,checks=0,bytes_checked=0,stalls=0,received=0,expected_frame=0;
    integer hold_left=0,reset_checks=0;reg checking=0,stress=0,stalled=0,pause_boundary=0,tail_stalled=0;
    reg [3:0] component_stalls=0;reg [569:0] held;
    reg [31:0] rng=32'h7c91245a;
    function automatic [7:0] sample(input integer frame,plane,x,ypos);
        sample=8'((x*(plane+3)+ypos*(11+6*plane)+frame*(3+2*plane))^((x*ypos)>>(plane+1)));
    endfunction
    always @(negedge clk)begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(!rst_n)out_ready=0;
        else if(pause_boundary&&present&&(!ROW_STREAM||row_index==7))out_ready=0;
        else if(hold_left>0)begin hold_left=hold_left-1;out_ready=0;end
        else if(checking&&stress&&present&&(!ROW_STREAM||row_index==7)&&!component_stalls[block_id])begin
            component_stalls[block_id]=1;hold_left=9;out_ready=0;
        end else if(checking&&stress&&present&&last&&(!ROW_STREAM||row_index==7)&&!tail_stalled)begin
            tail_stalled=1;hold_left=17;out_ready=0;
        end else out_ready=!stress||rng[3:0]>3;
    end
    always @(posedge clk)begin
        cycles=cycles+1;if(cycles>100000)$fatal(1,"R3 MCU watchdog");
        if(rst_n)begin
            checks=checks+1;
            if({ready,row_valid,block_valid,error_valid}!=={ref_ready,ref_row_valid,ref_block_valid,ref_error})
                $fatal(1,"R3 MCU cycle control differs row=%0d fixed=%0d",ROW_STREAM,FIXED);
            if(present&&payload!==ref_payload)$fatal(1,"R3 MCU valid payload/metadata differs");
            if(error_valid&&{error_id,error_code}!=={ref_error_id,ref_error_code})$fatal(1,"R3 MCU error differs");
            if(stalled)begin stalls=stalls+1;if(!present||payload!==held)$fatal(1,"R3 MCU held output changed");end
            stalled=present&&!out_ready;if(stalled)held=payload;
            if(checking&&present&&out_ready)begin : score
                integer block_number,group_number,mcu_number,kind,first_row,number_rows,px,py;
                block_number=ROW_STREAM?received/8:received;
                group_number=block_number/((W/16)*4);mcu_number=(block_number/4)%(W/16);kind=block_number%4;
                first_row=ROW_STREAM?received%8:0;number_rows=ROW_STREAM?1:8;
                if({component,block_id,mx,my,last,capture}!==
                    {2'(kind<2?0:kind-1),2'(kind),9'(mcu_number),9'(group_number),
                     1'(block_number==ROWS/8-1),32'(expected_frame)})$fatal(1,"R3 MCU golden tags");
                if(ROW_STREAM&&row_index!=first_row)$fatal(1,"R3 MCU golden row index");
                for(integer r=0;r<number_rows;r=r+1)for(integer k=0;k<8;k=k+1)begin
                    px=kind<2?mcu_number*16+kind*8+k:mcu_number*8+k;py=group_number*8+first_row+r;
                    if(data[(r*8+k)*8+:8]!==sample(expected_frame,kind<2?0:kind-1,px,py))
                        $fatal(1,"R3 MCU scalar pixel mismatch frame=%0d block=%0d row=%0d lane=%0d",expected_frame,block_number,first_row+r,k);
                    bytes_checked=bytes_checked+1;
                end
                received=received+1;
            end
            // A row7 transfer forbids another synchronous read on that edge.
            if(ROW_STREAM&&row_valid&&out_ready&&row_index==7&&dut.read_enable)
                $fatal(1,"R3 row7/read alignment precondition violated");
        end else stalled=0;
    end
    task send(input integer frame,rows,corrupt);
        begin
            for(integer py=0;py<rows;py=py+1)for(integer px=0;px<W;px=px+4)begin
                @(negedge clk);valid=1;sof=px==0&&py==0;eol=px==W-4;
                id=frame+((corrupt&&py==2&&px==8)?1:0);
                for(integer k=0;k<4;k=k+1)y[k*8+:8]=sample(frame,0,px+k,py);
                for(integer k=0;k<2;k=k+1)begin cb[k*8+:8]=sample(frame,1,px/2+k,py);cr[k*8+:8]=sample(frame,2,px/2+k,py);end
                do @(posedge clk);while(!ready);
            end
            @(negedge clk);valid=0;sof=0;eol=0;
        end
    endtask
    task reset_all;
        begin
            @(negedge clk);rst_n=0;valid=0;checking=0;repeat(4)@(negedge clk);rst_n=1;pause_boundary=0;
            repeat(2)@(negedge clk);
            if(row_valid||block_valid)$fatal(1,"R3 reset leaked old row/block");reset_checks=reset_checks+1;
        end
    endtask
    task full_frame(input integer frame,input bit stressed);
        begin
            expected_frame=frame;received=0;checking=1;stress=stressed;component_stalls=0;tail_stalled=0;
            send(frame,H,0);wait(received==(ROW_STREAM?ROWS:ROWS/8));@(negedge clk);checking=0;
            if(stressed&&component_stalls!=4'hf)$fatal(1,"R3 Y0/Y1/Cb/Cr boundary stall coverage");
            if(stressed&&!tail_stalled)$fatal(1,"R3 last-row/block stall not exercised");
        end
    endtask
    initial begin
        repeat(150)@(negedge clk);rst_n=1;
        send(99,1,0);reset_all();
        // Two full frames without resetting or inserting a frame preparation cycle.
        full_frame(1,0);full_frame(2,1);
        stress=0;pause_boundary=1;send(98,H,0);
        wait(present&&(!ROW_STREAM||row_index==7));repeat(3)@(negedge clk);reset_all();
        full_frame(3,1);
        send(97,3,1);full_frame(4,1);
        if(bytes_checked!=4*(ROWS/8)*64||stalls==0||reset_checks!=2)$fatal(1,"R3 MCU final coverage");
        $display("RESULT: PASS R3_MCU_SELECT row=%0d fixed=%0d checks=%0d bytes=%0d stalls=%0d frames=4 resets=%0d",
            ROW_STREAM,FIXED,checks,bytes_checked,stalls,reset_checks);$finish;
    end
endmodule
