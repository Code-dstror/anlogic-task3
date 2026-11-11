// 提供四十位宽的 ISP 行缓存读写接口
module isp_line_ram_40x1024 (
    // 时钟与复位
    input clk,
    // 写入接口
    input wr_en,
    input [9:0] wr_addr,
    input [39:0] wr_data,
    // 读出接口
    input rd_en,
    input [9:0] rd_addr,
    output [39:0] rd_data
);
    // 按低二十位和高二十位并行读写两块物理存储器
    isp_line_ram_20x1024 u_low (
        .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data[19:0]),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data[19:0])
    );
    isp_line_ram_20x1024 u_high (
        .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data[39:20]),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data[39:20])
    );
endmodule

// Native4 storage keeps all RAW14 bits for the shared SDR/HDR ISP path.
module isp_line_ram_native4 #(
    parameter integer SAMPLE_BITS = 10
) (
    input wire clk,
    input wire wr_en,
    input wire [9:0] wr_addr,
    input wire [4*SAMPLE_BITS-1:0] wr_data,
    input wire rd_en,
    input wire [9:0] rd_addr,
    output wire [4*SAMPLE_BITS-1:0] rd_data
);
    localparam integer WORDS = (4*SAMPLE_BITS + 19) / 20;
    wire [WORDS*20-1:0] write_padded = {{(WORDS*20-4*SAMPLE_BITS){1'b0}},wr_data};
    wire [WORDS*20-1:0] read_padded;
    genvar n;
    generate for (n=0; n<WORDS; n=n+1) begin : word
        isp_line_ram_20x1024 u_word (
            .clk(clk), .wr_en(wr_en), .wr_addr(wr_addr),
            .wr_data(write_padded[n*20 +: 20]), .rd_en(rd_en),
            .rd_addr(rd_addr), .rd_data(read_padded[n*20 +: 20]));
    end endgenerate
    assign rd_data = read_padded[4*SAMPLE_BITS-1:0];
endmodule

// 使用 TD 生成的双端口存储器实现二十位宽行缓存
module isp_line_ram_20x1024 (
    // 时钟与复位
    input clk,
    // 写入接口
    input wr_en,
    input [9:0] wr_addr,
    input [19:0] wr_data,
    // 读出接口
    input rd_en,
    input [9:0] rd_addr,
    output [19:0] rd_data
);
    // A 端口写入行数据，B 端口按读使能输出数据
    isp_line_ram_20x1024_ip u_memory (
        .doa(), .dia(wr_data), .addra(wr_addr),
        .cea(1'b1), .clka(clk), .wea(wr_en),
        .dob(rd_data), .dib(20'd0), .addrb(rd_addr),
        .ceb(rd_en), .web(1'b0)
    );
endmodule
