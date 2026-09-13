# MLK-AFH03-AFC03 平台硬件基线（赛题 3）

## 范围、来源与版本

此文件只说明 `local_refs/official_package/02_hardware` 所描述的板卡能力；赛题要实现什么以 [`task3-requirements.md`](../requirements/task3-requirements.md) 的赛题 PDF 结论为准。管脚表应以原理图为最终依据（核心板手册也如此声明）。

| 资料 | 版本/日期 | 使用页/页码 | 用途与备注 |
|---|---|---|---|
| `安路.pdf` | 创建/修改：2026-08-21 | PDF 页 9--11（平台 3）、17--25（赛题 3） | 平台名称/赛题需求的最高依据。 |
| `01_硬件手册/MLK-AFH03-AFC03硬件使用手册.pdf` | Rev2026 V1.0，2026-02-06（封面/修订表） | 页 5--6、8--16、24--44、55 | 底板+核心板资源、接口、内部 MIPI/PCIe。 |
| `01_硬件手册/MLK-AFC03核心板硬件使用手册.pdf` | Rev2026 V1.0，2026-02-06 | 页 5--6、8--23 | 核心板资源、存储、时钟、复位、电源和连接器。 |
| `02_原理图/MLK-AFH03-20251112.pdf` | 文件名：2025-11-12；PDF metadata 修改：2026-03-23；29 页 | sheet 8 HDMI、11 PCIe、13 CSI、14 DSI、23 FPGA_CLK、24 FPGA_MIPI_DSI、25 FPGA_JTAG&UART、27 FPGA_RK3576_PCIE_RC_EP | 底板实际连线核对；内部版本/修订栏未明确，日期与 metadata 需留意。 |
| `02_原理图/MLK-AFC03-20251112（仅FPGA部分及板级连接器不包含RK部分）.pdf` | 文件名：2025-11-12；PDF metadata 修改：2026-06-17；8 页 | 全部 8 页（FPGA、DDR3L、Flash、时钟/连接器） | 明确标注不含 RK 部分，不能单独证明 RK 连接。 |
| `08_框图及pinlist/AFH03/RK3576J_PH1A90SEG324_MIPI交互管脚定义表.xlsx`、`...PCIE交互管脚定义表.xlsx` | 表内未列版本/日期 | 各工作表（无 PDF 页码） | 与手册页 43--44交叉核对内部互连。 |
| `08_框图及pinlist/AFH03/MIPI_CSI_DSI管脚定义表.xlsx`、`PCIE2.0-M.2管脚定义表.xlsx` | 表内未列版本/日期 | 各工作表（无 PDF 页码） | 与手册页 30--33、30 核对外设接口。 |

## 1. 指定平台和核心资源

- **赛题平台完整名称**：`MLK-AFH03-AFC03-2GB LPDDR4X+32GB EMMC`（赛题 PDF 页 9）。它由 AFC03 核心板与 AFH03 底板构成（硬件手册页 5）。
- **异构芯片**：Rockchip **RK3576J**（FCCSP698L）与 Anlogic **PH1A90SEG324**（SEG324），均标为工业级（硬件手册页 8）。
- **RK3576J**：4×Cortex-A72 + 4×Cortex-A53，最高 2.2 GHz；Mali G52 MC3；6 TOPS NPU；16 MP ISP；H.264/H.265 解码/编码和 HDMI/eDP/MIPI-DSI/DP 显示能力（核心板手册页 5、8；赛题 PDF 页 9）。
- **RK 存储**：一片 2 GB LPDDR4X，标称 2133 MHz；一片 32 GB 国产 eMMC，eMMC 5.1 兼容并向下兼容 4.41/4.5/5.0；UFS 2.0 为空贴（核心板手册页 5、9--11）。手册同时说明 LPDDR4X/eMMC具体容量型号随销售情况可能不固定，故应以实物丝印/系统枚举复核。
- **FPGA**：PH1A90SEG324，115,776 LUT4、128,640 DFF、1,680 Dis-RAM、272×20 Kb ERAM（5,440 Kb）、240 DSP、12 PLL；配套 256 MB、16-bit DDR3L（933 MHz 数据主频）及 128 Mbit 1.8 V SPI Flash（核心板手册页 5--6、8、12--14）。

