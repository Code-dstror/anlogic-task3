module isp_line_ram_40x1024 (
    input clk, input wr_en, input [9:0] wr_addr, input [39:0] wr_data,
    input rd_en, input [9:0] rd_addr, output [39:0] rd_data
);
    isp_line_ram_20x1024 u_low (
        .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data[19:0]),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data[19:0])
    );
    isp_line_ram_20x1024 u_high (
        .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data[39:20]),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data[39:20])
    );
endmodule

module isp_line_ram_20x1024 (
    input clk, input wr_en, input [9:0] wr_addr, input [19:0] wr_data,
    input rd_en, input [9:0] rd_addr, output [19:0] rd_data
);
    PH1_LOGIC_ERAM #(
        .DATA_WIDTH_A(20), .DATA_WIDTH_B(20),
        .ADDR_WIDTH_A(10), .ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024), .DATA_DEPTH_B(1024),
        .BYTE_ENABLE(0), .BYTE_A(1), .BYTE_B(1), .MODE("DP"),
        .REGMODE_A("NOREG"), .REGMODE_B("NOREG"),
        .WRITEMODE_A("WRITETHROUGH"), .WRITEMODE_B("READBEFOREWRITE"),
        .RESETMODE_A("ASYNC"), .RESETMODE_B("ASYNC"),
        .OREGSET_A("RESET"), .OREGSET_B("RESET"), .SSROVERCE("ENABLE"),
        .ECC_DECODE("DISABLE"), .ECC_ENCODE("DISABLE"),
        .ASYNC_RESET_RELEASE_A("SYNC"), .ASYNC_RESET_RELEASE_B("SYNC"),
        .CLKMODE("SYNC"), .DEBUGGABLE("NO"), .PACKABLE("NO"),
        .FORCE_KEEP("OFF"), .INIT_FILE("NONE"), .FILL_ALL("NONE"),
        .IMPLEMENT("20K")
    ) u_memory (
        .doa(), .dob(rd_data), .dia(wr_data), .dib(20'd0),
        .ecc_sbiterrinj(1'b0), .ecc_dbiterrinj(1'b0),
        .cea(1'b1), .ocea(1'b1), .clka(clk), .wea(wr_en), .rsta(1'b0),
        .ceb(rd_en), .oceb(1'b1), .clkb(clk), .web(1'b0), .rstb(1'b0),
        .bea(1'b1), .beb(1'b1), .addra(wr_addr), .addrb(rd_addr),
        .ecc_sbiterr(), .ecc_dbiterr()
    );
endmodule
