// Gamma 2.2 lookup backed by the PH1 embedded-memory primitive.
module gamma_lut_10to8 #(
    parameter C_GAMMA_LINEAR_BYPASS = 1'b0,
    parameter C_INIT_FILE = "gamma22_10to8.dath"
) (
    input        i_clk,
    input        i_rstn,
    input  [9:0] i_index,
    output [7:0] o_value
);
    wire [7:0] gamma_value;
    reg  [7:0] linear_value;
    wire [7:0] unused_data_a;
    wire       unused_single_error;
    wire       unused_double_error;

    PH1_LOGIC_ERAM #(
        .DATA_WIDTH_A(8), .DATA_WIDTH_B(8),
        .ADDR_WIDTH_A(10), .ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024), .DATA_DEPTH_B(1024),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1), .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"), .WRITEMODE_B("NORMAL"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"), .SSROVERCE("ENABLE"),
        .ECC_DECODE("DISABLE"), .ECC_ENCODE("DISABLE"),
        .ASYNC_RESET_RELEASE_A("SYNC"), .ASYNC_RESET_RELEASE_B("SYNC"),
        .CLKMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE(C_INIT_FILE), .FILL_ALL("NONE"),
        .IMPLEMENT("20K")
    ) u_gamma_memory (
        .ecc_sbiterr(unused_single_error), .ecc_dbiterr(unused_double_error),
        .doa(unused_data_a), .dob(gamma_value), .dia(8'd0), .dib(8'd0),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .cea(1'b0), .ocea(1'b1), .clka(i_clk), .wea(1'b0), .rsta(~i_rstn),
        .ceb(1'b1), .oceb(1'b1), .clkb(i_clk), .web(1'b0), .rstb(~i_rstn),
        .bea(1'b1), .beb(1'b1), .addra(10'd0), .addrb(i_index)
    );

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn)
            linear_value <= 8'd0;
        else
            linear_value <= i_index[9:2];
    end

    assign o_value = C_GAMMA_LINEAR_BYPASS ? linear_value : gamma_value;
endmodule
