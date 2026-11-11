`timescale 1ns/1ps
module tb_mcu_write_ports;
    localparam W=240,H=24;
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,valid=0,sof=0,eol=0,out_ready=0;
    reg [31:0] y=0,id=0;
    reg [15:0] cb=0,cr=0;
    wire ready,ready_ref,row_valid,row_valid_ref,error_valid,error_ref;
    wire [63:0] data,data_ref;
    wire [2:0] index,index_ref,code,code_ref;
    wire [1:0] comp,comp_ref,block_id,block_ref;
    wire [8:0] mx,my,mx_ref,my_ref;
    wire last,last_ref;
    wire [31:0] capture,capture_ref,error_id,error_id_ref;
`define MCU_PORTS(R,V,D,I,C,B,X,Y,L,ID,E,EI,EC) \
        .i_clk(clk),.i_rst_n(rst_n),.i_valid(valid),.o_ready(R),.i_y(y),.i_cb(cb),.i_cr(cr), \
        .i_sof(sof),.i_eol(eol),.i_capture_id(id),.i_width(13'(W)),.i_height(13'(H)), \
        .o_block_valid(),.i_block_ready(1'b0),.o_samples(),.o_component(C),.o_block_index(B), \
        .o_mcu_x(X),.o_mcu_y(Y),.o_frame_last(L),.o_capture_id(ID), \
        .o_error_valid(E),.o_error_capture_id(EI),.o_error_code(EC), \
        .o_row_valid(V),.i_row_ready(out_ready),.o_row_data(D),.o_row_index(I)
    jpeg_mcu_422 #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.ROW_STREAM_ENABLE(1),.FIXED_GEOMETRY_ENABLE(1)) dut (
        `MCU_PORTS(ready,row_valid,data,index,comp,block_id,mx,my,last,capture,error_valid,error_id,code));
    mcu_baseline #(.MAX_WIDTH(W),.MAX_HEIGHT(H),.ROW_STREAM_ENABLE(1),.FIXED_GEOMETRY_ENABLE(1)) ref_dut (
        `MCU_PORTS(ready_ref,row_valid_ref,data_ref,index_ref,comp_ref,block_ref,mx_ref,my_ref,last_ref,capture_ref,error_ref,error_id_ref,code_ref));
`undef MCU_PORTS
    integer checks=0,bytes_checked=0,stalls=0,cycles=0,received=0;
    integer expected_frame=1,expected_rows=H/8*(W/16)*4*8;
    integer group_no,mcu_no,block_no,row_no,x,ypos,k;
    reg checking=0,stress=0,stalled=0,held_last=0;
    reg [121:0] held;
    wire [121:0] payload={comp,block_id,mx,my,last,capture,index,data};
    wire [121:0] ref_payload={comp_ref,block_ref,mx_ref,my_ref,last_ref,capture_ref,index_ref,data_ref};
    reg [31:0] rng=32'h892431a7;
    integer hold_left=0;
    function automatic [7:0] sample(input integer f,c,px,py);
        sample=(px*(c+3)+py*(11+6*c)+f*(3+2*c))&255;
    endfunction
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(!rst_n)out_ready=0;
        else if(hold_left>0)begin hold_left=hold_left-1;out_ready=0;end
        else if(stress&&!held_last&&row_valid&&last&&index==7)begin
            held_last=1;hold_left=17;out_ready=0;
        end else out_ready=!stress || rng[3:0]>3;
    end
    always @(posedge clk) begin
        cycles=cycles+1;if(cycles>60000)$fatal(1,"MCU timeout");
        if(rst_n)begin
            checks=checks+1;
            if({ready,row_valid,error_valid}!=={ready_ref,row_valid_ref,error_ref})$fatal(1,"MCU control differs");
            if(row_valid&&payload!==ref_payload)$fatal(1,"MCU output/tag cycle differs");
            if(error_valid&&{error_id,code}!=={error_id_ref,code_ref})$fatal(1,"MCU error differs");
            if(stalled)begin stalls=stalls+1;if(!row_valid||payload!==held)$fatal(1,"MCU stall lost");end
            stalled=row_valid&&!out_ready;if(stalled)held=payload;
            if(checking&&row_valid&&out_ready)begin
                group_no=received/((W/16)*4*8);mcu_no=(received/(4*8))%(W/16);
                block_no=(received/8)%4;row_no=received%8;
                if({comp,block_id,mx,my,last,capture,index}!==
                    {2'(block_no<2?0:block_no-1),2'(block_no),9'(mcu_no),9'(group_no),
                     1'(received/8==(expected_rows/8-1)),32'(expected_frame),3'(row_no)})
                    $fatal(1,"MCU golden metadata received=%0d",received);
                for(k=0;k<8;k=k+1)begin
                    x=block_no<2?mcu_no*16+block_no*8+k:mcu_no*8+k;ypos=group_no*8+row_no;
                    if(data[k*8+:8]!==sample(expected_frame,block_no<2?0:block_no-1,x,ypos))
                        $fatal(1,"MCU golden data row=%0d lane=%0d",received,k);
                    bytes_checked=bytes_checked+1;
                end
                received=received+1;
            end
        end else stalled=0;
    end
    task send(input integer f,rows,corrupt);
        integer px,py,lane;
        begin
            for(py=0;py<rows;py=py+1)for(px=0;px<W;px=px+4)begin
                @(negedge clk);valid=1;sof=(px==0&&py==0);eol=(px==W-4);
                id=f+((corrupt&&py==2&&px==8)?1:0);
                for(lane=0;lane<4;lane=lane+1)y[lane*8+:8]=sample(f,0,px+lane,py);
                for(lane=0;lane<2;lane=lane+1)begin
                    cb[lane*8+:8]=sample(f,1,px/2+lane,py);cr[lane*8+:8]=sample(f,2,px/2+lane,py);
                end
                @(posedge clk);while(!ready)@(posedge clk);
            end
            @(negedge clk);valid=0;sof=0;eol=0;
        end
    endtask
    task reset_all;
        begin @(negedge clk);rst_n=0;valid=0;repeat(4)@(negedge clk);rst_n=1;end
    endtask
    integer f;
    initial begin
        repeat(150)@(negedge clk);rst_n=1;
        send(99,1,0);reset_all();
        for(f=1;f<=3;f=f+1)begin
            expected_frame=f;received=0;checking=1;stress=f!=1;held_last=0;
            send(f,H,0);wait(received==expected_rows);@(negedge clk);checking=0;
        end
        // Error before a bank becomes full, then a fresh complete frame.
        send(9,3,1);expected_frame=4;received=0;checking=1;held_last=0;
        send(4,H,0);wait(received==expected_rows);@(negedge clk);checking=0;
        if(stalls==0||!held_last)$fatal(1,"MCU stall coverage missing");
        $display("RESULT: PASS mcu_write_ports checks=%0d bytes=%0d stalls=%0d frames=4",checks,bytes_checked,stalls);
        $finish;
    end
endmodule
