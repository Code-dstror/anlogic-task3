# 项目检查点：2026-09-13（DRAFT）

## 项目目标与团队分工

赛题 3 的目标是以 PH1A90SEG324 FPGA 与 RK3576 异构平台完成：MIPI CSI 传感器采集、FPGA 三项硬件预处理、FPGA JPEG 或 LZ77 压缩、芯片间高速传输、RK3576 NPU 本地目标检测及量化报告。

- Linux/RK3576：PCIe/MIPI 接收、压缩帧解析/解码、模型前处理、RKNN 推理、结果与统计。
- FPGA：传感器采集与控制、三项硬件预处理、JPEG/LZ77、缓存/时序、选定互连端与性能计数。
- 共同：互连角色/恢复、帧协议、缓冲所有权、错误/指标口径。

## 平台、目录与资料边界

- 指定平台：`MLK-AFH03-AFC03-2GB LPDDR4X+32GB EMMC`，RK3576J + PH1A90SEG324。
- 当前工作目录：`/home/uisrc/work/anlogic-task3`。
- 官方严格只读资料：`local_refs/official_package`；不得修改、移动、解压或在其中编译，也不复制官方源码。
- Linux 代码目录为 `linux/`；FPGA 代码目录为 `fpga/`，未经明确要求不修改；共同接口文档在 `interface/`。

## 已完成并提交的工作

当前 Git 历史中已提交：

- `c591126`：项目结构初始化。
- `b4cce43`：赛题需求与平台硬件基线。
- `094acf3`：官方 PCIe Linux/SGDMA/V4L2 基线分析。
- `f9700cd`：RK3576 首次上电与只读检查清单。

## 当前尚未提交的协议与协作文档

- `interface/pcie-jpeg-protocol-v0.1.md`：DRAFT 协议，尚未冻结或提交。
- `docs/decisions/0002-sgdma-char-device-first.md`：Proposed 决策，尚未提交。
- `docs/coordination/fpga-confirmation-checklist.md`：DRAFT 协作清单，尚未提交。
- 本检查点文件：尚未提交。

## 当前架构方向

- [0001](../decisions/0001-pcie-primary-mipi-fallback.md)：PCIe 是主方案，MIPI 是备选；仍为 proposed，未最终接受。
- [0002](../decisions/0002-sgdma-char-device-first.md)：第一版建议 SGDMA C2H 字符设备优先，由用户态接收 JPEG；固定 RGB24 V4L2 包装层暂不使用。轮询允许，MSI/MSI-X 和可选 V4L2 MJPEG 延后以实测决定。
- RK3576 作为 PCIe RC、FPGA 作为 EP 是官方课程 Linux 示例的事实和当前候选方向；当前 FPGA RTL/IP 配置仍待队友确认。
- 不预设 PCIe 2.0 或 3.0、BDF、BAR 地址、实际 `/dev` 节点、DMA 通道数、slot 数或最大帧长。

## 三个协议架构未决问题

1. **长度发现**：若 `payload_length` 位于 DMA 内部 header，Linux 无法在 DMA 前知道长度；待比较 BAR 每-slot 长度、固定整 slot DMA、两次 DMA、以及 SGDMA 实际完成长度/EOP 方案。
2. **多 slot metadata**：单组全局 READY/长度/序号不足；待比较每-slot BAR metadata 表、selected-slot 窗口和 FPGA descriptor ring。
3. **状态所有权**：`EMPTY/WRITING/READY/READING` 的写入方、状态发布与 payload 可见性的顺序、以及跨时钟域同步尚未冻结。

详细问题与填写入口见 [FPGA 协作确认清单](../coordination/fpga-confirmation-checklist.md)。

## 当前限制与阻塞项

- FPGA 队友暂时无法工作，P0/P1/P2 确认项均无已确认答案。
- 板卡暂时不在手边；无法验证枚举、实际协商链路、BAR、节点、C2H/EOP、IRQ 或 JPEG 数据。
- 摄像头到 FPGA 的物理接入、传感器参数、FPGA JPEG 与 SGDMA/slot RTL 设计、错误/复位合同均阻塞 Linux 接收程序 ABI 定稿。
- 板卡资料对内部 PCIe 2.0×1/3.0×1 有冲突；实际协商结果必须接板后记录。
- 赛题的模型、输入工作点、验收阈值、双路是否基础要求等仍需外部确认。

## 当前禁止的操作

在未明确批准前：不执行 `sudo`、安装软件、编译、加载/卸载内核模块、修改设备树、烧录、重启、配置开机自启动；不运行会改变板端状态的部署脚本。保持官方资料只读，且不修改 FPGA 代码。

## 下一步计划

1. FPGA 队友可工作后，先填写 P0，冻结传感器/PCIe EP/SGDMA/JPEG/长度发现合同。
2. 双方根据 P0 修订协议 DRAFT，确定可实现的单帧 C2H 路径。
3. 获得板卡与相应授权后，按首次上电清单执行只读基线，动态记录 BDF、BAR、节点、speed/width 和驱动状态。
4. 依次验证固定测试数据 DMA、单帧 JPEG、多 slot 连续传输、解码、RKNN；然后才评估中断、性能优化与 V4L2 MJPEG。

## 新会话恢复时首先阅读

1. `AGENTS.md` 与 `README.md`
2. `docs/context/project-checkpoint-2026-09-13.md`
3. `docs/requirements/task3-requirements.md`
4. `docs/hardware/platform-baseline.md`
5. `docs/coordination/fpga-confirmation-checklist.md`
6. `interface/pcie-jpeg-protocol-v0.1.md`
7. `docs/decisions/0001-pcie-primary-mipi-fallback.md` 与 `docs/decisions/0002-sgdma-char-device-first.md`
8. `docs/analysis/pcie-linux-baseline.md` 与 `docs/bringup/rk3576-first-boot-checklist.md`
