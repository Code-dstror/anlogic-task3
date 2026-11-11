`timescale 1ns/1ps
module tb_s1_row;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,frame_start=0,input_eol=0;
    reg [39:0] frame_gain;
    reg [31:0] frame_center;
    wire [9:0] row_gain;wire [7:0] row_center;wire fault;
    reg [17:0] gold [0:8639];reg [71:0] bands [0:7];
    reg [1023:0] root;
    integer pattern,y,t,max_cycles,cycles;
    preprocess_light_haze_row dut(.*);
    initial begin
        if(!$value$plusargs("ROOT=%s",root)) $fatal(1,"ROOT missing");
        $readmemh({root,"/rows.mem"},gold);$readmemh({root,"/bands.mem"},bands);
        repeat(5) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        max_cycles=0;
        for(pattern=0;pattern<8;pattern=pattern+1) begin
            frame_gain=bands[pattern][39:0];frame_center=bands[pattern][71:40];
            frame_start=1;@(negedge clk);frame_start=0;
            for(y=0;y<1080;y=y+1) begin
                if({row_center,row_gain}!==gold[pattern*1080+y])
                    $fatal(1,"row mismatch pattern=%0d y=%0d got=%h gold=%h",pattern,y,{row_center,row_gain},gold[pattern*1080+y]);
                if(fault) $fatal(1,"row deadline fault");
                // Seven wall clocks per test row stresses the six-cycle
                // budget more tightly than production's minimum 480 clocks.
                input_eol=1;@(negedge clk);input_eol=0;
                cycles=0;
                for(t=0;t<6;t=t+1) begin
                    if(!dut.next_ready) cycles=cycles+1;
                    @(negedge clk);
                end
                if(cycles>max_cycles) max_cycles=cycles;
            end
        end
        clear=1;@(negedge clk);clear=0;
        if(fault||row_gain!==256) $fatal(1,"clear failed");
        $display("RESULT: PASS S1_ROW patterns=8 rows=8640 max_background_clocks=%0d minimum_pixel_line_clocks=480",max_cycles);
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
