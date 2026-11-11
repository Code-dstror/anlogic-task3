`timescale 1ns/1ps
// Shared, cycle-free byte alignment after selecting the Y/Cb/Cr RAM words.
module jpeg_mcu_read_align8 (
    input wire [119:0] i_bank_words,
    input wire [14:0] i_byte_select,
    output reg [63:0] o_data
);
    wire [63:0] windows [0:14];
    genvar window_index,byte_index;
    generate for(window_index=0;window_index<15;window_index=window_index+1)begin:g_window
        for(byte_index=0;byte_index<8;byte_index=byte_index+1)begin:g_byte
            assign windows[window_index][byte_index*8+:8]=
                i_bank_words[((window_index+byte_index)%15)*8+:8];
        end
    end endgenerate
    integer n;
    always @* begin
        o_data=0;
        for(n=0;n<15;n=n+1)
            o_data=o_data | (windows[n] & {64{i_byte_select[n]}});
    end
endmodule
