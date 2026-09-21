# IMX415 摄像头 IP 使用、重建与上板入口

本文以来源提交 `6b398c144e7a563ea3d9fa6085ac3142813be2a7` 的同名文档为基础，
并适配当前目标 `feature/linux-transport@0585a3d`。它只说明已有独立摄像头
工程的重建、历史验证边界和上板前检查；不是板级验收记录，也不授权烧录。

## 工程与接口

独立 TD 工程为 [fpga_prj/imx415_camera.al](../fpga_prj/imx415_camera.al)。
该工程指定 PH1、`PH1A90SEG324`、速度等级 `-2`，顶层为
`imx415_camera_board_top`；它是独立的采集验证工程，并不修改当前 PCIe
工程。工程列入摄像头 RTL，以及
[fpga_rtl/constraints/imx415_camera_board_top.adc](../fpga_rtl/constraints/imx415_camera_board_top.adc)
和
[fpga_rtl/constraints/imx415_camera_board_top.sdc](../fpga_rtl/constraints/imx415_camera_board_top.sdc)。

可复用模块是
[fpga_rtl/camera/imx415_camera_axis.v](../fpga_rtl/camera/imx415_camera_axis.v)。
它接收像素时钟、传感器时钟、PHY 参考时钟和低有效复位；输出 RGB888 的
128-bit AXI-Stream：`TDATA`、`TKEEP`、`TVALID`、`TREADY` 与帧尾 `TLAST`。
最早字节位于 `TDATA[7:0]`，像素按 R、G、B 连续紧密排列，可跨拍；不是每
像素填充为 32 bit。此摄像头 IP 的输出不带 PCIe 帧头，且不包含 JPEG 或
PCIe。

`MODE_4K=0` 为 1920×1080，`MODE_4K=1` 为 3840×2160。模式、裁剪起点与
Bayer 相位均为综合时参数，变更后必须重新构建；实际画面位置和色彩仍须在
硬件核对。首版包含黑电平处理、双线性去马赛克与 Gamma，不含自动曝光、
自动白平衡或高级降噪。

`o_frame_done` 表示帧尾 AXI 握手已完成；`o_frame_error` 表示当前帧必须
丢弃。错误不能撤回先前已传出的数据。接口不提供 SOF/TUSER：接收端发生
错误后应保持 `TREADY`，丢弃数据直到下一次 `TLAST` 握手，并从其后一拍重新
计帧。该保守恢复可能额外丢弃一帧，但能处理报错时被反压保留的一拍。无限期
反压会耗尽有限接收 FIFO，导致丢帧和重新同步，不能保证无限期无损暂停。

独立顶层持续接收视频，并以 115200、8N1 UART 每秒发送 16 字节状态：

| 字节 | 内容 |
| --- | --- |
| 0–3 | ASCII `CAM1` |
| 4–7 | 完整帧累计计数，小端 |
| 8–11 | 状态字，小端：bit31 配置成功，bit30 配置错误，bit29 自动延迟完成，bit28:0 错误累计计数 |
| 12–15 | 最近一帧 XOR 摘要，小端；仅供活动观测，不能替代图像正确性检查 |

先检查配置成功、自动延迟完成和错误计数，再测量相邻秒的完整帧增量。该板级
顶层不向主机传送图像；如需后续使用，应将摄像头 IP 的 AXI-Stream 接至缓存
或图像处理链路。目标 1080p60/4K30 仍须以真实 FMC 转接板和 IMX415 测量。

## TD 重建（GUI/Tcl Console）

仓库提供以下 Tcl 脚本：

- [fpga_prj/scripts/sync_imx415_camera_project.tcl](../fpga_prj/scripts/sync_imx415_camera_project.tcl)：导入 `ph1_90.db`，创建或打开工程，注册仓库内 RTL 与 ADC/SDC，并生成项目登记 Tcl。
- [fpga_prj/scripts/diagnose_imx415_camera.tcl](../fpga_prj/scripts/diagnose_imx415_camera.tcl)：读取同步阶段生成的登记 Tcl，执行 HDL/约束读取与优化，并生成面积诊断报告。
- [fpga_prj/scripts/build_imx415_camera_project.tcl](../fpga_prj/scripts/build_imx415_camera_project.tcl)：重置 `syn_1`，运行至综合优化和 bitstream，复制最终报告并对 setup/hold WNS 作失败判定。

各脚本以自身位置规范化后向上两级解析仓库根目录；sync 因而使用已提交的
工程、RTL 和约束，在本地 TD 工作目录生成产物。它会创建
`tmp/camera_td/` 并写出 `tmp/camera_td/register_camera.tcl`。后者不是 Git
文件，而是 diagnose 的必要输入：diagnose 在切换至该解析出的仓库根目录后，
以相对路径打开它，并从其中提取 HDL 文件列表；随后才读取仓库内 ADC 和 SDC。

