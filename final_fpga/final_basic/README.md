# final_basic：camera_raw_r2 基础工程

本目录为 **camera_raw_r2 · 1a5603c1 / seed25** 的1080P基础工程，器件 **PH1A90SEG324-2**，TD **2026.2 / 6.2.3.210850**。
高分辨率与高帧率融合版本见 [final_high_fps](../final_high_fps/README.md)。

| 已建目录 | 内容与入口 |
|---|---|
| `fpga_prj/al` | [rfcamera_raw_r2.al](fpga_prj/al/rfcamera_raw_r2.al)，独立TD工程入口及短检查脚本 |
| `fpga_prj/bit` | [seed25比特流](fpga_prj/bit/camera_raw_r2_1a5603c1_seed25.bit)及SHA256，只有这一版bit |
| `fpga_src/rtl` | 全部本候选已跟踪RTL及include头文件，生产编译以.al显式清单为准 |
| `fpga_src/ip` | 完整IP目录，含配置、生成源码、系数和初始化文件 |
| `fpga_src/constraints` | 板级ADC、时钟及CDC等SDC |
| `fpga_src/simulation` | 原有仿真源码、模型、runner与验证记录，未加入生产清单 |
| `fpga_docs` | 源码身份、编译说明、RK协议/参数/调试指南、原始时序和版本差异 |

## 打开工程

使用TD2026.2打开 `fpga_prj/al/rfcamera_raw_r2.al`。项目内源码路径为 `../../fpga_src/...`，不依赖原 `refactor/camera_raw_r2` 目录。
原工程名、顶层 `anlogic2026`、器件、宏、注册顺序、IP注册方式和运行策略保持；迁移只改文件/include相对路径。
不要将所有 `.v` 通配加入工程，IP自带的源码不重复注册，也不要重新生成冻结IP。
此目录可整体复制到另一位置；打开前可用Python运行 `fpga_prj/al/tools/verify_sources.py` 检查依赖与哈希。

原服务器任务采用共享综合16线程、物理种子25/4线程；运行时读回保存在 `fpga_docs/debug_seed25/server_evidence/checkout/refactor/camera_raw_r2/fpga_prj/rfcamera_raw_r2_Runs/phy_1/controller-reports/run_parameters.txt`。`.al`保留提交源码的配置，seed25原由服务器在运行前设置；后续复编时应显式选择所需seed并重新验证时序，不默认新编译必然复现旧bit。

现有bit由原固定源码的服务器任务生成，未因这次整理而重新综合或布线。迁移后工程的检查结果见 [RELOCATION_CHECK.md](fpga_docs/RELOCATION_CHECK.md)。
原生运行输出会生成在 `fpga_prj/al/rfcamera_raw_r2_Runs`，它不属于交付源码或既有bit的资格证明。

## 功能、调试与已知边界

保留单目1080P SDR60、双目SDR30、单双目HDR30的目标；灰度、高斯、HE、去雾支持单双目，原车道算法仅单目。JPEG与RAW10冷选互斥，RAW仍经过DDR槽，未实现无损压缩。
实际性能须分眼、同窗按真实SOURCE/产品/退休对账。当前seed25的板级结果为NOT_RUN，时序通过不代替满幅帧率或画质验收。

- [调试文档入口](fpga_docs/debug_seed25/README.md)：启动、全部目标模式、RK参数、UART、异常留证和44项测试表。
- [相比41cb5991 / seed56的改进](fpga_docs/debug_seed25/CHANGES_FROM_41cb5991.md)：双像素T96、HDR响应预取、SOURCE/JPEG复位资格时序修正。
- [时序和资源](fpga_docs/debug_seed25/TIMING_REVIEW.md)：setup +0.001ns、数据hold +0.007ns、recovery +2.838ns、removal +0.002ns；摘要HWNS +0.002ns，TNS均0；当前有效约束下通过，余量很小。
- [不重烧切换单/双目的补充方案](fpga_docs/mono_dual_soft_switch/README.md)：是待RK驱动/SDK适配与上板验证的方案，不能当成已可用热切换功能。

`fpga_docs/source_reference`保留原工程协议、算法/黑盒合同、历史分析、RK SDK及生成器源文件。历史文档的相对路径和运行状态按原仓库解释；当前入口与本目录资格以本README、SOURCE_BINDING及RELOCATION_CHECK为准。
`fpga_src/simulation`的旧runner可能依赖原仓库、固定Git基线、ModelSim/TD模型和现场Python环境；本次只做目录迁移，没有把旧PASS宣称为新仿真通过。复测应遵守独立黑盒短测规则。

## 来源和维护

生产源固定为 `1a5603c1c8aa58565aa9b5facf40a7478ebcf6ba`，bit SHA256：
`eee7eff50323a8a5c7ddc850d3873e1dda13473debbfe8a690bcb6bab17ac362`。
[SOURCE_BINDING.json](fpga_docs/SOURCE_BINDING.json)列出全部生产输入及复制来源；[SHA256SUMS.txt](fpga_docs/SHA256SUMS.txt)覆盖本交付文件。
当前文件哈希以随包清单为准；历史报告中的哈希标识其原始输入。生成文件头的注释与原始版本可能不同，有效代码、IP保护载荷及比特流保持对应版本内容。
