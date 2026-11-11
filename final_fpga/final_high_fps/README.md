# final_high_fps 工程归档

2026-11-11 整理自 `camera_fusion_r1`，生产源码固定为
`43dbc3f1d03668898b01c29c4b89a89930b66b9d`，生产封印为
`df8064e9bd11af7c9fcf1e2b76169547d9d61d7b9b5ed8c26204ef864e0fee7e`。
包含 408 个生产输入，本目录可以整体移动后打开 TD 工程。
当前输入哈希见 `fpga_prj/SOURCE_MANIFEST.json`，原始源码身份与路径映射见 `fpga_docs/provenance/RELOCATION.json`。

| 目录 | 内容 |
| --- | --- |
| [fpga_src/rtl](fpga_src/rtl/) | 生产 RTL、头文件、JPEG/Gamma 查找表 |
| [fpga_src/ip](fpga_src/ip/) | 冻结 IP、配置、生成 RTL/Tcl 和 Tone 系数 |
| [fpga_src/constraints](fpga_src/constraints/) | ADC 引脚约束及全部用户 SDC |
| [fpga_src/rk_sdk](fpga_src/rk_sdk/) | 配套 RK Python SDK、RAW 驱动源文件与用法；是 peer SDK 的增量层 |
| [fpga_prj/al](fpga_prj/al/) | 唯一活动 TD 工程及将来由 TD 创建的独立 Runs |
| [fpga_prj/bit](fpga_prj/bit/) | 一版同源 seed54 bit、SHA256 和身份/资格说明 |
| [fpga_prj/scripts](fpga_prj/scripts/) / [tools](fpga_prj/tools/) | 原生检查脚本、本机 TD 包装器、协议生成器、UART 工具、静态归档检查 |
| [fpga_prj/verification_archive](fpga_prj/verification_archive/) | 原始仿真、公开合同、优化试验及辅助脚本源码档案，未注册进生产工程 |
| [fpga_docs](fpga_docs/README.md) | 模式/参数/接口文档、历史验证证据、优化记录和服务器报告 |

打开 [rfcamera_fusion_r1.al](fpga_prj/al/rfcamera_fusion_r1.al)，工具为 TD 2026.2 /
6.2.3.210850，器件 PH1A90SEG324-2，TOP `anlogic2026`。工程名称保持不变，
只调整注册文件、约束和 include 的相对路径；没有复制旧 Runs 或完成标记。
工程与 bit 的设置区别、工具依赖及检查命令见 [构建与检查说明](fpga_docs/BUILD_AND_VERIFY.md)。

本版包含单目 4K15/20、双目 1080P 30/40/45/48 名义档位、HDR、可调白平衡/Tone/融合预设，
支持范围以 [功能矩阵](fpga_docs/MODE_MATRIX.md) 为准，名义档位不等于实测持续帧率。

**随附 seed54 为未收敛候选。** 80 个同源种子已完成 bitgen，但回传摘要均有负 setup。
seed54 在这些摘要中 SWNS 最好：−0.214 ns；hold +0.006 ns，报告中的 recovery +3.582 ns、
removal +0.014 ns。Routed Slice 61925/64320（96.28%）、ERAM 265/272、DSP 149/240。
这版未做板级验证，详见 [比特流与服务器结果](fpga_docs/BITSTREAM_STATUS.md)。

本次整理的静态输入哈希、253 个注册项、5 个 include 目录及 51 个 IP 元数据依赖检查通过，
见 [DELIVERY_CHECK.json](fpga_docs/DELIVERY_CHECK.json)。本轮未运行仿真或 TD 编译，
历史仿真及综合结论按各报告的固定源码与范围保留。