因此必须先成功执行 sync，并确认 `tmp/camera_td/register_camera.tcl` 已存在，
才能运行 diagnose。sync 失败或该文件缺失时必须停止，不能跳过这一诊断前置
条件。`tmp/camera_td/**` 均为本地生成物，不是仓库依赖，也不得提交。除这种
前一阶段产生的本地工作产物外，重建的源文件来自已提交仓库，工具来自用户已
安装、具备 PH1 器件支持及许可证的 TD。仓库**目前没有已验证的 headless
启动 wrapper**；不要猜测 TD 命令行参数，也不要使用任何仓库外脚本启动 TD。

在 TD GUI 的 Tcl Console 中，以仓库绝对路径为工作目录。脚本末尾会执行
`exit 0`，因此每个阶段应使用一个新的 TD GUI 会话：

1. 打开 TD GUI，确认它使用的安装与许可证可支持 `PH1A90SEG324-2`。在 Tcl
   Console 执行：

   ```tcl
   cd {<仓库绝对路径>}
   source fpga_prj/scripts/sync_imx415_camera_project.tcl
   ```

2. 仅在 sync 成功且已确认 `tmp/camera_td/register_camera.tcl` 存在后，重新
   打开 TD GUI，并在 Tcl Console 执行诊断：

   ```tcl
   cd {<仓库绝对路径>}
   source fpga_prj/scripts/diagnose_imx415_camera.tcl
   ```

3. 再次重新打开 TD GUI，并在 Tcl Console 执行构建：

   ```tcl
   cd {<仓库绝对路径>}
   source fpga_prj/scripts/build_imx415_camera_project.tcl
   ```

构建脚本会在其生成的报告目录和运行输出目录中保存结果。应检查 Tcl Console
的退出状态、`@@@FAIL` 标记和最终时序报告，不能仅以 bitstream 文件存在判定
成功。脚本会把负的 setup 或 hold WNS 判为失败；未满足时序时不得将输出用于
正式烧录。

## 已有验证证据与严格边界

以下是来源提交留下的**历史证据**，本次文档适配未运行 TD、ModelSim 或板卡
操作：

来源记录中提及的 `tmp/modelsim/**`、`tmp/camera_td/**` 下历史日志、报告、
网表、SDF 和 bitstream 等原始输出，没有随 `6b398c1` 或当前目标分支提交。
仓库内的验证文档只保存来源提交对历史运行结果的摘要；这些路径既不是当前
clone 可直接查看的证据附件，也不是构建输入。新环境必须重新运行相应的
ModelSim/TD 流程、产生新的本地输出，才可独立复核；不得暗示重新运行必然得到
与历史相同的结果。本次文档适配没有重新执行 ModelSim、TD 或板卡验证。

- ModelSim 行为验证曾通过，包括 1080p/4K 完整帧、CSI 至 RGB 集成、随机
  输出反压、CRC 故障恢复、传感器控制、FIFO 溢出恢复、RGB 打包、UART 状态与
  静默源看门狗；这些是历史验证证据，本次未重跑。详细记录见
  [doc/imx415_camera_validation.md](imx415_camera_validation.md)。
- TD 6.2.168116 曾对 `PH1A90SEG324-2` 完成 synthesis、placement、routing
  和 bitstream 生成；但最终时序未收敛：setup WNS 为 **-2.923 ns**，hold WNS
  为 **-1.659 ns**。这不是本次重新执行的结果。
- 因时序未收敛，现有 bitstream 不能作为板级验收版本，且不得作为正式烧录
  版本。
- IMX415、PHY 电气与链路、真实图像采集、下游反压及恢复均未上板验证。行为
  仿真不能验证 MIPI 电气裕量、实际帧率、Bayer 相位、色彩或图像质量。

## 上板前安全清单

在任何下载或连板前，逐项完成并记录核对结果：

- 开发板与 FPGA 的准确型号必须与工程的 `PH1A90SEG324-2` 相符。
- 确认 IMX415 模组型号、所需电压与开发板供电能力；依据实物原理图核对供电
  顺序，禁止凭例程假设供电时序。
- 依据实物原理图逐针核对 FMC/排线的方向、键位、信号与管脚，尤其是 MIPI
  差分对、I2C、MCLK、XCLR 与电平标准；不得仅凭约束文件推断实物连线。
- 确认下载器型号、连线和目标器件，以及可用的 TD 版本和许可证。
- 重新核对 ADC/SDC 约束与实际开发板、转接板和 IMX415 模组原理图是否一致。
- 当前 setup/hold 时序未收敛是正式烧录的阻止条件。必须先完成并审查时序收敛，
  才能把新 bitstream 用于正式板级下载；之后仍需执行配置、链路、图像、反压和
  恢复测试，才可形成板级验收结论。
