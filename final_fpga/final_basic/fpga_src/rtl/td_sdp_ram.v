`timescale 1ns / 1ps

// Bank the registered TD simple dual-port ERAM without inferring storage.
module td_sdp_ram #(
    parameter integer WIDTH = 20,
    parameter integer DEPTH = 1024,
    parameter integer ADDR_WIDTH = 10,
    parameter integer DISTRIBUTED_ENABLE = 0,
    parameter integer REGISTER_INPUTS = 0
) (
    input wire clk,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [WIDTH-1:0] wr_data,
    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [WIDTH-1:0] rd_data
);
    wire memory_write_enable;
    wire [ADDR_WIDTH-1:0] memory_write_address;
    wire [WIDTH-1:0] memory_write_data;
    wire memory_read_enable;
    wire [ADDR_WIDTH-1:0] memory_read_address;
    generate if (REGISTER_INPUTS) begin : g_registered_inputs
        reg write_enable;
        reg [ADDR_WIDTH-1:0] write_address;
        reg [WIDTH-1:0] write_data;
        reg read_enable;
        reg [ADDR_WIDTH-1:0] read_address;
        always @(posedge clk) begin
            write_enable <= wr_en;
            read_enable <= rd_en;
            if (wr_en) begin
                write_address <= wr_addr;
                write_data <= wr_data;
            end
            if (rd_en) read_address <= rd_addr;
        end
        assign memory_write_enable = write_enable;
        assign memory_write_address = write_address;
        assign memory_write_data = write_data;
        assign memory_read_enable = read_enable;
        assign memory_read_address = read_address;
    end else begin : g_direct_inputs
        assign memory_write_enable = wr_en;
        assign memory_write_address = wr_addr;
        assign memory_write_data = wr_data;
        assign memory_read_enable = rd_en;
        assign memory_read_address = rd_addr;
    end endgenerate
    generate if (DISTRIBUTED_ENABLE) begin : g_distributed
        // This exact tiny shape is the two-bank JPEG transpose/reorder store.
        // The official read register owns synchronous latency and CE hold;
        // no memory contents or output register are reset by this adapter.
        if (WIDTH != 16 || DEPTH != 16 || ADDR_WIDTH != 4) begin : g_bad_shape
            TD_DISTRIBUTED_RAM_REQUIRES_16X16 invalid_configuration();
        end
        PH1_LOGIC_DRAM #(
            .DATA_WIDTH_W(16),.ADDR_WIDTH_W(4),.DATA_DEPTH_W(16),
            .DATA_WIDTH_R(16),.ADDR_WIDTH_R(4),.DATA_DEPTH_R(16),
            .INIT_FILE("NONE"),.FILL_ALL("NONE"),
            .READREG("ENABLE"),.RESETMODE("SYNC")
        ) u_dram (
            .di(memory_write_data),.waddr(memory_write_address),.we(memory_write_enable),.wclk(clk),
            .raddr(memory_read_address),.rdo(),.rdoq(rd_data),
            .rclk(clk),.rrst(1'b0),.rce(memory_read_enable)
        );
    end else begin : g_eram
    localparam integer BANKS = (DEPTH + 1023) / 1024;
    wire [BANKS*WIDTH-1:0] bank_data;
    reg [ADDR_WIDTH-1:0] read_address;
    // There is no RAM reset. Only valid data and the requesting control own it.
    always @(posedge clk) begin
        if (memory_read_enable) read_address <= memory_read_address;
    end
    genvar b;
    for (b=0; b<BANKS; b=b+1) begin : bank
        wire [19:0] read_word;
        wire [9:0] write_low = memory_write_address;
        wire [9:0] read_low = memory_read_address;
        isp_line_ram_20x1024_ip u_eram (
            .doa(), .dia({{(20-WIDTH){1'b0}},memory_write_data}), .addra(write_low),
            .cea(1'b1), .clka(clk),
            .wea(memory_write_enable && memory_write_address < DEPTH && (memory_write_address >> 10) == b),
            .dob(read_word), .dib(20'd0), .addrb(read_low),
            .ceb(memory_read_enable && memory_read_address < DEPTH && (memory_read_address >> 10) == b),
            .web(1'b0)
        );
        assign bank_data[b*WIDTH +: WIDTH] = read_word[WIDTH-1:0];
    end
    assign rd_data = bank_data[(read_address >> 10)*WIDTH +: WIDTH];
    end endgenerate
endmodule