## 2. 赛题 3 相关视频、显示、存储与调试资源

| 资源 | 板上能力/已知连接 | 赛题 3 关系 | 依据 |
|---|---|---|---|
| 外接摄像头 | AFH03 的 J8/J9 是 **两路 RK3576 4-lane MIPI CSI 输入**；每路含 3.3 V、I2C、MIPI 时钟/4 data lane、MCLK 和 PDN。CSI 最高每 lane 2.5 Gbps。 | 能接相机到 RK；文档没有把这两个连接器接到 FPGA。赛题却要求 FPGA CSI 传感器驱动，故 FPGA 侧传感器物理接入需确认。 | 组合手册页 5--6、30--31；pinlist `MIPI_CSI_DSI`。 |
| FPGA→RK 内部 MIPI | 核心板有 4-lane 直接链路：FPGA **MIPI DSI TX 输出** → RK3576 **CSI3 RX 输入**。pinlist给出 D0--D3/CLK 的 FPGA/RK 对应管脚。 | 可作为 R5 的 MIPI 方案候选；方向是 FPGA 至 RK，适合压缩帧送 RK。 | 组合手册页 43；MIPI 交互 pinlist。 |
| RK HDMI | 1 路 HDMI 2.1 TX，含 TMDS、HPD、DDC/CEC；支持 HDMI 2.1。 | 可用于展示检测结果，但赛题没有强制 HDMI。 | 组合手册页 28；原理图 sheet 8。 |
| RK MIPI DSI | 1 路 4-lane DSI TX（J34），可扩展 LCD，手册称最高 2.5 Gbps/lane、最大 2560×1600@60 Hz。 | 可选本地显示路径，非赛题强制。 | 组合手册页 6、32--33；pinlist `MIPI_CSI_DSI`。 |
| RK eMMC/LPDDR4X | 32 GB eMMC / 2 GB LPDDR4X 直连 RK。 | OS、模型、输入/结果和报告数据的主要本地存储候选。 | 核心板手册页 9--11。 |
| FPGA DDR3L | 256 MB、16-bit DDR3L。 | 采集、预处理、压缩的帧/行缓存候选。 | 核心板手册页 12--13。 |
| TF/网络 | RK 一路 4-bit TF 卡；两路千兆 RGMII 以太网。 | 可选数据导出/报告/演示；不替代必选 MIPI/PCIe 芯片间通道。 | 组合手册页 29、37。 |
| 调试 | 分别有 RK 与 FPGA 的 Type-C 转串口；FPGA 有独立 Type-C JTAG，且不支持热插拔。 | 适合调试；不是赛题的功能链路。 | 组合手册页 24、43；原理图 sheet 25。 |

## 3. RK3576—FPGA 可用连接与限制

### MIPI 候选

- 内部固定 4-lane 物理方向为 FPGA MIPI DSI TX 到 RK CSI3 RX；RK 引脚为 H28/H29、J28/J29、1H22/1H23、K28/K29、L28/L29，对应 FPGA 的 PLB/MIPIB lane 与时钟引脚，完整对应表见手册页 43或 MIPI 交互 pinlist。
- 因此若赛题链路选 MIPI，需确认 FPGA 所发内容在 RK CSI 接收端的协议/驱动可行性；“物理有 D-PHY 连线”不自动等同于能传任意 JPEG/LZ77 帧。

### PCIe 候选

