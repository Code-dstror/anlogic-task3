`timescale 1ns/1ps
module tb_dct_input;
    parameter integer REFERENCE=0;
    reg clk=0; always #4 clk=~clk;
    reg rst_n=0, valid=0, ready=0;
    wire input_ready, output_valid;
    reg [63:0] data=0;
    reg [2:0] row=0;
    reg [1:0] component=0, block_index=0;
    reg [8:0] x=0,y=0;
    reg last=0;
    reg [31:0] id=0;
    wire [127:0] output_data;
    wire [2:0] column;
    wire [1:0] output_component,output_block;
    wire [8:0] output_x,output_y;
    wire output_last;
    wire [31:0] output_id;
`define DCT_PORTS \
    .i_clk(clk),.i_rst_n(rst_n),.i_block_valid(1'b0),.o_block_ready(), \
    .i_samples(512'd0),.i_component(component),.i_mcu_x(x),.i_mcu_y(y), \
    .i_block_index(block_index),.i_frame_last(last),.i_capture_id(id), \
    .o_block_valid(),.i_block_ready(1'b0),.o_coeffs(),.o_component(), \
    .o_mcu_x(),.o_mcu_y(),.o_block_index(),.o_frame_last(),.o_capture_id(), \
    .o_column_valid(output_valid),.i_column_ready(ready),.o_column_data(output_data), \
    .o_column_index(column),.o_column_component(output_component), \
    .o_column_mcu_x(output_x),.o_column_mcu_y(output_y),.o_column_block_index(output_block), \
    .o_column_frame_last(output_last),.o_column_capture_id(output_id), \
    .i_row_valid(valid),.o_row_ready(input_ready),.i_row_data(data),.i_row_index(row)
    generate if(REFERENCE) begin:r
        dct_baseline #(.OUTPUT_STREAM_MODE(1),.TINY_DISTRIBUTED_RAM_ENABLE(1),.INPUT_ROW_STREAM_ENABLE(1)) dut (`DCT_PORTS);
    end else begin:c
        jpeg_dct8x8_pipeline #(.OUTPUT_STREAM_MODE(1),.TINY_DISTRIBUTED_RAM_ENABLE(1),.INPUT_ROW_STREAM_ENABLE(1)) dut (`DCT_PORTS);
    end endgenerate
`undef DCT_PORTS
    reg [511:0] vectors[0:31];
    reg [1023:0] gold[0:31];
    reg checking=0,stress=0,stalled=0;
    reg [185:0] held;
    wire [185:0] payload={output_component,output_x,output_y,output_block,output_last,output_id,column,output_data};
    reg [31:0] rng=32'h732a9261;
    integer cycle=0,received=0,columns=0,accepted=0,stable=0;
    integer v,start_cycle=0,finish_cycle=0,hold_left=0;
    reg held_final=0;
    always @(negedge clk) begin
        rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
        if(!rst_n || !checking) ready=0;
        else if(hold_left>0) begin ready=0;hold_left=hold_left-1;end
        else if(stress && !held_final && output_valid && column==7) begin
            ready=0;hold_left=23;held_final=1;
        end else ready=!stress || rng[2:0]!=0;
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if(cycle>50000) $fatal(1,"DCT timeout received=%0d columns=%0d",received,columns);
        if(!rst_n) begin received=0;columns=0;accepted=0;stalled=0;end
        else if(checking) begin
            if(valid && input_ready) accepted=accepted+1;
            if(stalled) begin
                stable=stable+1;
                if(!output_valid || payload!==held) $fatal(1,"DCT stalled payload changed");
            end
            stalled=output_valid&&!ready;
            if(stalled) held=payload;
            if(output_valid&&ready) begin
                if(received>=32 || accepted<(received+1)*8) $fatal(1,"Unexpected DCT output");
                if(column!==3'(columns%8)) $fatal(1,"DCT column order");
                if({output_component,output_x,output_y,output_block,output_last,output_id} !==
                   {2'(received%3),9'(received+9),9'(received+3),2'(received%4),1'(received%7==6),32'h12340000+received})
                    $fatal(1,"DCT tag mismatch block=%0d",received);
                for(v=0;v<8;v=v+1)
                    if(output_data[v*16+:16]!==gold[received][(v*8+column)*16+:16])
                        $fatal(1,"DCT numeric mismatch block=%0d v=%0d u=%0d",received,v,column);
                columns=columns+1;
                if(column==7) begin received=received+1;finish_cycle=cycle;end
            end
        end
    end
    task send_rows(input integer blocks,input integer rows);
        integer b,rn;
        begin
            for(b=0;b<blocks;b=b+1) for(rn=0;rn<rows;rn=rn+1) begin
                @(negedge clk);
                valid=1;row=rn;data=vectors[b][rn*64+:64];
                component=b%3;x=b+9;y=b+3;block_index=b%4;last=b%7==6;id=32'h12340000+b;
                @(posedge clk);while(!input_ready) @(posedge clk);
            end
            @(negedge clk);valid=0;
        end
    endtask
    task reset_all;
        begin
            @(negedge clk);rst_n=0;valid=0;checking=0;
            repeat(4) @(negedge clk);
            if(output_valid) $fatal(1,"Reset did not discard output");
            rst_n=1;
        end
    endtask
    initial begin
        $readmemh("samples.hex",vectors);$readmemh("coeffs.hex",gold);
        repeat(150) @(negedge clk);rst_n=1;
        send_rows(1,5);reset_all();
        checking=1;start_cycle=cycle;send_rows(32,8);
        wait(received==32);@(negedge clk);
        $display("DCT_METRIC reference=%0d mode=continuous cycles=%0d columns=%0d",REFERENCE,finish_cycle-start_cycle,columns);
        reset_all();checking=1;stress=1;start_cycle=cycle;send_rows(32,8);
        wait(received==32);repeat(5) @(negedge clk);
        if(stable==0 || !held_final) $fatal(1,"Missing stall coverage");
        $display("RESULT: PASS dct_input reference=%0d coefficients=4096 stable=%0d stress_cycles=%0d",REFERENCE,stable,finish_cycle-start_cycle);
        $finish;
    end
endmodule
