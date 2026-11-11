module uhd_probe (
    input wire clk, rst_n, abort, valid, last, ready,
    input wire [7:0] data,
    output reg [28:0] observe
);
    reg [12:0] stimulus;
    wire [127:0] packed_data;
    wire [15:0] keep;
    wire in_ready, out_valid, out_last, frame_error, overflow, idle;
    wire [7:0] folded;
    genvar bit_index, byte_index;
    generate for (bit_index=0; bit_index<8; bit_index=bit_index+1) begin : fold
        wire [15:0] terms;
        for (byte_index=0; byte_index<16; byte_index=byte_index+1) begin : lane
            assign terms[byte_index] = packed_data[byte_index*8+bit_index];
        end
        assign folded[bit_index] = ^terms;
    end endgenerate
    always @(posedge clk) begin
        stimulus <= {rst_n,abort,valid,last,ready,data};
        observe <= {idle,frame_error|overflow,in_ready,out_valid,out_last,keep,folded};
    end
    jpeg_byte_packer dut (
        .i_clk(clk), .i_rst_n(stimulus[12]), .i_abort(stimulus[11]),
        .i_valid(stimulus[10]), .i_last(stimulus[9]), .i_axis_tready(stimulus[8]), .i_byte(stimulus[7:0]),
        .o_ready(in_ready), .o_axis_tdata(packed_data), .o_axis_tkeep(keep), .o_axis_tvalid(out_valid),
        .o_axis_tlast(out_last), .o_frame_error(frame_error), .o_overflow(overflow), .o_idle(idle)
    );
endmodule
