`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlogic 2026 FPGA Team
// Engineer:        Codex
// Create Date:     2026/09/14
// Design Name:     pcie_app_regs
// Module Name:     pcie_app_regs
// Description:     AXI4-Lite application register bank for the PCIe user BAR.
// Dependencies:    pcie_protocol_v1.vh
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路2026 FPGA参赛团队
// 开发人员:        Codex
// 创建日期:        2026年09月14日
// 设计名称:        pcie_app_regs
// 模块名称:        pcie_app_regs
// 模块说明:        PCIe用户BAR的AXI4-Lite应用寄存器组。
// 依赖文件:        pcie_protocol_v1.vh

`include "pcie_protocol_v1.vh"
`include "c2h_test_fixture.vh"

module pcie_app_regs (
    input  wire        i_clk,
    input  wire        i_rst_n,

    input  wire [31:0] i_axil_awaddr,
    input  wire [2:0]  i_axil_awprot,
    input  wire        i_axil_awvalid,
    output wire        o_axil_awready,
    input  wire [31:0] i_axil_wdata,
    input  wire [3:0]  i_axil_wstrb,
    input  wire        i_axil_wvalid,
    output wire        o_axil_wready,
    output wire [1:0]  o_axil_bresp,
    output wire        o_axil_bvalid,
    input  wire        i_axil_bready,
    input  wire [31:0] i_axil_araddr,
    input  wire [2:0]  i_axil_arprot,
    input  wire        i_axil_arvalid,
    output wire        o_axil_arready,
    output wire [31:0] o_axil_rdata,
    output wire [1:0]  o_axil_rresp,
    output wire        o_axil_rvalid,
    input  wire        i_axil_rready,

    input  wire [31:0] i_status,
    input  wire [31:0] i_ready_mask,
    input  wire [31:0] i_sending_mask,
    input  wire [31:0] i_producer_sequence,
    input  wire [31:0] i_consumed_sequence,
    input  wire [31:0] i_drop_count,
    input  wire [31:0] i_overflow_count,
    input  wire [31:0] i_dma_error_count,
    input  wire [31:0] i_last_error,
    input  wire [31:0] i_h2c_byte_count,
    input  wire [31:0] i_h2c_frame_count,
    input  wire [31:0] i_h2c_error_count,
    input  wire [31:0] i_h2c_first_error,

    output wire        o_app_enable,
    output wire        o_soft_reset,
    output wire [31:0] o_test_length,
    output wire [1:0]  o_test_pattern,
    output wire        o_test_trigger
);

    localparam [31:0] USER_BAR_BASE = `PCIE_USER_BAR_BASE;

    reg aw_pending;
    reg w_pending;
    reg [31:0] awaddr_hold;
    reg [31:0] wdata_hold;
    reg [3:0] wstrb_hold;
    reg [1:0] axil_bresp_o;
    reg axil_bvalid_o;
    reg [31:0] axil_rdata_o;
    reg [1:0] axil_rresp_o;
    reg axil_rvalid_o;
    reg app_enable_o;
    reg soft_reset_o;
    reg [31:0] test_length_o;
    reg [1:0] test_pattern_o;
    reg test_trigger_o;
    reg [31:0] merged_write_data;

    wire aw_fire;
    wire w_fire;
    wire ar_fire;
    wire write_commit;
    wire write_in_user_window;
    wire read_in_user_window;
    wire [11:0] write_offset;
    wire [11:0] read_offset;

    function [31:0] merge_write_strobes;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_strobes;
        integer merge_lane;
        begin
            merge_write_strobes = old_value;
            for (merge_lane = 0; merge_lane < 4; merge_lane = merge_lane + 1) begin
                if (byte_strobes[merge_lane]) begin
                    merge_write_strobes[(merge_lane * 8) +: 8] =
                        new_value[(merge_lane * 8) +: 8];
                end
            end
        end
    endfunction

    assign o_axil_awready = !aw_pending && !axil_bvalid_o;
    assign o_axil_wready = !w_pending && !axil_bvalid_o;
    assign o_axil_arready = !axil_rvalid_o;
    assign aw_fire = i_axil_awvalid && o_axil_awready;
    assign w_fire = i_axil_wvalid && o_axil_wready;
    assign ar_fire = i_axil_arvalid && o_axil_arready;
    assign write_commit = aw_pending && w_pending && !axil_bvalid_o;
    assign write_in_user_window = awaddr_hold[31:12] == USER_BAR_BASE[31:12];
    assign read_in_user_window = i_axil_araddr[31:12] == USER_BAR_BASE[31:12];
    assign write_offset = awaddr_hold[11:0];
    assign read_offset = i_axil_araddr[11:0];

    assign o_axil_bresp = axil_bresp_o;
    assign o_axil_bvalid = axil_bvalid_o;
    assign o_axil_rdata = axil_rdata_o;
    assign o_axil_rresp = axil_rresp_o;
    assign o_axil_rvalid = axil_rvalid_o;
    assign o_app_enable = app_enable_o;
    assign o_soft_reset = soft_reset_o;
    assign o_test_length = test_length_o;
    assign o_test_pattern = test_pattern_o;
    assign o_test_trigger = test_trigger_o;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            awaddr_hold <= 32'd0;
            wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0;
            axil_bresp_o <= 2'b00;
            axil_bvalid_o <= 1'b0;
            app_enable_o <= 1'b0;
            soft_reset_o <= 1'b0;
            test_length_o <= `C2H_TEST_JPEG_FIXTURE_LENGTH;
            test_pattern_o <= `C2H_TEST_PATTERN_JPEG_FIXTURE;
            test_trigger_o <= 1'b0;
            merged_write_data <= 32'd0;
        end else begin
            soft_reset_o <= 1'b0;
            test_trigger_o <= 1'b0;

            if (aw_fire) begin
                aw_pending <= 1'b1;
                awaddr_hold <= i_axil_awaddr;
            end
            if (w_fire) begin
                w_pending <= 1'b1;
                wdata_hold <= i_axil_wdata;
                wstrb_hold <= i_axil_wstrb;
            end

            if (axil_bvalid_o && i_axil_bready) begin
                axil_bvalid_o <= 1'b0;
            end

            if (write_commit) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                axil_bvalid_o <= 1'b1;
                axil_bresp_o <= 2'b10;
                if (write_in_user_window && (write_offset[1:0] == 2'b00)) begin
                    case (write_offset)
                        `PCIE_REG_CONTROL: begin
                            merged_write_data = merge_write_strobes(
                                {30'd0, 1'b0, app_enable_o}, wdata_hold, wstrb_hold);
                            app_enable_o <= merged_write_data[0];
                            soft_reset_o <= merged_write_data[1];
                            axil_bresp_o <= 2'b00;
                        end
                        `PCIE_REG_TEST_LENGTH: begin
                            test_length_o <= merge_write_strobes(
                                test_length_o, wdata_hold, wstrb_hold);
                            axil_bresp_o <= 2'b00;
                        end
                        `PCIE_REG_TEST_PATTERN: begin
                            merged_write_data = merge_write_strobes(
                                {30'd0, test_pattern_o}, wdata_hold, wstrb_hold);
                            test_pattern_o <= merged_write_data[1:0];
                            axil_bresp_o <= 2'b00;
                        end
                        `PCIE_REG_TEST_TRIGGER: begin
                            test_trigger_o <= wstrb_hold[0] && wdata_hold[0];
                            axil_bresp_o <= 2'b00;
                        end
                        default: axil_bresp_o <= 2'b10;
                    endcase
                end
            end
        end
    end

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            axil_rdata_o <= 32'd0;
            axil_rresp_o <= 2'b00;
            axil_rvalid_o <= 1'b0;
        end else begin
            if (axil_rvalid_o && i_axil_rready) begin
                axil_rvalid_o <= 1'b0;
            end
            if (ar_fire) begin
                axil_rvalid_o <= 1'b1;
                axil_rdata_o <= 32'd0;
                axil_rresp_o <= 2'b10;
                if (read_in_user_window && (read_offset[1:0] == 2'b00)) begin
                    case (read_offset)
                        `PCIE_REG_DEVICE_MAGIC: begin
                            axil_rdata_o <= `PCIE_DEVICE_MAGIC;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_PROTOCOL_VERSION: begin
                            axil_rdata_o <= {16'd0, `PCIE_PROTOCOL_VERSION};
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_CAPABILITIES: begin
                            axil_rdata_o <= 32'h0000_002f;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_SLOT_COUNT: begin
                            axil_rdata_o <= `PCIE_SLOT_COUNT;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_MAX_PAYLOAD: begin
                            axil_rdata_o <= `PCIE_MAX_PAYLOAD;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_HEADER_LENGTH: begin
                            axil_rdata_o <= `PCIE_HEADER_LENGTH;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_CONTROL: begin
                            axil_rdata_o <= {31'd0, app_enable_o};
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_STATUS: begin
                            axil_rdata_o <= i_status;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_READY_MASK: begin
                            axil_rdata_o <= i_ready_mask;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_SENDING_MASK: begin
                            axil_rdata_o <= i_sending_mask;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_PRODUCER_SEQUENCE: begin
                            axil_rdata_o <= i_producer_sequence;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_CONSUMED_SEQUENCE: begin
                            axil_rdata_o <= i_consumed_sequence;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_DROP_COUNT: begin
                            axil_rdata_o <= i_drop_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_OVERFLOW_COUNT: begin
                            axil_rdata_o <= i_overflow_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_DMA_ERROR_COUNT: begin
                            axil_rdata_o <= i_dma_error_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_LAST_ERROR: begin
                            axil_rdata_o <= i_last_error;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_TEST_LENGTH: begin
                            axil_rdata_o <= test_length_o;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_TEST_PATTERN: begin
                            axil_rdata_o <= {30'd0, test_pattern_o};
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_H2C_BYTE_COUNT: begin
                            axil_rdata_o <= i_h2c_byte_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_H2C_FRAME_COUNT: begin
                            axil_rdata_o <= i_h2c_frame_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_H2C_ERROR_COUNT: begin
                            axil_rdata_o <= i_h2c_error_count;
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_H2C_FIRST_ERROR: begin
                            axil_rdata_o <= i_h2c_first_error;
                            axil_rresp_o <= 2'b00;
                        end
                        default: begin
                            axil_rdata_o <= 32'd0;
                            axil_rresp_o <= 2'b10;
                        end
                    endcase
                end
            end
        end
    end

    wire unused_axil_prot;
    assign unused_axil_prot = ^i_axil_awprot ^ ^i_axil_arprot;

endmodule
