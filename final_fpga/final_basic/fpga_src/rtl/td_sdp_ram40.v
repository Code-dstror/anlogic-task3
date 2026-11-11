`timescale 1ns / 1ps

// One official PH1 ERAM20K in 40-bit simple-dual-port mode, without inferred RAM.
module td_sdp_ram40 #(
    parameter integer WIDTH = 40,
    parameter integer DEPTH = 512,
    parameter integer ADDR_WIDTH = 9
) (
    input wire clk,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [WIDTH-1:0] wr_data,
    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [WIDTH-1:0] rd_data
);
    wire [39:0] write_word;
    wire [39:0] read_word;
    wire [8:0] write_address;
    wire [8:0] read_address;
    assign write_word = {{(40-WIDTH){1'b0}}, wr_data};
    assign write_address = {{(9-ADDR_WIDTH){1'b0}}, wr_addr};
    assign read_address = {{(9-ADDR_WIDTH){1'b0}}, rd_addr};
    assign rd_data = read_word[WIDTH-1:0];

    // All physical parameters belong to the official GUI-manageable IPC.
    // This adapter only pads logical ports and qualifies their CE.
    ram40_sdp_fixed u_configured_ip (
        .dia(write_word),
        .addra(write_address), .addrb(read_address),
        .cea(wr_en && wr_addr < DEPTH), .ceb(rd_en && rd_addr < DEPTH),
        .clka(clk), .dob(read_word)
    );

    generate if (WIDTH < 1 || WIDTH > 40 || DEPTH < 1 || DEPTH > 512 ||
        ADDR_WIDTH < 1 || ADDR_WIDTH > 9 || DEPTH > (1 << ADDR_WIDTH)) begin : invalid_logical_shape
        TD_RAM40_REQUIRES_WIDTH1_TO40_DEPTH1_TO512_AND_FITTING_ADDRESS invalid_configuration();
    end endgenerate
endmodule
