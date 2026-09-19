`timescale 1ns/1ps
module tb_camera_isp_gamma;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [9:0] index = 10'd0;
    wire [7:0] value;
    integer errors = 0;

    always #4 clk = ~clk;
    gamma_lut_10to8 u_dut (.i_clk(clk), .i_rstn(rst_n), .i_index(index), .o_value(value));

    task check;
        input [9:0] test_index;
        input [7:0] expected;
        begin
            index = test_index;
            @(posedge clk); #1;
            if (value !== expected) begin
                $display("FAIL gamma[%0d]=%0d expected %0d", test_index, value, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        check(10'd0, 8'd0);
        check(10'd256, 8'd136);
        check(10'd512, 8'd186);
        check(10'd1023, 8'd255);
        if (errors == 0) $display("@@@TB PASS: PH1 gamma ROM samples clean");
        else $display("@@@TB FAIL: gamma errors=%0d", errors);
        $finish;
    end
endmodule
