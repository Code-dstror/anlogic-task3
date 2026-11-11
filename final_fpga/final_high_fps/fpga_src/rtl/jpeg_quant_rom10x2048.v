`timescale 1ns/1ps
// Port-only adapter for fixed, GUI-manageable TD RAM configurations.
module jpeg_quant_rom10x2048 #(
    parameter integer LANE = 0
) (
    input wire i_clk,i_read_enable,
    input wire [10:0] i_address,
    output wire [9:0] o_data,
    input wire i_table_enable,
    input wire [10:0] i_table_address,
    output wire [9:0] o_table_data
);
    generate
        if (LANE == 0) begin : g_lane0
            jpeg_rom_q_lane0 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 1) begin : g_lane1
            jpeg_rom_q_lane1 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 2) begin : g_lane2
            jpeg_rom_q_lane2 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 3) begin : g_lane3
            jpeg_rom_q_lane3 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 4) begin : g_lane4
            jpeg_rom_q_lane4 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 5) begin : g_lane5
            jpeg_rom_q_lane5 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 6) begin : g_lane6
            jpeg_rom_q_lane6 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else if (LANE == 7) begin : g_lane7
            jpeg_rom_q_lane7 u_rom (
                .clka(i_clk),.cea(i_read_enable),.addra(i_address),.doa(o_data),
                .dia(10'd0),.wea(1'b0),.ceb(i_table_enable),
                .addrb(i_table_address),.dob(o_table_data),.dib(10'd0),.web(1'b0));
        end
        else begin : g_unsupported_lane
            JPEG_QUANT_ROM_LANE_MUST_BE_0_TO_7 invalid_configuration ();
        end
    endgenerate
endmodule
