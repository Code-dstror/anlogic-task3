`timescale 1ns/1ps
// Replace exactly five byte lanes; untouched bytes retain their prior value.
module raw10_append5 #(parameter integer CAPACITY=25) (
    input wire [CAPACITY*8-1:0] prior_data,
    input wire [4:0] offset,
    input wire [39:0] raw_data,
    output wire [CAPACITY*8-1:0] result
);
    wire [63:0] padded={24'd0,raw_data};
    wire [127:0] duplicated={padded,padded};
    wire [127:0] shifted=duplicated << {offset[2:0],3'b000};
    wire [63:0] rotated=shifted[127:64];
    wire [5:0] end_offset={1'b0,offset}+6'd5;
    genvar lane;
    generate for(lane=0;lane<CAPACITY;lane=lane+1)begin:bytes
        wire selected=offset<=lane && end_offset>lane;
        assign result[lane*8+:8]=selected ? rotated[(lane%8)*8+:8] : prior_data[lane*8+:8];
    end endgenerate
endmodule
