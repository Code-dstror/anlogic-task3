`timescale 1ns/1ps
// Combinational insertion into a32-byte reservoir. With append asserted the
// exporter guarantees residual_count0..16 and read_bytes1..16. No byte outside
// the accepted read prefix is written; all existing carry bytes are preserved.
module lz_export_byte_append32(
    input wire [255:0] residual_data,
    input wire [5:0] residual_count,
    input wire [127:0] read_data,
    input wire [4:0] read_bytes,
    input wire append,
    output wire [255:0] next_data
);
    wire [127:0] rot1=residual_count[0] ? {read_data[119:0],read_data[127:120]} : read_data;
    wire [127:0] rot2=residual_count[1] ? {rot1[111:0],rot1[127:112]} : rot1;
    wire [127:0] rot4=residual_count[2] ? {rot2[95:0],rot2[127:96]} : rot2;
    wire [127:0] rot8=residual_count[3] ? {rot4[63:0],rot4[127:64]} : rot4;
    wire [5:0] end_count=residual_count+{1'b0,read_bytes};
    genvar byte_lane;
    generate for(byte_lane=0;byte_lane<32;byte_lane=byte_lane+1)begin:g_byte
        wire write_byte=append && residual_count<=byte_lane && end_count>byte_lane;
        assign next_data[byte_lane*8+:8]=write_byte ? rot8[(byte_lane%16)*8+:8] : residual_data[byte_lane*8+:8];
    end endgenerate
endmodule
