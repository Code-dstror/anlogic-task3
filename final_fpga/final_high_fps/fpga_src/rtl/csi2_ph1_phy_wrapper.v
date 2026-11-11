`timescale 1ns / 1ps

// 封装 CSI 物理层采样、字节对齐和延迟校准
module csi2_ph1_phy_wrapper#(
    // 物理层通道与器件配置
    parameter MIPI_LAN  = 4 ,
    parameter DEVICE    = "EG"
)(
    // 手动延迟调试控制
    input wire I_debug_button,

    // 时钟与复位
    input wire                      I_ref_clock     ,
    input wire                      I_clk_hs_rx_p   ,
    input wire                      I_reset_n       ,
    input wire                      I_decoder_reset_n,
    // 相机物理接口
    input wire [MIPI_LAN-1:0]       I_hs_data_p     ,

    // 接收使能
    input wire                      I_enable        ,
    // 包边界控制
    input  wire                     I_wait_for_sync ,
    input  wire                     I_packet_done   ,

    // 字节域时钟与复位
    output wire                     O_hs_div_clk    ,
    output wire                     O_reset_out     ,

    // 对齐字节流
    output wire [MIPI_LAN-1:0]      O_rx_byte_data_align_vaild,
    output wire [8*MIPI_LAN-1:0]    O_rx_byte_data_align,

    // 延迟校准状态
    output wire                     O_delay_value        ,
    output wire                     O_auto_delay_done,
    output wire [7:0]               O_dbg_delay,
    output wire [5:0]               O_dbg_best_len,
    // Same byte-clock observations; these ports do not control reception.
    output wire [8*MIPI_LAN-1:0]     O_diag_raw_bytes,
    output wire [3*MIPI_LAN-1:0]     O_diag_byte_offset,
    output wire [MIPI_LAN-1:0]       O_diag_byte_found,
    output wire [15:0]              O_diag_calibration
    );

wire                    w_hs_clk_raw;
wire                    w_hs_clk   ;
wire                    w_hs_clk_x2_raw;
wire                    w_hs_clk_x2;
wire                    w_hs_clk_x4;
wire                    w_reset_out  ;
wire                    w_clock_ready;
// PH1A IDDR holds data only; fresh serial samples replace its old contents.
// Health reset still holds byte alignment/calibration/decoding for three full
// byte clocks before any lane may publish data. No 450 MHz data reset tree.
(* preserve="true", ASYNC_REG="TRUE" *) reg [2:0] r_core_release_pipe=3'b000;
wire w_io_reset_n;
reg  [1:0]              r_align_enable_sync;

wire [8*MIPI_LAN-1:0]   w_rx_byte_data;                   //synthesis keep
wire [MIPI_LAN-1:0]     w_rx_byte_data_align_vaild;       //synthesis keep
wire [8*MIPI_LAN-1:0]   w_rx_byte_data_align;             //synthesis keep
wire [5:0]              w_auto_delay_value;
wire 	                w_auto_delay_vaild;
wire                    w_auto_delay_done;
wire [5:0]              w_auto_delay_best_len;
wire                    w_auto_delay_window_valid;
wire                    w_auto_delay_scan_failed;
wire [5:0]              w_lane_delay_value;
wire                    w_lane_delay_vaild;
wire 	                w_delay_data_val[MIPI_LAN-1:0];
reg                     r_manual_mode;


assign O_hs_div_clk                 = w_hs_clk              ;
assign O_reset_out                  = w_reset_out               ;
assign O_rx_byte_data_align_vaild   = w_rx_byte_data_align_vaild;
assign O_rx_byte_data_align         = w_rx_byte_data_align      ;
assign O_delay_value                = w_lane_delay_value[0]     ;
assign O_auto_delay_done            = r_manual_mode || (w_auto_delay_done &&
    ((DEVICE != "PH1A") || w_auto_delay_window_valid));
assign O_dbg_best_len               = w_auto_delay_best_len;
assign O_dbg_delay                  = {w_lane_delay_vaild, r_manual_mode, w_lane_delay_value};
assign O_diag_raw_bytes             = w_rx_byte_data;
// [4:0] physical code, [10:5] scored window, [11] scan done,
// [12] acceptable window, [13] failed scan, [14] manual, [15] status valid.
assign O_diag_calibration = {w_auto_delay_done || r_manual_mode,
    r_manual_mode,w_auto_delay_scan_failed,w_auto_delay_window_valid,
    w_auto_delay_done,w_auto_delay_best_len,w_lane_delay_value[4:0]};

generate
    if (DEVICE == "PH1A") begin : g_io_release_clock
        // pclk 负载保持在区域时钟分支，避免全局缓冲增加 IDDR 复位移除路径延迟
        PH1_PHY_SCLK_V2 #(
            .GSR("ENABLE"), .BYPASS("ENABLE"), .DELAY(0)
        ) u_pclk_sclk (
            .ce(1'b1), .clkin(w_hs_clk_x2_raw), .clkout(w_hs_clk_x2)
        );
        // 字节采样分支与区域 pclk 发射分支匹配，DIV4 只驱动一个区域 SCLK
        PH1_PHY_SCLK_V2 #(
            .GSR("ENABLE"), .BYPASS("ENABLE"), .DELAY(0)
        ) u_byte_sclk (
            .ce(1'b1), .clkin(w_hs_clk_raw), .clkout(w_hs_clk)
        );
        assign w_io_reset_n = w_clock_ready;
    end else begin : g_generic_release_clock
        reg [2:0] r_io_release_pipe=3'b111;
        assign w_hs_clk = w_hs_clk_raw;
        assign w_hs_clk_x2 = w_hs_clk_x2_raw;
        assign w_io_reset_n = ~r_io_release_pipe[2];
        always @(posedge w_hs_clk or negedge w_clock_ready) begin
            if(!w_clock_ready)r_io_release_pipe<=3'b111;
            else r_io_release_pipe<={r_io_release_pipe[1:0],1'b0};
        end
    end
endgenerate
assign w_reset_out = r_core_release_pipe[2];

// A PH1A IDDR/half-byte/byte chain is entirely overwritten within this
// three-byte window. Clock loss asserts this boundary without a byte edge.
// 延迟释放字节域核心逻辑复位
always @(posedge w_hs_clk or negedge w_io_reset_n) begin
    if (!w_io_reset_n)
        r_core_release_pipe <= 3'b000;
    else
        r_core_release_pipe <= {r_core_release_pipe[1:0], 1'b1};
end

// I_enable 来自持续运行的参考时钟域，监测器使用原始电平以恢复停顿的字节时钟
// 字节对齐状态机使用同步到 w_hs_clk 的使能副本
// 将参考域使能同步到字节域
always @(posedge w_hs_clk or negedge w_reset_out) begin
    if (!w_reset_out)
        r_align_enable_sync <= 2'b00;
    else
        r_align_enable_sync <= {r_align_enable_sync[0], I_enable};
end


// 手动延迟调试控制
  // �͵�ƽ���¡��ͷ���(+1 tap)��
  // 1. δ�����ֶ�ģʽǰ���״��ͷ������� auto-delay ��ǰֵ
  // 2. �����ֶ�ģʽ��ÿ���ͷ��� delay tap + 1
reg  [1:0] r_debug_button_sync;
reg  [5:0] r_manual_delay;
reg        r_manual_delay_load;

wire w_debug_release = (r_debug_button_sync == 2'b01);

// 同步调试按键并锁存手动延迟设置
always @(posedge w_hs_clk or negedge w_reset_out) begin
    if (!w_reset_out) begin
        r_debug_button_sync <= 2'b11;
        r_manual_mode       <= 1'b0;
        r_manual_delay      <= 6'd0;
        r_manual_delay_load <= 1'b0;
    end else begin
        r_debug_button_sync <= {r_debug_button_sync[0], I_debug_button};
        r_manual_delay_load <= 1'b0;

        if (w_debug_release) begin
            r_manual_mode       <= 1'b1;
            r_manual_delay_load <= 1'b1;

            if (!r_manual_mode)
                r_manual_delay <= (DEVICE == "PH1A") ?
                    {1'b0,w_auto_delay_value[4:0]} : w_auto_delay_value;
            else if (DEVICE == "PH1A")
                r_manual_delay <= {1'b0,(r_manual_delay[4:0] + 5'd1)};
            else
                r_manual_delay <= r_manual_delay + 1'b1;
        end
    end
end

assign w_lane_delay_value = r_manual_mode ? r_manual_delay      : w_auto_delay_value;
assign w_lane_delay_vaild = r_manual_mode ? r_manual_delay_load : w_auto_delay_vaild;


rx_clk_gen #(
    .DEVICE (DEVICE)
)u_rx_clk_gen(
    .I_mipi_clk_p (I_clk_hs_rx_p ),
    .I_rst        (~I_reset_n    ),
    .O_clk        (w_hs_clk_raw  ),//����8λ����ʱ��
    .O_clk_x2     (w_hs_clk_x2_raw),//����4λ����ʱ��
    .O_clk_x4     (w_hs_clk_x4   ) //4��ʱ�ӣ���������ʱ��

);

// 请求应答监测器在持续运行的参考时钟域检测字节时钟停顿，并异步断言 O_ext_rst_n
// 旧检测器在受监测的字节域计数，时钟停在阈值之后便无法再次请求复位
// src_fpga/simulation/tb_clock_watchdog_legacy_failure.v 覆盖高、低电平停钟情形
// w_clock_ready 只表示字节时钟恢复跳变，有效数据仍需等待字节对齐完成
// IDDRx2 采样原语与 x2/x4 时钟的复位关系仍需单独确认
csi_clock_watchdog #(
    .TIMEOUT_REF_CYCLES (1024),
    .GOOD_ACKS          (3),
    .RELEASE_STAGES     (3)
) u_csi_clock_watchdog(
    .I_ref_clk   (I_ref_clock),
    .I_ext_clk   (w_hs_clk),
    .I_arst_n    (I_reset_n),
    .I_enable    (I_enable),
    .O_healthy_ref (),
    .O_clock_lost_pulse_ref (),
    .O_ext_rst_n (w_clock_ready)
);

generate if (DEVICE == "PH1A") begin : g_ph1a_delay_scan
    wire [4:0] physical_delay;
    assign w_auto_delay_value = {1'b0,physical_delay};
    ph1a_rx_delay_scan #(.MIPI_LAN(MIPI_LAN)) u_auto_delay_ctl (
        .I_byte_clk(w_hs_clk), .I_reset_n(w_reset_out),
        .I_byte_align_done(w_rx_byte_data_align_vaild),
        .I_raw_bytes(w_rx_byte_data),
        .O_delay_value(physical_delay), .O_delay_vaild(w_auto_delay_vaild),
        .O_scan_done(w_auto_delay_done), .O_window_len(w_auto_delay_best_len),
        .O_window_valid(w_auto_delay_window_valid),
        .O_scan_failed(w_auto_delay_scan_failed)
    );
end else begin : g_legacy_delay_scan
assign w_auto_delay_window_valid = (w_auto_delay_best_len != 0);
assign w_auto_delay_scan_failed = w_auto_delay_done && !w_auto_delay_window_valid;
auto_delay_ctl #(
  .MIPI_LAN(MIPI_LAN),
  .LAN_DATA_CUNT(10'h3ff)
)u_auto_delay_ctl(
    .I_byte_clk        (w_hs_clk),
    .I_reset_n         (w_reset_out),
    .I_byte_align_done (w_rx_byte_data_align_vaild),
        .O_delay_value     (w_auto_delay_value),
        .O_delay_vaild     (w_auto_delay_vaild),
        .O_auto_delay_done (w_auto_delay_done),
        .O_dbg_best_len    (w_auto_delay_best_len)
);
end endgenerate

generate
genvar i;
for (i=0; i<MIPI_LAN; i=i+1) begin : gen_channel_wrapper
// UG910 v1.6, section 36, specifies PH1A indly_en as active-high enable and
// its example ties it high. The official simulation model bypasses the delay
// whenever it is low. auto_delay's load pulse is not a valid steady enable.
csi_rx_hs_data_phy #(
    .DEVICE (DEVICE)
) u_csi_rx_hs_data_phy(
    .I_rxclk        (w_hs_clk      ),
    .I_rxclk_div_x2 (w_hs_clk_x2   ),
    .I_rxclk_div_x4 (w_hs_clk_x4   ),
    .I_reset_n      ((DEVICE == "PH1A") ? 1'b1 : w_io_reset_n),
    .I_hs_data_p    (I_hs_data_p[i]),
    .I_delay_value  (w_lane_delay_value),
    .I_delay_vaild  ((DEVICE == "PH1A") ? 1'b1 : w_lane_delay_vaild),
    .O_rx_data      (w_rx_byte_data[(8 * i) + 7:8 * i]),
    .O_delay_data_val(w_delay_data_val[i])
);

csi_rx_byte_align_observed u_csi_rx_byte_align(
    .I_clock           (w_hs_clk    ),
    .I_reset_n         (w_reset_out && I_decoder_reset_n),
    .I_enable          (r_align_enable_sync[1]),
    .I_lan_data_in     (w_rx_byte_data[(8 * i) + 7:8 * i]),
    .I_wait_for_sync   (I_wait_for_sync ),
    .I_packet_done     (I_packet_done   ),
    .O_data_out_vaild  (w_rx_byte_data_align_vaild[i]),
    .O_data_out        (w_rx_byte_data_align[(8 * i) + 7:8 * i]),
    .o_diag_offset     (O_diag_byte_offset[3*i+:3]),
    .o_diag_found      (O_diag_byte_found[i])
);

end
endgenerate

  // cwc cwc(
  // .probe0(I_hs_data_p				),
  // .probe1(O_auto_delay_done		),
  // .probe2(w_delay_data_val[0]		),
  // .probe3(w_delay_data_val[1]		),
  // .probe4(w_delay_data_val[2]		),
  // .probe5(w_delay_data_val[3]		),
  // .probe6(w_rx_byte_data[7:0]		),
  // .probe7(w_rx_byte_data[15:8]	),
  // .probe8(w_rx_byte_data[23:16]	),
  // .probe9(w_rx_byte_data[31:24]	),
  // .probe10(r_debug_delay	),
  // .clk(w_hs_clk)
  // );

endmodule
