`timescale 1ns/1ps
// OR a five-byte word into the unchanged twenty-byte reservoir.
module jpeg_metadata_append5 (
    input wire [159:0] prior_data,
    input wire [4:0] offset,
    input wire [39:0] word_data,
    output wire [159:0] result
);
    wire [63:0] padded={24'd0,word_data};
    wire [127:0] rotated_pair={padded,padded} << {offset[2:0],3'b000};
    wire [63:0] rotated=rotated_pair[127:64];
    wire [5:0] end_offset={1'b0,offset}+6'd5;
    genvar lane;
    generate for(lane=0;lane<20;lane=lane+1)begin:bytes
        wire selected=offset<=lane && end_offset>lane;
        assign result[lane*8+:8]=prior_data[lane*8+:8] |
            (selected ? rotated[(lane%8)*8+:8] : 8'd0);
    end endgenerate
endmodule
