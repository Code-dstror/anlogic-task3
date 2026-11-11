# PH1A90 + RK3576 图像采集与硬件处理

基于 **Anlogic PH1A90SEG324-2 FPGA、IMX415 图像传感器和 RK3576** 的图像采集工程。FPGA 完成相机采集、DDR 帧缓存、HDR/图像预处理与 JPEG 压缩，并通过 PCIe 向 RK3576 传输图像；也支持独立的 RAW10 输出模式。

本目录包含两套 FPGA 工程，以及可选的服务器构建工具和开发辅助工具。阅读硬件实现可从 `final_basic` 开始，需要高分辨率、高帧率和更多画质参数时再查看 `final_high_fps`。

## 工程选择

| 目录 | 内容 | 固定版本与状态 |
| --- | --- | --- |
| [final_basic](final_basic/README.md) | 1080P 基础工程：单目 SDR60、双目 SDR30、单/双目 HDR30 目标，JPEG/RAW10 冷态选择及图像预处理 | `camera_raw_r2 · 1a5603c1 / seed25`；随附 bit 在现有约束下时序通过，setup 余量仅 **+0.001 ns**；板级验证 **NOT_RUN** |
| [final_high_fps](final_high_fps/README.md) | 融合工程：单目 4K15/20、双目 1080P 30/40/45/48 档位、1080P HDR、白平衡、Tone 和融合预设 | `camera_fusion_r1 · 43dbc3f1 / seed54`；随附 bit 的 setup 为 **−0.214 ns，时序尚未收敛**；板级验证 **NOT_RUN** |
| [final_server](final_server/README.md) | TD v6.6 自动化控制器：任务队列、共享综合、多种子实现、资源准入、检查点接续、日志与产物回传 | 独立配置仓库、TD 路径和运行环境后使用 |
| [final_agents](final_agents/README.md) | 16 个 Codex Skills，以及 MATLAB、Visio 两个 MCP 的配置和配套资源 | 可选开发工具；无需安装即可阅读 FPGA 源码或打开 TD 工程 |

上述帧率是功能目标或配置档位，持续帧率与画质需要对应模式的实测确认。4K 不支持 HDR、去雾和车道处理，45/48 fps 属于探索档。详细范围见[基础版说明](final_basic/README.md)和[融合版功能矩阵](final_high_fps/fpga_docs/MODE_MATRIX.md)。

## 目录结构

两套 FPGA 工程采用相同的核心布局，各自使用独立的源码、IP、约束和运行目录：

```text
final_basic/ 或 final_high_fps/
├── fpga_src/
│   ├── rtl/          RTL 与头文件
│   ├── ip/           IP 配置、生成源码和初始化数据
│   └── constraints/  引脚与时序约束
├── fpga_prj/
│   ├── al/           TD 原生工程
│   └── bit/          一版对应源码的比特流及校验信息
└── fpga_docs/        功能、协议、参数、调试与验证资料
```

基础版仿真位于 `final_basic/fpga_src/simulation/`；融合版仿真与优化试验位于 `final_high_fps/fpga_prj/verification_archive/`。这些文件用于理解和复核实现，生产编译以各自 `.al` 的显式清单为准。

## 打开与检查

1. 安装 **TD 2026.2 / 6.2.3.210850** 及对应器件支持。静态检查脚本使用 **Python 3.12**；历史功能仿真使用 ModelSim SE-64 2020.4 和同一 TD 版本的仿真模型。
2. 根据需要打开一个工程：
   - 基础版：[rfcamera_raw_r2.al](final_basic/fpga_prj/al/rfcamera_raw_r2.al)
   - 融合版：[rfcamera_fusion_r1.al](final_high_fps/fpga_prj/al/rfcamera_fusion_r1.al)
3. 工程顶层均为 `anlogic2026`，器件均为 `PH1A90SEG324-2`。保留当前相对目录结构和已有 IP 注册方式；不要把两个版本或仿真目录中的同名模块一起加入工程。

在本 README 所在目录运行以下命令，可检查源码哈希、工程路径及随附 bit 身份，不启动 TD 编译：

```powershell
python -B final_basic/fpga_prj/al/tools/verify_sources.py
python -B final_high_fps/fpga_prj/tools/verify_delivery.py
```

编译参数、协议生成器和依赖说明见各子目录 README。历史测试中的原仓库路径、固定 Git 基线和外部 SDK 依赖须按对应说明配置；归档测试不等于可直接运行的完整系统回归。重新综合或布局布线后，应以新结果核对资源与时序。

## 核心文档

| 要了解的内容 | 入口 |
| --- | --- |
| 基础版启动、参数、UART 与调试 | [基础版调试指南](final_basic/fpga_docs/debug_seed25/README.md) |
| 基础版 bit 的时序与资源 | [seed25 时序记录](final_basic/fpga_docs/debug_seed25/TIMING_REVIEW.md) |
| 融合版功能、接口与算法资料 | [融合版技术文档](final_high_fps/fpga_docs/README.md) |
| 4K 与几何/RAW 配置 | [UHD/RK 控制说明](final_high_fps/fpga_docs/UHD_RK_CONTROL.md) |
| HDR、白平衡与 JPEG 参数 | [画质参数](final_high_fps/fpga_docs/RK_QUALITY_CONTROLS.md) |
| 融合版 bit 的构建与时序状态 | [seed54 状态](final_high_fps/fpga_docs/BITSTREAM_STATUS.md) |
| 服务器安装与自动构建 | [控制器说明](final_server/README.md) |
| 开发辅助 Skills/MCP | [工具说明](final_agents/README.md) |

RK 配套代码按各版文档接入现有接收端；融合版的 [RK SDK](final_high_fps/fpga_src/rk_sdk/README.md) 是增量层，4K 模式需要匹配的新接口。第三方组件的版权声明与许可证保留在对应目录及 [final_agents/licenses](final_agents/licenses/)。
