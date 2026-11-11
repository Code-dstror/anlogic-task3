`timescale 1ns / 1ps
`include "pcie_protocol_v1.vh"
`include "raw_video_v1.vh"
`include "c2h_test_fixture.vh"

// 实现PCIe应用状态与控制的AXI寄存器
module mono_pcie_app_regs_v2 #(
    parameter integer RAW_ENABLE = 0,
    parameter integer CONFIG_ENABLE = 0,
    parameter integer JPEG_RING_ENABLE = 0,
    parameter integer RECORD_ENABLE = 0,
    parameter integer CONFIG_EXT_ENABLE=0,
    parameter integer MONO_SCHEMA2_ENABLE=0,
    parameter integer ALGO_ENABLE=0,
    parameter integer STEREO_ENABLE=0
) (
    // 时钟与复位
    input  wire i_clk,
    input  wire i_rst_n,

    // AXI写地址
    input  wire [31:0] i_axil_awaddr,
    input  wire [2:0] i_axil_awprot,
    input  wire i_axil_awvalid,
    output wire o_axil_awready,

    // AXI写数据
    input  wire [31:0] i_axil_wdata,
    input  wire [3:0] i_axil_wstrb,
    input  wire i_axil_wvalid,
    output wire o_axil_wready,

    // AXI写响应
    output wire [1:0] o_axil_bresp,
    output wire o_axil_bvalid,
    input  wire i_axil_bready,

    // AXI读地址
    input  wire [31:0] i_axil_araddr,
    input  wire [2:0] i_axil_arprot,
    input  wire i_axil_arvalid,
    output wire o_axil_arready,

    // AXI读响应
    output wire [31:0] o_axil_rdata,
    output wire [1:0] o_axil_rresp,
    output wire o_axil_rvalid,
    input  wire i_axil_rready,

    // 应用状态输入
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

    // 应用控制输出
    output wire o_app_enable,
    output wire o_soft_reset,
    output wire [31:0] o_test_length,
    output wire [1:0] o_test_pattern,
    output wire o_test_trigger,

    // Optional S04 extension. Legacy instances leave RAW_ENABLE at zero.
    output wire o_raw_write_valid, output wire [11:0] o_raw_write_offset,
    output wire [31:0] o_raw_write_data, output wire [3:0] o_raw_write_strobes,
    input wire [1:0] i_raw_write_response,
    output wire o_raw_read_valid, output wire [11:0] o_raw_read_offset,
    input wire i_raw_read_response_valid, input wire [31:0] i_raw_read_data,
    input wire [1:0] i_raw_read_response,
    output wire o_cfg_write_valid, output wire [11:0] o_cfg_write_offset,
    output wire [31:0] o_cfg_write_data, output wire [3:0] o_cfg_write_strobes,
    input wire [1:0] i_cfg_write_response,
    output wire o_cfg_read_valid, output wire [11:0] o_cfg_read_offset,
    input wire i_cfg_read_response_valid, input wire [31:0] i_cfg_read_data,
    input wire [1:0] i_cfg_read_response,
    output wire o_jpeg_write_valid, output wire [11:0] o_jpeg_write_offset,
    output wire [31:0] o_jpeg_write_data, output wire [3:0] o_jpeg_write_strobes,
    input wire [1:0] i_jpeg_write_response,
    output wire o_jpeg_read_valid, output wire [11:0] o_jpeg_read_offset,
    input wire i_jpeg_read_response_valid, input wire [31:0] i_jpeg_read_data,
    input wire [1:0] i_jpeg_read_response,
    output wire o_record_write_valid, output wire [11:0] o_record_write_offset,
    output wire [31:0] o_record_write_data, output wire [3:0] o_record_write_strobes,
    input wire [1:0] i_record_write_response,
    output wire o_record_read_valid, output wire [11:0] o_record_read_offset,
    input wire i_record_read_response_valid, input wire [31:0] i_record_read_data,
    input wire [1:0] i_record_read_response,
    output wire o_algo_write_valid, output wire [11:0] o_algo_write_offset,
    output wire [31:0] o_algo_write_data, output wire [3:0] o_algo_write_strobes,
    input wire [1:0] i_algo_write_response,
    output wire o_algo_read_valid, output wire [11:0] o_algo_read_offset,
    input wire i_algo_read_response_valid, input wire [31:0] i_algo_read_data,
    input wire [1:0] i_algo_read_response,
    input wire i_stereo_start_inhibit,
    output wire o_stereo_write_valid,output wire [11:0] o_stereo_write_offset,
    output wire [31:0] o_stereo_write_data,output wire [3:0] o_stereo_write_strobes,
    input wire [1:0] i_stereo_write_response,
    output wire o_stereo_read_valid,output wire [11:0] o_stereo_read_offset,
    input wire i_stereo_read_response_valid,input wire [31:0] i_stereo_read_data,
    input wire [1:0] i_stereo_read_response
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
    reg raw_read_pending;
    reg cfg_read_pending;
    reg jpeg_read_pending;
    reg record_read_pending;
    reg algo_read_pending;
    reg stereo_read_pending;
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

    // 写地址缓存可用时接受新写事务
    assign o_axil_awready = !aw_pending && !axil_bvalid_o;
    assign o_axil_wready = !w_pending && !axil_bvalid_o;
    assign o_axil_arready = !axil_rvalid_o && !raw_read_pending && !cfg_read_pending &&
        !jpeg_read_pending && !record_read_pending && !algo_read_pending && !stereo_read_pending;
    assign aw_fire = i_axil_awvalid && o_axil_awready;
    assign w_fire = i_axil_wvalid && o_axil_wready;
    assign ar_fire = i_axil_arvalid && o_axil_arready;
    assign write_commit = aw_pending && w_pending && !axil_bvalid_o;
    // The native request bridge has qualified the endpoint's 1 MiB BAR0.
    // The AXI address can still contain the host-assigned base in [31:20].
    // Decode only the +0x80000 page within that BAR, not the host BAR base.
    assign write_in_user_window = awaddr_hold[19:12] == USER_BAR_BASE[19:12];
    assign read_in_user_window = i_axil_araddr[19:12] == USER_BAR_BASE[19:12];
    assign write_offset = awaddr_hold[11:0];
    assign read_offset = i_axil_araddr[11:0];
    wire raw_write_window = (write_offset >= 12'h100 && write_offset < 12'h200) ||
                            (write_offset >= 12'h400 && write_offset < 12'he00);
    wire raw_read_window = (read_offset >= 12'h100 && read_offset < 12'h200) ||
                           (read_offset >= 12'h400 && read_offset < 12'he00);
    assign o_raw_write_valid = RAW_ENABLE != 0 && write_commit && write_in_user_window &&
                               write_offset[1:0] == 0 && raw_write_window;
    assign o_raw_write_offset = write_offset;
    assign o_raw_write_data = wdata_hold;
    assign o_raw_write_strobes = wstrb_hold;
    assign o_raw_read_valid = RAW_ENABLE != 0 && ar_fire && read_in_user_window &&
                              read_offset[1:0] == 0 && raw_read_window;
    assign o_raw_read_offset = read_offset;
    // When enabled, the additive format service owns the upper CFG page.
    // Legacy instances preserve the original 0x200..0x2ff decode.
    wire ext_write_window=CONFIG_EXT_ENABLE!=0&&CONFIG_ENABLE!=0&&
        ((write_offset>=`PCIE_REG_CFG_EXT_MAGIC&&write_offset<=`PCIE_REG_CFG_EXT_COMBINATIONS)||
         (write_offset>=`PCIE_REG_CFG_EXT_SHADOW_BASE&&write_offset<`PCIE_REG_CFG_EXT_ACTIVE_BASE+128));
    wire ext_read_window=CONFIG_EXT_ENABLE!=0&&CONFIG_ENABLE!=0&&
        ((read_offset>=`PCIE_REG_CFG_EXT_MAGIC&&read_offset<=`PCIE_REG_CFG_EXT_COMBINATIONS)||
         (MONO_SCHEMA2_ENABLE!=0&&read_offset>=`PCIE_REG_CFG_EXT_SCHEMAS&&read_offset<=`PCIE_REG_CFG_EXT_V2_ENABLES)||
         (read_offset>=`PCIE_REG_CFG_EXT_SHADOW_BASE&&read_offset<`PCIE_REG_CFG_EXT_ACTIVE_BASE+128));
    wire cfg_write_window = (write_offset >= 12'h200 &&
        write_offset < (RECORD_ENABLE != 0 ? 12'h280 : 12'h300))||ext_write_window;
    wire cfg_read_window = (read_offset >= 12'h200 &&
        read_offset < (RECORD_ENABLE != 0 ? 12'h280 : 12'h300))||ext_read_window;
    wire record_write_window = write_offset >= 12'h280 && write_offset < 12'h300;
    wire record_read_window = read_offset >= 12'h280 && read_offset < 12'h300;
    assign o_record_write_valid = RECORD_ENABLE != 0 && write_commit && write_in_user_window &&
        write_offset[1:0] == 0 && record_write_window;
    assign o_record_write_offset = write_offset;
    assign o_record_write_data = wdata_hold;
    assign o_record_write_strobes = wstrb_hold;
    assign o_record_read_valid = RECORD_ENABLE != 0 && ar_fire && read_in_user_window &&
        read_offset[1:0] == 0 && record_read_window;
    assign o_record_read_offset = read_offset;
    assign o_cfg_write_valid = CONFIG_ENABLE != 0 && write_commit && write_in_user_window &&
                               write_offset[1:0] == 0 && cfg_write_window;
    assign o_cfg_write_offset = write_offset;
    assign o_cfg_write_data = wdata_hold;
    assign o_cfg_write_strobes = wstrb_hold;
    assign o_cfg_read_valid = CONFIG_ENABLE != 0 && ar_fire && read_in_user_window &&
                              read_offset[1:0] == 0 && cfg_read_window;
    assign o_cfg_read_offset = read_offset;
    wire jpeg_write_window=write_offset>=12'h300 && write_offset<12'h400&&!ext_write_window;
    wire jpeg_read_window=read_offset>=12'h300 && read_offset<12'h400&&!ext_read_window;
    assign o_jpeg_write_valid=JPEG_RING_ENABLE!=0 && write_commit && write_in_user_window &&
        write_offset[1:0]==0 && jpeg_write_window;
    assign o_jpeg_write_offset=write_offset;assign o_jpeg_write_data=wdata_hold;
    assign o_jpeg_write_strobes=wstrb_hold;
    assign o_jpeg_read_valid=JPEG_RING_ENABLE!=0 && ar_fire && read_in_user_window &&
        read_offset[1:0]==0 && jpeg_read_window;
    assign o_jpeg_read_offset=read_offset;
    wire algo_write_window=write_offset>=`PCIE_REG_ALGO_MAGIC&&write_offset<=`PCIE_REG_ALGO_ACTIVE_GENERATION;
    wire algo_read_window=read_offset>=`PCIE_REG_ALGO_MAGIC&&read_offset<=`PCIE_REG_ALGO_ACTIVE_GENERATION;
    assign o_algo_write_valid=ALGO_ENABLE!=0&&write_commit&&write_in_user_window&&
        write_offset[1:0]==0&&algo_write_window;
    assign o_algo_write_offset=write_offset;assign o_algo_write_data=wdata_hold;
    assign o_algo_write_strobes=wstrb_hold;
    assign o_algo_read_valid=ALGO_ENABLE!=0&&ar_fire&&read_in_user_window&&
        read_offset[1:0]==0&&algo_read_window;
    assign o_algo_read_offset=read_offset;

    assign o_axil_bresp = axil_bresp_o;
    assign o_axil_bvalid = axil_bvalid_o;
    assign o_axil_rdata = axil_rdata_o;
    assign o_axil_rresp = axil_rresp_o;
    assign o_axil_rvalid = axil_rvalid_o;
    wire stereo_write_window=write_offset>=`PCIE_REG_STEREO_MAGIC&&write_offset<=`PCIE_RAW_VIDEO_ACTIVE_PRODUCT;
    wire stereo_read_window=read_offset>=`PCIE_REG_STEREO_MAGIC&&read_offset<=`PCIE_RAW_VIDEO_ACTIVE_PRODUCT;
    assign o_stereo_write_valid=STEREO_ENABLE!=0&&write_commit&&write_in_user_window&&write_offset[1:0]==0&&stereo_write_window;
    assign o_stereo_write_offset=write_offset;assign o_stereo_write_data=wdata_hold;assign o_stereo_write_strobes=wstrb_hold;
    assign o_stereo_read_valid=STEREO_ENABLE!=0&&ar_fire&&read_in_user_window&&read_offset[1:0]==0&&stereo_read_window;
    assign o_stereo_read_offset=read_offset;
    assign o_app_enable = app_enable_o;
    assign o_soft_reset = soft_reset_o;
    assign o_test_length = test_length_o;
    assign o_test_pattern = test_pattern_o;
    assign o_test_trigger = test_trigger_o;

    // 在写地址数据握手后更新应用控制寄存器
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
                            if(STEREO_ENABLE!=0&&i_stereo_start_inhibit&&merged_write_data[0])
                                axil_bresp_o<=2'b10;
                            else begin
                                app_enable_o <= merged_write_data[0];
                                soft_reset_o <= merged_write_data[1];
                                axil_bresp_o <= 2'b00;
                            end
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
                        default: axil_bresp_o <= RAW_ENABLE != 0 && raw_write_window ?
                            i_raw_write_response : CONFIG_ENABLE != 0 && cfg_write_window ?
                            i_cfg_write_response : JPEG_RING_ENABLE != 0 && jpeg_write_window ?
                            i_jpeg_write_response : RECORD_ENABLE != 0 && record_write_window ?
                            i_record_write_response : ALGO_ENABLE!=0&&algo_write_window ?
                            i_algo_write_response : STEREO_ENABLE!=0&&stereo_write_window ? i_stereo_write_response : 2'b10;
                    endcase
                end
            end
        end
    end

    // 按读地址返回应用状态和计数器
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            axil_rdata_o <= 32'd0;
            axil_rresp_o <= 2'b00;
            axil_rvalid_o <= 1'b0;
            raw_read_pending <= 1'b0;
            cfg_read_pending <= 1'b0;
            jpeg_read_pending <= 1'b0;
            record_read_pending <= 1'b0;
            algo_read_pending <= 1'b0;
            stereo_read_pending <= 1'b0;
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
                            axil_rdata_o <= 32'h0000_002f | (RAW_ENABLE != 0 ?
                                             (32'd1 << `PCIE_CAPABILITY_RAW_FRAME_STORE) : 32'd0) |
                                (CONFIG_ENABLE != 0 ? (32'd1 << `PCIE_CAPABILITY_CONFIG_TRANSACTION) : 0) |
                                (JPEG_RING_ENABLE != 0 ? (32'd1 << `PCIE_CAPABILITY_JPEG_FRAME_RING) : 0) |
                                (RECORD_ENABLE != 0 ? (32'd1 << `PCIE_CAPABILITY_RECORD_V2) : 0);
                            axil_rresp_o <= 2'b00;
                        end
                        `PCIE_REG_SLOT_COUNT: begin
                            axil_rdata_o <= JPEG_RING_ENABLE != 0 ? 32'd6 : `PCIE_SLOT_COUNT;
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
                            if (RAW_ENABLE != 0 && raw_read_window) begin
                                raw_read_pending <= 1'b1;
                                axil_rvalid_o <= 1'b0;
                            end else if (CONFIG_ENABLE != 0 && cfg_read_window) begin
                                cfg_read_pending <= 1'b1;
                                axil_rvalid_o <= 1'b0;
                            end else if (JPEG_RING_ENABLE != 0 && jpeg_read_window) begin
                                jpeg_read_pending <= 1'b1;
                                axil_rvalid_o <= 1'b0;
                            end else if (RECORD_ENABLE != 0 && record_read_window) begin
                                record_read_pending <= 1'b1;
                                axil_rvalid_o <= 1'b0;
                            end else if (ALGO_ENABLE != 0 && algo_read_window) begin
                                algo_read_pending <= 1'b1;
                                axil_rvalid_o <= 1'b0;
                            end else if(STEREO_ENABLE!=0&&stereo_read_window)begin
                                stereo_read_pending<=1;axil_rvalid_o<=0;
                            end
                        end
                    endcase
                end
            end
            if (RAW_ENABLE != 0 && raw_read_pending && i_raw_read_response_valid) begin
                raw_read_pending <= 1'b0;
                axil_rvalid_o <= 1'b1;
                axil_rdata_o <= i_raw_read_data;
                axil_rresp_o <= i_raw_read_response;
            end
            if (CONFIG_ENABLE != 0 && cfg_read_pending && i_cfg_read_response_valid) begin
                cfg_read_pending <= 1'b0;
                axil_rvalid_o <= 1'b1;
                axil_rdata_o <= i_cfg_read_data;
                axil_rresp_o <= i_cfg_read_response;
            end
            if(JPEG_RING_ENABLE!=0 && jpeg_read_pending && i_jpeg_read_response_valid) begin
                jpeg_read_pending<=0;axil_rvalid_o<=1;axil_rdata_o<=i_jpeg_read_data;
                axil_rresp_o<=i_jpeg_read_response;
            end
            if (RECORD_ENABLE != 0 && record_read_pending && i_record_read_response_valid) begin
                record_read_pending <= 1'b0;
                axil_rvalid_o <= 1'b1;
                axil_rdata_o <= i_record_read_data;
                axil_rresp_o <= i_record_read_response;
            end
            if(STEREO_ENABLE!=0&&stereo_read_pending&&i_stereo_read_response_valid)begin
                stereo_read_pending<=0;axil_rvalid_o<=1;axil_rdata_o<=i_stereo_read_data;axil_rresp_o<=i_stereo_read_response;
            end
            if(ALGO_ENABLE!=0&&algo_read_pending&&i_algo_read_response_valid)begin
                algo_read_pending<=0;axil_rvalid_o<=1;
                axil_rdata_o<=i_algo_read_data;axil_rresp_o<=i_algo_read_response;
            end
        end
    end

    wire unused_axil_prot;
    assign unused_axil_prot = ^i_axil_awprot ^ ^i_axil_arprot;

endmodule
