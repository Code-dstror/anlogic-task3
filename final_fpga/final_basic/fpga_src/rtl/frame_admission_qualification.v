`timescale 1ns/1ps
module frame_admission_qualification (
    input wire i_clk,i_rst_n,
    input wire i_available,i_take,i_inhibit,
    output wire o_available
);
    reg available;
    assign o_available=available&&!i_inhibit;
    always @(posedge i_clk or negedge i_rst_n)begin
        if(!i_rst_n)available<=0;
        else if(i_take||i_inhibit)available<=0;
        else available<=i_available;
    end
endmodule