- 内部串行线为 FPGA TXM1_83/TXP1_83（A3/A4）→ RK `PCIE1_RXN/RXP`（M29/M28），RK `PCIE1_TXN/TXP`（N29/N28）→ FPGA RXM1_83/RXP1_83（B5/B6）（组合手册页 44，PCIe 交互 pinlist）。
- 组合手册称该内部链路为“PCIE30x1”，并明确使用后无法使用 USB2 OTG1（页 44）；核心板资源表及赛题平台表则称 RK--FPGA 为 `PCIE2.0x1`（核心板手册页 6；赛题 PDF 页 11）。在角色、速率和软件支持未确认前，不应把任一版本写死。
- 另有 RK 的外部 PCIe 2.0×1 M.2（给 NVMe SSD），与内部 FPGA 链路不是同一功能资源（组合手册页 30，pinlist `PCIE2.0-M.2`）。

## 4. 管脚、复位、供电、时钟基线

| 类别 | 已确认项目 | 依据 |
|---|---|---|
| FPGA 时钟 | 25 MHz 单端：T16；100 MHz LVDS：T13(P)/T14(N)。 | 核心板手册页 14；核心板原理图时钟页。 |
| RK 时钟 | 24 MHz 无源时钟。 | 核心板手册页 5。 |
| FPGA 配置/调试 | JTAG：TCK D11、TMS A10、TDI B11、TDO E11，1.8 V；底板 Type-C，不能热插拔。 | 组合手册页 43；原理图 sheet 25。 |
| 复位 | FPGA 为上电复位；RK `RESET_L` 低有效，底板 RESET 按键对应 RK W28。 | 核心板手册页 15；组合手册页 38。 |
| 上电/供电 | 核心板输入 5 V；RK PMIC 完成上电后以 `VCC_3V3_S0` 使能 FPGA 第一级，因而 RK 先于 FPGA 上电。FPGA有 0.95 V（最大 6 A）、1.8 V、3.3 V、1.35 V等电源。底板输入 12 V@3 A。 | 核心板手册页 15--16；组合手册页 5--6、55。 |
| 摄像头控制 | CSI0：I2C8 SCL A26 / SDA 1C22、MCLK 1E7、PDN 1A23；CSI1：I2C5 SCL 1E21 / SDA 1E22、MCLK 1B12、PDN 1D10。 | 组合手册页 30--31；`MIPI_CSI_DSI` pinlist。 |
| 显示 | HDMI TX：TMDS pairs 与 HPD/CEC/SCL/SDA见组合手册页 28；MIPI DSI TX D0--D3/CLK见页 32--33。 | 同左；原理图 sheets 8、14。 |

## 5. 板卡资料差异与待确认项

| 编号 | 差异/风险 | 处理结论 |
|---|---|---|
| H1 | 内部 FPGA--RK PCIe 被写成 PCIe 3.0×1（组合手册页 44），但核心板手册页 6和赛题 PDF 页 11写 PCIe 2.0×1。 | 向供应商/老师确认实际 IP、PHY 代际、RC/EP角色、可达速率与 BSP；目前不选定版本。 |
| H2 | 赛题要求 FPGA MIPI CSI 传感器 IP（赛题页 18），但板载 J8/J9 MIPI CSI 接口都接 RK；已记录的 FPGA--RK MIPI是反向的 FPGA DSI TX→RK CSI3 RX。 | 确认给 FPGA 接传感器的物理端口/转接板、所用 MIPI IP及授权/约束；不能假定 RK 的 `/dev/video*` 输入已满足 FPGA采集要求。 |
| H3 | 核心板手册列最大功耗 20 W（页 6），赛题平台表列最大功耗 24 W（PDF 页 11）；底板输入又是 12 V@3 A。 | 将其作为电源/散热预算的待确认实物参数，避免以任一数字作硬约束。 |
| H4 | 核心板手册说 LPDDR4X/eMMC具体容量型号随销售情况不固定（页 9、11），赛题指定平台名和表格是 2 GB+32 GB。 | 赛题项目按指定配置规划，但开工前核对拿到的板卡丝印、容量与系统枚举。 |
| H5 | 原理图文件名为 20251112，而 PDF metadata 修改日期是 2026 年；AFC03 原理图又明确不含 RK 部分。 | 管脚实施以实际原理图/实物为准；涉及 RK、芯片间链路时同时查 AFH03 原理图和连接器表。 |
